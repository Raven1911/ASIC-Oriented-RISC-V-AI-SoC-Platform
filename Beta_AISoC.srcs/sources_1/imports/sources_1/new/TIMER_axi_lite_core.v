`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 01/30/2026 03:11:21 PM
// Design Name: 
// Module Name: TIMER_axi_lite_core
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

module TIMER_axi_lite_core #(
    parameter NUM_MASTERS = 1,
    parameter ADDR_WIDTH = 32,          // Address width
    parameter DATA_WIDTH = 32,          // Data width
    parameter TRANS_W_STRB_W = 4,       // width strobe
    parameter TRANS_WR_RESP_W = 2,      // width response
    parameter TRANS_PROT      = 3,
    parameter CYCLE_CLOCK = 2,

    //config register timer
    parameter [ADDR_WIDTH-1:0] ADDR_REGISTERS_0= 32'h0200_6000,
    parameter [ADDR_WIDTH-1:0] ADDR_REGISTERS_1= 32'h0200_6004,
    parameter [ADDR_WIDTH-1:0] ADDR_REGISTERS_2= 32'h0200_6008
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

    //signals to connect
    //wire [3:0] o_wen;
    // wire [ADDR_WIDTH-1:0] o_addr_w;
    wire [ADDR_WIDTH-1:0] o_addr_r;                
    wire [DATA_WIDTH-1:0] o_data_w;
    wire [DATA_WIDTH-1:0] i_data_r;

    wire o_wr_w;
    wire o_rd_r;

    // signal declaration
    wire rd_reg0;
    // wire rd_reg1;
    // wire wr_reg2;
    wire [49:0] counter_ticked;


    // decoding
    assign rd_reg0       = (o_rd_r && (o_addr_r[31:0] == ADDR_REGISTERS_0)) ? 1 : 0;
    // assign rd_reg1       = (o_rd_r && (o_addr_r[31:0] == ADDR_REGISTERS_1)) ? 1 : 0;
    // assign wr_reg2       = (o_wr_w && (o_addr_w[31:0] == ADDR_REGISTERS_2)) ? 1 : 0;

    // read data  
    // assign i_data_r = (rd_reg0) ? {14'b0, counter_ticked[49:32]} : counter_ticked[31:0];

    assign i_data_r =
        (o_addr_r[31:0] == ADDR_REGISTERS_0) ? {14'b0, counter_ticked[49:32]} :
        (o_addr_r[31:0] == ADDR_REGISTERS_1) ? counter_ticked[31:0] :
                                            32'b0;

    


    // instantiate timer
    timer_core timer_unit
    (   
        .clk(clk),
        .resetn(resetn),
        .start_cnt_i(o_data_w[0]),
        .clear_cnt_i(o_data_w[1]),
        .counter_ticked(counter_ticked)
    );

    axi_lite_slave_interface #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .TRANS_W_STRB_W(TRANS_W_STRB_W),
        .TRANS_WR_RESP_W(TRANS_WR_RESP_W),
        .TRANS_PROT(TRANS_PROT),
        .CYCLE_CLOCK(CYCLE_CLOCK),
        .NUM_MASTERS(NUM_MASTERS)
    ) timer_axi_lite_interface (
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

        .o_addr_w(/* o_addr_w */),
        .o_awprot_w(),

        .o_wen(),       
        .o_data_w(o_data_w),
        .o_write_data_w(o_wr_w),

        .i_bresp_w('b00),

        .o_addr_r(o_addr_r),
        .o_arprot_r(),
        
        .i_data_r(i_data_r),
        .i_rresp_r('b00),
        .o_read_data_r(o_rd_r)
    );

endmodule

module timer_core(
    input clk,
    input resetn,
    input start_cnt_i,
    input clear_cnt_i,
    output reg [49:0] counter_ticked
);

    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            counter_ticked <= 0;
        end else begin
            if (clear_cnt_i) begin
                counter_ticked <= 0;
            end else if (start_cnt_i) begin
                counter_ticked <= counter_ticked + 1;
            end
        end
    end

endmodule
