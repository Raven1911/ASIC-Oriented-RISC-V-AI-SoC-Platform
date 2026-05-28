"""
Main application for Golden Model Software
Captures video from capture card, preprocesses, runs inference, and displays results
"""
import argparse
import json
import sys
import cv2
import numpy as np
import time
from pathlib import Path

# Add parent directory to path
sys.path.insert(0, str(Path(__file__).parent.parent))

from config import *
from src.capture import CaptureCardReader, list_capture_devices
from src.preprocessing import ImagePreprocessor
from src.model_inference import ModelInference
from src.gui_display import PerformanceMonitor
from src.uart_console import UartConsole, UartSnapshot, list_uart_ports
from src.firmware_builder import FirmwareBuildRunner


def normalize_backend(backend: str) -> str:
    if backend == "tflite":
        return "tflite-int8"
    if backend == "fp32":
        return "tflite-fp32"
    if backend == "alexnet":
        return "alexnet-int8"
    return backend


def load_model_stats(stats_path: str):
    path = Path(stats_path)
    if not path.exists():
        raise FileNotFoundError(f"Model stats file not found: {path}")
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def load_fixed_preprocess_params(fixed_params_path: str):
    path = Path(fixed_params_path)
    if not path.exists():
        raise FileNotFoundError(f"Fixed preprocessing params file not found: {path}")
    with path.open("r", encoding="utf-8") as handle:
        data = json.load(handle)

    input_cfg = data.get("input", {})
    fixed = input_cfg.get("fixed", {})
    required = ("mult", "offset", "shift")
    missing = [key for key in required if key not in fixed]
    if missing:
        raise ValueError(f"Fixed preprocessing params missing keys: {missing}")

    params = {
        "mult": fixed["mult"],
        "offset": fixed["offset"],
        "shift": fixed["shift"],
        "zero_point": input_cfg.get("zero_point"),
        "pixel_denominator": input_cfg.get("pixel_denominator"),
    }

    conv_layers = data.get("conv_layers") or []
    if conv_layers:
        final_conv = conv_layers[-1]
        if ("output_tensor_index" in final_conv
                and "output_zero_point" in final_conv):
            params["soc_gap"] = {
                "tensor_index": final_conv["output_tensor_index"],
                "zero_point": final_conv["output_zero_point"],
            }

    return params


def infer_fixed_preprocess_params_path(model_path: str):
    """Find a matching *_fixed_params_int_only.json next to an INT8 model."""
    path = Path(model_path)
    stem = path.stem
    candidates = []
    for suffix in ("_int8_per_layer", "_per_layer", "_int8"):
        if stem.endswith(suffix):
            base = stem[: -len(suffix)]
            candidates.append(path.with_name(f"{base}_fixed_params_int_only.json"))
    candidates.append(path.with_name(f"{stem}_fixed_params_int_only.json"))

    for candidate in candidates:
        if candidate.exists():
            return str(candidate)
    return None


class GoldenModelApp:
    """Main application class"""
    
    def __init__(self, device_id=CAPTURE_DEVICE_ID,
                 width: int = ORIGINAL_WIDTH, height: int = ORIGINAL_HEIGHT,
                 resize_mode: str = RESIZE_MODE,
                 warmup_seconds: float = CAPTURE_WARMUP_SECONDS,
                 backend: str = MODEL_BACKEND,
                 model_path: str = MODEL_PATH,
                 fp32_model_path: str = MODEL_FP32_PATH,
                 all_cnn_c_160_model_path: str = ALL_CNN_C_160_MODEL_PATH,
                 all_cnn_c_160_stats_path: str = ALL_CNN_C_160_STATS_PATH,
                 rps_cnn_96_s2_model_path: str = RPS_CNN_96_S2_FLOAT32_MODEL_PATH,
                 rps_cnn_96_s2_int8_model_path: str = RPS_CNN_96_S2_INT8_MODEL_PATH,
                 rps_cnn_96_s2_qat_int8_model_path: str = RPS_CNN_96_S2_QAT_INT8_MODEL_PATH,
                 rps_cnn_96_s2_qat_sympad_int8_model_path: str = RPS_CNN_96_S2_QAT_SYMPAD_INT8_MODEL_PATH,
                 rps_cnn_96_s2_stats_path: str = RPS_CNN_96_S2_STATS_PATH,
                 rps_cnn_96_s2_int8_fixed_params_path: str = RPS_CNN_96_S2_INT8_FIXED_PARAMS_PATH,
                 rps_cnn_96_s2_qat_int8_fixed_params_path: str = RPS_CNN_96_S2_QAT_INT8_FIXED_PARAMS_PATH,
                 rps_cnn_96_s2_qat_sympad_int8_fixed_params_path: str = RPS_CNN_96_S2_QAT_SYMPAD_INT8_FIXED_PARAMS_PATH,
                 alexnet_model_path: str = ALEXNET_INT8_MODEL_PATH,
                 squeezenet_model_path: str = SQUEEZENET1_1_MODEL_PATH,
                 uart_port: str = UART_PORT,
                 uart_baud: int = UART_BAUD,
                 uart_newline: str = UART_NEWLINE_MODE,
                 firmware_dir: str = FIRMWARE_DIR,
                 firmware_builder_script: str = FIRMWARE_BUILDER_SCRIPT,
                 firmware_flasher_script: str = FIRMWARE_FLASHER_SCRIPT,
                 firmware_target: str = FIRMWARE_BUILD_TARGET,
                 firmware_max_flash_kb: int = FIRMWARE_MAX_FLASH_KB,
                 firmware_flash_file: str = FIRMWARE_FLASH_FILE,
                 window_width: int = WINDOW_WIDTH,
                 window_height: int = WINDOW_HEIGHT,
                 fullscreen: bool = False):
        """Initialize application"""
        self.device_id = device_id
        self.width = width
        self.height = height
        self.resize_mode = resize_mode
        self.warmup_seconds = warmup_seconds
        self.backend = normalize_backend(backend)
        self.model_path = model_path
        self.fp32_model_path = fp32_model_path
        self.all_cnn_c_160_model_path = all_cnn_c_160_model_path
        self.all_cnn_c_160_stats_path = all_cnn_c_160_stats_path
        self.rps_cnn_96_s2_model_path = rps_cnn_96_s2_model_path
        self.rps_cnn_96_s2_int8_model_path = rps_cnn_96_s2_int8_model_path
        self.rps_cnn_96_s2_qat_int8_model_path = rps_cnn_96_s2_qat_int8_model_path
        self.rps_cnn_96_s2_qat_sympad_int8_model_path = rps_cnn_96_s2_qat_sympad_int8_model_path
        self.rps_cnn_96_s2_stats_path = rps_cnn_96_s2_stats_path
        self.rps_cnn_96_s2_int8_fixed_params_path = rps_cnn_96_s2_int8_fixed_params_path
        self.rps_cnn_96_s2_qat_int8_fixed_params_path = rps_cnn_96_s2_qat_int8_fixed_params_path
        self.rps_cnn_96_s2_qat_sympad_int8_fixed_params_path = rps_cnn_96_s2_qat_sympad_int8_fixed_params_path
        self.class_labels = CLASS_LABELS
        self.alexnet_model_path = alexnet_model_path
        self.squeezenet_model_path = squeezenet_model_path
        self.model_profiles = self._build_model_profiles()
        self.uart_port = uart_port
        self.uart_baud = uart_baud
        self.uart_newline = uart_newline
        self.firmware_target = firmware_target
        self.firmware_max_flash_kb = firmware_max_flash_kb
        self.firmware_flash_file = firmware_flash_file
        self.window_width = window_width
        self.window_height = window_height
        self.fullscreen = fullscreen
        self.capture = None
        self.preprocessor = None
        self.model = None
        self.display = None
        self.monitor = None
        self.uart_console = None
        self.firmware_builder = FirmwareBuildRunner(
            firmware_dir=firmware_dir,
            builder_script=firmware_builder_script,
            flasher_script=firmware_flasher_script,
            default_flash_file=firmware_flash_file,
        )
        self._last_build_status_key = None
        self._uart_reconnect_after_flash = None
        self.qt_app = None
        self.qt_window = None
        self.running = False
        self.cleaned_up = False

    def _build_model_profiles(self):
        """Return selectable RPS TFLite model profiles for the dashboard."""
        profiles = {
            key: value.copy()
            for key, value in MODEL_PROFILES.items()
        }
        profiles["all_cnn_c_160"]["model_path"] = self.all_cnn_c_160_model_path
        profiles["all_cnn_c_160"]["stats_path"] = self.all_cnn_c_160_stats_path
        profiles["rps_cnn_96_s2_float32"]["model_path"] = self.rps_cnn_96_s2_model_path
        profiles["rps_cnn_96_s2_float32"]["stats_path"] = self.rps_cnn_96_s2_stats_path
        profiles["rps_cnn_96_s2_int8"]["model_path"] = self.rps_cnn_96_s2_int8_model_path
        profiles["rps_cnn_96_s2_int8"]["stats_path"] = self.rps_cnn_96_s2_stats_path
        profiles["rps_cnn_96_s2_int8"]["fixed_params_path"] = self.rps_cnn_96_s2_int8_fixed_params_path
        profiles["rps_cnn_96_s2_qat_int8"]["model_path"] = self.rps_cnn_96_s2_qat_int8_model_path
        profiles["rps_cnn_96_s2_qat_int8"]["stats_path"] = self.rps_cnn_96_s2_stats_path
        profiles["rps_cnn_96_s2_qat_int8"]["fixed_params_path"] = self.rps_cnn_96_s2_qat_int8_fixed_params_path
        profiles["rps_cnn_96_s2_qat_sympad_int8"]["model_path"] = self.rps_cnn_96_s2_qat_sympad_int8_model_path
        profiles["rps_cnn_96_s2_qat_sympad_int8"]["stats_path"] = self.rps_cnn_96_s2_stats_path
        profiles["rps_cnn_96_s2_qat_sympad_int8"]["fixed_params_path"] = self.rps_cnn_96_s2_qat_sympad_int8_fixed_params_path
        return profiles

    def _model_options(self):
        """Return GUI combo-box items for selectable model profiles."""
        return [
            {"id": backend, "label": profile.get("label", backend)}
            for backend, profile in self.model_profiles.items()
        ]

    def _model_label(self, backend: str = None) -> str:
        """Return a display label for a backend/profile id."""
        backend = normalize_backend(backend or self.backend)
        profile = self.model_profiles.get(backend)
        if profile is not None:
            return profile.get("label", backend)
        return backend

    def _unload_current_model(self):
        """Unload the active model object if it supports explicit cleanup."""
        if self.model is not None and hasattr(self.model, "unload"):
            self.model.unload()
        self.model = None
        self.preprocessor = None
    
    def initialize(self) -> bool:
        """
        Initialize the Qt dashboard and model. Capture/UART can be connected
        from the GUI after startup.

        Returns:
            True if successful, False otherwise
        """
        try:
            print("Initializing Golden Model Application...")
            print("=" * 50)

            print("\n1. Initializing Qt Dashboard...")
            from src.qt_dashboard import DashboardWindow, create_qt_app

            self.qt_app = create_qt_app()
            capture_devices = self._refresh_capture_devices()
            uart_ports = self._refresh_uart_ports()
            self.qt_window = DashboardWindow(
                on_command=self._send_uart_command,
                on_model_select=self._select_model,
                on_capture_connect=self._connect_capture,
                on_capture_disconnect=self._disconnect_capture,
                on_capture_refresh=self._refresh_capture_devices,
                on_uart_connect=self._connect_uart,
                on_uart_disconnect=self._disconnect_uart,
                on_uart_refresh=self._refresh_uart_ports,
                on_terminal_clear=self._clear_uart_terminal,
                on_firmware_build=self._start_firmware_build,
                on_firmware_flash=self._start_firmware_flash,
                on_firmware_stop=self._stop_firmware_build,
                on_firmware_clear=self._clear_firmware_build_log,
                model_options=self._model_options(),
                capture_devices=capture_devices,
                uart_ports=uart_ports,
                initial_model=self.backend,
                initial_capture_device=str(self.device_id),
                initial_uart_port=self.uart_port,
                initial_uart_baud=self.uart_baud,
                initial_firmware_target=self.firmware_target,
                initial_firmware_max_flash_kb=self.firmware_max_flash_kb,
                initial_firmware_flash_file=self.firmware_flash_file,
                window_width=self.window_width,
                window_height=self.window_height,
                fullscreen=self.fullscreen,
            )
            self.qt_app.processEvents()

            print("\n2. Loading model...")
            if not self._initialize_model():
                return False
            self.qt_window.set_model_status(f"loaded {self._model_label()}", True)

            print("\n3. Initializing Performance Monitor...")
            self.monitor = PerformanceMonitor()

            if str(self.device_id).strip():
                ok, message = self._connect_capture(str(self.device_id))
                self.qt_window.set_capture_status(message, ok)

            if self.uart_port:
                ok, message = self._connect_uart(self.uart_port, self.uart_baud)
                self.qt_window.set_uart_status(message, ok)

            print("\n" + "=" * 50)
            print("Initialization completed successfully!")
            print("=" * 50)
            print("\nSelect Video Capture/UART in the right panel, then press Connect.")
            print("Type SoC commands in the terminal input after UART connects.")
            print("F11 toggles fullscreen, Esc leaves fullscreen.")
            print("\n" + "=" * 50 + "\n")

            return True

        except Exception as e:
            print(f"Initialization error: {e}")
            return False

    def _initialize_model(self) -> bool:
        """Load preprocessing and inference backend once at startup."""
        self._unload_current_model()
        self.class_labels = CLASS_LABELS

        if self.backend == "alexnet-int8":
            print("Loading Quantized AlexNet...")
            from src.alexnet_inference import QuantizedAlexNetInference

            self.model = QuantizedAlexNetInference(self.alexnet_model_path)
            if not self.model.load_model():
                print("Failed to load quantized AlexNet")
                return False
            return True

        if self.backend == "squeezenet1_1":
            print("Loading SqueezeNet 1.1...")
            from src.squeezenet_inference import SqueezeNet1_1Inference

            self.model = SqueezeNet1_1Inference(self.squeezenet_model_path)
            if not self.model.load_model():
                print("Failed to load SqueezeNet 1.1")
                return False
            return True

        target_width = TARGET_WIDTH
        target_height = TARGET_HEIGHT
        target_channels = TARGET_CHANNELS
        resize_mode = self.resize_mode
        preprocess_mean = None
        preprocess_std = None
        model_color_order = "BGR"
        selected_model_path = self.model_path
        fixed_preprocess_params_path = None
        fixed_preprocess_params = None
        host_output_mode = "model_output"

        if self.backend == "tflite-fp32":
            selected_model_path = self.fp32_model_path
        elif self.backend in self.model_profiles:
            profile = self.model_profiles[self.backend]
            stats = load_model_stats(profile["stats_path"])
            target_height, target_width, target_channels = stats["input_size"]
            resize_mode = profile.get("resize_mode", stats.get("resize_mode", "pad_max_pool"))
            preprocess_mean = stats["mean"]
            preprocess_std = stats["std"]
            model_color_order = profile.get("model_color_order", "RGB")
            self.class_labels = stats.get("class_names", RPS_CLASS_LABELS)
            selected_model_path = profile["model_path"]
            fixed_preprocess_params_path = profile.get("fixed_params_path")
            host_output_mode = profile.get("host_output_mode", "model_output")
            if not fixed_preprocess_params_path:
                fixed_preprocess_params_path = infer_fixed_preprocess_params_path(selected_model_path)

        if fixed_preprocess_params_path:
            fixed_preprocess_params = load_fixed_preprocess_params(fixed_preprocess_params_path)

        soc_gap_config = None
        if host_output_mode == "soc_gap_logits":
            soc_gap_config = (fixed_preprocess_params or {}).get("soc_gap")
            if not soc_gap_config:
                print("Warning: SoC GAP host output requested, "
                      "but final conv tensor was not found in fixed params")

        print(f"Selected model: {self._model_label()} ({self.backend})")

        print("Initializing Preprocessor...")
        self.preprocessor = ImagePreprocessor(
            target_width=target_width,
            target_height=target_height,
            target_channels=target_channels,
            resize_mode=resize_mode,
            model_color_order=model_color_order,
            mean=preprocess_mean,
            std=preprocess_std
        )
        print(f"Preprocessing config: {self.preprocessor.get_preprocessing_info()}")

        print("Loading Model...")
        self.model = ModelInference(
            model_path=selected_model_path,
            soc_gap_config=soc_gap_config,
        )
        if not self.model.load_model():
            print("Failed to load model")
            return False

        if hasattr(self.model, "get_input_quantization"):
            input_scale, input_zero_point, input_dtype = self.model.get_input_quantization()
            self.preprocessor.configure_model_input(self.model.get_input_shape())
            self.preprocessor.configure_quantization(
                input_scale=input_scale,
                input_zero_point=input_zero_point,
                input_dtype=input_dtype
            )
            print(f"Updated preprocessing quantization: "
                  f"scale={input_scale}, zero_point={input_zero_point}, dtype={input_dtype}")
            if fixed_preprocess_params_path and fixed_preprocess_params:
                fixed_params = fixed_preprocess_params
                pixel_denominator = fixed_params.get("pixel_denominator")
                if pixel_denominator not in (None, self.preprocessor.PIXEL_DEN):
                    raise ValueError(
                        f"Fixed preprocessing pixel_denominator={pixel_denominator}, "
                        f"expected {self.preprocessor.PIXEL_DEN}"
                    )
                fixed_zero_point = fixed_params.get("zero_point")
                if fixed_zero_point is not None and int(fixed_zero_point) != int(input_zero_point):
                    print(f"Warning: fixed params zero_point={fixed_zero_point} "
                          f"differs from model zero_point={input_zero_point}")
                self.preprocessor.configure_fixed_integer_preprocessing(
                    mult=fixed_params["mult"],
                    offset=fixed_params["offset"],
                    shift=fixed_params["shift"],
                    source=fixed_preprocess_params_path,
                )
                print(f"Using fixed integer preprocessing params from: "
                      f"{fixed_preprocess_params_path}")
            print(f"Updated preprocessing config: {self.preprocessor.get_preprocessing_info()}")

        return True
    
    def run(self):
        """Main application loop"""
        if not self.initialize():
            print("Failed to initialize application")
            return
        
        self.running = True
        frame_count = 0
        
        try:
            while self.running:
                self.qt_app.processEvents()
                if self.qt_window.closed:
                    self.running = False
                    break

                if self.capture is None or not self.capture.is_opened:
                    self.qt_window.set_idle_view("No video connected", self._dashboard_snapshot())
                    time.sleep(0.03)
                    continue

                frame_count += 1
                loop_start = time.time()
                
                # 1. Capture frame
                frame = self.capture.read_frame()
                if frame is None:
                    self.qt_window.set_capture_status("capture read failed", False)
                    self.capture.close()
                    self.capture = None
                    continue
                
                inference_start = time.time()
                
                if self.backend in {"alexnet-int8", "squeezenet1_1"}:
                    predictions = self.model.predict_frame(frame)
                else:
                    # 2. Preprocess
                    input_tensor = self.preprocessor.preprocess(frame)

                    # 3. Run inference
                    predictions = self.model.predict(input_tensor)
                
                # 4. Get top predictions
                top_preds = self.model.get_top_predictions(predictions, NUM_TOP_RESULTS)
                
                # 5. Format results
                if self.backend in {"alexnet-int8", "squeezenet1_1"}:
                    results = self.model.format_results(top_preds)
                else:
                    results = self.model.format_results(top_preds, self.class_labels)
                
                inference_time = (time.time() - inference_start) * 1000  # Convert to ms
                
                # 7. Update performance monitor
                loop_time = (time.time() - loop_start) * 1000
                fps = 1000 / loop_time if loop_time > 0 else 0
                self.monitor.update(fps, inference_time)
                
                # 8. Display frame
                self.qt_window.update_view(
                    frame,
                    results,
                    inference_time,
                    self.monitor.get_average_fps(),
                    self._dashboard_snapshot(),
                )
                self.qt_app.processEvents()
                self.running = not self.qt_window.closed
                
                # Print stats periodically
                if frame_count % 30 == 0:
                    print(f"Frame {frame_count} | "
                          f"Avg FPS: {self.monitor.get_average_fps():.1f} | "
                          f"Avg Inference: {self.monitor.get_average_processing_time():.1f}ms")
                    
                    print(f"Top {NUM_TOP_RESULTS} predictions:")
                    for result in results:
                        print(f"  {result['rank']}. {result['label']} "
                              f"(class {result['class_id']}): {result['percentage']:.2f}%")
        
        except KeyboardInterrupt:
            print("\nInterrupted by user")
        
        except Exception as e:
            print(f"Application error: {e}")
        
        finally:
            self.cleanup()

    def _refresh_capture_devices(self):
        """Scan OpenCV capture devices for the dashboard selector."""
        devices = list_capture_devices(width=self.width, height=self.height)
        if self.capture is not None and self.capture.is_opened:
            current_id = str(self.device_id)
            if all(device.get("id") != current_id for device in devices):
                devices.insert(0, {
                    "id": current_id,
                    "label": (
                        f"{current_id} | connected "
                        f"{self.capture.actual_width}x{self.capture.actual_height}"
                    ),
                })
        return devices

    def _refresh_uart_ports(self):
        """Scan serial ports for the dashboard selector."""
        ports = list_uart_ports()
        if self.uart_console is not None and self.uart_console.connected:
            current_port = self.uart_console.port
            if all(port.get("port") != current_port for port in ports):
                ports.insert(0, {
                    "port": current_port,
                    "label": f"{current_port} | connected",
                })
        return ports

    def _connect_capture(self, device_id: str):
        """Open or switch the video capture device from the dashboard."""
        device_id = str(device_id).strip()
        if not device_id:
            return False, "empty capture device"

        if self.capture is not None:
            self.capture.close()
            self.capture = None

        capture = CaptureCardReader(
            device_id=device_id,
            width=self.width,
            height=self.height,
            warmup_seconds=self.warmup_seconds,
        )
        if not capture.open():
            return False, f"failed to open capture {device_id}"

        self.capture = capture
        self.device_id = device_id
        self.monitor = PerformanceMonitor()
        return (
            True,
            f"connected {device_id}: {capture.actual_width}x{capture.actual_height}",
        )

    def _disconnect_capture(self):
        """Close the active video capture device from the dashboard."""
        if self.capture is not None:
            self.capture.close()
            self.capture = None
        return False, "not connected"

    def _connect_uart(self, port: str, baudrate: int):
        """Open or switch the UART port from the dashboard."""
        port = str(port).strip()
        if not port:
            return False, "empty UART port"

        if self.uart_console is not None:
            self.uart_console.close()
            self.uart_console = None

        console = UartConsole(
            port=port,
            baudrate=baudrate,
            newline_mode=self.uart_newline,
        )
        try:
            console.open()
        except Exception as exc:
            self.uart_port = port
            self.uart_baud = baudrate
            return False, f"failed to open {port}: {exc}"

        self.uart_console = console
        self.uart_port = port
        self.uart_baud = baudrate
        return True, f"connected {port} @ {baudrate}"

    def _disconnect_uart(self):
        """Close the active UART port from the dashboard."""
        if self.uart_console is not None:
            self.uart_console.close()
            self.uart_console = None
        return False, "not connected"

    def _select_model(self, backend: str):
        """Switch the active golden-model backend from the dashboard."""
        backend = normalize_backend(str(backend).strip())
        if not backend:
            return False, "empty model"

        selectable = set(self.model_profiles.keys())
        if backend not in selectable:
            return False, f"unknown selectable model: {backend}"

        if backend == self.backend and self.model is not None and self.model.is_loaded:
            return True, f"already loaded {self._model_label(backend)}"

        previous_backend = self.backend
        self.backend = backend

        if self.qt_window is not None:
            self.qt_window.set_model_status(f"loading {self._model_label()}...", False)
            self.qt_app.processEvents()

        if self._initialize_model():
            if self.monitor is not None:
                self.monitor = PerformanceMonitor()
            return True, f"loaded {self._model_label()}"

        failed_label = self._model_label(backend)
        self.backend = previous_backend
        if previous_backend != backend:
            self._initialize_model()
        return False, f"failed to load {failed_label}"

    def _uart_snapshot(self) -> UartSnapshot:
        """Return current UART state, including a stable disconnected state."""
        if self.uart_console is not None:
            return self.uart_console.snapshot()

        return UartSnapshot(
            connected=False,
            port=self.uart_port or "",
            baudrate=self.uart_baud,
            status="not connected",
            lines=[],
            current_line="",
            latest_result="",
            latest_confidence=0.0,
            latest_time_ms=0.0,
            latest_conv_ms=0.0,
            latest_cpu_ms=0.0,
            latest_wall_ms=0.0,
            latest_logits=[0, 0, 0],
            result_fps=0.0,
            result_sequence=0,
        )

    def _dashboard_snapshot(self) -> UartSnapshot:
        """Return UART terminal data while syncing the firmware-build tab."""
        self._sync_firmware_build_status()
        return self._uart_snapshot()

    def _sync_firmware_build_status(self, force: bool = False) -> None:
        if self.qt_window is None or self.firmware_builder is None:
            return

        build_snapshot = self.firmware_builder.snapshot()
        self.qt_window.update_build_log(build_snapshot.lines)
        key = (
            build_snapshot.running,
            build_snapshot.status,
            build_snapshot.operation,
            build_snapshot.returncode,
        )
        if not force and key == self._last_build_status_key:
            return

        success = (
            not build_snapshot.running
            and build_snapshot.returncode == 0
        )
        self.qt_window.set_build_status(
            build_snapshot.status,
            success=success,
            running=build_snapshot.running,
            operation=build_snapshot.operation,
        )
        self._last_build_status_key = key

        if (
                not build_snapshot.running
                and build_snapshot.operation == "flash"
                and self._uart_reconnect_after_flash is not None):
            port, baudrate = self._uart_reconnect_after_flash
            self._uart_reconnect_after_flash = None
            ok, message = self._connect_uart(port, baudrate)
            self.qt_window.set_uart_status(message, ok)
    
    def cleanup(self):
        """Clean up resources"""
        if self.cleaned_up:
            return
        self.cleaned_up = True
        print("\nCleaning up...")
        
        if self.capture is not None:
            self.capture.close()
        
        self._unload_current_model()

        if self.uart_console is not None:
            self.uart_console.close()
        if self.firmware_builder is not None:
            self.firmware_builder.close()
        if self.qt_window is not None and not self.qt_window.closed:
            self.qt_window.close()
        
        cv2.destroyAllWindows()
        print("Cleanup completed")
    
    def __del__(self):
        """Destructor"""
        self.cleanup()

    def _send_uart_command(self, text: str) -> None:
        """Send one line from the Qt terminal input to the SoC."""
        if self.uart_console is not None:
            self.uart_console.send_line(text)
        elif self.qt_window is not None:
            self.qt_window.set_uart_status("not connected", False)

    def _clear_uart_terminal(self) -> None:
        """Clear the UART terminal buffer shown in the dashboard."""
        if self.uart_console is not None:
            self.uart_console.clear()

    def _clear_firmware_build_log(self) -> None:
        """Clear the firmware build log shown in the dashboard."""
        if self.firmware_builder is not None:
            self.firmware_builder.clear()

    def _start_firmware_build(self, target: str, max_flash_kb: int):
        """Start a firmware build from the Qt dashboard."""
        ok, message = self.firmware_builder.start(target, max_flash_kb)
        if ok:
            self.firmware_target = target
            self.firmware_max_flash_kb = max_flash_kb
        self._sync_firmware_build_status(force=True)
        return ok, message

    def _start_firmware_flash(self, port: str, image_path: str):
        """Start host_flasher.py using the UART port selected in the dashboard."""
        port = str(port).strip()
        if not port:
            return False, "select a UART port first"

        reconnect = False
        reconnect_baud = self.uart_baud
        if (
                self.uart_console is not None
                and self.uart_console.connected
                and self.uart_console.port == port):
            reconnect = True
            reconnect_baud = self.uart_console.baudrate
            self.uart_console.close()
            self.uart_console = None
            if self.qt_window is not None:
                self.qt_window.set_uart_status("released UART for flashing", False)

        ok, message = self.firmware_builder.start_flash(port, image_path)
        if ok:
            self.firmware_flash_file = image_path or self.firmware_flash_file
            if reconnect:
                self._uart_reconnect_after_flash = (port, reconnect_baud)
        elif reconnect:
            reconnect_ok, reconnect_message = self._connect_uart(port, reconnect_baud)
            if self.qt_window is not None:
                self.qt_window.set_uart_status(reconnect_message, reconnect_ok)

        self._sync_firmware_build_status(force=True)
        return ok, message

    def _stop_firmware_build(self):
        """Stop the active firmware build subprocess."""
        ok, message = self.firmware_builder.stop()
        self._sync_firmware_build_status(force=True)
        return ok, message


def main():
    """Main entry point"""
    parser = argparse.ArgumentParser(description="Run live inference from a camera/capture card.")
    parser.add_argument("--device", default=str(CAPTURE_DEVICE_ID))
    parser.add_argument("--width", type=int, default=ORIGINAL_WIDTH)
    parser.add_argument("--height", type=int, default=ORIGINAL_HEIGHT)
    parser.add_argument("--warmup", type=float, default=CAPTURE_WARMUP_SECONDS)
    parser.add_argument(
        "--backend",
        choices=["tflite", "tflite-int8", "tflite-fp32", "fp32", "all_cnn_c_160", "rps_cnn_96_s2_float32", "rps_cnn_96_s2_int8", "rps_cnn_96_s2_qat_int8", "rps_cnn_96_s2_qat_sympad_int8", "alexnet", "alexnet-int8", "squeezenet1_1"],
        default=MODEL_BACKEND
    )
    parser.add_argument("--model", default=MODEL_PATH, help="Path to INT8 TFLite model.")
    parser.add_argument("--fp32-model", default=MODEL_FP32_PATH, help="Path to float32 TFLite model.")
    parser.add_argument("--all-cnn-c-160-model", default=ALL_CNN_C_160_MODEL_PATH)
    parser.add_argument("--all-cnn-c-160-stats", default=ALL_CNN_C_160_STATS_PATH)
    parser.add_argument("--rps-cnn-96-s2-model", default=RPS_CNN_96_S2_FLOAT32_MODEL_PATH)
    parser.add_argument("--rps-cnn-96-s2-int8-model", default=RPS_CNN_96_S2_INT8_MODEL_PATH)
    parser.add_argument("--rps-cnn-96-s2-qat-int8-model", default=RPS_CNN_96_S2_QAT_INT8_MODEL_PATH)
    parser.add_argument("--rps-cnn-96-s2-qat-sympad-int8-model", default=RPS_CNN_96_S2_QAT_SYMPAD_INT8_MODEL_PATH)
    parser.add_argument("--rps-cnn-96-s2-stats", default=RPS_CNN_96_S2_STATS_PATH)
    parser.add_argument("--rps-cnn-96-s2-int8-fixed-params", default=RPS_CNN_96_S2_INT8_FIXED_PARAMS_PATH)
    parser.add_argument("--rps-cnn-96-s2-qat-int8-fixed-params", default=RPS_CNN_96_S2_QAT_INT8_FIXED_PARAMS_PATH)
    parser.add_argument("--rps-cnn-96-s2-qat-sympad-int8-fixed-params", default=RPS_CNN_96_S2_QAT_SYMPAD_INT8_FIXED_PARAMS_PATH)
    parser.add_argument("--alexnet-model", default=ALEXNET_INT8_MODEL_PATH)
    parser.add_argument("--squeezenet-model", default=SQUEEZENET1_1_MODEL_PATH)
    parser.add_argument("--uart-port", default=UART_PORT, help="Optional SoC UART port, for example /dev/ttyUSB0.")
    parser.add_argument("--uart-baud", type=int, default=UART_BAUD)
    parser.add_argument(
        "--uart-newline",
        choices=["none", "lf", "cr", "crlf"],
        default=UART_NEWLINE_MODE,
        help="Newline appended when Enter sends a UART command.",
    )
    parser.add_argument("--firmware-dir", default=FIRMWARE_DIR)
    parser.add_argument("--firmware-builder", default=FIRMWARE_BUILDER_SCRIPT)
    parser.add_argument("--firmware-flasher", default=FIRMWARE_FLASHER_SCRIPT)
    parser.add_argument(
        "--firmware-target",
        choices=["app", "bootloader", "both", "test_unit"],
        default=FIRMWARE_BUILD_TARGET,
    )
    parser.add_argument("--firmware-max-flash-kb", type=int, default=FIRMWARE_MAX_FLASH_KB)
    parser.add_argument("--firmware-flash-file", default=FIRMWARE_FLASH_FILE)
    parser.add_argument("--window-width", type=int, default=WINDOW_WIDTH)
    parser.add_argument("--window-height", type=int, default=WINDOW_HEIGHT)
    parser.add_argument("--fullscreen", action="store_true")
    parser.add_argument(
        "--resize-mode",
        choices=[
            "pad_max_pool",
            "pad_avg_pool",
            "avg_pool",
            "resize",
            "resize_bilinear",
            "resize_bicubic",
            "crop_resize",
            "crop_avg_pool",
            "crop_max_pool",
        ],
        default=RESIZE_MODE
    )
    args = parser.parse_args()

    app = GoldenModelApp(
        device_id=args.device,
        width=args.width,
        height=args.height,
        resize_mode=args.resize_mode,
        warmup_seconds=args.warmup,
        backend=args.backend,
        model_path=args.model,
        fp32_model_path=args.fp32_model,
        all_cnn_c_160_model_path=args.all_cnn_c_160_model,
        all_cnn_c_160_stats_path=args.all_cnn_c_160_stats,
        rps_cnn_96_s2_model_path=args.rps_cnn_96_s2_model,
        rps_cnn_96_s2_int8_model_path=args.rps_cnn_96_s2_int8_model,
        rps_cnn_96_s2_qat_int8_model_path=args.rps_cnn_96_s2_qat_int8_model,
        rps_cnn_96_s2_qat_sympad_int8_model_path=args.rps_cnn_96_s2_qat_sympad_int8_model,
        rps_cnn_96_s2_stats_path=args.rps_cnn_96_s2_stats,
        rps_cnn_96_s2_int8_fixed_params_path=args.rps_cnn_96_s2_int8_fixed_params,
        rps_cnn_96_s2_qat_int8_fixed_params_path=args.rps_cnn_96_s2_qat_int8_fixed_params,
        rps_cnn_96_s2_qat_sympad_int8_fixed_params_path=args.rps_cnn_96_s2_qat_sympad_int8_fixed_params,
        alexnet_model_path=args.alexnet_model,
        squeezenet_model_path=args.squeezenet_model,
        uart_port=args.uart_port,
        uart_baud=args.uart_baud,
        uart_newline=args.uart_newline,
        firmware_dir=args.firmware_dir,
        firmware_builder_script=args.firmware_builder,
        firmware_flasher_script=args.firmware_flasher,
        firmware_target=args.firmware_target,
        firmware_max_flash_kb=args.firmware_max_flash_kb,
        firmware_flash_file=args.firmware_flash_file,
        window_width=args.window_width,
        window_height=args.window_height,
        fullscreen=args.fullscreen,
    )
    app.run()


if __name__ == "__main__":
    main()
