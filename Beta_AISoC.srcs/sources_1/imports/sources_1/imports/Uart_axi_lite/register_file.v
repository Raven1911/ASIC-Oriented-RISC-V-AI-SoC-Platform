`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 01/03/2025 02:56:30 PM
// Design Name: 
// Module Name: register_file
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


module register_file #(parameter ADDR_WIDTH = 3, DATA_WIDTH = 8)(
    input clk,
    input w_en,

    input [ADDR_WIDTH - 1 : 0] r_addr, //reading address
    input [ADDR_WIDTH - 1 : 0] w_addr, //writing address

    input [DATA_WIDTH - 1 : 0] w_data, //writing data
    output [DATA_WIDTH - 1 : 0] r_data //reading data
    );

    //memory buffer
    reg [DATA_WIDTH - 1 : 0] memory [0 : (2**ADDR_WIDTH) - 1];
    
    // Clear FIFO storage for clean simulation waveforms. FIFO data is only
    // meaningful when empty == 0, but zero init avoids false FF sideband values.
    integer i;
    initial begin
        for (i = 0; i < (2**ADDR_WIDTH); i = i + 1) begin
            memory[i] = {DATA_WIDTH{1'b0}}; 
        end
    end

    //wire operation
    always @(posedge clk) begin
        if (w_en) memory[w_addr] <= w_data;
        
    end

    //read operation
    assign r_data = memory[r_addr];

endmodule
