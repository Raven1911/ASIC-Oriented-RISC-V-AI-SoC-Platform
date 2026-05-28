`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 04/20/2025 02:14:35 AM
// Design Name: 
// Module Name: axi_lite_interconnect
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

/***************************************************************
 * AXI4-Lite Interconnect for picorv32_axi (Multiple Masters, Multiple Slaves)
 * This module connects multiple AXI4-Lite masters to multiple slaves using an arbiter,
 * decoder, and multiplexer. The arbiter selects one master at a time (Round-Robin),
 * the decoder selects the target slave based on address, and the multiplexer routes
 * signals between the selected master and slave.
 ***************************************************************/
module axi_lite_interconnect #(
    // Transaction configuration
    parameter ADDR_WIDTH = 32,          // Address width
    parameter DATA_WIDTH = 32,          // Data width
    parameter TRANS_W_STRB_W = 4,       // width strobe
    parameter TRANS_WR_RESP_W = 2,      // width response
    parameter TRANS_PROT      = 3,
    parameter QUANTUM_TIME = 16,

    // Interconnect configuration
    parameter NUM_MASTERS = 4,         // Number of masters
    parameter NUM_SLAVES  = 16,         // Number of slaves
    parameter [NUM_MASTERS*NUM_MASTERS-1:0] ID_MASTERS_MAPS = {
        // // Master 15: bit 15 = 1, others = 0
        // { 1'b1, {(NUM_MASTERS-1){1'b0}} },
        // // Master 14: bit 14 = 1, others = 0
        // { {(NUM_MASTERS-15){1'b0}}, 1'b1, {14{1'b0}} },
        // // Master 13: bit 13 = 1, others = 0
        // { {(NUM_MASTERS-14){1'b0}}, 1'b1, {13{1'b0}} },
        // // Master 12: bit 12 = 1, others = 0
        // { {(NUM_MASTERS-13){1'b0}}, 1'b1, {12{1'b0}} },
        // // Master 11: bit 11 = 1, others = 0
        // { {(NUM_MASTERS-12){1'b0}}, 1'b1, {11{1'b0}} },
        // // Master 10: bit 10 = 1, others = 0
        // { {(NUM_MASTERS-11){1'b0}}, 1'b1, {10{1'b0}} },
        // // Master 9: bit 9 = 1, others = 0
        // { {(NUM_MASTERS-10){1'b0}}, 1'b1, {9{1'b0}} },
        // // Master 8: bit 8 = 1, others = 0
        // { {(NUM_MASTERS-9){1'b0}}, 1'b1, {8{1'b0}} },
        // // Master 7: bit 7 = 1, others = 0
        // { {(NUM_MASTERS-8){1'b0}}, 1'b1, {7{1'b0}} },
        // // Master 6: bit 6 = 1, others = 0
        // { {(NUM_MASTERS-7){1'b0}}, 1'b1, {6{1'b0}} },
        // // Master 5: bit 5 = 1, others = 0
        // { {(NUM_MASTERS-6){1'b0}}, 1'b1, {5{1'b0}} },
        // // Master 4: bit 4 = 1, others = 0
        // { {(NUM_MASTERS-5){1'b0}}, 1'b1, {4{1'b0}} },
        // Master 3: bit 3 = 1, others = 0
        { 1'b1, {(NUM_MASTERS-1){1'b0}} },
        // { {(NUM_MASTERS-4){1'b0}}, 1'b1, {3{1'b0}} },
        // Master 2: bit 2 = 1, others = 0
        { {(NUM_MASTERS-3){1'b0}}, 1'b1, {2{1'b0}} },
        // Master 1: bit 1 = 1, others = 0
        { {(NUM_MASTERS-2){1'b0}}, 1'b1, {1{1'b0}} },
        // Master 0: bit 0 = 1, others = 0
        { {(NUM_MASTERS-1){1'b0}}, 1'b1 }
    },

    parameter [((ADDR_WIDTH*2)*NUM_SLAVES)-1:0] ADDR_MAP_SLAVES = { //{addr start, addr end}      
        {32'hF000_0000, 32'hFFFF_FFFF},     // slave 15
        {32'hE000_0000, 32'hEFFF_FFFF},     // slave 14       
        {32'hD000_0000, 32'hDFFF_FFFF},     // slave 13
        {32'hC000_0000, 32'hCFFF_FFFF},     // slave 12
        {32'hB000_0000, 32'hBFFF_FFFF},     // slave 11
        {32'hA000_0000, 32'hAFFF_FFFF},     // slave 10
        {32'h0900_0000, 32'h09FF_FFFF},     // slave 9       
        {32'h0800_0000, 32'h08FF_FFFF},     // slave 8

        {32'h0700_0000, 32'h07FF_FFFF},     // slave 7
        {32'h0600_0000, 32'h06FF_FFFF},     // slave 6       
        {32'h0500_0000, 32'h05FF_FFFF},     // slave 5
        {32'h0400_0000, 32'h04FF_FFFF},     // slave 4       
        {32'h0300_0000, 32'h03FF_FFFF},     // slave 3
        {32'h0200_0000, 32'h02FF_FFFF},     // slave 2
        {32'h0100_0000, 32'h01FF_FFFF},     // slave 1
        {32'h0000_0000, 32'h00FF_FFFF}      // slave 0
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


    
    //SLAVES PORT
    // slave AW Channel
    output      [ADDR_WIDTH*NUM_SLAVES-1:0]         s_axi_awaddr_o,
    output      [NUM_SLAVES-1:0]                    s_axi_awvalid_o,
    input       [NUM_SLAVES-1:0]                    s_axi_awready_i,
    output      [TRANS_PROT*NUM_SLAVES-1:0]         s_axi_awprot_o,    
    
    // slave W Channel
    output      [DATA_WIDTH*NUM_SLAVES-1:0]         s_axi_wdata_o,
    output      [TRANS_W_STRB_W*NUM_SLAVES-1:0]     s_axi_wstrb_o,
    output      [NUM_SLAVES-1:0]                    s_axi_wvalid_o,
    input       [NUM_SLAVES-1:0]                    s_axi_wready_i,

    // slave B Channel
    input       [TRANS_WR_RESP_W*NUM_SLAVES-1:0]    s_axi_bresp_i,
    input       [NUM_SLAVES-1:0]                    s_axi_bvalid_i,
    output      [NUM_SLAVES-1:0]                    s_axi_bready_o,

    // slave AR Channel
    output      [ADDR_WIDTH*NUM_SLAVES-1:0]         s_axi_araddr_o,
    output      [NUM_SLAVES-1:0]                    s_axi_arvalid_o,
    input       [NUM_SLAVES-1:0]                    s_axi_arready_i,
    output      [TRANS_PROT*NUM_SLAVES-1:0]         s_axi_arprot_o, 

    // slave R Channel
    input       [DATA_WIDTH*NUM_SLAVES-1:0]         s_axi_rdata_i,
    input       [TRANS_WR_RESP_W*NUM_SLAVES-1:0]    s_axi_rresp_i,
    input       [NUM_SLAVES-1:0]                    s_axi_rvalid_i,
    output      [NUM_SLAVES-1:0]                    s_axi_rready_o
    
);


    // wire AW Channel
    wire    [ADDR_WIDTH-1:0]            connect_axi_awaddr;
    wire                                connect_axi_awvalid;
    wire                                connect_axi_awready;
    wire    [TRANS_PROT-1:0]            connect_axi_awprot;

    // wire W Channel
    wire    [DATA_WIDTH-1:0]            connect_axi_wdata;
    wire    [TRANS_W_STRB_W-1:0]        connect_axi_wstrb;
    wire                                connect_axi_wvalid;
    wire                                connect_axi_wready;

    // wire B Channel
    wire    [TRANS_WR_RESP_W-1:0]       connect_axi_bresp;
    wire                                connect_axi_bvalid;
    wire                                connect_axi_bready;

    // wire AR Channel
    wire    [ADDR_WIDTH-1:0]            connect_axi_araddr;
    wire                                connect_axi_arvalid;
    wire                                connect_axi_arready;
    wire    [TRANS_PROT-1:0]            connect_axi_arprot;

    // wire R Channel
    wire    [DATA_WIDTH-1:0]            connect_axi_rdata;
    wire    [TRANS_WR_RESP_W-1:0]       connect_axi_rresp;
    wire                                connect_axi_rvalid;
    wire                                connect_axi_rready;

    wire                                connect_grant_permission_W_W;
    wire                                connect_grant_permission_B_W;
    wire                                connect_grant_permission_R_R;



    generate
        if (NUM_MASTERS == 1) begin
            axi_interconnect_1_n #(
                .ADDR_WIDTH(ADDR_WIDTH),
                .DATA_WIDTH(DATA_WIDTH),
                .TRANS_W_STRB_W(TRANS_W_STRB_W),
                .TRANS_WR_RESP_W(TRANS_WR_RESP_W),
                .TRANS_PROT(TRANS_PROT),
                .NUM_MASTERS(NUM_MASTERS),
                .NUM_SLAVES(NUM_SLAVES),
                .ADDR_MAP_SLAVES(ADDR_MAP_SLAVES)
            ) axi_interconnect_1_n_unit (
                .m_axi_aclk_i(m_axi_aclk_i),
                .m_axi_aresetn_i(m_axi_aresetn_i),

                .m_axi_awaddr_i(m_axi_awaddr_i),
                .m_axi_awvalid_i(m_axi_awvalid_i),
                .m_axi_awready_o(m_axi_awready_o),
                .m_axi_awprot_i(m_axi_awprot_i),

                .m_axi_wdata_i(m_axi_wdata_i),
                .m_axi_wstrb_i(m_axi_wstrb_i),
                .m_axi_wvalid_i(m_axi_wvalid_i),
                .m_axi_wready_o(m_axi_wready_o),

                .m_axi_bresp_o(m_axi_bresp_o),
                .m_axi_bvalid_o(m_axi_bvalid_o),
                .m_axi_bready_i(m_axi_bready_i),

                .m_axi_araddr_i(m_axi_araddr_i),
                .m_axi_arvalid_i(m_axi_arvalid_i),
                .m_axi_arready_o(m_axi_arready_o),
                .m_axi_arprot_i(m_axi_arprot_i),

                .m_axi_rdata_o(m_axi_rdata_o),
                .m_axi_rresp_o(m_axi_rresp_o),
                .m_axi_rvalid_o(m_axi_rvalid_o),
                .m_axi_rready_i(m_axi_rready_i),

                .s_axi_awaddr_o(s_axi_awaddr_o),
                .s_axi_awvalid_o(s_axi_awvalid_o),
                .s_axi_awready_i(s_axi_awready_i),
                .s_axi_awprot_o(s_axi_awprot_o),

                .s_axi_wdata_o(s_axi_wdata_o),
                .s_axi_wstrb_o(s_axi_wstrb_o),
                .s_axi_wvalid_o(s_axi_wvalid_o),
                .s_axi_wready_i(s_axi_wready_i),

                .s_axi_bresp_i(s_axi_bresp_i),
                .s_axi_bvalid_i(s_axi_bvalid_i),
                .s_axi_bready_o(s_axi_bready_o),

                .s_axi_araddr_o(s_axi_araddr_o),
                .s_axi_arvalid_o(s_axi_arvalid_o),
                .s_axi_arready_i(s_axi_arready_i),
                .s_axi_arprot_o(s_axi_arprot_o),

                .s_axi_rdata_i(s_axi_rdata_i),
                .s_axi_rresp_i(s_axi_rresp_i),
                .s_axi_rvalid_i(s_axi_rvalid_i),
                .s_axi_rready_o(s_axi_rready_o),

                .grant_permission_W_W_i(0),
                .grant_permission_B_W_i(0),
                .grant_permission_R_R_i(0)
            );
        end

        else begin
            axi_interconnect_n_1 #(
                .ADDR_WIDTH(ADDR_WIDTH),
                .DATA_WIDTH(DATA_WIDTH),
                .TRANS_W_STRB_W(TRANS_W_STRB_W),
                .TRANS_WR_RESP_W(TRANS_WR_RESP_W),
                .TRANS_PROT(TRANS_PROT),
                .QUANTUM_TIME(QUANTUM_TIME),
                .NUM_MASTERS(NUM_MASTERS),
                .NUM_SLAVES(NUM_SLAVES),
                .ID_MASTERS_MAPS(ID_MASTERS_MAPS)
            ) axi_interconnect_n_1_unit (
                .m_axi_aclk_i(m_axi_aclk_i),
                .m_axi_aresetn_i(m_axi_aresetn_i),

                .m_axi_awaddr_i(m_axi_awaddr_i),
                .m_axi_awvalid_i(m_axi_awvalid_i),
                .m_axi_awready_o(m_axi_awready_o),
                .m_axi_awprot_i(m_axi_awprot_i),

                .m_axi_wdata_i(m_axi_wdata_i),
                .m_axi_wstrb_i(m_axi_wstrb_i),
                .m_axi_wvalid_i(m_axi_wvalid_i),
                .m_axi_wready_o(m_axi_wready_o),

                .m_axi_bresp_o(m_axi_bresp_o),
                .m_axi_bvalid_o(m_axi_bvalid_o),
                .m_axi_bready_i(m_axi_bready_i),

                .m_axi_araddr_i(m_axi_araddr_i),
                .m_axi_arvalid_i(m_axi_arvalid_i),
                .m_axi_arready_o(m_axi_arready_o),
                .m_axi_arprot_i(m_axi_arprot_i),

                .m_axi_rdata_o(m_axi_rdata_o),
                .m_axi_rresp_o(m_axi_rresp_o),
                .m_axi_rvalid_o(m_axi_rvalid_o),
                .m_axi_rready_i(m_axi_rready_i),

                .s_axi_awaddr_o(connect_axi_awaddr),
                .s_axi_awvalid_o(connect_axi_awvalid),
                .s_axi_awready_i(connect_axi_awready),
                .s_axi_awprot_o(connect_axi_awprot),

                .s_axi_wdata_o(connect_axi_wdata),
                .s_axi_wstrb_o(connect_axi_wstrb),
                .s_axi_wvalid_o(connect_axi_wvalid),
                .s_axi_wready_i(connect_axi_wready),

                .s_axi_bresp_i(connect_axi_bresp),
                .s_axi_bvalid_i(connect_axi_bvalid),
                .s_axi_bready_o(connect_axi_bready),

                .s_axi_araddr_o(connect_axi_araddr),
                .s_axi_arvalid_o(connect_axi_arvalid),
                .s_axi_arready_i(connect_axi_arready),
                .s_axi_arprot_o(connect_axi_arprot),

                .s_axi_rdata_i(connect_axi_rdata),
                .s_axi_rresp_i(connect_axi_rresp),
                .s_axi_rvalid_i(connect_axi_rvalid),
                .s_axi_rready_o(connect_axi_rready),

                .grant_permission_W_W_o(connect_grant_permission_W_W),
                .grant_permission_B_W_o(connect_grant_permission_B_W),
                .grant_permission_R_R_o(connect_grant_permission_R_R)
            );
            

            axi_interconnect_1_n #(
                .ADDR_WIDTH(ADDR_WIDTH),
                .DATA_WIDTH(DATA_WIDTH),
                .TRANS_W_STRB_W(TRANS_W_STRB_W),
                .TRANS_WR_RESP_W(TRANS_WR_RESP_W),
                .TRANS_PROT(TRANS_PROT),
                .NUM_MASTERS(NUM_MASTERS),
                .NUM_SLAVES(NUM_SLAVES),
                .ADDR_MAP_SLAVES(ADDR_MAP_SLAVES)
            ) axi_interconnect_1_n_unit (
                .m_axi_aclk_i(m_axi_aclk_i),
                .m_axi_aresetn_i(m_axi_aresetn_i),

                .m_axi_awaddr_i(connect_axi_awaddr),
                .m_axi_awvalid_i(connect_axi_awvalid),
                .m_axi_awready_o(connect_axi_awready),
                .m_axi_awprot_i(connect_axi_awprot),

                .m_axi_wdata_i(connect_axi_wdata),
                .m_axi_wstrb_i(connect_axi_wstrb),
                .m_axi_wvalid_i(connect_axi_wvalid),
                .m_axi_wready_o(connect_axi_wready),

                .m_axi_bresp_o(connect_axi_bresp),
                .m_axi_bvalid_o(connect_axi_bvalid),
                .m_axi_bready_i(connect_axi_bready),

                .m_axi_araddr_i(connect_axi_araddr),
                .m_axi_arvalid_i(connect_axi_arvalid),
                .m_axi_arready_o(connect_axi_arready),
                .m_axi_arprot_i(connect_axi_arprot),

                .m_axi_rdata_o(connect_axi_rdata),
                .m_axi_rresp_o(connect_axi_rresp),
                .m_axi_rvalid_o(connect_axi_rvalid),
                .m_axi_rready_i(connect_axi_rready),

                .s_axi_awaddr_o(s_axi_awaddr_o),
                .s_axi_awvalid_o(s_axi_awvalid_o),
                .s_axi_awready_i(s_axi_awready_i),
                .s_axi_awprot_o(s_axi_awprot_o),

                .s_axi_wdata_o(s_axi_wdata_o),
                .s_axi_wstrb_o(s_axi_wstrb_o),
                .s_axi_wvalid_o(s_axi_wvalid_o),
                .s_axi_wready_i(s_axi_wready_i),

                .s_axi_bresp_i(s_axi_bresp_i),
                .s_axi_bvalid_i(s_axi_bvalid_i),
                .s_axi_bready_o(s_axi_bready_o),

                .s_axi_araddr_o(s_axi_araddr_o),
                .s_axi_arvalid_o(s_axi_arvalid_o),
                .s_axi_arready_i(s_axi_arready_i),
                .s_axi_arprot_o(s_axi_arprot_o),

                .s_axi_rdata_i(s_axi_rdata_i),
                .s_axi_rresp_i(s_axi_rresp_i),
                .s_axi_rvalid_i(s_axi_rvalid_i),
                .s_axi_rready_o(s_axi_rready_o),

                .grant_permission_W_W_i(connect_grant_permission_W_W),
                .grant_permission_B_W_i(connect_grant_permission_B_W),
                .grant_permission_R_R_i(connect_grant_permission_R_R)
            );

        end
    endgenerate

endmodule
