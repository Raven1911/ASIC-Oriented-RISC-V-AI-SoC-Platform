# Beta_AISoC_Firmware

Firmware, host tools và phần mềm golden model cho hệ Beta AI SoC.

Repo hiện có hai phần chính:

- `Beta_AISoC_Firmware/`: firmware RISC-V chạy trên SoC, bootloader, HAL và script build/flash.
- `software_golden_model_rps/`: phần mềm chạy trên host để nhận video capture card, chạy golden model và hiển thị song song kết quả `Host Computer` với `BK-AISoC`.

Tài liệu này ưu tiên flow đang dùng hiện tại: camera `640x480`, resize phần cứng sang `160x160x3`, model `ALL-CNN-C-160` nhận diện `paper / rock / scissors`, weight nằm trong SPI flash và được load sang HyperRAM0 trước khi chạy accelerator.

## Mục Lục

1. [Trạng Thái Hiện Tại](#1-trạng-thái-hiện-tại)
2. [Cấu Trúc Repo](#2-cấu-trúc-repo)
3. [Yêu Cầu Môi Trường](#3-yêu-cầu-môi-trường)
4. [Quick Start Cho Demo Camera](#4-quick-start-cho-demo-camera)
5. [Build Và Flash Firmware](#5-build-và-flash-firmware)
6. [Weight Và Model ALL-CNN-C-160](#6-weight-và-model-all-cnn-c-160)
7. [UART Menu Trên SoC](#7-uart-menu-trên-soc)
8. [Golden Model Host App](#8-golden-model-host-app)
9. [Cách Chạy Từng Script](#9-cách-chạy-từng-script)
10. [Bash Autocomplete](#10-bash-autocomplete)
11. [Flash Map Và Output Quan Trọng](#11-flash-map-và-output-quan-trọng)
12. [Các File Nên Đọc Khi Sửa Code](#12-các-file-nên-đọc-khi-sửa-code)
13. [Sử Dụng SoC HAL](#13-sử-dụng-soc-hal)
14. [Lệnh Kiểm Tra Nhanh](#14-lệnh-kiểm-tra-nhanh)

## 1. Trạng Thái Hiện Tại

Các phần chính đang có trong repo:

- Boot flow dùng boot image segmented `BAI1`. Bootloader copy riêng `LOAD_IMEM`, `LOAD_DMEM`, zero `BSS`, rồi mới jump vào app.
- App mặc định hiện bật menu `ALL-CNN-C-160`; các menu cũ như `ALL_CNN_C CIFAR-10`, `VGG16`, `SqueezeNet` vẫn còn code nhưng đang tắt bằng macro trong `App/Src/main.c`.
- Model camera hiện tại là `ALL-CNN-C-160`, 15 lớp convolution, input `160x160x3`, output 3 lớp `paper / rock / scissors`.
- Weight của model 160 được pack bằng script `pack_allcnnc160_from_tflite.py` thành layout mà accelerator đọc trực tiếp từ HyperRAM0.
- Flow weight mới:
  - gửi weight từ laptop xuống SPI flash bằng UART,
  - ghi metadata tại `0x001FF000`,
  - payload mặc định tại `0x00200000`,
  - lệnh `2.2` load từ flash sang HyperRAM0 và verify CRC32.
- Lệnh `7.1` chạy timing-only cho pipeline `camera IFMAP -> accelerator conv -> CPU GAP`.
- Lệnh `7.2` chạy loop nhận diện camera thật; UART chỉ in nhãn động để giảm độ trễ, không in logits mỗi frame nữa.
- Trong `7.2`, video/resize path chỉ giữ quyền truy cập cho layer đầu; sau đó firmware trả grant để các layer còn lại chạy accelerator bình thường.
- Phần mềm `software_golden_model_rps` đã có dashboard Qt:
  - stream video,
  - kết quả host và `BK-AISoC`,
  - chọn/reconnect capture card trực tiếp trong GUI,
  - chọn/reconnect UART port và `Baud` trực tiếp trong GUI,
  - terminal UART có scroll,
  - capture host chạy low-latency, chỉ giữ frame mới nhất để giảm delay từ capture-card buffer,
  - layout kết quả đã khóa để text FPS/thời gian dài không làm ô `BK-AISoC` bị nhảy ngang,
  - FPS của SoC đã trừ ước lượng thời gian truyền UART,
  - `F11` bật/tắt fullscreen, `Esc` thoát fullscreen về cửa sổ thường.
- Bash completion đã hỗ trợ:
  - `builder.py`
  - `host_flasher.py`
  - `uart_weight_sender.py`
  - `capture_dataset.py`
  - `python3 src/main.py` của golden model host app.

## 2. Cấu Trúc Repo

```text
Beta_AISoC_Firmware/
├── README.md
├── Beta_AISoC_Firmware/
│   ├── App/                  # firmware application
│   ├── Core/                 # startup + linker app
│   ├── Drivers/              # bootloader + SoC HAL
│   ├── Build/                # output build và weight blob
│   ├── models/               # tùy chọn: mỗi model một folder để generate accelerator
│   ├── scripts/              # host tools
│   └── testing/              # testbench support files
├── software_golden_model_rps/
│   ├── models/               # TFLite + stats của model host
│   ├── src/                  # capture, preprocess, dashboard, UART console
│   ├── assets/               # logo giao diện
│   ├── config.py
│   └── list_capture_devices.py
└── datasheet/                # dữ liệu phụ cho accuracy/test cũ
```

Các lệnh firmware bên dưới giả sử đang đứng trong:

```bash
cd Beta_AISoC_Firmware
```

Các lệnh golden model host app giả sử đang đứng trong:

```bash
cd software_golden_model_rps
```

## 3. Yêu Cầu Môi Trường

### 3.1 Firmware

Cần Python 3:

```bash
python3 --version
```

Cần RISC-V toolchain trong `PATH`:

```bash
riscv32-unknown-elf-gcc --version
riscv32-unknown-elf-objcopy --version
riscv32-unknown-elf-objdump --version
```

Cần `pyserial` cho các script UART:

```bash
python3 -m pip install pyserial
```

### 3.2 Golden Model Host App

Môi trường host app cần các package trong:

```text
software_golden_model_rps/requirements.txt
```

Virtual environment hiện có nằm ở root repo:

```bash
cd /home/raven1911/Data/Source_Thesis/Beta_AISoC_Firmware
source .venv-tf/bin/activate
```

Sau khi vào môi trường, cài hoặc cập nhật package cho golden model host app:

```bash
python3 -m pip install -r software_golden_model_rps/requirements.txt
```

Thoát môi trường:

```bash
deactivate
```

Các package hiện dùng:

- `opencv-python`
- `numpy`
- `tensorflow`
- `pyserial`
- `PyQt5`

## 4. Quick Start Cho Demo Camera

### 4.1 Build Và Flash App

Từ thư mục firmware:

```bash
cd Beta_AISoC_Firmware
./scripts/builder.py --target app
./scripts/host_flasher.py /dev/ttyUSB0 Build/main.bin
```

Nếu vừa sửa bootloader, linker hoặc builder:

```bash
./scripts/builder.py --target both
```

Sau đó nạp lại bootloader vào phần cứng theo flow Vivado hiện tại của bạn trước khi flash app mới.

### 4.2 Tạo Weight Blob Cho Model 160

```bash
./scripts/pack_allcnnc160_from_tflite.py \
  --model-dir "/path/to/Model ALL CNN C int 8" \
  --bin-out Build/allcnnc_160_packed_weights.bin \
  --hex-out Build/allcnnc_160_packed_weights.hex
```

`Build/allcnnc_160_packed_weights.hex` là raw hex text, mỗi dòng là byte hex, không phải Intel HEX.

### 4.3 Gửi Weight Xuống SPI Flash Qua UART

```bash
./scripts/uart_weight_sender.py \
  --port /dev/ttyUSB0 \
  --input Build/allcnnc_160_packed_weights.hex
```

Script mặc định tự gửi lệnh menu `2.1` trước khi bắt đầu protocol nhị phân.

Nếu muốn thấy menu trước rồi tự xác nhận lệnh:

```bash
./scripts/uart_weight_sender.py \
  --port /dev/ttyUSB0 \
  --input Build/allcnnc_160_packed_weights.hex \
  --interactive-menu
```

### 4.4 Chạy Demo Trên Board Qua Terminal

Mở terminal UART:

```bash
./scripts/host_flasher.py /dev/ttyUSB0 --terminal-only
```

Sau đó nhập tuần tự:

```text
1.1
2.2
7.2
```

Ý nghĩa:

1. `1.1`: config camera OV5640.
2. `2.2`: load weight từ SPI flash sang HyperRAM0 và verify CRC.
3. `7.2`: chạy camera result loop.

### 4.5 Chạy Demo Host + SoC Cùng Một Màn Hình

Từ root repo:

```bash
cd /home/raven1911/Data/Source_Thesis/Beta_AISoC_Firmware
source .venv-tf/bin/activate
cd software_golden_model_rps
python3 src/main.py --fullscreen
```

Trong GUI:

1. Chọn `Video Capture`, bấm `Connect`.
2. Chọn `UART`, chọn `Baud`, bấm `Connect`.
3. Có thể bấm `Refresh` hoặc `Reconnect` nếu rút/cắm lại capture card hoặc UART.

Nếu muốn tự kết nối sẵn lúc mở app:

```bash
python3 src/main.py --device 2 --uart-port /dev/ttyUSB0 --uart-baud 230400 --fullscreen
```

Trong terminal panel bên phải của dashboard, nhập:

```text
1.1
2.2
7.2
```

Phím tắt:

- `F11`: bật/tắt fullscreen.
- `Esc`: nếu đang fullscreen thì quay về dạng cửa sổ.
- `Enter`: gửi lệnh đang gõ trong ô command input xuống UART.

## 5. Build Và Flash Firmware

### 5.1 `builder.py`

Xem help:

```bash
./scripts/builder.py --help
```

Build app:

```bash
./scripts/builder.py --target app
```

Build bootloader:

```bash
./scripts/builder.py --target bootloader
```

Build app và bootloader:

```bash
./scripts/builder.py --target both
```

Build unit test:

```bash
./scripts/builder.py --target test_unit
```

Đổi kích thước `.mem` output, ví dụ 128 KB:

```bash
./scripts/builder.py --target app --max-flash-kb 128
```

Output chính:

```text
Build/main.elf
Build/main.bin
Build/main.hex
Build/main_disasm.s
Build/W25Q128JVxIM.mem
Build/bootloader.elf
Build/bootloader.bin
Build/bootloader.hex
Build/bootloader.mem
```

Lưu ý:

- `Build/main.bin` là boot image `BAI1`, không còn là flat binary chỉ chứa instruction.
- Nếu đổi bootloader hoặc linker, phải dùng bootloader mới tương ứng với image `BAI1`.

### 5.2 `host_flasher.py`

Flash app mặc định `Build/main.bin`:

```bash
./scripts/host_flasher.py /dev/ttyUSB0
```

Chỉ rõ file cần flash:

```bash
./scripts/host_flasher.py /dev/ttyUSB0 Build/main.bin
```

Flash có debug frame:

```bash
./scripts/host_flasher.py --debug /dev/ttyUSB0 Build/main.bin
```

Đổi chunk size:

```bash
./scripts/host_flasher.py --chunk-size 64 /dev/ttyUSB0
```

Flash xong giữ lại monitor UART:

```bash
./scripts/host_flasher.py --monitor /dev/ttyUSB0
```

Chỉ mở terminal UART, không flash:

```bash
./scripts/host_flasher.py /dev/ttyUSB0 --terminal-only
```

Nếu UART nhiễu, có thể tăng độ bảo thủ:

```bash
./scripts/host_flasher.py \
  --chunk-size 64 \
  --write-timeout 2.0 \
  --write-delay 0.001 \
  /dev/ttyUSB0
```

`host_flasher.py` dùng protocol:

1. `CMD_GET_CAP`
2. `CMD_INFO`
3. `CMD_ERASE`
4. `CMD_WRITE`
5. `CMD_VERIFY`
6. `CMD_JUMP`

## 6. Weight Và Model ALL-CNN-C-160

### 6.1 Tạo Weight Blob

Script:

```bash
./scripts/pack_allcnnc160_from_tflite.py --help
```

Ví dụ:

```bash
./scripts/pack_allcnnc160_from_tflite.py \
  --model-dir "/path/to/model_export_dir" \
  --bin-out Build/allcnnc_160_packed_weights.bin \
  --hex-out Build/allcnnc_160_packed_weights.hex
```

Thư mục `--model-dir` cần có ít nhất:

```text
all_cnn_c_160_rps_int8_per_layer.tflite
all_cnn_c_160_rps_fixed_params_per_layer.json
```

Script sẽ:

- đọc weight tensor và bias int32 từ model export,
- pack theo layout accelerator/HyperRAM,
- xuất `.bin` và/hoặc `.hex`,
- tạo blob đúng thứ tự filter và bias cho 15 layer.

### 6.2 Gửi Weight Xuống Flash

Xem help:

```bash
./scripts/uart_weight_sender.py --help
```

Ví dụ thường dùng:

```bash
./scripts/uart_weight_sender.py \
  --port /dev/ttyUSB0 \
  --input Build/allcnnc_160_packed_weights.hex
```

Ví dụ nếu cần chỉ rõ baud và offset:

```bash
./scripts/uart_weight_sender.py \
  --port /dev/ttyUSB0 \
  --input Build/allcnnc_160_packed_weights.hex \
  --baud 230400 \
  --flash-offset 0x00200000
```

Script chấp nhận:

- `.bin`
- raw `.hex`
- raw `.mem`

Sau khi truyền thành công, firmware ghi metadata để lệnh `2.2` biết:

- base flash offset,
- size,
- CRC32.

### 6.3 Load Weight Sang HyperRAM0

Trong UART menu, chạy:

```text
2.2
```

Flow `2.2`:

1. đọc metadata tại `0x001FF000`,
2. đọc payload từ flash offset ghi trong metadata,
3. copy sang HyperRAM0 tại `0x00000000`,
4. verify CRC32 giữa flash và HyperRAM,
5. in lỗi nếu metadata/CRC không khớp.

Nếu thấy lỗi kiểu:

```text
SPI flash CRC32 does not match weight metadata.
```

thì cần kiểm tra lại file đã nạp, vùng flash `0x00200000`, và metadata sector `0x001FF000`.

### 6.4 Sinh Code Accelerator Từ TFLite Và Tạo Flash Image

Script generic cho model convolution int8:

```bash
./scripts/generate_cnn_accel_app_from_tflite.py --help
```

Khuyến nghị đặt mỗi model trong một folder riêng, và **tên folder chính là tên module C được generate**:

```text
Beta_AISoC_Firmware/
└── models/
    └── allcnnc_96_qat_sympad/
        ├── model.tflite
        └── fixed_params.json
```

Trong folder model, script sẽ tự tìm:

- `<tên_folder>.tflite`, hoặc `model.tflite`, hoặc file `.tflite` duy nhất trong folder,
- file `*fixed_params*.json` hoặc `*params*.json` nếu có.

Nếu muốn IFMAP layer đầu lấy trực tiếp từ camera, phần chuẩn hóa và input quantization được gộp vào LUT theo công thức:

```text
q_in = clamp_int8(round(((pixel / pixel_denominator - mean[channel]) / std[channel]) / input_scale)
                  + input_zero_point)
```

Generator sẽ ưu tiên dùng sẵn `input.fixed` nếu JSON có:

```json
{
  "input": {
    "model_color_order": "RGB",
    "fixed": {
      "shift": 23,
      "mult": [8365456, 8258730, 8212540],
      "offset": [-1071980823, -1077884680, -1036059575]
    }
  }
}
```

Nếu chưa có `input.fixed`, generator có thể tự tính các số này từ:

- `input.mean`
- `input.std`
- `input.pixel_denominator`
- `input.tensor.scale` hoặc quantization scale trong `.tflite`
- `input.tensor.zero_point` hoặc quantization zero-point trong `.tflite`

Khi đủ thông tin, generator tự sinh:

- `VideoStreaming_ResizeConfig_t` theo kích thước input model, mặc định camera `640x480`,
- `VideoStreaming_PreprocessConfig_t` từ `input.fixed` hoặc từ normalization + quantization,
- hàm `RunCameraTimingOnly()` và `RunCameraResultLoop()`,
- logic grant camera IFMAP cho layer đầu giống file mẫu `allcnnc_96_qat_sympad_accel.c`.

Nếu muốn bắt buộc phải sinh camera path và báo lỗi khi thiếu config:

```bash
./scripts/generate_cnn_accel_app_from_tflite.py \
  --model-dir models/allcnnc_96_qat_sympad \
  --build-dir Build \
  --camera-ifmap on
```

Flow khuyến nghị khi đổi sang model mới:

```bash
./scripts/generate_cnn_accel_app_from_tflite.py \
  --model-dir models/allcnnc_96_qat_sympad \
  --build-dir Build
```

Sau đó kiểm tra app đã gọi đúng module vừa sinh, rồi build lại app:

```bash
./scripts/builder.py --target app
```

Cuối cùng tạo flash image 16MB để nạp bằng IMSProg, dùng `Build/main.bin` vừa build và weight/bias vừa generate:

```bash
./scripts/generate_cnn_accel_app_from_tflite.py \
  --model-dir models/allcnnc_96_qat_sympad \
  --build-dir Build \
  --no-c \
  --emit-flash-image \
  --flash-bin-out Build/flash_images/flash_instructions_with_allcnnc_96_qat_sympad_weights.bin
```

Nếu cần thêm Intel HEX cùng nội dung flash image:

```bash
./scripts/generate_cnn_accel_app_from_tflite.py \
  --model-dir models/allcnnc_96_qat_sympad \
  --build-dir Build \
  --no-c \
  --emit-flash-image \
  --flash-bin-out Build/flash_images/flash_instructions_with_allcnnc_96_qat_sympad_weights.bin \
  --flash-ihex-out Build/flash_images/flash_instructions_with_allcnnc_96_qat_sympad_weights.hex
```

Mặc định `--emit-flash-image` sẽ:

- lấy app hiện tại từ `Build/main.bin`, không tự compile app,
- pack weight/bias vừa sinh ra theo layout accelerator,
- đặt payload weight/bias vào SPI flash tại `0x00200000`,
- ghi metadata tại `0x001FF000`,
- tạo flash image 16MB, không ghi trực tiếp lên chip.

Các file sinh ra theo ví dụ trên:

```text
App/Src/allcnnc_96_qat_sympad_accel.c
App/Inc/allcnnc_96_qat_sympad_accel.h
Build/allcnnc_96_qat_sympad_packed_weights.bin
Build/allcnnc_96_qat_sympad_packed_weights.hex
Build/allcnnc_96_qat_sympad_accel_manifest.json
Build/flash_images/flash_instructions_with_allcnnc_96_qat_sympad_weights.bin
```

Sau khi nạp file `.bin` bằng IMSProg, trên UART vẫn cần chạy lệnh load flash sang HyperRAM0 trước khi inference:

```text
2.2
```

## 7. UART Menu Trên SoC

### 7.1 Menu Mặc Định Hiện Tại

Với macro hiện tại trong `App/Src/main.c`, menu mặc định có:

| Lệnh | Chức năng |
| --- | --- |
| `1.1` | Config OV5640 camera |
| `1.2` | Reset OV5640 bằng I2C |
| `1.3` | Reset video IP |
| `1.4` | Enable/disable video IP |
| `1.5` | Apply OV5640 default ISP |
| `1.6` | Tắt lens correction |
| `1.7` | Freeze AWB |
| `1.8` | Apply manual R/B gain |
| `1.9` | Apply neutral lens correction |
| `2.1` | Vào chế độ update weights qua UART |
| `2.2` | Load weights từ flash sang HyperRAM0 |
| `3.1` | Test HyperRAM ports |
| `7.1` | Chạy ALL-CNN-C-160 timing-only |
| `7.2` | Chạy ALL-CNN-C-160 camera result loop |

Các menu `4.x`, `5.x`, `6.x` vẫn còn trong source nhưng chỉ hiện nếu bật lại macro tương ứng:

```c
ENABLE_ALLCNN_CPU_MENU
ENABLE_ALLCNN_ACCEL_MENU
ENABLE_VGG16_MENU
ENABLE_VGG16_CPU_MENU
ENABLE_SQUEEZENET_MENU
```

### 7.2 Chuỗi Lệnh Thường Dùng

Demo camera live:

```text
1.1 -> 2.2 -> 7.2
```

Chỉ đo timing:

```text
1.1 -> 2.2 -> 7.1
```

Cập nhật weight mới rồi chạy lại:

```text
2.1  # thường script uart_weight_sender.py gửi tự động
2.2
7.2
```

Kiểm tra HyperRAM:

```text
3.1
```

### 7.3 Ghi Chú Riêng Cho `7.1` Và `7.2`

`7.1`:

- chạy 15 conv layer trên accelerator,
- final global average pooling chạy trên CPU,
- in cycle, thời gian ms và cycles / 1000 MACs.

`7.2`:

- nhận IFMAP layer đầu từ camera/resize path,
- trả video grant sau layer 1,
- chạy các layer còn lại bằng accelerator,
- chỉ in nhãn `paper`, `rock`, `scissors` trên một dòng UART động để giảm độ trễ.

### 7.4 Benchmark Cũ: ALL_CNN_C CIFAR-10 CPU-only Vs Accelerator

Phần này là số đo cũ của model `ALL_CNN_C CIFAR-10` trên ảnh test `cat`, không phải model camera `ALL-CNN-C-160` đang dùng cho demo hiện tại. Source benchmark vẫn còn trong:

```text
App/Src/allcnn_cifar10.c
App/Src/allcnn_cifar10_accel.c
```

Để hiện lại menu `4.x`, bật các macro sau trong `App/Src/main.c`, rồi build lại app:

```c
#define ENABLE_ALLCNN_CPU_MENU   1
#define ENABLE_ALLCNN_ACCEL_MENU 1
```

Flow CPU-only:

```text
2.2 -> 4.6 -> 4.0
```

Flow accelerator full model:

```text
2.2 -> 4.3 -> 4.4
```

Lệnh `4.4` chỉ chạy full model bằng dữ liệu hiện đang có trong HyperRAM. Nếu chỉ cần chạy timing thì có thể gọi thẳng `4.4`; nếu cần kết quả đúng thì chạy đủ `2.2 -> 4.3 -> 4.4`.

Thông số CPU-only đã đo:

| Mục | Cycles | Thời gian | Ghi chú |
| --- | ---: | ---: | --- |
| Input load | `967800` | `4 ms` | HWC -> CHW sang HyperRAM0 |
| Conv layers | `30831062752` | `154155 ms` | 9 Conv2D layers |
| GlobalAvgPool | `121661` | `0 ms` | final `6x6` mean |
| Compute-only | `30831184413` | `154155 ms` | Conv + GlobalAvgPool |
| Stage sum | `30832152213` | `154160 ms` | Input load + compute |
| Wall section | `30833755629` | `154168 ms` | gồm thêm một ít UART status print |

Thông số khác của CPU-only:

| Mục | Giá trị |
| --- | ---: |
| Total Conv MACs | `270798336` |
| CPU throughput | `1756 kMAC/s` |
| Predicted class | `3 (cat)` |

Thông số accelerator đã đo:

| Mục | Cycles | Thời gian | Ghi chú |
| --- | ---: | ---: | --- |
| Accelerator conv layers | `20269536` | `101 ms` | workload `281174016 MACs` |
| Global average pool CPU | `333898` | `1 ms` | hậu xử lý cuối |
| Model total measured stages | `20603434` | `103 ms` | conv + avgpool |
| Wall-clock section | `44387845` | `221 ms` | gồm UART/log overhead |

Thông số khác của accelerator:

| Mục | Giá trị |
| --- | ---: |
| Conv cost | `72 cycles / 1000 MACs` |
| Predicted class | `3 (cat)` |

Bảng so sánh trực tiếp:

| Chỉ số | CPU-only | CNN accelerator |
| --- | ---: | ---: |
| Conv/compute cycles | `30831184413` | `20603434` |
| Conv/compute time | `154155 ms` | `103 ms` |
| Wall section cycles | `30833755629` | `44387845` |
| Wall section time | `154168 ms` | `221 ms` |
| Predicted class | `3 (cat)` | `3 (cat)` |

Speedup từ lần đo cũ:

| Cách so | Kết quả |
| --- | ---: |
| Measured compute/model stages | khoảng `1496x` nhanh hơn CPU |
| Wall section khi còn bật UART/log | khoảng `695x` nhanh hơn CPU |

Khi dùng các số này để báo cáo, nên ghi rõ đây là benchmark của flow `ALL_CNN_C CIFAR-10` cũ. Model camera `ALL-CNN-C-160` mới có shape, số lớp và workload khác, nên không dùng trực tiếp các số trên để suy ra speedup của flow `7.x`.

## 8. Golden Model Host App

### 8.1 Mục Đích

`software_golden_model_rps` dùng để:

- nhận video từ capture card,
- chạy golden model TFLite trên host,
- hiển thị kết quả host cạnh kết quả UART từ SoC,
- có terminal để gửi menu command xuống SoC ngay trong cùng cửa sổ.

### 8.2 Kiểm Tra Capture Device

```bash
cd software_golden_model_rps
python3 list_capture_devices.py
```

GUI cũng có nút `Refresh` ở mục `Video Capture`, nên không bắt buộc chạy script này trước. Nếu script báo `Device 2: OK`, có thể chọn `2` trong GUI hoặc truyền sẵn:

```bash
python3 src/main.py --device 2
```

Nếu một đường dẫn kiểu `/dev/video2` mở được nhưng đọc frame lỗi, ưu tiên dùng index số mà `list_capture_devices.py` báo là OK.

Host app dùng chế độ capture low-latency: một thread nền đọc liên tục từ capture card và chỉ giữ frame mới nhất. Cách này giảm delay hiển thị do OpenCV/capture card buffer, đổi lại có thể bỏ qua frame cũ nếu inference trên host chậm hơn FPS camera.

### 8.3 Chạy Host App Không Kèm UART

Mở lại GUI golden model từ terminal mới:

```bash
cd /home/raven1911/Data/Source_Thesis/Beta_AISoC_Firmware
source .venv-tf/bin/activate
cd software_golden_model_rps
python src/main.py
```

Nếu đang đứng sẵn trong `software_golden_model_rps` và đã activate môi trường:

```bash
python3 src/main.py
```

Nếu GNOME taskbar hiện `Unknown` hoặc không hiện logo BK, cài lại launcher desktop:

```bash
cd /home/raven1911/Data/Source_Thesis/Beta_AISoC_Firmware
install -Dm644 software_golden_model_rps/bk-aisoc-golden-model.desktop \
  ~/.local/share/applications/bk-aisoc-golden-model.desktop
update-desktop-database ~/.local/share/applications
```

Trong GUI, chọn `Video Capture` rồi bấm `Connect`. Nếu không dùng SoC UART, để mục `UART` chưa kết nối.

### 8.4 Chạy Dashboard Host + BK-AISoC

```bash
python3 src/main.py --fullscreen
```

Trong GUI:

1. Chọn capture card ở `Video Capture`, bấm `Connect`.
2. Chọn cổng UART, chọn `Baud`, bấm `Connect`.
3. Dùng ô terminal phía dưới để gửi lệnh menu xuống SoC.

Vẫn có thể truyền sẵn cấu hình để app tự connect khi mở:

```bash
python3 src/main.py \
  --device 2 \
  --uart-port /dev/ttyUSB0 \
  --uart-baud 230400 \
  --fullscreen
```

Các option hay dùng:

```bash
python3 src/main.py --help
python3 src/main.py --window-width 1600 --window-height 900
python3 src/main.py --device 2 --window-width 1600 --window-height 900
python3 src/main.py --device 2 --uart-port /dev/ttyUSB0 --uart-baud 230400
python3 src/main.py --device 2 --uart-port /dev/ttyUSB0 --uart-newline lf
```

Dashboard hiện có:

- chọn/reconnect capture card trực tiếp trong GUI,
- chọn/reconnect UART port và `Baud` trực tiếp trong GUI,
- nhãn `Host Computer`,
- nhãn `BK-AISoC`,
- FPS host,
- FPS SoC đã trừ ước lượng thời gian truyền UART,
- độ phân giải stream,
- capture low-latency để giảm delay hiển thị,
- layout hai ô kết quả cố định, text dài sẽ được rút gọn thay vì đẩy layout,
- terminal UART có scrollbar,
- logo BK HCM ở phần stream,
- `F11` bật/tắt fullscreen,
- `Esc` thoát fullscreen về cửa sổ thường.

## 9. Cách Chạy Từng Script

### 9.1 Script Trong `Beta_AISoC_Firmware/scripts`

| Script | Dùng để làm gì | Ví dụ chạy |
| --- | --- | --- |
| `builder.py` | Build app, bootloader hoặc unit test | `./scripts/builder.py --target app` |
| `host_flasher.py` | Flash app qua bootloader, hoặc mở UART terminal | `./scripts/host_flasher.py /dev/ttyUSB0 Build/main.bin` |
| `uart_weight_sender.py` | Gửi weight blob xuống SPI flash qua UART | `./scripts/uart_weight_sender.py --port /dev/ttyUSB0 --input Build/allcnnc_160_packed_weights.hex` |
| `pack_allcnnc160_from_tflite.py` | Pack weight/bias từ model export sang layout accelerator | `./scripts/pack_allcnnc160_from_tflite.py --model-dir "/path/to/model_dir" --hex-out Build/allcnnc_160_packed_weights.hex` |
| `generate_cnn_accel_app_from_tflite.py` | Sinh C accelerator, camera config, packed weight/bias, manifest và flash image một model | `./scripts/generate_cnn_accel_app_from_tflite.py --model-dir models/allcnnc_96_qat_sympad --build-dir Build --emit-flash-image` |
| `make_flash_image_with_weights.py` | Ghép app `main.bin` với một hoặc nhiều payload weight vào image SPI flash 16MB | `./scripts/make_flash_image_with_weights.py --app Build/main.bin --weight-slot model:0x001FF000:0x00200000:Build/model_packed_weights.bin --bin-out Build/flash_images/flash_model.bin` |
| `capture_dataset.py` | Capture ảnh có nhãn từ camera/capture card | `./scripts/capture_dataset.py --device 2 --label rock --out dataset_capture/raw --show-32` |
| `list_video_devices.py` | Dò `/dev/video*` bằng OpenCV | `./scripts/list_video_devices.py --read-frame` |
| `allcnn_uart_accuracy.py` | Accuracy stream cho flow ALL_CNN_C CIFAR-10 cũ | `./scripts/allcnn_uart_accuracy.py --port /dev/ttyUSB0 --count 100` |
| `generate_cnn_hyperram_preload.py` | Tạo file preload HyperRAM cho testbench CNN cũ | `./scripts/generate_cnn_hyperram_preload.py --hr0-out /tmp/hr0.mem --hr1-out /tmp/hr1.mem` |
| `run_squeezenet_capture.py` | Chạy SqueezeNet host capture thử nghiệm | `./scripts/run_squeezenet_capture.py --device 2 --cpu` |

Một số ví dụ cụ thể:

Capture dataset thủ công:

```bash
./scripts/capture_dataset.py \
  --device 2 \
  --label rock \
  --out dataset_capture/raw \
  --show-32
```

Capture dataset tự động mỗi 0.5 giây, tối đa 100 ảnh:

```bash
./scripts/capture_dataset.py \
  --device 2 \
  --label paper \
  --count 100 \
  --interval 0.5 \
  --fullscreen
```

Probe video devices:

```bash
./scripts/list_video_devices.py --read-frame
```

Accuracy stream cũ:

```bash
./scripts/allcnn_uart_accuracy.py \
  --port /dev/ttyUSB0 \
  --count 100 \
  --progress-every 10
```

### 9.2 Script Trong `software_golden_model_rps`

| Script | Dùng để làm gì | Ví dụ chạy |
| --- | --- | --- |
| `list_capture_devices.py` | Dò device index đọc frame được | `python3 list_capture_devices.py` |
| `src/main.py` | Chạy golden model host app | `python3 src/main.py --fullscreen` |

## 10. Bash Autocomplete

Source file completion:

```bash
source Beta_AISoC_Firmware/scripts/beta_aisoc_completion.bash
```

Nếu đang đứng trong thư mục firmware:

```bash
source scripts/beta_aisoc_completion.bash
```

Ví dụ dùng `Tab`:

```bash
./scripts/builder.py --<Tab><Tab>
./scripts/host_flasher.py --<Tab><Tab>
./scripts/uart_weight_sender.py --<Tab><Tab>
./scripts/capture_dataset.py --<Tab><Tab>
```

Nếu đang đứng trong `software_golden_model_rps`:

```bash
python3 src/main.py --<Tab><Tab>
python3 src/main.py --device <Tab><Tab>
python3 src/main.py --uart-port <Tab><Tab>
python3 src/main.py --backend <Tab><Tab>
```

Completion hiện có gợi ý cho:

- option CLI,
- camera index và `/dev/video*`,
- UART port như `/dev/ttyUSB0`, `/dev/ttyACM0`,
- backend,
- resize mode,
- baudrate,
- file model và file stats,
- các option mới của `capture_dataset.py` như `--fullscreen`, `--preview-scale`, `--person-target`.

Để tự bật mỗi lần mở terminal, thêm vào `~/.bashrc`:

```bash
source /home/raven1911/Data/Source_Thesis/Beta_AISoC_Firmware/Beta_AISoC_Firmware/scripts/beta_aisoc_completion.bash
```

Sau đó reload:

```bash
source ~/.bashrc
```

## 11. Flash Map Và Output Quan Trọng

### 11.1 SPI Flash Map

| Vùng | Địa chỉ | Ghi chú |
| --- | --- | --- |
| Boot metadata | `0x00000000` | bootloader |
| App image | từ `0x00001000` | boot image `BAI1` |
| Weight metadata | `0x001FF000` | `WeightMetadata_t` |
| Weight payload mặc định | `0x00200000` | model blob |

Các define liên quan:

```text
App/Inc/weight_receiver.h
App/Inc/weight_hyperram_loader.h
```

### 11.2 HyperRAM Map Của Flow Hiện Tại

| Dữ liệu | Nơi chứa | Ghi chú |
| --- | --- | --- |
| Weight + bias ALL-CNN-C-160 | HyperRAM0 từ `0x00000000` | được `2.2` load từ SPI flash |
| Activation / IFMAP / OFMAP | HyperRAM1 | accelerator dùng trong lúc chạy model |

### 11.3 Output Weight

Các file thường gặp:

```text
Build/allcnnc_160_packed_weights.bin
Build/allcnnc_160_packed_weights.hex
Build/allcnn_cifar10_weights.hex
Build/<model>_packed_weights.bin
Build/<model>_packed_weights.hex
Build/<model>_accel_manifest.json
Build/flash_images/flash_instructions_with_<model>_weights.bin
Build/weight_payloads/
```

Trong đó:

- `allcnnc_160_packed_weights.*`: model camera mới.
- `allcnn_cifar10_weights.hex`: flow CIFAR-10 cũ.
- `<model>_packed_weights.*`: weight/bias đã được repack đúng layout accelerator từ `generate_cnn_accel_app_from_tflite.py`.
- `flash_images/`: nơi để các image SPI flash 16MB dùng cho IMSProg.
- `weight_payloads/`: nơi gom payload weight/bias riêng nếu muốn quản lý tách khỏi flash image.

## 12. Các File Nên Đọc Khi Sửa Code

### 12.1 Firmware App

| File | Vai trò |
| --- | --- |
| `App/Src/main.c` | UART menu, macro bật/tắt các flow |
| `App/Src/allcnnc_160_accel.c` | 15 layer ALL-CNN-C-160, `7.1`, `7.2` |
| `App/Inc/allcnnc_160_accel.h` | API của flow 160 |
| `App/Src/weight_receiver.c` | protocol nhận weight qua UART |
| `App/Src/weight_hyperram_loader.c` | load flash -> HyperRAM và verify CRC |
| `App/Inc/weight_receiver.h` | flash offset + metadata offset |
| `App/Inc/weight_hyperram_loader.h` | cấu hình HyperRAM loader |

### 12.2 Host Tools

| File | Vai trò |
| --- | --- |
| `scripts/builder.py` | build firmware image |
| `scripts/host_flasher.py` | bootloader flasher + UART monitor |
| `scripts/uart_weight_sender.py` | nạp weight qua UART |
| `scripts/pack_allcnnc160_from_tflite.py` | pack model export thành blob accelerator |
| `scripts/beta_aisoc_completion.bash` | Bash completion |

### 12.3 Golden Model Host App

| File | Vai trò |
| --- | --- |
| `software_golden_model_rps/config.py` | cấu hình mặc định |
| `software_golden_model_rps/src/main.py` | entrypoint app |
| `software_golden_model_rps/src/preprocessing.py` | preprocess host |
| `software_golden_model_rps/src/model_inference.py` | load/chạy TFLite |
| `software_golden_model_rps/src/uart_console.py` | đọc/gửi UART và tính FPS SoC |
| `software_golden_model_rps/src/qt_dashboard.py` | dashboard Qt |

## 13. Sử Dụng SoC HAL

Các driver HAL nằm trong:

```text
Beta_AISoC_Firmware/Drivers/SoC_HAL
```

Trong app, thường chỉ cần include `main.h` vì `App/Inc/main.h` đã include `soc_hal.h`:

```c
#include "../Inc/main.h"
```

Hoặc include trực tiếp:

```c
#include "soc_hal.h"
```

Module HAL được bật/tắt trong:

```text
Beta_AISoC_Firmware/App/Inc/soc_hal_config.h
```

Hiện tại các module đang dùng chính gồm UART, SPI, I2C, HyperRAM, timer, GPIO, video streaming, interrupt và mem.

### 13.1 Bảng Base Address Ngoại Vi

Các địa chỉ phần mềm đang khớp với address map phần cứng hiện tại:

| Ngoại vi | Instance 0 | Instance 1 | Ghi chú |
| --- | --- | --- | --- |
| UART | `UART0_BASE_ADDR = 0x02002000` | `UART1_BASE_ADDR = 0x02002100` | HAL có `uart_0`, `uart_1`. |
| SPI | `SPI0_BASE_ADDR = 0x02003000` | `SPI1_BASE_ADDR = 0x02003100` | HAL có `spi0`, `spi1`. |
| I2C | `I2C0_BASE_ADDR = 0x02004000` | `I2C1_BASE_ADDR = 0x02004100` | HAL có `i2c0`, `i2c1`. |
| HyperRAM | `HYPERRAM_0_BASE_ADDR = 0x02005000` | `HYPERRAM_1_BASE_ADDR = 0x02005100` | HAL có `hyperram0`, `hyperram1`. |
| Timer | `TIMER0_BASE_ADDR = 0x02006000` | - | Hiện có 1 timer AXI-Lite. |
| GPIO | `GPIO_BASE_ADDR = 0x02007000` | - | Hiện có 1 port GPIO 8-bit. |
| Video Streaming | `VIDEO_STREAMING_BASE_ADDR = 0x02008000` | - | Hiện có 1 block video streaming. |
| CNN Accelerator | `CNN_ACCEL_BASE_ADDR = 0x02009000` | - | AXI-Lite wrapper cho khối CNN accelerator. |

Các bảng dưới đây dùng offset tính từ base của từng instance. Ví dụ UART1 thanh ghi TX data là `UART1_BASE_ADDR + 0x0C`.

#### UART Register Map

Áp dụng cho `UART0_BASE_ADDR` và `UART1_BASE_ADDR`.

| Offset | Tên trong HAL | R/W | Ý nghĩa |
| --- | --- | --- | --- |
| `0x00` | `UART_RX_STATUS_REG_WORD_OFFSET` | R | `[7:0]` RX data, `[8]` RX_EMPTY, `[9]` TX_FULL. |
| `0x04` | `UART_TX_STATUS_REG_WORD_OFFSET` | R | Status TX/RX; HAL dùng bit `[9]` để kiểm tra TX_FULL. |
| `0x08` | `UART_DVSR_REG_WORD_OFFSET` | W | `[10:0]` baud divisor. Driver tính từ `SYS_CLK_FREQ / (16 * baud) - 1`. |
| `0x0C` | `UART_TX_REG_WORD_OFFSET` | W | `[7:0]` TX data, ghi vào đây để gửi 1 byte. |

#### SPI Register Map

Áp dụng cho `SPI0_BASE_ADDR` và `SPI1_BASE_ADDR`.

| Offset | Tên trong HAL | R/W | Ý nghĩa |
| --- | --- | --- | --- |
| `0x00` | `SPI_READ_REG_OFFSET` | R | `[7:0]` RX data, `[8]` READY. |
| `0x04` | `SPI_SS_REG_OFFSET` | W | Slave-select output `spi_ss_n`. HAL ghi `~slave_selection_mask` vì chân SS active-low. |
| `0x08` | `SPI_DATA_REG_OFFSET` | W | `[7:0]` TX data, ghi vào đây để start transfer. |
| `0x0C` | `SPI_CTRL_REG_OFFSET` | W | `[15:0]` divider, `[16]` CPOL, `[17]` CPHA. |

#### I2C Register Map

Áp dụng cho `I2C0_BASE_ADDR` và `I2C1_BASE_ADDR`.

| Offset | Tên trong HAL | R/W | Ý nghĩa |
| --- | --- | --- | --- |
| `0x00` | `I2C_DATA_REG` | R | `[7:0]` data out, `[8]` READY, `[9]` ACK. ACK = 0 nghĩa là slave acknowledge. |
| `0x04` | `I2C_DVSR_REG` | W | `[15:0]` clock divisor. Driver tính `clk_freq / (4 * i2c_freq) - 1`. |
| `0x08` | `I2C_CMD_REG` | W | `[10:8]` command, `[7:0]` data/nack. Command: `0` START, `1` WRITE, `2` READ, `3` STOP, `4` RESTART. |

#### HyperRAM Register Map

Áp dụng cho `HYPERRAM_0_BASE_ADDR` và `HYPERRAM_1_BASE_ADDR`.

| Offset | Tên trong struct | R/W | Ý nghĩa |
| --- | --- | --- | --- |
| `0x00` | `reg_cmd_upper` | R/W | `[15:0]` upper command/address. |
| `0x04` | `reg_cmd_lower` | R/W | `[31:0]` lower command/address. |
| `0x08` | `reg_config` | R/W | `[7:0]` burst_len, `[11:8]` latency, `[15:12]` recovery, `[17:16]` capture_shmoo. |
| `0x0C` | `reg_control` | R/W | `[7:0]` write data, `[8]` write FIFO push, `[9]` read FIFO pop, `[10]` start. |
| `0x10` | `reg_status` | R | `[7:0]` read data, `[8]` FIFO full, `[9]` FIFO empty, `[10]` start_ready. |
| `0x14` | `reg_mode` | R/W | `[0]` accel mode, `[1]` reserved, `[16:2]` DMAC write weight, `[31:17]` DMAC read weight. |

#### Timer Register Map

Áp dụng cho `TIMER0_BASE_ADDR`.

| Offset | Tên trong HAL | R/W | Ý nghĩa |
| --- | --- | --- | --- |
| `0x00` | `TIMER_COUNTER_UPPER_OFFSET` | R | Upper counter bits, phần trên của counter 50-bit. |
| `0x04` | `TIMER_COUNTER_LOWER_OFFSET` | R | Lower counter bits `[31:0]`. |
| `0x08` | `TIMER_CONTROL_OFFSET` | W | `[0]` start counter, `[1]` clear counter. |

#### GPIO Register Map

Áp dụng cho `GPIO_BASE_ADDR`.

| Offset | Tên trong HAL | R/W | Ý nghĩa |
| --- | --- | --- | --- |
| `0x00` | `GPIO_DEFINE_IO_OFFSET` | R/W | `[7:0]` direction, `1` là output, `0` là input; `[8]` write enable. |
| `0x04` | `GPIO_WRITE_PORT_OFFSET` | R/W | `[7:0]` output data latch. |
| `0x08` | `GPIO_READ_PORT_OFFSET` | R | `[7:0]` input pin state. |

#### Video Streaming Register Map

Áp dụng cho `VIDEO_STREAMING_BASE_ADDR`.

| Offset | Tên trong HAL | R/W | Ý nghĩa |
| --- | --- | --- | --- |
| `0x00` | `VIDEO_STREAMING_SCALE_MULT_OFFSET` | R/W | `int32_t` scale multiplier. |
| `0x04` | `VIDEO_STREAMING_SCALE_SHIFT_OFFSET` | R/W | `[5:0]` scale shift. |
| `0x08` | `VIDEO_STREAMING_ZERO_POINT_OFFSET` | R/W | `[7:0]` zero point. |
| `0x0C` | `VIDEO_STREAMING_CONTROL_OFFSET` | R/W | `[0]` enable video system, `[1]` grant request. |
| `0x10` | `VIDEO_STREAMING_RESERVED4_OFFSET` | - | Reserved, hiện chưa dùng trong driver. |
| `0x14` | `VIDEO_STREAMING_RESERVED5_OFFSET` | - | Reserved, hiện chưa dùng trong driver. |

#### CNN Accelerator Register Map

Áp dụng cho `CNN_ACCEL_BASE_ADDR`. Các offset bên dưới là byte offset từ base address. Trong driver C, các macro `CNN_ACCEL_*_WORD_OFFSET` là word offset, nên byte offset bằng `word_offset * 4`.

| Offset | Tên trong HAL | R/W | Ý nghĩa |
| --- | --- | --- | --- |
| `0x00` | `CNN_ACCEL_START_WORD_OFFSET` | W | Ghi `1` để start layer đã submit. Đây là pulse start. |
| `0x04` | `CNN_ACCEL_STATUS_WORD_OFFSET` | R | Status: `[0] table_valid`, `[1] table_ready`, `[2] busy`, `[3] done`, `[4] start`. |
| `0x08` | `CNN_ACCEL_IFHEIGHT_WORD_OFFSET` | W | Chiều cao input feature map. Hiện flow dùng feature map vuông nên width = height. |
| `0x0C` | `CNN_ACCEL_IFCHANNEL_WORD_OFFSET` | W | Số kênh input, driver mask `11 bit`. |
| `0x10` | `CNN_ACCEL_OFCHANNEL_WORD_OFFSET` | W | Số kênh output, driver mask `11 bit`. |
| `0x14` | `CNN_ACCEL_HF_WORD_OFFSET` | W | Kích thước kernel/filter, ví dụ `3` cho `3x3`, driver mask `4 bit`. |
| `0x18` | `CNN_ACCEL_STRIDE_WORD_OFFSET` | W | Stride, driver mask `3 bit`. |
| `0x1C` | `CNN_ACCEL_PADDING_WORD_OFFSET` | W | Padding, driver mask `2 bit`. |
| `0x20` | `CNN_ACCEL_IFPARR_WORD_OFFSET` | W | Mức song song input-channel của accelerator. |
| `0x24` | `CNN_ACCEL_OFTILE_WORD_OFFSET` | W | Số tile output-channel trong một nhóm config. |
| `0x28` | `CNN_ACCEL_OFPARR_WORD_OFFSET` | W | Mức song song output-channel của accelerator. |
| `0x2C` | `CNN_ACCEL_IFBADDR_WORD_OFFSET` | W | Base byte address IFMAP trong HyperRAM1. Driver mask `24 bit`. |
| `0x30` | `CNN_ACCEL_FLTBADDR_WORD_OFFSET` | W | Base byte address filter/weight packed trong HyperRAM0. Driver mask `24 bit`. |
| `0x34` | `CNN_ACCEL_BIAS_BADDR_WORD_OFFSET` | W | Base byte address bias packed trong HyperRAM0. Driver mask `24 bit`. |
| `0x38` | `CNN_ACCEL_OFBADDR_WORD_OFFSET` | W | Base byte address OFMAP trong HyperRAM1. Driver mask `24 bit`. |
| `0x3C` | `CNN_ACCEL_IFC_ZP_WORD_OFFSET` | W | Input zero-point, dùng `int8_t` ở `[7:0]`. |
| `0x40` | `CNN_ACCEL_FLTC_ZP_WORD_OFFSET` | W | Filter zero-point, dùng `int8_t` ở `[7:0]`. |
| `0x44` | `CNN_ACCEL_MULT_WORD_OFFSET` | W | Requant multiplier `int32_t`. |
| `0x48` | `CNN_ACCEL_MULT_SHIFT_WORD_OFFSET` | W | Requant shift, driver mask `6 bit`. |
| `0x4C` | `CNN_ACCEL_ALPHAMULT_WORD_OFFSET` | W | Leaky-ReLU alpha multiplier. Với ALL_CNN_C hiện set `0`. |
| `0x50` | `CNN_ACCEL_ALPHAMULT_SHIFT_WORD_OFFSET` | W | Leaky-ReLU alpha shift. Với ALL_CNN_C hiện set `0`. |
| `0x54` | `CNN_ACCEL_ZPY_WORD_OFFSET` | W | Output zero-point, dùng `int8_t` ở `[7:0]`. |
| `0x58` | `CNN_ACCEL_QMIN_WORD_OFFSET` | W | Clamp min, dùng `int8_t` ở `[7:0]`. |
| `0x5C` | `CNN_ACCEL_QMAX_WORD_OFFSET` | W | Clamp max, dùng `int8_t` ở `[7:0]`. |
| `0x60` | `CNN_ACCEL_IS_LEAKY_RELU_WORD_OFFSET` | W | `[0]` bật/tắt Leaky-ReLU. ALL_CNN_C hiện dùng `0`. |
| `0x64` | `CNN_ACCEL_WRITE_FIFO_WORD_OFFSET` | W | Ghi `1` để commit toàn bộ config vào instruction table/config FIFO. |

Status bits:

| Bit | Tên trong HAL | Ý nghĩa |
| --- | --- | --- |
| `[0]` | `TABLE_VALID` | Có config đang valid/pending ở phía AXI-Lite wrapper. |
| `[1]` | `TABLE_READY` | Wrapper sẵn sàng nhận config layer mới. |
| `[2]` | `BUSY` | Accelerator đang chạy layer. |
| `[3]` | `DONE` | Layer đã xong. IRQ accel done cũng dựa vào sự kiện này. |
| `[4]` | `START` | Pulse/start state debug. |

IRQ của CNN accelerator đang nối vào `irq[3]`, tương ứng `IRQ_EXTERNAL0_BIT` / `CNN_ACCEL_IRQ_BIT`. Firmware không có thanh ghi AXI-Lite riêng để clear IRQ; PicoRV32 tạo `eoi` khi handler kết thúc bằng `retirq`.

Lưu ý quan trọng: các hàm high-level kiểu `Uart_begin()`, `Uart_write()`, `spi_begin()`, `spi_transfer()` hiện chỉ dùng instance 0. Muốn dùng cả instance 0 và 1, nên gọi các hàm low-level có tham số con trỏ driver.

### 13.2 UART0 Và UART1

Header/source:

```text
Drivers/SoC_HAL/Inc/UART_Driver.h
Drivers/SoC_HAL/Src/UART_Driver.c
```

API high-level mặc định chỉ dùng UART0:

```c
Uart_begin(115200);
Uart_print("Hello");
Uart_println(" UART0");
Uart_write('A');
```

Đọc 1 byte từ UART0:

```c
uint8_t rx;

if (Uart_available()) {
    if (Uart_read(&rx)) {
        Uart_write(rx);
    }
}
```

Dùng rõ ràng cả UART0 và UART1:

```c
Uart_create(&uart_0, UART0_BASE_ADDR);
Uart_init_baudrate(&uart_0, 115200);

Uart_create(&uart_1, UART1_BASE_ADDR);
Uart_init_baudrate(&uart_1, 115200);

Uart_write_byte(&uart_0, '0');
Uart_write_byte(&uart_1, '1');

Uart_write_string(&uart_0, "UART0 OK\n");
Uart_write_string(&uart_1, "UART1 OK\n");
```

Đọc riêng từng UART:

```c
uint8_t rx0;
uint8_t rx1;

if (Uart_read_byte(&uart_0, &rx0)) {
    Uart_write_byte(&uart_0, rx0);
}

if (Uart_read_byte(&uart_1, &rx1)) {
    Uart_write_byte(&uart_1, rx1);
}
```

Gợi ý dùng trong app:

```c
int main(void)
{
    Uart_create(&uart_0, UART0_BASE_ADDR);
    Uart_init_baudrate(&uart_0, 115200);

    Uart_create(&uart_1, UART1_BASE_ADDR);
    Uart_init_baudrate(&uart_1, 115200);

    while (1) {
        Uart_write_string(&uart_0, "A from UART0\n");
        Uart_write_string(&uart_1, "B from UART1\n");
        delay(1000);
    }
}
```

### 13.3 SPI0 Và SPI1

Header/source:

```text
Drivers/SoC_HAL/Inc/SPI_Driver.h
Drivers/SoC_HAL/Src/SPI_Driver.c
```

API high-level mặc định chỉ dùng SPI0:

```c
spi_begin();

spi_set_slave(SPI_SLAVE_0);
uint8_t rx = spi_transfer(0x9F);
spi_set_slave(SPI_SLAVE_NONE);
```

`spi_select_slave(spi, mask)` nhận mask slave cần chọn. Ví dụ `SPI_SLAVE_0` làm `ss_n[0]` xuống thấp. Muốn bỏ chọn tất cả, dùng `SPI_SLAVE_NONE`.

Dùng rõ ràng cả SPI0 và SPI1:

```c
spi_init(&spi0, SPI0_BASE_ADDR);
spi_configure(&spi0,
              SPI_CPOL_LOW,
              SPI_CPHA_LEADING,
              SYS_CLK_FREQ,
              10000000U);

spi_init(&spi1, SPI1_BASE_ADDR);
spi_configure(&spi1,
              SPI_CPOL_LOW,
              SPI_CPHA_LEADING,
              SYS_CLK_FREQ,
              10000000U);

spi_select_slave(&spi0, SPI_SLAVE_0);
spi_write_byte(&spi0, 0xAA);
spi_select_slave(&spi0, SPI_SLAVE_NONE);

spi_select_slave(&spi1, SPI_SLAVE_0);
spi_write_byte(&spi1, 0x55);
spi_select_slave(&spi1, SPI_SLAVE_NONE);
```

Đọc byte nếu phần cứng đã ready:

```c
int16_t value = spi_read_byte(&spi1);

if (value >= 0) {
    uint8_t rx = (uint8_t)value;
    Uart_write_byte(&uart_0, rx);
}
```

Gửi chuỗi qua một SPI instance:

```c
spi_select_slave(&spi1, SPI_SLAVE_0);
spi_write_string(&spi1, "Hello SPI1");
spi_select_slave(&spi1, SPI_SLAVE_NONE);
```

Lưu ý khi dùng hai SPI: các hàm `spi_begin()`, `spi_transfer()`, `spi_transfer_buffer()`, `spi_set_data_mode()`, `spi_set_clock_frequency()` và `spi_set_slave()` là wrapper cho SPI0. Khi đã dùng SPI1, ưu tiên gọi các hàm có tham số `SpiDriver_t *spi` như `spi_init`, `spi_configure`, `spi_select_slave`, `spi_write_byte`, `spi_read_byte`.

### 13.4 I2C0 Và I2C1

Header/source:

```text
Drivers/SoC_HAL/Inc/I2C_Driver.h
Drivers/SoC_HAL/Src/I2C_Driver.c
```

Khởi tạo I2C0 và I2C1 ở 100 kHz:

```c
I2C_driver_init(&i2c0, I2C0_BASE_ADDR);
I2C_init(&i2c0, SYS_CLK_FREQ, 100000U);

I2C_driver_init(&i2c1, I2C1_BASE_ADDR);
I2C_init(&i2c1, SYS_CLK_FREQ, 100000U);
```

Driver nhận địa chỉ slave dạng 7-bit. Driver tự shift trái và thêm bit read/write.

Ghi một buffer qua I2C0:

```c
uint8_t data[] = {0x12, 0x34, 0x56};
bool ok = I2C_write_transaction(&i2c0, 0x3C, data, sizeof(data), true);

if (!ok) {
    Uart_println("I2C0 write failed");
}
```

Đọc nhiều byte qua I2C1:

```c
uint8_t buffer[4];
bool ok = I2C_read_transaction(&i2c1, 0x3C, buffer, sizeof(buffer), true);

if (ok) {
    Uart_println("I2C1 read OK");
}
```

Ghi register rồi đọc data theo kiểu common sensor flow:

```c
uint8_t reg_addr = 0x0A;
uint8_t value = 0;

if (I2C_write_transaction(&i2c1, 0x3C, &reg_addr, 1, true)) {
    I2C_read_transaction(&i2c1, 0x3C, &value, 1, true);
}
```

Dùng OV5640 với bus mong muốn:

```c
I2C_driver_init(&i2c0, I2C0_BASE_ADDR);
I2C_init(&i2c0, SYS_CLK_FREQ, 100000U);
OV5640_Init(&i2c0);
```

Nếu camera nối sang I2C1:

```c
I2C_driver_init(&i2c1, I2C1_BASE_ADDR);
I2C_init(&i2c1, SYS_CLK_FREQ, 100000U);
OV5640_Init(&i2c1);
```

### 13.5 HyperRAM0 Và HyperRAM1

Header/source:

```text
Drivers/SoC_HAL/Inc/HyperRAM_Driver.h
Drivers/SoC_HAL/Src/HyperRAM_Driver.c
```

Driver HyperRAM đã có sẵn hai global instance giống style `spi0/spi1` và `i2c0/i2c1`:

```c
extern HyperRAM_Driver_t hyperram0;
extern HyperRAM_Driver_t hyperram1;
```

Khởi tạo cả hai HyperRAM:

```c
HyperRAM_init(&hyperram0, HYPERRAM_0_BASE_ADDR);
HyperRAM_init(&hyperram1, HYPERRAM_1_BASE_ADDR);
```

Cấu hình timing cơ bản:

```c
HyperRAM_set_config(&hyperram0,
                    0,   // capture_shmoo
                    4,   // recovery
                    6,   // latency
                    16); // burst_len

HyperRAM_set_config(&hyperram1, 0, 4, 6, 16);
```

Cấu hình thanh ghi mode `ADDR_REGISTERS_5`:

```c
HyperRAM_set_accel_mode(&hyperram0, true);
HyperRAM_set_dmac_weights(&hyperram0, 8, 8);

uint32_t mode = HyperRAM_read_mode_register(&hyperram0);
```

Set command/address rồi start transaction:

```c
HyperRAM_set_cmd_addr(&hyperram0,
                      0x00000000U, // lower 32-bit của command/address
                      0x0000U);    // upper 16-bit của command/address

while (!HyperRAM_is_start_ready(&hyperram0)) {
}

HyperRAM_start(&hyperram0);
```

Ghi burst:

```c
uint8_t tx_data[] = {0x11, 0x22, 0x33, 0x44};

HyperRAM_burst_write(&hyperram0, tx_data, sizeof(tx_data));
```

Đọc burst:

```c
uint8_t rx_data[4];

HyperRAM_burst_read(&hyperram1, rx_data, sizeof(rx_data));
```

Ghi/đọc từng byte nếu muốn tự kiểm soát FIFO:

```c
while (HyperRAM_is_full(&hyperram0)) {
}
HyperRAM_write_byte(&hyperram0, 0xAB);

while (HyperRAM_is_empty(&hyperram0)) {
}
uint8_t data = HyperRAM_read_byte(&hyperram0);
```

Lưu ý: `HYPERRAM_0_BASE_ADDR` và `HYPERRAM_1_BASE_ADDR` là hai vùng driver HyperRAM chính đang dùng trong app.

### 13.6 GPIO

Header/source:

```text
Drivers/SoC_HAL/Inc/GPIO_Driver.h
Drivers/SoC_HAL/Src/GPIO_Driver.c
```

GPIO hiện có một port 8-bit, pin `D0` tới `D7`.

Khởi tạo:

```c
gpio_init();
```

`gpio_init()` hiện set toàn bộ pin về input. Sau đó cấu hình từng pin:

```c
pinMode(D0, OUTPUT);
pinMode(D1, INPUT);
```

Ghi pin:

```c
DigitalWrite(D0, HIGH);
DigitalWrite(D0, LOW);
```

Đọc pin:

```c
uint8_t d1 = DigitalRead(D1);
```

Toggle pin:

```c
DigitalToggle(D0);
```

Ví dụ blink đơn giản:

```c
int main(void)
{
    gpio_init();
    timer_init();

    pinMode(D0, OUTPUT);

    while (1) {
        DigitalToggle(D0);
        delay(500);
    }
}
```

### 13.7 Timer Polling

Header/source:

```text
Drivers/SoC_HAL/Inc/timer.h
Drivers/SoC_HAL/Src/timer.c
```

Timer AXI-Lite hiện tại là `timer0`.

Khởi tạo và dùng delay:

```c
timer_init();

delay(1000);             // delay 1000 ms
delayMicroseconds(100);  // delay 100 us
```

Đọc thời gian:

```c
uint32_t t_ms = millis();
uint32_t t_us = micros();
```

Điều khiển counter:

```c
clear(); // clear counter
go();    // start counter
pause(); // stop counter
```

Ví dụ gửi UART mỗi 1 giây bằng polling:

```c
int main(void)
{
    Uart_begin(115200);
    timer_init();

    while (1) {
        Uart_write('A');
        delay(1000);
    }
}
```

### 13.8 Interrupt Và Timer Interrupt

Header/source:

```text
Drivers/SoC_HAL/Inc/Interrupt_Driver.h
Drivers/SoC_HAL/Src/Interrupt_Driver.c
```

PicoRV32 gom interrupt thành một vector. Firmware dispatcher đọc pending mask rồi gọi handler theo priority software.

Quy ước bit:

| Bit | Ý nghĩa |
| --- | --- |
| `IRQ_TIMER_BIT = 0` | Timer nội bộ PicoRV32. |
| `IRQ_EBREAK_BIT = 1` | ebreak. |
| `IRQ_BUSERROR_BIT = 2` | bus error. |
| `IRQ_EXTERNAL_BASE_BIT = 3` | bit đầu tiên nên dành cho ngoại vi tự thiết kế. |
| `IRQ_EXTERNAL0_BIT = 3` | external IRQ 0. |
| `IRQ_EXTERNAL1_BIT = 4` | external IRQ 1. |

Priority là software priority:

```c
IRQ_PRIORITY_HIGHEST  // 0
IRQ_PRIORITY_DEFAULT  // 128
IRQ_PRIORITY_LOWEST   // 255
```

Số nhỏ hơn nghĩa là ưu tiên cao hơn. Nếu nhiều IRQ pending cùng lúc, dispatcher xử lý priority cao trước; nếu cùng priority thì bit nhỏ hơn xử lý trước.

Ví dụ timer interrupt mỗi 1 ms gửi ký tự `A` qua UART:

```c
#include "../Inc/main.h"

static Timer_Config_t g_timer_1ms;
static volatile bool g_send_a = false;

void HAL_Timer_TimeoutCallback(const Timer_Config_t *htim)
{
    if (htim == &g_timer_1ms) {
        g_send_a = true;
    }
}

int main(void)
{
    Uart_begin(115200);

    IRQ_Init();
    HAL_Timer_SetPriority(IRQ_PRIORITY_HIGHEST);

    /*
     * SYS_CLK_FREQ = 200 MHz.
     * cycles = (Prescaler + 1) * Period = (199 + 1) * 1000 = 200000 cycles.
     * 200000 cycles / 200 MHz = 1 ms.
     */
    HAL_Timer_SetConfig(&g_timer_1ms,
                        SYS_CLK_FREQ,
                        199,
                        1000,
                        true);

    HAL_Timer_Init(&g_timer_1ms);
    HAL_Timer_Start();

    while (1) {
        if (g_send_a) {
            g_send_a = false;
            Uart_write('A');
        }
    }
}
```

Ví dụ attach một external interrupt:

```c
static volatile bool g_event_irq = false;

static void MyEvent_IRQHandler(uint32_t irq_bit, void *context)
{
    (void)context;

    if (irq_bit == IRQ_EXTERNAL0_BIT) {
        g_event_irq = true;

        /*
         * Nếu ngoại vi có thanh ghi pending/clear interrupt riêng,
         * cần clear cờ interrupt của ngoại vi tại đây.
         */
    }
}

int main(void)
{
    IRQ_Init();

    IRQ_Attach(IRQ_EXTERNAL0_BIT,
               MyEvent_IRQHandler,
               NULL,
               IRQ_PRIORITY_DEFAULT);

    IRQ_Enable(IRQ_EXTERNAL0_BIT);

    while (1) {
        if (g_event_irq) {
            g_event_irq = false;
            Uart_println("event irq");
        }
    }
}
```

Lưu ý phần cứng: firmware interrupt chỉ chạy khi input `irq[31:0]` của PicoRV32 được nối tới tín hiệu interrupt thật. Nếu top Verilog đang tie `irq` về `0`, software vẫn compile nhưng sẽ không có interrupt nào xảy ra.

### 13.9 Video Streaming

Header/source:

```text
Drivers/SoC_HAL/Inc/VideoStreaming_Driver.h
Drivers/SoC_HAL/Src/VideoStreaming_Driver.c
```

Khởi tạo block video streaming mặc định:

```c
VideoStreaming_begin();
```

Hoặc init explicit:

```c
VideoStreaming_init(&video_streaming, VIDEO_STREAMING_BASE_ADDR);
```

Cấu hình quantization:

```c
VideoStreaming_set_scale_multiplier(&video_streaming, -2);
VideoStreaming_set_scale_shift(&video_streaming, 10);
VideoStreaming_set_zero_point(&video_streaming, (int8_t)0x20);
```

Hoặc set một lần:

```c
VideoStreaming_set_quantization(&video_streaming,
                                -2,          // multiplier
                                10,          // shift
                                (int8_t)0x20 // zero point
);
```

Enable/disable stream:

```c
VideoStreaming_enable(&video_streaming, true);
VideoStreaming_enable(&video_streaming, false);
```

Grant request:

```c
VideoStreaming_set_grant_request(&video_streaming, true);

if (VideoStreaming_get_grant_request(&video_streaming)) {
    Uart_println("video grant requested");
}
```

Đọc lại cấu hình:

```c
int32_t mult = VideoStreaming_get_scale_multiplier(&video_streaming);
uint8_t shift = VideoStreaming_get_scale_shift(&video_streaming);
int8_t zp = VideoStreaming_get_zero_point(&video_streaming);
bool enabled = VideoStreaming_is_enabled(&video_streaming);
```

### 13.10 CNN Accelerator

Header/source:

```text
Drivers/SoC_HAL/Inc/CNN_Accel_Driver.h
Drivers/SoC_HAL/Src/CNN_Accel_Driver.c
```

Khởi tạo block CNN accelerator:

```c
CNN_Accel_begin();
```

Hoặc init explicit:

```c
CNN_Accel_init(&cnn_accel, CNN_ACCEL_BASE_ADDR);
```

Luồng submit một layer ở mức driver:

```c
CNN_Accel_LayerConfig_t cfg = {0};

cfg.ifheight = 32;
cfg.ifchannel = 3;
cfg.ofchannel = 96;
cfg.hf = 3;
cfg.stride = 1;
cfg.padding = 1;
cfg.ifparr = 3;
cfg.oftile = 1;
cfg.ofparr = 8;

cfg.ifbaddr = 0x00000000U;      // HyperRAM1 IFMAP byte address
cfg.fltbaddr = 0x00180000U;     // HyperRAM0 packed filter byte address
cfg.bias_baddr = 0x00180A20U;   // HyperRAM0 packed bias byte address
cfg.ofbaddr = 0x00000C00U;      // HyperRAM1 OFMAP byte address

cfg.ifc_zp = 0;
cfg.fltc_zp = 0;
cfg.mult = 1455152256;
cfg.mult_shift = 38;
cfg.alphamult = 0;
cfg.alphamult_shift = 0;
cfg.zpy = -128;
cfg.qmin = -128;
cfg.qmax = 127;
cfg.is_leaky_relu = false;

if (!CNN_Accel_submit_layer_config(&cnn_accel, &cfg, 10000000U)) {
    Uart_println("CNN config submit timeout");
}

CNN_Accel_start(&cnn_accel);

if (!CNN_Accel_wait_done(&cnn_accel, 20000000U)) {
    Uart_println("CNN done timeout");
}

if (!CNN_Accel_wait_idle(&cnn_accel, 10000000U)) {
    Uart_println("CNN idle timeout");
}
```

`CNN_Accel_submit_layer_config()` làm ba việc:

1. Chờ `TABLE_READY = 1`.
2. Ghi toàn bộ register config layer.
3. Ghi `CNN_ACCEL_WRITE_FIFO_WORD_OFFSET = 1` để commit config, rồi chờ `TABLE_VALID = 0` nghĩa là instruction table đã nhận config.

Nếu muốn dùng IRQ thay vì polling `DONE`:

```c
static volatile bool cnn_done_irq = false;

static void cnn_irq_handler(uint32_t irq_bit, void *context)
{
    (void)irq_bit;
    (void)context;
    cnn_done_irq = true;
}

IRQ_Init();
CNN_Accel_attach_irq(cnn_irq_handler, 0, IRQ_PRIORITY_DEFAULT);
CNN_Accel_enable_irq();

cnn_done_irq = false;
CNN_Accel_start(&cnn_accel);

while (!cnn_done_irq) {
}

CNN_Accel_disable_irq();
```

Khi chạy với HyperRAM DMA path, cần cấu hình thêm hai HyperRAM trước lúc start layer:

```c
HyperRAM_set_dmac_weights(&hyperram0, 1, 2);
HyperRAM_set_dmac_weights(&hyperram1, 1, 2);
HyperRAM_set_accel_mode(&hyperram0, true);
HyperRAM_set_accel_mode(&hyperram1, true);
```

Với ảnh tĩnh trong HyperRAM, phải tắt grant video để IFBUF nhận dữ liệu từ HyperRAM1:

```c
VideoStreaming_enable(&video_streaming, false);
VideoStreaming_set_grant_request(&video_streaming, false);
```

Sau IRQ/done, nên chờ HyperRAM1 write path idle rồi mới tắt accel mode, để OFBUF ghi hết dữ liệu cuối về RAM. Flow full model trong:

```text
App/Src/allcnn_cifar10_accel.c
```

đã làm sẵn việc này bằng `drain_ofbuf_to_hyperram1()`.

Các helper high-level đang dùng trong app:

| Hàm | Chức năng |
| --- | --- |
| `AllCNN_CIFAR10_Accel_PrepareConv1Payload()` | Pack ảnh cat + Conv1 filter/bias vào HyperRAM đúng layout accelerator. |
| `AllCNN_CIFAR10_Accel_RunConv1Bringup()` | Chạy Conv1 bằng accelerator, chờ IRQ, compare OFMAP với CPU golden. |
| `AllCNN_CIFAR10_Accel_PrepareFullPayload()` | Pack full 9 layer ALL_CNN_C vào HyperRAM0/1. |
| `AllCNN_CIFAR10_Accel_RunFullModel()` | Chạy full model layer-by-layer, in profile và dự đoán class. |

### 13.11 MEM Helper

Header/source:

```text
Drivers/SoC_HAL/Inc/mem.h
Drivers/SoC_HAL/Src/mem.c
```

Các hàm `mem_*` đọc/ghi theo word offset tính từ:

```c
APPLICATION_START_ADDRESS = 0x01100000U
```

Ghi/đọc một word:

```c
mem_write_word(0, 0, 0x12345678U);
uint32_t value = mem_read_word(0, 0);
```

Đọc/ghi bit-field trong một word:

```c
mem_write_bits(0,      // segment_base_word_offset
               4,      // word_offset_in_segment
               0x5,    // data_to_write
               8,      // start_bit
               3);     // num_bits

uint32_t field = mem_read_bits(0, 4, 8, 3);
```

### 13.12 Gợi Ý System_Init

`App/Src/system_init.c` hiện init các block mặc định:

```c
System_Init_All();
```

Flow hiện tại gồm timer, GPIO, UART0, I2C0, video streaming và CNN accelerator. Nếu app cần dùng cả hai instance, nên init thêm thủ công trong `main()` hoặc mở rộng `System_Init_UART()` / `System_Init_I2C()` / `System_Init_HyperRAM()`.

Ví dụ init đầy đủ UART0/UART1/I2C0/I2C1/SPI0/SPI1/HyperRAM0/HyperRAM1:

```c
static void App_Init_Peripherals(void)
{
    timer_init();
    gpio_init();

    Uart_create(&uart_0, UART0_BASE_ADDR);
    Uart_init_baudrate(&uart_0, 115200);

    Uart_create(&uart_1, UART1_BASE_ADDR);
    Uart_init_baudrate(&uart_1, 115200);

    I2C_driver_init(&i2c0, I2C0_BASE_ADDR);
    I2C_init(&i2c0, SYS_CLK_FREQ, 100000U);

    I2C_driver_init(&i2c1, I2C1_BASE_ADDR);
    I2C_init(&i2c1, SYS_CLK_FREQ, 100000U);

    spi_init(&spi0, SPI0_BASE_ADDR);
    spi_configure(&spi0, SPI_CPOL_LOW, SPI_CPHA_LEADING, SYS_CLK_FREQ, 10000000U);

    spi_init(&spi1, SPI1_BASE_ADDR);
    spi_configure(&spi1, SPI_CPOL_LOW, SPI_CPHA_LEADING, SYS_CLK_FREQ, 10000000U);

    HyperRAM_init(&hyperram0, HYPERRAM_0_BASE_ADDR);
    HyperRAM_init(&hyperram1, HYPERRAM_1_BASE_ADDR);

    VideoStreaming_begin();
    CNN_Accel_begin();
}
```

Ví dụ `main()` dùng cả hai UART:

```c
int main(void)
{
    App_Init_Peripherals();

    while (1) {
        Uart_write_string(&uart_0, "log on uart0\n");
        Uart_write_string(&uart_1, "log on uart1\n");
        delay(1000);
    }
}
```

## 14. Lệnh Kiểm Tra Nhanh

```bash
./scripts/builder.py --help
./scripts/host_flasher.py --help
bash -n scripts/beta_aisoc_completion.bash
```

## Ghi Chú Cuối

- `Build/main.bin` và weight blob là hai payload khác nhau. App flash qua bootloader; weight flash qua `uart_weight_sender.py` hoặc qua flow nạp SPI flash ngoài.
- Với model camera mới, flow demo thực tế cần weight model mới và lệnh `7.x`, không dùng lại weight CIFAR-10 cũ cho inference camera.
- Khi đổi model hoặc preprocessing, cần kiểm tra lại đồng thời:
  - model export,
  - packer output,
  - thông số trong firmware layer table,
  - resize/preprocess phần cứng,
  - golden model host app.
