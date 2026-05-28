from pathlib import Path
import argparse
import json


LAYERS = [
    # name, ifh, ifc, ofc, hf, stride, pad, ifparr, oftile, ofparr, fltbaddr, biasbaddr
    ("Conv1", 96,   3,  32, 3, 2, 1, 3, 1, 8,      0,    864),
    ("Conv2", 48,  32,  64, 3, 2, 1, 4, 1, 8,    992,  19424),
    ("Conv3", 24,  64, 128, 3, 2, 1, 4, 1, 8,  19680,  93408),
    ("Conv4", 12, 128, 192, 3, 1, 1, 4, 1, 8,  93920, 315104),
    ("Conv5", 12, 192,   3, 1, 1, 0, 4, 1, 3, 315872, 316448),
]

TOTAL_SIZE = 316460
MODEL_FILE = "rps_cnn_96_s2_qat_int8_per_layer.tflite"
PARAMS_FILE = "rps_cnn_96_s2_qat_fixed_params_int_only.json"
ACCEL_M = 2


class FlatBuffer:
    def __init__(self, data):
        self.data = data

    def u16(self, off):
        return int.from_bytes(self.data[off:off + 2], "little")

    def u32(self, off):
        return int.from_bytes(self.data[off:off + 4], "little")

    def i32(self, off):
        return int.from_bytes(self.data[off:off + 4], "little", signed=True)

    def table_field(self, table, field):
        vtable = table - self.i32(table)
        vlen = self.u16(vtable)
        slot = 4 + field * 2
        if slot >= vlen:
            return 0
        rel = self.u16(vtable + slot)
        return table + rel if rel else 0

    def vector_len(self, vec_field):
        vec = vec_field + self.u32(vec_field)
        return self.u32(vec)

    def vector_elem_table(self, vec_field, idx):
        vec = vec_field + self.u32(vec_field)
        elem = vec + 4 + idx * 4
        return elem + self.u32(elem)

    def vector_bytes(self, vec_field):
        vec = vec_field + self.u32(vec_field)
        n = self.u32(vec)
        return self.data[vec + 4:vec + 4 + n]


def extract_tensors(path):
    data = path.read_bytes()
    fb = FlatBuffer(data)
    root = fb.u32(0)
    subgraphs_f = fb.table_field(root, 2)
    subgraph = fb.vector_elem_table(subgraphs_f, 0)
    tensors_f = fb.table_field(subgraph, 0)
    buffers_f = fb.table_field(root, 4)

    tensor_to_buffer = []
    for i in range(fb.vector_len(tensors_f)):
        tensor = fb.vector_elem_table(tensors_f, i)
        buffer_field = fb.table_field(tensor, 2)
        tensor_to_buffer.append(fb.u32(buffer_field) if buffer_field else 0)

    buffers = []
    for i in range(fb.vector_len(buffers_f)):
        buffer = fb.vector_elem_table(buffers_f, i)
        data_field = fb.table_field(buffer, 0)
        buffers.append(fb.vector_bytes(data_field) if data_field else b"")

    return tensor_to_buffer, buffers


def ceil_div(a, b):
    return (a + b - 1) // b


def build_slots(ofc, ofparr, oftile, group_start, group_cols):
    full_cols = ofc // ofparr
    tail_slots = ofc % ofparr
    lane_rows = [sum(1 for row in range(lane, ofparr, ACCEL_M)) for lane in range(ACCEL_M)]
    lane_count = [
        full_cols * lane_rows[lane] +
        (ceil_div(tail_slots - lane, ACCEL_M) if tail_slots > lane else 0)
        for lane in range(ACCEL_M)
    ]

    lane_base = [0]
    for lane in range(1, ACCEL_M):
        lane_base.append(lane_base[-1] + lane_count[lane - 1])

    block_id = group_start // oftile
    block_real = min(ofc - block_id * oftile * ofparr, oftile * ofparr)
    red_need = []
    for _ in range(group_cols):
        need = min(ofparr, block_real)
        red_need.append(need)
        block_real -= need

    lane_seq = [[] for _ in range(ACCEL_M)]
    lane_used = [[] for _ in range(ACCEL_M)]
    slots = [[[-1 for _ in range(group_cols)] for _ in range(lane_rows[lane])]
             for lane in range(ACCEL_M)]

    for lane in range(ACCEL_M):
        for row in range(lane_rows[lane]):
            for col in range(group_cols):
                idx = lane_base[lane] + lane_rows[lane] * group_start + row * group_cols + col
                if idx < lane_base[lane] + lane_count[lane] and idx < ofc:
                    lane_seq[lane].append(idx)
                    lane_used[lane].append(False)

    for col in range(group_cols):
        need = red_need[col]
        for lane in range(ACCEL_M):
            for row in range(lane_rows[lane]):
                pos = row * group_cols + col
                if need > 0 and pos < len(lane_seq[lane]) and not lane_used[lane][pos]:
                    slots[lane][row][col] = lane_seq[lane][pos]
                    lane_used[lane][pos] = True
                    need -= 1

        while need > 0:
            placed = False
            for lane in range(ACCEL_M):
                if placed:
                    break
                for pos, ch in enumerate(lane_seq[lane]):
                    if lane_used[lane][pos]:
                        continue
                    for row in range(lane_rows[lane]):
                        if slots[lane][row][col] < 0:
                            slots[lane][row][col] = ch
                            lane_used[lane][pos] = True
                            need -= 1
                            placed = True
                            break
                    if placed:
                        break
            if not placed:
                break

    return lane_rows, slots


def build_weight_group(weight, layer, group_start, group_cols):
    _, _, ifc, ofc, hf, _, _, ifparr, oftile, ofparr, _, _ = layer
    lane_rows, slots = build_slots(ofc, ofparr, oftile, group_start, group_cols)

    filters = []
    for col in range(group_cols):
        for lane in range(ACCEL_M):
            for row in range(lane_rows[lane]):
                ch = slots[lane][row][col]
                if 0 <= ch < ofc:
                    filters.append(ch)

    out = bytearray()
    filter_span = hf * hf * ifc
    for channel_group in range(0, ifc, ifparr):
        channel_count = min(ifparr, ifc - channel_group)
        packet = bytearray()
        for filter_idx in filters:
            filter_data = weight[filter_idx * filter_span:(filter_idx + 1) * filter_span]
            for c_local in range(channel_count):
                for ky in range(hf):
                    for kx in range(hf):
                        src = (ky * hf + kx) * ifc + channel_group + c_local
                        packet.append(filter_data[src])
        if len(packet) & 1:
            packet.append(0xFF)
        out.extend(packet)

    return out


def build_bias_group(biases, layer, group_start, group_cols):
    _, _, _, ofc, _, _, _, _, oftile, ofparr, _, _ = layer
    lane_rows, slots = build_slots(ofc, ofparr, oftile, group_start, group_cols)
    out = bytearray()

    for lane in range(ACCEL_M):
        for row in range(lane_rows[lane]):
            for col in range(group_cols):
                ch = slots[lane][row][col]
                if 0 <= ch < ofc:
                    out.extend(int(biases[ch]).to_bytes(4, "big", signed=True))

    return out


def weight_tensor_index(meta):
    if "weight_tensor_index" in meta:
        return meta["weight_tensor_index"]
    return meta["weight_tensor"]["index"]


def parse_args():
    parser = argparse.ArgumentParser(
        description="Pack RPS ALL-CNN-C-96 QAT INT8 TFLite weights/biases for accelerator HyperRAM0."
    )
    parser.add_argument("--model-dir", type=Path, required=True)
    parser.add_argument("--tflite", type=Path)
    parser.add_argument("--params", type=Path)
    parser.add_argument("--bin-out", type=Path, default=Path("Build/allcnnc_96_qat_packed_weights.bin"))
    parser.add_argument("--hex-out", type=Path, default=Path("Build/allcnnc_96_qat_packed_weights.hex"))
    return parser.parse_args()


def main():
    args = parse_args()
    tflite = args.tflite or (args.model_dir / MODEL_FILE)
    params = args.params or (args.model_dir / PARAMS_FILE)

    obj = json.loads(params.read_text())
    conv_layers = obj["conv_layers"]
    if len(conv_layers) != len(LAYERS):
        raise ValueError(f"Expected {len(LAYERS)} conv layers, got {len(conv_layers)}")

    tensor_to_buffer, buffers = extract_tensors(tflite)
    blob = bytearray(TOTAL_SIZE)

    for idx, (layer, meta) in enumerate(zip(LAYERS, conv_layers), 1):
        name, _, ifc, ofc, hf, _, _, _, oftile, ofparr, fltbaddr, biasaddr = layer
        weight_idx = weight_tensor_index(meta)
        weight = buffers[tensor_to_buffer[weight_idx]]
        expect = ofc * hf * hf * ifc
        if len(weight) != expect:
            raise ValueError(f"{name}: weight size {len(weight)} != {expect}")

        biases = meta["bias_values_int32"]
        if len(biases) != ofc:
            raise ValueError(f"{name}: bias count {len(biases)} != {ofc}")

        total_cols = ceil_div(ofc, ofparr)
        packed_weight = bytearray()
        packed_bias = bytearray()
        for group_start in range(0, total_cols, oftile):
            group_cols = min(oftile, total_cols - group_start)
            packed_weight.extend(build_weight_group(weight, layer, group_start, group_cols))
            packed_bias.extend(build_bias_group(biases, layer, group_start, group_cols))

        blob[fltbaddr:fltbaddr + len(packed_weight)] = packed_weight
        blob[biasaddr:biasaddr + len(packed_bias)] = packed_bias
        print(
            f"{idx} {name}: raw_weight={len(weight)} packed_weight={len(packed_weight)} "
            f"bias={len(packed_bias)} flt={fltbaddr} bias_addr={biasaddr}"
        )

    print(f"blob {len(blob)} bytes, first16={blob[:16].hex()}")

    if args.bin_out:
        args.bin_out.parent.mkdir(parents=True, exist_ok=True)
        args.bin_out.write_bytes(blob)
        print(f"wrote {args.bin_out} {args.bin_out.stat().st_size} bytes")

    if args.hex_out:
        args.hex_out.parent.mkdir(parents=True, exist_ok=True)
        with args.hex_out.open("w") as f:
            for offset in range(0, len(blob), 16):
                f.write(blob[offset:offset + 16].hex().upper() + "\n")
        print(f"wrote {args.hex_out} {args.hex_out.stat().st_size} bytes")


if __name__ == "__main__":
    main()
