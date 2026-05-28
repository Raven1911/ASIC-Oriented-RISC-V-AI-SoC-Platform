`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 03/10/2026 02:48:59 PM
// Design Name: 
// Module Name: i2c_eeprom_model
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


/////////////////////////////////////////////////////////////////////
////                                                             ////
////  I2C EEPROM Model (Based on OpenCores I2C Slave)            ////
////                                                             ////
////  Modified Features:                                         ////
////  - Memory initialization via $readmemh                      ////
////  - Flexible memory size and I2C address parameters          ////
////                                                             ////
/////////////////////////////////////////////////////////////////////
module i2c_eeprom_model #(
    parameter I2C_ADR = 7'b101_0000,    // Default I2C address 0x50
    parameter MEM_SIZE = 256,           // Memory capacity in bytes
    parameter INIT_FILE = "i2c_eeprom.mem"            // Hex file name for initial data loading
)(
    input scl,                          // I2C clock line
    inout sda                           // I2C data line (bidirectional)
);

    //-----------------------------------------
    // Internal Variables and Signals
    //-----------------------------------------
    wire debug = 1'b1;                  // Enable/disable debug log display

    reg [7:0] mem [0:MEM_SIZE-1];       // Memory storage array
    reg [7:0] mem_adr;                  // Current memory address pointer
    reg [7:0] mem_do;                   // Data output from memory

    reg sta, d_sta;                     // Start condition and delayed Start signals
    reg sto, d_sto;                     // Stop condition and delayed Stop signals

    reg [7:0] sr;                       // 8-bit shift register
    reg       rw;                       // Direction: 1 = Read, 0 = Write

    wire      my_adr;                   // Address match signal
    wire      i2c_reset;                // I2C state machine reset
    reg [2:0] bit_cnt;                  // 3-bit down-counter (for 8-bit transfer)
    wire      acc_done;                 // 1-byte transfer complete
    reg       ld;                       // Bit counter reload command

    reg       sda_o;                    // SDA output control logic level
    wire      sda_dly;                  // Delayed version of SDA

    // State machine (FSM) state definitions
    parameter idle         = 3'b000;    // Wait for Start and Address
    parameter slave_ack    = 3'b001;    // Send ACK after Slave Address match
    parameter get_mem_adr  = 3'b010;    // Receive target memory address
    parameter gma_ack      = 3'b011;    // Send ACK after Memory Address
    parameter data         = 3'b100;    // Data transmit or receive
    parameter data_ack     = 3'b101;    // Handle ACK/NACK for data bytes

    reg [2:0] state;                    // Current FSM state register

    //-----------------------------------------
    // Memory Initialization and File Loading
    //-----------------------------------------
    initial begin
        sda_o = 1'b1;                   // Default SDA to floating (high)
        state = idle;

        // Initialize memory with zeros
        for (integer i = 0; i < MEM_SIZE; i = i + 1) begin
            mem[i] = 8'hFF;
        end

        // Load data from file if INIT_FILE parameter is provided
        if (INIT_FILE != "") begin
            $display("[%t] I2C_EEPROM: Loading data from file: %s", $time, INIT_FILE);
            $readmemh(INIT_FILE, mem);
        end
    end

    //-----------------------------------------
    // Bit Shifting and Start/Stop Detection
    //-----------------------------------------
    
    // Shift SDA into sr on SCL rising edge
    always @(posedge scl)
        sr <= #1 {sr[6:0], sda};

    // Check if the received address matches the programmed I2C_ADR
    assign my_adr = (sr[7:1] == I2C_ADR);

    // Bit counter logic: reload on ld, otherwise decrement
    always @(posedge scl)
        if(ld) bit_cnt <= #1 3'b111;
        else   bit_cnt <= #1 bit_cnt - 3'h1;

    // Byte transfer complete signal
    assign acc_done = !(|bit_cnt);
    assign #1 sda_dly = sda;

    // Start condition detection: SDA falls while SCL is high
    always @(negedge sda)
        if(scl) begin
            sta   <= #1 1'b1;
            d_sta <= #1 1'b0;
            sto   <= #1 1'b0;
            // if(debug) $display("[%t] I2C_EEPROM: START condition detected", $time);
        end else sta <= #1 1'b0;

    always @(posedge scl) d_sta <= #1 sta;

    // Stop condition detection: SDA rises while SCL is high
    always @(posedge sda)
        if(scl) begin
            sta <= #1 1'b0;
            sto <= #1 1'b1;
            // if(debug) $display("[%t] I2C_EEPROM: STOP condition detected", $time);
        end else sto <= #1 1'b0;

    // Reset FSM on Start or Stop
    assign i2c_reset = sta || sto;

    //-----------------------------------------
    // I2C Slave State Machine (FSM)
    //-----------------------------------------
    always @(negedge scl or posedge sto)
        if (sto || (sta && !d_sta)) begin
            state <= #1 idle;           // Reset to idle state
            sda_o <= #1 1'b1;           // Release SDA line
            ld    <= #1 1'b1;           // Prepare bit counter for next byte
        end else begin
            sda_o <= #1 1'b1;           // Default: release SDA
            ld    <= #1 1'b0;

            case(state)
                idle: begin             // Wait for Master to send Slave Address
                    if (acc_done && my_adr) begin
                        state <= #1 slave_ack;
                        rw    <= #1 sr[0];   // Store R/W bit
                        sda_o <= #1 1'b0;    // Pull SDA low to send ACK
                        if(sr[0]) mem_do <= #1 mem[mem_adr]; // Pre-fetch data for Read command
                    end
                end

                slave_ack: begin
                    if(rw) begin        // If Read command
                        state <= #1 data;
                        sda_o <= #1 mem_do[7]; // Output MSB of data to SDA
                    end else begin      // If Write command
                        state <= #1 get_mem_adr;
                    end
                    ld <= #1 1'b1;      // Reset bit counter for next byte
                end

                get_mem_adr: begin      // Receive 8-bit internal memory address
                    if(acc_done) begin
                        state   <= #1 gma_ack;
                        mem_adr <= #1 sr;    // Update address pointer
                        sda_o   <= #1 1'b0;  // Send ACK
                    end
                end

                gma_ack: begin
                    state <= #1 data;   // Proceed to data phase
                    ld    <= #1 1'b1;
                end

                data: begin
                    if(rw) sda_o <= #1 mem_do[7]; // Read mode: Output data to Master

                    if(acc_done) begin
                        state <= #1 data_ack;
                        if(!rw) begin   // Write mode: Store received byte to memory
                            mem[mem_adr] <= #1 sr;
                            // if(debug) $display("[%t] I2C_EEPROM: WRITE ADR %x = DATA %x", $time, mem_adr, sr);
                        end
                        
                        // Auto-increment address for sequential access
                        mem_adr <= #1 mem_adr + 1;
                        
                        // ACK for Write; Release SDA for Read (wait for Master ACK)
                        sda_o   <= #1 rw; 
                    end
                end

                data_ack: begin
                    ld <= #1 1'b1;
                    if(rw) begin        // Check Master ACK/NACK after Slave data transmission
                        if(sr[0]) begin // Master NACK (sr[0]=1) -> Terminate transfer
                            state <= #1 idle;
                        end else begin  // Master ACK (sr[0]=0) -> Send next byte
                            state  <= #1 data;
                            mem_do <= #1 mem[mem_adr];
                            sda_o  <= #1 mem[mem_adr][7];
                        end
                    end else begin
                        state <= #1 data; // Write mode: wait for next data byte
                    end
                end
            endcase
        end

    // Sequential data shifting for Read mode
    always @(posedge scl)
        if(!acc_done && rw && state == data)
            mem_do <= #1 {mem_do[6:0], 1'b1};

    // Open-Drain Tri-state control for SDA
    // sda_o = 0: pull down to 0. sda_o = 1: floating (Z) for Pull-up to pull to 1.
    assign sda = sda_o ? 1'bz : 1'b0;

    //-----------------------------------------
    // Timing Constraints and Checks
    //-----------------------------------------
    specify
        specparam normal_scl_low  = 4700, normal_scl_high = 4000;
        $width(negedge scl, normal_scl_low);
        $width(posedge scl, normal_scl_high);
    endspecify

endmodule