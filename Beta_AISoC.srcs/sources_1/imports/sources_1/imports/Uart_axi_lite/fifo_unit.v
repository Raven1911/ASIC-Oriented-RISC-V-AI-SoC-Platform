`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 01/03/2025 03:19:10 PM
// Design Name: 
// Module Name: fifo_unit
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


module fifo_unit #(parameter ADDR_WIDTH = 3, DATA_WIDTH = 8)(
    input clk, reset_n,
    input wr, rd,

    input [DATA_WIDTH - 1 : 0] w_data, //writing data
    output [DATA_WIDTH - 1 : 0] r_data, //reading data

    output full, empty

    );

    //signal
    wire [ADDR_WIDTH - 1 : 0] w_addr, r_addr;

    //instantiate registers file
    register_file #(.ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH))
        reg_file_unit(
            .clk(clk),
            .w_en(~full & wr),

            .r_addr(r_addr), //reading address
            .w_addr(w_addr), //writing address

            .w_data(w_data), //writing data
            .r_data(r_data) //reading data
        
        );

    //instantiate fifo ctrl
    fifo_ctrl #(.ADDR_WIDTH(ADDR_WIDTH))
        fifo_ctrl(
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
