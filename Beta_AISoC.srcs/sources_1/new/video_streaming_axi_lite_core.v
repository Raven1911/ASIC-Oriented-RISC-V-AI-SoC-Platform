`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 05/04/2026 11:49:11 AM
// Design Name: 
// Module Name: video_streaming_axi_lite_core
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

module video_streaming_axi_lite_core#(
    // ========================================================
    // AXI-LITE CONFIGURATION (CPU PORT)
    // ========================================================
    parameter NUM_MASTERS           = 1,
    parameter ADDR_WIDTH            = 32,          // AXI-Lite Address width
    parameter DATA_WIDTH            = 32,          // AXI-Lite Data width
    parameter TRANS_W_STRB_W        = 4,           // width strobe
    parameter TRANS_WR_RESP_W       = 2,           // width response
    parameter TRANS_PROT            = 3,
    parameter CYCLE_CLOCK           = 2,

    // Config register memory map
    //
    // REG0: resize geometry packed config
    //   [7:0]   out_size
    //   [15:8]  scaled_h
    //   [23:16] pad_top
    //   [24]    output_bgr
    //
    // REG1: out_pixels = out_size * out_size
    // REG2: x_step Q16.16
    // REG3: y_step Q16.16
    // REG4: control
    //   [0] enb_videosys
    //   [1] grant_rqs
    //
    // REG5: preprocessing LUT write, full-word write only
    //   [1:0]   LUT channel, 0=R, 1=G, 2=B
    //   [9:2]   LUT address, source pixel value 0..255
    //   [17:10] LUT data, signed int8 result
    //   [31]    write pulse
    parameter [ADDR_WIDTH-1:0] ADDR_REGISTERS_0 = 32'h0200_8000,
    parameter [ADDR_WIDTH-1:0] ADDR_REGISTERS_1 = 32'h0200_8004,
    parameter [ADDR_WIDTH-1:0] ADDR_REGISTERS_2 = 32'h0200_8008,
    parameter [ADDR_WIDTH-1:0] ADDR_REGISTERS_3 = 32'h0200_800C,
    parameter [ADDR_WIDTH-1:0] ADDR_REGISTERS_4 = 32'h0200_8010,
    parameter [ADDR_WIDTH-1:0] ADDR_REGISTERS_5 = 32'h0200_8014,

    parameter                           BURST_SELECT_WIDTH = 16,
    parameter                           DATA_WIDTH_BYTE    = 1
)(
    // ========================================================
    // 1. SYSTEM SIGNALS
    // ========================================================
    input                               clk,
    input                               clk24MHz_i,
    input                               clk25MHz_i,
    input                               clk50MHz_i,
    input                               resetn,


    // ========================================================
    // 2. AXI-LITE INTERFACE (CPU)
    // ========================================================
    // Write Address Channel
    input       [ADDR_WIDTH-1:0]        i_axi_awaddr,
    input                               i_axi_awvalid,
    output                              o_axi_awready,
    input       [TRANS_PROT-1:0]        i_axi_awprot,

    // Write Data Channel
    input       [DATA_WIDTH-1:0]        i_axi_wdata,
    input       [TRANS_W_STRB_W-1:0]    i_axi_wstrb,
    input                               i_axi_wvalid,
    output                              o_axi_wready,

    // Write Response Channel
    output      [TRANS_WR_RESP_W-1:0]   o_axi_bresp,
    output                              o_axi_bvalid,
    input                               i_axi_bready,

    // Read Address Channel
    input       [ADDR_WIDTH-1:0]        i_axi_araddr,
    input                               i_axi_arvalid,
    output                              o_axi_arready,
    input       [TRANS_PROT-1:0]        i_axi_arprot,

    // Read Data Channel
    output      [DATA_WIDTH-1:0]        o_axi_rdata,
    output                              o_axi_rvalid,
    output      [TRANS_WR_RESP_W-1:0]   o_axi_rresp,
    input                               i_axi_rready,


    /////////////////////////////////////////////
    output                              grant_request_cam2accel_o,
    // handshaking accel signal
    input                               ARVALID_i,
    output                              ARREADY_o,
    input   [ADDR_WIDTH-1:0]            ARADDR_i,
    input   [BURST_SELECT_WIDTH-1:0]    ARBURST_i,

    // --- AXIS Master Port (Read data out for Accel) ---
    output                              m_tvalid_o,
    input                               m_tready_i,
    output  [DATA_WIDTH_BYTE*8-1:0]     m_tdata_o,
    output  [DATA_WIDTH_BYTE-1:0]       m_tstrb_o,
    output  [DATA_WIDTH_BYTE-1:0]       m_tkeep_o,
    output                              m_tlast_o,
    output                              m_tid_o,

    // Camera Interface (Asynchronous to clk_i)
    input                               cam_pclk_i,
    input   [7:0]                       cam_half_pixel_i,   // Incoming 8-bit pixel data
    input                               cam_href,           // Horizontal Enable
    input                               cam_vsync,          // Vertical Sync
    output                              cam_xclk_o,         // Camera external clock output

    // HDMI Interface (Asynchronous to clk_i)
    output                              HDMI_TX_HS,         // Horizontal Sync
    output                              HDMI_TX_VS,         // Vertical Sync
    output                              HDMI_TX_DE,         // (DE) Báo hiệu vùng pixel hợp lệ (ĐÃ TRỄ 1 CYCLE)
    output                              HDMI_TX_CLK,        // Clock cho ADV7511/HDMI (như module gốc)
    output  [23:0]                      HDMI_TX_D           // Dữ liệu RGB 24-bit (ĐÃ TRỄ 1 CYCLE)
);


    // ========================================================
    // INTERNAL WIRES DECLARATION
    // ========================================================
    // AXI-Lite internal connections
    wire [ADDR_WIDTH-1:0]           o_addr_w;
    wire [ADDR_WIDTH-1:0]           o_addr_r;                
    wire [DATA_WIDTH-1:0]           o_data_w;
    wire [DATA_WIDTH-1:0]           i_data_r;
    wire [TRANS_W_STRB_W-1:0]       o_wen;
    wire                            o_wr_w;
    wire                            o_rd_r;

    // Register decode signals
    wire                            wr_reg0;
    wire                            wr_reg1;
    wire                            wr_reg2;
    wire                            wr_reg3;
    wire                            wr_reg4;
    wire                            wr_reg5;

    // Read data wires
    wire [DATA_WIDTH-1:0]           video_streaming_reg0;
    wire [DATA_WIDTH-1:0]           video_streaming_reg1;
    wire [DATA_WIDTH-1:0]           video_streaming_reg2;
    wire [DATA_WIDTH-1:0]           video_streaming_reg3;
    wire [DATA_WIDTH-1:0]           video_streaming_reg4;
    wire [DATA_WIDTH-1:0]           video_streaming_reg5;
    reg  [DATA_WIDTH-1:0]           rdata_mux;

    // Runtime resize config registers.
    // Defaults match the old built-in 96x96 resize setting:
    //   scaled_h = 72, pad_top = 12,
    //   x_step = y_step = floor((640 << 16) / 96) = 436906.
    reg        [7:0]                resize_out_size_reg;
    reg        [23:0]               resize_out_pixels_reg;
    reg        [7:0]                resize_scaled_h_reg;
    reg        [7:0]                resize_pad_top_reg;
    reg        [31:0]               resize_x_step_reg;
    reg        [31:0]               resize_y_step_reg;
    reg                             resize_output_bgr_reg;

    // Last LUT write command is kept for CPU readback/debug.
    // The actual LUT write pulse is generated directly from a full-word
    // AXI-Lite write to REG5, so channel/address/data are stable at the
    // same clk edge that resize_maxpooling samples preproc_lut_wr_en_i.
    reg        [31:0]               preproc_lut_write_reg;
    wire                            preproc_lut_wr_en;
    wire       [1:0]                preproc_lut_channel;
    wire       [7:0]                preproc_lut_addr;
    wire signed [7:0]               preproc_lut_data;

    reg                             grant_rqs;
    reg                             enb_videosys;

    wire                            resetn_video;

    assign cam_xclk_o = clk24MHz_i;

    // o_wen[0] -> data[7:0], o_wen[1] -> data[15:8],
    // o_wen[2] -> data[23:16], o_wen[3] -> data[31:24].
    // Address decode uses o_addr_w/o_addr_r directly, no address align.
    assign wr_reg0 = (o_wr_w && (o_addr_w[31:0] == ADDR_REGISTERS_0)) ? 1'b1 : 1'b0;
    assign wr_reg1 = (o_wr_w && (o_addr_w[31:0] == ADDR_REGISTERS_1)) ? 1'b1 : 1'b0;
    assign wr_reg2 = (o_wr_w && (o_addr_w[31:0] == ADDR_REGISTERS_2)) ? 1'b1 : 1'b0;
    assign wr_reg3 = (o_wr_w && (o_addr_w[31:0] == ADDR_REGISTERS_3)) ? 1'b1 : 1'b0;
    assign wr_reg4 = (o_wr_w && (o_addr_w[31:0] == ADDR_REGISTERS_4)) ? 1'b1 : 1'b0;
    assign wr_reg5 = (o_wr_w && (o_addr_w[31:0] == ADDR_REGISTERS_5)) ? 1'b1 : 1'b0;

    assign preproc_lut_wr_en  = wr_reg5 && (&o_wen) && o_data_w[31];
    assign preproc_lut_channel = o_data_w[1:0];
    assign preproc_lut_addr    = o_data_w[9:2];
    assign preproc_lut_data    = o_data_w[17:10];

    // Write RW registers, Verilog style, no function.
    always @(posedge clk or negedge resetn) begin
        if (~resetn) begin
            resize_out_size_reg     <= 8'd96;
            resize_out_pixels_reg   <= 24'd9216;
            resize_scaled_h_reg     <= 8'd72;
            resize_pad_top_reg      <= 8'd12;
            resize_x_step_reg       <= 32'd436906;
            resize_y_step_reg       <= 32'd436906;
            resize_output_bgr_reg   <= 1'b0;
            preproc_lut_write_reg   <= 32'd0;
            grant_rqs               <= 1'b0;
            enb_videosys            <= 1'b1;
        end else begin
            if (wr_reg0) begin
                if (o_wen[0]) begin
                    resize_out_size_reg <= o_data_w[7:0];
                end
                if (o_wen[1]) begin
                    resize_scaled_h_reg <= o_data_w[15:8];
                end
                if (o_wen[2]) begin
                    resize_pad_top_reg <= o_data_w[23:16];
                end
                if (o_wen[3]) begin
                    resize_output_bgr_reg <= o_data_w[24];
                end
            end

            if (wr_reg1) begin
                if (o_wen[0]) begin
                    resize_out_pixels_reg[7:0] <= o_data_w[7:0];
                end
                if (o_wen[1]) begin
                    resize_out_pixels_reg[15:8] <= o_data_w[15:8];
                end
                if (o_wen[2]) begin
                    resize_out_pixels_reg[23:16] <= o_data_w[23:16];
                end
            end

            if (wr_reg2) begin
                if (o_wen[0]) begin
                    resize_x_step_reg[7:0] <= o_data_w[7:0];
                end
                if (o_wen[1]) begin
                    resize_x_step_reg[15:8] <= o_data_w[15:8];
                end
                if (o_wen[2]) begin
                    resize_x_step_reg[23:16] <= o_data_w[23:16];
                end
                if (o_wen[3]) begin
                    resize_x_step_reg[31:24] <= o_data_w[31:24];
                end
            end

            if (wr_reg3) begin
                if (o_wen[0]) begin
                    resize_y_step_reg[7:0] <= o_data_w[7:0];
                end
                if (o_wen[1]) begin
                    resize_y_step_reg[15:8] <= o_data_w[15:8];
                end
                if (o_wen[2]) begin
                    resize_y_step_reg[23:16] <= o_data_w[23:16];
                end
                if (o_wen[3]) begin
                    resize_y_step_reg[31:24] <= o_data_w[31:24];
                end
            end

            if (wr_reg4) begin
                if (o_wen[0]) begin
                    enb_videosys <= o_data_w[0];
                    grant_rqs    <= o_data_w[1];
                end
            end

            if (wr_reg5) begin
                if (o_wen[0]) begin
                    preproc_lut_write_reg[7:0] <= o_data_w[7:0];
                end
                if (o_wen[1]) begin
                    preproc_lut_write_reg[15:8] <= o_data_w[15:8];
                end
                if (o_wen[2]) begin
                    preproc_lut_write_reg[23:16] <= o_data_w[23:16];
                end
                if (o_wen[3]) begin
                    preproc_lut_write_reg[31:24] <= o_data_w[31:24];
                end
            end
        end
    end

    // Read data register map
    assign video_streaming_reg0 = {7'b0, resize_output_bgr_reg, resize_pad_top_reg, resize_scaled_h_reg, resize_out_size_reg};
    assign video_streaming_reg1 = {8'b0, resize_out_pixels_reg};
    assign video_streaming_reg2 = resize_x_step_reg;
    assign video_streaming_reg3 = resize_y_step_reg;
    assign video_streaming_reg4 = {30'b0, grant_rqs, enb_videosys};
    assign video_streaming_reg5 = preproc_lut_write_reg;

    // Read Data Multiplexer
    always @(*) begin
        case (o_addr_r)
            ADDR_REGISTERS_0: rdata_mux = video_streaming_reg0;
            ADDR_REGISTERS_1: rdata_mux = video_streaming_reg1;
            ADDR_REGISTERS_2: rdata_mux = video_streaming_reg2;
            ADDR_REGISTERS_3: rdata_mux = video_streaming_reg3;
            ADDR_REGISTERS_4: rdata_mux = video_streaming_reg4;
            ADDR_REGISTERS_5: rdata_mux = video_streaming_reg5;
            default:          rdata_mux = 32'h0;
        endcase
    end

    assign i_data_r = rdata_mux;

    assign grant_request_cam2accel_o = grant_rqs;
    // assign resetn_video = resetn & enb_videosys;

    reg resetn_video_reg;

    always @(posedge clk or negedge resetn) begin
        if (~resetn) begin
            resetn_video_reg <= 1'b0;
        end else begin
            // Khi resetn ở mức cao, đồng bộ hóa tín hiệu enable qua một flip-flop
            resetn_video_reg <= enb_videosys; 
        end
    end

    // wire resetn_video;
    assign resetn_video = resetn_video_reg;

    DVP_RX_TX_core DVP_core (
        // System Clock Domain
        .clk_i               (clk),
        .clk25MHz_i          (clk25MHz_i),
        .clk50MHz_i          (clk50MHz_i),
        .resetn_i            (resetn_video),

        // Camera Interface
        .cam_pclk_i          (cam_pclk_i),
        .cam_half_pixel_i    (cam_half_pixel_i),
        .cam_href            (cam_href),
        .cam_vsync           (cam_vsync),

        // DUT Outputs
        .hsync               (HDMI_TX_HS),
        .vsync               (HDMI_TX_VS),
        .dataEnable          (HDMI_TX_DE),
        .vgaClock            (HDMI_TX_CLK),
        .RGBchannel          (HDMI_TX_D),

        // Config Frame
        .resolution_width_i  ('d640),
        .resolution_depth_i  ('d480),

        // Runtime resize config
        .out_size_reg             (resize_out_size_reg),
        .out_pixels_reg           (resize_out_pixels_reg),
        .scaled_h_reg             (resize_scaled_h_reg),
        .pad_top_reg              (resize_pad_top_reg),
        .x_step_reg               (resize_x_step_reg),
        .y_step_reg               (resize_y_step_reg),
        .output_bgr_reg           (resize_output_bgr_reg),

        // Runtime preprocessing LUT write port
        .preproc_lut_wr_en_i      (preproc_lut_wr_en),
        .preproc_lut_channel_i    (preproc_lut_channel),
        .preproc_lut_addr_i       (preproc_lut_addr),
        .preproc_lut_data_i       (preproc_lut_data),

        // handshaking accel signal
        .ARVALID_i(ARVALID_i),
        .ARREADY_o(ARREADY_o),
        .ARADDR_i(ARADDR_i),
        .ARBURST_i(ARBURST_i),

        // --- AXIS Master Port (Read data out for Accel) ---
        .m_tvalid_o(m_tvalid_o),
        .m_tready_i(m_tready_i),
        .m_tdata_o(m_tdata_o),
        .m_tstrb_o(m_tstrb_o),
        .m_tkeep_o(m_tkeep_o),
        .m_tlast_o(m_tlast_o),
        .m_tid_o(m_tid_o)
    );




    axi_lite_slave_interface #(
        .ADDR_WIDTH         (ADDR_WIDTH),
        .DATA_WIDTH         (DATA_WIDTH),
        .TRANS_W_STRB_W     (TRANS_W_STRB_W),
        .TRANS_WR_RESP_W    (TRANS_WR_RESP_W),
        .TRANS_PROT         (TRANS_PROT),
        .CYCLE_CLOCK        (CYCLE_CLOCK),
        .NUM_MASTERS        (NUM_MASTERS)
    ) dvp_axi_lite_interface (
        .clk_i              (clk),
        .resetn_i           (resetn),

        .i_axi_awaddr       (i_axi_awaddr),
        .i_axi_awvalid      (i_axi_awvalid),
        .o_axi_awready      (o_axi_awready),
        .i_axi_awprot       (i_axi_awprot),

        .i_axi_wdata        (i_axi_wdata),
        .i_axi_wstrb        (i_axi_wstrb),
        .i_axi_wvalid       (i_axi_wvalid),
        .o_axi_wready       (o_axi_wready),

        .o_axi_bresp        (o_axi_bresp),
        .o_axi_bvalid       (o_axi_bvalid),
        .i_axi_bready       (i_axi_bready),

        .i_axi_araddr       (i_axi_araddr),
        .i_axi_arvalid      (i_axi_arvalid),
        .o_axi_arready      (o_axi_arready),
        .i_axi_arprot       (i_axi_arprot),

        .o_axi_rdata        (o_axi_rdata),
        .o_axi_rvalid       (o_axi_rvalid),
        .o_axi_rresp        (o_axi_rresp),
        .i_axi_rready       (i_axi_rready),

        .o_addr_w           (o_addr_w),
        .o_awprot_w         (),

        .o_wen              (o_wen),   
        .o_data_w           (o_data_w),
        .o_write_data_w     (o_wr_w),

        .i_bresp_w          (2'b00),

        .o_addr_r           (o_addr_r),
        .o_arprot_r         (),
        
        .i_data_r           (i_data_r),
        .i_rresp_r          (2'b00),
        .o_read_data_r      (o_rd_r)
    );

endmodule


module DVP_RX_TX_core#(
    parameter DATA_WIDTH = 8,
    parameter ADDR_WIDTH_FIFO = 11,
    parameter DATA_WIDTH_FIFO = 16,

    parameter BRAM_ADDR_WIDTH = 32,
    parameter BRAM_DATA_WIDTH = 16,
    parameter BRAM_NUMBER_BLOCK = 5,   
    parameter BRAM_DEPTH_SIZE = 65536,   
    parameter BRAM_MODE = 2,
    parameter BRAM_ENB_TEST_PATTERN = 0,

    parameter FIFO_DATA_WIDTH = 16,
    parameter FIFO_DEPTH_WIDTH = 9,

    parameter                           ADDR_WIDTH = 24,
    parameter                           BURST_SELECT_WIDTH = 16,
    parameter                           DATA_WIDTH_BYTE = 1


)(
    // System Clock Domain
    input                           clk_i,      // System clock (Faster than cam_pclk_i)
    input                           clk25MHz_i, // clock ip hdmi
    input                           clk50MHz_i, // clock ip hdmi
    input                           resetn_i,   // Asynchronous reset (active low)

    // Camera Interface (Asynchronous to clk_i)
    input                           cam_pclk_i,
    input   [DATA_WIDTH-1:0]        cam_half_pixel_i, // Incoming 8-bit pixel data
    input                           cam_href,   // Horizontal Enable
    input                           cam_vsync,  // Vertical Sync
    

    output                          hsync,        // Horizontal Sync
    output                          vsync,        // Vertical Sync
    output                          dataEnable,   // (DE) Báo hiệu vùng pixel hợp lệ (ĐÃ TRỄ 1 CYCLE)
    output                          vgaClock,     // Clock cho ADV7511/HDMI (như module gốc)
    output  [23:0]                  RGBchannel, // Dữ liệu RGB 24-bit (ĐÃ TRỄ 1 CYCLE)

    //config frame
    input   [15:0]                  resolution_width_i,
    input   [15:0]                  resolution_depth_i,

    // Runtime resize config.
    // CPU writes these through video_streaming_axi_lite_core before
    // issuing accelerator read requests.
    input          [7:0]            out_size_reg,
    input   [ADDR_WIDTH-1:0]        out_pixels_reg,
    input          [7:0]            scaled_h_reg,
    input          [7:0]            pad_top_reg,
    input         [31:0]            x_step_reg,
    input         [31:0]            y_step_reg,
    input                           output_bgr_reg,

    // Runtime preprocessing LUT write port.
    // CPU should load all 3x256 entries before resize processing.
    input                           preproc_lut_wr_en_i,
    input          [1:0]            preproc_lut_channel_i,
    input          [7:0]            preproc_lut_addr_i,
    input   signed [7:0]            preproc_lut_data_i,

    // handshaking accel signal
    input                               ARVALID_i,
    output                              ARREADY_o,
    input   [ADDR_WIDTH-1:0]            ARADDR_i,
    input   [BURST_SELECT_WIDTH-1:0]    ARBURST_i,

    // --- AXIS Master Port (Read data out for Accel) ---
    output                              m_tvalid_o,
    input                               m_tready_i,
    output  [DATA_WIDTH_BYTE*8-1:0]     m_tdata_o,
    output  [DATA_WIDTH_BYTE-1:0]       m_tstrb_o,
    output  [DATA_WIDTH_BYTE-1:0]       m_tkeep_o,
    output                              m_tlast_o,
    output                              m_tid_o






    );


    wire                            wr_pixel_o;
    wire    [DATA_WIDTH*2-1:0]      pixel_data_o;

    wire    [23:0]                  fb_addr;
    wire    [15:0]                  fb_pixel_data;

    // Declare frame-buffer/FIFO control wires before their first use.
    // The old file declared some of these after instances, which caused
    // Vivado to create implicit nets first and then report duplicate
    // declarations when the explicit wire declarations appeared later.
    wire                            ctrl_empty;
    wire                            ctrl_full;
    wire                            ctrl_wr;
    wire                            ctrl_rd;
    wire                            ctrl2fifo_rd;
    wire                            ctrl2fifo_rd_2;
    wire    [BRAM_ADDR_WIDTH-1:0]   ctrl_addr_wr;
    wire    [BRAM_ADDR_WIDTH-1:0]   ctrl_addr_rd;
    wire    [DATA_WIDTH*2-1:0]      ctrl_data_i;
    wire    [DATA_WIDTH*2-1:0]      delay_data_i;
    wire    [DATA_WIDTH*2-1:0]      ctrl_data_o;
    wire    [FIFO_DEPTH_WIDTH-1:0]  data_count_w;
    wire    [15:0]                  rgb565_wire;
    wire                            fifo_read_en;
    wire                            fifo_hdmi_empty;



    // Instantiate the Unit Under Test (DUT)

    wire detect_vsync;
    wire n_edge_vsync;
    uiSensorRGB565 cam_Sensor (
        .rstn_i(resetn_i),
        .cmos_clk_i(),
        .cmos_pclk_i(cam_pclk_i),
        .cmos_href_i(cam_href),
        .cmos_vsync_i(cam_vsync),
        .cmos_data_i(cam_half_pixel_i),
        .cmos_xclk_o(),
        .rgb_o(pixel_data_o),
        .de_o(wr_pixel_o),
        .vs_o(detect_vsync),
        .hs_o()
    );

    edge_detector edge_vsync(
        .clk(clk_i),
        .reset_n(resetn_i),
        .level_edge(detect_vsync),
        .p_edge(),
        .n_edge(n_edge_vsync),
        .any_edge()
    );



    // ov5640_data ov5640_data_inst(
    //     .sys_rst_n          (resetn_i),  //复位信号
    //     .ov5640_pclk        (cam_pclk_i    ),   //摄像头像素时钟
    //     .ov5640_href        (cam_href    ),   //摄像头行同步信号
    //     .ov5640_vsync       (cam_vsync   ),   //摄像头场同步信号
    //     .ov5640_data        (cam_half_pixel_i    ),   //摄像头图像数据

    //     .ov5640_wr_en       (wr_pixel_o   ),   //图像数据有效使能信号
    //     .ov5640_data_out    (pixel_data_o)    //图像数据

    // );


    wire [FIFO_DEPTH_WIDTH-1:0] data_count_r;

    asyn_fifo #(
        .DATA_WIDTH(FIFO_DATA_WIDTH),
        .FIFO_DEPTH_WIDTH(FIFO_DEPTH_WIDTH)
    ) fifo_camera(
		.rst_n(resetn_i /* && !n_edge_vsync */),
		.clk_write(cam_pclk_i),
		.clk_read(clk_i), //clock input from both domains
		.write(wr_pixel_o),
		.read(ctrl_wr), 
		.data_write(pixel_data_o), //input FROM write clock domain
		.data_read(ctrl_data_i), //output TO read clock domain
		//.full(),
		.empty(ctrl_empty), //full=sync to write domain clk , empty=sync to read domain clk
        //.data_count_w(),
		.data_count_r(data_count_r)
    );

    // fifo_dvp_unit#(
    //     .ADDR_WIDTH(ADDR_WIDTH_FIFO),
    //     .DATA_WIDTH(DATA_WIDTH_FIFO)
    // ) fifo_camera (
    //     .clk(clk_i), 
    //     .reset_n(resetn_i),
    //     .wr(wr_pixel_o), 
    //     .rd(ctrl_wr),

    //     .w_data(pixel_data_o), //writing data
    //     .r_data(ctrl_data_i), //reading data

    //     .full(), 
    //     .empty(ctrl_empty)
    // );


    wire ctrl_delay_wr0;
    wire ctrl_delay_wr1;
    register_DFF #(
        .SIZE_BITS(1)
    ) delay_wr2framebuffer(
        .clk_i(clk_i),
        .resetn_i(resetn_i),
        .D_i(ctrl_wr),
        .Q_o(ctrl_delay_wr0)
    );

    register_DFF #(
        .SIZE_BITS(1)
    ) delay_wr12framebuffer(
        .clk_i(clk_i),
        .resetn_i(resetn_i),
        .D_i(ctrl_delay_wr0),
        .Q_o(ctrl_delay_wr1)
    );

    wire [BRAM_ADDR_WIDTH-1:0] delay_addr_wr0;
    wire [BRAM_ADDR_WIDTH-1:0] delay_addr_wr1;
    register_DFF #(
        .SIZE_BITS(BRAM_ADDR_WIDTH)
    ) delay_addr_wr2framebuffer(
        .clk_i(clk_i),
        .resetn_i(resetn_i),
        .D_i(ctrl_addr_wr),
        .Q_o(delay_addr_wr0)
    );
    register_DFF #(
        .SIZE_BITS(BRAM_ADDR_WIDTH)
    ) delay_addr1_wr2framebuffer(
        .clk_i(clk_i),
        .resetn_i(resetn_i),
        .D_i(delay_addr_wr0),
        .Q_o(delay_addr_wr1)
    );

    

    wire [BRAM_DATA_WIDTH-1:0] delay_data_wr;
    register_DFF #(
        .SIZE_BITS(BRAM_DATA_WIDTH)
    ) delay_data_wr2framebuffer(
        .clk_i(clk_i),
        .resetn_i(resetn_i),
        .D_i(ctrl_data_i),
        .Q_o(delay_data_wr)
    );
    

    frame_buffer # (
        .ADDR_WIDTH     (BRAM_ADDR_WIDTH),
        .DATA_WIDTH     (BRAM_DATA_WIDTH),
        .NUMBER_BRAM    (BRAM_NUMBER_BLOCK),
        .DEPTH_SIZE     (BRAM_DEPTH_SIZE),
        .MODE           (BRAM_MODE),
        .ENB_TEST_PATTERN(BRAM_ENB_TEST_PATTERN)
    ) frame_buffer_unit (
        .clk_i    (clk_i),
        .resetn_i (resetn_i),

        .wr0_i    (/*ctrl_wr*/ ctrl_delay_wr1),
        //.wr1_i    (),

        .addr_wr0 (delay_addr_wr1),
        //.addr_wr1 (),
        .addr_rd0 (ctrl_addr_rd),
        .addr_rd1 ({8'b0,fb_addr}),

        .Data_in0 (delay_data_wr /*ctrl_data_i*/),
        //.Data_in1 (),
        .Data_out0(ctrl_data_o),
        .Data_out1(fb_pixel_data)
    );

    wire page_written_once_wire;
    control_frame_buffer_write_only #(
        .ADDR_WIDTH(BRAM_ADDR_WIDTH),
        .FIFO_DEPTH_WIDTH(FIFO_DEPTH_WIDTH)
    ) control_write_frame_buffer (
        .clk_i(clk_i),
        .resetn_i(resetn_i),

        .resolution_width_i(resolution_width_i),
        .resolution_depth_i(resolution_depth_i),

        .empty_i(ctrl_empty),
        .data_count_r_i(data_count_r),
        .n_edge_vsync_i(n_edge_vsync),

        .wr_o(ctrl_wr),
        .addr_wr_o(ctrl_addr_wr),
        .page_written_once_o(page_written_once_wire)
    );

    control_frame_buffer_read_only #(
        .ADDR_WIDTH(BRAM_ADDR_WIDTH),
        .READ_STROBE_PERIOD(1),
        .FIFO_DEPTH_WIDTH(FIFO_DEPTH_WIDTH)
    ) control_read_frame_buffer (
        .clk_i(clk_i),  
        .resetn_i(resetn_i),

        .resolution_width_i(resolution_width_i),
        .resolution_depth_i(resolution_depth_i),

        .page_written_once_i(page_written_once_wire),
        .full_i(ctrl_full),
        .data_count_w_i(data_count_w),

        .rd_o(ctrl_rd),
        .addr_rd_o(ctrl_addr_rd)
    );


    register_DFF #(
        .SIZE_BITS(1)
    ) register_DFF_HDMI_FIFO (
        .clk_i(clk_i),
        .resetn_i(resetn_i),
        .D_i(ctrl_rd),
        .Q_o(ctrl2fifo_rd)
    );

    register_DFF #(
        .SIZE_BITS(1)
    ) register_DFF_HDMI_FIFO_2 (
        .clk_i(clk_i),
        .resetn_i(resetn_i),
        .D_i(ctrl2fifo_rd),
        .Q_o(ctrl2fifo_rd_2)
    );

    // fifo_dvp_unit#(
    //     .ADDR_WIDTH(ADDR_WIDTH_FIFO),
    //     .DATA_WIDTH(DATA_WIDTH_FIFO)
    // ) fifo_hdmi (
    //     .clk(clk_i), 
    //     .reset_n(resetn_i),
    //     .wr(ctrl2fifo_rd), 
    //     .rd(0),

    //     .w_data(ctrl_data_o), //writing data
    //     .r_data(), //reading data

    //     .full(ctrl_full), 
    //     .empty()
    // );

    wire wr_fifo_hdmi;
    assign wr_fifo_hdmi =  ctrl2fifo_rd_2;///* ctrl_rd | */ ctrl2fifo_rd;
    
    asyn_fifo #(
        .DATA_WIDTH(FIFO_DATA_WIDTH),
        .FIFO_DEPTH_WIDTH(FIFO_DEPTH_WIDTH) 
    ) fifo_hdmi(
		.rst_n(resetn_i),
		.clk_write(clk_i),
		.clk_read(clk25MHz_i), //clock input from both domains
		.write(wr_fifo_hdmi),
		.read(fifo_read_en), 
		.data_write(ctrl_data_o), //input FROM write clock domain
		.data_read(rgb565_wire), //output TO read clock domain
		.full(ctrl_full),
		.empty(fifo_hdmi_empty), //full=sync to write domain clk , empty=sync to read domain clk
        .data_count_w(data_count_w)//,
		//.data_count_r() //asserted if fifo is equal or more than than half of its max capacity
    );


    // fifo_dvp_unit#(
    //     .ADDR_WIDTH(ADDR_WIDTH_FIFO),
    //     .DATA_WIDTH(DATA_WIDTH_FIFO)
    // ) fifo_hdmi (
    //     .clk(clk_i), 
    //     .reset_n(resetn_i),
    //     .wr(wr_fifo_hdmi), 
    //     .rd(fifo_read_en),

    //     .w_data(ctrl_data_o), //writing data
    //     .r_data(rgb565_wire), //reading data

    //     .full(ctrl_full), 
    //     .empty(fifo_hdmi_empty)
    // );

    vgaHDMI_interface3 HDMI_interface_uut (
        .clock25(clk25MHz_i),
        .clock50(clk50MHz_i),
        .resetn(resetn_i),
        .fifo_data_in(rgb565_wire), 
        .empty_fifo(fifo_hdmi_empty),
        .hsync(hsync),
        .vsync(vsync),
        .dataEnable(dataEnable),
        .vgaClock(vgaClock),
        .RGBchannel(RGBchannel),
        .fifo_read_en(fifo_read_en)
    );


    resize_mover_data #(
        .ADDR_WIDTH         (ADDR_WIDTH),
        .BURST_SELECT_WIDTH (BURST_SELECT_WIDTH),
        .DATA_WIDTH_BYTE    (DATA_WIDTH_BYTE),
        .FB_READ_LATENCY    (2)
    ) resize_mover_data_dut (
        .clk_i                    (clk_i),
        .resetn_i                 (resetn_i),

        .out_size_reg             (out_size_reg),
        .out_pixels_reg           (out_pixels_reg),
        .scaled_h_reg             (scaled_h_reg),
        .pad_top_reg              (pad_top_reg),
        .x_step_reg               (x_step_reg),
        .y_step_reg               (y_step_reg),
        .output_bgr_reg           (output_bgr_reg),
        .preproc_lut_wr_en_i      (preproc_lut_wr_en_i),
        .preproc_lut_channel_i    (preproc_lut_channel_i),
        .preproc_lut_addr_i       (preproc_lut_addr_i),
        .preproc_lut_data_i       (preproc_lut_data_i),

        .fb_addr_o                (fb_addr),
        .fb_pixel_data_i          (fb_pixel_data),

        .ARVALID_i                (ARVALID_i),
        .ARREADY_o                (ARREADY_o),
        .ARADDR_i                 (ARADDR_i),
        .ARBURST_i                (ARBURST_i),

        .m_tvalid_o               (m_tvalid_o),
        .m_tready_i               (m_tready_i),
        .m_tdata_o                (m_tdata_o),
        .m_tstrb_o                (m_tstrb_o),
        .m_tkeep_o                (m_tkeep_o),
        .m_tlast_o                (m_tlast_o),
        .m_tid_o                  (m_tid_o)
    );

endmodule


// module register_DFF#(
//     SIZE_BITS = 32
// )(  
//     input                           clk_i,
//     input                           resetn_i,
//     input       [SIZE_BITS-1:0]    D_i,

//     output  reg [SIZE_BITS-1:0]    Q_o
// );
//     always @(posedge clk_i, negedge resetn_i) begin
//         if (~resetn_i) begin
//             Q_o <= 0;
//         end
//         else begin
//             Q_o <= D_i;
//         end
//     end

// endmodule


//FIFO

//module fifo
module fifo_dvp_unit #(parameter ADDR_WIDTH = 3, DATA_WIDTH = 8)(
    input clk, reset_n,
    input wr, rd,

    input [DATA_WIDTH - 1 : 0] w_data, //writing data
    output [DATA_WIDTH - 1 : 0] r_data, //reading data

    output full, empty

    );

    //signal
    wire [ADDR_WIDTH - 1 : 0] w_addr, r_addr;

    //instantiate registers file
    register_file_dvp #(.ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH))
        reg_file_dvp_unit(
            .clk(clk),
            .w_en(~full & wr),

            .r_addr(r_addr), //reading address
            .w_addr(w_addr), //writing address

            .w_data(w_data), //writing data
            .r_data(r_data) //reading data
        
        );

    //instantiate fifo ctrl
    fifo_ctrl_dvp #(.ADDR_WIDTH(ADDR_WIDTH))
        fifo_ctrl_dvp_unit(
            .clk(clk), 
            .reset_n(reset_n),
            .wr(wr), 
            .rd(rd),

            .full(full),
            .empty(empty),

            .w_addr(w_addr),
            .r_addr(r_addr)
        );

endmodule


module fifo_ctrl_dvp #(parameter ADDR_WIDTH = 3)(
    input clk, reset_n,
    input wr, rd,

    output reg full, empty,

    output [ADDR_WIDTH - 1 : 0] w_addr,
    output [ADDR_WIDTH - 1 : 0] r_addr
    );

    //variable sequential
    reg [ADDR_WIDTH - 1 : 0] w_ptr, w_ptr_next;
    reg [ADDR_WIDTH - 1 : 0] r_ptr, r_ptr_next;
 
    reg full_next, empty_next;


    // sequential circuit
    always @(posedge clk, negedge reset_n) begin
        if(~reset_n)begin
            w_ptr <= 'b0;
            r_ptr <= 'b0;
            full <= 1'b0;
            empty <= 1'b1;
        end

        else begin
            w_ptr <= w_ptr_next;
            r_ptr <= r_ptr_next;
            full <= full_next;
            empty <= empty_next;
        end

    end

    //combi circuit
    always @(*)begin
        //default
        w_ptr_next = w_ptr;
        r_ptr_next = r_ptr;
        full_next = full;
        empty_next = empty;

        case ({wr, rd})
            2'b01: begin    //read
                if(~empty)begin
                    r_ptr_next = r_ptr + 1;
                    full_next = 1'b0;
                    if(r_ptr_next == w_ptr)begin
                        empty_next = 1'b1;
                    end
                end
            end

            2'b10: begin    //write
                if(~full)begin
                    w_ptr_next = w_ptr + 1;
                    empty_next = 1'b0;
                    if(w_ptr_next == r_ptr)begin
                        full_next = 1'b1;
                    end
                end
            end

            2'b11: begin    //read & write
                if(empty)begin
                    w_ptr_next = w_ptr;
                    r_ptr_next = r_ptr;
                end

                else begin
                    w_ptr_next = w_ptr + 1;
                    r_ptr_next = r_ptr + 1;
                end
            end

            default: ; // 2'b00
        endcase


    end

    //output
    assign w_addr = w_ptr;
    assign r_addr = r_ptr;

endmodule



module register_file_dvp #(parameter ADDR_WIDTH = 3, DATA_WIDTH = 8)(
    input clk,
    input w_en,

    input [ADDR_WIDTH - 1 : 0] r_addr, //reading address
    input [ADDR_WIDTH - 1 : 0] w_addr, //writing address

    input [DATA_WIDTH - 1 : 0] w_data, //writing data
    output [DATA_WIDTH - 1 : 0] r_data //reading data
    );

    //memory buffer
    reg [DATA_WIDTH -1 : 0] memory [0 : 2 ** ADDR_WIDTH - 1];

    //wire operation
    always @(posedge clk) begin
        if (w_en) memory[w_addr] <= w_data;
        
    end

    //read operation
    assign r_data = memory[r_addr];

endmodule




module uiSensorRGB565(
    input rstn_i,
	input cmos_clk_i,//cmos senseor clock.
	input cmos_pclk_i,//input pixel clock.
	input cmos_href_i,//input pixel hs signal.
	input cmos_vsync_i,//input pixel vs signal.
	input [7:0]cmos_data_i,//data.
	output cmos_xclk_o,//output clock to cmos sensor.
    output [15:0] rgb_o,
    output de_o,
    output vs_o,
    output hs_o
    );
    
assign cmos_xclk_o = cmos_clk_i; 
     
reg cmos_href_r1 = 1'b0,cmos_href_r2 = 1'b0,cmos_href_r3 = 1'b0;
reg cmos_vsync_r1 = 1'b0,cmos_vsync_r2 = 1'b0;
reg [7:0]cmos_data_r1 = 8'b0;
reg [7:0]cmos_data_r2 = 8'b0;    

(* ASYNC_REG = "TRUE" *) reg rstn1,rstn2;

always@(posedge cmos_pclk_i)begin
    rstn1 <= rstn_i;
    rstn2 <= rstn1;
end



always@(posedge cmos_pclk_i)begin
       cmos_href_r1  <= cmos_href_i;
       cmos_href_r2  <= cmos_href_r1;
       cmos_href_r3  <= cmos_href_r2;       
       cmos_data_r1  <= cmos_data_i;
       cmos_data_r2  <= cmos_data_r1;
       cmos_vsync_r1 <= ~cmos_vsync_i;      
       cmos_vsync_r2 <= cmos_vsync_r1;       
end    

parameter [7:0] FRAM_FREE_CNT = 20; //number of frames to be free after reset, for sensor to be stable and output valid data. Depends on the sensor, can be adjusted according to the actual situation.
reg [7:0]vs_cnt;
wire vs_p = !cmos_vsync_r2&&cmos_vsync_r1;
always@(posedge cmos_pclk_i)begin
    if(!rstn2)begin
        vs_cnt <= 8'd0;
    end 
    else if(vs_p)begin
        if(vs_cnt < FRAM_FREE_CNT)
            vs_cnt <= vs_cnt + 1'b1;
         else
            vs_cnt <= vs_cnt;
    end
end    

wire out_en = (vs_cnt == FRAM_FREE_CNT);
//output data 8bit changed into 16bit in rgb565.

reg href_cnt   = 1'b0;
reg data_en  = 1'b0;
reg [15:0]rgb2 = 32'd0;

always@(posedge cmos_pclk_i)begin
	if(vs_p||(~out_en))begin
	   href_cnt  <= 1'd0;
	   data_en   <= 1'b0;
	   rgb2      <= 16'd0;
	end	
	else begin
	   href_cnt  <= cmos_href_r2 ?  href_cnt + 1'b1 : 1'b0 ;
       data_en   <= (href_cnt==1'd1);
       if(cmos_href_r2) begin
            rgb2 <= {rgb2[7:0],cmos_data_r2};
       end    
	end	
end

assign  rgb_o  = rgb2;

assign	de_o   =  out_en && data_en ;
assign	vs_o   =  out_en && cmos_vsync_r2 ;
assign	hs_o   =  out_en && cmos_href_r3 ;

endmodule



module vgaHDMI_interface3(
    // **input**
    input clock25, clock50, resetn,

    input wire              empty_fifo, // FIFO empty flag
    input wire [15:0]       fifo_data_in, // RGB565 data from FIFO
    output reg              fifo_read_en, // FIFO read enable

    // output               fifo_read_en, // FIFO read enable

    // **output**
    output  hsync, vsync,
    output  dataEnable,
    output  vgaClock,
    // output /* reg */ [23:0] RGBchannel
    output  reg  [23:0] RGBchannel
    );

    //FSM state declarations
	localparam      DELAY = 0,
					IDLE = 1,
					DISPLAY = 2;

    reg[1:0]    state_q,state_d;
    reg [23:0]  RGBchannel_q, RGBchannel_d;
    reg         fifo_read_en_q, fifo_read_en_d;
	wire[9:0]   pixel_x,pixel_y;

    //register operations
    always @(posedge clock25, negedge resetn) begin
        if(!resetn) begin
            state_q<=DELAY;
            
            RGBchannel_q <= 24'b0;
            // fifo_read_en_q <= 0;
        end
        else begin
            state_q<=state_d;
            RGBchannel_q <= RGBchannel_d;
            // fifo_read_en_q <= fifo_read_en_d;
        end
    end


    //FSM next-state logic
        always @* begin
        state_d=state_q; 
        RGBchannel_d = RGBchannel_q;
        fifo_read_en=0;
        fifo_read_en_d=0;
        // RGBchannel=24'b0;
        case(state_q)   
            DELAY: if(pixel_x==1 && pixel_y==1) begin
                state_d=IDLE; //delay of one frame(33ms) needed to start up the camera
            end
                
            IDLE:  if(pixel_x==1 && pixel_y==0 && !empty_fifo) begin //wait for pixel-data coming from asyn_fifo 
                        // RGBchannel_d = {fifo_data_in[15:11],3'b000, fifo_data_in[10:5],2'b00, fifo_data_in[4:0],3'b000}; //convert RGB565 to RGB888
                        RGBchannel = {
                            fifo_data_in[15:11], fifo_data_in[15:13],
                            fifo_data_in[10:5],  fifo_data_in[10:9],
                            fifo_data_in[4:0],   fifo_data_in[4:2]
                        }; // convert RGB565 to RGB888 by bit replication
                        
                        // RGBchannel_d = 24'hF8FCF8;
                        fifo_read_en = 1;
                        // fifo_read_en_d = 1; // Đọc dữ liệu từ FIFO ở trạng thái IDLE khi pixel bắt đầu hiển thị (pixel_x=1, pixel_y=0) và FIFO không rỗng	
                        state_d = DISPLAY;
                    end
            DISPLAY: if(pixel_x>=1 && pixel_x<=640 && pixel_y<480) begin //we will continue to read the asyn_fifo as long as current pixel coordinate is inside the visible screen(640x480) 
                            // RGBchannel_d = {fifo_data_in[15:11],3'b000, fifo_data_in[10:5],2'b00, fifo_data_in[4:0],3'b000}; //convert RGB565 to RGB888
                            //RGBchannel_d = 24'hF8FCF8;
                            fifo_read_en = 1;	
                            // fifo_read_en_d = 1;

                            // if (empty_fifo) begin
                            //     // TRƯỜNG HỢP 1: FIFO RỖNG -> Xuất màu ĐỎ để báo lỗi
                            //     RGBchannel_d = 24'hFF0000; 
                            // end 
                            // // else if (fifo_data_in == 16'h0000) begin
                            // //     // TRƯỜNG HỢP 2: FIFO CÓ DATA NHƯNG LÀ 0 -> Xuất màu XANH DƯƠNG
                            // //     // (Có thể do camera đang bị che tối om)
                            // //     RGBchannel_d = 24'h0000FF;
                            // // end 
                            // else begin
                            //     // TRƯỜNG HỢP 3: CHẠY THẬT
                            //     RGBchannel_d = {fifo_data_in[15:11], 3'b000, fifo_data_in[10:5], 2'b00, fifo_data_in[4:0], 3'b000};
                            // end
                            // RGBchannel_d = {fifo_data_in[15:11], 3'b000, fifo_data_in[10:5], 2'b00, fifo_data_in[4:0], 3'b000};
                            // RGBchannel = {fifo_data_in[15:11],3'b000, fifo_data_in[10:5],2'b00, fifo_data_in[4:0],3'b000}; //convert RGB565 to RGB888
                            RGBchannel = {
                                fifo_data_in[15:11], fifo_data_in[15:13],
                                fifo_data_in[10:5],  fifo_data_in[10:9],
                                fifo_data_in[4:0],   fifo_data_in[4:2]
                            }; // convert RGB565 to RGB888 by bit replication
                        end
            // default: state_d=DELAY;
            IDLE: state_d=DELAY;
        endcase
        end

    // assign RGBchannel = RGBchannel_q;
    // assign fifo_read_en = fifo_read_en_q;

    //module instantiations
	vgaHDMI_core m0
	(
		.clock25(clock25), //clock must be 25MHz for 640x480
        .clock50(clock50),
		.resetn(resetn),  
		.hsync(hsync),
		.vsync(vsync),
		.dataEnable(dataEnable),
        .vgaClock(vgaClock),
		.pixel_x(pixel_x),
		.pixel_y(pixel_y)
	);



endmodule




module vgaHDMI_core(
    // **input**
    input clock25, clock50, resetn,

    // **output**
    output [9:0] pixel_x, pixel_y,
    output reg hsync, vsync,
    output reg dataEnable,
    output reg vgaClock
    );



    reg [9:0]pixelH, pixelV; // estado interno de pixeles del modulo

    initial begin
        hsync      = 1;
        vsync      = 1;
        pixelH     = 0;
        pixelV     = 0;
        dataEnable = 0;
        vgaClock   = 0;
    end
    
    // Manejo de Pixeles y Sincronizacion

    always @(posedge clock25 or negedge resetn) begin
    if(~resetn) begin
        hsync  <= 1;
        vsync  <= 1;
        pixelH <= 0;
        pixelV <= 0;
    end
    else begin
        // Display Horizontal
        if(pixelH==0 && pixelV!=524) begin
        pixelH<=pixelH+1'b1;
        pixelV<=pixelV+1'b1;
        end
        else if(pixelH==0 && pixelV==524) begin
        pixelH <= pixelH + 1'b1;
        pixelV <= 0; // pixel 525
        end
        else if(pixelH<=640) pixelH <= pixelH + 1'b1;
        // Front Porch
        else if(pixelH<=656) pixelH <= pixelH + 1'b1;
        // Sync Pulse
        else if(pixelH<=752) begin
        pixelH <= pixelH + 1'b1;
        hsync  <= 0;
        end
        // Back Porch
        else if(pixelH<799) begin
        pixelH <= pixelH+1'b1;
        hsync  <= 1;
        end
        else pixelH<=0; // pixel 800

        // Manejo Senal Vertical
        // Sync Pulse
        if(pixelV == 491 || pixelV == 492)
        vsync <= 0;
        else
        vsync <= 1;
    end
    end

    
    // dataEnable signal
    always @(posedge clock25 or negedge resetn) begin
    if(~resetn) dataEnable<= 0;

    else begin
        if(pixelH >= 0 && pixelH <640 && pixelV >= 0 && pixelV < 480)
        dataEnable <= 1;
        else
        dataEnable <= 0;
    end
    end

    // VGA pixeClock signal
    // Los clocks no deben manejar salidas directas, se debe usar un truco
    // initial vgaClock = 0;

    always @(posedge clock50 or negedge resetn) begin
    if(~resetn) vgaClock <= 0;
    else        vgaClock <= ~vgaClock;
    end


    assign pixel_x = pixelH;
    assign pixel_y = pixelV;


endmodule


module control_frame_buffer_write_only#(
    parameter ADDR_WIDTH = 32,
    parameter FIFO_DEPTH_WIDTH = 9,
    parameter THRESHOLD_START = 500, 
    parameter THRESHOLD_STOP  = 499 
)(
    input                               clk_i,
    input                               resetn_i,

    input       [15:0]                  resolution_width_i,
    input       [15:0]                  resolution_depth_i,
    input                               empty_i,
    input       [FIFO_DEPTH_WIDTH-1:0]  data_count_r_i,
    input                               n_edge_vsync_i, 
    output                              wr_o,
    output      [ADDR_WIDTH-1:0]        addr_wr_o,
    output                              page_written_once_o
);


    wire    [ADDR_WIDTH-1:0]    total_pixel;
    // assign  total_pixel = (resolution_width_i * resolution_depth_i) - 1;
    assign  total_pixel = 'd307199; 


    localparam STATE_IDLE  = 1'b0;
    localparam STATE_WRITE = 1'b1; 

    //================================================================
    // Registers
    //================================================================
    reg                       state_reg, state_next;
    reg     [ADDR_WIDTH-1:0]  count_pixel_wr_reg, count_pixel_wr_next;
    reg                       page_written_once_reg, page_written_once_next;

    reg     [ADDR_WIDTH-1:0]  addr_wr_o_reg, addr_wr_o_next;
    reg                       wr_o_reg, wr_o_next;

    //================================================================
    always @(posedge clk_i, negedge resetn_i) begin
        if (~resetn_i) begin
            state_reg             <= STATE_IDLE;
            count_pixel_wr_reg    <= {ADDR_WIDTH{1'b0}};
            page_written_once_reg <= 1'b0;
            addr_wr_o_reg         <= {ADDR_WIDTH{1'b0}};
            wr_o_reg              <= 1'b0;
        end
        else begin
            state_reg             <= state_next;
            count_pixel_wr_reg    <= count_pixel_wr_next;
            page_written_once_reg <= page_written_once_next;
            addr_wr_o_reg         <= addr_wr_o_next;
            wr_o_reg              <= wr_o_next;
        end
    end

    always @(*) begin
        state_next             = state_reg;
        count_pixel_wr_next    = count_pixel_wr_reg;
        page_written_once_next = page_written_once_reg;
        addr_wr_o_next         = addr_wr_o_reg;
        wr_o_next              = 1'b0;
        case (state_reg)
            STATE_IDLE: begin
                if (data_count_r_i >= THRESHOLD_START) begin
                    state_next = STATE_WRITE;
                end
            end
            STATE_WRITE: begin
                if (data_count_r_i <= THRESHOLD_STOP) begin
                    state_next = STATE_IDLE;
                end
                else if (~empty_i) begin
                    wr_o_next      = 1'b1;
                    addr_wr_o_next = count_pixel_wr_reg;
                    if ((count_pixel_wr_reg == total_pixel)) begin
                        count_pixel_wr_next = {ADDR_WIDTH{1'b0}};
                        page_written_once_next = 1'b1; 
                    end else begin
                        count_pixel_wr_next = count_pixel_wr_reg + 1;
                    end
                end
            end
            
            default: state_next = STATE_IDLE;
        endcase
        if (page_written_once_reg == 1'b1) begin
            page_written_once_next = 1'b1;
        end

    end
    assign addr_wr_o = addr_wr_o_reg;
    assign wr_o = wr_o_reg;
    assign page_written_once_o = page_written_once_reg;

endmodule


module control_frame_buffer_read_only#(
    parameter ADDR_WIDTH = 32,
    parameter READ_STROBE_PERIOD = 4,
    parameter FIFO_DEPTH_WIDTH = 9,
    parameter THRESHOLD_HIGH = 500,
    parameter THRESHOLD_LOW  = 499
)(
    input                               clk_i,
    input                               resetn_i,

    input       [15:0]                  resolution_width_i,
    input       [15:0]                  resolution_depth_i,
    input                               page_written_once_i,
    input       [FIFO_DEPTH_WIDTH-1:0]  data_count_w_i,
    input                               full_i,
    output                              rd_o,
    output      [ADDR_WIDTH-1:0]        addr_rd_o
);

    wire    [ADDR_WIDTH-1:0]    total_pixel;
    // assign  total_pixel = (resolution_width_i * resolution_depth_i) - 1;
    assign  total_pixel = 'd307199; 

    // localparam STROBE_CNT_WIDTH = (READ_STROBE_PERIOD < 2) ? 1 : $clog2(READ_STROBE_PERIOD);

    //================================================================
    // Registers
    //================================================================
    reg     [ADDR_WIDTH-1:0]  count_pixel_rd_reg, count_pixel_rd_next;
    reg                       read_enabled_reg, read_enabled_next;
    reg     [ADDR_WIDTH-1:0]  addr_rd_o_reg, addr_rd_o_next;
    reg                       rd_o_reg, rd_o_next;
    // reg     [STROBE_CNT_WIDTH-1:0] read_strobe_cnt_reg, read_strobe_cnt_next;
    reg                       fifo_pause_reg, fifo_pause_next;
    //================================================================
    always @(posedge clk_i, negedge resetn_i) begin
        if (~resetn_i) begin
            count_pixel_rd_reg  <= {ADDR_WIDTH{1'b0}};
            read_enabled_reg    <= 1'b0;
            addr_rd_o_reg       <= {ADDR_WIDTH{1'b0}};
            rd_o_reg            <= 1'b0;
            // read_strobe_cnt_reg <= {STROBE_CNT_WIDTH{1'b0}};
            fifo_pause_reg      <= 1'b0; 
        end
        else begin
            count_pixel_rd_reg  <= count_pixel_rd_next;
            read_enabled_reg    <= read_enabled_next;
            addr_rd_o_reg       <= addr_rd_o_next;
            rd_o_reg            <= rd_o_next;
            // read_strobe_cnt_reg <= read_strobe_cnt_next;
            fifo_pause_reg      <= fifo_pause_next;
        end
    end
    //================================================================
    always @(*) begin
        fifo_pause_next = fifo_pause_reg;
        if (data_count_w_i >= THRESHOLD_HIGH) begin
            fifo_pause_next = 1'b1;
        end 
        else if (data_count_w_i <= THRESHOLD_LOW) begin
            fifo_pause_next = 1'b0;
        end
    end

    wire can_read_base;
    assign can_read_base = (read_enabled_reg == 1'b1) && (fifo_pause_next == 1'b0) && (full_i == 1'b0);
    
    wire read_strobe_allow;

    // assign read_strobe_allow = (read_strobe_cnt_reg == 0);

    always @(*) begin
        count_pixel_rd_next  = count_pixel_rd_reg;
        // read_strobe_cnt_next = read_strobe_cnt_reg;
        addr_rd_o_next       = addr_rd_o_reg;
        rd_o_next            = 1'b0;
        read_enabled_next = read_enabled_reg | page_written_once_i;
        if (can_read_base) begin
            // if (READ_STROBE_PERIOD > 1) begin
            //     if (read_strobe_cnt_reg == READ_STROBE_PERIOD - 1)
            //         read_strobe_cnt_next = 0;
            //     else
            //         read_strobe_cnt_next = read_strobe_cnt_reg + 1;
            // end
            // if (read_strobe_allow) begin
            //     rd_o_next = 1'b1;
            //     addr_rd_o_next = count_pixel_rd_reg;
            //     if (count_pixel_rd_reg == total_pixel)
            //         count_pixel_rd_next = {ADDR_WIDTH{1'b0}};
            //     else
            //         count_pixel_rd_next = count_pixel_rd_reg + 1;
            // end
            rd_o_next = 1'b1;
            addr_rd_o_next = count_pixel_rd_reg;

            if (count_pixel_rd_reg == total_pixel)
                count_pixel_rd_next = {ADDR_WIDTH{1'b0}};
            else
                count_pixel_rd_next = count_pixel_rd_reg + 1;
        end
    end

    assign addr_rd_o = addr_rd_o_reg;
    assign rd_o = rd_o_reg;

endmodule



module asyn_fifo
	#(
		parameter DATA_WIDTH=16,
					 FIFO_DEPTH_WIDTH=11  //total depth will then be 2**FIFO_DEPTH_WIDTH
	)
	(
	input wire rst_n,
	input wire clk_write,clk_read, //clock input from both domains
	input wire write,read, 
	input wire [DATA_WIDTH-1:0] data_write, //input FROM write clock domain
	output wire [DATA_WIDTH-1:0] data_read, //output TO read clock domain
	output reg full,empty, //full=sync to write domain clk , empty=sync to read domain clk
	output reg[FIFO_DEPTH_WIDTH-1:0] data_count_w,data_count_r //counts number of data left in fifo memory(sync to either write or read clk)
    );
	 
	 
	 /*
	 async_fifo #(.DATA_WIDTH(16),.FIFO_DEPTH_WIDTH(10)) m2 //1024x16 FIFO mem
	(
		.rst_n(rst_n),
		.clk_write(),
		.clk_read(), //clock input from both domains
		.write(),
		.read(), 
		.data_write(), //input FROM write clock domain
		.data_read(), //output TO read clock domain
		.full(),
		.empty(), //full=sync to write domain clk , empty=sync to read domain clk
		..data_count_w(),
		.data_count_r() //counts number of data left in fifo memory(sync to either write or read clk)
    );
	 */
	 
	 
	 localparam FIFO_DEPTH=2**FIFO_DEPTH_WIDTH;
	 
	 initial begin
		full=0;
		empty=1;
	 end
	 
	 
	 ///////////////////WRITE CLOCK DOMAIN//////////////////////////////
	 reg[FIFO_DEPTH_WIDTH:0] w_ptr_q=0; //binary counter for write pointer
	 reg[FIFO_DEPTH_WIDTH:0] r_ptr_sync; //binary pointer for read pointer sync to write clk
	 wire[FIFO_DEPTH_WIDTH:0] w_grey,w_grey_nxt; //grey counter for write pointer
	 reg[FIFO_DEPTH_WIDTH:0] r_grey_sync; //grey counter for the read pointer synchronized to write clock
	 
	 wire we;
	 reg[3:0] i; //log_2(FIFO_DEPTH_WIDTH)
	 
	 assign w_grey=w_ptr_q^(w_ptr_q>>1); //binary to grey code conversion for current write pointer
	 assign w_grey_nxt=(w_ptr_q+1'b1)^((w_ptr_q+1'b1)>>1);  //next grey code
	 assign we= write && !full; 
	 
	 //register operation
	 always @(posedge clk_write,negedge rst_n) begin
		if(!rst_n) begin
			w_ptr_q<=0;
			full<=0;
		end
		else begin
			if(write && !full) begin //write condition
				w_ptr_q<=w_ptr_q+1'b1; 
				full <= w_grey_nxt == {~r_grey_sync[FIFO_DEPTH_WIDTH:FIFO_DEPTH_WIDTH-1],r_grey_sync[FIFO_DEPTH_WIDTH-2:0]}; //algorithm for full logic which can be observed on the grey code table
			end
			else full <= w_grey == {~r_grey_sync[FIFO_DEPTH_WIDTH:FIFO_DEPTH_WIDTH-1],r_grey_sync[FIFO_DEPTH_WIDTH-2:0]}; 
			
			for(i=0;i<=FIFO_DEPTH_WIDTH;i=i+1) r_ptr_sync[i]=^(r_grey_sync>>i); //grey code to binary converter 
			data_count_w <= (w_ptr_q>=r_ptr_sync)? (w_ptr_q-r_ptr_sync):(FIFO_DEPTH-r_ptr_sync+w_ptr_q); //compares write pointer and sync read pointer to generate data_count
		end							
	 end

	/////////////////////////////////////////////////////////////////////
	 
	 
	  ///////////////////READ CLOCK DOMAIN//////////////////////////////
	 reg[FIFO_DEPTH_WIDTH:0] r_ptr_q=0; //binary counter for read pointer
	 wire[FIFO_DEPTH_WIDTH:0] r_ptr_d;
	 reg[FIFO_DEPTH_WIDTH:0] w_ptr_sync; //binary counter for write pointer sync to read clk
	 reg[FIFO_DEPTH_WIDTH:0] w_grey_sync; //grey counter for the write pointer synchronized to read clock
	 wire[FIFO_DEPTH_WIDTH:0] r_grey,r_grey_nxt; //grey counter for read pointer 
	 
	 
	 assign r_grey= r_ptr_q^(r_ptr_q>>1);  //binary to grey code conversion
	 assign r_grey_nxt= (r_ptr_q+1'b1)^((r_ptr_q+1'b1)>>1); //next grey code
	 assign r_ptr_d= (read && !empty)? r_ptr_q+1'b1:r_ptr_q;
	 
	 //register operation
	 always @(posedge clk_read,negedge rst_n) begin
		if(!rst_n) begin
			r_ptr_q<=0;
			empty<=1;
		end
		else begin
			r_ptr_q<=r_ptr_d;
			if(read && !empty) empty <= r_grey_nxt==w_grey_sync;//empty condition
			else empty <= r_grey==w_grey_sync; 
			
			for(i=0;i<=FIFO_DEPTH_WIDTH;i=i+1) w_ptr_sync[i]=^(w_grey_sync>>i); //grey code to binary converter
			data_count_r = (w_ptr_q>=r_ptr_sync)? (w_ptr_q-r_ptr_sync):(FIFO_DEPTH-r_ptr_sync+w_ptr_q); //compares read pointer to sync write pointer to generate data_count
		end
	 end
	 ////////////////////////////////////////////////////////////////////////
	 
	 
	 /////////////////////CLOCK DOMAIN CROSSING//////////////////////////////
	 reg[FIFO_DEPTH_WIDTH:0] r_grey_sync_temp;
	 reg[FIFO_DEPTH_WIDTH:0] w_grey_sync_temp;
	 always @(posedge clk_write) begin //2 D-Flipflops for reduced metastability in clock domain crossing from READ DOMAIN to WRITE DOMAIN
		r_grey_sync_temp<=r_grey; 
		r_grey_sync<=r_grey_sync_temp;
	 end
	 always @(posedge clk_read) begin //2 D-Flipflops for reduced metastability in clock domain crossing from WRITE DOMAIN to READ DOMAIN
		w_grey_sync_temp<=w_grey;
		w_grey_sync<=w_grey_sync_temp;
	 end
	 
	//////////////////////////////////////////////////////////////////////////
	 
	 
	 
	//instantiation of dual port block ram
	dual_port_sync #(.ADDR_WIDTH(FIFO_DEPTH_WIDTH) , .DATA_WIDTH(DATA_WIDTH)) m0
	(
		.clk_r(clk_read),
		.clk_w(clk_write),
		.we(we),
		.din(data_write),
		.addr_a(w_ptr_q[FIFO_DEPTH_WIDTH-1:0]), //write address
		.addr_b(r_ptr_d[FIFO_DEPTH_WIDTH-1:0] ), //read address ,addr_b is already buffered inside this module so we will use the "_d" ptr to advance the data(not "_q")
		.dout(data_read)
	);

endmodule



	//inference template for dual port block ram
module dual_port_sync
	#(
		parameter ADDR_WIDTH=11, //2k by 8 dual port synchronous ram(16k block ram)
					 DATA_WIDTH=8
	)
	(
		input 	clk_r,
		input 	clk_w,
		input 	we, 
		input	[DATA_WIDTH-1:0] din,
		input	[ADDR_WIDTH-1:0] addr_a,addr_b, //addr_a for write, addr_b for read
		output reg[DATA_WIDTH-1:0] dout
		// output [DATA_WIDTH-1:0] dout
	);
	
	reg[DATA_WIDTH-1:0] ram[2**ADDR_WIDTH-1:0];
	reg[ADDR_WIDTH-1:0] addr_b_q;
	
	always @(posedge clk_w) begin
		if(we) ram[addr_a]<=din;
	end
	always @(posedge clk_r) begin
		addr_b_q<=addr_b;	
		dout<=ram[addr_b_q];
	end
	// assign dout=ram[addr_b_q];

	
endmodule





module frame_buffer#(
    parameter ADDR_WIDTH    = 32,
    parameter DATA_WIDTH    = 16,
    parameter NUMBER_BRAM   = 75,
    parameter DEPTH_SIZE    = 4096, // size bram = (DATA_WIDTH * DEPTH_SIZE)/8 (Byte)
    parameter MODE = 2,     // MOD 0 SINGLE PORT READ_WRITE
                            // MOD 1 DUAL PORT READ_WRITE // erro
                            // MOD 2 DUAL PORT READ / SINGLE PORT WRITE
    parameter ENB_TEST_PATTERN = 1
)(  

    input                               clk_i,
    input                               resetn_i,

    input                               wr0_i,
    input                               wr1_i,

    input           [ADDR_WIDTH-1:0]    addr_wr0, //address global
    input           [ADDR_WIDTH-1:0]    addr_wr1, //address global
    input           [ADDR_WIDTH-1:0]    addr_rd0, //address global
    input           [ADDR_WIDTH-1:0]    addr_rd1, //address global

    input           [DATA_WIDTH-1:0]    Data_in0,
    input           [DATA_WIDTH-1:0]    Data_in1,
    output          [DATA_WIDTH-1:0]    Data_out0,
    output          [DATA_WIDTH-1:0]    Data_out1

    );

    localparam integer LOCAL_ADDR_WIDTH = (DEPTH_SIZE <= 1) ? 1 : $clog2(DEPTH_SIZE);

    generate
        if (MODE == 0) begin
            wire            [NUMBER_BRAM-1:0]                    s_wr_in;
            wire            [NUMBER_BRAM*ADDR_WIDTH-1:0]         s_addr_wr;  // address local for each BRAM
            wire            [NUMBER_BRAM*ADDR_WIDTH-1:0]         s_addr_rd;  // address local for each BRAM
            wire            [NUMBER_BRAM*DATA_WIDTH-1:0]         s_Data_in;
            wire            [NUMBER_BRAM*DATA_WIDTH-1:0]         s_Data_out;
            wire            [NUMBER_BRAM-1:0]                    ID_bram_selected;

            

            decoder_frame_buffer#(
                .ADDR_WIDTH(ADDR_WIDTH),
                .DATA_WIDTH(DATA_WIDTH),
                .NUMBER_BRAM(NUMBER_BRAM),
                .DEPTH_SIZE(DEPTH_SIZE)
            )decoder_frame_buffer_uut(
                //input mem
                .wr_i(wr0_i),
                .addr_wr(addr_wr0),
                .addr_rd(addr_rd0),
                .Data_in(Data_in0),
            //decoder port for each bram
                .s_wr_in_o(s_wr_in), 
                .s_addr_wr_o(s_addr_wr),
                .s_addr_rd_o(s_addr_rd),
                .s_Data_in_o(s_Data_in),
                .ID_bram_selected_rd_o(ID_bram_selected)
            );

            // gen block ram
            genvar bram_count;
            // generate
                for (bram_count = 0; bram_count < NUMBER_BRAM; bram_count = bram_count + 1) begin : g_bram
                    wire [ADDR_WIDTH-1:0]  aw = s_addr_wr [((ADDR_WIDTH*bram_count)+ADDR_WIDTH-1) -: ADDR_WIDTH];
                    wire [ADDR_WIDTH-1:0]  ar = s_addr_rd [((ADDR_WIDTH*bram_count)+ADDR_WIDTH-1) -: ADDR_WIDTH];
                    wire [DATA_WIDTH-1:0]  din = s_Data_in [((DATA_WIDTH*bram_count)+DATA_WIDTH-1) -: DATA_WIDTH];
                    wire                   we  = s_wr_in[bram_count];
                    wire [LOCAL_ADDR_WIDTH-1:0] aw_local = aw[LOCAL_ADDR_WIDTH-1:0];
                    wire [LOCAL_ADDR_WIDTH-1:0] ar_local = ar[LOCAL_ADDR_WIDTH-1:0];

                    block_ram_frame_buffer0 #(
                        .ADDR_WIDTH (LOCAL_ADDR_WIDTH),
                        .DATA_WIDTH (DATA_WIDTH),
                        .DEPTH_SIZE (DEPTH_SIZE)
                    ) u_bram (
                        .clk_i    (clk_i),
                        .wr_i     (we),
                        .addr_wr  (aw_local),
                        .addr_rd  (ar_local),
                        .Data_in  (din),
                        .Data_out (s_Data_out[((DATA_WIDTH*bram_count)+DATA_WIDTH-1) -: DATA_WIDTH])
                    );
                end
            // endgenerate

            encoder_frame_buffer#(
                .DATA_WIDTH(DATA_WIDTH),
                .NUMBER_BRAM(NUMBER_BRAM)
            )encoder_frame_buffer_uut(
                .clk_i(clk_i),
                .resetn_i(resetn_i),
                .ID_bram_selected_rd_i(ID_bram_selected),
                .s_Data_out_i(s_Data_out),
                .Data_out(Data_out0)   
            );
            
        end

        // else if (MODE == 1) begin
        //     //port 0
        //     wire            [NUMBER_BRAM-1:0]                    s_wr0_in;
        //     wire            [NUMBER_BRAM*ADDR_WIDTH-1:0]         s_addr_wr0;  // address local for each BRAM
        //     wire            [NUMBER_BRAM*ADDR_WIDTH-1:0]         s_addr_rd0;  // address local for each BRAM
        //     wire            [NUMBER_BRAM*DATA_WIDTH-1:0]         s_Data_in0;
        //     wire            [NUMBER_BRAM*DATA_WIDTH-1:0]         s_Data_out0;
        //     wire            [NUMBER_BRAM-1:0]                    ID_bram_selected0;

        //     //port 1
        //     wire            [NUMBER_BRAM-1:0]                    s_wr1_in;
        //     wire            [NUMBER_BRAM*ADDR_WIDTH-1:0]         s_addr_wr1;  // address local for each BRAM
        //     wire            [NUMBER_BRAM*ADDR_WIDTH-1:0]         s_addr_rd1;  // address local for each BRAM
        //     wire            [NUMBER_BRAM*DATA_WIDTH-1:0]         s_Data_in1;
        //     wire            [NUMBER_BRAM*DATA_WIDTH-1:0]         s_Data_out1;
        //     wire            [NUMBER_BRAM-1:0]                    ID_bram_selected1;



        //     decoder_frame_buffer#(
        //         .ADDR_WIDTH(ADDR_WIDTH),
        //         .DATA_WIDTH(DATA_WIDTH),
        //         .NUMBER_BRAM(NUMBER_BRAM),
        //         .DEPTH_SIZE(DEPTH_SIZE)
        //     )decoder_frame_buffer0_uut(
        //         //input mem
        //         .wr_i(wr0_i),
        //         .addr_wr(addr_wr0),
        //         .addr_rd(addr_rd0),
        //         .Data_in(Data_in0),
        //     //decoder port for each bram
        //         .s_wr_in_o(s_wr0_in), 
        //         .s_addr_wr_o(s_addr_wr0),
        //         .s_addr_rd_o(s_addr_rd0),
        //         .s_Data_in_o(s_Data_in0),
        //         .ID_bram_selected_rd_o(ID_bram_selected0)
        //     );

        //     decoder_frame_buffer#(
        //         .ADDR_WIDTH(ADDR_WIDTH),
        //         .DATA_WIDTH(DATA_WIDTH),
        //         .NUMBER_BRAM(NUMBER_BRAM),
        //         .DEPTH_SIZE(DEPTH_SIZE)
        //     )decoder_frame_buffer1_uut(
        //         //input mem
        //         .wr_i(wr1_i),
        //         .addr_wr(addr_wr1),
        //         .addr_rd(addr_rd1),
        //         .Data_in(Data_in1),
        //     //decoder port for each bram
        //         .s_wr_in_o(s_wr1_in), 
        //         .s_addr_wr_o(s_addr_wr1),
        //         .s_addr_rd_o(s_addr_rd1),
        //         .s_Data_in_o(s_Data_in1),
        //         .ID_bram_selected_rd_o(ID_bram_selected1)   
        //     );

        //     // gen block ram
        //     genvar bram_count;
        //     // generate
        //         for (bram_count = 0; bram_count < NUMBER_BRAM; bram_count = bram_count + 1) begin : g_bram
        //             wire [ADDR_WIDTH-1:0]  aw0 = s_addr_wr0 [((ADDR_WIDTH*bram_count)+ADDR_WIDTH-1) -: ADDR_WIDTH];
        //             wire [ADDR_WIDTH-1:0]  ar0 = s_addr_rd0 [((ADDR_WIDTH*bram_count)+ADDR_WIDTH-1) -: ADDR_WIDTH];
        //             wire [DATA_WIDTH-1:0]  din0 = s_Data_in0 [((DATA_WIDTH*bram_count)+DATA_WIDTH-1) -: DATA_WIDTH];
        //             wire                   we0  = s_wr0_in[bram_count];

        //             wire [ADDR_WIDTH-1:0]  aw1 = s_addr_wr1 [((ADDR_WIDTH*bram_count)+ADDR_WIDTH-1) -: ADDR_WIDTH];
        //             wire [ADDR_WIDTH-1:0]  ar1 = s_addr_rd1 [((ADDR_WIDTH*bram_count)+ADDR_WIDTH-1) -: ADDR_WIDTH];
        //             wire [DATA_WIDTH-1:0]  din1 = s_Data_in1 [((DATA_WIDTH*bram_count)+DATA_WIDTH-1) -: DATA_WIDTH];
        //             wire                   we1  = s_wr1_in[bram_count];

        //             block_ram_frame_buffer1 #(
        //                 .ADDR_WIDTH (ADDR_WIDTH),   // có thể giảm xuống $clog2(DEPTH_SIZE) nếu muốn gọn địa chỉ local
        //                 .DATA_WIDTH (DATA_WIDTH),
        //                 .DEPTH_SIZE (DEPTH_SIZE)
        //             ) u_bram (
        //                 .clk_i    (clk_i),
        //                 .wr_i0     (we0),
        //                 .addr_wr0  (aw0   - (DEPTH_SIZE*bram_count)),
        //                 .addr_rd0  (ar0   - (DEPTH_SIZE*bram_count)),
        //                 .Data_in0  (din0),
        //                 .Data_out0 (s_Data_out0[((DATA_WIDTH*bram_count)+DATA_WIDTH-1) -: DATA_WIDTH]),

        //                 .wr_i1     (we1),
        //                 .addr_wr1  (aw1   - (DEPTH_SIZE*bram_count)),
        //                 .addr_rd1  (ar1   - (DEPTH_SIZE*bram_count)),
        //                 .Data_in1  (din1),
        //                 .Data_out1 (s_Data_out1[((DATA_WIDTH*bram_count)+DATA_WIDTH-1) -: DATA_WIDTH])
        //             );
        //         end
        //     // endgenerate

        //     encoder_frame_buffer#(
        //         .DATA_WIDTH(DATA_WIDTH),
        //         .NUMBER_BRAM(NUMBER_BRAM)
        //     )encoder_frame_buffer0_uut(
        //         .clk_i(clk_i),
        //         .resetn_i(resetn_i),
        //         .ID_bram_selected_rd_i(ID_bram_selected0),
        //         .s_Data_out_i(s_Data_out0),
        //         .Data_out(Data_out0)   
        //     );

        //     encoder_frame_buffer#(
        //         .DATA_WIDTH(DATA_WIDTH),
        //         .NUMBER_BRAM(NUMBER_BRAM)
        //     )encoder_frame_buffer1_uut(
        //         .clk_i(clk_i),
        //         .resetn_i(resetn_i),
        //         .ID_bram_selected_rd_i(ID_bram_selected1),
        //         .s_Data_out_i(s_Data_out1),
        //         .Data_out(Data_out1)   
        //     );


        // end


        else if (MODE == 2) begin
            //port 0
            wire            [NUMBER_BRAM-1:0]                    s_wr0_in;
            wire            [NUMBER_BRAM*ADDR_WIDTH-1:0]         s_addr_wr0;  // address local for each BRAM
            wire            [NUMBER_BRAM*ADDR_WIDTH-1:0]         s_addr_rd0;  // address local for each BRAM
            wire            [NUMBER_BRAM*DATA_WIDTH-1:0]         s_Data_in0;
            wire            [NUMBER_BRAM*DATA_WIDTH-1:0]         s_Data_out0;
            wire            [NUMBER_BRAM-1:0]                    ID_bram_selected0;

            //port 1
            wire            [NUMBER_BRAM*ADDR_WIDTH-1:0]         s_addr_rd1;  // address local for each BRAM
            wire            [NUMBER_BRAM*DATA_WIDTH-1:0]         s_Data_out1;
            wire            [NUMBER_BRAM-1:0]                    ID_bram_selected1;



            decoder_frame_buffer#(
                .ADDR_WIDTH(ADDR_WIDTH),
                .DATA_WIDTH(DATA_WIDTH),
                .NUMBER_BRAM(NUMBER_BRAM),
                .DEPTH_SIZE(DEPTH_SIZE)
            )decoder_frame_buffer0_uut(
                //input mem
                .wr_i(wr0_i),
                .addr_wr(addr_wr0),
                .addr_rd(addr_rd0),
                .Data_in(Data_in0),
            //decoder port for each bram
                .s_wr_in_o(s_wr0_in), 
                .s_addr_wr_o(s_addr_wr0),
                .s_addr_rd_o(s_addr_rd0),
                .s_Data_in_o(s_Data_in0),
                .ID_bram_selected_rd_o(ID_bram_selected0)
            );

            single_rd_ecoder_frame_buffer#(
                .ADDR_WIDTH(ADDR_WIDTH),
                .DATA_WIDTH(DATA_WIDTH),
                .NUMBER_BRAM(NUMBER_BRAM),
                .DEPTH_SIZE(DEPTH_SIZE)
            )decoder_frame_buffer1_uut(
                //input mem
                .addr_rd(addr_rd1),
            //decoder port for each bram
                .s_addr_rd_o(s_addr_rd1),
                .ID_bram_selected_rd_o(ID_bram_selected1)   
            );

            // gen block ram
            genvar bram_count;
            // generate
                for (bram_count = 0; bram_count < NUMBER_BRAM; bram_count = bram_count + 1) begin : g_bram
                    wire [ADDR_WIDTH-1:0]  aw0 = s_addr_wr0 [((ADDR_WIDTH*bram_count)+ADDR_WIDTH-1) -: ADDR_WIDTH];
                    wire [ADDR_WIDTH-1:0]  ar0 = s_addr_rd0 [((ADDR_WIDTH*bram_count)+ADDR_WIDTH-1) -: ADDR_WIDTH];
                    wire [DATA_WIDTH-1:0]  din0 = s_Data_in0 [((DATA_WIDTH*bram_count)+DATA_WIDTH-1) -: DATA_WIDTH];
                    wire                   we0  = s_wr0_in[bram_count];  
                    wire [ADDR_WIDTH-1:0]  ar1 = s_addr_rd1 [((ADDR_WIDTH*bram_count)+ADDR_WIDTH-1) -: ADDR_WIDTH];
                    wire [LOCAL_ADDR_WIDTH-1:0] aw0_local = aw0[LOCAL_ADDR_WIDTH-1:0];
                    wire [LOCAL_ADDR_WIDTH-1:0] ar0_local = ar0[LOCAL_ADDR_WIDTH-1:0];
                    wire [LOCAL_ADDR_WIDTH-1:0] ar1_local = ar1[LOCAL_ADDR_WIDTH-1:0];

                    block_ram_frame_buffer2 #(
                        .ADDR_WIDTH (LOCAL_ADDR_WIDTH),
                        .DATA_WIDTH (DATA_WIDTH),
                        .DEPTH_SIZE (DEPTH_SIZE),
                        .TEST_PATTERN_NUM (bram_count),
                        .ENB_TEST_PATTERN(ENB_TEST_PATTERN)
                    ) u_bram (
                        .clk_i    (clk_i),
                        .wr_i0     (we0),
                        .addr_wr0  (aw0_local),
                        .addr_rd0  (ar0_local),
                        .Data_in0  (din0),
                        .Data_out0 (s_Data_out0[((DATA_WIDTH*bram_count)+DATA_WIDTH-1) -: DATA_WIDTH]),
                        .addr_rd1  (ar1_local),
                        .Data_out1 (s_Data_out1[((DATA_WIDTH*bram_count)+DATA_WIDTH-1) -: DATA_WIDTH])
                    );
                end
            // endgenerate

            encoder_frame_buffer#(
                .DATA_WIDTH(DATA_WIDTH),
                .NUMBER_BRAM(NUMBER_BRAM)
            )encoder_frame_buffer0_uut(
                .clk_i(clk_i),
                .resetn_i(resetn_i),
                .ID_bram_selected_rd_i(ID_bram_selected0),
                .s_Data_out_i(s_Data_out0),
                .Data_out(Data_out0)   
            );

            encoder_frame_buffer#(
                .DATA_WIDTH(DATA_WIDTH),
                .NUMBER_BRAM(NUMBER_BRAM)
            )encoder_frame_buffer1_uut(
                .clk_i(clk_i),
                .resetn_i(resetn_i),
                .ID_bram_selected_rd_i(ID_bram_selected1),
                .s_Data_out_i(s_Data_out1),
                .Data_out(Data_out1)   
            );


        end
    endgenerate

    





endmodule


module decoder_frame_buffer#(
    parameter ADDR_WIDTH    = 32,
    parameter DATA_WIDTH    = 16, //WORD_SIZE
    parameter NUMBER_BRAM   = 16,
    parameter DEPTH_SIZE    = 262144 // size bram = (WORD_SIZE * DEPTH_SIZE)/8 (Byte) 


)(
    //input mem
    input                               wr_i,

    input           [ADDR_WIDTH-1:0]    addr_wr,
    input           [ADDR_WIDTH-1:0]    addr_rd,
    input           [DATA_WIDTH-1:0]    Data_in,


    //decoder port for each bram
    output          [NUMBER_BRAM-1:0]                             s_wr_in_o, 
    output          [NUMBER_BRAM*ADDR_WIDTH-1:0]                  s_addr_wr_o,
    output          [NUMBER_BRAM*ADDR_WIDTH-1:0]                  s_addr_rd_o,
    output          [NUMBER_BRAM*DATA_WIDTH-1:0]                  s_Data_in_o,
    output          [NUMBER_BRAM-1:0]                             ID_bram_selected_rd_o

);  

    wire [NUMBER_BRAM-1:0] ID_bram_selected_wr;
    wire [NUMBER_BRAM-1:0] ID_bram_selected_rd;
    

    genvar  bram_count;
    //decoder addr_wr   
    generate
        for (bram_count = 0; bram_count < NUMBER_BRAM; bram_count = bram_count + 1) begin
            assign ID_bram_selected_wr[bram_count] = ((addr_wr >= DEPTH_SIZE*bram_count) && (addr_wr < (DEPTH_SIZE*bram_count) + DEPTH_SIZE));
        end
    endgenerate

    //decoder addr_rd   
    generate
        for (bram_count = 0; bram_count < NUMBER_BRAM; bram_count = bram_count + 1) begin
            assign ID_bram_selected_rd[bram_count] = ((addr_rd >= DEPTH_SIZE*bram_count) && (addr_rd < (DEPTH_SIZE*bram_count) + DEPTH_SIZE));
        end
    endgenerate


    //connect awaddr_wr master to bram
    generate
        for (bram_count = 0; bram_count < NUMBER_BRAM; bram_count = bram_count + 1) begin
            assign s_addr_wr_o[((ADDR_WIDTH*bram_count)+ADDR_WIDTH-1) -: ADDR_WIDTH] = (ID_bram_selected_wr[bram_count]) ?  addr_wr : 0;
        end
    endgenerate

    generate
        for (bram_count = 0; bram_count < NUMBER_BRAM; bram_count = bram_count + 1) begin
            assign s_addr_rd_o[((ADDR_WIDTH*bram_count)+ADDR_WIDTH-1) -: ADDR_WIDTH] = (ID_bram_selected_rd[bram_count]) ?  addr_rd : 0;
        end
    endgenerate

    generate
        for (bram_count = 0; bram_count < NUMBER_BRAM; bram_count = bram_count + 1) begin
            assign s_wr_in_o[bram_count] = (ID_bram_selected_wr[bram_count]) ?  wr_i : 0;
        end
    endgenerate

    generate
        for (bram_count = 0; bram_count < NUMBER_BRAM; bram_count = bram_count + 1) begin
            assign s_Data_in_o[((DATA_WIDTH*bram_count)+DATA_WIDTH-1) -: DATA_WIDTH] = (ID_bram_selected_wr[bram_count]) ? Data_in : 0;
        end
    endgenerate



    assign ID_bram_selected_rd_o = ID_bram_selected_rd;


endmodule



// single port read
module single_rd_ecoder_frame_buffer#(
    parameter ADDR_WIDTH    = 32,
    parameter DATA_WIDTH    = 16, //WORD_SIZE
    parameter NUMBER_BRAM   = 16,
    parameter DEPTH_SIZE    = 1024 // size bram = (WORD_SIZE * DEPTH_SIZE)/8 (Byte) 


)(
    //input mem
    input           [ADDR_WIDTH-1:0]                              addr_rd,


    //decoder port for each bram
    output          [NUMBER_BRAM*ADDR_WIDTH-1:0]                  s_addr_rd_o,
    output          [NUMBER_BRAM-1:0]                             ID_bram_selected_rd_o

);  

    wire [NUMBER_BRAM-1:0] ID_bram_selected_rd;
    

    genvar  bram_count;

    //decoder addr_rd   
    generate
        for (bram_count = 0; bram_count < NUMBER_BRAM; bram_count = bram_count + 1) begin
            assign ID_bram_selected_rd[bram_count] = ((addr_rd >= DEPTH_SIZE*bram_count) && (addr_rd < (DEPTH_SIZE*bram_count) + DEPTH_SIZE));
        end
    endgenerate


    //connect awaddr_rd master to bram
    generate
        for (bram_count = 0; bram_count < NUMBER_BRAM; bram_count = bram_count + 1) begin
            assign s_addr_rd_o[((ADDR_WIDTH*bram_count)+ADDR_WIDTH-1) -: ADDR_WIDTH] = (ID_bram_selected_rd[bram_count]) ?  addr_rd : 0;
        end
    endgenerate

    assign ID_bram_selected_rd_o = ID_bram_selected_rd;


endmodule


// module encoder_frame_buffer#(
//     parameter DATA_WIDTH    = 16, //WORD_SIZE
//     parameter NUMBER_BRAM   = 3
// )(  
//     input                                       clk_i,
//     input                                       resetn_i,
//     input       [NUMBER_BRAM-1:0]               ID_bram_selected_rd_i,
//     input       [NUMBER_BRAM*DATA_WIDTH-1:0]    s_Data_out_i,
//     output  reg [DATA_WIDTH-1:0]                Data_out    

// );  

//     reg         [NUMBER_BRAM-1:0]  ID_bram_next, ID_bram_reg;

//     always @(posedge clk_i) begin
//         if (~resetn_i) begin
//             ID_bram_reg <= 0;
//         end
//         else begin
//             ID_bram_reg <= ID_bram_next;
//         end
        
//     end

//     integer i;
//     always @(*) begin
//         ID_bram_next = ID_bram_selected_rd_i;
//         Data_out  = {DATA_WIDTH{1'b0}};
//         for (i = 0; i < NUMBER_BRAM; i = i + 1) begin  
//             Data_out = Data_out | ({DATA_WIDTH{/* ID_bram_selected_rd_i */ID_bram_reg[i]}} & s_Data_out_i[((DATA_WIDTH*i) + DATA_WIDTH -1) -: DATA_WIDTH]);
//         end
//     end

// endmodule


module encoder_frame_buffer#(
    parameter DATA_WIDTH    = 16, //WORD_SIZE
    parameter NUMBER_BRAM   = 3
)(  
    input                                       clk_i,
    input                                       resetn_i,
    input       [NUMBER_BRAM-1:0]               ID_bram_selected_rd_i,
    input       [NUMBER_BRAM*DATA_WIDTH-1:0]    s_Data_out_i,
    output      [DATA_WIDTH-1:0]                Data_out    

);  

    reg         [NUMBER_BRAM-1:0]  ID_bram_next, ID_bram_reg;
    reg         [DATA_WIDTH-1:0]   Data_out_next, Data_out_reg;


    always @(posedge clk_i or negedge resetn_i) begin
        if (~resetn_i) begin
            ID_bram_reg <= 0;
            Data_out_reg <= 0;
        end
        else begin
            ID_bram_reg <= ID_bram_next;
            Data_out_reg <= Data_out_next;
        end
        
    end

    integer i;
    always @(*) begin
        ID_bram_next = ID_bram_selected_rd_i;
        Data_out_next  = {DATA_WIDTH{1'b0}};
        for (i = 0; i < NUMBER_BRAM; i = i + 1) begin  
            Data_out_next = Data_out_next | ({DATA_WIDTH{/* ID_bram_selected_rd_i */ID_bram_reg[i]}} & s_Data_out_i[((DATA_WIDTH*i) + DATA_WIDTH -1) -: DATA_WIDTH]);
        end
    end

    assign Data_out = Data_out_reg;

endmodule



module block_ram_frame_buffer0#(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter DEPTH_SIZE = 1024 // size bram = (WORD_SIZE * DEPTH_SIZE)/8 (Byte) 
)(
    input                               clk_i,

    input                               wr_i,

    input           [ADDR_WIDTH-1:0]    addr_wr,
    input           [ADDR_WIDTH-1:0]    addr_rd,

    input           [DATA_WIDTH-1:0]    Data_in,
    output  reg     [DATA_WIDTH-1:0]    Data_out

    );

    reg [DATA_WIDTH-1:0] mem [0:DEPTH_SIZE-1]; //524_288 byte

    always @(posedge clk_i) begin
        if(wr_i) begin
            mem[addr_wr] <= Data_in;
        end
        Data_out <= mem[addr_rd];
    end

endmodule


// module block_ram_frame_buffer1#(
//     parameter ADDR_WIDTH = 32,
//     parameter DATA_WIDTH = 32,
//     parameter DEPTH_SIZE = 1024 // size bram = (WORD_SIZE * DEPTH_SIZE)/8 (Byte) 
// )(
//     input                               clk_i,

//     input                               wr_i0,
//     input                               wr_i1,

//     input           [ADDR_WIDTH-1:0]    addr_wr0,
//     input           [ADDR_WIDTH-1:0]    addr_wr1,
//     input           [ADDR_WIDTH-1:0]    addr_rd0,
//     input           [ADDR_WIDTH-1:0]    addr_rd1,

//     input           [DATA_WIDTH-1:0]    Data_in0,
//     input           [DATA_WIDTH-1:0]    Data_in1,
//     output  reg     [DATA_WIDTH-1:0]    Data_out0,
//     output  reg     [DATA_WIDTH-1:0]    Data_out1

//     );

//     reg [DATA_WIDTH-1:0] mem [0:DEPTH_SIZE-1]; //524_288 byte


//     // port 0
//     always @(posedge clk_i) begin
//         if(wr_i0) begin
//             mem[addr_wr0] <= Data_in0;
//         end
//         Data_out0 <= mem[addr_rd0];
        
//     end


//     // port 1
//     always @(posedge clk_i) begin
//         if(wr_i1) begin
//             mem[addr_wr1] <= Data_in1;
//         end
//         Data_out1 <= mem[addr_rd1];
//     end

// endmodule


// module block_ram_frame_buffer2#(
//     parameter ADDR_WIDTH = 32,
//     parameter DATA_WIDTH = 32,
//     parameter DEPTH_SIZE = 1024, // size bram = (WORD_SIZE * DEPTH_SIZE)/8 (Byte) 
//     parameter TEST_PATTERN_NUM = 0,
//     parameter ENB_TEST_PATTERN = 1
// )(
//     input                               clk_i,

//     input                               wr_i0,

//     input           [ADDR_WIDTH-1:0]    addr_wr0,

//     input           [ADDR_WIDTH-1:0]    addr_rd0,
//     input           [ADDR_WIDTH-1:0]    addr_rd1,

//     input           [DATA_WIDTH-1:0]    Data_in0,

//     output  reg     [DATA_WIDTH-1:0]    Data_out0,
//     output  reg     [DATA_WIDTH-1:0]    Data_out1

//     );

//     reg [DATA_WIDTH-1:0] mem [0:DEPTH_SIZE-1]; //524_288 byte

//     generate
//         if (ENB_TEST_PATTERN == 1) begin
//             if (TEST_PATTERN_NUM <= 35) begin
//                 initial begin
//                     // $readmemh("black_mem.hex", mem); // For hexadecimal data
//                     // $readmemh("white_mem.hex", mem);
//                     // $readmemh("soft_purple.hex", mem);
//                     $readmemh("black_mem_white.hex", mem);
//                 end
//             end
//             else begin
//                 initial begin
//                     // $readmemh("white_mem.hex", mem); // For hexadecimal data
//                     $readmemh("black_mem_white.hex", mem);
//                 end
//             end
//         end
        
//     endgenerate
    


//     // port 0
//     always @(posedge clk_i) begin
//         if(wr_i0) begin
//             mem[addr_wr0] <= Data_in0;
//         end
//         Data_out0 <= mem[addr_rd0];
        
//     end


//     // port 1
//     always @(posedge clk_i) begin
//         Data_out1 <= mem[addr_rd1];
//     end

// endmodule


//// dang xailuznay
// module block_ram_frame_buffer2#(
//     parameter ADDR_WIDTH = 32,
//     parameter DATA_WIDTH = 32,
//     parameter DEPTH_SIZE = 1024,
//     parameter TEST_PATTERN_NUM = 0,
//     parameter ENB_TEST_PATTERN = 1
// )(
//     input                               clk_i,

//     input                               wr_i0,
//     input           [ADDR_WIDTH-1:0]    addr_wr0,

//     input           [ADDR_WIDTH-1:0]    addr_rd0, // Đọc cho HDMI
//     input           [ADDR_WIDTH-1:0]    addr_rd1, // Đọc cho CNN Accel

//     input           [DATA_WIDTH-1:0]    Data_in0,

//     output  reg     [DATA_WIDTH-1:0]    Data_out0,
//     output  reg     [DATA_WIDTH-1:0]    Data_out1
// );

//     // 1. Tách thủ công thành 2 vùng nhớ độc lập
//     // Mỗi vùng nhớ bây giờ chỉ cần 2 port vật lý (1 Read, 1 Write)
//     (* ram_style = "block" *) reg [DATA_WIDTH-1:0] mem_hdmi  [0:DEPTH_SIZE-1];
//     (* ram_style = "block" *) reg [DATA_WIDTH-1:0] mem_accel [0:DEPTH_SIZE-1];

//     // Tạo Init cho mảng nhớ (giữ nguyên logic test pattern của bạn)
//     generate
//         if (ENB_TEST_PATTERN == 1) begin
//             if (TEST_PATTERN_NUM <= 35) begin
//                 initial begin
//                     $readmemh("black_mem_white.hex", mem_hdmi);
//                     $readmemh("black_mem_white.hex", mem_accel);
//                 end
//             end else begin
//                 initial begin
//                     $readmemh("black_mem_white.hex", mem_hdmi);
//                     $readmemh("black_mem_white.hex", mem_accel);
//                 end
//             end
//         end
//     endgenerate

//     // =================================================================
//     // 2. PIPELINE ĐƯỜNG GHI CHO BRAM THỨ 2 (CHÌA KHÓA FIX TIMING)
//     // =================================================================
//     reg                   wr_i0_pipe;
//     reg [ADDR_WIDTH-1:0]  addr_wr0_pipe;
//     reg [DATA_WIDTH-1:0]  Data_in0_pipe;

//     always @(posedge clk_i) begin
//         // Trễ 1 clock cycle để cắt đường timing path quá dài
//         wr_i0_pipe    <= wr_i0;
//         addr_wr0_pipe <= addr_wr0;
//         Data_in0_pipe <= Data_in0;
//     end

//     // =================================================================
//     // 3. ĐIỀU KHIỂN GHI/ĐỌC ĐỘC LẬP
//     // =================================================================
    
//     // Khối 1: Phục vụ xuất hình ảnh ra HDMI (Ghi trực tiếp, không trễ)
//     always @(posedge clk_i) begin
//         if(wr_i0) begin
//             mem_hdmi[addr_wr0] <= Data_in0;
//         end
//         Data_out0 <= mem_hdmi[addr_rd0];
//     end

//     // Khối 2: Phục vụ AI Accelerator (Ghi trễ 1 clock, Đọc bình thường)
//     always @(posedge clk_i) begin
//         if(wr_i0_pipe) begin
//             mem_accel[addr_wr0_pipe] <= Data_in0_pipe;
//         end
//         Data_out1 <= mem_accel[addr_rd1];
//     end

// endmodule

module block_ram_frame_buffer2#(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter DEPTH_SIZE = 1024,
    parameter TEST_PATTERN_NUM = 0,
    parameter ENB_TEST_PATTERN = 1
)(
    input                               clk_i,

    input                               wr_i0,
    input           [ADDR_WIDTH-1:0]    addr_wr0,

    input           [ADDR_WIDTH-1:0]    addr_rd0, // Đọc cho HDMI
    input           [ADDR_WIDTH-1:0]    addr_rd1, // Đọc cho CNN Accel

    input           [DATA_WIDTH-1:0]    Data_in0,

    output  reg     [DATA_WIDTH-1:0]    Data_out0,
    output  reg     [DATA_WIDTH-1:0]    Data_out1
);

    // 1. Tách thủ công thành 2 vùng nhớ độc lập
    // Mỗi vùng nhớ bây giờ chỉ cần 2 port vật lý (1 Read, 1 Write).
    //
    // DEPTH_SIZE=65536 làm Vivado phải ghép nhiều RAMB36 theo chiều sâu.
    // cascade_height=0 tắt BRAM cascade để tránh DRC REQP-1962 trên ADDR15
    // khi các RAMB36 trong cùng chain không nhận cùng kiểu tín hiệu ADDR15.
    (* ram_style = "block", cascade_height = 0 *) reg [DATA_WIDTH-1:0] mem_hdmi  [0:DEPTH_SIZE-1];
    (* ram_style = "block", cascade_height = 0 *) reg [DATA_WIDTH-1:0] mem_accel [0:DEPTH_SIZE-1];

    // Tạo Init cho mảng nhớ (giữ nguyên logic test pattern của bạn)
    generate
        if (ENB_TEST_PATTERN == 1) begin
            if (TEST_PATTERN_NUM <= 35) begin
                initial begin
                    $readmemh("black_mem_white.hex", mem_hdmi);
                    $readmemh("black_mem_white.hex", mem_accel);
                end
            end else begin
                initial begin
                    $readmemh("black_mem_white.hex", mem_hdmi);
                    $readmemh("black_mem_white.hex", mem_accel);
                end
            end
        end
    endgenerate

    // =================================================================
    // 2. PIPELINE ĐƯỜNG GHI CHO BRAM THỨ 2 (DELAY 2 CHU KỲ CLOCK)
    // =================================================================
    
    // Tầng 1 (Trễ 1 clock)
    reg                   wr_i0_pipe1;
    reg [ADDR_WIDTH-1:0]  addr_wr0_pipe1;
    reg [DATA_WIDTH-1:0]  Data_in0_pipe1;

    // Tầng 2 (Trễ 2 clock)
    reg                   wr_i0_pipe2;
    reg [ADDR_WIDTH-1:0]  addr_wr0_pipe2;
    reg [DATA_WIDTH-1:0]  Data_in0_pipe2;

    always @(posedge clk_i) begin
        // Ghi vào tầng 1
        wr_i0_pipe1    <= wr_i0;
        addr_wr0_pipe1 <= addr_wr0;
        Data_in0_pipe1 <= Data_in0;

        // Ghi vào tầng 2 (Lấy dữ liệu từ tầng 1)
        wr_i0_pipe2    <= wr_i0_pipe1;
        addr_wr0_pipe2 <= addr_wr0_pipe1;
        Data_in0_pipe2 <= Data_in0_pipe1;
    end

    // =================================================================
    // 3. ĐIỀU KHIỂN GHI/ĐỌC ĐỘC LẬP
    // =================================================================
    
    // Khối 1: Phục vụ xuất hình ảnh ra HDMI (Ghi trực tiếp, không trễ)
    always @(posedge clk_i) begin
        if(wr_i0) begin
            mem_hdmi[addr_wr0] <= Data_in0;
        end
        Data_out0 <= mem_hdmi[addr_rd0];
    end

    // Khối 2: Phục vụ AI Accelerator (Sử dụng tín hiệu từ tầng trễ thứ 2)
    always @(posedge clk_i) begin
        if(wr_i0_pipe2) begin
            mem_accel[addr_wr0_pipe2] <= Data_in0_pipe2;
        end
        Data_out1 <= mem_accel[addr_rd1];
    end

endmodule

////////////////////////////RESIZE IMAGE//////////////////////////////////////

module resize_mover_data#(
    parameter                           ADDR_WIDTH = 24,
    parameter                           BURST_SELECT_WIDTH = 16,
    parameter                           DATA_WIDTH_BYTE = 1,
    parameter                           FB_READ_LATENCY = 2
)(
    // ============================================================
    // System
    // ============================================================
    input                               clk_i,
    input                               resetn_i,
    
    // ============================================================
    // Runtime resize / preprocessing config registers
    //
    // Đây là các thanh ghi CPU sẽ ghi qua AXI-Lite/top-level sau này.
    // Phải giữ ổn định trong suốt quá trình xử lý một frame.
    // Module này chỉ chuyển tiếp các cổng này xuống control/resize.
    // ============================================================
    input          [7:0]                out_size_reg,          // kich thuoc output vuong: out_size x out_size, toi da 255
    input   [ADDR_WIDTH-1:0]            out_pixels_reg,        // CPU tinh out_size * out_size, dung de chia 3 plane R/G/B
    input          [7:0]                scaled_h_reg,          // chieu cao anh that sau khi giu aspect ratio
    input          [7:0]                pad_top_reg,           // so dong padding phia tren; padding duoi suy ra tu out_size/scaled_h
    input         [31:0]                x_step_reg,            // buoc X dang Q16.16: floor((IN_W << 16) / out_size)
    input         [31:0]                y_step_reg,            // buoc Y dang Q16.16: floor((IN_H << 16) / scaled_h)
    input                               output_bgr_reg,        // 0: output plane RGB, 1: output plane BGR

    // ============================================================
    // Runtime preprocessing LUT write port.
    //
    // CPU tinh san ket qua chuan hoa/quantization cho moi gia tri
    // pixel 8-bit, roi ghi vao 3 LUT R/G/B truoc khi start frame:
    //
    //   LUT_R[p] = clamp_int8(round_shift(p * mult_r + offset_r, shift))
    //   LUT_G[p] = clamp_int8(round_shift(p * mult_g + offset_g, shift))
    //   LUT_B[p] = clamp_int8(round_shift(p * mult_b + offset_b, shift))
    //
    // Khi resize dang chay, giu preproc_lut_wr_en_i = 0 de tranh
    // vua doc vua ghi cung LUT trong mot chu ky.
    //
    // preproc_lut_channel_i:
    //   2'd0 -> LUT kenh R
    //   2'd1 -> LUT kenh G
    //   2'd2 -> LUT kenh B
    //   2'd3 -> khong dung, bo qua
    // ============================================================
    input                               preproc_lut_wr_en_i,   // xung 1 clock: ghi 1 entry LUT
    input          [1:0]                preproc_lut_channel_i, // chon LUT can ghi: R/G/B
    input          [7:0]                preproc_lut_addr_i,    // dia chi LUT = gia tri pixel goc 0..255
    input   signed [7:0]                preproc_lut_data_i,    // du lieu LUT = gia tri int8 sau preprocessing

    // ============================================================
    // Frame buffer read interface
    // latency = FB_READ_LATENCY clocks
    // ============================================================
    output  [ADDR_WIDTH-1:0]            fb_addr_o,
    input   [15:0]                      fb_pixel_data_i,

    // handshaking accel signal
    input                               ARVALID_i,
    output                              ARREADY_o,
    input   [ADDR_WIDTH-1:0]            ARADDR_i,
    input   [BURST_SELECT_WIDTH-1:0]    ARBURST_i,

    // --- AXIS Master Port (Read data out for Accel) ---
    output                              m_tvalid_o,
    input                               m_tready_i,
    output  [DATA_WIDTH_BYTE*8-1:0]     m_tdata_o,
    output  [DATA_WIDTH_BYTE-1:0]       m_tstrb_o,
    output  [DATA_WIDTH_BYTE-1:0]       m_tkeep_o,
    output                              m_tlast_o,
    output                              m_tid_o

    );


    wire                          R_tvalid_i;
    wire                          R_tready_o;
    wire  [DATA_WIDTH_BYTE*8-1:0] R_tdata_i;
    wire  [DATA_WIDTH_BYTE-1:0]   R_tstrb_i;
    wire  [DATA_WIDTH_BYTE-1:0]   R_tkeep_i;
    wire                          R_tlast_i;
    wire                          R_tid_i;

    wire                          G_tvalid_i;
    wire                          G_tready_o;
    wire  [DATA_WIDTH_BYTE*8-1:0] G_tdata_i;
    wire  [DATA_WIDTH_BYTE-1:0]   G_tstrb_i;
    wire  [DATA_WIDTH_BYTE-1:0]   G_tkeep_i;
    wire                          G_tlast_i;
    wire                          G_tid_i;

    wire                          B_tvalid_i;
    wire                          B_tready_o;
    wire  [DATA_WIDTH_BYTE*8-1:0] B_tdata_i;
    wire  [DATA_WIDTH_BYTE-1:0]   B_tstrb_i;
    wire  [DATA_WIDTH_BYTE-1:0]   B_tkeep_i;
    wire                          B_tlast_i;
    wire                          B_tid_i;


    wire    [2:0] select_data_channel_rgb_w;


    wire                          ff_wr_rgb_buf;
    wire                          ff_tlast_pixel;
    wire    [7:0]                 ff_r_pixel_data;
    wire    [7:0]                 ff_g_pixel_data;
    wire    [7:0]                 ff_b_pixel_data;

    wire    [ADDR_WIDTH-1:0]      rm_addr_base;
    wire                          rm_valid;
    wire                          rm_ready;


    control_data_resize_image #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .BURST_SELECT_WIDTH(BURST_SELECT_WIDTH)
    ) control_data_resize_image_uut (
        .clk_i(clk_i),
        .resetn_i(resetn_i),
        .ARVALID_i(ARVALID_i),
        .ARREADY_o(ARREADY_o),
        .ARADDR_i(ARADDR_i),
        .ARBURST_i(ARBURST_i),
        .out_pixels_reg(out_pixels_reg),
        .output_bgr_reg(output_bgr_reg),
        .select_data_channel_rgb_o(select_data_channel_rgb_w),
        .tvalid_data_channel_rgb_i(m_tvalid_o),
        .tready_data_channel_rgb_i(m_tready_i),
        .tlast_data_channel_rgb_i(m_tlast_o),
        .rm_addr_base_o(rm_addr_base),
        .rm_valid_o(rm_valid),
        .rm_ready_i(rm_ready)
    );


    resize_maxpooling #(
        .ADDR_WIDTH_BASE (ADDR_WIDTH),
        .FB_READ_LATENCY (FB_READ_LATENCY)
    ) resize_maxpooling_uut (
        .clk_i                    (clk_i),
        .resetn_i                 (resetn_i),

        .out_size_reg             (out_size_reg),
        .scaled_h_reg             (scaled_h_reg),
        .pad_top_reg              (pad_top_reg),
        .x_step_reg               (x_step_reg),
        .y_step_reg               (y_step_reg),
        .preproc_lut_wr_en_i      (preproc_lut_wr_en_i),
        .preproc_lut_channel_i    (preproc_lut_channel_i),
        .preproc_lut_addr_i       (preproc_lut_addr_i),
        .preproc_lut_data_i       (preproc_lut_data_i),

        .cal_addr_base_i          (rm_addr_base),
        .cal_valid_i              (rm_valid),
        .cal_ready_o              (rm_ready),

        .fb_addr_o                (fb_addr_o),
        .fb_pixel_data_i          (fb_pixel_data_i),

        .ff_wr_rgb_buf_o          (ff_wr_rgb_buf),
        .ff_tlast_pixel_o         (ff_tlast_pixel),
        .ff_r_pixel_data_o        (ff_r_pixel_data),
        .ff_g_pixel_data_o        (ff_g_pixel_data),
        .ff_b_pixel_data_o        (ff_b_pixel_data)
    );





    axi4_stream #(
        .DATA_WIDTH_BYTE  (DATA_WIDTH_BYTE), 
        .SELECT_INTERFACE (0),  // 0 master
        .SIZE_FIFO        (8)
    ) fifo_R_channel (
        .aclk_i           (clk_i), 
        .aresetn_i        (resetn_i), 
        
        // Output Ports
        .m_tvalid_o       (R_tvalid_i), 
        .m_tready_i       (R_tready_o), 
        .m_tdata_o        (R_tdata_i), 
        .m_tstrb_o        (R_tstrb_i), 
        .m_tkeep_o        (R_tkeep_i), 
        .m_tlast_o        (R_tlast_i), 
        .m_tid_o          (R_tid_i),
        
   
        .user_m_wr_data_i (ff_wr_rgb_buf), 
        .user_m_data_i    (ff_r_pixel_data), 
        .user_m_tstrb_i   (1'b0),
        .user_m_tkeep_i   (1'b0),
        .user_m_tlast_i   (ff_tlast_pixel),
        .user_m_tid_i     (1'b0),
        
        // Unused Ports
        .user_m_busy_o    (), 
        .s_tready_o       (), 
        .user_s_ready_o   (), 
        .user_s_data_o    ()
    );

    axi4_stream #(
        .DATA_WIDTH_BYTE  (DATA_WIDTH_BYTE), 
        .SELECT_INTERFACE (0),  // 0 master
        .SIZE_FIFO        (8)
    ) fifo_G_channel (
        .aclk_i           (clk_i), 
        .aresetn_i        (resetn_i), 
        
        // Output Ports
        .m_tvalid_o       (G_tvalid_i), 
        .m_tready_i       (G_tready_o), 
        .m_tdata_o        (G_tdata_i), 
        .m_tstrb_o        (G_tstrb_i), 
        .m_tkeep_o        (G_tkeep_i), 
        .m_tlast_o        (G_tlast_i), 
        .m_tid_o          (G_tid_i),
        
  
        .user_m_wr_data_i (ff_wr_rgb_buf), 
        .user_m_data_i    (ff_g_pixel_data), 
        .user_m_tstrb_i   (1'b0),
        .user_m_tkeep_i   (1'b0),
        .user_m_tlast_i   (ff_tlast_pixel),
        .user_m_tid_i     (1'b0),
        
        // Unused Ports
        .user_m_busy_o    (), 
        .s_tready_o       (), 
        .user_s_ready_o   (), 
        .user_s_data_o    ()
    );

    axi4_stream #(
        .DATA_WIDTH_BYTE  (DATA_WIDTH_BYTE), 
        .SELECT_INTERFACE (0),  // 0 master
        .SIZE_FIFO        (8)
    ) fifo_B_channel (
        .aclk_i           (clk_i), 
        .aresetn_i        (resetn_i), 
        
        // Output Ports
        .m_tvalid_o       (B_tvalid_i), 
        .m_tready_i       (B_tready_o), 
        .m_tdata_o        (B_tdata_i), 
        .m_tstrb_o        (B_tstrb_i), 
        .m_tkeep_o        (B_tkeep_i), 
        .m_tlast_o        (B_tlast_i), 
        .m_tid_o          (B_tid_i),
        

        .user_m_wr_data_i (ff_wr_rgb_buf), 
        .user_m_data_i    (ff_b_pixel_data), 
        .user_m_tstrb_i   (1'b0),
        .user_m_tkeep_i   (1'b0),
        .user_m_tlast_i   (ff_tlast_pixel),
        .user_m_tid_i     (1'b0),
        
        // Unused Ports
        .user_m_busy_o    (), 
        .s_tready_o       (), 
        .user_s_ready_o   (), 
        .user_s_data_o    ()
    );


    // wire [2:0] select_data_channel_rgb_w; 

    encoder_3to1_axis_interface #(
        .DATA_WIDTH_BYTE           (DATA_WIDTH_BYTE)
    ) encoder_3to1_uut (
        .select_data_channel_rgb_i (select_data_channel_rgb_w), // Nối từ control_data_resize_image_uut
        
        // Master interface port 0 (R Channel)
        .mR_tvalid_i               (R_tvalid_i),
        .mR_tready_o               (R_tready_o),
        .mR_tdata_i                (R_tdata_i),
        .mR_tstrb_i                (R_tstrb_i),
        .mR_tkeep_i                (R_tkeep_i),
        .mR_tlast_i                (R_tlast_i),
        .mR_tid_i                  (R_tid_i),

        // Master interface port 1 (G Channel)
        .mG_tvalid_i               (G_tvalid_i),
        .mG_tready_o               (G_tready_o),
        .mG_tdata_i                (G_tdata_i),
        .mG_tstrb_i                (G_tstrb_i),
        .mG_tkeep_i                (G_tkeep_i),
        .mG_tlast_i                (G_tlast_i),
        .mG_tid_i                  (G_tid_i),

        // Master interface port 2 (B Channel)
        .mB_tvalid_i               (B_tvalid_i),
        .mB_tready_o               (B_tready_o),
        .mB_tdata_i                (B_tdata_i),
        .mB_tstrb_i                (B_tstrb_i),
        .mB_tkeep_i                (B_tkeep_i),
        .mB_tlast_i                (B_tlast_i),
        .mB_tid_i                  (B_tid_i),

        // Master select interface port (Output for Accel)
        .s_tvalid1_o               (m_tvalid_o),
        .s_tready1_i               (m_tready_i),
        .s_tdata1_o                (m_tdata_o),
        .s_tstrb1_o                (m_tstrb_o),
        .s_tkeep1_o                (m_tkeep_o),
        .s_tlast1_o                (m_tlast_o),
        .s_tid_o                   (m_tid_o)
    );



endmodule

module encoder_3to1_axis_interface #(
    parameter DATA_WIDTH_BYTE = 1
)(  
    input  [2:0]                   select_data_channel_rgb_i, // onehot          
    
    //master interface port 0 (R Channel)
    input                          mR_tvalid_i,
    output                         mR_tready_o,
    input  [DATA_WIDTH_BYTE*8-1:0] mR_tdata_i,
    input  [DATA_WIDTH_BYTE-1:0]   mR_tstrb_i,
    input  [DATA_WIDTH_BYTE-1:0]   mR_tkeep_i,
    input                          mR_tlast_i,
    input                          mR_tid_i,

    //master interface port 1 (G Channel)
    input                          mG_tvalid_i,
    output                         mG_tready_o,
    input  [DATA_WIDTH_BYTE*8-1:0] mG_tdata_i,
    input  [DATA_WIDTH_BYTE-1:0]   mG_tstrb_i,
    input  [DATA_WIDTH_BYTE-1:0]   mG_tkeep_i,
    input                          mG_tlast_i,
    input                          mG_tid_i,

    //master interface port 2 (B Channel)
    input                          mB_tvalid_i,
    output                         mB_tready_o,
    input  [DATA_WIDTH_BYTE*8-1:0] mB_tdata_i,
    input  [DATA_WIDTH_BYTE-1:0]   mB_tstrb_i,
    input  [DATA_WIDTH_BYTE-1:0]   mB_tkeep_i,
    input                          mB_tlast_i,
    input                          mB_tid_i,

    //master select interface port (Output to downstream)
    output                         s_tvalid1_o,
    input                          s_tready1_i,
    output [DATA_WIDTH_BYTE*8-1:0] s_tdata1_o,
    output [DATA_WIDTH_BYTE-1:0]   s_tstrb1_o,
    output [DATA_WIDTH_BYTE-1:0]   s_tkeep1_o,
    output                         s_tlast1_o,
    output                         s_tid_o 
);

    // ============================================================
    // Logic MUX AXI-Stream
    // Quy ước select_data_channel_rgb_i (One-Hot):
    // Bit [2] : Chọn kênh R (Cao nhất)
    // Bit [1] : Chọn kênh G
    // Bit [0] : Chọn kênh B (Thấp nhất)
    // ============================================================

    // 1. Dồn kênh (Multiplexing) cho Data, Strb, Keep, và ID
    assign s_tdata1_o  = select_data_channel_rgb_i[2] ? mR_tdata_i :
                         select_data_channel_rgb_i[1] ? mG_tdata_i :
                         select_data_channel_rgb_i[0] ? mB_tdata_i : {(DATA_WIDTH_BYTE*8){1'b0}};

    assign s_tstrb1_o  = select_data_channel_rgb_i[2] ? mR_tstrb_i :
                         select_data_channel_rgb_i[1] ? mG_tstrb_i :
                         select_data_channel_rgb_i[0] ? mB_tstrb_i : {DATA_WIDTH_BYTE{1'b0}};

    assign s_tkeep1_o  = select_data_channel_rgb_i[2] ? mR_tkeep_i :
                         select_data_channel_rgb_i[1] ? mG_tkeep_i :
                         select_data_channel_rgb_i[0] ? mB_tkeep_i : {DATA_WIDTH_BYTE{1'b0}};

    assign s_tid_o     = select_data_channel_rgb_i[2] ? mR_tid_i :
                         select_data_channel_rgb_i[1] ? mG_tid_i :
                         select_data_channel_rgb_i[0] ? mB_tid_i : 1'b0;

    // 2. Dồn kênh cho tín hiệu Valid và Last 
    assign s_tvalid1_o = (select_data_channel_rgb_i[2] & mR_tvalid_i) |
                         (select_data_channel_rgb_i[1] & mG_tvalid_i) |
                         (select_data_channel_rgb_i[0] & mB_tvalid_i);

    assign s_tlast1_o  = (select_data_channel_rgb_i[2] & mR_tlast_i) |
                         (select_data_channel_rgb_i[1] & mG_tlast_i) |
                         (select_data_channel_rgb_i[0] & mB_tlast_i);

    // 3. Phân kênh (Demultiplexing) cho tín hiệu Ready
    assign mR_tready_o = select_data_channel_rgb_i[2] & s_tready1_i;
    assign mG_tready_o = select_data_channel_rgb_i[1] & s_tready1_i;
    assign mB_tready_o = select_data_channel_rgb_i[0] & s_tready1_i;

endmodule



module resize_maxpooling #(
    parameter ADDR_WIDTH_BASE = 24,

    // ============================================================
    // Input frame buffer size
    // ============================================================
    parameter IN_W      = 640,
    parameter IN_H      = 480,

    // Actual frame-buffer BRAM returns data 2 clocks after address.
    parameter FB_READ_LATENCY = 2
)(
    // ============================================================
    // System
    // ============================================================
    input                               clk_i,
    input                               resetn_i,

    // ============================================================
    // Runtime resize / preprocessing config.
    //
    // CPU tinh cac gia tri nay va ghi xuong truoc khi start frame.
    // Phai giu on dinh trong luc resize dang chay.
    //
    //   scaled_h = (out_size * IN_H) / IN_W
    //   pad_top  = (out_size - scaled_h) / 2
    //   x_step   = floor((IN_W << 16) / out_size)
    //   y_step   = floor((IN_H << 16) / scaled_h)
    //
    // out_size must fit the existing 8-bit output counters.
    // ============================================================
    input          [7:0]               out_size_reg,          // kich thuoc output vuong: out_size x out_size, toi da 255
    input          [7:0]               scaled_h_reg,          // chieu cao vung anh that trong output sau khi giu aspect ratio
    input          [7:0]               pad_top_reg,           // so dong padding phia tren; padding duoi suy ra tu out_size/scaled_h
    input         [31:0]               x_step_reg,            // buoc X dang Q16.16 cho resize mapping
    input         [31:0]               y_step_reg,            // buoc Y dang Q16.16 cho resize mapping

    // ============================================================
    // Runtime preprocessing LUT write port.
    //
    // CPU computes final int8 preprocessing values in software:
    //   lut_r[p] = clamp_int8(round_shift(p * mult_r + offset_r, shift))
    //   lut_g[p] = clamp_int8(round_shift(p * mult_g + offset_g, shift))
    //   lut_b[p] = clamp_int8(round_shift(p * mult_b + offset_b, shift))
    //
    // Then CPU writes all 256 entries for each channel before starting
    // a frame. During resize processing, keep preproc_lut_wr_en_i = 0.
    //
    // Channel coding:
    //   2'd0 -> R LUT
    //   2'd1 -> G LUT
    //   2'd2 -> B LUT
    //   2'd3 -> unused, ignored
    // ============================================================
    input                              preproc_lut_wr_en_i,   // 1 clock pulse writes one LUT entry
    input          [1:0]               preproc_lut_channel_i, // selects R/G/B LUT
    input          [7:0]               preproc_lut_addr_i,    // source pixel value 0..255
    input   signed [7:0]               preproc_lut_data_i,    // final quantized int8 output for that pixel value

    // ============================================================
    // DMA handshake
    // 1 handshake = process 1 output row.
    // cal_addr_base_i is used only to detect frame start when == 0.
    // ============================================================
    input   [ADDR_WIDTH_BASE-1:0]       cal_addr_base_i,
    input                               cal_valid_i,
    output                              cal_ready_o,

    // ============================================================
    // Frame buffer read interface
    // latency = FB_READ_LATENCY clocks
    // ============================================================
    output  [ADDR_WIDTH_BASE-1:0]       fb_addr_o,
    input   [15:0]                      fb_pixel_data_i,

    // ============================================================
    // FIFO output
    //
    // 3 output channels are valid at the same cycle:
    //
    //   ff_r_pixel_data_o -> FIFO R
    //   ff_g_pixel_data_o -> FIFO G
    //   ff_b_pixel_data_o -> FIFO B
    //
    // Use the same ff_wr_rgb_buf_o for all 3 FIFOs.
    //
    // ff_tlast_pixel_o is asserted with the final pixel of a row,
    // in the same cycle as the 3 quantized channel outputs.
    // ============================================================
    output                              ff_wr_rgb_buf_o,
    output                              ff_tlast_pixel_o,
    output  signed [7:0]                ff_r_pixel_data_o,
    output  signed [7:0]                ff_g_pixel_data_o,
    output  signed [7:0]                ff_b_pixel_data_o
);

    // ============================================================
    // Runtime-derived constants
    // ============================================================

    wire [7:0] out_last;
    wire [8:0] pad_top_ext;
    wire [8:0] pad_end_ext;

    assign out_last    = out_size_reg - 8'd1;
    assign pad_top_ext = {1'b0, pad_top_reg};
    assign pad_end_ext = {1'b0, pad_top_reg} + {1'b0, scaled_h_reg};

    // Internal resize math uses fixed Q16.16 accumulators.
    // This is not exposed as a module parameter because x_step_reg and
    // y_step_reg are defined as Q16.16 runtime registers.
    localparam FP = 16;

    localparam [9:0] IN_W_LAST      = IN_W - 1;              // 639
    localparam [8:0] IN_H_LAST      = IN_H - 1;              // 479

    // ============================================================
    // FSM states
    // ============================================================

    localparam S_IDLE        = 4'd0;
    localparam S_ROW_SETUP   = 4'd1;
    localparam S_ROW_Y_CALC  = 4'd2;
    localparam S_PIXEL_SETUP = 4'd3;
    localparam S_STREAM      = 4'd4;
    localparam S_Q_FEED      = 4'd5;
    localparam S_PAD_FEED    = 4'd6;
    localparam S_ROW_DRAIN   = 4'd7;
    localparam S_ROW_DONE    = 4'd8;

    reg [3:0] state_reg;
    reg [3:0] state_next;

    // ============================================================
    // Output registers
    // ============================================================

    reg [ADDR_WIDTH_BASE-1:0] fb_addr_comb;

    reg        ff_wr_rgb_buf_reg;
    reg        ff_wr_rgb_buf_next;

    reg        ff_tlast_pixel_reg;
    reg        ff_tlast_pixel_next;

    reg signed [7:0] ff_r_pixel_data_reg;
    reg signed [7:0] ff_r_pixel_data_next;

    reg signed [7:0] ff_g_pixel_data_reg;
    reg signed [7:0] ff_g_pixel_data_next;

    reg signed [7:0] ff_b_pixel_data_reg;
    reg signed [7:0] ff_b_pixel_data_next;

    assign fb_addr_o          = fb_addr_comb;
    assign ff_wr_rgb_buf_o    = ff_wr_rgb_buf_reg;
    assign ff_tlast_pixel_o   = ff_tlast_pixel_reg;
    assign ff_r_pixel_data_o  = ff_r_pixel_data_reg;
    assign ff_g_pixel_data_o  = ff_g_pixel_data_reg;
    assign ff_b_pixel_data_o  = ff_b_pixel_data_reg;

    // ============================================================
    // DMA handshake
    // ============================================================

    assign cal_ready_o = (state_reg == S_IDLE);

    wire fire;
    assign fire = cal_valid_i && cal_ready_o;

    // ============================================================
    // Row / pixel counters
    // ============================================================

    reg [7:0] row_y_reg;
    reg [7:0] row_y_next;

    reg [7:0] current_row_y_reg;
    reg [7:0] current_row_y_next;

    reg [7:0] out_x_reg;
    reg [7:0] out_x_next;

    wire row_padding;
    assign row_padding =
        ({1'b0, current_row_y_reg} < pad_top_ext) ||
        ({1'b0, current_row_y_reg} >= pad_end_ext);

    wire row_real_image;
    assign row_real_image =
        ({1'b0, current_row_y_reg} >= pad_top_ext) &&
        ({1'b0, current_row_y_reg} < pad_end_ext);

    // ============================================================
    // Q16.16 accumulators
    //
    // Timing optimization:
    //   x_acc += x_step_reg per output pixel
    //   y_acc += y_step_reg per real output row
    //
    // Avoid runtime multipliers in resize mapping.
    // ============================================================

    reg [31:0] x_acc_reg;
    reg [31:0] x_acc_next;

    reg [31:0] y_acc_reg;
    reg [31:0] y_acc_next;

    wire [31:0] x_acc_plus_step;
    wire [31:0] y_acc_plus_step;

    assign x_acc_plus_step = x_acc_reg + x_step_reg;
    assign y_acc_plus_step = y_acc_reg + y_step_reg;

    // ============================================================
    // Y mapping from accumulator
    // ============================================================

    wire [8:0] calc_src_y0;
    wire [8:0] calc_src_y1_raw;

    assign calc_src_y0     = y_acc_reg[FP+8:FP];
    assign calc_src_y1_raw = y_acc_plus_step[FP+8:FP];

    reg [8:0] row_src_y0_reg;
    reg [8:0] row_src_y0_next;

    reg [8:0] row_src_y1_reg;
    reg [8:0] row_src_y1_next;

    // y * 640 = y * 512 + y * 128
    wire [18:0] calc_y0_base;
    assign calc_y0_base = (calc_src_y0 << 9) + (calc_src_y0 << 7);

    reg [18:0] row_src_y0_base_reg;
    reg [18:0] row_src_y0_base_next;

    // ============================================================
    // X mapping from accumulator
    // ============================================================

    wire [9:0] calc_src_x0;
    wire [9:0] calc_src_x1_raw;

    assign calc_src_x0     = x_acc_reg[FP+9:FP];
    assign calc_src_x1_raw = x_acc_plus_step[FP+9:FP];

    reg [9:0] src_x0_reg;
    reg [9:0] src_x0_next;

    reg [9:0] src_x1_reg;
    reg [9:0] src_x1_next;

    // ============================================================
    // Issue side
    // ============================================================

    reg        issue_active_reg;
    reg        issue_active_next;

    reg [9:0] issue_x_reg;
    reg [9:0] issue_x_next;

    reg [8:0] issue_y_reg;
    reg [8:0] issue_y_next;

    reg [18:0] issue_row_base_reg;
    reg [18:0] issue_row_base_next;

    wire [18:0] issue_addr;
    wire        issue_last;

    assign issue_addr = issue_row_base_reg + issue_x_reg;

    assign issue_last =
        (issue_x_reg == src_x1_reg) &&
        (issue_y_reg == row_src_y1_reg);

    // ============================================================
    // Return side
    // frame buffer latency = FB_READ_LATENCY clocks
    // ============================================================

    reg rd_valid_reg;
    reg rd_valid_next;

    reg rd_last_reg;
    reg rd_last_next;

    reg rd_valid_d1_reg;
    reg rd_last_d1_reg;

    wire rd_return_valid;
    wire rd_return_last;

    assign rd_return_valid = (FB_READ_LATENCY == 2) ? rd_valid_d1_reg : rd_valid_reg;
    assign rd_return_last  = (FB_READ_LATENCY == 2) ? rd_last_d1_reg  : rd_last_reg;

    // ============================================================
    // RGB565 max pooling
    // ============================================================

    reg [4:0] max_r_reg;
    reg [4:0] max_r_next;

    reg [5:0] max_g_reg;
    reg [5:0] max_g_next;

    reg [4:0] max_b_reg;
    reg [4:0] max_b_next;

    wire [4:0] pix_r;
    wire [5:0] pix_g;
    wire [4:0] pix_b;

    assign pix_r = fb_pixel_data_i[15:11];
    assign pix_g = fb_pixel_data_i[10:5];
    assign pix_b = fb_pixel_data_i[4:0];

    wire [4:0] next_max_r;
    wire [5:0] next_max_g;
    wire [4:0] next_max_b;

    assign next_max_r = (pix_r > max_r_reg) ? pix_r : max_r_reg;
    assign next_max_g = (pix_g > max_g_reg) ? pix_g : max_g_reg;
    assign next_max_b = (pix_b > max_b_reg) ? pix_b : max_b_reg;

    // RGB565 result before quantization
    reg [15:0] pixel_result_reg;
    reg [15:0] pixel_result_next;

    // Expand RGB565 -> RGB888 channels
    wire [4:0] result_r5;
    wire [5:0] result_g6;
    wire [4:0] result_b5;

    wire [7:0] result_r8;
    wire [7:0] result_g8;
    wire [7:0] result_b8;

    assign result_r5 = pixel_result_reg[15:11];
    assign result_g6 = pixel_result_reg[10:5];
    assign result_b5 = pixel_result_reg[4:0];

    assign result_r8 = {result_r5, result_r5[4:2]};
    assign result_g8 = {result_g6, result_g6[5:4]};
    assign result_b8 = {result_b5, result_b5[4:2]};

    // ============================================================
    // Quantizer input control
    // One q_in_valid carries R/G/B simultaneously.
    // ============================================================

    // q_in_* are combinational request signals generated by the FSM.
    // They are registered into q_src_* before the LUT lookup.
    // This keeps state/FSM muxing out of the LUT read address path.
    reg        q_in_valid;
    reg [7:0]  q_in_r8;
    reg [7:0]  q_in_g8;
    reg [7:0]  q_in_b8;
    reg        q_in_last;

    reg        q_src_valid_reg;
    reg        q_src_valid_next;

    reg [7:0]  q_src_r8_reg;
    reg [7:0]  q_src_r8_next;

    reg [7:0]  q_src_g8_reg;
    reg [7:0]  q_src_g8_next;

    reg [7:0]  q_src_b8_reg;
    reg [7:0]  q_src_b8_next;

    reg        q_src_last_reg;
    reg        q_src_last_next;

    // ============================================================
    // Runtime preprocessing LUTs for R/G/B
    //
    // Hardware no longer contains preprocessing multipliers, offsets,
    // variable shifters, or clamp logic. CPU precomputes the final int8
    // output for every possible 8-bit source value and writes these LUTs.
    //
    // Read path:
    //   q_src_*_reg holds the RGB888 value.
    //   q_lut_*_reg captures preproc_lut_*[q_src_*_reg].
    //
    // Write path:
    //   preproc_lut_wr_en_i writes one entry on clk_i.
    //   Do not write LUTs while a frame is being processed, because a
    //   same-cycle read/write to the same LUT address is device-dependent.
    // ============================================================

    // Force these small 256x8 tables into distributed LUT RAM.
    // Without this attribute, Vivado may infer one RAMB18 half block per
    // channel, which reports as 1.5 BRAM tiles for only 768 bytes of data.
    (* ram_style = "distributed" *) reg signed [7:0] preproc_lut_r [0:255];
    (* ram_style = "distributed" *) reg signed [7:0] preproc_lut_g [0:255];
    (* ram_style = "distributed" *) reg signed [7:0] preproc_lut_b [0:255];

    reg        q_valid_reg;
    reg        q_valid_next;

    reg        q_last_reg;
    reg        q_last_next;

    reg signed [7:0] q_lut_r_reg;
    reg signed [7:0] q_lut_r_next;

    reg signed [7:0] q_lut_g_reg;
    reg signed [7:0] q_lut_g_next;

    reg signed [7:0] q_lut_b_reg;
    reg signed [7:0] q_lut_b_next;

    wire signed [7:0] q_lut_r_d;
    wire signed [7:0] q_lut_g_d;
    wire signed [7:0] q_lut_b_d;

    assign q_lut_r_d = preproc_lut_r[q_src_r8_reg];
    assign q_lut_g_d = preproc_lut_g[q_src_g8_reg];
    assign q_lut_b_d = preproc_lut_b[q_src_b8_reg];

    wire q_out_valid;
    wire q_out_last;

    assign q_out_valid = q_valid_reg;
    assign q_out_last  = q_last_reg;

    // ============================================================
    // Sequential block
    // ============================================================

    always @(posedge clk_i) begin
        // CPU/Lite-side LUT programming port.
        // The image-processing state is reset independently from this RAM:
        // reset does not clear LUT content. Firmware should load all entries
        // after reset and before issuing the first resize/read request.
        if (preproc_lut_wr_en_i) begin
            case (preproc_lut_channel_i)
                2'd0: preproc_lut_r[preproc_lut_addr_i] <= preproc_lut_data_i;
                2'd1: preproc_lut_g[preproc_lut_addr_i] <= preproc_lut_data_i;
                2'd2: preproc_lut_b[preproc_lut_addr_i] <= preproc_lut_data_i;
                default: begin
                end
            endcase
        end

        if (!resetn_i) begin
            state_reg <= S_IDLE;

            ff_wr_rgb_buf_reg   <= 1'b0;
            ff_tlast_pixel_reg  <= 1'b0;
            ff_r_pixel_data_reg <= 8'sd0;
            ff_g_pixel_data_reg <= 8'sd0;
            ff_b_pixel_data_reg <= 8'sd0;

            row_y_reg           <= 8'd0;
            current_row_y_reg   <= 8'd0;
            out_x_reg           <= 8'd0;

            x_acc_reg           <= 32'd0;
            y_acc_reg           <= 32'd0;

            row_src_y0_reg      <= 9'd0;
            row_src_y1_reg      <= 9'd0;
            row_src_y0_base_reg <= 19'd0;

            src_x0_reg          <= 10'd0;
            src_x1_reg          <= 10'd0;

            issue_active_reg    <= 1'b0;
            issue_x_reg         <= 10'd0;
            issue_y_reg         <= 9'd0;
            issue_row_base_reg  <= 19'd0;

            rd_valid_reg        <= 1'b0;
            rd_last_reg         <= 1'b0;
            rd_valid_d1_reg     <= 1'b0;
            rd_last_d1_reg      <= 1'b0;

            max_r_reg           <= 5'd0;
            max_g_reg           <= 6'd0;
            max_b_reg           <= 5'd0;

            pixel_result_reg    <= 16'd0;

            q_valid_reg         <= 1'b0;
            q_last_reg          <= 1'b0;

            q_src_valid_reg     <= 1'b0;
            q_src_r8_reg        <= 8'd0;
            q_src_g8_reg        <= 8'd0;
            q_src_b8_reg        <= 8'd0;
            q_src_last_reg      <= 1'b0;

            q_lut_r_reg         <= 8'sd0;
            q_lut_g_reg         <= 8'sd0;
            q_lut_b_reg         <= 8'sd0;
        end else begin
            state_reg <= state_next;

            ff_wr_rgb_buf_reg   <= ff_wr_rgb_buf_next;
            ff_tlast_pixel_reg  <= ff_tlast_pixel_next;
            ff_r_pixel_data_reg <= ff_r_pixel_data_next;
            ff_g_pixel_data_reg <= ff_g_pixel_data_next;
            ff_b_pixel_data_reg <= ff_b_pixel_data_next;

            row_y_reg           <= row_y_next;
            current_row_y_reg   <= current_row_y_next;
            out_x_reg           <= out_x_next;

            x_acc_reg           <= x_acc_next;
            y_acc_reg           <= y_acc_next;

            row_src_y0_reg      <= row_src_y0_next;
            row_src_y1_reg      <= row_src_y1_next;
            row_src_y0_base_reg <= row_src_y0_base_next;

            src_x0_reg          <= src_x0_next;
            src_x1_reg          <= src_x1_next;

            issue_active_reg    <= issue_active_next;
            issue_x_reg         <= issue_x_next;
            issue_y_reg         <= issue_y_next;
            issue_row_base_reg  <= issue_row_base_next;

            rd_valid_reg        <= rd_valid_next;
            rd_last_reg         <= rd_last_next;
            rd_valid_d1_reg     <= rd_valid_reg;
            rd_last_d1_reg      <= rd_last_reg;

            max_r_reg           <= max_r_next;
            max_g_reg           <= max_g_next;
            max_b_reg           <= max_b_next;

            pixel_result_reg    <= pixel_result_next;

            q_valid_reg         <= q_valid_next;
            q_last_reg          <= q_last_next;

            q_src_valid_reg     <= q_src_valid_next;
            q_src_r8_reg        <= q_src_r8_next;
            q_src_g8_reg        <= q_src_g8_next;
            q_src_b8_reg        <= q_src_b8_next;
            q_src_last_reg      <= q_src_last_next;

            q_lut_r_reg         <= q_lut_r_next;
            q_lut_g_reg         <= q_lut_g_next;
            q_lut_b_reg         <= q_lut_b_next;
        end
    end

    // ============================================================
    // Combinational block
    // ============================================================

    always @(*) begin
        // ------------------------------------------------------------
        // Default hold
        // ------------------------------------------------------------
        state_next = state_reg;

        fb_addr_comb = {ADDR_WIDTH_BASE{1'b0}};

        // FIFO output is registered pulse
        ff_wr_rgb_buf_next   = 1'b0;
        ff_tlast_pixel_next  = 1'b0;
        ff_r_pixel_data_next = ff_r_pixel_data_reg;
        ff_g_pixel_data_next = ff_g_pixel_data_reg;
        ff_b_pixel_data_next = ff_b_pixel_data_reg;

        row_y_next           = row_y_reg;
        current_row_y_next   = current_row_y_reg;
        out_x_next           = out_x_reg;

        x_acc_next           = x_acc_reg;
        y_acc_next           = y_acc_reg;

        row_src_y0_next      = row_src_y0_reg;
        row_src_y1_next      = row_src_y1_reg;
        row_src_y0_base_next = row_src_y0_base_reg;

        src_x0_next          = src_x0_reg;
        src_x1_next          = src_x1_reg;

        issue_active_next    = issue_active_reg;
        issue_x_next         = issue_x_reg;
        issue_y_next         = issue_y_reg;
        issue_row_base_next  = issue_row_base_reg;

        rd_valid_next        = rd_valid_reg;
        rd_last_next         = rd_last_reg;

        max_r_next           = max_r_reg;
        max_g_next           = max_g_reg;
        max_b_next           = max_b_reg;

        pixel_result_next    = pixel_result_reg;

        q_valid_next         = q_valid_reg;
        q_last_next          = q_last_reg;
        q_lut_r_next         = q_lut_r_reg;
        q_lut_g_next         = q_lut_g_reg;
        q_lut_b_next         = q_lut_b_reg;

        // Quantizer input default
        q_in_valid = 1'b0;
        q_in_r8    = 8'd0;
        q_in_g8    = 8'd0;
        q_in_b8    = 8'd0;
        q_in_last  = 1'b0;

        // Quantizer output to 3 FIFOs.
        // All 3 channels valid together.
        if (q_out_valid) begin
            ff_wr_rgb_buf_next   = 1'b1;
            ff_tlast_pixel_next  = q_out_last;
            ff_r_pixel_data_next = q_lut_r_reg;
            ff_g_pixel_data_next = q_lut_g_reg;
            ff_b_pixel_data_next = q_lut_b_reg;
        end

        case (state_reg)

            // ========================================================
            // Wait for DMA request for one output row
            // ========================================================
            S_IDLE: begin
                issue_active_next = 1'b0;
                rd_valid_next     = 1'b0;
                rd_last_next      = 1'b0;

                if (fire) begin
                    out_x_next = 8'd0;
                    x_acc_next = 32'd0;

                    if (cal_addr_base_i == {ADDR_WIDTH_BASE{1'b0}}) begin
                        current_row_y_next = 8'd0;
                        row_y_next         = 8'd0;
                        y_acc_next         = 32'd0;
                    end else begin
                        current_row_y_next = row_y_reg;
                    end

                    state_next = S_ROW_SETUP;
                end
            end

            // ========================================================
            // Check padding row
            // ========================================================
            S_ROW_SETUP: begin
                if (row_padding) begin
                    // Padding RGB565 = black
                    pixel_result_next = 16'h0000;
                    state_next        = S_PAD_FEED;
                end else begin
                    state_next = S_ROW_Y_CALC;
                end
            end

            // ========================================================
            // Compute source Y window using y_acc
            // ========================================================
            S_ROW_Y_CALC: begin
                row_src_y0_next      = calc_src_y0;
                row_src_y0_base_next = calc_y0_base;

                if ({1'b0, current_row_y_reg} == (pad_end_ext - 9'd1)) begin
                    row_src_y1_next = IN_H_LAST;
                end else if (calc_src_y1_raw == 9'd0) begin
                    row_src_y1_next = 9'd0;
                end else begin
                    row_src_y1_next = calc_src_y1_raw - 9'd1;
                end

                state_next = S_PIXEL_SETUP;
            end

            // ========================================================
            // Compute source X window using x_acc
            // ========================================================
            S_PIXEL_SETUP: begin
                src_x0_next = calc_src_x0;

                if (out_x_reg == out_last) begin
                    src_x1_next = IN_W_LAST;
                end else if (calc_src_x1_raw == 10'd0) begin
                    src_x1_next = 10'd0;
                end else begin
                    src_x1_next = calc_src_x1_raw - 10'd1;
                end

                // Prepare x accumulator for next output pixel
                x_acc_next = x_acc_plus_step;

                // Setup issue side
                issue_x_next        = calc_src_x0;
                issue_y_next        = row_src_y0_reg;
                issue_row_base_next = row_src_y0_base_reg;
                issue_active_next   = 1'b1;

                // Clear return side
                rd_valid_next = 1'b0;
                rd_last_next  = 1'b0;

                // Clear max accumulator
                max_r_next = 5'd0;
                max_g_next = 6'd0;
                max_b_next = 5'd0;

                state_next = S_STREAM;
            end

            // ========================================================
            // Stream input window from frame buffer
            // ========================================================
            S_STREAM: begin
                // Return side
                if (rd_return_valid) begin
                    max_r_next = next_max_r;
                    max_g_next = next_max_g;
                    max_b_next = next_max_b;

                    if (rd_return_last) begin
                        pixel_result_next = {next_max_r, next_max_g, next_max_b};
                        state_next        = S_Q_FEED;
                    end
                end

                // Issue side
                if (issue_active_reg) begin
                    fb_addr_comb = {{(ADDR_WIDTH_BASE-19){1'b0}}, issue_addr};

                    rd_valid_next = 1'b1;
                    rd_last_next  = issue_last;

                    if (issue_last) begin
                        issue_active_next = 1'b0;
                    end else begin
                        if (issue_x_reg < src_x1_reg) begin
                            issue_x_next = issue_x_reg + 10'd1;
                        end else begin
                            issue_x_next        = src_x0_reg;
                            issue_y_next        = issue_y_reg + 9'd1;
                            issue_row_base_next = issue_row_base_reg + IN_W;
                        end
                    end
                end else begin
                    rd_valid_next = 1'b0;
                    rd_last_next  = 1'b0;
                end
            end

            // ========================================================
            // Feed real-image pixel result to parallel quantizer
            // ========================================================
            S_Q_FEED: begin
                q_in_valid = 1'b1;
                q_in_r8    = result_r8;
                q_in_g8    = result_g8;
                q_in_b8    = result_b8;
                q_in_last  = (out_x_reg == out_last);

                if (out_x_reg == out_last) begin
                    state_next = S_ROW_DRAIN;
                end else begin
                    out_x_next = out_x_reg + 8'd1;
                    state_next = S_PIXEL_SETUP;
                end
            end

            // ========================================================
            // Padding row: feed black pixels directly to quantizer
            // This can feed 1 pixel per clock.
            // ========================================================
            S_PAD_FEED: begin
                q_in_valid = 1'b1;
                q_in_r8    = 8'd0;
                q_in_g8    = 8'd0;
                q_in_b8    = 8'd0;
                q_in_last  = (out_x_reg == out_last);

                if (out_x_reg == out_last) begin
                    state_next = S_ROW_DRAIN;
                end else begin
                    out_x_next = out_x_reg + 8'd1;
                    state_next = S_PAD_FEED;
                end
            end

            // ========================================================
            // Wait until the final quantized pixel of this row
            // leaves the pipeline.
            // ========================================================
            S_ROW_DRAIN: begin
                if (q_out_valid && q_out_last) begin
                    state_next = S_ROW_DONE;
                end
            end

            // ========================================================
            // End of one output row
            // ========================================================
            S_ROW_DONE: begin
                if (current_row_y_reg == out_last) begin
                    row_y_next = 8'd0;
                    y_acc_next = 32'd0;
                end else begin
                    row_y_next = current_row_y_reg + 8'd1;

                    // Only real image rows advance the Y accumulator.
                    if (row_real_image)
                        y_acc_next = y_acc_plus_step;
                end

                state_next = S_IDLE;
            end

            default: begin
                state_next = S_IDLE;
            end

        endcase

        // ============================================================
        // LUT preprocessing pipeline update
        // ============================================================
        //
        // q_in_valid/q_in_r8/q_in_g8/q_in_b8/q_in_last are selected
        // inside the FSM case above.
        //
        // Therefore q_src_* and q_valid/q_last must be calculated AFTER
        // the case statement. Otherwise they only see default q_in_* = 0.
        //
        // Pipeline latency:
        //   cycle N   : FSM asserts q_in_* for one pixel.
        //   cycle N+1 : q_src_* holds RGB888 and LUT read is captured.
        //   cycle N+2 : q_out_valid uses q_lut_*_reg to write FIFOs.
        // ============================================================

        q_src_valid_next = q_in_valid;
        q_src_r8_next    = q_in_r8;
        q_src_g8_next    = q_in_g8;
        q_src_b8_next    = q_in_b8;
        q_src_last_next  = q_in_last;

        q_valid_next = q_src_valid_reg;
        q_last_next  = q_src_last_reg;

        q_lut_r_next = q_lut_r_d;
        q_lut_g_next = q_lut_g_d;
        q_lut_b_next = q_lut_b_d;
    end

endmodule

module control_data_resize_image#(
    parameter                           ADDR_WIDTH = 24,
    parameter                           BURST_SELECT_WIDTH = 16
)(
    //system signal
    input                               clk_i,
    input                               resetn_i,
    
    // handshaking accel signal
    input                               ARVALID_i,
    output                              ARREADY_o,
    input   [ADDR_WIDTH-1:0]            ARADDR_i,
    input   [BURST_SELECT_WIDTH-1:0]    ARBURST_i,

    //runtime config registers
    // CPU ghi out_pixels_reg = out_size * out_size.
    // Khoang dia chi doc duoc chia thanh 3 plane:
    //   [0, out_pixels)              : plane 0
    //   [out_pixels, 2*out_pixels)   : plane 1
    //   [2*out_pixels, 3*out_pixels) : plane 2
    input   [ADDR_WIDTH-1:0]            out_pixels_reg,

    // 0: plane output theo thu tu R, G, B
    // 1: plane output theo thu tu B, G, R
    input                               output_bgr_reg,

    //mux channel signal
    output  [2:0]                       select_data_channel_rgb_o, // {r,g,b}
    input                               tvalid_data_channel_rgb_i,
    input                               tready_data_channel_rgb_i,
    input                               tlast_data_channel_rgb_i,

    //handshaking resize signal 
    output  [ADDR_WIDTH-1:0]            rm_addr_base_o,
    output                              rm_valid_o,
    input                               rm_ready_i
    );


    localparam [3:0]    IDLE        = 'd0,
                        RED_SETUP0  = 'd1,
                        RED_SETUP1  = 'd2,
                        GREEN_SETUP = 'd3,
                        BLUE_SETUP  = 'd4;

    localparam [2:0] CHANNEL_R = 3'b100;
    localparam [2:0] CHANNEL_G = 3'b010;
    localparam [2:0] CHANNEL_B = 3'b001;

    wire [2:0] plane0_channel;
    wire [2:0] plane1_channel;
    wire [2:0] plane2_channel;
    wire [ADDR_WIDTH-1:0] out_pixels_x2;

    assign plane0_channel = output_bgr_reg ? CHANNEL_B : CHANNEL_R;
    assign plane1_channel = CHANNEL_G;
    assign plane2_channel = output_bgr_reg ? CHANNEL_R : CHANNEL_B;
    assign out_pixels_x2  = out_pixels_reg + out_pixels_reg;


    reg [3:0]               state_next, state_reg;

    //
    reg                     arready_next, arready_reg;
    reg [2:0]               select_data_channel_rgb_next, select_data_channel_rgb_reg;
    //
    reg [ADDR_WIDTH-1:0]    rm_addr_base_next, rm_addr_base_reg;
    reg                     rm_valid_next, rm_valid_reg;

    always @(posedge clk_i) begin
        if (~resetn_i) begin
            state_reg <= IDLE;
            arready_reg <= 0;
            select_data_channel_rgb_reg <= 0; 
            rm_addr_base_reg <= 0;
            rm_valid_reg <= 0;
        end
        else begin
            state_reg <= state_next;
            arready_reg <= arready_next;
            select_data_channel_rgb_reg <= select_data_channel_rgb_next; 
            rm_addr_base_reg <= rm_addr_base_next;
            rm_valid_reg <= rm_valid_next;
        end
             
    end


    always @(*) begin
        state_next = state_reg;
        arready_next = arready_reg;
        select_data_channel_rgb_next = select_data_channel_rgb_reg; 
        rm_addr_base_next = rm_addr_base_reg;
        rm_valid_next = rm_valid_reg;

        case (state_reg) 
            IDLE: begin
                if (ARVALID_i) begin
                    if ((ARADDR_i >= 'd0) && (ARADDR_i < out_pixels_reg) ) begin
                        rm_addr_base_next = ARADDR_i;
                        select_data_channel_rgb_next = plane0_channel;
                        rm_valid_next = 1;
                        state_next = RED_SETUP0;
                        arready_next = 1;
                        
                    end
                    else if ((ARADDR_i >= out_pixels_reg) && (ARADDR_i < out_pixels_x2)) begin
                        select_data_channel_rgb_next = plane1_channel;
                        state_next = GREEN_SETUP;
                        arready_next = 1;
                        
                    end
                    else begin
                        select_data_channel_rgb_next = plane2_channel;
                        state_next = BLUE_SETUP;
                        arready_next = 1;
                    end
                end

            end
            RED_SETUP0: begin
                arready_next = 0;
                if (rm_ready_i) begin
                    rm_valid_next = 0;
                    state_next = RED_SETUP1;
                end
            end
            RED_SETUP1: begin
                if (tlast_data_channel_rgb_i && tvalid_data_channel_rgb_i && tready_data_channel_rgb_i) begin
                    state_next = IDLE;
                    select_data_channel_rgb_next = 3'b000;
                end
            end
            GREEN_SETUP: begin
                arready_next = 0;
                if (tlast_data_channel_rgb_i && tvalid_data_channel_rgb_i && tready_data_channel_rgb_i) begin
                    state_next = IDLE;
                    select_data_channel_rgb_next = 3'b000;
                end
              
            end
            BLUE_SETUP: begin
                arready_next = 0;
                if (tlast_data_channel_rgb_i && tvalid_data_channel_rgb_i && tready_data_channel_rgb_i) begin
                    state_next = IDLE;
                    select_data_channel_rgb_next = 3'b000;
                end
            end

            default: begin
                state_next = IDLE;
            end
                
            
        endcase


    end

    assign ARREADY_o = arready_reg;
    assign select_data_channel_rgb_o = select_data_channel_rgb_reg;
    assign rm_addr_base_o = rm_addr_base_reg;
    assign rm_valid_o = rm_valid_reg;
endmodule
