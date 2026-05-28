`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 02/28/2026 03:38:20 PM
// Design Name: 
// Module Name: comp_wr_ctrl
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


module comp_wr_ctrl#(
    parameter WIDTH = 8,
    parameter PE_PER_PU = 12
)(
    input                           clk,
    input                           rst_n,
    input   [3:0]                   cwc_inf_hf_i,
    input   [2:0]                   cwc_inf_stride_i,
    input   [1:0]                   cwc_inf_padding_i,
    input                           cwc_pe_end_layer_nxt_i,
    input                           cwc_pe_end_layer_real_nxt_i,

    input   [PE_PER_PU*WIDTH-1:0]   cwc_pp_data_i,
    input   [PE_PER_PU-1:0]         cwc_pp_vld_i,
    input   [PE_PER_PU-1:0]         cwc_pp_end_data_i,
    output  [PE_PER_PU-1:0]         cwc_pp_rdy_o,
    output  [PE_PER_PU-1:0]         cwc_pp_clear_o,
    output  [PE_PER_PU-1:0]         cwc_pp_pe_is_read_o,

    input                           cwc_pu_swap_en_i,
    
    input                           cwc_scale_rdy_i,
    output                          cwc_scale_vld_o,
    output  [WIDTH-1:0]             cwc_scale_data_o,
    output                          cwc_pu_done_compute_o,
    output                          cwc_pu_done_compute_layer_o
    );
    
    reg     [3:0]                   count_p;
    wire    [3:0]                   count_p_nxt;
    reg     [2:0]                   cwc_inf_stride_i_count;
    wire    [2:0]                   cwc_inf_stride_i_count_nxt;
    reg     [$clog2(PE_PER_PU)-1:0] id;
    reg                             end_layer;
    reg                             end_layer_real;
    wire    [$clog2(PE_PER_PU)-1:0] id_nxt;
    reg     [PE_PER_PU-1:0]         pp_clear_reg;
    // reg     [PE_PER_PU-1:0]         is_read_reg;
    wire    [PE_PER_PU-1:0]         pp_clear_nxt;
    // wire    [PE_PER_PU-1:0]         is_read_nxt;

    wire                            is_add_cwc_inf_padding_i_data;
    wire                            vld_id;
    wire                            vld_id_nxt;
    wire                            end_data_id;
    wire    [4:0]                   next_id_sum;

    posedge_detection a(
        .clk(clk),
        .rst_n(rst_n),
        .signal_i(end_layer && !(|cwc_pp_vld_i)),
        .signal_o(cwc_pu_done_compute_o)
    );
    assign cwc_pu_done_compute_layer_o = end_layer_real && !(|cwc_pp_vld_i);
    assign cwc_pp_rdy_o         = {PE_PER_PU{cwc_scale_rdy_i && cwc_scale_vld_o}} & (1'b1 << id);
    assign end_data_id          = cwc_pp_end_data_i[id]; //change assign end_data_id          = |cwc_pp_end_data_i;
    assign vld_id               = (id < PE_PER_PU) ? cwc_pp_vld_i[id] && !pp_clear_reg[id]: 1'b0;
    assign cwc_scale_vld_o      = vld_id;
    assign cwc_pp_pe_is_read_o  = {PE_PER_PU{~end_layer}};
    assign next_id_sum          = {1'b0, id} + {1'b0, cwc_inf_hf_i};
    assign vld_id_nxt           = (next_id_sum < PE_PER_PU) ? cwc_pp_vld_i[next_id_sum] && !pp_clear_reg[next_id_sum]: 1'b0;
    assign cwc_scale_data_o     = (id < PE_PER_PU) ? cwc_pp_data_i[id*WIDTH +: WIDTH] : {WIDTH{1'b0}};
    assign is_id_nxt_vld        = vld_id_nxt;
    assign is_add_cwc_inf_padding_i_data = end_layer && !cwc_pu_swap_en_i;
    assign id_nxt               = is_id_nxt_vld ? (id + cwc_inf_hf_i) : (is_add_cwc_inf_padding_i_data ? (id % cwc_inf_hf_i - (cwc_inf_stride_i - cwc_inf_stride_i_count)) : (cwc_inf_hf_i - 1));
    assign count_p_nxt          = count_p + 1;
    assign cwc_inf_stride_i_count_nxt = (cwc_inf_stride_i_count == cwc_inf_stride_i - 1) ? 0 : cwc_inf_stride_i_count + 1;
    
    always @(posedge clk) begin
        if(!rst_n) begin
            end_layer <= 0;
        end else begin
            if(cwc_pu_swap_en_i) begin
                end_layer   <= cwc_pe_end_layer_nxt_i;
            end
        end
    end
    always @(posedge clk) begin
        if(!rst_n) begin
            end_layer_real <= 0;
        end else begin
            if(cwc_pu_swap_en_i) begin
                end_layer_real   <= cwc_pe_end_layer_real_nxt_i;
            end
        end
    end
    always @(posedge clk) begin
        if(!rst_n) id          <= 0;
        else begin 
            if(cwc_pu_swap_en_i) begin
                id          <= cwc_inf_hf_i - 1;
            end 
            else if(!vld_id || end_data_id && vld_id && cwc_scale_rdy_i) begin
                id          <= id_nxt;
            end
        end
    end
    always @(posedge clk) begin
        if(!rst_n) begin
            count_p     <= 0;
        end else begin
            if(is_add_cwc_inf_padding_i_data) begin
                count_p <= 0;
            end else if((cwc_pu_swap_en_i && ((count_p + cwc_inf_padding_i) != cwc_inf_hf_i))) begin
                count_p <= count_p_nxt;
            end
        end
       
    end
    always @(posedge clk) begin
        if(!rst_n) begin
            cwc_inf_stride_i_count <= 0;
        end
        else begin
            if(is_add_cwc_inf_padding_i_data) begin
                cwc_inf_stride_i_count <= 0;
            end else if(cwc_pu_swap_en_i && (count_p + cwc_inf_padding_i) == cwc_inf_hf_i) begin
                cwc_inf_stride_i_count <= cwc_inf_stride_i_count_nxt;
            end
        end 
    end

    genvar i;
    generate
        for(i = 0; i < PE_PER_PU; i = i + 1) begin : pp_clear_gen
            wire        [3:0]   i_mod_cwc_inf_hf_i;
            wire                cwc_inf_stride_i_term_cond;
            wire        [2:0]   cwc_inf_stride_i_term;
            wire signed [6:0]   val_term;
            wire        [6:0]   distance;
            wire                is_val_valid;
            wire                val_mod_cwc_inf_stride_i_zero;
            wire                cwc_inf_padding_i_cond;
            wire                complex_cond_met;
            wire                is_cwc_inf_hf_i_edge;

            assign i_mod_cwc_inf_hf_i           = i % cwc_inf_hf_i;
            assign cwc_inf_stride_i_term_cond   = ((cwc_inf_stride_i_count_nxt == 0) && ((count_p + cwc_inf_padding_i) == cwc_inf_hf_i)) | ((cwc_inf_stride_i_count == 0) && ((count_p_nxt + cwc_inf_padding_i) == cwc_inf_hf_i));
            assign cwc_inf_stride_i_term        = ((count_p + cwc_inf_padding_i) != cwc_inf_hf_i ) ? 2'b00 : (cwc_inf_stride_i - cwc_inf_stride_i_count_nxt);
            assign val_term                     = $signed({1'b0, cwc_inf_hf_i}) - 1 - $signed({1'b0, i_mod_cwc_inf_hf_i}) - $signed({1'b0, cwc_inf_stride_i_term});
            assign distance                     = $signed({1'b0, cwc_inf_hf_i}) - 1 - $signed({1'b0, i_mod_cwc_inf_hf_i});
            assign is_val_valid                 = (val_term >= 0);
            assign val_mod_cwc_inf_stride_i_zero = (cwc_inf_stride_i == 1) ? 1'b1 :
                                       (cwc_inf_stride_i == 2) ? (val_term[0] == 1'b0) : // Chia hết cho 2 chỉ cần ktra LSB
                                       (cwc_inf_stride_i == 3) ? (val_term == 0 || val_term == 3 || val_term == 6 || val_term == 9 || val_term == 12 || val_term == 15) : 
                                       (cwc_inf_stride_i == 4) ? (val_term[1:0] == 2'b0) : 1'b0;
            assign cwc_inf_padding_i_cond       = cwc_inf_padding_i >= distance;
            assign complex_cond_met             = is_val_valid & cwc_inf_padding_i_cond & val_mod_cwc_inf_stride_i_zero;
            assign is_cwc_inf_hf_i_edge         = (i_mod_cwc_inf_hf_i == cwc_inf_hf_i - 1);
            assign pp_clear_nxt[i]              = is_cwc_inf_hf_i_edge ? (cwc_inf_stride_i_term_cond ? 0 : 1)
                                                : (cwc_pe_end_layer_nxt_i & !complex_cond_met) ? 1 : 0;
            
            // assign is_read_nxt[i] = ~((is_cwc_inf_hf_i_edge && cwc_inf_stride_i_term_cond) || (cwc_pe_end_layer_nxt_i && complex_cond_met));
            always @(posedge clk) begin
                if(!rst_n) begin
                    pp_clear_reg[i] <= 0;
                    // is_read_reg[i]  <= 1;
                end
                if(cwc_pu_swap_en_i) begin
                    pp_clear_reg[i] <= pp_clear_nxt[i];
                    // is_read_reg[i]  <= is_read_nxt[i];
                end
            end
            assign cwc_pp_clear_o[i] = pp_clear_reg[i];
            // assign cwc_pp_pe_is_read_o[i]  = is_read_reg[i];
        end
    endgenerate
endmodule
