`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 04/29/2026 11:10:00 PM
// Design Name: 
// Module Name: layer_info
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


module layer_info #(
    parameter DATA_WIDTH = 8
)(
    input                               clk,
    input                               rst_n,

    input                               inf_table_vld_i,
    output                              inf_table_rdy_o,
    input           [7:0]               inf_table_ifheight_i,
    input           [10:0]              inf_table_ifchannel_i,
    input           [10:0]              inf_table_ofchannel_i,
    input           [3:0]               inf_table_hf_i,
    input           [2:0]               inf_table_stride_i,
    input           [1:0]               inf_table_padding_i,
    input           [2:0]               inf_table_ifparr_i,
    input           [1:0]               inf_table_oftile_i,
    input           [4:0]               inf_table_ofparr_i,
    input           [23:0]              inf_table_ifbaddr_i,
    input           [23:0]              inf_table_fltbaddr_i,
    input           [23:0]              inf_table_bias_baddr_i,
    input           [23:0]              inf_table_ofbaddr_i,
    input  signed   [DATA_WIDTH-1:0]    inf_table_ifc_zp_i,
    input  signed   [DATA_WIDTH-1:0]    inf_table_fltc_zp_i,
    input  signed   [31:0]              inf_table_mult_i,
    input           [5:0]               inf_table_mult_shift_i,
    input  signed   [31:0]              inf_table_alphamult_i,
    input           [5:0]               inf_table_alphamult_shift_i,
    input  signed   [7:0]               inf_table_zpy_i,
    input  signed   [7:0]               inf_table_qmin_i,
    input  signed   [7:0]               inf_table_qmax_i,
    input                               inf_table_is_leaky_ReLU_i,

    //ifbuf info
    input                               inf_ifbuf_rdy_i,
    output                              inf_ifbuf_vld_o,
    output          [23:0]              inf_ifbuf_ifbaddr_o,
    output          [7:0]               inf_ifbuf_ifwidth_o,
    output          [10:0]              inf_ifbuf_ifchannel_o,
    output          [3:0]               inf_ifbuf_ifparr_o,
    output          [15:0]              inf_ifbuf_ifsize_o,
    output          [6:0]               inf_ifbuf_ifblock_o,
    output          [3:0]               inf_ifbuf_oftiles_o,
    output          [3:0]               inf_ifbuf_oftiles_tail_o,
    output          [7:0]               inf_ifbuf_iftiles_o,
    output          [8:0]               inf_ifbuf_wp_o,
    output          [1:0]               inf_ifbuf_padding_o,
    output          [DATA_WIDTH-1:0]    inf_ifbuf_ifc_zp_o,
    
    //fltbuf info
    input                               inf_fltbuf_rdy_i,
    output                              inf_fltbuf_vld_o,
    output          [23:0]              inf_fltbuf_fltbaddr_o,
    output          [3:0]               inf_fltbuf_ifparr_o,
    output          [3:0]               inf_fltbuf_ifparr_tail_o,
    output          [6:0]               inf_fltbuf_fltsize_o,
    output          [6:0]               inf_fltbuf_ifblock_o,
    output          [4:0]               inf_fltbuf_ofparr_o,
    output          [4:0]               inf_fltbuf_ofparr_tail_o,
    output          [3:0]               inf_fltbuf_oftiles_o,
    output          [3:0]               inf_fltbuf_oftiles_tail_o,
    output          [7:0]               inf_fltbuf_iftiles_o,
    
    //bias buf info
    input                               inf_bias_rdy_i,
    output                              inf_bias_vld_o,
    output          [23:0]              inf_bias_bias_baddr_o,
    output          [7:0]               inf_bias_ofwidth_o,
    output          [10:0]              inf_bias_ofchannel_o,
    output          [4:0]               inf_bias_burstlen_o,
    output          [4:0]               inf_bias_burstlen_tail_o,
    output          [4:0]               inf_bias_burstlen_lane0_o,
    output          [4:0]               inf_bias_burstlen_tail_lane0_o,

    //comp info
    input                               inf_comp_rdy_i,
    output                              inf_comp_vld_o,
    output          [3:0]               inf_comp_hf_o,
    output          [2:0]               inf_comp_stride_o,
    output          [1:0]               inf_comp_padding_o,
    output          [DATA_WIDTH-1:0]    inf_comp_ifc_zp_o,
    output          [DATA_WIDTH-1:0]    inf_comp_fltc_zp_o,
    output          [7:0]               inf_comp_ofwidth_o,
    output signed   [31:0]              inf_comp_mult_o,
    output          [5:0]               inf_comp_mult_shift_o,
    output signed   [31:0]              inf_comp_alphamult_o,
    output          [5:0]               inf_comp_alphamult_shift_o,
    output signed   [7:0]               inf_comp_zpy_o,
    output signed   [7:0]               inf_comp_qmin_o,
    output signed   [7:0]               inf_comp_qmax_o,
    output                              inf_comp_is_leaky_ReLU_o,

    //ofbuf info - coming soon
    input                               inf_ofbuf_rdy_i,
    output                              inf_ofbuf_vld_o,
    output          [23:0]              inf_ofbuf_ofbaddr_l0_o,    
    output          [23:0]              inf_ofbuf_ofbaddr_l1_o,    
    output          [7:0]               inf_ofbuf_ofwidth_o,       
    output          [15:0]              inf_ofbuf_ofsize_o,        
    output          [6:0]               inf_ofbuf_ofblock_o,       
    output          [4:0]               inf_ofbuf_ofc_bl_l0_o,     
    output          [4:0]               inf_ofbuf_ofc_bl_tail_l0_o,
    output          [4:0]               inf_ofbuf_ofc_bl_l1_o,     
    output          [4:0]               inf_ofbuf_ofc_bl_tail_l1_o
    );
    wire            [7:0]               ifheight;
    wire            [15:0]              ifsize;
    wire            [10:0]              ifchannel;
    wire            [10:0]              ofchannel_lut;
    reg                                 table_rdy;
    reg             [2:0]               count_cycle;
    reg                                 if_vld;
    reg                                 flt_vld;
    reg                                 bias_vld;
    reg                                 comp_vld;
    reg                                 of_vld;
    wire                                rst_cnt;
    posedge_detection d(
        .clk(clk),
        .rst_n(rst_n),
        .signal_i(!(if_vld || flt_vld || bias_vld || comp_vld || of_vld)),//CHANGE .signal_i(!(if_vld || flt_vld || bias_vld || comp_vld || of_vld)),
        .signal_o(rst_cnt)
    );

    always @(posedge clk) begin
        if(!rst_n) begin
            count_cycle <= 3'd0;
        end else begin
            if(!(&count_cycle) && inf_table_vld_i) begin
                count_cycle <= count_cycle + 1;
            end else if(rst_cnt) begin
                count_cycle <= 3'd0;
            end
        end
    end

    always @(posedge clk) begin
        if(!rst_n) begin
            table_rdy <= 1'b0;
        end else begin
            if(count_cycle == 3'b110) begin
                table_rdy <= 1'b1;
            end else if(inf_table_vld_i) begin
                table_rdy <= 1'b0;
            end
        end
    end

    always @(posedge clk) begin
        if(!rst_n) begin
            if_vld <= 1'b0;
        end else begin
            if(count_cycle == 3'b110) begin
                if_vld <= 1'b1;
            end else if(inf_ifbuf_rdy_i) begin
                if_vld <= 1'b0;
            end
        end
    end
    always @(posedge clk) begin
        if(!rst_n) begin
            flt_vld <= 1'b0;
        end else begin
            if(count_cycle == 3'b110) begin
                flt_vld <= 1'b1;
            end else if(inf_fltbuf_rdy_i) begin
                flt_vld <= 1'b0;
            end
        end
    end
    always @(posedge clk) begin
        if(!rst_n) begin
            bias_vld <= 1'b0;
        end else begin
            if(count_cycle == 3'b110) begin
                bias_vld <= 1'b1;
            end else if(inf_bias_rdy_i) begin
                bias_vld <= 1'b0;
            end
        end
    end
    always @(posedge clk) begin
        if(!rst_n) begin
            comp_vld <= 1'b0;
        end else begin
            if(count_cycle == 3'b110) begin
                comp_vld <= 1'b1;
            end else if(inf_comp_rdy_i) begin
                comp_vld <= 1'b0;
            end
        end
    end
    always @(posedge clk) begin
        if(!rst_n) begin
            of_vld <= 1'b0;
        end else begin
            if(count_cycle == 3'b110) begin
                of_vld <= 1'b1;
            end else if(inf_ofbuf_rdy_i) begin
                of_vld <= 1'b0;
            end
        end
    end
    assign ifheight         = inf_table_ifheight_i;
    assign ifsize           = inf_table_ifheight_i * (inf_table_ifheight_i + inf_table_ifheight_i[0]);
    assign ifchannel        = inf_table_ifchannel_i;
    assign ofchannel_lut    = inf_table_ofchannel_i;
    // //==========================================
    // //LOOK UP TABLE FOR IFMAP HEIGHT AND IFMAP SIZE
    // //==========================================
    // always @(*) begin
    //     case(inf_table_ifheight_i)
    //         4'b0000: begin
    //             ifheight    = 227;
    //             ifsize      = 228*227;
    //         end
    //         4'b0001: begin
    //             ifheight    = 224;
    //             ifsize      = 224*224;
    //         end
    //         4'b0010: begin
    //             ifheight    = 112;
    //             ifsize      = 112*112;
    //         end
    //         4'b0011: begin
    //             ifheight    = 56;
    //             ifsize      = 56*56;
    //         end
    //         4'b0100: begin
    //             ifheight    = 28;
    //             ifsize      = 28*28;
    //         end
    //         4'b0101: begin
    //             ifheight    = 27;
    //             ifsize      = 28*27;
    //         end
    //         4'b0110: begin
    //             ifheight    = 14;
    //             ifsize      = 14*14;
    //         end
    //         4'b0111: begin
    //             ifheight    = 13;
    //             ifsize      = 14*13;
    //         end
    //         default: begin
    //             ifheight    = 7;
    //             ifsize      = 8*7;
    //         end
    //     endcase
    // end

    // //==========================================
    // //LOOK UP TABLE FOR NUMBER CHANNEL IFMAP AND NUMBER CHANNEL EACH FILTER
    // //==========================================
    // always @(*) begin
    //     case(inf_table_ifchannel_i)
    //         4'b0000: begin
    //             ifchannel    = 1024;
    //         end
    //         4'b0001: begin
    //             ifchannel    = 512;
    //         end
    //         4'b0010: begin
    //             ifchannel    = 384;
    //         end
    //         4'b0011: begin
    //             ifchannel    = 256;
    //         end
    //         4'b0100: begin
    //             ifchannel    = 192;
    //         end
    //         4'b0101: begin
    //             ifchannel    = 128;
    //         end
    //         4'b0110: begin
    //             ifchannel    = 96;
    //         end
    //         4'b0111: begin
    //             ifchannel    = 64;
    //         end
    //         4'b1000: begin
    //             ifchannel    = 48;
    //         end
    //         4'b1001: begin
    //             ifchannel    = 32;
    //         end
    //         4'b1010: begin
    //             ifchannel    = 16;
    //         end
    //         4'b1011: begin
    //             ifchannel    = 255;
    //         end
    //         default: begin
    //             ifchannel    = 3;
    //         end
    //     endcase
    // end

    // //==========================================
    // //LOOK UP TABLE FOR NUMBER CHANNEL OFMAP
    // //==========================================
    // always @(*) begin
    //     case(inf_table_ofchannel_i)
    //         4'b0000: begin
    //             ofchannel_lut    = 1024;
    //         end
    //         4'b0001: begin
    //             ofchannel_lut    = 512;
    //         end
    //         4'b0010: begin
    //             ofchannel_lut    = 384;
    //         end
    //         4'b0011: begin
    //             ofchannel_lut    = 256;
    //         end
    //         4'b0100: begin
    //             ofchannel_lut    = 192;
    //         end
    //         4'b0101: begin
    //             ofchannel_lut    = 128;
    //         end
    //         4'b0110: begin
    //             ofchannel_lut    = 96;
    //         end
    //         4'b0111: begin
    //             ofchannel_lut    = 64;
    //         end
    //         4'b1000: begin
    //             ofchannel_lut    = 48;
    //         end
    //         4'b1001: begin
    //             ofchannel_lut    = 32;
    //         end
    //         4'b1010: begin
    //             ofchannel_lut    = 16;
    //         end
    //         4'b1011: begin
    //             ofchannel_lut    = 255;
    //         end
    //         default: begin
    //             ofchannel_lut    = 3;
    //         end
    //     endcase
    // end
    wire                [23:0]              ifbaddr_d;
    wire                [7:0]               ifwidth_d;
    wire                [10:0]              ifchannel_d;
    wire                [3:0]               ifparr_d;
    wire                [3:0]               ifparr_tail_d;
    wire                [15:0]              ifsize_d;
    wire                [6:0]               ifblock_d;
    wire                [3:0]               oftile_d;
    wire                [3:0]               oftile_tail_d;
    wire                [7:0]               iftiles_d;
    wire                [8:0]               wp_d;
    wire                [1:0]               padding_d;
    wire                [DATA_WIDTH-1:0]    ifc_zp_d;
    wire                [DATA_WIDTH-1:0]    fltc_zp_d;
    wire                [23:0]              fltbaddr_d;
    wire                [6:0]               fltsize_d;
    wire                [4:0]               ofparr_d;
    wire                [4:0]               ofparr_tail_d;
    wire                [23:0]              bias_baddr_d;
    wire                [7:0]               ofwidth_d;
    wire                [10:0]              ofchannel_d;
    wire                [4:0]               burstlen_d;
    wire                [4:0]               burstlen_tail_d;
    wire                [4:0]               burstlen_lane0_d;
    wire                [4:0]               burstlen_tail_lane0_d;
    wire                [3:0]               hf_d;
    wire                [2:0]               stride_d;
    wire    signed      [31:0]              mult_d;
    wire                [5:0]               mult_shift_d;
    wire    signed      [31:0]              alphamult_d;
    wire                [5:0]               alphamult_shift_d;
    wire    signed      [7:0]               zpy_d;
    wire    signed      [7:0]               qmin_d;
    wire    signed      [7:0]               qmax_d;
    wire                                    is_leaky_ReLU_d;

    
    wire                [3:0]               ifparr_ext;
    wire                [4:0]               ofparr_ext;
    wire                [3:0]               oftile_ext;
    wire                [3:0]               ifparr_div;
    wire                [4:0]               ofparr_div;
    wire                [3:0]               oftile_div;
    wire                [2:0]               stride_div;
    wire                [7:0]               hf_square;
    wire                [11:0]              padded_width;
    wire                [11:0]              conv_span;
    wire                [11:0]              conv_steps;
    wire                [8:0]               ofparr_x_oftile;
    wire                [10:0]              ofblock_den;
    wire                [10:0]              ifblock_calc;
    wire                [10:0]              iftiles_calc;
    wire                [10:0]              ifparr_rem;
    wire                [10:0]              ofparr_rem;
    wire                [10:0]              total_oftiles;
    wire                [10:0]              oftile_tail_rem;
    wire                [11:0]              wp_calc;
    wire                [11:0]              ofwidth_calc;
    wire                [10:0]              bias_tail_rem;
    wire                [10:0]              bias_tail_real;
    wire                [5:0]               bias_h0_lanes;
    wire                [10:0]              bias_tail_full_tile;
    wire                [10:0]              bias_tail_mod;
    wire                [10:0]              bias_tail_lane0;
    wire                [10:0]              bias_lane0;

    wire                [23:0]              ofbaddr_l0_d;    
    wire                [23:0]              ofbaddr_l1_d;       
    wire                [15:0]              ofsize_d;  
    wire                [15:0]              ofsize_d1;     
    wire                [15:0]              ofsize_d2;        
    wire                [4:0]               ofc_bl_l1_d;     
    wire                [4:0]               ofc_bl_tail_l1_d;
    // -----------------------------------------------------------------------------
    // Output feature map size / base address calculation
    // Written as explicit hardware stages to avoid long arithmetic expressions.
    // -----------------------------------------------------------------------------

    wire [15:0] ofwidth_ext_d;
    wire [15:0] ofwidth_lsb_ext_d;
    wire [16:0] ofwidth_plus_lsb_d;

    wire [7:0]  ifblock_minus1_d;

    wire [18:0] bias_lane0_mul_ifblock_d;
    wire [18:0] bias_tail_lane0_ext_d;
    wire [19:0] bias_lane0_offset_d;

    wire [35:0] ofsize_mul_bias_offset_d;
    wire [35:0] ofbaddr_base_ext_d;
    wire [36:0] ofbaddr_l1_sum_d;

    assign ofbaddr_l0_d = inf_table_ofbaddr_i;

    // ofsize_d1 = ofwidth_d
    assign ofwidth_ext_d = {8'd0, ofwidth_d};
    assign ofsize_d1     = ofwidth_ext_d;

    // ofsize_d2 = ofwidth_d + ofwidth_d[0]
    // Do not write {8'd0, (ofwidth_d[0] + ofwidth_d)}
    // because the inner add can be evaluated as only 8 bits.
    assign ofwidth_lsb_ext_d   = {15'd0, ofwidth_d[0]};
    assign ofwidth_plus_lsb_d  = {1'b0, ofwidth_ext_d} + {1'b0, ofwidth_lsb_ext_d};
    assign ofsize_d2           = ofwidth_plus_lsb_d[15:0];

    // ofsize_d = ofsize_d1 * ofsize_d2
    assign ofsize_d = ofsize_d1 * ofsize_d2;

    // ifblock_d is 7 bits.
    // Extend before subtracting to avoid ambiguous arithmetic width.
    assign ifblock_minus1_d = {1'b0, ifblock_d} - 8'd1;

    // lane offset = bias_lane0 * (ifblock_d - 1) + bias_tail_lane0
    // bias_lane0          : 11 bits
    // ifblock_minus1_d    : 8 bits
    // multiply result     : 19 bits
    // bias_tail_lane0     : 11 bits, extended to 19 bits
    assign bias_lane0_mul_ifblock_d = bias_lane0 * ifblock_minus1_d;
    assign bias_tail_lane0_ext_d    = {8'd0, bias_tail_lane0};
    assign bias_lane0_offset_d      = {1'b0, bias_lane0_mul_ifblock_d}
                                    + {1'b0, bias_tail_lane0_ext_d};

    // byte/element offset = ofsize_d * lane_offset
    // ofsize_d            : 16 bits
    // bias_lane0_offset_d : 20 bits
    // multiply result     : 36 bits
    assign ofsize_mul_bias_offset_d = ofsize_d * bias_lane0_offset_d;

    // final base address
    assign ofbaddr_base_ext_d = {12'd0, inf_table_ofbaddr_i};
    assign ofbaddr_l1_sum_d   = {1'b0, ofbaddr_base_ext_d}
                            + {1'b0, ofsize_mul_bias_offset_d};

    assign ofbaddr_l1_d = ofbaddr_l1_sum_d[23:0];
    assign ofc_bl_l1_d      = burstlen_d - burstlen_lane0_d;
    assign ofc_bl_tail_l1_d = burstlen_tail_d - burstlen_tail_lane0_d;
    
    assign ifparr_ext       = {1'b0, inf_table_ifparr_i};
    assign ofparr_ext       = inf_table_ofparr_i;
    assign oftile_ext       = {2'b00, inf_table_oftile_i};
    assign ifparr_div       = (ifparr_ext == 4'd0) ? 4'd1 : ifparr_ext;
    assign ofparr_div       = (ofparr_ext == 5'd0) ? 5'd1 : ofparr_ext;
    assign oftile_div       = (oftile_ext == 4'd0) ? 4'd1 : oftile_ext;
    assign stride_div       = (inf_table_stride_i == 3'd0) ? 3'd1 : inf_table_stride_i;
    assign hf_square        = {4'd0, inf_table_hf_i} * {4'd0, inf_table_hf_i};
    assign padded_width     = {4'd0, ifheight} + {9'd0, inf_table_padding_i, 1'b0};
    assign conv_span        = (padded_width >= {8'd0, inf_table_hf_i}) ?
                              (padded_width - {8'd0, inf_table_hf_i}) : 12'd0;
    assign conv_steps       = conv_span / {9'd0, stride_div};
    assign ofparr_x_oftile  = {4'd0, ofparr_div} * {5'd0, oftile_div};
    assign ofblock_den      = {2'd0, ofparr_x_oftile};
    assign ifblock_calc     = (ofchannel_lut + ofblock_den - 11'd1) / ofblock_den;
    assign iftiles_calc         = (ifchannel + {7'd0, ifparr_div} - 11'd1) / {7'd0, ifparr_div};
    assign ifparr_rem           = ifchannel % {7'd0, ifparr_div};
    assign ofparr_rem           = ofchannel_lut % {6'd0, ofparr_div};
    assign total_oftiles        = (ofchannel_lut + {6'd0, ofparr_div} - 11'd1) / {6'd0, ofparr_div};
    assign oftile_tail_rem      = total_oftiles % {7'd0, oftile_div};
    assign bias_tail_rem        = ofchannel_lut % ofblock_den;
    assign bias_tail_real       = (bias_tail_rem == 11'd0) ? ofblock_den : bias_tail_rem;
    assign bias_h0_lanes        = ({1'b0, ofparr_div} + 6'd1) >> 1;
    assign bias_tail_full_tile  = bias_tail_real / {6'd0, ofparr_div};
    assign bias_tail_mod        = bias_tail_real % {6'd0, ofparr_div};
    assign bias_tail_lane0      = (bias_tail_full_tile * {5'd0, bias_h0_lanes}) + ((bias_tail_mod + 11'd1) >> 1);
    assign bias_lane0           = (ofchannel_lut < ofblock_den) ?
                                  bias_tail_lane0 : ({5'd0, bias_h0_lanes} * {7'd0, oftile_div});
    assign wp_calc              = (conv_steps * {9'd0, stride_div}) + {8'd0, inf_table_hf_i} - 12'd1;
    assign ofwidth_calc         = conv_steps + 12'd1;

    assign ifbaddr_d                 = inf_table_ifbaddr_i;
    assign ifwidth_d                 = ifheight;
    assign ifchannel_d               = ifchannel;
    assign ifparr_d                  = ifparr_ext;
    assign ifparr_tail_d             = (ifparr_rem == 11'd0) ? ifparr_ext : ifparr_rem[3:0];
    assign ifsize_d                  = ifsize;
    assign ifblock_d                 = ifblock_calc[6:0];
    assign oftile_d                  = oftile_ext;
    assign oftile_tail_d             = (oftile_tail_rem == 11'd0) ? oftile_ext : oftile_tail_rem[3:0];
    assign iftiles_d                 = iftiles_calc[7:0];
    assign wp_d                      = wp_calc[8:0];
    assign padding_d                 = inf_table_padding_i;
    assign ifc_zp_d                  = inf_table_ifc_zp_i;
    assign fltc_zp_d                 = inf_table_fltc_zp_i;
    assign fltbaddr_d                = inf_table_fltbaddr_i;
    assign fltsize_d                 = hf_square[6:0];
    assign ofparr_d                  = ofparr_ext;
    assign ofparr_tail_d             = (ofparr_rem == 11'd0) ? ofparr_ext : ofparr_rem[4:0];
    assign bias_baddr_d              = inf_table_bias_baddr_i;
    assign ofwidth_d                 = ofwidth_calc[7:0];
    assign ofchannel_d               = ofchannel_lut;
    assign burstlen_d                = (ofchannel_lut < ofblock_den) ? bias_tail_real[4:0] : ofblock_den[4:0];
    assign burstlen_tail_d           = bias_tail_real[4:0];
    assign burstlen_lane0_d          = bias_lane0[4:0];
    assign burstlen_tail_lane0_d     = bias_tail_lane0[4:0];
    assign hf_d                      = inf_table_hf_i;
    assign stride_d                  = inf_table_stride_i;
    assign mult_d                    = inf_table_mult_i;
    assign mult_shift_d              = inf_table_mult_shift_i;
    assign alphamult_d               = inf_table_alphamult_i;
    assign alphamult_shift_d         = inf_table_alphamult_shift_i;
    assign zpy_d                     = inf_table_zpy_i;
    assign qmin_d                    = inf_table_qmin_i;
    assign qmax_d                    = inf_table_qmax_i;
    assign is_leaky_ReLU_d           = inf_table_is_leaky_ReLU_i;

    reg                 [23:0]              ifbaddr_q;
    reg                 [7:0]               ifwidth_q;
    reg                 [10:0]              ifchannel_q;
    reg                 [3:0]               ifparr_q;
    reg                 [3:0]               ifparr_tail_q;
    reg                 [15:0]              ifsize_q;
    reg                 [6:0]               ifblock_q;
    reg                 [3:0]               oftile_q;
    reg                 [3:0]               oftile_tail_q;
    reg                 [7:0]               iftiles_q;
    reg                 [8:0]               wp_q;
    reg                 [1:0]               padding_q;
    reg                 [DATA_WIDTH-1:0]    ifc_zp_q;
    reg                 [DATA_WIDTH-1:0]    fltc_zp_q;
    reg                 [23:0]              fltbaddr_q;
    reg                 [6:0]               fltsize_q;
    reg                 [4:0]               ofparr_q;
    reg                 [4:0]               ofparr_tail_q;
    reg                 [23:0]              bias_baddr_q;
    reg                 [7:0]               ofwidth_q;
    reg                 [10:0]              ofchannel_q;
    reg                 [4:0]               burstlen_q;
    reg                 [4:0]               burstlen_tail_q;
    reg                 [4:0]               burstlen_lane0_q;
    reg                 [4:0]               burstlen_tail_lane0_q;
    reg                 [3:0]               hf_q;
    reg                 [2:0]               stride_q;
    reg    signed       [31:0]              mult_q;
    reg                 [5:0]               mult_shift_q;
    reg    signed       [31:0]              alphamult_q;
    reg                 [5:0]               alphamult_shift_q;
    reg    signed       [7:0]               zpy_q;
    reg    signed       [7:0]               qmin_q;
    reg    signed       [7:0]               qmax_q;
    reg                                     is_leaky_ReLU_q;

    reg                 [23:0]              ofbaddr_l0_q;    
    reg                 [23:0]              ofbaddr_l1_q;       
    reg                 [15:0]              ofsize_q;   
    reg                 [4:0]               ofc_bl_l1_q;     
    reg                 [4:0]               ofc_bl_tail_l1_q;         
    always @(posedge clk) begin
        if(count_cycle == 3'b110) begin
            ifbaddr_q                 <= ifbaddr_d;
            ifwidth_q                 <= ifwidth_d;
            ifchannel_q               <= ifchannel_d;
            ifparr_q                  <= ifparr_d;
            ifparr_tail_q             <= ifparr_tail_d;
            ifsize_q                  <= ifsize_d;
            ifblock_q                 <= ifblock_d;
            oftile_q                  <= oftile_d;
            oftile_tail_q             <= oftile_tail_d;
            iftiles_q                 <= iftiles_d;
            wp_q                      <= wp_d;
            padding_q                 <= padding_d;
            ifc_zp_q                  <= ifc_zp_d;
            fltc_zp_q                 <= fltc_zp_d;
            fltbaddr_q                <= fltbaddr_d;
            fltsize_q                 <= fltsize_d;
            ofparr_q                  <= ofparr_d;
            ofparr_tail_q             <= ofparr_tail_d;
            bias_baddr_q              <= bias_baddr_d;
            ofwidth_q                 <= ofwidth_d;
            ofchannel_q               <= ofchannel_d;
            burstlen_q                <= burstlen_d;
            burstlen_tail_q           <= burstlen_tail_d;
            burstlen_lane0_q          <= burstlen_lane0_d;
            burstlen_tail_lane0_q     <= burstlen_tail_lane0_d;
            hf_q                      <= hf_d;
            stride_q                  <= stride_d;
            mult_q                    <= mult_d;
            mult_shift_q              <= mult_shift_d;
            alphamult_q               <= alphamult_d;
            alphamult_shift_q         <= alphamult_shift_d;
            zpy_q                     <= zpy_d;
            qmin_q                    <= qmin_d;
            qmax_q                    <= qmax_d;
            is_leaky_ReLU_q           <= is_leaky_ReLU_d;
            ofbaddr_l0_q              <= ofbaddr_l0_d;
            ofbaddr_l1_q              <= ofbaddr_l1_d;
            ofsize_q                  <= ofsize_d;    
            ofc_bl_l1_q               <= ofc_bl_l1_d;
            ofc_bl_tail_l1_q          <= ofc_bl_tail_l1_d;
        end
    end

    assign inf_table_rdy_o                  = table_rdy;

    assign inf_ifbuf_vld_o                  = if_vld;
    assign inf_ifbuf_ifbaddr_o              = ifbaddr_q;
    assign inf_ifbuf_ifwidth_o              = ifwidth_q;
    assign inf_ifbuf_ifchannel_o            = ifchannel_q;
    assign inf_ifbuf_ifparr_o               = ifparr_q;
    assign inf_ifbuf_ifsize_o               = ifsize_q;
    assign inf_ifbuf_ifblock_o              = ifblock_q;
    assign inf_ifbuf_oftiles_o              = oftile_q;
    assign inf_ifbuf_oftiles_tail_o         = oftile_tail_q;
    assign inf_ifbuf_iftiles_o              = iftiles_q;
    assign inf_ifbuf_wp_o                   = wp_q;
    assign inf_ifbuf_padding_o              = padding_q;
    assign inf_ifbuf_ifc_zp_o               = ifc_zp_q;

    assign inf_fltbuf_vld_o                 = flt_vld;
    assign inf_fltbuf_fltbaddr_o            = fltbaddr_q;
    assign inf_fltbuf_ifparr_o              = ifparr_q;
    assign inf_fltbuf_ifparr_tail_o         = ifparr_tail_q;
    assign inf_fltbuf_fltsize_o             = fltsize_q;
    assign inf_fltbuf_ifblock_o             = ifblock_q;
    assign inf_fltbuf_ofparr_o              = ofparr_q;
    assign inf_fltbuf_ofparr_tail_o         = ofparr_tail_q;
    assign inf_fltbuf_oftiles_o             = oftile_q;
    assign inf_fltbuf_oftiles_tail_o        = oftile_tail_q;
    assign inf_fltbuf_iftiles_o             = iftiles_q;

    assign inf_bias_vld_o                   = bias_vld;
    assign inf_bias_bias_baddr_o            = bias_baddr_q;
    assign inf_bias_ofwidth_o               = ofwidth_q;
    assign inf_bias_ofchannel_o             = ofchannel_q;
    assign inf_bias_burstlen_o              = burstlen_q;
    assign inf_bias_burstlen_tail_o         = burstlen_tail_q;
    assign inf_bias_burstlen_lane0_o        = burstlen_lane0_q;
    assign inf_bias_burstlen_tail_lane0_o   = burstlen_tail_lane0_q;

    assign inf_comp_vld_o                   = comp_vld;
    assign inf_comp_hf_o                    = hf_q;
    assign inf_comp_stride_o                = stride_q;
    assign inf_comp_padding_o               = padding_q;
    assign inf_comp_ifc_zp_o                = ifc_zp_q;
    assign inf_comp_fltc_zp_o               = fltc_zp_q;
    assign inf_comp_ofwidth_o               = ofwidth_q;
    assign inf_comp_mult_o                  = mult_q;
    assign inf_comp_mult_shift_o            = mult_shift_q;
    assign inf_comp_alphamult_o             = alphamult_q;
    assign inf_comp_alphamult_shift_o       = alphamult_shift_q;
    assign inf_comp_zpy_o                   = zpy_q;
    assign inf_comp_qmin_o                  = qmin_q;
    assign inf_comp_qmax_o                  = qmax_q;
    assign inf_comp_is_leaky_ReLU_o         = is_leaky_ReLU_q;

    assign inf_ofbuf_vld_o                  = of_vld;
    assign inf_ofbuf_ofwidth_o              = ofwidth_q;
    assign inf_ofbuf_ofbaddr_l0_o           = ofbaddr_l0_q;
    assign inf_ofbuf_ofbaddr_l1_o           = ofbaddr_l1_q;
    assign inf_ofbuf_ofsize_o               = ofsize_q;
    assign inf_ofbuf_ofblock_o              = ifblock_q;
    assign inf_ofbuf_ofc_bl_l0_o            = burstlen_lane0_q;
    assign inf_ofbuf_ofc_bl_tail_l0_o       = burstlen_tail_lane0_q;
    assign inf_ofbuf_ofc_bl_l1_o            = ofc_bl_l1_q;
    assign inf_ofbuf_ofc_bl_tail_l1_o       = ofc_bl_tail_l1_q;
    (* keep = "false" *) wire _unused_sink; 
    
    assign _unused_sink = &{
        hf_square[7],
        ifblock_calc[10:7],
        iftiles_calc[10:6],
        ofwidth_calc[11:8],
        wp_calc[11:9],
        ofbaddr_l1_sum_d[36:24],
        ofwidth_plus_lsb_d[16]

    };
endmodule
