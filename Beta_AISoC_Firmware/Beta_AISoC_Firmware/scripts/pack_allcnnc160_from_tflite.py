from pathlib import Path
import argparse
import json


LAYERS = [
    # ifh, ifc, ofc, hf, stride, pad, ifparr, oftile, ofparr, fltbaddr, biasbaddr
    (160,   3,  32, 3, 1, 1, 3, 1,  8,       0,     864),
    (160,  32,  32, 3, 1, 1, 4, 1,  8,     992,   10208),
    (160,  32,  64, 3, 2, 1, 4, 1,  8,   10336,   28768),
    ( 80,  64,  64, 3, 1, 1, 4, 1,  8,   29024,   65888),
    ( 80,  64,  64, 3, 1, 1, 4, 1,  8,   66144,  103008),
    ( 80,  64,  96, 3, 2, 1, 4, 1,  8,  103264,  158560),
    ( 40,  96,  96, 3, 1, 1, 3, 1,  8,  158944,  241888),
    ( 40,  96, 128, 3, 1, 1, 3, 1,  8,  242272,  352864),
    ( 40, 128, 128, 3, 2, 1, 4, 1,  8,  353376,  500832),
    ( 20, 128, 128, 3, 1, 1, 4, 1,  8,  501344,  648800),
    ( 20, 128, 192, 3, 1, 1, 4, 1,  8,  649312,  870496),
    ( 20, 192, 192, 3, 2, 1, 4, 1,  8,  871264, 1203040),
    ( 10, 192, 192, 3, 1, 1, 4, 1,  8, 1203808, 1535584),
    ( 10, 192, 192, 1, 1, 0, 4, 1, 24, 1536352, 1573216),
    ( 10, 192,   3, 1, 1, 0, 4, 1,  3, 1573984, 1574560),
]
TOTAL_SIZE = 1574572
M = 2

class FB:
    def __init__(self, data): self.data=data
    def u16(self, off): return int.from_bytes(self.data[off:off+2], 'little')
    def u32(self, off): return int.from_bytes(self.data[off:off+4], 'little')
    def i32(self, off): return int.from_bytes(self.data[off:off+4], 'little', signed=True)
    def table_field(self, table, field):
        vtable = table - self.i32(table)
        vlen = self.u16(vtable)
        slot = 4 + field*2
        if slot >= vlen: return 0
        rel = self.u16(vtable + slot)
        return table + rel if rel else 0
    def vector_len(self, vec_field):
        vec = vec_field + self.u32(vec_field)
        return self.u32(vec)
    def vector_elem_table(self, vec_field, idx):
        vec = vec_field + self.u32(vec_field)
        elem = vec + 4 + idx*4
        return elem + self.u32(elem)
    def vector_bytes(self, vec_field):
        vec = vec_field + self.u32(vec_field)
        n = self.u32(vec)
        return self.data[vec+4:vec+4+n]

def extract_tensors(path):
    data = path.read_bytes(); fb=FB(data)
    root = fb.u32(0)
    subgraphs_f = fb.table_field(root, 2)
    subgraph = fb.vector_elem_table(subgraphs_f, 0)
    tensors_f = fb.table_field(subgraph, 0)
    buffers_f = fb.table_field(root, 4)
    tensors=[]
    for i in range(fb.vector_len(tensors_f)):
        t = fb.vector_elem_table(tensors_f, i)
        bf = fb.table_field(t, 2)
        tensors.append(fb.u32(bf) if bf else 0)
    buffers=[]
    for i in range(fb.vector_len(buffers_f)):
        b=fb.vector_elem_table(buffers_f, i)
        df=fb.table_field(b,0)
        buffers.append(fb.vector_bytes(df) if df else b'')
    return tensors,buffers

def ceil_div(a,b): return (a+b-1)//b

def build_slots(ofc, ofparr, oftile, group_start, group_cols):
    full_cols=ofc//ofparr; tail_slots=ofc%ofparr
    lane_rows=[sum(1 for r in range(l,ofparr,M)) for l in range(M)]
    lane_count=[full_cols*lane_rows[l] + (ceil_div(tail_slots-l, M) if tail_slots>l else 0) for l in range(M)]
    lane_base=[0]
    for l in range(1,M): lane_base.append(lane_base[-1]+lane_count[l-1])
    block_id=group_start//oftile
    block_real=min(ofc-block_id*oftile*ofparr, oftile*ofparr)
    red_need=[]
    for _ in range(group_cols):
        need=min(ofparr, block_real); red_need.append(need); block_real-=need
    lane_seq=[[] for _ in range(M)]; lane_used=[[] for _ in range(M)]
    slots=[[[ -1 for _ in range(group_cols)] for _ in range(lane_rows[l])] for l in range(M)]
    for l in range(M):
        for r in range(lane_rows[l]):
            for col in range(group_cols):
                idx=lane_base[l]+lane_rows[l]*group_start+r*group_cols+col
                if idx < lane_base[l]+lane_count[l] and idx < ofc:
                    lane_seq[l].append(idx); lane_used[l].append(False)
    for col in range(group_cols):
        need=red_need[col]
        for l in range(M):
            for r in range(lane_rows[l]):
                pos=r*group_cols+col
                if need>0 and pos < len(lane_seq[l]) and not lane_used[l][pos]:
                    slots[l][r][col]=lane_seq[l][pos]; lane_used[l][pos]=True; need-=1
        while need>0:
            placed=False
            for l in range(M):
                if placed: break
                for pos,ch in enumerate(lane_seq[l]):
                    if lane_used[l][pos]: continue
                    for r in range(lane_rows[l]):
                        if slots[l][r][col] < 0:
                            slots[l][r][col]=ch; lane_used[l][pos]=True; need-=1; placed=True; break
                    if placed: break
            if not placed: break
    return lane_rows, slots

def build_weight_group(weight, layer, group_start, group_cols):
    _,ifc,ofc,hf,_,_,ifparr,oftile,ofparr,_,_ = layer
    lane_rows, slots = build_slots(ofc, ofparr, oftile, group_start, group_cols)
    filters=[]
    for col in range(group_cols):
        for l in range(M):
            for r in range(lane_rows[l]):
                ch=slots[l][r][col]
                if 0 <= ch < ofc: filters.append(ch)
    out=bytearray()
    filter_span=hf*hf*ifc
    for cg in range(0, ifc, ifparr):
        cp=min(ifparr, ifc-cg)
        packet=bytearray()
        for f in filters:
            fdata=weight[f*filter_span:(f+1)*filter_span]
            for c_local in range(cp):
                for ky in range(hf):
                    for kx in range(hf):
                        src=(ky*hf+kx)*ifc + cg + c_local
                        packet.append(fdata[src])
        if len(packet)&1: packet.append(0xFF)
        out.extend(packet)
    return out

def build_bias_group(biases, layer, group_start, group_cols):
    _,_,ofc,_,_,_,_,oftile,ofparr,_,_ = layer
    lane_rows, slots = build_slots(ofc, ofparr, oftile, group_start, group_cols)
    out=bytearray(); count=0
    for l in range(M):
        for r in range(lane_rows[l]):
            for col in range(group_cols):
                ch=slots[l][r][col]
                if 0 <= ch < ofc:
                    out.extend(int(biases[ch]).to_bytes(4,'big',signed=True)); count+=1
    return out

def parse_args():
    parser = argparse.ArgumentParser(description='Pack ALL-CNN-C-160 TFLite weights for accelerator HyperRAM layout.')
    parser.add_argument('--model-dir', type=Path, required=True)
    parser.add_argument('--bin-out', type=Path)
    parser.add_argument('--hex-out', type=Path)
    return parser.parse_args()

def main():
    args = parse_args()
    tflite = args.model_dir / 'all_cnn_c_160_rps_int8_per_layer.tflite'
    params = args.model_dir / 'all_cnn_c_160_rps_fixed_params_per_layer.json'
    obj=json.loads(params.read_text())
    tensor_to_buffer, buffers=extract_tensors(tflite)
    blob=bytearray(TOTAL_SIZE)
    for idx,(layer,meta) in enumerate(zip(LAYERS,obj['conv_layers']),1):
        weight_idx=meta['weight_tensor']['index']; weight=buffers[tensor_to_buffer[weight_idx]]
        expect=meta['weight_tensor']['shape'][0]*meta['weight_tensor']['shape'][1]*meta['weight_tensor']['shape'][2]*meta['weight_tensor']['shape'][3]
        assert len(weight)==expect, (idx,len(weight),expect)
        biases=meta['bias_values_int32']
        *_, ofc, hf, stride, pad, ifparr, oftile, ofparr, fltbaddr, biasaddr = layer
        total_cols=ceil_div(ofc,ofparr)
        w=bytearray(); b=bytearray()
        for gs in range(0,total_cols,oftile):
            gc=min(oftile,total_cols-gs)
            w.extend(build_weight_group(weight,layer,gs,gc))
            b.extend(build_bias_group(biases,layer,gs,gc))
        blob[fltbaddr:fltbaddr+len(w)] = w
        blob[biasaddr:biasaddr+len(b)] = b
        print(idx, len(weight), len(w), len(b), fltbaddr, biasaddr)
    print('blob', len(blob), blob[:16].hex())
    if args.bin_out:
        args.bin_out.parent.mkdir(parents=True, exist_ok=True)
        args.bin_out.write_bytes(blob)
        print(args.bin_out, args.bin_out.stat().st_size)
    if args.hex_out:
        args.hex_out.parent.mkdir(parents=True, exist_ok=True)
        with args.hex_out.open('w') as f:
            for i in range(0,len(blob),16): f.write(blob[i:i+16].hex().upper()+'\n')
        print(args.hex_out, args.hex_out.stat().st_size)

if __name__=='__main__': main()
