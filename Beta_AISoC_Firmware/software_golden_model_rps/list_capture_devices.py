"""
List camera/capture-card device indices visible to OpenCV.
"""
import argparse

import cv2


def main():
    parser = argparse.ArgumentParser(description="Scan OpenCV camera device indices.")
    parser.add_argument("--max-index", type=int, default=10)
    parser.add_argument("--width", type=int, default=640)
    parser.add_argument("--height", type=int, default=480)
    args = parser.parse_args()

    print(f"Scanning device IDs 0..{args.max_index}")
    print("=" * 50)

    found = False
    for device_id in range(args.max_index + 1):
        cap = cv2.VideoCapture(device_id)
        if not cap.isOpened():
            cap.release()
            continue

        cap.set(cv2.CAP_PROP_FRAME_WIDTH, args.width)
        cap.set(cv2.CAP_PROP_FRAME_HEIGHT, args.height)
        ret, frame = cap.read()

        if ret and frame is not None:
            found = True
            actual_width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
            actual_height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
            fps = cap.get(cv2.CAP_PROP_FPS)
            print(
                f"Device {device_id}: OK | "
                f"frame={frame.shape} | capture={actual_width}x{actual_height} | fps={fps:.2f}"
            )
        else:
            print(f"Device {device_id}: opened but could not read frame")

        cap.release()

    if not found:
        print("No readable camera/capture-card devices found.")


if __name__ == "__main__":
    main()
