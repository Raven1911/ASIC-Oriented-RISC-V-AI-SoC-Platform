`timescale 1ns / 1ps

// -----------------------------------------------------------------------------
// cnn_axi_lite
// -----------------------------------------------------------------------------
// AXI-Lite wrapper for CNN_accel.
//
// Register-side contract follows the other Beta_AISoC AXI-Lite peripherals:
//   - o_addr_w/o_data_w/o_wen are the captured write address/data/byte-strobes.
//   - o_write_data_w is the register-write commit pulse.
//   - o_addr_r selects the combinational readback mux.
// -----------------------------------------------------------------------------
module cnn_axi_lite #(
    parameter NUM_MASTERS      = 1,
    parameter ADDR_WIDTH       = 32,
    parameter DATA_WIDTH       = 32,
    parameter TRANS_W_STRB_W   = 4,
    parameter TRANS_WR_RESP_W  = 2,
    parameter TRANS_PROT       = 3,
    parameter CYCLE_CLOCK      = 2,

    // // CNN_accel parameters
    parameter CNN_DATA_WIDTH= 8,
    parameter ACC_WIDTH     = 32,
    parameter IFBUF_DEPTH   = 224,
    parameter FLTBUF_DEPTH  = 4700,
    parameter COMP_DEPTH    = 12,
    parameter FIFO_DEPTH    = 12,
    parameter OFBUF_DEPTH   = 896,
    parameter K             = 4,
    parameter M             = 2,
    parameter PE_PER_PU     = 12,
    parameter PPDEPTH       = 224,
    parameter BURSTL_IFMAP = 8,
    parameter BURSTL_FILTER = 10,
    parameter BURSTL_BIAS = 7,
    parameter BURSTL_OFMAP = 8,

    // Register map
    parameter [ADDR_WIDTH-1:0] ADDR_CNN_BASE          = 32'h0200_9000,
    parameter [ADDR_WIDTH-1:0] ADDR_START             = ADDR_CNN_BASE + 32'h0000_0000,
    parameter [ADDR_WIDTH-1:0] ADDR_STATUS            = ADDR_CNN_BASE + 32'h0000_0004,
    parameter [ADDR_WIDTH-1:0] ADDR_IFHEIGHT          = ADDR_CNN_BASE + 32'h0000_0008,
    parameter [ADDR_WIDTH-1:0] ADDR_IFCHANNEL         = ADDR_CNN_BASE + 32'h0000_000C,
    parameter [ADDR_WIDTH-1:0] ADDR_OFCHANNEL         = ADDR_CNN_BASE + 32'h0000_0010,
    parameter [ADDR_WIDTH-1:0] ADDR_HF                = ADDR_CNN_BASE + 32'h0000_0014,
    parameter [ADDR_WIDTH-1:0] ADDR_STRIDE            = ADDR_CNN_BASE + 32'h0000_0018,
    parameter [ADDR_WIDTH-1:0] ADDR_PADDING           = ADDR_CNN_BASE + 32'h0000_001C,
    parameter [ADDR_WIDTH-1:0] ADDR_IFPARR            = ADDR_CNN_BASE + 32'h0000_0020,
    parameter [ADDR_WIDTH-1:0] ADDR_OFTILE            = ADDR_CNN_BASE + 32'h0000_0024,
    parameter [ADDR_WIDTH-1:0] ADDR_OFPARR            = ADDR_CNN_BASE + 32'h0000_0028,
    parameter [ADDR_WIDTH-1:0] ADDR_IFBADDR           = ADDR_CNN_BASE + 32'h0000_002C,
    parameter [ADDR_WIDTH-1:0] ADDR_FLTBADDR          = ADDR_CNN_BASE + 32'h0000_0030,
    parameter [ADDR_WIDTH-1:0] ADDR_BIAS_BADDR        = ADDR_CNN_BASE + 32'h0000_0034,
    parameter [ADDR_WIDTH-1:0] ADDR_OFBADDR           = ADDR_CNN_BASE + 32'h0000_0038,
    parameter [ADDR_WIDTH-1:0] ADDR_IFC_ZP            = ADDR_CNN_BASE + 32'h0000_003C,
    parameter [ADDR_WIDTH-1:0] ADDR_FLTC_ZP           = ADDR_CNN_BASE + 32'h0000_0040,
    parameter [ADDR_WIDTH-1:0] ADDR_MULT              = ADDR_CNN_BASE + 32'h0000_0044,
    parameter [ADDR_WIDTH-1:0] ADDR_MULT_SHIFT        = ADDR_CNN_BASE + 32'h0000_0048,
    parameter [ADDR_WIDTH-1:0] ADDR_ALPHAMULT         = ADDR_CNN_BASE + 32'h0000_004C,
    parameter [ADDR_WIDTH-1:0] ADDR_ALPHAMULT_SHIFT   = ADDR_CNN_BASE + 32'h0000_0050,
    parameter [ADDR_WIDTH-1:0] ADDR_ZPY               = ADDR_CNN_BASE + 32'h0000_0054,
    parameter [ADDR_WIDTH-1:0] ADDR_QMIN              = ADDR_CNN_BASE + 32'h0000_0058,
    parameter [ADDR_WIDTH-1:0] ADDR_QMAX              = ADDR_CNN_BASE + 32'h0000_005C,
    parameter [ADDR_WIDTH-1:0] ADDR_IS_LEAKY_RELU     = ADDR_CNN_BASE + 32'h0000_0060,
    parameter [ADDR_WIDTH-1:0] ADDR_WRITE_FIFO        = ADDR_CNN_BASE + 32'h0000_0064
)(




    input                               clk,
    input                               resetn,

    // AXI-Lite Write Address Channel
    input       [ADDR_WIDTH-1:0]        i_axi_awaddr,
    input                               i_axi_awvalid,
    output                              o_axi_awready,
    input       [TRANS_PROT-1:0]        i_axi_awprot,

    // AXI-Lite Write Data Channel
    input       [DATA_WIDTH-1:0]        i_axi_wdata,
    input       [TRANS_W_STRB_W-1:0]    i_axi_wstrb,
    input                               i_axi_wvalid,
    output                              o_axi_wready,

    // AXI-Lite Write Response Channel
    output      [TRANS_WR_RESP_W-1:0]   o_axi_bresp,
    output                              o_axi_bvalid,
    input                               i_axi_bready,

    // AXI-Lite Read Address Channel
    input       [ADDR_WIDTH-1:0]        i_axi_araddr,
    input                               i_axi_arvalid,
    output                              o_axi_arready,
    input       [TRANS_PROT-1:0]        i_axi_arprot,

    // AXI-Lite Read Data Channel
    output      [DATA_WIDTH-1:0]        o_axi_rdata,
    output                              o_axi_rvalid,
    output      [TRANS_WR_RESP_W-1:0]   o_axi_rresp,
    input                               i_axi_rready,

    // Interrupt ports: direct CNN signal, not an AXI-Lite decoded register bit.
    output                              irq_accel_done_o,
    input                               eoi_accel_done_i,

    // Optional direct status port
    output                              cnn_cpu_accel_busy_o,

    // IFBUF DMA side
    input                               cnn_ifbuf_dma_rdycfg_i,
    input                               cnn_ifbuf_dma_vld_i,
    input       [CNN_DATA_WIDTH-1:0]    cnn_ifbuf_dma_data_i,
    input                               cnn_ifbuf_dma_tlast_i,
    output                              cnn_ifbuf_dma_vldcfg_o,
    output      [BURSTL_IFMAP-1:0]      cnn_ifbuf_dma_burst_o,
    output      [23:0]                  cnn_ifbuf_dma_baddr_o,
    output                              cnn_ifbuf_dma_rdy_o,

    // FLTBUF DMA side
    input                               cnn_fltbuf_dma_rdycfg_i,
    input                               cnn_fltbuf_dma_vld_i,
    input       [CNN_DATA_WIDTH-1:0]    cnn_fltbuf_dma_data_i,
    input                               cnn_fltbuf_dma_tlast_i,
    output                              cnn_fltbuf_dma_vldcfg_o,
    output      [BURSTL_FILTER-1:0]     cnn_fltbuf_dma_burst_o,
    output      [23:0]                  cnn_fltbuf_dma_baddr_o,
    output                              cnn_fltbuf_dma_rdy_o,

    // BIAS BUF DMA side
    input                               cnn_bias_dma_rdycfg_i,
    output                              cnn_bias_dma_vldcfg_o,
    output      [BURSTL_BIAS-1:0]       cnn_bias_dma_burst_o,
    output      [23:0]                  cnn_bias_dma_baddr_o,
    input                               cnn_bias_dma_vld_i,
    input       [7:0]                   cnn_bias_dma_data_i,
    input                               cnn_bias_dma_tlast_i,
    output                              cnn_bias_dma_rdy_o,

    // OFBUF DMA side
    input                               cnn_ofbuf_dma_rdycfg_i,
    output                              cnn_ofbuf_dma_vldcfg_o,
    output      [BURSTL_OFMAP-1:0]      cnn_ofbuf_dma_burst_o,
    output      [23:0]                  cnn_ofbuf_dma_baddr_o,
    output                              cnn_ofbuf_dma_vld_o,
    output      [CNN_DATA_WIDTH-1:0]    cnn_ofbuf_dma_data_o,
    output                              cnn_ofbuf_dma_tlast_o,
    input                               cnn_ofbuf_dma_rdy_i

    // // Optional debug / status
    // output                              cnn_comp_pa_done_compute_o,
    // output                              cnn_ifbuf_comp_end_layer_o,
    // output                              cnn_ifbuf_comp_end_layer_real_o,
    // output                              cnn_fltbuf_comp_donepass_o
);

    // -------------------------------------------------------------------------
    // Signals exported by axi_lite_slave_interface
    // -------------------------------------------------------------------------
    wire [ADDR_WIDTH-1:0]       axi_addr_w;
    wire [DATA_WIDTH-1:0]       axi_data_w;
    wire [TRANS_W_STRB_W-1:0]   axi_wstrb;
    wire                        axi_write_data_w;

    wire [ADDR_WIDTH-1:0]       axi_addr_r;
    reg  [DATA_WIDTH-1:0]       axi_data_r;

    // -------------------------------------------------------------------------
    // CNN configuration/status registers
    // -------------------------------------------------------------------------
    reg                         cnn_table_vld_reg;
    reg                         cnn_cpu_accel_start_reg;

    reg [7:0]                   cnn_table_ifheight_reg;
    reg [10:0]                  cnn_table_ifchannel_reg;
    reg [10:0]                  cnn_table_ofchannel_reg;
    reg [3:0]                   cnn_table_hf_reg;
    reg [2:0]                   cnn_table_stride_reg;
    reg [1:0]                   cnn_table_padding_reg;
    reg [2:0]                   cnn_table_ifparr_reg;
    reg [1:0]                   cnn_table_oftile_reg;
    reg [4:0]                   cnn_table_ofparr_reg;
    reg [23:0]                  cnn_table_ifbaddr_reg;
    reg [23:0]                  cnn_table_fltbaddr_reg;
    reg [23:0]                  cnn_table_bias_baddr_reg;
    reg [23:0]                  cnn_table_ofbaddr_reg;
    reg signed [CNN_DATA_WIDTH-1:0] cnn_table_ifc_zp_reg;
    reg signed [CNN_DATA_WIDTH-1:0] cnn_table_fltc_zp_reg;
    reg signed [31:0]           cnn_table_mult_reg;
    reg [5:0]                   cnn_table_mult_shift_reg;
    reg signed [31:0]           cnn_table_alphamult_reg;
    reg [5:0]                   cnn_table_alphamult_shift_reg;
    reg signed [7:0]            cnn_table_zpy_reg;
    reg signed [7:0]            cnn_table_qmin_reg;
    reg signed [7:0]            cnn_table_qmax_reg;
    reg                         cnn_table_is_leaky_ReLU_reg;

    wire                        cnn_table_rdy_w;
    (* KEEP = "TRUE", DONT_TOUCH = "TRUE" *) wire cnn_irq_accel_done_w;

    assign irq_accel_done_o = cnn_irq_accel_done_w;

    wire [31:0] reg_start_r;
    wire [31:0] reg_write_fifo_r;
    wire [31:0] reg_status_r;
    wire [31:0] reg_ifheight_r;
    wire [31:0] reg_ifchannel_r;
    wire [31:0] reg_ofchannel_r;
    wire [31:0] reg_hf_r;
    wire [31:0] reg_stride_r;
    wire [31:0] reg_padding_r;
    wire [31:0] reg_ifparr_r;
    wire [31:0] reg_oftile_r;
    wire [31:0] reg_ofparr_r;
    wire [31:0] reg_ifbaddr_r;
    wire [31:0] reg_fltbaddr_r;
    wire [31:0] reg_bias_baddr_r;
    wire [31:0] reg_ofbaddr_r;
    wire [31:0] reg_ifc_zp_r;
    wire [31:0] reg_fltc_zp_r;
    wire [31:0] reg_mult_r;
    wire [31:0] reg_mult_shift_r;
    wire [31:0] reg_alphamult_r;
    wire [31:0] reg_alphamult_shift_r;
    wire [31:0] reg_zpy_r;
    wire [31:0] reg_qmin_r;
    wire [31:0] reg_qmax_r;
    wire [31:0] reg_is_leaky_relu_r;

    reg  [31:0] wr_data_old;
    reg  [31:0] wr_data_strobed;

    assign reg_start_r             = {31'd0, cnn_cpu_accel_start_reg};
    assign reg_write_fifo_r        = {31'd0, cnn_table_vld_reg};
    assign reg_status_r            = {27'd0, cnn_cpu_accel_start_reg, cnn_irq_accel_done_w, cnn_cpu_accel_busy_o, cnn_table_rdy_w, cnn_table_vld_reg};
    assign reg_ifheight_r          = {24'd0, cnn_table_ifheight_reg};
    assign reg_ifchannel_r         = {21'd0, cnn_table_ifchannel_reg};
    assign reg_ofchannel_r         = {21'd0, cnn_table_ofchannel_reg};
    assign reg_hf_r                = {28'd0, cnn_table_hf_reg};
    assign reg_stride_r            = {29'd0, cnn_table_stride_reg};
    assign reg_padding_r           = {30'd0, cnn_table_padding_reg};
    assign reg_ifparr_r            = {29'd0, cnn_table_ifparr_reg};
    assign reg_oftile_r            = {30'd0, cnn_table_oftile_reg};
    assign reg_ofparr_r            = {27'd0, cnn_table_ofparr_reg};
    assign reg_ifbaddr_r           = {8'd0, cnn_table_ifbaddr_reg};
    assign reg_fltbaddr_r          = {8'd0, cnn_table_fltbaddr_reg};
    assign reg_bias_baddr_r        = {8'd0, cnn_table_bias_baddr_reg};
    assign reg_ofbaddr_r           = {8'd0, cnn_table_ofbaddr_reg};
    assign reg_ifc_zp_r            = {{(32-CNN_DATA_WIDTH){cnn_table_ifc_zp_reg[CNN_DATA_WIDTH-1]}}, cnn_table_ifc_zp_reg};
    assign reg_fltc_zp_r           = {{(32-CNN_DATA_WIDTH){cnn_table_fltc_zp_reg[CNN_DATA_WIDTH-1]}}, cnn_table_fltc_zp_reg};
    assign reg_mult_r              = cnn_table_mult_reg;
    assign reg_mult_shift_r        = {26'd0, cnn_table_mult_shift_reg};
    assign reg_alphamult_r         = cnn_table_alphamult_reg;
    assign reg_alphamult_shift_r   = {26'd0, cnn_table_alphamult_shift_reg};
    assign reg_zpy_r               = {{24{cnn_table_zpy_reg[7]}}, cnn_table_zpy_reg};
    assign reg_qmin_r              = {{24{cnn_table_qmin_reg[7]}}, cnn_table_qmin_reg};
    assign reg_qmax_r              = {{24{cnn_table_qmax_reg[7]}}, cnn_table_qmax_reg};
    assign reg_is_leaky_relu_r     = {31'd0, cnn_table_is_leaky_ReLU_reg};

    always @(*) begin
        case (axi_addr_w)
            ADDR_START:           wr_data_old = reg_start_r;
            ADDR_WRITE_FIFO:      wr_data_old = reg_write_fifo_r;
            ADDR_STATUS:          wr_data_old = reg_status_r;
            ADDR_IFHEIGHT:        wr_data_old = reg_ifheight_r;
            ADDR_IFCHANNEL:       wr_data_old = reg_ifchannel_r;
            ADDR_OFCHANNEL:       wr_data_old = reg_ofchannel_r;
            ADDR_HF:              wr_data_old = reg_hf_r;
            ADDR_STRIDE:          wr_data_old = reg_stride_r;
            ADDR_PADDING:         wr_data_old = reg_padding_r;
            ADDR_IFPARR:          wr_data_old = reg_ifparr_r;
            ADDR_OFTILE:          wr_data_old = reg_oftile_r;
            ADDR_OFPARR:          wr_data_old = reg_ofparr_r;
            ADDR_IFBADDR:         wr_data_old = reg_ifbaddr_r;
            ADDR_FLTBADDR:        wr_data_old = reg_fltbaddr_r;
            ADDR_BIAS_BADDR:      wr_data_old = reg_bias_baddr_r;
            ADDR_OFBADDR:         wr_data_old = reg_ofbaddr_r;
            ADDR_IFC_ZP:          wr_data_old = reg_ifc_zp_r;
            ADDR_FLTC_ZP:         wr_data_old = reg_fltc_zp_r;
            ADDR_MULT:            wr_data_old = reg_mult_r;
            ADDR_MULT_SHIFT:      wr_data_old = reg_mult_shift_r;
            ADDR_ALPHAMULT:       wr_data_old = reg_alphamult_r;
            ADDR_ALPHAMULT_SHIFT: wr_data_old = reg_alphamult_shift_r;
            ADDR_ZPY:             wr_data_old = reg_zpy_r;
            ADDR_QMIN:            wr_data_old = reg_qmin_r;
            ADDR_QMAX:            wr_data_old = reg_qmax_r;
            ADDR_IS_LEAKY_RELU:   wr_data_old = reg_is_leaky_relu_r;
            default:              wr_data_old = 32'd0;
        endcase
    end

    always @(*) begin
        wr_data_strobed = wr_data_old;
        if (axi_wstrb[0]) begin
            wr_data_strobed[7:0] = axi_data_w[7:0];
        end
        if (axi_wstrb[1]) begin
            wr_data_strobed[15:8] = axi_data_w[15:8];
        end
        if (axi_wstrb[2]) begin
            wr_data_strobed[23:16] = axi_data_w[23:16];
        end
        if (axi_wstrb[3]) begin
            wr_data_strobed[31:24] = axi_data_w[31:24];
        end
    end

    // -------------------------------------------------------------------------
    // Register write side.
    //
    // ADDR_START:
    //   write bit[0] = 1 to generate a one-clock start pulse into CNN_accel.
    //
    // ADDR_WRITE_FIFO:
    //   write bit[0] = 1 to assert cnn_table_vld_reg. The bit remains asserted
    //   until CNN_accel raises cnn_table_rdy_w, forming a vld/rdy handshake.
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            cnn_table_vld_reg             <= 1'b0;
            cnn_cpu_accel_start_reg       <= 1'b0;
            cnn_table_ifheight_reg        <= 8'd0;
            cnn_table_ifchannel_reg       <= 11'd0;
            cnn_table_ofchannel_reg       <= 11'd0;
            cnn_table_hf_reg              <= 4'd0;
            cnn_table_stride_reg          <= 3'd0;
            cnn_table_padding_reg         <= 2'd0;
            cnn_table_ifparr_reg          <= 3'd0;
            cnn_table_oftile_reg          <= 2'd0;
            cnn_table_ofparr_reg          <= 5'd0;
            cnn_table_ifbaddr_reg         <= 24'd0;
            cnn_table_fltbaddr_reg        <= 24'd0;
            cnn_table_bias_baddr_reg      <= 24'd0;
            cnn_table_ofbaddr_reg         <= 24'd0;
            cnn_table_ifc_zp_reg          <= {CNN_DATA_WIDTH{1'b0}};
            cnn_table_fltc_zp_reg         <= {CNN_DATA_WIDTH{1'b0}};
            cnn_table_mult_reg            <= 32'sd0;
            cnn_table_mult_shift_reg      <= 6'd0;
            cnn_table_alphamult_reg       <= 32'sd0;
            cnn_table_alphamult_shift_reg <= 6'd0;
            cnn_table_zpy_reg             <= 8'sd0;
            cnn_table_qmin_reg            <= 8'sd0;
            cnn_table_qmax_reg            <= 8'sd0;
            cnn_table_is_leaky_ReLU_reg   <= 1'b0;
        end else begin
            cnn_cpu_accel_start_reg <= 1'b0;

            if (cnn_table_rdy_w) begin
                cnn_table_vld_reg <= 1'b0;
            end

            if (axi_write_data_w) begin
                case (axi_addr_w)
                    ADDR_START: begin
                        if (axi_wstrb[0] && axi_data_w[0]) begin
                            cnn_cpu_accel_start_reg <= 1'b1;
                        end
                    end

                    ADDR_WRITE_FIFO: begin
                        if (axi_wstrb[0] && axi_data_w[0]) begin
                            cnn_table_vld_reg <= 1'b1;
                        end
                    end

                    ADDR_IFHEIGHT:        cnn_table_ifheight_reg        <= wr_data_strobed[7:0];
                    ADDR_IFCHANNEL:       cnn_table_ifchannel_reg       <= wr_data_strobed[10:0];
                    ADDR_OFCHANNEL:       cnn_table_ofchannel_reg       <= wr_data_strobed[10:0];
                    ADDR_HF:              cnn_table_hf_reg              <= wr_data_strobed[3:0];
                    ADDR_STRIDE:          cnn_table_stride_reg          <= wr_data_strobed[2:0];
                    ADDR_PADDING:         cnn_table_padding_reg         <= wr_data_strobed[1:0];
                    ADDR_IFPARR:          cnn_table_ifparr_reg          <= wr_data_strobed[2:0];
                    ADDR_OFTILE:          cnn_table_oftile_reg          <= wr_data_strobed[1:0];
                    ADDR_OFPARR:          cnn_table_ofparr_reg          <= wr_data_strobed[4:0];
                    ADDR_IFBADDR:         cnn_table_ifbaddr_reg         <= wr_data_strobed[23:0];
                    ADDR_FLTBADDR:        cnn_table_fltbaddr_reg        <= wr_data_strobed[23:0];
                    ADDR_BIAS_BADDR:      cnn_table_bias_baddr_reg      <= wr_data_strobed[23:0];
                    ADDR_OFBADDR:         cnn_table_ofbaddr_reg         <= wr_data_strobed[23:0];
                    ADDR_IFC_ZP:          cnn_table_ifc_zp_reg          <= wr_data_strobed[CNN_DATA_WIDTH-1:0];
                    ADDR_FLTC_ZP:         cnn_table_fltc_zp_reg         <= wr_data_strobed[CNN_DATA_WIDTH-1:0];
                    ADDR_MULT:            cnn_table_mult_reg            <= wr_data_strobed;
                    ADDR_MULT_SHIFT:      cnn_table_mult_shift_reg      <= wr_data_strobed[5:0];
                    ADDR_ALPHAMULT:       cnn_table_alphamult_reg       <= wr_data_strobed;
                    ADDR_ALPHAMULT_SHIFT: cnn_table_alphamult_shift_reg <= wr_data_strobed[5:0];
                    ADDR_ZPY:             cnn_table_zpy_reg             <= wr_data_strobed[7:0];
                    ADDR_QMIN:            cnn_table_qmin_reg            <= wr_data_strobed[7:0];
                    ADDR_QMAX:            cnn_table_qmax_reg            <= wr_data_strobed[7:0];
                    ADDR_IS_LEAKY_RELU:   cnn_table_is_leaky_ReLU_reg   <= wr_data_strobed[0];
                    default: ;
                endcase
            end
        end
    end

    // -------------------------------------------------------------------------
    // Read mux. axi_lite_slave_interface samples axi_data_r when its R channel
    // response is generated, so axi_data_r is purely combinational from o_addr_r.
    // -------------------------------------------------------------------------
    always @(*) begin
        case (axi_addr_r)
            ADDR_START:           axi_data_r = reg_start_r;
            ADDR_WRITE_FIFO:      axi_data_r = reg_write_fifo_r;
            ADDR_STATUS:          axi_data_r = reg_status_r;
            ADDR_IFHEIGHT:        axi_data_r = reg_ifheight_r;
            ADDR_IFCHANNEL:       axi_data_r = reg_ifchannel_r;
            ADDR_OFCHANNEL:       axi_data_r = reg_ofchannel_r;
            ADDR_HF:              axi_data_r = reg_hf_r;
            ADDR_STRIDE:          axi_data_r = reg_stride_r;
            ADDR_PADDING:         axi_data_r = reg_padding_r;
            ADDR_IFPARR:          axi_data_r = reg_ifparr_r;
            ADDR_OFTILE:          axi_data_r = reg_oftile_r;
            ADDR_OFPARR:          axi_data_r = reg_ofparr_r;
            ADDR_IFBADDR:         axi_data_r = reg_ifbaddr_r;
            ADDR_FLTBADDR:        axi_data_r = reg_fltbaddr_r;
            ADDR_BIAS_BADDR:      axi_data_r = reg_bias_baddr_r;
            ADDR_OFBADDR:         axi_data_r = reg_ofbaddr_r;
            ADDR_IFC_ZP:          axi_data_r = reg_ifc_zp_r;
            ADDR_FLTC_ZP:         axi_data_r = reg_fltc_zp_r;
            ADDR_MULT:            axi_data_r = reg_mult_r;
            ADDR_MULT_SHIFT:      axi_data_r = reg_mult_shift_r;
            ADDR_ALPHAMULT:       axi_data_r = reg_alphamult_r;
            ADDR_ALPHAMULT_SHIFT: axi_data_r = reg_alphamult_shift_r;
            ADDR_ZPY:             axi_data_r = reg_zpy_r;
            ADDR_QMIN:            axi_data_r = reg_qmin_r;
            ADDR_QMAX:            axi_data_r = reg_qmax_r;
            ADDR_IS_LEAKY_RELU:   axi_data_r = reg_is_leaky_relu_r;
            default:              axi_data_r = 32'd0;
        endcase
    end

    // -------------------------------------------------------------------------
    // CNN accelerator instance
    // -------------------------------------------------------------------------
    CNN_accel #(
        .DATA_WIDTH(CNN_DATA_WIDTH),
        .ACC_WIDTH(ACC_WIDTH),
        .IFBUF_DEPTH(IFBUF_DEPTH),
        .FLTBUF_DEPTH(FLTBUF_DEPTH),
        .COMP_DEPTH(COMP_DEPTH),
        .FIFO_DEPTH(FIFO_DEPTH),
        .OFBUF_DEPTH(OFBUF_DEPTH),
        .K(K),
        .M(M),
        .PE_PER_PU(PE_PER_PU),
        .PPDEPTH(PPDEPTH),
        .BURSTL_IFMAP(BURSTL_IFMAP),
        .BURSTL_FILTER(BURSTL_FILTER),
        .BURSTL_BIAS(BURSTL_BIAS),
        .BURSTL_OFMAP(BURSTL_OFMAP)
    ) u_cnn_accel (
        .clk(clk),
        .rst_n(resetn),

        .cnn_table_vld_i(cnn_table_vld_reg),
        .cnn_table_rdy_o(cnn_table_rdy_w),
        .cnn_table_ifheight_i(cnn_table_ifheight_reg),
        .cnn_table_ifchannel_i(cnn_table_ifchannel_reg),
        .cnn_table_ofchannel_i(cnn_table_ofchannel_reg),
        .cnn_table_hf_i(cnn_table_hf_reg),
        .cnn_table_stride_i(cnn_table_stride_reg),
        .cnn_table_padding_i(cnn_table_padding_reg),
        .cnn_table_ifparr_i(cnn_table_ifparr_reg),
        .cnn_table_oftile_i(cnn_table_oftile_reg),
        .cnn_table_ofparr_i(cnn_table_ofparr_reg),
        .cnn_table_ifbaddr_i(cnn_table_ifbaddr_reg),
        .cnn_table_fltbaddr_i(cnn_table_fltbaddr_reg),
        .cnn_table_bias_baddr_i(cnn_table_bias_baddr_reg),
        .cnn_table_ofbaddr_i(cnn_table_ofbaddr_reg),
        .cnn_table_ifc_zp_i(cnn_table_ifc_zp_reg),
        .cnn_table_fltc_zp_i(cnn_table_fltc_zp_reg),
        .cnn_table_mult_i(cnn_table_mult_reg),
        .cnn_table_mult_shift_i(cnn_table_mult_shift_reg),
        .cnn_table_alphamult_i(cnn_table_alphamult_reg),
        .cnn_table_alphamult_shift_i(cnn_table_alphamult_shift_reg),
        .cnn_table_zpy_i(cnn_table_zpy_reg),
        .cnn_table_qmin_i(cnn_table_qmin_reg),
        .cnn_table_qmax_i(cnn_table_qmax_reg),
        .cnn_table_is_leaky_ReLU_i(cnn_table_is_leaky_ReLU_reg),

        .cnn_cpu_accel_busy_o(cnn_cpu_accel_busy_o),
        .cnn_cpu_accel_start_i(cnn_cpu_accel_start_reg),
        .cnn_cpu_accel_done_o(cnn_irq_accel_done_w),
        .cnn_cpu_receive_interupt_i(eoi_accel_done_i),

        .cnn_ifbuf_dma_rdycfg_i(cnn_ifbuf_dma_rdycfg_i),
        .cnn_ifbuf_dma_vld_i(cnn_ifbuf_dma_vld_i),
        .cnn_ifbuf_dma_data_i(cnn_ifbuf_dma_data_i),
        .cnn_ifbuf_dma_tlast_i(cnn_ifbuf_dma_tlast_i),
        .cnn_ifbuf_dma_vldcfg_o(cnn_ifbuf_dma_vldcfg_o),
        .cnn_ifbuf_dma_burst_o(cnn_ifbuf_dma_burst_o),
        .cnn_ifbuf_dma_baddr_o(cnn_ifbuf_dma_baddr_o),
        .cnn_ifbuf_dma_rdy_o(cnn_ifbuf_dma_rdy_o),

        .cnn_fltbuf_dma_rdycfg_i(cnn_fltbuf_dma_rdycfg_i),
        .cnn_fltbuf_dma_vld_i(cnn_fltbuf_dma_vld_i),
        .cnn_fltbuf_dma_data_i(cnn_fltbuf_dma_data_i),
        .cnn_fltbuf_dma_tlast_i(cnn_fltbuf_dma_tlast_i),
        .cnn_fltbuf_dma_vldcfg_o(cnn_fltbuf_dma_vldcfg_o),
        .cnn_fltbuf_dma_burst_o(cnn_fltbuf_dma_burst_o),
        .cnn_fltbuf_dma_baddr_o(cnn_fltbuf_dma_baddr_o),
        .cnn_fltbuf_dma_rdy_o(cnn_fltbuf_dma_rdy_o),

        .cnn_bias_dma_rdycfg_i(cnn_bias_dma_rdycfg_i),
        .cnn_bias_dma_vldcfg_o(cnn_bias_dma_vldcfg_o),
        .cnn_bias_dma_burst_o(cnn_bias_dma_burst_o),
        .cnn_bias_dma_baddr_o(cnn_bias_dma_baddr_o),
        .cnn_bias_dma_vld_i(cnn_bias_dma_vld_i),
        .cnn_bias_dma_data_i(cnn_bias_dma_data_i),
        .cnn_bias_dma_tlast_i(cnn_bias_dma_tlast_i),
        .cnn_bias_dma_rdy_o(cnn_bias_dma_rdy_o),

        .cnn_ofbuf_dma_rdycfg_i(cnn_ofbuf_dma_rdycfg_i),
        .cnn_ofbuf_dma_vldcfg_o(cnn_ofbuf_dma_vldcfg_o),
        .cnn_ofbuf_dma_burst_o(cnn_ofbuf_dma_burst_o),
        .cnn_ofbuf_dma_baddr_o(cnn_ofbuf_dma_baddr_o),
        .cnn_ofbuf_dma_vld_o(cnn_ofbuf_dma_vld_o),
        .cnn_ofbuf_dma_data_o(cnn_ofbuf_dma_data_o),
        .cnn_ofbuf_dma_tlast_o(cnn_ofbuf_dma_tlast_o),
        .cnn_ofbuf_dma_rdy_i(cnn_ofbuf_dma_rdy_i),

        .cnn_comp_pa_done_compute_o(/*cnn_comp_pa_done_compute_o*/),
        .cnn_ifbuf_comp_end_layer_o(/*cnn_ifbuf_comp_end_layer_o*/),
        .cnn_ifbuf_comp_end_layer_real_o(/*cnn_ifbuf_comp_end_layer_real_o*/),
        .cnn_fltbuf_comp_donepass_o(/*cnn_fltbuf_comp_donepass_o*/)
    );

    // -------------------------------------------------------------------------
    // AXI-Lite protocol adapter. This module produces AXI READY/VALID/BRESP/RRESP
    // and exposes captured address/data/status signals to this register wrapper.
    // -------------------------------------------------------------------------
    axi_lite_slave_interface #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .TRANS_W_STRB_W(TRANS_W_STRB_W),
        .TRANS_WR_RESP_W(TRANS_WR_RESP_W),
        .TRANS_PROT(TRANS_PROT),
        .CYCLE_CLOCK(CYCLE_CLOCK),
        .NUM_MASTERS(NUM_MASTERS)
    ) u_axi_lite_slave_interface (
        .clk_i(clk),
        .resetn_i(resetn),

        .i_axi_awaddr(i_axi_awaddr),
        .i_axi_awvalid(i_axi_awvalid),
        .o_axi_awready(o_axi_awready),
        .i_axi_awprot(i_axi_awprot),

        .i_axi_wdata(i_axi_wdata),
        .i_axi_wstrb(i_axi_wstrb),
        .i_axi_wvalid(i_axi_wvalid),
        .o_axi_wready(o_axi_wready),

        .o_axi_bresp(o_axi_bresp),
        .o_axi_bvalid(o_axi_bvalid),
        .i_axi_bready(i_axi_bready),

        .i_axi_araddr(i_axi_araddr),
        .i_axi_arvalid(i_axi_arvalid),
        .o_axi_arready(o_axi_arready),
        .i_axi_arprot(i_axi_arprot),

        .o_axi_rdata(o_axi_rdata),
        .o_axi_rvalid(o_axi_rvalid),
        .o_axi_rresp(o_axi_rresp),
        .i_axi_rready(i_axi_rready),

        .o_addr_w(axi_addr_w),
        .o_awprot_w(),
        .o_wen(axi_wstrb),
        .o_data_w(axi_data_w),
        .o_write_data_w(axi_write_data_w),
        .i_bresp_w(2'b00),

        .o_addr_r(axi_addr_r),
        .o_arprot_r(),
        .i_data_r(axi_data_r),
        .i_rresp_r(2'b00),
        .o_read_data_r()
    );

endmodule
