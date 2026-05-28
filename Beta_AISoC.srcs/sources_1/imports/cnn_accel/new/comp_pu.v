`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 03/03/2026 10:12:44 PM
// Design Name: 
// Module Name: comp_pu
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


module comp_pu #(
    parameter WIDTH         = 8,         // Độ rộng dữ liệu đầu vào (8-bit)
    parameter ACC_WIDTH     = 32,    // Độ rộng bộ cộng dồn (thường dùng 32-bit cho INT8 MAC)
    parameter PE_PER_PU     = 12,
    parameter DEPTH         = 11,
    parameter K             = 7,
    parameter PPDEPTH       = 640
)(
    input                   clk,
    input                   rst_n,

    //from inftruction
    input           [3:0]           pu_inf_hf_i,
    input           [2:0]           pu_inf_stride_i,
    input           [1:0]           pu_inf_padding_i,
    input   signed  [WIDTH-1:0]     pu_inf_ifc_zp_i,
    input   signed  [WIDTH-1:0]     pu_inf_fltc_zp_i,
    //from ifmap cache
    input                           pu_ifc_end_row_circle_i,
    input                           pu_ifc_end_row_i,
    input                           pu_ifc_end_depth_i,
    input                           pu_ifc_end_layer_i,
    input                           pu_ifc_end_layer_real_i,
    input                           pu_ifc_vld_i,
    input           [K*WIDTH-1:0]   pu_ifc_data_i,
    output                          pu_ifc_rdy_o,
    //from and to filter buf
    input           [K-1:0]         pu_fltbuf_vld_i,
    input           [K*WIDTH-1:0]   pu_fltbuf_data_i,
    input                           pu_fltbuf_done_pass_i,
    output                          pu_fltbuf_rdy_o,
    output                          pu_comp_vld_o,
    input                           pu_comp_vld_i,
    //from and to scale
    input                           pu_swap_fltc_i,
    output                          pu_swap_fltc_o,
    input                           pu_scale_rdy_i,
    output                          pu_scale_vld_o,
    output          [ACC_WIDTH-1:0] pu_scale_data_o,
    output                          pu_pa_done_compute_o,
    output                          pu_pa_done_compute_layer_o
    );

    wire                            clr_ch_flt;
    reg                             pp_id;
    
    // wire rst_n;
    wire    [K-1:0]                     fltc_fltbuf_vld_i;
    wire    [K*WIDTH-1:0]               fltc_fltbuf_data_i;
    wire    [K-1:0]                     fltc_fltbuf_rdy_o;
    wire    [3:0]                       fltc_inf_hf_i;
    wire                                fltc_fltbuf_done_pass_i;
    wire                                fltc_pe_rdy_i;
    wire                                fltc_pu_clr_ch_flt_i;
    wire    [K*PE_PER_PU-1:0]           fltc_pe_vld_flat_o;
    reg     [PE_PER_PU-1:0]             fltc_pe_vld_o;
    wire    [K*PE_PER_PU*WIDTH-1:0]     fltc_pe_data_o;

    wire    [3:0]                       pe_inf_hf_i;
    wire                                pe_ifc_end_row_circle_i;
    wire                                pe_ifc_end_depth_i;
    wire                                pe_ifc_end_layer_i;
    wire                                pe_ifc_end_layer_real_i;
    wire                                pe_ifc_vld_i;
    wire    [K*WIDTH-1:0]               pe_ifc_data_i;
    wire    [PE_PER_PU-1:0]             pe_fltc_vld_i;
    wire    [K*PE_PER_PU*WIDTH-1:0]     pe_fltc_data_i;
    wire    [PE_PER_PU*ACC_WIDTH-1:0]   pe_pp_pre_data_i;
    wire    [PE_PER_PU-1:0]             pe_ifc_fltc_rdy_o;
    wire    [PE_PER_PU-1:0]             pe_pp_pre_rd_o;
    wire    [PE_PER_PU*ACC_WIDTH-1:0]   pe_pp_cur_data_i;
    wire    [PE_PER_PU-1:0]             pe_pp_cur_rd_o;
    wire    [PE_PER_PU-1:0]             pe_pp_wr_o;
    wire    [PE_PER_PU*ACC_WIDTH-1:0]   pe_pp_data_o;
    wire    signed  [WIDTH-1:0]         pe_ifc_zp_i;
    wire    signed  [WIDTH-1:0]         pe_fltc_zp_i;

    wire                                pp_pu_id_i;
    wire    [PE_PER_PU-1:0]             pp_pe_wr_en_i;
    wire    [PE_PER_PU-1:0]             pp_pe_rd_ena_i;
    wire    [PE_PER_PU-1:0]             pp_pe_rd_enb_i;
    wire    [PE_PER_PU-1:0]             pp_cwc_clr_i;
    wire    [ACC_WIDTH*PE_PER_PU-1:0]   pp_pe_data_i;
    wire    [ACC_WIDTH*PE_PER_PU-1:0]   pp_pe_data_a_o;
    wire    [PE_PER_PU-1:0]             pp_pe_vld_o;
    wire    [ACC_WIDTH*PE_PER_PU-1:0]   pp_pe_cwc_data_b_o;
    wire    [PE_PER_PU-1:0]             pp_cwc_end_data_o;
    wire    [PE_PER_PU-1:0]             pe_cwc_end_layer_o;
    wire    [PE_PER_PU-1:0]             pe_cwc_end_layer_real_o;
    wire    [PE_PER_PU-1:0]             pe_cwc_swap_en_o;

    wire    [3:0]                       cwc_inf_hf_i;
    wire    [2:0]                       cwc_inf_stride_i;
    wire    [1:0]                       cwc_inf_padding_i;
    wire                                cwc_pe_end_layer_nxt_i;
    wire                                cwc_pe_end_layer_real_nxt_i;
    wire    [ACC_WIDTH*PE_PER_PU-1:0]   cwc_pp_data_i;
    wire    [PE_PER_PU-1:0]             cwc_pp_vld_i;
    wire    [K-1:0]                     swap_fltc_o;
    wire    [PE_PER_PU-1:0]             cwc_pp_end_data_i;
    wire    [PE_PER_PU-1:0]             cwc_pp_rdy_o;
    wire    [PE_PER_PU-1:0]             cwc_pp_clear_o;
    wire    [PE_PER_PU-1:0]             cwc_pp_pe_is_read_o;
    wire    [ACC_WIDTH*PE_PER_PU-1:0]   data_pre_mask;
    wire                                cwc_pu_swap_en_i;
    wire                                cwc_scale_rdy_i;
    wire                                cwc_scale_vld_o;
    wire    [ACC_WIDTH-1:0]             cwc_scale_data_o;
    wire                                cwc_pu_done_compute_o;
    wire                                cwc_pu_done_compute_layer_o;

    reg     [3:0]                       pu_inf_hf_reg;
    reg     [2:0]                       pu_inf_stride_reg;
    reg     [1:0]                       pu_inf_padding_reg;
    reg     [WIDTH-1:0]                 pu_inf_ifc_zp_reg;
    reg     [WIDTH-1:0]                 pu_inf_fltc_zp_reg;

    always @(posedge clk) begin
        pu_inf_hf_reg       <= pu_inf_hf_i;
        pu_inf_stride_reg   <= pu_inf_stride_i;
        pu_inf_padding_reg  <= pu_inf_padding_i;
        pu_inf_ifc_zp_reg   <= pu_inf_ifc_zp_i;
        pu_inf_fltc_zp_reg  <= pu_inf_fltc_zp_i;
    end

    assign clr_ch_flt               = pu_ifc_end_row_i && pe_ifc_fltc_rdy_o[0];
    assign pu_fltbuf_rdy_o          = fltc_fltbuf_rdy_o[0];
    assign pu_ifc_rdy_o             = pe_ifc_fltc_rdy_o[0];
    assign pu_scale_vld_o           = cwc_scale_vld_o;
    assign pu_scale_data_o          = cwc_scale_data_o;
    assign pu_pa_done_compute_o     = cwc_pu_done_compute_o;
    assign pu_pa_done_compute_layer_o = cwc_pu_done_compute_layer_o;
    assign pu_swap_fltc_o           = swap_fltc_o[0];
    
    always @(posedge clk) begin
        if(!rst_n) begin
            pp_id <= 0;
        end else if(pe_cwc_swap_en_o[0]) begin
            pp_id <= ~pp_id;
        end
    end
    
    assign fltc_fltbuf_vld_i        = pu_fltbuf_vld_i;
    assign fltc_fltbuf_done_pass_i  = pu_fltbuf_done_pass_i;
    assign fltc_fltbuf_data_i       = pu_fltbuf_data_i;
    assign fltc_inf_hf_i            = pu_inf_hf_reg;
    assign fltc_pu_clr_ch_flt_i     = clr_ch_flt;
    assign fltc_pe_rdy_i            = pe_ifc_fltc_rdy_o[0];
    
    genvar j;
    generate
        for(j = 0; j < K; j = j + 1) begin: gen_fltc
            filter_cache #(
            .WIDTH(WIDTH),
            .DEPTH(11),
            .PE_PER_PU(PE_PER_PU)
        ) flt_cache_uut (
            .clk                        (clk),
            .rst_n                      (rst_n),
            .fltc_fltbuf_vld_i          (fltc_fltbuf_vld_i[j]),
            .fltc_fltbuf_done_pass_i    (fltc_fltbuf_done_pass_i),
            .fltc_fltbuf_data_i         (fltc_fltbuf_data_i[j*WIDTH +: WIDTH]),
            .zp                         (pu_inf_fltc_zp_reg),
            .fltc_fltbuf_rdy_o          (fltc_fltbuf_rdy_o[j]),
            .fltc_inf_hf_i              (fltc_inf_hf_i),
            .swap_fltc_i                (pu_swap_fltc_i),
            .swap_fltc_o                (swap_fltc_o[j]),
            
            .fltc_pe_rdy_i              (fltc_pe_rdy_i),
            .fltc_pu_clr_ch_flt_i       (fltc_pu_clr_ch_flt_i),
            .fltc_pe_vld_o              (fltc_pe_vld_flat_o[j*PE_PER_PU +: PE_PER_PU]),
            .fltc_pe_data_o             (fltc_pe_data_o[j*PE_PER_PU*WIDTH +: PE_PER_PU*WIDTH])
        );
        end
    endgenerate

    integer t;
    always @(*) begin
        fltc_pe_vld_o = 0;
        for(t = 0; t < K; t = t + 1) begin
            fltc_pe_vld_o = fltc_pe_vld_o | fltc_pe_vld_flat_o[t* PE_PER_PU +: PE_PER_PU];
        end
    end

    assign pe_ifc_zp_i                  = pu_inf_ifc_zp_reg;
    assign pe_fltc_zp_i                 = pu_inf_fltc_zp_reg;
    assign pe_inf_hf_i                  = pu_inf_hf_reg;
    assign pe_ifc_end_row_circle_i      = pu_ifc_end_row_circle_i;
    assign pe_ifc_end_depth_i           = pu_ifc_end_depth_i;
    assign pe_ifc_end_layer_i           = pu_ifc_end_layer_i;
    assign pe_ifc_end_layer_real_i      = pu_ifc_end_layer_real_i;
    assign pe_ifc_vld_i                 = pu_ifc_vld_i;
    assign pe_ifc_data_i                = pu_ifc_data_i;
    assign pe_fltc_vld_i                = fltc_pe_vld_o;
    assign pe_pp_pre_data_i             = pp_pe_cwc_data_b_o & data_pre_mask | pp_pe_data_a_o & ~data_pre_mask;
    assign pe_pp_cur_data_i             = pp_pe_data_a_o;
    assign pu_comp_vld_o                = |pp_pe_vld_o;
    assign data_pre_mask                = {ACC_WIDTH{cwc_pp_pe_is_read_o}}; 
    
    genvar pe, k;
    generate
        for(pe = 0; pe < PE_PER_PU; pe = pe + 1) begin : gen_pe
            for(k = 0; k < K; k = k + 1) begin : gen_k
                assign pe_fltc_data_i[(pe * K + k)*WIDTH +: WIDTH] = fltc_pe_data_o[(k * PE_PER_PU + pe)*WIDTH +: WIDTH];
            end
            
        end
    endgenerate
    
    assign pp_pu_id_i           = pp_id;
    assign pp_pe_wr_en_i        = pe_pp_wr_o;
    assign pp_pe_rd_ena_i       = pe_pp_cur_rd_o;
    assign pp_pe_rd_enb_i       = {1'b0, pe_pp_pre_rd_o[PE_PER_PU - 1 : 1]};
    assign pp_cwc_clr_i         = cwc_pp_clear_o;
    assign pp_pe_data_i         = pe_pp_data_o;
    genvar i;
    generate
        for (i = 0; i < PE_PER_PU; i = i + 1) begin : comp_pe_array
            wire [ACC_WIDTH-1:0] pre_data_tmp;

        // Xử lý riêng logic tránh index âm
            if (i == 0) begin
                assign pre_data_tmp = {ACC_WIDTH{1'b0}};
            end else begin
                assign pre_data_tmp = pe_pp_pre_data_i[(i-1)*ACC_WIDTH +: ACC_WIDTH];
            end
            comp_pe #(
                .ID(i),
                .WIDTH(WIDTH),
                .ACC_WIDTH(ACC_WIDTH),
                .K(K)
            ) comp_pe_uut (
                .clk                        (clk),
                .rst_n                      (rst_n),
                .pe_inf_hf_i                (pe_inf_hf_i), 

                .pe_ifc_end_row_circle_i    (pe_ifc_end_row_circle_i),
                .pe_ifc_end_depth_i         (pe_ifc_end_depth_i),
                .pe_ifc_end_layer_i         (pe_ifc_end_layer_i),
                .pe_ifc_end_layer_real_i    (pe_ifc_end_layer_real_i),
                .pe_ifc_vld_i               (pe_ifc_vld_i),
                .pe_ifc_data_i              (pe_ifc_data_i),
                .pe_ifc_zp_i                (pe_ifc_zp_i),
                .pe_fltc_zp_i               (pe_fltc_zp_i),
                .pe_fltc_vld_i              (pe_fltc_vld_i[i]),
                .pe_fltc_data_i             (pe_fltc_data_i[i*K*WIDTH +: K*WIDTH]),
                .pe_ifc_fltc_rdy_o          (pe_ifc_fltc_rdy_o[i]),

                .pe_pp_pre_data_i           (pre_data_tmp),
                .pe_pp_pre_rd_o             (pe_pp_pre_rd_o[i]),
                .pe_pp_cur_data_i           (pe_pp_cur_data_i[i*ACC_WIDTH +: ACC_WIDTH]),
                .pe_pp_cur_rd_o             (pe_pp_cur_rd_o[i]),
                .pe_pp_vld_i                (pu_comp_vld_i),
                .pe_pp_wr_o                 (pe_pp_wr_o[i]),
                .pe_pp_data_o               (pe_pp_data_o[i*ACC_WIDTH +: ACC_WIDTH]),
                .pe_cwc_end_layer_o         (pe_cwc_end_layer_o[i]),
                .pe_cwc_end_layer_real_o    (pe_cwc_end_layer_real_o[i]),
                .pe_cwc_swap_en_o           (pe_cwc_swap_en_o[i])
            );

            pu_ping_pong_fifo #(
                .WIDTH(ACC_WIDTH),
                .DEPTH(PPDEPTH)
            ) pp_uut (
                .clk                        (clk),
                .rst_n                      (rst_n),
                .pp_pu_id_i                 (pp_pu_id_i),
                .pp_pe_wr_en_i              (pp_pe_wr_en_i[i]),
                .pp_pe_rd_ena_i             (pp_pe_rd_ena_i[i] || (pp_pe_rd_enb_i[i] && ~cwc_pp_pe_is_read_o[i])),
                .pp_pe_rd_enb_i             ((pp_pe_rd_enb_i[i] && cwc_pp_pe_is_read_o[i]) || cwc_pp_rdy_o[i]),
                .pp_cwc_clr_i               (pp_cwc_clr_i[i]),
                .pp_pe_data_i               (pp_pe_data_i[i*ACC_WIDTH +: ACC_WIDTH]),
                .pp_pe_data_a_o             (pp_pe_data_a_o[i*ACC_WIDTH +: ACC_WIDTH]),
                .pp_pe_cwc_data_b_o         (pp_pe_cwc_data_b_o[i*ACC_WIDTH +: ACC_WIDTH]),
                .pp_pe_vld_o                (pp_pe_vld_o[i]),
                .pp_cwc_end_data_o          (pp_cwc_end_data_o[i])
            );
        end
    endgenerate

    

    assign cwc_inf_hf_i             = pu_inf_hf_reg;
    assign cwc_inf_stride_i         = pu_inf_stride_reg;
    assign cwc_inf_padding_i        = pu_inf_padding_reg;
    assign cwc_pe_end_layer_nxt_i   = pe_cwc_end_layer_o[0];
    assign cwc_pe_end_layer_real_nxt_i   = pe_cwc_end_layer_real_o[0];
    assign cwc_pp_data_i            = pp_pe_cwc_data_b_o;
    assign cwc_pp_vld_i             = pp_pe_vld_o;
    assign cwc_pp_end_data_i        = pp_cwc_end_data_o;
    assign cwc_pu_swap_en_i         = pe_cwc_swap_en_o[0];
    assign cwc_scale_rdy_i          = pu_scale_rdy_i;
    
    comp_wr_ctrl #(
        .WIDTH(ACC_WIDTH),
        .PE_PER_PU(PE_PER_PU)
    ) cwc_uut (
        .clk                        (clk),
        .rst_n                      (rst_n),
        .cwc_inf_hf_i               (cwc_inf_hf_i),
        .cwc_inf_stride_i           (cwc_inf_stride_i),
        .cwc_inf_padding_i          (cwc_inf_padding_i),
        .cwc_pe_end_layer_nxt_i     (cwc_pe_end_layer_nxt_i),
        .cwc_pe_end_layer_real_nxt_i(cwc_pe_end_layer_real_nxt_i),
        
        .cwc_pp_data_i              (cwc_pp_data_i),
        .cwc_pp_vld_i               (cwc_pp_vld_i),
        .cwc_pp_end_data_i          (cwc_pp_end_data_i),
        .cwc_pp_rdy_o               (cwc_pp_rdy_o),
        .cwc_pp_clear_o             (cwc_pp_clear_o),
        .cwc_pp_pe_is_read_o        (cwc_pp_pe_is_read_o),
        .cwc_pu_swap_en_i           (cwc_pu_swap_en_i),
        
        .cwc_scale_rdy_i            (cwc_scale_rdy_i),
        .cwc_scale_vld_o            (cwc_scale_vld_o),
        .cwc_scale_data_o           (cwc_scale_data_o),
        .cwc_pu_done_compute_o      (cwc_pu_done_compute_o),
        .cwc_pu_done_compute_layer_o(cwc_pu_done_compute_layer_o)
    );
// =========================================================================
    // Lint Warning Suppression (Dummy Sink)
    // =========================================================================
    // Explicitly consume unused bits to safely suppress unread linting warnings
    (* keep = "false" *) wire _unused_sink; 
    
    assign _unused_sink = &{
        1'b0,                                                               // Pad to ensure reduction AND works cleanly
        fltc_fltbuf_rdy_o[K-1:1],                                           // Unused bits 1 to K-1
        pe_cwc_end_layer_o[PE_PER_PU-1:1],                                  // Unused bits 1 to PE_PER_PU-1
        pe_cwc_end_layer_real_o[PE_PER_PU-1:1],
        pe_cwc_swap_en_o[PE_PER_PU-1:1],                                    // Unused bits 1 to PE_PER_PU-1
        pe_ifc_fltc_rdy_o[PE_PER_PU-1:1],                                   // Unused bits 1 to PE_PER_PU-1
        pe_pp_pre_data_i[PE_PER_PU*ACC_WIDTH-1 : (PE_PER_PU-1)*ACC_WIDTH],  // Unused bits from the final PE 
        pe_pp_pre_rd_o[0],                                                  // Unused bit 0
        swap_fltc_o[K-1:1]                                                  // Unused bits 1 to K-1
    };
endmodule