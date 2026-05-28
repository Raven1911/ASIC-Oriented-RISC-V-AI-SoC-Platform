`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 05/08/2026 12:02:45 PM
// Design Name: 
// Module Name: Beta_AISoC_CNN_DMA_Path_tb
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

module Beta_AISoC_CNN_DMA_Path_tb #(
    parameter        RUN_CAMERA_IFMAP_TEST = 1,
    parameter        USE_TINY_ACCEL_PROGRAM = 1,
    parameter        RUN_FULL_ACCEL = 0,
    parameter        PRESET_PAYLOAD_READY_FLAGS = 1,
    parameter        VERBOSE_TB_LOG = 0,
    parameter        UART_MONITOR_PRINT = 0,
    parameter        UART_AXI_PRINT = 0,
    parameter        DUMP_CONV1_OFMAP_ROW0 = 0,
    parameter integer DUMP_CONV1_OFMAP_WORDS = 16,
    parameter        UART_MONITOR_TRIGGER_LOG = 0,
    parameter        QUIET_TB_LOG = 0,
    parameter        ENABLE_CAMERA_STIMULUS = 0,
    parameter        REQUIRE_CAMERA_IFMAP = 1,
    parameter        CAM_STIM_FORCE_WARMUP = 1,
    parameter        PRELOAD_VIDEO_FRAMEBUFFER = RUN_CAMERA_IFMAP_TEST,
    parameter integer CAM_STIM_WIDTH = 640,
    parameter integer CAM_STIM_HEIGHT = 480,
    parameter integer TB_EXPECTED_DONE_IRQS = 0,
    parameter [31:0] TB_UART_COMMAND = 32'h0000_0000,
    parameter [31:0] TB_PROGADDR_RESET = (RUN_CAMERA_IFMAP_TEST != 0) ? 32'h0100_0000 : 32'h0110_0000,
    parameter [31:0] TB_PROGADDR_IRQ = TB_PROGADDR_RESET + 32'h0000_0010,
    parameter [31:0] TB_CONV1_READY_FLAG_ADDR = 32'h0000_7002,
    parameter [31:0] TB_FULL_READY_FLAG_ADDR = 32'h0000_7001,
    parameter [1023:0] MAIN_HEX_FILE = "/home/raven1911/Data/Source_Thesis/Beta_AISoC_Firmware/Beta_AISoC_Firmware/Build/main.hex",
    parameter [1023:0] TINY_IMEM_HEX_FILE = "/home/raven1911/Data/Source_Thesis/Beta_AISoC_Firmware/Beta_AISoC_Firmware/Build/cnn_path_bmem.hex",
    parameter [1023:0] TINY_BMEM_HEX_FILE = "/home/raven1911/Data/Source_Thesis/Beta_AISoC_Firmware/Beta_AISoC_Firmware/Build/cnn_cam_ifmap_bmem.hex",
    parameter [1023:0] VIDEO_FRAME_HEX_FILE = "/home/raven1911/Data/vivado_prj/resize_image/resize_image.srcs/sim_1/new/frame_640x480.hex",
    parameter [1023:0] HYPERRAM0_MEM_FILE = "s27kl0641_hr0_cnn_path.mem",
    parameter [1023:0] HYPERRAM1_MEM_FILE = "s27kl0641_hr1_cnn_path.mem"
);
    localparam [23:0] CNN_TB_IFMAP_BASE_BYTE = 24'h000000;
    localparam [23:0] CNN_TB_OFMAP_BASE_BYTE = 24'h000C00;
    localparam [23:0] CNN_TB_FLT_BASE_BYTE   = 24'h180000;
    localparam [23:0] CNN_TB_BIAS_BASE_BYTE  = 24'h180A20;
    localparam [23:0] CNN_TB_IFMAP_BASE_WORD = CNN_TB_IFMAP_BASE_BYTE >> 1;
    localparam [23:0] CNN_TB_OFMAP_BASE_WORD = CNN_TB_OFMAP_BASE_BYTE >> 1;
    localparam [23:0] CNN_TB_FLT_BASE_WORD   = CNN_TB_FLT_BASE_BYTE >> 1;
    localparam [23:0] CNN_TB_BIAS_BASE_WORD  = CNN_TB_BIAS_BASE_BYTE >> 1;

    localparam [31:0] TB_IMEM_BASE = 32'h0110_0000;
    localparam [31:0] TB_DMEM_BASE = 32'h0000_0000;
    localparam [31:0] BOOT_IMAGE_MAGIC = 32'h3149_4142;
    localparam integer BOOT_IMAGE_HEADER_BYTES = 24;
    localparam integer BOOT_IMAGE_SEGMENT_BYTES = 20;
    localparam integer BOOT_SEG_LOAD_IMEM = 1;
    localparam integer BOOT_SEG_LOAD_DMEM = 2;
    localparam integer BOOT_SEG_ZERO_DMEM = 3;
    localparam integer MAIN_HEX_MAX_WORDS = 65536;
    localparam integer TB_IMEM_WORDS = 65536 >> 2;
    localparam integer TB_DMEM_WORDS = 65536 >> 2;
    localparam integer VIDEO_FRAME_PIXELS = CAM_STIM_WIDTH * CAM_STIM_HEIGHT;
    localparam integer VIDEO_FB_BLOCK_DEPTH = 65536;
    localparam [31:0] TB_CONV1_BIAS_ADDR = 32'h0000_5EA0;
    localparam [31:0] TB_CONV1_WEIGHT_ADDR = 32'h0000_6020;
    localparam [31:0] TB_CONV1_SOURCE_READY_ADDR = 32'h0000_7000;

    //---------------------------------------------------------
    // 1. Clock and Reset Signals
    //---------------------------------------------------------
    reg clk_p, clk_n;
    reg reset_n;

    //---------------------------------------------------------
    // 2. SoC Peripheral Connections
    //---------------------------------------------------------
    reg [31:0] irq_in;

    wire uart0_rx, uart0_tx;
    wire uart1_rx, uart1_tx;

    wire spi0_ss_n;
    wire spi0_clk, spi0_mosi, spi0_miso;

    wire spi1_ss_n;
    wire spi1_clk, spi1_mosi, spi1_miso;

    tri i2c0_scl, i2c0_sda;
    tri i2c1_scl, i2c1_sda;

    wire [7:0] hyperram0_dq_io;
    wire       hyperram0_rwds_io;
    wire       hyperram0_hclk_p, hyperram0_cs_n, hyperram0_resetn;

    wire [7:0] hyperram1_dq_io;
    wire       hyperram1_rwds_io;
    wire       hyperram1_hclk_p, hyperram1_cs_n, hyperram1_resetn;

    wire [3:0] gpo;
    reg  [3:0] gpi;
    wire [7:0] gpio_bus;
    assign gpio_bus = {gpi, 4'bz};
    assign gpo = gpio_bus[3:0];

    wire trap0, trap1;

    reg        cam_pclk;
    reg [7:0]  cam_half_pixel;
    reg        cam_href;
    reg        cam_vsync;
    wire       cam_xclk;
    wire       HDMI_TX_HS;
    wire       HDMI_TX_VS;
    wire       HDMI_TX_DE;
    wire       HDMI_TX_CLK;
    wire [23:0] HDMI_TX_D;

    pullup(i2c0_scl);
    pullup(i2c0_sda);
    pullup(i2c1_scl);
    pullup(i2c1_sda);

    defparam Beta_AISoC_uut.hyperram0.SIM_ENB   = 1;
    defparam Beta_AISoC_uut.hyperram1.SIM_ENB   = 1;

    defparam Beta_AISoC_uut.hyperram1.SHMOOD_SELECT   = 0;

    //---------------------------------------------------------
    // 3. SoC Unit Under Test
    //---------------------------------------------------------
    Beta_AISoC #(
        .PROGADDR_RESET(TB_PROGADDR_RESET),
        .PROGADDR_IRQ(TB_PROGADDR_IRQ)
    ) Beta_AISoC_uut (
        .clk_p(clk_p),
        .clk_n(clk_n),
        .resetn(reset_n),

        .trap0(trap0),
        .trap1(trap1),

        .uart0_rx(uart0_rx),
        .uart0_tx(uart0_tx),
        // .uart1_rx(uart1_rx),
        // .uart1_tx(uart1_tx),

        .spi0_clk(spi0_clk),
        .spi0_mosi(spi0_mosi),
        .spi0_miso(spi0_miso),
        .spi0_ss_n(spi0_ss_n),

        // .spi1_clk(spi1_clk),
        // .spi1_mosi(spi1_mosi),
        // .spi1_miso(spi1_miso),
        // .spi1_ss_n(spi1_ss_n),

        .i2c0_scl(i2c0_scl),
        .i2c0_sda(i2c0_sda),
        // .i2c1_scl(i2c1_scl),
        // .i2c1_sda(i2c1_sda),

        .hyperram0_dq_io(hyperram0_dq_io),
        .hyperram0_rwds_io(hyperram0_rwds_io),
        .hyperram0_hclk_p(hyperram0_hclk_p),
        .hyperram0_cs_n(hyperram0_cs_n),
        .hyperram0_resetn(hyperram0_resetn),

        .hyperram1_dq_io(hyperram1_dq_io),
        .hyperram1_rwds_io(hyperram1_rwds_io),
        .hyperram1_hclk_p(hyperram1_hclk_p),
        .hyperram1_cs_n(hyperram1_cs_n),
        .hyperram1_resetn(hyperram1_resetn),

        .gpio_io(gpio_bus),

        .cam_pclk_i(cam_pclk),
        .cam_half_pixel_i(cam_half_pixel),
        .cam_href(cam_href),
        .cam_vsync(cam_vsync),
        .cam_xclk_o(cam_xclk),

        .HDMI_TX_HS(HDMI_TX_HS),
        .HDMI_TX_VS(HDMI_TX_VS),
        .HDMI_TX_DE(HDMI_TX_DE),
        .HDMI_TX_CLK(HDMI_TX_CLK),
        .HDMI_TX_D(HDMI_TX_D)
    );

    //---------------------------------------------------------
    // 4. Peripheral Models
    //---------------------------------------------------------
    uart_monitor_responder #(
        .BAUD_RATE(115200),
        .CLK_FREQ(200_000_000),
        .TRIGGER_DATA(8'h3E),
        .MEM_FILE(""),
        .MEM_DEPTH(8),
        .PRINT_RX(UART_MONITOR_PRINT),
        .PRINT_TRIGGER(UART_MONITOR_TRIGGER_LOG)
    ) uart_mon_inst0 (
        .rx(uart0_tx),
        .tx(uart0_rx)
    );

    uart_monitor_responder #(
        .BAUD_RATE(115200),
        .CLK_FREQ(200_000_000),
        .TRIGGER_DATA(8'h3E),
        .MEM_FILE(""),
        .MEM_DEPTH(1),
        .PRINT_RX(UART_MONITOR_PRINT),
        .PRINT_TRIGGER(UART_MONITOR_TRIGGER_LOG)
    ) uart_mon_inst1 (
        .rx(uart1_tx),
        .tx(uart1_rx)
    );

    task print_uart_tx_byte;
        input [7:0] data;
        begin
            if (data == 8'h0D) begin
            end else if (data == 8'h0A) begin
                $write("\n");
            end else if ((data >= 8'h20) && (data <= 8'h7E)) begin
                $write("%c", data);
            end else begin
                $write("<%02h>", data);
            end
            $fflush();
        end
    endtask

    always @(posedge Beta_AISoC_uut.clk) begin
        if (UART_AXI_PRINT && Beta_AISoC_uut.uart0.wr_uart_reg3) begin
            print_uart_tx_byte(Beta_AISoC_uut.uart0.o_data_w[7:0]);
        end
    end

    i2c_eeprom_model #(
        .I2C_ADR(7'h50),
        .MEM_SIZE(256),
        .INIT_FILE("i2c_eeprom.mem")
    ) eeprom_inst0 (
        .scl(i2c0_scl),
        .sda(i2c0_sda)
    );

    i2c_eeprom_model #(
        .I2C_ADR(7'h50),
        .MEM_SIZE(256),
        .INIT_FILE("i2c_eeprom.mem")
    ) eeprom_inst1 (
        .scl(i2c1_scl),
        .sda(i2c1_sda)
    );

    wire flash0_wp_n = 1'b1;
    wire flash0_hold_n = 1'b1;
    W25Q128JVxIM flash_inst0 (
        .CSn(spi0_ss_n),
        .CLK(spi0_clk),
        .DIO(spi0_mosi),
        .DO(spi0_miso),
        .WPn(flash0_wp_n),
        .HOLDn(flash0_hold_n)
    );

    wire flash1_wp_n = 1'b1;
    wire flash1_hold_n = 1'b1;
    W25Q128JVxIM flash_inst1 (
        .CSn(spi1_ss_n),
        .CLK(spi1_clk),
        .DIO(spi1_mosi),
        .DO(spi1_miso),
        .WPn(flash1_wp_n),
        .HOLDn(flash1_hold_n)
    );

    s27kl0641 #(
        .UserPreload(1),
        .mem_file_name(HYPERRAM0_MEM_FILE)
    ) dram_inst0 (
        .DQ7(hyperram0_dq_io[7]), .DQ6(hyperram0_dq_io[6]),
        .DQ5(hyperram0_dq_io[5]), .DQ4(hyperram0_dq_io[4]),
        .DQ3(hyperram0_dq_io[3]), .DQ2(hyperram0_dq_io[2]),
        .DQ1(hyperram0_dq_io[1]), .DQ0(hyperram0_dq_io[0]),
        .RWDS(hyperram0_rwds_io),
        .CSNeg(hyperram0_cs_n),
        .CK(hyperram0_hclk_p),
        .RESETNeg(hyperram0_resetn)
    );

    s27kl0641 #(
        .UserPreload(1),
        .mem_file_name(HYPERRAM1_MEM_FILE)
    ) dram_inst1 (
        .DQ7(hyperram1_dq_io[7]), .DQ6(hyperram1_dq_io[6]),
        .DQ5(hyperram1_dq_io[5]), .DQ4(hyperram1_dq_io[4]),
        .DQ3(hyperram1_dq_io[3]), .DQ2(hyperram1_dq_io[2]),
        .DQ1(hyperram1_dq_io[1]), .DQ0(hyperram1_dq_io[0]),
        .RWDS(hyperram1_rwds_io),
        .CSNeg(hyperram1_cs_n),
        .CK(hyperram1_hclk_p),
        .RESETNeg(hyperram1_resetn)
    );

    //---------------------------------------------------------
    // 5. Clock and Reset
    //---------------------------------------------------------
    initial begin
        clk_p = 1'b0;
        clk_n = 1'b1;
        forever #2.5 begin
            clk_p = ~clk_p;
            clk_n = ~clk_p;
        end
    end

    initial begin
        if ($test$plusargs("dump_cnn_path")) begin
            $dumpfile("Beta_AISoC_CNN_DMA_Path_tb.vcd");
            $dumpvars(0, Beta_AISoC_CNN_DMA_Path_tb);
        end
    end

    //---------------------------------------------------------
    // 5a. Direct app image preload, no bootloader
    //---------------------------------------------------------
    reg [31:0] main_hex_words [0:MAIN_HEX_MAX_WORDS-1];
    reg [1023:0] main_hex_file;
    reg [1023:0] tiny_imem_hex_file;
    reg [1023:0] tiny_bmem_hex_file;
    reg [1023:0] video_frame_hex_file;
    reg          run_full_accel;
    reg          run_camera_ifmap_test;
    reg          require_camera_ifmap;
    reg [15:0]   video_frame_words [0:VIDEO_FRAME_PIXELS-1];
    integer      expected_done_irqs;

    function [7:0] main_hex_byte;
        input integer byte_addr;
        reg [31:0] raw_word;
        begin
            raw_word = main_hex_words[byte_addr >> 2];
            case (byte_addr[1:0])
                2'd0: main_hex_byte = raw_word[31:24];
                2'd1: main_hex_byte = raw_word[23:16];
                2'd2: main_hex_byte = raw_word[15:8];
                default: main_hex_byte = raw_word[7:0];
            endcase
        end
    endfunction

    function [31:0] main_hex_le32;
        input integer byte_addr;
        begin
            main_hex_le32 = {main_hex_byte(byte_addr + 3),
                             main_hex_byte(byte_addr + 2),
                             main_hex_byte(byte_addr + 1),
                             main_hex_byte(byte_addr + 0)};
        end
    endfunction

    task write_imem_byte;
        input [31:0] addr;
        input [7:0] data;
        integer word_idx;
        begin
            word_idx = (addr - TB_IMEM_BASE) >> 2;
            case (addr[1:0])
                2'd0: Beta_AISoC_uut.imem_cpu.mem_register_unit.mem[word_idx][7:0]   = data;
                2'd1: Beta_AISoC_uut.imem_cpu.mem_register_unit.mem[word_idx][15:8]  = data;
                2'd2: Beta_AISoC_uut.imem_cpu.mem_register_unit.mem[word_idx][23:16] = data;
                default: Beta_AISoC_uut.imem_cpu.mem_register_unit.mem[word_idx][31:24] = data;
            endcase
        end
    endtask

    task write_dmem_byte;
        input [31:0] addr;
        input [7:0] data;
        integer word_idx;
        begin
            word_idx = (addr - TB_DMEM_BASE) >> 2;
            case (addr[1:0])
                2'd0: Beta_AISoC_uut.dmem_cpu.mem_register_unit.mem[word_idx][7:0]   = data;
                2'd1: Beta_AISoC_uut.dmem_cpu.mem_register_unit.mem[word_idx][15:8]  = data;
                2'd2: Beta_AISoC_uut.dmem_cpu.mem_register_unit.mem[word_idx][23:16] = data;
                default: Beta_AISoC_uut.dmem_cpu.mem_register_unit.mem[word_idx][31:24] = data;
            endcase
        end
    endtask

    function [7:0] read_dmem_byte;
        input [31:0] addr;
        integer word_idx;
        reg [31:0] word_data;
        begin
            word_idx = (addr - TB_DMEM_BASE) >> 2;
            word_data = Beta_AISoC_uut.dmem_cpu.mem_register_unit.mem[word_idx];
            case (addr[1:0])
                2'd0: read_dmem_byte = word_data[7:0];
                2'd1: read_dmem_byte = word_data[15:8];
                2'd2: read_dmem_byte = word_data[23:16];
                default: read_dmem_byte = word_data[31:24];
            endcase
        end
    endfunction

    task clear_cpu_memories;
        integer idx;
        begin
            for (idx = 0; idx < TB_IMEM_WORDS; idx = idx + 1)
                Beta_AISoC_uut.bmem_cpu.mem_register_unit.mem[idx] = 32'h0000_0000;
            for (idx = 0; idx < TB_IMEM_WORDS; idx = idx + 1)
                Beta_AISoC_uut.imem_cpu.mem_register_unit.mem[idx] = 32'h0000_0000;
            for (idx = 0; idx < TB_DMEM_WORDS; idx = idx + 1)
                Beta_AISoC_uut.dmem_cpu.mem_register_unit.mem[idx] = 32'h0000_0000;
        end
    endtask

    task load_tiny_accel_imem_hex;
        begin
            $readmemh(tiny_imem_hex_file, Beta_AISoC_uut.imem_cpu.mem_register_unit.mem);
            $display("[%t] Loaded tiny CNN accel program into IMEM: %0s", $time, tiny_imem_hex_file);
            $display("[%t] This TB skips app/menu/boot. HyperRAM0/1 data comes from preload mem files.", $time);
        end
    endtask

    task load_tiny_accel_bmem_hex;
        begin
            $readmemh(tiny_bmem_hex_file, Beta_AISoC_uut.bmem_cpu.mem_register_unit.mem);
            $display("[%t] Loaded camera-IFMAP CNN program into BMEM: %0s", $time, tiny_bmem_hex_file);
            $display("[%t] CPU reset/IRQ vectors: 0x%08h / 0x%08h", $time, TB_PROGADDR_RESET, TB_PROGADDR_IRQ);
        end
    endtask

    task write_video_framebuffer_pixel;
        input integer pixel_idx;
        input [15:0] pixel_data;
        integer local_idx;
        begin
            if (pixel_idx < VIDEO_FB_BLOCK_DEPTH) begin
                local_idx = pixel_idx;
                Beta_AISoC_uut.video_streaming.DVP_core.frame_buffer_unit.genblk1.g_bram[0].u_bram.mem_hdmi[local_idx] = pixel_data;
                Beta_AISoC_uut.video_streaming.DVP_core.frame_buffer_unit.genblk1.g_bram[0].u_bram.mem_accel[local_idx] = pixel_data;
            end else if (pixel_idx < (VIDEO_FB_BLOCK_DEPTH * 2)) begin
                local_idx = pixel_idx - VIDEO_FB_BLOCK_DEPTH;
                Beta_AISoC_uut.video_streaming.DVP_core.frame_buffer_unit.genblk1.g_bram[1].u_bram.mem_hdmi[local_idx] = pixel_data;
                Beta_AISoC_uut.video_streaming.DVP_core.frame_buffer_unit.genblk1.g_bram[1].u_bram.mem_accel[local_idx] = pixel_data;
            end else if (pixel_idx < (VIDEO_FB_BLOCK_DEPTH * 3)) begin
                local_idx = pixel_idx - (VIDEO_FB_BLOCK_DEPTH * 2);
                Beta_AISoC_uut.video_streaming.DVP_core.frame_buffer_unit.genblk1.g_bram[2].u_bram.mem_hdmi[local_idx] = pixel_data;
                Beta_AISoC_uut.video_streaming.DVP_core.frame_buffer_unit.genblk1.g_bram[2].u_bram.mem_accel[local_idx] = pixel_data;
            end else if (pixel_idx < (VIDEO_FB_BLOCK_DEPTH * 4)) begin
                local_idx = pixel_idx - (VIDEO_FB_BLOCK_DEPTH * 3);
                Beta_AISoC_uut.video_streaming.DVP_core.frame_buffer_unit.genblk1.g_bram[3].u_bram.mem_hdmi[local_idx] = pixel_data;
                Beta_AISoC_uut.video_streaming.DVP_core.frame_buffer_unit.genblk1.g_bram[3].u_bram.mem_accel[local_idx] = pixel_data;
            end else if (pixel_idx < (VIDEO_FB_BLOCK_DEPTH * 5)) begin
                local_idx = pixel_idx - (VIDEO_FB_BLOCK_DEPTH * 4);
                Beta_AISoC_uut.video_streaming.DVP_core.frame_buffer_unit.genblk1.g_bram[4].u_bram.mem_hdmi[local_idx] = pixel_data;
                Beta_AISoC_uut.video_streaming.DVP_core.frame_buffer_unit.genblk1.g_bram[4].u_bram.mem_accel[local_idx] = pixel_data;
            end
        end
    endtask

    task load_video_framebuffer_hex;
        integer idx;
        begin
            if (PRELOAD_VIDEO_FRAMEBUFFER != 0) begin
                for (idx = 0; idx < VIDEO_FRAME_PIXELS; idx = idx + 1) begin
                    video_frame_words[idx] = 16'h0000;
                end
                $readmemh(video_frame_hex_file, video_frame_words);
                for (idx = 0; idx < VIDEO_FRAME_PIXELS; idx = idx + 1) begin
                    write_video_framebuffer_pixel(idx, video_frame_words[idx]);
                end
                force Beta_AISoC_uut.video_streaming.DVP_core.frame_buffer_unit.wr0_i = 1'b0;
                if (!QUIET_TB_LOG) begin
                    $display("[%t] Preloaded video frame buffer from %0s (%0d RGB565 pixels).",
                             $time, video_frame_hex_file, VIDEO_FRAME_PIXELS);
                    $display("[%t] Frame buffer write port forced off for file-preload camera IFMAP test.", $time);
                    $display("[%t] FB preload sample word[26]=0x%04h mem_accel[26]=0x%04h",
                             $time, video_frame_words[26],
                             Beta_AISoC_uut.video_streaming.DVP_core.frame_buffer_unit.genblk1.g_bram[0].u_bram.mem_accel[26]);
                end
            end
        end
    endtask

    task load_main_hex_boot_image;
        integer idx;
        integer seg;
        integer desc_base;
        integer byte_idx;
        reg [31:0] magic;
        reg [31:0] version;
        reg [31:0] payload_offset;
        reg [31:0] segment_count;
        reg [31:0] entry_addr;
        reg [31:0] kind;
        reg [31:0] flash_offset;
        reg [31:0] dst_addr;
        reg [31:0] size_bytes;
        begin
            for (idx = 0; idx < MAIN_HEX_MAX_WORDS; idx = idx + 1)
                main_hex_words[idx] = 32'h0000_0000;

            $readmemh(main_hex_file, main_hex_words);

            magic = main_hex_le32(0);
            version = main_hex_le32(4);
            payload_offset = main_hex_le32(8);
            segment_count = main_hex_le32(12);
            entry_addr = main_hex_le32(16);

            if (magic !== BOOT_IMAGE_MAGIC) begin
                $display("[%t] ERROR: %0s is not a BAI1 app boot image. magic=0x%08h",
                         $time, main_hex_file, magic);
                $finish;
            end

            if (VERBOSE_TB_LOG) begin
                $display("[%t] Loading app image directly into CPU memories: %0s", $time, main_hex_file);
                $display("  version=%0d payload=0x%08h segments=%0d entry=0x%08h",
                         version, payload_offset, segment_count, entry_addr);
            end

            for (seg = 0; seg < segment_count; seg = seg + 1) begin
                desc_base = BOOT_IMAGE_HEADER_BYTES + seg * BOOT_IMAGE_SEGMENT_BYTES;
                kind = main_hex_le32(desc_base + 0);
                flash_offset = main_hex_le32(desc_base + 8);
                dst_addr = main_hex_le32(desc_base + 12);
                size_bytes = main_hex_le32(desc_base + 16);

                if (kind == BOOT_SEG_LOAD_IMEM) begin
                    if (VERBOSE_TB_LOG) begin
                        $display("  SEG%0d IMEM dst=0x%08h size=0x%08h flash=0x%08h",
                                 seg, dst_addr, size_bytes, flash_offset);
                    end
                    for (byte_idx = 0; byte_idx < size_bytes; byte_idx = byte_idx + 1)
                        write_imem_byte(dst_addr + byte_idx, main_hex_byte(flash_offset + byte_idx));
                end else if (kind == BOOT_SEG_LOAD_DMEM) begin
                    if (VERBOSE_TB_LOG) begin
                        $display("  SEG%0d DMEM dst=0x%08h size=0x%08h flash=0x%08h",
                                 seg, dst_addr, size_bytes, flash_offset);
                    end
                    for (byte_idx = 0; byte_idx < size_bytes; byte_idx = byte_idx + 1)
                        write_dmem_byte(dst_addr + byte_idx, main_hex_byte(flash_offset + byte_idx));
                end else if (kind == BOOT_SEG_ZERO_DMEM) begin
                    if (VERBOSE_TB_LOG) begin
                        $display("  SEG%0d ZERO DMEM dst=0x%08h size=0x%08h",
                                 seg, dst_addr, size_bytes);
                    end
                    for (byte_idx = 0; byte_idx < size_bytes; byte_idx = byte_idx + 1)
                        write_dmem_byte(dst_addr + byte_idx, 8'h00);
                end else begin
                    $display("[%t] ERROR: unsupported app segment kind %0d.", $time, kind);
                    $finish;
                end
            end
        end
    endtask

    task configure_uart_command;
        integer idx;
        begin
            for (idx = 0; idx < 8; idx = idx + 1)
                uart_mon_inst0.resp_memory[idx] = 8'h00;

            uart_mon_inst0.resp_memory[0] = 8'h33; // '3'
            uart_mon_inst0.resp_memory[1] = 8'h2E; // '.'
            uart_mon_inst0.resp_memory[2] = run_full_accel ? 8'h34 : 8'h33; // '4' or '3'
            uart_mon_inst0.resp_memory[3] = 8'h0D;

            if (TB_UART_COMMAND != 32'h0000_0000) begin
                uart_mon_inst0.resp_memory[0] = TB_UART_COMMAND[31:24];
                uart_mon_inst0.resp_memory[1] = TB_UART_COMMAND[23:16];
                uart_mon_inst0.resp_memory[2] = TB_UART_COMMAND[15:8];
                uart_mon_inst0.resp_memory[3] = TB_UART_COMMAND[7:0];
            end

            if (VERBOSE_TB_LOG) begin
                $display("[%t] UART0 command selected: 3.%0d", $time, run_full_accel ? 4 : 3);
            end
        end
    endtask

    task preset_payload_ready_flags;
        begin
            if (PRESET_PAYLOAD_READY_FLAGS != 0) begin
                if (run_full_accel) begin
                    write_dmem_byte(TB_FULL_READY_FLAG_ADDR, 8'h01);
                    if (VERBOSE_TB_LOG) begin
                        $display("[%t] Preset firmware full-payload-ready flag at DMEM 0x%08h.",
                                 $time, TB_FULL_READY_FLAG_ADDR);
                    end
                end else begin
                    write_dmem_byte(TB_CONV1_READY_FLAG_ADDR, 8'h01);
                    if (VERBOSE_TB_LOG) begin
                        $display("[%t] Preset firmware conv1-payload-ready flag at DMEM 0x%08h.",
                                 $time, TB_CONV1_READY_FLAG_ADDR);
                    end
                end
            end
        end
    endtask

    initial begin
        run_full_accel = (RUN_FULL_ACCEL != 0);
        run_camera_ifmap_test = (RUN_CAMERA_IFMAP_TEST != 0);
        if ($test$plusargs("CNN_TB_CAM_IFMAP")) begin
            run_camera_ifmap_test = 1'b1;
        end
        if ($test$plusargs("CNN_TB_NO_CAM_IFMAP")) begin
            run_camera_ifmap_test = 1'b0;
        end
        require_camera_ifmap = (REQUIRE_CAMERA_IFMAP != 0) || run_camera_ifmap_test;
        if ($test$plusargs("CNN_TB_RUN_FULL")) begin
            run_full_accel = 1'b1;
        end
        if ($test$plusargs("CNN_TB_RUN_CONV1")) begin
            run_full_accel = 1'b0;
        end
        expected_done_irqs = (TB_EXPECTED_DONE_IRQS != 0) ? TB_EXPECTED_DONE_IRQS :
                              ((USE_TINY_ACCEL_PROGRAM != 0) ? 1 : (run_full_accel ? 9 : 1));
        if ($value$plusargs("CNN_TB_EXPECTED_IRQS=%d", expected_done_irqs)) begin
            if (VERBOSE_TB_LOG) begin
                $display("[%t] Expected CNN done IRQ count override: %0d", $time, expected_done_irqs);
            end
        end

        main_hex_file = MAIN_HEX_FILE;
        tiny_imem_hex_file = TINY_IMEM_HEX_FILE;
        tiny_bmem_hex_file = TINY_BMEM_HEX_FILE;
        video_frame_hex_file = VIDEO_FRAME_HEX_FILE;
        if ($value$plusargs("MAIN_HEX=%s", main_hex_file)) begin
            if (VERBOSE_TB_LOG) begin
                $display("[%t] MAIN_HEX override: %0s", $time, main_hex_file);
            end
        end
        if ($value$plusargs("TINY_IMEM_HEX=%s", tiny_imem_hex_file)) begin
            if (VERBOSE_TB_LOG) begin
                $display("[%t] TINY_IMEM_HEX override: %0s", $time, tiny_imem_hex_file);
            end
        end
        if ($value$plusargs("TINY_BMEM_HEX=%s", tiny_bmem_hex_file)) begin
            if (VERBOSE_TB_LOG) begin
                $display("[%t] TINY_BMEM_HEX override: %0s", $time, tiny_bmem_hex_file);
            end
        end
        if ($value$plusargs("VIDEO_FRAME_HEX=%s", video_frame_hex_file)) begin
            if (VERBOSE_TB_LOG) begin
                $display("[%t] VIDEO_FRAME_HEX override: %0s", $time, video_frame_hex_file);
            end
        end

        #1;
        clear_cpu_memories;
        load_video_framebuffer_hex;
        if (USE_TINY_ACCEL_PROGRAM != 0) begin
            if (run_camera_ifmap_test) begin
                if ((TB_PROGADDR_RESET != 32'h0100_0000) || (TB_PROGADDR_IRQ != 32'h0100_0010)) begin
                    $fatal(1, "[%t] CNN_TB_CAM_IFMAP needs BMEM vectors. Use RUN_CAMERA_IFMAP_TEST=1, or set TB_PROGADDR_RESET=0x01000000 and TB_PROGADDR_IRQ=0x01000010.", $time);
                end
                load_tiny_accel_bmem_hex;
            end else begin
                load_tiny_accel_imem_hex;
            end
        end else begin
            configure_uart_command;
            load_main_hex_boot_image;
            preset_payload_ready_flags;
        end
    end

    initial begin
        cam_pclk = 1'b0;
        forever #10 cam_pclk = ~cam_pclk;
    end

    function [15:0] cam_rgb565_pixel;
        input integer x;
        input integer y;
        reg [4:0] r;
        reg [5:0] g;
        reg [4:0] b;
        begin
            r = (x >> 1) & 5'h1F;
            g = (y >> 1) & 6'h3F;
            b = (x + y) & 5'h1F;
            cam_rgb565_pixel = {r, g, b};
        end
    endfunction

    task cam_send_byte;
        input [7:0] data;
        begin
            @(negedge cam_pclk);
            cam_half_pixel = data;
        end
    endtask

    task cam_send_pixel;
        input [15:0] rgb565;
        begin
            cam_send_byte(rgb565[15:8]);
            cam_send_byte(rgb565[7:0]);
        end
    endtask

    task cam_send_frame;
        integer x;
        integer y;
        begin
            cam_vsync = 1'b1;
            cam_href = 1'b0;
            repeat (16) @(negedge cam_pclk);
            cam_vsync = 1'b0;
            repeat (8) @(negedge cam_pclk);

            for (y = 0; y < CAM_STIM_HEIGHT; y = y + 1) begin
                cam_href = 1'b1;
                for (x = 0; x < CAM_STIM_WIDTH; x = x + 1) begin
                    cam_send_pixel(cam_rgb565_pixel(x, y));
                end
                cam_href = 1'b0;
                repeat (32) @(negedge cam_pclk);
            end

            cam_vsync = 1'b1;
            repeat (128) @(negedge cam_pclk);
        end
    endtask

    initial begin
        cam_half_pixel = 8'h00;
        cam_href = 1'b0;
        cam_vsync = 1'b1;

        if (ENABLE_CAMERA_STIMULUS != 0) begin
            wait (reset_n == 1'b1);
            wait (Beta_AISoC_uut.video_streaming.resetn_video == 1'b1);
            repeat (16) @(posedge cam_pclk);
            if (CAM_STIM_FORCE_WARMUP != 0) begin
                Beta_AISoC_uut.video_streaming.DVP_core.cam_Sensor.vs_cnt = 8'd20;
            end
            forever begin
                cam_send_frame;
            end
        end
    end

    initial begin
        wait (dram_inst0.PoweredUp == 1 && dram_inst1.PoweredUp == 1);
        if (VERBOSE_TB_LOG) begin
            $display("[%t] HyperRAM preload files are active:", $time);
            $display("  HR0 file: %0s", HYPERRAM0_MEM_FILE);
            $display("  HR1 file: %0s", HYPERRAM1_MEM_FILE);
            $display("  HR1 IFMAP byte @ 0x%06h / Mem @ 0x%06h", CNN_TB_IFMAP_BASE_BYTE, CNN_TB_IFMAP_BASE_WORD);
            $display("  HR1 OFMAP byte @ 0x%06h / Mem @ 0x%06h", CNN_TB_OFMAP_BASE_BYTE, CNN_TB_OFMAP_BASE_WORD);
            $display("  HR0 FLT   byte @ 0x%06h / Mem @ 0x%06h", CNN_TB_FLT_BASE_BYTE, CNN_TB_FLT_BASE_WORD);
            $display("  HR0 BIAS  byte @ 0x%06h / Mem @ 0x%06h", CNN_TB_BIAS_BASE_BYTE, CNN_TB_BIAS_BASE_WORD);
            $display("  HR0 MEM[0]   = 0x%04h", dram_inst0.Mem[0]);
            $display("  HR1 IFMAP[0] = 0x%04h", dram_inst1.Mem[CNN_TB_IFMAP_BASE_WORD]);
            $display("  HR1 OFMAP[0] = 0x%04h", dram_inst1.Mem[CNN_TB_OFMAP_BASE_WORD]);
            $display("  HR0 FLT[0]   = 0x%04h", dram_inst0.Mem[CNN_TB_FLT_BASE_WORD]);
            $display("  HR0 BIAS[0]  = 0x%04h", dram_inst0.Mem[CNN_TB_BIAS_BASE_WORD]);
        end
    end

    initial begin
        reset_n = 1'b0;
        gpi     = 4'b1100;
        irq_in  = 32'h0;

        if (VERBOSE_TB_LOG) begin
            $display("[%t] CNN DMA path TB start.", $time);
            $display("[%t] Add +dump_cnn_path if a VCD waveform is needed.", $time);
        end
        if (!QUIET_TB_LOG) begin
            $display("[%t] TB note: Vivado simulation uses rdata_vld = rdata_vld_reg[1] (`ifndef SYNTHESIS branch).", $time);
            $display("[%t] TB note: add tb_hr0_* / tb_hr1_* / tb_ifbuf_* / tb_flt_* / tb_bias_* / tb_ofbuf_* to wave.", $time);
        end

        dram_inst0.SPEED100 = 1;
        dram_inst1.SPEED100 = 1;

        wait (dram_inst0.PoweredUp == 1 && dram_inst1.PoweredUp == 1);
        if (VERBOSE_TB_LOG) begin
            $display("[%t] Both HyperRAM vendor models are powered up.", $time);
        end

        #100000;
        @(posedge clk_p);
        #1200;
        reset_n = 1'b1;
        if (VERBOSE_TB_LOG) begin
            $display("[%t] Reset released. CPU starts at 0x%08h.", $time, TB_PROGADDR_RESET);
        end
    end

    //---------------------------------------------------------
    // 6. CNN DMA Path Monitor
    //---------------------------------------------------------
    integer timeout_cycles;
    integer cycle_count;
    integer cfg_stall_limit;
    integer data_stall_limit;

    integer if_cfg_count,   if_beat_count,   if_last_count,   if_cfg_wait,   if_data_wait;
    integer flt_cfg_count,  flt_beat_count,  flt_last_count,  flt_cfg_wait,  flt_data_wait;
    integer bias_cfg_count, bias_beat_count, bias_last_count, bias_cfg_wait, bias_data_wait;
    integer of_cfg_count,   of_beat_count,   of_last_count,   of_cfg_wait,   of_data_wait;
    integer hr1_read_fifo_count, hr1_read_tlast_count;
    integer cnn_done_irq_count;

    reg [31:0] last_cnn_status;
    reg        last_irq_done;
    reg        last_cpu_irq3;
    reg        last_cpu_eoi3;
    reg [31:0] last_cpu_irq_mask;
    reg        saw_cnn_activity;
    reg        saw_camera_ifmap_cfg;
    reg        saw_camera_ifmap_data;
    reg        dumped_conv1_ofmap_row0;

    wire [31:0] cnn_status_dbg = Beta_AISoC_uut.cnn_accel.reg_status_r;
    wire [31:0] cpu0_irq_mask_dbg = Beta_AISoC_uut.cpu0.picorv32_core.irq_mask;

    // Wave aliases for checking the HyperRAM read-valid alignment.
    // Vivado simulation uses the RTL `ifndef SYNTHESIS` branch:
    //   rdata_vld = rdata_vld_reg[1]
    wire        tb_hr0_rdata_vld       = Beta_AISoC_uut.hyperram0.u_hyperbus_master.rdata_vld;
    wire [1:0]  tb_hr0_rdata_vld_pipe  = Beta_AISoC_uut.hyperram0.u_hyperbus_master.dut.rdata_vld_reg[1:0];
    wire [7:0]  tb_hr0_rdata           = Beta_AISoC_uut.hyperram0.u_hyperbus_master.rdata;
    wire [7:0]  tb_hr0_dq_i_reg        = Beta_AISoC_uut.hyperram0.u_hyperbus_master.dut.dq_i_reg;
    wire [3:0]  tb_hr0_bus_state       = Beta_AISoC_uut.hyperram0.u_hyperbus_master.dut.bus_state;
    wire [3:0]  tb_hr0_bus_state_prev  = Beta_AISoC_uut.hyperram0.u_hyperbus_master.dut.bus_state_prev;
    wire        tb_hr0_wr_read_fifo    = Beta_AISoC_uut.hyperram0.wr_read_fifo;
    wire        tb_hr0_tlast_read_fifo = Beta_AISoC_uut.hyperram0.tlast_read_fifo;
    wire [9:0]  tb_hr0_total_bytes     = Beta_AISoC_uut.hyperram0.coordinator_center_dmac.coordinator_center_dmac.total_bytes_reg;
    wire [9:0]  tb_hr0_tlast_counter   = Beta_AISoC_uut.hyperram0.coordinator_center_dmac.coordinator_center_dmac.tlast_counter_reg;
    wire        tb_hr0_read_active     = Beta_AISoC_uut.hyperram0.coordinator_center_dmac.coordinator_center_dmac.read_packet_active_reg;

    wire        tb_hr1_rdata_vld       = Beta_AISoC_uut.hyperram1.u_hyperbus_master.rdata_vld;
    wire [1:0]  tb_hr1_rdata_vld_pipe  = Beta_AISoC_uut.hyperram1.u_hyperbus_master.dut.rdata_vld_reg[1:0];
    wire [7:0]  tb_hr1_rdata           = Beta_AISoC_uut.hyperram1.u_hyperbus_master.rdata;
    wire [7:0]  tb_hr1_dq_i_reg        = Beta_AISoC_uut.hyperram1.u_hyperbus_master.dut.dq_i_reg;
    wire [3:0]  tb_hr1_bus_state       = Beta_AISoC_uut.hyperram1.u_hyperbus_master.dut.bus_state;
    wire [3:0]  tb_hr1_bus_state_prev  = Beta_AISoC_uut.hyperram1.u_hyperbus_master.dut.bus_state_prev;
    wire        tb_hr1_wr_read_fifo    = Beta_AISoC_uut.hyperram1.wr_read_fifo;
    wire        tb_hr1_tlast_read_fifo = Beta_AISoC_uut.hyperram1.tlast_read_fifo;
    wire [9:0]  tb_hr1_total_bytes     = Beta_AISoC_uut.hyperram1.coordinator_center_dmac.coordinator_center_dmac.total_bytes_reg;
    wire [9:0]  tb_hr1_tlast_counter   = Beta_AISoC_uut.hyperram1.coordinator_center_dmac.coordinator_center_dmac.tlast_counter_reg;
    wire        tb_hr1_read_active     = Beta_AISoC_uut.hyperram1.coordinator_center_dmac.coordinator_center_dmac.read_packet_active_reg;

    wire        tb_select_video        = Beta_AISoC_uut.video_grant_request_cam2accel;
    wire [23:0] tb_video_fb_addr       = Beta_AISoC_uut.video_streaming.DVP_core.fb_addr;
    wire [15:0] tb_video_fb_pixel      = Beta_AISoC_uut.video_streaming.DVP_core.fb_pixel_data;
    wire        tb_video_axis_vld      = Beta_AISoC_uut.video_streaming.m_tvalid_o;
    wire        tb_video_axis_rdy      = Beta_AISoC_uut.video_streaming.m_tready_i;
    wire [7:0]  tb_video_axis_data     = Beta_AISoC_uut.video_streaming.m_tdata_o;
    wire        tb_video_axis_last     = Beta_AISoC_uut.video_streaming.m_tlast_o;
    wire        tb_ifbuf_vldcfg        = Beta_AISoC_uut.cnn_ifbuf_dma_vldcfg;
    wire        tb_ifbuf_rdycfg        = Beta_AISoC_uut.cnn_ifbuf_dma_rdycfg;
    wire        tb_ifbuf_vld           = Beta_AISoC_uut.cnn_ifbuf_dma_vld;
    wire        tb_ifbuf_rdy           = Beta_AISoC_uut.cnn_ifbuf_dma_rdy;
    wire        tb_ifbuf_tlast         = Beta_AISoC_uut.cnn_ifbuf_dma_tlast;
    wire [7:0]  tb_ifbuf_data          = Beta_AISoC_uut.cnn_ifbuf_dma_data;
    wire        tb_flt_vld             = Beta_AISoC_uut.hyperram0_m_tvalid_o;
    wire        tb_flt_rdy             = Beta_AISoC_uut.hyperram0_m_tready_i;
    wire        tb_flt_tlast           = Beta_AISoC_uut.hyperram0_m_tlast_o;
    wire [7:0]  tb_flt_data            = Beta_AISoC_uut.hyperram0_m_tdata_o;
    wire        tb_bias_vld            = Beta_AISoC_uut.hyperram0_m1_tvalid_o;
    wire        tb_bias_rdy            = Beta_AISoC_uut.hyperram0_m1_tready_i;
    wire        tb_bias_tlast          = Beta_AISoC_uut.hyperram0_m1_tlast_o;
    wire [7:0]  tb_bias_data           = Beta_AISoC_uut.hyperram0_m1_tdata_o;
    wire        tb_ofbuf_vld           = Beta_AISoC_uut.hyperram1_s_tvalid_i;
    wire        tb_ofbuf_rdy           = Beta_AISoC_uut.hyperram1_s_tready_o;
    wire        tb_ofbuf_tlast         = Beta_AISoC_uut.hyperram1_s_tlast_i;
    wire [7:0]  tb_ofbuf_data          = Beta_AISoC_uut.hyperram1_s_tdata_i;

    task print_compact_accel_summary;
    begin
        $display("  STATUS=0x%08h table_vld=%0d table_rdy=%0d busy=%0d done=%0d start=%0d irq=%0d eoi[3]=%0d",
                 cnn_status_dbg,
                 cnn_status_dbg[0],
                 cnn_status_dbg[1],
                 cnn_status_dbg[2],
                 cnn_status_dbg[3],
                 cnn_status_dbg[4],
                 Beta_AISoC_uut.cnn_irq_accel_done,
                 Beta_AISoC_uut.cpu0_eoi[3]);
        $display("  IF cfg/data/tlast=%0d/%0d/%0d | FLT=%0d/%0d/%0d | BIAS=%0d/%0d/%0d | OF=%0d/%0d/%0d | select_video=%0d",
                 if_cfg_count, if_beat_count, if_last_count,
                 flt_cfg_count, flt_beat_count, flt_last_count,
                 bias_cfg_count, bias_beat_count, bias_last_count,
                 of_cfg_count, of_beat_count, of_last_count,
                 Beta_AISoC_uut.video_grant_request_cam2accel);
    end
    endtask

    task print_path_summary;
    begin
        if (VERBOSE_TB_LOG) begin
        $display("");
        $display("=======================================================");
        $display(" CNN DMA path summary at cycle %0d", cycle_count);
        $display("  STATUS=0x%08h table_vld=%0d table_rdy=%0d busy=%0d done=%0d start=%0d irq=%0d",
                 cnn_status_dbg,
                 cnn_status_dbg[0],
                 cnn_status_dbg[1],
                 cnn_status_dbg[2],
                 cnn_status_dbg[3],
                 cnn_status_dbg[4],
                 Beta_AISoC_uut.cnn_irq_accel_done);
        $display("  CPU IRQ: irq[3]=%0d eoi[3]=%0d irq_mask=0x%08h",
                 Beta_AISoC_uut.cpu0_irq[3],
                 Beta_AISoC_uut.cpu0_eoi[3],
                 cpu0_irq_mask_dbg);
        $display("  IFBUF : cfg=%0d beats=%0d tlast=%0d  src_video=%0d",
                 if_cfg_count, if_beat_count, if_last_count,
                 Beta_AISoC_uut.video_grant_request_cam2accel);
        $display("  FLTBUF: cfg=%0d beats=%0d tlast=%0d",
                 flt_cfg_count, flt_beat_count, flt_last_count);
        $display("  BIAS  : cfg=%0d beats=%0d tlast=%0d",
                 bias_cfg_count, bias_beat_count, bias_last_count);
        $display("  OFBUF : cfg=%0d beats=%0d tlast=%0d",
                 of_cfg_count, of_beat_count, of_last_count);
        $display("  HR0 AR v/r=%0d/%0d addr=0x%06h burst=%0d | HR0 m1 v/r/last=%0d/%0d/%0d",
                 Beta_AISoC_uut.hyperram0_ARVALID_i,
                 Beta_AISoC_uut.hyperram0_ARREADY_o,
                 Beta_AISoC_uut.hyperram0_ARADDR_i,
                 Beta_AISoC_uut.hyperram0_ARBURST_i,
                 Beta_AISoC_uut.hyperram0_m1_tvalid_o,
                 Beta_AISoC_uut.hyperram0_m1_tready_i,
                 Beta_AISoC_uut.hyperram0_m1_tlast_o);
        $display("  HR0 AW v/r=%0d/%0d addr=0x%06h burst=%0d | HR0 m0 v/r/last=%0d/%0d/%0d",
                 Beta_AISoC_uut.hyperram0_AWVALID_i,
                 Beta_AISoC_uut.hyperram0_AWREADY_o,
                 Beta_AISoC_uut.hyperram0_AWADDR_i,
                 Beta_AISoC_uut.hyperram0_AWBURST_i,
                 Beta_AISoC_uut.hyperram0_m_tvalid_o,
                 Beta_AISoC_uut.hyperram0_m_tready_i,
                 Beta_AISoC_uut.hyperram0_m_tlast_o);
        $display("  HR1 AR v/r=%0d/%0d addr=0x%06h burst=%0d | HR1 m v/r/last=%0d/%0d/%0d",
                 Beta_AISoC_uut.hyperram1_ARVALID_i,
                 Beta_AISoC_uut.hyperram1_ARREADY_o,
                 Beta_AISoC_uut.hyperram1_ARADDR_i,
                 Beta_AISoC_uut.hyperram1_ARBURST_i,
                 Beta_AISoC_uut.hyperram1_m_tvalid_o,
                 Beta_AISoC_uut.hyperram1_m_tready_i,
                 Beta_AISoC_uut.hyperram1_m_tlast_o);
        $display("  HR1 AW v/r=%0d/%0d addr=0x%06h burst=%0d | HR1 s v/r/last=%0d/%0d/%0d",
                 Beta_AISoC_uut.hyperram1_AWVALID_i,
                 Beta_AISoC_uut.hyperram1_AWREADY_o,
                 Beta_AISoC_uut.hyperram1_AWADDR_i,
                 Beta_AISoC_uut.hyperram1_AWBURST_i,
                 Beta_AISoC_uut.hyperram1_s_tvalid_i,
                 Beta_AISoC_uut.hyperram1_s_tready_o,
                 Beta_AISoC_uut.hyperram1_s_tlast_i);
        $display("  HR1 DMAC read fifo writes=%0d src_tlast=%0d wr=%0d src_last=%0d total_bytes=%0d tlast_counter=%0d",
                 hr1_read_fifo_count,
                 hr1_read_tlast_count,
                 Beta_AISoC_uut.hyperram1.wr_read_fifo,
                 Beta_AISoC_uut.hyperram1.tlast_read_fifo,
                 Beta_AISoC_uut.hyperram1.coordinator_center_dmac.coordinator_center_dmac.total_bytes_reg,
                 Beta_AISoC_uut.hyperram1.coordinator_center_dmac.coordinator_center_dmac.tlast_counter_reg);
        $display("=======================================================");
        $display("");
        end
    end
    endtask

    task dump_conv1_ofmap_row0;
        integer dump_i;
        begin
            $display("");
            $display("=======================================================");
            $display(" HR1 Conv1 OFMAP oc0,row0 dump");
            $display("  FW flags: source_ready=%02h full_ready=%02h conv1_ready=%02h",
                     read_dmem_byte(TB_CONV1_SOURCE_READY_ADDR),
                     read_dmem_byte(TB_FULL_READY_FLAG_ADDR),
                     read_dmem_byte(TB_CONV1_READY_FLAG_ADDR));
            $write("  FW s_conv1_weight[0..15] =");
            for (dump_i = 0; dump_i < 16; dump_i = dump_i + 1) begin
                $write(" %02h", read_dmem_byte(TB_CONV1_WEIGHT_ADDR + dump_i));
            end
            $write("\n");
            $write("  FW s_conv1_bias[0..3]    =");
            for (dump_i = 0; dump_i < 4; dump_i = dump_i + 1) begin
                $write(" %02h", read_dmem_byte(TB_CONV1_BIAS_ADDR + dump_i));
            end
            $write("\n");
            $display("  byte base = 0x%06h, vendor Mem base = 0x%06h",
                     CNN_TB_OFMAP_BASE_BYTE, CNN_TB_OFMAP_BASE_WORD);
            for (dump_i = 0; dump_i < DUMP_CONV1_OFMAP_WORDS; dump_i = dump_i + 1) begin
                $display("  Mem[%06h] = %04h",
                         CNN_TB_OFMAP_BASE_WORD + dump_i,
                         dram_inst1.Mem[CNN_TB_OFMAP_BASE_WORD + dump_i][15:0]);
            end
            $display("=======================================================");
            $display("");
        end
    endtask

    initial begin
        timeout_cycles  = ((RUN_FULL_ACCEL != 0) || $test$plusargs("CNN_TB_RUN_FULL")) ? 200_000_000 : 20_000_000;
        if ($test$plusargs("CNN_TB_RUN_CONV1")) begin
            timeout_cycles = 20_000_000;
        end
        cfg_stall_limit = 200_000;
        data_stall_limit = 200_000;
        if ($value$plusargs("CNN_PATH_TIMEOUT=%d", timeout_cycles)) begin
            if (VERBOSE_TB_LOG) begin
                $display("[%t] CNN path timeout override: %0d cycles.", $time, timeout_cycles);
            end
        end
    end

    always @(posedge clk_p or negedge reset_n) begin
        if (!reset_n) begin
            cycle_count      <= 0;
            if_cfg_count     <= 0;
            if_beat_count    <= 0;
            if_last_count    <= 0;
            if_cfg_wait      <= 0;
            if_data_wait     <= 0;
            flt_cfg_count    <= 0;
            flt_beat_count   <= 0;
            flt_last_count   <= 0;
            flt_cfg_wait     <= 0;
            flt_data_wait    <= 0;
            bias_cfg_count   <= 0;
            bias_beat_count  <= 0;
            bias_last_count  <= 0;
            bias_cfg_wait    <= 0;
            bias_data_wait   <= 0;
            of_cfg_count     <= 0;
            of_beat_count    <= 0;
            of_last_count    <= 0;
            of_cfg_wait      <= 0;
            of_data_wait     <= 0;
            hr1_read_fifo_count  <= 0;
            hr1_read_tlast_count <= 0;
            cnn_done_irq_count <= 0;
            last_cnn_status  <= 32'hFFFF_FFFF;
            last_irq_done    <= 1'b0;
            last_cpu_irq3    <= 1'b0;
            last_cpu_eoi3    <= 1'b0;
            last_cpu_irq_mask <= 32'hFFFF_FFFF;
            saw_cnn_activity <= 1'b0;
            saw_camera_ifmap_cfg <= 1'b0;
            saw_camera_ifmap_data <= 1'b0;
            dumped_conv1_ofmap_row0 <= 1'b0;
        end else begin
            cycle_count <= cycle_count + 1;

            if (cnn_status_dbg != last_cnn_status) begin
                if (VERBOSE_TB_LOG) begin
                    $display("[%t] CNN STATUS 0x%08h -> 0x%08h  table_vld=%0d table_rdy=%0d busy=%0d done=%0d start=%0d",
                             $time, last_cnn_status, cnn_status_dbg,
                             cnn_status_dbg[0], cnn_status_dbg[1],
                             cnn_status_dbg[2], cnn_status_dbg[3],
                             cnn_status_dbg[4]);
                end
                last_cnn_status <= cnn_status_dbg;
            end

            if (Beta_AISoC_uut.cnn_irq_accel_done != last_irq_done) begin
                if (VERBOSE_TB_LOG) begin
                    $display("[%t] CNN IRQ done changed to %0d.", $time, Beta_AISoC_uut.cnn_irq_accel_done);
                end
                if (Beta_AISoC_uut.cnn_irq_accel_done) begin
                    cnn_done_irq_count <= cnn_done_irq_count + 1;
                    if ((DUMP_CONV1_OFMAP_ROW0 != 0) && !run_full_accel && !dumped_conv1_ofmap_row0) begin
                        dumped_conv1_ofmap_row0 <= 1'b1;
                        dump_conv1_ofmap_row0;
                    end
                    if (!QUIET_TB_LOG && (VERBOSE_TB_LOG || ((cnn_done_irq_count + 1) >= expected_done_irqs))) begin
                        $display("[%t] CNN accelerator done IRQ observed (%0d/%0d).",
                                 $time, cnn_done_irq_count + 1, expected_done_irqs);
                        if ((USE_TINY_ACCEL_PROGRAM != 0) && ((cnn_done_irq_count + 1) >= expected_done_irqs)) begin
                            $display("Tiny CNN accel program -> IRQ PASS");
                            print_compact_accel_summary;
                        end
                        print_path_summary;
                    end
                    if ((cnn_done_irq_count + 1) >= expected_done_irqs) begin
                        if (require_camera_ifmap &&
                            (!saw_camera_ifmap_cfg || !saw_camera_ifmap_data)) begin
                            $fatal(1, "[%t] ERROR: camera IFMAP was required, but video cfg/data was not observed before first done IRQ.", $time);
                        end
                        #5000000;
                        $finish;
                    end
                end
                last_irq_done <= Beta_AISoC_uut.cnn_irq_accel_done;
            end

            if (Beta_AISoC_uut.cpu0_irq[3] != last_cpu_irq3) begin
                if (VERBOSE_TB_LOG) begin
                    $display("[%t] CPU irq[3] changed to %0d.", $time, Beta_AISoC_uut.cpu0_irq[3]);
                end
                last_cpu_irq3 <= Beta_AISoC_uut.cpu0_irq[3];
            end

            if (Beta_AISoC_uut.cpu0_eoi[3] != last_cpu_eoi3) begin
                if (VERBOSE_TB_LOG) begin
                    $display("[%t] CPU eoi[3] changed to %0d.", $time, Beta_AISoC_uut.cpu0_eoi[3]);
                end
                last_cpu_eoi3 <= Beta_AISoC_uut.cpu0_eoi[3];
            end

            if (cpu0_irq_mask_dbg != last_cpu_irq_mask) begin
                if (VERBOSE_TB_LOG) begin
                    $display("[%t] CPU irq_mask 0x%08h -> 0x%08h  irq[3] is %s",
                             $time,
                             last_cpu_irq_mask,
                             cpu0_irq_mask_dbg,
                             cpu0_irq_mask_dbg[3] ? "masked" : "enabled");
                end
                last_cpu_irq_mask <= cpu0_irq_mask_dbg;
            end

            // IFBUF path: CNN or video mux -> HyperRAM1 read -> accel IFBUF stream.
            if (Beta_AISoC_uut.cnn_ifbuf_dma_vldcfg) begin
                saw_cnn_activity <= 1'b1;
                if_cfg_wait <= Beta_AISoC_uut.cnn_ifbuf_dma_rdycfg ? 0 : if_cfg_wait + 1;
            end else begin
                if_cfg_wait <= 0;
            end

            if (Beta_AISoC_uut.cnn_ifbuf_dma_vldcfg && Beta_AISoC_uut.cnn_ifbuf_dma_rdycfg) begin
                if_cfg_count <= if_cfg_count + 1;
                if (Beta_AISoC_uut.video_grant_request_cam2accel) begin
                    saw_camera_ifmap_cfg <= 1'b1;
                end else if (require_camera_ifmap && (if_cfg_count == 0)) begin
                    $fatal(1, "[%t] ERROR: first IFBUF config was not routed to camera/video.", $time);
                end
                if (VERBOSE_TB_LOG && Beta_AISoC_uut.video_grant_request_cam2accel) begin
                    $display("[%t] IFBUF CFG #%0d routed to VIDEO  addr=0x%06h burst=%0d",
                             $time, if_cfg_count + 1,
                             Beta_AISoC_uut.cnn_ifbuf_dma_baddr,
                             Beta_AISoC_uut.cnn_ifbuf_dma_burst);
                    $display("[%t] WARNING: Conv1 static-image test normally expects IFBUF from HyperRAM1, not video.", $time);
                end else if (VERBOSE_TB_LOG) begin
                    $display("[%t] IFBUF CFG #%0d routed to HR1 AR addr=0x%06h burst=%0d",
                             $time, if_cfg_count + 1,
                             Beta_AISoC_uut.cnn_ifbuf_dma_baddr,
                             Beta_AISoC_uut.cnn_ifbuf_dma_burst);
                end
            end

            if (Beta_AISoC_uut.cnn_ifbuf_dma_vld && !Beta_AISoC_uut.cnn_ifbuf_dma_rdy) begin
                if_data_wait <= if_data_wait + 1;
            end else begin
                if_data_wait <= 0;
            end

            if (Beta_AISoC_uut.cnn_ifbuf_dma_vld && Beta_AISoC_uut.cnn_ifbuf_dma_rdy) begin
                if_beat_count <= if_beat_count + 1;
                if (Beta_AISoC_uut.video_grant_request_cam2accel) begin
                    saw_camera_ifmap_data <= 1'b1;
                    if (require_camera_ifmap &&
                        (^Beta_AISoC_uut.cnn_ifbuf_dma_data === 1'bx)) begin
                        $display("[%t] ERROR: camera IFMAP data contains X. fb_addr=%0d fb_pixel=0x%04h video_axis=%0d/%0d data=0x%02h last=%0d",
                                 $time,
                                 Beta_AISoC_uut.video_streaming.DVP_core.fb_addr,
                                 Beta_AISoC_uut.video_streaming.DVP_core.fb_pixel_data,
                                 Beta_AISoC_uut.video_streaming.m_tvalid_o,
                                 Beta_AISoC_uut.video_streaming.m_tready_i,
                                 Beta_AISoC_uut.video_streaming.m_tdata_o,
                                 Beta_AISoC_uut.video_streaming.m_tlast_o);
                        $fatal(1, "[%t] ERROR: camera IFMAP data contains X.", $time);
                    end
                end
                if (VERBOSE_TB_LOG && (if_beat_count < 8)) begin
                    $display("[%t] IFBUF DATA beat #%0d data=0x%02h last=%0d",
                             $time, if_beat_count + 1,
                             Beta_AISoC_uut.cnn_ifbuf_dma_data,
                             Beta_AISoC_uut.cnn_ifbuf_dma_tlast);
                end
                if (Beta_AISoC_uut.cnn_ifbuf_dma_tlast) begin
                    if_last_count <= if_last_count + 1;
                    if (VERBOSE_TB_LOG) begin
                        $display("[%t] IFBUF DATA TLAST #%0d total_beats=%0d",
                                 $time, if_last_count + 1, if_beat_count + 1);
                    end
                end
            end

            if (Beta_AISoC_uut.hyperram1.wr_read_fifo) begin
                hr1_read_fifo_count <= hr1_read_fifo_count + 1;
                if (Beta_AISoC_uut.hyperram1.tlast_read_fifo) begin
                    hr1_read_tlast_count <= hr1_read_tlast_count + 1;
                    if (VERBOSE_TB_LOG) begin
                        $display("[%t] HR1 DMAC SRC TLAST #%0d fifo_writes=%0d total_bytes=%0d tlast_counter=%0d",
                                 $time,
                                 hr1_read_tlast_count + 1,
                                 hr1_read_fifo_count + 1,
                                 Beta_AISoC_uut.hyperram1.coordinator_center_dmac.coordinator_center_dmac.total_bytes_reg,
                                 Beta_AISoC_uut.hyperram1.coordinator_center_dmac.coordinator_center_dmac.tlast_counter_reg);
                    end
                end
            end

            // FLTBUF path: CNN -> HyperRAM0 AW read port -> m0 stream -> accel.
            if (Beta_AISoC_uut.hyperram0_AWVALID_i) begin
                saw_cnn_activity <= 1'b1;
                flt_cfg_wait <= Beta_AISoC_uut.hyperram0_AWREADY_o ? 0 : flt_cfg_wait + 1;
            end else begin
                flt_cfg_wait <= 0;
            end

            if (Beta_AISoC_uut.hyperram0_AWVALID_i && Beta_AISoC_uut.hyperram0_AWREADY_o) begin
                flt_cfg_count <= flt_cfg_count + 1;
                if (VERBOSE_TB_LOG) begin
                    $display("[%t] FLTBUF CFG #%0d via HR0 AW-read addr=0x%06h burst=%0d",
                             $time, flt_cfg_count + 1,
                             Beta_AISoC_uut.hyperram0_AWADDR_i,
                             Beta_AISoC_uut.hyperram0_AWBURST_i);
                end
            end

            if (Beta_AISoC_uut.hyperram0_m_tvalid_o && !Beta_AISoC_uut.hyperram0_m_tready_i) begin
                flt_data_wait <= flt_data_wait + 1;
            end else begin
                flt_data_wait <= 0;
            end

            if (Beta_AISoC_uut.hyperram0_m_tvalid_o && Beta_AISoC_uut.hyperram0_m_tready_i) begin
                flt_beat_count <= flt_beat_count + 1;
                if (VERBOSE_TB_LOG && (flt_beat_count < 8)) begin
                    $display("[%t] FLTBUF DATA beat #%0d data=0x%02h last=%0d",
                             $time, flt_beat_count + 1,
                             Beta_AISoC_uut.hyperram0_m_tdata_o,
                             Beta_AISoC_uut.hyperram0_m_tlast_o);
                end
                if (Beta_AISoC_uut.hyperram0_m_tlast_o) begin
                    flt_last_count <= flt_last_count + 1;
                    if (VERBOSE_TB_LOG) begin
                        $display("[%t] FLTBUF DATA TLAST #%0d total_beats=%0d",
                                 $time, flt_last_count + 1, flt_beat_count + 1);
                    end
                end
            end

            // BIAS path: CNN -> HyperRAM0 AR read port -> m1 stream -> accel.
            if (Beta_AISoC_uut.hyperram0_ARVALID_i) begin
                saw_cnn_activity <= 1'b1;
                bias_cfg_wait <= Beta_AISoC_uut.hyperram0_ARREADY_o ? 0 : bias_cfg_wait + 1;
            end else begin
                bias_cfg_wait <= 0;
            end

            if (Beta_AISoC_uut.hyperram0_ARVALID_i && Beta_AISoC_uut.hyperram0_ARREADY_o) begin
                bias_cfg_count <= bias_cfg_count + 1;
                if (VERBOSE_TB_LOG) begin
                    $display("[%t] BIAS CFG #%0d via HR0 AR-read addr=0x%06h burst=%0d",
                             $time, bias_cfg_count + 1,
                             Beta_AISoC_uut.hyperram0_ARADDR_i,
                             Beta_AISoC_uut.hyperram0_ARBURST_i);
                end
            end

            if (Beta_AISoC_uut.hyperram0_m1_tvalid_o && !Beta_AISoC_uut.hyperram0_m1_tready_i) begin
                bias_data_wait <= bias_data_wait + 1;
            end else begin
                bias_data_wait <= 0;
            end

            if (Beta_AISoC_uut.hyperram0_m1_tvalid_o && Beta_AISoC_uut.hyperram0_m1_tready_i) begin
                bias_beat_count <= bias_beat_count + 1;
                if (VERBOSE_TB_LOG && (bias_beat_count < 8)) begin
                    $display("[%t] BIAS DATA beat #%0d data=0x%02h last=%0d",
                             $time, bias_beat_count + 1,
                             Beta_AISoC_uut.hyperram0_m1_tdata_o,
                             Beta_AISoC_uut.hyperram0_m1_tlast_o);
                end
                if (Beta_AISoC_uut.hyperram0_m1_tlast_o) begin
                    bias_last_count <= bias_last_count + 1;
                    if (VERBOSE_TB_LOG) begin
                        $display("[%t] BIAS DATA TLAST #%0d total_beats=%0d",
                                 $time, bias_last_count + 1, bias_beat_count + 1);
                    end
                end
            end

            // OFBUF path: CNN -> HyperRAM1 AW write config + slave stream.
            if (Beta_AISoC_uut.hyperram1_AWVALID_i) begin
                saw_cnn_activity <= 1'b1;
                of_cfg_wait <= Beta_AISoC_uut.hyperram1_AWREADY_o ? 0 : of_cfg_wait + 1;
            end else begin
                of_cfg_wait <= 0;
            end

            if (Beta_AISoC_uut.hyperram1_AWVALID_i && Beta_AISoC_uut.hyperram1_AWREADY_o) begin
                of_cfg_count <= of_cfg_count + 1;
                if (VERBOSE_TB_LOG) begin
                    $display("[%t] OFBUF CFG #%0d via HR1 AW-write addr=0x%06h burst=%0d",
                             $time, of_cfg_count + 1,
                             Beta_AISoC_uut.hyperram1_AWADDR_i,
                             Beta_AISoC_uut.hyperram1_AWBURST_i);
                end
            end

            if (Beta_AISoC_uut.hyperram1_s_tvalid_i && !Beta_AISoC_uut.hyperram1_s_tready_o) begin
                of_data_wait <= of_data_wait + 1;
            end else begin
                of_data_wait <= 0;
            end

            if (Beta_AISoC_uut.hyperram1_s_tvalid_i && Beta_AISoC_uut.hyperram1_s_tready_o) begin
                of_beat_count <= of_beat_count + 1;
                if (VERBOSE_TB_LOG && (of_beat_count < 8)) begin
                    $display("[%t] OFBUF DATA beat #%0d data=0x%02h last=%0d",
                             $time, of_beat_count + 1,
                             Beta_AISoC_uut.hyperram1_s_tdata_i,
                             Beta_AISoC_uut.hyperram1_s_tlast_i);
                end
                if (Beta_AISoC_uut.hyperram1_s_tlast_i) begin
                    of_last_count <= of_last_count + 1;
                    if (VERBOSE_TB_LOG) begin
                        $display("[%t] OFBUF DATA TLAST #%0d total_beats=%0d",
                                 $time, of_last_count + 1, of_beat_count + 1);
                    end
                end
            end

            if (if_cfg_wait == cfg_stall_limit) begin
                $display("[%t] ERROR: IFBUF cfg valid stuck without ready.", $time);
                print_path_summary;
            end
            if (flt_cfg_wait == cfg_stall_limit) begin
                $display("[%t] ERROR: FLTBUF cfg valid stuck without ready.", $time);
                print_path_summary;
            end
            if (bias_cfg_wait == cfg_stall_limit) begin
                $display("[%t] ERROR: BIAS cfg valid stuck without ready.", $time);
                print_path_summary;
            end
            if (of_cfg_wait == cfg_stall_limit) begin
                $display("[%t] ERROR: OFBUF cfg valid stuck without ready.", $time);
                print_path_summary;
            end

            if (if_data_wait == data_stall_limit) begin
                $display("[%t] ERROR: IFBUF data valid stuck without ready.", $time);
                print_path_summary;
            end
            if (flt_data_wait == data_stall_limit) begin
                $display("[%t] ERROR: FLTBUF data valid stuck without ready.", $time);
                print_path_summary;
            end
            if (bias_data_wait == data_stall_limit) begin
                $display("[%t] ERROR: BIAS data valid stuck without ready.", $time);
                print_path_summary;
            end
            if (of_data_wait == data_stall_limit) begin
                $display("[%t] ERROR: OFBUF data valid stuck without ready.", $time);
                print_path_summary;
            end

            if (VERBOSE_TB_LOG && (cycle_count % 500000) == 0 && cycle_count != 0) begin
                print_path_summary;
            end

            if (timeout_cycles != 0 && cycle_count >= timeout_cycles) begin
                if (!saw_cnn_activity) begin
                    $display("[%t] TIMEOUT: No CNN DMA activity observed. Firmware may not have run the selected menu command.", $time);
                end else begin
                    $display("[%t] TIMEOUT: CNN DMA activity observed but no done IRQ.", $time);
                end
                if (USE_TINY_ACCEL_PROGRAM != 0) begin
                    $display("Tiny CNN accel program -> FAIL");
                    print_compact_accel_summary;
                end
                print_path_summary;
                $finish;
            end

            if (trap0 || trap1) begin
                $display("[%t] Trap detected: trap0=%0d trap1=%0d.", $time, trap0, trap1);
                print_path_summary;
                #50000;
                $finish;
            end
        end
    end

endmodule
