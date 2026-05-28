# BK_AISoC Vivado Summary

- Generated: 2026-05-18 13:56:58 +0700
- Project: `/home/raven1911/Data/vivado_prj/Beta_AISoC/Beta_AISoC.xpr`
- Top module: `BK_AISoC`
- Device: `xc7vx485tffg1761-2`
- Vivado: `2024.2`
- Runs used: `synth_5` and `impl_5_copy_1`

## 1. Kết Luận Nhanh

| Mục | Giá trị cần biết |
| --- | --- |
| Bitstream | Đã tạo thành công: `BK_AISoC.bit` (2026-05-18 12:39:59 +0700, 20,273,543 bytes) |
| Timing final | PASS, tất cả timing constraints do user khai báo đều đạt |
| Setup margin | WNS = `0.005 ns`, TNS = `0.000 ns`, failing endpoints = `0` |
| Hold margin | WHS = `0.045 ns`, THS = `0.000 ns`, failing endpoints = `0` |
| Route | Fully routed, routing errors = `0` |
| Power estimate | `3.248 W`, confidence = `Low` |
| Điểm đáng chú ý | Timing pass nhưng setup margin rất sát: `0.005 ns` ở clock 200 MHz |

## 2. Timing Chính

| Stage | WNS(ns) | TNS(ns) | Setup fail | WHS(ns) | THS(ns) | Hold fail | Nhận xét |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Sau route | -0.229 | -0.834 | 7 | 0.045 | 0.000 | 0 | Fail setup nhẹ |
| Sau post-route physopt | 0.005 | 0.000 | 0 | 0.045 | 0.000 | 0 | Pass |

Clock dùng trong design:

| Clock | Period | Frequency |
| --- | --- | --- |
| `clk_p` / `clk_out200MHz_clk_wiz_0` | 5.000 ns | 200 MHz |
| `cam_pclk_i` | 20.000 ns | 50 MHz |
| `clk_out50MHz_clk_wiz_0` | 20.000 ns | 50 MHz |
| `clk_out25MHz_clk_wiz_0` | 40.000 ns | 25 MHz |
| `clk_out24MHz_clk_wiz_0` | 41.667 ns | 24 MHz |

Critical path summary:
| Loại | Slack(ns) | Clock | Block liên quan | Nhận xét |
| --- | --- | --- | --- | --- |
| Worst setup | 0.005 | clk_out200MHz_clk_wiz_0 | `cnn_accel/u_cnn_accel/u_filter_buf` | Margin sát nhất, data delay `4.919ns  (logic 1.578ns (32.083%)  route 3.341ns (67.917%))` |
| Worst hold | 0.045 | clk_out200MHz_clk_wiz_0 | `video_streaming/DVP_core/resize_mover_data_dut` | Hold vẫn pass, data delay `0.212ns  (logic 0.100ns (47.069%)  route 0.112ns (52.931%))` |

## 3. Tài Nguyên Tổng

| Resource | Used | Available | Util% |
| --- | --- | --- | --- |
| Slice LUTs | 39,174 | 303,600 | 12.90 |
| LUT as Logic | 36,302 | 303,600 | 11.96 |
| LUT as Memory | 2,872 | 130,800 | 2.20 |
| Slice Registers | 25,691 | 607,200 | 4.23 |
| Block RAM Tile | 414 | 1,030 | 40.19 |
| DSPs | 22 | 2,800 | 0.79 |
| Bonded IOB | 85 | 700 | 12.14 |
| BUFGCTRL | 6 | 32 | 18.75 |
| MMCME2_ADV | 1 | 14 | 7.14 |

Nhận xét: BRAM là tài nguyên dùng nhiều nhất theo phần trăm (`40.19%`). LUT, FF và DSP còn dư rất nhiều.

## 4. Tài Nguyên Theo IP / Block Cấp Cao

| IP / Instance | Module | LUT | LUT% | FF | FF% | BRAM tile eq. | BRAM% | DSP | DSP% |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| (BK_AISoC) | (top) | 1,560 | 4.0% | 1 | 0.0% | 0 | 0.0% | 0 | 0.0% |
| axi_lite_interconnect_unit | axi_lite_interconnect | 27 | 0.1% | 12 | 0.0% | 0 | 0.0% | 0 | 0.0% |
| bmem_cpu | mem_axi_lite__parameterized0 | 8 | 0.0% | 106 | 0.4% | 16 | 3.9% | 0 | 0.0% |
| clk_wiz_0_uut | clk_wiz_0 | 0 | 0.0% | 0 | 0.0% | 0 | 0.0% | 0 | 0.0% |
| cnn_accel | cnn_axi_lite | 32,110 | 81.9% | 21,149 | 82.3% | 45 | 10.9% | 19 | 86.4% |
| cnn_ifbuf_source_mux | cnn_ifbuf_dma_mux | 8 | 0.0% | 0 | 0.0% | 0 | 0.0% | 0 | 0.0% |
| cpu0 | picorv32_axi | 2,220 | 5.7% | 1,168 | 4.5% | 0 | 0.0% | 0 | 0.0% |
| dmem_cpu | mem_axi_lite | 8 | 0.0% | 106 | 0.4% | 16 | 3.9% | 0 | 0.0% |
| gpio | GPIO_axi_lite_core | 30 | 0.1% | 91 | 0.4% | 0 | 0.0% | 0 | 0.0% |
| hyperram0 | hyperram_axi_lite_core | 685 | 1.7% | 546 | 2.1% | 0 | 0.0% | 0 | 0.0% |
| hyperram1 | hyperram_axi_lite_core__parameterized0 | 732 | 1.9% | 539 | 2.1% | 0 | 0.0% | 0 | 0.0% |
| i2c0 | I2C_axi_lite_core | 59 | 0.2% | 106 | 0.4% | 0 | 0.0% | 0 | 0.0% |
| imem_cpu | mem_axi_lite__parameterized1 | 8 | 0.0% | 106 | 0.4% | 16 | 3.9% | 0 | 0.0% |
| spi0 | Spi_axi_lite_core | 36 | 0.1% | 101 | 0.4% | 0 | 0.0% | 0 | 0.0% |
| timer0 | TIMER_axi_lite_core | 85 | 0.2% | 105 | 0.4% | 0 | 0.0% | 0 | 0.0% |
| uart0 | uart_axi_lite | 337 | 0.9% | 142 | 0.6% | 0 | 0.0% | 0 | 0.0% |
| video_streaming | video_streaming_axi_lite_core | 1,317 | 3.4% | 1,427 | 5.6% | 321 | 77.5% | 3 | 13.6% |

Nhận xét nhanh:
- `cnn_accel` chiếm phần lớn LUT/FF/DSP: khoảng `81.9%` LUT, `82.3%` FF, `86.4%` DSP của design.
- `video_streaming` chiếm phần lớn BRAM: khoảng `77.5%` BRAM tile equivalent.
- CPU PicoRV32 và peripheral AXI-lite nhỏ so với accelerator/video path.

## 5. Power

| Metric | Value |
| --- | --- |
| Total On-Chip Power | 3.248 W |
| Dynamic | 2.956 W |
| Device Static | 0.292 W |
| Junction Temperature | 28.7 C |
| Max Ambient | 81.3 C |
| Confidence | Low |

Lưu ý: power confidence là `Low`, nên số power chỉ nên dùng như ước lượng nếu chưa có SAIF/VCD switching activity.

## 6. Warning / Risk Cần Biết

| Nguồn | Warning | Critical warning | Error |
| --- | --- | --- | --- |
| Synthesis | 544 | 0 | 0 |
| Implementation | 128 | 0 | 0 |

DRC đáng chú ý:
| Rule | Severity | Ý nghĩa | Count |
| --- | --- | --- | --- |
| CFGBVS-1 | Warning | Missing CFGBVS and CONFIG_VOLTAGE Design Properties | 1 |
| DPIP-1 | Warning | Input pipelining | 17 |
| DPOP-1 | Warning | PREG Output pipelining | 10 |
| DPOP-2 | Warning | MREG Output pipelining | 19 |
| PDRC-153 | Warning | Gated clock check | 1 |
| RBOR-1 | Warning | RAMB output registers | 49 |
| REQP-1839 | Warning | RAMB36 async control check | 20 |
| REQP-1840 | Warning | RAMB18 async control check | 20 |

Methodology đáng chú ý:
| Rule | Severity | Ý nghĩa | Count |
| --- | --- | --- | --- |
| SYNTH-6 | Warning | Timing of a RAM block might be sub-optimal | 226 |
| SYNTH-9 | Warning | Small multiplier | 1152 |
| SYNTH-15 | Warning | Byte wide write enable not inferred | 48 |
| TIMING-9 | Warning | Unknown CDC Logic | 1 |
| TIMING-10 | Warning | Missing property on synchronizer | 1 |
| TIMING-18 | Warning | Missing input or output delay | 77 |
| TIMING-20 | Warning | Non-clocked latch | 16 |

Các điểm nên xử lý nếu cần report sạch:
1. Thêm/kiểm tra `CFGBVS` và `CONFIG_VOLTAGE` trong XDC.
2. Bổ sung `set_input_delay` / `set_output_delay` cho các cổng ngoài nếu cần timing signoff.
3. Kiểm tra latch `RGBchannel_reg` trong `video_streaming/DVP_core/HDMI_interface_uut`.
4. Xem lại worst setup path trong `cnn_accel/u_cnn_accel/u_filter_buf` vì margin chỉ `0.005 ns`.
5. Nếu báo cáo power chính thức, chạy lại power với SAIF/VCD activity.

## 7. File Report Gốc

| Loại | File |
| --- | --- |
| Timing final | reports/vivado/BK_AISoC_timing_summary_consolidated.rpt |
| Utilization placed | /home/raven1911/Data/vivado_prj/Beta_AISoC/Beta_AISoC.runs/impl_5_copy_1/BK_AISoC_utilization_placed.rpt |
| Utilization hierarchical | reports/vivado/BK_AISoC_utilization_hierarchical_depth6.rpt |
| Power | /home/raven1911/Data/vivado_prj/Beta_AISoC/Beta_AISoC.runs/impl_5_copy_1/BK_AISoC_power_routed.rpt |
| DRC | /home/raven1911/Data/vivado_prj/Beta_AISoC/Beta_AISoC.runs/impl_5_copy_1/BK_AISoC_drc_routed.rpt |
| Methodology | /home/raven1911/Data/vivado_prj/Beta_AISoC/Beta_AISoC.runs/impl_5_copy_1/BK_AISoC_methodology_drc_routed.rpt |
| Route status | reports/vivado/BK_AISoC_route_status_consolidated.rpt |
