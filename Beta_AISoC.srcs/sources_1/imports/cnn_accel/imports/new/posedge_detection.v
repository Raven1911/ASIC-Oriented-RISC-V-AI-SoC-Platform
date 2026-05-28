`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 05/03/2025 03:47:37 PM
// Design Name: 
// Module Name: posedge_detection
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


module posedge_detection(
    input clk,
    input rst_n,
    input signal_i,
    output reg signal_o
    );
    reg signal_i_next;
    always @(*) begin
        signal_o = signal_i && ~signal_i_next;
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            signal_i_next <= 1'b1;
        end else signal_i_next <= signal_i;
    end

endmodule
