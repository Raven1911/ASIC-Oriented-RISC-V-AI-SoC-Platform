`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 04/03/2026 06:12:01 PM
// Design Name: 
// Module Name: CNN_accel
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



module CNN_accel#(
    parameter DATA_WIDTH    = 8,
    parameter ACC_WIDTH     = 32,
    parameter IFBUF_DEPTH   = 224,
    parameter FLTBUF_DEPTH  = 3456,
    parameter COMP_DEPTH    = 12,
    parameter FIFO_DEPTH    = 12,
    parameter OFBUF_DEPTH   = 896,
    parameter K             = 4,
    parameter M             = 2,
    parameter PE_PER_PU     = 12,
    parameter PPDEPTH       = 224,
    parameter BURSTL_IFMAP = 8,
    parameter BURSTL_FILTER = 10,
    parameter BURSTL_BIAS = 7,
    parameter BURSTL_OFMAP = 8
)(
    input               clk,
    input               rst_n,

    // =========================================================
    // TABLE instruction interface
    // =========================================================
    input                               cnn_table_vld_i,
    output                              cnn_table_rdy_o,
    input           [7:0]               cnn_table_ifheight_i,
    input           [10:0]              cnn_table_ifchannel_i,
    input           [10:0]              cnn_table_ofchannel_i,
    input           [3:0]               cnn_table_hf_i,
    input           [2:0]               cnn_table_stride_i,
    input           [1:0]               cnn_table_padding_i,
    input           [2:0]               cnn_table_ifparr_i,
    input           [1:0]               cnn_table_oftile_i,
    input           [4:0]               cnn_table_ofparr_i,
    input           [23:0]              cnn_table_ifbaddr_i,
    input           [23:0]              cnn_table_fltbaddr_i,
    input           [23:0]              cnn_table_bias_baddr_i,
    input           [23:0]              cnn_table_ofbaddr_i,
    input  signed   [DATA_WIDTH-1:0]    cnn_table_ifc_zp_i,
    input  signed   [DATA_WIDTH-1:0]    cnn_table_fltc_zp_i,
    input  signed   [31:0]              cnn_table_mult_i,
    input           [5:0]               cnn_table_mult_shift_i,
    input  signed   [31:0]              cnn_table_alphamult_i,
    input           [5:0]               cnn_table_alphamult_shift_i,
    input  signed   [7:0]               cnn_table_zpy_i,
    input  signed   [7:0]               cnn_table_qmin_i,
    input  signed   [7:0]               cnn_table_qmax_i,
    input                               cnn_table_is_leaky_ReLU_i,

    // =========================================================
    // cnn cpu interface
    // =========================================================

    output                              cnn_cpu_accel_busy_o, //status
    input                               cnn_cpu_accel_start_i,
    output                              cnn_cpu_accel_done_o, //interupt
    input                               cnn_cpu_receive_interupt_i,

    // =========================================================
    // IFBUF DMA side
    // =========================================================
    input                   cnn_ifbuf_dma_rdycfg_i, //dma rdy to receive config from ifbuf
    input                   cnn_ifbuf_dma_vld_i, //dma has data to send ifbuf
    input  [DATA_WIDTH-1:0] cnn_ifbuf_dma_data_i,
    input                   cnn_ifbuf_dma_tlast_i,
    output                  cnn_ifbuf_dma_vldcfg_o, //ifbuf has valid config
    output [BURSTL_IFMAP-1:0]            cnn_ifbuf_dma_burst_o, //length of data, it will be align to even
    output [23:0]           cnn_ifbuf_dma_baddr_o, //base address of data need to read
    output                  cnn_ifbuf_dma_rdy_o,

    // =========================================================
    // FLTBUF DMA side
    // =========================================================
    input                   cnn_fltbuf_dma_rdycfg_i,
    input                   cnn_fltbuf_dma_vld_i,
    input  [DATA_WIDTH-1:0] cnn_fltbuf_dma_data_i,
    input                   cnn_fltbuf_dma_tlast_i,
    output                  cnn_fltbuf_dma_vldcfg_o,
    output [BURSTL_FILTER-1:0]            cnn_fltbuf_dma_burst_o,
    output [23:0]           cnn_fltbuf_dma_baddr_o,
    output                  cnn_fltbuf_dma_rdy_o,

    // =========================================================
    // BIAS BUF DMA side
    // =========================================================
    input                           cnn_bias_dma_rdycfg_i,
    output                          cnn_bias_dma_vldcfg_o,
    output          [BURSTL_BIAS-1:0]           cnn_bias_dma_burst_o, 
    output          [23:0]          cnn_bias_dma_baddr_o,
    input                           cnn_bias_dma_vld_i,
    input           [7:0]           cnn_bias_dma_data_i,
    input                           cnn_bias_dma_tlast_i,
    output                          cnn_bias_dma_rdy_o,
    // =========================================================
    // OFBUF DMA side
    // =========================================================
    input                           cnn_ofbuf_dma_rdycfg_i,
    output                          cnn_ofbuf_dma_vldcfg_o,
    output [BURSTL_OFMAP-1:0]       cnn_ofbuf_dma_burst_o,
    output [23:0]                   cnn_ofbuf_dma_baddr_o,
    output                          cnn_ofbuf_dma_vld_o,
    output [DATA_WIDTH-1:0]         cnn_ofbuf_dma_data_o,
    output                          cnn_ofbuf_dma_tlast_o,
    input                           cnn_ofbuf_dma_rdy_i,

    // =========================================================
    // Optional debug / status
    // =========================================================
    output                    cnn_comp_pa_done_compute_o,
    output                    cnn_ifbuf_comp_end_layer_o,
    output                    cnn_ifbuf_comp_end_layer_real_o, 
    output                    cnn_fltbuf_comp_donepass_o
);

    // =========================================================
    // Instruction table -> layer_info wires
    // =========================================================
    wire                            table_inf_vld_w;
    wire                            table_inf_rdy_w;
    wire [7:0]                      table_inf_ifheight_w;
    wire [10:0]                     table_inf_ifchannel_w;
    wire [10:0]                     table_inf_ofchannel_w;
    wire [3:0]                      table_inf_hf_w;
    wire [2:0]                      table_inf_stride_w;
    wire [1:0]                      table_inf_padding_w;
    wire [2:0]                      table_inf_ifparr_w;
    wire [1:0]                      table_inf_oftile_w;
    wire [4:0]                      table_inf_ofparr_w;
    wire [23:0]                     table_inf_ifbaddr_w;
    wire [23:0]                     table_inf_fltbaddr_w;
    wire [23:0]                     table_inf_bias_baddr_w;
    wire [23:0]                     table_inf_ofbaddr_w;
    wire signed [DATA_WIDTH-1:0]    table_inf_ifc_zp_w;
    wire signed [DATA_WIDTH-1:0]    table_inf_fltc_zp_w;
    wire signed [31:0]              table_inf_mult_w;
    wire [5:0]                      table_inf_mult_shift_w;
    wire signed [31:0]              table_inf_alphamult_w;
    wire [5:0]                      table_inf_alphamult_shift_w;
    wire signed [7:0]               table_inf_zpy_w;
    wire signed [7:0]               table_inf_qmin_w;
    wire signed [7:0]               table_inf_qmax_w;
    wire                            table_inf_is_leaky_ReLU_w;

    // =========================================================
    // Internal instruction wires driven by layer_info
    // =========================================================
    wire                            ifbuf_inf_vld_i;
    wire [23:0]                     ifbuf_inf_ifbaddr_i;
    wire [7:0]                      ifbuf_inf_ifwidth_i;
    wire [10:0]                     ifbuf_inf_channel_i;
    wire [3:0]                      ifbuf_inf_ifparr_i;
    wire [15:0]                     ifbuf_inf_ifsize_i;
    wire [6:0]                      ifbuf_inf_ifblock_i;
    wire [3:0]                      ifbuf_inf_oftiles_i;
    wire [3:0]                      ifbuf_inf_oftiles_tail_i;
    wire [7:0]                      ifbuf_inf_iftiles_i;
    wire [8:0]                      ifbuf_inf_wp_i;
    wire [1:0]                      ifbuf_inf_padding_i;
    wire signed [DATA_WIDTH-1:0]    ifbuf_inf_ifc_zp_i;
    wire                            ifbuf_inf_rdy_o;

    wire                            fltbuf_inf_vld_i;
    wire [23:0]                     fltbuf_inf_fltbaddr_i;
    wire [3:0]                      fltbuf_inf_ifparr_i;
    wire [3:0]                      fltbuf_inf_ifparr_tail_i;
    wire [6:0]                      fltbuf_inf_fltsize_i;
    wire [6:0]                      fltbuf_inf_ifblock_i;
    wire [4:0]                      fltbuf_inf_ofparr_i;
    wire [4:0]                      fltbuf_inf_ofparr_tail_i;
    wire [3:0]                      fltbuf_inf_oftiles_i;
    wire [3:0]                      fltbuf_inf_oftiles_tail_i;
    wire [7:0]                      fltbuf_inf_iftiles_i;
    wire                            fltbuf_inf_rdy_o;

    wire                            bias_inf_vld_i;
    wire                            bias_inf_rdy_o;
    wire [23:0]                     bias_inf_bias_baddr_i;
    wire [7:0]                      bias_inf_ofwidth_i;
    wire [10:0]                     bias_inf_ofchannel_i;
    wire [4:0]                      bias_inf_burstlen_i;
    wire [4:0]                      bias_inf_burstlen_tail_i;
    wire [4:0]                      bias_inf_burstlen_lane0_i;
    wire [4:0]                      bias_inf_burstlen_tail_lane0_i;

    wire                            comp_inf_rdy_o;
    wire                            comp_inf_vld_i;
    wire [3:0]                      comp_inf_hf_i;
    wire [2:0]                      comp_inf_stride_i;
    wire [1:0]                      comp_inf_padding_i;
    wire signed [DATA_WIDTH-1:0]    comp_inf_ifc_zp_i;
    wire signed [DATA_WIDTH-1:0]    comp_inf_fltc_zp_i;
    wire [7:0]                      comp_inf_ofwidth_i;
    wire signed [31:0]              comp_inf_mult_i;
    wire [5:0]                      comp_inf_mult_shift_i;
    wire signed [31:0]              comp_inf_alphamult_i;
    wire [5:0]                      comp_inf_alphamult_shift_i;
    wire signed [7:0]               comp_inf_zpy_i;
    wire signed [7:0]               comp_inf_qmin_i;
    wire signed [7:0]               comp_inf_qmax_i;
    wire                            comp_inf_is_leaky_ReLU_i;
    wire                            ofbuf_inf_vld_w;

    // =========================================================
    // Skid-buffered instruction channels from layer_info
    // =========================================================
    localparam IFBUF_INF_PAYLOAD_WIDTH  = 96 + DATA_WIDTH;
    localparam FLTBUF_INF_PAYLOAD_WIDTH = 79 + DATA_WIDTH;
    localparam BIAS_INF_PAYLOAD_WIDTH   = 63;
    localparam COMP_INF_PAYLOAD_WIDTH   = 118 + (2*DATA_WIDTH);
    localparam OFBUF_INF_PAYLOAD_WIDTH  = 99;

    // Raw layer_info -> IFBUF instruction channel
    wire                            ifbuf_inf_vld_li_w;
    wire                            ifbuf_inf_rdy_li_w;
    wire [23:0]                     ifbuf_inf_ifbaddr_li_w;
    wire [7:0]                      ifbuf_inf_ifwidth_li_w;
    wire [10:0]                     ifbuf_inf_channel_li_w;
    wire [3:0]                      ifbuf_inf_ifparr_li_w;
    wire [15:0]                     ifbuf_inf_ifsize_li_w;
    wire [6:0]                      ifbuf_inf_ifblock_li_w;
    wire [3:0]                      ifbuf_inf_oftiles_li_w;
    wire [3:0]                      ifbuf_inf_oftiles_tail_li_w;
    wire [7:0]                      ifbuf_inf_iftiles_li_w;
    wire [8:0]                      ifbuf_inf_wp_li_w;
    wire [1:0]                      ifbuf_inf_padding_li_w;
    wire signed [DATA_WIDTH-1:0]    ifbuf_inf_ifc_zp_li_w;
    wire [IFBUF_INF_PAYLOAD_WIDTH-1:0] ifbuf_inf_payload_li_w;
    wire [IFBUF_INF_PAYLOAD_WIDTH-1:0] ifbuf_inf_payload_w;

    // Raw layer_info -> FLTBUF instruction channel
    wire                            fltbuf_inf_vld_li_w;
    wire                            fltbuf_inf_rdy_li_w;
    wire [23:0]                     fltbuf_inf_fltbaddr_li_w;
    wire [3:0]                      fltbuf_inf_ifparr_li_w;
    wire [3:0]                      fltbuf_inf_ifparr_tail_li_w;
    wire [6:0]                      fltbuf_inf_fltsize_li_w;
    wire [6:0]                      fltbuf_inf_ifblock_li_w;
    wire [4:0]                      fltbuf_inf_ofparr_li_w;
    wire [4:0]                      fltbuf_inf_ofparr_tail_li_w;
    wire [3:0]                      fltbuf_inf_oftiles_li_w;
    wire [3:0]                      fltbuf_inf_oftiles_tail_li_w;
    wire [7:0]                      fltbuf_inf_iftiles_li_w;
    wire [7:0]                      fltbuf_inf_height_w;
    wire signed [DATA_WIDTH-1:0]    fltbuf_inf_zp_w;
    wire [FLTBUF_INF_PAYLOAD_WIDTH-1:0] fltbuf_inf_payload_li_w;
    wire [FLTBUF_INF_PAYLOAD_WIDTH-1:0] fltbuf_inf_payload_w;

    // Raw layer_info -> BIASBUF instruction channel
    wire                            bias_inf_vld_li_w;
    wire                            bias_inf_rdy_li_w;
    wire [23:0]                     bias_inf_bias_baddr_li_w;
    wire [7:0]                      bias_inf_ofwidth_li_w;
    wire [10:0]                     bias_inf_ofchannel_li_w;
    wire [4:0]                      bias_inf_burstlen_li_w;
    wire [4:0]                      bias_inf_burstlen_tail_li_w;
    wire [4:0]                      bias_inf_burstlen_lane0_li_w;
    wire [4:0]                      bias_inf_burstlen_tail_lane0_li_w;
    wire [BIAS_INF_PAYLOAD_WIDTH-1:0] bias_inf_payload_li_w;
    wire [BIAS_INF_PAYLOAD_WIDTH-1:0] bias_inf_payload_w;

    // Raw layer_info -> COMP instruction channel
    wire                            comp_inf_vld_li_w;
    wire                            comp_inf_rdy_li_w;
    wire [3:0]                      comp_inf_hf_li_w;
    wire [2:0]                      comp_inf_stride_li_w;
    wire [1:0]                      comp_inf_padding_li_w;
    wire signed [DATA_WIDTH-1:0]    comp_inf_ifc_zp_li_w;
    wire signed [DATA_WIDTH-1:0]    comp_inf_fltc_zp_li_w;
    wire [7:0]                      comp_inf_ofwidth_li_w;
    wire signed [31:0]              comp_inf_mult_li_w;
    wire [5:0]                      comp_inf_mult_shift_li_w;
    wire signed [31:0]              comp_inf_alphamult_li_w;
    wire [5:0]                      comp_inf_alphamult_shift_li_w;
    wire signed [7:0]               comp_inf_zpy_li_w;
    wire signed [7:0]               comp_inf_qmin_li_w;
    wire signed [7:0]               comp_inf_qmax_li_w;
    wire                            comp_inf_is_leaky_ReLU_li_w;
    wire [COMP_INF_PAYLOAD_WIDTH-1:0] comp_inf_payload_li_w;
    wire [COMP_INF_PAYLOAD_WIDTH-1:0] comp_inf_payload_w;

    // Raw layer_info -> OFBUF instruction channel
    wire                            ofbuf_inf_vld_li_w;
    wire                            ofbuf_inf_rdy_li_w;
    wire [23:0]                     ofbuf_inf_ofbaddr_l0_li_w;
    wire [23:0]                     ofbuf_inf_ofbaddr_l1_li_w;
    wire [7:0]                      ofbuf_inf_ofwidth_li_w;
    wire [15:0]                     ofbuf_inf_ofsize_li_w;
    wire [6:0]                      ofbuf_inf_ofblock_li_w;
    wire [4:0]                      ofbuf_inf_ofc_bl_l0_li_w;
    wire [4:0]                      ofbuf_inf_ofc_bl_tail_l0_li_w;
    wire [4:0]                      ofbuf_inf_ofc_bl_l1_li_w;
    wire [4:0]                      ofbuf_inf_ofc_bl_tail_l1_li_w;
    wire [OFBUF_INF_PAYLOAD_WIDTH-1:0] ofbuf_inf_payload_li_w;
    wire [OFBUF_INF_PAYLOAD_WIDTH-1:0] ofbuf_inf_payload_w;
    wire [23:0]                     ofbuf_inf_ofbaddr_l0_w;
    wire [23:0]                     ofbuf_inf_ofbaddr_l1_w;
    wire [7:0]                      ofbuf_inf_ofwidth_w;
    wire [15:0]                     ofbuf_inf_ofsize_w;
    wire [6:0]                      ofbuf_inf_ofblock_w;
    wire [4:0]                      ofbuf_inf_ofc_bl_l0_w;
    wire [4:0]                      ofbuf_inf_ofc_bl_tail_l0_w;
    wire [4:0]                      ofbuf_inf_ofc_bl_l1_w;
    wire [4:0]                      ofbuf_inf_ofc_bl_tail_l1_w;
    wire                            ofbuf_inf_rdy_w;

    // =========================================================
    // Internal datapath wires
    // =========================================================
    wire                    ifbuf_comp_vld_w;
    wire [K*DATA_WIDTH-1:0] ifbuf_comp_data_w;
    wire                    ifbuf_comp_end_row_w;
    wire                    ifbuf_comp_end_row_circle_w;
    wire                    ifbuf_comp_end_depth_w;
    wire                    ifbuf_comp_end_layer_w;
    wire                    ifbuf_comp_end_layer_real_w;
    wire                    comp_ifbuf_rdy_w;

    wire [K*DATA_WIDTH+4:0] ifbuf_comp_payload_w;
    wire [K*DATA_WIDTH+4:0] ifbuf_comp_payload_buf_w;
    wire                    ifbuf_comp_vld_buf_w;
    wire                    ifbuf_comp_rdy_buf_w;
    wire                    ifbuf_comp_end_row_buf_w;
    wire                    ifbuf_comp_end_row_circle_buf_w;
    wire                    ifbuf_comp_end_depth_buf_w;
    wire                    ifbuf_comp_end_layer_buf_w;
    wire                    ifbuf_comp_end_layer_real_buf_w;
    wire [K*DATA_WIDTH-1:0] ifbuf_comp_data_buf_w;

    wire [K*M-1:0]            fltbuf_comp_vld_w;
    wire [K*M*DATA_WIDTH-1:0] fltbuf_comp_data_w;
    wire                      fltbuf_comp_donepass_w;
    wire [M-1:0]              comp_fltbuf_rdy_w;
    wire                      fltbuf_comp_rdy_w;

    wire [M-1:0]            comp_ofbuf_vld_w;
    wire [M-1:0]            comp_ofbuf_rdy_w;
    wire [M*DATA_WIDTH-1:0]  comp_ofbuf_data_w;
    wire [M-1:0]            ofbuf_comp_vld_w;
    wire [M-1:0]            ofbuf_comp_rdy_w;
    wire [M*DATA_WIDTH-1:0] ofbuf_comp_data_w;

    // reg [3:0]               comp_inf_hf_reg; //height of channel of filter
    // reg [2:0]               comp_inf_stride_reg;
    // reg [1:0]               comp_inf_padding_reg;
    // reg signed [DATA_WIDTH-1:0]    comp_inf_ifc_zp_reg; //zero point of ifmap
    // reg signed [DATA_WIDTH-1:0]    comp_inf_fltc_zp_reg;

    // always @(posedge clk) begin
    //     comp_inf_hf_reg         <= comp_inf_hf_i;
    //     comp_inf_stride_reg     <= comp_inf_stride_i;
    //     comp_inf_padding_reg    <= comp_inf_padding_i;
    //     comp_inf_ifc_zp_reg     <= comp_inf_ifc_zp_i;
    //     comp_inf_fltc_zp_reg    <= comp_inf_fltc_zp_i;
    // end

    // Current filter_buf RTL only exposes one scalar ready input.
    // Best-effort integration: only pop weights when both PA branches are ready.
    //===================================================================================
    //===================================================================================
    reg accel_busy;
    reg accel_done;
    wire accel_start;
    assign cnn_cpu_accel_busy_o = accel_busy;
    posedge_detection f(
        .clk(clk),
        .rst_n(rst_n),
        .signal_i(cnn_cpu_accel_start_i),
        .signal_o(accel_start)
    );
    assign cnn_cpu_accel_done_o = accel_done;
    always @(posedge clk) begin
        if(!rst_n) begin
            accel_busy <=  0;
        end else begin
            if(accel_start) accel_busy <=  1;
            else if(accel_done) accel_busy <= 0;
        end
    end
    always @(posedge clk) begin
        if(!rst_n) begin
            accel_done <=  0;
        end else begin
            if(cnn_cpu_receive_interupt_i) accel_done <= 0;
            else if(!(ofbuf_inf_vld_w || table_inf_vld_w) && ofbuf_inf_rdy_w && accel_busy) accel_done <=  1;
        end
    end
    //===================================================================================
    //===================================================================================
    assign fltbuf_comp_rdy_w = &comp_fltbuf_rdy_w;

    assign cnn_ifbuf_comp_end_layer_o = ifbuf_comp_end_layer_w;
    assign cnn_ifbuf_comp_end_layer_real_o = ifbuf_comp_end_layer_real_w;
    assign cnn_fltbuf_comp_donepass_o = fltbuf_comp_donepass_w;

    // =========================================================
    // INSTRUCTION TABLE: CNN_accel -> instruction_table -> layer_info
    // =========================================================
    instruction_table #(
        .DATA_WIDTH(DATA_WIDTH),
        .FIFO_DEPTH(12)
    ) u_instruction_table (
        .clk(clk),
        .rst_n(rst_n),

        .table_cnn_vld_i(cnn_table_vld_i),
        .table_cnn_rdy_o(cnn_table_rdy_o),
        .table_cnn_ifheight_i(cnn_table_ifheight_i),
        .table_cnn_ifchannel_i(cnn_table_ifchannel_i),
        .table_cnn_ofchannel_i(cnn_table_ofchannel_i),
        .table_cnn_hf_i(cnn_table_hf_i),
        .table_cnn_stride_i(cnn_table_stride_i),
        .table_cnn_padding_i(cnn_table_padding_i),
        .table_cnn_ifparr_i(cnn_table_ifparr_i),
        .table_cnn_oftile_i(cnn_table_oftile_i),
        .table_cnn_ofparr_i(cnn_table_ofparr_i),
        .table_cnn_ifbaddr_i(cnn_table_ifbaddr_i),
        .table_cnn_fltbaddr_i(cnn_table_fltbaddr_i),
        .table_cnn_bias_baddr_i(cnn_table_bias_baddr_i),
        .table_cnn_ofbaddr_i(cnn_table_ofbaddr_i),
        .table_cnn_ifc_zp_i(cnn_table_ifc_zp_i),
        .table_cnn_fltc_zp_i(cnn_table_fltc_zp_i),
        .table_cnn_mult_i(cnn_table_mult_i),
        .table_cnn_mult_shift_i(cnn_table_mult_shift_i),
        .table_cnn_alphamult_i(cnn_table_alphamult_i),
        .table_cnn_alphamult_shift_i(cnn_table_alphamult_shift_i),
        .table_cnn_zpy_i(cnn_table_zpy_i),
        .table_cnn_qmin_i(cnn_table_qmin_i),
        .table_cnn_qmax_i(cnn_table_qmax_i),
        .table_cnn_is_leaky_ReLU_i(cnn_table_is_leaky_ReLU_i),

        .table_inf_vld_o(table_inf_vld_w),
        .table_inf_rdy_i(table_inf_rdy_w && accel_busy), //change .table_inf_rdy_i(table_inf_rdy_w),
        .table_inf_ifheight_o(table_inf_ifheight_w),
        .table_inf_ifchannel_o(table_inf_ifchannel_w),
        .table_inf_ofchannel_o(table_inf_ofchannel_w),
        .table_inf_hf_o(table_inf_hf_w),
        .table_inf_stride_o(table_inf_stride_w),
        .table_inf_padding_o(table_inf_padding_w),
        .table_inf_ifparr_o(table_inf_ifparr_w),
        .table_inf_oftile_o(table_inf_oftile_w),
        .table_inf_ofparr_o(table_inf_ofparr_w),
        .table_inf_ifbaddr_o(table_inf_ifbaddr_w),
        .table_inf_fltbaddr_o(table_inf_fltbaddr_w),
        .table_inf_bias_baddr_o(table_inf_bias_baddr_w),
        .table_inf_ofbaddr_o(table_inf_ofbaddr_w),
        .table_inf_ifc_zp_o(table_inf_ifc_zp_w),
        .table_inf_fltc_zp_o(table_inf_fltc_zp_w),
        .table_inf_mult_o(table_inf_mult_w),
        .table_inf_mult_shift_o(table_inf_mult_shift_w),
        .table_inf_alphamult_o(table_inf_alphamult_w),
        .table_inf_alphamult_shift_o(table_inf_alphamult_shift_w),
        .table_inf_zpy_o(table_inf_zpy_w),
        .table_inf_qmin_o(table_inf_qmin_w),
        .table_inf_qmax_o(table_inf_qmax_w),
        .table_inf_is_leaky_ReLU_o(table_inf_is_leaky_ReLU_w)
    );

    // =========================================================
    // LAYER INFO
    // =========================================================
    layer_info #(
        .DATA_WIDTH(DATA_WIDTH)
    ) u_layer_info (
        .clk(clk),
        .rst_n(rst_n),

        .inf_table_vld_i(table_inf_vld_w && accel_busy),//change  .inf_table_vld_i(table_inf_vld_w),
        .inf_table_rdy_o(table_inf_rdy_w),
        .inf_table_ifheight_i(table_inf_ifheight_w),
        .inf_table_ifchannel_i(table_inf_ifchannel_w),
        .inf_table_ofchannel_i(table_inf_ofchannel_w),
        .inf_table_hf_i(table_inf_hf_w),
        .inf_table_stride_i(table_inf_stride_w),
        .inf_table_padding_i(table_inf_padding_w),
        .inf_table_ifparr_i(table_inf_ifparr_w),
        .inf_table_oftile_i(table_inf_oftile_w),
        .inf_table_ofparr_i(table_inf_ofparr_w),
        .inf_table_ifbaddr_i(table_inf_ifbaddr_w),
        .inf_table_fltbaddr_i(table_inf_fltbaddr_w),
        .inf_table_bias_baddr_i(table_inf_bias_baddr_w),
        .inf_table_ofbaddr_i(table_inf_ofbaddr_w),
        .inf_table_ifc_zp_i(table_inf_ifc_zp_w),
        .inf_table_fltc_zp_i(table_inf_fltc_zp_w),
        .inf_table_mult_i(table_inf_mult_w),
        .inf_table_mult_shift_i(table_inf_mult_shift_w),
        .inf_table_alphamult_i(table_inf_alphamult_w),
        .inf_table_alphamult_shift_i(table_inf_alphamult_shift_w),
        .inf_table_zpy_i(table_inf_zpy_w),
        .inf_table_qmin_i(table_inf_qmin_w),
        .inf_table_qmax_i(table_inf_qmax_w),
        .inf_table_is_leaky_ReLU_i(table_inf_is_leaky_ReLU_w),

        .inf_ifbuf_rdy_i(ifbuf_inf_rdy_li_w),
        .inf_ifbuf_vld_o(ifbuf_inf_vld_li_w),
        .inf_ifbuf_ifbaddr_o(ifbuf_inf_ifbaddr_li_w),
        .inf_ifbuf_ifwidth_o(ifbuf_inf_ifwidth_li_w),
        .inf_ifbuf_ifchannel_o(ifbuf_inf_channel_li_w),
        .inf_ifbuf_ifparr_o(ifbuf_inf_ifparr_li_w),
        .inf_ifbuf_ifsize_o(ifbuf_inf_ifsize_li_w),
        .inf_ifbuf_ifblock_o(ifbuf_inf_ifblock_li_w),
        .inf_ifbuf_oftiles_o(ifbuf_inf_oftiles_li_w),
        .inf_ifbuf_oftiles_tail_o(ifbuf_inf_oftiles_tail_li_w),
        .inf_ifbuf_iftiles_o(ifbuf_inf_iftiles_li_w),
        .inf_ifbuf_wp_o(ifbuf_inf_wp_li_w),
        .inf_ifbuf_padding_o(ifbuf_inf_padding_li_w),
        .inf_ifbuf_ifc_zp_o(ifbuf_inf_ifc_zp_li_w),

        .inf_fltbuf_rdy_i(fltbuf_inf_rdy_li_w),
        .inf_fltbuf_vld_o(fltbuf_inf_vld_li_w),
        .inf_fltbuf_fltbaddr_o(fltbuf_inf_fltbaddr_li_w),
        .inf_fltbuf_ifparr_o(fltbuf_inf_ifparr_li_w),
        .inf_fltbuf_ifparr_tail_o(fltbuf_inf_ifparr_tail_li_w),
        .inf_fltbuf_fltsize_o(fltbuf_inf_fltsize_li_w),
        .inf_fltbuf_ifblock_o(fltbuf_inf_ifblock_li_w),
        .inf_fltbuf_ofparr_o(fltbuf_inf_ofparr_li_w),
        .inf_fltbuf_ofparr_tail_o(fltbuf_inf_ofparr_tail_li_w),
        .inf_fltbuf_oftiles_o(fltbuf_inf_oftiles_li_w),
        .inf_fltbuf_oftiles_tail_o(fltbuf_inf_oftiles_tail_li_w),
        .inf_fltbuf_iftiles_o(fltbuf_inf_iftiles_li_w),

        .inf_bias_rdy_i(bias_inf_rdy_li_w),
        .inf_bias_vld_o(bias_inf_vld_li_w),
        .inf_bias_bias_baddr_o(bias_inf_bias_baddr_li_w),
        .inf_bias_ofwidth_o(bias_inf_ofwidth_li_w),
        .inf_bias_ofchannel_o(bias_inf_ofchannel_li_w),
        .inf_bias_burstlen_o(bias_inf_burstlen_li_w),
        .inf_bias_burstlen_tail_o(bias_inf_burstlen_tail_li_w),
        .inf_bias_burstlen_lane0_o(bias_inf_burstlen_lane0_li_w),
        .inf_bias_burstlen_tail_lane0_o(bias_inf_burstlen_tail_lane0_li_w),

        .inf_comp_rdy_i(comp_inf_rdy_li_w),
        .inf_comp_vld_o(comp_inf_vld_li_w),
        .inf_comp_hf_o(comp_inf_hf_li_w),
        .inf_comp_stride_o(comp_inf_stride_li_w),
        .inf_comp_padding_o(comp_inf_padding_li_w),
        .inf_comp_ifc_zp_o(comp_inf_ifc_zp_li_w),
        .inf_comp_fltc_zp_o(comp_inf_fltc_zp_li_w),
        .inf_comp_ofwidth_o(comp_inf_ofwidth_li_w),
        .inf_comp_mult_o(comp_inf_mult_li_w),
        .inf_comp_mult_shift_o(comp_inf_mult_shift_li_w),
        .inf_comp_alphamult_o(comp_inf_alphamult_li_w),
        .inf_comp_alphamult_shift_o(comp_inf_alphamult_shift_li_w),
        .inf_comp_zpy_o(comp_inf_zpy_li_w),
        .inf_comp_qmin_o(comp_inf_qmin_li_w),
        .inf_comp_qmax_o(comp_inf_qmax_li_w),
        .inf_comp_is_leaky_ReLU_o(comp_inf_is_leaky_ReLU_li_w),

        .inf_ofbuf_rdy_i(ofbuf_inf_rdy_li_w),
        .inf_ofbuf_vld_o(ofbuf_inf_vld_li_w),
        .inf_ofbuf_ofbaddr_l0_o(ofbuf_inf_ofbaddr_l0_li_w),
        .inf_ofbuf_ofbaddr_l1_o(ofbuf_inf_ofbaddr_l1_li_w),
        .inf_ofbuf_ofwidth_o(ofbuf_inf_ofwidth_li_w),
        .inf_ofbuf_ofsize_o(ofbuf_inf_ofsize_li_w),
        .inf_ofbuf_ofblock_o(ofbuf_inf_ofblock_li_w),
        .inf_ofbuf_ofc_bl_l0_o(ofbuf_inf_ofc_bl_l0_li_w),
        .inf_ofbuf_ofc_bl_tail_l0_o(ofbuf_inf_ofc_bl_tail_l0_li_w),
        .inf_ofbuf_ofc_bl_l1_o(ofbuf_inf_ofc_bl_l1_li_w),
        .inf_ofbuf_ofc_bl_tail_l1_o(ofbuf_inf_ofc_bl_tail_l1_li_w)
    );

    // =========================================================
    // SKID BUFFERS: layer_info -> IFBUF / FLTBUF / BIASBUF / COMP / OFBUF
    // =========================================================
    assign ifbuf_inf_payload_li_w = {
        ifbuf_inf_ifbaddr_li_w,
        ifbuf_inf_ifwidth_li_w,
        ifbuf_inf_channel_li_w,
        ifbuf_inf_ifparr_li_w,
        ifbuf_inf_ifsize_li_w,
        ifbuf_inf_ifblock_li_w,
        ifbuf_inf_oftiles_li_w,
        ifbuf_inf_oftiles_tail_li_w,
        ifbuf_inf_iftiles_li_w,
        ifbuf_inf_wp_li_w,
        ifbuf_inf_padding_li_w,
        ifbuf_inf_ifc_zp_li_w
    };

    skid_buffer #(
        .SBUF_TYPE(0),
        .DATA_WIDTH(IFBUF_INF_PAYLOAD_WIDTH)
    ) u_skid_layer_info_ifbuf (
        .clk(clk),
        .rst_n(rst_n),

        .bwd_data_i(ifbuf_inf_payload_li_w),
        .bwd_valid_i(ifbuf_inf_vld_li_w),
        .fwd_ready_i(ifbuf_inf_rdy_o),

        .fwd_data_o(ifbuf_inf_payload_w),
        .bwd_ready_o(ifbuf_inf_rdy_li_w),
        .fwd_valid_o(ifbuf_inf_vld_i)
    );

    assign {
        ifbuf_inf_ifbaddr_i,
        ifbuf_inf_ifwidth_i,
        ifbuf_inf_channel_i,
        ifbuf_inf_ifparr_i,
        ifbuf_inf_ifsize_i,
        ifbuf_inf_ifblock_i,
        ifbuf_inf_oftiles_i,
        ifbuf_inf_oftiles_tail_i,
        ifbuf_inf_iftiles_i,
        ifbuf_inf_wp_i,
        ifbuf_inf_padding_i,
        ifbuf_inf_ifc_zp_i
    } = ifbuf_inf_payload_w;

    assign fltbuf_inf_payload_li_w = {
        fltbuf_inf_fltbaddr_li_w,
        fltbuf_inf_ifparr_li_w,
        fltbuf_inf_ifparr_tail_li_w,
        fltbuf_inf_fltsize_li_w,
        fltbuf_inf_ifblock_li_w,
        fltbuf_inf_ofparr_li_w,
        fltbuf_inf_ofparr_tail_li_w,
        fltbuf_inf_oftiles_li_w,
        fltbuf_inf_oftiles_tail_li_w,
        fltbuf_inf_iftiles_li_w,
        ifbuf_inf_ifwidth_li_w,
        comp_inf_fltc_zp_li_w
    };

    skid_buffer #(
        .SBUF_TYPE(0),
        .DATA_WIDTH(FLTBUF_INF_PAYLOAD_WIDTH)
    ) u_skid_layer_info_fltbuf (
        .clk(clk),
        .rst_n(rst_n),

        .bwd_data_i(fltbuf_inf_payload_li_w),
        .bwd_valid_i(fltbuf_inf_vld_li_w),
        .fwd_ready_i(fltbuf_inf_rdy_o),

        .fwd_data_o(fltbuf_inf_payload_w),
        .bwd_ready_o(fltbuf_inf_rdy_li_w),
        .fwd_valid_o(fltbuf_inf_vld_i)
    );

    assign {
        fltbuf_inf_fltbaddr_i,
        fltbuf_inf_ifparr_i,
        fltbuf_inf_ifparr_tail_i,
        fltbuf_inf_fltsize_i,
        fltbuf_inf_ifblock_i,
        fltbuf_inf_ofparr_i,
        fltbuf_inf_ofparr_tail_i,
        fltbuf_inf_oftiles_i,
        fltbuf_inf_oftiles_tail_i,
        fltbuf_inf_iftiles_i,
        fltbuf_inf_height_w,
        fltbuf_inf_zp_w
    } = fltbuf_inf_payload_w;

    assign bias_inf_payload_li_w = {
        bias_inf_bias_baddr_li_w,
        bias_inf_ofwidth_li_w,
        bias_inf_ofchannel_li_w,
        bias_inf_burstlen_li_w,
        bias_inf_burstlen_tail_li_w,
        bias_inf_burstlen_lane0_li_w,
        bias_inf_burstlen_tail_lane0_li_w
    };

    skid_buffer #(
        .SBUF_TYPE(0),
        .DATA_WIDTH(BIAS_INF_PAYLOAD_WIDTH)
    ) u_skid_layer_info_biasbuf (
        .clk(clk),
        .rst_n(rst_n),

        .bwd_data_i(bias_inf_payload_li_w),
        .bwd_valid_i(bias_inf_vld_li_w),
        .fwd_ready_i(bias_inf_rdy_o),

        .fwd_data_o(bias_inf_payload_w),
        .bwd_ready_o(bias_inf_rdy_li_w),
        .fwd_valid_o(bias_inf_vld_i)
    );

    assign {
        bias_inf_bias_baddr_i,
        bias_inf_ofwidth_i,
        bias_inf_ofchannel_i,
        bias_inf_burstlen_i,
        bias_inf_burstlen_tail_i,
        bias_inf_burstlen_lane0_i,
        bias_inf_burstlen_tail_lane0_i
    } = bias_inf_payload_w;

    assign comp_inf_payload_li_w = {
        comp_inf_hf_li_w,
        comp_inf_stride_li_w,
        comp_inf_padding_li_w,
        comp_inf_ifc_zp_li_w,
        comp_inf_fltc_zp_li_w,
        comp_inf_ofwidth_li_w,
        comp_inf_mult_li_w,
        comp_inf_mult_shift_li_w,
        comp_inf_alphamult_li_w,
        comp_inf_alphamult_shift_li_w,
        comp_inf_zpy_li_w,
        comp_inf_qmin_li_w,
        comp_inf_qmax_li_w,
        comp_inf_is_leaky_ReLU_li_w
    };

    skid_buffer #(
        .SBUF_TYPE(0),
        .DATA_WIDTH(COMP_INF_PAYLOAD_WIDTH)
    ) u_skid_layer_info_comp (
        .clk(clk),
        .rst_n(rst_n),

        .bwd_data_i(comp_inf_payload_li_w),
        .bwd_valid_i(comp_inf_vld_li_w),
        .fwd_ready_i(comp_inf_rdy_o),

        .fwd_data_o(comp_inf_payload_w),
        .bwd_ready_o(comp_inf_rdy_li_w),
        .fwd_valid_o(comp_inf_vld_i)
    );

    assign {
        comp_inf_hf_i,
        comp_inf_stride_i,
        comp_inf_padding_i,
        comp_inf_ifc_zp_i,
        comp_inf_fltc_zp_i,
        comp_inf_ofwidth_i,
        comp_inf_mult_i,
        comp_inf_mult_shift_i,
        comp_inf_alphamult_i,
        comp_inf_alphamult_shift_i,
        comp_inf_zpy_i,
        comp_inf_qmin_i,
        comp_inf_qmax_i,
        comp_inf_is_leaky_ReLU_i
    } = comp_inf_payload_w;

    assign ofbuf_inf_payload_li_w = {
        ofbuf_inf_ofbaddr_l0_li_w,
        ofbuf_inf_ofbaddr_l1_li_w,
        ofbuf_inf_ofwidth_li_w,
        ofbuf_inf_ofsize_li_w,
        ofbuf_inf_ofblock_li_w,
        ofbuf_inf_ofc_bl_l0_li_w,
        ofbuf_inf_ofc_bl_tail_l0_li_w,
        ofbuf_inf_ofc_bl_l1_li_w,
        ofbuf_inf_ofc_bl_tail_l1_li_w
    };

    skid_buffer #(
        .SBUF_TYPE(0),
        .DATA_WIDTH(OFBUF_INF_PAYLOAD_WIDTH)
    ) u_skid_layer_info_ofbuf (
        .clk(clk),
        .rst_n(rst_n),

        .bwd_data_i(ofbuf_inf_payload_li_w),
        .bwd_valid_i(ofbuf_inf_vld_li_w),
        .fwd_ready_i(ofbuf_inf_rdy_w),

        .fwd_data_o(ofbuf_inf_payload_w),
        .bwd_ready_o(ofbuf_inf_rdy_li_w),
        .fwd_valid_o(ofbuf_inf_vld_w)
    );

    assign {
        ofbuf_inf_ofbaddr_l0_w,
        ofbuf_inf_ofbaddr_l1_w,
        ofbuf_inf_ofwidth_w,
        ofbuf_inf_ofsize_w,
        ofbuf_inf_ofblock_w,
        ofbuf_inf_ofc_bl_l0_w,
        ofbuf_inf_ofc_bl_tail_l0_w,
        ofbuf_inf_ofc_bl_l1_w,
        ofbuf_inf_ofc_bl_tail_l1_w
    } = ofbuf_inf_payload_w;

    // =========================================================
    // IFBUF
    // =========================================================
    ifbuf #(
        .DATA_WIDTH(DATA_WIDTH),
        .DEPTH(IFBUF_DEPTH),
        .K(K)
    ) u_ifbuf (
        .clk(clk),
        .rst_n(rst_n),

        .ifbuf_inf_vld_i(ifbuf_inf_vld_i),
        .ifbuf_inf_ifbaddr_i(ifbuf_inf_ifbaddr_i),
        .ifbuf_inf_ifparr_i(ifbuf_inf_ifparr_i),
        .ifbuf_inf_ifsize_i(ifbuf_inf_ifsize_i),
        .ifbuf_inf_channel_i(ifbuf_inf_channel_i),
        .ifbuf_inf_ifwidth_i(ifbuf_inf_ifwidth_i),
        .ifbuf_inf_ifblock_i(ifbuf_inf_ifblock_i),
        .ifbuf_inf_oftiles_i(ifbuf_inf_oftiles_i),
        .ifbuf_inf_oftiles_tail_i(ifbuf_inf_oftiles_tail_i),
        .ifbuf_inf_iftiles_i(ifbuf_inf_iftiles_i),
        .ifbuf_inf_wp_i(ifbuf_inf_wp_i),
        .ifbuf_inf_padding_i(ifbuf_inf_padding_i),
        .ifbuf_inf_ifc_zp_i(ifbuf_inf_ifc_zp_i),
        .ifbuf_inf_rdy_o(ifbuf_inf_rdy_o),

        .ifbuf_dma_rdycfg_i(cnn_ifbuf_dma_rdycfg_i),
        .ifbuf_dma_vld_i(cnn_ifbuf_dma_vld_i),
        .ifbuf_dma_data_i(cnn_ifbuf_dma_data_i),
        .ifbuf_dma_tlast_i(cnn_ifbuf_dma_tlast_i),
        .ifbuf_dma_vldcfg_o(cnn_ifbuf_dma_vldcfg_o),
        .ifbuf_dma_burst_o(cnn_ifbuf_dma_burst_o),
        .ifbuf_dma_baddr_o(cnn_ifbuf_dma_baddr_o),
        .ifbuf_dma_rdy_o(cnn_ifbuf_dma_rdy_o),

        .ifbuf_comp_rdy_i(comp_ifbuf_rdy_w),
        .ifbuf_comp_vld_o(ifbuf_comp_vld_w),
        .ifbuf_comp_data_o(ifbuf_comp_data_w),
        .ifbuf_comp_end_row_o(ifbuf_comp_end_row_w),
        .ifbuf_comp_end_row_circle_o(ifbuf_comp_end_row_circle_w),
        .ifbuf_comp_end_depth_o(ifbuf_comp_end_depth_w),
        .ifbuf_comp_end_layer_o(ifbuf_comp_end_layer_w),
        .ifbuf_comp_end_layer_real_o(ifbuf_comp_end_layer_real_w)
    );

    assign ifbuf_comp_payload_w = {
        ifbuf_comp_end_layer_w,
        ifbuf_comp_end_layer_real_w,
        ifbuf_comp_end_depth_w,
        ifbuf_comp_end_row_circle_w,
        ifbuf_comp_end_row_w,
        ifbuf_comp_data_w
    };

    
    skid_buffer #(
        .SBUF_TYPE(0),
        .DATA_WIDTH(K*DATA_WIDTH + 5)
    ) skide_ifbuf_computation (
        .clk(clk),
        .rst_n(rst_n),

        .bwd_data_i(ifbuf_comp_payload_w),
        .bwd_valid_i(ifbuf_comp_vld_w),
        .fwd_ready_i(ifbuf_comp_rdy_buf_w),

        .fwd_data_o(ifbuf_comp_payload_buf_w),
        .bwd_ready_o(comp_ifbuf_rdy_w),
        .fwd_valid_o(ifbuf_comp_vld_buf_w)
    );
    assign {
        ifbuf_comp_end_layer_buf_w,
        ifbuf_comp_end_layer_real_buf_w,
        ifbuf_comp_end_depth_buf_w,
        ifbuf_comp_end_row_circle_buf_w,
        ifbuf_comp_end_row_buf_w,
        ifbuf_comp_data_buf_w
    } = ifbuf_comp_payload_buf_w;

    // =========================================================
    // FLTBUF
    // =========================================================
   
    filter_buf #(
        .DATA_WIDTH(DATA_WIDTH),
        .DEPTH(FLTBUF_DEPTH),
        .K(K),
        .M(M),
        .PE_PER_PU(PE_PER_PU)
    ) u_filter_buf (
        .clk(clk),
        .rst_n(rst_n),

        .fltbuf_inf_vld_i(fltbuf_inf_vld_i),
        .fltbuf_inf_fltbaddr_i(fltbuf_inf_fltbaddr_i),
        .fltbuf_inf_ifparr_i(fltbuf_inf_ifparr_i),
        .fltbuf_inf_ifparr_tail_i(fltbuf_inf_ifparr_tail_i),
        .fltbuf_inf_fltsize_i(fltbuf_inf_fltsize_i),
        .fltbuf_inf_ifblock_i(fltbuf_inf_ifblock_i),
        .fltbuf_inf_ofparr_i(fltbuf_inf_ofparr_i),
        .fltbuf_inf_ofparr_tail_i(fltbuf_inf_ofparr_tail_i),
        .fltbuf_inf_oftiles_i(fltbuf_inf_oftiles_i),
        .fltbuf_inf_oftiles_tail_i(fltbuf_inf_oftiles_tail_i),
        .fltbuf_inf_iftiles_i(fltbuf_inf_iftiles_i),
        .fltbuf_inf_rdy_o(fltbuf_inf_rdy_o),
        .fltbuf_inf_height_i(fltbuf_inf_height_w),
        .zp(fltbuf_inf_zp_w),

        .fltbuf_dma_rdycfg_i(cnn_fltbuf_dma_rdycfg_i),
        .fltbuf_dma_vld_i(cnn_fltbuf_dma_vld_i),
        .fltbuf_dma_data_i(cnn_fltbuf_dma_data_i),
        .fltbuf_dma_tlast_i(cnn_fltbuf_dma_tlast_i),
        .fltbuf_dma_vldcfg_o(cnn_fltbuf_dma_vldcfg_o),
        .fltbuf_dma_burst_o(cnn_fltbuf_dma_burst_o),
        .fltbuf_dma_baddr_o(cnn_fltbuf_dma_baddr_o),
        .fltbuf_dma_rdy_o(cnn_fltbuf_dma_rdy_o),

        .fltbuf_comp_rdy_i(fltbuf_comp_rdy_w),
        .fltbuf_comp_vld_o(fltbuf_comp_vld_w),
        .fltbuf_comp_data_o(fltbuf_comp_data_w),
        .fltbuf_comp_donepass_o(fltbuf_comp_donepass_w)
    );
    // =========================================================
    // BIAS BUF
    // =========================================================
    wire [M-1:0] comp_bias_rdy_w;
    wire [M-1:0] comp_bias_vld_w;
    wire signed [M*ACC_WIDTH-1:0] comp_bias_data_w;

    bias_buffer #(
        .DATA_WIDTH(32)
    ) u_bias_buf (
        .clk(clk),
        .rst_n(rst_n),

        .bias_inf_vld_i(bias_inf_vld_i),
        .bias_inf_rdy_o(bias_inf_rdy_o),
        .bias_inf_bias_baddr_i(bias_inf_bias_baddr_i),
        .bias_inf_ofwidth_i(bias_inf_ofwidth_i),
        .bias_inf_ofchannel_i(bias_inf_ofchannel_i),
        .bias_inf_burstlen_i(bias_inf_burstlen_i),
        .bias_inf_burstlen_tail_i(bias_inf_burstlen_tail_i),
        .bias_inf_burstlen_lane0_i(bias_inf_burstlen_lane0_i),
        .bias_inf_burstlen_tail_lane0_i(bias_inf_burstlen_tail_lane0_i),

        .bias_dma_rdycfg_i(cnn_bias_dma_rdycfg_i),
        .bias_dma_vldcfg_o(cnn_bias_dma_vldcfg_o),
        .bias_dma_burst_o(cnn_bias_dma_burst_o), 
        .bias_dma_baddr_o(cnn_bias_dma_baddr_o),
        .bias_dma_vld_i(cnn_bias_dma_vld_i),
        .bias_dma_data_i(cnn_bias_dma_data_i),
        .bias_dma_tlast_i(cnn_bias_dma_tlast_i),
        .bias_dma_rdy_o(cnn_bias_dma_rdy_o),
        
        .bias_scale_rdy_i(comp_bias_rdy_w),
        .bias_scale_data_o(comp_bias_data_w),
        .bias_scale_vld_o(comp_bias_vld_w)
        
        );
    // =========================================================
    // COMPUTATION
    // =========================================================
    computation #(
        .WIDTH(DATA_WIDTH),
        .ACC_WIDTH(ACC_WIDTH),
        .PE_PER_PU(PE_PER_PU),
        .DEPTH(COMP_DEPTH),
        .K(K),
        .M(M),
        .PPDEPTH(PPDEPTH),
        .FIFO_DEPTH(FIFO_DEPTH)
    ) u_computation (
        .clk(clk),
        .rst_n(rst_n),

        .comp_inf_rdy_o(comp_inf_rdy_o),
        .comp_inf_vld_i(comp_inf_vld_i),
        .comp_inf_hf_i(comp_inf_hf_i),
        .comp_inf_stride_i(comp_inf_stride_i),
        .comp_inf_padding_i(comp_inf_padding_i),
        .comp_inf_ifc_zp_i(comp_inf_ifc_zp_i),
        .comp_inf_fltc_zp_i(comp_inf_fltc_zp_i),
        .comp_inf_ofwidth_i(comp_inf_ofwidth_i),
        .comp_inf_mult_i(comp_inf_mult_i),
        .comp_inf_mult_shift_i(comp_inf_mult_shift_i),
        .comp_inf_alphamult_i(comp_inf_alphamult_i),
        .comp_inf_alphamult_shift_i(comp_inf_alphamult_shift_i),
        .comp_inf_zpy_i(comp_inf_zpy_i),
        .comp_inf_qmin_i(comp_inf_qmin_i),
        .comp_inf_qmax_i(comp_inf_qmax_i),
        .comp_inf_is_leaky_ReLU_i(comp_inf_is_leaky_ReLU_i),

        .comp_ifbuf_vld_i(ifbuf_comp_vld_buf_w),
        .comp_ifbuf_data_i(ifbuf_comp_data_buf_w),

        .comp_ifbuf_end_row_i(ifbuf_comp_end_row_buf_w),

        .comp_ifbuf_end_row_circle_i(ifbuf_comp_end_row_circle_buf_w),
        .comp_ifbuf_end_depth_i(ifbuf_comp_end_depth_buf_w),
        .comp_ifbuf_end_layer_i(ifbuf_comp_end_layer_buf_w),
        .comp_ifbuf_end_layer_real_i(ifbuf_comp_end_layer_real_buf_w),
        .comp_ifbuf_rdy_o(ifbuf_comp_rdy_buf_w),

        .comp_fltbuf_vld_i(fltbuf_comp_vld_w),
        .comp_fltbuf_data_i(fltbuf_comp_data_w),
        .comp_fltbuf_done_pass_i(fltbuf_comp_donepass_w),
        .comp_fltbuf_rdy_o(comp_fltbuf_rdy_w),

        .comp_bias_data_i(comp_bias_data_w),
        .comp_bias_vld_i(comp_bias_vld_w),
        .comp_bias_rdy_o(comp_bias_rdy_w),

        .comp_ofbuf_rdy_i(comp_ofbuf_rdy_w),
        .comp_ofbuf_vld_o(comp_ofbuf_vld_w),
        .comp_ofbuf_data_o(comp_ofbuf_data_w),
        .comp_pa_done_compute_o(cnn_comp_pa_done_compute_o)
    );

    genvar gi;
    generate
        for (gi = 0; gi < M; gi = gi + 1) begin : gen_ofbuf
            skid_buffer #(
                .SBUF_TYPE(0),
                .DATA_WIDTH(DATA_WIDTH)
            ) u_skid_ofbuf (
                .clk(clk),
                .rst_n(rst_n),

                .bwd_data_i (comp_ofbuf_data_w[gi*DATA_WIDTH +: DATA_WIDTH]),
                .bwd_valid_i(comp_ofbuf_vld_w[gi]),
                .fwd_ready_i(ofbuf_comp_rdy_w[gi]),

                .fwd_data_o (ofbuf_comp_data_w[gi*DATA_WIDTH +: DATA_WIDTH]),
                .bwd_ready_o(comp_ofbuf_rdy_w[gi]),
                .fwd_valid_o(ofbuf_comp_vld_w[gi])
            );
        end
    endgenerate


    // =========================================================
    // OFBUF
    // =========================================================
    ofbuf #(
        .DATA_WIDTH(DATA_WIDTH),
        .DEPTH(OFBUF_DEPTH),
        .M(M)
    ) u_ofbuf (
        .clk(clk),
        .rst_n(rst_n),

        .ofbuf_inf_vld_i(ofbuf_inf_vld_w),
        .ofbuf_inf_ofbaddr_l0_i(ofbuf_inf_ofbaddr_l0_w),
        .ofbuf_inf_ofbaddr_l1_i(ofbuf_inf_ofbaddr_l1_w),
        .ofbuf_inf_ofwidth_i(ofbuf_inf_ofwidth_w),
        .ofbuf_inf_ofsize_i(ofbuf_inf_ofsize_w),
        .ofbuf_inf_ofblock_i(ofbuf_inf_ofblock_w),
        .ofbuf_inf_ofc_bl_l0_i(ofbuf_inf_ofc_bl_l0_w),
        .ofbuf_inf_ofc_bl_tail_l0_i(ofbuf_inf_ofc_bl_tail_l0_w),
        .ofbuf_inf_ofc_bl_l1_i(ofbuf_inf_ofc_bl_l1_w),
        .ofbuf_inf_ofc_bl_tail_l1_i(ofbuf_inf_ofc_bl_tail_l1_w),
        .ofbuf_inf_rdy_o(ofbuf_inf_rdy_w),

        .ofbuf_dma_rdycfg_i(cnn_ofbuf_dma_rdycfg_i),
        .ofbuf_dma_vldcfg_o(cnn_ofbuf_dma_vldcfg_o),
        .ofbuf_dma_burst_o(cnn_ofbuf_dma_burst_o),
        .ofbuf_dma_baddr_o(cnn_ofbuf_dma_baddr_o),
        .ofbuf_dma_vld_o(cnn_ofbuf_dma_vld_o),
        .ofbuf_dma_data_o(cnn_ofbuf_dma_data_o),
        .ofbuf_dma_tlast_o(cnn_ofbuf_dma_tlast_o),
        .ofbuf_dma_rdy_i(cnn_ofbuf_dma_rdy_i),

        .ofbuf_comp_vld_i(ofbuf_comp_vld_w),
        .ofbuf_comp_rdy_o(ofbuf_comp_rdy_w),
        .ofbuf_comp_data_i(ofbuf_comp_data_w)
    );

endmodule