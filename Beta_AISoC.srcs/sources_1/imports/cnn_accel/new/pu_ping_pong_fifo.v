`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 02/10/2026 08:58:01 PM
// Design Name: 
// Module Name: ping_pong_fifo
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


module pu_ping_pong_fifo #(
    parameter WIDTH = 8,
    parameter DEPTH = 2048
)(
    input                   clk,
    input                   rst_n,
    input                   pp_pu_id_i,
    input                   pp_pe_wr_en_i,
    input                   pp_pe_rd_ena_i,
    input                   pp_pe_rd_enb_i,
    input                   pp_cwc_clr_i,
    input   [WIDTH-1:0]     pp_pe_data_i,
    output  [WIDTH-1:0]     pp_pe_data_a_o,
    output  [WIDTH-1:0]     pp_pe_cwc_data_b_o,
    output                  pp_pe_vld_o,
    output                  pp_cwc_end_data_o
    );

    wire [WIDTH-1:0] data_o1, data_o2;
    wire [WIDTH-1:0] pp_pe_data_i1, pp_pe_data_i2;
    wire            pp_pe_wr_en_i1, pp_pe_wr_en_i2;
    wire            rd_en1, rd_en2;
    wire            clr1, clr2;
    wire            vld1, vld2;
    wire            end_data1, end_data2;
    
    assign rd_en1           = pp_pe_rd_ena_i & pp_pu_id_i || pp_pe_rd_enb_i & ~pp_pu_id_i || (pp_pe_rd_ena_i || pp_pe_rd_enb_i) && !pp_pe_vld_o; // Cho phep doc tu fifo1 khi pp_pu_id_i=0 va tu fifo2 khi pp_pu_id_i=1
    assign rd_en2           = pp_pe_rd_ena_i & ~pp_pu_id_i || pp_pe_rd_enb_i & pp_pu_id_i || (pp_pe_rd_ena_i || pp_pe_rd_enb_i) && !pp_pe_vld_o;
    assign clr1             = pp_cwc_clr_i & ~pp_pu_id_i;
    assign clr2             = pp_cwc_clr_i & pp_pu_id_i;
    assign pp_pe_wr_en_i1   = pp_pe_wr_en_i && (pp_pu_id_i); // Cho phep ghi vao fifo1 khi pp_pu_id_i=1 hoac doc tu fifo1
    assign pp_pe_wr_en_i2   = pp_pe_wr_en_i && (!pp_pu_id_i);  // Cho phep ghi vao fifo2 khi pp_pu_id_i=0 hoac doc tu fifo2
    assign pp_pe_data_i1    = pp_pe_data_i; 
    assign pp_pe_data_i2    = pp_pe_data_i; 
    assign pp_pe_cwc_data_b_o = pp_pu_id_i ? (pp_pe_vld_o ? data_o2 : data_o1) : (pp_pe_vld_o ? data_o1 : data_o2);
    assign pp_pe_data_a_o   = pp_pu_id_i ? data_o1 : data_o2;
    assign pp_pe_vld_o      = pp_pu_id_i ? vld2 : vld1;
    assign pp_cwc_end_data_o = pp_pu_id_i ? end_data2 : end_data1;
    
    fifo_bram #(
        .WIDTH(WIDTH),
        .DEPTH(DEPTH)
    ) fifo1 (
        .clk(clk),
        .rst_n(rst_n),
        .wr_en(pp_pe_wr_en_i1),
        .rd_en(rd_en1),
        .clr(clr1),
        .din(pp_pe_data_i1),
        .dout(data_o1),
        .full(),
        .vld_o(vld1),
        .end_data(end_data1)
    );
    fifo_bram #(
        .WIDTH(WIDTH),
        .DEPTH(DEPTH)
    ) fifo2 (
        .clk(clk),
        .rst_n(rst_n),
        .wr_en(pp_pe_wr_en_i2),
        .rd_en(rd_en2),
        .clr(clr2),
        .din(pp_pe_data_i2),
        .dout(data_o2),
        .full(),
        .vld_o(vld2),
        .end_data(end_data2)
    );
endmodule
