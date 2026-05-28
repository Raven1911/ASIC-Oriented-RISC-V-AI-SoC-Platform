#!/usr/bin/env python3
"""Run SqueezeNet 1.1 on live frames from a capture card.

The camera frame is expected to be 640x480 by default. Preprocessing keeps the
4:3 image inside a 224x224 square by max-pooling to 224x168 and adding 28 black
rows at the top and bottom.
"""

from __future__ import annotations

import argparse
from collections import deque
import time
from pathlib import Path

import numpy as np


IMAGENET_MEAN = (0.485, 0.456, 0.406)
IMAGENET_STD = (0.229, 0.224, 0.225)


def parse_device(value: str):
    if value.isdigit():
        return int(value)
    return value


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Run SqueezeNet 1.1 ImageNet classifier on a live capture-card frame."
    )
    parser.add_argument("--device", default="0", help="OpenCV device index or path, for example 0 or /dev/video2.")
    parser.add_argument("--width", type=int, default=640, help="Capture width requested from the device.")
    parser.add_argument("--height", type=int, default=480, help="Capture height requested from the device.")
    parser.add_argument("--fps", type=float, default=0.0, help="Optional capture FPS request. 0 leaves default.")
    parser.add_argument(
        "--backend",
        choices=("auto", "v4l2"),
        default="v4l2",
        help="OpenCV capture backend. Default v4l2.",
    )
    parser.add_argument(
        "--fourcc",
        default="",
        help="Optional capture pixel format, for example MJPG or YUYV.",
    )
    parser.add_argument("--read-retries", type=int, default=30, help="Frame read retries before giving up.")
    parser.add_argument("--read-retry-delay", type=float, default=0.05, help="Delay between read retries in seconds.")
    parser.add_argument("--out-size", type=int, default=224, help="Square model input size. Default 224.")
    parser.add_argument(
        "--resize-mode",
        choices=("letterbox", "stretch"),
        default="letterbox",
        help="letterbox keeps 4:3 with padding; stretch uses no padding. Default letterbox.",
    )
    parser.add_argument("--topk", type=int, default=5, help="Number of ImageNet predictions to print/overlay.")
    parser.add_argument("--smooth", type=int, default=8, help="Average probabilities over the last N frames.")
    parser.add_argument("--min-confidence", type=float, default=0.15, help="Mark top result uncertain below this probability.")
    parser.add_argument("--cpu", action="store_true", help="Force CPU even when CUDA is available.")
    parser.add_argument("--no-preview", action="store_true", help="Run without OpenCV preview windows.")
    parser.add_argument("--print-every", type=float, default=1.0, help="Print top predictions every N seconds.")
    parser.add_argument("--max-frames", type=int, default=0, help="Stop after N frames. 0 means run until q/esc.")
    parser.add_argument(
        "--weights-file",
        type=Path,
        help="Optional local PyTorch state_dict for squeezenet1_1. If omitted, TorchVision uses ImageNet weights.",
    )
    parser.add_argument(
        "--save-input",
        type=Path,
        help="Optional PNG path for the latest 224x224 max-pooled model input preview.",
    )
    return parser.parse_args()


def open_capture(cv2, args: argparse.Namespace):
    device = parse_device(args.device)
    if args.backend == "v4l2":
        cap = cv2.VideoCapture(device, cv2.CAP_V4L2)
    else:
        cap = cv2.VideoCapture(device)

    if not cap.isOpened():
        return cap

    if args.fourcc:
        fourcc = args.fourcc.upper()
        if len(fourcc) != 4:
            raise ValueError("--fourcc must contain exactly 4 characters, for example MJPG or YUYV")
        cap.set(cv2.CAP_PROP_FOURCC, cv2.VideoWriter_fourcc(*fourcc))
    cap.set(cv2.CAP_PROP_FRAME_WIDTH, args.width)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, args.height)
    if args.fps > 0.0:
        cap.set(cv2.CAP_PROP_FPS, args.fps)
    cap.set(cv2.CAP_PROP_BUFFERSIZE, 1)
    return cap


def read_frame_with_retries(cap, retries: int, delay_s: float):
    attempts = max(1, retries)
    for attempt in range(attempts):
        ok, frame = cap.read()
        if ok:
            return True, frame
        if attempt + 1 < attempts and delay_s > 0.0:
            time.sleep(delay_s)
    return False, None


def axis_windows(in_size: int, out_size: int) -> list[tuple[int, int]]:
    fp = 16
    step = (in_size << fp) // out_size
    acc = 0
    windows: list[tuple[int, int]] = []

    for idx in range(out_size):
        start = acc >> fp
        if idx == out_size - 1:
            stop = in_size
        else:
            stop_raw = (acc + step) >> fp
            stop = max(start + 1, stop_raw)
        windows.append((start, stop))
        acc += step

    return windows


def maxpool_resize(frame_bgr: np.ndarray, out_w: int, out_h: int) -> np.ndarray:
    in_h, in_w = frame_bgr.shape[:2]
    x_windows = axis_windows(in_w, out_w)
    y_windows = axis_windows(in_h, out_h)
    resized = np.empty((out_h, out_w, 3), dtype=np.uint8)

    for oy, (y0, y1) in enumerate(y_windows):
        row = resized[oy]
        for ox, (x0, x1) in enumerate(x_windows):
            row[ox] = frame_bgr[y0:y1, x0:x1].max(axis=(0, 1))

    return resized


def letterbox_maxpool(frame_bgr: np.ndarray, out_size: int) -> tuple[np.ndarray, int, int]:
    in_h, in_w = frame_bgr.shape[:2]
    scaled_h = (out_size * in_h) // in_w
    if scaled_h <= 0 or scaled_h > out_size:
        raise ValueError(f"unsupported frame aspect ratio: {in_w}x{in_h}")

    pad_top = (out_size - scaled_h) // 2
    pad_bottom = out_size - scaled_h - pad_top

    output = np.zeros((out_size, out_size, 3), dtype=np.uint8)
    output[pad_top:pad_top + scaled_h] = maxpool_resize(frame_bgr, out_size, scaled_h)
    return output, pad_top, pad_bottom


def preprocess_frame(frame_bgr: np.ndarray, out_size: int, resize_mode: str) -> tuple[np.ndarray, int, int]:
    if resize_mode == "letterbox":
        return letterbox_maxpool(frame_bgr, out_size)
    if resize_mode == "stretch":
        return maxpool_resize(frame_bgr, out_size, out_size), 0, 0
    raise ValueError(f"unknown resize mode: {resize_mode}")


def load_model(args: argparse.Namespace):
    try:
        import torch
        from torchvision.models import SqueezeNet1_1_Weights, squeezenet1_1
    except ImportError as exc:
        missing = exc.name or "torch/torchvision"
        raise RuntimeError(
            f"Missing dependency: {missing}. Install PyTorch and TorchVision, for example: "
            "pip install torch torchvision"
        ) from exc

    if args.weights_file:
        model = squeezenet1_1(weights=None)
        state = torch.load(args.weights_file, map_location="cpu")
        if isinstance(state, dict) and "state_dict" in state:
            state = state["state_dict"]
        model.load_state_dict(state)
        categories = [str(i) for i in range(1000)]
    else:
        weights = SqueezeNet1_1_Weights.IMAGENET1K_V1
        model = squeezenet1_1(weights=weights)
        categories = weights.meta["categories"]

    device = torch.device("cpu" if args.cpu or not torch.cuda.is_available() else "cuda")
    model.to(device)
    model.eval()
    return torch, model, categories, device


def make_tensor(torch, input_bgr: np.ndarray, device):
    rgb = input_bgr[:, :, ::-1].astype(np.float32) / 255.0
    tensor = torch.from_numpy(rgb).permute(2, 0, 1).unsqueeze(0)
    mean = torch.tensor(IMAGENET_MEAN, dtype=tensor.dtype).view(1, 3, 1, 1)
    std = torch.tensor(IMAGENET_STD, dtype=tensor.dtype).view(1, 3, 1, 1)
    tensor = (tensor - mean) / std
    return tensor.to(device)


def draw_overlay(cv2, frame: np.ndarray, lines: list[str], fps: float, pad_top: int, pad_bottom: int) -> np.ndarray:
    display = frame.copy()
    cv2.putText(
        display,
        f"SqueezeNet1.1 224 maxpool pad={pad_top}/{pad_bottom} FPS={fps:.1f}",
        (12, 28),
        cv2.FONT_HERSHEY_SIMPLEX,
        0.65,
        (0, 255, 0),
        2,
        cv2.LINE_AA,
    )
    for i, line in enumerate(lines):
        cv2.putText(
            display,
            line,
            (12, 58 + i * 26),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.62,
            (0, 255, 0),
            2,
            cv2.LINE_AA,
        )
    return display


def main() -> int:
    args = parse_args()

    try:
        import cv2
    except ImportError:
        print("Missing dependency: cv2. Install with: pip install opencv-python")
        return 1

    try:
        torch, model, categories, device = load_model(args)
    except RuntimeError as exc:
        print(exc)
        return 1

    try:
        cap = open_capture(cv2, args)
    except ValueError as exc:
        print(exc)
        return 1

    if not cap.isOpened():
        print(f"Failed to open capture device: {args.device}")
        return 1

    actual_w = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    actual_h = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    actual_fps = cap.get(cv2.CAP_PROP_FPS)
    actual_fourcc = int(cap.get(cv2.CAP_PROP_FOURCC))
    fourcc_text = "".join(chr((actual_fourcc >> (8 * i)) & 0xFF) for i in range(4))
    print(f"Capture device opened: {actual_w}x{actual_h} fps={actual_fps:.2f} fourcc={fourcc_text!r}")
    print(f"Model: SqueezeNet 1.1 ImageNet on {device}")
    print(f"Preprocess: {actual_w}x{actual_h} -> {args.out_size} square by max-pool {args.resize_mode}")

    frame_count = 0
    last_print = 0.0
    last_time = time.monotonic()
    fps = 0.0
    lines: list[str] = []
    prob_history = deque(maxlen=max(1, args.smooth))

    while True:
        ok, frame = read_frame_with_retries(cap, args.read_retries, args.read_retry_delay)
        if not ok:
            print("Frame read failed after retries.")
            print("Try another /dev/video node, or try --fourcc MJPG / --fourcc YUYV.")
            print("If another app has the capture card open, close it first.")
            break

        input_bgr, pad_top, pad_bottom = preprocess_frame(frame, args.out_size, args.resize_mode)
        tensor = make_tensor(torch, input_bgr, device)

        with torch.inference_mode():
            logits = model(tensor)
            probs = torch.nn.functional.softmax(logits[0], dim=0)
            prob_history.append(probs.detach().cpu())
            smooth_probs = torch.stack(tuple(prob_history), dim=0).mean(dim=0)
            values, indices = torch.topk(smooth_probs, k=min(args.topk, smooth_probs.numel()))

        top_predictions = [
            (categories[int(idx)], float(prob) * 100.0)
            for prob, idx in zip(values, indices)
        ]
        lines = [f"{rank}. {label}: {prob:.1f}%" for rank, (label, prob) in enumerate(top_predictions, 1)]
        if top_predictions and top_predictions[0][1] < args.min_confidence * 100.0:
            lines.insert(0, "uncertain")

        now = time.monotonic()
        dt = now - last_time
        if dt > 0.0:
            fps = (0.9 * fps) + (0.1 * (1.0 / dt)) if fps > 0.0 else (1.0 / dt)
        last_time = now

        if args.save_input:
            cv2.imwrite(str(args.save_input), input_bgr)

        if now - last_print >= args.print_every:
            last_print = now
            print(" | ".join(lines))

        if not args.no_preview:
            display = draw_overlay(cv2, frame, lines, fps, pad_top, pad_bottom)
            preview = cv2.resize(input_bgr, (448, 448), interpolation=cv2.INTER_NEAREST)
            cv2.imshow("capture", display)
            cv2.imshow("squeezenet_input_224", preview)
            key = cv2.waitKey(1) & 0xFF
            if key in (ord("q"), 27):
                break

        frame_count += 1
        if args.max_frames > 0 and frame_count >= args.max_frames:
            break

    cap.release()
    if not args.no_preview:
        cv2.destroyAllWindows()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
