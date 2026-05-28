`timescale 1ns / 1ps

module instruction_table #(
    parameter DATA_WIDTH = 8,
    parameter FIFO_DEPTH = 16
)(
    input                               clk,
    input                               rst_n,

    input                              table_cnn_vld_i,
    output                             table_cnn_rdy_o,
    input          [7:0]               table_cnn_ifheight_i,
    input          [10:0]              table_cnn_ifchannel_i,
    input          [10:0]              table_cnn_ofchannel_i,
    input          [3:0]               table_cnn_hf_i,
    input          [2:0]               table_cnn_stride_i,
    input          [1:0]               table_cnn_padding_i,
    input          [2:0]               table_cnn_ifparr_i,
    input          [1:0]               table_cnn_oftile_i,
    input          [4:0]               table_cnn_ofparr_i,
    input          [23:0]              table_cnn_ifbaddr_i,
    input          [23:0]              table_cnn_fltbaddr_i,
    input          [23:0]              table_cnn_bias_baddr_i,
    input          [23:0]              table_cnn_ofbaddr_i,
    input signed   [DATA_WIDTH-1:0]    table_cnn_ifc_zp_i,
    input signed   [DATA_WIDTH-1:0]    table_cnn_fltc_zp_i,
    input signed   [31:0]              table_cnn_mult_i,
    input          [5:0]               table_cnn_mult_shift_i,
    input signed   [31:0]              table_cnn_alphamult_i,
    input          [5:0]               table_cnn_alphamult_shift_i,
    input signed   [7:0]               table_cnn_zpy_i,
    input signed   [7:0]               table_cnn_qmin_i,
    input signed   [7:0]               table_cnn_qmax_i,
    input                              table_cnn_is_leaky_ReLU_i,

    output                              table_inf_vld_o,
    input                               table_inf_rdy_i,
    output          [7:0]               table_inf_ifheight_o,
    output          [10:0]              table_inf_ifchannel_o,
    output          [10:0]              table_inf_ofchannel_o,
    output          [3:0]               table_inf_hf_o,
    output          [2:0]               table_inf_stride_o,
    output          [1:0]               table_inf_padding_o,
    output          [2:0]               table_inf_ifparr_o,
    output          [1:0]               table_inf_oftile_o,
    output          [4:0]               table_inf_ofparr_o,
    output          [23:0]              table_inf_ifbaddr_o,
    output          [23:0]              table_inf_fltbaddr_o,
    output          [23:0]              table_inf_bias_baddr_o,
    output          [23:0]              table_inf_ofbaddr_o,
    output signed   [DATA_WIDTH-1:0]    table_inf_ifc_zp_o,
    output signed   [DATA_WIDTH-1:0]    table_inf_fltc_zp_o,
    output signed   [31:0]              table_inf_mult_o,
    output          [5:0]               table_inf_mult_shift_o,
    output signed   [31:0]              table_inf_alphamult_o,
    output          [5:0]               table_inf_alphamult_shift_o,
    output signed   [7:0]               table_inf_zpy_o,
    output signed   [7:0]               table_inf_qmin_o,
    output signed   [7:0]               table_inf_qmax_o,
    output                              table_inf_is_leaky_ReLU_o
);
    localparam TABLE_PAYLOAD_WIDTH = 246 + (2*DATA_WIDTH);

    wire [TABLE_PAYLOAD_WIDTH-1:0] table_cnn_data_in;
    wire [TABLE_PAYLOAD_WIDTH-1:0] table_cnn_data_out;
    wire fifo_full;
    wire fifo_empty;

    assign table_inf_vld_o      = !fifo_empty;
    assign table_cnn_rdy_o      = !fifo_full;
    assign table_cnn_data_in = {table_cnn_ifheight_i,
                                table_cnn_ifchannel_i,
                                table_cnn_ofchannel_i,
                                table_cnn_hf_i,
                                table_cnn_stride_i,
                                table_cnn_padding_i,
                                table_cnn_ifparr_i,
                                table_cnn_oftile_i,
                                table_cnn_ofparr_i,
                                table_cnn_ifbaddr_i,
                                table_cnn_fltbaddr_i,
                                table_cnn_bias_baddr_i,
                                table_cnn_ofbaddr_i,
                                table_cnn_ifc_zp_i,
                                table_cnn_fltc_zp_i,
                                table_cnn_mult_i,
                                table_cnn_mult_shift_i,
                                table_cnn_alphamult_i,
                                table_cnn_alphamult_shift_i,
                                table_cnn_zpy_i,
                                table_cnn_qmin_i,
                                table_cnn_qmax_i,
                                table_cnn_is_leaky_ReLU_i
                                };

    assign {table_inf_ifheight_o,
            table_inf_ifchannel_o,
            table_inf_ofchannel_o,
            table_inf_hf_o,
            table_inf_stride_o,
            table_inf_padding_o,
            table_inf_ifparr_o,
            table_inf_oftile_o,
            table_inf_ofparr_o,
            table_inf_ifbaddr_o,
            table_inf_fltbaddr_o,
            table_inf_bias_baddr_o,
            table_inf_ofbaddr_o,
            table_inf_ifc_zp_o,
            table_inf_fltc_zp_o,
            table_inf_mult_o,
            table_inf_mult_shift_o,
            table_inf_alphamult_o,
            table_inf_alphamult_shift_o,
            table_inf_zpy_o,
            table_inf_qmin_o,
            table_inf_qmax_o,
            table_inf_is_leaky_ReLU_o
            } = table_cnn_data_out;
    fifo_n #(
       .DATA_WIDTH(TABLE_PAYLOAD_WIDTH),
       .FF_TYPE(0),
       .FF_NUM(2),
       .FIFO_DEPTH(FIFO_DEPTH)
       ) fifo_bram_uut (
        .clk(clk),
        .data_i(table_cnn_data_in),
        .data_o(table_cnn_data_out),
        .rd_valid_i(table_inf_rdy_i),
        .wr_valid_i(table_cnn_vld_i),
        .clr_rd_i(1'b0),
        .clr_ff_i(1'b0),
        .empty_o(fifo_empty),
        .full_o(fifo_full),
        .almost_empty_o(),
        .almost_full_o(),
        .counter(),
        .rst_n(rst_n)
       );
endmodule
