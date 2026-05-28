`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 01/07/2025 05:48:03 PM
// Design Name: 
// Module Name: buad_gen
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


module buad_gen(
    clk,
    reset_n,
    dvsr,

    tick
    );

    //GPIO
    input           clk, reset_n;
    input   [10:0]  dvsr;

    output          tick;


    //variable state
    reg     [10:0]  r_reg;
    wire    [10:0]  r_next;

    //squential circuit
    always @(posedge clk or negedge reset_n) begin
        if(~reset_n)begin
            r_reg <= 0;
        end
        else begin
            r_reg <= r_next;
        end
        
    end

    //next_state
    assign r_next = (r_reg == dvsr) ? 0 : r_reg + 1;


    //output logic
    assign tick = (r_reg == 1);



endmodule
