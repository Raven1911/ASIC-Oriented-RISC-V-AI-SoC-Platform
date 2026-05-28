`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 07/12/2025 01:12:59 AM
// Design Name: 
// Module Name: debouncer_delayed
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



module debouncer_delayed#(COUNTER_VALUE = 1_999_999)(
    input clk,
    input reset_n,
    input noisy,
    
    output debounced,
    output p_edge,
    output n_edge,
    output any_edge
    );
    
    wire    timer_done, timer_reset;
    
    debouncer_delayed_fsm FSM0(
        .clk(clk),
        .reset_n(reset_n),
        .noisy(noisy),
        .timer_done(timer_done),
        
        //output
        .timer_reset(timer_reset), 
        .debounced(debounced)
    
    );
    
    edge_detector EDGE_DE(
        .clk(clk),
        .reset_n(reset_n),
        .level_edge(debounced),
        
        //output
        .p_edge(p_edge),
        .n_edge(n_edge),
        .any_edge(any_edge)
    
    
    );
    //set COUNTER_VALUE time bounces //arty a7 = 1_999_999(100Mhz), de10 = 999_999 (50MhZ)
    timer_parameter #(.COUNTER_VALUE(COUNTER_VALUE)) T0(
        .clk(clk),
        .reset_n(~timer_reset),
        .enable(~timer_reset),
       
        //output
        .done(timer_done)
    );
    
    
    
endmodule




module debouncer_delayed_fsm(
    input   clk,
    input   reset_n,
    input   noisy,
    input   timer_done,
    output  timer_reset, debounced
    );
    
    reg [1:0]   state_reg,  state_next;
    parameter   S0 = 2'b00, S1 = 2'b01, S2 = 2'b10, S3 = 2'b11;
    
    //Sequential state register
    always @(posedge clk or negedge reset_n) begin
        if(~reset_n)    state_reg <= S0;
        
        else            state_reg <= state_next;        
       
    end
    
    //datapath circuit
    always @(*) begin
        state_next = state_reg;
        case (state_reg)
            S0: begin
                if(~noisy)  state_next = S0;
                else if(noisy) state_next = S1;
            end
            
            S1: begin
                if(~noisy) state_next = S0;
                else if(noisy & (~timer_done)) state_next = S1;
                else if(noisy & timer_done) state_next = S2;
            end
            
            S2: begin
                if(noisy) state_next = S2;
                else if(~noisy) state_next = S3;        
            end
            
            S3: begin
                if(noisy) state_next = S2;
                else if((~noisy) & (~timer_done)) state_next = S3;
                else if((~noisy) & timer_done) state_next = S0;
            end
            
            default: state_next = S0;
 
        endcase 
    end
    
    assign timer_reset = (state_reg == S0) | (state_reg == S2);
    assign debounced = (state_reg == S2) | (state_reg == S3);
    
    
endmodule



module edge_detector(
    input clk,
    input reset_n,
    input level_edge,
    
    output p_edge,
    output n_edge,
    output any_edge
    );
    
    //Edge detector mearly outputs
    
    reg state_reg, state_next;
    parameter S0 = 1'b0, S1 = 1'b1;
    
    //sequential state regs
    always @(posedge clk, negedge reset_n) begin
        if(~reset_n)
            state_reg <= S0;
        
        else
            state_reg <= state_next;
    end
    
    always @(*) begin
        case(state_reg)
            S0: begin
                if(level_edge)
                    state_next = S1;
                else
                    state_next = S0;
            end
            
            S1: begin
                if(level_edge)
                    state_next = S1;
                else
                    state_next = S0;
            end
            
            default: state_next = S0;   
        endcase
    end
    
    assign p_edge = (state_reg == S0) & level_edge;
    assign n_edge = (state_reg == S1) & ~level_edge;
    assign any_edge = p_edge | n_edge;
    
    
endmodule


module timer_parameter
    #(parameter COUNTER_VALUE = 'd255)(
    input clk,
    input reset_n,
    input enable,
   
    output done
    );
    
    localparam BITS = $clog2(COUNTER_VALUE);
    
    reg [BITS-1:0] counter = 0;
    
    // before no optimize --> clock up to 40MHz
    // always @(posedge clk, negedge reset_n) begin
    //     if(~reset_n) begin 
    //         Q_reg <= 'b0;
    //         //Q_next <= 'b0;
    //     end
        
    //     else if(enable) 
    //         Q_reg <= Q_next;
    //     else 
    //         Q_reg <= Q_reg;    
    // end
    
    // always @(posedge clk) begin
    //     if(Q_next == COUNTER_VALUE || (~reset_n)) 
    //         Q_next <= 'b0;
    //     else if(enable)
    //         Q_next <= Q_next + 1;
    // end

    // Affter  optimize --> clock up to 200MHz
    always @(posedge clk or negedge reset_n)begin
        if(~reset_n)begin
            counter <= 'b0;
        end

        else if (counter == COUNTER_VALUE) begin
            counter <= 'b0;
        end

        else if (enable) begin
            counter <= counter + 1;
        end

    end
    
    assign done = (counter == COUNTER_VALUE) ? 1 : 0;
    
endmodule
