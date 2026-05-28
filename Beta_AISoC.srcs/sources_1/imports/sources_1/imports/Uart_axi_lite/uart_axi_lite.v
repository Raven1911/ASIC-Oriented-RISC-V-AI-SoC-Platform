`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 04/03/2025 01:41:04 PM
// Design Name: 
// Module Name: uart_axi_lite
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


module uart_axi_lite#(
    parameter NUM_MASTERS = 1,
    parameter ADDR_WIDTH = 32,          // Address width
    parameter DATA_WIDTH = 32,          // Data width
    parameter TRANS_W_STRB_W = 4,       // width strobe
    parameter TRANS_WR_RESP_W = 2,      // width response
    parameter TRANS_PROT      = 3,
    parameter CYCLE_CLOCK = 2,
    parameter FIFO_DEPTH_BIT = 8, // bit address fifo

    //config register timer
    parameter [ADDR_WIDTH-1:0] ADDR_REGISTERS_0 = 32'h0200_2000,
    parameter [ADDR_WIDTH-1:0] ADDR_REGISTERS_1 = 32'h0200_2004,
    parameter [ADDR_WIDTH-1:0] ADDR_REGISTERS_2 = 32'h0200_2008,
    parameter [ADDR_WIDTH-1:0] ADDR_REGISTERS_3 = 32'h0200_200C,
    parameter [ADDR_WIDTH-1:0] ADDR_REGISTERS_4 = 32'h0200_2010
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
    input                               i_axi_rready,

    //RX TX
    output      tx,
    input       rx
    );

    //signals to connect
    //wire [3:0] o_wen;
    wire [ADDR_WIDTH-1:0] o_addr_w;
    wire [ADDR_WIDTH-1:0] o_addr_r;                
    wire [DATA_WIDTH-1:0] o_data_w;
    wire [DATA_WIDTH-1:0] i_data_r;

    wire o_wr_w;
    wire o_rd_r;



 
    //signals register uart
    wire            rd_uart_reg0; 
    wire            rd_uart_reg1;
    wire            wr_dvsr_reg2;
    wire            wr_uart_reg3; 
    wire            wr_uart_reg4;

    wire            tx_full, rx_empty;
    reg     [10:0]  dvsr_reg;
    wire    [7:0]   r_data;

    //body////////////////////////////////////////////
    always @(posedge clk or negedge resetn) begin
        if(~resetn) dvsr_reg <= 0;
        else begin
            if (wr_dvsr_reg2) begin
               dvsr_reg <= o_data_w[10:0];
            end
        end
        
    end

    //decoding logic
    assign rd_uart_reg0 = (o_rd_r && (o_addr_r == ADDR_REGISTERS_0)) ? 1 : 0;
    assign rd_uart_reg1 = (o_rd_r && (o_addr_r == ADDR_REGISTERS_1)) ? 1 : 0;
    assign wr_dvsr_reg2 = (o_wr_w && (o_addr_w == ADDR_REGISTERS_2)) ? 1 : 0;
    assign wr_uart_reg3 = (o_wr_w && (o_addr_w == ADDR_REGISTERS_3)) ? 1 : 0;
    assign wr_uart_reg4 = (o_wr_w && (o_addr_w == ADDR_REGISTERS_4)) ? 1 : 0;

    //slot read
    assign i_data_r = {22'h00000, tx_full, rx_empty, r_data};

    uart_unit
    #(              .DBIT('d8),       // databit
                    .SB_TICK('d16),   // tick for stop bits
                    .FIFO_W(FIFO_DEPTH_BIT)      // addr bits of FIFO
    ) 
    uart0(
        .clk(clk),
        .reset_n(resetn),
        .rd_uart(rd_uart_reg0),
        .wr_uart(wr_uart_reg3 /*|| wr_uart_reg3*/),
        .rx(rx),
        .w_data(o_data_w[7:0]),
        .dvsr(dvsr_reg),
        .tx_full(tx_full),
        .rx_empty(rx_empty),
        .tx(tx),
        .r_data(r_data)
    );

    


// Instantiate the AXI-Lite slave interface
    axi_lite_slave_interface #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .TRANS_W_STRB_W(TRANS_W_STRB_W),
        .TRANS_WR_RESP_W(TRANS_WR_RESP_W),
        .TRANS_PROT(TRANS_PROT),
        .CYCLE_CLOCK(CYCLE_CLOCK),
        .NUM_MASTERS(NUM_MASTERS)
    ) uart0_axi_lite_interface (
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
