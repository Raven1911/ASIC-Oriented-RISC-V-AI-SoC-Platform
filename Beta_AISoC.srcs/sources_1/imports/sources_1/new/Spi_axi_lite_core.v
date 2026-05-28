`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 07/12/2025 01:11:26 AM
// Design Name: 
// Module Name: Spi_axi_lite_core
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



module Spi_axi_lite_core#(
    parameter NUM_MASTERS = 1,
    parameter NSlave = 2,
    parameter ADDR_WIDTH = 32,          // Address width
    parameter DATA_WIDTH = 32,          // Data width
    parameter TRANS_W_STRB_W = 4,       // width strobe
    parameter TRANS_WR_RESP_W = 2,      // width response
    parameter TRANS_PROT      = 3,
    parameter CYCLE_CLOCK = 2,
    //config register timer
    parameter [ADDR_WIDTH-1:0] ADDR_REGISTERS_0 = 32'h0200_3000,
    parameter [ADDR_WIDTH-1:0] ADDR_REGISTERS_1 = 32'h0200_3004,
    parameter [ADDR_WIDTH-1:0] ADDR_REGISTERS_2 = 32'h0200_3008,
    parameter [ADDR_WIDTH-1:0] ADDR_REGISTERS_3 = 32'h0200_300C


)(
    input clk,
    input resetn,

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

    //external logic
    output                          spi_clk,
    output                          spi_mosi,
    input                           spi_miso,
    output reg [NSlave-1:0]         spi_ss_n
    );

    
    //signals to connect
    //wire [3:0] o_wen;
    wire [ADDR_WIDTH-1:0] o_addr_w;
    wire [ADDR_WIDTH-1:0] o_addr_r;                
    wire [DATA_WIDTH-1:0] o_data_w;
    wire [DATA_WIDTH-1:0] i_data_r;

    wire o_wr_w;
    wire o_rd_r;


    //
    wire rd_spi, wr_ss, wr_spi, wr_ctrl;
    //reg [17:0] ctrl_reg;
    //reg [NSlave-1:0] ss_n_reg;
    wire [7:0] spi_out;
    wire spi_ready;
    reg cpol, cpha;
    reg [15:0] dvsr;


    //seq
    always @(posedge clk, negedge resetn) begin
        if(~resetn) begin
            {cpha, cpol, dvsr} <= 17'h0_0200;
            spi_ss_n <= {NSlave{1'b1}};
        end

        else begin
            if (wr_ctrl) begin
                //ctrl_reg <=  o_data_w[17:0];
                dvsr <= o_data_w[15:0];
                cpol <= o_data_w[16];
                cpha <= o_data_w[17];
            end    
            
            if (wr_ss)  spi_ss_n <=  o_data_w[NSlave-1:0];
            //if (rd_spi) i_data_r <= {23'b0, spi_ready, spi_out};
        end
    end

    //decoding
    assign rd_spi   = (o_rd_r && (o_addr_r[31:0] == ADDR_REGISTERS_0)) ? 1 : 0;
    assign wr_ss    = (o_wr_w && (o_addr_w[31:0] == ADDR_REGISTERS_1)) ? 1 : 0;
    assign wr_spi   = (o_wr_w && (o_addr_w[31:0] == ADDR_REGISTERS_2)) ? 1 : 0;
    assign wr_ctrl  = (o_wr_w && (o_addr_w[31:0] == ADDR_REGISTERS_3)) ? 1 : 0;

    //read multiplexing
    assign i_data_r = {23'b0, spi_ready, spi_out};

    Spi #(.DATA_WITH(8)) Spi_unit
    (
        .clk(clk),
        .resetn(resetn),
        .din(o_data_w[7:0]),
        .dvsr(dvsr), //0.5*(# clk in SCK period)
        .start(wr_spi),
        .cpol(cpol),
        .cpha(cpha),
        .dout(spi_out),
        .spi_done_tick(),
        .ready(spi_ready),

        //spi interface
        .sclk(spi_clk),
        .miso(spi_miso),
        .mosi(spi_mosi)    

    );

    // // Instantiate axi interface module
    // axi_lite_interface_spi #(
    //     .ADDR_WIDTH(ADDR_WIDTH),
    //     .DATA_WIDTH(DATA_WIDTH)
    // ) axi_adapter(
    //     .clk(clk),
    //     .resetn(resetn),

    //     //AXI-Lite Write Address Channels
    //     .i_axi_awaddr(i_axi_awaddr),
    //     .i_axi_awvalid(i_axi_awvalid),
    //     .o_axi_awready(o_axi_awready),

    //     //AXI-Lite Write Data Channel
    //     .i_axi_wdata(i_axi_wdata),
    //     .i_axi_wstrb(i_axi_wstrb),
    //     .i_axi_wvalid(i_axi_wvalid),
    //     .o_axi_wready(o_axi_wready),

    //     //AXI-Lite Write Response Channels
    //     .o_axi_bvalid(o_axi_bvalid),
    //     .i_axi_bready(i_axi_bready),

    //     //AXI-Lite Read Address Channels
    //     .i_axi_araddr(i_axi_araddr),
    //     .i_axi_arvalid(i_axi_arvalid),
    //     .o_axi_arready(o_axi_arready),

    //     //AXI4-Lite Read Data Channel
    //     .o_axi_rdata(o_axi_rdata),
    //     .o_axi_rvalid(o_axi_rvalid),
    //     .i_axi_rready(i_axi_rready),    

    //     //channel for slave
    //     .o_wen(),
    //     .o_addr_w(o_addr_w),
    //     .o_addr_r(o_addr_r),             
    //     .o_data_w(o_data_w),
    //     .i_data_r(i_data_r),
    //     .o_wr_w(o_wr_w),
    //     .o_rd_r(o_rd_r)
    // );


    axi_lite_slave_interface #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .TRANS_W_STRB_W(TRANS_W_STRB_W),
        .TRANS_WR_RESP_W(TRANS_WR_RESP_W),
        .TRANS_PROT(TRANS_PROT),
        .CYCLE_CLOCK(CYCLE_CLOCK),
        .NUM_MASTERS(NUM_MASTERS)
    ) spi0_axi_lite_interface (
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

        .o_addr_w(o_addr_w),
        .o_awprot_w(),

        .o_wen(),       
        .o_data_w(o_data_w),
        .o_write_data_w(o_wr_w),

        .i_bresp_w('b00),

        .o_addr_r(o_addr_r),
        .o_arprot_r(),
        
        .i_data_r(i_data_r),
        .i_rresp_r('b00),
        .o_read_data_r(o_rd_r)
    );


    



endmodule


// module axi_lite_interface_spi #(
//     parameter ADDR_WIDTH = 32,
//     parameter DATA_WIDTH = 32
// )(  
//     input clk,
//     input resetn,

//     // AXI-Lite Write Address Channels
//     input [ADDR_WIDTH-1:0] i_axi_awaddr,
//     input i_axi_awvalid,
//     output reg o_axi_awready,

//     // AXI-Lite Write Data Channel
//     input [DATA_WIDTH-1:0] i_axi_wdata,
//     input [3:0] i_axi_wstrb,
//     input i_axi_wvalid,
//     output reg o_axi_wready,

//     // AXI-Lite Write Response Channels
//     output reg o_axi_bvalid,
//     input i_axi_bready,

//     // AXI-Lite Read Address Channels
//     input [ADDR_WIDTH-1:0] i_axi_araddr,
//     input i_axi_arvalid,
//     output reg o_axi_arready,

//     // AXI4-Lite Read Data Channel
//     output reg [DATA_WIDTH-1:0] o_axi_rdata,
//     output reg o_axi_rvalid,
//     input i_axi_rready,

//     // Channel for slave
//     output reg [3:0] o_wen,
//     output reg [ADDR_WIDTH-1:0] o_addr_w,
//     output wire [ADDR_WIDTH-1:0] o_addr_r,             
//     output reg [DATA_WIDTH-1:0] o_data_w,
//     input wire [DATA_WIDTH-1:0] i_data_r,
//     output reg o_wr_w,
//     output reg o_rd_r
// );

//     // State declaration
//     // Write channel FSM
//     localparam W_ADDRESS   = 2'b00;
//     localparam W_WRITE     = 2'b01;
//     localparam W_RESPONSE  = 2'b10;

//     // Read channel FSM
//     localparam R_ADDRESS   = 2'b00;
//     localparam R_READ      = 2'b01;

//     reg [1:0] W_state, R_state; // Current FSM states
//     reg [1:0] W_state_next, R_state_next; // Next FSM states

//     // Next value registers for outputs
//     reg o_axi_awready_next, o_axi_wready_next, o_axi_bvalid_next;
//     reg o_axi_arready_next, o_axi_rvalid_next;
//     reg [DATA_WIDTH-1:0] o_axi_rdata_next;
//     reg [3:0] o_wen_next;
//     reg [ADDR_WIDTH-1:0] o_addr_w_next;
//     reg [DATA_WIDTH-1:0] o_data_w_next;
//     reg o_wr_w_next, o_rd_r_next;

//     // Sequential circuit: Update states and outputs
//     always @(posedge clk or negedge resetn) begin
//         if (~resetn) begin
//             W_state <= W_ADDRESS;
//             R_state <= R_ADDRESS;
//             o_axi_awready <= 0;
//             o_axi_wready <= 0;
//             o_axi_bvalid <= 0;
//             o_axi_arready <= 0;
//             o_axi_rvalid <= 0;
//             o_axi_rdata <= 0;
//             o_wen <= 4'b0000;
//             o_addr_w <= 0;
//             o_data_w <= 0;
//             o_wr_w <= 0;
//             o_rd_r <= 0;
//         end
//         else begin
//             W_state <= W_state_next;
//             R_state <= R_state_next;
//             o_axi_awready <= o_axi_awready_next;
//             o_axi_wready <= o_axi_wready_next;
//             o_axi_bvalid <= o_axi_bvalid_next;
//             o_axi_arready <= o_axi_arready_next;
//             o_axi_rvalid <= o_axi_rvalid_next;
//             o_axi_rdata <= o_axi_rdata_next;
//             o_wen <= o_wen_next;
//             o_addr_w <= o_addr_w_next;
//             o_data_w <= o_data_w_next;
//             o_wr_w <= o_wr_w_next;
//             o_rd_r <= o_rd_r_next;
//         end
//     end

//     // Combinational circuit: Determine next states and outputs
//     always @(*) begin
//         // Default values
//         W_state_next = W_state;
//         R_state_next = R_state;
//         o_axi_awready_next = 0;
//         o_axi_wready_next = 0;
//         o_axi_bvalid_next = 0;
//         o_axi_arready_next = 0;
//         o_axi_rvalid_next = 0;
//         o_axi_rdata_next = o_axi_rdata;
//         o_wen_next = 4'b0000;
//         o_addr_w_next = o_addr_w;
//         o_data_w_next = o_data_w;
//         o_wr_w_next = 0;
//         o_rd_r_next = 0;

//         // Write channel FSM
//         case (W_state)
//             W_ADDRESS: begin
//                 o_axi_bvalid_next = 0;
//                 o_wr_w_next = 0;
//                 if (i_axi_awvalid) begin
//                     o_axi_awready_next = 1;
//                     o_addr_w_next = i_axi_awaddr;
//                     W_state_next = W_WRITE;
//                 end
//             end
//             W_WRITE: begin
//                 o_axi_awready_next = 0;
//                 if (i_axi_wvalid) begin
//                     o_axi_wready_next = 1;
//                     o_wen_next = i_axi_wstrb;
//                     o_data_w_next = i_axi_wdata;
//                     W_state_next = W_RESPONSE;
//                 end
//             end
//             W_RESPONSE: begin
//                 o_axi_wready_next = 0;
//                 o_wen_next = 4'b0000;
//                 if (i_axi_bready) begin
//                     o_axi_bvalid_next = 1;
//                     o_wr_w_next = 1;
//                     W_state_next = W_ADDRESS;
//                 end
//             end
//             default: begin
//                 W_state_next = W_ADDRESS;
//             end
//         endcase

//         // Read channel FSM
//         case (R_state)
//             R_ADDRESS: begin
//                 o_axi_rvalid_next = 0;
//                 o_rd_r_next = 0;
//                 if (i_axi_arvalid) begin
//                     o_axi_arready_next = 1;
//                     R_state_next = R_READ;
//                 end
//             end
//             R_READ: begin
//                 o_axi_arready_next = 0;
//                 if (i_axi_rready) begin
//                     o_axi_rvalid_next = 1;
//                     o_rd_r_next = 1;
//                     o_axi_rdata_next = i_data_r;
//                     R_state_next = R_ADDRESS;
//                 end
//             end
//             default: begin
//                 R_state_next = R_ADDRESS;
//             end
//         endcase
//     end

//     // Assign read address directly
//     assign o_addr_r = i_axi_araddr;

// endmodule

module Spi #(
    parameter DATA_WITH = 8
)(
    input                       clk,
    input                       resetn,
    input   [DATA_WITH-1:0]     din,
    input   [15:0]              dvsr, //0.5*(# clk in SCK period)
    input                       start,
    input                       cpol,
    input                       cpha,
    output  [DATA_WITH-1:0]     dout,
    output                      spi_done_tick,
    output                      ready,

    //spi interface
    output                      sclk,
    input                       miso,
    output                      mosi    


    );

    //fsm state type
    localparam  idle        = 'b00,
                cpha_delay  = 'b01,
                p0          = 'b10,
                p1          = 'b11;

    //define variable
    reg [1:0] state_reg, state_next;
    wire p_clk;
    reg [15:0] c_reg, c_next;
    reg spi_clk_reg; 
    wire spi_clk_next;
    reg ready_i; 
    reg spi_done_tick_i;
    reg [2:0]n_reg, n_next;
    reg [DATA_WITH-1:0]si_reg, si_next;
    reg [DATA_WITH-1:0]so_reg, so_next;



    /////////BODY//////////////
    //fsm for transmitting one byte

    //sequential circuit
    always @(posedge clk, negedge resetn) begin
        if (~resetn) begin
            state_reg       <= idle;
            c_reg           <= 0;
            //ready_i         <= 0;
            spi_clk_reg     <= 0;
            //spi_done_tick_i <= 0;
            n_reg           <= 0;
            si_reg          <= 0;
            so_reg          <= 0;
            
        end
        else begin
            state_reg       <= state_next;
            c_reg           <= c_next;
            spi_clk_reg     <= spi_clk_next;
            n_reg           <= n_next;
            si_reg          <= si_next;
            so_reg          <= so_next;
        end
    end

    //comb circuit
    always @(*) begin
        //defaut state
        state_next       = state_reg;
        c_next           = c_reg;
        ready_i          = 0;
        // spi_clk_next     = spi_clk_reg;
        spi_done_tick_i  = 0;
        n_next           = n_reg;
        si_next          = si_reg;
        so_next          = so_reg;

        case (state_reg)
            idle: begin
                ready_i = 1;
                if (start) begin
                    so_next = din;
                    c_next  = 0;
                    n_next  = 0;
                    if (cpha) begin
                        state_next = cpha_delay;
                    end
                    else state_next = p0;
                end
              
            end
            cpha_delay: begin
                if (c_reg == dvsr) begin
                    state_next  = p0;
                    c_next      = 0;
                end  
                else c_next = c_reg + 1; 
            end
            p0: begin
                if (c_reg == dvsr) begin // sclk 0 to 1
                    state_next = p1;
                    si_next = {si_reg[DATA_WITH-2:0], miso};
                    c_next = 0;
                end

                else c_next = c_reg + 1;
              
            end
            p1: begin
                if (c_reg == dvsr) begin
                    if (n_reg == DATA_WITH - 1) begin
                        spi_done_tick_i = 1;
                        state_next = idle;
                    end
                    else begin
                        so_next = {so_reg[DATA_WITH-2:0], 1'b0};
                        state_next = p0;
                        n_next = n_reg +1;
                        c_next = 0;
                    end
                end

                else c_next = c_reg + 1;
              
            end 
            default: state_next = idle;
        endcase

        // spi_clk_next = (cpol) ? ~p_clk : p_clk;
        // p_clk = (state_next == p1 && ~cpha) || (state_next == p0 && cpha);
        
    end

    assign ready = ready_i;
    // assign ready = (state_reg == idle) && !start;

    assign spi_done_tick = spi_done_tick_i;

    //look a head output dec
    assign p_clk = (state_next == p1 && ~cpha) || (state_next == p0 && cpha);
    assign spi_clk_next = (cpol) ? ~p_clk : p_clk;

    //output
    assign dout = si_reg;
    assign mosi = so_reg[DATA_WITH-1];
    assign sclk = spi_clk_reg;



endmodule