`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 07/25/2025 11:12:49 AM
// Design Name: 
// Module Name: axi_lite_slave_interface
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

module axi_lite_slave_interface#(
    parameter ADDR_WIDTH = 32,          // Address width
    parameter DATA_WIDTH = 32,          // Data width
    parameter TRANS_W_STRB_W = 4,       // width strobe
    parameter TRANS_WR_RESP_W = 2,      // width response
    parameter TRANS_PROT      = 3,
    parameter CYCLE_CLOCK = 2,
    parameter NUM_MASTERS = 1
)(
    input                               clk_i,
    input                               resetn_i,

    // AXI-Lite Write Address Channels
    input       [ADDR_WIDTH-1:0]        i_axi_awaddr,
    input                               i_axi_awvalid,
    output                              o_axi_awready,
    input       [TRANS_PROT-1:0]        i_axi_awprot,

    // AXI-Lite Write Data Channel
    input       [DATA_WIDTH-1:0]        i_axi_wdata,
    input       [TRANS_W_STRB_W-1:0]    i_axi_wstrb,
    input                               i_axi_wvalid,
    output                              o_axi_wready,

    // AXI-Lite Write Response Channels
    output      [TRANS_WR_RESP_W-1:0]   o_axi_bresp,
    output                              o_axi_bvalid,
    input                               i_axi_bready,

    // AXI-Lite Read Address Channels
    input       [ADDR_WIDTH-1:0]        i_axi_araddr,
    input                               i_axi_arvalid,
    output                              o_axi_arready,
    input       [TRANS_PROT-1:0]        i_axi_arprot,

    // AXI4-Lite Read Data Channel
    output      [DATA_WIDTH-1:0]        o_axi_rdata,
    output                              o_axi_rvalid,
    output      [TRANS_WR_RESP_W-1:0]   o_axi_rresp,
    input                               i_axi_rready,

    // Channel for slave

    
    output      [ADDR_WIDTH-1:0]        o_addr_w,
    output      [TRANS_PROT-1:0]        o_awprot_w,

    output      [3:0]                   o_wen,
    output      [DATA_WIDTH-1:0]        o_data_w,
    output                              o_write_data_w,

    input       [TRANS_WR_RESP_W-1:0]   i_bresp_w,

    output      [ADDR_WIDTH-1:0]        o_addr_r,
    output      [TRANS_PROT-1:0]        o_arprot_r,

    input       [DATA_WIDTH-1:0]        i_data_r,
    input       [TRANS_WR_RESP_W-1:0]   i_rresp_r,
    output                              o_read_data_r

    );

    wire    axi_awready, axi_wready, axi_bvalid;
    wire    axi_awready_pre;
    wire    axi_wready_pre;
    wire    axi_bvalid_pre;

    wire    axi_arready, axi_rvalid;
    wire    axi_rvalid_pre;


    //response write channel
    ///AW//////////////////////////////
    tick_timer #(
        .CYCLE_CLOCK(CYCLE_CLOCK)
    ) AW_slave (
        .clk_i(clk_i),
        .start_i(i_axi_awvalid),
        .resetn_i(resetn_i /*i_axi_awvalid*/),
        .set_i(axi_awready),
        .tick_timer(axi_awready),
        .tick_pre(axi_awready_pre)
    );

    // Instantiate the DFF module
    generate
        if (NUM_MASTERS == 1) begin
            // register_DFF #(
            //     .SIZE_BITS(ADDR_WIDTH)
            // ) register_DFF_AW_0 (
            //     .clk_i(axi_awready),
            //     .resetn_i(resetn_i),
            //     .D_i(i_axi_awaddr),
            //     .Q_o(o_addr_w)
            // );
            register_DFF_new#(
                .SIZE_BITS(ADDR_WIDTH)
            ) register_DFF_AW_0 (
                .clk_i(clk_i),
                .enb_i(axi_awready_pre),
                .resetn_i(resetn_i),
                .D_i(i_axi_awaddr),
                .Q_o(o_addr_w)
            );
        end

        else begin
            // register_DFF_negedge #(
            //     .SIZE_BITS(ADDR_WIDTH)
            // ) register_DFF_AW_0 (
            //     .clkn_i(axi_awready),
            //     .resetn_i(resetn_i),
            //     .D_i(i_axi_awaddr),
            //     .Q_o(o_addr_w)
            // );
            register_DFF_negedge_new #(
                .SIZE_BITS(ADDR_WIDTH)
            ) register_DFF_AW_0 (
                .clkn_i(clk_i),
                .enb_i(axi_awready_pre),
                .resetn_i(resetn_i),
                .D_i(i_axi_awaddr),
                .Q_o(o_addr_w)
            );
        end
    endgenerate
    

    // register_DFF #(
    //     .SIZE_BITS(TRANS_PROT)
    // ) register_DFF_AW_1 (
    //     .clk_i(axi_awready),
    //     .resetn_i(resetn_i),
    //     .D_i(i_axi_awprot),
    //     .Q_o(o_awprot_w)
    // );

    register_DFF_new #(
        .SIZE_BITS(TRANS_PROT)
    ) register_DFF_AW_1 (
        .clk_i(clk_i),
        .enb_i(axi_awready_pre),
        .resetn_i(resetn_i),
        .D_i(i_axi_awprot),
        .Q_o(o_awprot_w)
    );

    
    ////////////////////////////W//////////////////////////////
    tick_timer #(
        .CYCLE_CLOCK(CYCLE_CLOCK)
    ) W_slave (
        .clk_i(clk_i),
        .start_i(i_axi_wvalid),
        .resetn_i(resetn_i /*i_axi_wvalid*/),
        .set_i(axi_wready),
        .tick_timer(axi_wready),
        .tick_pre(axi_wready_pre)
    );


    // Instantiate the DFF module
        // register_DFF #(
        //     .SIZE_BITS(DATA_WIDTH)
        // ) register_DFF_W_0 (
        //     .clk_i(axi_wready),
        //     .resetn_i(resetn_i),
        //     .D_i(i_axi_wdata),
        //     .Q_o(o_data_w)
        // );

    register_DFF_new #(
        .SIZE_BITS(DATA_WIDTH)
    ) register_DFF_W_0 (
        .clk_i(clk_i),
        .enb_i(axi_wready_pre),
        .resetn_i(resetn_i),
        .D_i(i_axi_wdata),
        .Q_o(o_data_w)
    );

    // register_DFF #(
    //     .SIZE_BITS(TRANS_W_STRB_W)
    // ) register_DFF_W_1 (
    //     .clk_i(axi_wready),
    //     .resetn_i(resetn_i),
    //     .D_i(i_axi_wstrb),
    //     .Q_o(o_wen)
    // );
    register_DFF_new #(
        .SIZE_BITS(TRANS_W_STRB_W)
    ) register_DFF_W_1 (
        .clk_i(clk_i),
        .enb_i(axi_wready_pre),
        .resetn_i(resetn_i),
        .D_i(i_axi_wstrb),
        .Q_o(o_wen)
    );



    /////////B//////////////////////////////////////
    tick_timer #(
        .CYCLE_CLOCK(CYCLE_CLOCK)
    ) B_slave (
        .clk_i(clk_i),
        .start_i(i_axi_bready),
        .resetn_i(resetn_i /*i_axi_bready*/),
        .set_i(axi_bvalid),
        .tick_timer(axi_bvalid),
        .tick_pre(axi_bvalid_pre)
    );

    // register_DFF #(
    //     .SIZE_BITS(TRANS_WR_RESP_W)
    // ) register_DFF_B_0 (
    //     .clk_i(axi_bvalid),
    //     .resetn_i(resetn_i),
    //     .D_i(i_bresp_w),
    //     .Q_o(o_axi_bresp)
    // );

    register_DFF_new #(
        .SIZE_BITS(TRANS_WR_RESP_W)
    ) register_DFF_B_0 (
        .clk_i(clk_i),
        .enb_i(axi_bvalid_pre),
        .resetn_i(resetn_i),
        .D_i(i_bresp_w),
        .Q_o(o_axi_bresp)
    );





    //response read channel
    tick_timer #(
        .CYCLE_CLOCK(CYCLE_CLOCK)
    ) AR_slave (
        .clk_i(clk_i),
        .start_i(i_axi_arvalid),
        .resetn_i(resetn_i /*i_axi_arvalid*/),
        .set_i(axi_arready),
        .tick_timer(axi_arready)
    );  


    generate
        if (NUM_MASTERS == 1) begin
            // register_DFF #(
            //     .SIZE_BITS(ADDR_WIDTH)
            // ) register_DFF_AR_0 (
            //     .clk_i(axi_arready),
            //     .resetn_i(resetn_i),
            //     .D_i(i_axi_araddr),
            //     .Q_o(o_addr_r)
            // );
            register_DFF_new #(
                .SIZE_BITS(ADDR_WIDTH)
            ) register_DFF_AR_0 (
                .clk_i(clk_i),
                .enb_i(axi_arready),
                .resetn_i(resetn_i),
                .D_i(i_axi_araddr),
                .Q_o(o_addr_r)
            );
        end

        else begin
            // register_DFF_negedge #(
            //     .SIZE_BITS(ADDR_WIDTH)
            // ) register_DFF_AR_0 (
            //     .clkn_i(axi_arready),
            //     .resetn_i(resetn_i),
            //     .D_i(i_axi_araddr),
            //     .Q_o(o_addr_r)
            // );
            register_DFF_negedge_new #(
                .SIZE_BITS(ADDR_WIDTH)
            ) register_DFF_AR_0 (
                .clkn_i(clk_i),
                .enb_i(axi_arready),
                .resetn_i(resetn_i),
                .D_i(i_axi_araddr),
                .Q_o(o_addr_r)
            );
        end
    endgenerate


    // register_DFF #(
    //     .SIZE_BITS(TRANS_PROT)
    // ) register_DFF_AR_1 (
    //     .clk_i(axi_arready),
    //     .resetn_i(resetn_i),
    //     .D_i(i_axi_arprot),
    //     .Q_o(o_arprot_r)
    // );
    register_DFF_new #(
        .SIZE_BITS(TRANS_PROT)
    ) register_DFF_AR_1 (
        .clk_i(clk_i),
        .enb_i(axi_arready),
        .resetn_i(resetn_i),
        .D_i(i_axi_arprot),
        .Q_o(o_arprot_r)
    );



    tick_timer #(
        .CYCLE_CLOCK(CYCLE_CLOCK)
    ) R_slave (
        .clk_i(clk_i),
        .start_i(i_axi_rready),
        .resetn_i(resetn_i /*i_axi_rready*/),
        .set_i(axi_rvalid),
        .tick_timer(axi_rvalid),
        .tick_pre(axi_rvalid_pre)
    );

    // register_DFF #(
    //     .SIZE_BITS(DATA_WIDTH)
    // ) register_DFF_R_0 (
    //     .clk_i(axi_rvalid),
    //     .resetn_i(resetn_i),
    //     .D_i(i_data_r),
    //     .Q_o(o_axi_rdata)
    // );

    register_DFF_new #(
        .SIZE_BITS(DATA_WIDTH)
    ) register_DFF_R_0 (
        .clk_i(clk_i),
        .enb_i(axi_rvalid_pre),
        .resetn_i(resetn_i),
        .D_i(i_data_r),
        .Q_o(o_axi_rdata)
    );

    // register_DFF #(
    //     .SIZE_BITS(TRANS_WR_RESP_W)
    // ) register_DFF_R_1 (
    //     .clk_i(axi_rvalid),
    //     .resetn_i(resetn_i),
    //     .D_i(i_rresp_r),
    //     .Q_o(o_axi_rresp)
    // );

    register_DFF_new #(
        .SIZE_BITS(TRANS_WR_RESP_W)
    ) register_DFF_R_1 (
        .clk_i(clk_i),
        .enb_i(axi_rvalid_pre),
        .resetn_i(resetn_i),
        .D_i(i_rresp_r),
        .Q_o(o_axi_rresp)
    );


    assign  o_axi_awready       = axi_awready;

    assign  o_axi_wready        = axi_wready;
    assign  o_write_data_w      = axi_wready;

    assign  o_axi_bvalid        = axi_bvalid;

    assign  o_axi_arready       = axi_arready;

    assign  o_axi_rvalid        = axi_rvalid;
    assign  o_read_data_r       = axi_rvalid; //i_axi_rready;
    

endmodule




module register_DFF#(
    SIZE_BITS = 32
)(  
    input                           clk_i,
    input                           resetn_i,
    input       [SIZE_BITS-1:0]    D_i,

    output  reg [SIZE_BITS-1:0]    Q_o
);
    always @(posedge clk_i, negedge resetn_i) begin
        if (~resetn_i) begin
            Q_o <= 0;
        end
        else begin
            Q_o <= D_i;
        end
    end

endmodule

module register_DFF_new#(
    SIZE_BITS = 32
)(  
    input                           clk_i,
    input                           resetn_i,
    input                           enb_i,
    input       [SIZE_BITS-1:0]     D_i,

    output  reg [SIZE_BITS-1:0]     Q_o
);
    always @(posedge clk_i, negedge resetn_i) begin
        if (~resetn_i) begin
            Q_o <= 0;
        end
        else begin
            if (enb_i) begin
                Q_o <= D_i;
            end
            // Q_o <= D_i;
        end
    end

endmodule



module register_DFF_negedge#(
    SIZE_BITS = 32
)(  
    input                           clkn_i,
    input                           resetn_i,
    input       [SIZE_BITS-1:0]     D_i,

    output  reg [SIZE_BITS-1:0]     Q_o
);
    always @(negedge clkn_i, negedge resetn_i) begin
        if (~resetn_i) begin
            Q_o <= 0;
        end
        else begin
            Q_o <= D_i;
        end
    end

endmodule


module register_DFF_negedge_new#(
    SIZE_BITS = 32
)(  
    input                           clkn_i,
    input                           resetn_i,
    input                           enb_i,
    input       [SIZE_BITS-1:0]     D_i,

    output  reg [SIZE_BITS-1:0]     Q_o
);
    always @(negedge clkn_i, negedge resetn_i) begin
        if (~resetn_i) begin
            Q_o <= 0;
        end
        else begin
            if (enb_i) begin
                Q_o <= D_i;
            end
            // Q_o <= D_i;
        end
    end

endmodule


module tick_timer#(
    parameter CYCLE_CLOCK = 2 // cycle

)(  
    input   clk_i,
    input   start_i,
    input   resetn_i,
    input   set_i,

    output  tick_timer,
    output  tick_pre

);

    reg [$clog2(CYCLE_CLOCK)-1:0] count_next, count_reg;
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
            if (count_reg >= CYCLE_CLOCK - 1) begin
                count_next = 0;
                tick_next = 1;
            end
            else if (set_i)begin
                count_next = 0;
            end
            else begin  
                count_next = count_next + 1;
                tick_next = 0;
            end
        end
    end

    assign tick_timer = tick_reg;
    assign tick_pre   = tick_next;

endmodule


