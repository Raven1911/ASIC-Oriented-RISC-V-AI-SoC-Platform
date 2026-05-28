`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 03/21/2026 07:38:17 PM
// Design Name: 
// Module Name: ifbuf
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


module ifbuf #(
    parameter DATA_WIDTH    = 8,
    parameter DEPTH         = 300,
    parameter K             = 8
)(
    input                           clk,
    input                           rst_n,
    
    // Giao tiếp inftruction
    input                           ifbuf_inf_vld_i,
    input       [23:0]              ifbuf_inf_ifbaddr_i,
    input       [7:0]               ifbuf_inf_ifwidth_i,
    input       [10:0]              ifbuf_inf_channel_i,
    input       [3:0]               ifbuf_inf_ifparr_i,
    input       [15:0]              ifbuf_inf_ifsize_i,
    input       [6:0]               ifbuf_inf_ifblock_i,
    input       [3:0]               ifbuf_inf_oftiles_i,
    input       [3:0]               ifbuf_inf_oftiles_tail_i,
    input       [7:0]               ifbuf_inf_iftiles_i,
    input       [8:0]               ifbuf_inf_wp_i,
    input       [1:0]               ifbuf_inf_padding_i,
    input       signed [DATA_WIDTH-1:0]    ifbuf_inf_ifc_zp_i,
    output                          ifbuf_inf_rdy_o,

    // Tín hiệu DMA
    input                           ifbuf_dma_rdycfg_i,
    input                           ifbuf_dma_vld_i,
    input       [DATA_WIDTH-1:0]    ifbuf_dma_data_i,
    input                           ifbuf_dma_tlast_i,
    output                          ifbuf_dma_vldcfg_o,
    output reg  [7:0]               ifbuf_dma_burst_o, 
    output      [23:0]              ifbuf_dma_baddr_o,
    output                          ifbuf_dma_rdy_o,

    // Tín hiệu giao tiếp với khối khác
    input                           ifbuf_comp_rdy_i,
    output                          ifbuf_comp_vld_o,
    output      [K*DATA_WIDTH-1:0]  ifbuf_comp_data_o,
    output                          ifbuf_comp_end_row_o,
    output                          ifbuf_comp_end_row_circle_o,
    output                          ifbuf_comp_end_depth_o,
    output                          ifbuf_comp_end_layer_o,
    output                          ifbuf_comp_end_layer_real_o
);

    // ==========================================
    // 1. Latch các thông số inftruction nội bộ của ifbuf 
    // (Các thông số không thuộc về ifbuf_mem)
    // ==========================================
    reg [3:0]               ifbuf_inf_oftiles_reg;
    reg [3:0]               ifbuf_inf_oftiles_tail_reg;
    reg [7:0]               ifbuf_inf_iftiles_reg;
    reg [8:0]               ifbuf_inf_wp_reg;
    reg [1:0]               ifbuf_inf_padding_reg;
    reg signed [DATA_WIDTH-1:0]    ifbuf_inf_ifc_zp_reg;
    reg [3:0]               ifbuf_inf_ifparr_reg;
    wire                    swap_en;

    // ==========================================
    // 2. inftantiate module con ifbuf_mem
    // ==========================================
    reg [23:0]  ifbuf_inf_ifbaddr_reg;
    reg [7:0]   ifbuf_inf_width_reg;
    reg [10:0]  ifbuf_inf_channel_reg;
    reg [15:0]  ifbuf_inf_ifsize_reg;
    reg [6:0]   ifbuf_inf_ifblock_reg;

    // Khai báo các tín hiệu logic nội bộ
    reg         vld_i_reg;
    wire        vld_i_rst;
    reg         vld;
    reg         en_config;
    wire        en_config_rst;
    reg [6:0]   ifblock_count;
    reg [6:0]   ifblock_count_r;
    wire        ifblock_count_en;
    wire        ifblock_count_r_en;
    reg [8:0]   height_config;
    reg [16:0]  height_width_config;
    wire        height_config_en;
    reg [10:0]  channel_config;
    reg [3:0]   channel_count;
    wire        channel_config_en;  // Bổ sung wire bị thiếu
    reg [31:0]  base_addr_config;
    wire [31:0] base_addr_config_nxt;
    wire [7:0]  width_align;
    wire [K-1:0] wr_en;
    wire        vld_o;
    wire        clr;
    wire [K*DATA_WIDTH-1:0] data_o;
    reg [K-1:0] key_ring;
    reg         done_prepare;
    reg         id;
    wire        is_padding_data;
    reg [8:0]   count_w_read;
    wire        count_w_read_en;
    reg [2:0]   count_oftiles_read;
    wire        count_oftiles_read_en;
    reg [7:0]   count_depth_read;
    wire        count_depth_read_en;
    reg [8:0]   count_height_read;
    wire        count_height_read_en;
    reg         inf_rdy_dly;
    // Phân luồng các Assign logic
    assign channel_config_en    = ifbuf_dma_rdycfg_i && ifbuf_dma_vldcfg_o;
    assign height_config_en     = channel_config_en && (channel_config == ifbuf_inf_channel_reg - 1);
    assign ifblock_count_en     = height_config_en && (height_config == ifbuf_inf_width_reg - 1);
    assign vld_i_rst            = ifblock_count_en && (ifblock_count == ifbuf_inf_ifblock_reg - 1);
    assign ifbuf_inf_rdy_o      = !vld_i_reg;
    assign base_addr_config_nxt = (!vld || ifblock_count_en) ? ifbuf_inf_ifbaddr_reg :
                                  ((channel_config == ifbuf_inf_channel_reg - 1) ? 
                                   (ifbuf_inf_ifbaddr_reg + height_width_config + ifbuf_dma_burst_o) : 
                                   (base_addr_config + ifbuf_inf_ifsize_reg));
                                  
    assign en_config_rst        = channel_config_en && ((channel_count == ifbuf_inf_ifparr_reg - 1) || (channel_config == ifbuf_inf_channel_reg - 1));

    // Đẩy giá trị nội bộ ra Output
    assign ifbuf_dma_baddr_o    = base_addr_config;
    assign ifbuf_dma_vldcfg_o   = vld && en_config;
    assign width_align          = ifbuf_inf_width_reg + ifbuf_inf_width_reg[0];

    always @(posedge clk) begin
        if (ifbuf_inf_rdy_o) begin
            ifbuf_inf_oftiles_reg   <= ifbuf_inf_oftiles_i;
            ifbuf_inf_iftiles_reg   <= ifbuf_inf_iftiles_i;
            ifbuf_inf_wp_reg        <= ifbuf_inf_wp_i;
            ifbuf_inf_padding_reg   <= ifbuf_inf_padding_i;
            ifbuf_inf_ifparr_reg    <= ifbuf_inf_ifparr_i;
            ifbuf_inf_oftiles_tail_reg <= ifbuf_inf_oftiles_tail_i;
        end
        inf_rdy_dly <=  ifbuf_inf_rdy_o;
    end

    always @(posedge clk) begin
        ifbuf_dma_burst_o       <= width_align;
        if(ifbuf_inf_rdy_o) begin
            ifbuf_inf_ifbaddr_reg   <= ifbuf_inf_ifbaddr_i;
            ifbuf_inf_width_reg     <= ifbuf_inf_ifwidth_i;
            ifbuf_inf_channel_reg   <= ifbuf_inf_channel_i;
            ifbuf_inf_ifsize_reg    <= ifbuf_inf_ifsize_i;
            ifbuf_inf_ifblock_reg   <= ifbuf_inf_ifblock_i;
            ifbuf_inf_ifc_zp_reg    <= ifbuf_inf_ifc_zp_i;
        end
    end

    // Khối Valid Input Register
    always @(posedge clk) begin
        if (!rst_n) begin
            vld_i_reg <= 0;
        end else begin
            if (vld_i_rst) begin
                vld_i_reg <= 0;
            end else if (ifbuf_inf_vld_i) begin
                vld_i_reg <= 1;
            end
        end 
    end

    // Khối Valid Register
    always @(posedge clk) begin
        if (!rst_n) begin
            vld <= 0;
        end else begin
            if (vld_i_rst) begin
                vld <= 0;
            end else begin
                vld <= vld_i_reg;
            end
        end 
    end

    // Khối cấu hình Base Address
    always @(posedge clk) begin
        if (!vld || channel_config_en) begin
            base_addr_config <= base_addr_config_nxt;
        end
    end

    // Khối đếm Channel
    always @(posedge clk) begin
        if (inf_rdy_dly) begin
            channel_config <= 0;
            channel_count <= 0;
        end else if (channel_config_en) begin
            channel_config <= (channel_config == ifbuf_inf_channel_reg - 1) ? 0 : channel_config + 1;
            channel_count <= en_config_rst ? 0 : channel_count + 1;
        end 
    end

    // Khối đếm Height
    always @(posedge clk) begin
        if (inf_rdy_dly) begin
            height_config <= 0;
            height_width_config <= 0;
        end else if (height_config_en) begin
            height_config <= (height_config == ifbuf_inf_width_reg - 1) ? 0 : height_config + 1;
            height_width_config <= (height_config == ifbuf_inf_width_reg - 1) ? 0 : height_width_config + ifbuf_dma_burst_o;
        end 
    end

    // Khối đếm Block
    always @(posedge clk) begin
        if (inf_rdy_dly) begin
            ifblock_count <= 0;
        end else if (ifblock_count_en) begin
            ifblock_count <= (ifblock_count == ifbuf_inf_ifblock_reg - 1) ? 0 : ifblock_count + 1;
        end 
    end

    // Khối Enable Config
    always @(posedge clk) begin
        if (!rst_n) begin
            en_config <= 1;
        end else begin
            if (en_config_rst) begin
                en_config <= 0;
            end else if(swap_en) en_config <= 1;
        end
    end

    // ==========================================
    // 3. Khối FIFO và logic sinh tự động (Giữ nguyên của bạn)
    // ==========================================
    
    assign clr              = count_depth_read_en;
    assign ifbuf_comp_vld_o = vld_o;
    assign swap_en          = done_prepare && (!vld_o || clr);
    assign ifbuf_dma_rdy_o  = !done_prepare;
    reg [10:0] channel_wr_cnt;
    always @(posedge clk) begin
        if (!rst_n) begin
            channel_wr_cnt <= 0;
        end else if (ifbuf_dma_tlast_i && ifbuf_dma_vld_i) begin
            channel_wr_cnt <= channel_wr_cnt == ifbuf_inf_channel_reg - 1 ? 0 : channel_wr_cnt + 1;
        end 
    end
    always @(posedge clk) begin
        if(!rst_n) begin
            done_prepare <= 0;
        end else begin
            if(swap_en) done_prepare <= 0;
            else if (ifbuf_dma_vld_i && ifbuf_dma_tlast_i && (channel_wr_cnt + 1 == channel_config || channel_wr_cnt == ifbuf_inf_channel_reg - 1) && !en_config) begin
                done_prepare <= 1;
            end
        end 
    end
    always @(posedge clk) begin
        if(!rst_n) begin
            id <= 0;
        end else begin
            if(swap_en) id <= !id;
        end 
    end

    genvar i;
    generate
        for (i = 0; i < K; i = i + 1) begin : fifo_array
            always @(posedge clk) begin
                if (!rst_n) begin
                    key_ring[i] <= (i == 0) ? 1'b1 : 1'b0;
                end else begin
                    if (swap_en) begin
                        key_ring[i] <= (i == 0) ? 1'b1 : 1'b0;
                    end else if(ifbuf_dma_tlast_i && ifbuf_dma_vld_i) begin
                        key_ring[i] <= (i == 0) ? key_ring[K - 1] : key_ring[i - 1];
                    end
                end
            end
        end
    endgenerate
    ping_pong_circle_fifo #(
        .WIDTH(DATA_WIDTH),
        .DEPTH(DEPTH)
    ) ifbuf_uut (
        .clk    (clk),
        .rst_n  (rst_n),
        .id_i   (id),
        .wr_en  (wr_en[0]),
        .rd_en  (count_w_read_en && !is_padding_data),
        .clr_i  (clr),
        .data_i (ifbuf_dma_data_i),
        .zp(ifbuf_inf_ifc_zp_reg),
        .data_o (data_o[0 +: DATA_WIDTH]),
        .vld_o  (vld_o)
    );
    genvar pp;
    generate
        for (pp = 1; pp < K; pp = pp + 1) begin : ping_pong
            ping_pong_ifbuf #(
                .WIDTH(DATA_WIDTH),
                .DEPTH(DEPTH)
            ) ifbuf_uut (
                .clk    (clk),
                .rst_n  (rst_n),
                .id_i   (id),
                .wr_en  (wr_en[pp]),
                .rd_en  (count_w_read_en && !is_padding_data),
                .clr_i  (clr),
                .data_i (ifbuf_dma_data_i),
                .zp(ifbuf_inf_ifc_zp_reg),
                .data_o (data_o[pp*DATA_WIDTH +: DATA_WIDTH]),
                .vld_o  ()
            );
        end
    endgenerate
    assign ifbuf_comp_data_o = is_padding_data ? {K{ifbuf_inf_ifc_zp_reg}} : data_o;
    genvar j;
    generate
        for (j = 0; j < K; j = j + 1) begin : wr_en_array
            assign wr_en[j] = ifbuf_dma_vld_i && (!ifbuf_dma_tlast_i || !ifbuf_inf_width_reg[0]) && key_ring[j]; 
        end
    endgenerate
    assign is_padding_data          = count_w_read < ifbuf_inf_padding_reg || count_w_read >= ifbuf_inf_width_reg + ifbuf_inf_padding_reg;
    assign count_w_read_en          = ifbuf_comp_rdy_i && ifbuf_comp_vld_o;
    assign count_oftiles_read_en    = count_w_read_en && (count_w_read == ifbuf_inf_wp_reg);
    assign count_depth_read_en      = count_oftiles_read_en && ((ifblock_count_r == ifbuf_inf_ifblock_reg - 1) && (count_oftiles_read == ifbuf_inf_oftiles_tail_reg - 1) || (count_oftiles_read == ifbuf_inf_oftiles_reg - 1));
    assign count_height_read_en     = count_depth_read_en && (count_depth_read == ifbuf_inf_iftiles_reg - 1);
    assign ifblock_count_r_en       = count_height_read_en && (count_height_read == ifbuf_inf_width_reg - 1);
    always @(posedge clk) begin
        if(swap_en) begin
            count_w_read <= 9'b0;
        end else if(count_w_read_en) begin
            count_w_read <= (count_w_read == ifbuf_inf_wp_reg) ? 9'b0 : count_w_read + 1;
        end 
    end

    always @(posedge clk) begin
        if(!rst_n) begin
            count_oftiles_read <= 11'b0;
        end else if(count_oftiles_read_en) begin
            count_oftiles_read <= ((ifblock_count_r == ifbuf_inf_ifblock_reg - 1) && (count_oftiles_read == ifbuf_inf_oftiles_tail_reg - 1) || (count_oftiles_read == ifbuf_inf_oftiles_reg - 1)) ? 11'b0 : count_oftiles_read + 1;
        end
    end
    always @(posedge clk) begin
        if (!rst_n) begin
            ifblock_count_r <= 0;
        end else if (ifblock_count_r_en) begin
            ifblock_count_r <= (ifblock_count_r == ifbuf_inf_ifblock_reg - 1) ? 0 : ifblock_count_r + 1;
        end 
    end
    always @(posedge clk) begin
        if(!rst_n) begin
            count_depth_read <= 11'b0;
        end else if(count_depth_read_en) begin
            count_depth_read <= (count_depth_read == ifbuf_inf_iftiles_reg - 1) ? 11'b0 : count_depth_read + 1;
        end
    end

    always @(posedge clk) begin
        if(!rst_n) begin
            count_height_read <= 9'b0;
        end else if(count_height_read_en) begin
            count_height_read <= (count_height_read == ifbuf_inf_width_reg - 1) ? 9'b0 : count_height_read + 1;
        end
    end
    assign ifbuf_comp_end_row_o         = (count_w_read == ifbuf_inf_wp_reg);
    assign ifbuf_comp_end_row_circle_o  = ifbuf_comp_end_row_o && ((ifblock_count_r == ifbuf_inf_ifblock_reg - 1) && (count_oftiles_read == ifbuf_inf_oftiles_tail_reg - 1) || (count_oftiles_read == ifbuf_inf_oftiles_reg - 1));
    assign ifbuf_comp_end_depth_o       = ifbuf_comp_end_row_circle_o && (count_depth_read == ifbuf_inf_iftiles_reg - 1);
    assign ifbuf_comp_end_layer_o       = ifbuf_comp_end_depth_o && (count_height_read == ifbuf_inf_width_reg - 1);
    assign ifbuf_comp_end_layer_real_o  = ifbuf_comp_end_layer_o && (ifblock_count_r == ifbuf_inf_ifblock_reg - 1);
endmodule


module ping_pong_ifbuf #(
    parameter WIDTH = 8,
    parameter DEPTH = 11
)(
    input               clk,
    input               rst_n,
    input               id_i,
    input               wr_en,
    input               rd_en,
    input               clr_i,
    input   [WIDTH-1:0] data_i,
    input   [WIDTH-1:0] zp,
    output  [WIDTH-1:0] data_o,
    output              vld_o
    );
    wire [WIDTH-1:0]    data_o1, data_o2;
    wire [WIDTH-1:0]    data_i1, data_i2;
    wire                wr_en1, wr_en2;
    wire                rd_en1, rd_en2;
    wire                clr1, clr2;
    wire                vld1, vld2;

    assign rd_en1   = rd_en & ~id_i;
    assign rd_en2   = rd_en & id_i;
    assign clr1     = clr_i & ~id_i;
    assign clr2     = clr_i & id_i;
    assign wr_en1   = wr_en & id_i; // Cho phep ghi vao fifo1 khi id_i=1
    assign wr_en2   = wr_en & ~id_i;  // Cho phep ghi vao fifo2 khi id_i=0
    assign data_i1  = data_i; // Du lieu vao fifo1 la data_i khi ghi, la data_o1 khi doc
    assign data_i2  = data_i; // Du lieu vao fifo2 la data_i khi ghi, la data_o2 khi doc
    assign data_o   = id_i ? data_o2 : data_o1;
    assign vld_o    = id_i ? vld2 : vld1;
    fifo_bram_zp #(
        .WIDTH(WIDTH),
        .DEPTH(DEPTH)
    ) ifbuf_mem0 (
        .clk(clk),
        .rst_n(rst_n),
        .wr_en(wr_en1 || rd_en1 && vld1),
        .rd_en(rd_en1),
        .clr(clr1),
        .din(rd_en1 && vld1 ? data_o1 : data_i1),
        .zp(zp),
        .dout(data_o1),
        .full(),
        .vld_o(vld1),
        .end_data()
    );
    fifo_bram_zp #(
        .WIDTH(WIDTH),
        .DEPTH(DEPTH)
    ) ifbuf_mem1 (
        .clk(clk),
        .rst_n(rst_n),
        .wr_en(wr_en2 || rd_en2 && vld2),
        .rd_en(rd_en2),
        .clr(clr2),
        .din(rd_en2 && vld2 ? data_o2 : data_i2),
        .zp(zp),
        .dout(data_o2),
        .full(),
        .vld_o(vld2),
        .end_data()
    );
endmodule
