`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 04/21/2026 02:18:47 PM
// Design Name: 
// Module Name: scale_ReLU
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


module scale_ReLU #(
    parameter DATA_OUT_WIDTH = 8,
    parameter DATA_IN_WIDTH = 32
)(
    input                                       clk,
    input                                       rst_n,
                
    input           [7:0]                       scale_inf_width_i,
    input   signed  [31:0]                      scale_inf_mult_i,
    input           [5:0]                       scale_inf_mult_shift_i,
    input   signed  [31:0]                      scale_inf_alphamult_i,
    input           [5:0]                       scale_inf_alphamult_shift_i,
    input   signed  [7:0]                       scale_inf_zpy_i,
    input   signed  [7:0]                       scale_inf_qmin_i,
    input   signed  [7:0]                       scale_inf_qmax_i,
    input                                       scale_inf_is_leaky_ReLU_i,

    input   signed  [DATA_IN_WIDTH-1:0]         scale_bias_data_i,
    input                                       scale_bias_vld_i,
    output                                      scale_bias_rdy_o,

    input   signed  [DATA_IN_WIDTH-1:0]         scale_comp_data_i,
    input                                       scale_comp_vld_i,
    output                                      scale_comp_rdy_o,

    input                                       scale_ofbuf_rdy_i,
    output  signed  [DATA_OUT_WIDTH-1:0]        scale_ofbuf_data_o,
    output                                      scale_ofbuf_vld_o
    );

    reg             [7:0]                       scale_inf_width_reg;
    reg  signed     [DATA_IN_WIDTH-1:0]         scale_inf_mult_reg;
    reg             [5:0]                       scale_inf_mult_shift_reg;
    reg  signed     [31:0]                      scale_inf_alphamult_reg;
    reg             [5:0]                       scale_inf_alphamult_shift_reg;
    reg  signed     [7:0]                       scale_inf_zpy_reg;
    reg  signed     [7:0]                       scale_inf_qmin_reg;
    reg  signed     [7:0]                       scale_inf_qmax_reg;
    reg                                         scale_inf_is_leaky_ReLU_reg;
    reg  signed     [DATA_IN_WIDTH-1:0]         bias_data_q;
    reg                                         bias_vld_q;
    reg             [7:0]                       count_w_q;
    reg  signed     [63:0]                      round_value;
    reg  signed     [63:0]                      round_value_alpha;

    reg             [10:0]          data_vld_q; //Pipeline 11 STAGES
    reg  signed     [31:0]          data_stage_0_q;
    reg  signed     [63:0]          data_stage_1_q;
    reg  signed     [63:0]          data_stage_2_q;
    reg  signed     [63:0]          data_stage_3_q;
    reg  signed     [31:0]          data_stage_4_q;
    reg  signed     [63:0]          data_stage_5_q;
    reg  signed     [31:0]          data_stage_5_cross_q;
    reg  signed     [63:0]          data_stage_6_q;
    reg  signed     [31:0]          data_stage_6_cross_q;
    reg  signed     [31:0]          data_stage_7_q;
    reg  signed     [31:0]          data_stage_7_cross_q;
    reg  signed     [31:0]          data_stage_8_q;
    reg  signed     [31:0]          data_stage_9_q;
    reg  signed     [7:0]           data_stage_10_q;

    wire            [10:0]          pipe_rdy;
    wire signed     [31:0]          data_stage_0_d;
    wire signed     [63:0]          data_stage_1_d;
    wire signed     [63:0]          data_stage_2_d;
    wire signed     [63:0]          data_stage_3_d;
    wire signed     [31:0]          data_stage_4_d;
    wire signed     [63:0]          data_stage_5_d;
    wire signed     [63:0]          data_stage_6_d;
    wire signed     [31:0]          data_stage_7_d;
    wire signed     [31:0]          data_stage_8_d;
    wire signed     [31:0]          data_stage_9_d;
    wire signed     [7:0]           data_stage_10_d;

    
    assign scale_bias_rdy_o     = !bias_vld_q || ((count_w_q == scale_inf_width_reg - 1) && scale_comp_rdy_o && scale_comp_vld_i);//change assign scale_bias_rdy_o     = !bias_vld_q || (count_w_q == scale_inf_width_reg - 1)
    assign scale_comp_rdy_o     = bias_vld_q && pipe_rdy[0];
    assign scale_ofbuf_data_o   = data_stage_10_q;
    assign scale_ofbuf_vld_o    = data_vld_q[10];

    // Per-stage ready chain.
    // pipe_rdy[i] = 1 when stage i can accept new data because:
    //   1) stage i is empty, or
    //   2) some downstream stage can move/accept, or
    //   3) the output buffer is ready.
    // Expanded form:
    //   pipe_rdy[i] = !data_vld_q[i] || !data_vld_q[i+1] || ... ||
    //                 !data_vld_q[10] || scale_ofbuf_rdy_i
    assign pipe_rdy[10] = !data_vld_q[10] || scale_ofbuf_rdy_i;
    always @(posedge clk) begin
        if (scale_bias_vld_i && scale_bias_rdy_o) begin
            scale_inf_width_reg <= scale_inf_width_i;
            scale_inf_mult_reg <= scale_inf_mult_i;
            scale_inf_mult_shift_reg <= scale_inf_mult_shift_i;
            scale_inf_alphamult_reg <= scale_inf_alphamult_i;
            scale_inf_alphamult_shift_reg <= scale_inf_alphamult_shift_i;
            scale_inf_zpy_reg <= scale_inf_zpy_i;
            scale_inf_qmin_reg <= scale_inf_qmin_i;
            scale_inf_qmax_reg <= scale_inf_qmax_i;
            scale_inf_is_leaky_ReLU_reg <= scale_inf_is_leaky_ReLU_i;
        end
        round_value <= |scale_inf_mult_shift_reg ? 64'sd1 << (scale_inf_mult_shift_reg - 1) : 64'sd0;
        round_value_alpha <= |scale_inf_alphamult_shift_reg ? 64'sd1 << (scale_inf_alphamult_shift_reg - 1) : 64'sd0;
    end

    always @(posedge clk) begin
        if(!rst_n) begin
            bias_vld_q <= 0;
        end else if(scale_bias_rdy_o) begin
            bias_vld_q <= scale_bias_vld_i; //change
        end
    end
    always @(posedge clk) begin
        if(scale_bias_rdy_o && scale_bias_vld_i) begin
            bias_data_q <= scale_bias_data_i;
        end
    end

    always @(posedge clk) begin
        if(!rst_n) begin
            count_w_q <= 0;
        end else if(scale_comp_rdy_o && scale_comp_vld_i) begin
            count_w_q <= (count_w_q == scale_inf_width_reg - 1) ? 0 : count_w_q + 1;
        end
    end

    genvar stage;
    generate
        for(stage = 0; stage < 10; stage = stage + 1) begin : gen_pipe_rdy
            assign pipe_rdy[stage] = !data_vld_q[stage] || pipe_rdy[stage+1];
        end
    endgenerate

    // Valid pipeline. Each stage has its own ready condition instead of using
    // one global pipe_en for all 11 stages.
    always @(posedge clk) begin
        if(!rst_n) begin
            data_vld_q <= 11'd0;
        end else begin
            if(pipe_rdy[0])  data_vld_q[0]  <= bias_vld_q && scale_comp_vld_i;
            if(pipe_rdy[1])  data_vld_q[1]  <= data_vld_q[0];
            if(pipe_rdy[2])  data_vld_q[2]  <= data_vld_q[1];
            if(pipe_rdy[3])  data_vld_q[3]  <= data_vld_q[2];
            if(pipe_rdy[4])  data_vld_q[4]  <= data_vld_q[3];
            if(pipe_rdy[5])  data_vld_q[5]  <= data_vld_q[4];
            if(pipe_rdy[6])  data_vld_q[6]  <= data_vld_q[5];
            if(pipe_rdy[7])  data_vld_q[7]  <= data_vld_q[6];
            if(pipe_rdy[8])  data_vld_q[8]  <= data_vld_q[7];
            if(pipe_rdy[9])  data_vld_q[9]  <= data_vld_q[8];
            if(pipe_rdy[10]) data_vld_q[10] <= data_vld_q[9];
        end
    end
    
    //======================================================================================
    // Pipeline data-path combinational logic
    // - All *_d signals are defined before the pipeline registers.
    // - Each stage description below matches the corresponding registered stage.
    // - Logic is unchanged; only formatting/grouping/comments are updated.
    //======================================================================================

    //======================================================================================
    //          STAGE 0: ADD BIAS
    //          Input compensation data is added with the latched bias value.
    //======================================================================================
    assign data_stage_0_d  = bias_data_q + scale_comp_data_i;

    //======================================================================================
    //          STAGE 1: MULTIPLY MULTIPLIER
    //          Scale the biased data by the configured multiplier.
    //======================================================================================
    assign data_stage_1_d  = data_stage_0_q * scale_inf_mult_reg;

    //======================================================================================
    //          STAGE 2: ADD ROUND VALUE
    //          Add rounding compensation before the main right shift.
    //======================================================================================
    assign data_stage_2_d  = data_stage_1_q + round_value - ({64{|scale_inf_mult_shift_reg && data_stage_1_q[63]}} & 64'sd1);

    //======================================================================================
    //          STAGE 3: SHIFT
    //          Apply arithmetic right shift using the configured multiplier shift.
    //======================================================================================
    assign data_stage_3_d  = |scale_inf_mult_shift_reg ? data_stage_2_q >>> scale_inf_mult_shift_reg : data_stage_2_q;

    //======================================================================================
    //          STAGE 4: CLAMP TO 32 BIT
    //          Saturate shifted 64-bit data into signed 32-bit range.
    //======================================================================================
    assign data_stage_4_d  = (|data_stage_3_q[63:31] && !(&data_stage_3_q[63:31])) ?
                             (data_stage_3_q[63] ? 32'h8000_0000 : 32'h7FFF_FFFF) :
                             data_stage_3_q[31:0];

    //======================================================================================
    //          STAGE 5: MULTIPLY WITH ALPHA MULTIPLIER
    //          Prepare the leaky-ReLU negative branch by multiplying alpha multiplier.
    //          data_stage_5_cross_q carries the unclamped 32-bit value for branch select.
    //======================================================================================
    assign data_stage_5_d  = data_stage_4_q * scale_inf_alphamult_reg;

    //======================================================================================
    //          STAGE 6: ADD ROUND ALPHA VALUE
    //          Add rounding compensation for the alpha path.
    //          data_stage_6_cross_q continues carrying the original branch-select value.
    //======================================================================================
    assign data_stage_6_d  = data_stage_5_q + round_value_alpha - ({64{|scale_inf_alphamult_shift_reg && data_stage_5_q[63]}} & 64'sd1);

    //======================================================================================
    //          STAGE 7: ALPHA SHIFT
    //          Apply arithmetic right shift to the alpha path.
    //          data_stage_7_cross_q continues carrying the original branch-select value.
    //======================================================================================
    assign data_stage_7_d  = |scale_inf_alphamult_shift_reg ? data_stage_6_q >>> scale_inf_alphamult_shift_reg : data_stage_6_q;

    //======================================================================================
    //          STAGE 8: CHOOSE RELU / LEAKY RELU OUTPUT
    //          If original value is negative, choose alpha path for leaky ReLU or zero for ReLU.
    //          If original value is non-negative, keep the original value.
    //======================================================================================
    assign data_stage_8_d  = data_stage_7_cross_q[31] ?
                             (scale_inf_is_leaky_ReLU_reg ? data_stage_7_q : 32'sd0) :
                             data_stage_7_cross_q;

    //======================================================================================
    //          STAGE 9: ADD ZPY
    //          Add output zero-point offset before final output clamping.
    //======================================================================================
    assign data_stage_9_d  = data_stage_8_q + scale_inf_zpy_reg;

    //======================================================================================
    //          STAGE 10: CLAMP min(qmax, max(qmin, data_stage_9_q))
    //          Saturate final result to configured quantized output range.
    //======================================================================================
    assign data_stage_10_d = data_stage_9_q > scale_inf_qmax_reg ? scale_inf_qmax_reg :
                             data_stage_9_q < scale_inf_qmin_reg ? scale_inf_qmin_reg :
                             data_stage_9_q;

    //======================================================================================
    // Pipeline data registers
    // Each stage register advances independently when its own pipe_rdy bit is asserted.
    // This lets bubbles move through the pipeline instead of freezing all stages until
    // only the final stage can move.
    //======================================================================================
    always @(posedge clk) begin
        if(pipe_rdy[0]) begin
            // STAGE 0 register: bias-added data
            data_stage_0_q       <= data_stage_0_d;
        end

        if(pipe_rdy[1]) begin
            // STAGE 1 register: multiplier result
            data_stage_1_q       <= data_stage_1_d;
        end

        if(pipe_rdy[2]) begin
            // STAGE 2 register: rounded multiplier result
            data_stage_2_q       <= data_stage_2_d;
        end

        if(pipe_rdy[3]) begin
            // STAGE 3 register: shifted multiplier result
            data_stage_3_q       <= data_stage_3_d;
        end

        if(pipe_rdy[4]) begin
            // STAGE 4 register: signed 32-bit clamped result
            data_stage_4_q       <= data_stage_4_d;
        end

        if(pipe_rdy[5]) begin
            // STAGE 5 registers: alpha multiply path and original-value cross path
            data_stage_5_q       <= data_stage_5_d;
            data_stage_5_cross_q <= data_stage_4_q;
        end

        if(pipe_rdy[6]) begin
            // STAGE 6 registers: rounded alpha path and original-value cross path
            data_stage_6_q       <= data_stage_6_d;
            data_stage_6_cross_q <= data_stage_5_cross_q;
        end

        if(pipe_rdy[7]) begin
            // STAGE 7 registers: shifted alpha path and original-value cross path
            data_stage_7_q       <= data_stage_7_d;
            data_stage_7_cross_q <= data_stage_6_cross_q;
        end

        if(pipe_rdy[8]) begin
            // STAGE 8 register: ReLU / leaky-ReLU selected data
            data_stage_8_q       <= data_stage_8_d;
        end

        if(pipe_rdy[9]) begin
            // STAGE 9 register: zero-point adjusted data
            data_stage_9_q       <= data_stage_9_d;
        end

        if(pipe_rdy[10]) begin
            // STAGE 10 register: final quantized output data
            data_stage_10_q      <= data_stage_10_d;
        end
    end
    
endmodule
