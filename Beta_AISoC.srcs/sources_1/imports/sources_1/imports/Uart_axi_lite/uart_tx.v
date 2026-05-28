`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 01/08/2025 01:41:50 AM
// Design Name: 
// Module Name: uart_tx
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


module uart_tx
    #(parameter     DBIT = 8, // databit
                    SB_TICK = 16 // tick for stop bits

    ) 
    (
        clk,
        reset_n,
        tx_start, 
        s_tick,
        din,

        tx_done_tick,
        tx
    );

    //GPIO conf
    input clk, reset_n;
    input tx_start, s_tick;

    input [7:0] din;
    output reg tx_done_tick;
    output tx;
    

    //////////////////////////////
    //Define fsm state 
    localparam  IDLE    = 2'b00,
                START   = 2'b01,
                DATA    = 2'b10,
                STOP    = 2'b11;

    //signal delaration
    reg [1:0]   state_reg, state_next;
    reg [3:0]   s_reg, s_next;
    reg [2:0]   n_reg, n_next;
    reg [7:0]   b_reg, b_next; // din <- fifo
    reg         tx_reg, tx_next;

    ////////////////////////////////////////////////BODY/////////////////////////////////

    //squential circuit
    always @(posedge clk, negedge reset_n) begin
        if (~reset_n) begin
            state_reg <= IDLE;
            s_reg <= 'd0;
            n_reg <= 'd0;
            b_reg <= 'd0;
            tx_reg <= 1'b1;
        end

        else begin
            state_reg <= state_next;
            s_reg <= s_next;
            n_reg <= n_next;
            b_reg <= b_next;
            tx_reg <= tx_next; 
        end
        
    end

    //combination circuit
    always @(*) begin
        //defaults
        state_next = state_reg;
        s_next = s_reg;
        n_next = n_reg;
        b_next = b_reg;
        tx_done_tick = 1'b0;
        tx_next = tx_reg;
        
        //fsm
        case (state_reg)
            IDLE: begin
                tx_next = 1'b1;
                if (tx_start) begin
                    state_next = START;
                    s_next = 'd0;
                    b_next = din;
                end
              
            end

            START: begin
                tx_next = 1'b0;
                if (s_tick) begin
                    if (s_reg == 'd15) begin
                        state_next = DATA;
                        s_next = 'd0;
                        n_next = 'd0;
                    end 

                    else begin
                        s_next = s_reg + 'd1;
                    end
                end
              
            end

            DATA: begin
                tx_next = b_reg[0];
                if (s_tick) begin
                    if (s_reg == 'd15) begin
                        s_next = 'd0;
                        b_next = b_reg >> 'd1;
                        if (n_reg == (DBIT - 1)) begin
                            state_next = STOP;
                        end

                        else begin
                            n_next = n_reg + 'd1;
                        end
                    end
                    else begin
                        s_next = s_reg + 'd1;
                    end
                end
            end

            STOP: begin
                tx_next = 1'b1;
                if (s_tick) begin
                    if (s_reg == (SB_TICK - 1)) begin
                        tx_done_tick = 1'b1;
                        state_next = IDLE;
                    end

                    else begin
                        s_next = s_reg + 'd1;
                    end
                end
            end
            
        endcase

        
    end

    //output
    assign tx = tx_reg;

endmodule
