`timescale 1ns / 1ps

module computation #(
    // Parameters cho comp_pu
    parameter WIDTH         = 8,
    parameter ACC_WIDTH     = 32,
    parameter PE_PER_PU     = 12,
    parameter DEPTH         = 12,
    parameter K             = 8,
    parameter M             = 2,
    parameter PPDEPTH       = 640,
    
    // Parameters bổ sung cho ifmap_cache
    parameter FIFO_DEPTH    = 12
)(
    input  clk,
    input  rst_n,

    // Tín hiệu inftruction (Dùng chung và riêng cho PU/Cache)
    output                      comp_inf_rdy_o,
    input                       comp_inf_vld_i,
    input           [3:0]       comp_inf_hf_i,
    input           [2:0]       comp_inf_stride_i,
    input           [1:0]       comp_inf_padding_i,
    input   signed  [WIDTH-1:0] comp_inf_ifc_zp_i,
    input   signed  [WIDTH-1:0] comp_inf_fltc_zp_i,
    input           [7:0]       comp_inf_ofwidth_i,
    input   signed  [31:0]      comp_inf_mult_i,
    input           [5:0]       comp_inf_mult_shift_i,
    input   signed  [31:0]      comp_inf_alphamult_i,
    input           [5:0]       comp_inf_alphamult_shift_i,
    input   signed  [7:0]       comp_inf_zpy_i,
    input   signed  [7:0]       comp_inf_qmin_i,
    input   signed  [7:0]       comp_inf_qmax_i,
    input                       comp_inf_is_leaky_ReLU_i,

    // Giao tiếp với Input Feature Map (ifbuf) - đi vào ifmap_cache
    input                   comp_ifbuf_vld_i,
    input  [K*WIDTH-1:0]    comp_ifbuf_data_i,
    input                   comp_ifbuf_end_row_i,
    input                   comp_ifbuf_end_row_circle_i,
    input                   comp_ifbuf_end_depth_i,
    input                   comp_ifbuf_end_layer_i,
    input                   comp_ifbuf_end_layer_real_i,
    output                  comp_ifbuf_rdy_o,

    // Giao tiếp với Filter Buffer (fltbuf) - đi vào comp_pu (Đã mở rộng cho M PU)
    input  [K*M-1:0]        comp_fltbuf_vld_i,
    input  [K*M*WIDTH-1:0]  comp_fltbuf_data_i,
    input                   comp_fltbuf_done_pass_i, // Dùng chung
    output [M-1:0]          comp_fltbuf_rdy_o,

    input    [M*ACC_WIDTH-1:0]      comp_bias_data_i,
    input    [M-1:0]            comp_bias_vld_i,
    output   [M-1:0]            comp_bias_rdy_o,

    // Giao tiếp với Output Buffer (scale) - đi ra từ comp_pu (Đã mở rộng cho M PU)
    input  [M-1:0]          comp_ofbuf_rdy_i,
    output [M-1:0]          comp_ofbuf_vld_o,
    output [M*WIDTH-1:0] comp_ofbuf_data_o,
    
    // Tín hiệu báo xong - Lấy từ PU[0]
    output                  comp_pa_done_compute_o
);

    // ==========================================
    // Khai báo wire kết nối nội bộ giữa ifmap_cache và comp_pu
    // ==========================================
    wire [K*WIDTH-1:0]  ifc_pu_data_w;
    wire                ifc_pu_vld_w;
    wire                pu_ifc_rdy_w;
    wire                ifc_pu_end_row_w;
    wire                ifc_pu_end_row_circle_w;
    wire                ifc_pu_end_depth_w;
    wire                ifc_pu_end_layer_w;
    wire                ifc_pu_end_layer_real_w;

    // Tín hiệu rdy và done compute gom từ các PU
    wire [M-1:0]        pu_ifc_rdy_m;
    wire [M-1:0]        pu_pa_done_compute_m;
    wire [M-1:0]        pu_pa_done_compute_layer_m;

    reg             [3:0]           comp_inf_hf_reg;
    reg             [2:0]           comp_inf_stride_reg;
    reg             [1:0]           comp_inf_padding_reg;
    reg   signed    [WIDTH-1:0]     comp_inf_ifc_zp_reg;
    reg   signed    [WIDTH-1:0]     comp_inf_fltc_zp_reg;
    reg             [7:0]       comp_inf_ofwidth_reg;
    reg   signed    [31:0]      comp_inf_mult_reg;
    reg             [5:0]       comp_inf_mult_shift_reg;
    reg   signed    [31:0]      comp_inf_alphamult_reg;
    reg             [5:0]       comp_inf_alphamult_shift_reg;
    reg   signed    [7:0]       comp_inf_zpy_reg;
    reg   signed    [7:0]       comp_inf_qmin_reg;
    reg   signed    [7:0]       comp_inf_qmax_reg;
    reg                       comp_inf_is_leaky_ReLU_reg;
    reg                         inf_rdy;
    reg                         comp_rdy;
    reg             [1:0]       cnt_rdy;
    wire                        done_compute_layer;
    wire                        comp_rdy_en;
    
    assign comp_inf_rdy_o = inf_rdy;
    posedge_detection b(
        .clk(clk),
        .rst_n(rst_n),
        .signal_i(&pu_pa_done_compute_layer_m),
        .signal_o(done_compute_layer)
    );

    always @(posedge clk) begin
        if(!rst_n) begin
            inf_rdy <= 1'b1;
        end else begin
            if(comp_inf_vld_i) inf_rdy <= 1'b0;
            else if(done_compute_layer) inf_rdy <= 1'b1;
        end
    end
    always @(posedge clk) begin
        if(comp_inf_rdy_o) begin
            cnt_rdy <= 2'd0;
        end else if(!(&cnt_rdy)) begin
            cnt_rdy <= cnt_rdy + 2'd1;
        end
    end
    posedge_detection c(
        .clk(clk),
        .rst_n(rst_n),
        .signal_i(&cnt_rdy),
        .signal_o(comp_rdy_en)
    );
    always @(posedge clk) begin
        if(comp_inf_rdy_o || (comp_ifbuf_vld_i && comp_ifbuf_rdy_o && comp_ifbuf_end_layer_real_i)) begin
            comp_rdy <= 1'b0;
        end else if(comp_rdy_en) begin
            comp_rdy <= 1'b1;
        end
    end

    always @(posedge clk) begin
        if(comp_inf_rdy_o) begin
            comp_inf_hf_reg                 <= comp_inf_hf_i;
            comp_inf_stride_reg             <= comp_inf_stride_i;
            comp_inf_padding_reg            <= comp_inf_padding_i;
            comp_inf_ifc_zp_reg             <= comp_inf_ifc_zp_i;
            comp_inf_fltc_zp_reg            <= comp_inf_fltc_zp_i;
            comp_inf_ofwidth_reg            <= comp_inf_ofwidth_i;
            comp_inf_mult_reg               <= comp_inf_mult_i;
            comp_inf_mult_shift_reg         <= comp_inf_mult_shift_i;
            comp_inf_alphamult_reg          <= comp_inf_alphamult_i;
            comp_inf_alphamult_shift_reg    <= comp_inf_alphamult_shift_i;
            comp_inf_zpy_reg                <= comp_inf_zpy_i;
            comp_inf_qmin_reg               <= comp_inf_qmin_i;
            comp_inf_qmax_reg               <= comp_inf_qmax_i;
            comp_inf_is_leaky_ReLU_reg      <= comp_inf_is_leaky_ReLU_i;
        end
    end
    // Chỉ báo rdy cho cache khi tất cả M PUs đều sẵn sàng
    assign pu_ifc_rdy_w = pu_ifc_rdy_m[0]; 
    
    // Gán tín hiệu done compute từ PU 0 ra ngoài theo yêu cầu
    assign comp_pa_done_compute_o = pu_pa_done_compute_m[0];
    wire comp_ifbuf_rdy_w;
    assign comp_ifbuf_rdy_o = comp_ifbuf_rdy_w && comp_rdy;
    // ==========================================
    // inftantiation: ifmap_cache
    // ==========================================
    ifmap_cache #(
        .DATA_WIDTH(WIDTH),      // Map WIDTH của hệ thống vào DATA_WIDTH
        .FIFO_DEPTH(FIFO_DEPTH),
        .K(K)
    ) ifmap_cache_inft (
        .clk(clk),
        .rst_n(rst_n),
        
        // Từ inftruction
        .ifc_inf_hf_i(comp_inf_hf_reg),
        .ifc_inf_stride_i(comp_inf_stride_reg),
        
        // Giao tiếp với IFBUF bên ngoài
        .ifc_ifbuf_data_i(comp_ifbuf_data_i),
        .ifc_ifbuf_end_row_i(comp_ifbuf_end_row_i),
        .ifc_ifbuf_end_row_circle_i(comp_ifbuf_end_row_circle_i),
        .ifc_ifbuf_end_depth_i(comp_ifbuf_end_depth_i),
        .ifc_ifbuf_end_layer_i(comp_ifbuf_end_layer_i),
        .ifc_ifbuf_end_layer_real_i(comp_ifbuf_end_layer_real_i),
        .ifc_ifbuf_vld_i(comp_ifbuf_vld_i && comp_rdy),
        .ifc_ifbuf_rdy_o(comp_ifbuf_rdy_w),
        
        // Giao tiếp nội bộ với comp_pu
        .ifc_pu_rdy_i(pu_ifc_rdy_w), // Nhận tín hiệu AND từ tất cả PUs
        .ifc_pu_vld_o(ifc_pu_vld_w),
        .ifc_pu_data_o(ifc_pu_data_w),
        .ifc_pu_end_row_o(ifc_pu_end_row_w),
        .ifc_pu_end_row_circle_o(ifc_pu_end_row_circle_w),
        .ifc_pu_end_depth_o(ifc_pu_end_depth_w),
        .ifc_pu_end_layer_o(ifc_pu_end_layer_w),
        .ifc_pu_end_layer_real_o(ifc_pu_end_layer_real_w)
    );

    // ==========================================
    // inftantiation: M comp_pu modules
    // ==========================================
    wire [M-1:0]    pu_comp_vld_o;
    wire [M-1:0]    pu_swap_fltc_o;
    wire [M-1:0]    comp_scale_vld_w;
    wire [M-1:0]    scale_comp_rdy_w;
    wire [M-1:0]    comp_fltbuf_rdy_w;
    wire [M*ACC_WIDTH-1:0] comp_scale_data_w;
    wire            pu_comp_vld_i;
    assign pu_comp_vld_i = |pu_comp_vld_o;
    assign comp_fltbuf_rdy_o = comp_fltbuf_rdy_w;
    genvar i;
    generate
        for (i = 0; i < M; i = i + 1) begin : gen_comp_pu
            comp_pu #(
                .WIDTH(WIDTH),
                .ACC_WIDTH(ACC_WIDTH),
                .PE_PER_PU(PE_PER_PU),
                .DEPTH(DEPTH),
                .K(K),
                .PPDEPTH(PPDEPTH)
            ) comp_pu_inft (
                .clk(clk),
                .rst_n(rst_n),

                .pu_inf_hf_i(comp_inf_hf_reg),
                .pu_inf_stride_i(comp_inf_stride_reg),
                .pu_inf_padding_i(comp_inf_padding_reg),
                .pu_inf_ifc_zp_i(comp_inf_ifc_zp_reg),
                .pu_inf_fltc_zp_i(comp_inf_fltc_zp_reg),
                
                // Giao tiếp nội bộ với ifmap_cache (Chung cho tất cả PU)
                .pu_ifc_end_row_circle_i(ifc_pu_end_row_circle_w),
                .pu_ifc_end_row_i(ifc_pu_end_row_w), 
                .pu_ifc_end_depth_i(ifc_pu_end_depth_w),
                .pu_ifc_end_layer_i(ifc_pu_end_layer_w),
                .pu_ifc_end_layer_real_i(ifc_pu_end_layer_real_w),
                .pu_ifc_vld_i(ifc_pu_vld_w),
                .pu_ifc_data_i(ifc_pu_data_w),
                
                
                .pu_ifc_rdy_o(pu_ifc_rdy_m[i]),
                
                // Giao tiếp với FLTBUF bên ngoài (Phần riêng)
                .pu_fltbuf_vld_i(comp_fltbuf_vld_i[i*K +: K]),
                .pu_fltbuf_data_i(comp_fltbuf_data_i[i*K*WIDTH +: K*WIDTH]),
                .pu_fltbuf_done_pass_i(comp_fltbuf_done_pass_i), // Dùng chung
                .pu_fltbuf_rdy_o(comp_fltbuf_rdy_w[i]),
                
                .pu_swap_fltc_i(pu_swap_fltc_o[0]),
                .pu_swap_fltc_o(pu_swap_fltc_o[i]),
                .pu_comp_vld_o(pu_comp_vld_o[i]),
                .pu_comp_vld_i(pu_comp_vld_i),
                // Giao tiếp với scale bên ngoài (Phần riêng)
                .pu_scale_rdy_i(scale_comp_rdy_w[i]),
                .pu_scale_vld_o(comp_scale_vld_w[i]),
                .pu_scale_data_o(comp_scale_data_w[(i+1)*ACC_WIDTH-1 : i*ACC_WIDTH]),
                
                // Tín hiệu done (Xuất ra mảng rồi lấy phần tử 0)
                .pu_pa_done_compute_o(pu_pa_done_compute_m[i]),
                .pu_pa_done_compute_layer_o(pu_pa_done_compute_layer_m[i])
            );

            scale_ReLU  #(
                .DATA_IN_WIDTH(ACC_WIDTH),
                .DATA_OUT_WIDTH(WIDTH)
            ) scale_ReLU_inft (
                .clk(clk),
                .rst_n(rst_n),

                .scale_inf_width_i(comp_inf_ofwidth_reg),
                .scale_inf_mult_i(comp_inf_mult_reg),
                .scale_inf_mult_shift_i(comp_inf_mult_shift_reg),
                .scale_inf_alphamult_i(comp_inf_alphamult_reg),
                .scale_inf_alphamult_shift_i(comp_inf_alphamult_shift_reg),
                .scale_inf_zpy_i(comp_inf_zpy_reg),
                .scale_inf_qmin_i(comp_inf_qmin_reg),
                .scale_inf_qmax_i(comp_inf_qmax_reg),
                .scale_inf_is_leaky_ReLU_i(comp_inf_is_leaky_ReLU_reg),

                .scale_bias_data_i(comp_bias_data_i[i*ACC_WIDTH +: ACC_WIDTH]),
                .scale_bias_vld_i(comp_bias_vld_i[i]),
                .scale_bias_rdy_o(comp_bias_rdy_o[i]),

                .scale_comp_data_i(comp_scale_data_w[(i+1)*ACC_WIDTH-1 : i*ACC_WIDTH]),
                .scale_comp_vld_i(comp_scale_vld_w[i]),
                .scale_comp_rdy_o(scale_comp_rdy_w[i]),

                .scale_ofbuf_rdy_i(comp_ofbuf_rdy_i[i]),
                .scale_ofbuf_data_o(comp_ofbuf_data_o[WIDTH*i +: WIDTH]),
                .scale_ofbuf_vld_o(comp_ofbuf_vld_o[i])
            );
        end
    endgenerate
    (* keep = "false" *) wire _unused_sink; 
    
    assign _unused_sink = &{
        1'b0,                                                               // Pad to ensure reduction AND works cleanly
        pu_pa_done_compute_m[1],                                             // Unused bit 0
        pu_ifc_rdy_m[M-1:1],
        pu_swap_fltc_o[M-1:1]
    };
endmodule