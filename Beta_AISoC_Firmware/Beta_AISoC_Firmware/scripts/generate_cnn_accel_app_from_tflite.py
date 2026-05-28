#!/usr/bin/env python3
"""Generate CNN accelerator firmware files from an int8 TFLite model.

The generator is intentionally dependency-free: it parses the small subset of
the TFLite FlatBuffer schema needed by the accelerator flow in this firmware.
It extracts CONV_2D layers, folds simple NHWC PAD ops into the accelerator
padding register, chooses IFPARR/OFTILE/OFPARR with the same search model used
by cycle_calculatev6_fixed_caps.cpp, packs filter/bias bytes for HyperRAM0, and
emits App/Src + App/Inc C code that submits each layer to CNN_Accel_Driver.
"""

from __future__ import annotations

import argparse
import json
import math
import re
import struct
import zlib
from dataclasses import dataclass, field
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Sequence, Tuple


FLASH_SIZE = 16 * 1024 * 1024
BOOT_META_OFFSET = 0x00000000
BOOT_IMAGE_OFFSET = 0x00001000
BOOT_VALID_MAGIC = 0xA5A55A5A
APP_MAX_SIZE = 64 * 1024
DEFAULT_FLASH_WEIGHT_METADATA_OFFSET = 0x001FF000
DEFAULT_FLASH_WEIGHT_OFFSET = 0x00200000
DEFAULT_FLASH_STATIC_INPUT_OFFSET = 0x00340000
WEIGHT_METADATA_MAGIC = 0x53544757  # "WGTS"
WEIGHT_METADATA_VERSION = 1

ACCEL_M = 2
MAX_NFP = 24
FIXED_MAX_POSSIBLE_K = 4
FIXED_PARTIAL_SRAM = 43008
FIXED_OFMAP_SRAM = 1792
FIXED_IFMAP_SRAM = 1792
FIXED_WEIGHT_SRAM = 37600

BUILTIN_OPERATOR = {
    0: "ADD",
    1: "AVERAGE_POOL_2D",
    2: "CONCATENATION",
    3: "CONV_2D",
    4: "DEPTHWISE_CONV_2D",
    9: "FULLY_CONNECTED",
    14: "LOGISTIC",
    17: "MAX_POOL_2D",
    18: "MUL",
    22: "RESHAPE",
    25: "SOFTMAX",
    32: "CUSTOM",
    34: "PAD",
    40: "MEAN",
    41: "SUB",
    45: "PADV2",
    56: "LEAKY_RELU",
}

TENSOR_TYPE = {
    0: "FLOAT32",
    1: "FLOAT16",
    2: "INT32",
    3: "UINT8",
    4: "INT64",
    6: "BOOL",
    7: "INT16",
    9: "INT8",
    15: "UINT32",
    16: "UINT16",
    17: "INT4",
}


class FlatBuffer:
    def __init__(self, data: bytes):
        self.data = data

    def u8(self, off: int) -> int:
        return self.data[off]

    def i8(self, off: int) -> int:
        value = self.data[off]
        return value - 256 if value >= 128 else value

    def u16(self, off: int) -> int:
        return int.from_bytes(self.data[off : off + 2], "little")

    def u32(self, off: int) -> int:
        return int.from_bytes(self.data[off : off + 4], "little")

    def i32(self, off: int) -> int:
        return int.from_bytes(self.data[off : off + 4], "little", signed=True)

    def u64(self, off: int) -> int:
        return int.from_bytes(self.data[off : off + 8], "little")

    def i64(self, off: int) -> int:
        return int.from_bytes(self.data[off : off + 8], "little", signed=True)

    def f32(self, off: int) -> float:
        return struct.unpack_from("<f", self.data, off)[0]

    def root_table(self) -> int:
        return self.u32(0)

    def table_field(self, table: int, field: int) -> int:
        vtable = table - self.i32(table)
        vlen = self.u16(vtable)
        slot = 4 + field * 2
        if slot >= vlen:
            return 0
        rel = self.u16(vtable + slot)
        return table + rel if rel else 0

    def indirect(self, field_addr: int) -> int:
        return field_addr + self.u32(field_addr)

    def vector_start(self, vec_field: int) -> int:
        return vec_field + self.u32(vec_field)

    def vector_len(self, vec_field: int) -> int:
        return self.u32(self.vector_start(vec_field))

    def vector_elem_table(self, vec_field: int, idx: int) -> int:
        vec = self.vector_start(vec_field)
        elem = vec + 4 + idx * 4
        return elem + self.u32(elem)

    def vector_i32(self, vec_field: int) -> List[int]:
        vec = self.vector_start(vec_field)
        count = self.u32(vec)
        return [self.i32(vec + 4 + i * 4) for i in range(count)]

    def vector_i64(self, vec_field: int) -> List[int]:
        vec = self.vector_start(vec_field)
        count = self.u32(vec)
        return [self.i64(vec + 4 + i * 8) for i in range(count)]

    def vector_f32(self, vec_field: int) -> List[float]:
        vec = self.vector_start(vec_field)
        count = self.u32(vec)
        return [self.f32(vec + 4 + i * 4) for i in range(count)]

    def vector_bytes(self, vec_field: int) -> bytes:
        vec = self.vector_start(vec_field)
        count = self.u32(vec)
        return self.data[vec + 4 : vec + 4 + count]

    def string(self, str_field: int) -> str:
        vec = self.vector_start(str_field)
        count = self.u32(vec)
        return self.data[vec + 4 : vec + 4 + count].decode("utf-8", errors="replace")


@dataclass
class Quantization:
    scale: List[float] = field(default_factory=list)
    zero_point: List[int] = field(default_factory=list)
    quantized_dimension: int = 0


@dataclass
class Tensor:
    index: int
    name: str
    shape: List[int]
    dtype: str
    buffer: int
    quant: Quantization

    @property
    def element_size(self) -> int:
        if self.dtype in ("INT8", "UINT8", "INT4"):
            return 1
        if self.dtype in ("INT16", "UINT16", "FLOAT16"):
            return 2
        if self.dtype in ("INT32", "UINT32", "FLOAT32"):
            return 4
        if self.dtype == "INT64":
            return 8
        return 1

    def hwc_shape(self) -> Tuple[int, int, int]:
        if len(self.shape) == 4:
            return self.shape[1], self.shape[2], self.shape[3]
        if len(self.shape) == 3:
            return self.shape[0], self.shape[1], self.shape[2]
        raise ValueError(f"Tensor {self.index} shape is not NHWC-like: {self.shape}")

    def activation_bytes(self) -> int:
        if len(self.shape) == 4:
            return self.shape[1] * self.shape[2] * self.shape[3] * self.element_size
        total = 1
        for dim in self.shape:
            total *= dim
        return total * self.element_size

    def activation_row_stride_bytes(self, row_alignment: int) -> int:
        if len(self.shape) == 4:
            row_bytes = self.shape[2] * self.element_size
            return align_up(row_bytes, row_alignment)
        if len(self.shape) == 3:
            row_bytes = self.shape[1] * self.element_size
            return align_up(row_bytes, row_alignment)
        return align_up(self.activation_bytes(), row_alignment)

    def activation_storage_bytes(self, row_alignment: int) -> int:
        if len(self.shape) == 4:
            return self.shape[3] * self.shape[1] * self.activation_row_stride_bytes(row_alignment)
        if len(self.shape) == 3:
            return self.shape[2] * self.shape[0] * self.activation_row_stride_bytes(row_alignment)
        return self.activation_row_stride_bytes(row_alignment)


@dataclass
class Operator:
    index: int
    opcode_index: int
    op_name: str
    inputs: List[int]
    outputs: List[int]
    options: int


@dataclass
class TFLiteModel:
    tensors: List[Tensor]
    buffers: List[bytes]
    operators: List[Operator]
    inputs: List[int]
    outputs: List[int]


@dataclass
class ConvOptions:
    padding: int = 0
    stride_w: int = 1
    stride_h: int = 1
    fused_activation: int = 0
    dilation_w: int = 1
    dilation_h: int = 1


@dataclass
class Pool2DOptions:
    padding: int = 0
    stride_w: int = 1
    stride_h: int = 1
    filter_w: int = 1
    filter_h: int = 1
    fused_activation: int = 0


@dataclass
class ConcatOptions:
    axis: int = 3
    fused_activation: int = 0


@dataclass
class MemoryFootprint:
    partial: int
    ofmap: int
    ifmap: int
    weight: int

    @property
    def total(self) -> int:
        return self.partial + self.ofmap + self.ifmap + self.weight


@dataclass
class LayerConfig:
    nip: int
    npass: int
    nfp: int
    cycles: int
    mem: MemoryFootprint


@dataclass
class ConvLayer:
    name: str
    op_index: int
    input_tensor: int
    weight_tensor: int
    bias_tensor: Optional[int]
    output_tensor: int
    ifheight: int
    ifwidth: int
    ifchannel: int
    ofheight: int
    ofwidth: int
    ofchannel: int
    hf: int
    wf: int
    stride: int
    padding: int
    ifparr: int = 1
    oftile: int = 1
    ofparr: int = 1
    ifbaddr: int = 0
    fltbaddr: int = 0
    bias_baddr: int = 0
    ofbaddr: int = 0
    ifc_zp: int = 0
    fltc_zp: int = 0
    mult: int = 0
    mult_shift: int = 0
    zpy: int = 0
    qmin: int = -128
    qmax: int = 127
    is_leaky_relu: bool = False
    packed_weight_size: int = 0
    packed_bias_size: int = 0
    cycles: int = 0
    input_from_tensor: Optional[int] = None
    ifrow_stride: int = 0
    ofrow_stride: int = 0
    ifmap_raw_bytes: int = 0
    ifmap_storage_bytes: int = 0
    ofmap_raw_bytes: int = 0
    ofmap_storage_bytes: int = 0


@dataclass
class TensorView:
    tensor_index: int
    addr: int = 0
    height: int = 0
    width: int = 0
    channels: int = 0
    row_stride: int = 0


@dataclass
class CpuOp:
    name: str
    op_index: int
    kind: str
    inputs: List[int]
    output: int
    input_views: List[TensorView] = field(default_factory=list)
    output_view: TensorView = field(default_factory=lambda: TensorView(-1))
    filter_h: int = 1
    filter_w: int = 1
    stride_h: int = 1
    stride_w: int = 1
    pad_top: int = 0
    pad_left: int = 0
    concat_axis: int = 3
    qmin: int = -128
    qmax: int = 127


@dataclass
class ExecutionStep:
    kind: str
    index: int


@dataclass
class ZeroCopyConcatAlias:
    name: str
    op_index: int
    input_tensor: int
    output_tensor: int
    producer_op_index: int
    channel_offset: int


@dataclass
class CameraConfig:
    input_tensor: int
    out_size: int
    out_pixels: int
    scaled_h: int
    pad_top: int
    x_step: int
    y_step: int
    output_bgr: bool
    shift: int
    mult_r: int
    mult_g: int
    mult_b: int
    offset_r: int
    offset_g: int
    offset_b: int


@dataclass
class StaticInputConfig:
    name: str
    flash_offset: int
    size: int
    crc32: int
    expected_top1: int = -1
    expected_value: int = 0
    tensor_refs: List["StaticTensorReference"] = field(default_factory=list)


@dataclass
class StaticTensorReference:
    name: str
    tensor: int
    addr: int
    height: int
    width: int
    channels: int
    row_stride: int
    logical_bytes: int
    crc32: int


def ceil_div(a: int, b: int) -> int:
    return (a + b - 1) // b


def align_up(value: int, alignment: int) -> int:
    if alignment <= 1:
        return value
    return (value + alignment - 1) // alignment * alignment


def product(values: Sequence[int]) -> int:
    result = 1
    for value in values:
        result *= value
    return result


def sanitize_identifier(text: str, fallback: str = "generated_model") -> str:
    text = re.sub(r"[^0-9A-Za-z_]+", "_", text.strip())
    text = re.sub(r"_+", "_", text).strip("_")
    if not text:
        text = fallback
    if text[0].isdigit():
        text = f"model_{text}"
    return text


def snake_to_pascal(text: str) -> str:
    parts = [part for part in re.split(r"[_\W]+", text) if part]
    return "".join(part[:1].upper() + part[1:] for part in parts) or "GeneratedModel"


def parse_tflite(path: Path) -> TFLiteModel:
    fb = FlatBuffer(path.read_bytes())
    root = fb.root_table()

    opcodes_field = fb.table_field(root, 1)
    subgraphs_field = fb.table_field(root, 2)
    buffers_field = fb.table_field(root, 4)
    if not subgraphs_field or not buffers_field:
        raise ValueError("TFLite model is missing subgraphs or buffers")

    opcodes: List[str] = []
    if opcodes_field:
        for i in range(fb.vector_len(opcodes_field)):
            opcode = fb.vector_elem_table(opcodes_field, i)
            builtin_field = fb.table_field(opcode, 3)
            deprecated_field = fb.table_field(opcode, 0)
            if builtin_field:
                code = fb.i8(builtin_field)
            elif deprecated_field:
                code = fb.i8(deprecated_field)
            else:
                code = 0
            opcodes.append(BUILTIN_OPERATOR.get(code, f"BUILTIN_{code}"))

    subgraph = fb.vector_elem_table(subgraphs_field, 0)
    tensors_field = fb.table_field(subgraph, 0)
    inputs_field = fb.table_field(subgraph, 1)
    outputs_field = fb.table_field(subgraph, 2)
    operators_field = fb.table_field(subgraph, 3)

    tensors: List[Tensor] = []
    for i in range(fb.vector_len(tensors_field)):
        tensor = fb.vector_elem_table(tensors_field, i)
        shape_field = fb.table_field(tensor, 0)
        type_field = fb.table_field(tensor, 1)
        buffer_field = fb.table_field(tensor, 2)
        name_field = fb.table_field(tensor, 3)
        quant_field = fb.table_field(tensor, 4)

        shape = fb.vector_i32(shape_field) if shape_field else []
        dtype_code = fb.i8(type_field) if type_field else 0
        buffer_index = fb.u32(buffer_field) if buffer_field else 0
        name = fb.string(name_field) if name_field else f"tensor_{i}"
        quant = Quantization()
        if quant_field:
            quant_table = fb.indirect(quant_field)
            scale_field = fb.table_field(quant_table, 2)
            zp_field = fb.table_field(quant_table, 3)
            qdim_field = fb.table_field(quant_table, 5)
            quant.scale = fb.vector_f32(scale_field) if scale_field else []
            quant.zero_point = fb.vector_i64(zp_field) if zp_field else []
            quant.quantized_dimension = fb.i32(qdim_field) if qdim_field else 0

        tensors.append(
            Tensor(
                index=i,
                name=name,
                shape=shape,
                dtype=TENSOR_TYPE.get(dtype_code, f"TYPE_{dtype_code}"),
                buffer=buffer_index,
                quant=quant,
            )
        )

    buffers: List[bytes] = []
    for i in range(fb.vector_len(buffers_field)):
        buffer = fb.vector_elem_table(buffers_field, i)
        data_field = fb.table_field(buffer, 0)
        buffers.append(fb.vector_bytes(data_field) if data_field else b"")

    operators: List[Operator] = []
    if operators_field:
        for i in range(fb.vector_len(operators_field)):
            op = fb.vector_elem_table(operators_field, i)
            opcode_field = fb.table_field(op, 0)
            inputs_vec = fb.table_field(op, 1)
            outputs_vec = fb.table_field(op, 2)
            options_field = fb.table_field(op, 4)
            opcode_index = fb.u32(opcode_field) if opcode_field else 0
            op_name = opcodes[opcode_index] if opcode_index < len(opcodes) else f"OP_{opcode_index}"
            operators.append(
                Operator(
                    index=i,
                    opcode_index=opcode_index,
                    op_name=op_name,
                    inputs=fb.vector_i32(inputs_vec) if inputs_vec else [],
                    outputs=fb.vector_i32(outputs_vec) if outputs_vec else [],
                    options=fb.indirect(options_field) if options_field else 0,
                )
            )

    return TFLiteModel(
        tensors=tensors,
        buffers=buffers,
        operators=operators,
        inputs=fb.vector_i32(inputs_field) if inputs_field else [],
        outputs=fb.vector_i32(outputs_field) if outputs_field else [],
    )


def read_conv_options(fb_data: bytes, options_table: int) -> ConvOptions:
    if not options_table:
        return ConvOptions()
    fb = FlatBuffer(fb_data)
    padding_field = fb.table_field(options_table, 0)
    stride_w_field = fb.table_field(options_table, 1)
    stride_h_field = fb.table_field(options_table, 2)
    fused_field = fb.table_field(options_table, 3)
    dilation_w_field = fb.table_field(options_table, 4)
    dilation_h_field = fb.table_field(options_table, 5)
    return ConvOptions(
        padding=fb.i8(padding_field) if padding_field else 0,
        stride_w=fb.i32(stride_w_field) if stride_w_field else 1,
        stride_h=fb.i32(stride_h_field) if stride_h_field else 1,
        fused_activation=fb.i8(fused_field) if fused_field else 0,
        dilation_w=fb.i32(dilation_w_field) if dilation_w_field else 1,
        dilation_h=fb.i32(dilation_h_field) if dilation_h_field else 1,
    )


def read_pool2d_options(fb_data: bytes, options_table: int) -> Pool2DOptions:
    if not options_table:
        return Pool2DOptions()
    fb = FlatBuffer(fb_data)
    padding_field = fb.table_field(options_table, 0)
    stride_w_field = fb.table_field(options_table, 1)
    stride_h_field = fb.table_field(options_table, 2)
    filter_w_field = fb.table_field(options_table, 3)
    filter_h_field = fb.table_field(options_table, 4)
    fused_field = fb.table_field(options_table, 5)
    return Pool2DOptions(
        padding=fb.i8(padding_field) if padding_field else 0,
        stride_w=fb.i32(stride_w_field) if stride_w_field else 1,
        stride_h=fb.i32(stride_h_field) if stride_h_field else 1,
        filter_w=fb.i32(filter_w_field) if filter_w_field else 1,
        filter_h=fb.i32(filter_h_field) if filter_h_field else 1,
        fused_activation=fb.i8(fused_field) if fused_field else 0,
    )


def read_concat_options(fb_data: bytes, options_table: int) -> ConcatOptions:
    if not options_table:
        return ConcatOptions()
    fb = FlatBuffer(fb_data)
    axis_field = fb.table_field(options_table, 0)
    fused_field = fb.table_field(options_table, 1)
    return ConcatOptions(
        axis=fb.i32(axis_field) if axis_field else 3,
        fused_activation=fb.i8(fused_field) if fused_field else 0,
    )


def tensor_buffer(model: TFLiteModel, tensor_index: int) -> bytes:
    tensor = model.tensors[tensor_index]
    if tensor.buffer >= len(model.buffers):
        return b""
    return model.buffers[tensor.buffer]


def scalar_zero_point(tensor: Tensor, default: int = 0) -> int:
    return int(tensor.quant.zero_point[0]) if tensor.quant.zero_point else default


def scalar_scale(tensor: Tensor, default: float = 1.0) -> float:
    return float(tensor.quant.scale[0]) if tensor.quant.scale else default


def choose_single_weight_zero_point(tensor: Tensor, warnings: List[str]) -> int:
    if not tensor.quant.zero_point:
        return 0
    unique = sorted(set(int(v) for v in tensor.quant.zero_point))
    if len(unique) > 1:
        warnings.append(
            f"Tensor {tensor.index} has per-channel weight zero-points; using {unique[0]} for FLTC_ZP"
        )
    return unique[0]


def fixed_multiplier(real_scale: float) -> Tuple[int, int]:
    if real_scale == 0.0:
        return 0, 0
    sign = -1 if real_scale < 0 else 1
    value = abs(real_scale)
    shift = 31
    mult = int(round(value * (1 << shift)))
    while mult > 0x7FFFFFFF and shift > 0:
        shift -= 1
        mult = int(round(value * (1 << shift)))
    while mult == 0 and shift < 63:
        shift += 1
        mult = int(round(value * (1 << shift)))
    if mult > 0x7FFFFFFF:
        raise ValueError(f"Cannot fit requant scale {real_scale} into int32 multiplier")
    return sign * mult, shift


def activation_clamp(dtype: str, output_zp: int, output_scale: float, fused_activation: int) -> Tuple[int, int]:
    if dtype == "UINT8":
        qmin, qmax = 0, 255
    else:
        qmin, qmax = -128, 127

    if fused_activation == 1:
        qmin = max(qmin, output_zp)
    elif fused_activation == 3 and output_scale > 0:
        qmin = max(qmin, output_zp)
        qmax = min(qmax, int(round(6.0 / output_scale)) + output_zp)

    qmin = max(-128, min(127, qmin))
    qmax = max(-128, min(127, qmax))
    return qmin, qmax


def parse_sidecar(path: Optional[Path]) -> Dict:
    if path is None:
        return {}
    return json.loads(path.read_text())


def sidecar_conv_lookup(sidecar: Dict) -> Dict[int, Dict]:
    result: Dict[int, Dict] = {}
    for idx, layer in enumerate(sidecar.get("conv_layers", [])):
        if "op_index" in layer:
            result[int(layer["op_index"])] = layer
        result.setdefault(idx, layer)
    return result


def sidecar_input_tensor_index(sidecar: Dict, model: TFLiteModel) -> Optional[int]:
    input_info = sidecar.get("input", {})
    if "tensor_index" in input_info:
        return int(input_info["tensor_index"])
    tensor_info = input_info.get("tensor", {})
    if isinstance(tensor_info, dict) and "index" in tensor_info:
        return int(tensor_info["index"])
    return int(model.inputs[0]) if model.inputs else None


def list_of_ints(value: object, count: int, label: str) -> Optional[List[int]]:
    if not isinstance(value, list) or len(value) < count:
        return None
    try:
        return [int(value[i]) for i in range(count)]
    except (TypeError, ValueError) as exc:
        raise ValueError(f"{label} must contain integer values") from exc


def list_of_floats(value: object, count: int, label: str) -> Optional[List[float]]:
    if isinstance(value, (int, float)):
        return [float(value)] * count
    if not isinstance(value, list) or not value:
        return None
    if len(value) == 1:
        return [float(value[0])] * count
    if len(value) < count:
        return None
    try:
        return [float(value[i]) for i in range(count)]
    except (TypeError, ValueError) as exc:
        raise ValueError(f"{label} must contain numeric values") from exc


def first_numeric(value: object) -> Optional[float]:
    if isinstance(value, (int, float)):
        return float(value)
    if isinstance(value, list) and value:
        return first_numeric(value[0])
    return None


def derive_input_fixed_from_normalization(
    input_info: Dict,
    input_tensor: Tensor,
) -> Optional[Tuple[int, List[int], List[int]]]:
    tensor_info = input_info.get("tensor", {})
    if not isinstance(tensor_info, dict):
        tensor_info = {}

    mean = list_of_floats(input_info.get("mean"), 3, "input.mean")
    std = list_of_floats(input_info.get("std"), 3, "input.std")
    if mean is None or std is None:
        return None

    scale_value = (
        first_numeric(input_info.get("scale"))
        or first_numeric(tensor_info.get("scale"))
        or first_numeric(input_tensor.quant.scale)
    )
    zero_point_value = (
        first_numeric(input_info.get("zero_point"))
        or first_numeric(tensor_info.get("zero_point"))
        or first_numeric(input_tensor.quant.zero_point)
    )
    if scale_value is None:
        return None
    if zero_point_value is None:
        zero_point_value = 0.0

    pixel_denominator = float(input_info.get("pixel_denominator", 255))
    if pixel_denominator <= 0 or scale_value <= 0:
        raise ValueError("input pixel_denominator and input scale must be positive")
    if any(value <= 0 for value in std):
        raise ValueError("input.std values must be positive")

    real_mult = [1.0 / (pixel_denominator * std[ch] * scale_value) for ch in range(3)]
    real_offset = [
        zero_point_value - (mean[ch] / (std[ch] * scale_value))
        for ch in range(3)
    ]

    shift = 0
    for candidate in range(31, -1, -1):
        scale = 1 << candidate
        mult_ok = all(abs(int(round(value * scale))) <= 0x7FFFFFFF for value in real_mult)
        offset_ok = all(abs(int(round(value * scale))) <= 0x7FFFFFFF for value in real_offset)
        if mult_ok and offset_ok:
            shift = candidate
            break

    scale = 1 << shift
    mult = [int(round(value * scale)) for value in real_mult]
    offset = [int(round(value * scale)) for value in real_offset]
    return shift, mult, offset


def build_camera_config(
    model: TFLiteModel,
    layers: List[ConvLayer],
    sidecar: Dict,
    mode: str,
    camera_width: int,
    camera_height: int,
    force_output_bgr: bool,
    warnings: List[str],
) -> Optional[CameraConfig]:
    def reject(reason: str) -> Optional[CameraConfig]:
        if mode == "on":
            raise ValueError(f"Camera IFMAP requested but cannot be generated: {reason}")
        return None

    if mode == "off":
        return None
    if not layers:
        return reject("model has no convolution layers")
    if camera_width <= 0 or camera_height <= 0:
        return reject("camera input width/height must be positive")

    input_tensor_index = sidecar_input_tensor_index(sidecar, model)
    if input_tensor_index is None or input_tensor_index >= len(model.tensors):
        return reject("could not resolve model input tensor")

    input_tensor = model.tensors[input_tensor_index]
    try:
        input_h, input_w, input_c = input_tensor.hwc_shape()
    except ValueError as exc:
        return reject(str(exc))

    if input_h != input_w:
        return reject(f"model input is not square H/W={input_h}/{input_w}")
    if input_c != 3:
        return reject(f"model input channel count is {input_c}, expected RGB/BGR camera input with 3 channels")
    if input_h > 255:
        return reject(f"model input size {input_h} exceeds 8-bit video out_size register")
    if layers[0].input_tensor != input_tensor_index:
        return reject(
            "first accelerator layer does not read the model input tensor directly; "
            "fold or remove unsupported input ops before using camera IFMAP"
        )
    if layers[0].ifheight != input_h or layers[0].ifwidth != input_w:
        return reject(
            f"first layer IFMAP {layers[0].ifheight}x{layers[0].ifwidth} "
            f"does not match model input {input_h}x{input_w}"
        )

    input_info = sidecar.get("input", {})
    if not isinstance(input_info, dict):
        input_info = {}
    fixed = input_info.get("fixed", {})
    if not isinstance(fixed, dict):
        fixed = {}

    mult = list_of_ints(fixed.get("mult"), 3, "input.fixed.mult")
    offset = list_of_ints(fixed.get("offset"), 3, "input.fixed.offset")
    if mult is None or offset is None or "shift" not in fixed:
        derived = derive_input_fixed_from_normalization(input_info, input_tensor)
        if derived is None:
            return reject(
                "provide input.fixed shift/mult/offset, or input.mean/input.std plus input tensor scale/zero_point"
            )
        shift, mult, offset = derived
        warnings.append(
            "Camera IFMAP preprocessing fixed constants were derived from input.mean/std and input quantization"
        )
    else:
        shift = int(fixed["shift"])
    if shift < 0 or shift > 63:
        return reject(f"input.fixed.shift={shift} is outside supported 0..63 range")

    scaled_h = (camera_height * input_h) // camera_width
    if scaled_h <= 0:
        return reject("computed scaled_h is zero")
    if scaled_h > input_h:
        return reject(
            f"camera aspect ratio would scale height to {scaled_h}, larger than output size {input_h}"
        )
    vertical_pad = input_h - scaled_h
    if (vertical_pad & 1) != 0:
        warnings.append(
            f"Camera IFMAP vertical pad is odd ({vertical_pad}); using pad_top={vertical_pad // 2}"
        )
    x_step = (camera_width << 16) // input_w
    y_step = (camera_height << 16) // scaled_h
    color_order = str(input_info.get("model_color_order", "RGB")).upper()
    if color_order not in ("RGB", "BGR"):
        warnings.append(f"Unknown input.model_color_order={color_order!r}; assuming RGB")
        color_order = "RGB"

    return CameraConfig(
        input_tensor=input_tensor_index,
        out_size=input_h,
        out_pixels=input_h * input_w,
        scaled_h=scaled_h,
        pad_top=vertical_pad // 2,
        x_step=x_step,
        y_step=y_step,
        output_bgr=force_output_bgr or color_order == "BGR",
        shift=shift,
        mult_r=mult[0],
        mult_g=mult[1],
        mult_b=mult[2],
        offset_r=offset[0],
        offset_g=offset[1],
        offset_b=offset[2],
    )


def read_padding_values(model: TFLiteModel, tensor_index: int) -> Optional[List[List[int]]]:
    tensor = model.tensors[tensor_index]
    raw = tensor_buffer(model, tensor_index)
    if not raw or tensor.dtype not in ("INT32", "INT64"):
        return None
    element_size = 8 if tensor.dtype == "INT64" else 4
    signed = True
    values = [
        int.from_bytes(raw[i : i + element_size], "little", signed=signed)
        for i in range(0, min(len(raw), product(tensor.shape) * element_size), element_size)
    ]
    if len(tensor.shape) != 2 or tensor.shape[1] != 2 or len(values) != tensor.shape[0] * 2:
        return None
    return [[values[i * 2], values[i * 2 + 1]] for i in range(tensor.shape[0])]


def find_pad_source(
    model: TFLiteModel,
    producer_by_tensor: Dict[int, Operator],
    tensor_index: int,
) -> Optional[Tuple[int, List[List[int]]]]:
    producer = producer_by_tensor.get(tensor_index)
    if producer is None or producer.op_name not in ("PAD", "PADV2") or len(producer.inputs) < 2:
        return None
    pads = read_padding_values(model, producer.inputs[1])
    if not pads or len(pads) != 4:
        return None
    return producer.inputs[0], pads


def find_simple_pad_source(
    model: TFLiteModel,
    producer_by_tensor: Dict[int, Operator],
    tensor_index: int,
) -> Optional[Tuple[int, int]]:
    pad_source = find_pad_source(model, producer_by_tensor, tensor_index)
    if pad_source is None:
        return None
    source_tensor, pads = pad_source
    if pads[0] != [0, 0] or pads[3] != [0, 0]:
        return None
    if pads[1][0] != pads[1][1] or pads[2][0] != pads[2][1] or pads[1][0] != pads[2][0]:
        return None
    return source_tensor, int(pads[1][0])


def same_padding_pair(input_size: int, output_size: int, kernel: int, stride: int, dilation: int) -> Tuple[int, int]:
    effective_kernel = (kernel - 1) * dilation + 1
    total = max((output_size - 1) * stride + effective_kernel - input_size, 0)
    before = total // 2
    after = total - before
    return before, after


def warn_non_per_layer_scale(warnings: List[str], layer_name: str, tensor_role: str, tensor: Tensor) -> None:
    if len(tensor.quant.scale) > 1:
        warnings.append(
            f"{layer_name}: {tensor_role} tensor {tensor.index} scale is not per-layer "
            f"({len(tensor.quant.scale)} values, quantized_dimension={tensor.quant.quantized_dimension})"
        )


def warn_row_padding_once(
    warnings: List[str],
    warned_tensors: set,
    tensor: Tensor,
    row_alignment: int,
) -> None:
    if tensor.index in warned_tensors or len(tensor.shape) not in (3, 4):
        return
    row_bytes = (tensor.shape[2] if len(tensor.shape) == 4 else tensor.shape[1]) * tensor.element_size
    row_stride = tensor.activation_row_stride_bytes(row_alignment)
    if row_stride != row_bytes:
        warnings.append(
            f"Tensor {tensor.index} row_bytes={row_bytes} is not aligned to {row_alignment}; "
            f"activation allocation uses row_stride={row_stride} with dummy byte(s) per row"
        )
    warned_tensors.add(tensor.index)


def extract_conv_layers(
    tflite_path: Path,
    model: TFLiteModel,
    sidecar: Dict,
    fold_pad: bool,
    warnings: List[str],
) -> List[ConvLayer]:
    raw_data = tflite_path.read_bytes()
    producer_by_tensor: Dict[int, Operator] = {}
    for op in model.operators:
        for out in op.outputs:
            producer_by_tensor[out] = op

    conv_lookup = sidecar_conv_lookup(sidecar)
    conv_layers: List[ConvLayer] = []
    conv_order = 0

    for op in model.operators:
        if op.op_name != "CONV_2D":
            continue
        if len(op.inputs) < 2 or not op.outputs:
            warnings.append(f"Skipping malformed CONV_2D op {op.index}")
            continue

        opts = read_conv_options(raw_data, op.options)
        if opts.stride_h != opts.stride_w:
            warnings.append(
                f"CONV_2D op {op.index}: asymmetric stride H/W={opts.stride_h}/{opts.stride_w}; "
                f"generated config uses stride_h={opts.stride_h}"
            )
        if opts.dilation_h != 1 or opts.dilation_w != 1:
            raise ValueError(f"CONV_2D op {op.index}: dilation is not supported by this generator")

        raw_input_tensor = op.inputs[0]
        input_tensor = raw_input_tensor
        folded_pad = 0
        if fold_pad:
            pad_source = find_pad_source(model, producer_by_tensor, raw_input_tensor)
            if pad_source is not None:
                pad_input_tensor, pads = pad_source
                if pads[0] != [0, 0] or pads[3] != [0, 0]:
                    warnings.append(
                        f"CONV_2D op {op.index}: preceding PAD also pads batch/channel {pads}; "
                        "cannot fold it into the accelerator padding register"
                    )
                elif pads[1][0] != pads[1][1] or pads[2][0] != pads[2][1] or pads[1][0] != pads[2][0]:
                    warnings.append(
                        f"CONV_2D op {op.index}: asymmetric explicit PAD "
                        f"top/bottom/left/right={pads[1][0]}/{pads[1][1]}/{pads[2][0]}/{pads[2][1]}; "
                        "generated config keeps the padded tensor as IFMAP"
                    )
                else:
                    input_tensor, folded_pad = pad_input_tensor, int(pads[1][0])

        weight_tensor = op.inputs[1]
        bias_tensor = op.inputs[2] if len(op.inputs) > 2 and op.inputs[2] >= 0 else None
        output_tensor = op.outputs[0]

        if_tensor = model.tensors[input_tensor]
        weight = model.tensors[weight_tensor]
        of_tensor = model.tensors[output_tensor]
        ifh, ifw, ifc = if_tensor.hwc_shape()
        ofh, ofw, ofc = of_tensor.hwc_shape()
        if len(weight.shape) != 4:
            raise ValueError(f"CONV_2D op {op.index}: weight tensor must be OHWI, got {weight.shape}")
        ofc_w, hf, wf, ifc_w = weight.shape
        if hf != wf:
            warnings.append(
                f"CONV_2D op {op.index}: filter is not square H/W={hf}/{wf}; "
                f"HF register can hold one value, generated config uses hf={hf}"
            )
        if ifc_w != ifc or ofc_w != ofc:
            raise ValueError(
                f"CONV_2D op {op.index}: tensor channel mismatch input/weight/output "
                f"({ifc}, {weight.shape}, {ofc})"
            )
        if ifh != ifw:
            warnings.append(
                f"CONV_2D op {op.index}: IFMAP is not square H/W={ifh}/{ifw}; "
                f"IFHEIGHT register only stores {ifh}"
            )
        if ofh != ofw:
            warnings.append(
                f"CONV_2D op {op.index}: OFMAP is not square H/W={ofh}/{ofw}; "
                "generated code derives output width from IFHEIGHT/stride/padding"
            )

        side = conv_lookup.get(op.index, conv_lookup.get(conv_order, {}))
        name = side.get("name") or f"Conv{len(conv_layers) + 1}"
        if len(name) > 28:
            name = f"Conv{len(conv_layers) + 1}"

        warn_non_per_layer_scale(warnings, str(name), "input", if_tensor)
        warn_non_per_layer_scale(warnings, str(name), "weight", weight)
        warn_non_per_layer_scale(warnings, str(name), "output", of_tensor)
        if bias_tensor is not None:
            bias_obj = model.tensors[bias_tensor]
            warn_non_per_layer_scale(warnings, str(name), "bias", bias_obj)
            if product(bias_obj.shape) != ofc:
                warnings.append(
                    f"{name}: bias tensor {bias_tensor} shape {bias_obj.shape} is not per filter "
                    f"(expected {ofc} values)"
                )
        if "bias_values_int32" in side and len(side["bias_values_int32"]) != ofc:
            warnings.append(
                f"{name}: sidecar bias_values_int32 is not per filter "
                f"({len(side['bias_values_int32'])} values, expected {ofc})"
            )

        if folded_pad:
            padding = folded_pad
        elif opts.padding == 0:
            pad_top, pad_bottom = same_padding_pair(ifh, ofh, hf, opts.stride_h, opts.dilation_h)
            pad_left, pad_right = same_padding_pair(ifw, ofw, wf, opts.stride_w, opts.dilation_w)
            padding = max(pad_top, pad_bottom, pad_left, pad_right)
            if (pad_top != pad_bottom) or (pad_left != pad_right) or (pad_top != pad_left):
                warnings.append(
                    f"CONV_2D op {op.index}: asymmetric SAME padding "
                    f"top/bottom/left/right={pad_top}/{pad_bottom}/{pad_left}/{pad_right}; "
                    f"generated config uses padding={padding}"
                )
        else:
            padding = 0

        input_zp = int(side.get("input_zero_point", scalar_zero_point(if_tensor, 0)))
        weight_zp_values = side.get("weight_zero_point")
        if isinstance(weight_zp_values, list) and len(weight_zp_values) > 1:
            warnings.append(
                f"{name}: weight zero-point is not per-layer ({len(weight_zp_values)} values); "
                f"generated config uses {weight_zp_values[0]}"
            )
        fltc_zp = int(weight_zp_values[0]) if isinstance(weight_zp_values, list) else choose_single_weight_zero_point(weight, warnings)
        output_zp = int(side.get("output_zero_point", scalar_zero_point(of_tensor, 0)))
        output_scale = scalar_scale(of_tensor, 1.0)

        if "requant_mult_int32" in side and "requant_shift_uint6" in side:
            if len(side["requant_mult_int32"]) != 1 or len(side["requant_shift_uint6"]) != 1:
                warnings.append(
                    f"{name}: sidecar requant scale is not per-layer "
                    f"(mult={len(side['requant_mult_int32'])}, shift={len(side['requant_shift_uint6'])})"
                )
            mult = int(side["requant_mult_int32"][0])
            mult_shift = int(side["requant_shift_uint6"][0])
        else:
            in_scale = scalar_scale(if_tensor, 1.0)
            out_scale = output_scale
            weight_scales = weight.quant.scale or [1.0]
            unique_scales = {round(float(scale), 18) for scale in weight_scales}
            if len(unique_scales) > 1:
                warnings.append(
                    f"CONV_2D op {op.index}: per-channel weight scales found; using channel 0 for MULT"
                )
            real_scale = in_scale * float(weight_scales[0]) / out_scale
            mult, mult_shift = fixed_multiplier(real_scale)

        qmin, qmax = activation_clamp(of_tensor.dtype, output_zp, output_scale, opts.fused_activation)

        conv_layers.append(
            ConvLayer(
                name=str(name),
                op_index=op.index,
                input_tensor=input_tensor,
                input_from_tensor=raw_input_tensor,
                weight_tensor=weight_tensor,
                bias_tensor=bias_tensor,
                output_tensor=output_tensor,
                ifheight=ifh,
                ifwidth=ifw,
                ifchannel=ifc,
                ofheight=ofh,
                ofwidth=ofw,
                ofchannel=ofc,
                hf=hf,
                wf=wf,
                stride=opts.stride_h,
                padding=padding,
                ifc_zp=input_zp,
                fltc_zp=fltc_zp,
                mult=mult,
                mult_shift=mult_shift,
                zpy=output_zp,
                qmin=int(side.get("qmin", qmin)),
                qmax=int(side.get("qmax", qmax)),
                is_leaky_relu=bool(side.get("is_leaky_relu", False)),
            )
        )
        conv_order += 1

    if not conv_layers:
        raise ValueError("No CONV_2D layers found in the TFLite model")
    return conv_layers


def normalize_axis(axis: int, rank: int) -> int:
    return axis + rank if axis < 0 else axis


def tensor_view_for(model: TFLiteModel, tensor_index: int, addr: int, row_alignment: int) -> TensorView:
    tensor = model.tensors[tensor_index]
    h, w, c = tensor.hwc_shape()
    return TensorView(
        tensor_index=tensor_index,
        addr=addr,
        height=h,
        width=w,
        channels=c,
        row_stride=tensor.activation_row_stride_bytes(row_alignment),
    )


def warn_concat_quantization(
    warnings: List[str],
    name: str,
    model: TFLiteModel,
    input_tensors: Sequence[int],
    output_tensor: int,
) -> None:
    out = model.tensors[output_tensor]
    out_scale = scalar_scale(out, 1.0)
    out_zp = scalar_zero_point(out, 0)
    for tensor_index in input_tensors:
        tensor = model.tensors[tensor_index]
        in_scale = scalar_scale(tensor, 1.0)
        in_zp = scalar_zero_point(tensor, 0)
        if abs(in_scale - out_scale) > 1e-12 or in_zp != out_zp:
            warnings.append(
                f"{name}: concat input tensor {tensor_index} quantization "
                f"(scale={in_scale}, zp={in_zp}) differs from output "
                f"(scale={out_scale}, zp={out_zp}); CPU fallback copies raw int8 bytes"
            )


def extract_cpu_ops(
    tflite_path: Path,
    model: TFLiteModel,
    warnings: List[str],
    max_inputs: int = 4,
) -> List[CpuOp]:
    raw_data = tflite_path.read_bytes()
    cpu_ops: List[CpuOp] = []
    pool_count = 0
    concat_count = 0

    for op in model.operators:
        if op.op_name == "MAX_POOL_2D":
            if len(op.inputs) < 1 or len(op.outputs) < 1 or op.inputs[0] < 0:
                warnings.append(f"Skipping malformed MAX_POOL_2D op {op.index}")
                continue
            opts = read_pool2d_options(raw_data, op.options)
            input_tensor = op.inputs[0]
            output_tensor = op.outputs[0]
            if_tensor = model.tensors[input_tensor]
            of_tensor = model.tensors[output_tensor]
            ifh, ifw, ifc = if_tensor.hwc_shape()
            ofh, ofw, ofc = of_tensor.hwc_shape()
            if ifc != ofc:
                raise ValueError(
                    f"MAX_POOL_2D op {op.index}: input/output channel mismatch {ifc}/{ofc}"
                )
            if opts.stride_h != opts.stride_w:
                warnings.append(
                    f"MAX_POOL_2D op {op.index}: asymmetric stride H/W="
                    f"{opts.stride_h}/{opts.stride_w}; CPU fallback supports it"
                )
            if opts.filter_h != opts.filter_w:
                warnings.append(
                    f"MAX_POOL_2D op {op.index}: nonsquare filter H/W="
                    f"{opts.filter_h}/{opts.filter_w}; CPU fallback supports it"
                )
            if opts.padding == 0:
                pad_top, pad_bottom = same_padding_pair(ifh, ofh, opts.filter_h, opts.stride_h, 1)
                pad_left, pad_right = same_padding_pair(ifw, ofw, opts.filter_w, opts.stride_w, 1)
                if pad_top != pad_bottom or pad_left != pad_right or pad_top != pad_left:
                    warnings.append(
                        f"MAX_POOL_2D op {op.index}: asymmetric SAME padding "
                        f"top/bottom/left/right={pad_top}/{pad_bottom}/{pad_left}/{pad_right}; "
                        "CPU fallback uses top/left offsets and skips out-of-range pixels"
                    )
            else:
                pad_top = 0
                pad_left = 0

            qmin, qmax = activation_clamp(
                of_tensor.dtype,
                scalar_zero_point(of_tensor, 0),
                scalar_scale(of_tensor, 1.0),
                opts.fused_activation,
            )
            pool_count += 1
            cpu_ops.append(
                CpuOp(
                    name=f"MaxPool{pool_count}",
                    op_index=op.index,
                    kind="MAX_POOL_2D",
                    inputs=[input_tensor],
                    output=output_tensor,
                    filter_h=opts.filter_h,
                    filter_w=opts.filter_w,
                    stride_h=opts.stride_h,
                    stride_w=opts.stride_w,
                    pad_top=pad_top,
                    pad_left=pad_left,
                    qmin=qmin,
                    qmax=qmax,
                )
            )

        elif op.op_name == "CONCATENATION":
            inputs = [idx for idx in op.inputs if idx >= 0]
            if not inputs or not op.outputs:
                warnings.append(f"Skipping malformed CONCATENATION op {op.index}")
                continue
            if len(inputs) > max_inputs:
                raise ValueError(
                    f"CONCATENATION op {op.index}: {len(inputs)} inputs, max generated CPU inputs is {max_inputs}"
                )
            opts = read_concat_options(raw_data, op.options)
            output_tensor = op.outputs[0]
            out_tensor = model.tensors[output_tensor]
            axis = normalize_axis(opts.axis, len(out_tensor.shape))
            if axis != 3:
                raise ValueError(
                    f"CONCATENATION op {op.index}: CPU fallback only supports NHWC channel axis, got axis={opts.axis}"
                )

            out_h, out_w, out_c = out_tensor.hwc_shape()
            channel_sum = 0
            for tensor_index in inputs:
                tensor = model.tensors[tensor_index]
                h, w, c = tensor.hwc_shape()
                if h != out_h or w != out_w:
                    raise ValueError(
                        f"CONCATENATION op {op.index}: input tensor {tensor_index} shape "
                        f"{tensor.shape} does not match output H/W {out_h}x{out_w}"
                    )
                channel_sum += c
            if channel_sum != out_c:
                raise ValueError(
                    f"CONCATENATION op {op.index}: input channels sum {channel_sum}, output channels {out_c}"
                )
            if opts.fused_activation != 0:
                warnings.append(
                    f"CONCATENATION op {op.index}: fused activation {opts.fused_activation} "
                    "is ignored by raw-copy CPU fallback"
                )
            concat_count += 1
            name = f"Concat{concat_count}"
            warn_concat_quantization(warnings, name, model, inputs, output_tensor)
            cpu_ops.append(
                CpuOp(
                    name=name,
                    op_index=op.index,
                    kind="CONCATENATION",
                    inputs=inputs,
                    output=output_tensor,
                    input_views=[],
                    concat_axis=axis,
                )
            )

    return cpu_ops


def optimize_zero_copy_concats(
    model: TFLiteModel,
    layers: List[ConvLayer],
    cpu_ops: List[CpuOp],
    row_alignment: int,
    warnings: List[str],
) -> Tuple[List[CpuOp], List[ZeroCopyConcatAlias]]:
    producer_by_tensor = {layer.output_tensor: layer for layer in layers}
    consumers: Dict[int, List[int]] = {}
    for op in model.operators:
        for tensor_index in op.inputs:
            if tensor_index >= 0:
                consumers.setdefault(tensor_index, []).append(op.index)

    optimized_ops: List[CpuOp] = []
    aliases: List[ZeroCopyConcatAlias] = []

    for cpu_op in cpu_ops:
        if cpu_op.kind != "CONCATENATION":
            optimized_ops.append(cpu_op)
            continue

        out_tensor = model.tensors[cpu_op.output]
        out_h, out_w, out_c = out_tensor.hwc_shape()
        out_row_stride = out_tensor.activation_row_stride_bytes(row_alignment)
        channel_offset = 0
        local_aliases: List[ZeroCopyConcatAlias] = []
        reject_reason: Optional[str] = None

        for input_tensor_index in cpu_op.inputs:
            input_tensor = model.tensors[input_tensor_index]
            in_h, in_w, in_c = input_tensor.hwc_shape()
            producer = producer_by_tensor.get(input_tensor_index)
            tensor_consumers = consumers.get(input_tensor_index, [])

            if producer is None:
                reject_reason = f"input tensor {input_tensor_index} is not produced by a CONV_2D layer"
                break
            if tensor_consumers != [cpu_op.op_index]:
                reject_reason = (
                    f"input tensor {input_tensor_index} has consumers {tensor_consumers}, "
                    "so it cannot be redirected safely"
                )
                break
            if input_tensor.dtype != out_tensor.dtype:
                reject_reason = (
                    f"input tensor {input_tensor_index} dtype {input_tensor.dtype} "
                    f"differs from output dtype {out_tensor.dtype}"
                )
                break
            if in_h != out_h or in_w != out_w:
                reject_reason = (
                    f"input tensor {input_tensor_index} shape {in_h}x{in_w} "
                    f"does not match concat output {out_h}x{out_w}"
                )
                break
            if input_tensor.activation_row_stride_bytes(row_alignment) != out_row_stride:
                reject_reason = (
                    f"input tensor {input_tensor_index} row stride "
                    f"{input_tensor.activation_row_stride_bytes(row_alignment)} differs "
                    f"from output row stride {out_row_stride}"
                )
                break

            local_aliases.append(
                ZeroCopyConcatAlias(
                    name=cpu_op.name,
                    op_index=cpu_op.op_index,
                    input_tensor=input_tensor_index,
                    output_tensor=cpu_op.output,
                    producer_op_index=producer.op_index,
                    channel_offset=channel_offset,
                )
            )
            channel_offset += in_c

        if reject_reason is not None or channel_offset != out_c:
            if reject_reason is None:
                reject_reason = f"input channel sum {channel_offset} differs from output channels {out_c}"
            warnings.append(f"{cpu_op.name}: keeping CPU concat fallback because {reject_reason}")
            optimized_ops.append(cpu_op)
            continue

        aliases.extend(local_aliases)
        warnings.append(
            f"{cpu_op.name}: zero-copy concat enabled; producer conv layers write directly "
            f"into output tensor {cpu_op.output}"
        )

    return optimized_ops, aliases


def apply_zero_copy_concat_aliases(
    model: TFLiteModel,
    layers: List[ConvLayer],
    cpu_ops: List[CpuOp],
    aliases: List[ZeroCopyConcatAlias],
    row_alignment: int,
    warnings: List[str],
) -> None:
    if not aliases:
        return

    tensor_addr: Dict[int, int] = {}
    for layer in layers:
        tensor_addr.setdefault(layer.input_tensor, layer.ifbaddr)
        tensor_addr.setdefault(layer.output_tensor, layer.ofbaddr)
    for cpu_op in cpu_ops:
        for view in cpu_op.input_views:
            tensor_addr.setdefault(view.tensor_index, view.addr)
        tensor_addr.setdefault(cpu_op.output_view.tensor_index, cpu_op.output_view.addr)

    producer_by_tensor = {layer.output_tensor: layer for layer in layers}
    for alias in aliases:
        producer = producer_by_tensor.get(alias.input_tensor)
        output_addr = tensor_addr.get(alias.output_tensor)
        if producer is None or output_addr is None:
            warnings.append(
                f"{alias.name}: zero-copy alias for tensor {alias.input_tensor} could not be applied"
            )
            continue

        out_tensor = model.tensors[alias.output_tensor]
        out_h, _, _ = out_tensor.hwc_shape()
        channel_bytes = out_h * out_tensor.activation_row_stride_bytes(row_alignment)
        producer.ofbaddr = output_addr + alias.channel_offset * channel_bytes
        tensor_addr[alias.input_tensor] = producer.ofbaddr


def detect_final_gap_op_indices(model: TFLiteModel, layers: List[ConvLayer]) -> set:
    if not layers:
        return set()
    final_output = layers[-1].output_tensor
    return {
        op.index
        for op in model.operators
        if op.op_name == "MEAN" and op.inputs and op.inputs[0] == final_output
    }


def build_execution_steps(
    model: TFLiteModel,
    layers: List[ConvLayer],
    cpu_ops: List[CpuOp],
    final_gap_ops: set,
    zero_copy_concat_ops: set,
    warnings: List[str],
) -> List[ExecutionStep]:
    layer_by_op = {layer.op_index: idx for idx, layer in enumerate(layers)}
    cpu_by_op = {op.op_index: idx for idx, op in enumerate(cpu_ops)}
    steps: List[ExecutionStep] = []
    passthrough_ops = {"PAD", "PADV2", "RESHAPE"}

    for op in model.operators:
        if op.index in layer_by_op:
            steps.append(ExecutionStep("ACCEL_CONV", layer_by_op[op.index]))
        elif op.index in cpu_by_op:
            steps.append(ExecutionStep("CPU_OP", cpu_by_op[op.index]))
        elif op.index in final_gap_ops:
            continue
        elif op.index in zero_copy_concat_ops:
            continue
        elif op.op_name in passthrough_ops:
            continue
        else:
            warnings.append(
                f"Operator {op.index} ({op.op_name}) has no generated accelerator/CPU step; "
                "generated C may need another fallback for full-model execution"
            )

    return steps


def simulate_layer(layer: ConvLayer, nip: int, npass: int, nfp: int) -> Tuple[int, MemoryFootprint]:
    total_cycles = 0
    total_first_row_cycles = 0
    total_remaining_rows_cycles = 0
    t_ifmap = ceil_div(layer.ifchannel, nip)

    for co_idx in range(0, layer.ofchannel, npass * nfp):
        actual_filters_in_chunk = min(npass * nfp, layer.ofchannel - co_idx)
        actual_passes = ceil_div(actual_filters_in_chunk, nfp)
        c_depth = 0
        c_depth_wo_weight_load = 0

        for ci_idx in range(0, layer.ifchannel, nip):
            actual_nip = min(nip, layer.ifchannel - ci_idx)
            total_c_pass = 0
            total_c_pass_wo_weight_load = 0

            for p in range(actual_passes):
                actual_nfp = min(nfp, actual_filters_in_chunk - p * nfp)
                c_comp_pass = layer.ofwidth * layer.wf
                c_load_pass = actual_nfp * actual_nip * layer.wf * layer.hf
                total_c_pass += max(c_comp_pass, c_load_pass)
                total_c_pass_wo_weight_load += c_comp_pass

            c_load_ifmap = actual_nip * layer.ifwidth
            total_store_time = layer.ofheight * layer.ofchannel * layer.ofwidth
            num_filter_chunks = ceil_div(layer.ofchannel, npass * nfp)
            c_store_tile_amortized = math.ceil(total_store_time / (t_ifmap * layer.ifwidth * num_filter_chunks))
            c_tile = max(total_c_pass, c_load_ifmap + c_store_tile_amortized)
            c_tile_wo_weight_load = max(total_c_pass_wo_weight_load, c_load_ifmap + c_store_tile_amortized)
            c_depth += c_tile
            c_depth_wo_weight_load += c_tile_wo_weight_load

        total_first_row_cycles += c_depth
        total_remaining_rows_cycles += c_depth_wo_weight_load * (layer.ifheight - 1)
        total_cycles += c_depth + c_depth_wo_weight_load * (layer.ifheight - 1)

    mem = MemoryFootprint(
        partial=layer.ofwidth * 4 * 24 * 2 * npass,
        ofmap=layer.ofwidth * npass * 2 * ceil_div(nfp, 2),
        ifmap=layer.ifwidth * 4 * 2,
        weight=ceil_div(layer.ifchannel, nip) * ceil_div(nfp, 2) * npass * layer.hf * layer.wf * 4 * 2,
    )
    return total_cycles, mem


def fits_fixed_sram(mem: MemoryFootprint) -> bool:
    return (
        mem.partial <= FIXED_PARTIAL_SRAM
        and mem.ofmap <= FIXED_OFMAP_SRAM
        and mem.ifmap <= FIXED_IFMAP_SRAM
        and mem.weight <= FIXED_WEIGHT_SRAM
    )


def choose_layer_config(layer: ConvLayer, max_k: int, max_oftile: int) -> LayerConfig:
    candidates: List[LayerConfig] = []
    for nip in range(1, min(max_k, layer.ifchannel) + 1):
        max_nfp = min(MAX_NFP // layer.wf, layer.ofchannel)
        for nfp in range(1, max_nfp + 1):
            for npass in range(1, max_oftile + 1):
                cycles, mem = simulate_layer(layer, nip, npass, nfp)
                if fits_fixed_sram(mem):
                    candidates.append(LayerConfig(nip=nip, npass=npass, nfp=nfp, cycles=cycles, mem=mem))
    if not candidates:
        raise ValueError(f"{layer.name}: no IFPARR/OFTILE/OFPARR config fits fixed SRAM caps")
    return min(candidates, key=lambda c: (c.cycles, c.mem.total, c.mem.partial, c.mem.ofmap, c.nip, c.npass, c.nfp))


def build_slots(ofc: int, ofparr: int, oftile: int, group_start: int, group_cols: int) -> Tuple[List[int], List[List[List[int]]]]:
    full_cols = ofc // ofparr
    tail_slots = ofc % ofparr
    lane_rows = [sum(1 for row in range(lane, ofparr, ACCEL_M)) for lane in range(ACCEL_M)]
    lane_count = [
        full_cols * lane_rows[lane] + (ceil_div(tail_slots - lane, ACCEL_M) if tail_slots > lane else 0)
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

    lane_seq: List[List[int]] = [[] for _ in range(ACCEL_M)]
    lane_used: List[List[bool]] = [[] for _ in range(ACCEL_M)]
    slots = [[[-1 for _ in range(group_cols)] for _ in range(lane_rows[lane])] for lane in range(ACCEL_M)]

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


def build_weight_group(weight: bytes, layer: ConvLayer, group_start: int, group_cols: int) -> bytes:
    lane_rows, slots = build_slots(layer.ofchannel, layer.ofparr, layer.oftile, group_start, group_cols)

    filters: List[int] = []
    for col in range(group_cols):
        for lane in range(ACCEL_M):
            for row in range(lane_rows[lane]):
                ch = slots[lane][row][col]
                if 0 <= ch < layer.ofchannel:
                    filters.append(ch)

    out = bytearray()
    filter_span = layer.hf * layer.wf * layer.ifchannel
    for channel_group in range(0, layer.ifchannel, layer.ifparr):
        channel_count = min(layer.ifparr, layer.ifchannel - channel_group)
        packet = bytearray()
        for filter_idx in filters:
            filter_data = weight[filter_idx * filter_span : (filter_idx + 1) * filter_span]
            for c_local in range(channel_count):
                for ky in range(layer.hf):
                    for kx in range(layer.wf):
                        src = (ky * layer.wf + kx) * layer.ifchannel + channel_group + c_local
                        packet.append(filter_data[src])
        if len(packet) & 1:
            packet.append(0xFF)
        out.extend(packet)
    return bytes(out)


def build_bias_group(biases: Sequence[int], layer: ConvLayer, group_start: int, group_cols: int) -> bytes:
    lane_rows, slots = build_slots(layer.ofchannel, layer.ofparr, layer.oftile, group_start, group_cols)
    out = bytearray()
    for lane in range(ACCEL_M):
        for row in range(lane_rows[lane]):
            for col in range(group_cols):
                ch = slots[lane][row][col]
                if 0 <= ch < layer.ofchannel:
                    out.extend(int(biases[ch]).to_bytes(4, "big", signed=True))
    return bytes(out)


def read_bias_values(model: TFLiteModel, layer: ConvLayer, sidecar: Dict) -> List[int]:
    side = sidecar_conv_lookup(sidecar).get(layer.op_index, {})
    if "bias_values_int32" in side:
        return [int(v) for v in side["bias_values_int32"]]
    if layer.bias_tensor is None:
        return [0] * layer.ofchannel
    raw = tensor_buffer(model, layer.bias_tensor)
    if len(raw) < layer.ofchannel * 4:
        raise ValueError(f"{layer.name}: bias tensor is too small")
    return [int.from_bytes(raw[i * 4 : i * 4 + 4], "little", signed=True) for i in range(layer.ofchannel)]


def pack_parameters(
    model: TFLiteModel,
    layers: List[ConvLayer],
    sidecar: Dict,
    base_addr: int,
    alignment: int,
) -> bytes:
    sections: List[Tuple[int, bytes]] = []
    cursor = base_addr
    for layer in layers:
        weight = tensor_buffer(model, layer.weight_tensor)
        expected = layer.ofchannel * layer.hf * layer.wf * layer.ifchannel
        if len(weight) != expected:
            raise ValueError(f"{layer.name}: weight size {len(weight)} != expected {expected}")
        biases = read_bias_values(model, layer, sidecar)
        if len(biases) != layer.ofchannel:
            raise ValueError(f"{layer.name}: bias count {len(biases)} != output channels {layer.ofchannel}")

        packed_weight = bytearray()
        packed_bias = bytearray()
        total_cols = ceil_div(layer.ofchannel, layer.ofparr)
        for group_start in range(0, total_cols, layer.oftile):
            group_cols = min(layer.oftile, total_cols - group_start)
            packed_weight.extend(build_weight_group(weight, layer, group_start, group_cols))
            packed_bias.extend(build_bias_group(biases, layer, group_start, group_cols))

        cursor = align_up(cursor, alignment)
        layer.fltbaddr = cursor
        layer.packed_weight_size = len(packed_weight)
        sections.append((cursor, bytes(packed_weight)))
        cursor += len(packed_weight)

        cursor = align_up(cursor, alignment)
        layer.bias_baddr = cursor
        layer.packed_bias_size = len(packed_bias)
        sections.append((cursor, bytes(packed_bias)))
        cursor += len(packed_bias)

    total_size = align_up(max(addr + len(data) for addr, data in sections) - base_addr, alignment)
    blob = bytearray([0x00]) * total_size
    for addr, data in sections:
        offset = addr - base_addr
        blob[offset : offset + len(data)] = data
    return bytes(blob)


def assign_append_activation_addresses(
    model: TFLiteModel,
    layers: List[ConvLayer],
    cpu_ops: List[CpuOp],
    input_base: int,
    alignment: int,
    row_alignment: int,
) -> int:
    tensor_addr: Dict[int, int] = {}
    cursor = input_base

    def allocate(tensor_index: int) -> int:
        nonlocal cursor
        if tensor_index < 0:
            return 0
        if tensor_index not in tensor_addr:
            tensor_addr[tensor_index] = cursor
            cursor = align_up(
                cursor + model.tensors[tensor_index].activation_storage_bytes(row_alignment),
                alignment,
            )
        return tensor_addr[tensor_index]

    for tensor_index in model.inputs:
        allocate(tensor_index)

    layer_by_op = {layer.op_index: layer for layer in layers}
    cpu_by_op = {op.op_index: op for op in cpu_ops}
    for op in model.operators:
        layer = layer_by_op.get(op.index)
        if layer is not None:
            layer.ifbaddr = allocate(layer.input_tensor)
            layer.ofbaddr = allocate(layer.output_tensor)
            continue

        cpu_op = cpu_by_op.get(op.index)
        if cpu_op is not None:
            for tensor_index in cpu_op.inputs:
                allocate(tensor_index)
            allocate(cpu_op.output)

    for layer in layers:
        layer.ifbaddr = allocate(layer.input_tensor)
        layer.ofbaddr = allocate(layer.output_tensor)

    for cpu_op in cpu_ops:
        cpu_op.input_views = [
            tensor_view_for(model, tensor_index, allocate(tensor_index), row_alignment)
            for tensor_index in cpu_op.inputs
        ]
        cpu_op.output_view = tensor_view_for(model, cpu_op.output, allocate(cpu_op.output), row_alignment)

    return cursor - input_base


def assign_append_activation_addresses_legacy(
    model: TFLiteModel,
    layers: List[ConvLayer],
    input_base: int,
    alignment: int,
    row_alignment: int,
) -> int:
    tensor_addr: Dict[int, int] = {}
    cursor = input_base
    for tensor_index in model.inputs:
        tensor_addr[tensor_index] = cursor
        cursor = align_up(cursor + model.tensors[tensor_index].activation_storage_bytes(row_alignment), alignment)

    for layer in layers:
        if layer.input_tensor not in tensor_addr:
            tensor_addr[layer.input_tensor] = cursor
            cursor = align_up(cursor + model.tensors[layer.input_tensor].activation_storage_bytes(row_alignment), alignment)
        layer.ifbaddr = tensor_addr[layer.input_tensor]

        if layer.output_tensor not in tensor_addr:
            tensor_addr[layer.output_tensor] = cursor
            cursor = align_up(cursor + model.tensors[layer.output_tensor].activation_storage_bytes(row_alignment), alignment)
        layer.ofbaddr = tensor_addr[layer.output_tensor]

    return cursor - input_base


def interval_overlap(a: Tuple[int, int], b: Tuple[int, int]) -> bool:
    return a[0] <= b[1] and b[0] <= a[1]


def byte_overlap(a_base: int, a_size: int, b_base: int, b_size: int) -> bool:
    return a_base < b_base + b_size and b_base < a_base + a_size


def assign_liveness_activation_addresses(
    model: TFLiteModel,
    layers: List[ConvLayer],
    cpu_ops: List[CpuOp],
    execution_steps: List[ExecutionStep],
    final_gap_enabled: bool,
    input_base: int,
    alignment: int,
    row_alignment: int,
) -> int:
    intervals: Dict[int, List[int]] = {}
    produced_at: Dict[int, int] = {}

    def touch_input(tensor_index: int, step_idx: int) -> None:
        start = produced_at.get(tensor_index, -1)
        current = intervals.setdefault(tensor_index, [start, step_idx])
        current[0] = min(current[0], start)
        current[1] = max(current[1], step_idx)

    def touch_output(tensor_index: int, step_idx: int) -> None:
        produced_at[tensor_index] = step_idx
        current = intervals.setdefault(tensor_index, [step_idx, step_idx])
        current[0] = min(current[0], step_idx)
        current[1] = max(current[1], step_idx)

    for step_idx, step in enumerate(execution_steps):
        if step.kind == "ACCEL_CONV":
            layer = layers[step.index]
            touch_input(layer.input_tensor, step_idx)
            touch_output(layer.output_tensor, step_idx)
        elif step.kind == "CPU_OP":
            cpu_op = cpu_ops[step.index]
            for tensor_index in cpu_op.inputs:
                touch_input(tensor_index, step_idx)
            touch_output(cpu_op.output, step_idx)

    final_step = len(execution_steps)
    if final_gap_enabled and layers:
        touch_input(layers[-1].output_tensor, final_step)

    for tensor_index in model.outputs:
        touch_input(tensor_index, final_step)

    allocations: Dict[int, Tuple[int, int, Tuple[int, int]]] = {}
    cursor = input_base
    for tensor_index in model.inputs:
        size = model.tensors[tensor_index].activation_storage_bytes(row_alignment)
        interval = tuple(intervals.get(tensor_index, [-1, 0]))
        allocations[tensor_index] = (cursor, size, interval)
        cursor = align_up(cursor + size, alignment)

    ordered_tensors: List[int] = []
    for step in execution_steps:
        if step.kind == "ACCEL_CONV":
            layer = layers[step.index]
            ordered_tensors.extend([layer.input_tensor, layer.output_tensor])
        elif step.kind == "CPU_OP":
            cpu_op = cpu_ops[step.index]
            ordered_tensors.extend(cpu_op.inputs)
            ordered_tensors.append(cpu_op.output)
    if final_gap_enabled and layers:
        ordered_tensors.append(layers[-1].output_tensor)

    for tensor_index in ordered_tensors:
            if tensor_index in allocations:
                continue
            size = model.tensors[tensor_index].activation_storage_bytes(row_alignment)
            interval = tuple(intervals[tensor_index])
            candidate = input_base
            while True:
                candidate = align_up(candidate, alignment)
                conflict = False
                next_candidate = candidate + alignment
                for base, other_size, other_interval in allocations.values():
                    if interval_overlap(interval, other_interval) and byte_overlap(candidate, size, base, other_size):
                        conflict = True
                        next_candidate = max(next_candidate, align_up(base + other_size, alignment))
                if not conflict:
                    allocations[tensor_index] = (candidate, size, interval)
                    break
                candidate = next_candidate

    for layer in layers:
        layer.ifbaddr = allocations[layer.input_tensor][0]
        layer.ofbaddr = allocations[layer.output_tensor][0]

    for cpu_op in cpu_ops:
        cpu_op.input_views = [
            tensor_view_for(model, tensor_index, allocations[tensor_index][0], row_alignment)
            for tensor_index in cpu_op.inputs
        ]
        cpu_op.output_view = tensor_view_for(model, cpu_op.output, allocations[cpu_op.output][0], row_alignment)

    return max(base + size for base, size, _ in allocations.values()) - input_base


def populate_layer_activation_layout(
    model: TFLiteModel,
    layers: List[ConvLayer],
    cpu_ops: List[CpuOp],
    row_alignment: int,
    warnings: List[str],
) -> None:
    warned_tensors: set = set()
    for layer in layers:
        if_tensor = model.tensors[layer.input_tensor]
        of_tensor = model.tensors[layer.output_tensor]
        layer.ifrow_stride = if_tensor.activation_row_stride_bytes(row_alignment)
        layer.ofrow_stride = of_tensor.activation_row_stride_bytes(row_alignment)
        layer.ifmap_raw_bytes = if_tensor.activation_bytes()
        layer.ifmap_storage_bytes = if_tensor.activation_storage_bytes(row_alignment)
        layer.ofmap_raw_bytes = of_tensor.activation_bytes()
        layer.ofmap_storage_bytes = of_tensor.activation_storage_bytes(row_alignment)
        warn_row_padding_once(warnings, warned_tensors, if_tensor, row_alignment)
        warn_row_padding_once(warnings, warned_tensors, of_tensor, row_alignment)
    for cpu_op in cpu_ops:
        for tensor_index in [*cpu_op.inputs, cpu_op.output]:
            warn_row_padding_once(warnings, warned_tensors, model.tensors[tensor_index], row_alignment)


def detect_final_gap(model: TFLiteModel, layers: List[ConvLayer]) -> bool:
    final_output = layers[-1].output_tensor
    for op in model.operators:
        if op.op_name == "MEAN" and op.inputs and op.inputs[0] == final_output:
            return True
    return False


def c_bool(value: bool) -> str:
    return "true" if value else "false"


def c_i64(value: int) -> str:
    return f"({value}LL)" if value < 0 else f"{value}LL"


def c_string(text: str) -> str:
    return json.dumps(text)


def emit_header(
    path: Path,
    module: str,
    api_prefix: str,
    guard: str,
    first_layer: ConvLayer,
    final_layer: ConvLayer,
    gap_enabled: bool,
    camera_config: Optional[CameraConfig],
    static_input: Optional[StaticInputConfig],
) -> None:
    final_raw_bytes = final_layer.ofmap_raw_bytes
    final_storage_bytes = final_layer.ofmap_storage_bytes
    comment_lines = [
        "/*",
        " * Generated accelerator path. Before calling RunPreparedInput, place the",
        " * model input tensor in HyperRAM1 at the generated layer-1 IFBADDR and",
        " * load the generated packed weight blob into HyperRAM0 at offset 0.",
    ]
    if not gap_enabled:
        comment_lines.append(
            " * This model has no detected final MEAN op; logits_out is ignored and the final OFMAP stays in HyperRAM1."
        )
    if camera_config is not None:
        comment_lines.append(
            " * Camera helpers configure the video resize block and preprocessing LUTs from the model sidecar."
        )
    if static_input is not None:
        comment_lines.append(
            " * Static-image helper copies a preprocessed CHW int8 IFMAP from SPI flash into HyperRAM1."
        )
    comment_lines.append(" */")

    camera_decls = []
    if camera_config is not None:
        camera_decls = [
            f"bool {api_prefix}_Accel_RunCameraTimingOnly(void);",
            f"bool {api_prefix}_Accel_RunCameraResultLoop(void);",
        ]
    static_decls = []
    if static_input is not None:
        static_decls = [
            f"bool {api_prefix}_Accel_RunStaticImageFromFlash(void);",
        ]

    lines = [
        f"#ifndef {guard}",
        f"#define {guard}",
        "",
        "#include <stdbool.h>",
        "#include <stdint.h>",
        "",
        f"#define {module.upper()}_INPUT_IFMAP_ADDR   {first_layer.ifbaddr}U",
        f"#define {module.upper()}_INPUT_IFMAP_BYTES  {first_layer.ifmap_storage_bytes}U",
        f"#define {module.upper()}_INPUT_RAW_BYTES    {first_layer.ifmap_raw_bytes}U",
        f"#define {module.upper()}_INPUT_HEIGHT       {first_layer.ifheight}U",
        f"#define {module.upper()}_INPUT_WIDTH        {first_layer.ifwidth}U",
        f"#define {module.upper()}_INPUT_CHANNELS     {first_layer.ifchannel}U",
        f"#define {module.upper()}_INPUT_ROW_STRIDE   {first_layer.ifrow_stride}U",
        "",
        f"#define {module.upper()}_FINAL_OFMAP_ADDR  {final_layer.ofbaddr}U",
        f"#define {module.upper()}_FINAL_OFMAP_BYTES {final_storage_bytes}U",
        f"#define {module.upper()}_FINAL_OFMAP_RAW_BYTES {final_raw_bytes}U",
        f"#define {module.upper()}_FINAL_CHANNELS    {final_layer.ofchannel}U",
        "",
        *comment_lines,
        f"bool {api_prefix}_Accel_RunTimingOnly(void);",
        f"bool {api_prefix}_Accel_RunPreparedInput(int32_t *logits_out, uint32_t logits_count);",
        *camera_decls,
        *static_decls,
        f"uint32_t {api_prefix}_Accel_FinalOfmapAddr(void);",
        f"uint32_t {api_prefix}_Accel_FinalOfmapBytes(void);",
        "",
        f"#endif /* {guard} */",
        "",
    ]
    path.write_text("\n".join(lines))


def layer_initializer(layer: ConvLayer) -> str:
    return (
        f"    {{ {c_string(layer.name)}, {layer.ifheight}U, {layer.ifchannel}U, {layer.ofchannel}U, "
        f"{layer.hf}U, {layer.stride}U, {layer.padding}U, {layer.ifparr}U, {layer.oftile}U, {layer.ofparr}U, "
        f"{layer.ifbaddr}U, {layer.fltbaddr}U, {layer.bias_baddr}U, {layer.ofbaddr}U, "
        f"{layer.ifrow_stride}U, {layer.ofrow_stride}U, "
        f"{layer.ifc_zp}, {layer.fltc_zp}, {layer.mult}, {layer.mult_shift}U, "
        f"{layer.zpy}, {layer.qmin}, {layer.qmax}, {c_bool(layer.is_leaky_relu)} }}"
    )


def tensor_view_initializer(view: TensorView) -> str:
    return (
        f"{{ {view.addr}U, {view.height}U, {view.width}U, "
        f"{view.channels}U, {view.row_stride}U }}"
    )


def cpu_op_initializer(cpu_op: CpuOp, max_inputs: int) -> str:
    kind = "CPU_OP_MAX_POOL_2D" if cpu_op.kind == "MAX_POOL_2D" else "CPU_OP_CONCATENATION"
    views = [tensor_view_initializer(view) for view in cpu_op.input_views]
    zero_view = "{ 0U, 0U, 0U, 0U, 0U }"
    while len(views) < max_inputs:
        views.append(zero_view)
    input_views = ", ".join(views)
    return (
        f"    {{ {c_string(cpu_op.name)}, {kind}, {len(cpu_op.input_views)}U, "
        f"{{ {input_views} }}, {tensor_view_initializer(cpu_op.output_view)}, "
        f"{cpu_op.filter_h}U, {cpu_op.filter_w}U, {cpu_op.stride_h}U, {cpu_op.stride_w}U, "
        f"{cpu_op.pad_top}U, {cpu_op.pad_left}U, {cpu_op.qmin}, {cpu_op.qmax} }}"
    )


def execution_step_initializer(step: ExecutionStep) -> str:
    kind = "EXEC_STEP_ACCEL_CONV" if step.kind == "ACCEL_CONV" else "EXEC_STEP_CPU_OP"
    return f"    {{ {kind}, {step.index}U }}"


def camera_source_decls(module: str, macro: str, camera: Optional[CameraConfig]) -> str:
    if camera is None:
        return ""
    return f'''
#define {macro}_VIDEO_WARMUP_MS           100U
#define {macro}_VIDEO_OUT_SIZE            {camera.out_size}U
#define {macro}_VIDEO_OUT_PIXELS          {camera.out_pixels}U
#define {macro}_VIDEO_SCALED_H            {camera.scaled_h}U
#define {macro}_VIDEO_PAD_TOP             {camera.pad_top}U
#define {macro}_VIDEO_X_STEP              {camera.x_step}U
#define {macro}_VIDEO_Y_STEP              {camera.y_step}U
#define {macro}_PREPROC_SHIFT             {camera.shift}U
#define {macro}_PREPROC_MULT_R            {camera.mult_r}
#define {macro}_PREPROC_MULT_G            {camera.mult_g}
#define {macro}_PREPROC_MULT_B            {camera.mult_b}
#define {macro}_PREPROC_OFFSET_R          {c_i64(camera.offset_r)}
#define {macro}_PREPROC_OFFSET_G          {c_i64(camera.offset_g)}
#define {macro}_PREPROC_OFFSET_B          {c_i64(camera.offset_b)}

static const VideoStreaming_ResizeConfig_t s_{module}_video_resize_config = {{
    {macro}_VIDEO_OUT_SIZE,
    {macro}_VIDEO_OUT_PIXELS,
    {macro}_VIDEO_SCALED_H,
    {macro}_VIDEO_PAD_TOP,
    {macro}_VIDEO_X_STEP,
    {macro}_VIDEO_Y_STEP,
    {c_bool(camera.output_bgr)}
}};

static const VideoStreaming_PreprocessConfig_t s_{module}_video_preprocess_config = {{
    {macro}_PREPROC_SHIFT,
    {macro}_PREPROC_MULT_R,
    {macro}_PREPROC_MULT_G,
    {macro}_PREPROC_MULT_B,
    {macro}_PREPROC_OFFSET_R,
    {macro}_PREPROC_OFFSET_G,
    {macro}_PREPROC_OFFSET_B
}};
'''


def camera_context_fields(camera: Optional[CameraConfig]) -> str:
    if camera is None:
        return ""
    return """    bool old_video_enable;
    bool old_video_grant;
    VideoStreaming_ResizeConfig_t old_video_resize_config;
    int32_t old_video_scale_mult;
    uint8_t old_video_scale_shift;
    int8_t old_video_zero_point;
"""


def camera_begin_code(module: str, macro: str, camera: Optional[CameraConfig]) -> str:
    if camera is None:
        return ""
    return f'''
    context->old_video_enable = VideoStreaming_is_enabled(&video_streaming);
    context->old_video_grant = VideoStreaming_get_grant_request(&video_streaming);
    VideoStreaming_get_resize_config(&video_streaming, &context->old_video_resize_config);
    context->old_video_scale_mult = VideoStreaming_get_scale_multiplier(&video_streaming);
    context->old_video_scale_shift = VideoStreaming_get_scale_shift(&video_streaming);
    context->old_video_zero_point = VideoStreaming_get_zero_point(&video_streaming);

    VideoStreaming_set_grant_request(&video_streaming, false);
    VideoStreaming_enable(&video_streaming, false);
    if (use_camera_ifmap) {{
        VideoStreaming_set_resize_config(&video_streaming, &s_{module}_video_resize_config);
        VideoStreaming_program_preprocessing_luts(&video_streaming, &s_{module}_video_preprocess_config);
        VideoStreaming_enable(&video_streaming, true);
        delay({macro}_VIDEO_WARMUP_MS);
    }}
'''


def camera_end_code(camera: Optional[CameraConfig]) -> str:
    if camera is None:
        return ""
    return """
    VideoStreaming_set_grant_request(&video_streaming, false);
    VideoStreaming_enable(&video_streaming, false);
    VideoStreaming_set_resize_config(&video_streaming, &context->old_video_resize_config);
    VideoStreaming_set_quantization(&video_streaming,
                                    context->old_video_scale_mult,
                                    context->old_video_scale_shift,
                                    context->old_video_zero_point);
    VideoStreaming_set_grant_request(&video_streaming, context->old_video_grant);
    VideoStreaming_enable(&video_streaming, context->old_video_enable);
"""


def camera_public_functions(
    module: str,
    macro: str,
    type_prefix: str,
    api_prefix: str,
    display_name: str,
    camera: Optional[CameraConfig],
    gap_enabled: bool,
) -> str:
    if camera is None:
        return ""
    return f'''
static {macro}_SIZE_OPT uint32_t argmax_logits(const int32_t *logits, uint32_t count)
{{
    uint32_t best = 0U;

    for (uint32_t i = 1U; i < count; i++) {{
        if (logits[i] > logits[best]) {{
            best = i;
        }}
    }}

    return best;
}}

static {macro}_SIZE_OPT void print_result_line(const int32_t *logits,
                                               tick_t conv_ticks,
                                               tick_t cpu_ticks,
                                               tick_t wall_ticks)
{{
    uint32_t label = argmax_logits(logits, {macro}_FINAL_CHANNELS);
    tick_t total_ticks = ticks_add(conv_ticks, cpu_ticks);

    Uart_write('\\r');
    Uart_print("SOC_RESULT class=");
    print_u32_dec(label);
    Uart_print(" logits=");
    for (uint32_t i = 0U; i < {macro}_FINAL_CHANNELS; i++) {{
        if (i != 0U) {{
            Uart_write(',');
        }}
        print_i32_dec(logits[i]);
    }}
    Uart_print(" conv_ms=");
    print_u32_dec(ticks_to_ms(conv_ticks));
    Uart_print(" cpu_ms=");
    print_u32_dec(ticks_to_ms(cpu_ticks));
    Uart_print(" total_ms=");
    print_u32_dec(ticks_to_ms(total_ticks));
    Uart_print(" wall_ms=");
    print_u32_dec(ticks_to_ms(wall_ticks));
    Uart_print("   ");
    Uart_write('\\r');
}}

bool {api_prefix}_Accel_RunCameraTimingOnly(void)
{{
    bool ok;
    {type_prefix}_RunContext_t context;
    tick_t conv_ticks = {{0U, 0U}};
    tick_t cpu_ticks = {{0U, 0U}};
    tick_t wall_ticks = {{0U, 0U}};
    tick_t measured_ticks;
    uint32_t conv_macs = total_conv_macs();
    int32_t *logits = s_{module}_logits;

    Uart_println("");
    Uart_println("=== Run {display_name} camera accelerator timing ===");
    Uart_println("Pipeline: camera IFMAP, conv layers on accelerator, fallback ops/GAP on CPU.");
    Uart_print("  Camera output            : ");
    print_u32_dec({macro}_VIDEO_OUT_SIZE);
    Uart_write('x');
    print_u32_dec({macro}_VIDEO_OUT_SIZE);
    Uart_println("x3");
    Uart_print("  Camera scaled_h/pad_top  : ");
    print_u32_dec({macro}_VIDEO_SCALED_H);
    Uart_write('/');
    print_u32_dec({macro}_VIDEO_PAD_TOP);
    Uart_println("");
    Uart_print("  Conv layers              : ");
    print_u32_dec({macro}_LAYER_COUNT);
    Uart_println("");
    Uart_print("  HR0 filter/bias reserved : ");
    print_u32_dec({macro}_PARAM_BYTES_RESERVED);
    Uart_println(" bytes");
    Uart_print("  HR1 activation reserved  : ");
    print_u32_dec({macro}_ACTIVATION_BYTES_RESERVED);
    Uart_println(" bytes");
    Uart_print("  Conv workload            : ");
    print_u32_dec(conv_macs);
    Uart_println(" MACs");

    ok = begin_run_context(&context, true);
    if (ok) {{
        ok = run_model_once(&context,
                            true,
                            true,
                            ({macro}_HAS_FINAL_GAP != 0U) ? logits : 0,
                            {macro}_FINAL_CHANNELS,
                            &conv_ticks,
                            &cpu_ticks,
                            &wall_ticks);
    }}

    if (ok) {{
        measured_ticks = ticks_add(conv_ticks, cpu_ticks);
        Uart_println("");
        Uart_println("{display_name} camera timing summary:");
        Uart_print("  Accelerator conv layers : ");
        print_tick_metric(conv_ticks);
        Uart_println("");
        Uart_print("  Conv average cost       : ");
        print_cycles_per_unit(conv_ticks, conv_macs / 1000U);
        Uart_println(" cycles / 1000 MACs");
        Uart_print("  CPU fallback/post       : ");
        print_tick_metric(cpu_ticks);
        Uart_println("");
        Uart_print("  Full measured pipeline  : ");
        print_tick_metric(measured_ticks);
        Uart_println("");
        Uart_print("  Wall section            : ");
        print_tick_metric(wall_ticks);
        Uart_println("  (includes UART/log overhead)");
    }}

    end_run_context(&context);

    Uart_println(ok ? "{display_name} camera timing -> DONE" : "{display_name} camera timing -> FAIL");
    return ok;
}}

bool {api_prefix}_Accel_RunCameraResultLoop(void)
{{
    {type_prefix}_RunContext_t context;
    bool ok;

    if ({macro}_HAS_FINAL_GAP == 0U) {{
        Uart_println("Camera result loop requires a final MEAN/GlobalAvgPool op.");
        return false;
    }}

    Uart_println("");
    Uart_println("Camera result loop, q to stop:");

    ok = begin_run_context(&context, true);

    while (ok) {{
        tick_t conv_ticks;
        tick_t cpu_ticks;
        tick_t wall_ticks;
        int32_t *logits = s_{module}_logits;
        uint8_t rx_data;

        ok = run_model_once(&context,
                            false,
                            true,
                            logits,
                            {macro}_FINAL_CHANNELS,
                            &conv_ticks,
                            &cpu_ticks,
                            &wall_ticks);
        if (!ok) {{
            break;
        }}

        print_result_line(logits, conv_ticks, cpu_ticks, wall_ticks);

        if (Uart_read(&rx_data) && ((rx_data == 'q') || (rx_data == 'Q'))) {{
            break;
        }}
    }}

    Uart_println("");
    end_run_context(&context);
    Uart_println(ok ? "{display_name} camera loop -> DONE" : "{display_name} camera loop -> FAIL");
    return ok;
}}
'''


def static_input_source_decls(module: str, macro: str, static_input: Optional[StaticInputConfig]) -> str:
    if static_input is None:
        return ""
    expected_top1 = "0xFFFFFFFFU" if static_input.expected_top1 < 0 else f"{static_input.expected_top1}U"
    return f'''
#define {macro}_STATIC_INPUT_FLASH_OFFSET  0x{static_input.flash_offset:06X}U
#define {macro}_STATIC_INPUT_BYTES         {static_input.size}U
#define {macro}_STATIC_INPUT_CRC32         0x{static_input.crc32:08X}U
#define {macro}_STATIC_GOLDEN_TOP1         {expected_top1}
#define {macro}_STATIC_GOLDEN_VALUE        {static_input.expected_value}
#define {macro}_STATIC_FLASH_CHUNK_BYTES   256U
#define {macro}_STATIC_TENSOR_REF_COUNT    {len(static_input.tensor_refs)}U
'''


def static_input_global_decls(
    module: str,
    macro: str,
    type_prefix: str,
    static_input: Optional[StaticInputConfig],
) -> str:
    if static_input is None:
        return ""
    ref_table_len = max(1, len(static_input.tensor_refs))
    ref_rows = []
    for ref in static_input.tensor_refs:
        ref_rows.append(
            "    { "
            f"{c_string(ref.name)}, {ref.tensor}U, 0x{ref.addr:08X}U, "
            f"{ref.height}U, {ref.width}U, {ref.channels}U, {ref.row_stride}U, "
            f"{ref.logical_bytes}U, 0x{ref.crc32:08X}U"
            " }"
        )
    if not ref_rows:
        ref_rows.append('    { "NoRef", 0U, 0U, 0U, 0U, 0U, 0U, 0U, 0U }')
    ref_table = ",\n".join(ref_rows)
    return f'''
typedef struct {{
    const char *name;
    uint16_t tensor;
    uint32_t addr;
    uint16_t height;
    uint16_t width;
    uint16_t channels;
    uint16_t row_stride;
    uint32_t logical_bytes;
    uint32_t crc32;
}} {type_prefix}_StaticTensorRef_t;

static const {type_prefix}_StaticTensorRef_t s_{module}_static_tensor_refs[{ref_table_len}U] = {{
{ref_table}
}};

static uint8_t s_{module}_static_flash_buf[{macro}_STATIC_FLASH_CHUNK_BYTES];
'''


def static_input_public_functions(
    module: str,
    macro: str,
    type_prefix: str,
    api_prefix: str,
    display_name: str,
    static_input: Optional[StaticInputConfig],
    camera_config: Optional[CameraConfig],
) -> str:
    if static_input is None:
        return ""
    run_model_false_arg = "false," if camera_config is not None else ""
    end_context_call = "&context" if camera_config is not None else ""
    begin_context_args = ", false" if camera_config is not None else ""
    return f'''
static {macro}_SIZE_OPT uint32_t argmax_i32(const int32_t *values, uint32_t count)
{{
    uint32_t best = 0U;

    for (uint32_t i = 1U; i < count; i++) {{
        if (values[i] > values[best]) {{
            best = i;
        }}
    }}

    return best;
}}

static {macro}_SIZE_OPT void print_static_top5(const int32_t *logits, uint32_t count)
{{
    uint32_t selected[5] = {{0U, 0U, 0U, 0U, 0U}};
    uint32_t selected_count = 0U;

    for (uint32_t rank = 0U; (rank < 5U) && (rank < count); rank++) {{
        uint32_t best = 0U;
        bool best_valid = false;

        for (uint32_t i = 0U; i < count; i++) {{
            bool used = false;

            for (uint32_t j = 0U; j < selected_count; j++) {{
                if (selected[j] == i) {{
                    used = true;
                    break;
                }}
            }}
            if (used) {{
                continue;
            }}
            if ((!best_valid) || (logits[i] > logits[best])) {{
                best = i;
                best_valid = true;
            }}
        }}

        if (!best_valid) {{
            break;
        }}
        selected[selected_count++] = best;
        if (rank != 0U) {{
            Uart_print(", ");
        }}
        print_u32_dec(best);
        Uart_write(':');
        print_i32_dec(logits[best]);
    }}
}}

static {macro}_SIZE_OPT bool load_static_input_from_flash({type_prefix}_RunContext_t *context)
{{
    uint32_t crc;
    uint32_t copied = 0U;
    uint32_t next_progress = 0U;

    Uart_println("  Static input: checking flash CRC...");
    crc = flash_crc32({macro}_STATIC_INPUT_FLASH_OFFSET, {macro}_STATIC_INPUT_BYTES);
    if (crc != {macro}_STATIC_INPUT_CRC32) {{
        Uart_print("Static input CRC mismatch flash=0x");
        print_hex_32(crc);
        Uart_print(" expected=0x");
        print_hex_32({macro}_STATIC_INPUT_CRC32);
        Uart_println("");
        return false;
    }}
    Uart_println("  Static input: CRC OK.");
    Uart_println("  Static input: copying flash -> HRAM1...");

    while (copied < {macro}_STATIC_INPUT_BYTES) {{
        uint32_t chunk = {macro}_STATIC_INPUT_BYTES - copied;

        if (chunk > {macro}_STATIC_FLASH_CHUNK_BYTES) {{
            chunk = {macro}_STATIC_FLASH_CHUNK_BYTES;
        }}
        flash_read_data({macro}_STATIC_INPUT_FLASH_OFFSET + copied,
                        s_{module}_static_flash_buf,
                        chunk);
        if (!hram_write_block_any(&context->w95_h1_write,
                                  {macro}_INPUT_IFMAP_ADDR + copied,
                                  s_{module}_static_flash_buf,
                                  chunk)) {{
            Uart_println("Static input HRAM1 write failed.");
            return false;
        }}
        copied += chunk;
        if (copied >= next_progress) {{
            Uart_print("    copied ");
            print_u32_dec(copied);
            Uart_print("/");
            print_u32_dec({macro}_STATIC_INPUT_BYTES);
            Uart_println(" bytes");
            next_progress += 32768U;
        }}
    }}

    Uart_println("  Static input: copy complete.");
    return true;
}}

static {macro}_SIZE_OPT uint32_t static_crc32_update(uint32_t crc, uint8_t byte)
{{
    crc ^= byte;
    for (uint8_t bit = 0U; bit < 8U; bit++) {{
        crc = (crc >> 1) ^ ((uint32_t)(-((int32_t)(crc & 1U))) & 0xEDB88320U);
    }}
    return crc;
}}

static {macro}_SIZE_OPT bool static_tensor_crc32(W95_HandleTypeDef *w95_read,
                                                 const {type_prefix}_StaticTensorRef_t *ref,
                                                 uint32_t *crc32_out)
{{
    uint32_t crc = 0xFFFFFFFFU;

    if ((ref == 0) || (crc32_out == 0) || (ref->row_stride > {macro}_HRAM_RW_BUF_BYTES)) {{
        return false;
    }}

    for (uint32_t c = 0U; c < ref->channels; c++) {{
        uint32_t ch_base = ref->addr + c * (uint32_t)ref->height * (uint32_t)ref->row_stride;

        for (uint32_t y = 0U; y < ref->height; y++) {{
            if (!hram_read_block_any(w95_read,
                                     ch_base + y * (uint32_t)ref->row_stride,
                                     s_{module}_hyperram_rw_buf,
                                     ref->row_stride)) {{
                return false;
            }}
            for (uint32_t x = 0U; x < ref->width; x++) {{
                crc = static_crc32_update(crc, s_{module}_hyperram_rw_buf[x]);
            }}
        }}
    }}

    *crc32_out = ~crc;
    return true;
}}

static {macro}_SIZE_OPT bool static_tensor_channel_crc32(W95_HandleTypeDef *w95_read,
                                                         const {type_prefix}_StaticTensorRef_t *ref,
                                                         uint32_t channel,
                                                         uint32_t *crc32_out)
{{
    uint32_t crc = 0xFFFFFFFFU;

    if ((ref == 0) ||
        (crc32_out == 0) ||
        (channel >= ref->channels) ||
        (ref->row_stride > {macro}_HRAM_RW_BUF_BYTES)) {{
        return false;
    }}

    uint32_t ch_base = ref->addr + channel * (uint32_t)ref->height * (uint32_t)ref->row_stride;

    for (uint32_t y = 0U; y < ref->height; y++) {{
        if (!hram_read_block_any(w95_read,
                                 ch_base + y * (uint32_t)ref->row_stride,
                                 s_{module}_hyperram_rw_buf,
                                 ref->row_stride)) {{
            return false;
        }}
        for (uint32_t x = 0U; x < ref->width; x++) {{
            crc = static_crc32_update(crc, s_{module}_hyperram_rw_buf[x]);
        }}
    }}

    *crc32_out = ~crc;
    return true;
}}

static {macro}_SIZE_OPT bool check_static_intermediate_refs({type_prefix}_RunContext_t *context)
{{
    if ({macro}_STATIC_TENSOR_REF_COUNT == 0U) {{
        Uart_println("STATIC_INTERMEDIATE no golden refs");
        return true;
    }}

    Uart_println("STATIC_INTERMEDIATE checking CRCs...");
    for (uint32_t i = 0U; i < {macro}_STATIC_TENSOR_REF_COUNT; i++) {{
        const {type_prefix}_StaticTensorRef_t *ref = &s_{module}_static_tensor_refs[i];
        uint32_t crc = 0U;

        if (!static_tensor_crc32(&context->w95_h1_read, ref, &crc)) {{
            Uart_print("STATIC_INTERMEDIATE read_fail name=");
            Uart_print(ref->name);
            Uart_print(" tensor=");
            print_u32_dec(ref->tensor);
            Uart_println("");
            return false;
        }}

        if (crc != ref->crc32) {{
            Uart_print("STATIC_INTERMEDIATE first_mismatch name=");
            Uart_print(ref->name);
            Uart_print(" tensor=");
            print_u32_dec(ref->tensor);
            Uart_print(" addr=0x");
            print_hex_32(ref->addr);
            Uart_print(" bytes=");
            print_u32_dec(ref->logical_bytes);
            Uart_print(" crc=0x");
            print_hex_32(crc);
            Uart_print(" expected=0x");
            print_hex_32(ref->crc32);
            Uart_println("");
            Uart_println("STATIC_INTERMEDIATE channel CRC dump:");
            uint32_t dump_channels = ref->channels;
            if (dump_channels > 64U) {{
                dump_channels = 64U;
            }}
            for (uint32_t ch = 0U; ch < dump_channels; ch++) {{
                uint32_t ch_crc = 0U;
                Uart_print("  ch=");
                print_u32_dec(ch);
                Uart_print(" crc=0x");
                if (static_tensor_channel_crc32(&context->w95_h1_read, ref, ch, &ch_crc)) {{
                    print_hex_32(ch_crc);
                }} else {{
                    Uart_print("READ_FAIL");
                }}
                Uart_println("");
            }}
            if (ref->channels > dump_channels) {{
                Uart_print("  ... truncated at ");
                print_u32_dec(dump_channels);
                Uart_print("/");
                print_u32_dec(ref->channels);
                Uart_println(" channels");
            }}
            return false;
        }}
    }}

    Uart_println("STATIC_INTERMEDIATE all CRCs PASS");
    return true;
}}

static {macro}_SIZE_OPT void print_static_result(const int32_t *logits, uint32_t count)
{{
    uint32_t predicted = argmax_i32(logits, count);

    Uart_print("STATIC_RESULT class=");
    print_u32_dec(predicted);
    Uart_print(" value=");
    print_i32_dec(logits[predicted]);
    Uart_print(" expected=");
    if ({macro}_STATIC_GOLDEN_TOP1 == 0xFFFFFFFFU) {{
        Uart_print("n/a");
    }} else {{
        print_u32_dec({macro}_STATIC_GOLDEN_TOP1);
        Uart_print(" expected_value=");
        print_i32_dec({macro}_STATIC_GOLDEN_VALUE);
        Uart_print((predicted == {macro}_STATIC_GOLDEN_TOP1) ? " PASS" : " FAIL");
    }}
    Uart_println("");
    Uart_print("STATIC_TOP5 ");
    print_static_top5(logits, count);
    Uart_println("");
}}

bool {api_prefix}_Accel_RunStaticImageFromFlash(void)
{{
    bool ok;
    {type_prefix}_RunContext_t context;
    tick_t conv_ticks = {{0U, 0U}};
    tick_t cpu_ticks = {{0U, 0U}};
    tick_t wall_ticks = {{0U, 0U}};
    int32_t *logits = s_{module}_logits;

    Uart_println("");
    Uart_println("=== Run {display_name} static image from flash ===");
    Uart_print("  Static input flash : 0x");
    print_hex_32({macro}_STATIC_INPUT_FLASH_OFFSET);
    Uart_print(", ");
    print_u32_dec({macro}_STATIC_INPUT_BYTES);
    Uart_println(" bytes");
    Uart_print("  Input HRAM1 addr   : ");
    print_u32_dec({macro}_INPUT_IFMAP_ADDR);
    Uart_println("");

    Uart_println("  Begin run context...");
    ok = begin_run_context(&context{begin_context_args});
    Uart_println(ok ? "  Run context OK." : "  Run context failed.");
    if (ok) {{
        ok = load_static_input_from_flash(&context);
    }}
    if (ok) {{
        Uart_println("  Running model...");
        ok = run_model_once(&context,
                            false,
                            {run_model_false_arg}
                            logits,
                            {macro}_FINAL_CHANNELS,
                            &conv_ticks,
                            &cpu_ticks,
                            &wall_ticks);
    }}

    if (ok) {{
        print_static_result(logits, {macro}_FINAL_CHANNELS);
        (void)check_static_intermediate_refs(&context);
        Uart_print("  Conv ticks         : ");
        print_tick_metric(conv_ticks);
        Uart_println("");
        Uart_print("  CPU fallback ticks : ");
        print_tick_metric(cpu_ticks);
        Uart_println("");
        Uart_print("  Wall ticks         : ");
        print_tick_metric(wall_ticks);
        Uart_println("");
    }}

    end_run_context({end_context_call});

    Uart_println(ok ? "{display_name} static image -> DONE" : "{display_name} static image -> FAIL");
    return ok;
}}
'''


def emit_source(
    path: Path,
    header_name: str,
    module: str,
    api_prefix: str,
    display_name: str,
    layers: List[ConvLayer],
    cpu_ops: List[CpuOp],
    execution_steps: List[ExecutionStep],
    param_bytes: int,
    activation_bytes: int,
    gap_enabled: bool,
    camera_config: Optional[CameraConfig],
    static_input: Optional[StaticInputConfig],
) -> None:
    macro = module.upper()
    type_prefix = snake_to_pascal(module)
    layer_table = ",\n".join(layer_initializer(layer) for layer in layers)
    max_cpu_inputs = max((len(op.input_views) for op in cpu_ops), default=1)
    cpu_table_len = max(1, len(cpu_ops))
    step_table_len = max(1, len(execution_steps))
    cpu_op_table = ",\n".join(cpu_op_initializer(op, max_cpu_inputs) for op in cpu_ops)
    if not cpu_op_table:
        cpu_op_table = (
            f"    {{ \"NoCpuOp\", CPU_OP_MAX_POOL_2D, 0U, "
            f"{{ {', '.join(['{ 0U, 0U, 0U, 0U, 0U }'] * max_cpu_inputs)} }}, "
            "{ 0U, 0U, 0U, 0U, 0U }, 1U, 1U, 1U, 1U, 0U, 0U, -128, 127 }"
        )
    step_table = ",\n".join(execution_step_initializer(step) for step in execution_steps)
    if not step_table:
        step_table = "    { EXEC_STEP_ACCEL_CONV, 0U }"
    max_cpu_input_channel_bytes = max(
        (view.height * view.row_stride for op in cpu_ops for view in op.input_views),
        default=1,
    )
    max_cpu_output_channel_bytes = max(
        (op.output_view.height * op.output_view.row_stride for op in cpu_ops),
        default=1,
    )
    hram_rw_buf_bytes = 510
    gap_code = "1U" if gap_enabled else "0U"
    video_include = '#include "VideoStreaming_Driver.h"\n' if camera_config is not None else ""
    static_include = '#include "flash_utils.h"\n' if static_input is not None else ""
    camera_decls = camera_source_decls(module, macro, camera_config)
    static_decls = static_input_source_decls(module, macro, static_input)
    camera_fields = camera_context_fields(camera_config)
    camera_begin = camera_begin_code(module, macro, camera_config)
    camera_end = camera_end_code(camera_config)
    begin_camera_param = ",\n                                            bool use_camera_ifmap" if camera_config is not None else ""
    end_context_param = f"const {type_prefix}_RunContext_t *context" if camera_config is not None else "void"
    end_context_call = "&context" if camera_config is not None else ""
    run_model_camera_param = "                                            bool use_camera_ifmap," if camera_config is not None else ""
    run_model_false_arg = "false," if camera_config is not None else ""
    camera_grant_before = """        if (use_camera_ifmap && (i == 0U)) {
            VideoStreaming_set_grant_request(&video_streaming, true);
        }
""" if camera_config is not None else ""
    camera_grant_after = """        if (use_camera_ifmap && (i == 0U)) {
            VideoStreaming_set_grant_request(&video_streaming, false);
        }
""" if camera_config is not None else ""
    camera_functions = camera_public_functions(
        module, macro, type_prefix, api_prefix, display_name, camera_config, gap_enabled
    )
    static_globals = static_input_global_decls(module, macro, type_prefix, static_input)
    static_functions = static_input_public_functions(
        module, macro, type_prefix, api_prefix, display_name, static_input, camera_config
    )

    source = f'''#include "{header_name}"

#include <stdint.h>

#include "CNN_Accel_Driver.h"
#include "HyperRAM_Driver.h"
#include "Interrupt_Driver.h"
#include "timer.h"
#include "UART_Driver.h"
{static_include}{video_include}#include "W95_HyperRAM.h"
#include "weight_hyperram_loader.h"

#define {macro}_SIZE_OPT __attribute__((noinline, optimize("Os")))

#define {macro}_LAYER_COUNT               {len(layers)}U
#define {macro}_CPU_OP_COUNT              {len(cpu_ops)}U
#define {macro}_CPU_OP_TABLE_LEN          {cpu_table_len}U
#define {macro}_EXEC_STEP_COUNT           {len(execution_steps)}U
#define {macro}_EXEC_STEP_TABLE_LEN       {step_table_len}U
#define {macro}_CPU_MAX_INPUTS            {max_cpu_inputs}U
#define {macro}_CPU_IN_CHANNEL_BYTES      {max_cpu_input_channel_bytes}U
#define {macro}_CPU_OUT_CHANNEL_BYTES     {max_cpu_output_channel_bytes}U
#define {macro}_HRAM_RW_BUF_BYTES         {hram_rw_buf_bytes}U
#define {macro}_HRAM_BLOCK_CHUNK_BYTES    510U
#define {macro}_CPU_PROGRESS_LOG          0U
#define {macro}_DMAC_WRITE_WEIGHT         1U
#define {macro}_DMAC_READ_WEIGHT          2U
#define {macro}_SUBMIT_WAIT_LIMIT         10000000U
#define {macro}_IRQ_WAIT_LIMIT            100000000U
#define {macro}_HRAM_DRAIN_WAIT_LIMIT     50000000U
#define {macro}_HRAM_CPU_WAIT_LIMIT       5000000U
#define {macro}_HRAM_DRAIN_STABLE_READS   128U
#define {macro}_PARAM_BYTES_RESERVED      {param_bytes}U
#define {macro}_ACTIVATION_BYTES_RESERVED {activation_bytes}U
#define {macro}_HAS_FINAL_GAP             {gap_code}
#define {macro}_FINAL_ROW_BYTES           {layers[-1].ofrow_stride}U
#define {macro}_LOWER_WRAP_MS             ((uint32_t)(0x100000000ULL / CYCLES_PER_MS))
#define {macro}_LOWER_WRAP_REM            ((uint32_t)(0x100000000ULL % CYCLES_PER_MS))
{camera_decls}
{static_decls}

typedef struct {{
    const char *name;
    uint8_t  ifheight;
    uint16_t ifchannel;
    uint16_t ofchannel;
    uint8_t  hf;
    uint8_t  stride;
    uint8_t  padding;
    uint8_t  ifparr;
    uint8_t  oftile;
    uint8_t  ofparr;
    uint32_t ifbaddr;
    uint32_t fltbaddr;
    uint32_t bias_baddr;
    uint32_t ofbaddr;
    uint16_t ifrow_stride;
    uint16_t ofrow_stride;
    int8_t   ifc_zp;
    int8_t   fltc_zp;
    int32_t  mult;
    uint8_t  mult_shift;
    int8_t   zpy;
    int8_t   qmin;
    int8_t   qmax;
    bool     is_leaky_relu;
}} {type_prefix}_Layer_t;

typedef enum {{
    CPU_OP_MAX_POOL_2D = 0,
    CPU_OP_CONCATENATION = 1
}} {type_prefix}_CpuOpKind_t;

typedef struct {{
    uint32_t addr;
    uint16_t height;
    uint16_t width;
    uint16_t channels;
    uint16_t row_stride;
}} {type_prefix}_TensorView_t;

typedef struct {{
    const char *name;
    {type_prefix}_CpuOpKind_t kind;
    uint8_t input_count;
    {type_prefix}_TensorView_t inputs[{macro}_CPU_MAX_INPUTS];
    {type_prefix}_TensorView_t output;
    uint8_t filter_h;
    uint8_t filter_w;
    uint8_t stride_h;
    uint8_t stride_w;
    uint8_t pad_top;
    uint8_t pad_left;
    int8_t qmin;
    int8_t qmax;
}} {type_prefix}_CpuOp_t;

typedef enum {{
    EXEC_STEP_ACCEL_CONV = 0,
    EXEC_STEP_CPU_OP = 1
}} {type_prefix}_ExecStepKind_t;

typedef struct {{
    {type_prefix}_ExecStepKind_t kind;
    uint16_t index;
}} {type_prefix}_ExecStep_t;

typedef struct {{
{camera_fields}
    W95_HandleTypeDef w95_h1_read;
    W95_HandleTypeDef w95_h1_write;
}} {type_prefix}_RunContext_t;

static const {type_prefix}_Layer_t s_{module}_layers[{macro}_LAYER_COUNT] = {{
{layer_table}
}};

static const {type_prefix}_CpuOp_t s_{module}_cpu_ops[{macro}_CPU_OP_TABLE_LEN] = {{
{cpu_op_table}
}};

static const {type_prefix}_ExecStep_t s_{module}_exec_steps[{macro}_EXEC_STEP_TABLE_LEN] = {{
{step_table}
}};

static volatile bool s_{module}_irq_seen;
static uint8_t s_{module}_gap_row[{macro}_FINAL_ROW_BYTES + 1U];
static uint8_t s_{module}_cpu_channel_in[{macro}_CPU_IN_CHANNEL_BYTES + 1U];
static uint8_t s_{module}_cpu_channel_out[{macro}_CPU_OUT_CHANNEL_BYTES + 1U];
static uint8_t s_{module}_hyperram_rw_buf[{macro}_HRAM_RW_BUF_BYTES];
static int32_t s_{module}_logits[{macro}_FINAL_CHANNELS];
{static_globals}static volatile int32_t s_{module}_gap_sink;

static {macro}_SIZE_OPT void print_u32_dec(uint32_t value)
{{
    char text[10];
    uint32_t pos = 0U;

    if (value == 0U) {{
        Uart_write('0');
        return;
    }}

    while ((value > 0U) && (pos < sizeof(text))) {{
        text[pos++] = (char)('0' + (value % 10U));
        value /= 10U;
    }}

    while (pos > 0U) {{
        Uart_write((uint8_t)text[--pos]);
    }}
}}

static {macro}_SIZE_OPT void print_i32_dec(int32_t value)
{{
    uint32_t magnitude;

    if (value < 0) {{
        Uart_write('-');
        magnitude = (uint32_t)(-(value + 1)) + 1U;
    }} else {{
        magnitude = (uint32_t)value;
    }}

    print_u32_dec(magnitude);
}}

static {macro}_SIZE_OPT tick_t ticks_elapsed(tick_t start, tick_t end)
{{
    tick_t diff;

    diff.lower = end.lower - start.lower;
    diff.upper = (end.upper - start.upper) & COUNTER_MAX_UPPER;
    if (end.lower < start.lower) {{
        diff.upper = (diff.upper - 1U) & COUNTER_MAX_UPPER;
    }}

    return diff;
}}

static {macro}_SIZE_OPT tick_t ticks_add(tick_t a, tick_t b)
{{
    tick_t sum;

    sum.lower = a.lower + b.lower;
    sum.upper = (a.upper + b.upper) & COUNTER_MAX_UPPER;
    if (sum.lower < a.lower) {{
        sum.upper = (sum.upper + 1U) & COUNTER_MAX_UPPER;
    }}

    return sum;
}}

static {macro}_SIZE_OPT uint32_t ticks_to_ms(tick_t ticks)
{{
    uint32_t ms = ticks.upper * {macro}_LOWER_WRAP_MS + ticks.lower / CYCLES_PER_MS;
    uint32_t rem = ticks.upper * {macro}_LOWER_WRAP_REM + ticks.lower % CYCLES_PER_MS;

    ms += rem / CYCLES_PER_MS;
    return ms;
}}

static {macro}_SIZE_OPT uint8_t tick_cycles_to_digits(tick_t ticks, uint8_t *digits, uint8_t max_digits)
{{
    uint8_t count = 0U;
    uint32_t upper = ticks.upper & COUNTER_MAX_UPPER;
    uint32_t lower = ticks.lower;

    do {{
        uint32_t q_upper = upper / 10U;
        uint32_t upper_rem = upper - q_upper * 10U;
        uint32_t q_lower = lower / 10U;
        uint32_t digit = lower - q_lower * 10U;

        for (uint32_t i = 0U; i < upper_rem; i++) {{
            q_lower += 429496729U;
            digit += 6U;
            if (digit >= 10U) {{
                digit -= 10U;
                q_lower++;
            }}
        }}

        digits[count++] = (uint8_t)digit;
        upper = q_upper;
        lower = q_lower;
    }} while (((upper != 0U) || (lower != 0U)) && (count < max_digits));

    return count;
}}

static {macro}_SIZE_OPT void print_tick_cycles(tick_t ticks)
{{
    uint8_t digits[20];
    uint8_t count = tick_cycles_to_digits(ticks, digits, sizeof(digits));

    while (count > 0U) {{
        Uart_write((uint8_t)('0' + digits[--count]));
    }}
}}

static {macro}_SIZE_OPT void print_tick_metric(tick_t ticks)
{{
    print_tick_cycles(ticks);
    Uart_print(" cycles (");
    print_u32_dec(ticks_to_ms(ticks));
    Uart_print(" ms)");
}}

static {macro}_SIZE_OPT uint32_t ticks_to_u32_saturated(tick_t ticks)
{{
    return (ticks.upper != 0U) ? 0xFFFFFFFFU : ticks.lower;
}}

static {macro}_SIZE_OPT void print_cycles_per_unit(tick_t ticks, uint32_t units)
{{
    uint32_t cycles;

    if (units == 0U) {{
        Uart_print("n/a");
        return;
    }}

    if (ticks.upper != 0U) {{
        Uart_write('>');
    }}
    cycles = ticks_to_u32_saturated(ticks);
    print_u32_dec((cycles + (units >> 1U)) / units);
}}

static {macro}_SIZE_OPT void print_hex_32(uint32_t value)
{{
    static const char hex[] = "0123456789ABCDEF";

    for (int8_t shift = 28; shift >= 0; shift -= 4) {{
        Uart_write((uint8_t)hex[(value >> (uint32_t)shift) & 0x0FU]);
    }}
}}

static {macro}_SIZE_OPT void copy_u8_no_libcall(uint8_t *dst,
                                                const uint8_t *src,
                                                uint32_t size)
{{
    volatile uint8_t *vdst = (volatile uint8_t *)dst;
    const volatile uint8_t *vsrc = (const volatile uint8_t *)src;

    for (uint32_t i = 0U; i < size; i++) {{
        vdst[i] = vsrc[i];
    }}
}}

static {macro}_SIZE_OPT uint32_t layer_ofwidth(const {type_prefix}_Layer_t *layer)
{{
    uint32_t padded = (uint32_t)layer->ifheight + ((uint32_t)layer->padding << 1U);
    uint32_t span = (padded >= layer->hf) ? (padded - (uint32_t)layer->hf) : 0U;

    return (span / (uint32_t)layer->stride) + 1U;
}}

static {macro}_SIZE_OPT uint32_t layer_ofmap_bytes(const {type_prefix}_Layer_t *layer)
{{
    uint32_t ofwidth = layer_ofwidth(layer);

    return ofwidth * ofwidth * (uint32_t)layer->ofchannel;
}}

static {macro}_SIZE_OPT uint32_t layer_ofmap_storage_bytes(const {type_prefix}_Layer_t *layer)
{{
    uint32_t ofwidth = layer_ofwidth(layer);

    return (uint32_t)layer->ofchannel * ofwidth * (uint32_t)layer->ofrow_stride;
}}

static {macro}_SIZE_OPT uint32_t layer_macs(const {type_prefix}_Layer_t *layer)
{{
    return layer_ofmap_bytes(layer) *
           (uint32_t)layer->ifchannel *
           (uint32_t)layer->hf *
           (uint32_t)layer->hf;
}}

static {macro}_SIZE_OPT uint32_t total_conv_macs(void)
{{
    uint32_t total = 0U;

    for (uint32_t i = 0U; i < {macro}_LAYER_COUNT; i++) {{
        total += layer_macs(&s_{module}_layers[i]);
    }}

    return total;
}}

static {macro}_SIZE_OPT void print_cnn_status(const char *prefix, uint32_t status)
{{
    Uart_print(prefix);
    Uart_print(" STATUS=0x");
    print_hex_32(status);
    Uart_print(" busy=");
    Uart_write((status & CNN_ACCEL_STATUS_BUSY_Msk) != 0U ? '1' : '0');
    Uart_print(" done=");
    Uart_write((status & CNN_ACCEL_STATUS_DONE_Msk) != 0U ? '1' : '0');
    Uart_print(" table_rdy=");
    Uart_write((status & CNN_ACCEL_STATUS_TABLE_READY_Msk) != 0U ? '1' : '0');
    Uart_println("");
}}

static {macro}_SIZE_OPT void print_hyperram_status(const char *name, HyperRAM_Driver_t *drv)
{{
    uint32_t mode = HyperRAM_read_mode_register(drv);
    uint32_t status = *drv->reg_status;

    Uart_print("  ");
    Uart_print(name);
    Uart_print(" mode=0x");
    print_hex_32(mode);
    Uart_print(" status=0x");
    print_hex_32(status);
    Uart_println("");
}}

static {macro}_SIZE_OPT bool wait_hyperram_master_idle(const char *name, HyperRAM_Driver_t *drv)
{{
    uint32_t wait = {macro}_HRAM_DRAIN_WAIT_LIMIT;
    uint32_t stable = 0U;

    while (wait > 0U) {{
        if (HyperRAM_is_start_ready(drv)) {{
            stable++;
            if (stable >= {macro}_HRAM_DRAIN_STABLE_READS) {{
                return true;
            }}
        }} else {{
            stable = 0U;
        }}
        wait--;
    }}

    Uart_print("  ");
    Uart_print(name);
    Uart_println(" drain timeout.");
    print_hyperram_status(name, drv);
    return false;
}}

static {macro}_SIZE_OPT bool wait_hyperram_start_ready(const char *name, HyperRAM_Driver_t *drv)
{{
    uint32_t wait = {macro}_HRAM_CPU_WAIT_LIMIT;

    while (wait > 0U) {{
        if (HyperRAM_is_start_ready(drv)) {{
            return true;
        }}
        wait--;
    }}

    Uart_print("  ");
    Uart_print(name);
    Uart_println(" start-ready timeout.");
    print_hyperram_status(name, drv);
    return false;
}}

static {macro}_SIZE_OPT bool hram_write_byte_checked(const char *name,
                                                     HyperRAM_Driver_t *drv,
                                                     uint8_t data)
{{
    uint32_t wait = {macro}_HRAM_CPU_WAIT_LIMIT;

    while (HyperRAM_is_full(drv)) {{
        if (wait == 0U) {{
            Uart_print("  ");
            Uart_print(name);
            Uart_println(" write FIFO timeout.");
            print_hyperram_status(name, drv);
            return false;
        }}
        wait--;
    }}

    HyperRAM_write_byte(drv, data);
    return true;
}}

static {macro}_SIZE_OPT bool hram_read_byte_checked(const char *name,
                                                    HyperRAM_Driver_t *drv,
                                                    uint8_t *data)
{{
    uint32_t wait = {macro}_HRAM_CPU_WAIT_LIMIT;

    while (HyperRAM_is_empty(drv)) {{
        if (wait == 0U) {{
            Uart_print("  ");
            Uart_print(name);
            Uart_println(" read FIFO timeout.");
            print_hyperram_status(name, drv);
            return false;
        }}
        wait--;
    }}

    *data = HyperRAM_read_byte(drv);
    return true;
}}

static {macro}_SIZE_OPT bool hram_burst_write_checked(const char *name,
                                                      HyperRAM_Driver_t *drv,
                                                      const uint8_t *src,
                                                      uint32_t size)
{{
    for (uint32_t i = 0U; i < size; i++) {{
        if (!hram_write_byte_checked(name, drv, src[i])) {{
            return false;
        }}
    }}
    return true;
}}

static {macro}_SIZE_OPT bool hram_burst_read_checked(const char *name,
                                                     HyperRAM_Driver_t *drv,
                                                     uint8_t *dst,
                                                     uint32_t size)
{{
    for (uint32_t i = 0U; i < size; i++) {{
        if (!hram_read_byte_checked(name, drv, &dst[i])) {{
            return false;
        }}
    }}
    return true;
}}

static {macro}_SIZE_OPT bool hram_read_aligned(W95_HandleTypeDef *w95,
                                               uint32_t addr,
                                               uint8_t *dst,
                                               uint32_t size)
{{
    if (((addr & 1U) != 0U) || ((size & 1U) != 0U) || (size == 0U) || ((size / 2U) > 255U)) {{
        return false;
    }}

    HyperRAM_set_config(w95->hram_port,
                        w95->capture_shmoo,
                        w95->recovery,
                        w95->latency,
                        (uint8_t)(size / 2U));
    if (!wait_hyperram_start_ready("HRAM read", w95->hram_port)) {{
        return false;
    }}
    if (!W95_SetMemoryCommandAddress(w95->hram_port, addr, W95_CMD_MEM_READ_LINEAR)) {{
        Uart_println("  HRAM read address setup failed.");
        return false;
    }}
    HyperRAM_start(w95->hram_port);
    return hram_burst_read_checked("HRAM read", w95->hram_port, dst, size);
}}

static {macro}_SIZE_OPT bool hram_write_aligned(W95_HandleTypeDef *w95,
                                                uint32_t addr,
                                                const uint8_t *src,
                                                uint32_t size)
{{
    if (((addr & 1U) != 0U) || ((size & 1U) != 0U) || (size == 0U) || ((size / 2U) > 255U)) {{
        return false;
    }}

    HyperRAM_set_config(w95->hram_port,
                        w95->capture_shmoo,
                        w95->recovery,
                        w95->latency,
                        (uint8_t)(size / 2U));
    if (!wait_hyperram_start_ready("HRAM write", w95->hram_port)) {{
        return false;
    }}
    if (!W95_SetMemoryCommandAddress(w95->hram_port, addr, W95_CMD_MEM_WRITE_LINEAR)) {{
        Uart_println("  HRAM write address setup failed.");
        return false;
    }}
    if (!hram_burst_write_checked("HRAM write", w95->hram_port, src, size)) {{
        return false;
    }}
    HyperRAM_start(w95->hram_port);
    return true;
}}

static {macro}_SIZE_OPT bool hram_read_any(W95_HandleTypeDef *w95,
                                           uint32_t addr,
                                           uint8_t *dst,
                                           uint32_t size)
{{
    uint32_t offset = addr & 1U;
    uint32_t aligned_addr = addr & ~1U;
    uint32_t aligned_size = (offset + size + 1U) & ~1U;

    if ((size == 0U) || (aligned_size > {macro}_HRAM_RW_BUF_BYTES)) {{
        return false;
    }}

    if (!hram_read_aligned(w95, aligned_addr, s_{module}_hyperram_rw_buf, aligned_size)) {{
        return false;
    }}

    copy_u8_no_libcall(dst, &s_{module}_hyperram_rw_buf[offset], size);
    return true;
}}

static {macro}_SIZE_OPT bool hram_write_any(W95_HandleTypeDef *w95,
                                            uint32_t addr,
                                            const uint8_t *src,
                                            uint32_t size)
{{
    uint32_t offset = addr & 1U;
    uint32_t aligned_addr = addr & ~1U;
    uint32_t aligned_size = (offset + size + 1U) & ~1U;

    if ((size == 0U) || (aligned_size > {macro}_HRAM_RW_BUF_BYTES)) {{
        return false;
    }}

    if ((offset != 0U) || ((size & 1U) != 0U)) {{
        if (!hram_read_aligned(w95, aligned_addr, s_{module}_hyperram_rw_buf, aligned_size)) {{
            return false;
        }}
    }}

    copy_u8_no_libcall(&s_{module}_hyperram_rw_buf[offset], src, size);
    return hram_write_aligned(w95, aligned_addr, s_{module}_hyperram_rw_buf, aligned_size);
}}

static {macro}_SIZE_OPT bool hram_read_block_any(W95_HandleTypeDef *w95,
                                                 uint32_t addr,
                                                 uint8_t *dst,
                                                 uint32_t size)
{{
    uint32_t done = 0U;

    while (done < size) {{
        uint32_t chunk = size - done;

        if (chunk > {macro}_HRAM_BLOCK_CHUNK_BYTES) {{
            chunk = {macro}_HRAM_BLOCK_CHUNK_BYTES;
        }}
        if (!hram_read_any(w95, addr + done, &dst[done], chunk)) {{
            return false;
        }}
        done += chunk;
    }}

    return true;
}}

static {macro}_SIZE_OPT bool hram_write_block_any(W95_HandleTypeDef *w95,
                                                  uint32_t addr,
                                                  const uint8_t *src,
                                                  uint32_t size)
{{
    uint32_t done = 0U;

    while (done < size) {{
        uint32_t chunk = size - done;

        if (chunk > {macro}_HRAM_BLOCK_CHUNK_BYTES) {{
            chunk = {macro}_HRAM_BLOCK_CHUNK_BYTES;
        }}
        if (!hram_write_any(w95, addr + done, &src[done], chunk)) {{
            return false;
        }}
        done += chunk;
    }}

    return true;
}}

static void {module}_irq_handler(uint32_t irq_bit, void *context)
{{
    (void)irq_bit;
    (void)context;
    s_{module}_irq_seen = true;
}}

static {macro}_SIZE_OPT void fill_layer_config(const {type_prefix}_Layer_t *layer,
                                               CNN_Accel_LayerConfig_t *config)
{{
    config->ifheight = layer->ifheight;
    config->ifchannel = layer->ifchannel;
    config->ofchannel = layer->ofchannel;
    config->hf = layer->hf;
    config->stride = layer->stride;
    config->padding = layer->padding;
    config->ifparr = layer->ifparr;
    config->oftile = layer->oftile;
    config->ofparr = layer->ofparr;
    config->ifbaddr = layer->ifbaddr;
    config->fltbaddr = layer->fltbaddr;
    config->bias_baddr = layer->bias_baddr;
    config->ofbaddr = layer->ofbaddr;
    config->ifc_zp = layer->ifc_zp;
    config->fltc_zp = layer->fltc_zp;
    config->mult = layer->mult;
    config->mult_shift = layer->mult_shift;
    config->alphamult = layer->is_leaky_relu ? 1 : 0;
    config->alphamult_shift = 0U;
    config->zpy = layer->zpy;
    config->qmin = layer->qmin;
    config->qmax = layer->qmax;
    config->is_leaky_relu = layer->is_leaky_relu;
}}

static {macro}_SIZE_OPT void print_layer_config(const {type_prefix}_Layer_t *layer)
{{
    Uart_print("      cfg k/s/p    : ");
    print_u32_dec(layer->hf);
    Uart_write('/');
    print_u32_dec(layer->stride);
    Uart_write('/');
    print_u32_dec(layer->padding);
    Uart_print("  Nip/Npass/Nfp=");
    print_u32_dec(layer->ifparr);
    Uart_write('/');
    print_u32_dec(layer->oftile);
    Uart_write('/');
    print_u32_dec(layer->ofparr);
    Uart_println("");
    Uart_print("      addr if/flt/bias/of: ");
    print_u32_dec(layer->ifbaddr);
    Uart_write('/');
    print_u32_dec(layer->fltbaddr);
    Uart_write('/');
    print_u32_dec(layer->bias_baddr);
    Uart_write('/');
    print_u32_dec(layer->ofbaddr);
    Uart_println("");
    Uart_print("      row stride if/of : ");
    print_u32_dec(layer->ifrow_stride);
    Uart_write('/');
    print_u32_dec(layer->ofrow_stride);
    Uart_println("");
}}

static {macro}_SIZE_OPT bool run_layer(uint8_t idx,
                                       const {type_prefix}_Layer_t *layer,
                                       bool verbose,
                                       tick_t *elapsed)
{{
    CNN_Accel_LayerConfig_t config;
    tick_t start_tick;
    tick_t end_tick;
    uint32_t wait = {macro}_IRQ_WAIT_LIMIT;
    uint32_t status;
    bool done_seen = false;

    fill_layer_config(layer, &config);
    s_{module}_irq_seen = false;

    if (verbose) {{
        Uart_print("  Layer ");
        print_u32_dec((uint32_t)idx + 1U);
        Uart_write(' ');
        Uart_print(layer->name);
        Uart_print(": ");
        print_u32_dec(layer->ifheight);
        Uart_write('x');
        print_u32_dec(layer->ifheight);
        Uart_write('x');
        print_u32_dec(layer->ifchannel);
        Uart_print(" -> ");
        print_u32_dec(layer_ofwidth(layer));
        Uart_write('x');
        print_u32_dec(layer_ofwidth(layer));
        Uart_write('x');
        print_u32_dec(layer->ofchannel);
        Uart_println("");
        print_layer_config(layer);
    }}

    status = CNN_Accel_get_status(&cnn_accel);
    if ((status & CNN_ACCEL_STATUS_BUSY_Msk) != 0U) {{
        print_cnn_status("    CNN busy before layer:", status);
        return false;
    }}

    start_tick = read_tick();

    if (!CNN_Accel_submit_layer_config(&cnn_accel, &config, {macro}_SUBMIT_WAIT_LIMIT)) {{
        print_cnn_status("    submit timeout:", CNN_Accel_get_status(&cnn_accel));
        return false;
    }}

    CNN_Accel_start(&cnn_accel);

    while (wait > 0U) {{
        status = CNN_Accel_get_status(&cnn_accel);
        if (s_{module}_irq_seen || ((status & CNN_ACCEL_STATUS_DONE_Msk) != 0U)) {{
            done_seen = true;
            break;
        }}
        wait--;
    }}

    status = CNN_Accel_get_status(&cnn_accel);
    if ((status & CNN_ACCEL_STATUS_DONE_Msk) != 0U) {{
        done_seen = true;
    }}

    if (!done_seen) {{
        print_cnn_status("    IRQ timeout:", status);
        print_hyperram_status("HR0", &hyperram0);
        print_hyperram_status("HR1", &hyperram1);
        return false;
    }}

    if (!CNN_Accel_wait_idle(&cnn_accel, {macro}_SUBMIT_WAIT_LIMIT)) {{
        print_cnn_status("    idle timeout:", CNN_Accel_get_status(&cnn_accel));
        return false;
    }}

    if (!wait_hyperram_master_idle("HR1", &hyperram1)) {{
        return false;
    }}

    end_tick = read_tick();
    *elapsed = ticks_elapsed(start_tick, end_tick);
    return true;
}}

static {macro}_SIZE_OPT void print_layer_profile(const {type_prefix}_Layer_t *layer, tick_t ticks)
{{
    uint32_t macs = layer_macs(layer);

    Uart_println("    finished:");
    Uart_print("      Time         : ");
    print_tick_metric(ticks);
    Uart_println("");
    Uart_print("      Workload     : ");
    print_u32_dec(macs);
    Uart_println(" MACs");
    Uart_print("      Output bytes : ");
    print_u32_dec(layer_ofmap_bytes(layer));
    Uart_println("");
    Uart_print("      Cost         : ");
    print_cycles_per_unit(ticks, macs / 1000U);
    Uart_println(" cycles / 1000 MACs");
}}

static {macro}_SIZE_OPT uint32_t tensor_channel_bytes(const {type_prefix}_TensorView_t *view)
{{
    return (uint32_t)view->height * (uint32_t)view->row_stride;
}}

static {macro}_SIZE_OPT void clear_u8_buffer(uint8_t *dst, uint32_t size)
{{
    for (uint32_t i = 0U; i < size; i++) {{
        dst[i] = 0U;
    }}
}}

static {macro}_SIZE_OPT int8_t clamp_i8(int32_t value, int8_t qmin, int8_t qmax)
{{
    if (value < (int32_t)qmin) {{
        return qmin;
    }}
    if (value > (int32_t)qmax) {{
        return qmax;
    }}
    return (int8_t)value;
}}

static {macro}_SIZE_OPT bool run_cpu_maxpool(W95_HandleTypeDef *w95_read,
                                             W95_HandleTypeDef *w95_write,
                                             const {type_prefix}_CpuOp_t *op,
                                             bool verbose)
{{
    const {type_prefix}_TensorView_t *input = &op->inputs[0];
    const {type_prefix}_TensorView_t *output = &op->output;
    uint32_t in_channel_bytes = tensor_channel_bytes(input);
    uint32_t out_channel_bytes = tensor_channel_bytes(output);

    if ((in_channel_bytes > {macro}_CPU_IN_CHANNEL_BYTES) ||
        (out_channel_bytes > {macro}_CPU_OUT_CHANNEL_BYTES)) {{
        return false;
    }}

    for (uint32_t c = 0U; c < input->channels; c++) {{
        uint32_t in_ch_base = input->addr + c * in_channel_bytes;
        uint32_t out_ch_base = output->addr + c * out_channel_bytes;

        if (verbose && ({macro}_CPU_PROGRESS_LOG != 0U) &&
            (((c & 7U) == 0U) || ((c + 1U) == input->channels))) {{
            Uart_print("    channel ");
            print_u32_dec(c + 1U);
            Uart_write('/');
            print_u32_dec(input->channels);
            Uart_println("");
        }}

        if (!hram_read_block_any(w95_read, in_ch_base, s_{module}_cpu_channel_in, in_channel_bytes)) {{
            Uart_print("    MaxPool HRAM read failed at channel ");
            print_u32_dec(c + 1U);
            Uart_println("");
            return false;
        }}

        clear_u8_buffer(s_{module}_cpu_channel_out, out_channel_bytes);
        for (uint32_t oy = 0U; oy < output->height; oy++) {{
            uint32_t out_row_base = oy * (uint32_t)output->row_stride;

            for (uint32_t ox = 0U; ox < output->width; ox++) {{
                int8_t max_value = (int8_t)-128;
                bool seen = false;

                for (uint32_t ky = 0U; ky < op->filter_h; ky++) {{
                    int32_t iy = (int32_t)(oy * (uint32_t)op->stride_h + ky) - (int32_t)op->pad_top;

                    if ((iy < 0) || ((uint32_t)iy >= input->height)) {{
                        continue;
                    }}

                    for (uint32_t kx = 0U; kx < op->filter_w; kx++) {{
                        int32_t ix = (int32_t)(ox * (uint32_t)op->stride_w + kx) - (int32_t)op->pad_left;
                        int8_t value;

                        if ((ix < 0) || ((uint32_t)ix >= input->width)) {{
                            continue;
                        }}

                        value = (int8_t)s_{module}_cpu_channel_in[(uint32_t)iy * (uint32_t)input->row_stride + (uint32_t)ix];
                        if ((!seen) || (value > max_value)) {{
                            max_value = value;
                            seen = true;
                        }}
                    }}
                }}

                if (!seen) {{
                    max_value = (int8_t)-128;
                }}
                s_{module}_cpu_channel_out[out_row_base + ox] = (uint8_t)clamp_i8(max_value, op->qmin, op->qmax);
            }}
        }}

        if (!hram_write_block_any(w95_write, out_ch_base, s_{module}_cpu_channel_out, out_channel_bytes)) {{
            Uart_print("    MaxPool HRAM write failed at channel ");
            print_u32_dec(c + 1U);
            Uart_println("");
            return false;
        }}
    }}

    return true;
}}

static {macro}_SIZE_OPT bool run_cpu_concat(W95_HandleTypeDef *w95_read,
                                            W95_HandleTypeDef *w95_write,
                                            const {type_prefix}_CpuOp_t *op,
                                            bool verbose)
{{
    const {type_prefix}_TensorView_t *output = &op->output;
    uint32_t out_channel_bytes = tensor_channel_bytes(output);
    uint32_t out_channel = 0U;

    if (out_channel_bytes > {macro}_CPU_OUT_CHANNEL_BYTES) {{
        return false;
    }}

    for (uint32_t input_idx = 0U; input_idx < op->input_count; input_idx++) {{
        const {type_prefix}_TensorView_t *input = &op->inputs[input_idx];
        uint32_t in_channel_bytes = tensor_channel_bytes(input);

        if (in_channel_bytes > {macro}_CPU_IN_CHANNEL_BYTES) {{
            return false;
        }}

        for (uint32_t c = 0U; c < input->channels; c++) {{
            uint32_t in_ch_base = input->addr + c * in_channel_bytes;
            uint32_t out_ch_base = output->addr + out_channel * out_channel_bytes;

            if (verbose && ({macro}_CPU_PROGRESS_LOG != 0U) &&
                (((out_channel & 31U) == 0U) || ((out_channel + 1U) == output->channels))) {{
                Uart_print("    concat channel ");
                print_u32_dec(out_channel + 1U);
                Uart_write('/');
                print_u32_dec(output->channels);
                Uart_println("");
            }}

            if (!hram_read_block_any(w95_read, in_ch_base, s_{module}_cpu_channel_in, in_channel_bytes)) {{
                Uart_print("    Concat HRAM read failed at channel ");
                print_u32_dec(out_channel + 1U);
                Uart_println("");
                return false;
            }}

            if ((input->height == output->height) &&
                (input->width == output->width) &&
                (input->row_stride == output->row_stride)) {{
                if (!hram_write_block_any(w95_write, out_ch_base, s_{module}_cpu_channel_in, in_channel_bytes)) {{
                    Uart_print("    Concat HRAM write failed at channel ");
                    print_u32_dec(out_channel + 1U);
                    Uart_println("");
                    return false;
                }}
            }} else {{
                clear_u8_buffer(s_{module}_cpu_channel_out, out_channel_bytes);
                for (uint32_t y = 0U; y < input->height && y < output->height; y++) {{
                    copy_u8_no_libcall(&s_{module}_cpu_channel_out[y * (uint32_t)output->row_stride],
                                       &s_{module}_cpu_channel_in[y * (uint32_t)input->row_stride],
                                       (input->width < output->width) ? input->width : output->width);
                }}
                if (!hram_write_block_any(w95_write, out_ch_base, s_{module}_cpu_channel_out, out_channel_bytes)) {{
                    Uart_print("    Concat HRAM write failed at channel ");
                    print_u32_dec(out_channel + 1U);
                    Uart_println("");
                    return false;
                }}
            }}

            out_channel++;
        }}
    }}

    return out_channel == output->channels;
}}

static {macro}_SIZE_OPT bool run_cpu_op({type_prefix}_RunContext_t *context,
                                        uint8_t idx,
                                        const {type_prefix}_CpuOp_t *op,
                                        bool verbose,
                                        tick_t *elapsed)
{{
    tick_t start_tick;
    tick_t end_tick;
    bool ok = false;

    if (verbose) {{
        Uart_print("  CPU ");
        Uart_print(op->name);
        Uart_print(": ");
        print_u32_dec(op->output.height);
        Uart_write('x');
        print_u32_dec(op->output.width);
        Uart_write('x');
        print_u32_dec(op->output.channels);
        Uart_println("");
        (void)idx;
    }}

    start_tick = read_tick();
    if (op->kind == CPU_OP_MAX_POOL_2D) {{
        ok = run_cpu_maxpool(&context->w95_h1_read, &context->w95_h1_write, op, verbose);
    }} else if (op->kind == CPU_OP_CONCATENATION) {{
        ok = run_cpu_concat(&context->w95_h1_read, &context->w95_h1_write, op, verbose);
    }}
    end_tick = read_tick();
    *elapsed = ticks_elapsed(start_tick, end_tick);

    if (verbose && ok) {{
        Uart_println("    finished:");
        Uart_print("      Time         : ");
        print_tick_metric(*elapsed);
        Uart_println("");
        Uart_print("      Output bytes : ");
        print_u32_dec(tensor_channel_bytes(&op->output) * (uint32_t)op->output.channels);
        Uart_println("");
    }}

    return ok;
}}

static {macro}_SIZE_OPT bool run_global_avgpool(W95_HandleTypeDef *w95_read,
                                                const {type_prefix}_Layer_t *layer,
                                                bool verbose,
                                                int32_t *logits_out,
                                                uint32_t logits_count,
                                                tick_t *elapsed)
{{
    tick_t start_tick;
    tick_t end_tick;
    uint32_t h = layer_ofwidth(layer);
    uint32_t ch_bytes = h * h;
    uint32_t ch_stride = h * (uint32_t)layer->ofrow_stride;
    int32_t sink = 0;

    if ({macro}_HAS_FINAL_GAP == 0U) {{
        elapsed->lower = 0U;
        elapsed->upper = 0U;
        return true;
    }}
    if ((logits_out == 0) || (logits_count < (uint32_t)layer->ofchannel) || (h > {macro}_FINAL_ROW_BYTES)) {{
        return false;
    }}

    if (verbose) {{
        Uart_print("  CPU GlobalAvgPool: ");
        print_u32_dec(h);
        Uart_write('x');
        print_u32_dec(h);
        Uart_write('x');
        print_u32_dec(layer->ofchannel);
        Uart_print(" -> ");
        print_u32_dec(layer->ofchannel);
        Uart_println(" logits");
    }}

    start_tick = read_tick();

    for (uint32_t c = 0U; c < layer->ofchannel; c++) {{
        int32_t sum = 0;
        uint32_t ch_base = layer->ofbaddr + c * ch_stride;

        for (uint32_t y = 0U; y < h; y++) {{
            if (!hram_read_block_any(w95_read,
                                     ch_base + y * (uint32_t)layer->ofrow_stride,
                                     s_{module}_gap_row,
                                     layer->ofrow_stride)) {{
                return false;
            }}
            for (uint32_t x = 0U; x < h; x++) {{
                sum += (int32_t)(int8_t)s_{module}_gap_row[x] - (int32_t)layer->zpy;
            }}
        }}
        sum /= (int32_t)ch_bytes;
        logits_out[c] = sum;
        sink += sum;
    }}

    s_{module}_gap_sink = sink;
    end_tick = read_tick();
    *elapsed = ticks_elapsed(start_tick, end_tick);

    if (verbose) {{
        Uart_println("    finished:");
        Uart_print("      Time         : ");
        print_tick_metric(*elapsed);
        Uart_println("");
        Uart_print("      Read bytes   : ");
        print_u32_dec(ch_bytes * (uint32_t)layer->ofchannel);
        Uart_println("");
    }}
    return true;
}}

static {macro}_SIZE_OPT bool begin_run_context({type_prefix}_RunContext_t *context{begin_camera_param})
{{
    CNN_Accel_begin();
    HyperRAM_init(&hyperram0, HYPERRAM_0_BASE_ADDR);
    HyperRAM_init(&hyperram1, HYPERRAM_1_BASE_ADDR);
    HyperRAM_set_accel_mode(&hyperram0, false);
    HyperRAM_set_accel_mode(&hyperram1, false);
    W95_Init(&context->w95_h1_read,
             &hyperram1,
             WEIGHT_HYPERRAM1_READ_LATENCY,
             WEIGHT_HYPERRAM1_READ_RECOVERY,
             WEIGHT_HYPERRAM1_READ_CAPTURE_SHMOO);
    W95_Init(&context->w95_h1_write,
             &hyperram1,
             WEIGHT_HYPERRAM1_WRITE_LATENCY,
             WEIGHT_HYPERRAM1_WRITE_RECOVERY,
             WEIGHT_HYPERRAM1_WRITE_CAPTURE_SHMOO);
{camera_begin}

    if (!CNN_Accel_attach_irq({module}_irq_handler, 0, IRQ_PRIORITY_DEFAULT)) {{
        Uart_println("  CNN IRQ attach failed.");
        return false;
    }}

    CNN_Accel_enable_irq();
    HyperRAM_set_dmac_weights(&hyperram0, {macro}_DMAC_WRITE_WEIGHT, {macro}_DMAC_READ_WEIGHT);
    HyperRAM_set_dmac_weights(&hyperram1, {macro}_DMAC_WRITE_WEIGHT, {macro}_DMAC_READ_WEIGHT);
    return true;
}}

static {macro}_SIZE_OPT void end_run_context({end_context_param})
{{
    CNN_Accel_disable_irq();
    HyperRAM_set_accel_mode(&hyperram0, false);
    HyperRAM_set_accel_mode(&hyperram1, false);
{camera_end}
}}

static {macro}_SIZE_OPT bool run_model_once({type_prefix}_RunContext_t *context,
                                            bool verbose,
{run_model_camera_param}
                                            int32_t *logits_out,
                                            uint32_t logits_count,
                                            tick_t *conv_ticks,
                                            tick_t *cpu_ticks,
                                            tick_t *wall_ticks)
{{
    bool ok = true;
    tick_t wall_start;

    conv_ticks->lower = 0U;
    conv_ticks->upper = 0U;
    cpu_ticks->lower = 0U;
    cpu_ticks->upper = 0U;
    wall_ticks->lower = 0U;
    wall_ticks->upper = 0U;

    HyperRAM_set_accel_mode(&hyperram0, true);
    HyperRAM_set_accel_mode(&hyperram1, true);
    wall_start = read_tick();

    for (uint16_t step_idx = 0U; ok && (step_idx < {macro}_EXEC_STEP_COUNT); step_idx++) {{
        const {type_prefix}_ExecStep_t *step = &s_{module}_exec_steps[step_idx];
        tick_t elapsed;

        if (step->kind == EXEC_STEP_ACCEL_CONV) {{
            uint8_t layer_idx = (uint8_t)step->index;

            HyperRAM_set_accel_mode(&hyperram0, true);
            HyperRAM_set_accel_mode(&hyperram1, true);
{camera_grant_before.replace('i == 0U', 'layer_idx == 0U').replace('i)', 'layer_idx)')}
            ok = run_layer(layer_idx, &s_{module}_layers[layer_idx], verbose, &elapsed);
{camera_grant_after.replace('i == 0U', 'layer_idx == 0U').replace('i)', 'layer_idx)')}
            HyperRAM_set_accel_mode(&hyperram0, false);
            HyperRAM_set_accel_mode(&hyperram1, false);
            if (ok) {{
                *conv_ticks = ticks_add(*conv_ticks, elapsed);
                if (verbose) {{
                    print_layer_profile(&s_{module}_layers[layer_idx], elapsed);
                }}
            }}
        }} else if (step->kind == EXEC_STEP_CPU_OP) {{
            uint8_t cpu_idx = (uint8_t)step->index;

            HyperRAM_set_accel_mode(&hyperram0, false);
            HyperRAM_set_accel_mode(&hyperram1, false);
            ok = run_cpu_op(context, cpu_idx, &s_{module}_cpu_ops[cpu_idx], verbose, &elapsed);
            if (ok) {{
                *cpu_ticks = ticks_add(*cpu_ticks, elapsed);
            }} else {{
                Uart_println("    CPU fallback op failed.");
            }}
        }}
    }}

    if (ok) {{
        tick_t elapsed;

        ok = run_global_avgpool(&context->w95_h1_read,
                                &s_{module}_layers[{macro}_LAYER_COUNT - 1U],
                                verbose,
                                logits_out,
                                logits_count,
                                &elapsed);
        if (ok) {{
            *cpu_ticks = ticks_add(*cpu_ticks, elapsed);
        }} else {{
            Uart_println("    GlobalAvgPool failed.");
        }}
    }}

    if (ok) {{
        *wall_ticks = ticks_elapsed(wall_start, read_tick());
    }}

    return ok;
}}

bool {api_prefix}_Accel_RunTimingOnly(void)
{{
    bool ok;
    {type_prefix}_RunContext_t context;
    tick_t conv_ticks = {{0U, 0U}};
    tick_t cpu_ticks = {{0U, 0U}};
    tick_t wall_ticks = {{0U, 0U}};
    tick_t measured_ticks;
    uint32_t conv_macs = total_conv_macs();
    int32_t *logits = s_{module}_logits;

    Uart_println("");
    Uart_println("=== Run {display_name} accelerator timing ===");
    Uart_println("Prepared-input path: load IFMAP in HyperRAM1 and packed params in HyperRAM0 before running.");
    Uart_print("  Conv layers              : ");
    print_u32_dec({macro}_LAYER_COUNT);
    Uart_println("");
    Uart_print("  HR0 filter/bias reserved : ");
    print_u32_dec({macro}_PARAM_BYTES_RESERVED);
    Uart_println(" bytes");
    Uart_print("  HR1 activation reserved  : ");
    print_u32_dec({macro}_ACTIVATION_BYTES_RESERVED);
    Uart_println(" bytes");
    Uart_print("  Conv workload            : ");
    print_u32_dec(conv_macs);
    Uart_println(" MACs");

    ok = begin_run_context(&context{", false" if camera_config is not None else ""});
    if (ok) {{
        ok = run_model_once(&context,
                            true,
                            {run_model_false_arg}
                            ({macro}_HAS_FINAL_GAP != 0U) ? logits : 0,
                            {macro}_FINAL_CHANNELS,
                            &conv_ticks,
                            &cpu_ticks,
                            &wall_ticks);
    }}

    if (ok) {{
        measured_ticks = ticks_add(conv_ticks, cpu_ticks);
        Uart_println("");
        Uart_println("{display_name} timing summary:");
        Uart_print("  Accelerator conv layers : ");
        print_tick_metric(conv_ticks);
        Uart_println("");
        Uart_print("  Conv average cost       : ");
        print_cycles_per_unit(conv_ticks, conv_macs / 1000U);
        Uart_println(" cycles / 1000 MACs");
        Uart_print("  CPU fallback/post       : ");
        print_tick_metric(cpu_ticks);
        Uart_println("");
        Uart_print("  Full measured pipeline  : ");
        print_tick_metric(measured_ticks);
        Uart_println("");
        Uart_print("  Wall section            : ");
        print_tick_metric(wall_ticks);
        Uart_println("  (includes UART/log overhead)");
    }}

    end_run_context({end_context_call});

    Uart_println(ok ? "{display_name} timing -> DONE" : "{display_name} timing -> FAIL");
    return ok;
}}

{camera_functions}

{static_functions}

bool {api_prefix}_Accel_RunPreparedInput(int32_t *logits_out, uint32_t logits_count)
{{
    bool ok;
    {type_prefix}_RunContext_t context;
    tick_t conv_ticks;
    tick_t cpu_ticks;
    tick_t wall_ticks;

    ok = begin_run_context(&context{", false" if camera_config is not None else ""});
    if (ok) {{
        ok = run_model_once(&context,
                            false,
                            {run_model_false_arg}
                            logits_out,
                            logits_count,
                            &conv_ticks,
                            &cpu_ticks,
                            &wall_ticks);
    }}

    end_run_context({end_context_call});
    return ok;
}}

uint32_t {api_prefix}_Accel_FinalOfmapAddr(void)
{{
    return s_{module}_layers[{macro}_LAYER_COUNT - 1U].ofbaddr;
}}

uint32_t {api_prefix}_Accel_FinalOfmapBytes(void)
{{
    return layer_ofmap_storage_bytes(&s_{module}_layers[{macro}_LAYER_COUNT - 1U]);
}}
'''
    path.write_text(source)


def write_hex(path: Path, blob: bytes) -> None:
    with path.open("w") as f:
        for offset in range(0, len(blob), 16):
            f.write(blob[offset : offset + 16].hex().upper() + "\n")


def ihex_checksum(record_bytes: bytes) -> int:
    return (-sum(record_bytes)) & 0xFF


def write_ihex(path: Path, image: bytes, record_size: int = 32) -> None:
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
            payload = image[addr : addr + record_size]
            record = bytes([len(payload), (low_addr >> 8) & 0xFF, low_addr & 0xFF, 0x00]) + payload
            f.write(":" + record.hex().upper() + f"{ihex_checksum(record):02X}\n")

        final_upper = len(image) >> 16
        if final_upper != current_upper:
            payload = struct.pack(">H", final_upper)
            record = bytes([len(payload), 0x00, 0x00, 0x04]) + payload
            f.write(":" + record.hex().upper() + f"{ihex_checksum(record):02X}\n")

        f.write(":00000001FF\n")


def validate_flash_range(start: int, size: int, label: str) -> Tuple[int, int]:
    if start < 0 or size < 0:
        raise ValueError(f"{label} uses a negative flash range")
    end = start + size
    if end > FLASH_SIZE:
        raise ValueError(f"{label} range 0x{start:06X}..0x{end:06X} exceeds 16MB flash")
    return start, end


def ensure_no_flash_overlap(
    used_ranges: Sequence[Tuple[int, int, str]],
    new_range: Tuple[int, int],
    label: str,
) -> None:
    start, end = new_range
    for used_start, used_end, used_label in used_ranges:
        if start < used_end and used_start < end:
            raise ValueError(
                f"{label} range 0x{start:06X}..0x{end:06X} overlaps {used_label} "
                f"0x{used_start:06X}..0x{used_end:06X}"
            )


def build_flash_image_with_generated_weights(
    app_path: Path,
    weights: bytes,
    static_input: Optional[bytes],
    bin_out: Path,
    ihex_out: Optional[Path],
    metadata_offset: int,
    flash_offset: int,
    static_input_offset: int,
) -> Tuple[int, Optional[int]]:
    app = app_path.read_bytes()
    if len(app) > APP_MAX_SIZE:
        raise ValueError(f"App image is {len(app)} bytes, max supported is {APP_MAX_SIZE}")

    image = bytearray([0xFF]) * FLASH_SIZE
    struct.pack_into("<II", image, BOOT_META_OFFSET, BOOT_VALID_MAGIC, len(app))
    image[BOOT_IMAGE_OFFSET : BOOT_IMAGE_OFFSET + len(app)] = app

    used_ranges = [
        (BOOT_META_OFFSET, BOOT_META_OFFSET + 8, "boot metadata"),
        (BOOT_IMAGE_OFFSET, BOOT_IMAGE_OFFSET + len(app), "app"),
    ]
    metadata_range = validate_flash_range(metadata_offset, 20, "weight metadata")
    payload_range = validate_flash_range(flash_offset, len(weights), "weight payload")
    ensure_no_flash_overlap(used_ranges, metadata_range, "weight metadata")
    ensure_no_flash_overlap(used_ranges, payload_range, "weight payload")
    ensure_no_flash_overlap([(*metadata_range, "weight metadata")], payload_range, "weight payload")
    used_ranges.append((*metadata_range, "weight metadata"))
    used_ranges.append((*payload_range, "weight payload"))

    weight_crc32 = zlib.crc32(weights) & 0xFFFFFFFF
    struct.pack_into(
        "<IIIII",
        image,
        metadata_offset,
        WEIGHT_METADATA_MAGIC,
        WEIGHT_METADATA_VERSION,
        flash_offset,
        len(weights),
        weight_crc32,
    )
    image[flash_offset : flash_offset + len(weights)] = weights

    static_crc32 = None
    if static_input is not None:
        static_range = validate_flash_range(static_input_offset, len(static_input), "static input payload")
        ensure_no_flash_overlap(used_ranges, static_range, "static input payload")
        static_crc32 = zlib.crc32(static_input) & 0xFFFFFFFF
        image[static_input_offset : static_input_offset + len(static_input)] = static_input

    bin_out.parent.mkdir(parents=True, exist_ok=True)
    bin_out.write_bytes(image)

    if ihex_out:
        write_ihex(ihex_out, image)

    return weight_crc32, static_crc32


def build_manifest(
    module: str,
    display_name: str,
    layers: List[ConvLayer],
    cpu_ops: List[CpuOp],
    execution_steps: List[ExecutionStep],
    zero_copy_concat_aliases: List[ZeroCopyConcatAlias],
    param_bytes: int,
    activation_bytes: int,
    activation_row_alignment: int,
    gap_enabled: bool,
    camera_config: Optional[CameraConfig],
    static_input: Optional[StaticInputConfig],
    warnings: List[str],
) -> Dict:
    return {
        "module": module,
        "display_name": display_name,
        "param_bytes": param_bytes,
        "activation_bytes": activation_bytes,
        "activation_row_alignment": activation_row_alignment,
        "has_final_global_avgpool": gap_enabled,
        "zero_copy_concat_aliases": [
            {
                "name": alias.name,
                "op_index": alias.op_index,
                "input_tensor": alias.input_tensor,
                "output_tensor": alias.output_tensor,
                "producer_op_index": alias.producer_op_index,
                "channel_offset": alias.channel_offset,
            }
            for alias in zero_copy_concat_aliases
        ],
        "static_input": (
            {
                "name": static_input.name,
                "flash_offset": static_input.flash_offset,
                "size": static_input.size,
                "crc32": f"0x{static_input.crc32:08X}",
                "expected_top1": static_input.expected_top1,
                "expected_value": static_input.expected_value,
            }
            if static_input is not None
            else None
        ),
        "cpu_fallback_ops": [
            {
                "name": op.name,
                "op_index": op.op_index,
                "kind": op.kind,
                "inputs": op.inputs,
                "output": op.output,
                "input_views": [
                    {
                        "tensor": view.tensor_index,
                        "addr": view.addr,
                        "height": view.height,
                        "width": view.width,
                        "channels": view.channels,
                        "row_stride": view.row_stride,
                    }
                    for view in op.input_views
                ],
                "output_view": {
                    "tensor": op.output_view.tensor_index,
                    "addr": op.output_view.addr,
                    "height": op.output_view.height,
                    "width": op.output_view.width,
                    "channels": op.output_view.channels,
                    "row_stride": op.output_view.row_stride,
                },
                "filter_h": op.filter_h,
                "filter_w": op.filter_w,
                "stride_h": op.stride_h,
                "stride_w": op.stride_w,
                "pad_top": op.pad_top,
                "pad_left": op.pad_left,
            }
            for op in cpu_ops
        ],
        "execution_steps": [
            {
                "kind": step.kind,
                "index": step.index,
                "name": (
                    layers[step.index].name
                    if step.kind == "ACCEL_CONV"
                    else cpu_ops[step.index].name
                ),
            }
            for step in execution_steps
        ],
        "camera_ifmap": (
            {
                "input_tensor": camera_config.input_tensor,
                "out_size": camera_config.out_size,
                "out_pixels": camera_config.out_pixels,
                "scaled_h": camera_config.scaled_h,
                "pad_top": camera_config.pad_top,
                "x_step": camera_config.x_step,
                "y_step": camera_config.y_step,
                "output_bgr": camera_config.output_bgr,
                "preprocess": {
                    "shift": camera_config.shift,
                    "mult": [camera_config.mult_r, camera_config.mult_g, camera_config.mult_b],
                    "offset": [camera_config.offset_r, camera_config.offset_g, camera_config.offset_b],
                },
            }
            if camera_config is not None
            else None
        ),
        "layers": [
            {
                "name": layer.name,
                "op_index": layer.op_index,
                "input_tensor": layer.input_tensor,
                "raw_input_tensor": layer.input_from_tensor,
                "weight_tensor": layer.weight_tensor,
                "bias_tensor": layer.bias_tensor,
                "output_tensor": layer.output_tensor,
                "ifheight": layer.ifheight,
                "ifwidth": layer.ifwidth,
                "ifchannel": layer.ifchannel,
                "ofheight": layer.ofheight,
                "ofwidth": layer.ofwidth,
                "ofchannel": layer.ofchannel,
                "hf": layer.hf,
                "stride": layer.stride,
                "padding": layer.padding,
                "ifparr": layer.ifparr,
                "oftile": layer.oftile,
                "ofparr": layer.ofparr,
                "ifbaddr": layer.ifbaddr,
                "fltbaddr": layer.fltbaddr,
                "bias_baddr": layer.bias_baddr,
                "ofbaddr": layer.ofbaddr,
                "ifrow_stride": layer.ifrow_stride,
                "ofrow_stride": layer.ofrow_stride,
                "ifmap_raw_bytes": layer.ifmap_raw_bytes,
                "ifmap_storage_bytes": layer.ifmap_storage_bytes,
                "ofmap_raw_bytes": layer.ofmap_raw_bytes,
                "ofmap_storage_bytes": layer.ofmap_storage_bytes,
                "ifc_zp": layer.ifc_zp,
                "fltc_zp": layer.fltc_zp,
                "mult": layer.mult,
                "mult_shift": layer.mult_shift,
                "zpy": layer.zpy,
                "qmin": layer.qmin,
                "qmax": layer.qmax,
                "is_leaky_relu": layer.is_leaky_relu,
                "packed_weight_size": layer.packed_weight_size,
                "packed_bias_size": layer.packed_bias_size,
                "estimated_cycles": layer.cycles,
            }
            for layer in layers
        ],
        "warnings": warnings,
    }


def build_static_input_config(args: argparse.Namespace) -> Tuple[Optional[StaticInputConfig], Optional[bytes]]:
    if args.static_input_bin is None:
        return None, None
    static_path = args.static_input_bin
    if not static_path.exists():
        raise FileNotFoundError(f"Static input bin not found: {static_path}")
    payload = static_path.read_bytes()
    expected_top1 = -1
    expected_value = 0
    tensor_refs: List[StaticTensorReference] = []
    if args.static_golden is not None:
        if not args.static_golden.exists():
            raise FileNotFoundError(f"Static golden JSON not found: {args.static_golden}")
        golden = json.loads(args.static_golden.read_text(encoding="utf-8"))
        top5 = golden.get("soc_reference", {}).get("top5", [])
        if top5:
            expected_top1 = int(top5[0].get("index", -1))
            expected_value = int(round(float(top5[0].get("value", 0))))
        for ref in golden.get("soc_intermediate", {}).get("references", []):
            tensor_refs.append(
                StaticTensorReference(
                    name=str(ref["name"]),
                    tensor=int(ref["tensor"]),
                    addr=int(ref["addr"]),
                    height=int(ref["height"]),
                    width=int(ref["width"]),
                    channels=int(ref["channels"]),
                    row_stride=int(ref["row_stride"]),
                    logical_bytes=int(ref["logical_bytes"]),
                    crc32=int(str(ref["crc32"]), 0),
                )
            )
    name = args.static_input_name or static_path.stem
    return (
        StaticInputConfig(
            name=name,
            flash_offset=args.flash_input_offset,
            size=len(payload),
            crc32=zlib.crc32(payload) & 0xFFFFFFFF,
            expected_top1=expected_top1,
            expected_value=expected_value,
            tensor_refs=tensor_refs,
        ),
        payload,
    )


def pick_single_file(candidates: Sequence[Path], label: str, option_name: str) -> Optional[Path]:
    if not candidates:
        return None
    if len(candidates) == 1:
        return candidates[0]
    joined = ", ".join(str(path) for path in candidates)
    raise ValueError(f"Multiple {label} files found: {joined}. Use {option_name} to select one.")


def find_model_tflite(model_dir: Path) -> Path:
    preferred = [
        model_dir / f"{model_dir.name}.tflite",
        model_dir / "model.tflite",
    ]
    for path in preferred:
        if path.exists():
            return path

    candidates = sorted(model_dir.glob("*.tflite"))
    selected = pick_single_file(candidates, "TFLite", "--tflite")
    if selected is None:
        raise ValueError(f"No .tflite file found in model directory: {model_dir}")
    return selected


def find_model_params(model_dir: Path) -> Optional[Path]:
    for pattern in ("*fixed_params*.json", "*params*.json"):
        candidates = sorted(model_dir.glob(pattern))
        selected = pick_single_file(candidates, "params JSON", "--params")
        if selected is not None:
            return selected
    return None


def path_from_model_dir(path: Path, model_dir: Optional[Path]) -> Path:
    if path.is_absolute() or model_dir is None or path.exists():
        return path
    return model_dir / path


def resolve_model_inputs(args: argparse.Namespace) -> Tuple[Path, Optional[Path], str]:
    model_dir = args.model_dir
    if model_dir is not None:
        if not model_dir.is_dir():
            raise ValueError(f"--model-dir is not a directory: {model_dir}")

    if args.tflite is not None:
        tflite = path_from_model_dir(args.tflite, model_dir)
    elif model_dir is not None:
        tflite = find_model_tflite(model_dir)
    else:
        raise ValueError("Provide --tflite or --model-dir")

    if not tflite.exists():
        raise FileNotFoundError(f"TFLite file not found: {tflite}")

    if args.params is not None:
        params = path_from_model_dir(args.params, model_dir)
        if not params.exists():
            raise FileNotFoundError(f"Params JSON file not found: {params}")
    elif model_dir is not None:
        params = find_model_params(model_dir)
    else:
        params = None

    module_source = args.name or (model_dir.name if model_dir is not None else tflite.stem)
    module = sanitize_identifier(module_source).lower()
    return tflite, params, module


def parse_args() -> argparse.Namespace:
    firmware_root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--model-dir",
        type=Path,
        help=(
            "Directory for one model. If --tflite is omitted, the script auto-selects "
            "<folder>.tflite, model.tflite, or the only *.tflite in this directory. "
            "If --name is omitted, the folder name becomes the generated module name."
        ),
    )
    parser.add_argument("--tflite", type=Path, help="Input int8 TFLite file")
    parser.add_argument("--params", type=Path, help="Optional fixed-params JSON sidecar")
    parser.add_argument("--name", help="Generated module name; default is the TFLite stem")
    parser.add_argument("--app-src-dir", type=Path, default=firmware_root / "App" / "Src")
    parser.add_argument("--app-inc-dir", type=Path, default=firmware_root / "App" / "Inc")
    parser.add_argument("--build-dir", type=Path, default=Path("Build"))
    parser.add_argument("--bin-out", type=Path, help="Packed HyperRAM0 weight/bias binary")
    parser.add_argument("--hex-out", type=Path, help="Packed HyperRAM0 weight/bias raw-hex file")
    parser.add_argument("--manifest-out", type=Path, help="JSON manifest with generated layer configs")
    parser.add_argument("--static-input-bin", type=Path, help="Optional preprocessed CHW int8 IFMAP payload for static-image SoC test")
    parser.add_argument("--static-golden", type=Path, help="Optional golden JSON produced by prepare_static_image_input.py")
    parser.add_argument("--static-input-name", help="Static input display/name metadata; default is --static-input-bin stem")
    parser.add_argument(
        "--emit-flash-image",
        action="store_true",
        help="Also build a complete 16MB SPI flash .bin using only this generated weight blob",
    )
    parser.add_argument(
        "--flash-app",
        type=Path,
        default=firmware_root / "Build" / "main.bin",
        help="Application image to place at flash boot offset when building --emit-flash-image",
    )
    parser.add_argument(
        "--flash-bin-out",
        type=Path,
        help="Complete SPI flash .bin output; implies --emit-flash-image",
    )
    parser.add_argument(
        "--flash-ihex-out",
        type=Path,
        help="Optional Intel HEX output for the same generated SPI flash image",
    )
    parser.add_argument(
        "--flash-weight-offset",
        type=lambda x: int(x, 0),
        default=DEFAULT_FLASH_WEIGHT_OFFSET,
        help="Flash offset for the generated packed weight/bias payload; default 0x00200000",
    )
    parser.add_argument(
        "--flash-metadata-offset",
        type=lambda x: int(x, 0),
        default=DEFAULT_FLASH_WEIGHT_METADATA_OFFSET,
        help="Flash metadata offset for the generated payload; default 0x001FF000",
    )
    parser.add_argument(
        "--flash-input-offset",
        type=lambda x: int(x, 0),
        default=DEFAULT_FLASH_STATIC_INPUT_OFFSET,
        help="Flash offset for --static-input-bin when building --emit-flash-image; default 0x00340000",
    )
    parser.add_argument(
        "--camera-ifmap",
        choices=("auto", "on", "off"),
        default="auto",
        help="Generate camera IFMAP helpers when sidecar/model input supports it; default auto",
    )
    parser.add_argument(
        "--camera-input-width",
        type=int,
        default=640,
        help="Camera source width used to derive video resize step; default 640",
    )
    parser.add_argument(
        "--camera-input-height",
        type=int,
        default=480,
        help="Camera source height used to derive video resize step; default 480",
    )
    parser.add_argument(
        "--camera-output-bgr",
        action="store_true",
        help="Set VideoStreaming output_bgr even when sidecar model_color_order is RGB",
    )
    parser.add_argument("--activation-allocator", choices=("append", "liveness"), default="append")
    parser.add_argument("--input-base", type=lambda x: int(x, 0), default=0)
    parser.add_argument("--param-base", type=lambda x: int(x, 0), default=0)
    parser.add_argument("--activation-align", type=int, default=4)
    parser.add_argument(
        "--no-zero-copy-concat",
        action="store_true",
        help="Keep CONCATENATION ops as CPU copy fallbacks instead of redirecting producer conv OFMAPs",
    )
    parser.add_argument(
        "--activation-row-align",
        type=int,
        default=2,
        help="Align each IFMAP/OFMAP row to this many bytes; default 2 accounts for one dummy byte on odd int8 rows",
    )
    parser.add_argument("--param-align", type=int, default=4)
    parser.add_argument("--max-k", type=int, default=FIXED_MAX_POSSIBLE_K)
    parser.add_argument("--max-oftile", type=int, default=1)
    parser.add_argument("--no-fold-pad", action="store_true")
    parser.add_argument("--no-c", action="store_true", help="Only generate packed params and manifest")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    tflite_path, params_path, module = resolve_model_inputs(args)
    api_prefix = snake_to_pascal(module)
    display_name = api_prefix
    header_name = f"{module}_accel.h"
    source_name = f"{module}_accel.c"
    guard = f"{module.upper()}_ACCEL_H"

    args.build_dir.mkdir(parents=True, exist_ok=True)
    args.app_src_dir.mkdir(parents=True, exist_ok=True)
    args.app_inc_dir.mkdir(parents=True, exist_ok=True)

    bin_out = args.bin_out or (args.build_dir / f"{module}_packed_weights.bin")
    hex_out = args.hex_out or (args.build_dir / f"{module}_packed_weights.hex")
    manifest_out = args.manifest_out or (args.build_dir / f"{module}_accel_manifest.json")
    static_input_config, static_input_payload = build_static_input_config(args)

    warnings: List[str] = []
    model = parse_tflite(tflite_path)
    sidecar = parse_sidecar(params_path)
    layers = extract_conv_layers(tflite_path, model, sidecar, not args.no_fold_pad, warnings)
    cpu_ops = extract_cpu_ops(tflite_path, model, warnings)
    zero_copy_concat_aliases: List[ZeroCopyConcatAlias] = []
    if not args.no_zero_copy_concat:
        cpu_ops, zero_copy_concat_aliases = optimize_zero_copy_concats(
            model,
            layers,
            cpu_ops,
            args.activation_row_align,
            warnings,
        )

    for layer in layers:
        cfg = choose_layer_config(layer, args.max_k, args.max_oftile)
        layer.ifparr = cfg.nip
        layer.oftile = cfg.npass
        layer.ofparr = cfg.nfp
        layer.cycles = cfg.cycles

    final_gap_ops = detect_final_gap_op_indices(model, layers)
    gap_enabled = bool(final_gap_ops)
    zero_copy_concat_ops = {alias.op_index for alias in zero_copy_concat_aliases}
    execution_steps = build_execution_steps(
        model,
        layers,
        cpu_ops,
        final_gap_ops,
        zero_copy_concat_ops,
        warnings,
    )

    if args.activation_allocator == "liveness":
        activation_bytes = assign_liveness_activation_addresses(
            model,
            layers,
            cpu_ops,
            execution_steps,
            gap_enabled,
            args.input_base,
            args.activation_align,
            args.activation_row_align,
        )
    else:
        activation_bytes = assign_append_activation_addresses(
            model,
            layers,
            cpu_ops,
            args.input_base,
            args.activation_align,
            args.activation_row_align,
        )

    apply_zero_copy_concat_aliases(
        model,
        layers,
        cpu_ops,
        zero_copy_concat_aliases,
        args.activation_row_align,
        warnings,
    )
    populate_layer_activation_layout(model, layers, cpu_ops, args.activation_row_align, warnings)

    packed = pack_parameters(model, layers, sidecar, args.param_base, args.param_align)
    param_bytes = len(packed)
    camera_config = build_camera_config(
        model,
        layers,
        sidecar,
        args.camera_ifmap,
        args.camera_input_width,
        args.camera_input_height,
        args.camera_output_bgr,
        warnings,
    )

    bin_out.parent.mkdir(parents=True, exist_ok=True)
    bin_out.write_bytes(packed)
    hex_out.parent.mkdir(parents=True, exist_ok=True)
    write_hex(hex_out, packed)

    if not args.no_c:
        emit_header(
            args.app_inc_dir / header_name,
            module,
            api_prefix,
            guard,
            layers[0],
            layers[-1],
            gap_enabled,
            camera_config,
            static_input_config,
        )
        emit_source(
            args.app_src_dir / source_name,
            header_name,
            module,
            api_prefix,
            display_name,
            layers,
            cpu_ops,
            execution_steps,
            param_bytes,
            activation_bytes,
            gap_enabled,
            camera_config,
            static_input_config,
        )

    manifest = build_manifest(
        module,
        display_name,
        layers,
        cpu_ops,
        execution_steps,
        zero_copy_concat_aliases,
        param_bytes,
        activation_bytes,
        args.activation_row_align,
        gap_enabled,
        camera_config,
        static_input_config,
        warnings,
    )
    manifest_out.parent.mkdir(parents=True, exist_ok=True)
    manifest_out.write_text(json.dumps(manifest, indent=2))

    flash_bin_out = None
    flash_crc32 = None
    flash_static_crc32 = None
    if args.emit_flash_image or args.flash_bin_out or args.flash_ihex_out:
        flash_bin_out = args.flash_bin_out or (
            args.build_dir / "flash_images" / f"flash_instructions_with_{module}_weights.bin"
        )
        flash_crc32, flash_static_crc32 = build_flash_image_with_generated_weights(
            args.flash_app,
            packed,
            static_input_payload,
            flash_bin_out,
            args.flash_ihex_out,
            args.flash_metadata_offset,
            args.flash_weight_offset,
            args.flash_input_offset,
        )

    if args.model_dir is not None:
        print(f"model dir    : {args.model_dir}")
    print(f"model        : {tflite_path}")
    if params_path is not None:
        print(f"params       : {params_path}")
    print(f"conv layers  : {len(layers)}")
    print(f"cpu fallback : {len(cpu_ops)} ops")
    if zero_copy_concat_aliases:
        print(f"zero-copy cat: {len({alias.op_index for alias in zero_copy_concat_aliases})} ops")
    print(f"exec steps   : {len(execution_steps)}")
    print(f"params bin   : {bin_out} ({bin_out.stat().st_size} bytes)")
    print(f"params hex   : {hex_out} ({hex_out.stat().st_size} bytes)")
    print(f"manifest     : {manifest_out}")
    if not args.no_c:
        print(f"source       : {args.app_src_dir / source_name}")
        print(f"header       : {args.app_inc_dir / header_name}")
    print(f"activation   : {activation_bytes} bytes ({args.activation_allocator})")
    if static_input_config is not None:
        print(
            f"static input : 0x{static_input_config.flash_offset:06X} "
            f"({static_input_config.size} bytes), crc32=0x{static_input_config.crc32:08X}"
        )
        if static_input_config.expected_top1 >= 0:
            print(
                f"static golden: top1={static_input_config.expected_top1}, "
                f"value={static_input_config.expected_value}"
            )
    if camera_config is not None:
        print(
            "camera      : "
            f"{args.camera_input_width}x{args.camera_input_height} -> "
            f"{camera_config.out_size}x{camera_config.out_size}x3, "
            f"scaled_h={camera_config.scaled_h}, pad_top={camera_config.pad_top}, "
            f"x_step={camera_config.x_step}, y_step={camera_config.y_step}"
        )
    if flash_bin_out is not None:
        print(f"flash app    : {args.flash_app}")
        print(
            f"flash weight : 0x{args.flash_weight_offset:06X} ({param_bytes} bytes), "
            f"metadata 0x{args.flash_metadata_offset:06X}, crc32=0x{flash_crc32:08X}"
        )
        if flash_static_crc32 is not None and static_input_config is not None:
            print(
                f"flash input  : 0x{args.flash_input_offset:06X} "
                f"({static_input_config.size} bytes), crc32=0x{flash_static_crc32:08X}"
            )
        print(f"flash bin    : {flash_bin_out} ({flash_bin_out.stat().st_size} bytes)")
        if args.flash_ihex_out:
            print(f"flash ihex   : {args.flash_ihex_out} ({args.flash_ihex_out.stat().st_size} bytes)")
    if warnings:
        print("warnings:")
        for warning in warnings:
            print(f"  - {warning}")


if __name__ == "__main__":
    main()
