#!/usr/bin/env python3
"""List OpenCV-readable video devices."""

from __future__ import annotations

import argparse
from pathlib import Path
import time


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Probe /dev/video* devices with OpenCV.")
    parser.add_argument("--max-index", type=int, default=10, help="Also probe numeric indexes 0..N-1.")
    parser.add_argument("--read-frame", action="store_true", help="Try to read one frame from each device.")
    parser.add_argument("--retries", type=int, default=10, help="Read retries per device when --read-frame is used.")
    parser.add_argument("--delay", type=float, default=0.05, help="Delay between read retries.")
    return parser.parse_args()


def sysfs_name(device) -> str:
    if not isinstance(device, str) or not device.startswith("/dev/video"):
        return ""
    name_path = Path("/sys/class/video4linux") / Path(device).name / "name"
    try:
        return name_path.read_text().strip()
    except OSError:
        return ""


def read_frame_with_retries(cap, retries: int, delay_s: float):
    for attempt in range(max(1, retries)):
        ok, frame = cap.read()
        if ok:
            return True, frame
        if attempt + 1 < retries and delay_s > 0.0:
            time.sleep(delay_s)
    return False, None


def probe_device(cv2, device, read_frame: bool, retries: int, delay_s: float) -> tuple[bool, str]:
    cap = cv2.VideoCapture(device, cv2.CAP_V4L2)
    if not cap.isOpened():
        name = sysfs_name(device)
        suffix = f" name={name!r}" if name else ""
        return False, "not open" + suffix

    width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    fps = cap.get(cv2.CAP_PROP_FPS)
    backend = cap.getBackendName() if hasattr(cap, "getBackendName") else "unknown"
    fourcc = int(cap.get(cv2.CAP_PROP_FOURCC))
    fourcc_text = "".join(chr((fourcc >> (8 * i)) & 0xFF) for i in range(4))
    name = sysfs_name(device)
    name_text = f" name={name!r}" if name else ""
    detail = f"{width}x{height} fps={fps:.2f} fourcc={fourcc_text!r} backend={backend}{name_text}"

    if read_frame:
        ok, frame = read_frame_with_retries(cap, retries, delay_s)
        if ok:
            detail += f" frame={frame.shape[1]}x{frame.shape[0]}"
        else:
            detail += " frame=FAIL"

    cap.release()
    return True, detail


def main() -> int:
    args = parse_args()

    try:
        import cv2
    except ImportError:
        print("Missing dependency: cv2. Install with: pip install opencv-python")
        return 1

    candidates: list[object] = []
    seen: set[str] = set()

    for path in sorted(Path("/dev").glob("video*")):
        key = str(path)
        seen.add(key)
        candidates.append(key)

    for index in range(args.max_index):
        key = str(index)
        if key not in seen:
            candidates.append(index)

    for device in candidates:
        ok, detail = probe_device(cv2, device, args.read_frame, args.retries, args.delay)
        status = "OK" if ok else "--"
        print(f"{status:2} {device}: {detail}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
