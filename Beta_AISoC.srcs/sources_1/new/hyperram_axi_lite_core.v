`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 09/25/2025 04:54:46 PM
// Design Name: 
// Module Name: OSPI_axi_lite_core
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

`define SYNTHESIS


module hyperram_axi_lite_core #( 
    // ========================================================
    // AXI-LITE CONFIGURATION (CPU PORT)
    // ========================================================
    parameter SETUP_PORTS           = 0,
    parameter NUM_MASTERS           = 1,
    parameter ADDR_WIDTH            = 32,          // AXI-Lite Address width
    parameter DATA_WIDTH            = 32,          // AXI-Lite Data width
    parameter TRANS_W_STRB_W        = 4,           // width strobe
    parameter TRANS_WR_RESP_W       = 2,           // width response
    parameter TRANS_PROT            = 3,
    parameter CYCLE_CLOCK           = 2,

    // Config register memory map
    parameter [ADDR_WIDTH-1:0] ADDR_REGISTERS_0 = 32'h0200_5000,
    parameter [ADDR_WIDTH-1:0] ADDR_REGISTERS_1 = 32'h0200_5004,
    parameter [ADDR_WIDTH-1:0] ADDR_REGISTERS_2 = 32'h0200_5008,
    parameter [ADDR_WIDTH-1:0] ADDR_REGISTERS_3 = 32'h0200_500C,
    parameter [ADDR_WIDTH-1:0] ADDR_REGISTERS_4 = 32'h0200_5010,
    parameter [ADDR_WIDTH-1:0] ADDR_REGISTERS_5 = 32'h0200_5014, // NEW: Mode Selection Register

    // ========================================================
    // ACCEL PORT CONFIGURATION (DMAC & AXIS)
    // ========================================================
    parameter ADDR_WIDTH_DMAC       = 24,
    parameter BURST_WIDTH           = 8,
    parameter DATA_WIDTH_BYTE       = 1,            // 1: 8bit, 2: 16bit, 4: 32bit, 8: 64bit
    parameter MODE_2READ_ENB        = 1,
    parameter SHMOOD_SELECT         = 0,  // 0: FMC0 , 1: FMC1
    parameter SIM_ENB               = 0 // 0: DIS 1: ENB
)(  
    // ========================================================
    // 1. SYSTEM SIGNALS
    // ========================================================
    input                           clk,
    input                           resetn,

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

    // ========================================================
    // 3. ACCEL COMMAND PORT (AXI to DMAC)
    // ========================================================
    input                               AWVALID_i,
    output                              AWREADY_o,
    input       [ADDR_WIDTH_DMAC-1:0]   AWADDR_i,
    input       [BURST_WIDTH-1:0]       AWBURST_i,

    input                               ARVALID_i,
    output                              ARREADY_o,
    input       [ADDR_WIDTH_DMAC-1:0]   ARADDR_i,
    input       [BURST_WIDTH-1:0]       ARBURST_i,  

    // ========================================================
    // 4. ACCEL DATA PORT (AXI-STREAM)
    // ========================================================
    // --- Master Port (Read data out for Accel) ---
    output                          m_tvalid_o,
    input                           m_tready_i,
    output  [DATA_WIDTH_BYTE*8-1:0] m_tdata_o,
    output  [DATA_WIDTH_BYTE-1:0]   m_tstrb_o,
    output  [DATA_WIDTH_BYTE-1:0]   m_tkeep_o,
    output                          m_tlast_o,
    output                          m_tid_o,

    // --- Master Port 1 (Read data out for Accel CH1 - DÙNG CHO CHẾ ĐỘ 2 READ) ---
    // --- Master Port 0 (Read data out for Accel CH0) ---
    output                          m1_tvalid_o,
    input                           m1_tready_i,
    output  [DATA_WIDTH_BYTE*8-1:0] m1_tdata_o,
    output  [DATA_WIDTH_BYTE-1:0]   m1_tstrb_o,
    output  [DATA_WIDTH_BYTE-1:0]   m1_tkeep_o,
    output                          m1_tlast_o,

    // --- Slave Port (Write data in from Accel) ---
    input                           s_tvalid_i,
    output                          s_tready_o,
    input   [DATA_WIDTH_BYTE*8-1:0] s_tdata_i,
    input   [DATA_WIDTH_BYTE-1:0]   s_tstrb_i,
    input   [DATA_WIDTH_BYTE-1:0]   s_tkeep_i,
    input                           s_tlast_i,

    // ========================================================
    // 5. EXTERNAL HYPERBUS PHYSICAL PINS
    // ========================================================
    inout   [7:0]                   dq_io,
    inout                           rwds_io,
    output                          hclk_p,
    output                          hclk_n,
    output                          cs_n
);

    // ========================================================
    // INTERNAL WIRES DECLARATION
    // ========================================================
    // AXI-Lite internal connections
    wire [ADDR_WIDTH-1:0]           o_addr_w;
    wire [ADDR_WIDTH-1:0]           o_addr_r;                
    wire [DATA_WIDTH-1:0]           o_data_w;
    wire [DATA_WIDTH-1:0]           i_data_r;
    wire                            o_wr_w;
    wire                            o_rd_r;

    // Register decoding signals
    wire                            wr_reg0, wr_reg1, wr_reg2, wr_reg3, wr_reg5;
    wire                            rd_reg4;
    wire [31:0]                     rd_hyperram_reg4;

    // CPU FIFO Interface connections
    wire                            cpu_full;
    wire                            cpu_empty;
    wire [7:0]                      cpu_rdata;
    
    // DMAC Outputs
    wire                            dmac_start;
    wire [47:0]                     dmac_cmd_addr;
    wire [7:0]                      dmac_burst_len;
    wire [3:0]                      dmac_latency;
    wire [3:0]                      dmac_recovery;
    wire [1:0]                      dmac_capture_shmoo;
    wire                            dmac_wr_read_fifo;

    // HyperBus Master Output Status
    wire                            master_start_rdy;
    wire                            wr_read_fifo;
    wire                            tlast_read_fifo;
    wire                            tid_read_fifo;
    wire                            tlast_write_fifo;

    // MUX Intermediate signals
    wire                            mode_accel;
    wire [47:0]                     final_cmd_addr;
    wire                            final_start;
    wire [7:0]                      final_burst_len;
    wire [3:0]                      final_latency;
    wire [3:0]                      final_recovery;
    wire [1:0]                      final_capture_shmoo;
    wire                            dmac_start_rdy;

    // ========================================================
    // CPU REGISTERS BLOCK
    // ========================================================
    reg [31:0] wr_hyperram_reg0, wr_hyperram_reg1, wr_hyperram_reg2, wr_hyperram_reg3, wr_hyperram_reg5;
    reg [31:0] rdata_mux;

    always @(posedge clk, negedge resetn) begin
        if(~resetn) begin
            wr_hyperram_reg0 <= 0;
            wr_hyperram_reg1 <= 0;
            wr_hyperram_reg2 <= 0;
            wr_hyperram_reg3 <= 0;
            wr_hyperram_reg5[1:0] <= 2'b10; // Default 0 = CPU Mode
            wr_hyperram_reg5[16:2] <= 15'd1; // Default write weights for DMAC channels (if Accel mode is enabled)
            wr_hyperram_reg5[31:17] <= 15'd2; // Default read weights for DMAC channels (if Accel mode is enabled)
        end
        else begin
            if (wr_reg0) wr_hyperram_reg0 <= o_data_w;
            if (wr_reg1) wr_hyperram_reg1 <= o_data_w;
            if (wr_reg2) wr_hyperram_reg2 <= o_data_w;
            if (wr_reg3) wr_hyperram_reg3 <= o_data_w;
            if (wr_reg5) wr_hyperram_reg5 <= o_data_w;
        end
    end

    // Address Decoding
    assign wr_reg0 = (o_wr_w && (o_addr_w == ADDR_REGISTERS_0)) ? 1'b1 : 1'b0;
    assign wr_reg1 = (o_wr_w && (o_addr_w == ADDR_REGISTERS_1)) ? 1'b1 : 1'b0;
    assign wr_reg2 = (o_wr_w && (o_addr_w == ADDR_REGISTERS_2)) ? 1'b1 : 1'b0;
    assign wr_reg3 = (o_wr_w && (o_addr_w == ADDR_REGISTERS_3)) ? 1'b1 : 1'b0;
    assign wr_reg5 = (o_wr_w && (o_addr_w == ADDR_REGISTERS_5)) ? 1'b1 : 1'b0;
    assign rd_reg4 = (o_rd_r && (o_addr_r == ADDR_REGISTERS_4)) ? 1'b1 : 1'b0;

    // Read Data Multiplexer
    always @(*) begin
        case (o_addr_r)
            ADDR_REGISTERS_0: rdata_mux = wr_hyperram_reg0;
            ADDR_REGISTERS_1: rdata_mux = wr_hyperram_reg1;
            ADDR_REGISTERS_2: rdata_mux = wr_hyperram_reg2;
            ADDR_REGISTERS_3: rdata_mux = wr_hyperram_reg3;
            ADDR_REGISTERS_4: rdata_mux = rd_hyperram_reg4;
            ADDR_REGISTERS_5: rdata_mux = wr_hyperram_reg5;
            default:          rdata_mux = 32'h0;
        endcase
    end
    
    assign i_data_r = rdata_mux;

    // Map Read Status (Register 4)
    assign rd_hyperram_reg4[7:0]   = cpu_rdata;
    assign rd_hyperram_reg4[8]     = cpu_full;
    assign rd_hyperram_reg4[9]     = cpu_empty;
    assign rd_hyperram_reg4[10]    = master_start_rdy;
    assign rd_hyperram_reg4[31:11] = 21'd0;

    // ========================================================
    // MULTIPLEXER (MUX) FOR COMMAND ROUTING
    // ========================================================
    // mode_accel = 0 -> Controlled by CPU via HyperRAM Registers
    // mode_accel = 1 -> Controlled by DMAC Accel core
    assign mode_accel          = wr_hyperram_reg5[0];

    assign final_cmd_addr      = mode_accel ? dmac_cmd_addr      : {wr_hyperram_reg0[15:0], wr_hyperram_reg1};
    assign final_start         = mode_accel ? dmac_start         : wr_hyperram_reg3[10];
    
    assign final_burst_len     = mode_accel ? dmac_burst_len     : wr_hyperram_reg2[ 7: 0];  // 8 bit
    assign final_latency       = mode_accel ? dmac_latency       : wr_hyperram_reg2[11: 8];  // 4 bit
    assign final_recovery      = mode_accel ? dmac_recovery      : wr_hyperram_reg2[15:12];  // 4 bit
    assign final_capture_shmoo = mode_accel ? dmac_capture_shmoo : wr_hyperram_reg2[17:16];  // 2 bit;

    // Give ready signal back to DMAC only if Accel mode is enabled
    assign dmac_start_rdy      = mode_accel ? master_start_rdy   : 1'b0;
    assign dmac_wr_read_fifo   = mode_accel ? wr_read_fifo       : 1'b0;


    // ========================================================
    // KHAI BÁO DÂY TRUNG GIAN NỐI VỚI HYPERBUS MASTER
    // ========================================================
    wire                          hb_m_tvalid;
    wire                          hb_m_tready;
    wire  [DATA_WIDTH_BYTE*8-1:0] hb_m_tdata;
    wire  [DATA_WIDTH_BYTE-1:0]   hb_m_tstrb;
    wire  [DATA_WIDTH_BYTE-1:0]   hb_m_tkeep;
    wire                          hb_m_tlast;
    wire                          hb_m_tid;

    wire                          hb_s_tvalid;
    wire                          hb_s_tready;
    wire  [DATA_WIDTH_BYTE*8-1:0] hb_s_tdata;
    wire  [DATA_WIDTH_BYTE-1:0]   hb_s_tstrb;
    wire  [DATA_WIDTH_BYTE-1:0]   hb_s_tkeep;
    wire                          hb_s_tlast;

    // ========================================================
    // GENERATE BLOCK: ĐỊNH TUYẾN DỮ LIỆU DỰA VÀO CHẾ ĐỘ
    // ========================================================
    generate
        if (MODE_2READ_ENB == 1) begin : gen_2read_mode
            // --- CHẾ ĐỘ 2 READ ---
            // 1. Tắt port Slave đi vào Hyperbus vì không dùng Write
            assign hb_s_tvalid = 1'b0;
            assign hb_s_tdata  = 0;
            assign hb_s_tstrb  = 0;
            assign hb_s_tkeep  = 0;
            assign hb_s_tlast  = 1'b0;
            assign s_tready_o  = 1'b0; // Báo Accel là cổng Write đang không khả dụng

            // 2. Gọi Decoder để chia cổng Read từ Hyperbus ra làm 2 Master Port
            decoder_1to2_axis_interface #(
                .DATA_WIDTH_BYTE(DATA_WIDTH_BYTE)
            ) axis_demux (
                // Input từ Hyperbus Master FIFO
                .m_tvalid_i (hb_m_tvalid),
                .m_tready_o (hb_m_tready),
                .m_tdata_i  (hb_m_tdata),
                .m_tstrb_i  (hb_m_tstrb),
                .m_tkeep_i  (hb_m_tkeep),
                .m_tlast_i  (hb_m_tlast),
                .m_tid_i    (hb_m_tid),

                // Output 0 -> Master Port 0
                .s_tvalid0_o(m_tvalid_o),
                .s_tready0_i(m_tready_i),
                .s_tdata0_o (m_tdata_o),
                .s_tstrb0_o (m_tstrb_o),
                .s_tkeep0_o (m_tkeep_o),
                .s_tlast0_o (m_tlast_o),

                // Output 1 -> Master Port 1
                .s_tvalid1_o(m1_tvalid_o),
                .s_tready1_i(m1_tready_i),
                .s_tdata1_o (m1_tdata_o),
                .s_tstrb1_o (m1_tstrb_o),
                .s_tkeep1_o (m1_tkeep_o),
                .s_tlast1_o (m1_tlast_o)
            );
            assign m_tid_o = 1'b0; // Không cần thiết nữa vì đã tách luồng
        end 
        else begin : gen_1r1w_mode
            // --- CHẾ ĐỘ 1 READ 1 WRITE (LOGIC CŨ) ---
            // 1. Nối thẳng cổng Master từ Hyperbus ra Port M0
            assign m_tvalid_o  = hb_m_tvalid;
            assign hb_m_tready = m_tready_i;
            assign m_tdata_o   = hb_m_tdata;
            assign m_tstrb_o   = hb_m_tstrb;
            assign m_tkeep_o   = hb_m_tkeep;
            assign m_tlast_o   = hb_m_tlast;
            assign m_tid_o     = hb_m_tid;

            // 2. Nối thẳng cổng Slave S0 vào Hyperbus
            assign hb_s_tvalid = s_tvalid_i;
            assign s_tready_o  = hb_s_tready;
            assign hb_s_tdata  = s_tdata_i;
            assign hb_s_tstrb  = s_tstrb_i;
            assign hb_s_tkeep  = s_tkeep_i;
            assign hb_s_tlast  = s_tlast_i;

            // 3. Tắt cổng Master 1 (Không sử dụng)
            assign m1_tvalid_o = 1'b0;
            assign m1_tdata_o  = 0;
            assign m1_tstrb_o  = 0;
            assign m1_tkeep_o  = 0;
            assign m1_tlast_o  = 1'b0;
        end
    endgenerate

    // ========================================================
    // MODULE: DMAC (Accelerator Command Generator)
    // ========================================================
    dmac_peri2accel #(
        .NUM_MASTERS        (2),
        .ADDR_WIDTH         (ADDR_WIDTH_DMAC),
        .BURST_WIDTH        (BURST_WIDTH),
        .BURST_SELECT_WIDTH (BURST_WIDTH),
        .MODE_2READ_ENB     (MODE_2READ_ENB),
        .SHMOOD_SELECT      (SHMOOD_SELECT),
        .SIM_ENB            (SIM_ENB)
    ) coordinator_center_dmac (
        .clk_i              (clk),
        .resetn_i           (resetn),
        
        .start_o            (dmac_start),
        .start_ready_i      (dmac_start_rdy),
        .cmd_addr_o         (dmac_cmd_addr),
        .burst_len_o        (dmac_burst_len),
        .latency_o          (dmac_latency),
        .recovery_o         (dmac_recovery),
        .capture_shmoo_o    (dmac_capture_shmoo),
        
        .wr_read_fifo_i     (dmac_wr_read_fifo),
        .tlast_read_fifo_o  (tlast_read_fifo),
        .read_ch_id_o       (tid_read_fifo),
        .tlast_write_fifo_i (tlast_write_fifo),
        
        .AWVALID_i          (AWVALID_i),
        .AWREADY_o          (AWREADY_o),
        .AWADDR_i           (AWADDR_i),
        .AWBURST_i          (AWBURST_i),
        .ARVALID_i          (ARVALID_i),
        .ARREADY_o          (ARREADY_o),
        .ARADDR_i           (ARADDR_i),
        .ARBURST_i          (ARBURST_i),
        .weight_write_channel_i     (wr_hyperram_reg5[16:2]),   // Example weight for write channel
        .weight_read_channel_i      (wr_hyperram_reg5[31:17])    // Example weight for read channel
    );

    // ========================================================
    // MODULE: HYPERBUS MASTER (4-Port Multiplexed Core)
    // ========================================================
    hyperbus_master #(
        .W_BURSTLEN         (8),
        .ADDR_WIDTH_FIFO    (10),
        .DATA_WIDTH_FIFO    (8),
        .DATA_WIDTH_BYTE    (DATA_WIDTH_BYTE),
        .SETUP_PORTS        (SETUP_PORTS)
    ) u_hyperbus_master (
        // System Config
        .clk                (clk),               
        .rst_n              (resetn),             
        .mode_sel           (mode_accel),  // Passed from register 5

        // Shared Control Signals
        .cmd_addr           (final_cmd_addr),          
        .start              (final_start),             
        .start_rdy          (master_start_rdy),         
        .burst_len          (final_burst_len),         
        .latency            (final_latency),           
        .recovery           (final_recovery),          
        .capture_shmoo      (final_capture_shmoo),     

        // CPU Port (Basic FIFO) - Connected to Registers
        .wdata_cpu_i        (wr_hyperram_reg3[7:0]),
        .wr_cpu_i           (wr_hyperram_reg3[8]),
        .full_cpu_o         (cpu_full),
        
        .rdata_cpu_o        (cpu_rdata),
        .rd_cpu_i           (wr_hyperram_reg3[9]),
        .empty_cpu_o        (cpu_empty),

        // Accel Port (AXI-STREAM Master)
        // .m_tvalid_o         (m_tvalid_o),        
        // .m_tready_i         (m_tready_i),        
        // .m_tdata_o          (m_tdata_o),         
        // .m_tstrb_o          (m_tstrb_o),         
        // .m_tkeep_o          (m_tkeep_o),         
        // .m_tlast_o          (m_tlast_o),

        .m_tvalid_o         (hb_m_tvalid),        
        .m_tready_i         (hb_m_tready),        
        .m_tdata_o          (hb_m_tdata),         
        .m_tstrb_o          (hb_m_tstrb),         
        .m_tkeep_o          (hb_m_tkeep),         
        .m_tlast_o          (hb_m_tlast),
        .m_tid_o            (hb_m_tid),        

        // Accel Port (AXI-STREAM Slave)
        // .s_tvalid_i         (s_tvalid_i),        
        // .s_tready_o         (s_tready_o),        
        // .s_tdata_i          (s_tdata_i),         
        // .s_tstrb_i          (s_tstrb_i),         
        // .s_tkeep_i          (s_tkeep_i),         
        // .s_tlast_i          (s_tlast_i),

        .s_tvalid_i         (hb_s_tvalid),        
        .s_tready_o         (hb_s_tready),        
        .s_tdata_i          (hb_s_tdata),         
        .s_tstrb_i          (hb_s_tstrb),         
        .s_tkeep_i          (hb_s_tkeep),         
        .s_tlast_i          (hb_s_tlast),        

        // Physical HyperBus Interface
        .dq_io              (dq_io),             
        .rwds_io            (rwds_io),           
        .hclk_p             (hclk_p),            
        .hclk_n             (hclk_n),            
        .cs_n               (cs_n),              

        // Internal Status FIFO (Connected between DMAC & Core)
        .wr_read_fifo_o     (wr_read_fifo),    
        .tlast_read_fifo_i  (tlast_read_fifo),
        .tid_read_fifo_i    (tid_read_fifo),     
        .tlast_write_fifo_o (tlast_write_fifo) 
    );

    // ========================================================
    // MODULE: AXI-LITE SLAVE INTERFACE
    // ========================================================
    axi_lite_slave_interface #(
        .ADDR_WIDTH         (ADDR_WIDTH),
        .DATA_WIDTH         (DATA_WIDTH),
        .TRANS_W_STRB_W     (TRANS_W_STRB_W),
        .TRANS_WR_RESP_W    (TRANS_WR_RESP_W),
        .TRANS_PROT         (TRANS_PROT),
        .CYCLE_CLOCK        (CYCLE_CLOCK),
        .NUM_MASTERS        (NUM_MASTERS)
    ) hyperram_axi_lite_interface (
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

        .o_wen              (),       
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





module hyperbus_master #(
    parameter W_BURSTLEN      = 8,
    parameter ADDR_WIDTH_FIFO = 8,
    parameter DATA_WIDTH_FIFO = 8,
    parameter DATA_WIDTH_BYTE = 1,
    parameter SETUP_PORTS     = 0
)(
    // ========================================================
    // 1. SYSTEM SIGNALS
    // ========================================================
    input                           clk,
    input                           rst_n,
    input                           mode_sel,       // 0: CPU Mode (FIFO) | 1: Accel Mode (AXI-Stream)

    // ========================================================
    // 2. HYPERBUS CONTROL CONFIGURATION
    // ========================================================
    input   [47:0]                  cmd_addr,
    input                           start,
    output                          start_rdy,
    input   [W_BURSTLEN-1:0]        burst_len,
    input   [3:0]                   latency,
    input   [3:0]                   recovery,
    input   [1:0]                   capture_shmoo,

    // ========================================================
    // 3. CPU PORT (BASIC FIFO INTERFACE)
    // ========================================================
    // --- CPU Write Port ---
    input   [7:0]                   wdata_cpu_i,    // CPU write data
    input                           wr_cpu_i,       // CPU write pulse (level)
    output                          full_cpu_o,     // FIFO full status for CPU
    
    // --- CPU Read Port ---
    output  [7:0]                   rdata_cpu_o,    // CPU read data
    input                           rd_cpu_i,       // CPU read pulse (level)
    output                          empty_cpu_o,    // FIFO empty status for CPU

    // ========================================================
    // 4. ACCEL PORT (AXI-STREAM INTERFACE)
    // ========================================================
    // --- AXIS Master Port (Read data out for Accel) ---
    output                          m_tvalid_o,
    input                           m_tready_i,
    output  [DATA_WIDTH_BYTE*8-1:0] m_tdata_o,
    output  [DATA_WIDTH_BYTE-1:0]   m_tstrb_o,
    output  [DATA_WIDTH_BYTE-1:0]   m_tkeep_o,
    output                          m_tlast_o,
    output                          m_tid_o,

    // --- AXIS Slave Port (Write data in from Accel) ---
    input                           s_tvalid_i,
    output                          s_tready_o,
    input   [DATA_WIDTH_BYTE*8-1:0] s_tdata_i,
    input   [DATA_WIDTH_BYTE-1:0]   s_tstrb_i,
    input   [DATA_WIDTH_BYTE-1:0]   s_tkeep_i,
    input                           s_tlast_i,

    // ========================================================
    // 5. EXTERNAL HYPERBUS PHYSICAL PINS & FIFO STATUS
    // ========================================================
    inout   [7:0]                   dq_io,
    inout                           rwds_io,
    output                          hclk_p,
    output                          hclk_n,
    output                          cs_n,
    
    output                          wr_read_fifo_o,
    input                           tlast_read_fifo_i,
    input                           tid_read_fifo_i,
    output                          tlast_write_fifo_o
);

    // ========================================================
    // INTERNAL SIGNALS DECLARATION (NO DIRECT ASSIGNMENT)
    // ========================================================
    // HyperBus Tristate buffers
    wire [7:0]                      dq_i, dq_o, dq_oe;
    wire                            rwds_i, rwds_o, rwds_oe;

    // Interface Core Data Paths
    wire [7:0]                      wdata;
    wire                            wdata_rdy; 
    wire [7:0]                      rdata;
    wire                            rdata_vld; 

    // Edge Detectors for CPU pulses
    wire                            edge_wr;
    wire                            edge_rd;
    wire                            edge_start;

    // AXIS FIFO Internal Links
    wire                            internal_s_tready;
    wire                            internal_m_tvalid;
    wire [7:0]                      internal_m_tdata;

    // Intermediate MUX signals
    wire                            mux_start;
    wire                            mux_s_tvalid;
    wire [7:0]                      mux_s_tdata;
    wire [DATA_WIDTH_BYTE-1:0]      mux_s_tstrb;
    wire [DATA_WIDTH_BYTE-1:0]      mux_s_tkeep;
    wire                            mux_s_tlast;
    wire                            mux_m_tready;
    wire                            fifo_m_tlast_in;

    wire                            full_cpu;
    wire                            empty_cpu;

    // ========================================================
    // ASSIGNMENTS AND MUX LOGIC
    // ========================================================
    
    // Tristate Buffer Assignments
    assign dq_io   = dq_oe   ? dq_o   : 8'bz;
    assign dq_i    = dq_io;                
    assign rwds_io = rwds_oe ? rwds_o : 1'bz; 
    assign rwds_i  = rwds_io;

    // 1. Start Control MUX
    assign mux_start    = mode_sel ? start      : edge_start;

    // 2. WRITE Path: Routing to AXI-Stream Slave FIFO
    assign mux_s_tvalid = mode_sel ? s_tvalid_i : edge_wr;
    assign mux_s_tdata  = mode_sel ? s_tdata_i  : wdata_cpu_i;
    assign mux_s_tstrb  = mode_sel ? s_tstrb_i  : {DATA_WIDTH_BYTE{1'b1}};
    assign mux_s_tkeep  = mode_sel ? s_tkeep_i  : {DATA_WIDTH_BYTE{1'b1}};
    assign mux_s_tlast  = mode_sel ? s_tlast_i  : 1'b0;

    assign s_tready_o   = mode_sel ? internal_s_tready : 1'b0;
    assign full_cpu_o   = mode_sel ? 1'b1              : full_cpu;

    // 3. READ Path: Fetching from AXI-Stream Master FIFO
    assign mux_m_tready = mode_sel ? m_tready_i : edge_rd;

    assign m_tvalid_o   = mode_sel ? internal_m_tvalid : 1'b0;
    assign m_tdata_o    = internal_m_tdata;
    
    assign empty_cpu_o  = mode_sel ? 1'b1              : empty_cpu;
    assign rdata_cpu_o  = internal_m_tdata;
    assign fifo_m_tlast_in = mode_sel ? tlast_read_fifo_i : 1'b0;
    
    assign wr_read_fifo_o = rdata_vld;

    // ========================================================
    // CPU PULSE CONVERSION (LEVEL TO EDGE)
    // ========================================================
    edge_detector_hyperbus edge_start_unit (
        .clk        (clk), 
        .reset_n    (rst_n), 
        .level_edge (start), 
        .p_edge     (edge_start), 
        .n_edge     (), 
        .any_edge   ()
    );

    edge_detector_hyperbus edge_wdata_unit (
        .clk        (clk), 
        .reset_n    (rst_n), 
        .level_edge (wr_cpu_i), 
        .p_edge     (edge_wr), 
        .n_edge     (), 
        .any_edge   ()
    );

    edge_detector_hyperbus edge_rdata_unit (
        .clk        (clk), 
        .reset_n    (rst_n), 
        .level_edge (rd_cpu_i), 
        .p_edge     (edge_rd), 
        .n_edge     (), 
        .any_edge   ()
    );

    // ========================================================
    // PHYSICAL MODULES INSTANTIATION
    // ========================================================
    
    // --- HYPERBUS CONTROL CORE ---
    hyperbus_interface #(
        .W_BURSTLEN     (W_BURSTLEN),
        .SETUP_PORTS    (SETUP_PORTS)
    ) dut (
        .clk            (clk), 
        .rst_n          (rst_n),
        .cmd_addr       (cmd_addr), 
        .start          (mux_start), 
        .start_rdy      (start_rdy),
        .burst_len      (burst_len), 
        .latency        (latency), 
        .recovery       (recovery), 
        .capture_shmoo  (capture_shmoo),
        
        .wdata          (wdata), 
        .wdata_rdy      (wdata_rdy),
        .rdata          (rdata), 
        .rdata_vld      (rdata_vld),
        
        .dq_i           (dq_i), 
        .dq_o           (dq_o), 
        .dq_oe          (dq_oe),
        .rwds_i         (rwds_i), 
        .rwds_o         (rwds_o), 
        .rwds_oe        (rwds_oe),
        .hclk_p         (hclk_p), 
        .hclk_n         (hclk_n), 
        .cs_n           (cs_n)
    );

    // --- READ FIFO CORE (AXI-Stream Master) ---
    axi4_stream #(
        .DATA_WIDTH_BYTE  (DATA_WIDTH_BYTE), 
        .SELECT_INTERFACE (0), 
        .SIZE_FIFO        (ADDR_WIDTH_FIFO)
    ) fifo_m (
        .aclk_i           (clk), 
        .aresetn_i        (rst_n), 
        
        // Output Ports
        .m_tvalid_o       (internal_m_tvalid), 
        .m_tready_i       (mux_m_tready), 
        .m_tdata_o        (internal_m_tdata), 
        .m_tstrb_o        (m_tstrb_o), 
        .m_tkeep_o        (m_tkeep_o), 
        .m_tlast_o        (m_tlast_o),
        .m_tid_o          (m_tid_o),
        
        // Input Ports from Hyperbus Interface
        .user_m_empty_o   (empty_cpu),
        .user_m_wr_data_i (rdata_vld), 
        .user_m_data_i    (rdata), 
        .user_m_tstrb_i   ({DATA_WIDTH_BYTE{1'b1}}), 
        .user_m_tkeep_i   ({DATA_WIDTH_BYTE{1'b1}}), 
        .user_m_tlast_i   (fifo_m_tlast_in),
        .user_m_tid_i     (tid_read_fifo_i),
        
        // Unused Ports
        .user_m_busy_o    (), 
        .s_tready_o       (), 
        .user_s_ready_o   (), 
        .user_s_data_o    ()
    );     

    // --- WRITE FIFO CORE (AXI-Stream Slave) ---
    axi4_stream #(
        .DATA_WIDTH_BYTE  (DATA_WIDTH_BYTE), 
        .SELECT_INTERFACE (1), 
        .SIZE_FIFO        (ADDR_WIDTH_FIFO)
    ) fifo_s (
        .aclk_i           (clk), 
        .aresetn_i        (rst_n), 
        
        // Input Ports
        .s_tvalid_i       (mux_s_tvalid), 
        .s_tready_o       (internal_s_tready), 
        .s_tdata_i        (mux_s_tdata), 
        .s_tstrb_i        (mux_s_tstrb), 
        .s_tkeep_i        (mux_s_tkeep), 
        .s_tlast_i        (mux_s_tlast), 
        
        // Output Ports to Hyperbus Interface
        .user_s_full_o    (full_cpu),
        .user_s_rd_data_i (wdata_rdy), 
        .user_s_data_o    (wdata), 
        .user_s_tlast_o   (tlast_write_fifo_o), 
        
        // Unused Ports
        .user_s_ready_o   (), 
        .user_s_tstrb_o   (), 
        .user_s_tkeep_o   (), 
        .m_tvalid_o       (), 
        .user_m_busy_o    ()
    );

endmodule






// Encapsulates all the timing details of the HyperBus interface
// Contains some half-cycle paths, but these should all be register-register
// (or at most a couple of muxes)

// HyperBus is a DDR interface. Each transaction consists of:
// - CSn assertion while clock is idle (low)
// - A 48 bit command and address (CA) sequence, clocked out on 6 edges
// - An access latency period. Latency clock count is configured via config register in the HRAM,
//   and latency is doubled if a RAM refresh operation is in progress, which is signalled by RWDS
//   high during CA phase.
// - A read/write data burst transferring one byte per clock edge, even number of bytes total.
// - CSn deassertion while clock idle, to terminate the burst
// - A short recovery period before reasserting CSn
//
// HCLK need not be free-running.
// 
// During write data bursts, RWDS functions as a byte masking signal, allowing
// individual bytes on a DRAM row to be updated without R-M-W sequence. We don't use this.
// 
// CA, write data, and RWDS (during write bursts) should be centre-clocked by the HCLK signal,
// so that the slave capture is aligned with the signal eye.
// 
// CSn ¬¬¬____________________________________¬¬¬¬
// CLK __________¬¬¬¬¬¬¬¬________¬¬¬¬¬¬¬¬_________
// DQ  ------<  A   ><  B   ><  C   ><  D   >
//
//
// During read data bursts, RWDS is used as a source-synchronous DDR strobe, aligned
// with DQ transitions. Some RAMs also have a secondary clock input which allows
// RWDS to be skewed to align it with the DQ eye. As we are only aiming for low speed operation,
// we will simply capture DQ on our transmitted clock. TODO: some shmooing on the capture?
//
// For register accesses, there is no latency period: CA is followed immediately by a 16-bit register value.
// The entire access occurs on 8 consecutive clock edges.


module hyperbus_interface #(
	parameter W_BURSTLEN = 5,
    parameter SETUP_PORTS = 0
) (
	input wire                   clk,
	input wire                   rst_n,

	// Control

	input  wire [47:0]           cmd_addr,      // Full contents of the hyperbus CA packet
	input  wire                  start,         // Start a new DRAM/register access sequence
	output wire                  start_rdy,     // Interface is ready to start a sequence
	input  wire [W_BURSTLEN-1:0] burst_len,     // Number of halfwords to transfer (double number of bytes)
	input  wire [3:0]            latency,       // Number of clocks between CA[23:16] being transferred, and first read/write data. Doubled if RWDS high during CA. >= 2
	input  wire [3:0]            recovery,      // Number of clocks to wait 
	input  wire [1:0]            capture_shmoo, // Capture DQi at 0, 180 or 360 clk degrees (0 90 180 HCLK degrees) after the DDR HCLK
	                                            // edge which causes it to transition to *next* data. 0 degrees probably correct for almost all speeds.
	                                            // 2 -> 0 degrees
	                                            // 1 -> 180 degrees
	                                            // 0 -> 360 degrees

	// Data

	input  wire [7:0]            wdata,
	output wire                  wdata_rdy, // Backpressure only. Host must always provide valid data during a write transaction
	output wire [7:0]            rdata,
	output wire                  rdata_vld, // Forward pressure only. Host must always accept data it has previously requested

	// HyperBus

	input  wire [7:0]            dq_i,
	output wire [7:0]            dq_o,
	output wire [7:0]            dq_oe,

	input  wire                  rwds_i,
	output wire                  rwds_o,
	output wire                  rwds_oe,

	output  reg                  hclk_p,  // For 3V RAMs, just use the single-ended (positive) clock
	output  reg                  hclk_n,

	output  reg                  cs_n
);

// ----------------------------------------------------------------------------
// Hyperbus state machine

localparam W_STATE = 4;

localparam S_IDLE     = 4'd0; // Ready to start a new sequence
localparam S_SETUP0   = 4'd1; // Asserting CS and first CA byte
localparam S_SETUP1   = 4'd2; // Nhịp chờ 2 (thêm 5ns)
localparam S_SETUP2   = 4'd3; // Nhịp chờ 2 (thêm 5ns)
localparam S_CA       = 4'd4; // Driving clock and shifting CA packet
localparam S_LATENCY  = 4'd5; // Driving clock until access latency elapses
localparam S_RBURST   = 4'd6; // Driving clock and capturing read data
localparam S_WBURST   = 4'd7; // Driving clock and write data
localparam S_RECOVERY = 4'd8; // Hold CS high a while before accepting new command
localparam S_WAIT_END = 4'd9; // Nhịp chờ 2 (thêm 5ns)

reg [W_STATE-1:0] bus_state_next; // combinatorial
reg [W_STATE-1:0] bus_state;
reg [W_STATE-1:0] bus_state_prev;

always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		bus_state <= S_IDLE;
		bus_state_prev <= S_IDLE;
	end else begin
		bus_state <= bus_state_next;
		bus_state_prev <= bus_state;
	end
end

// Some useful housekeeping values

reg [W_BURSTLEN-1:0] cycle_ctr;

reg latency_2x; // RWDS sample taken during CA phase (2 clocks in seems ok)
always @ (posedge clk or negedge rst_n)
	if (!rst_n)
		latency_2x <= 1'b0;
	else if (bus_state == S_CA && cycle_ctr == 5'h3 && hclk_p) //5'h3
		latency_2x <= rwds_i;

reg is_reg_write;
always @ (posedge clk or negedge rst_n)
	if (!rst_n)
		is_reg_write <= 1'b0;
	else if (start_rdy)
		is_reg_write <= start && cmd_addr[47:46] == 2'b01;

reg is_write;
always @ (posedge clk or negedge rst_n)
	if (!rst_n)
		is_write <= 1'b0;
	else if (start && start_rdy)
		is_write <= !cmd_addr[47];

// Counter logic

// - 1 because the count starts after row address (1 hclk before end of CA)
wire [W_BURSTLEN-1:0] latency_after_ca;
assign latency_after_ca = (latency << latency_2x) - 5'h1;

// Ép lệnh GHI luôn dùng độ trễ tiêu chuẩn (1x), chỉ lệnh ĐỌC mới phụ thuộc vào latency_2x\
// assign latency_after_ca = is_write ? (latency - 5'h1) : ((latency << latency_2x) - 5'h1);

always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		cycle_ctr <= {W_BURSTLEN{1'b0}};
	end else begin
		// if (bus_state == S_IDLE && bus_state_next == S_CA) begin
		// 	cycle_ctr <= 5'h3;
        if (bus_state == S_SETUP2 && bus_state_next == S_CA) begin
			cycle_ctr <= 5'h3;
		end else if (bus_state == S_CA && bus_state_next == S_LATENCY) begin
			cycle_ctr <= latency_after_ca;
			// Note that for low latency settings (2 cycles) we go straight from CA to burst if RWDS was low:
		end else if ((bus_state == S_CA || bus_state == S_LATENCY) && (bus_state_next == S_RBURST || bus_state_next == S_WBURST)) begin
			cycle_ctr <= is_reg_write ? 1 : burst_len;
		end else if (hclk_p) begin
			// Counter transitions each time hclk returns to idle state (count full pulses, not DDR edges)
			cycle_ctr <= cycle_ctr - 1'b1;
		end
	end
end

// Main state transitions

wire final_edge = cycle_ctr == 5'h1 && hclk_p;

// always @ (*) begin
// 	bus_state_next = bus_state;
// 	case (bus_state)
// 	S_IDLE: begin
// 		if (start)
// 			bus_state_next = S_CA;
// 	end
// 	S_CA: begin
// 		if (final_edge) begin
// 			if (|latency_after_ca && !is_reg_write)
// 				bus_state_next = S_LATENCY;
// 			else
// 				bus_state_next = is_write ? S_WBURST : S_RBURST;
// 		end
// 	end
// 	S_LATENCY: begin
// 		if (final_edge)
// 			bus_state_next = is_write ? S_WBURST : S_RBURST;
// 	end
// 	S_RBURST: begin
// 		if (final_edge)
// 			bus_state_next = S_RECOVERY;
// 	end
// 	S_WBURST: begin
// 		if (final_edge)
// 			bus_state_next = S_RECOVERY;
// 	end
// 	S_RECOVERY: begin
// 		bus_state_next = S_IDLE; //TODO add some way of controlling this length
// 	end

// 	endcase
// end


always @ (*) begin
	bus_state_next = bus_state;
	case (bus_state)
	S_IDLE: begin
		if (start)
		    bus_state_next = S_SETUP0;
	end
    S_SETUP0: begin
        bus_state_next = S_SETUP1;
    end
    S_SETUP1: begin
        bus_state_next = S_SETUP2;
    end
    S_SETUP2: begin
        bus_state_next = S_CA;        // Đứng chờ 1 chu kỳ (5ns) để dập chân CS# xuống
    end
	S_CA: begin
		if (final_edge) begin
			if (|latency_after_ca && !is_reg_write)
				bus_state_next = S_LATENCY;
			else
				bus_state_next = is_write ? S_WBURST : S_RBURST;
		end
	end
	S_LATENCY: begin
		if (final_edge)
			bus_state_next = is_write ? S_WBURST : S_RBURST;
	end
	S_RBURST: begin
		if (final_edge)
			bus_state_next = S_RECOVERY;
	end
	S_WBURST: begin
		if (final_edge)
			bus_state_next = S_RECOVERY;
	end
	S_RECOVERY: begin
		bus_state_next = S_WAIT_END; //TODO add some way of controlling this length
	end
    S_WAIT_END: begin
        bus_state_next = S_IDLE;
    end

	endcase
end

// ----------------------------------------------------------------------------
// Handle non-DQ bus signals

wire drive_clk =
	bus_state == S_CA      ||
	bus_state == S_LATENCY ||
	bus_state == S_WBURST  ||
	bus_state == S_RBURST  ;

always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		hclk_p <= 1'b0;
		hclk_n <= 1'b1;
	end else if (drive_clk) begin
		hclk_p <= hclk_n;
		hclk_n <= hclk_p;
	end
end

// Used as a byte strobe during writes. Except when:
//   36. The host must not drive RWDS during a write to register space.

reg rwds_assert;
always @ (posedge clk or negedge rst_n)
	if (!rst_n)
		rwds_assert <= 1'b0;
	else
		rwds_assert <= bus_state_next == S_WBURST && !is_reg_write;

reg rwds_assert_falling;
always @ (negedge clk or negedge rst_n)
	if (!rst_n)
		rwds_assert_falling <= 1'b0;
	else
		rwds_assert_falling <= rwds_assert;

// Active-LOW byte strobe
assign rwds_o = 1'b0;
assign rwds_oe = rwds_assert_falling;

always @ (posedge clk or negedge rst_n)
	if (!rst_n)
		cs_n <= 1'b1; // active high, deassert at reset
	else
		cs_n <= bus_state_next == S_IDLE || bus_state == S_RECOVERY;

// ----------------------------------------------------------------------------
// Launch/capture flops for DQ (half-clock retiming)

reg [7:0] dq_o_reg;
reg [7:0] dq_o_reg_falling;

// HCLK transitions align with posedge of clk.
// DQ outputs are eye-aligned, so we write bus data to dq_o_reg on the posedge 
// *before* the HCLK transition, and then register again via dq_o_reg_falling 
// to align transitions with clk negedge.

always @ (negedge clk or negedge rst_n)
	if (!rst_n)
		dq_o_reg_falling <= 8'h0;
	else
		dq_o_reg_falling <= dq_o_reg;


assign dq_o = dq_o_reg_falling;

// Drive period is aligned with assertion of write data
// i.e. we generate it one clk before the HCLK edge
// and then delay by half a clock

reg dq_oe_reg;
always @ (posedge clk or negedge rst_n)
	if (!rst_n)
		dq_oe_reg <= 1'b0;
	else
		dq_oe_reg <= bus_state_next == S_WBURST || bus_state_next == S_CA;

reg dq_oe_reg_falling;
always @ (negedge clk or negedge rst_n)
	if (!rst_n)
		dq_oe_reg_falling <= 1'b0;
	else
		dq_oe_reg_falling <= dq_oe_reg;

assign dq_oe = {8{dq_oe_reg_falling}};

// Read is going to need some diagrams :)

wire [7:0] dq_i_delay;

prog_halfclock_delay #(
	.MAX_DELAY(2),
	.FINAL_FALLING(1)
) dq_i_delay_line [7:0] (
	.clk (clk),
	.in  (dq_i),
	.sel (capture_shmoo),
	.out (dq_i_delay)
);

reg [7:0] dq_i_reg;
always @ (posedge clk or negedge rst_n)
	if (!rst_n)
		dq_i_reg <= 8'h0;
	else
		dq_i_reg <= dq_i_delay;

// ----------------------------------------------------------------------------
// Host interfaces


// The first byte of CA packet goes straight to bus. Rest is captured and shifted:
reg [39:0] ca_shift;
always @ (posedge clk or negedge rst_n)
	if (!rst_n)
		ca_shift <= 40'h0;  
	else if (bus_state_next == S_CA && bus_state != S_CA)
		ca_shift <= cmd_addr[39:0];
	else
		ca_shift <= ca_shift << 8;

// Recall that dq_o_reg is delayed by half a clk before appearing on bus,
// and is captured on the *following* HCLK transition.
always @ (posedge clk or negedge rst_n)
	if (!rst_n)
		dq_o_reg <= 8'h0;
	else if (bus_state_next == S_CA)
		dq_o_reg <= bus_state == S_CA ? ca_shift[39:32] : cmd_addr[47:40];
	else
		dq_o_reg <= wdata;

assign wdata_rdy = bus_state_next == S_WBURST;

///sim ////////////////////////////////////////////////////////////////////////////////////
// reg [1:0] rdata_vld_reg;
// always @ (posedge clk or negedge rst_n)
// 	if (!rst_n)
// 		rdata_vld_reg <= 2'b00;
// 	else
// 		rdata_vld_reg <= {rdata_vld_reg[0], bus_state_prev == S_RBURST};

// assign rdata_vld = rdata_vld_reg[1];

//real behavior //////////////////////////////////////////////////////////////////////////////////
// // Thay vì reg [1:0] rdata_vld_reg;
// reg [3:0] rdata_vld_reg;
// always @ (posedge clk or negedge rst_n) begin
//     if (!rst_n)
//         rdata_vld_reg <= 4'b0000;
//     else
//         // Đẩy bit dần từ [0] -> [1] -> [2] -> [3]
//         rdata_vld_reg <= {rdata_vld_reg[2:0], bus_state_prev == S_RBURST};
// end
// // Lấy tín hiệu ở đuôi thanh ghi dịch
// // assign rdata_vld = rdata_vld_reg[2];
// assign rdata_vld = (SETUP_PORTS == 1) ? rdata_vld_reg[2] : rdata_vld_reg[3];

`ifndef SYNTHESIS
    // =======================================================================
    // 1. MÔ PHỎNG (SIMULATION BEHAVIOR)
    // Chạy khi mô phỏng trên Vivado Simulator, ModelSim...
    // =======================================================================
    reg [1:0] rdata_vld_reg;
    always @ (posedge clk or negedge rst_n) begin
        if (!rst_n)
            rdata_vld_reg <= 2'b00;
        else
            rdata_vld_reg <= {rdata_vld_reg[0], bus_state_prev == S_RBURST};
    end
    
    assign rdata_vld = rdata_vld_reg[1];

`else
    // =======================================================================
    // 2. THỰC TẾ (REAL BEHAVIOR)
    // Chạy khi tổng hợp mạch (Synthesis) và Implementation xuống FPGA
    // Thiết kế thanh ghi dịch 3-bit để hoạt động ổn định trên phần cứng
    // =======================================================================
    reg [3:0] rdata_vld_reg;
    always @ (posedge clk or negedge rst_n) begin
        if (!rst_n)
            rdata_vld_reg <= 4'b0000;
        else
            // Đẩy bit dần từ [0] -> [1] -> [2] -> [3]
            rdata_vld_reg <= {rdata_vld_reg[2:0], bus_state_prev == S_RBURST};
    end
    // Lấy tín hiệu ở đuôi thanh ghi dịch
    // assign rdata_vld = rdata_vld_reg[2];
    assign rdata_vld = (SETUP_PORTS == 1) ? rdata_vld_reg[2] : rdata_vld_reg[3];

`endif


assign rdata = dq_i_reg;

assign start_rdy = bus_state == S_IDLE;


endmodule




// Alternating posedge/negedge register stages for *input* timing adjustment
//
// Mux sels are decoded from input select. At most one will be selecting the "in" net
// 
// in -+------+-------------+-------------+
//     |      |             |             |
//     |      +--|\         +--|\         +--|\     
//     |         | |           | |           | |    
//     |  +---+  | |-+  +---+  | |-+  +---+  | |---- out 
//     +--|D Q|--|/  +--|D Q|--|/  +--|D Q|--|/
//        |   |         |   |         |   |         
//        +-^-+         +-^-+         +-^-+         
//          o             |             o
//          |             |             |
// clk -----+-------------+-------------+
//
// Above is for a MAX_DELAY of 3

module prog_halfclock_delay #(
	parameter MAX_DELAY = 2,                // Number of register stages to insert
	parameter FINAL_FALLING = 1,          // If 1, final stage is falling edge
	parameter W_SEL = $clog2(MAX_DELAY + 1) // let this default
) (
	input wire clk,
	input wire in,
	input wire [W_SEL-1:0] sel,
	output wire out
);

(* keep = 1'b1 *) reg [MAX_DELAY-1:0] q;
                  reg [MAX_DELAY  :0] d;

// Insert bypass muxes
// Numbering is a bit odd: d[i] is the D *generated from* q[i]
// i.e. the input to the following flop

always @ (*) begin: bypass
	integer i;
	for (i = 0; i <= MAX_DELAY; i = i + 1) begin
		if (i == MAX_DELAY || sel == i)
			d[i] = in;
		else
			d[i] = q[i];
	end
end

genvar i;
generate
for (i = 0; i < MAX_DELAY; i = i + 1) begin: flops
	if (i[0] ^ |FINAL_FALLING) begin
		always @ (negedge clk)
			q[i] <= d[i + 1];
	end else begin
		always @ (posedge clk)
			q[i] <= d[i + 1];
	end
end
endgenerate

assign out = d[0];

endmodule



//module fifo
module fifo_hyperbus_unit #(parameter ADDR_WIDTH = 3, DATA_WIDTH = 8)(
    input clk, reset_n,
    input wr, rd,

    input [DATA_WIDTH - 1 : 0] w_data, //writing data
    output [DATA_WIDTH - 1 : 0] r_data, //reading data

    output full, empty

    );

    //signal
    wire [ADDR_WIDTH - 1 : 0] w_addr, r_addr;

    //instantiate registers file
    register_file_hyperbus #(.ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH))
        register_file_hyperbus_unit(
            .clk(clk),
            .w_en(~full & wr),

            .r_addr(r_addr), //reading address
            .w_addr(w_addr), //writing address

            .w_data(w_data), //writing data
            .r_data(r_data) //reading data
        
        );

    //instantiate fifo ctrl
    fifo_ctrl_hyperbus #(.ADDR_WIDTH(ADDR_WIDTH))
        fifo_ctrl_hyperbus_unit(
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


module fifo_ctrl_hyperbus #(parameter ADDR_WIDTH = 3)(
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

module register_file_hyperbus #(parameter ADDR_WIDTH = 3, DATA_WIDTH = 8)(
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


module edge_detector_hyperbus(
    input clk,
    input reset_n,
    input level_edge,
    
    output p_edge,
    output n_edge,
    output any_edge
    );
    
    //Edge detector mearly outputs
    
    reg state_reg, state_next;
    parameter S0 = 1'b0, S1 = 1'b1;
    
    //sequential state regs
    always @(posedge clk, negedge reset_n) begin
        if(~reset_n)
            state_reg <= S0;
        
        else
            state_reg <= state_next;
    end
    
    always @(*) begin
        case(state_reg)
            S0: begin
                if(level_edge)
                    state_next = S1;
                else
                    state_next = S0;
            end
            
            S1: begin
                if(level_edge)
                    state_next = S1;
                else
                    state_next = S0;
            end
            
            default: state_next = S0;   
        endcase
    end
    
    assign p_edge = (state_reg == S0) & level_edge;
    assign n_edge = (state_reg == S1) & ~level_edge;
    assign any_edge = p_edge | n_edge;
    
    
endmodule
