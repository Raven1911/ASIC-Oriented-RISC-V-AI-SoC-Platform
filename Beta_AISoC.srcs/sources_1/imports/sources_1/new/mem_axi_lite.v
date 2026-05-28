`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 07/26/2025 12:39:47 AM
// Design Name: 
// Module Name: mem_axi_lite
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


module mem_axi_lite#(
    parameter NUM_MASTERS = 1,
    parameter MEM_SIZE = 532480, // 520KB
    parameter ADDR_WIDTH = 32,          // Address width
    parameter DATA_WIDTH = 32,          // Data width
    parameter TRANS_W_STRB_W = 4,       // width strobe
    parameter TRANS_WR_RESP_W = 2,      // width response
    parameter TRANS_PROT      = 3,
    parameter CYCLE_CLOCK = 2,
    parameter BASE_ADDR = 32'h0000_0000,
    parameter ENB_READMEM = 0

)(
    input clk,
    input resetn,

    // AXI-Lite Write Address Channels
    input       [ADDR_WIDTH-1:0]        i_axi_awaddr,
    input                               i_axi_awvalid,
    output                              o_axi_awready,
    input       [TRANS_PROT-1:0]        i_axi_awprot,

    // AXI-Lite Write Data Channel
    input       [DATA_WIDTH-1:0]        i_axi_wdata,
    input       [TRANS_W_STRB_W-1:0]    i_axi_wstrb,
    input                               i_axi_wvalid,
    output                              o_axi_wready,

    // AXI-Lite Write Response Channels
    output      [TRANS_WR_RESP_W-1:0]   o_axi_bresp,
    output                              o_axi_bvalid,
    input                               i_axi_bready,

    // AXI-Lite Read Address Channels
    input       [ADDR_WIDTH-1:0]        i_axi_araddr,
    input                               i_axi_arvalid,
    output                              o_axi_arready,
    input       [TRANS_PROT-1:0]        i_axi_arprot,

    // AXI4-Lite Read Data Channel
    output      [DATA_WIDTH-1:0]        o_axi_rdata,
    output                              o_axi_rvalid,
    output      [TRANS_WR_RESP_W-1:0]   o_axi_rresp,
    input                               i_axi_rready
    );

    wire [3:0] o_wen;
    wire [ADDR_WIDTH-1:0] o_addr_w;
    wire [ADDR_WIDTH-1:0] o_addr_r;                
    wire [DATA_WIDTH-1:0] o_data_w;
    wire [DATA_WIDTH-1:0] i_data_r;

    wire write_en;
    // wire o_wr_w;
    // wire o_rd_r;


    
    axi_lite_slave_interface #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .TRANS_W_STRB_W(TRANS_W_STRB_W),
        .TRANS_WR_RESP_W(TRANS_WR_RESP_W),
        .TRANS_PROT(TRANS_PROT),
        .CYCLE_CLOCK(CYCLE_CLOCK),
        .NUM_MASTERS(NUM_MASTERS)
    ) mem_axi_lite_interface (
        .clk_i(clk),
        .resetn_i(resetn),

        .i_axi_awaddr(i_axi_awaddr),
        .i_axi_awvalid(i_axi_awvalid),
        .o_axi_awready(o_axi_awready),
        .i_axi_awprot(i_axi_awprot),

        .i_axi_wdata(i_axi_wdata),
        .i_axi_wstrb(i_axi_wstrb),
        .i_axi_wvalid(i_axi_wvalid),
        .o_axi_wready(o_axi_wready),

        .o_axi_bresp(o_axi_bresp),
        .o_axi_bvalid(o_axi_bvalid),
        .i_axi_bready(i_axi_bready),

        .i_axi_araddr(i_axi_araddr),
        .i_axi_arvalid(i_axi_arvalid),
        .o_axi_arready(o_axi_arready),
        .i_axi_arprot(i_axi_arprot),

        .o_axi_rdata(o_axi_rdata),
        .o_axi_rvalid(o_axi_rvalid),
        .o_axi_rresp(o_axi_rresp),
        .i_axi_rready(i_axi_rready),

        .o_addr_w(o_addr_w),
        .o_awprot_w(),

        .o_wen(o_wen),       
        .o_data_w(o_data_w),
        .o_write_data_w(write_en),

        .i_bresp_w('b00),

        .o_addr_r(o_addr_r),
        .o_arprot_r(),
        
        .i_data_r(i_data_r),
        .i_rresp_r('b00),
        .o_read_data_r()
    );

    // Instantiate dmem module
    mem_register #(
        .MEM_SIZE(MEM_SIZE),
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .BASE_ADDR(BASE_ADDR),
        .ENB_READMEM(ENB_READMEM)
    ) mem_register_unit (
        .clk(clk),
        .write_en(write_en),
        .wen(o_wen),
        .addr_r(o_addr_r), // Word-aligned address (ignore lower 2 bits)
        .addr_w(o_addr_w), // Word-aligned address (ignore lower 2 bits)
        .din(o_data_w),
        .dout(i_data_r)
    );
endmodule



module mem_register #(
    parameter MEM_SIZE = 532480, // 520KB
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter BASE_ADDR = 32'h0000_0000,
    parameter ENB_READMEM = 0

)(
    input clk,
    input write_en,
    input [3:0] wen,
    input [ADDR_WIDTH-1:0] addr_r, addr_w,
    input [DATA_WIDTH-1:0] din,
    output reg [DATA_WIDTH-1:0] dout
    );

    //big endian
    reg [DATA_WIDTH-1:0] mem [0:(MEM_SIZE >> 2) - 1];
    
    generate
        if (ENB_READMEM == 1) begin
            initial $readmemh("boot_AISoC.hex", mem);
        end
    endgenerate
    

    always @(posedge clk) begin
        dout <= mem[(addr_r - BASE_ADDR)>>2];
        // if (write_en && wen[0]) mem[(addr_w - BASE_ADDR) >> 2][ 7: 0] <= din[ 7: 0];
		// if (write_en && wen[1]) mem[(addr_w - BASE_ADDR) >> 2][15: 8] <= din[15: 8];
		// if (write_en && wen[2]) mem[(addr_w - BASE_ADDR) >> 2][23:16] <= din[23:16];
		// if (write_en && wen[3]) mem[(addr_w - BASE_ADDR) >> 2][31:24] <= din[31:24];
        if (write_en) begin
            if (wen[0]) mem[(addr_w - BASE_ADDR) >> 2][ 7: 0] <= din[ 7: 0];
            if (wen[1]) mem[(addr_w - BASE_ADDR) >> 2][15: 8] <= din[15: 8];
            if (wen[2]) mem[(addr_w - BASE_ADDR) >> 2][23:16] <= din[23:16];
            if (wen[3]) mem[(addr_w - BASE_ADDR) >> 2][31:24] <= din[31:24];
        end
        
    end

    
endmodule