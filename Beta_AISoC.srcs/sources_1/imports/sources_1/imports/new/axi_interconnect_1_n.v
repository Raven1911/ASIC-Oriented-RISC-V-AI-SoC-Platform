`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 07/24/2025 01:22:38 AM
// Design Name: 
// Module Name: axi_interconnect_1_n
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



module axi_interconnect_1_n#(
    // Transaction configuration
    parameter ADDR_WIDTH        = 32,          // Address width
    parameter DATA_WIDTH        = 32,          // Data width
    parameter TRANS_W_STRB_W    = 4,       // width strobe
    parameter TRANS_WR_RESP_W   = 2,       // width response
    parameter TRANS_PROT        = 3,

    // Interconnect configuration
    parameter NUM_MASTERS = 16,    // Number of masters (only config parameter of fifo, not config port of master)
    parameter NUM_SLAVES  = 16,    // Number of slaves
    // parameter ADDR_WIDTH_FIFO = $clog2(NUM_MASTERS)+1, // config fifo
    // parameter DATA_WIDTH_FIFO = NUM_SLAVES,           //config fifo
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
    // MASTER PORT
    input                           m_axi_aclk_i,
    input                           m_axi_aresetn_i, 

    // master AW Channel
    input   [ADDR_WIDTH-1:0]        m_axi_awaddr_i,
    input                           m_axi_awvalid_i,
    output                          m_axi_awready_o,
    input   [TRANS_PROT-1:0]        m_axi_awprot_i,

    // master W Channel
    input   [DATA_WIDTH-1:0]        m_axi_wdata_i,
    input   [TRANS_W_STRB_W-1:0]    m_axi_wstrb_i,
    input                           m_axi_wvalid_i,
    output                          m_axi_wready_o,

    // master B Channel
    output  [TRANS_WR_RESP_W-1:0]   m_axi_bresp_o,
    output                          m_axi_bvalid_o,
    input                           m_axi_bready_i,

    // master AR Channel
    input   [ADDR_WIDTH-1:0]        m_axi_araddr_i,
    input                           m_axi_arvalid_i,
    output                          m_axi_arready_o,
    input   [TRANS_PROT-1:0]        m_axi_arprot_i,

    // master R Channel
    output  [DATA_WIDTH-1:0]        m_axi_rdata_o,
    output  [TRANS_WR_RESP_W-1:0]   m_axi_rresp_o,
    output                          m_axi_rvalid_o,
    input                           m_axi_rready_i,


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
    output      [NUM_SLAVES-1:0]                    s_axi_rready_o,


    input                                           grant_permission_W_W_i,
    input                                           grant_permission_B_W_i,
    input                                           grant_permission_R_R_i


    );
    localparam ADDR_WIDTH_FIFO = $clog2(NUM_MASTERS)+1;
    localparam DATA_WIDTH_FIFO = NUM_SLAVES;
    

    wire                                   full_fifo_AW_W, empty_fifo_AW_W, full_fifo_W_B, empty_fifo_W_B;
    wire                                   full_fifo_AR_R, empty_fifo_AR_R;
    wire        [NUM_SLAVES-1:0]           slave_id_AW_W_write;
    wire        [NUM_SLAVES-1:0]           slave_id_AW_W_read;
    wire        [NUM_SLAVES-1:0]           slave_id_W_B_write;
    wire        [NUM_SLAVES-1:0]           slave_id_W_B_read;
    wire        [NUM_SLAVES-1:0]           slave_id_AR_R_write;
    wire        [NUM_SLAVES-1:0]           slave_id_AR_R_read;

    /////////////////////////////
    //WRITE TRANSACTION
    /////////////////////////////
    AW_dispatcher#(
        .ADDR_WIDTH(ADDR_WIDTH),
        .TRANS_PROT(TRANS_PROT),
        .NUM_SLAVES(NUM_SLAVES),
        .ADDR_MAP_SLAVES(ADDR_MAP_SLAVES)
    ) AW_dispatcher_unit (
        .m_axi_awaddr_i(m_axi_awaddr_i),
        .m_axi_awvalid_i(m_axi_awvalid_i),
        .m_axi_awready_o(m_axi_awready_o),
        .m_axi_awprot_i(m_axi_awprot_i),

        .s_axi_awaddr_o(s_axi_awaddr_o),
        .s_axi_awvalid_o(s_axi_awvalid_o),
        .s_axi_awready_i(s_axi_awready_i),
        .s_axi_awprot_o(s_axi_awprot_o),
        .slave_id_o(slave_id_AW_W_write)
    );

    fifo_axi_unit#(
        .ADDR_WIDTH(ADDR_WIDTH_FIFO),
        .DATA_WIDTH(DATA_WIDTH_FIFO)
    ) fifo_AW_W (
        .clk(m_axi_aclk_i), 
        .reset_n(m_axi_aresetn_i),
        .wr((!full_fifo_AW_W) && m_axi_awready_o), 
        .rd(m_axi_wready_o || grant_permission_W_W_i),

        .w_data(slave_id_AW_W_write), //writing data
        .r_data(slave_id_AW_W_read), //reading data

        .full(full_fifo_AW_W), 
        .empty(empty_fifo_AW_W)
    );

    W_dispatcher #(
        .DATA_WIDTH(DATA_WIDTH),
        .TRANS_W_STRB_W(TRANS_W_STRB_W),
        .NUM_SLAVES(NUM_SLAVES)
    ) W_dispatcher_unit (
        .m_axi_wdata_i(m_axi_wdata_i),
        .m_axi_wstrb_i(m_axi_wstrb_i),
        .m_axi_wvalid_i(m_axi_wvalid_i),
        .m_axi_wready_o(m_axi_wready_o),
        .s_axi_wdata_o(s_axi_wdata_o),
        .s_axi_wstrb_o(s_axi_wstrb_o),
        .s_axi_wvalid_o(s_axi_wvalid_o),
        .s_axi_wready_i(s_axi_wready_i),
        .slave_id_i(slave_id_AW_W_read),
        .empty_fifo_i(empty_fifo_AW_W),
        .slave_id_o(slave_id_W_B_write)
    );


    fifo_axi_unit#(
        .ADDR_WIDTH(ADDR_WIDTH_FIFO),
        .DATA_WIDTH(DATA_WIDTH_FIFO)
    ) fifo_W_B (
        .clk(m_axi_aclk_i), 
        .reset_n(m_axi_aresetn_i),
        .wr((!full_fifo_W_B) && m_axi_wready_o), 
        .rd(m_axi_bvalid_o || grant_permission_B_W_i),

        .w_data(slave_id_W_B_write), //writing data
        .r_data(slave_id_W_B_read), //reading data

        .full(full_fifo_W_B), 
        .empty(empty_fifo_W_B)
    );


    B_dispatcher #(
        .TRANS_WR_RESP_W(TRANS_WR_RESP_W),
        .NUM_SLAVES(NUM_SLAVES)
    ) B_dispatcher_unit (
        .m_axi_bresp_o(m_axi_bresp_o),
        .m_axi_bvalid_o(m_axi_bvalid_o),
        .m_axi_bready_i(m_axi_bready_i),
        .s_axi_bresp_i(s_axi_bresp_i),
        .s_axi_bvalid_i(s_axi_bvalid_i),
        .s_axi_bready_o(s_axi_bready_o),
        .slave_id_i(slave_id_W_B_read),
        .empty_fifo_i(empty_fifo_W_B)
    );


    /////////////////////////////
    //READ TRANSACTION
    /////////////////////////////
    AR_dispatcher#(
        .ADDR_WIDTH(ADDR_WIDTH),
        .TRANS_PROT(TRANS_PROT),
        .NUM_SLAVES(NUM_SLAVES),
        .ADDR_MAP_SLAVES(ADDR_MAP_SLAVES)
    ) AR_dispatcher_unit (
        .m_axi_araddr_i(m_axi_araddr_i),
        .m_axi_arvalid_i(m_axi_arvalid_i),
        .m_axi_arready_o(m_axi_arready_o),
        .m_axi_arprot_i(m_axi_arprot_i),

        .s_axi_araddr_o(s_axi_araddr_o),
        .s_axi_arvalid_o(s_axi_arvalid_o),
        .s_axi_arready_i(s_axi_arready_i),
        .s_axi_arprot_o(s_axi_arprot_o),

        .slave_id_o(slave_id_AR_R_write)
    );


    fifo_axi_unit#(
        .ADDR_WIDTH(ADDR_WIDTH_FIFO),
        .DATA_WIDTH(DATA_WIDTH_FIFO)
    ) fifo_AR_R (
        .clk(m_axi_aclk_i), 
        .reset_n(m_axi_aresetn_i),
        .wr((!full_fifo_AR_R) && m_axi_arready_o), 
        .rd(m_axi_rvalid_o || grant_permission_R_R_i),

        .w_data(slave_id_AR_R_write), //writing data
        .r_data(slave_id_AR_R_read), //reading data

        .full(full_fifo_AR_R), 
        .empty(empty_fifo_AR_R)
    );


    R_dispatcher #(
        .DATA_WIDTH(DATA_WIDTH),
        .TRANS_WR_RESP_W(TRANS_WR_RESP_W),
        .NUM_SLAVES(NUM_SLAVES)
    ) R_dispatcher_unit (
        .m_axi_rdata_o(m_axi_rdata_o),
        .m_axi_rresp_o(m_axi_rresp_o),
        .m_axi_rvalid_o(m_axi_rvalid_o),
        .m_axi_rready_i(m_axi_rready_i),

        .s_axi_rdata_i(s_axi_rdata_i),
        .s_axi_rresp_i(s_axi_rresp_i),
        .s_axi_rvalid_i(s_axi_rvalid_i),
        .s_axi_rready_o(s_axi_rready_o),

        .slave_id_i(slave_id_AR_R_read),
        .empty_fifo_i(empty_fifo_AR_R)
    );

endmodule



module AW_dispatcher#(
    // Transaction configuration
    parameter ADDR_WIDTH = 32,          // Address width
    parameter TRANS_PROT = 3,
    // Interconnect configuration
    parameter NUM_SLAVES = 16,    // Number of slaves
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
     // master AW Channel
    input       [ADDR_WIDTH-1:0]                    m_axi_awaddr_i,
    input                                           m_axi_awvalid_i,
    output      reg                                 m_axi_awready_o, 
    input       [TRANS_PROT-1:0]                    m_axi_awprot_i,
    //SLAVES PORT
    // slave AW Channel
    output      [ADDR_WIDTH*NUM_SLAVES-1:0]         s_axi_awaddr_o,
    output      [NUM_SLAVES-1:0]                    s_axi_awvalid_o,
    input       [NUM_SLAVES-1:0]                    s_axi_awready_i,
    output      [TRANS_PROT*NUM_SLAVES-1:0]         s_axi_awprot_o,

    output      [NUM_SLAVES-1:0]                    slave_id_o
);



    wire [NUM_SLAVES-1:0] slave_selected;    
    genvar  slv_count;

    //decoder addr   
    generate
        for (slv_count = 0; slv_count < NUM_SLAVES; slv_count = slv_count + 1) begin
            assign slave_selected[slv_count] = ((m_axi_awaddr_i >= ADDR_MAP_SLAVES[(ADDR_WIDTH*2*slv_count)+(ADDR_WIDTH*2)-1 -: ADDR_WIDTH]) && (m_axi_awaddr_i <= ADDR_MAP_SLAVES[(ADDR_WIDTH*2*slv_count)+ADDR_WIDTH-1 -: ADDR_WIDTH]) && m_axi_awvalid_i);
        end
    endgenerate

    //connect awaddr master to slave
    generate
        for (slv_count = 0; slv_count < NUM_SLAVES; slv_count = slv_count + 1) begin
            assign s_axi_awaddr_o[((ADDR_WIDTH*slv_count)+ADDR_WIDTH-1) -: ADDR_WIDTH] = (slave_selected[slv_count]) ?  m_axi_awaddr_i : 0;
        end
    endgenerate

    //connect awvalid master to slave
    generate
        for (slv_count = 0; slv_count < NUM_SLAVES; slv_count = slv_count + 1) begin
            assign s_axi_awvalid_o[slv_count] = (slave_selected[slv_count]) ?  m_axi_awvalid_i : 0;
        end
    endgenerate

    //connect awprot master to slave
    generate
        for (slv_count = 0; slv_count < NUM_SLAVES; slv_count = slv_count + 1) begin
            assign s_axi_awprot_o[((TRANS_PROT*slv_count)+TRANS_PROT-1) -: TRANS_PROT] = (slave_selected[slv_count]) ?  m_axi_awprot_i : 0;
        end
    endgenerate

    //connect awready slave to master
    // integer i;
    // always @(*) begin
    //     m_axi_awready_o = 0;
    //     for (i = 0; i < NUM_SLAVES; i = i + 1) begin
    //         if (slave_selected[i]) begin
    //             m_axi_awready_o = s_axi_awready_i[i];
    //         end
    //     end
    // end

    integer i;
    always @(*) begin
        m_axi_awready_o = 0;
        for (i = 0; i < NUM_SLAVES; i = i + 1) begin
            m_axi_awready_o = |(s_axi_awready_i & slave_selected);
        end
    end
    


    assign slave_id_o = slave_selected;

endmodule


module W_dispatcher#(
    // Transaction configuration
    parameter DATA_WIDTH = 32,          // Data width
    parameter TRANS_W_STRB_W = 4,       // width strobe
    // Interconnect configuration
    parameter NUM_SLAVES = 16            // Number of slaves
)(
    // master W Channel
    input   [DATA_WIDTH-1:0]        m_axi_wdata_i,
    input   [TRANS_W_STRB_W-1:0]    m_axi_wstrb_i,
    input                           m_axi_wvalid_i,
    output reg                      m_axi_wready_o,

    // slave W Channel
    output      [DATA_WIDTH*NUM_SLAVES-1:0]         s_axi_wdata_o,
    output      [TRANS_W_STRB_W*NUM_SLAVES-1:0]     s_axi_wstrb_o,
    output      [NUM_SLAVES-1:0]                    s_axi_wvalid_o,
    input       [NUM_SLAVES-1:0]                    s_axi_wready_i,

    //
    input       [NUM_SLAVES-1:0]                    slave_id_i,
    input                                           empty_fifo_i,
    output      [NUM_SLAVES-1:0]                    slave_id_o
);

    wire [NUM_SLAVES-1:0] slave_selected;

    genvar  slv_count;

    //connect wdata master to slave
    generate
        for (slv_count = 0; slv_count < NUM_SLAVES; slv_count = slv_count + 1) begin
            assign s_axi_wdata_o[((DATA_WIDTH*slv_count)+DATA_WIDTH-1) -: DATA_WIDTH] = (slave_selected[slv_count]) ? m_axi_wdata_i : 0;
        end
    endgenerate

    //connect wstrb master to slave
    generate
        for (slv_count = 0; slv_count < NUM_SLAVES; slv_count = slv_count + 1) begin
            assign s_axi_wstrb_o[((TRANS_W_STRB_W*slv_count)+TRANS_W_STRB_W-1) -: TRANS_W_STRB_W] = (slave_selected[slv_count]) ?  m_axi_wstrb_i : 0;
        end
    endgenerate

    //connect wvalid master to slave
    generate
        for (slv_count = 0; slv_count < NUM_SLAVES; slv_count = slv_count + 1) begin
            assign s_axi_wvalid_o[slv_count] = (slave_selected[slv_count]) ?  m_axi_wvalid_i : 0;
        end
    endgenerate


    //connect wready slave to master
    // integer i;
    // always @(*) begin
    //     m_axi_wready_o = 0;
    //     for (i = 0; i < NUM_SLAVES; i = i + 1) begin
    //         if (slave_selected[i]) begin
    //             m_axi_wready_o = s_axi_wready_i[i];
    //         end
    //     end
    // end

    integer i;
    always @(*) begin
        m_axi_wready_o = 0;
        for (i = 0; i < NUM_SLAVES; i = i + 1) begin
            m_axi_wready_o = | (s_axi_wready_i & slave_selected);
        end
    end

    assign slave_selected = (!empty_fifo_i && m_axi_wvalid_i) ? slave_id_i : 0;
    assign slave_id_o = slave_selected; 

endmodule



module B_dispatcher#(
    // Transaction configuration
    parameter TRANS_WR_RESP_W = 2,       // width response

    // Interconnect configuration
    parameter NUM_SLAVES  = 16    // Number of slaves
)(

    // master B Channel
    output  reg [TRANS_WR_RESP_W-1:0]   m_axi_bresp_o,
    output  reg                         m_axi_bvalid_o,
    input                               m_axi_bready_i,

    // slave B Channel
    input       [TRANS_WR_RESP_W*NUM_SLAVES-1:0]    s_axi_bresp_i,
    input       [NUM_SLAVES-1:0]                    s_axi_bvalid_i,
    output      [NUM_SLAVES-1:0]                    s_axi_bready_o,

    //
    input       [NUM_SLAVES-1:0]                    slave_id_i,
    input                                           empty_fifo_i


);
    wire [NUM_SLAVES-1:0] slave_selected;

    genvar  slv_count;
    //connect bready master to slave
    generate
        for (slv_count = 0; slv_count < NUM_SLAVES; slv_count = slv_count + 1) begin
            assign s_axi_bready_o[slv_count] = (slave_selected[slv_count]) ?  m_axi_bready_i : 0;
        end
    endgenerate


    //connect bvalid slave to master
    // integer i;
    // always @(*) begin
    //     m_axi_bvalid_o = 0;
    //     m_axi_bresp_o  = 0;
    //     for (i = 0; i < NUM_SLAVES; i = i + 1) begin
    //         if (slave_selected[i]) begin
    //             m_axi_bvalid_o = s_axi_bvalid_i[i];
    //             m_axi_bresp_o  = s_axi_bresp_i[((TRANS_WR_RESP_W*i) + TRANS_WR_RESP_W -1) -: TRANS_WR_RESP_W];
    //         end
    //     end
    // end

    integer i;
    always @(*) begin
        m_axi_bvalid_o = 0;
        m_axi_bresp_o  = {TRANS_WR_RESP_W{1'b0}};
        for (i = 0; i < NUM_SLAVES; i = i + 1) begin
            m_axi_bvalid_o = |(s_axi_bvalid_i & slave_selected);
            m_axi_bresp_o  = m_axi_bresp_o | ({TRANS_WR_RESP_W{slave_selected[i]}} & s_axi_bresp_i[((TRANS_WR_RESP_W*i) + TRANS_WR_RESP_W -1) -: TRANS_WR_RESP_W]);
        end
    end

    assign slave_selected = (!empty_fifo_i && m_axi_bready_i) ? slave_id_i : 0;

endmodule


module AR_dispatcher#(
    // Transaction configuration
    parameter ADDR_WIDTH = 32,          // Address width
    parameter TRANS_PROT = 3,
    // Interconnect configuration
    parameter NUM_SLAVES  = 16,    // Number of slaves
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

    // master AR Channel
    input       [ADDR_WIDTH-1:0]                    m_axi_araddr_i,
    input                                           m_axi_arvalid_i,
    output reg                                      m_axi_arready_o,
    input       [TRANS_PROT-1:0]                    m_axi_arprot_i,

    // slave AR Channel
    output      [ADDR_WIDTH*NUM_SLAVES-1:0]         s_axi_araddr_o,
    output      [NUM_SLAVES-1:0]                    s_axi_arvalid_o,
    input       [NUM_SLAVES-1:0]                    s_axi_arready_i,
    output      [TRANS_PROT*NUM_SLAVES-1:0]         s_axi_arprot_o, 

    output      [NUM_SLAVES-1:0]                    slave_id_o

);

    wire [NUM_SLAVES-1:0] slave_selected;    
    genvar  slv_count;

    //decoder addr   
    generate
        for (slv_count = 0; slv_count < NUM_SLAVES; slv_count = slv_count + 1) begin
            assign slave_selected[slv_count] = ((m_axi_araddr_i >= ADDR_MAP_SLAVES[(ADDR_WIDTH*2*slv_count)+(ADDR_WIDTH*2)-1 -: ADDR_WIDTH]) && (m_axi_araddr_i <= ADDR_MAP_SLAVES[(ADDR_WIDTH*2*slv_count)+ADDR_WIDTH-1 -: ADDR_WIDTH]) && m_axi_arvalid_i) ;
        end
    endgenerate

    //connect araddr master to slave
    generate
        for (slv_count = 0; slv_count < NUM_SLAVES; slv_count = slv_count + 1) begin
            assign s_axi_araddr_o[((ADDR_WIDTH*slv_count)+ADDR_WIDTH-1) -: ADDR_WIDTH] = (slave_selected[slv_count]) ?  m_axi_araddr_i : 0;
        end
    endgenerate

    //connect arvalid master to slave
    generate
        for (slv_count = 0; slv_count < NUM_SLAVES; slv_count = slv_count + 1) begin
            assign s_axi_arvalid_o[slv_count] = (slave_selected[slv_count]) ?  m_axi_arvalid_i : 0;
        end
    endgenerate

    //connect arprot master to slave
    generate
        for (slv_count = 0; slv_count < NUM_SLAVES; slv_count = slv_count + 1) begin
            assign s_axi_arprot_o[((TRANS_PROT*slv_count)+TRANS_PROT-1) -: TRANS_PROT] = (slave_selected[slv_count]) ?  m_axi_arprot_i : 0;
        end
    endgenerate


    //connect arready slave to master
    // integer i;
    // always @(*) begin
    //     m_axi_arready_o = 0;
    //     for (i = 0; i < NUM_SLAVES; i = i + 1) begin
    //         if (slave_selected[i]) begin
    //             m_axi_arready_o = s_axi_arready_i[i];
    //         end
    //     end
    // end

    integer i;
    always @(*) begin
        m_axi_arready_o = 0;
        for (i = 0; i < NUM_SLAVES; i = i + 1) begin
            m_axi_arready_o = |(s_axi_arready_i & slave_selected);
        end
    end

    assign slave_id_o = slave_selected;

endmodule




module R_dispatcher#(
    // Transaction configuration
    parameter DATA_WIDTH = 32,          // Data width
    parameter TRANS_WR_RESP_W = 2,       // width response
    // Interconnect configuration
    parameter NUM_SLAVES  = 16          // Number of slaves
)(
    // master R Channel
    output reg  [DATA_WIDTH-1:0]        m_axi_rdata_o,
    output reg  [TRANS_WR_RESP_W-1:0]   m_axi_rresp_o,
    output reg                          m_axi_rvalid_o,
    input                               m_axi_rready_i,

    // slave R Channel
    input       [DATA_WIDTH*NUM_SLAVES-1:0]         s_axi_rdata_i,
    input       [TRANS_WR_RESP_W*NUM_SLAVES-1:0]    s_axi_rresp_i,
    input       [NUM_SLAVES-1:0]                    s_axi_rvalid_i,
    output      [NUM_SLAVES-1:0]                    s_axi_rready_o,

    //
    input       [NUM_SLAVES-1:0]                    slave_id_i,
    input                                           empty_fifo_i

);
    wire [NUM_SLAVES-1:0] slave_selected;
    
    genvar  slv_count;

    generate
        for (slv_count = 0; slv_count < NUM_SLAVES; slv_count = slv_count + 1) begin
            assign s_axi_rready_o[slv_count] = (slave_selected[slv_count]) ?  m_axi_rready_i : 0;
        end
    endgenerate

    //connect slave to master
    // integer i;
    // always @(*) begin
    //     m_axi_rvalid_o = 0;
    //     m_axi_rresp_o  = 0;
    //     m_axi_rdata_o  = 0;
    //     for (i = 0; i < NUM_SLAVES; i = i + 1) begin
    //         if (slave_selected[i]) begin
    //             m_axi_rvalid_o = s_axi_rvalid_i[i];
    //             m_axi_rresp_o  = s_axi_rresp_i[((TRANS_WR_RESP_W*i) + TRANS_WR_RESP_W -1) -: TRANS_WR_RESP_W];
    //             m_axi_rdata_o  = s_axi_rdata_i[((DATA_WIDTH*i) + DATA_WIDTH -1) -: DATA_WIDTH];
    //         end
    //     end
    // end

    integer i;
    always @(*) begin
        m_axi_rvalid_o = 0;
        m_axi_rresp_o  = {TRANS_WR_RESP_W{1'b0}};
        m_axi_rdata_o  = {DATA_WIDTH{1'b0}};
        for (i = 0; i < NUM_SLAVES; i = i + 1) begin
            m_axi_rvalid_o = |(s_axi_rvalid_i & slave_selected);
            m_axi_rresp_o  = m_axi_rresp_o | ({TRANS_WR_RESP_W{slave_selected[i]}} & s_axi_rresp_i[((TRANS_WR_RESP_W*i) + TRANS_WR_RESP_W -1) -: TRANS_WR_RESP_W]);
            m_axi_rdata_o  = m_axi_rdata_o | ({DATA_WIDTH{slave_selected[i]}} & s_axi_rdata_i[((DATA_WIDTH*i) + DATA_WIDTH -1) -: DATA_WIDTH]);
        end
    end


    assign slave_selected = (!empty_fifo_i && m_axi_rready_i) ? slave_id_i : 0;
endmodule



//module fifo
module fifo_axi_unit #(parameter ADDR_WIDTH = 3, DATA_WIDTH = 8)(
    input clk, reset_n,
    input wr, rd,

    input [DATA_WIDTH - 1 : 0] w_data, //writing data
    output [DATA_WIDTH - 1 : 0] r_data, //reading data

    output full, empty

    );

    //signal
    wire [ADDR_WIDTH - 1 : 0] w_addr, r_addr;

    //instantiate registers file
    register_file_axi #(.ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH))
        reg_file_axi_unit(
            .clk(clk),
            .w_en(~full & wr),

            .r_addr(r_addr), //reading address
            .w_addr(w_addr), //writing address

            .w_data(w_data), //writing data
            .r_data(r_data) //reading data
        
        );

    //instantiate fifo ctrl
    fifo_ctrl_axi #(.ADDR_WIDTH(ADDR_WIDTH))
        fifo_ctrl_axi_unit(
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


module fifo_ctrl_axi #(parameter ADDR_WIDTH = 3)(
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



module register_file_axi #(parameter ADDR_WIDTH = 3, DATA_WIDTH = 8)(
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
