#!/usr/bin/env python3
"""Compare SoC static intermediate CRC UART logs against a golden JSON file."""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from typing import Dict, List, Optional, Tuple


MISMATCH_RE = re.compile(
    r"STATIC_INTERMEDIATE first_mismatch name=(?P<name>\S+) "
    r"tensor=(?P<tensor>\d+) .* crc=0x(?P<crc>[0-9A-Fa-f]+) "
    r"expected=0x(?P<expected>[0-9A-Fa-f]+)"
)
CHANNEL_RE = re.compile(r"\bch=(?P<ch>\d+)\s+crc=0x(?P<crc>[0-9A-Fa-f]+)")


def load_refs(path: Path) -> List[dict]:
    data = json.loads(path.read_text(encoding="utf-8"))
    return list(data.get("soc_intermediate", {}).get("references", []))


def find_ref(refs: List[dict], name: str, tensor: int) -> Optional[dict]:
    for ref in refs:
        if str(ref.get("name")) == name and int(ref.get("tensor", -1)) == tensor:
            return ref
    return None


def parse_log(path: Path) -> Tuple[Optional[dict], Dict[int, int]]:
    mismatch = None
    channels: Dict[int, int] = {}
    in_channel_dump = False

    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        m = MISMATCH_RE.search(line)
        if m:
            mismatch = {
                "name": m.group("name"),
                "tensor": int(m.group("tensor")),
                "crc": int(m.group("crc"), 16),
                "expected": int(m.group("expected"), 16),
            }
            channels.clear()
            in_channel_dump = False
            continue

        if "STATIC_INTERMEDIATE channel CRC dump:" in line:
            in_channel_dump = True
            continue

        if in_channel_dump:
            m = CHANNEL_RE.search(line)
            if m:
                channels[int(m.group("ch"))] = int(m.group("crc"), 16)
                continue
            if line.strip() and not line.lstrip().startswith("..."):
                in_channel_dump = False

    return mismatch, channels


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--golden", type=Path, required=True, help="dog_golden.json or another static golden JSON")
    parser.add_argument("--log", type=Path, required=True, help="UART log captured from the SoC run")
    args = parser.parse_args()

    refs = load_refs(args.golden)
    mismatch, channels = parse_log(args.log)

    if mismatch is None:
        raise SystemExit("No STATIC_INTERMEDIATE first_mismatch line found in log.")

    ref = find_ref(refs, mismatch["name"], mismatch["tensor"])
    print(
        f"tensor {mismatch['name']} #{mismatch['tensor']}: "
        f"soc_crc=0x{mismatch['crc']:08X}, golden_crc=0x{mismatch['expected']:08X}"
    )
    if ref is None:
        raise SystemExit("No matching tensor reference found in golden JSON.")

    golden_channels = [int(str(v), 0) for v in ref.get("channel_crc32", [])]
    if not golden_channels:
        raise SystemExit("Golden JSON has no channel_crc32 for this tensor. Re-run prepare_static_image_input.py.")

    if not channels:
        raise SystemExit("No channel CRC dump found in log. Rebuild app with the latest generator.")

    first_bad = None
    for ch in sorted(channels):
        expected = golden_channels[ch] if ch < len(golden_channels) else None
        actual = channels[ch]
        if expected is None or actual != expected:
            first_bad = (ch, actual, expected)
            break

    if first_bad is None:
        print("All dumped channels match golden; mismatch is after dumped range or in full-tensor ordering.")
        return

    ch, actual, expected = first_bad
    if expected is None:
        print(f"first bad channel: {ch}, soc_crc=0x{actual:08X}, golden channel missing")
    else:
        print(f"first bad channel: {ch}, soc_crc=0x{actual:08X}, golden_crc=0x{expected:08X}")


if __name__ == "__main__":
    main()
