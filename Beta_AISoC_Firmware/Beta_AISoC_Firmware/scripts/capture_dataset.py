#!/usr/bin/env python3
"""Capture labeled 640x480 frames from a UVC/HDMI capture device.

Example:
  python3 scripts/capture_dataset.py --device 0
  python3 scripts/capture_dataset.py --device 0 --label rock --count 200
  python3 scripts/capture_dataset.py --device /dev/video2 --label paper --interval 0.5

Keys in preview mode:
  0-2     : select rock/paper/scissors class in menu mode
  space/s : save one frame for the selected class
  b       : back to class menu
  n       : start the next person counter
  f       : toggle fullscreen preview
  q/esc   : quit
"""

from __future__ import annotations

import argparse
import time
from pathlib import Path


RPS_LABELS = (
    "rock",
    "paper",
    "scissors",
)
CAPTURE_WINDOW = "capture"
RTL_PREVIEW_WINDOW = "rtl_32x32_preview"
SIDEBAR_WIDTH = 320


def parse_device(value: str):
    if value.isdigit():
        return int(value)
    return value


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Capture labeled PNG frames from a 640x480 camera/capture card."
    )
    parser.add_argument(
        "--device",
        default="0",
        help="OpenCV device index or path, for example 0 or /dev/video2.",
    )
    parser.add_argument(
        "--label",
        choices=RPS_LABELS,
        default=None,
        help="Class label folder to save into. Omit for interactive class menu.",
    )
    parser.add_argument(
        "--out",
        default="dataset_capture/raw",
        help="Output root. Images are saved under <out>/<label>/.",
    )
    parser.add_argument(
        "--count",
        type=int,
        default=0,
        help="Stop after this many saved images. 0 means unlimited until q/esc.",
    )
    parser.add_argument(
        "--interval",
        type=float,
        default=0.0,
        help="Auto-save interval in seconds. 0 means manual save with space/s.",
    )
    parser.add_argument(
        "--warmup",
        type=float,
        default=2.0,
        help="Seconds to wait before saving frames.",
    )
    parser.add_argument(
        "--width",
        type=int,
        default=640,
        help="Capture width requested from the device.",
    )
    parser.add_argument(
        "--height",
        type=int,
        default=480,
        help="Capture height requested from the device.",
    )
    parser.add_argument(
        "--no-preview",
        action="store_true",
        help="Run headless without an OpenCV preview window.",
    )
    parser.add_argument(
        "--show-32",
        action="store_true",
        help="Show a 32x32 preview using RTL-like letterbox geometry.",
    )
    parser.add_argument(
        "--fullscreen",
        action="store_true",
        help="Start the main preview window in fullscreen mode.",
    )
    parser.add_argument(
        "--preview-scale",
        type=float,
        default=1.0,
        help="Initial whole preview scale. 1.0 keeps the camera image at native display size.",
    )
    parser.add_argument(
        "--person-target",
        type=int,
        default=30,
        help="Target image count per class for one person.",
    )
    return parser.parse_args()


def make_rtl_preview(frame, cv2):
    """Create a visual 32x32 preview: 640x480 -> 32x24 + 4px top/bottom pad."""
    resized = cv2.resize(frame, (32, 24), interpolation=cv2.INTER_AREA)
    preview = cv2.copyMakeBorder(
        resized,
        4,
        4,
        0,
        0,
        cv2.BORDER_CONSTANT,
        value=(0, 0, 0),
    )
    return cv2.resize(preview, (320, 320), interpolation=cv2.INTER_NEAREST)


def timestamp_name(label: str, index: int) -> str:
    return f"{label}_{index:06d}.png"


def next_image_index(out_root: Path, label: str) -> int:
    out_dir = out_root / label
    prefix = f"{label}_"
    max_index = -1

    if not out_dir.exists():
        return 0

    for path in out_dir.glob(f"{label}_*.png"):
        stem = path.stem
        if not stem.startswith(prefix):
            continue

        suffix = stem[len(prefix) :]
        if suffix.isdigit():
            max_index = max(max_index, int(suffix))

    return max_index + 1


def count_label_images(out_root: Path, label: str) -> int:
    out_dir = out_root / label
    prefix = f"{label}_"

    if not out_dir.exists():
        return 0

    return sum(
        1
        for path in out_dir.glob(f"{label}_*.png")
        if path.stem.startswith(prefix) and path.stem[len(prefix) :].isdigit()
    )


def label_from_key(key: int) -> str | None:
    if ord("0") <= key < ord("0") + len(RPS_LABELS):
        return RPS_LABELS[key - ord("0")]
    return None


def set_capture_fullscreen(cv2, enabled: bool) -> None:
    mode = cv2.WINDOW_FULLSCREEN if enabled else cv2.WINDOW_NORMAL
    cv2.setWindowProperty(CAPTURE_WINDOW, cv2.WND_PROP_FULLSCREEN, mode)


def draw_panel_text(cv2, canvas, text: str, x: int, y: int, scale: float, color, thickness: int = 1) -> None:
    cv2.putText(
        canvas,
        text,
        (x, y),
        cv2.FONT_HERSHEY_SIMPLEX,
        scale,
        color,
        thickness,
        cv2.LINE_AA,
    )


def make_capture_view(
    frame,
    cv2,
    selected_label: str | None,
    next_indices: dict[str, int],
    total_counts: dict[str, int],
    session_counts: dict[str, int],
    person_counts: dict[str, int],
    person_index: int,
    person_target: int,
    total_saved: int,
    warmup_done: bool,
):
    canvas = cv2.copyMakeBorder(
        frame,
        0,
        0,
        0,
        SIDEBAR_WIDTH,
        cv2.BORDER_CONSTANT,
        value=(24, 24, 24),
    )

    x = frame.shape[1] + 18
    y = 30
    white = (235, 235, 235)
    green = (0, 220, 0)
    cyan = (220, 220, 0)
    gray = (180, 180, 180)

    draw_panel_text(cv2, canvas, "Capture", x, y, 0.8, white, 2)
    y += 34
    mode_text = "menu" if selected_label is None else selected_label
    draw_panel_text(cv2, canvas, f"mode: {mode_text}", x, y, 0.58, green, 1)
    y += 28
    draw_panel_text(cv2, canvas, f"person: {person_index}", x, y, 0.58, white, 1)
    y += 24
    draw_panel_text(cv2, canvas, f"target/class: {person_target}", x, y, 0.58, white, 1)
    y += 32

    draw_panel_text(cv2, canvas, "person counter", x, y, 0.58, cyan, 1)
    y += 24
    for label in RPS_LABELS:
        color = green if label == selected_label else white
        draw_panel_text(
            cv2,
            canvas,
            f"{label:<8} {person_counts.get(label, 0):>3}/{person_target}",
            x,
            y,
            0.56,
            color,
            1,
        )
        y += 22

    y += 12
    draw_panel_text(cv2, canvas, "dataset total", x, y, 0.58, cyan, 1)
    y += 24
    for label in RPS_LABELS:
        draw_panel_text(
            cv2,
            canvas,
            f"{label:<8} {total_counts.get(label, 0):>4}",
            x,
            y,
            0.56,
            white,
            1,
        )
        y += 22

    y += 12
    draw_panel_text(cv2, canvas, f"session saved: {total_saved}", x, y, 0.56, white, 1)
    y += 22
    if selected_label is not None:
        draw_panel_text(
            cv2,
            canvas,
            f"next file: {next_indices.get(selected_label, 0):06d}",
            x,
            y,
            0.56,
            white,
            1,
        )
        y += 22
        draw_panel_text(
            cv2,
            canvas,
            f"class session: {session_counts.get(selected_label, 0)}",
            x,
            y,
            0.56,
            white,
            1,
        )
        y += 22
        if not warmup_done:
            draw_panel_text(cv2, canvas, "warmup", x, y, 0.56, green, 1)
            y += 22

    y = max(y + 14, frame.shape[0] - 118)
    draw_panel_text(cv2, canvas, "keys", x, y, 0.58, cyan, 1)
    y += 22
    draw_panel_text(cv2, canvas, "0/1/2 select class", x, y, 0.48, gray, 1)
    y += 19
    draw_panel_text(cv2, canvas, "space/s save", x, y, 0.48, gray, 1)
    y += 19
    draw_panel_text(cv2, canvas, "b menu   n next person", x, y, 0.48, gray, 1)
    y += 19
    draw_panel_text(cv2, canvas, "f fullscreen   q quit", x, y, 0.48, gray, 1)
    return canvas


def save_frame(
    frame,
    cv2,
    out_root: Path,
    label: str,
    next_indices: dict[str, int],
    total_counts: dict[str, int],
    session_counts: dict[str, int],
    person_counts: dict[str, int],
) -> bool:
    out_dir = out_root / label
    out_dir.mkdir(parents=True, exist_ok=True)
    index = next_indices.get(label, 0)
    path = out_dir / timestamp_name(label, index)

    while path.exists():
        index += 1
        path = out_dir / timestamp_name(label, index)

    if cv2.imwrite(str(path), frame):
        next_indices[label] = index + 1
        total_counts[label] = total_counts.get(label, 0) + 1
        session_counts[label] = session_counts.get(label, 0) + 1
        person_counts[label] = person_counts.get(label, 0) + 1
        print(f"[{label} #{index:06d}] {path}")
        return True
    print(f"Failed to save: {path}")
    return False


def main() -> int:
    args = parse_args()

    try:
        import cv2
    except ImportError:
        print("Missing dependency: python3-opencv / cv2")
        print("Install with: pip install opencv-python")
        return 1

    out_root = Path(args.out)
    out_root.mkdir(parents=True, exist_ok=True)

    cap = cv2.VideoCapture(parse_device(args.device))
    if not cap.isOpened():
        print(f"Failed to open capture device: {args.device}")
        return 1

    cap.set(cv2.CAP_PROP_FRAME_WIDTH, args.width)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, args.height)

    actual_w = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    actual_h = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    print(f"Capture device opened: {actual_w}x{actual_h}")
    print(f"Saving PNG frames under: {out_root}")
    if args.interval > 0.0:
        print(f"Auto capture interval: {args.interval:.3f}s")
    else:
        print("Manual capture: select 0-2, press space or s to save, b for menu.")

    warmup_deadline = time.monotonic() + max(args.warmup, 0.0)
    next_indices = {label: next_image_index(out_root, label) for label in RPS_LABELS}
    total_counts = {label: count_label_images(out_root, label) for label in RPS_LABELS}
    session_counts = {label: 0 for label in RPS_LABELS}
    person_counts = {label: 0 for label in RPS_LABELS}
    person_index = 1
    person_target = max(args.person_target, 1)
    selected_label = args.label
    total_saved = 0
    last_save = 0.0

    for label in RPS_LABELS:
        print(
            f"{label}: total={total_counts[label]} "
            f"next={next_indices[label]:06d}"
        )

    fullscreen = args.fullscreen
    if not args.no_preview:
        preview_scale = max(args.preview_scale, 0.1)
        preview_w = max(1, int(round((actual_w + SIDEBAR_WIDTH) * preview_scale)))
        preview_h = max(1, int(round(actual_h * preview_scale)))
        cv2.namedWindow(CAPTURE_WINDOW, cv2.WINDOW_NORMAL)
        cv2.resizeWindow(CAPTURE_WINDOW, preview_w, preview_h)
        set_capture_fullscreen(cv2, fullscreen)
        if args.show_32:
            cv2.namedWindow(RTL_PREVIEW_WINDOW, cv2.WINDOW_NORMAL)
            cv2.resizeWindow(RTL_PREVIEW_WINDOW, 320, 320)
        print(
            f"Preview window: {preview_w}x{preview_h}; "
            f"camera image stays {actual_w}x{actual_h}."
        )
        print("Preview window is resizable. Press f to toggle fullscreen.")

    while True:
        ok, frame = cap.read()
        if not ok:
            print("Frame read failed.")
            break

        now = time.monotonic()
        warmup_done = now >= warmup_deadline
        do_save = False

        if selected_label and warmup_done and args.interval > 0.0 and (now - last_save) >= args.interval:
            do_save = True

        if do_save:
            if save_frame(
                frame,
                cv2,
                out_root,
                selected_label,
                next_indices,
                total_counts,
                session_counts,
                person_counts,
            ):
                total_saved += 1
                last_save = now

        if not args.no_preview:
            display = make_capture_view(
                frame,
                cv2,
                selected_label,
                next_indices,
                total_counts,
                session_counts,
                person_counts,
                person_index,
                person_target,
                total_saved,
                warmup_done,
            )
            cv2.imshow(CAPTURE_WINDOW, display)
            if args.show_32:
                cv2.imshow(RTL_PREVIEW_WINDOW, make_rtl_preview(frame, cv2))

            key = cv2.waitKey(1) & 0xFF
            if key in (27, ord("q")):
                break
            if key == ord("f"):
                fullscreen = not fullscreen
                set_capture_fullscreen(cv2, fullscreen)
                print("Fullscreen on." if fullscreen else "Fullscreen off.")
                continue
            if key == ord("n"):
                person_index += 1
                person_counts = {label: 0 for label in RPS_LABELS}
                print(f"Start person {person_index}.")
                continue
            if key == ord("b"):
                selected_label = None
                print("Back to class menu.")
            elif selected_label is None:
                next_label = label_from_key(key)
                if next_label is not None:
                    selected_label = next_label
                    print(f"Selected class: {selected_label}")
            elif warmup_done and key in (ord(" "), ord("s")):
                if save_frame(
                    frame,
                    cv2,
                    out_root,
                    selected_label,
                    next_indices,
                    total_counts,
                    session_counts,
                    person_counts,
                ):
                    total_saved += 1
                    last_save = now
        else:
            time.sleep(0.005)

        if args.count > 0 and total_saved >= args.count:
            break

    cap.release()
    if not args.no_preview:
        cv2.destroyAllWindows()
    print(f"Done. Saved {total_saved} image(s).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
