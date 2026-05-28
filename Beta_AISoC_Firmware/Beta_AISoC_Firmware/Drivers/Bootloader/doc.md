# TÀI LIỆU ĐẶC TẢ GIAO THỨC BOOTLOADER: PROT-BOOT-H (Ver 4.0)

## 1. Tổng quan hệ thống (System Overview)
**PROT-BOOT-H (Protocol for Bootloader over Hardware)** là giao thức truyền thông tầng ứng dụng, hoạt động theo mô hình Master-Slave (Host-Target), được thiết kế chuyên biệt cho hệ thống **SoC tùy chỉnh dựa trên lõi PicoRV32 (FPGA)**. 

Giao thức này quản lý toàn bộ vòng đời khởi động: từ việc tiếp nhận Firmware qua UART, ghi an toàn vào SPI Flash ngoài (dòng W25Q), xác minh toàn vẹn dữ liệu, cho đến việc tải Firmware vào IMEM (SRAM) và chuyển giao quyền thực thi.

### 1.1. Các đặc tính nổi bật của Phiên bản 4.0 (Enterprise-Grade Features)
* **Progressive CRC & Dummy Consume:** Tính toán CRC luân phiên (byte-by-byte) kết hợp kỹ thuật "Tiêu thụ ảo" giúp bảo vệ 100% RAM khỏi lỗi tràn bộ đệm (Buffer Overflow) khi Host gửi gói tin sai kích thước, đồng thời loại trừ triệt để lỗi mất đồng bộ (Framing Desynchronization).
* **Duplicate ARQ Handling:** Nhận diện và xử lý an toàn các gói tin bị Host gửi lặp (do mất ACK), ngăn chặn việc ghi đè Flash hoặc thực thi lệnh hai lần.
* **Page Boundary Wrap-around Protection:** Tự động chia nhỏ Payload để ghi an toàn qua ranh giới trang (Page Boundary) của SPI Flash, tuân thủ tuyệt đối đặc tính phần cứng của bộ đệm trang 256-byte.
* **Continuous Burst Read:** Tối đa hóa băng thông đọc SPI bằng kỹ thuật truyền liên tục (giữ chân CS LOW), giảm thời gian nạp Firmware từ Flash vào IMEM xuống mức tối thiểu.
* **Zero-Overhead FSM:** Máy trạng thái được thiết kế phẳng (Flat FSM) với từ khóa `static inline`, đạt tốc độ phản hồi tính bằng nanogiây trên lõi RISC-V.

---

## 2. Ràng buộc Kỹ thuật & Phần cứng (Hardware Constraints)

| Thông số | Giá trị cấu hình | Ghi chú |
| :--- | :--- | :--- |
| **Tần số CPU ($f_{CPU}$)** | `200 MHz` | Đảm bảo CPU luôn xử lý kịp FIFO của phần cứng UART. |
| **Tần số SPI ($f_{SPI}$)** | `10 MHz` | Tối ưu độ ổn định tín hiệu trên bo mạch FPGA. |
| **UART Baudrate** | `230400 bps` | Giao tiếp bất đồng bộ, truyền dữ liệu dạng Little-Endian. |
| **SPI Flash Size** | `16 MB` | (Ví dụ: Winbond W25Q128JW) |
| **Đơn vị Sector / Page**| `4096 Bytes` / `256 Bytes`| Tiêu chuẩn căn lề bộ nhớ Flash vật lý. |
| **Max Payload Size** | `1024 Bytes` | Giới hạn Buffer cấp phát tĩnh trên BRAM của FPGA. |

### 2.1. Phân bổ bộ nhớ SPI Flash (Memory Map)
Flash được chia làm hai vùng độc lập để đảm bảo an toàn (Fail-safe) nếu quá trình nạp bị ngắt điện giữa chừng:
* **Sector 0 (`0x00000000`): Vùng Metadata.** Chỉ chứa `VALID_MAGIC_WORD` (`0xA5A55A5A`) và `IMAGE_SIZE` (4 bytes).
* **Sector 1+ (`0x00001000`): Vùng Application.** Chứa dữ liệu mã máy nhị phân (.bin) thực tế của Firmware.

---

## 3. Cấu trúc Khung truyền tải (Frame Structure)

### 3.1. Khung yêu cầu từ Host $\to$ Target (Host Request)
| Byte Offset | Trường | Kích thước | Giá trị / Mô tả |
| :--- | :--- | :--- | :--- |
| 0 | **SOF** | 1 byte | Start of Frame (`0xA5`). |
| 1 | **SEQ** | 1 byte | Số thứ tự gói tin (0-255), tăng tuần tự. |
| 2 | **CMD** | 1 byte | Mã lệnh thực thi (Xem Mục 4). |
| 3 - 4 | **LEN** | 2 bytes | Độ dài vùng PAYLOAD (Little-Endian). |
| 5 ... | **PAYLOAD** | N bytes | Dữ liệu tùy biến theo lệnh ($N \le 1024$). |
| N+5 - N+6 | **CRC16** | 2 bytes | CRC-16-CCITT tính từ `SEQ` đến hết `PAYLOAD`. |
| N+7 | **EOF** | 1 byte | End of Frame (`0x55`). |

### 3.2. Khung phản hồi từ Target $\to$ Host (Target Response)
| Byte Offset | Trường | Kích thước | Giá trị / Mô tả |
| :--- | :--- | :--- | :--- |
| 0 | **SOF** | 1 byte | Start of Frame (`0xA5`). |
| 1 | **SEQ_M** | 1 byte | Mirror (Copy) lại số `SEQ` của Host để xác nhận. |
| 2 | **STATUS**| 1 byte | Trạng thái (`0x79`: ACK, `0x1F`: NACK, `0xEE`: ERROR). |
| 3 - 4 | **LEN** | 2 bytes | Độ dài vùng RES_DATA. |
| 5 ... | **RES_DATA**| N bytes | Dữ liệu phản hồi hoặc cấu trúc mã lỗi chi tiết. |
| N+5 - N+6 | **CRC16** | 2 bytes | CRC-16-CCITT tính từ `SEQ_M` đến hết `RES_DATA`. |
| N+7 | **EOF** | 1 byte | End of Frame (`0x55`). |

---

## 4. Danh mục Tập lệnh (Command Set)

*(Lưu ý: Tất cả dữ liệu nhiều byte đều sử dụng Little-Endian)*

1. **CMD_GET_CAP (0x07): Khám phá cấu hình**
   * *Mô tả:* Host lấy thông số cấu hình phần cứng của FPGA SoC.
   * *Payload Host:* Trống.
   * *Phản hồi (14B):* `[Ver (2B)] [Flash_Size (4B)] [Sec_Size (2B)] [Page_Size (2B)] [IMEM_Base (4B)]`.

2. **CMD_INFO (0x02): Khai báo Metadata**
   * *Mô tả:* Host gửi thông số của Firmware sắp nạp để Target kiểm tra.
   * *Payload Host (14B):* `[File_Size (4B)] [File_CRC32 (4B)] [Dest_Addr (4B)] [App_ID (2B)]`.

3. **CMD_ERASE (0x03): Xóa vùng nhớ**
   * *Mô tả:* Yêu cầu xóa SPI Flash. **Lưu ý:** Target sẽ mất nhiều thời gian xử lý lệnh này. Host PC cần tự động mở rộng Timeout của cổng COM (ví dụ: +45ms cho mỗi 4KB).
   * *Payload Host (8B):* `[Addr (4B)] [Size (4B)]`.

4. **CMD_WRITE (0x04): Ghi khối dữ liệu**
   * *Mô tả:* Truyền dữ liệu mã máy. Target tự động xử lý chia nhỏ gói để vượt qua ranh giới trang (Page Wrap-around).
   * *Payload Host (4+N Bytes):* `[Offset (4B)] [Data_Chunk (N Bytes)]`. 

5. **CMD_VERIFY (0x05): Xác minh & Lưu trạng thái (Commit)**
   * *Mô tả:* Yêu cầu Target tính toán CRC32 phần cứng toàn bộ Firmware và đối chiếu.
   * *Payload Host:* Trống.
   * *Phản hồi (4B):* Nếu hợp lệ, Target xóa Sector 0, ghi Magic Word, và trả về 4 byte `Calculated_CRC32` kèm trạng thái `ACK`.

6. **CMD_JUMP (0x06): Chuyển giao quyền**
   * *Mô tả:* Target phản hồi ACK, ngắt hoàn toàn các ngoại vi UART/SPI và nhảy (Jump) vào hàm ứng dụng tại `IMEM`.

---

## 5. Quản lý Lỗi & Xử lý Ngoại lệ (Error Handling)

### 5.1. Phân định Lỗi Giao thức
Hệ thống sử dụng cơ chế chốt chặn CRC luân phiên để phân biệt rõ ràng 2 nhóm lỗi:
* **Lỗi Kênh truyền (Noise/Physical Error):** Khi `CRC_Calculated != CRC_Received` do nhiễu lật bit vật lý. Target phản hồi `STATUS_NACK (0x1F)`. Host tiếp nhận và tự động gửi lại (Retry) đúng gói tin đó.
* **Lỗi Logic (Application Error):** Khi CRC hoàn toàn khớp nhưng nội dung gói tin vô lý (Sai CMD, Payload vượt quá 1024). Target phản hồi `STATUS_ERROR (0xEE)`. Host cần ngắt kết nối và kiểm tra lại script điều khiển phần mềm.

### 5.2. Cấu trúc Payload Lỗi (Error Response Payload)
Khi trả về `STATUS_ERROR`, Target luôn kèm theo **6 byte dữ liệu chẩn đoán** để Host dễ dàng Debug:

| Byte 0 (Nhóm Lỗi) | Byte 1 (Mã Lỗi) | Byte 2 - 5 (Info) | Ý nghĩa (Nguyên nhân) |
| :--- | :--- | :--- | :--- |
| `0x02` (Logic) | `0x05` | Kích thước `LEN` | Lỗi tràn cấu trúc (`LEN > MAX_PAYLOAD_SIZE`). |
| `0x02` (Logic) | `0x06` | Mã CRC32 sai | `CMD_VERIFY` thất bại, trả về CRC thực tế tính được. |
| `0x03` (Flash) | `0x03` | Địa chỉ vật lý | Lỗi Verify ngay sau khi ghi (Readback Fail). Trả về địa chỉ hỏng. |

---

## 6. Quy trình Vận hành Thực tế (Operational Lifecycle)

**Giai đoạn 1: Quyết định Khởi động (Boot Decision)**
* Khi Reset phần cứng, Target mở một "cửa sổ Timeout" (Mặc định 2 giây).
* Nếu Host gửi byte `SOF`, Target lập tức ngắt Timeout và chuyển sang *Giai đoạn 2*.
* Nếu hết 2 giây không có tín hiệu: Target sử dụng SPI Burst Read để tải Metadata từ Sector 0. Nếu `Magic Word` hợp lệ, Target copy toàn bộ mã máy từ Sector 1 vào IMEM và khởi chạy Ứng dụng một cách tĩnh lặng.

**Giai đoạn 2: Nạp dữ liệu (Flashing & ARQ)**
* Host thực hiện chuỗi lệnh: `CMD_INFO` $\to$ `CMD_ERASE` $\to$ Chuỗi các `CMD_WRITE`.
* *Cơ chế Stop-and-Wait ARQ:* Với mỗi `CMD_WRITE`, Target thực hiện ghi Flash, Verify đọc lại (Readback), và gửi `ACK`. Nếu Host bị timeout tín hiệu nhận và gửi lại gói cũ, Target tự động nhận diện qua `SEQ`, chỉ gửi `ACK` và bỏ qua thao tác ghi Flash nhằm tối ưu thời gian.

**Giai đoạn 3: Xác nhận và Chuyển giao (Double Validation & Handover)**
* Host gửi `CMD_VERIFY`. Target chạy bộ gia tốc tính CRC32 phần cứng. Nếu khớp, Target mới thực sự ghi `VALID_MAGIC_WORD` vào Sector 0. Đây là bước **Commit an toàn**, đảm bảo SoC không bao giờ chạy một Firmware lỗi.
* Host nhận được mã xác thực CRC trả về, gởi `CMD_JUMP`.
* Target ngắt UART, kéo CS SPI lên mức an toàn, và chuyển con trỏ lệnh vào `IMEM_BASE`.

---
*© 2026 - Giao thức nạp Firmware PicoRV32 SoC. Phát triển bởi Trần Nhật Minh.*
