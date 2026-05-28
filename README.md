# ASIC-Oriented RISC-V AI SoC Platform

Repository này trình bày nền tảng **RISC-V AI SoC định hướng ASIC**, bao gồm kiến trúc hệ thống, firmware, luồng tăng tốc CNN, tài liệu thesis và video demo thực nghiệm.

## Liên Kết Nhanh

- **Report thesis:** [docs/report-thesis/main.pdf](docs/report-thesis/main.pdf)
- **Video demo:** [Google Drive demo folder](https://drive.google.com/drive/folders/19oA3CzA9WKEoQ1JPa15cW4yM1nDpZaN2?usp=sharing)
- **Hình kiến trúc:** [docs/images/soc-architecture.png](docs/images/soc-architecture.png)

## Mục Tiêu Dự Án

Dự án tập trung xây dựng một nền tảng SoC phục vụ các bài toán AI nhúng, có khả năng triển khai trên FPGA và định hướng tiến tới ASIC. Hệ thống kết hợp CPU RISC-V, firmware điều khiển, các ngoại vi SoC, bộ nhớ ngoài và khối CNN accelerator để chạy demo nhận diện theo thời gian thực.

Các phần chính:

- Thiết kế nền tảng SoC dựa trên RISC-V.
- Tích hợp firmware, bootloader và lớp SoC HAL.
- Tích hợp các ngoại vi như UART, SPI/OSPI, I2C, GPIO, timer, HyperRAM và video streaming.
- Xây dựng luồng CNN accelerator cho tác vụ AI nhúng.
- So sánh và kiểm chứng kết quả với golden model chạy trên host.
- Trình bày báo cáo thesis, kiến trúc hệ thống và video demo.

## Kiến Trúc Hệ Thống

![SoC architecture](docs/images/soc-architecture.png)

Luồng xử lý tổng quát:

```text
Camera / Input data
        |
        v
Video streaming + preprocessing
        |
        v
RISC-V SoC firmware
        |
        v
CNN accelerator + DMA/memory subsystem
        |
        v
UART / Host dashboard / Demo output
```

## Ghi Chú

Repository này được trình bày theo hướng giúp người xem GitHub nắm nhanh ba lớp thông tin:

- **Tài liệu:** report thesis và hình kiến trúc.
- **Hiện thực:** firmware, driver, accelerator flow và host tool.
- **Kết quả:** video demo và dashboard/golden model.
