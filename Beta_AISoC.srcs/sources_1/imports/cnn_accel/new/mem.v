`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 04/17/2026 12:10:57 PM
// Design Name: 
// Module Name: mem
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


module memory
#(
    parameter DATA_W        = 8,
    parameter FIFO_DEPTH    = 10,
    parameter ADDR_W        = $clog2(FIFO_DEPTH)
)
(
    input                   clk,

    // Input declaration
    input   [DATA_W-1:0]    wr_data_i,
    input   [ADDR_W-1:0]    wr_addr_i,
    input                   wr_vld_i,

    input                   rd_rdy_i,
    input   [ADDR_W-1:0]    rd_addr_i,

    // Ouptut declaration
    output  [DATA_W-1:0]    rd_data_o
);
    reg [DATA_W-1:0]    mem     [FIFO_DEPTH-1:0];
    reg [DATA_W-1:0]    data_r;
    assign rd_data_o = data_r;
    always @(posedge clk) begin
        if(wr_vld_i) mem[wr_addr_i] <= wr_data_i;

        if(rd_rdy_i) data_r         <= mem[rd_addr_i];
    end

endmodule
