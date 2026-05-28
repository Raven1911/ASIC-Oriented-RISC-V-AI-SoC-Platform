"""
Module for image preprocessing
"""
import cv2
import numpy as np
from decimal import Decimal, ROUND_HALF_UP, getcontext
from typing import Tuple


class ImagePreprocessor:
    """Handle image preprocessing from capture frames to quantized model input."""

    MEAN_NUM = np.array([4465, 4822, 4914], dtype=np.int64)
    STD_NUM = np.array([2010, 1994, 2023], dtype=np.int64)
    STATS_DEN = 10000
    PIXEL_DEN = 255
    MAX_FIXED_SHIFT = 63
    INT32_MIN = -(1 << 31)
    INT32_MAX = (1 << 31) - 1
    
    def __init__(self, target_width: int = 32, target_height: int = 32, 
                 target_channels: int = 3, input_scale: float = 1.0,
                 input_zero_point: int = 0, input_dtype=np.int8,
                 frame_color_order: str = "BGR", model_color_order: str = "BGR",
                 resize_mode: str = "pad_max_pool", mean=None, std=None):
        """
        Initialize preprocessor
        
        Args:
            target_width: Target image width
            target_height: Target image height
            target_channels: Target number of channels
            input_scale: Quantization input scale from the TFLite model
            input_zero_point: Quantization input zero-point from the TFLite model
            input_dtype: Quantized input dtype, usually np.int8 or np.uint8
            frame_color_order: Color order of input frame, "BGR" for OpenCV frames
            model_color_order: Color order used during model training/preprocessing
            resize_mode: "pad_max_pool", "pad_avg_pool", "avg_pool", "resize",
                "resize_bilinear", "resize_bicubic", "crop_resize",
                "crop_avg_pool", or "crop_max_pool"
            mean: Per-channel normalized mean used before inference
            std: Per-channel normalized std used before inference
        """
        self.target_width = target_width
        self.target_height = target_height
        self.target_channels = target_channels
        self.resize_mode = resize_mode
        self.input_scale = float(input_scale)
        self.input_zero_point = int(input_zero_point)
        self.input_dtype = np.dtype(input_dtype)
        self.frame_color_order = frame_color_order.upper()
        self.model_color_order = model_color_order.upper()
        self.channel_layout = "NHWC"
        self.preprocess_shift = 0
        self.fixed_preprocess_params = False
        self.fixed_preprocess_source = ""
        default_mean = self.MEAN_NUM.astype(np.float64) / float(self.STATS_DEN)
        default_std = self.STD_NUM.astype(np.float64) / float(self.STATS_DEN)
        self.mean = np.array(mean if mean is not None else default_mean, dtype=np.float64)
        self.std = np.array(std if std is not None else default_std, dtype=np.float64)
        self._validate_resize_mode()
        self._update_integer_quantization_params()
    
    def preprocess(self, frame: np.ndarray) -> np.ndarray:
        """
        Preprocess an image to a quantized NCHW/NHWC-ready tensor.
        
        Steps:
        1. Ensure the configured channel count
        2. Resize according to resize_mode
        3. Convert OpenCV BGR frames to RGB when needed
        4. Standardize with training mean/std
        5. Quantize to the model input dtype
        
        Args:
            frame: Input frame (BGR from OpenCV)
            
        Returns:
            Preprocessed image tensor ready for model
        """
        frame = self._ensure_target_channels(frame)
        resized = self._resize_frame(frame)

        if (self.target_channels == 3
                and self.frame_color_order != self.model_color_order):
            resized = resized[:, :, ::-1]

        if np.issubdtype(self.input_dtype, np.floating):
            processed = self._standardize_float(resized)
        else:
            processed = self._quantize_pixels_integer(resized)

        # Add batch dimension for model input.
        batch = np.expand_dims(processed, axis=0)
        
        return batch

    def configure_quantization(self, input_scale: float, input_zero_point: int,
                               input_dtype=np.int8):
        """Update input quantization parameters after loading a TFLite model."""
        dtype = np.dtype(input_dtype)
        if input_scale <= 0 and not np.issubdtype(dtype, np.floating):
            raise ValueError("input_scale must be greater than 0")

        self.input_scale = float(input_scale) if input_scale > 0 else 1.0
        self.input_zero_point = int(input_zero_point)
        self.input_dtype = dtype
        if np.issubdtype(dtype, np.floating):
            self.fixed_preprocess_params = False
            self.fixed_preprocess_source = ""
        self._update_integer_quantization_params()

    def configure_fixed_integer_preprocessing(self, mult, offset, shift: int,
                                              source: str = ""):
        """Use exact integer preprocessing constants from a fixed-params JSON."""
        if np.issubdtype(self.input_dtype, np.floating):
            raise ValueError("fixed integer preprocessing cannot be used with floating input dtype")

        mult_arr = np.asarray(mult, dtype=np.int64)
        offset_arr = np.asarray(offset, dtype=np.int64)
        if mult_arr.ndim != 1 or offset_arr.ndim != 1:
            raise ValueError("fixed preprocessing mult/offset must be 1D lists")
        if mult_arr.size != offset_arr.size:
            raise ValueError("fixed preprocessing mult and offset must have the same length")
        if mult_arr.size not in (1, self.target_channels):
            raise ValueError(
                f"fixed preprocessing has {mult_arr.size} channels, "
                f"expected 1 or {self.target_channels}"
            )
        shift = int(shift)
        if shift < 0 or shift > self.MAX_FIXED_SHIFT:
            raise ValueError(f"fixed preprocessing shift must be 0..{self.MAX_FIXED_SHIFT}")
        if np.any(mult_arr < self.INT32_MIN) or np.any(mult_arr > self.INT32_MAX):
            raise ValueError("fixed preprocessing mult values must fit int32")
        if np.any(offset_arr < self.INT32_MIN) or np.any(offset_arr > self.INT32_MAX):
            raise ValueError("fixed preprocessing offset values must fit int32")

        self.preprocess_mult = mult_arr.astype(np.int32)
        self.preprocess_offset = offset_arr.astype(np.int32)
        self.preprocess_shift = shift
        self.fixed_preprocess_params = True
        self.fixed_preprocess_source = source

    def configure_model_input(self, input_shape):
        """Update target dimensions from a model input shape."""
        shape = tuple(int(dim) for dim in input_shape)
        if len(shape) != 4:
            raise ValueError(f"Expected a 4D model input shape, got {shape}")

        if shape[-1] in (1, 3):
            self.target_height = shape[1]
            self.target_width = shape[2]
            self.target_channels = shape[3]
            self.channel_layout = "NHWC"
        elif shape[1] in (1, 3):
            self.target_channels = shape[1]
            self.target_height = shape[2]
            self.target_width = shape[3]
            self.channel_layout = "NCHW"
        else:
            raise ValueError(f"Cannot infer channel layout from input shape: {shape}")

        self._update_integer_quantization_params()
    
    def preprocess_batch(self, frames: list) -> np.ndarray:
        """
        Preprocess multiple frames
        
        Args:
            frames: List of input frames
            
        Returns:
            Batch of preprocessed images
        """
        batch = []
        for frame in frames:
            processed = self.preprocess(frame)
            batch.append(processed[0])  # Remove batch dimension and add to list
        
        return np.array(batch)
    
    def get_preprocessing_info(self) -> dict:
        """Get preprocessing configuration info"""
        return {
            'target_width': self.target_width,
            'target_height': self.target_height,
            'target_channels': self.target_channels,
            'frame_color_order': self.frame_color_order,
            'model_color_order': self.model_color_order,
            'resize': self.resize_mode,
            'standardization': (
                'fixed integer mult/offset/shift'
                if self.fixed_preprocess_params
                else f'{self.model_color_order} mean/std'
            ),
            'mean': self.mean.tolist(),
            'std': self.std.tolist(),
            'quantization': {
                'scale': self.input_scale,
                'zero_point': self.input_zero_point,
                'dtype': str(self.input_dtype),
                'integer_source': (
                    self.fixed_preprocess_source
                    if self.fixed_preprocess_params
                    else 'derived_mean_std'
                ),
                'integer_mult': self.preprocess_mult.tolist() if self.preprocess_mult.size else None,
                'integer_offset': self.preprocess_offset.tolist() if self.preprocess_offset.size else None,
                'integer_shift': self.preprocess_shift,
                'mult_bits': 32,
                'shift_bits': 6,
            },
            'batch_shape': f'(batch_size, {self.target_height}, {self.target_width}, {self.target_channels})',
        }

    def _ensure_target_channels(self, frame: np.ndarray) -> np.ndarray:
        """Convert grayscale/BGR/BGRA frames to the configured channel count."""
        if frame is None:
            raise ValueError("frame must not be None")

        if self.target_channels == 1:
            if len(frame.shape) == 2:
                return frame[:, :, np.newaxis]
            if frame.shape[2] == 1:
                return frame
            if self.frame_color_order == "RGB":
                gray = cv2.cvtColor(frame[:, :, :3], cv2.COLOR_RGB2GRAY)
            else:
                gray = cv2.cvtColor(frame[:, :, :3], cv2.COLOR_BGR2GRAY)
            return gray[:, :, np.newaxis]

        if len(frame.shape) == 2:
            return cv2.cvtColor(frame, cv2.COLOR_GRAY2BGR)

        if frame.shape[2] == self.target_channels:
            return frame

        if frame.shape[2] == 4:
            return frame[:, :, :3]

        raise ValueError(f"Unsupported frame shape: {frame.shape}")

    def set_resize_mode(self, resize_mode: str):
        """Set how frames are resized before quantization."""
        self.resize_mode = resize_mode
        self._validate_resize_mode()

    def _validate_resize_mode(self):
        valid_modes = {
            "pad_max_pool",
            "pad_max_pool_hw",
            "pad_avg_pool",
            "avg_pool",
            "resize",
            "resize_bilinear",
            "resize_bicubic",
            "crop_resize",
            "crop_avg_pool",
            "crop_max_pool",
        }
        if self.resize_mode not in valid_modes:
            raise ValueError(
                "resize_mode must be one of: " + ", ".join(sorted(valid_modes))
            )

    def _resize_frame(self, frame: np.ndarray) -> np.ndarray:
        if self.resize_mode == "pad_max_pool_hw":
            return self._resize_hardware_pad_max_pool(frame)

        if self.resize_mode in {"pad_max_pool", "pad_avg_pool"}:
            return self._resize_with_padding_and_pool(frame)

        if self.resize_mode == "avg_pool":
            return self._adaptive_pool_2d(
                frame,
                output_size=(self.target_height, self.target_width)
            )

        if self.resize_mode in {"crop_max_pool", "crop_avg_pool"}:
            cropped = self._center_crop_to_target_aspect_ratio(frame)
            return self._adaptive_pool_2d(
                cropped,
                output_size=(self.target_height, self.target_width)
            )

        if self.resize_mode == "crop_resize":
            frame = self._center_crop_to_target_aspect_ratio(frame)

        interpolation = {
            "resize": cv2.INTER_AREA,
            "crop_resize": cv2.INTER_AREA,
            "resize_bilinear": cv2.INTER_LINEAR,
            "resize_bicubic": cv2.INTER_CUBIC,
        }[self.resize_mode]

        return cv2.resize(
            frame,
            (self.target_width, self.target_height),
            interpolation=interpolation
        )

    def _resize_hardware_pad_max_pool(self, frame: np.ndarray) -> np.ndarray:
        """Match the FPGA camera preprocessing: RGB565 max-pool, then square pad."""
        image = self._rgb565_expand_preserving_order(frame)
        in_height, in_width = image.shape[:2]
        channels = image.shape[2]
        output = np.zeros(
            (self.target_height, self.target_width, channels),
            dtype=image.dtype,
        )

        if in_width >= in_height:
            scaled_height = max(1, min(
                self.target_height,
                (self.target_width * in_height) // in_width,
            ))
            pad_top = (self.target_height - scaled_height) // 2
            x_step = (in_width << 16) // self.target_width
            y_step = (in_height << 16) // scaled_height

            y_acc = 0
            for out_y in range(pad_top, pad_top + scaled_height):
                y0 = y_acc >> 16
                y_next = y_acc + y_step
                if out_y == pad_top + scaled_height - 1:
                    y1 = in_height
                else:
                    y1 = max(y0 + 1, y_next >> 16)

                x_acc = 0
                for out_x in range(self.target_width):
                    x0 = x_acc >> 16
                    x_next = x_acc + x_step
                    if out_x == self.target_width - 1:
                        x1 = in_width
                    else:
                        x1 = max(x0 + 1, x_next >> 16)

                    output[out_y, out_x] = image[y0:y1, x0:x1].max(axis=(0, 1))
                    x_acc = x_next

                y_acc = y_next
            return output

        scaled_width = max(1, min(
            self.target_width,
            (self.target_height * in_width) // in_height,
        ))
        pad_left = (self.target_width - scaled_width) // 2
        x_step = (in_width << 16) // scaled_width
        y_step = (in_height << 16) // self.target_height

        y_acc = 0
        for out_y in range(self.target_height):
            y0 = y_acc >> 16
            y_next = y_acc + y_step
            if out_y == self.target_height - 1:
                y1 = in_height
            else:
                y1 = max(y0 + 1, y_next >> 16)

            x_acc = 0
            for out_x in range(pad_left, pad_left + scaled_width):
                x0 = x_acc >> 16
                x_next = x_acc + x_step
                if out_x == pad_left + scaled_width - 1:
                    x1 = in_width
                else:
                    x1 = max(x0 + 1, x_next >> 16)

                output[out_y, out_x] = image[y0:y1, x0:x1].max(axis=(0, 1))
                x_acc = x_next

            y_acc = y_next
        return output

    def _rgb565_expand_preserving_order(self, frame: np.ndarray) -> np.ndarray:
        """Quantize an 8-bit 3-channel frame like the RGB565 framebuffer."""
        if frame.shape[2] != 3:
            return frame

        c0_5 = (frame[:, :, 0].astype(np.uint16) >> 3)
        c1_6 = (frame[:, :, 1].astype(np.uint16) >> 2)
        c2_5 = (frame[:, :, 2].astype(np.uint16) >> 3)

        expanded = np.empty_like(frame)
        expanded[:, :, 0] = ((c0_5 << 3) | (c0_5 >> 2)).astype(frame.dtype)
        expanded[:, :, 1] = ((c1_6 << 2) | (c1_6 >> 4)).astype(frame.dtype)
        expanded[:, :, 2] = ((c2_5 << 3) | (c2_5 >> 2)).astype(frame.dtype)
        return expanded

    def _resize_with_padding_and_pool(self, frame: np.ndarray) -> np.ndarray:
        """Pad to the target aspect ratio, then downsample with adaptive pooling."""
        padded = self._pad_to_target_aspect_ratio(frame)
        return self._adaptive_pool_2d(
            padded,
            output_size=(self.target_height, self.target_width)
        )

    def _pad_to_target_aspect_ratio(self, frame: np.ndarray) -> np.ndarray:
        height, width = frame.shape[:2]
        target_ratio = self.target_width / self.target_height
        current_ratio = width / height

        if np.isclose(current_ratio, target_ratio):
            return frame

        if current_ratio > target_ratio:
            new_height = int(np.ceil(width / target_ratio))
            pad_total = new_height - height
            pad_top = pad_total // 2
            pad_bottom = pad_total - pad_top
            padding = ((pad_top, pad_bottom), (0, 0), (0, 0))
        else:
            new_width = int(np.ceil(height * target_ratio))
            pad_total = new_width - width
            pad_left = pad_total // 2
            pad_right = pad_total - pad_left
            padding = ((0, 0), (pad_left, pad_right), (0, 0))

        return np.pad(frame, padding, mode="constant", constant_values=0)

    def _center_crop_to_target_aspect_ratio(self, frame: np.ndarray) -> np.ndarray:
        height, width = frame.shape[:2]
        target_ratio = self.target_width / self.target_height
        current_ratio = width / height

        if np.isclose(current_ratio, target_ratio):
            return frame

        if current_ratio > target_ratio:
            new_width = int(np.floor(height * target_ratio))
            left = (width - new_width) // 2
            return frame[:, left:left + new_width]

        new_height = int(np.floor(width / target_ratio))
        top = (height - new_height) // 2
        return frame[top:top + new_height, :]

    def _adaptive_pool_2d(self, image: np.ndarray,
                          output_size: Tuple[int, int]) -> np.ndarray:
        out_height, out_width = output_size
        in_height, in_width = image.shape[:2]
        pooled = np.empty((out_height, out_width, image.shape[2]), dtype=image.dtype)

        for out_y in range(out_height):
            y0 = int(np.floor(out_y * in_height / out_height))
            y1 = int(np.ceil((out_y + 1) * in_height / out_height))
            for out_x in range(out_width):
                x0 = int(np.floor(out_x * in_width / out_width))
                x1 = int(np.ceil((out_x + 1) * in_width / out_width))
                window = image[y0:y1, x0:x1]
                if self.resize_mode in {"pad_avg_pool", "crop_avg_pool", "avg_pool"}:
                    pooled[out_y, out_x] = np.round(window.mean(axis=(0, 1)))
                else:
                    pooled[out_y, out_x] = window.max(axis=(0, 1))

        return pooled

    def _quantize(self, image: np.ndarray) -> np.ndarray:
        if self.input_scale <= 0:
            raise ValueError("input_scale must be greater than 0")

        if np.issubdtype(self.input_dtype, np.floating):
            return image.astype(self.input_dtype)

        quantized = np.round(image / self.input_scale + self.input_zero_point)

        if self.input_dtype == np.dtype(np.int8):
            quantized = np.clip(quantized, -128, 127)
        elif self.input_dtype == np.dtype(np.uint8):
            quantized = np.clip(quantized, 0, 255)
        else:
            limits = np.iinfo(self.input_dtype)
            quantized = np.clip(quantized, limits.min, limits.max)

        return quantized.astype(self.input_dtype)

    def _update_integer_quantization_params(self):
        """Build fixed-point multipliers for integer-only input preprocessing."""
        if np.issubdtype(self.input_dtype, np.floating):
            self.fixed_preprocess_params = False
            self.fixed_preprocess_source = ""
            self.preprocess_mult = np.array([], dtype=np.int32)
            self.preprocess_offset = np.array([], dtype=np.int32)
            self.preprocess_shift = 0
            return
        if self.fixed_preprocess_params:
            return

        getcontext().prec = 48
        scale = Decimal(str(self.input_scale))
        if scale <= 0:
            raise ValueError("input_scale must be greater than 0")

        input_zp = Decimal(self.input_zero_point)

        for shift in range(self.MAX_FIXED_SHIFT, -1, -1):
            shift_factor = Decimal(1 << shift)
            mults = []
            offsets = []

            if self.target_channels == 1:
                # q = round(pixel / 255 / input_scale + input_zp)
                mult = self._decimal_to_int(
                    shift_factor / (Decimal(self.PIXEL_DEN) * scale)
                )
                offset = self._decimal_to_int(input_zp * shift_factor)
                mults.append(mult)
                offsets.append(offset)
            else:
                for mean_value, std_value in zip(self.mean, self.std):
                    mean = Decimal(str(float(mean_value)))
                    std = Decimal(str(float(std_value)))

                    # q = round(((pixel / 255 - mean) / std) / scale + input_zp)
                    pixel_mult = shift_factor / (Decimal(self.PIXEL_DEN) * std * scale)
                    offset = (input_zp - (mean / (std * scale))) * shift_factor

                    mults.append(self._decimal_to_int(pixel_mult))
                    offsets.append(self._decimal_to_int(offset))

            if all(self.INT32_MIN <= value <= self.INT32_MAX for value in mults + offsets):
                self.preprocess_mult = np.array(mults, dtype=np.int32)
                self.preprocess_offset = np.array(offsets, dtype=np.int32)
                self.preprocess_shift = shift
                return

        raise ValueError("Could not fit preprocessing multiplier/offset into int32")

    @staticmethod
    def _decimal_to_int(value: Decimal) -> int:
        if value >= 0:
            return int(value.to_integral_value(rounding=ROUND_HALF_UP))
        return -int((-value).to_integral_value(rounding=ROUND_HALF_UP))

    def _standardize_float(self, image: np.ndarray) -> np.ndarray:
        image_float = image.astype(np.float32) / float(self.PIXEL_DEN)

        if self.target_channels == 1:
            return image_float.astype(self.input_dtype)

        mean = self.mean.astype(np.float32)
        std = self.std.astype(np.float32)
        standardized = (image_float - mean) / std
        return standardized.astype(self.input_dtype)

    def _quantize_pixels_integer(self, image: np.ndarray) -> np.ndarray:
        pixels = image.astype(np.int64)
        raw = pixels * self.preprocess_mult + self.preprocess_offset
        quantized = self._round_shift(raw, self.preprocess_shift)

        if self.input_dtype == np.dtype(np.int8):
            quantized = np.clip(quantized, -128, 127)
        elif self.input_dtype == np.dtype(np.uint8):
            quantized = np.clip(quantized, 0, 255)
        elif np.issubdtype(self.input_dtype, np.integer):
            limits = np.iinfo(self.input_dtype)
            quantized = np.clip(quantized, limits.min, limits.max)
        else:
            return quantized.astype(np.float32)

        return quantized.astype(self.input_dtype)

    @staticmethod
    def _round_shift(value: np.ndarray, shift: int) -> np.ndarray:
        if shift <= 0:
            return value << (-shift)

        rounding = np.int64(1 << (shift - 1))
        positive = (value + rounding) >> shift
        negative = -(((-value) + rounding) >> shift)
        return np.where(value >= 0, positive, negative)
