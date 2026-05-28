`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 07/12/2025 01:08:00 AM
// Design Name: 
// Module Name: AISoC
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



module AISoC#(
    //config axi interconnect
    // Transaction configuration
    parameter ADDR_WIDTH = 32,          // Address width
    parameter DATA_WIDTH = 32,          // Data width
    parameter TRANS_W_STRB_W =  4,       // width strobe
    parameter TRANS_WR_RESP_W = 2,       // width response
    parameter TRANS_PROT      = 3,
    parameter QUANTUM_TIME = 16,

    // Interconnect configuration
    parameter NUM_MASTERS = 1,    // Number of masters (only config parameter of fifo, not config port of master)
    parameter NUM_SLAVES  = 9,    // Number of slaves
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

        {32'h0200_7000, 32'h0200_7FFF},     // slave 8
        {32'h0200_6000, 32'h0200_6FFF},     // slave 7
        {32'h0200_5000, 32'h0200_5FFF},     // slave 6       
        {32'h0200_4000, 32'h0200_4FFF},     // slave 5
        {32'h0200_3000, 32'h0200_3FFF},     // slave 4       
        {32'h0200_0000, 32'h0200_2FFF},     // slave 3
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
	parameter [ 0:0] ENABLE_IRQ = 0,
	parameter [ 0:0] ENABLE_IRQ_QREGS = 1,
	parameter [ 0:0] ENABLE_IRQ_TIMER = 1,
	parameter [ 0:0] ENABLE_TRACE = 0,
	parameter [ 0:0] REGS_INIT_ZERO = 1,
	parameter [31:0] MASKED_IRQ = 32'h 0000_0000,
	parameter [31:0] LATCHED_IRQ = 32'h ffff_ffff,
	parameter [31:0] PROGADDR_RESET = 32'h 0100_0000,
	parameter [31:0] PROGADDR_IRQ = 32'h 0000_0010,
	parameter [31:0] STACKADDR = 32'h 0001_0000,

    parameter [31:0] LATCHED_IRQ1 = 32'h ffff_ffff,
	parameter [31:0] PROGADDR_RESET1 = 32'h 0400_0000,
	parameter [31:0] PROGADDR_IRQ1 = 32'h 0000_0010,
	parameter [31:0] STACKADDR1 = 32'h 0300_4000,


    //config imem and dmem
    parameter B_MEM_SIZE = 65536, // 64KB  ROM
    parameter D_MEM_SIZE =  65536, // 64KB  SRAM
    parameter I_MEM_SIZE = 65536, // 64KB  FLASH

    //config spi
    parameter NSlave = 2
)(
    input   clk,
    // input   resetn,
    // input   clk_wizard, // debug
    input   reset_n,// debug

    output  trap0,
    output  trap1,

    //port uart0
    input  wire                         rx0,
    output wire                         tx0,

    //port spi0
    output                              spi0_clk,
    output                              spi0_mosi,
    input                               spi0_miso,
    output      [1:0]                   spi0_ss_n,

    //port i2c0
    output tri                          i2c0_scl,
    inout  tri                          i2c0_sda,

    //port ospi0
    inout       [7:0]                   ospi0_dq_io,
    inout                               ospi0_rwds_io,
	output                              ospi0_hclk_p,  // For 3V RAMs, just use the single-ended (positive) clock
	// output                              ospi0_hclk_n,
	output                              ospi0_cs_n,
    output                              ospi0_resetn,

    // GPIO port
    inout       [7:0]                   gpio_io

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

    // AXI signals to spi0_axi_lite//////////////////slave 4/////////////////////
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

    // AXI signals to i2c0_axi_lite//////////////////slave 5/////////////////////
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

    // AXI signals to ospi0_axi_lite//////////////////slave 6/////////////////////
    wire                        ospi0_awvalid;   
    wire                        ospi0_awready;
    wire [ADDR_WIDTH-1:0]       ospi0_awaddr;
    wire [TRANS_PROT-1:0]       ospi0_awprot;
    wire                        ospi0_wvalid;    
    wire                        ospi0_wready;
    wire [TRANS_WR_RESP_W-1:0]  ospi0_bresp;
    wire [DATA_WIDTH-1:0]       ospi0_wdata;
    wire [TRANS_W_STRB_W-1:0]   ospi0_wstrb;
    wire                        ospi0_bvalid;    
    wire                        ospi0_bready;
    wire                        ospi0_arvalid;   
    wire                        ospi0_arready;
    wire [ADDR_WIDTH-1:0]       ospi0_araddr;
    wire [TRANS_PROT-1:0]       ospi0_arprot;
    wire                        ospi0_rvalid;    
    wire                        ospi0_rready;
    wire [DATA_WIDTH-1:0]       ospi0_rdata;
    wire [TRANS_WR_RESP_W-1:0]  ospi0_rresp;


    // AXI signals to timer0_axi_lite//////////////////slave 7/////////////////////
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

    // AXI signals to gpio_axi_lite//////////////////slave 8/////////////////////
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



    // clk_wiz_0 inst
    // (
    // // Clock out ports  
    // .clk_out_8MHz(clk),
    // // Status and control signals               
    // // Clock in ports
    // .clk_in_100MHz(clk_wizard)
    // );


    wire resetn;
    debouncer_delayed #(.COUNTER_VALUE(1_999_999)
    ) debounced_resetn (
        .clk(clk),
        .reset_n(1'b1),
        .noisy(reset_n),
        
        .debounced(resetn),
        .p_edge(),
        .n_edge(),
        .any_edge()
    );

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
        .irq(32'h0), // Chưa dùng IRQ
        .eoi()       // Chưa dùng IRQ
    );

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
		.PROGADDR_RESET      (PROGADDR_RESET     ),
		.PROGADDR_IRQ        (PROGADDR_IRQ        ),
		.STACKADDR           (STACKADDR           )
    ) cpu1 (
        .clk(clk),
        .resetn(resetn),
        .trap(trap1),
        .mem_axi_awvalid(cpu1_awvalid),
        .mem_axi_awready(cpu1_awready),
        .mem_axi_awaddr(cpu1_awaddr),
        .mem_axi_awprot(cpu1_awprot),
        .mem_axi_wvalid(cpu1_wvalid),
        .mem_axi_wready(cpu1_wready),
        .mem_axi_wdata(cpu1_wdata),
        .mem_axi_wstrb(cpu1_wstrb),
        .mem_axi_bvalid(cpu1_bvalid),
        .mem_axi_bready(cpu1_bready),
        .mem_axi_arvalid(cpu1_arvalid),
        .mem_axi_arready(cpu1_arready),
        .mem_axi_araddr(cpu1_araddr),
        .mem_axi_arprot(cpu1_arprot),
        .mem_axi_rvalid(cpu1_rvalid),
        .mem_axi_rready(cpu1_rready),
        .mem_axi_rdata(cpu1_rdata),
        .irq(32'h0), // Chưa dùng IRQ
        .eoi()       // Chưa dùng IRQ
    );


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
        .s_axi_awaddr_o     ({gpio_awaddr, timer0_awaddr, ospi0_awaddr, i2c0_awaddr,  spi0_awaddr,  uart0_awaddr,   imem_awaddr,    bmem_awaddr,    dmem_awaddr}),
        .s_axi_awvalid_o    ({gpio_awvalid, timer0_awvalid, ospi0_awvalid, i2c0_awvalid, spi0_awvalid, uart0_awvalid,  imem_awvalid,   bmem_awvalid,   dmem_awvalid}),
        .s_axi_awready_i    ({gpio_awready, timer0_awready, ospi0_awready, i2c0_awready, spi0_awready, uart0_awready,  imem_awready,   bmem_awready,   dmem_awready}),
        .s_axi_awprot_o     ({gpio_awprot, timer0_awprot, ospi0_awprot, i2c0_awprot,  spi0_awprot,  uart0_awprot,   imem_awprot,    bmem_awprot,    dmem_awprot}),

        .s_axi_wdata_o      ({gpio_wdata, timer0_wdata, ospi0_wdata, i2c0_wdata,   spi0_wdata,   uart0_wdata,    imem_wdata,     bmem_wdata,     dmem_wdata}),
        .s_axi_wstrb_o      ({gpio_wstrb, timer0_wstrb, ospi0_wstrb, i2c0_wstrb,   spi0_wstrb,   uart0_wstrb,    imem_wstrb,     bmem_wstrb,     dmem_wstrb}),
        .s_axi_wvalid_o     ({gpio_wvalid, timer0_wvalid, ospi0_wvalid, i2c0_wvalid,  spi0_wvalid,  uart0_wvalid,   imem_wvalid,    bmem_wvalid,    dmem_wvalid}),
        .s_axi_wready_i     ({gpio_wready, timer0_wready, ospi0_wready, i2c0_wready,  spi0_wready,  uart0_wready,   imem_wready,    bmem_wready,    dmem_wready}),

        .s_axi_bresp_i      ({gpio_bresp, timer0_bresp, ospi0_bresp, i2c0_bresp,   spi0_bresp,   uart0_bresp,    imem_bresp,     bmem_bresp,     dmem_bresp}),
        .s_axi_bvalid_i     ({gpio_bvalid, timer0_bvalid, ospi0_bvalid, i2c0_bvalid,  spi0_bvalid,  uart0_bvalid,   imem_bvalid,    bmem_bvalid,    dmem_bvalid}),
        .s_axi_bready_o     ({gpio_bready, timer0_bready, ospi0_bready, i2c0_bready,  spi0_bready,  uart0_bready,   imem_bready,    bmem_bready,    dmem_bready}),

        .s_axi_araddr_o     ({gpio_araddr, timer0_araddr, ospi0_araddr, i2c0_araddr,  spi0_araddr,  uart0_araddr,   imem_araddr,    bmem_araddr,    dmem_araddr}),
        .s_axi_arvalid_o    ({gpio_arvalid, timer0_arvalid, ospi0_arvalid, i2c0_arvalid, spi0_arvalid, uart0_arvalid,  imem_arvalid,   bmem_arvalid,   dmem_arvalid}),
        .s_axi_arready_i    ({gpio_arready, timer0_arready, ospi0_arready, i2c0_arready, spi0_arready, uart0_arready,  imem_arready,   bmem_arready,   dmem_arready}),
        .s_axi_arprot_o     ({gpio_arprot, timer0_arprot, ospi0_arprot, i2c0_arprot,  spi0_arprot,  uart0_arprot,   imem_arprot,    bmem_arprot,    dmem_arprot}),

        .s_axi_rdata_i      ({gpio_rdata, timer0_rdata, ospi0_rdata, i2c0_rdata,   spi0_rdata,   uart0_rdata,    imem_rdata,     bmem_rdata,     dmem_rdata}),
        .s_axi_rresp_i      ({gpio_rresp, timer0_rresp, ospi0_rresp, i2c0_rresp,   spi0_rresp,   uart0_rresp,    imem_rresp,     bmem_rresp,     dmem_rresp}),
        .s_axi_rvalid_i     ({gpio_rvalid, timer0_rvalid, ospi0_rvalid, i2c0_rvalid,  spi0_rvalid,  uart0_rvalid,   imem_rvalid,    bmem_rvalid,    dmem_rvalid}),
        .s_axi_rready_o     ({gpio_rready, timer0_rready, ospi0_rready, i2c0_rready,  spi0_rready,  uart0_rready,   imem_rready,    bmem_rready,    dmem_rready})
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
        .FIFO_DEPTH_BIT(8)
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

        .tx(tx0),
        .rx(rx0)
    );

    // Instantiate Spi0_axi_lite (Slave 4)
    Spi_axi_lite_core #(
        .NUM_MASTERS(NUM_MASTERS),
        .NSlave(NSlave),
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
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


    // Instantiate i2c0_axi_lite (Slave 5)
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



    // Instantiate ospi0_axi_lite (Slave 6)
    OSPI_axi_lite_core #(
        .NUM_MASTERS(NUM_MASTERS),
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .TRANS_W_STRB_W(TRANS_W_STRB_W),
        .TRANS_WR_RESP_W(TRANS_WR_RESP_W),
        .TRANS_PROT(TRANS_PROT),
        .ADDR_REGISTERS_0(32'h0200_5000),
        .ADDR_REGISTERS_1(32'h0200_5004),
        .ADDR_REGISTERS_2(32'h0200_5008),
        .ADDR_REGISTERS_3(32'h0200_500C),
        .ADDR_REGISTERS_4(32'h0200_5010)
    ) ospi0 (
        .clk(clk),
        .resetn(resetn),
        .i_axi_awvalid(ospi0_awvalid),
        .o_axi_awready(ospi0_awready),
        .i_axi_awaddr(ospi0_awaddr),
        .i_axi_awprot(ospi0_awprot),

        .i_axi_wvalid(ospi0_wvalid),
        .o_axi_wready(ospi0_wready),
        .i_axi_wdata(ospi0_wdata),
        .i_axi_wstrb(ospi0_wstrb),
        .o_axi_bvalid(ospi0_bvalid),
        .i_axi_bready(ospi0_bready),
        .o_axi_bresp(ospi0_bresp),

        .i_axi_arvalid(ospi0_arvalid),
        .o_axi_arready(ospi0_arready),
        .i_axi_araddr(ospi0_araddr),
        .i_axi_arprot(ospi0_arprot),

        .o_axi_rvalid(ospi0_rvalid),
        .i_axi_rready(ospi0_rready),
        .o_axi_rdata(ospi0_rdata),
        .o_axi_rresp(ospi0_rresp),
        
        ///
        .dq_io(ospi0_dq_io),
        .rwds_io(ospi0_rwds_io),

	    .hclk_p(ospi0_hclk_p),  // For 3V RAMs, just use the single-ended (positive) clock
	    .hclk_n(), // ospi0_hclk_n

	    .cs_n(ospi0_cs_n)
    );

    assign ospi0_resetn = 'b1;


    
    // Instantiate timer0_axi_lite (Slave 7)
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


    
    // Instantiate gpio_axi_lite (Slave 8)
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


    

endmodule
