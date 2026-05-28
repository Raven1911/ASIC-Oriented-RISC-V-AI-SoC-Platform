`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 04/23/2026 02:58:08 PM
// Design Name: 
// Module Name: bias_buffer
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


module bias_buffer #(
    parameter   DATA_WIDTH = 32,
    parameter   M = 2, 
    parameter   BIAS_DEPTH = 25
)(
    input                           clk,
    input                           rst_n,
    
    input                           bias_inf_vld_i,
    output                          bias_inf_rdy_o,
    input           [23:0]          bias_inf_bias_baddr_i,
    input           [7:0]           bias_inf_ofwidth_i,
    input           [10:0]          bias_inf_ofchannel_i,
    input           [4:0]           bias_inf_burstlen_i,
    input           [4:0]           bias_inf_burstlen_tail_i,
    input           [4:0]           bias_inf_burstlen_lane0_i,
    input           [4:0]           bias_inf_burstlen_tail_lane0_i,

    input                           bias_dma_rdycfg_i,
    output                          bias_dma_vldcfg_o,
    output          [6:0]           bias_dma_burst_o, 
    output          [23:0]          bias_dma_baddr_o,
    input                           bias_dma_vld_i,
    input           [7:0]           bias_dma_data_i,
    input                           bias_dma_tlast_i,
    output                          bias_dma_rdy_o,
    
    input     [M-1:0]               bias_scale_rdy_i,
    output    [M*DATA_WIDTH-1:0]    bias_scale_data_o,
    output    [M-1:0]               bias_scale_vld_o
    
    );

    reg         [23:0]          bias_inf_bias_baddr_reg;
    reg         [7:0]           bias_inf_ifwidth_reg;
    reg         [10:0]          bias_inf_ofchannel_reg;
    reg         [4:0]           bias_inf_burstlen_reg;
    reg         [4:0]           bias_inf_burstlen_tail_reg;
    reg         [4:0]           bias_inf_burstlen_lane0_reg;
    reg         [4:0]           bias_inf_burstlen_lane1_reg;
    reg         [4:0]           bias_inf_burstlen_tail_lane0_reg;
    reg         [4:0]           bias_inf_burstlen_tail_lane1_reg;

    reg                         inf_rdy_dly;
    reg                         inf_rdy_dly_2;
    reg         [6:0]           burst_length;
    reg         [4:0]           burst_length_real;
    reg         [31:0]          base_addr;
    reg         [10:0]          ch_cnt_nxt_swp;
    reg                         is_tail_cfg;
    reg                         is_tail_read;
    reg                         is_tail_write;
    reg                         vldcfg;
    reg                         inf_rdy;

    reg         [4:0]           count_bias;
    reg                         is_lane_1;
    reg                         done_write;
    reg                         id;
    reg         [4:0]           cnt_bias_rd1;
    reg         [4:0]           cnt_bias_rd2;
    reg         [7:0]           cnt_height_rd1;
    reg         [7:0]           cnt_height_rd2;
    wire                        cnt_height_rd1_en;
    wire                        cnt_height_rd2_en;
    wire                        swap_en;
    //-------------------------------------------CONFIG------------------------------------------------
    assign bias_inf_rdy_o = inf_rdy;
    assign bias_dma_vldcfg_o = vldcfg;
    assign bias_dma_burst_o = burst_length;
    assign bias_dma_baddr_o = base_addr;
    assign bias_dma_rdy_o = 1'b1;
    always @(posedge clk) begin
        if(bias_inf_rdy_o) begin
            bias_inf_bias_baddr_reg             <= bias_inf_bias_baddr_i;
            bias_inf_ifwidth_reg                <= bias_inf_ofwidth_i;
            bias_inf_ofchannel_reg              <= bias_inf_ofchannel_i;
            bias_inf_burstlen_reg               <= bias_inf_burstlen_i;
            bias_inf_burstlen_tail_reg          <= bias_inf_burstlen_tail_i;
            bias_inf_burstlen_lane0_reg         <= bias_inf_burstlen_lane0_i;
            bias_inf_burstlen_lane1_reg         <= bias_inf_burstlen_i - bias_inf_burstlen_lane0_i;
            bias_inf_burstlen_tail_lane0_reg    <= bias_inf_burstlen_tail_lane0_i;
            bias_inf_burstlen_tail_lane1_reg    <= bias_inf_burstlen_tail_i - bias_inf_burstlen_tail_lane0_i;
            
        end
        inf_rdy_dly                         <= bias_inf_rdy_o && bias_inf_vld_i;
        inf_rdy_dly_2                       <= inf_rdy_dly;
    end
    always @(posedge clk) begin
        if(!rst_n) begin
            id <= 0;
        end else if(swap_en) begin
            id <= ~id;
        end
    end

    always @(posedge clk) begin
        if(swap_en || inf_rdy_dly) begin
            burst_length        <= (inf_rdy_dly || !is_tail_cfg) ? 
                                    {bias_inf_burstlen_reg, 2'b00}: 
                                    {bias_inf_burstlen_tail_reg, 2'b00};
            burst_length_real   <= (inf_rdy_dly || !is_tail_cfg) ? 
                                    bias_inf_burstlen_reg : 
                                    bias_inf_burstlen_tail_reg;
            base_addr           <= inf_rdy_dly ? bias_inf_bias_baddr_reg : (burst_length + base_addr);
        end
    end
    always @(posedge clk) begin
        if((bias_dma_rdycfg_i && bias_dma_vldcfg_o) || inf_rdy_dly) begin
            ch_cnt_nxt_swp  <= inf_rdy_dly ? bias_inf_burstlen_reg : ch_cnt_nxt_swp + bias_inf_burstlen_reg;
        end
    end
    always @(posedge clk) begin
        if(bias_inf_rdy_o) begin
            is_tail_cfg   <= 0;
        end else if((bias_dma_rdycfg_i && bias_dma_vldcfg_o) || inf_rdy_dly) begin
            is_tail_cfg   <= inf_rdy_dly ? !(bias_inf_burstlen_reg < bias_inf_ofchannel_reg) : !((ch_cnt_nxt_swp + bias_inf_burstlen_reg) < bias_inf_ofchannel_reg);
        end
    end
    always @(posedge clk) begin
        if(bias_inf_rdy_o) begin
            is_tail_write <= 0;
        end else if(swap_en || inf_rdy_dly_2) begin
            is_tail_write <= is_tail_cfg;
        end
    end
    always @(posedge clk) begin
        if(!rst_n) begin
            vldcfg <= 0;
        end if(bias_dma_rdycfg_i && bias_dma_vldcfg_o || inf_rdy) begin
            vldcfg <= 0;
        end else if((!is_tail_write && swap_en) || inf_rdy_dly) begin
            vldcfg <= 1;
        end
    end
    always @(posedge clk) begin
        if(!rst_n) begin
            inf_rdy <= 1;
        end else if(is_tail_write && swap_en) begin
            inf_rdy <= 1;
        end else if(bias_inf_vld_i) begin
            inf_rdy <= 0;
        end
    end
    //-------------------------------------------WRITE CONTROL------------------------------------------------
    reg [1:0] cnt_byte;
    reg [31:0] bias_full;
    reg dma_vld_dly;
    reg dma_tlast_dly;
    genvar bidx;
    generate
        for(bidx = 0; bidx < 4; bidx = bidx + 1) begin
            always @(posedge clk) begin
                if(bias_dma_vld_i) begin
                    bias_full[bidx*8 +: 8] <= (bidx == 0) ? bias_dma_data_i : bias_full[(bidx-1)*8 +: 8];
                end
            end
        end
    
    endgenerate
    always @(posedge clk) begin
        if(inf_rdy_dly) begin
            cnt_byte <= 0;
        end else if(bias_dma_vld_i) begin
            cnt_byte <= cnt_byte + 1;
        end
    end
    always @(posedge clk) begin
        dma_vld_dly <= bias_dma_vld_i;
        dma_tlast_dly <= bias_dma_tlast_i;
    end
    assign swap_en = done_write && !(bias_scale_vld_o[1] || bias_scale_vld_o[0]);
    always @(posedge clk) begin
        if(bias_dma_tlast_i && bias_dma_vld_i) begin
            done_write <= 1;
        end else if(swap_en || inf_rdy_dly) begin
            done_write <= 0;
        end
    end
    always @(posedge clk) begin
        if((dma_tlast_dly && dma_vld_dly && !(|cnt_byte)) || inf_rdy_dly) begin
            count_bias <= 0;
        end else if(dma_vld_dly && !(|cnt_byte)) begin
            count_bias <= count_bias + 1;
        end
    end
    always @(posedge clk) begin
        if((dma_tlast_dly && dma_vld_dly && !(|cnt_byte)) || inf_rdy_dly) begin
            is_lane_1 <= 0;
        end else if(dma_vld_dly && !(|cnt_byte) && ((count_bias + 1) == bias_inf_burstlen_lane0_reg || ((count_bias + 1) == bias_inf_burstlen_tail_lane0_reg && is_tail_write))) begin
            is_lane_1 <= 1;
        end
    end
    ping_pong_bias #(
        .WIDTH(DATA_WIDTH),
        .BIAS_DEPTH(BIAS_DEPTH)
    ) pp_bram1 (
        .clk(clk),
        .rst_n(rst_n),
        .id_i(id),
        .wr_en(dma_vld_dly && !(|cnt_byte) && !is_lane_1),
        .rd_en(bias_scale_rdy_i[0]),
        .is_wr_back(cnt_height_rd1 != bias_inf_ifwidth_reg - 1),
        .clr_i(1'b0),
        .data_i(bias_full),
        .data_o(bias_scale_data_o[DATA_WIDTH-1:0]),
        .vld_o(bias_scale_vld_o[0])
    );
    ping_pong_bias #(
        .WIDTH(DATA_WIDTH),
        .BIAS_DEPTH(BIAS_DEPTH)
    ) pp_bram2 (
        .clk(clk),
        .rst_n(rst_n),
        .id_i(id),
        .wr_en(dma_vld_dly && !(|cnt_byte) && is_lane_1),
        .rd_en(bias_scale_rdy_i[1]),
        .is_wr_back(cnt_height_rd2 != bias_inf_ifwidth_reg - 1),
        .clr_i(1'b0),
        .data_i(bias_full),
        .data_o(bias_scale_data_o[2*DATA_WIDTH-1:DATA_WIDTH]),
        .vld_o(bias_scale_vld_o[1])
    );
    //-------------------------------------------READ & CLEAR CONTROL------------------------------------------------
    assign cnt_height_rd1_en = bias_scale_rdy_i[0] && bias_scale_vld_o[0] && ((cnt_bias_rd1 == bias_inf_burstlen_lane0_reg - 1) || is_tail_read && (cnt_bias_rd1 == bias_inf_burstlen_tail_lane0_reg - 1));
    assign cnt_height_rd2_en = bias_scale_rdy_i[1] && bias_scale_vld_o[1] && ((cnt_bias_rd2 == bias_inf_burstlen_lane1_reg - 1) || is_tail_read && (cnt_bias_rd2 == bias_inf_burstlen_tail_lane1_reg - 1));
    always @(posedge clk) begin
        if(swap_en) begin
            is_tail_read <= is_tail_write;
        end
    end
    always @(posedge clk) begin
        if(swap_en) begin
            cnt_bias_rd1 <= 0;
        end else if(bias_scale_rdy_i[0] && bias_scale_vld_o[0]) begin
            cnt_bias_rd1 <= ((cnt_bias_rd1 == bias_inf_burstlen_lane0_reg - 1) || is_tail_read && (cnt_bias_rd1 == bias_inf_burstlen_tail_lane0_reg - 1)) 
            ? 0 : cnt_bias_rd1 + 1;
        end
    end
    always @(posedge clk) begin
        if(swap_en) begin
            cnt_bias_rd2 <= 0;
        end else if(bias_scale_rdy_i[1] && bias_scale_vld_o[1]) begin
            cnt_bias_rd2 <= ((cnt_bias_rd2 == bias_inf_burstlen_lane1_reg - 1) || is_tail_read && (cnt_bias_rd2 == bias_inf_burstlen_tail_lane1_reg - 1)) 
            ? 0 : cnt_bias_rd2 + 1;
        end
    end

    always @(posedge clk) begin
        if(swap_en) begin
            cnt_height_rd1 <= 0;
        end else if(cnt_height_rd1_en) begin
            cnt_height_rd1 <= (cnt_height_rd1 == bias_inf_ifwidth_reg - 1) ? 0 : cnt_height_rd1 + 1;
        end
    end
    always @(posedge clk) begin
        if(swap_en) begin
            cnt_height_rd2 <= 0;
        end else if(cnt_height_rd2_en) begin
            cnt_height_rd2 <= (cnt_height_rd2 == bias_inf_ifwidth_reg - 1) ? 0 : cnt_height_rd2 + 1;
        end
    end
endmodule

module ping_pong_bias #(
    parameter WIDTH = 32,
    parameter BIAS_DEPTH = 30
)(
    input               clk,
    input               rst_n,
    input               id_i,
    input               wr_en,
    input               rd_en,
    input               is_wr_back,
    input               clr_i,
    input   [WIDTH-1:0] data_i,
    output  [WIDTH-1:0] data_o,
    output              vld_o
    );
    wire [WIDTH-1:0]    data_o1, data_o2;
    wire [WIDTH-1:0]    data_i1, data_i2;
    wire                wr_en1, wr_en2;
    wire                rd_en1, rd_en2;
    wire                clr1, clr2;
    wire                empty1, empty2;

    assign rd_en1   = rd_en & ~id_i;
    assign rd_en2   = rd_en & id_i;
    assign clr1     = clr_i & ~id_i;
    assign clr2     = clr_i & id_i;
    assign wr_en1   = wr_en & id_i; // Cho phep ghi vao fifo1 khi id_i=1
    assign wr_en2   = wr_en & ~id_i;  // Cho phep ghi vao fifo2 khi id_i=0
    assign data_i1  = data_i; // Du lieu vao fifo1 la data_i khi ghi, la data_o1 khi doc
    assign data_i2  = data_i; // Du lieu vao fifo2 la data_i khi ghi, la data_o2 khi doc
    assign data_o   = id_i ? data_o2 : data_o1;
    assign vld_o    = id_i ? !empty2 : !empty1;
    
    fifo_n #(
       .DATA_WIDTH(WIDTH),
       .FF_TYPE(0),
       .FF_NUM(2),
       .FIFO_DEPTH(BIAS_DEPTH)
       ) bias_fifo1 (
        .clk(clk),
        .data_i(rd_en1 && !empty1 ? data_o1 : data_i1),
        .data_o(data_o1),
        .rd_valid_i(rd_en1),
        .wr_valid_i(wr_en1 || rd_en1 && !empty1 && is_wr_back),
        .clr_rd_i(1'b0),
        .clr_ff_i(clr1),
        .empty_o(empty1),
        .full_o(),
        .almost_empty_o(),
        .almost_full_o(),
        .counter(),
        .rst_n(rst_n)
    );
    fifo_n #(
       .DATA_WIDTH(WIDTH),
       .FF_TYPE(0),
       .FF_NUM(2),
       .FIFO_DEPTH(BIAS_DEPTH)
       ) bias_fifo2 (
        .clk(clk),
        .data_i(rd_en2 && !empty2 ? data_o2 : data_i2),
        .data_o(data_o2),
        .rd_valid_i(rd_en2),
        .wr_valid_i(wr_en2 || rd_en2 && !empty2 && is_wr_back),
        .clr_rd_i(1'b0),
        .clr_ff_i(clr2),
        .empty_o(empty2),
        .full_o(),
        .almost_empty_o(),
        .almost_full_o(),
        .counter(),
        .rst_n(rst_n)
    );
endmodule