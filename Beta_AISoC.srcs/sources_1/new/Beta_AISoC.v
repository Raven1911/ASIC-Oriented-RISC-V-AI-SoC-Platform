`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 01/30/2026 05:22:24 PM
// Design Name: 
// Module Name: Beta_AISoC
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

module Beta_AISoC#(
    // config axi interconnect
    // Transaction configuration
    parameter ADDR_WIDTH = 32,          // Address width
    parameter DATA_WIDTH = 32,          // Data width
    parameter TRANS_W_STRB_W =  4,       // width strobe
    parameter TRANS_WR_RESP_W = 2,       // width response
    parameter TRANS_PROT      = 3,
    parameter QUANTUM_TIME = 16,

    // ========================================================
    // ACCEL PORT CONFIGURATION (DMAC & AXIS)
    // ========================================================
    parameter ADDR_WIDTH_DMAC       = 24,
    parameter BURST_WIDTH           = 10,
    parameter DATA_WIDTH_BYTE       = 1,           // 1: 8bit, 2: 16bit, 4: 32bit, 8: 64bit

    // Interconnect configuration
    parameter NUM_MASTERS = 1,    // Number of masters (only config parameter of fifo, not config port of master)
    parameter NUM_SLAVES  = 15,    // Number of slaves
    parameter [NUM_MASTERS*NUM_MASTERS-1:0] ID_MASTERS_MAPS = {
        // // Master 15: bit 15 = 1, others = 0
        // { 1'b1, {(NUM_MASTERS-1){1'b0}} },
        // // Master 14: bit 14 = 1, others = 0
        // { {(NUM_MASTERS-15){1'b0}}, 1'b1, {14{1'b0}} },
        // // Master 13: bit 13 = 1, others = 0
        // { {(NUM_MASTERS-14){1'b0}}, 1'b1, {13{1'b0}} },
        // // Master 12: bit 12 = 1, others = 0
        // { {(NUM_MASTERS-13){1'b0}}, 1'b1, {12{1'b0}} },
        // // Master 11: bit 11 = 1, others = 0
        // { {(NUM_MASTERS-12){1'b0}}, 1'b1, {11{1'b0}} },
        // // Master 10: bit 10 = 1, others = 0
        // { {(NUM_MASTERS-11){1'b0}}, 1'b1, {10{1'b0}} },
        // // Master 9: bit 9 = 1, others = 0
        // { {(NUM_MASTERS-10){1'b0}}, 1'b1, {9{1'b0}} },
        // // Master 8: bit 8 = 1, others = 0
        // { {(NUM_MASTERS-9){1'b0}}, 1'b1, {8{1'b0}} },
        // // Master 7: bit 7 = 1, others = 0
        // { {(NUM_MASTERS-8){1'b0}}, 1'b1, {7{1'b0}} },
        // // Master 6: bit 6 = 1, others = 0
        // { {(NUM_MASTERS-7){1'b0}}, 1'b1, {6{1'b0}} },
        // // Master 5: bit 5 = 1, others = 0
        // { {(NUM_MASTERS-6){1'b0}}, 1'b1, {5{1'b0}} },
        // // Master 4: bit 4 = 1, others = 0
        // { {(NUM_MASTERS-5){1'b0}}, 1'b1, {4{1'b0}} },
        // // Master 3: bit 3 = 1, others = 0
        // { {(NUM_MASTERS-4){1'b0}}, 1'b1, {3{1'b0}} },
        // // Master 2: bit 2 = 1, others = 0
        // { {(NUM_MASTERS-3){1'b0}}, 1'b1, {2{1'b0}} },
        // // Master 1: bit 1 = 1, others = 0
        // { {(NUM_MASTERS-2){1'b0}}, 1'b1, {1{1'b0}} },

        { 1'b1, {(NUM_MASTERS-1){1'b0}} },
        // Master 0: bit 0 = 1, others = 0
        { {(NUM_MASTERS-1){1'b0}}, 1'b1 }
    },
    parameter [((ADDR_WIDTH*2)*NUM_SLAVES)-1:0] ADDR_MAP_SLAVES = { //{addr start, addr end}      
        // {32'hF000_0000, 32'hFFFF_FFFF},     // slave 15
        // {32'hE000_0000, 32'hEFFF_FFFF},     // slave 14       
        // {32'hD000_0000, 32'hDFFF_FFFF},     // slave 13
        // {32'hC000_0000, 32'hCFFF_FFFF},     // slave 12
        // {32'hB000_0000, 32'hBFFF_FFFF},     // slave 11
        // {32'hA000_0000, 32'hAFFF_FFFF},     // slave 10
        // {32'h0900_0000, 32'h09FF_FFFF},     // slave 9


        // Peripherals
        //cnn accelerator
        {32'h0200_9000, 32'h0200_90FF},     // slave 14
        //video streaming
        {32'h0200_8000, 32'h0200_8FFF},     // slave 13
        //GPIO
        {32'h0200_7000, 32'h0200_7FFF},     // slave 12
        //timer0
        {32'h0200_6000, 32'h0200_6FFF},     // slave 11
        //ospi0, ospi1
        {32'h0200_5100, 32'h0200_51FF},     // slave 10
        {32'h0200_5000, 32'h0200_50FF},     // slave 9
        //i2c0, i2c1
        {32'h0200_4100, 32'h0200_41FF},     // slave 8
        {32'h0200_4000, 32'h0200_40FF},     // slave 7
        //spi0, spi1
        {32'h0200_3100, 32'h0200_31FF},     // slave 6
        {32'h0200_3000, 32'h0200_30FF},     // slave 5
        //uart0, uart1
        {32'h0200_2100, 32'h0200_21FF},     // slave 4         
        {32'h0200_2000, 32'h0200_20FF},     // slave 3
        //Mem
        {32'h0110_0000, 32'h0111_0000},     // slave 2
        {32'h0100_0000, 32'h0101_0000},     // slave 1
        {32'h0000_0000, 32'h0001_0000}      // slave 0
    },

    //config cpu
    parameter [ 0:0] ENABLE_COUNTERS = 1,
	parameter [ 0:0] ENABLE_COUNTERS64 = 1,
	parameter [ 0:0] ENABLE_REGS_16_31 = 1,
	parameter [ 0:0] ENABLE_REGS_DUALPORT = 1,
	parameter [ 0:0] TWO_STAGE_SHIFT = 1,
	parameter [ 0:0] BARREL_SHIFTER = 0,
	parameter [ 0:0] TWO_CYCLE_COMPARE = 0,
	parameter [ 0:0] TWO_CYCLE_ALU = 0,
	parameter [ 0:0] COMPRESSED_ISA = 0,
	parameter [ 0:0] CATCH_MISALIGN = 1,
	parameter [ 0:0] CATCH_ILLINSN = 1,
	parameter [ 0:0] ENABLE_PCPI = 0,
	parameter [ 0:0] ENABLE_MUL = 1,
	parameter [ 0:0] ENABLE_FAST_MUL = 0,
	parameter [ 0:0] ENABLE_DIV = 1,
	parameter [ 0:0] ENABLE_IRQ = 1,
	parameter [ 0:0] ENABLE_IRQ_QREGS = 1,
	parameter [ 0:0] ENABLE_IRQ_TIMER = 1,
	parameter [ 0:0] ENABLE_TRACE = 0,
	parameter [ 0:0] REGS_INIT_ZERO = 1,
	parameter [31:0] MASKED_IRQ = 32'h 0000_0000,
	parameter [31:0] LATCHED_IRQ = 32'h ffff_ffff,
	parameter [31:0] PROGADDR_RESET = 32'h 0100_0000,
	parameter [31:0] PROGADDR_IRQ = 32'h 0110_0010,
	parameter [31:0] STACKADDR = 32'h 0001_0000,

    parameter [31:0] LATCHED_IRQ1 = 32'h ffff_ffff,
	parameter [31:0] PROGADDR_RESET1 = 32'h 0400_0000,
	parameter [31:0] PROGADDR_IRQ1 = 32'h 0000_0010,
	parameter [31:0] STACKADDR1 = 32'h 0300_4000,


    //config imem and dmem
    parameter B_MEM_SIZE =  65536, // 64KB  ROM
    parameter D_MEM_SIZE =  65536, //65536, // 124KB  SRAM 131072
    parameter I_MEM_SIZE =  65536, //65536, // 124KB  FLASH

    //config spi
    parameter NSlave = 1
)(
    // input   clk,
    input   clk_p,
    input   clk_n,
    input   resetn,
    // input   clk_wizard, // debug
    // input   reset_n,// debug

    output  trap0,
    output  trap1,

    //interrupt port
    // input       [31:0]                  irq,
    // output      [31:0]                  eoi, //End of Interrupt

    //port uart0
    input  wire                         uart0_rx,
    output wire                         uart0_tx,
    //port uart1
    // input  wire                         uart1_rx,
    // output wire                         uart1_tx,

    //port spi0
    output                              spi0_clk,
    output                              spi0_mosi,
    input                               spi0_miso,
    output      [NSlave-1:0]            spi0_ss_n,

    //port spi1
    // output                              spi1_clk,
    // output                              spi1_mosi,
    // input                               spi1_miso,
    // output      [NSlave-1:0]            spi1_ss_n,

    //port i2c0
    output tri                          i2c0_scl,
    inout  tri                          i2c0_sda,

    //port i2c1
    // output tri                          i2c1_scl,
    // inout  tri                          i2c1_sda,

    // //port ospi0
    // inout       [7:0]                   ospi0_dq_io,
    // inout                               ospi0_rwds_io,
	// output                              ospi0_hclk_p,  // For 3V RAMs, just use the single-ended (positive) clock
	// // output                              ospi0_hclk_n,
	// output                              ospi0_cs_n,
    // output                              ospi0_resetn,

    // //port ospi1
    // inout       [7:0]                   ospi1_dq_io,
    // inout                               ospi1_rwds_io,
	// output                              ospi1_hclk_p,  // For 3V RAMs, just use the single-ended (positive) clock
	// // output                              ospi1_hclk_n,
	// output                              ospi1_cs_n,
    // output                              ospi1_resetn,

    //port hyperram0
    inout       [7:0]                   hyperram0_dq_io,
    inout                               hyperram0_rwds_io,
	output                              hyperram0_hclk_p,  // For 3V RAMs, just use the single-ended (positive) clock
	// output                              hyperram0_hclk_n,
	output                              hyperram0_cs_n,
    output                              hyperram0_resetn,

    //port hyperram1
    inout       [7:0]                   hyperram1_dq_io,
    inout                               hyperram1_rwds_io,
	output                              hyperram1_hclk_p,  // For 3V RAMs, just use the single-ended (positive) clock
	// output                              hyperram1_hclk_n,
	output                              hyperram1_cs_n,
    output                              hyperram1_resetn,

    // GPIO port
    inout       [7:0]                   gpio_io,

    // Camera Interface
    input                               cam_pclk_i,
    input       [7:0]                   cam_half_pixel_i,
    input                               cam_href,
    input                               cam_vsync,
    output                              cam_xclk_o,

    // HDMI Interface
    output                              HDMI_TX_HS,
    output                              HDMI_TX_VS,
    output                              HDMI_TX_DE,
    output                              HDMI_TX_CLK,
    output      [23:0]                  HDMI_TX_D

    );
    

    // AXI signals from picorv32_axi
    ////////MASTER0////////////////////////
    wire                        cpu0_awvalid;    
    wire                        cpu0_awready;
    wire [ADDR_WIDTH-1:0]       cpu0_awaddr;
    wire [TRANS_PROT-1:0]       cpu0_awprot;
    wire                        cpu0_wvalid;     
    wire                        cpu0_wready;
    wire [DATA_WIDTH-1:0]       cpu0_wdata;
    wire [TRANS_W_STRB_W-1:0]   cpu0_wstrb;
    wire                        cpu0_bvalid;     
    wire                        cpu0_bready;
    wire [TRANS_WR_RESP_W-1:0]  cpu0_bresp;
    wire                        cpu0_arvalid;    
    wire                        cpu0_arready;
    wire [ADDR_WIDTH-1:0]       cpu0_araddr;
    wire [TRANS_PROT-1:0]       cpu0_arprot;
    wire                        cpu0_rvalid;     
    wire                        cpu0_rready;
    wire [DATA_WIDTH-1:0]       cpu0_rdata;
    wire [TRANS_WR_RESP_W-1:0]  cpu0_rresp;
    wire [31:0]                 cpu0_irq;
    wire [31:0]                 cpu0_eoi;
    wire                        cnn_irq_accel_done;
    reg                         cnn_irq_accel_done_d;
    wire                        cnn_irq_accel_done_irq;

    localparam integer IRQ_CNN_ACCEL_DONE = 3;

    ////////MASTER1////////////////////////
    wire                        cpu1_awvalid;    
    wire                        cpu1_awready;
    wire [ADDR_WIDTH-1:0]       cpu1_awaddr;
    wire [TRANS_PROT-1:0]       cpu1_awprot;
    wire                        cpu1_wvalid;     
    wire                        cpu1_wready;
    wire [DATA_WIDTH-1:0]       cpu1_wdata;
    wire [TRANS_W_STRB_W-1:0]   cpu1_wstrb;
    wire                        cpu1_bvalid;     
    wire                        cpu1_bready;
    wire [TRANS_WR_RESP_W-1:0]  cpu1_bresp;
    wire                        cpu1_arvalid;    
    wire                        cpu1_arready;
    wire [ADDR_WIDTH-1:0]       cpu1_araddr;
    wire [TRANS_PROT-1:0]       cpu1_arprot;
    wire                        cpu1_rvalid;     
    wire                        cpu1_rready;
    wire [DATA_WIDTH-1:0]       cpu1_rdata;
    wire [TRANS_WR_RESP_W-1:0]  cpu1_rresp;



    // AXI signals to dmem_axi_lite//////////////////slave 0/////////////////////
    wire                        dmem_awvalid;   
    wire                        dmem_awready;
    wire [ADDR_WIDTH-1:0]       dmem_awaddr;
    wire [TRANS_PROT-1:0]       dmem_awprot;
    wire                        dmem_wvalid;    
    wire                        dmem_wready;
    wire [DATA_WIDTH-1:0]       dmem_wdata;
    wire [TRANS_W_STRB_W-1:0]   dmem_wstrb;
    wire                        dmem_bvalid;    
    wire                        dmem_bready;
    wire [TRANS_WR_RESP_W-1:0]  dmem_bresp;
    
    wire                        dmem_arvalid;   
    wire                        dmem_arready;
    wire [ADDR_WIDTH-1:0]       dmem_araddr;
    wire [TRANS_PROT-1:0]       dmem_arprot;
    wire                        dmem_rvalid;    
    wire                        dmem_rready;
    wire [DATA_WIDTH-1:0]       dmem_rdata;
    wire [TRANS_WR_RESP_W-1:0]  dmem_rresp;

    // // AXI signals to imem_axi_lite//////////////////slave 1/////////////////////
    wire                        bmem_awvalid;   
    wire                        bmem_awready;
    wire [ADDR_WIDTH-1:0]       bmem_awaddr;
    wire [TRANS_PROT-1:0]       bmem_awprot;
    wire                        bmem_wvalid;    
    wire                        bmem_wready;
    wire [TRANS_WR_RESP_W-1:0]  bmem_bresp;
    wire [DATA_WIDTH-1:0]       bmem_wdata;
    wire [TRANS_W_STRB_W-1:0]   bmem_wstrb;
    wire                        bmem_bvalid;    
    wire                        bmem_bready;
    wire                        bmem_arvalid;   
    wire                        bmem_arready;
    wire [ADDR_WIDTH-1:0]       bmem_araddr;
    wire [TRANS_PROT-1:0]       bmem_arprot;
    wire                        bmem_rvalid;    
    wire                        bmem_rready;
    wire [DATA_WIDTH-1:0]       bmem_rdata;
    wire [TRANS_WR_RESP_W-1:0]  bmem_rresp;

    // AXI signals to imem_axi_lite//////////////////slave 2/////////////////////
    wire                        imem_awvalid;   
    wire                        imem_awready;
    wire [ADDR_WIDTH-1:0]       imem_awaddr;
    wire [TRANS_PROT-1:0]       imem_awprot;
    wire                        imem_wvalid;    
    wire                        imem_wready;
    wire [TRANS_WR_RESP_W-1:0]  imem_bresp;
    wire [DATA_WIDTH-1:0]       imem_wdata;
    wire [TRANS_W_STRB_W-1:0]   imem_wstrb;
    wire                        imem_bvalid;    
    wire                        imem_bready;
    wire                        imem_arvalid;   
    wire                        imem_arready;
    wire [ADDR_WIDTH-1:0]       imem_araddr;
    wire [TRANS_PROT-1:0]       imem_arprot;
    wire                        imem_rvalid;    
    wire                        imem_rready;
    wire [DATA_WIDTH-1:0]       imem_rdata;
    wire [TRANS_WR_RESP_W-1:0]  imem_rresp;

    // AXI signals to uart0_axi_lite//////////////////slave 3/////////////////////
    wire                        uart0_awvalid;  
    wire                        uart0_awready;
    wire [ADDR_WIDTH-1:0]       uart0_awaddr;
    wire [TRANS_PROT-1:0]       uart0_awprot;
    wire                        uart0_wvalid;   
    wire                        uart0_wready;
    wire [TRANS_WR_RESP_W-1:0]  uart0_bresp;
    wire [DATA_WIDTH-1:0]       uart0_wdata;
    wire [TRANS_W_STRB_W-1:0]   uart0_wstrb;
    wire                        uart0_bvalid;   
    wire                        uart0_bready;
    wire                        uart0_arvalid;  
    wire                        uart0_arready;
    wire [ADDR_WIDTH-1:0]       uart0_araddr;
    wire [TRANS_PROT-1:0]       uart0_arprot;
    wire                        uart0_rvalid;   
    wire                        uart0_rready;
    wire [DATA_WIDTH-1:0]       uart0_rdata;
    wire [TRANS_WR_RESP_W-1:0]  uart0_rresp;

    // AXI signals to uart0_axi_lite//////////////////slave 4/////////////////////
    wire                        uart1_awvalid;  
    wire                        uart1_awready;
    wire [ADDR_WIDTH-1:0]       uart1_awaddr;
    wire [TRANS_PROT-1:0]       uart1_awprot;
    wire                        uart1_wvalid;   
    wire                        uart1_wready;
    wire [TRANS_WR_RESP_W-1:0]  uart1_bresp;
    wire [DATA_WIDTH-1:0]       uart1_wdata;
    wire [TRANS_W_STRB_W-1:0]   uart1_wstrb;
    wire                        uart1_bvalid;   
    wire                        uart1_bready;
    wire                        uart1_arvalid;  
    wire                        uart1_arready;
    wire [ADDR_WIDTH-1:0]       uart1_araddr;
    wire [TRANS_PROT-1:0]       uart1_arprot;
    wire                        uart1_rvalid;   
    wire                        uart1_rready;
    wire [DATA_WIDTH-1:0]       uart1_rdata;
    wire [TRANS_WR_RESP_W-1:0]  uart1_rresp;


    // AXI signals to spi0_axi_lite//////////////////slave 5/////////////////////
    wire                        spi0_awvalid;   
    wire                        spi0_awready;
    wire [ADDR_WIDTH-1:0]       spi0_awaddr;
    wire [TRANS_PROT-1:0]       spi0_awprot;
    wire                        spi0_wvalid;    
    wire                        spi0_wready;
    wire [TRANS_WR_RESP_W-1:0]  spi0_bresp;
    wire [DATA_WIDTH-1:0]       spi0_wdata;
    wire [TRANS_W_STRB_W-1:0]   spi0_wstrb;
    wire                        spi0_bvalid;    
    wire                        spi0_bready;
    wire                        spi0_arvalid;   
    wire                        spi0_arready;
    wire [ADDR_WIDTH-1:0]       spi0_araddr;
    wire [TRANS_PROT-1:0]       spi0_arprot;
    wire                        spi0_rvalid;    
    wire                        spi0_rready;
    wire [DATA_WIDTH-1:0]       spi0_rdata;
    wire [TRANS_WR_RESP_W-1:0]  spi0_rresp;

    // AXI signals to spi0_axi_lite//////////////////slave 6/////////////////////
    wire                        spi1_awvalid;   
    wire                        spi1_awready;
    wire [ADDR_WIDTH-1:0]       spi1_awaddr;
    wire [TRANS_PROT-1:0]       spi1_awprot;
    wire                        spi1_wvalid;    
    wire                        spi1_wready;
    wire [TRANS_WR_RESP_W-1:0]  spi1_bresp;
    wire [DATA_WIDTH-1:0]       spi1_wdata;
    wire [TRANS_W_STRB_W-1:0]   spi1_wstrb;
    wire                        spi1_bvalid;    
    wire                        spi1_bready;
    wire                        spi1_arvalid;   
    wire                        spi1_arready;
    wire [ADDR_WIDTH-1:0]       spi1_araddr;
    wire [TRANS_PROT-1:0]       spi1_arprot;
    wire                        spi1_rvalid;    
    wire                        spi1_rready;
    wire [DATA_WIDTH-1:0]       spi1_rdata;
    wire [TRANS_WR_RESP_W-1:0]  spi1_rresp;

    // AXI signals to i2c0_axi_lite//////////////////slave 7/////////////////////
    wire                        i2c0_awvalid;   
    wire                        i2c0_awready;
    wire [ADDR_WIDTH-1:0]       i2c0_awaddr;
    wire [TRANS_PROT-1:0]       i2c0_awprot;
    wire                        i2c0_wvalid;    
    wire                        i2c0_wready;
    wire [TRANS_WR_RESP_W-1:0]  i2c0_bresp;
    wire [DATA_WIDTH-1:0]       i2c0_wdata;
    wire [TRANS_W_STRB_W-1:0]   i2c0_wstrb;
    wire                        i2c0_bvalid;    
    wire                        i2c0_bready;
    wire                        i2c0_arvalid;   
    wire                        i2c0_arready;
    wire [ADDR_WIDTH-1:0]       i2c0_araddr;
    wire [TRANS_PROT-1:0]       i2c0_arprot;
    wire                        i2c0_rvalid;    
    wire                        i2c0_rready;
    wire [DATA_WIDTH-1:0]       i2c0_rdata;
    wire [TRANS_WR_RESP_W-1:0]  i2c0_rresp;

    // AXI signals to i2c0_axi_lite//////////////////slave 8/////////////////////
    wire                        i2c1_awvalid;   
    wire                        i2c1_awready;
    wire [ADDR_WIDTH-1:0]       i2c1_awaddr;
    wire [TRANS_PROT-1:0]       i2c1_awprot;
    wire                        i2c1_wvalid;    
    wire                        i2c1_wready;
    wire [TRANS_WR_RESP_W-1:0]  i2c1_bresp;
    wire [DATA_WIDTH-1:0]       i2c1_wdata;
    wire [TRANS_W_STRB_W-1:0]   i2c1_wstrb;
    wire                        i2c1_bvalid;    
    wire                        i2c1_bready;
    wire                        i2c1_arvalid;   
    wire                        i2c1_arready;
    wire [ADDR_WIDTH-1:0]       i2c1_araddr;
    wire [TRANS_PROT-1:0]       i2c1_arprot;
    wire                        i2c1_rvalid;    
    wire                        i2c1_rready;
    wire [DATA_WIDTH-1:0]       i2c1_rdata;
    wire [TRANS_WR_RESP_W-1:0]  i2c1_rresp;

    // // AXI signals to ospi0_axi_lite//////////////////slave 9/////////////////////
    // wire                        ospi0_awvalid;   
    // wire                        ospi0_awready;
    // wire [ADDR_WIDTH-1:0]       ospi0_awaddr;
    // wire [TRANS_PROT-1:0]       ospi0_awprot;
    // wire                        ospi0_wvalid;    
    // wire                        ospi0_wready;
    // wire [TRANS_WR_RESP_W-1:0]  ospi0_bresp;
    // wire [DATA_WIDTH-1:0]       ospi0_wdata;
    // wire [TRANS_W_STRB_W-1:0]   ospi0_wstrb;
    // wire                        ospi0_bvalid;    
    // wire                        ospi0_bready;
    // wire                        ospi0_arvalid;   
    // wire                        ospi0_arready;
    // wire [ADDR_WIDTH-1:0]       ospi0_araddr;
    // wire [TRANS_PROT-1:0]       ospi0_arprot;
    // wire                        ospi0_rvalid;    
    // wire                        ospi0_rready;
    // wire [DATA_WIDTH-1:0]       ospi0_rdata;
    // wire [TRANS_WR_RESP_W-1:0]  ospi0_rresp;
    // // ==========================================
    // // Wires cho ACCEL COMMAND PORT (ospi0)
    // // ==========================================
    // wire                           ospi0_AWVALID_i;
    // wire                           ospi0_AWREADY_o;
    // wire   [ADDR_WIDTH_DMAC-1:0]   ospi0_AWADDR_i;
    // wire   [BURST_WIDTH-1:0]       ospi0_AWBURST_i;

    // wire                           ospi0_ARVALID_i;
    // wire                           ospi0_ARREADY_o;
    // wire   [ADDR_WIDTH_DMAC-1:0]   ospi0_ARADDR_i;
    // wire   [BURST_WIDTH-1:0]       ospi0_ARBURST_i;

    // // ==========================================
    // // Wires cho ACCEL DATA PORT (AXI-STREAM) (ospi0)
    // // ==========================================
    // // --- Master Port ---
    // wire                           ospi0_m_tvalid_o;
    // wire                           ospi0_m_tready_i;
    // wire   [DATA_WIDTH_BYTE*8-1:0] ospi0_m_tdata_o;
    // wire   [DATA_WIDTH_BYTE-1:0]   ospi0_m_tstrb_o;
    // wire   [DATA_WIDTH_BYTE-1:0]   ospi0_m_tkeep_o;
    // wire                           ospi0_m_tlast_o;

    // // --- Slave Port ---
    // wire                           ospi0_s_tvalid_i;
    // wire                           ospi0_s_tready_o;
    // wire   [DATA_WIDTH_BYTE*8-1:0] ospi0_s_tdata_i;
    // wire   [DATA_WIDTH_BYTE-1:0]   ospi0_s_tstrb_i;
    // wire   [DATA_WIDTH_BYTE-1:0]   ospi0_s_tkeep_i;
    // wire                           ospi0_s_tlast_i;


    // AXI signals to hyperram0_axi_lite//////////////////slave 9/////////////////////
    wire                        hyperram0_awvalid;
    wire                        hyperram0_awready;
    wire [ADDR_WIDTH-1:0]       hyperram0_awaddr;
    wire [TRANS_PROT-1:0]       hyperram0_awprot;
    wire                        hyperram0_wvalid;
    wire                        hyperram0_wready;
    wire [TRANS_WR_RESP_W-1:0]  hyperram0_bresp;
    wire [DATA_WIDTH-1:0]       hyperram0_wdata;
    wire [TRANS_W_STRB_W-1:0]   hyperram0_wstrb;

    wire                        hyperram0_bvalid;
    wire                        hyperram0_bready;
    
    wire                        hyperram0_arvalid;
    wire                        hyperram0_arready;
    wire [ADDR_WIDTH-1:0]       hyperram0_araddr;
    wire [TRANS_PROT-1:0]       hyperram0_arprot;

    wire                        hyperram0_rvalid;
    wire                        hyperram0_rready;
    wire [DATA_WIDTH-1:0]       hyperram0_rdata;
    wire [TRANS_WR_RESP_W-1:0]  hyperram0_rresp;

    // ==========================================
    // Wires cho ACCEL COMMAND PORT (hyperram0)
    // ==========================================
    wire                           hyperram0_AWVALID_i;
    wire                           hyperram0_AWREADY_o;
    wire   [ADDR_WIDTH_DMAC-1:0]   hyperram0_AWADDR_i;
    wire   [BURST_WIDTH-1:0]       hyperram0_AWBURST_i;

    wire                           hyperram0_ARVALID_i;
    wire                           hyperram0_ARREADY_o;
    wire   [ADDR_WIDTH_DMAC-1:0]   hyperram0_ARADDR_i;
    wire   [BURST_WIDTH-1:0]       hyperram0_ARBURST_i;

    // ==========================================
    // Wires cho ACCEL DATA PORT (AXI-STREAM) (hyperram0)
    // ==========================================
    // --- Master Port ---
    wire                           hyperram0_m_tvalid_o;
    wire                           hyperram0_m_tready_i;
    wire   [DATA_WIDTH_BYTE*8-1:0] hyperram0_m_tdata_o;
    wire   [DATA_WIDTH_BYTE-1:0]   hyperram0_m_tstrb_o;
    wire   [DATA_WIDTH_BYTE-1:0]   hyperram0_m_tkeep_o;
    wire                           hyperram0_m_tlast_o;

    wire                           hyperram0_m1_tvalid_o;
    wire                           hyperram0_m1_tready_i;
    wire   [DATA_WIDTH_BYTE*8-1:0] hyperram0_m1_tdata_o;
    wire   [DATA_WIDTH_BYTE-1:0]   hyperram0_m1_tstrb_o;
    wire   [DATA_WIDTH_BYTE-1:0]   hyperram0_m1_tkeep_o;
    wire                           hyperram0_m1_tlast_o;


    // --- Slave Port ---
    wire                           hyperram0_s_tvalid_i;
    wire                           hyperram0_s_tready_o;
    wire   [DATA_WIDTH_BYTE*8-1:0] hyperram0_s_tdata_i;
    wire   [DATA_WIDTH_BYTE-1:0]   hyperram0_s_tstrb_i;
    wire   [DATA_WIDTH_BYTE-1:0]   hyperram0_s_tkeep_i;
    wire                           hyperram0_s_tlast_i;

    wire   [6:0]                   cnn_bias_dma_burst;

    assign hyperram0_ARBURST_i   = {{(BURST_WIDTH-7){1'b0}}, cnn_bias_dma_burst};
    assign hyperram0_s_tvalid_i  = 1'b0;
    assign hyperram0_s_tdata_i   = {(DATA_WIDTH_BYTE*8){1'b0}};
    assign hyperram0_s_tstrb_i   = {DATA_WIDTH_BYTE{1'b0}};
    assign hyperram0_s_tkeep_i   = {DATA_WIDTH_BYTE{1'b0}};
    assign hyperram0_s_tlast_i   = 1'b0;

    // // AXI signals to ospi0_axi_lite//////////////////slave 10/////////////////////
    // wire                        ospi1_awvalid;   
    // wire                        ospi1_awready;
    // wire [ADDR_WIDTH-1:0]       ospi1_awaddr;
    // wire [TRANS_PROT-1:0]       ospi1_awprot;
    // wire                        ospi1_wvalid;    
    // wire                        ospi1_wready;
    // wire [TRANS_WR_RESP_W-1:0]  ospi1_bresp;
    // wire [DATA_WIDTH-1:0]       ospi1_wdata;
    // wire [TRANS_W_STRB_W-1:0]   ospi1_wstrb;
    // wire                        ospi1_bvalid;    
    // wire                        ospi1_bready;
    // wire                        ospi1_arvalid;   
    // wire                        ospi1_arready;
    // wire [ADDR_WIDTH-1:0]       ospi1_araddr;
    // wire [TRANS_PROT-1:0]       ospi1_arprot;
    // wire                        ospi1_rvalid;    
    // wire                        ospi1_rready;
    // wire [DATA_WIDTH-1:0]       ospi1_rdata;
    // wire [TRANS_WR_RESP_W-1:0]  ospi1_rresp;
    // // ==========================================
    // // Wires cho ACCEL COMMAND PORT (ospi1)
    // // ==========================================
    // wire                           ospi1_AWVALID_i;
    // wire                           ospi1_AWREADY_o;
    // wire   [ADDR_WIDTH_DMAC-1:0]   ospi1_AWADDR_i;
    // wire   [BURST_WIDTH-1:0]       ospi1_AWBURST_i;

    // wire                           ospi1_ARVALID_i;
    // wire                           ospi1_ARREADY_o;
    // wire   [ADDR_WIDTH_DMAC-1:0]   ospi1_ARADDR_i;
    // wire   [BURST_WIDTH-1:0]       ospi1_ARBURST_i;

    // // ==========================================
    // // Wires cho ACCEL DATA PORT (AXI-STREAM) (ospi1)
    // // ==========================================
    // // --- Master Port ---
    // wire                           ospi1_m_tvalid_o;
    // wire                           ospi1_m_tready_i;
    // wire   [DATA_WIDTH_BYTE*8-1:0] ospi1_m_tdata_o;
    // wire   [DATA_WIDTH_BYTE-1:0]   ospi1_m_tstrb_o;
    // wire   [DATA_WIDTH_BYTE-1:0]   ospi1_m_tkeep_o;
    // wire                           ospi1_m_tlast_o;

    // // --- Slave Port ---
    // wire                           ospi1_s_tvalid_i;
    // wire                           ospi1_s_tready_o;
    // wire   [DATA_WIDTH_BYTE*8-1:0] ospi1_s_tdata_i;
    // wire   [DATA_WIDTH_BYTE-1:0]   ospi1_s_tstrb_i;
    // wire   [DATA_WIDTH_BYTE-1:0]   ospi1_s_tkeep_i;
    // wire                           ospi1_s_tlast_i;


    // AXI signals to hyperram1_axi_lite//////////////////slave 10/////////////////////
    wire                        hyperram1_awvalid;
    wire                        hyperram1_awready;
    wire [ADDR_WIDTH-1:0]       hyperram1_awaddr;
    wire [TRANS_PROT-1:0]       hyperram1_awprot;
    wire                        hyperram1_wvalid;
    wire                        hyperram1_wready;
    wire [TRANS_WR_RESP_W-1:0]  hyperram1_bresp;
    wire [DATA_WIDTH-1:0]       hyperram1_wdata;
    wire [TRANS_W_STRB_W-1:0]   hyperram1_wstrb;

    wire                        hyperram1_bvalid;
    wire                        hyperram1_bready;
    
    wire                        hyperram1_arvalid;
    wire                        hyperram1_arready;
    wire [ADDR_WIDTH-1:0]       hyperram1_araddr;
    wire [TRANS_PROT-1:0]       hyperram1_arprot;

    wire                        hyperram1_rvalid;
    wire                        hyperram1_rready;
    wire [DATA_WIDTH-1:0]       hyperram1_rdata;
    wire [TRANS_WR_RESP_W-1:0]  hyperram1_rresp;

    // ==========================================
    // Wires cho ACCEL COMMAND PORT (hyperram1)
    // ==========================================
    wire                           hyperram1_AWVALID_i;
    wire                           hyperram1_AWREADY_o;
    wire   [ADDR_WIDTH_DMAC-1:0]   hyperram1_AWADDR_i;
    wire   [BURST_WIDTH-1:0]       hyperram1_AWBURST_i;

    wire                           hyperram1_ARVALID_i;
    wire                           hyperram1_ARREADY_o;
    wire   [ADDR_WIDTH_DMAC-1:0]   hyperram1_ARADDR_i;
    wire   [BURST_WIDTH-1:0]       hyperram1_ARBURST_i;

    // ==========================================
    // Wires cho ACCEL DATA PORT (AXI-STREAM) (hyperram1)
    // ==========================================
    // --- Master Port ---
    wire                           hyperram1_m_tvalid_o;
    wire                           hyperram1_m_tready_i;
    wire   [DATA_WIDTH_BYTE*8-1:0] hyperram1_m_tdata_o;
    wire   [DATA_WIDTH_BYTE-1:0]   hyperram1_m_tstrb_o;
    wire   [DATA_WIDTH_BYTE-1:0]   hyperram1_m_tkeep_o;
    wire                           hyperram1_m_tlast_o;

    // --- Slave Port ---
    wire                           hyperram1_s_tvalid_i;
    wire                           hyperram1_s_tready_o;
    wire   [DATA_WIDTH_BYTE*8-1:0] hyperram1_s_tdata_i;
    wire   [DATA_WIDTH_BYTE-1:0]   hyperram1_s_tstrb_i;
    wire   [DATA_WIDTH_BYTE-1:0]   hyperram1_s_tkeep_i;
    wire                           hyperram1_s_tlast_i;

    wire                           cnn_ifbuf_dma_rdycfg;
    wire                           cnn_ifbuf_dma_vld;
    wire   [DATA_WIDTH_BYTE*8-1:0] cnn_ifbuf_dma_data;
    wire                           cnn_ifbuf_dma_tlast;
    wire                           cnn_ifbuf_dma_vldcfg;
    wire   [7:0]                   cnn_ifbuf_dma_burst;
    wire   [ADDR_WIDTH_DMAC-1:0]   cnn_ifbuf_dma_baddr;
    wire                           cnn_ifbuf_dma_rdy;
    wire   [7:0]                   cnn_ofbuf_dma_burst;

    assign hyperram1_AWBURST_i   = {{(BURST_WIDTH-8){1'b0}}, cnn_ofbuf_dma_burst};
    assign hyperram1_s_tstrb_i   = {DATA_WIDTH_BYTE{1'b1}};
    assign hyperram1_s_tkeep_i   = {DATA_WIDTH_BYTE{1'b1}};

    // AXI signals to timer0_axi_lite//////////////////slave 11/////////////////////
    wire                        timer0_awvalid;   
    wire                        timer0_awready;
    wire [ADDR_WIDTH-1:0]       timer0_awaddr;
    wire [TRANS_PROT-1:0]       timer0_awprot;
    wire                        timer0_wvalid;    
    wire                        timer0_wready;
    wire [TRANS_WR_RESP_W-1:0]  timer0_bresp;
    wire [DATA_WIDTH-1:0]       timer0_wdata;
    wire [TRANS_W_STRB_W-1:0]   timer0_wstrb;
    wire                        timer0_bvalid;    
    wire                        timer0_bready;
    wire                        timer0_arvalid;   
    wire                        timer0_arready;
    wire [ADDR_WIDTH-1:0]       timer0_araddr;
    wire [TRANS_PROT-1:0]       timer0_arprot;
    wire                        timer0_rvalid;    
    wire                        timer0_rready;
    wire [DATA_WIDTH-1:0]       timer0_rdata;
    wire [TRANS_WR_RESP_W-1:0]  timer0_rresp;

    // AXI signals to gpio_axi_lite//////////////////slave 12/////////////////////
    wire                        gpio_awvalid;   
    wire                        gpio_awready;
    wire [ADDR_WIDTH-1:0]       gpio_awaddr;
    wire [TRANS_PROT-1:0]       gpio_awprot;
    wire                        gpio_wvalid;    
    wire                        gpio_wready;
    wire [TRANS_WR_RESP_W-1:0]  gpio_bresp;
    wire [DATA_WIDTH-1:0]       gpio_wdata;
    wire [TRANS_W_STRB_W-1:0]   gpio_wstrb;
    wire                        gpio_bvalid;    
    wire                        gpio_bready;
    wire                        gpio_arvalid;   
    wire                        gpio_arready;
    wire [ADDR_WIDTH-1:0]       gpio_araddr;
    wire [TRANS_PROT-1:0]       gpio_arprot;
    wire                        gpio_rvalid;    
    wire                        gpio_rready;
    wire [DATA_WIDTH-1:0]       gpio_rdata;
    wire [TRANS_WR_RESP_W-1:0]  gpio_rresp;

    
    // AXI signals to video_streaming_axi_lite_core//////////////////slave 13/////////////////////
    wire                        video_awvalid;
    wire                        video_awready;
    wire [ADDR_WIDTH-1:0]       video_awaddr;
    wire [TRANS_PROT-1:0]       video_awprot;
    wire                        video_wvalid;
    wire                        video_wready;
    wire [TRANS_WR_RESP_W-1:0]  video_bresp;
    wire [DATA_WIDTH-1:0]       video_wdata;
    wire [TRANS_W_STRB_W-1:0]   video_wstrb;
    wire                        video_bvalid;
    wire                        video_bready;
    wire                        video_arvalid;
    wire                        video_arready;
    wire [ADDR_WIDTH-1:0]       video_araddr;
    wire [TRANS_PROT-1:0]       video_arprot;
    wire                        video_rvalid;
    wire                        video_rready;
    wire [DATA_WIDTH-1:0]       video_rdata;
    wire [TRANS_WR_RESP_W-1:0]  video_rresp;

    // Video accel ports are declared internally, not connected to top yet.
    wire                            video_grant_request_cam2accel;
    wire                            video_ARVALID_i;
    wire                            video_ARREADY_o;
    wire [ADDR_WIDTH-1:0]           video_ARADDR_i;
    wire [15:0]                     video_ARBURST_i;
    wire                            video_m_tvalid_o;
    wire                            video_m_tready_i;
    wire [DATA_WIDTH_BYTE*8-1:0]    video_m_tdata_o;
    wire [DATA_WIDTH_BYTE-1:0]      video_m_tstrb_o;
    wire [DATA_WIDTH_BYTE-1:0]      video_m_tkeep_o;
    wire                            video_m_tlast_o;
    wire                            video_m_tid_o;

    // AXI signals to cnn_axi_lite//////////////////slave 14/////////////////////
    wire                        cnn_awvalid;
    wire                        cnn_awready;
    wire [ADDR_WIDTH-1:0]       cnn_awaddr;
    wire [TRANS_PROT-1:0]       cnn_awprot;
    wire                        cnn_wvalid;
    wire                        cnn_wready;
    wire [TRANS_WR_RESP_W-1:0]  cnn_bresp;
    wire [DATA_WIDTH-1:0]       cnn_wdata;
    wire [TRANS_W_STRB_W-1:0]   cnn_wstrb;
    wire                        cnn_bvalid;
    wire                        cnn_bready;
    wire                        cnn_arvalid;
    wire                        cnn_arready;
    wire [ADDR_WIDTH-1:0]       cnn_araddr;
    wire [TRANS_PROT-1:0]       cnn_arprot;
    wire                        cnn_rvalid;
    wire                        cnn_rready;
    wire [DATA_WIDTH-1:0]       cnn_rdata;
    wire [TRANS_WR_RESP_W-1:0]  cnn_rresp;


    wire clk;
    wire clk24MHz;
    wire clk24MHz_oddr;
    wire clk25MHz;
    wire clk50MHz;
    wire locked;

    always @(posedge clk or negedge resetn) begin
        if (!resetn)
            cnn_irq_accel_done_d <= 1'b0;
        else
            cnn_irq_accel_done_d <= cnn_irq_accel_done;
    end

    assign cnn_irq_accel_done_irq = cnn_irq_accel_done & ~cnn_irq_accel_done_d;
    assign cpu0_irq = {28'd0, cnn_irq_accel_done_irq, 3'd0};

    clk_wiz_0 clk_wiz_0_uut
    (
        // Clock out ports
        .clk_out200MHz(clk),
        .clk_out24MHz(clk24MHz),
        .clk_out25MHz(clk25MHz),
        .clk_out50MHz(clk50MHz),
        // Status and control signals
        .resetn(1),
        .locked(locked),
        // Clock in ports
        .clk_in1_p(clk_p),
        .clk_in1_n(clk_n)
    );

    ODDR #(
        .DDR_CLK_EDGE("OPPOSITE_EDGE"),
        .INIT(1'b0),
        .SRTYPE("SYNC")
    ) ODDR_clk_24m_out (
        .Q  (clk24MHz_oddr),
        .C  (clk24MHz),
        .CE (1'b1),
        .D1 (1'b1),
        .D2 (1'b0),
        .R  (1'b0),
        .S  (1'b0)
    );


    // wire resetn;
    // wire reset_n_sync;
    // assign resetn = reset_n_sync & (locked);
    // // reset debouncer
    // debouncer_delayed #(.COUNTER_VALUE(1_999_999)
    // ) debounced_resetn (
    //     .clk(clk),
    //     .reset_n(1'b1),
    //     .noisy(reset_n),
        
    //     .debounced(reset_n_sync),
    //     .p_edge(),
    //     .n_edge(),
    //     .any_edge()
    // );

    // Instantiate picorv32_axi
    picorv32_axi #(
        .ENABLE_COUNTERS     (ENABLE_COUNTERS     ),
		.ENABLE_COUNTERS64   (ENABLE_COUNTERS64   ),
		.ENABLE_REGS_16_31   (ENABLE_REGS_16_31   ),
		.ENABLE_REGS_DUALPORT(ENABLE_REGS_DUALPORT),
		.TWO_STAGE_SHIFT     (TWO_STAGE_SHIFT     ),
		.BARREL_SHIFTER      (BARREL_SHIFTER      ),
		.TWO_CYCLE_COMPARE   (TWO_CYCLE_COMPARE   ),
		.TWO_CYCLE_ALU       (TWO_CYCLE_ALU       ),
		.COMPRESSED_ISA      (COMPRESSED_ISA      ),
		.CATCH_MISALIGN      (CATCH_MISALIGN      ),
		.CATCH_ILLINSN       (CATCH_ILLINSN       ),
		.ENABLE_PCPI         (ENABLE_PCPI         ),
		.ENABLE_MUL          (ENABLE_MUL          ),
		.ENABLE_FAST_MUL     (ENABLE_FAST_MUL     ),
		.ENABLE_DIV          (ENABLE_DIV          ),
		.ENABLE_IRQ          (ENABLE_IRQ          ),
		.ENABLE_IRQ_QREGS    (ENABLE_IRQ_QREGS    ),
		.ENABLE_IRQ_TIMER    (ENABLE_IRQ_TIMER    ),
		.ENABLE_TRACE        (ENABLE_TRACE        ),
		.REGS_INIT_ZERO      (REGS_INIT_ZERO      ),
		.MASKED_IRQ          (MASKED_IRQ          ),
		.LATCHED_IRQ         (LATCHED_IRQ         ),
		.PROGADDR_RESET      (PROGADDR_RESET      ),
		.PROGADDR_IRQ        (PROGADDR_IRQ        ),
		.STACKADDR           (STACKADDR           )
    ) cpu0 (
        .clk(clk),
        .resetn(resetn),
        .trap(trap0),
        .mem_axi_awvalid(cpu0_awvalid),
        .mem_axi_awready(cpu0_awready),
        .mem_axi_awaddr(cpu0_awaddr),
        .mem_axi_awprot(cpu0_awprot),
        .mem_axi_wvalid(cpu0_wvalid),
        .mem_axi_wready(cpu0_wready),
        .mem_axi_wdata(cpu0_wdata),
        .mem_axi_wstrb(cpu0_wstrb),
        .mem_axi_bvalid(cpu0_bvalid),
        .mem_axi_bready(cpu0_bready),
        .mem_axi_arvalid(cpu0_arvalid),
        .mem_axi_arready(cpu0_arready),
        .mem_axi_araddr(cpu0_araddr),
        .mem_axi_arprot(cpu0_arprot),
        .mem_axi_rvalid(cpu0_rvalid),
        .mem_axi_rready(cpu0_rready),
        .mem_axi_rdata(cpu0_rdata),
        .irq(cpu0_irq),
        .eoi(cpu0_eoi)
    );

    // picorv32_axi #(
    //     .ENABLE_COUNTERS     (ENABLE_COUNTERS     ),
	// 	.ENABLE_COUNTERS64   (ENABLE_COUNTERS64   ),
	// 	.ENABLE_REGS_16_31   (ENABLE_REGS_16_31   ),
	// 	.ENABLE_REGS_DUALPORT(ENABLE_REGS_DUALPORT),
	// 	.TWO_STAGE_SHIFT     (TWO_STAGE_SHIFT     ),
	// 	.BARREL_SHIFTER      (BARREL_SHIFTER      ),
	// 	.TWO_CYCLE_COMPARE   (TWO_CYCLE_COMPARE   ),
	// 	.TWO_CYCLE_ALU       (TWO_CYCLE_ALU       ),
	// 	.COMPRESSED_ISA      (COMPRESSED_ISA      ),
	// 	.CATCH_MISALIGN      (CATCH_MISALIGN      ),
	// 	.CATCH_ILLINSN       (CATCH_ILLINSN       ),
	// 	.ENABLE_PCPI         (ENABLE_PCPI         ),
	// 	.ENABLE_MUL          (ENABLE_MUL          ),
	// 	.ENABLE_FAST_MUL     (ENABLE_FAST_MUL     ),
	// 	.ENABLE_DIV          (ENABLE_DIV          ),
	// 	.ENABLE_IRQ          (ENABLE_IRQ          ),
	// 	.ENABLE_IRQ_QREGS    (ENABLE_IRQ_QREGS    ),
	// 	.ENABLE_IRQ_TIMER    (ENABLE_IRQ_TIMER    ),
	// 	.ENABLE_TRACE        (ENABLE_TRACE        ),
	// 	.REGS_INIT_ZERO      (REGS_INIT_ZERO      ),
	// 	.MASKED_IRQ          (MASKED_IRQ          ),
	// 	.LATCHED_IRQ         (LATCHED_IRQ         ),
	// 	.PROGADDR_RESET      (PROGADDR_RESET     ),
	// 	.PROGADDR_IRQ        (PROGADDR_IRQ        ),
	// 	.STACKADDR           (STACKADDR           )
    // ) cpu1 (
    //     .clk(clk),
    //     .resetn(resetn),
    //     .trap(trap1),
    //     .mem_axi_awvalid(cpu1_awvalid),
    //     .mem_axi_awready(cpu1_awready),
    //     .mem_axi_awaddr(cpu1_awaddr),
    //     .mem_axi_awprot(cpu1_awprot),
    //     .mem_axi_wvalid(cpu1_wvalid),
    //     .mem_axi_wready(cpu1_wready),
    //     .mem_axi_wdata(cpu1_wdata),
    //     .mem_axi_wstrb(cpu1_wstrb),
    //     .mem_axi_bvalid(cpu1_bvalid),
    //     .mem_axi_bready(cpu1_bready),
    //     .mem_axi_arvalid(cpu1_arvalid),
    //     .mem_axi_arready(cpu1_arready),
    //     .mem_axi_araddr(cpu1_araddr),
    //     .mem_axi_arprot(cpu1_arprot),
    //     .mem_axi_rvalid(cpu1_rvalid),
    //     .mem_axi_rready(cpu1_rready),
    //     .mem_axi_rdata(cpu1_rdata),
    //     .irq(32'h0), // Chưa dùng IRQ
    //     .eoi()       // Chưa dùng IRQ
    // );


    // Instantiate axi lite interconnect
    axi_lite_interconnect #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .TRANS_W_STRB_W(TRANS_W_STRB_W),
        .TRANS_WR_RESP_W(TRANS_WR_RESP_W),
        .TRANS_PROT(TRANS_PROT),
        .QUANTUM_TIME(QUANTUM_TIME),
        .NUM_MASTERS(NUM_MASTERS),
        .NUM_SLAVES(NUM_SLAVES),
        .ID_MASTERS_MAPS(ID_MASTERS_MAPS),
        .ADDR_MAP_SLAVES(ADDR_MAP_SLAVES)
    ) axi_lite_interconnect_unit (
        .m_axi_aclk_i(clk),
        .m_axi_aresetn_i(resetn),

        // Master Interface
        .m_axi_awaddr_i     ({cpu1_awaddr,  cpu0_awaddr}),
        .m_axi_awvalid_i    ({cpu1_awvalid, cpu0_awvalid}),
        .m_axi_awready_o    ({cpu1_awready, cpu0_awready}),
        // .m_axi_awprot_i({cpu1_awprot, cpu0_awprot}),
        .m_axi_awprot_i     ({(TRANS_PROT*NUM_MASTERS){1'b0}}),

        .m_axi_wdata_i      ({cpu1_wdata,   cpu0_wdata}),
        .m_axi_wstrb_i      ({cpu1_wstrb,   cpu0_wstrb}),
        .m_axi_wvalid_i     ({cpu1_wvalid,  cpu0_wvalid}),
        .m_axi_wready_o     ({cpu1_wready,  cpu0_wready}),

        .m_axi_bresp_o      ({cpu1_bresp,   cpu0_bresp}),
        .m_axi_bvalid_o     ({cpu1_bvalid,  cpu0_bvalid}),
        .m_axi_bready_i     ({cpu1_bready,  cpu0_bready}),
        
        .m_axi_araddr_i     ({cpu1_araddr,  cpu0_araddr}),
        .m_axi_arvalid_i    ({cpu1_arvalid, cpu0_arvalid}),
        .m_axi_arready_o    ({cpu1_arready, cpu0_arready}),
        // .m_axi_arprot_i({cpu1_arprot, cpu0_arprot}),
        .m_axi_arprot_i     (({(TRANS_PROT*NUM_MASTERS){1'b0}})),

        .m_axi_rdata_o      ({cpu1_rdata,   cpu0_rdata}),
        .m_axi_rresp_o      ({cpu1_rresp,   cpu0_rresp}),
        .m_axi_rvalid_o     ({cpu1_rvalid,  cpu0_rvalid}),
        .m_axi_rready_i     ({cpu1_rready,  cpu0_rready}),

        // Slave Interfaces
        .s_axi_awaddr_o     ({cnn_awaddr,     video_awaddr,     gpio_awaddr,  timer0_awaddr,  hyperram1_awaddr,   hyperram0_awaddr,   i2c1_awaddr,  i2c0_awaddr,  spi1_awaddr,  spi0_awaddr,  uart1_awaddr,   uart0_awaddr,   imem_awaddr,    bmem_awaddr,    dmem_awaddr}),
        .s_axi_awvalid_o    ({cnn_awvalid,    video_awvalid,    gpio_awvalid, timer0_awvalid, hyperram1_awvalid,  hyperram0_awvalid,  i2c1_awvalid, i2c0_awvalid, spi1_awvalid, spi0_awvalid, uart1_awvalid,  uart0_awvalid,  imem_awvalid,   bmem_awvalid,   dmem_awvalid}),
        .s_axi_awready_i    ({cnn_awready,    video_awready,    gpio_awready, timer0_awready, hyperram1_awready,  hyperram0_awready,  i2c1_awready, i2c0_awready, spi1_awready, spi0_awready, uart1_awready,  uart0_awready,  imem_awready,   bmem_awready,   dmem_awready}),
        .s_axi_awprot_o     ({cnn_awprot,     video_awprot,     gpio_awprot,  timer0_awprot,  hyperram1_awprot,   hyperram0_awprot,   i2c1_awprot,  i2c0_awprot,  spi1_awprot,  spi0_awprot,  uart1_awprot,   uart0_awprot,   imem_awprot,    bmem_awprot,    dmem_awprot}),

        .s_axi_wdata_o      ({cnn_wdata,      video_wdata,      gpio_wdata,   timer0_wdata,   hyperram1_wdata,    hyperram0_wdata,    i2c1_wdata,   i2c0_wdata,   spi1_wdata,   spi0_wdata,   uart1_wdata,    uart0_wdata,    imem_wdata,     bmem_wdata,     dmem_wdata}),
        .s_axi_wstrb_o      ({cnn_wstrb,      video_wstrb,      gpio_wstrb,   timer0_wstrb,   hyperram1_wstrb,    hyperram0_wstrb,    i2c1_wstrb,   i2c0_wstrb,   spi1_wstrb,   spi0_wstrb,   uart1_wstrb,    uart0_wstrb,    imem_wstrb,     bmem_wstrb,     dmem_wstrb}),
        .s_axi_wvalid_o     ({cnn_wvalid,     video_wvalid,     gpio_wvalid,  timer0_wvalid,  hyperram1_wvalid,   hyperram0_wvalid,   i2c1_wvalid,  i2c0_wvalid,  spi1_wvalid,  spi0_wvalid,  uart1_wvalid,   uart0_wvalid,   imem_wvalid,    bmem_wvalid,    dmem_wvalid}),
        .s_axi_wready_i     ({cnn_wready,     video_wready,     gpio_wready,  timer0_wready,  hyperram1_wready,   hyperram0_wready,   i2c1_wready,  i2c0_wready,  spi1_wready,  spi0_wready,  uart1_wready,   uart0_wready,   imem_wready,    bmem_wready,    dmem_wready}),

        .s_axi_bresp_i      ({cnn_bresp,      video_bresp,      gpio_bresp,   timer0_bresp,   hyperram1_bresp,    hyperram0_bresp,    i2c1_bresp,   i2c0_bresp,   spi1_bresp,   spi0_bresp,   uart1_bresp,    uart0_bresp,    imem_bresp,     bmem_bresp,     dmem_bresp}),
        .s_axi_bvalid_i     ({cnn_bvalid,     video_bvalid,     gpio_bvalid,  timer0_bvalid,  hyperram1_bvalid,   hyperram0_bvalid,   i2c1_bvalid,  i2c0_bvalid,  spi1_bvalid,  spi0_bvalid,  uart1_bvalid,   uart0_bvalid,   imem_bvalid,    bmem_bvalid,    dmem_bvalid}),
        .s_axi_bready_o     ({cnn_bready,     video_bready,     gpio_bready,  timer0_bready,  hyperram1_bready,   hyperram0_bready,   i2c1_bready,  i2c0_bready,  spi1_bready,  spi0_bready,  uart1_bready,   uart0_bready,   imem_bready,    bmem_bready,    dmem_bready}),

        .s_axi_araddr_o     ({cnn_araddr,     video_araddr,     gpio_araddr,  timer0_araddr,  hyperram1_araddr,   hyperram0_araddr,   i2c1_araddr,  i2c0_araddr,  spi1_araddr,  spi0_araddr,  uart1_araddr,   uart0_araddr,   imem_araddr,    bmem_araddr,    dmem_araddr}),
        .s_axi_arvalid_o    ({cnn_arvalid,    video_arvalid,    gpio_arvalid, timer0_arvalid, hyperram1_arvalid,  hyperram0_arvalid,  i2c1_arvalid, i2c0_arvalid, spi1_arvalid, spi0_arvalid, uart1_arvalid,  uart0_arvalid,  imem_arvalid,   bmem_arvalid,   dmem_arvalid}),
        .s_axi_arready_i    ({cnn_arready,    video_arready,    gpio_arready, timer0_arready, hyperram1_arready,  hyperram0_arready,  i2c1_arready, i2c0_arready, spi1_arready, spi0_arready, uart1_arready,  uart0_arready,  imem_arready,   bmem_arready,   dmem_arready}),
        .s_axi_arprot_o     ({cnn_arprot,     video_arprot,     gpio_arprot,  timer0_arprot,  hyperram1_arprot,   hyperram0_arprot,   i2c1_arprot,  i2c0_arprot,  spi1_arprot,  spi0_arprot,  uart1_arprot,   uart0_arprot,   imem_arprot,    bmem_arprot,    dmem_arprot}),

        .s_axi_rdata_i      ({cnn_rdata,      video_rdata,      gpio_rdata,   timer0_rdata,   hyperram1_rdata,    hyperram0_rdata,    i2c1_rdata,   i2c0_rdata,   spi1_rdata,   spi0_rdata,   uart1_rdata,    uart0_rdata,    imem_rdata,     bmem_rdata,     dmem_rdata}),
        .s_axi_rresp_i      ({cnn_rresp,      video_rresp,      gpio_rresp,   timer0_rresp,   hyperram1_rresp,    hyperram0_rresp,    i2c1_rresp,   i2c0_rresp,   spi1_rresp,   spi0_rresp,   uart1_rresp,    uart0_rresp,    imem_rresp,     bmem_rresp,     dmem_rresp}),
        .s_axi_rvalid_i     ({cnn_rvalid,     video_rvalid,     gpio_rvalid,  timer0_rvalid,  hyperram1_rvalid,   hyperram0_rvalid,   i2c1_rvalid,  i2c0_rvalid,  spi1_rvalid,  spi0_rvalid,  uart1_rvalid,   uart0_rvalid,   imem_rvalid,    bmem_rvalid,    dmem_rvalid}),
        .s_axi_rready_o     ({cnn_rready,     video_rready,     gpio_rready,  timer0_rready,  hyperram1_rready,   hyperram0_rready,   i2c1_rready,  i2c0_rready,  spi1_rready,  spi0_rready,  uart1_rready,   uart0_rready,   imem_rready,    bmem_rready,    dmem_rready})
    );




    // Instantiate dmem_axi_lite (Slave 0)
    mem_axi_lite #(
        .NUM_MASTERS(NUM_MASTERS),
        .MEM_SIZE(D_MEM_SIZE), // 520 kB
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .TRANS_W_STRB_W(TRANS_W_STRB_W),
        .TRANS_WR_RESP_W(TRANS_WR_RESP_W),
        .TRANS_PROT(TRANS_PROT),
        .BASE_ADDR(32'h0000_0000),
        .ENB_READMEM(0)
    ) dmem_cpu (
        .clk(clk),
        .resetn(resetn),
        .i_axi_awvalid(dmem_awvalid),
        .o_axi_awready(dmem_awready),
        .i_axi_awaddr(dmem_awaddr),
        .i_axi_awprot(dmem_awprot),

        .i_axi_wvalid(dmem_wvalid),
        .o_axi_wready(dmem_wready),
        .i_axi_wdata(dmem_wdata),
        .i_axi_wstrb(dmem_wstrb),

        .o_axi_bvalid(dmem_bvalid),
        .i_axi_bready(dmem_bready),
        .o_axi_bresp(dmem_bresp),

        .i_axi_arvalid(dmem_arvalid),
        .o_axi_arready(dmem_arready),
        .i_axi_araddr(dmem_araddr),
        .i_axi_arprot(dmem_arprot),

        .o_axi_rvalid(dmem_rvalid),
        .i_axi_rready(dmem_rready),
        .o_axi_rdata(dmem_rdata),
        .o_axi_rresp(dmem_rresp)
    );

    // Instantiate bmem_axi_lite (Slave 1, read-only)
    mem_axi_lite #(
        .NUM_MASTERS(NUM_MASTERS),
        .MEM_SIZE(B_MEM_SIZE),
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .TRANS_W_STRB_W(TRANS_W_STRB_W),
        .TRANS_WR_RESP_W(TRANS_WR_RESP_W),
        .TRANS_PROT(TRANS_PROT),
        .BASE_ADDR(PROGADDR_RESET),
        .ENB_READMEM(1)
    ) bmem_cpu (
        .clk(clk),
        .resetn(resetn),
        // Read-only (imem không cần write channels)
        .i_axi_awvalid(bmem_awvalid),
        .o_axi_awready(bmem_awready),
        .i_axi_awaddr(bmem_awaddr),
        .i_axi_awprot(bmem_awprot),

        .i_axi_wvalid(bmem_wvalid),
        .o_axi_wready(bmem_wready),
        .i_axi_wdata(bmem_wdata),
        .i_axi_wstrb(bmem_wstrb),

        .o_axi_bvalid(bmem_bvalid),
        .i_axi_bready(bmem_bready),
        .o_axi_bresp(bmem_bresp),

        .i_axi_arvalid(bmem_arvalid),
        .o_axi_arready(bmem_arready),
        .i_axi_araddr(bmem_araddr),
        .i_axi_arprot(bmem_arprot),

        .o_axi_rvalid(bmem_rvalid),
        .i_axi_rready(bmem_rready),
        .o_axi_rdata(bmem_rdata),
        .o_axi_rresp(bmem_rresp)
    );


    // Instantiate imem_axi_lite (Slave 2)
    mem_axi_lite #(
        .NUM_MASTERS(NUM_MASTERS),
        .MEM_SIZE(I_MEM_SIZE),
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .TRANS_W_STRB_W(TRANS_W_STRB_W),
        .TRANS_WR_RESP_W(TRANS_WR_RESP_W),
        .TRANS_PROT(TRANS_PROT),
        .BASE_ADDR(32'h0110_0000),
        .ENB_READMEM(0)
    ) imem_cpu (    
        .clk(clk),
        .resetn(resetn),
        .i_axi_awvalid(imem_awvalid),
        .o_axi_awready(imem_awready),
        .i_axi_awaddr(imem_awaddr),
        .i_axi_awprot(imem_awprot),

        .i_axi_wvalid(imem_wvalid),
        .o_axi_wready(imem_wready),
        .i_axi_wdata(imem_wdata),
        .i_axi_wstrb(imem_wstrb),

        .o_axi_bvalid(imem_bvalid),
        .i_axi_bready(imem_bready),
        .o_axi_bresp(imem_bresp),

        .i_axi_arvalid(imem_arvalid),
        .o_axi_arready(imem_arready),
        .i_axi_araddr(imem_araddr),
        .i_axi_arprot(imem_arprot),

        .o_axi_rvalid(imem_rvalid),
        .i_axi_rready(imem_rready),
        .o_axi_rdata(imem_rdata),
        .o_axi_rresp(imem_rresp)
    );


    // Instantiate uart0_axi_lite (Slave 3)
    uart_axi_lite #(
        .NUM_MASTERS(NUM_MASTERS),
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .FIFO_DEPTH_BIT(10),
        .ADDR_REGISTERS_0(32'h0200_2000),
        .ADDR_REGISTERS_1(32'h0200_2004),
        .ADDR_REGISTERS_2(32'h0200_2008),
        .ADDR_REGISTERS_3(32'h0200_200C),
        .ADDR_REGISTERS_4(32'h0200_2010)
    ) uart0 (
        .clk(clk),
        .resetn(resetn),
        .i_axi_awvalid(uart0_awvalid),
        .o_axi_awready(uart0_awready),
        .i_axi_awaddr(uart0_awaddr),
        .i_axi_awprot(uart0_awprot),

        .i_axi_wvalid(uart0_wvalid),
        .o_axi_wready(uart0_wready),
        .i_axi_wdata(uart0_wdata),
        .i_axi_wstrb(uart0_wstrb),
        .o_axi_bvalid(uart0_bvalid),
        .i_axi_bready(uart0_bready),
        .o_axi_bresp(uart0_bresp),

        .i_axi_arvalid(uart0_arvalid),
        .o_axi_arready(uart0_arready),
        .i_axi_araddr(uart0_araddr),
        .i_axi_arprot(uart0_arprot),

        .o_axi_rvalid(uart0_rvalid),
        .i_axi_rready(uart0_rready),
        .o_axi_rdata(uart0_rdata),
        .o_axi_rresp(uart0_rresp),

        .tx(uart0_tx),
        .rx(uart0_rx)
    );

    // Instantiate uart1_axi_lite (Slave 4)
    // uart_axi_lite #(
    //     .NUM_MASTERS(NUM_MASTERS),
    //     .ADDR_WIDTH(ADDR_WIDTH),
    //     .DATA_WIDTH(DATA_WIDTH),
    //     .FIFO_DEPTH_BIT(8),
    //     .ADDR_REGISTERS_0(32'h0200_2100),
    //     .ADDR_REGISTERS_1(32'h0200_2104),
    //     .ADDR_REGISTERS_2(32'h0200_2108),
    //     .ADDR_REGISTERS_3(32'h0200_210C),
    //     .ADDR_REGISTERS_4(32'h0200_2110)
    // ) uart1 (
    //     .clk(clk),
    //     .resetn(resetn),
    //     .i_axi_awvalid(uart1_awvalid),
    //     .o_axi_awready(uart1_awready),
    //     .i_axi_awaddr(uart1_awaddr),
    //     .i_axi_awprot(uart1_awprot),

    //     .i_axi_wvalid(uart1_wvalid),
    //     .o_axi_wready(uart1_wready),
    //     .i_axi_wdata(uart1_wdata),
    //     .i_axi_wstrb(uart1_wstrb),
    //     .o_axi_bvalid(uart1_bvalid),
    //     .i_axi_bready(uart1_bready),
    //     .o_axi_bresp(uart1_bresp),

    //     .i_axi_arvalid(uart1_arvalid),
    //     .o_axi_arready(uart1_arready),
    //     .i_axi_araddr(uart1_araddr),
    //     .i_axi_arprot(uart1_arprot),

    //     .o_axi_rvalid(uart1_rvalid),
    //     .i_axi_rready(uart1_rready),
    //     .o_axi_rdata(uart1_rdata),
    //     .o_axi_rresp(uart1_rresp),

    //     .tx(uart1_tx),
    //     .rx(uart1_rx)
    // );

    // Instantiate Spi0_axi_lite (Slave 5)
    Spi_axi_lite_core #(
        .NUM_MASTERS(NUM_MASTERS),
        .NSlave(NSlave),
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_REGISTERS_0(32'h0200_3000),
        .ADDR_REGISTERS_1(32'h0200_3004),
        .ADDR_REGISTERS_2(32'h0200_3008),
        .ADDR_REGISTERS_3(32'h0200_300C)

    ) spi0 (
        .clk(clk),
        .resetn(resetn),
        .i_axi_awvalid(spi0_awvalid),
        .o_axi_awready(spi0_awready),
        .i_axi_awaddr(spi0_awaddr),
        .i_axi_awprot(spi0_awprot),

        .i_axi_wvalid(spi0_wvalid),
        .o_axi_wready(spi0_wready),
        .i_axi_wdata(spi0_wdata),
        .i_axi_wstrb(spi0_wstrb),
        .o_axi_bvalid(spi0_bvalid),
        .i_axi_bready(spi0_bready),
        .o_axi_bresp(spi0_bresp),

        .i_axi_arvalid(spi0_arvalid),
        .o_axi_arready(spi0_arready),
        .i_axi_araddr(spi0_araddr),
        .i_axi_arprot(spi0_arprot),

        .o_axi_rvalid(spi0_rvalid),
        .i_axi_rready(spi0_rready),
        .o_axi_rdata(spi0_rdata),
        .o_axi_rresp(spi0_rresp),

        .spi_clk(spi0_clk),
        .spi_mosi(spi0_mosi),
        .spi_miso(spi0_miso),
        .spi_ss_n(spi0_ss_n)
    );

    // Instantiate Spi1_axi_lite (Slave 6)
    // Spi_axi_lite_core #(
    //     .NUM_MASTERS(NUM_MASTERS),
    //     .NSlave(NSlave),
    //     .ADDR_WIDTH(ADDR_WIDTH),
    //     .DATA_WIDTH(DATA_WIDTH),
    //     .ADDR_REGISTERS_0(32'h0200_3100),
    //     .ADDR_REGISTERS_1(32'h0200_3104),
    //     .ADDR_REGISTERS_2(32'h0200_3108),
    //     .ADDR_REGISTERS_3(32'h0200_310C)
    // ) spi1 (
    //     .clk(clk),
    //     .resetn(resetn),
    //     .i_axi_awvalid(spi1_awvalid),
    //     .o_axi_awready(spi1_awready),
    //     .i_axi_awaddr(spi1_awaddr),
    //     .i_axi_awprot(spi1_awprot),

    //     .i_axi_wvalid(spi1_wvalid),
    //     .o_axi_wready(spi1_wready),
    //     .i_axi_wdata(spi1_wdata),
    //     .i_axi_wstrb(spi1_wstrb),
    //     .o_axi_bvalid(spi1_bvalid),
    //     .i_axi_bready(spi1_bready),
    //     .o_axi_bresp(spi1_bresp),

    //     .i_axi_arvalid(spi1_arvalid),
    //     .o_axi_arready(spi1_arready),
    //     .i_axi_araddr(spi1_araddr),
    //     .i_axi_arprot(spi1_arprot),

    //     .o_axi_rvalid(spi1_rvalid),
    //     .i_axi_rready(spi1_rready),
    //     .o_axi_rdata(spi1_rdata),
    //     .o_axi_rresp(spi1_rresp),

    //     .spi_clk(spi1_clk),
    //     .spi_mosi(spi1_mosi),
    //     .spi_miso(spi1_miso),
    //     .spi_ss_n(spi1_ss_n)
    // );



    // Instantiate i2c0_axi_lite (Slave 7)
    I2C_axi_lite_core #(
        .NUM_MASTERS(NUM_MASTERS),
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .TRANS_W_STRB_W(TRANS_W_STRB_W),
        .TRANS_WR_RESP_W(TRANS_WR_RESP_W),
        .TRANS_PROT(TRANS_PROT),
        .ADDR_REGISTERS_0(32'h0200_4000),
        .ADDR_REGISTERS_1(32'h0200_4004),
        .ADDR_REGISTERS_2(32'h0200_4008)
    ) i2c0 (
        .clk(clk),
        .resetn(resetn),
        .i_axi_awvalid(i2c0_awvalid),
        .o_axi_awready(i2c0_awready),
        .i_axi_awaddr(i2c0_awaddr),
        .i_axi_awprot(i2c0_awprot),

        .i_axi_wvalid(i2c0_wvalid),
        .o_axi_wready(i2c0_wready),
        .i_axi_wdata(i2c0_wdata),
        .i_axi_wstrb(i2c0_wstrb),
        .o_axi_bvalid(i2c0_bvalid),
        .i_axi_bready(i2c0_bready),
        .o_axi_bresp(i2c0_bresp),

        .i_axi_arvalid(i2c0_arvalid),
        .o_axi_arready(i2c0_arready),
        .i_axi_araddr(i2c0_araddr),
        .i_axi_arprot(i2c0_arprot),

        .o_axi_rvalid(i2c0_rvalid),
        .i_axi_rready(i2c0_rready),
        .o_axi_rdata(i2c0_rdata),
        .o_axi_rresp(i2c0_rresp),

        .i2c_scl(i2c0_scl),
        .i2c_sda(i2c0_sda)
    );

    // Instantiate i2c1_axi_lite (Slave 8)
    // I2C_axi_lite_core #(
    //     .NUM_MASTERS(NUM_MASTERS),
    //     .ADDR_WIDTH(ADDR_WIDTH),
    //     .DATA_WIDTH(DATA_WIDTH),
    //     .TRANS_W_STRB_W(TRANS_W_STRB_W),
    //     .TRANS_WR_RESP_W(TRANS_WR_RESP_W),
    //     .TRANS_PROT(TRANS_PROT),
    //     .ADDR_REGISTERS_0(32'h0200_4100),
    //     .ADDR_REGISTERS_1(32'h0200_4104),
    //     .ADDR_REGISTERS_2(32'h0200_4108)
    // ) i2c1 (
    //     .clk(clk),
    //     .resetn(resetn),
    //     .i_axi_awvalid(i2c1_awvalid),
    //     .o_axi_awready(i2c1_awready),
    //     .i_axi_awaddr(i2c1_awaddr),
    //     .i_axi_awprot(i2c1_awprot),

    //     .i_axi_wvalid(i2c1_wvalid),
    //     .o_axi_wready(i2c1_wready),
    //     .i_axi_wdata(i2c1_wdata),
    //     .i_axi_wstrb(i2c1_wstrb),
    //     .o_axi_bvalid(i2c1_bvalid),
    //     .i_axi_bready(i2c1_bready),
    //     .o_axi_bresp(i2c1_bresp),

    //     .i_axi_arvalid(i2c1_arvalid),
    //     .o_axi_arready(i2c1_arready),
    //     .i_axi_araddr(i2c1_araddr),
    //     .i_axi_arprot(i2c1_arprot),

    //     .o_axi_rvalid(i2c1_rvalid),
    //     .i_axi_rready(i2c1_rready),
    //     .o_axi_rdata(i2c1_rdata),
    //     .o_axi_rresp(i2c1_rresp),

    //     .i2c_scl(i2c1_scl),
    //     .i2c_sda(i2c1_sda)
    // );



    // // Instantiate ospi0_axi_lite (Slave 9)
    // OSPI_axi_lite_core #(
    //     .NUM_MASTERS(NUM_MASTERS),
    //     .ADDR_WIDTH(ADDR_WIDTH),
    //     .DATA_WIDTH(DATA_WIDTH),
    //     .TRANS_W_STRB_W(TRANS_W_STRB_W),
    //     .TRANS_WR_RESP_W(TRANS_WR_RESP_W),
    //     .TRANS_PROT(TRANS_PROT),
    //     .ADDR_REGISTERS_0(32'h0200_5000),
    //     .ADDR_REGISTERS_1(32'h0200_5004),
    //     .ADDR_REGISTERS_2(32'h0200_5008),
    //     .ADDR_REGISTERS_3(32'h0200_500C),
    //     .ADDR_REGISTERS_4(32'h0200_5010),
    //     .ADDR_REGISTERS_5(32'h0200_5014)
    // ) ospi0 (
    //     // ==========================================
    //     // SYSTEM SIGNALS
    //     // ==========================================
    //     .clk            (clk),
    //     .resetn         (resetn),

    //     // ==========================================
    //     // AXI-LITE INTERFACE (CPU)
    //     // ==========================================
    //     .i_axi_awvalid  (ospi0_awvalid),
    //     .o_axi_awready  (ospi0_awready),
    //     .i_axi_awaddr   (ospi0_awaddr),
    //     .i_axi_awprot   (ospi0_awprot),

    //     .i_axi_wvalid   (ospi0_wvalid),
    //     .o_axi_wready   (ospi0_wready),
    //     .i_axi_wdata    (ospi0_wdata),
    //     .i_axi_wstrb    (ospi0_wstrb),

    //     .o_axi_bvalid   (ospi0_bvalid),
    //     .i_axi_bready   (ospi0_bready),
    //     .o_axi_bresp    (ospi0_bresp),

    //     .i_axi_arvalid  (ospi0_arvalid),
    //     .o_axi_arready  (ospi0_arready),
    //     .i_axi_araddr   (ospi0_araddr),
    //     .i_axi_arprot   (ospi0_arprot),

    //     .o_axi_rvalid   (ospi0_rvalid),
    //     .i_axi_rready   (ospi0_rready),
    //     .o_axi_rdata    (ospi0_rdata),
    //     .o_axi_rresp    (ospi0_rresp),

    //     // ==========================================
    //     // ACCEL COMMAND PORT (AXI to DMAC) - ĐÃ THÊM
    //     // ==========================================
    //     .AWVALID_i      (ospi0_AWVALID_i),
    //     .AWREADY_o      (ospi0_AWREADY_o),
    //     .AWADDR_i       (ospi0_AWADDR_i),
    //     .AWBURST_i      (ospi0_AWBURST_i),

    //     .ARVALID_i      (ospi0_ARVALID_i),
    //     .ARREADY_o      (ospi0_ARREADY_o),
    //     .ARADDR_i       (ospi0_ARADDR_i),
    //     .ARBURST_i      (ospi0_ARBURST_i),

    //     // ==========================================
    //     // ACCEL DATA PORT (AXI-STREAM) - ĐÃ THÊM
    //     // ==========================================
    //     // --- Master Port ---
    //     .m_tvalid_o     (ospi0_m_tvalid_o),
    //     .m_tready_i     (ospi0_m_tready_i),
    //     .m_tdata_o      (ospi0_m_tdata_o),
    //     .m_tstrb_o      (ospi0_m_tstrb_o),
    //     .m_tkeep_o      (ospi0_m_tkeep_o),
    //     .m_tlast_o      (ospi0_m_tlast_o),

    //     // --- Slave Port ---
    //     .s_tvalid_i     (ospi0_s_tvalid_i),
    //     .s_tready_o     (ospi0_s_tready_o),
    //     .s_tdata_i      (ospi0_s_tdata_i),
    //     .s_tstrb_i      (ospi0_s_tstrb_i),
    //     .s_tkeep_i      (ospi0_s_tkeep_i),
    //     .s_tlast_i      (ospi0_s_tlast_i),
        
    //     // ==========================================
    //     // EXTERNAL HYPERBUS PHYSICAL PINS
    //     // ==========================================
    //     .dq_io          (ospi0_dq_io),
    //     .rwds_io        (ospi0_rwds_io),
    //     .hclk_p         (ospi0_hclk_p),     // For 3V RAMs, just use the single-ended (positive) clock
    //     .hclk_n         (),                 // ospi0_hclk_n (bỏ trống nếu không dùng)
    //     .cs_n           (ospi0_cs_n)
    // );

    // assign ospi0_resetn = 'b1;

    // Instantiate hyperram0_axi_lite (Slave 9)
    hyperram_axi_lite_core #(
        .SETUP_PORTS            (0),
        .NUM_MASTERS            (NUM_MASTERS),
        .ADDR_WIDTH             (ADDR_WIDTH),
        .DATA_WIDTH             (DATA_WIDTH),
        .TRANS_W_STRB_W         (TRANS_W_STRB_W),
        .TRANS_WR_RESP_W        (TRANS_WR_RESP_W),
        .TRANS_PROT             (TRANS_PROT),
        .ADDR_WIDTH_DMAC        (ADDR_WIDTH_DMAC),
        .BURST_WIDTH            (BURST_WIDTH),
        .DATA_WIDTH_BYTE        (DATA_WIDTH_BYTE),
        .MODE_2READ_ENB         (1),
        .SHMOOD_SELECT          (0),  // 0: FMC0 , 1: FMC1
        .SIM_ENB                (0),
        .ADDR_REGISTERS_0(32'h0200_5000),
        .ADDR_REGISTERS_1(32'h0200_5004),
        .ADDR_REGISTERS_2(32'h0200_5008),
        .ADDR_REGISTERS_3(32'h0200_500C),
        .ADDR_REGISTERS_4(32'h0200_5010),
        .ADDR_REGISTERS_5(32'h0200_5014)
    ) hyperram0 (
        // ==========================================
        // SYSTEM SIGNALS
        // ==========================================
        .clk            (clk),
        .resetn         (resetn),

        // ==========================================
        // AXI-LITE INTERFACE (CPU)
        // ==========================================
        .i_axi_awvalid  (hyperram0_awvalid),
        .o_axi_awready  (hyperram0_awready),
        .i_axi_awaddr   (hyperram0_awaddr),
        .i_axi_awprot   (hyperram0_awprot),

        .i_axi_wvalid   (hyperram0_wvalid),
        .o_axi_wready   (hyperram0_wready),
        .i_axi_wdata    (hyperram0_wdata),
        .i_axi_wstrb    (hyperram0_wstrb),

        .o_axi_bvalid   (hyperram0_bvalid),
        .i_axi_bready   (hyperram0_bready),
        .o_axi_bresp    (hyperram0_bresp),

        .i_axi_arvalid  (hyperram0_arvalid),
        .o_axi_arready  (hyperram0_arready),
        .i_axi_araddr   (hyperram0_araddr),
        .i_axi_arprot   (hyperram0_arprot),

        .o_axi_rvalid   (hyperram0_rvalid),
        .i_axi_rready   (hyperram0_rready),
        .o_axi_rdata    (hyperram0_rdata),
        .o_axi_rresp    (hyperram0_rresp),

        // ==========================================
        // ACCEL COMMAND PORT (AXI to DMAC) - ĐÃ THÊM
        // ==========================================
        .AWVALID_i      (hyperram0_AWVALID_i),
        .AWREADY_o      (hyperram0_AWREADY_o),
        .AWADDR_i       (hyperram0_AWADDR_i),
        .AWBURST_i      (hyperram0_AWBURST_i),

        .ARVALID_i      (hyperram0_ARVALID_i),
        .ARREADY_o      (hyperram0_ARREADY_o),
        .ARADDR_i       (hyperram0_ARADDR_i),
        .ARBURST_i      (hyperram0_ARBURST_i),

        // ==========================================
        // ACCEL DATA PORT (AXI-STREAM) - ĐÃ THÊM
        // ==========================================
        // --- Master Port 0---
        .m_tvalid_o     (hyperram0_m_tvalid_o),
        .m_tready_i     (hyperram0_m_tready_i),
        .m_tdata_o      (hyperram0_m_tdata_o),
        .m_tstrb_o      (hyperram0_m_tstrb_o),
        .m_tkeep_o      (hyperram0_m_tkeep_o),
        .m_tlast_o      (hyperram0_m_tlast_o),
        // --- Master Port 1---
        .m1_tvalid_o    (hyperram0_m1_tvalid_o),
        .m1_tready_i    (hyperram0_m1_tready_i),
        .m1_tdata_o     (hyperram0_m1_tdata_o),
        .m1_tstrb_o     (hyperram0_m1_tstrb_o),
        .m1_tkeep_o     (hyperram0_m1_tkeep_o),
        .m1_tlast_o     (hyperram0_m1_tlast_o),

        // --- Slave Port ---
        .s_tvalid_i     (hyperram0_s_tvalid_i),
        .s_tready_o     (hyperram0_s_tready_o),
        .s_tdata_i      (hyperram0_s_tdata_i),
        .s_tstrb_i      (hyperram0_s_tstrb_i),
        .s_tkeep_i      (hyperram0_s_tkeep_i),
        .s_tlast_i      (hyperram0_s_tlast_i),
        
        // ==========================================
        // EXTERNAL HYPERBUS PHYSICAL PINS
        // ==========================================
        .dq_io          (hyperram0_dq_io),
        .rwds_io        (hyperram0_rwds_io),
        .hclk_p         (hyperram0_hclk_p),     // For 3V RAMs, just use the single-ended (positive) clock
        .hclk_n         (/*hyperram0_hclk_n*/),                 // hyperram0_hclk_n (bỏ trống nếu không dùng)
        .cs_n           (hyperram0_cs_n)
    );
    assign hyperram0_resetn = 'b1;


    // // Instantiate ospi1_axi_lite (Slave 10)
    // OSPI_axi_lite_core #(
    //     .NUM_MASTERS(NUM_MASTERS),
    //     .ADDR_WIDTH(ADDR_WIDTH),
    //     .DATA_WIDTH(DATA_WIDTH),
    //     .TRANS_W_STRB_W(TRANS_W_STRB_W),
    //     .TRANS_WR_RESP_W(TRANS_WR_RESP_W),
    //     .TRANS_PROT(TRANS_PROT),
    //     .ADDR_REGISTERS_0(32'h0200_5100),
    //     .ADDR_REGISTERS_1(32'h0200_5104),
    //     .ADDR_REGISTERS_2(32'h0200_5108),
    //     .ADDR_REGISTERS_3(32'h0200_510C),
    //     .ADDR_REGISTERS_4(32'h0200_5110),
    //     .ADDR_REGISTERS_5(32'h0200_5114)
    // ) ospi1 (
    //     // ==========================================
    //     // SYSTEM SIGNALS
    //     // ==========================================
    //     .clk            (clk),
    //     .resetn         (resetn),

    //     // ==========================================
    //     // AXI-LITE INTERFACE (CPU)
    //     // ==========================================
    //     .i_axi_awvalid  (ospi1_awvalid),
    //     .o_axi_awready  (ospi1_awready),
    //     .i_axi_awaddr   (ospi1_awaddr),
    //     .i_axi_awprot   (ospi1_awprot),

    //     .i_axi_wvalid   (ospi1_wvalid),
    //     .o_axi_wready   (ospi1_wready),
    //     .i_axi_wdata    (ospi1_wdata),
    //     .i_axi_wstrb    (ospi1_wstrb),
        
    //     .o_axi_bvalid   (ospi1_bvalid),
    //     .i_axi_bready   (ospi1_bready),
    //     .o_axi_bresp    (ospi1_bresp),

    //     .i_axi_arvalid  (ospi1_arvalid),
    //     .o_axi_arready  (ospi1_arready),
    //     .i_axi_araddr   (ospi1_araddr),
    //     .i_axi_arprot   (ospi1_arprot),

    //     .o_axi_rvalid   (ospi1_rvalid),
    //     .i_axi_rready   (ospi1_rready),
    //     .o_axi_rdata    (ospi1_rdata),
    //     .o_axi_rresp    (ospi1_rresp),
        
    //     // ==========================================
    //     // ACCEL COMMAND PORT (AXI to DMAC) - ĐÃ THÊM
    //     // ==========================================
    //     .AWVALID_i      (ospi1_AWVALID_i),
    //     .AWREADY_o      (ospi1_AWREADY_o),
    //     .AWADDR_i       (ospi1_AWADDR_i),
    //     .AWBURST_i      (ospi1_AWBURST_i),

    //     .ARVALID_i      (ospi1_ARVALID_i),
    //     .ARREADY_o      (ospi1_ARREADY_o),
    //     .ARADDR_i       (ospi1_ARADDR_i),
    //     .ARBURST_i      (ospi1_ARBURST_i),

    //     // ==========================================
    //     // ACCEL DATA PORT (AXI-STREAM) - ĐÃ THÊM
    //     // ==========================================
    //     // --- Master Port ---
    //     .m_tvalid_o     (ospi1_m_tvalid_o),
    //     .m_tready_i     (ospi1_m_tready_i),
    //     .m_tdata_o      (ospi1_m_tdata_o),
    //     .m_tstrb_o      (ospi1_m_tstrb_o),
    //     .m_tkeep_o      (ospi1_m_tkeep_o),
    //     .m_tlast_o      (ospi1_m_tlast_o),

    //     // --- Slave Port ---
    //     .s_tvalid_i     (ospi1_s_tvalid_i),
    //     .s_tready_o     (ospi1_s_tready_o),
    //     .s_tdata_i      (ospi1_s_tdata_i),
    //     .s_tstrb_i      (ospi1_s_tstrb_i),
    //     .s_tkeep_i      (ospi1_s_tkeep_i),
    //     .s_tlast_i      (ospi1_s_tlast_i),

    //     // ==========================================
    //     // EXTERNAL HYPERBUS PHYSICAL PINS
    //     // ==========================================
    //     .dq_io          (ospi1_dq_io),
    //     .rwds_io        (ospi1_rwds_io),

    //     .hclk_p         (ospi1_hclk_p),  // For 3V RAMs, just use the single-ended (positive) clock
    //     .hclk_n         (),              // ospi1_hclk_n (bỏ trống nếu không dùng)

    //     .cs_n           (ospi1_cs_n)
    // );
    // assign ospi1_resetn = 'b1;

    // Instantiate hyperram1_axi_lite (Slave 10)
    hyperram_axi_lite_core #(
        .SETUP_PORTS(1),
        .NUM_MASTERS(NUM_MASTERS),
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .TRANS_W_STRB_W(TRANS_W_STRB_W),
        .TRANS_WR_RESP_W(TRANS_WR_RESP_W),
        .TRANS_PROT(TRANS_PROT),
        .ADDR_WIDTH_DMAC        (ADDR_WIDTH_DMAC),
        .BURST_WIDTH            (BURST_WIDTH),
        .DATA_WIDTH_BYTE        (DATA_WIDTH_BYTE),
        .MODE_2READ_ENB         (0),
        .SHMOOD_SELECT          (1),  // 0: FMC0 , 1: FMC1
        .SIM_ENB                (0),
        .ADDR_REGISTERS_0(32'h0200_5100),
        .ADDR_REGISTERS_1(32'h0200_5104),
        .ADDR_REGISTERS_2(32'h0200_5108),
        .ADDR_REGISTERS_3(32'h0200_510C),
        .ADDR_REGISTERS_4(32'h0200_5110),
        .ADDR_REGISTERS_5(32'h0200_5114)
    ) hyperram1 (
        // ==========================================
        // SYSTEM SIGNALS
        // ==========================================
        .clk            (clk),
        .resetn         (resetn),

        // ==========================================
        // AXI-LITE INTERFACE (CPU)
        // ==========================================
        .i_axi_awvalid  (hyperram1_awvalid),
        .o_axi_awready  (hyperram1_awready),
        .i_axi_awaddr   (hyperram1_awaddr),
        .i_axi_awprot   (hyperram1_awprot),

        .i_axi_wvalid   (hyperram1_wvalid),
        .o_axi_wready   (hyperram1_wready),
        .i_axi_wdata    (hyperram1_wdata),
        .i_axi_wstrb    (hyperram1_wstrb),
        
        .o_axi_bvalid   (hyperram1_bvalid),
        .i_axi_bready   (hyperram1_bready),
        .o_axi_bresp    (hyperram1_bresp),

        .i_axi_arvalid  (hyperram1_arvalid),
        .o_axi_arready  (hyperram1_arready),
        .i_axi_araddr   (hyperram1_araddr),
        .i_axi_arprot   (hyperram1_arprot),

        .o_axi_rvalid   (hyperram1_rvalid),
        .i_axi_rready   (hyperram1_rready),
        .o_axi_rdata    (hyperram1_rdata),
        .o_axi_rresp    (hyperram1_rresp),
        
        // ==========================================
        // ACCEL COMMAND PORT (AXI to DMAC) - ĐÃ THÊM
        // ==========================================
        .AWVALID_i      (hyperram1_AWVALID_i),
        .AWREADY_o      (hyperram1_AWREADY_o),
        .AWADDR_i       (hyperram1_AWADDR_i),
        .AWBURST_i      (hyperram1_AWBURST_i),

        .ARVALID_i      (hyperram1_ARVALID_i),
        .ARREADY_o      (hyperram1_ARREADY_o),
        .ARADDR_i       (hyperram1_ARADDR_i),
        .ARBURST_i      (hyperram1_ARBURST_i),

        // ==========================================
        // ACCEL DATA PORT (AXI-STREAM) - ĐÃ THÊM
        // ==========================================
        // --- Master Port ---
        .m_tvalid_o     (hyperram1_m_tvalid_o),
        .m_tready_i     (hyperram1_m_tready_i),
        .m_tdata_o      (hyperram1_m_tdata_o),
        .m_tstrb_o      (hyperram1_m_tstrb_o),
        .m_tkeep_o      (hyperram1_m_tkeep_o),
        .m_tlast_o      (hyperram1_m_tlast_o),

        // --- Slave Port ---
        .s_tvalid_i     (hyperram1_s_tvalid_i),
        .s_tready_o     (hyperram1_s_tready_o),
        .s_tdata_i      (hyperram1_s_tdata_i),
        .s_tstrb_i      (hyperram1_s_tstrb_i),
        .s_tkeep_i      (hyperram1_s_tkeep_i),
        .s_tlast_i      (hyperram1_s_tlast_i),

        // ==========================================
        // EXTERNAL HYPERBUS PHYSICAL PINS
        // ==========================================
        .dq_io          (hyperram1_dq_io),
        .rwds_io        (hyperram1_rwds_io),

        .hclk_p         (hyperram1_hclk_p),  // For 3V RAMs, just use the single-ended (positive) clock
        .hclk_n         (/*hyperram1_hclk_n*/),              // hyperram1_hclk_n (bỏ trống nếu không dùng)

        .cs_n           (hyperram1_cs_n)
    );
    assign hyperram1_resetn = 'b1;


    
    // Instantiate timer0_axi_lite (Slave 11)
    TIMER_axi_lite_core #(
        .NUM_MASTERS(NUM_MASTERS),
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .TRANS_W_STRB_W(TRANS_W_STRB_W),
        .TRANS_WR_RESP_W(TRANS_WR_RESP_W),
        .TRANS_PROT(TRANS_PROT),
        .ADDR_REGISTERS_0(32'h0200_6000)
        // .ADDR_REGISTERS_1(32'h0200_6004),
        // .ADDR_REGISTERS_2(32'h0200_6008),
    ) timer0 (
        .clk(clk),
        .resetn(resetn),
        .i_axi_awvalid(timer0_awvalid),
        .o_axi_awready(timer0_awready),
        .i_axi_awaddr(timer0_awaddr),
        .i_axi_awprot(timer0_awprot),

        .i_axi_wvalid(timer0_wvalid),
        .o_axi_wready(timer0_wready),
        .i_axi_wdata(timer0_wdata),
        .i_axi_wstrb(timer0_wstrb),
        .o_axi_bvalid(timer0_bvalid),
        .i_axi_bready(timer0_bready),
        .o_axi_bresp(timer0_bresp),

        .i_axi_arvalid(timer0_arvalid),
        .o_axi_arready(timer0_arready),
        .i_axi_araddr(timer0_araddr),
        .i_axi_arprot(timer0_arprot),

        .o_axi_rvalid(timer0_rvalid),
        .i_axi_rready(timer0_rready),
        .o_axi_rdata(timer0_rdata),
        .o_axi_rresp(timer0_rresp)
    );


    
    // Instantiate gpio_axi_lite (Slave 12)
    GPIO_axi_lite_core #(
        .NUM_MASTERS(NUM_MASTERS),
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .TRANS_W_STRB_W(TRANS_W_STRB_W),
        .TRANS_WR_RESP_W(TRANS_WR_RESP_W),
        .TRANS_PROT(TRANS_PROT),
        .ADDR_REGISTERS_0(32'h0200_7000),
        .ADDR_REGISTERS_1(32'h0200_7004),
        .ADDR_REGISTERS_2(32'h0200_7008)
    ) gpio (
        .clk(clk),
        .resetn(resetn),
        .i_axi_awvalid(gpio_awvalid),
        .o_axi_awready(gpio_awready),
        .i_axi_awaddr(gpio_awaddr),
        .i_axi_awprot(gpio_awprot),

        .i_axi_wvalid(gpio_wvalid),
        .o_axi_wready(gpio_wready),
        .i_axi_wdata(gpio_wdata),
        .i_axi_wstrb(gpio_wstrb),
        .o_axi_bvalid(gpio_bvalid),
        .i_axi_bready(gpio_bready),
        .o_axi_bresp(gpio_bresp),

        .i_axi_arvalid(gpio_arvalid),
        .o_axi_arready(gpio_arready),
        .i_axi_araddr(gpio_araddr),
        .i_axi_arprot(gpio_arprot),

        .o_axi_rvalid(gpio_rvalid),
        .i_axi_rready(gpio_rready),
        .o_axi_rdata(gpio_rdata),
        .o_axi_rresp(gpio_rresp),

        .gpio_io(gpio_io)
    );


    // Instantiate video_streaming_axi_lite_core (Slave 13)
    video_streaming_axi_lite_core #(
        .NUM_MASTERS(NUM_MASTERS),
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .TRANS_W_STRB_W(TRANS_W_STRB_W),
        .TRANS_WR_RESP_W(TRANS_WR_RESP_W),
        .TRANS_PROT(TRANS_PROT),
        .CYCLE_CLOCK(2),
        .ADDR_REGISTERS_0(32'h0200_8000),
        .ADDR_REGISTERS_1(32'h0200_8004),
        .ADDR_REGISTERS_2(32'h0200_8008),
        .ADDR_REGISTERS_3(32'h0200_800C),
        .ADDR_REGISTERS_4(32'h0200_8010),
        .ADDR_REGISTERS_5(32'h0200_8014),
        .BURST_SELECT_WIDTH(16),
        .DATA_WIDTH_BYTE(DATA_WIDTH_BYTE)
    ) video_streaming (
        // ==========================================
        // SYSTEM SIGNALS
        // ==========================================
        .clk            (clk),
        .clk24MHz_i     (clk24MHz_oddr),
        .clk25MHz_i     (clk25MHz),
        .clk50MHz_i     (clk50MHz),
        .resetn         (resetn),

        // ==========================================
        // AXI-LITE INTERFACE (CPU)
        // ==========================================
        .i_axi_awaddr   (video_awaddr),
        .i_axi_awvalid  (video_awvalid),
        .o_axi_awready  (video_awready),
        .i_axi_awprot   (video_awprot),

        .i_axi_wdata    (video_wdata),
        .i_axi_wstrb    (video_wstrb),
        .i_axi_wvalid   (video_wvalid),
        .o_axi_wready   (video_wready),

        .o_axi_bresp    (video_bresp),
        .o_axi_bvalid   (video_bvalid),
        .i_axi_bready   (video_bready),

        .i_axi_araddr   (video_araddr),
        .i_axi_arvalid  (video_arvalid),
        .o_axi_arready  (video_arready),
        .i_axi_arprot   (video_arprot),

        .o_axi_rdata    (video_rdata),
        .o_axi_rvalid   (video_rvalid),
        .o_axi_rresp    (video_rresp),
        .i_axi_rready   (video_rready),

        // ==========================================
        // ACCEL PORTS - declared internally, not connected to top yet
        // ==========================================
        .grant_request_cam2accel_o (video_grant_request_cam2accel),
        .ARVALID_i                 (video_ARVALID_i),
        .ARREADY_o                 (video_ARREADY_o),
        .ARADDR_i                  (video_ARADDR_i),
        .ARBURST_i                 (video_ARBURST_i),

        .m_tvalid_o                (video_m_tvalid_o),
        .m_tready_i                (video_m_tready_i),
        .m_tdata_o                 (video_m_tdata_o),
        .m_tstrb_o                 (video_m_tstrb_o),
        .m_tkeep_o                 (video_m_tkeep_o),
        .m_tlast_o                 (video_m_tlast_o),
        .m_tid_o                   (video_m_tid_o),

        // ==========================================
        // CAMERA TOP IO
        // ==========================================
        .cam_pclk_i                (cam_pclk_i),
        .cam_half_pixel_i          (cam_half_pixel_i),
        .cam_href                  (cam_href),
        .cam_vsync                 (cam_vsync),
        .cam_xclk_o                (cam_xclk_o),

        // ==========================================
        // HDMI TOP IO
        // ==========================================
        .HDMI_TX_HS                (HDMI_TX_HS),
        .HDMI_TX_VS                (HDMI_TX_VS),
        .HDMI_TX_DE                (HDMI_TX_DE),
        .HDMI_TX_CLK               (HDMI_TX_CLK),
        .HDMI_TX_D                 (HDMI_TX_D)
    );

    cnn_ifbuf_dma_mux #(
        .ADDR_WIDTH_DMAC(ADDR_WIDTH_DMAC),
        .HYPER_BURST_WIDTH(BURST_WIDTH),
        .VIDEO_ADDR_WIDTH(ADDR_WIDTH),
        .VIDEO_BURST_WIDTH(16),
        .DATA_WIDTH_BYTE(DATA_WIDTH_BYTE),
        .CNN_BURST_WIDTH(8)
    ) cnn_ifbuf_source_mux (
        .select_video_i(video_grant_request_cam2accel),

        .cnn_cfg_valid_i(cnn_ifbuf_dma_vldcfg),
        .cnn_cfg_ready_o(cnn_ifbuf_dma_rdycfg),
        .cnn_cfg_addr_i(cnn_ifbuf_dma_baddr),
        .cnn_cfg_burst_i(cnn_ifbuf_dma_burst),
        
        .cnn_stream_valid_o(cnn_ifbuf_dma_vld),
        .cnn_stream_data_o(cnn_ifbuf_dma_data),
        .cnn_stream_tlast_o(cnn_ifbuf_dma_tlast),
        .cnn_stream_ready_i(cnn_ifbuf_dma_rdy),

        .hyper_arvalid_o(hyperram1_ARVALID_i),
        .hyper_arready_i(hyperram1_ARREADY_o),
        .hyper_araddr_o(hyperram1_ARADDR_i),
        .hyper_arburst_o(hyperram1_ARBURST_i),
        .hyper_tvalid_i(hyperram1_m_tvalid_o),
        .hyper_tready_o(hyperram1_m_tready_i),
        .hyper_tdata_i(hyperram1_m_tdata_o),
        .hyper_tlast_i(hyperram1_m_tlast_o),

        .video_arvalid_o(video_ARVALID_i),
        .video_arready_i(video_ARREADY_o),
        .video_araddr_o(video_ARADDR_i),
        .video_arburst_o(video_ARBURST_i),
        .video_tvalid_i(video_m_tvalid_o),
        .video_tready_o(video_m_tready_i),
        .video_tdata_i(video_m_tdata_o),
        .video_tlast_i(video_m_tlast_o)
    );

    // Instantiate cnn_axi_lite (Slave 14)
    cnn_axi_lite #(
        .NUM_MASTERS(NUM_MASTERS),
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .TRANS_W_STRB_W(TRANS_W_STRB_W),
        .TRANS_WR_RESP_W(TRANS_WR_RESP_W),
        .TRANS_PROT(TRANS_PROT),
        .CYCLE_CLOCK(2),
        .ADDR_CNN_BASE(32'h0200_9000)
    ) cnn_accel (
        .clk(clk),
        .resetn(resetn),

        .i_axi_awaddr(cnn_awaddr),
        .i_axi_awvalid(cnn_awvalid),
        .o_axi_awready(cnn_awready),
        .i_axi_awprot(cnn_awprot),

        .i_axi_wdata(cnn_wdata),
        .i_axi_wstrb(cnn_wstrb),
        .i_axi_wvalid(cnn_wvalid),
        .o_axi_wready(cnn_wready),

        .o_axi_bresp(cnn_bresp),
        .o_axi_bvalid(cnn_bvalid),
        .i_axi_bready(cnn_bready),

        .i_axi_araddr(cnn_araddr),
        .i_axi_arvalid(cnn_arvalid),
        .o_axi_arready(cnn_arready),
        .i_axi_arprot(cnn_arprot),

        .o_axi_rdata(cnn_rdata),
        .o_axi_rvalid(cnn_rvalid),
        .o_axi_rresp(cnn_rresp),
        .i_axi_rready(cnn_rready),

        .irq_accel_done_o(cnn_irq_accel_done),
        .eoi_accel_done_i(cpu0_eoi[IRQ_CNN_ACCEL_DONE]),
        .cnn_cpu_accel_busy_o(),

        .cnn_ifbuf_dma_rdycfg_i(cnn_ifbuf_dma_rdycfg),
        .cnn_ifbuf_dma_vld_i(cnn_ifbuf_dma_vld),
        .cnn_ifbuf_dma_data_i(cnn_ifbuf_dma_data),
        .cnn_ifbuf_dma_tlast_i(cnn_ifbuf_dma_tlast),
        .cnn_ifbuf_dma_vldcfg_o(cnn_ifbuf_dma_vldcfg),
        .cnn_ifbuf_dma_burst_o(cnn_ifbuf_dma_burst),
        .cnn_ifbuf_dma_baddr_o(cnn_ifbuf_dma_baddr),
        .cnn_ifbuf_dma_rdy_o(cnn_ifbuf_dma_rdy),

        .cnn_fltbuf_dma_rdycfg_i(hyperram0_AWREADY_o),
        .cnn_fltbuf_dma_vld_i(hyperram0_m_tvalid_o),
        .cnn_fltbuf_dma_data_i(hyperram0_m_tdata_o),
        .cnn_fltbuf_dma_tlast_i(hyperram0_m_tlast_o),
        .cnn_fltbuf_dma_vldcfg_o(hyperram0_AWVALID_i),
        .cnn_fltbuf_dma_burst_o(hyperram0_AWBURST_i),
        .cnn_fltbuf_dma_baddr_o(hyperram0_AWADDR_i),
        .cnn_fltbuf_dma_rdy_o(hyperram0_m_tready_i),

        .cnn_bias_dma_rdycfg_i(hyperram0_ARREADY_o),
        .cnn_bias_dma_vldcfg_o(hyperram0_ARVALID_i),
        .cnn_bias_dma_burst_o(cnn_bias_dma_burst),
        .cnn_bias_dma_baddr_o(hyperram0_ARADDR_i),
        .cnn_bias_dma_vld_i(hyperram0_m1_tvalid_o),
        .cnn_bias_dma_data_i(hyperram0_m1_tdata_o),
        .cnn_bias_dma_tlast_i(hyperram0_m1_tlast_o),
        .cnn_bias_dma_rdy_o(hyperram0_m1_tready_i),

        .cnn_ofbuf_dma_rdycfg_i(hyperram1_AWREADY_o),
        .cnn_ofbuf_dma_vldcfg_o(hyperram1_AWVALID_i),
        .cnn_ofbuf_dma_burst_o(cnn_ofbuf_dma_burst),
        .cnn_ofbuf_dma_baddr_o(hyperram1_AWADDR_i),
        .cnn_ofbuf_dma_vld_o(hyperram1_s_tvalid_i),
        .cnn_ofbuf_dma_data_o(hyperram1_s_tdata_i),
        .cnn_ofbuf_dma_tlast_o(hyperram1_s_tlast_i),
        .cnn_ofbuf_dma_rdy_i(hyperram1_s_tready_o)
    );

endmodule

