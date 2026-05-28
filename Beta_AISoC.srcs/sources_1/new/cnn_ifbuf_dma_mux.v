`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 05/11/2026 06:44:55 PM
// Design Name: 
// Module Name: cnn_ifbuf_dma_mux
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
module cnn_ifbuf_dma_mux #(
    parameter ADDR_WIDTH_DMAC   = 24,
    parameter HYPER_BURST_WIDTH = 10,
    parameter VIDEO_ADDR_WIDTH  = 32,
    parameter VIDEO_BURST_WIDTH = 16,
    parameter DATA_WIDTH_BYTE   = 1,
    parameter CNN_BURST_WIDTH   = 8
)(
    input                               select_video_i,

    input                               cnn_cfg_valid_i,
    output                              cnn_cfg_ready_o,
    input       [ADDR_WIDTH_DMAC-1:0]   cnn_cfg_addr_i,
    input       [CNN_BURST_WIDTH-1:0]   cnn_cfg_burst_i,

    output                              cnn_stream_valid_o,
    output      [DATA_WIDTH_BYTE*8-1:0] cnn_stream_data_o,
    output                              cnn_stream_tlast_o,
    input                               cnn_stream_ready_i,

    output                              hyper_arvalid_o,
    input                               hyper_arready_i,
    output      [ADDR_WIDTH_DMAC-1:0]   hyper_araddr_o,
    output      [HYPER_BURST_WIDTH-1:0] hyper_arburst_o,
    input                               hyper_tvalid_i,
    output                              hyper_tready_o,
    input       [DATA_WIDTH_BYTE*8-1:0] hyper_tdata_i,
    input                               hyper_tlast_i,

    output                              video_arvalid_o,
    input                               video_arready_i,
    output      [VIDEO_ADDR_WIDTH-1:0]  video_araddr_o,
    output      [VIDEO_BURST_WIDTH-1:0] video_arburst_o,
    input                               video_tvalid_i,
    output                              video_tready_o,
    input       [DATA_WIDTH_BYTE*8-1:0] video_tdata_i,
    input                               video_tlast_i
);

    assign hyper_arvalid_o = select_video_i ? 1'b0 : cnn_cfg_valid_i;
    assign hyper_araddr_o  = cnn_cfg_addr_i;
    assign hyper_arburst_o = {{(HYPER_BURST_WIDTH-CNN_BURST_WIDTH){1'b0}}, cnn_cfg_burst_i};
    assign hyper_tready_o  = select_video_i ? 1'b0 : cnn_stream_ready_i;

    assign video_arvalid_o = select_video_i ? cnn_cfg_valid_i : 1'b0;
    assign video_araddr_o  = {{(VIDEO_ADDR_WIDTH-ADDR_WIDTH_DMAC){1'b0}}, cnn_cfg_addr_i};
    assign video_arburst_o = {{(VIDEO_BURST_WIDTH-CNN_BURST_WIDTH){1'b0}}, cnn_cfg_burst_i};
    assign video_tready_o  = select_video_i ? cnn_stream_ready_i : 1'b0;

    assign cnn_cfg_ready_o     = select_video_i ? video_arready_i : hyper_arready_i;
    assign cnn_stream_valid_o  = select_video_i ? video_tvalid_i  : hyper_tvalid_i;
    assign cnn_stream_data_o   = select_video_i ? video_tdata_i   : hyper_tdata_i;
    assign cnn_stream_tlast_o  = select_video_i ? video_tlast_i  : hyper_tlast_i;

endmodule
