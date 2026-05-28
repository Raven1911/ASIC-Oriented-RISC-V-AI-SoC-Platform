`timescale 1ns / 1ps

module ifmap_cache #(
    parameter DATA_WIDTH    = 8,        
    parameter FIFO_DEPTH    = 12,
    parameter K             = 7
)(
    input                       clk,
    input                       rst_n,              
    input  [3:0]                ifc_inf_hf_i,
    input  [2:0]                ifc_inf_stride_i,
    input  [K*DATA_WIDTH-1:0]   ifc_ifbuf_data_i,
    input                       ifc_ifbuf_end_row_i,
    input                       ifc_ifbuf_end_row_circle_i,
    input                       ifc_ifbuf_end_depth_i,
    input                       ifc_ifbuf_end_layer_i,
    input                       ifc_ifbuf_end_layer_real_i,
    input                       ifc_ifbuf_vld_i,
    output                      ifc_ifbuf_rdy_o,  
    
    input                       ifc_pu_rdy_i,
    output                      ifc_pu_vld_o,    
    output [K*DATA_WIDTH - 1:0] ifc_pu_data_o,
    output                      ifc_pu_end_row_o,
    output                      ifc_pu_end_row_circle_o,
    output                      ifc_pu_end_depth_o,
    output                      ifc_pu_end_layer_o,
    output                      ifc_pu_end_layer_real_o
);

    // ==========================================
    // Khai báo tín hiệu nội bộ
    // ==========================================
    reg     [3:0]               prefill_cnt; 
    reg     [3:0]               window_cnt;  
    reg                         is_begin;
    wire    [K*DATA_WIDTH + 4:0] fifo_dout;
    wire                        fifo_wr_en;
    wire                        empty;
    wire    [K*DATA_WIDTH + 4:0] fifo_din;
    reg                         window_active;              
    wire    [K*DATA_WIDTH + 4:0] combined_data_in;
    
    // Các tín hiệu Look-ahead
    wire    [3:0]               prefill_cnt_nxt;
    wire    [3:0]               window_cnt_nxt;
    wire                        window_active_nxt;
    
    assign combined_data_in = {ifc_ifbuf_end_layer_real_i, ifc_ifbuf_end_row_i, ifc_ifbuf_end_row_circle_i, ifc_ifbuf_end_depth_i, ifc_ifbuf_end_layer_i, ifc_ifbuf_data_i};
    // assign window_active = (prefill_cnt == (|(ifc_inf_hf_i - ifc_inf_stride_i) ? (ifc_inf_hf_i - ifc_inf_stride_i) : 1));

    // ==========================================
    // 1. Logic Look-ahead (Tính toán chu kỳ tiếp theo)
    // ==========================================
    assign prefill_cnt_nxt = (ifc_ifbuf_end_row_i == 1'b1) ? 4'd0 :
                             (!window_active && ifc_ifbuf_vld_i && ifc_ifbuf_rdy_o) ? prefill_cnt + 1'b1 :
                             prefill_cnt;

    assign window_active_nxt = (prefill_cnt_nxt == (|(ifc_inf_hf_i - ifc_inf_stride_i) ? (ifc_inf_hf_i - ifc_inf_stride_i) : 1));

    assign fifo_wr_en = ((prefill_cnt < (ifc_inf_hf_i - ifc_inf_stride_i) || (prefill_cnt < 1 && ifc_inf_hf_i == ifc_inf_stride_i)) && ifc_ifbuf_vld_i) || 
                        (window_active && ifc_pu_rdy_i);

    assign window_cnt_nxt = (ifc_ifbuf_end_row_i == 1'b1) ? 4'd0 :
                            (window_active && fifo_wr_en) ? 
                                ((window_cnt == ifc_inf_hf_i - 1) ? 4'd0 : window_cnt + 1'b1) :
                            window_cnt;

    // ==========================================
    // 2. Cập nhật thanh ghi đồng bộ (Dùng tín hiệu _nxt)
    // ==========================================
    always @(posedge clk) begin
        if (!rst_n) begin
            prefill_cnt <= 0;
            window_cnt  <= 0;
            window_active <= 0;
            //ifc_ifbuf_rdy_o <= 1'b0; // Hoặc 1'b1 tùy thuộc vào trạng thái init thiết kế của bạn
        end else begin
            // Cập nhật counter
            prefill_cnt     <= prefill_cnt_nxt;
            window_cnt      <= window_cnt_nxt;
            window_active   <= (prefill_cnt_nxt == (|(ifc_inf_hf_i - ifc_inf_stride_i) ? (ifc_inf_hf_i - ifc_inf_stride_i) : 1));
        end
    end
    assign ifc_ifbuf_rdy_o  = (prefill_cnt < (ifc_inf_hf_i - ifc_inf_stride_i)) || (prefill_cnt < 1 && ifc_inf_hf_i == ifc_inf_stride_i) ||
                               (window_active && (window_cnt_nxt < ifc_inf_stride_i) && ifc_pu_rdy_i);
    // ==========================================
    // 3. Logic của thanh ghi đếm 'is_begin'
    // ==========================================
    always @(posedge clk) begin
        if (!rst_n) begin
            is_begin <= 0;
        end else begin
            if ((prefill_cnt == (|(ifc_inf_hf_i - ifc_inf_stride_i) ? (ifc_inf_hf_i - ifc_inf_stride_i - 1) : 0)) && ifc_ifbuf_vld_i && ifc_ifbuf_rdy_o) begin
                is_begin <= 1;
            end else if(fifo_dout[K*DATA_WIDTH + 3] && ifc_pu_rdy_i && ifc_pu_vld_o) begin
                is_begin <= window_active;
            end
        end
    end

    // ==========================================
    // 4. Các tín hiệu ngõ ra khác
    // ==========================================
    assign fifo_din                 = (window_active && (window_cnt >= ifc_inf_stride_i)) ? fifo_dout : combined_data_in;
    assign ifc_pu_data_o            = fifo_dout[K*DATA_WIDTH - 1 : 0];
    assign ifc_pu_end_layer_o       = fifo_dout[K*DATA_WIDTH];
    assign ifc_pu_end_layer_real_o  = fifo_dout[K*DATA_WIDTH + 4];
    assign ifc_pu_end_depth_o       = fifo_dout[K*DATA_WIDTH + 1];
    assign ifc_pu_end_row_circle_o  = fifo_dout[K*DATA_WIDTH + 2];
    assign ifc_pu_end_row_o         = fifo_dout[K*DATA_WIDTH + 3];
    assign ifc_pu_vld_o             = is_begin && ~empty;
    
       fifo_n #(
       .DATA_WIDTH(K*DATA_WIDTH + 5),
       .FF_TYPE(0),
       .FF_NUM(2),
       .FIFO_DEPTH(FIFO_DEPTH)
       ) ifmap_cache_uut (
        .clk(clk),
        .data_i(fifo_din),
        .data_o(fifo_dout),
        .rd_valid_i(ifc_pu_rdy_i && ifc_pu_vld_o),
        .wr_valid_i(fifo_wr_en),
        .clr_rd_i(1'b0),
        .clr_ff_i(1'b0),
        .empty_o(empty),
        .full_o(),
        .almost_empty_o(),
        .almost_full_o(),
        .counter(),
        .rst_n(rst_n)
       );
    (* keep = "false" *) wire _unused_sink;
    assign _unused_sink = &{
        window_active_nxt
    };
endmodule