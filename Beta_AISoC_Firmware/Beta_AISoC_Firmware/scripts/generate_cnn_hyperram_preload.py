#!/usr/bin/env python3
"""Generate HyperRAM preload files for the CNN accelerator path testbench."""

import argparse
import re
from pathlib import Path


HR0_PARAM_BASE = 0x00180000
HR1_IFMAP_BASE = 0x000000
HR1_OFMAP_BASE = 0x000C00
ACCEL_M = 2

RAW_META = [
    (4, 2592, 1368484, 384),
    (2596, 82944, 1368868, 384),
    (85540, 82944, 1369252, 384),
    (168484, 165888, 1369636, 768),
    (334372, 331776, 1370404, 768),
    (666148, 331776, 1371172, 768),
    (997924, 331776, 1371940, 768),
    (1329700, 36864, 1372708, 768),
    (1366564, 1920, 1373476, 40),
]

LAYERS = [
    # ifh, ifc, ofc, hf, stride, pad, ifparr, oftile, ofparr, ifbaddr, fltbaddr, biasbaddr, ofbaddr
    (32, 3, 96, 3, 1, 1, 3, 1, 8, 0, 0, 2592, 3072),
    (32, 96, 96, 3, 1, 1, 3, 1, 8, 101376, 2976, 85920, 199680),
    (32, 96, 96, 3, 2, 1, 3, 1, 8, 297984, 86304, 169248, 396288),
    (16, 96, 192, 3, 1, 1, 3, 1, 8, 420864, 169632, 335520, 445440),
    (16, 192, 192, 3, 1, 1, 3, 1, 8, 494592, 336288, 668064, 543744),
    (16, 192, 192, 3, 2, 1, 4, 1, 8, 592896, 668832, 1000608, 642048),
    (8, 192, 192, 3, 1, 1, 3, 1, 8, 654336, 1001376, 1333152, 666624),
    (8, 192, 192, 1, 1, 0, 2, 1, 24, 678912, 1333920, 1370784, 691200),
    (8, 192, 10, 1, 1, 0, 2, 1, 10, 703488, 1371552, 1373472, 715776),
]


def ceil_div(a, b):
    return (a + b - 1) // b


def parse_args():
    default_root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--firmware-root", type=Path, default=default_root)
    parser.add_argument("--weights-hex", type=Path)
    parser.add_argument("--image-c", type=Path)
    parser.add_argument("--hr0-out", type=Path, required=True)
    parser.add_argument("--hr1-out", type=Path, required=True)
    parser.add_argument("--include-raw-weights", action="store_true")
    return parser.parse_args()


def read_weights(path):
    text = path.read_text()
    raw = bytes.fromhex("".join(re.findall(r"[0-9a-fA-F]+", text)))
    blob_size = int.from_bytes(raw[:4], "little")
    if blob_size != len(raw):
        raise ValueError(f"weight blob size mismatch: header=0x{blob_size:08x}, file=0x{len(raw):08x}")
    return raw


def read_test_image_hwc(path):
    text = path.read_text()
    match = re.search(r"allcnn_test_image\s*\[\s*3072\s*\]\s*=\s*\{(.*?)\};", text, re.S)
    if match is None:
        raise ValueError("cannot find allcnn_test_image[3072]")
    values = [int(x) for x in re.findall(r"-?\d+", match.group(1))]
    if len(values) != 3072:
        raise ValueError(f"image length mismatch: {len(values)}")
    return [(value & 0xFF) for value in values]


def image_hwc_to_chw(image):
    packed = bytearray()
    for c in range(3):
        for y in range(32):
            for x in range(32):
                packed.append(image[y * 32 * 3 + x * 3 + c])
    return bytes(packed)


def build_slots(layer, group_start, group_cols):
    _, _, ofchannel, _, _, _, _, oftile, ofparr, *_ = layer
    lane_rows = [0] * ACCEL_M
    lane_count = [0] * ACCEL_M
    lane_base = [0] * ACCEL_M
    lane_seq = [[] for _ in range(ACCEL_M)]
    lane_used = [[] for _ in range(ACCEL_M)]
    slot_ch = [
        [[-1 for _ in range(group_cols)] for _ in range(ceil_div(ofparr, ACCEL_M))]
        for _ in range(ACCEL_M)
    ]

    full_cols = ofchannel // ofparr
    tail_slots = ofchannel % ofparr

    for lane in range(ACCEL_M):
        for r in range(lane, ofparr, ACCEL_M):
            lane_rows[lane] += 1

    for lane in range(ACCEL_M):
        lane_count[lane] = full_cols * lane_rows[lane]
        if tail_slots > lane:
            lane_count[lane] += ceil_div(tail_slots - lane, ACCEL_M)

    for lane in range(1, ACCEL_M):
        lane_base[lane] = lane_base[lane - 1] + lane_count[lane - 1]

    block_id = group_start // oftile
    block_real = ofchannel - block_id * oftile * ofparr
    block_real = min(block_real, oftile * ofparr)
    red_need = []
    for _ in range(group_cols):
        need = min(ofparr, block_real)
        red_need.append(need)
        block_real -= need

    for lane in range(ACCEL_M):
        for r in range(lane_rows[lane]):
            for col in range(group_cols):
                idx_in_lane = lane_base[lane] + lane_rows[lane] * group_start + r * group_cols + col
                if idx_in_lane < lane_base[lane] + lane_count[lane] and idx_in_lane < ofchannel:
                    lane_seq[lane].append(idx_in_lane)
                    lane_used[lane].append(False)

    for col in range(group_cols):
        need = red_need[col]
        for lane in range(ACCEL_M):
            for r in range(lane_rows[lane]):
                seq_pos = r * group_cols + col
                if need > 0 and seq_pos < len(lane_seq[lane]) and not lane_used[lane][seq_pos]:
                    slot_ch[lane][r][col] = lane_seq[lane][seq_pos]
                    lane_used[lane][seq_pos] = True
                    need -= 1

        while need > 0:
            placed = False
            for lane in range(ACCEL_M):
                if placed:
                    break
                for seq_pos, channel in enumerate(lane_seq[lane]):
                    if lane_used[lane][seq_pos]:
                        continue
                    for r in range(lane_rows[lane]):
                        if slot_ch[lane][r][col] < 0:
                            slot_ch[lane][r][col] = channel
                            lane_used[lane][seq_pos] = True
                            need -= 1
                            placed = True
                            break
                    if placed:
                        break
            if not placed:
                break

    return lane_rows, slot_ch


def build_filter_group(raw, meta, layer, group_start, group_cols):
    weight_offset, _, _, _ = meta
    ifheight, ifchannel, ofchannel, hf, _, _, ifparr, _, ofparr, *_ = layer
    del ifheight, ofparr

    lane_rows, slot_ch = build_slots(layer, group_start, group_cols)
    filters = []
    for col in range(group_cols):
        for lane in range(ACCEL_M):
            for r in range(lane_rows[lane]):
                f = slot_ch[lane][r][col]
                if 0 <= f < ofchannel:
                    filters.append(f)

    iftiles = ceil_div(ifchannel, ifparr)
    filter_span = hf * hf * ifchannel
    offsets = []
    sizes = []
    total_size = 0
    for tile in range(iftiles):
        cg = tile * ifparr
        cp = min(ifparr, ifchannel - cg)
        raw_packet_size = cp * len(filters) * hf * hf
        packet_size = raw_packet_size + (raw_packet_size & 1)
        offsets.append(total_size)
        sizes.append(packet_size)
        total_size += packet_size

    group = bytearray([0xFF] * total_size)
    for bf, f in enumerate(filters):
        filter_data = raw[weight_offset + f * filter_span:weight_offset + (f + 1) * filter_span]
        if len(filter_data) != filter_span:
            raise ValueError("short filter data")
        for tile in range(iftiles):
            cg = tile * ifparr
            cp = min(ifparr, ifchannel - cg)
            pos = offsets[tile] + bf * cp * hf * hf
            end = offsets[tile] + sizes[tile]
            for c_local in range(cp):
                for ky in range(hf):
                    for kx in range(hf):
                        if pos >= end:
                            raise ValueError("filter packet overflow")
                        src_idx = (ky * hf + kx) * ifchannel + cg + c_local
                        group[pos] = filter_data[src_idx]
                        pos += 1
    return bytes(group)


def build_bias_packet(raw, meta, layer, group_start, group_cols):
    _, _, bias_offset, _ = meta
    _, _, ofchannel, _, _, _, _, _, _, *_ = layer
    lane_rows, slot_ch = build_slots(layer, group_start, group_cols)
    packet = bytearray()
    real_bias_count = 0

    for lane in range(ACCEL_M):
        for r in range(lane_rows[lane]):
            for col in range(group_cols):
                ch = slot_ch[lane][r][col]
                if 0 <= ch < ofchannel:
                    packet.extend(raw[bias_offset + ch * 4:bias_offset + ch * 4 + 4])
                    real_bias_count += 1

    if real_bias_count & 1:
        packet.extend(b"\x00\x00\x00\x00")

    return bytes(packet)


def pack_full_params(raw):
    sections = []
    for idx, layer in enumerate(LAYERS):
        meta = RAW_META[idx]
        _, weight_size, _, bias_size = meta
        _, _, ofchannel, _, _, _, _, oftile, ofparr, _, fltbaddr, bias_baddr, _ = layer
        total_cols = ceil_div(ofchannel, ofparr)

        weight = bytearray()
        for group_start in range(0, total_cols, oftile):
            group_cols = min(oftile, total_cols - group_start)
            weight.extend(build_filter_group(raw, meta, layer, group_start, group_cols))
        if len(weight) != weight_size:
            raise ValueError(f"L{idx + 1} weight size mismatch: {len(weight)} != {weight_size}")
        sections.append((HR0_PARAM_BASE + fltbaddr, bytes(weight)))

        bias = bytearray()
        for group_start in range(0, total_cols, oftile):
            group_cols = min(oftile, total_cols - group_start)
            bias.extend(build_bias_packet(raw, meta, layer, group_start, group_cols))
        if len(bias) != bias_size:
            raise ValueError(f"L{idx + 1} bias size mismatch: {len(bias)} != {bias_size}")
        sections.append((HR0_PARAM_BASE + bias_baddr, bytes(bias)))

    return sections


def write_mem(path, sections, title):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w") as f:
        f.write(f"//# {title}\n")
        f.write("//# Generated by scripts/generate_cnn_hyperram_preload.py\n")
        f.write("//# Address records use vendor model Mem[word_address] index: byte_address >> 1.\n")
        for base_addr, data in sections:
            if base_addr & 1:
                raise ValueError(f"unaligned HyperRAM preload address: 0x{base_addr:06X}")
            if len(data) & 1:
                data = data + b"\x00"
            f.write(f"@{(base_addr >> 1):06X}\n")
            for i in range(0, len(data), 2):
                f.write(f"{data[i]:02X}{data[i + 1]:02X}\n")


def main():
    args = parse_args()
    weights_hex = args.weights_hex or (args.firmware_root / "Build/allcnn_cifar10_weights.hex")
    image_c = args.image_c or (args.firmware_root / "App/Src/allcnn_cifar10.c")

    raw = read_weights(weights_hex)
    image = image_hwc_to_chw(read_test_image_hwc(image_c))
    hr0_sections = []
    if args.include_raw_weights:
        hr0_sections.append((0x000000, raw))
    hr0_sections.extend(pack_full_params(raw))
    hr1_sections = [
        (HR1_IFMAP_BASE, image),
        (HR1_OFMAP_BASE, b"\x00\x00"),
    ]

    write_mem(args.hr0_out, hr0_sections, "HyperRAM0 CNN packed filter/bias preload")
    write_mem(args.hr1_out, hr1_sections, "HyperRAM1 CNN IFMAP preload")

    hr0_bytes = sum(len(data) for _, data in hr0_sections)
    hr1_bytes = sum(len(data) for _, data in hr1_sections)
    print(f"Generated {args.hr0_out} ({len(hr0_sections)} sections, {hr0_bytes} bytes)")
    print(f"Generated {args.hr1_out} ({len(hr1_sections)} sections, {hr1_bytes} bytes)")
    print(f"HR1 first word expected: {image[0]:02X}{image[1]:02X}")
    print(f"HR0 first packed word expected: {hr0_sections[-18][1][0]:02X}{hr0_sections[-18][1][1]:02X}")


if __name__ == "__main__":
    main()
