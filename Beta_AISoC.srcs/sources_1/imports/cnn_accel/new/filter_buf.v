`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 03/25/2026 08:59:18 AM
// Design Name: 
// Module Name: filter_buf
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



module filter_buf #(
    parameter DATA_WIDTH    = 8,
    parameter DEPTH         = 300,
    parameter K             = 8,
    parameter M             = 2,
    parameter PE_PER_PU     = 12
)(
    input   clk,
    input   rst_n,
    
    // Giao tiếp inftruction
    input               fltbuf_inf_vld_i,
    input       [23:0]  fltbuf_inf_fltbaddr_i,
    input       [3:0]   fltbuf_inf_ifparr_i,
    input       [3:0]   fltbuf_inf_ifparr_tail_i,
    input       [6:0]   fltbuf_inf_fltsize_i,
    input       [6:0]   fltbuf_inf_ifblock_i,
    input       [4:0]   fltbuf_inf_ofparr_i,
    input       [4:0]   fltbuf_inf_ofparr_tail_i,
    input       [3:0]   fltbuf_inf_oftiles_i,
    input       [3:0]   fltbuf_inf_oftiles_tail_i,
    input       [7:0]   fltbuf_inf_iftiles_i,
    input       [7:0]   fltbuf_inf_height_i,
    output reg          fltbuf_inf_rdy_o,
    input       [DATA_WIDTH-1:0] zp,
    // Tín hiệu DMA
    input               fltbuf_dma_rdycfg_i,
    input               fltbuf_dma_vld_i,
    input   [DATA_WIDTH-1:0] fltbuf_dma_data_i,
    input               fltbuf_dma_tlast_i,
    output              fltbuf_dma_vldcfg_o,
    output reg  [9:0]   fltbuf_dma_burst_o, 
    output reg  [23:0]  fltbuf_dma_baddr_o,
    output              fltbuf_dma_rdy_o,

    // Tín hiệu giao tiếp với khối khác
    input               fltbuf_comp_rdy_i,
    output reg [K*M-1:0] fltbuf_comp_vld_o,
    output     [K*M*DATA_WIDTH-1:0] fltbuf_comp_data_o,
    output              fltbuf_comp_donepass_o
    );
    localparam IDLE = 0;
    localparam WAIT_6C = 1;
    localparam VLDCFG = 2;
    reg [1:0]   STATE;
    reg [2:0]   count_cycle;
    reg [23:0]  fltbaddr_reg;
    reg [3:0]   ifparr_reg;
    reg [3:0]   ifparr_tail_reg;
    reg [6:0]   fltsize_reg;
    reg [6:0]   ifblock_reg;
    reg [4:0]   ofparr_reg;
    reg [4:0]   ofparr_tail_reg;
    reg [3:0]   oftiles_reg;
    reg [3:0]   oftiles_tail_reg;
    reg [7:0]   iftiles_reg;
    reg [3:0]   filter_rd_cnt;
    reg [6:0]   fltsize_rd_cnt;
    reg [7:0]   iftiles_rd_cnt;
    reg [3:0]   oftiles_rd_cnt;
    reg [6:0]   ifblock_rd_cnt;
    reg [7:0]   height_rd_cnt;
    reg [7:0]   height_reg;
    reg         end_layer;
    wire        last_height_rd;
    wire        height_rd_cnt_en;
    wire        last_fltsize_rd;
    reg         last_filter_rd;
    reg [4:0]   actual_rd_filter0;
    wire        fltsize_rd_cnt_en;
    wire        filter_rd_cnt_en;
    reg [6:0]   fltsize_wr_cnt;
    reg [3:0]   channel_wr_cnt;
    reg [4:0]   filter_wr_cnt;
    reg [7:0]   iftiles_wr_cnt;
    reg [3:0]   oftiles_wr_cnt;
    reg [6:0]   ifblock_wr_cnt;
    wire        wr_val;
    wire        last_channel_wr;
    wire        last_fltsize_wr;
    wire        last_filter_wr;
    reg         pa_wr_cnt;
    wire        fltsize_wr_cnt_en;
    wire        channel_wr_cnt_en;
    wire        filter_wr_cnt_en;
    wire        pa_wr_cnt_en;
    reg [7:0]   iftiles_cfg_cnt;
    reg         en_cfg;
    reg         vldcfg;
    wire        iftiles_cfg_cnt_en;
    reg [3:0]   oftiles_cfg_cnt;
    wire        oftiles_cfg_cnt_en;
    reg [6:0]   ifblock_cfg_cnt;
    wire        ifblock_cfg_cnt_en;
    reg [3:0]   actual_channel;
    reg [4:0]   actual_filter;
    wire [9:0]  fltbuf_dma_burst_nxt;
    wire [K*M-1:0] cache_wr_en;
    wire [K*M-1:0] fltbuf_comp_vld_o_nxt;
    reg wr_map [M-1:0][K-1:0];
    reg [M-1:0] cache_rd_en;
    wire        last_iftile;
    wire        last_ifblock;
    wire        last_oftile;
    wire        oftiles_rd_cnt_en;
    reg [511:0] pass_valid;
    reg [8:0]   pass_idx;
    reg [8:0]   pass_total;   
    reg         t_last;
    reg         pa1_rd_vld;
    reg         pa0_rd_vld;
    reg [4:0]   actual_rd_filter;
    wire        ifblock_rd_cnt_en;
    reg [4:0]   actual_rd_filter1;
    reg         done_pass;
    reg [3:0]   actual_wr_channel;
    reg [4:0]   actual_wr_filter;
    wire        last_iftile_wr;
    wire        last_iftile_rd;
    wire        last_ifblock_wr;
    reg         inf_rdy_dly;
    assign last_fltsize_rd      = (fltsize_rd_cnt == fltsize_reg - 1);
    assign fltsize_rd_cnt_en    = cache_rd_en[0];
    assign filter_rd_cnt_en     = (fltsize_rd_cnt == fltsize_reg - 1) && fltsize_rd_cnt_en;
    assign fltbuf_dma_rdy_o     = 1;
    assign last_fltsize_wr      = (fltsize_wr_cnt == fltsize_reg - 1);
    assign last_channel_wr      = (channel_wr_cnt == actual_wr_channel - 1);
    assign last_filter_wr       = (filter_wr_cnt == actual_wr_filter - 1);
    assign fltsize_wr_cnt_en    = wr_val;
    assign channel_wr_cnt_en    = (fltsize_wr_cnt == fltsize_reg - 1) && fltsize_wr_cnt_en;
    assign filter_wr_cnt_en     = (channel_wr_cnt == actual_wr_channel - 1) && channel_wr_cnt_en;
    assign pa_wr_cnt_en         = (filter_wr_cnt == ((actual_wr_filter - 1) >> 1)) && filter_wr_cnt_en;
    
    assign last_iftile          = (iftiles_cfg_cnt == iftiles_reg - 1);
    
    assign last_ifblock         = (ifblock_cfg_cnt == ifblock_reg - 1);
    
    assign last_oftile          = last_ifblock
                                ? (oftiles_cfg_cnt == oftiles_tail_reg - 1)
                                : (oftiles_cfg_cnt == oftiles_reg - 1);
    assign fltbuf_dma_burst_nxt = actual_channel * actual_filter * fltsize_reg;
    assign iftiles_cfg_cnt_en   = oftiles_cfg_cnt_en && ((ifblock_cfg_cnt == ifblock_reg - 1) && (oftiles_cfg_cnt == oftiles_tail_reg - 1) || (oftiles_cfg_cnt == oftiles_reg - 1));
    assign oftiles_cfg_cnt_en   = fltbuf_dma_vldcfg_o && fltbuf_dma_rdycfg_i;
    assign ifblock_cfg_cnt_en   = iftiles_cfg_cnt_en && (iftiles_cfg_cnt == iftiles_reg - 1);
    always @(posedge clk) begin
        if(fltbuf_inf_rdy_o) begin
            fltbaddr_reg    <= fltbuf_inf_fltbaddr_i;
            ifparr_reg      <= fltbuf_inf_ifparr_i;
            ifparr_tail_reg <= fltbuf_inf_ifparr_tail_i;
            fltsize_reg     <= fltbuf_inf_fltsize_i;
            ifblock_reg     <= fltbuf_inf_ifblock_i;
            ofparr_reg      <= fltbuf_inf_ofparr_i;
            ofparr_tail_reg <= fltbuf_inf_ofparr_tail_i;
            oftiles_reg     <= fltbuf_inf_oftiles_i;
            oftiles_tail_reg <= fltbuf_inf_oftiles_tail_i;
            iftiles_reg     <= fltbuf_inf_iftiles_i;
            height_reg      <= fltbuf_inf_height_i;
        end
        inf_rdy_dly         <= fltbuf_inf_rdy_o;
    end
    always @(posedge clk) begin
        if(inf_rdy_dly) begin
            actual_channel  <= 0;
            actual_filter   <= 0;
        end
        else if(!fltbuf_dma_vldcfg_o || fltbuf_dma_vldcfg_o && fltbuf_dma_rdycfg_i) begin
            actual_filter   <= (last_ifblock && last_oftile) ? ofparr_tail_reg : ofparr_reg;
            actual_channel  <= last_iftile ? ifparr_tail_reg : ifparr_reg;
        end
    end
    always @(posedge clk) begin
        if(fltbuf_inf_rdy_o) begin
            fltbuf_dma_baddr_o <= fltbuf_inf_fltbaddr_i;
        end else if(fltbuf_dma_vldcfg_o && fltbuf_dma_rdycfg_i) begin
            fltbuf_dma_baddr_o <= fltbuf_dma_baddr_o + fltbuf_dma_burst_o;
        end
    end
    always @(posedge clk) begin
        if(!rst_n) fltbuf_inf_rdy_o <= 1;
        else begin
            if((ifblock_rd_cnt == ifblock_reg - 1) && end_layer) fltbuf_inf_rdy_o <= 1;
            else if(fltbuf_inf_rdy_o && fltbuf_inf_vld_i) fltbuf_inf_rdy_o <= 0;
        end
    end
    always @(posedge clk) begin
        if(inf_rdy_dly) iftiles_cfg_cnt <= 0;
        else if (iftiles_cfg_cnt_en) iftiles_cfg_cnt <= (last_iftile) ? 0 : iftiles_cfg_cnt + 1;
    end
    always @(posedge clk) begin
        if(inf_rdy_dly) oftiles_cfg_cnt <= 0;
        else if (oftiles_cfg_cnt_en) oftiles_cfg_cnt <= (last_oftile) ? 0 : oftiles_cfg_cnt + 1;
    end
    always @(posedge clk) begin
        if(inf_rdy_dly) pass_total <= 0;
        else begin
            if(end_layer) pass_total <= 0;
            else if (oftiles_cfg_cnt_en) pass_total <= pass_total + 1;
        end
    end
    always @(posedge clk) begin
        if(inf_rdy_dly) ifblock_cfg_cnt <= 0;
        else if (ifblock_cfg_cnt_en) ifblock_cfg_cnt <= (last_ifblock) ? 0 : ifblock_cfg_cnt + 1;
    end
    assign fltbuf_dma_vldcfg_o = en_cfg && vldcfg;
    always @(posedge clk) begin
        if(!rst_n) en_cfg <= 1;
        else begin
            if(ifblock_cfg_cnt_en) en_cfg <= 0;
            else if(end_layer) en_cfg <= 1;
        end
    end
    always @(posedge clk) begin
        if(!rst_n) begin
            STATE <= IDLE;
            count_cycle <= 0;
            vldcfg <= 0;
            fltbuf_dma_burst_o <= 0;
        end else begin
            case (STATE)
                IDLE: begin
                    if(fltbuf_inf_rdy_o && fltbuf_inf_vld_i) STATE <= WAIT_6C;
                    count_cycle <= 0;
                    vldcfg <= 0;
                end
                WAIT_6C: begin
                    if(count_cycle == 4) STATE <= VLDCFG;
                    count_cycle <= count_cycle + 1;
                    vldcfg <= 0;
                end
                VLDCFG: begin
                    if(ifblock_cfg_cnt_en && (ifblock_cfg_cnt == ifblock_reg - 1)) begin
                        STATE <= IDLE;
                        count_cycle <= 0;
                        vldcfg <= 0;
                    end
                    else if(fltbuf_dma_vldcfg_o && fltbuf_dma_rdycfg_i) begin 
                        STATE <= WAIT_6C;
                        count_cycle <= 0;
                        vldcfg <= 0;
                    end else begin
                        count_cycle <= 0;
                        vldcfg <= 1;
                        STATE <= VLDCFG;
                        fltbuf_dma_burst_o <= fltbuf_dma_burst_nxt + fltbuf_dma_burst_nxt[0];
                    end
                    
                end
                default: begin
                    if(fltbuf_inf_rdy_o && fltbuf_inf_vld_i) STATE <= WAIT_6C;
                    count_cycle <= 0;
                    vldcfg <= 0;
                end
            endcase
        end
    end

    ///////////////////////////////READ CONTROL///////////////////////////////////////
    wire iftiles_rd_cnt_en;
    assign last_iftile_rd  = (iftiles_rd_cnt == iftiles_reg - 1);
    reg last_ifblock_rd;
    // assign last_ifblock_rd = (ifblock_rd_cnt == ifblock_reg - 1);
    always @(posedge clk) begin
        if(inf_rdy_dly) last_ifblock_rd <= 1'b0;
        else begin
            if(fltbuf_inf_rdy_o)        last_ifblock_rd <= 0;
            else if(ifblock_reg == 1)   last_ifblock_rd <= (ifblock_rd_cnt == ifblock_reg - 1);
            else if(ifblock_rd_cnt_en && ifblock_rd_cnt == ifblock_reg - 2) last_ifblock_rd <= 1;
        end
    end
    wire last_oftile_rd;
    wire end_layer_nxt;
    reg end_layer1;
        assign last_oftile_rd   = last_ifblock_rd
                                ? (oftiles_rd_cnt == oftiles_tail_reg - 1)
                                : (oftiles_rd_cnt == oftiles_reg - 1);
    assign iftiles_rd_cnt_en    = oftiles_rd_cnt_en && ((ifblock_rd_cnt == ifblock_reg - 1) && (oftiles_rd_cnt == oftiles_tail_reg - 1) || (oftiles_rd_cnt == oftiles_reg - 1));
    assign oftiles_rd_cnt_en    = fltbuf_comp_donepass_o;
    assign ifblock_rd_cnt_en    = end_layer;
    assign height_rd_cnt_en     = iftiles_rd_cnt_en && last_iftile_rd;
    assign last_height_rd       = height_rd_cnt == height_reg - 1;
    assign end_layer_nxt        = last_height_rd && height_rd_cnt_en;
    wire [8:0] pass_idx_after;
    wire       pass_valid_after_sel;
    wire       pa0_rd_vld_after;
    wire       pa1_rd_vld_after;
    wire [3:0] filter_rd_cnt_after;
    wire [7:0] iftiles_rd_cnt_after;
    wire [3:0] oftiles_rd_cnt_after;
    wire [6:0] ifblock_rd_cnt_after;
    wire       last_ifblock_rd_after;
    wire       last_oftile_rd_after;
    wire [4:0] actual_rd_filter_after;
    wire [4:0] actual_rd_filter0_after;
    wire [4:0] actual_rd_filter1_after;

    always @(*) begin
        actual_rd_filter    = (last_ifblock_rd && last_oftile_rd) ? ofparr_tail_reg : ofparr_reg;
        actual_rd_filter0   = (actual_rd_filter + actual_rd_filter[0]) >> 1;
        actual_rd_filter1   = actual_rd_filter >> 1;
        cache_rd_en[0]      = pass_valid[pass_idx] && pa0_rd_vld && fltbuf_comp_rdy_i;
        cache_rd_en[1]      = pass_valid[pass_idx] && (|actual_rd_filter1) && pa1_rd_vld && fltbuf_comp_rdy_i;
    end
    assign iftiles_rd_cnt_after = iftiles_rd_cnt_en ? ((last_iftile_rd)     ? 7'd0 : (iftiles_rd_cnt + 1'b1))   : iftiles_rd_cnt;
    assign oftiles_rd_cnt_after = oftiles_rd_cnt_en ? ((last_oftile_rd)     ? 4'd0 : (oftiles_rd_cnt + 1'b1))   : oftiles_rd_cnt;
    assign ifblock_rd_cnt_after = ifblock_rd_cnt_en ? ((last_ifblock_rd)    ? 7'd0 : (ifblock_rd_cnt + 1'b1))   : ifblock_rd_cnt;
    assign filter_rd_cnt_after  = filter_rd_cnt_en  ? ((last_filter_rd)     ? 4'd0 : (filter_rd_cnt + 1'b1))    : filter_rd_cnt;

    assign last_ifblock_rd_after    = (ifblock_rd_cnt_after == ifblock_reg - 1);
    assign last_oftile_rd_after     = last_ifblock_rd_after
                                    ? (oftiles_rd_cnt_after == oftiles_tail_reg - 1)
                                    : (oftiles_rd_cnt_after == oftiles_reg - 1);
    assign actual_rd_filter_after   = (last_ifblock_rd_after && last_oftile_rd_after) ? ofparr_tail_reg : ofparr_reg;
    assign actual_rd_filter0_after  = (actual_rd_filter_after + actual_rd_filter_after[0]) >> 1;
    assign actual_rd_filter1_after  = actual_rd_filter_after >> 1;

    assign pass_idx_after           = done_pass ? (((pass_idx == pass_total - 1) && !en_cfg) ? 9'd0 : (pass_idx + 1'b1)) : pass_idx;
    assign pass_valid_after_sel     = end_layer ? 1'b0 :
                                    ((fltbuf_dma_tlast_i && fltbuf_dma_vld_i && fltsize_reg != 1 || t_last && fltsize_reg == 1) ?
                                    ((pass_idx_after == 0) ? 1'b1 : pass_valid[pass_idx_after - 1'b1]) :
                                    pass_valid[pass_idx_after]);
    assign pa0_rd_vld_after         = done_pass ? 1'b1 :
                                    ((filter_rd_cnt_en && last_filter_rd) ? 1'b0 : pa0_rd_vld);
    assign pa1_rd_vld_after         = done_pass ? 1'b1 :
                                    ((filter_rd_cnt_en && (filter_rd_cnt == actual_rd_filter1 - 1)) ? 1'b0 : pa1_rd_vld);

    always @(posedge clk) begin
        if(inf_rdy_dly) last_filter_rd <= 1'b0;
        else last_filter_rd <= (filter_rd_cnt_after == actual_rd_filter0_after - 1'b1);
    end
    always @(posedge clk) begin
        if(inf_rdy_dly) fltbuf_comp_vld_o <= {(K*M){1'b0}};
        else fltbuf_comp_vld_o <= fltbuf_comp_vld_o_nxt;
    end
    always @(posedge clk) begin
        if(inf_rdy_dly) begin
            end_layer1 <= 0;
            end_layer <= 0;
        end
        else begin
            end_layer1 <= end_layer_nxt;
            end_layer <= end_layer1;
        end
    end

    always @(posedge clk) begin
        if(inf_rdy_dly) iftiles_rd_cnt <= 0;
        else begin
            if(end_layer) iftiles_rd_cnt <= 0;
            else if (iftiles_rd_cnt_en) iftiles_rd_cnt <= (last_iftile_rd) ? 0 : iftiles_rd_cnt + 1;
        end
    end
    always @(posedge clk) begin
        if(inf_rdy_dly) height_rd_cnt <= 0;
        else if (height_rd_cnt_en) height_rd_cnt <= (last_height_rd) ? 0 : height_rd_cnt + 1;
    end
    always @(posedge clk) begin
        if(inf_rdy_dly) oftiles_rd_cnt <= 0;
        else begin
            if(end_layer) oftiles_rd_cnt <= 0;
            else if (oftiles_rd_cnt_en) oftiles_rd_cnt <= (last_oftile_rd) ? 0 : oftiles_rd_cnt + 1;
        end
    end
    always @(posedge clk) begin
        if(inf_rdy_dly) ifblock_rd_cnt <= 0;
        else if (ifblock_rd_cnt_en) ifblock_rd_cnt <= (last_ifblock_rd) ? 0 : ifblock_rd_cnt + 1;
    end
    always @(posedge clk) begin
        if(inf_rdy_dly) fltsize_rd_cnt <= 0;
        else begin
            if(end_layer) fltsize_rd_cnt <= 0;
            else if (fltsize_rd_cnt_en) fltsize_rd_cnt <= (last_fltsize_rd) ? 0 : fltsize_rd_cnt + 1;
        end
    end
    always @(posedge clk) begin
        if(inf_rdy_dly) filter_rd_cnt <= 0;
        else begin 
            if(end_layer) filter_rd_cnt <= 0;
            else if (filter_rd_cnt_en) filter_rd_cnt <= (last_filter_rd) ? 0 : filter_rd_cnt + 1;
        end
    end
    always @(posedge clk) begin
        if(inf_rdy_dly) done_pass <= 0;
        else begin
            if(done_pass) done_pass <= 0;
            else if (filter_rd_cnt_en && last_filter_rd) done_pass <= 1;
        end
    end
    assign fltbuf_comp_donepass_o = done_pass;
    always @(posedge clk) begin
        if(inf_rdy_dly) pa0_rd_vld <= 1;
        else begin
            if(fltbuf_comp_donepass_o) pa0_rd_vld <= 1;
            else if (filter_rd_cnt_en && last_filter_rd) pa0_rd_vld <= 0;
        end
    end
    always @(posedge clk) begin
        if(inf_rdy_dly) pa1_rd_vld <= 1;
        else begin
            if(fltbuf_comp_donepass_o) pa1_rd_vld <= 1;
            else if (filter_rd_cnt_en && (filter_rd_cnt == actual_rd_filter1 - 1)) pa1_rd_vld <= 0;
        end
    end
    always @(posedge clk) begin
        if(inf_rdy_dly) pass_idx <= 0;
        else begin
            if(fltbuf_comp_donepass_o) pass_idx <= ((pass_idx == pass_total - 1) && !en_cfg)? 0 : pass_idx + 1;
        end
    end
    ///////////////////////////////WRITE CONTROL//////////////////////////////////////

    // Các tín hiệu điều khiển nội bộ cho K*M khối cache
    
    
    // Khởi tạo K * M khối fltbuf_cache
    
    
    assign last_iftile_wr       = (iftiles_wr_cnt == iftiles_reg - 1);
    
    assign last_ifblock_wr      = (ifblock_wr_cnt == ifblock_reg - 1);
    wire last_oftile_wr;
    assign last_oftile_wr       = last_ifblock_wr
                                ? (oftiles_wr_cnt == oftiles_tail_reg - 1)
                                : (oftiles_wr_cnt == oftiles_reg - 1);
    assign iftiles_wr_cnt_en    = oftiles_wr_cnt_en && ((ifblock_wr_cnt == ifblock_reg - 1) && (oftiles_wr_cnt == oftiles_tail_reg - 1) || (oftiles_wr_cnt == oftiles_reg - 1));
    assign oftiles_wr_cnt_en    = fltbuf_dma_tlast_i && fltbuf_dma_vld_i;
    assign ifblock_wr_cnt_en    = iftiles_wr_cnt_en && (iftiles_wr_cnt == iftiles_reg - 1);
    integer m, k;
    
    assign wr_val               = fltbuf_dma_vld_i && (fltbuf_dma_tlast_i && !(actual_wr_channel[0] && actual_wr_filter[0]) || !fltbuf_dma_tlast_i);
    always @(*) begin
        actual_wr_filter    = (last_ifblock_wr && last_oftile_wr) ? ofparr_tail_reg : ofparr_reg;
        actual_wr_channel   = last_iftile_wr ? ifparr_tail_reg : ifparr_reg;
        for (m = 0; m < M; m = m + 1) begin
            for (k = 0; k < K; k = k + 1) begin
                wr_map[m][k] = 1'b0;
            end
        end
        wr_map[pa_wr_cnt][channel_wr_cnt] = wr_val;
    end
    always @(posedge clk) begin
        if(inf_rdy_dly) iftiles_wr_cnt <= 0;
        else if (iftiles_wr_cnt_en) iftiles_wr_cnt <= (last_iftile_wr) ? 0 : iftiles_wr_cnt + 1;
    end
    
    integer j;
    always @(posedge clk) begin
        t_last <= fltbuf_dma_tlast_i && fltbuf_dma_vld_i;
    end
    always @(posedge clk) begin
        if(inf_rdy_dly) pass_valid <= 512'b0;
        else begin
            if(end_layer) pass_valid <= 512'b0;
            else if (fltbuf_dma_tlast_i && fltbuf_dma_vld_i && fltsize_reg != 1 || t_last && fltsize_reg == 1) begin
                pass_valid[0] <= 1;
                for(j = 1; j < 512; j = j + 1) pass_valid[j] <= pass_valid[j - 1];
            end
        end
    end
    always @(posedge clk) begin
        if(inf_rdy_dly) oftiles_wr_cnt <= 0;
        else if (oftiles_wr_cnt_en) oftiles_wr_cnt <= (last_oftile_wr) ? 0 : oftiles_wr_cnt + 1;
    end
    always @(posedge clk) begin
        if(inf_rdy_dly) ifblock_wr_cnt <= 0;
        else if (ifblock_wr_cnt_en) ifblock_wr_cnt <= (last_ifblock_wr) ? 0 : ifblock_wr_cnt + 1;
    end
    always @(posedge clk) begin
        if(inf_rdy_dly) fltsize_wr_cnt <= 0;
        else if (fltsize_wr_cnt_en) fltsize_wr_cnt <= (last_fltsize_wr) ? 0 : fltsize_wr_cnt + 1;
    end
    always @(posedge clk) begin
        if(inf_rdy_dly) channel_wr_cnt <= 0;
        else if (channel_wr_cnt_en) channel_wr_cnt <= (last_channel_wr) ? 0 : channel_wr_cnt + 1;
    end
    always @(posedge clk) begin
        if(inf_rdy_dly) filter_wr_cnt <= 0;
        else if (filter_wr_cnt_en) filter_wr_cnt <= (last_filter_wr) ? 0 : filter_wr_cnt + 1;
    end
    always @(posedge clk) begin
        if(inf_rdy_dly) pa_wr_cnt <= 0;
        else begin
            if(fltbuf_dma_tlast_i && fltbuf_dma_vld_i) pa_wr_cnt <= 0;
            else if (pa_wr_cnt_en) pa_wr_cnt <= 1;
        end
    end
    wire [K*M-1:0] mem_vld;
    genvar i;
    generate
        for (i = 0; i < K * M; i = i + 1) begin : gen_fltbuf_cache
            assign cache_wr_en[i]           = wr_map[i/K][i%K];
            assign fltbuf_comp_vld_o_nxt[i] = !(end_layer_nxt || end_layer1) && mem_vld[i] && pass_valid_after_sel && ((i < K) ? pa0_rd_vld_after : pa1_rd_vld_after && (|actual_rd_filter1));
            
            fltbuf_cache #(
                .WIDTH(DATA_WIDTH), 
                .DEPTH(DEPTH)       // Bạn có thể map tham số DEPTH của filter_buf xuống đây
            ) u_cache_inft (
                .clk(clk),
                .rst_n(rst_n),
                .wr_en(cache_wr_en[i]),
                .rd_en(cache_rd_en[i/K]),
                .din(fltbuf_dma_data_i), // Tùy chỉnh nguồn dữ liệu DMA đưa vào từng cache
                .zp(zp),
                .clear_rd(((pass_idx == pass_total - 1) && !en_cfg && filter_rd_cnt_en && last_filter_rd)),
                .clear_rd_wr(end_layer),
                // Gom dout của từng cache vào bus data output tổng
                .dout(fltbuf_comp_data_o[(i+1)*DATA_WIDTH - 1 : i*DATA_WIDTH]), 
                .full(),
                // Nối trực tiếp cờ vld từ cache ra port tổng
                .vld_o(mem_vld[i]), 
                .end_data()
            );
        end
    endgenerate
    (* keep = "false" *) wire _unused_sink;
    assign _unused_sink = &{
        actual_rd_filter0,
        actual_rd_filter1_after,
        iftiles_rd_cnt_after
    };
endmodule
