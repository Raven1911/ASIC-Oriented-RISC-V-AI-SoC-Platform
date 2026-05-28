`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 01/08/2025 03:33:27 AM
// Design Name: 
// Module Name: uart_unit
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


module uart_unit
    #(parameter     DBIT = 8,       // databit
                    SB_TICK = 16,   // tick for stop bits
                    FIFO_W = 3      // addr bits of FIFO
    ) 
    (
        clk,
        reset_n,
        rd_uart,
        wr_uart,
        rx,
        w_data,
        dvsr,
        tx_full,
        rx_empty,
        tx,
        r_data
    );

    //GPIO confi
    input clk, reset_n, rd_uart, wr_uart, rx;
    input [7:0] w_data;
    input [10:0] dvsr;

    output tx_full, rx_empty;
    output tx;
    output [7:0] r_data;

    //signal delaration
    wire tick, rx_done_tick, tx_done_tick;
    wire tx_empty, tx_fifo_not_empty;
    wire [7:0] tx_fifo_out, rx_data_out;

    //////////////////////////////////BODY////////////////////////////////
    //
    buad_gen buad_gen(
    .clk(clk),
    .reset_n(reset_n),
    .dvsr(dvsr),

    .tick(tick)
    );

    //
    uart_rx 
    #(  .DBIT(DBIT), // databit
        .SB_TICK(SB_TICK)// tick for stop bits

    ) 
        uart_rx_unit(
        .clk(clk),
        .reset_n(reset_n),
        .rx(rx), 
        .s_tick(tick),

        .rx_done_tick(rx_done_tick),
        .dout(rx_data_out)
    );

    //
    uart_tx
    #(  .DBIT(DBIT), // databit
        .SB_TICK(SB_TICK) // tick for stop bits
    ) 
        uart_tx_unit(
        .clk(clk),
        .reset_n(reset_n),
        .tx_start(tx_fifo_not_empty), 
        .s_tick(tick),
        .din(tx_fifo_out),

        .tx_done_tick(tx_done_tick),
        .tx(tx)
    );

    //fifo rx
    fifo_unit #(.ADDR_WIDTH(FIFO_W), .DATA_WIDTH(DBIT))
        fifo_rx_unit(
        .clk(clk), 
        .reset_n(reset_n),
        .wr(rx_done_tick), 
        .rd(rd_uart),

        .w_data(rx_data_out), //writing data
        .r_data(r_data), //reading data

        .full(), 
        .empty(rx_empty)

    );

    //fifo tx
    fifo_unit #(.ADDR_WIDTH(FIFO_W), .DATA_WIDTH(DBIT))
        fifo_tx_unit(
        .clk(clk), 
        .reset_n(reset_n),
        .wr(wr_uart), 
        .rd(tx_done_tick),

        .w_data(w_data), //writing data
        .r_data(tx_fifo_out), //reading data

        .full(tx_full), 
        .empty(tx_empty)

    );

    assign tx_fifo_not_empty = ~tx_empty;


endmodule
