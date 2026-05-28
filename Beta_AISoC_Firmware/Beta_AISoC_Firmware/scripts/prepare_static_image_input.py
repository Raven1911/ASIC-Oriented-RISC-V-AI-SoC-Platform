#!/usr/bin/env python3
"""Prepare a static image input payload and golden output for an int8 TFLite model."""

from __future__ import annotations

import argparse
import json
import zlib
from pathlib import Path
from typing import List

import numpy as np
from PIL import Image
import tensorflow as tf


def align_up(value: int, alignment: int) -> int:
    if alignment <= 1:
        return value
    return (value + alignment - 1) // alignment * alignment


def load_labels(path: Path) -> List[str]:
    if not path.exists():
        return []
    return [line.strip() for line in path.read_text(encoding="utf-8").splitlines()]


def resize_short_center_crop(image: Image.Image, resize_short: int, crop_size: int) -> Image.Image:
    width, height = image.size
    if width <= 0 or height <= 0:
        raise ValueError("image has invalid dimensions")

    if width < height:
        new_width = resize_short
        new_height = int(round(height * resize_short / width))
    else:
        new_height = resize_short
        new_width = int(round(width * resize_short / height))

    resample = getattr(Image, "Resampling", Image).BILINEAR
    resized = image.resize((new_width, new_height), resample)
    left = (new_width - crop_size) // 2
    top = (new_height - crop_size) // 2
    return resized.crop((left, top, left + crop_size, top + crop_size))


def quantize_pixels_fixed(rgb: np.ndarray, fixed: dict) -> np.ndarray:
    shift = int(fixed["shift"])
    mult = np.asarray(fixed["mult"], dtype=np.int64).reshape(1, 1, 3)
    offset = np.asarray(fixed["offset"], dtype=np.int64).reshape(1, 1, 3)
    values = rgb.astype(np.int64) * mult + offset
    quant = np.rint(values.astype(np.float64) / float(1 << shift))
    return np.clip(quant, -128, 127).astype(np.int8)


def pack_chw_row_aligned(q_hwc: np.ndarray, row_align: int) -> bytes:
    height, width, channels = q_hwc.shape
    row_stride = align_up(width, row_align)
    out = bytearray(channels * height * row_stride)

    pos = 0
    for channel in range(channels):
        for y in range(height):
            row = q_hwc[y, :, channel].astype(np.int8).tobytes()
            out[pos : pos + width] = row
            pos += row_stride

    return bytes(out)


def pack_chw_logical(q_hwc: np.ndarray, height: int, width: int, channels: int) -> bytes:
    if q_hwc.ndim == 4:
        q_hwc = q_hwc[0]
    if q_hwc.shape[0] < height or q_hwc.shape[1] < width or q_hwc.shape[2] < channels:
        raise ValueError(f"tensor shape {q_hwc.shape} is smaller than requested {height}x{width}x{channels}")

    out = bytearray(height * width * channels)
    pos = 0
    for channel in range(channels):
        for y in range(height):
            row = q_hwc[y, :width, channel].astype(np.int8).tobytes()
            out[pos : pos + width] = row
            pos += width
    return bytes(out)


def topk(values: np.ndarray, labels: List[str], count: int = 5) -> List[dict]:
    order = np.argsort(values)[-count:][::-1]
    result = []
    for idx in order:
        label = labels[int(idx)] if int(idx) < len(labels) else str(int(idx))
        result.append({"index": int(idx), "label": label, "value": float(values[int(idx)])})
    return result


def build_intermediate_references(interpreter: tf.lite.Interpreter, manifest: dict) -> List[dict]:
    refs = []
    layers_by_name = {layer["name"]: layer for layer in manifest.get("layers", [])}
    cpu_ops_by_name = {op["name"]: op for op in manifest.get("cpu_fallback_ops", [])}

    for step_index, step in enumerate(manifest.get("execution_steps", [])):
        if step["kind"] == "ACCEL_CONV":
            layer = layers_by_name[step["name"]]
            tensor_index = int(layer["output_tensor"])
            height = int(layer["ofheight"])
            width = int(layer["ofwidth"])
            channels = int(layer["ofchannel"])
            row_stride = int(layer["ofrow_stride"])
            addr = int(layer["ofbaddr"])
        elif step["kind"] == "CPU_OP":
            op = cpu_ops_by_name[step["name"]]
            output_view = op["output_view"]
            tensor_index = int(output_view["tensor"])
            height = int(output_view["height"])
            width = int(output_view["width"])
            channels = int(output_view["channels"])
            row_stride = int(output_view["row_stride"])
            addr = int(output_view["addr"])
        else:
            continue

        tensor_value = interpreter.get_tensor(tensor_index)
        packed = pack_chw_logical(tensor_value, height, width, channels)
        channel_bytes = height * width
        channel_crc32 = [
            f"0x{zlib.crc32(packed[c * channel_bytes : (c + 1) * channel_bytes]) & 0xFFFFFFFF:08X}"
            for c in range(channels)
        ]
        refs.append(
            {
                "step_index": int(step_index),
                "kind": step["kind"],
                "name": step["name"],
                "tensor": tensor_index,
                "addr": addr,
                "height": height,
                "width": width,
                "channels": channels,
                "row_stride": row_stride,
                "logical_bytes": len(packed),
                "crc32": f"0x{zlib.crc32(packed) & 0xFFFFFFFF:08X}",
                "channel_crc32": channel_crc32,
            }
        )
    return refs


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--model-dir", type=Path, required=True)
    parser.add_argument("--image", type=Path, required=True)
    parser.add_argument("--out-dir", type=Path, default=Path("Build/input_payloads"))
    parser.add_argument("--name", help="Output basename; default is image stem")
    parser.add_argument("--row-align", type=int, default=2)
    parser.add_argument("--resize-short", type=int, default=256)
    parser.add_argument("--crop-size", type=int, default=224)
    args = parser.parse_args()

    model_path = args.model_dir / "model.tflite"
    params_path = args.model_dir / "fixed_params.json"
    labels_path = args.model_dir / "labels.txt"
    if not model_path.exists():
        raise FileNotFoundError(model_path)
    if not params_path.exists():
        raise FileNotFoundError(params_path)

    params = json.loads(params_path.read_text(encoding="utf-8"))
    input_info = params["input"]
    fixed = input_info["fixed"]
    name = args.name or args.image.stem
    args.out_dir.mkdir(parents=True, exist_ok=True)

    cropped = resize_short_center_crop(Image.open(args.image).convert("RGB"), args.resize_short, args.crop_size)
    rgb = np.asarray(cropped, dtype=np.uint8)
    q_hwc = quantize_pixels_fixed(rgb, fixed)
    payload = pack_chw_row_aligned(q_hwc, args.row_align)

    input_bin = args.out_dir / f"{name}_ifmap_chw.bin"
    preview_png = args.out_dir / f"{name}_preprocessed_rgb.png"
    golden_json = args.out_dir / f"{name}_golden.json"
    input_bin.write_bytes(payload)
    cropped.save(preview_png)

    interpreter = tf.lite.Interpreter(
        model_path=str(model_path),
        experimental_preserve_all_tensors=True,
        experimental_op_resolver_type=tf.lite.experimental.OpResolverType.BUILTIN_WITHOUT_DEFAULT_DELEGATES,
    )
    interpreter.allocate_tensors()
    input_detail = interpreter.get_input_details()[0]
    output_detail = interpreter.get_output_details()[0]
    interpreter.set_tensor(input_detail["index"], q_hwc.reshape(1, args.crop_size, args.crop_size, 3))
    interpreter.invoke()

    output_q = interpreter.get_tensor(output_detail["index"])[0].astype(np.int32)
    output_scale, output_zp = output_detail["quantization"]
    output_dequant = (output_q.astype(np.float32) - int(output_zp)) * float(output_scale)

    manifest_path = args.model_dir.parents[1] / "Build" / "weight_payloads" / f"{args.model_dir.name}_accel_manifest.json"
    final_conv_tensor = None
    final_conv_zp = 0
    soc_gap_logits = []
    soc_top5 = []
    if manifest_path.exists():
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        final_layer = manifest["layers"][-1]
        final_conv_tensor = int(final_layer["output_tensor"])
        final_conv_zp = int(final_layer["zpy"])
        final_conv = interpreter.get_tensor(final_conv_tensor).astype(np.int32)
        soc_gap_logits = np.mean(final_conv[0] - final_conv_zp, axis=(0, 1)).astype(np.int32).tolist()
        soc_top5 = topk(np.asarray(soc_gap_logits, dtype=np.float32), load_labels(labels_path), 5)
        intermediate_refs = build_intermediate_references(interpreter, manifest)
    else:
        intermediate_refs = []

    labels = load_labels(labels_path)
    golden = {
        "model_dir": str(args.model_dir),
        "image": str(args.image),
        "input_bin": str(input_bin),
        "preview_png": str(preview_png),
        "preprocess": {
            "resize_short": args.resize_short,
            "center_crop": args.crop_size,
            "color_order": "RGB",
            "row_align": args.row_align,
            "layout": "CHW, row_stride=align_up(width,row_align)",
            "fixed": fixed,
        },
        "input": {
            "shape_nhwc": [1, args.crop_size, args.crop_size, 3],
            "payload_bytes": len(payload),
            "row_stride": align_up(args.crop_size, args.row_align),
        },
        "tflite_output": {
            "tensor_index": int(output_detail["index"]),
            "scale": float(output_scale),
            "zero_point": int(output_zp),
            "top5": topk(output_dequant, labels, 5),
            "top5_quantized": topk(output_q.astype(np.float32), labels, 5),
            "int8": [int(v) for v in output_q.tolist()],
        },
        "soc_reference": {
            "description": "Expected logits printed by generated RunStaticImageFromFlash: mean(final_conv_int8 - final_conv_zp) per class.",
            "final_conv_tensor": final_conv_tensor,
            "final_conv_zero_point": final_conv_zp,
            "top5": soc_top5,
            "logits": soc_gap_logits,
        },
        "soc_intermediate": {
            "description": "CRC32 of logical CHW tensor bytes after each generated execution step; row padding/dummy bytes are excluded.",
            "references": intermediate_refs,
        },
    }
    golden_json.write_text(json.dumps(golden, indent=2) + "\n", encoding="utf-8")

    print(f"input bin : {input_bin} ({len(payload)} bytes)")
    print(f"golden    : {golden_json}")
    print(f"preview   : {preview_png}")
    if soc_top5:
        top = soc_top5[0]
        print(f"SoC ref top1: {top['index']} {top['label']} value={top['value']}")
    tflite_top = golden["tflite_output"]["top5"][0]
    print(f"TFLite top1 : {tflite_top['index']} {tflite_top['label']} value={tflite_top['value']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
