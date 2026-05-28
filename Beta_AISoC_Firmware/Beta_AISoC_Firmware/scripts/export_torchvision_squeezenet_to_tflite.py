#!/usr/bin/env python3
"""Export TorchVision SqueezeNet 1.1 weights to a TensorFlow Lite model.

This script avoids an ONNX dependency by rebuilding the SqueezeNet 1.1 graph in
Keras, copying the TorchVision convolution weights, then using the TensorFlow
Lite converter. The exported model input is the normalized ImageNet tensor, so
the generated fixed_params.json can be used to quantize raw RGB pixels into the
same int8 input domain.
"""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
from typing import Dict, Iterable, Tuple

os.environ.setdefault("TF_CPP_MIN_LOG_LEVEL", "2")

import numpy as np
import tensorflow as tf
import torch
from torchvision.models import SqueezeNet1_1_Weights, squeezenet1_1


IMAGENET_MEAN = np.array([0.485, 0.456, 0.406], dtype=np.float32)
IMAGENET_STD = np.array([0.229, 0.224, 0.225], dtype=np.float32)
PIXEL_DENOMINATOR = 255.0


def conv2d(name: str, filters: int, kernel_size: int, stride: int = 1, padding: str = "valid"):
    return tf.keras.layers.Conv2D(
        filters=filters,
        kernel_size=kernel_size,
        strides=stride,
        padding=padding,
        use_bias=True,
        name=name,
    )


def fire_module(
    x,
    convs: Dict[str, tf.keras.layers.Conv2D],
    prefix: str,
    inplanes: int,
    squeeze_planes: int,
    expand1x1_planes: int,
    expand3x3_planes: int,
):
    del inplanes

    sq = conv2d(f"{prefix}_squeeze", squeeze_planes, 1)
    convs[f"{prefix}.squeeze"] = sq
    x = tf.keras.layers.ReLU(name=f"{prefix}_squeeze_relu")(sq(x))

    exp1 = conv2d(f"{prefix}_expand1x1", expand1x1_planes, 1)
    convs[f"{prefix}.expand1x1"] = exp1
    y1 = tf.keras.layers.ReLU(name=f"{prefix}_expand1x1_relu")(exp1(x))

    exp3 = conv2d(f"{prefix}_expand3x3", expand3x3_planes, 3, padding="same")
    convs[f"{prefix}.expand3x3"] = exp3
    y3 = tf.keras.layers.ReLU(name=f"{prefix}_expand3x3_relu")(exp3(x))

    return tf.keras.layers.Concatenate(axis=-1, name=f"{prefix}_concat")([y1, y3])


def build_keras_squeezenet1_1(input_size: int) -> Tuple[tf.keras.Model, Dict[str, tf.keras.layers.Conv2D]]:
    inputs = tf.keras.Input(shape=(input_size, input_size, 3), name="input")
    convs: Dict[str, tf.keras.layers.Conv2D] = {}

    c0 = conv2d("features_0", 64, 3, stride=2)
    convs["features.0"] = c0
    x = tf.keras.layers.ReLU(name="features_1")(c0(inputs))
    x = tf.keras.layers.MaxPooling2D(pool_size=3, strides=2, padding="valid", name="features_2")(x)

    x = fire_module(x, convs, "features.3", 64, 16, 64, 64)
    x = fire_module(x, convs, "features.4", 128, 16, 64, 64)
    x = tf.keras.layers.MaxPooling2D(pool_size=3, strides=2, padding="valid", name="features_5")(x)
    x = fire_module(x, convs, "features.6", 128, 32, 128, 128)
    x = fire_module(x, convs, "features.7", 256, 32, 128, 128)
    x = tf.keras.layers.MaxPooling2D(pool_size=3, strides=2, padding="valid", name="features_8")(x)
    x = fire_module(x, convs, "features.9", 256, 48, 192, 192)
    x = fire_module(x, convs, "features.10", 384, 48, 192, 192)
    x = fire_module(x, convs, "features.11", 384, 64, 256, 256)
    x = fire_module(x, convs, "features.12", 512, 64, 256, 256)

    final_conv = conv2d("classifier_1", 1000, 1)
    convs["classifier.1"] = final_conv
    x = tf.keras.layers.ReLU(name="classifier_2")(final_conv(x))
    outputs = tf.keras.layers.GlobalAveragePooling2D(name="classifier_3")(x)
    return tf.keras.Model(inputs=inputs, outputs=outputs, name="squeezenet1_1_imagenet"), convs


def copy_conv_weights(
    keras_convs: Dict[str, tf.keras.layers.Conv2D],
    torch_state: Dict[str, torch.Tensor],
) -> None:
    for prefix, layer in keras_convs.items():
        weight = torch_state[f"{prefix}.weight"].detach().cpu().numpy()
        bias = torch_state[f"{prefix}.bias"].detach().cpu().numpy()
        layer.set_weights([np.transpose(weight, (2, 3, 1, 0)), bias])


def normalize_rgb01(rgb01: np.ndarray) -> np.ndarray:
    return ((rgb01.astype(np.float32) - IMAGENET_MEAN) / IMAGENET_STD).astype(np.float32)


def representative_dataset(input_size: int, count: int) -> Iterable[list[np.ndarray]]:
    rng = np.random.default_rng(20260523)
    anchors = [
        np.zeros((1, input_size, input_size, 3), dtype=np.float32),
        np.ones((1, input_size, input_size, 3), dtype=np.float32),
        np.full((1, input_size, input_size, 3), 0.5, dtype=np.float32),
    ]
    for sample in anchors:
        yield [normalize_rgb01(sample)]
    for _ in range(max(0, count - len(anchors))):
        sample = rng.random((1, input_size, input_size, 3), dtype=np.float32)
        yield [normalize_rgb01(sample)]


def choose_fixed_input_params(input_scale: float, input_zero_point: int):
    real_mult = 1.0 / (PIXEL_DENOMINATOR * IMAGENET_STD * input_scale)
    real_offset = input_zero_point - (IMAGENET_MEAN / (IMAGENET_STD * input_scale))

    shift = 0
    for candidate in range(31, -1, -1):
        scale = 1 << candidate
        mult_ok = np.all(np.abs(np.rint(real_mult * scale).astype(np.int64)) <= 0x7FFFFFFF)
        offset_ok = np.all(np.abs(np.rint(real_offset * scale).astype(np.int64)) <= 0x7FFFFFFF)
        if mult_ok and offset_ok:
            shift = candidate
            break

    scale = 1 << shift
    mult = np.rint(real_mult * scale).astype(np.int64).tolist()
    offset = np.rint(real_offset * scale).astype(np.int64).tolist()
    return shift, [int(v) for v in mult], [int(v) for v in offset]


def write_text_lines(path: Path, lines: Iterable[str]) -> None:
    path.write_text("".join(f"{line}\n" for line in lines), encoding="utf-8")


def parse_args() -> argparse.Namespace:
    default_root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--out-dir",
        type=Path,
        default=default_root / "models" / "squeezenet1_1_imagenet",
        help="Output model directory",
    )
    parser.add_argument(
        "--weights",
        type=Path,
        default=Path.home() / ".cache" / "torch" / "hub" / "checkpoints" / "squeezenet1_1-b8a52dc0.pth",
        help="Local TorchVision squeezenet1_1 checkpoint",
    )
    parser.add_argument("--input-size", type=int, default=224)
    parser.add_argument("--representative-count", type=int, default=64)
    parser.add_argument(
        "--keep-per-tensor-weights",
        action="store_true",
        default=True,
        help="Disable TFLite per-channel weight quantization so accelerator sidecar stays per-layer",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if not args.weights.exists():
        raise FileNotFoundError(
            f"TorchVision checkpoint not found: {args.weights}. "
            "Run the TorchVision model once or pass --weights."
        )

    args.out_dir.mkdir(parents=True, exist_ok=True)
    tf.keras.backend.clear_session()

    torch_model = squeezenet1_1(weights=None)
    torch_state = torch.load(args.weights, map_location="cpu")
    torch_model.load_state_dict(torch_state)
    torch_model.eval()

    keras_model, keras_convs = build_keras_squeezenet1_1(args.input_size)
    copy_conv_weights(keras_convs, torch_state)

    rng = np.random.default_rng(1234)
    rgb01 = rng.random((1, args.input_size, args.input_size, 3), dtype=np.float32)
    normalized = normalize_rgb01(rgb01)
    with torch.no_grad():
        torch_out = torch_model(torch.from_numpy(np.transpose(normalized, (0, 3, 1, 2)))).detach().cpu().numpy()
    keras_out = keras_model(normalized, training=False).numpy()
    max_abs_diff = float(np.max(np.abs(torch_out - keras_out)))
    mean_abs_diff = float(np.mean(np.abs(torch_out - keras_out)))

    float_converter = tf.lite.TFLiteConverter.from_keras_model(keras_model)
    float_tflite = float_converter.convert()
    (args.out_dir / "squeezenet1_1_imagenet_float32.tflite").write_bytes(float_tflite)

    converter = tf.lite.TFLiteConverter.from_keras_model(keras_model)
    converter.optimizations = [tf.lite.Optimize.DEFAULT]
    converter.representative_dataset = lambda: representative_dataset(args.input_size, args.representative_count)
    converter.target_spec.supported_ops = [tf.lite.OpsSet.TFLITE_BUILTINS_INT8]
    converter.inference_input_type = tf.int8
    converter.inference_output_type = tf.int8
    if args.keep_per_tensor_weights:
        converter._experimental_disable_per_channel = True
    int8_tflite = converter.convert()
    model_path = args.out_dir / "model.tflite"
    model_path.write_bytes(int8_tflite)

    interpreter = tf.lite.Interpreter(model_content=int8_tflite)
    input_detail = interpreter.get_input_details()[0]
    output_detail = interpreter.get_output_details()[0]
    in_q = input_detail["quantization_parameters"]
    out_q = output_detail["quantization_parameters"]
    input_scale = float(in_q["scales"][0])
    input_zero_point = int(in_q["zero_points"][0])
    output_scale = float(out_q["scales"][0])
    output_zero_point = int(out_q["zero_points"][0])
    shift, mult, offset = choose_fixed_input_params(input_scale, input_zero_point)

    weights_enum = SqueezeNet1_1_Weights.IMAGENET1K_V1
    categories = [str(item) for item in weights_enum.meta["categories"]]
    write_text_lines(args.out_dir / "labels.txt", categories)
    (args.out_dir / "labels.json").write_text(
        json.dumps({"categories": categories}, indent=2) + "\n",
        encoding="utf-8",
    )

    fixed_params = {
        "model_path": "model.tflite",
        "source": {
            "family": "torchvision.models.squeezenet1_1",
            "weights": "SqueezeNet1_1_Weights.IMAGENET1K_V1",
            "checkpoint": str(args.weights),
        },
        "format": {
            "input_formula": "q_in = clamp_int8(round((pixel * mult[channel] + offset[channel]) / 2^shift))",
            "pixel_range": "raw RGB uint8 pixels, 0..255",
        },
        "input": {
            "tensor": {
                "index": int(input_detail["index"]),
                "name": str(input_detail["name"]),
                "shape": [int(v) for v in input_detail["shape"]],
                "dtype": "int8",
                "scale": [input_scale],
                "zero_point": [input_zero_point],
                "quantized_dimension": int(in_q["quantized_dimension"]),
            },
            "model_color_order": "RGB",
            "pixel_denominator": int(PIXEL_DENOMINATOR),
            "mean": [float(v) for v in IMAGENET_MEAN],
            "std": [float(v) for v in IMAGENET_STD],
            "fixed": {
                "shift": int(shift),
                "mult": mult,
                "offset": offset,
            },
            "resize": {
                "recommended": "resize/crop or letterbox to 224x224 before quantizing",
                "torchvision_default": "resize 256, center crop 224",
            },
        },
        "output": {
            "tensor": {
                "index": int(output_detail["index"]),
                "name": str(output_detail["name"]),
                "shape": [int(v) for v in output_detail["shape"]],
                "dtype": "int8",
                "scale": [output_scale],
                "zero_point": [output_zero_point],
                "quantized_dimension": int(out_q["quantized_dimension"]),
            },
            "labels": "labels.txt",
        },
    }
    (args.out_dir / "fixed_params.json").write_text(json.dumps(fixed_params, indent=2) + "\n", encoding="utf-8")

    ops = [detail["op_name"] for detail in interpreter._get_ops_details()]
    manifest = {
        "out_dir": str(args.out_dir),
        "input_size": args.input_size,
        "representative_count": args.representative_count,
        "torch_to_keras_max_abs_diff": max_abs_diff,
        "torch_to_keras_mean_abs_diff": mean_abs_diff,
        "int8_input_scale": input_scale,
        "int8_input_zero_point": input_zero_point,
        "int8_output_scale": output_scale,
        "int8_output_zero_point": output_zero_point,
        "tflite_ops": ops,
        "notes": [
            "model.tflite is full-int8, NHWC input, logits output",
            "weights are quantized per tensor for accelerator per-layer metadata compatibility",
            "SqueezeNet has MAX_POOL_2D and CONCATENATION ops; the generic conv-only accelerator generator cannot execute the full graph without extra scheduling support",
        ],
    }
    (args.out_dir / "export_manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")

    print(f"Wrote {model_path}")
    print(f"Wrote {args.out_dir / 'fixed_params.json'}")
    print(f"Torch/Keras max abs diff: {max_abs_diff:.6g}")
    print(f"Input quantization: scale={input_scale:.9g}, zero_point={input_zero_point}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
