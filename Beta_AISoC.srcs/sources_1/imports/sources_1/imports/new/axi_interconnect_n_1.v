`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 07/24/2025 01:21:26 AM
// Design Name: 
// Module Name: axi_interconnect_n_1
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


module axi_interconnect_n_1#(
    // Transaction configuration
    parameter ADDR_WIDTH = 32,          // Address width
    parameter DATA_WIDTH = 32,          // Data width
    parameter TRANS_W_STRB_W = 4,       // width strobe
    parameter TRANS_WR_RESP_W = 2,      // width response
    parameter TRANS_PROT      = 3,
    parameter QUANTUM_TIME = 16,

    // Interconnect configuration
    parameter NUM_MASTERS = 16,         // Number of masters
    parameter NUM_SLAVES  = 16,         // Number of slaves
    parameter [NUM_MASTERS*NUM_MASTERS-1:0] ID_MASTERS_MAPS = {
        // Master 15: bit 15 = 1, others = 0
        { 1'b1, {(NUM_MASTERS-1){1'b0}} },
        // Master 14: bit 14 = 1, others = 0
        { {(NUM_MASTERS-15){1'b0}}, 1'b1, {14{1'b0}} },
        // Master 13: bit 13 = 1, others = 0
        { {(NUM_MASTERS-14){1'b0}}, 1'b1, {13{1'b0}} },
        // Master 12: bit 12 = 1, others = 0
        { {(NUM_MASTERS-13){1'b0}}, 1'b1, {12{1'b0}} },
        // Master 11: bit 11 = 1, others = 0
        { {(NUM_MASTERS-12){1'b0}}, 1'b1, {11{1'b0}} },
        // Master 10: bit 10 = 1, others = 0
        { {(NUM_MASTERS-11){1'b0}}, 1'b1, {10{1'b0}} },
        // Master 9: bit 9 = 1, others = 0
        { {(NUM_MASTERS-10){1'b0}}, 1'b1, {9{1'b0}} },
        // Master 8: bit 8 = 1, others = 0
        { {(NUM_MASTERS-9){1'b0}}, 1'b1, {8{1'b0}} },
        // Master 7: bit 7 = 1, others = 0
        { {(NUM_MASTERS-8){1'b0}}, 1'b1, {7{1'b0}} },
        // Master 6: bit 6 = 1, others = 0
        { {(NUM_MASTERS-7){1'b0}}, 1'b1, {6{1'b0}} },
        // Master 5: bit 5 = 1, others = 0
        { {(NUM_MASTERS-6){1'b0}}, 1'b1, {5{1'b0}} },
        // Master 4: bit 4 = 1, others = 0
        { {(NUM_MASTERS-5){1'b0}}, 1'b1, {4{1'b0}} },
        // Master 3: bit 3 = 1, others = 0
        { {(NUM_MASTERS-4){1'b0}}, 1'b1, {3{1'b0}} },
        // Master 2: bit 2 = 1, others = 0
        { {(NUM_MASTERS-3){1'b0}}, 1'b1, {2{1'b0}} },
        // Master 1: bit 1 = 1, others = 0
        { {(NUM_MASTERS-2){1'b0}}, 1'b1, {1{1'b0}} },
        // Master 0: bit 0 = 1, others = 0
        { {(NUM_MASTERS-1){1'b0}}, 1'b1 }
    }
)(

    // MULTIPLE MASTER PORT
    input                                            m_axi_aclk_i,
    input                                            m_axi_aresetn_i, 

    // master AW Channel
    input   [ADDR_WIDTH*NUM_MASTERS-1:0]             m_axi_awaddr_i,
    input   [NUM_MASTERS-1:0]                        m_axi_awvalid_i,
    output  [NUM_MASTERS-1:0]                        m_axi_awready_o,
    input   [NUM_MASTERS*TRANS_PROT-1:0]             m_axi_awprot_i,

    // master W Channel
    input   [DATA_WIDTH*NUM_MASTERS-1:0]             m_axi_wdata_i,
    input   [TRANS_W_STRB_W*NUM_MASTERS-1:0]         m_axi_wstrb_i,
    input   [NUM_MASTERS-1:0]                        m_axi_wvalid_i,
    output  [NUM_MASTERS-1:0]                        m_axi_wready_o,

    // master B Channel
    output  [TRANS_WR_RESP_W*NUM_MASTERS-1:0]        m_axi_bresp_o,
    output  [NUM_MASTERS-1:0]                        m_axi_bvalid_o,
    input   [NUM_MASTERS-1:0]                        m_axi_bready_i,

    // master AR Channel
    input   [ADDR_WIDTH*NUM_MASTERS-1:0]             m_axi_araddr_i,
    input   [NUM_MASTERS-1:0]                        m_axi_arvalid_i,
    output  [NUM_MASTERS-1:0]                        m_axi_arready_o,
    input   [NUM_MASTERS*TRANS_PROT-1:0]             m_axi_arprot_i,

    // master R Channel
    output  [DATA_WIDTH*NUM_MASTERS-1:0]             m_axi_rdata_o,
    output  [TRANS_WR_RESP_W*NUM_MASTERS-1:0]        m_axi_rresp_o,
    output  [NUM_MASTERS-1:0]                        m_axi_rvalid_o,
    input   [NUM_MASTERS-1:0]                        m_axi_rready_i,


    // ONE SLAVES PORT
    // slave AW Channel
    output  [ADDR_WIDTH-1:0]                        s_axi_awaddr_o,
    output                                          s_axi_awvalid_o,
    input                                           s_axi_awready_i,
    output  [TRANS_PROT-1:0]                        s_axi_awprot_o,
    
    // slave W Channel
    output  [DATA_WIDTH-1:0]                        s_axi_wdata_o,
    output  [TRANS_W_STRB_W-1:0]                    s_axi_wstrb_o,
    output                                          s_axi_wvalid_o,
    input                                           s_axi_wready_i,

    // slave B Channel
    input   [TRANS_WR_RESP_W-1:0]                   s_axi_bresp_i,
    input                                           s_axi_bvalid_i,
    output                                          s_axi_bready_o,

    // slave AR Channel
    output  [ADDR_WIDTH-1:0]                        s_axi_araddr_o,
    output                                          s_axi_arvalid_o,
    input                                           s_axi_arready_i,
    output  [TRANS_PROT-1:0]                        s_axi_arprot_o,

    // slave R Channel
    input   [DATA_WIDTH-1:0]                        s_axi_rdata_i,
    input   [TRANS_WR_RESP_W-1:0]                   s_axi_rresp_i,
    input                                           s_axi_rvalid_i,
    output                                          s_axi_rready_o,

    output                                          grant_permission_W_W_o,
    output                                          grant_permission_B_W_o,
    output                                          grant_permission_R_R_o  

    );

    localparam ADDR_WIDTH_FIFO = $clog2(NUM_MASTERS)+1;
    localparam DATA_WIDTH_FIFO = NUM_MASTERS;

    wire                            full_fifo_AW_W, empty_fifo_AW_W, full_fifo_W_B, empty_fifo_W_B;
    wire                            full_fifo_AR_R, empty_fifo_AR_R;
    wire [NUM_MASTERS-1:0]          master_id_AW_W_write, master_id_AW_W_read, master_id_W_B_write, master_id_W_B_read;
    wire [NUM_MASTERS-1:0]          master_id_AR_R_write, master_id_AR_R_read;
    wire                            grant_permission_AW_W, grant_permission_W_W, grant_permission_B_W;  
    wire                            grant_permission_AR_R, grant_permission_R_R;   


    /////////////////////////////////WRITE TRANSACTION///////////////////////////
    /// AW CHANNEL
    AW_arbiter_m #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .TRANS_PROT(TRANS_PROT),
        .NUM_MASTERS(NUM_MASTERS),
        .ID_MASTERS_MAPS(ID_MASTERS_MAPS)
    ) AW_arbiter_master (
        .m_axi_aresetn_i(m_axi_aresetn_i),
        .m_axi_awaddr_i(m_axi_awaddr_i),
        .m_axi_awvalid_i(m_axi_awvalid_i),
        .m_axi_awready_o(m_axi_awready_o),
        .m_axi_awprot_i(m_axi_awprot_i),
        .s_axi_awaddr_o(s_axi_awaddr_o),
        .s_axi_awvalid_o(s_axi_awvalid_o),
        .s_axi_awready_i(s_axi_awready_i),
        .s_axi_awprot_o(s_axi_awprot_o),
        .enb_grant_i(grant_permission_AW_W),
        .Master_ID_Selected_o(master_id_AW_W_write)
    );

    fifo_masters_unit#(
        .ADDR_WIDTH(ADDR_WIDTH_FIFO),
        .DATA_WIDTH(DATA_WIDTH_FIFO)
    ) fifo_master_AW_W (
        .clk(m_axi_aclk_i), 
        .reset_n(m_axi_aresetn_i),
        .wr((!full_fifo_AW_W) && s_axi_awready_i), 
        .rd(s_axi_wready_i || grant_permission_W_W),

        .w_data(master_id_AW_W_write), //writing data
        .r_data(master_id_AW_W_read), //reading data

        .full(full_fifo_AW_W), 
        .empty(empty_fifo_AW_W)
    );

    DLock_timer #(
        .QUANTUM_TIME(QUANTUM_TIME)
    ) AW_DLock_timer (
        .clk_i(m_axi_aclk_i),
        .start_i(s_axi_awvalid_o),
        .set_i(s_axi_awready_i),
        .resetn_i(m_axi_aresetn_i), // || !s_axi_awready_i
        .tick_timer(grant_permission_AW_W)
    );

    // W CHANNEL
    W_dispatcher_m #(
        .DATA_WIDTH(DATA_WIDTH),
        .TRANS_W_STRB_W(TRANS_W_STRB_W),
        .NUM_MASTERS(NUM_MASTERS)
    ) W_dispatcher_master (
        .m_axi_wdata_i(m_axi_wdata_i),
        .m_axi_wstrb_i(m_axi_wstrb_i),
        .m_axi_wvalid_i(m_axi_wvalid_i),
        .m_axi_wready_o(m_axi_wready_o),
        .s_axi_wdata_o(s_axi_wdata_o),
        .s_axi_wstrb_o(s_axi_wstrb_o),
        .s_axi_wvalid_o(s_axi_wvalid_o),
        .s_axi_wready_i(s_axi_wready_i),
        .Master_ID_Selected_i(master_id_AW_W_read),
        .Master_ID_Selected_o(master_id_W_B_write),
        .empty_fifo_i(empty_fifo_AW_W)
    );


    fifo_masters_unit#(
        .ADDR_WIDTH(ADDR_WIDTH_FIFO),
        .DATA_WIDTH(DATA_WIDTH_FIFO)
    ) fifo_master_W_B (
        .clk(m_axi_aclk_i), 
        .reset_n(m_axi_aresetn_i),
        .wr((!full_fifo_W_B) && s_axi_wready_i), 
        .rd(s_axi_bvalid_i || grant_permission_B_W),

        .w_data(master_id_W_B_write), //writing data
        .r_data(master_id_W_B_read), //reading data

        .full(full_fifo_W_B), 
        .empty(empty_fifo_W_B)
    );


    DLock_timer #(
        .QUANTUM_TIME(QUANTUM_TIME)
    ) W_DLock_timer (
        .clk_i(m_axi_aclk_i),
        .start_i(s_axi_wvalid_o),
        .set_i(s_axi_wready_i),
        .resetn_i(m_axi_aresetn_i),
        .tick_timer(grant_permission_W_W)
    );


    //B CHANNEL

    B_dispatcher_m #(
        .TRANS_WR_RESP_W(TRANS_WR_RESP_W),
        .NUM_MASTERS(NUM_MASTERS)
    ) B_dispatcher_master (
        .m_axi_bresp_o(m_axi_bresp_o),
        .m_axi_bvalid_o(m_axi_bvalid_o),
        .m_axi_bready_i(m_axi_bready_i),
        .s_axi_bresp_i(s_axi_bresp_i),
        .s_axi_bvalid_i(s_axi_bvalid_i),
        .s_axi_bready_o(s_axi_bready_o),
        .Master_ID_Selected_i(master_id_W_B_read),
        .empty_fifo_i(empty_fifo_W_B)
    );


    DLock_timer #(
        .QUANTUM_TIME(QUANTUM_TIME)
    ) B_DLock_timer (
        .clk_i(m_axi_aclk_i),
        .start_i(s_axi_bready_o),
        .set_i(s_axi_bvalid_i),
        .resetn_i(m_axi_aresetn_i),
        .tick_timer(grant_permission_B_W)
    );



    /////////////////////////READ TRANSACTION////////////////////////////

    //AR CHANNEL/////////////////
    AR_arbiter_m #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .TRANS_PROT(TRANS_PROT),
        .NUM_MASTERS(NUM_MASTERS),
        .ID_MASTERS_MAPS(ID_MASTERS_MAPS)
    ) AR_arbiter_master (
        .m_axi_aresetn_i(m_axi_aresetn_i),
        .m_axi_araddr_i(m_axi_araddr_i),
        .m_axi_arvalid_i(m_axi_arvalid_i),
        .m_axi_arready_o(m_axi_arready_o),
        .m_axi_arprot_i(m_axi_arprot_i),
        .s_axi_araddr_o(s_axi_araddr_o),
        .s_axi_arvalid_o(s_axi_arvalid_o),
        .s_axi_arready_i(s_axi_arready_i),
        .s_axi_arprot_o(s_axi_arprot_o),
        .Master_ID_Selected_o(master_id_AR_R_write),
        .enb_grant_i(grant_permission_AR_R)
    );

    DLock_timer #(
        .QUANTUM_TIME(QUANTUM_TIME)
    ) AR_DLock_timer (
        .clk_i(m_axi_aclk_i),
        .start_i(s_axi_arvalid_o),
        .set_i(s_axi_arready_i),
        .resetn_i(m_axi_aresetn_i), // || !s_axi_arready_i
        .tick_timer(grant_permission_AR_R)
    );


    fifo_masters_unit#(
        .ADDR_WIDTH(ADDR_WIDTH_FIFO),
        .DATA_WIDTH(DATA_WIDTH_FIFO)
    ) fifo_master_AR_R (
        .clk(m_axi_aclk_i), 
        .reset_n(m_axi_aresetn_i),
        .wr((!full_fifo_AR_R) && s_axi_arready_i), 
        .rd( s_axi_rvalid_i || grant_permission_R_R),

        .w_data(master_id_AR_R_write), //writing data
        .r_data(master_id_AR_R_read), //reading data

        .full(full_fifo_AR_R), 
        .empty(empty_fifo_AR_R)
    );


    //R CHANNEL
    R_dispatcher_m #(
        .DATA_WIDTH(DATA_WIDTH),
        .TRANS_WR_RESP_W(TRANS_WR_RESP_W),
        .NUM_MASTERS(NUM_MASTERS)
    ) R_dispatcher_master (
        .m_axi_rdata_o(m_axi_rdata_o),
        .m_axi_rresp_o(m_axi_rresp_o),
        .m_axi_rvalid_o(m_axi_rvalid_o),
        .m_axi_rready_i(m_axi_rready_i),
        .s_axi_rdata_i(s_axi_rdata_i),
        .s_axi_rresp_i(s_axi_rresp_i),
        .s_axi_rvalid_i(s_axi_rvalid_i),
        .s_axi_rready_o(s_axi_rready_o),
        .Master_ID_Selected_i(master_id_AR_R_read),
        .empty_fifo_i(empty_fifo_AR_R)
    );


    DLock_timer #(
        .QUANTUM_TIME(QUANTUM_TIME)
    ) R_DLock_timer (
        .clk_i(m_axi_aclk_i),
        .start_i(s_axi_rready_o),
        .set_i(s_axi_rvalid_i),
        .resetn_i(m_axi_aresetn_i),
        .tick_timer(grant_permission_R_R)
    );


    assign grant_permission_W_W_o = grant_permission_W_W;
    assign grant_permission_B_W_o = grant_permission_B_W;
    assign grant_permission_R_R_o = grant_permission_R_R;

endmodule


module AW_arbiter_m#(
    // Transaction configuration
    parameter ADDR_WIDTH = 32,          // Address width
    parameter TRANS_PROT = 3,
    // Interconnect configuration
    parameter NUM_MASTERS = 16,         // Number of masters
    parameter [NUM_MASTERS*NUM_MASTERS-1:0] ID_MASTERS_MAPS = {
        // Master 15: bit 15 = 1, others = 0
        { 1'b1, {(NUM_MASTERS-1){1'b0}} },
        // Master 14: bit 14 = 1, others = 0
        { {(NUM_MASTERS-15){1'b0}}, 1'b1, {14{1'b0}} },
        // Master 13: bit 13 = 1, others = 0
        { {(NUM_MASTERS-14){1'b0}}, 1'b1, {13{1'b0}} },
        // Master 12: bit 12 = 1, others = 0
        { {(NUM_MASTERS-13){1'b0}}, 1'b1, {12{1'b0}} },
        // Master 11: bit 11 = 1, others = 0
        { {(NUM_MASTERS-12){1'b0}}, 1'b1, {11{1'b0}} },
        // Master 10: bit 10 = 1, others = 0
        { {(NUM_MASTERS-11){1'b0}}, 1'b1, {10{1'b0}} },
        // Master 9: bit 9 = 1, others = 0
        { {(NUM_MASTERS-10){1'b0}}, 1'b1, {9{1'b0}} },
        // Master 8: bit 8 = 1, others = 0
        { {(NUM_MASTERS-9){1'b0}}, 1'b1, {8{1'b0}} },
        // Master 7: bit 7 = 1, others = 0
        { {(NUM_MASTERS-8){1'b0}}, 1'b1, {7{1'b0}} },
        // Master 6: bit 6 = 1, others = 0
        { {(NUM_MASTERS-7){1'b0}}, 1'b1, {6{1'b0}} },
        // Master 5: bit 5 = 1, others = 0
        { {(NUM_MASTERS-6){1'b0}}, 1'b1, {5{1'b0}} },
        // Master 4: bit 4 = 1, others = 0
        { {(NUM_MASTERS-5){1'b0}}, 1'b1, {4{1'b0}} },
        // Master 3: bit 3 = 1, others = 0
        { {(NUM_MASTERS-4){1'b0}}, 1'b1, {3{1'b0}} },
        // Master 2: bit 2 = 1, others = 0
        { {(NUM_MASTERS-3){1'b0}}, 1'b1, {2{1'b0}} },
        // Master 1: bit 1 = 1, others = 0
        { {(NUM_MASTERS-2){1'b0}}, 1'b1, {1{1'b0}} },
        // Master 0: bit 0 = 1, others = 0
        { {(NUM_MASTERS-1){1'b0}}, 1'b1 }
    }
)(
    // MULTIPLE MASTER PORT
    input                                               m_axi_aresetn_i, 

    // master AW Channel
    input   [ADDR_WIDTH*NUM_MASTERS-1:0]                m_axi_awaddr_i,
    input   [NUM_MASTERS-1:0]                           m_axi_awvalid_i,
    output  [NUM_MASTERS-1:0]                           m_axi_awready_o,
    input   [NUM_MASTERS*TRANS_PROT-1:0]                m_axi_awprot_i,

    // slave AW Channel
    output  reg [ADDR_WIDTH-1:0]                        s_axi_awaddr_o,
    output  reg                                         s_axi_awvalid_o,
    input                                               s_axi_awready_i,
    output  reg [TRANS_PROT-1:0]                        s_axi_awprot_o,

    input                                               enb_grant_i,
    output  [NUM_MASTERS-1:0]                           Master_ID_Selected_o
);

    wire   [NUM_MASTERS-1:0]                            Master_ID_Selected;


    // combi circuit for aw channel
    // connect awready master to slave
    genvar  mst_count;
    generate
        for (mst_count = 0; mst_count < NUM_MASTERS; mst_count = mst_count + 1) begin
            assign m_axi_awready_o[mst_count] = (Master_ID_Selected[mst_count]) ?  s_axi_awready_i : 0;
        end
    endgenerate

    // connect awaddr, awvalid master to slave
    // integer i;
    // always @(*) begin
    //     s_axi_awaddr_o = {ADDR_WIDTH{1'b0}};
    //     s_axi_awprot_o = {TRANS_PROT{1'b0}};
    //     s_axi_awvalid_o = 0;
    //     for (i = 0; i < NUM_MASTERS; i = i + 1) begin    
    //         if (Master_ID_Selected[i]) begin
    //             s_axi_awaddr_o = m_axi_awaddr_i[((ADDR_WIDTH*i) + ADDR_WIDTH -1) -: ADDR_WIDTH];
    //             s_axi_awprot_o = m_axi_awprot_i[((TRANS_PROT*i) + TRANS_PROT -1) -: TRANS_PROT];
    //             s_axi_awvalid_o = m_axi_awvalid_i[i];
    //         end
    //     end
    // end
    integer i;
    always @(*) begin
        s_axi_awaddr_o  = {ADDR_WIDTH{1'b0}};
        s_axi_awprot_o  = {TRANS_PROT{1'b0}};
        s_axi_awvalid_o = 0;
        for (i = 0; i < NUM_MASTERS; i = i + 1) begin  
            s_axi_awaddr_o = s_axi_awaddr_o | ({ADDR_WIDTH{Master_ID_Selected[i]}} & m_axi_awaddr_i[((ADDR_WIDTH*i) + ADDR_WIDTH -1) -: ADDR_WIDTH]);
            s_axi_awprot_o = s_axi_awprot_o | ({TRANS_PROT{Master_ID_Selected[i]}} & m_axi_awprot_i[((TRANS_PROT*i) + TRANS_PROT -1) -: TRANS_PROT]);
            s_axi_awvalid_o = |(m_axi_awvalid_i & Master_ID_Selected);
        end
    end




    arbiter#(
        .NUM_MASTERS(NUM_MASTERS),              // Number of masters
        .ID_MASTERS_MAPS(ID_MASTERS_MAPS) 
    ) arbiter_W  (  
        .resetn_i(m_axi_aresetn_i),
        .enb_grant_i(s_axi_awready_i || enb_grant_i),
        .requite_grant_i(m_axi_awvalid_i),
        .grant_permission_o(Master_ID_Selected) // id one hot
    );

    assign Master_ID_Selected_o = Master_ID_Selected;

endmodule


module W_dispatcher_m#(
    parameter DATA_WIDTH = 32,          // Data width
    parameter TRANS_W_STRB_W = 4,       // width strobe
    parameter NUM_MASTERS = 16          // Number of masters
)(

    // master W Channel
    input   [DATA_WIDTH*NUM_MASTERS-1:0]                    m_axi_wdata_i,
    input   [TRANS_W_STRB_W*NUM_MASTERS-1:0]                m_axi_wstrb_i,
    input   [NUM_MASTERS-1:0]                               m_axi_wvalid_i,
    output  [NUM_MASTERS-1:0]                               m_axi_wready_o,

    // slave W Channel
    output  reg [DATA_WIDTH-1:0]                            s_axi_wdata_o,
    output  reg [TRANS_W_STRB_W-1:0]                        s_axi_wstrb_o,
    output  reg                                             s_axi_wvalid_o,
    input                                                   s_axi_wready_i,

    input   [NUM_MASTERS-1:0]                               Master_ID_Selected_i,
    output  [NUM_MASTERS-1:0]                               Master_ID_Selected_o,
    input                                                   empty_fifo_i



);  
    wire    [NUM_MASTERS-1:0]                               Master_ID_Selected;

    // combi circuit for w channel
    // connect wready slave to master
    genvar  mst_count;
    generate
        for (mst_count = 0; mst_count < NUM_MASTERS; mst_count = mst_count + 1) begin
            assign m_axi_wready_o[mst_count] = (Master_ID_Selected[mst_count]) ?  s_axi_wready_i : 0;
        end
    endgenerate

    // connect wdata, wstrb, wvalid, master to slave
    // integer i;
    // always @(*) begin
    //     s_axi_wdata_o = 0;
    //     s_axi_wstrb_o = 0;
    //     s_axi_wvalid_o = 0;
    //     for (i = 0; i < NUM_MASTERS; i = i + 1) begin
    //         if (Master_ID_Selected[i]) begin
    //             s_axi_wdata_o   = m_axi_wdata_i[((DATA_WIDTH*i) + DATA_WIDTH -1) -: DATA_WIDTH];
    //             s_axi_wstrb_o   = m_axi_wstrb_i[((TRANS_W_STRB_W*i) + TRANS_W_STRB_W -1) -: TRANS_W_STRB_W];
    //             s_axi_wvalid_o  = m_axi_wvalid_i[i];
    //         end
    //     end
    // end

    integer i;
    always @(*) begin
        s_axi_wdata_o = {DATA_WIDTH{1'b0}};
        s_axi_wstrb_o = {TRANS_W_STRB_W{1'b0}};
        s_axi_wvalid_o = 0;
        for (i = 0; i < NUM_MASTERS; i = i + 1) begin
            s_axi_wdata_o   = s_axi_wdata_o | ({DATA_WIDTH{Master_ID_Selected[i]}} & m_axi_wdata_i[((DATA_WIDTH*i) + DATA_WIDTH -1) -: DATA_WIDTH]);
            s_axi_wstrb_o   = s_axi_wstrb_o | ({TRANS_W_STRB_W{Master_ID_Selected[i]}} & m_axi_wstrb_i[((TRANS_W_STRB_W*i) + TRANS_W_STRB_W -1) -: TRANS_W_STRB_W]);
            s_axi_wvalid_o  = |(m_axi_wvalid_i & Master_ID_Selected);
        end
    end



    assign Master_ID_Selected   = (!empty_fifo_i) ? Master_ID_Selected_i : 0;
    assign Master_ID_Selected_o =  Master_ID_Selected;


endmodule


module B_dispatcher_m#(
    // Transaction configuration
    parameter TRANS_WR_RESP_W = 2,      // width response
    // Interconnect configuration
    parameter NUM_MASTERS = 16         // Number of masters
)(

    // master B Channel
    output  [TRANS_WR_RESP_W*NUM_MASTERS-1:0]        m_axi_bresp_o,
    output  [NUM_MASTERS-1:0]                        m_axi_bvalid_o,
    input   [NUM_MASTERS-1:0]                        m_axi_bready_i,

    // slave B Channel
    input   [TRANS_WR_RESP_W-1:0]                    s_axi_bresp_i,
    input                                            s_axi_bvalid_i,
    output  reg                                      s_axi_bready_o,

    input   [NUM_MASTERS-1:0]                        Master_ID_Selected_i,
    input                                            empty_fifo_i
);  
    wire    [NUM_MASTERS-1:0]                        Master_ID_Selected;

    // combi circuit for aw channel
    // connect bresp, bvalid slave to master
    genvar  mst_count;
    generate
        for (mst_count = 0; mst_count < NUM_MASTERS; mst_count = mst_count + 1) begin
            assign m_axi_bresp_o[((TRANS_WR_RESP_W*mst_count) + TRANS_WR_RESP_W -1) -: TRANS_WR_RESP_W] = (Master_ID_Selected[mst_count]) ?  s_axi_bresp_i : 0;
        end
    endgenerate

    generate
        for (mst_count = 0; mst_count < NUM_MASTERS; mst_count = mst_count + 1) begin
            assign m_axi_bvalid_o[mst_count] = (Master_ID_Selected[mst_count]) ?  s_axi_bvalid_i : 0;
        end
    endgenerate
    

    // connect bready master to slave
    // integer i;
    // always @(*) begin
    //     s_axi_bready_o = 0;
    //     for (i = 0; i < NUM_MASTERS; i = i + 1) begin    
    //         if (Master_ID_Selected[i]) begin
    //             s_axi_bready_o = m_axi_bready_i[i];
    //         end
    //     end
    // end

    integer i;
    always @(*) begin
        s_axi_bready_o = 0;
        for (i = 0; i < NUM_MASTERS; i = i + 1) begin    
            s_axi_bready_o = |(m_axi_bready_i & Master_ID_Selected);
        end
    end


    assign Master_ID_Selected = (!empty_fifo_i) ? Master_ID_Selected_i : 0;

endmodule


module AR_arbiter_m#(
    // Transaction configuration
    parameter ADDR_WIDTH = 32,          // Address width
    parameter TRANS_PROT = 3,
    // Interconnect configuration
    parameter NUM_MASTERS = 16,         // Number of masters
    parameter [NUM_MASTERS*NUM_MASTERS-1:0] ID_MASTERS_MAPS = {
        // Master 15: bit 15 = 1, others = 0
        { 1'b1, {(NUM_MASTERS-1){1'b0}} },
        // Master 14: bit 14 = 1, others = 0
        { {(NUM_MASTERS-15){1'b0}}, 1'b1, {14{1'b0}} },
        // Master 13: bit 13 = 1, others = 0
        { {(NUM_MASTERS-14){1'b0}}, 1'b1, {13{1'b0}} },
        // Master 12: bit 12 = 1, others = 0
        { {(NUM_MASTERS-13){1'b0}}, 1'b1, {12{1'b0}} },
        // Master 11: bit 11 = 1, others = 0
        { {(NUM_MASTERS-12){1'b0}}, 1'b1, {11{1'b0}} },
        // Master 10: bit 10 = 1, others = 0
        { {(NUM_MASTERS-11){1'b0}}, 1'b1, {10{1'b0}} },
        // Master 9: bit 9 = 1, others = 0
        { {(NUM_MASTERS-10){1'b0}}, 1'b1, {9{1'b0}} },
        // Master 8: bit 8 = 1, others = 0
        { {(NUM_MASTERS-9){1'b0}}, 1'b1, {8{1'b0}} },
        // Master 7: bit 7 = 1, others = 0
        { {(NUM_MASTERS-8){1'b0}}, 1'b1, {7{1'b0}} },
        // Master 6: bit 6 = 1, others = 0
        { {(NUM_MASTERS-7){1'b0}}, 1'b1, {6{1'b0}} },
        // Master 5: bit 5 = 1, others = 0
        { {(NUM_MASTERS-6){1'b0}}, 1'b1, {5{1'b0}} },
        // Master 4: bit 4 = 1, others = 0
        { {(NUM_MASTERS-5){1'b0}}, 1'b1, {4{1'b0}} },
        // Master 3: bit 3 = 1, others = 0
        { {(NUM_MASTERS-4){1'b0}}, 1'b1, {3{1'b0}} },
        // Master 2: bit 2 = 1, others = 0
        { {(NUM_MASTERS-3){1'b0}}, 1'b1, {2{1'b0}} },
        // Master 1: bit 1 = 1, others = 0
        { {(NUM_MASTERS-2){1'b0}}, 1'b1, {1{1'b0}} },
        // Master 0: bit 0 = 1, others = 0
        { {(NUM_MASTERS-1){1'b0}}, 1'b1 }
    }
)(  

    input                                            m_axi_aresetn_i, 

    // master AR Channel
    input   [ADDR_WIDTH*NUM_MASTERS-1:0]             m_axi_araddr_i,
    input   [NUM_MASTERS-1:0]                        m_axi_arvalid_i,
    output  [NUM_MASTERS-1:0]                        m_axi_arready_o,
    input   [NUM_MASTERS*TRANS_PROT-1:0]             m_axi_arprot_i,


    // slave AR Channel
    output  reg [ADDR_WIDTH-1:0]                            s_axi_araddr_o,
    output  reg                                             s_axi_arvalid_o,
    input                                                   s_axi_arready_i,
    output  reg [TRANS_PROT-1:0]                            s_axi_arprot_o,

    output      [NUM_MASTERS-1:0]                           Master_ID_Selected_o,
    input                                                   enb_grant_i
);
    wire   [NUM_MASTERS-1:0]                                Master_ID_Selected;

    // combi circuit for ar channel
    // connect arready master to slave
    genvar  mst_count;
    generate
        for (mst_count = 0; mst_count < NUM_MASTERS; mst_count = mst_count + 1) begin
            assign m_axi_arready_o[mst_count] = (Master_ID_Selected[mst_count]) ?  s_axi_arready_i : 0;
        end
    endgenerate

    // connect araddr, arvalid master to slave
    // integer i;
    // always @(*) begin
    //     s_axi_araddr_o = 0;
    //     s_axi_arvalid_o = 0;
    //     s_axi_arprot_o = 0;
    //     for (i = 0; i < NUM_MASTERS; i = i + 1) begin    
    //         if (Master_ID_Selected[i]) begin
    //             s_axi_araddr_o = m_axi_araddr_i[((ADDR_WIDTH*i) + ADDR_WIDTH -1) -: ADDR_WIDTH];
    //             s_axi_arvalid_o = m_axi_arvalid_i[i];
    //             s_axi_arprot_o = m_axi_arprot_i[((TRANS_PROT*i) + TRANS_PROT -1) -: TRANS_PROT];
    //         end
    //     end
    // end

    integer i;
    always @(*) begin
        s_axi_araddr_o = {ADDR_WIDTH{1'b0}};
        s_axi_arprot_o = {TRANS_PROT{1'b0}};
        s_axi_arvalid_o = 0;
        for (i = 0; i < NUM_MASTERS; i = i + 1) begin
            s_axi_araddr_o = s_axi_araddr_o | ({ADDR_WIDTH{Master_ID_Selected[i]}} & m_axi_araddr_i[((ADDR_WIDTH*i) + ADDR_WIDTH -1) -: ADDR_WIDTH]);
            s_axi_arprot_o = s_axi_arprot_o | ({TRANS_PROT{Master_ID_Selected[i]}} & m_axi_arprot_i[((TRANS_PROT*i) + TRANS_PROT -1) -: TRANS_PROT]);
            s_axi_arvalid_o = |(m_axi_arvalid_i & Master_ID_Selected);
        end
    end

    arbiter#(
        .NUM_MASTERS(NUM_MASTERS),              // Number of masters
        .ID_MASTERS_MAPS(ID_MASTERS_MAPS) 
    ) arbiter_R  (  
        .resetn_i(m_axi_aresetn_i),
        .enb_grant_i(s_axi_arready_i || enb_grant_i),
        .requite_grant_i(m_axi_arvalid_i),
        .grant_permission_o(Master_ID_Selected) // id one hot
    );

    assign Master_ID_Selected_o = Master_ID_Selected;

endmodule


module R_dispatcher_m#(
    parameter DATA_WIDTH = 32,
    parameter TRANS_WR_RESP_W = 2, 
    parameter NUM_MASTERS = 16   
)(

    // master R Channel
    output  [DATA_WIDTH*NUM_MASTERS-1:0]                m_axi_rdata_o,
    output  [TRANS_WR_RESP_W*NUM_MASTERS-1:0]           m_axi_rresp_o,
    output  [NUM_MASTERS-1:0]                           m_axi_rvalid_o,
    input   [NUM_MASTERS-1:0]                           m_axi_rready_i,

    // slave R Channel
    input   [DATA_WIDTH-1:0]                            s_axi_rdata_i,
    input   [TRANS_WR_RESP_W-1:0]                       s_axi_rresp_i,
    input                                               s_axi_rvalid_i,
    output  reg                                         s_axi_rready_o,

    input  [NUM_MASTERS-1:0]                            Master_ID_Selected_i,
    input                                               empty_fifo_i

);

    wire   [NUM_MASTERS-1:0]                            Master_ID_Selected;

    // combi circuit for w channel
    // connect rdata, rresp, rvalid, slave to master
    genvar  mst_count;
    generate
        for (mst_count = 0; mst_count < NUM_MASTERS; mst_count = mst_count + 1) begin
            assign m_axi_rdata_o[((DATA_WIDTH*mst_count) + DATA_WIDTH -1) -: DATA_WIDTH] = (Master_ID_Selected[mst_count]) ?  s_axi_rdata_i : 0;
        end
    endgenerate

    generate
        for (mst_count = 0; mst_count < NUM_MASTERS; mst_count = mst_count + 1) begin
            assign m_axi_rresp_o[((TRANS_WR_RESP_W*mst_count) + TRANS_WR_RESP_W -1) -: TRANS_WR_RESP_W] = (Master_ID_Selected[mst_count]) ?  s_axi_rresp_i : 0;
        end
    endgenerate
    
    generate
        for (mst_count = 0; mst_count < NUM_MASTERS; mst_count = mst_count + 1) begin
            assign m_axi_rvalid_o[mst_count] = (Master_ID_Selected[mst_count]) ?  s_axi_rvalid_i : 0;
        end
    endgenerate

    // connect rready, master to slave
    // integer i;
    // always @(*) begin
    //     s_axi_rready_o = 0;
    //     for (i = 0; i < NUM_MASTERS; i = i + 1) begin
    //         if (Master_ID_Selected[i]) begin
    //             s_axi_rready_o  = m_axi_rready_i[i];
    //         end
    //     end
    // end

    integer i;
    always @(*) begin
        s_axi_rready_o = 0;
        for (i = 0; i < NUM_MASTERS; i = i + 1) begin
            s_axi_rready_o  = |(m_axi_rready_i & Master_ID_Selected);
        end
    end


    assign Master_ID_Selected = (!empty_fifo_i) ? Master_ID_Selected_i : 0;

endmodule

//////////////////////////////ARBITER////////////////////////////////////////////////

module arbiter#(
    parameter   NUM_MASTERS = 16,         // Number of masters
    parameter   [NUM_MASTERS*NUM_MASTERS-1:0] ID_MASTERS_MAPS = {
        // Master 15: bit 15 = 1, others = 0
        { 1'b1, {(NUM_MASTERS-1){1'b0}} },
        // Master 14: bit 14 = 1, others = 0
        { {(NUM_MASTERS-15){1'b0}}, 1'b1, {14{1'b0}} },
        // Master 13: bit 13 = 1, others = 0
        { {(NUM_MASTERS-14){1'b0}}, 1'b1, {13{1'b0}} },
        // Master 12: bit 12 = 1, others = 0
        { {(NUM_MASTERS-13){1'b0}}, 1'b1, {12{1'b0}} },
        // Master 11: bit 11 = 1, others = 0
        { {(NUM_MASTERS-12){1'b0}}, 1'b1, {11{1'b0}} },
        // Master 10: bit 10 = 1, others = 0
        { {(NUM_MASTERS-11){1'b0}}, 1'b1, {10{1'b0}} },
        // Master 9: bit 9 = 1, others = 0
        { {(NUM_MASTERS-10){1'b0}}, 1'b1, {9{1'b0}} },
        // Master 8: bit 8 = 1, others = 0
        { {(NUM_MASTERS-9){1'b0}}, 1'b1, {8{1'b0}} },
        // Master 7: bit 7 = 1, others = 0
        { {(NUM_MASTERS-8){1'b0}}, 1'b1, {7{1'b0}} },
        // Master 6: bit 6 = 1, others = 0
        { {(NUM_MASTERS-7){1'b0}}, 1'b1, {6{1'b0}} },
        // Master 5: bit 5 = 1, others = 0
        { {(NUM_MASTERS-6){1'b0}}, 1'b1, {5{1'b0}} },
        // Master 4: bit 4 = 1, others = 0
        { {(NUM_MASTERS-5){1'b0}}, 1'b1, {4{1'b0}} },
        // Master 3: bit 3 = 1, others = 0
        { {(NUM_MASTERS-4){1'b0}}, 1'b1, {3{1'b0}} },
        // Master 2: bit 2 = 1, others = 0
        { {(NUM_MASTERS-3){1'b0}}, 1'b1, {2{1'b0}} },
        // Master 1: bit 1 = 1, others = 0
        { {(NUM_MASTERS-2){1'b0}}, 1'b1, {1{1'b0}} },
        // Master 0: bit 0 = 1, others = 0
        { {(NUM_MASTERS-1){1'b0}}, 1'b1 }
    }


)(  
    input                                               resetn_i,
    input                                               enb_grant_i,
    input   [NUM_MASTERS-1:0]                           requite_grant_i,

    output  [NUM_MASTERS-1:0]                           grant_permission_o // id one hot

);

    wire    [$clog2(NUM_MASTERS)-1:0]                   number_signal;
    reg     [NUM_MASTERS*NUM_MASTERS-1:0]               Master_ID_Map;

    // combi circuit for round robin
    integer ni_mters_comb;
    integer nj_mters_comb;
    always @(*) begin
        Master_ID_Map = 'd0;
        for (nj_mters_comb = 0; nj_mters_comb < NUM_MASTERS; nj_mters_comb = nj_mters_comb + 1) begin
            if (nj_mters_comb == 0) begin
                for (ni_mters_comb = NUM_MASTERS - 1 - nj_mters_comb; ni_mters_comb >= 0; ni_mters_comb = ni_mters_comb - 1) begin
                    if (requite_grant_i[ni_mters_comb]) begin
                        Master_ID_Map[((NUM_MASTERS*nj_mters_comb) + NUM_MASTERS - 1) -: NUM_MASTERS] = ID_MASTERS_MAPS[((NUM_MASTERS*ni_mters_comb) + NUM_MASTERS - 1) -: NUM_MASTERS];  
                    end
                end
            end
            else begin
                for (ni_mters_comb = nj_mters_comb - 1; ni_mters_comb >= 0; ni_mters_comb = ni_mters_comb - 1) begin
                    if (requite_grant_i[ni_mters_comb]) begin
                        Master_ID_Map[((NUM_MASTERS*nj_mters_comb) + NUM_MASTERS - 1) -: NUM_MASTERS] = ID_MASTERS_MAPS[((NUM_MASTERS*ni_mters_comb) + NUM_MASTERS - 1) -: NUM_MASTERS];  
                    end 
                end
                for (ni_mters_comb = NUM_MASTERS - 1; ni_mters_comb >= nj_mters_comb; ni_mters_comb = ni_mters_comb - 1) begin
                    if (requite_grant_i[ni_mters_comb]) begin
                        Master_ID_Map[((NUM_MASTERS*nj_mters_comb) + NUM_MASTERS - 1) -: NUM_MASTERS] = ID_MASTERS_MAPS[((NUM_MASTERS*ni_mters_comb) + NUM_MASTERS - 1) -: NUM_MASTERS];  
                    end 
                end
              
            end
        end

    end


    counter_arbiter #(
        .NUM_MASTERS(NUM_MASTERS)
    ) counter_arbiter_unit (
        .tick_count_i(enb_grant_i),
        .resetn_i(resetn_i),
        .number_o(number_signal)
    );

    mux_ID_arbiter #(
        .NUM_MASTERS(NUM_MASTERS)
    ) mux_ID_arbiter_unit (

        .Master_ID_Selected_i(Master_ID_Map),
        .number_select_i(number_signal),
        .Master_ID_Selected_o(grant_permission_o)
    );
endmodule


module counter_arbiter#(
    parameter NUM_MASTERS = 16              // Number of masters
)(
    input                                   tick_count_i,
    input                                   resetn_i,             

    output  [$clog2(NUM_MASTERS)-1:0]       number_o

);
    reg [$clog2(NUM_MASTERS)-1:0] count_reg, count_next;

    always @(negedge tick_count_i or negedge resetn_i) begin
        if (~resetn_i) begin
            count_reg <= 0;
        end
        else begin
            count_reg <= count_next;
        end
    end

    always @(*) begin
        count_next = count_reg;
        if (count_reg >= NUM_MASTERS) begin
            count_next = 0;
        end

        else count_next = count_next + 1;
    end

    assign  number_o = count_reg;

endmodule

module mux_ID_arbiter#(
    parameter NUM_MASTERS = 16
)(
    input   [NUM_MASTERS*NUM_MASTERS-1:0]   Master_ID_Selected_i,
    input   [$clog2(NUM_MASTERS)-1:0]       number_select_i,
    output  [NUM_MASTERS-1:0]               Master_ID_Selected_o
);

    assign Master_ID_Selected_o = Master_ID_Selected_i[((number_select_i * NUM_MASTERS) + NUM_MASTERS -1)  -: NUM_MASTERS];

endmodule

//////////////////////////////////////////////DEADLOCK TIMER//////////////////////////////////////////
module DLock_timer#(
    parameter QUANTUM_TIME = 16 // cycle

)(  
    input   clk_i,
    input   start_i,
    input   set_i,
    input   resetn_i,
    output  tick_timer

);

    reg [$clog2(QUANTUM_TIME)-1:0] count_next, count_reg;
    reg                            tick_next, tick_reg;

    always @(posedge clk_i or negedge resetn_i) begin
        if (~resetn_i) begin
            count_reg <= 0;
            tick_reg <= 0;
        end
        else begin
            tick_reg <= tick_next;
            count_reg <= count_next;
        end
    end

    always @(*) begin
        count_next = count_reg;
        tick_next = 0;
        if (start_i) begin
            if (count_reg >= QUANTUM_TIME - 1) begin
                count_next = 0;
                tick_next = 1;
            end
            else if(set_i) begin
                count_next = 0;
            end
            else begin  
                count_next = count_next + 1;
                tick_next = 0;
            end
        end
    end

    assign tick_timer = tick_reg;

endmodule



////////FIFO//////////////////////////////////


//module fifo
module fifo_masters_unit #(parameter ADDR_WIDTH = 3, DATA_WIDTH = 8)(
    input clk, reset_n,
    input wr, rd,

    input [DATA_WIDTH - 1 : 0] w_data, //writing data
    output [DATA_WIDTH - 1 : 0] r_data, //reading data

    output full, empty

    );

    //signal
    wire [ADDR_WIDTH - 1 : 0] w_addr, r_addr;

    //instantiate registers file
    register_file_masters #(.ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH))
        reg_file_unit_masters(
            .clk(clk),
            .w_en(~full & wr),

            .r_addr(r_addr), //reading address
            .w_addr(w_addr), //writing address

            .w_data(w_data), //writing data
            .r_data(r_data) //reading data
        
        );

    //instantiate fifo ctrl
    fifo_ctrl_masters #(.ADDR_WIDTH(ADDR_WIDTH))
        fifo_ctrl_masters(
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


module fifo_ctrl_masters #(parameter ADDR_WIDTH = 3)(
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



module register_file_masters #(parameter ADDR_WIDTH = 3, DATA_WIDTH = 8)(
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