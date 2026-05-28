`timescale 1ns / 1ps

module fifo_bram #(
    parameter WIDTH = 8,
    parameter FF_TYPE = 2,
    parameter DEPTH = 224 * 12
)(
    input               clk,
    input               rst_n,
    input               wr_en,
    input               rd_en,
    input               clr,
    input   [WIDTH-1:0] din,
    output  [WIDTH-1:0] dout,
    output              full,
    output              vld_o,
    output              end_data
);

    wire                empty;
    wire [WIDTH-1:0]    data_mem;
    assign vld_o = !empty;
       fifo_n
       #(
       .DATA_WIDTH(WIDTH),
       .FF_TYPE(2),
       .FF_NUM(2),
       .FIFO_DEPTH(DEPTH)
       ) fifo_bram_uut (
        .clk(clk),
        .data_i(din),
        .data_o(data_mem),
        .rd_valid_i(rd_en),
        .wr_valid_i(wr_en),
        .clr_rd_i(1'b0),
        .clr_ff_i(clr),
        .empty_o(empty),
        .full_o(full),
        .almost_empty_o(end_data),
        .almost_full_o(),
        .counter(),
        .rst_n(rst_n)
       );
    assign dout = data_mem ;

endmodule