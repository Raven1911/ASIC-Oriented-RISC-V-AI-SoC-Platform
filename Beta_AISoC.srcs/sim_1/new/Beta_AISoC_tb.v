`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 01/30/2026 05:33:25 PM
// Design Name: 
// Module Name: Beta_AISoC_tb
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



module Beta_AISoC_tb;

    //===========================================
    // Clock & Reset
    //===========================================
    reg clk_p, clk_n;     // differential clock input cho AISoC
    reg reset_n;          // active-low reset

    // UART
    reg  rx0;
    wire tx0;

    // SPI
    wire        spi0_clk;
    wire        spi0_mosi;
    reg         spi0_miso;
    wire [1:0]  spi0_ss_n;

    // I2C
    tri         i2c0_scl;
    tri         i2c0_sda;

    //port ospi0
    tri      [7:0]                  ospi0_dq_io;
    tri                             ospi0_rwds_io;

	wire                            ospi0_hclk_p;  // For 3V RAMs, just use the single-ended (positive) clock
	// wire                            ospi0_hclk_n;
	wire                            ospi0_cs_n;

    //GPIO  
    wire    [7:0]   gpio;

    // Trap outputs
    wire trap0;
    wire trap1;

    //===========================================
    // Pull-up cho I2C bus
    //===========================================
    pullup(i2c0_scl);
    pullup(i2c0_sda);
    

    

    //===========================================
    // Instantiate Top-level SoC
    //===========================================
    Beta_AISoC uut (
        .clk_p(clk_p),
        .clk_n(clk_n),
        .reset_n(reset_n),
        .trap0(trap0),
        .trap1(trap1),

        // UART
        .rx0(rx0),
        .tx0(tx0),

        // SPI
        .spi0_clk(spi0_clk),
        .spi0_mosi(spi0_mosi),
        .spi0_miso(spi0_miso),
        .spi0_ss_n(spi0_ss_n),      

        // I2C
        .i2c0_scl(i2c0_scl),
        .i2c0_sda(i2c0_sda),
        .ospi0_dq_io(ospi0_dq_io),
        .ospi0_rwds_io(ospi0_rwds_io),
        .ospi0_hclk_p(ospi0_hclk_p),
        // .ospi0_hclk_n(ospi0_hclk_n),
        .ospi0_cs_n(ospi0_cs_n),
        .gpio_io(gpio)
    );

    //===========================================
    // Clock generation (simulate differential clock)
    //===========================================
    initial begin
        clk_p = 0;
        clk_n = 1;
        forever begin
            #2.5 clk_p = ~clk_p;  // 200 MHz
            clk_n = ~clk_p;       // opposite phase
        end
    end

    //===========================================
    // Reset and Stimulus
    //===========================================
    initial begin
        // Initial state
        reset_n   = 0;
        rx0       = 1;   // idle line for UART
        spi0_miso = 1;

        // Apply reset
        #10000;
        reset_n = 1;

        // Run for a while
        #100000;

        $display("Simulation finished at time %t", $time);
        $finish;
    end

endmodule
