#!/usr/bin/env python3

import argparse
import struct
import zlib
from pathlib import Path


FLASH_SIZE = 16 * 1024 * 1024
BOOT_META_OFFSET = 0x00000000
BOOT_IMAGE_OFFSET = 0x00001000
BOOT_VALID_MAGIC = 0xA5A55A5A
APP_MAX_SIZE = 64 * 1024

WEIGHT_METADATA_OFFSET = 0x001FF000
WEIGHT_FLASH_OFFSET = 0x00200000
WEIGHT_METADATA_MAGIC = 0x53544757  # "WGTS"
WEIGHT_METADATA_VERSION = 1


def parse_args():
    parser = argparse.ArgumentParser(
        description="Build a complete 16MB SPI flash image with app firmware and weight payload."
    )
    parser.add_argument("--app", type=Path, default=Path("Build/main.bin"))
    parser.add_argument("--weights", type=Path)
    parser.add_argument(
        "--weight-slot",
        action="append",
        default=[],
        metavar="NAME:METADATA_OFFSET:FLASH_OFFSET:PAYLOAD",
        help=(
            "Add a named weight payload. Offsets may be decimal or hex. "
            "Example: allcnn:0x001FF000:0x00200000:Build/allcnn_cifar10_weights.hex"
        ),
    )
    parser.add_argument("--bin-out", type=Path, required=True)
    parser.add_argument("--ihex-out", type=Path)
    args = parser.parse_args()

    if not args.weights and not args.weight_slot:
        parser.error("provide --weights or at least one --weight-slot")

    return args


def parse_int(text):
    return int(text, 0)


def parse_weight_slot(text):
    parts = text.split(":", 3)
    if len(parts) != 4:
        raise ValueError(
            "--weight-slot must use NAME:METADATA_OFFSET:FLASH_OFFSET:PAYLOAD"
        )
    name, metadata_offset, flash_offset, payload = parts
    if not name:
        raise ValueError("--weight-slot NAME must not be empty")
    return {
        "name": name,
        "metadata_offset": parse_int(metadata_offset),
        "flash_offset": parse_int(flash_offset),
        "path": Path(payload),
    }


def read_payload(path):
    data = path.read_bytes()
    if path.suffix.lower() == ".hex" and not data.lstrip().startswith(b":"):
        compact = b"".join(data.split())
        if len(compact) % 2 != 0:
            raise ValueError(f"Raw hex payload has odd digit count: {path}")
        try:
            return bytes.fromhex(compact.decode("ascii"))
        except ValueError as exc:
            raise ValueError(f"Could not parse raw hex payload: {path}") from exc
    return data


def ihex_checksum(record_bytes):
    return (-sum(record_bytes)) & 0xFF


def write_ihex(path, image, record_size=32):
    path.parent.mkdir(parents=True, exist_ok=True)
    current_upper = 0

    with path.open("w") as f:
        for addr in range(0, len(image), record_size):
            upper = addr >> 16
            if upper != current_upper:
                payload = struct.pack(">H", upper)
                record = bytes([len(payload), 0x00, 0x00, 0x04]) + payload
                f.write(":" + record.hex().upper() + f"{ihex_checksum(record):02X}\n")
                current_upper = upper

            low_addr = addr & 0xFFFF
            payload = image[addr:addr + record_size]
            record = bytes([len(payload), (low_addr >> 8) & 0xFF, low_addr & 0xFF, 0x00]) + payload
            f.write(":" + record.hex().upper() + f"{ihex_checksum(record):02X}\n")

        final_upper = len(image) >> 16
        if final_upper != current_upper:
            payload = struct.pack(">H", final_upper)
            record = bytes([len(payload), 0x00, 0x00, 0x04]) + payload
            f.write(":" + record.hex().upper() + f"{ihex_checksum(record):02X}\n")

        f.write(":00000001FF\n")


def main():
    args = parse_args()
    app = args.app.read_bytes()
    slots = []

    if len(app) > APP_MAX_SIZE:
        raise ValueError(f"App image is {len(app)} bytes, max supported is {APP_MAX_SIZE}")

    if args.weights:
        slots.append({
            "name": "default",
            "metadata_offset": WEIGHT_METADATA_OFFSET,
            "flash_offset": WEIGHT_FLASH_OFFSET,
            "path": args.weights,
        })
    slots.extend(parse_weight_slot(slot) for slot in args.weight_slot)

    image = bytearray([0xFF]) * FLASH_SIZE

    struct.pack_into("<II", image, BOOT_META_OFFSET, BOOT_VALID_MAGIC, len(app))
    image[BOOT_IMAGE_OFFSET:BOOT_IMAGE_OFFSET + len(app)] = app

    used_ranges = [(BOOT_META_OFFSET, BOOT_META_OFFSET + 8, "boot metadata"),
                   (BOOT_IMAGE_OFFSET, BOOT_IMAGE_OFFSET + len(app), "app")]
    resolved_slots = []
    for slot in slots:
        weights = read_payload(slot["path"])
        metadata_offset = slot["metadata_offset"]
        flash_offset = slot["flash_offset"]
        metadata_end = metadata_offset + 20
        flash_end = flash_offset + len(weights)

        if metadata_end > FLASH_SIZE or flash_end > FLASH_SIZE:
            raise ValueError(f"Weight slot {slot['name']} does not fit in flash image")
        for start, end, used_name in used_ranges:
            if metadata_offset < end and start < metadata_end:
                raise ValueError(f"Metadata for {slot['name']} overlaps {used_name}")
            if flash_offset < end and start < flash_end:
                raise ValueError(f"Payload for {slot['name']} overlaps {used_name}")

        weight_crc32 = zlib.crc32(weights) & 0xFFFFFFFF
        weight_metadata = struct.pack(
            "<IIIII",
            WEIGHT_METADATA_MAGIC,
            WEIGHT_METADATA_VERSION,
            flash_offset,
            len(weights),
            weight_crc32,
        )
        image[metadata_offset:metadata_end] = weight_metadata
        image[flash_offset:flash_end] = weights
        used_ranges.append((metadata_offset, metadata_end, f"{slot['name']} metadata"))
        used_ranges.append((flash_offset, flash_end, f"{slot['name']} payload"))
        resolved_slots.append((slot, weights, weight_crc32))

    args.bin_out.parent.mkdir(parents=True, exist_ok=True)
    args.bin_out.write_bytes(image)

    if args.ihex_out:
        write_ihex(args.ihex_out, image)

    print(f"app:     {args.app} ({len(app)} bytes) -> 0x{BOOT_IMAGE_OFFSET:06X}")
    for slot, weights, weight_crc32 in resolved_slots:
        print(
            f"weights[{slot['name']}]: {slot['path']} ({len(weights)} bytes) "
            f"-> 0x{slot['flash_offset']:06X}"
        )
        print(
            f"metadata[{slot['name']}]: crc32=0x{weight_crc32:08X} "
            f"-> 0x{slot['metadata_offset']:06X}"
        )
    print(f"bin:     {args.bin_out} ({args.bin_out.stat().st_size} bytes)")
    if args.ihex_out:
        print(f"ihex:    {args.ihex_out} ({args.ihex_out.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
