`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 02/01/2026 03:13:32 PM
// Design Name: 
// Module Name: Beta_AISoC_SPIflash_tb
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


module Beta_AISoC_SPIflash_tb;

    //===========================================
    // 1. Clock & Reset Signals
    //===========================================
    reg clk_p, clk_n;
    reg reset_n;

    // UART
    reg  rx0;
    wire tx0;

    // SPI
    wire        spi0_clk;
    wire        spi0_mosi;
    wire        spi0_miso; // Chuyển thành wire để nhận từ Model
    wire [1:0]  spi0_ss_n;

    // I2C
    tri         i2c0_scl;
    tri         i2c0_sda;

    // OSPI & GPIO
    tri [7:0]   ospi0_dq_io;
    tri         ospi0_rwds_io;
    wire        ospi0_hclk_p;
    wire        ospi0_cs_n;
    wire [7:0]  gpio;

    // Trap
    wire trap0, trap1;

    // Pull-ups cho I2C
    pullup(i2c0_scl);
    pullup(i2c0_sda);

    //===========================================
    // 2. Instantiate Top-level SoC (UUT)
    //===========================================
    Beta_AISoC uut (
        .clk_p(clk_p),
        .clk_n(clk_n),
        .reset_n(reset_n),
        .trap0(trap0),
        .trap1(trap1),
        .rx0(rx0),
        .tx0(tx0),
        .spi0_clk(spi0_clk),
        .spi0_mosi(spi0_mosi),
        .spi0_miso(spi0_miso),
        .spi0_ss_n(spi0_ss_n),      
        .i2c0_scl(i2c0_scl),
        .i2c0_sda(i2c0_sda),
        .ospi0_dq_io(ospi0_dq_io),
        .ospi0_rwds_io(ospi0_rwds_io),
        .ospi0_hclk_p(ospi0_hclk_p),
        .ospi0_cs_n(ospi0_cs_n),
        .gpio_io(gpio)
    );

    //===========================================
    // 3. SPI Flash Winbond Model (Giả lập)
    //===========================================
    // Kết nối model vào Slave Select 0 (spi0_ss_n[0])
    spiflash_model flash_memory (
        .cs_n(spi0_ss_n[0]),
        .sck(spi0_clk),
        .mosi(spi0_mosi),
        .miso(spi0_miso)
    );

    //===========================================
    // 4. Clock Generation (200 MHz)
    //===========================================
    initial begin
        clk_p = 0;
        clk_n = 1;
        forever begin
            #2.5 clk_p = ~clk_p;
            clk_n = ~clk_p;
        end
    end

    //===========================================
    // 5. Stimulus & Memory Initialization
    //===========================================
    initial begin
        // Khởi tạo các tín hiệu
        reset_n   = 0;
        rx0       = 1;
        
        // --- Nạp dữ liệu giả lập vào Flash ---
        // // Word đầu tiên: 0x11223344 (Theo code C Big Endian)
        // flash_memory.mem[0] = 8'h11; 
        // flash_memory.mem[1] = 8'h22;
        // flash_memory.mem[2] = 8'h33;
        // flash_memory.mem[3] = 8'h44;

        // flash_memory.mem[4] = 8'hAA;    
        // flash_memory.mem[5] = 8'hBB;
        // flash_memory.mem[6] = 8'hCC;
        // flash_memory.mem[7] = 8'hDD;
        
        // // Sequence kết thúc: 0xFFFFFFFF (Để thoát while(1))
        // flash_memory.mem[8] = 8'hFF;
        // flash_memory.mem[9] = 8'hFF;
        // flash_memory.mem[10 ] = 8'hFF;
        // flash_memory.mem[11] = 8'hFF;

        // flash_memory.mem[12] = 8'hFF;
        // flash_memory.mem[13] = 8'hFF;
        // flash_memory.mem[14] = 8'hFF;
        // flash_memory.mem[15 ] = 8'hFF;

        $display("[%t] Starting Simulation...", $time);

        // Giải phóng Reset
        #1000;
        reset_n = 1;
        $display("[%t] Reset released.", $time);

        // Theo dõi tín hiệu Trap (nếu CPU bị lỗi)
        wait(trap0 || trap1);
        $display("[%t] Trap detected! CPU Halted.", $time);
        
        #1000;
        $finish;
    end

    // Timeout phòng trường hợp code C bị treo
    initial begin
        #500000; 
        $display("Simulation timeout!");
        //$finish;
    end

endmodule

