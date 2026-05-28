`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 02/10/2026 11:39:37 PM
// Design Name: 
// Module Name: filter_cache
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


module filter_cache #(
    parameter WIDTH = 8,
    parameter DEPTH = 11,
    parameter PE_PER_PU = 12
)(
    input                   clk,
    input                   rst_n,
    input                   fltc_fltbuf_vld_i,
    input   [WIDTH-1:0]     fltc_fltbuf_data_i,
    input   [WIDTH-1:0]     zp,
    output                  fltc_fltbuf_rdy_o,

    input                   swap_fltc_i,
    output                  swap_fltc_o,
    input   [3:0]           fltc_inf_hf_i,
    input                   fltc_fltbuf_done_pass_i,
    input                   fltc_pe_rdy_i,
    input                   fltc_pu_clr_ch_flt_i,
    output  [PE_PER_PU-1:0] fltc_pe_vld_o,

    output [PE_PER_PU*WIDTH-1:0] fltc_pe_data_o //THEM REG
    );

    reg [3:0]   count_w;
    reg [3:0]   count_w_nxt;
    reg [3:0]   count_h;
    reg [3:0]   count_h_nxt;
    reg         id;
    reg         done_prepare;
    // wire done_prepare_en;
    wire [PE_PER_PU-1:0]    wr_en;
    wire [PE_PER_PU-1:0]    rd_en;
    reg                     count_en;
    wire                    id_en;
    wire [PE_PER_PU-1:0]    vld_o;

    assign rd_en                = {PE_PER_PU{fltc_pe_rdy_i}} & fltc_pe_vld_o;
    assign fltc_fltbuf_rdy_o    = !done_prepare; // Cho phep nhan du lieu moi khi count chua den muc max
    assign swap_fltc_o          = (done_prepare || fltc_fltbuf_done_pass_i) & (fltc_pu_clr_ch_flt_i | !vld_o[0]);
    assign id_en                = swap_fltc_i;
    assign fltc_pe_vld_o        = vld_o;
    always @(posedge clk) begin
      if(!rst_n) begin
          done_prepare <= 0;
      end else begin
        if(id_en) done_prepare <= 0;
        else if (fltc_fltbuf_done_pass_i) begin
          done_prepare <= 1;
        end
      end 
    end
    always @(*) begin
        if (count_w == fltc_inf_hf_i - 1) begin
            count_w_nxt = 0;
        end else begin
            count_w_nxt = count_w + 1;
        end
        count_h_nxt = count_h + 1;
    end
    always @(posedge clk) begin
        if (!rst_n) begin
            id <= 0;
        end else if (id_en) begin
            id <= ~id; // Dao id khi du lieu da san sang cho comp
        end
    end
    always @(posedge clk) begin
        if (!rst_n) begin
            count_en <= 0;
        end else begin
            count_en <= fltc_fltbuf_vld_i & fltc_fltbuf_rdy_o;
        end
    end
    always @(posedge clk) begin
        if (!rst_n) begin
            count_w <= 0;
        end else begin
            if(id_en) count_w <= 0;
            else if (count_en) begin
                count_w <= count_w_nxt;
            end
        end 
    end
    always @(posedge clk) begin
        if (!rst_n) begin
            count_h <= 0;
        end else begin
            if(id_en) count_h <= 0;
            else if (count_en && count_w == fltc_inf_hf_i - 1) begin
                count_h <= count_h_nxt; 
            end
        end 
    end
    genvar i;
    generate
        for (i = 0; i < PE_PER_PU; i = i + 1) begin : fifo_array
            pp_circle_reg #(
                .WIDTH(WIDTH),
                .DEPTH(DEPTH)
            ) circle_reg_inft (
                .clk(clk),
                .rst_n(rst_n),
                .id_i(id),
                .inf_hf_i(fltc_inf_hf_i),
                .wr_en(wr_en[i]),
                .rd_en(rd_en[i]),
                .clr_i(fltc_pu_clr_ch_flt_i),
                .zp(zp),
                .data_i(fltc_fltbuf_data_i),
                .data_o(fltc_pe_data_o[i*WIDTH +: WIDTH]),
                .vld_o(vld_o[i])
            );
        end
    endgenerate
    genvar j;
    generate
        for (j = 0; j < PE_PER_PU; j = j + 1) begin : wr_en_array
            assign wr_en[j] = count_en & (count_h == j);
        end
    endgenerate
endmodule