# Configuration for Golden Model Software

# Capture Card Settings
CAPTURE_DEVICE_ID = 0  # Camera device ID (0 for default camera/capture card)
ORIGINAL_WIDTH = 640
ORIGINAL_HEIGHT = 480
CAPTURE_WARMUP_SECONDS = 0.0

# Optional SoC UART terminal shown next to the live software result.
UART_PORT = ""
UART_BAUD = 230400
UART_NEWLINE_MODE = "lf"

# Optional firmware builder controls shown in the Qt dashboard.
# Empty paths are auto-detected from the repository layout.
FIRMWARE_DIR = ""
FIRMWARE_BUILDER_SCRIPT = ""
FIRMWARE_FLASHER_SCRIPT = ""
FIRMWARE_BUILD_TARGET = "app"
FIRMWARE_MAX_FLASH_KB = 64
FIRMWARE_FLASH_FILE = "Build/main.bin"

# Preprocessing Settings
TARGET_WIDTH = 32
TARGET_HEIGHT = 32
TARGET_CHANNELS = 3
RESIZE_MODE = "pad_max_pool"  # Options: "pad_max_pool", "pad_avg_pool", "avg_pool", "resize", "resize_bilinear", "resize_bicubic", "crop_resize", "crop_avg_pool", "crop_max_pool"

# Model Settings
MODEL_BACKEND = "all_cnn_c_160"  # Options: "tflite", "tflite-int8", "tflite-fp32", "fp32", "all_cnn_c_160", "rps_cnn_96_s2_float32", "rps_cnn_96_s2_int8", "rps_cnn_96_s2_qat_int8", "rps_cnn_96_s2_qat_sympad_int8", "alexnet", "alexnet-int8", "squeezenet1_1"
MODEL_PATH = "./models/ALL_CNN_C_INT8_per_tensor.tflite"
MODEL_FP32_PATH = "./models/ALL_CNN_C_FLOAT32.tflite"
ALL_CNN_C_160_MODEL_PATH = "./models/all_cnn_c_160_rps_float32.tflite"
ALL_CNN_C_160_STATS_PATH = "./models/all_cnn_c_160_rps_stats.json"
RPS_CNN_96_S2_FLOAT32_MODEL_PATH = "./models/rps_cnn_96_s2_float32.tflite"
RPS_CNN_96_S2_INT8_MODEL_PATH = "./models/rps_cnn_96_s2_int8_per_layer.tflite"
RPS_CNN_96_S2_QAT_INT8_MODEL_PATH = "./models/rps_cnn_96_s2_qat_int8_per_layer.tflite"
RPS_CNN_96_S2_QAT_SYMPAD_INT8_MODEL_PATH = "./models/rps_cnn_96_s2_qat_sympad_int8_per_layer.tflite"
RPS_CNN_96_S2_STATS_PATH = "./models/rps_cnn_96_s2_stats.json"
RPS_CNN_96_S2_INT8_FIXED_PARAMS_PATH = "./models/rps_cnn_96_s2_fixed_params_int_only.json"
RPS_CNN_96_S2_QAT_INT8_FIXED_PARAMS_PATH = "./models/rps_cnn_96_s2_qat_fixed_params_int_only.json"
RPS_CNN_96_S2_QAT_SYMPAD_INT8_FIXED_PARAMS_PATH = "./models/rps_cnn_96_s2_qat_sympad_fixed_params_int_only.json"
ALEXNET_INT8_MODEL_PATH = "./models/alexnet_int8_quantized.pt"
SQUEEZENET1_1_MODEL_PATH = ""  # Empty = use pretrained torchvision SqueezeNet 1.1 ImageNet labels
NUM_TOP_RESULTS = 5  # Display top 5 results

MODEL_PROFILES = {
    "all_cnn_c_160": {
        "label": "ALL-CNN-C 160x160",
        "model_path": ALL_CNN_C_160_MODEL_PATH,
        "stats_path": ALL_CNN_C_160_STATS_PATH,
        "model_color_order": "RGB",
    },
    "rps_cnn_96_s2_float32": {
        "label": "RPS CNN 96x96 S2 Float32",
        "model_path": RPS_CNN_96_S2_FLOAT32_MODEL_PATH,
        "stats_path": RPS_CNN_96_S2_STATS_PATH,
        "model_color_order": "RGB",
    },
    "rps_cnn_96_s2_int8": {
        "label": "RPS CNN 96x96 S2 Int8",
        "model_path": RPS_CNN_96_S2_INT8_MODEL_PATH,
        "stats_path": RPS_CNN_96_S2_STATS_PATH,
        "fixed_params_path": RPS_CNN_96_S2_INT8_FIXED_PARAMS_PATH,
        "model_color_order": "RGB",
        "host_output_mode": "soc_gap_logits",
    },
    "rps_cnn_96_s2_qat_int8": {
        "label": "RPS CNN 96x96 S2 QAT Int8",
        "model_path": RPS_CNN_96_S2_QAT_INT8_MODEL_PATH,
        "stats_path": RPS_CNN_96_S2_STATS_PATH,
        "fixed_params_path": RPS_CNN_96_S2_QAT_INT8_FIXED_PARAMS_PATH,
        "model_color_order": "RGB",
        "host_output_mode": "soc_gap_logits",
    },
    "rps_cnn_96_s2_qat_sympad_int8": {
        "label": "RPS CNN 96x96 S2 QAT SymPad Int8",
        "model_path": RPS_CNN_96_S2_QAT_SYMPAD_INT8_MODEL_PATH,
        "stats_path": RPS_CNN_96_S2_STATS_PATH,
        "fixed_params_path": RPS_CNN_96_S2_QAT_SYMPAD_INT8_FIXED_PARAMS_PATH,
        "model_color_order": "RGB",
        "resize_mode": "pad_max_pool_hw",
        "host_output_mode": "soc_gap_logits",
    },
}

# Class Labels (Update this with your actual class names)
CLASS_LABELS = [
    "Airplane", "Automobile", "Bird", "Cat", "Deer", "Dog", "Frog", "Horse", "Ship", "Truck"
    # Add more class labels as needed
]

RPS_CLASS_LABELS = ["paper", "rock", "scissors"]

# Display Settings
DISPLAY_WIDTH = 800
DISPLAY_HEIGHT = 600
FONT_SCALE = 1.0
THICKNESS = 2
WINDOW_WIDTH = 1920
WINDOW_HEIGHT = 1080
