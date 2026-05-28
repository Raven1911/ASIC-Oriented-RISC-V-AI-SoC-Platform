`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 08/23/2025 11:00:18 PM
// Design Name: 
// Module Name: i2c_master
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

// i2c single-master (Verilog-2001)
// * Limitation
//   - only function as I2C master
//   - no arbitration (i.e., no other master allowed)
//   - do not support slave "clock-stretching"
// * Input
//   cmd (command): 000:start, 001:write, 010:read, 011:stop, 100:restart
//   din: write:8-bit data; read: LSB is ack/nack bit used in read
// * Output:
//   dout: received data
//   ack:  received ack in write (should be 0)
// * Basic design
//   - external system
//       * generate proper start-write/read-stop condition
//       * use LSB of din (ack/nack) to indicate last byte in read
//   - FSM
//       * loop 9 times for read/write (8 bit data + ack)
//       * no distinction between read/write (shift-in/out simultaneously)
//   - Output control circuit
//       * data out of sda: loops 0-7 of write and loop 8 of read (send ack/nack)
//       * data into sda: loops 0-7 of read and loop 8 of write (receive ack)
//   - dvsr: divisor to obtain a quarter of i2c clock period
//       * 0.5*(# clk in SCK period)
//
// During a read operation, LSB of din is the NACK bit (indicate last byte)

module i2c_master(
   input  clk,
   input  resetn,
   input  [7:0]  din,
   input  [15:0] dvsr,
   input  [2:0]  cmd,
   input         wr_i2c,
   output tri    scl,
   inout  tri    sda,
   output        ready,
   output        done_tick,
   output        ack,
   output [7:0]  dout
);

   // symbolic constants
   localparam [2:0] START_CMD   = 3'b000;
   localparam [2:0] WR_CMD      = 3'b001;
   localparam [2:0] RD_CMD      = 3'b010;
   localparam [2:0] STOP_CMD    = 3'b011;
   localparam [2:0] RESTART_CMD = 3'b100;

   // FSM states (encoded)
   localparam [3:0]
      S_IDLE    = 4'd0,
      S_HOLD    = 4'd1,
      S_START1  = 4'd2,
      S_START2  = 4'd3,
      S_DATA1   = 4'd4,
      S_DATA2   = 4'd5,
      S_DATA3   = 4'd6,
      S_DATA4   = 4'd7,
      S_DATAEND = 4'd8,
      S_RESTART = 4'd9,
      S_STOP1   = 4'd10,
      S_STOP2   = 4'd11;

   // declarations
   reg [3:0]  state_reg, state_next;
   reg [15:0] c_reg, c_next;
   wire [15:0] qutr;
   wire [15:0] half;
   reg [8:0]  tx_reg, tx_next;
   reg [8:0]  rx_reg, rx_next;
   reg [2:0]  cmd_reg, cmd_next;
   reg [3:0]  bit_reg, bit_next;

   reg sda_out, scl_out, sda_reg, scl_reg, data_phase;
   reg done_tick_i, ready_i;

   wire into;
   wire nack;

   //**************************************************************
   // Output control logic
   //**************************************************************
   // buffer for sda and scl lines
   always @(posedge clk or negedge resetn) begin
      if (~resetn) begin
         sda_reg <= 1'b1;
         scl_reg <= 1'b1;
      end else begin
         sda_reg <= sda_out;
         scl_reg <= scl_out;
      end
   end

   // only master drives SCL line
   assign scl = (scl_reg) ? 1'bz : 1'b0;

   // "into" asserted when sda is input into master
   assign into = (data_phase && (cmd_reg==RD_CMD) && (bit_reg<8)) ||
                 (data_phase && (cmd_reg==WR_CMD) && (bit_reg==8));

   // sda uses pull-up; drive low only when needed
   assign sda = (into || sda_reg) ? 1'bz : 1'b0;

   // outputs
   assign dout = rx_reg[8:1];
   assign ack  = rx_reg[0];   // obtained from slave in write
   assign nack = din[0];      // used by master in read operation

   //**************************************************************
   // FSMD
   //**************************************************************
   // registers
   always @(posedge clk or negedge resetn) begin
      if (~resetn) begin
         state_reg <= S_IDLE;
         c_reg     <= 16'd0;
         bit_reg   <= 4'd0;
         cmd_reg   <= 3'd0;
         tx_reg    <= 9'd0;
         rx_reg    <= 9'd0;
      end else begin
         state_reg <= state_next;
         c_reg     <= c_next;
         bit_reg   <= bit_next;
         cmd_reg   <= cmd_next;
         tx_reg    <= tx_next;
         rx_reg    <= rx_next;
      end
   end

   assign qutr = dvsr;
   assign half = {qutr[14:0], 1'b0}; // half = 2 * qutr

   // next-state / combinational logic
   always @(*) begin
      state_next   = state_reg;
      c_next       = c_reg + 16'd1;   // timer counts continuously
      bit_next     = bit_reg;
      tx_next      = tx_reg;
      rx_next      = rx_reg;
      cmd_next     = cmd_reg;
      done_tick_i  = 1'b0;
      ready_i      = 1'b0;
      scl_out      = 1'b1;
      sda_out      = 1'b1;
      data_phase   = 1'b0;

      case (state_reg)
         S_IDLE: begin
            ready_i = 1'b1;
            if (wr_i2c && (cmd==START_CMD)) begin
               state_next = S_START1;
               c_next     = 16'd0;
            end
         end

         S_START1: begin // start condition
            sda_out = 1'b0;
            if (c_reg==half) begin
               c_next     = 16'd0;
               state_next = S_START2;
            end
         end

         S_START2: begin
            sda_out = 1'b0;
            scl_out = 1'b0;
            if (c_reg==qutr) begin
               c_next     = 16'd0;
               state_next = S_HOLD;
            end
         end

         S_HOLD: begin // in progress; prepared for the next op
            ready_i = 1'b1;
            sda_out = 1'b0;
            scl_out = 1'b0;
            if (wr_i2c) begin
               cmd_next = cmd;
               c_next   = 16'd0;
               case (cmd)
                  RESTART_CMD, START_CMD:
                     state_next = S_RESTART;
                  STOP_CMD:
                     state_next = S_STOP1;
                  default: begin // read/write a byte
                     bit_next   = 4'd0;
                     state_next = S_DATA1;
                     tx_next    = {din, nack}; // nack used as NACK in read
                  end
               endcase
            end
         end

         S_DATA1: begin
            sda_out    = tx_reg[8];
            scl_out    = 1'b0;
            data_phase = 1'b1;
            if (c_reg==qutr) begin
               c_next     = 16'd0;
               state_next = S_DATA2;
            end
         end

         S_DATA2: begin
            sda_out    = tx_reg[8];
            data_phase = 1'b1;
            if (c_reg==qutr) begin
               c_next     = 16'd0;
               state_next = S_DATA3;
               rx_next    = {rx_reg[7:0], sda}; // shift data in
            end
         end

         S_DATA3: begin
            sda_out    = tx_reg[8];
            data_phase = 1'b1;
            if (c_reg==qutr) begin
               c_next     = 16'd0;
               state_next = S_DATA4;
            end
         end

         S_DATA4: begin
            sda_out    = tx_reg[8];
            scl_out    = 1'b0;
            data_phase = 1'b1;
            if (c_reg==qutr) begin
               c_next = 16'd0;
               if (bit_reg==4'd8) begin
                  state_next  = S_DATAEND; // done with 8 data bits + 1 ack
                  done_tick_i = 1'b1;
               end else begin
                  tx_next   = {tx_reg[7:0], 1'b0};
                  bit_next  = bit_reg + 4'd1;
                  state_next = S_DATA1;
               end
            end
         end

         S_DATAEND: begin
            sda_out = 1'b0;
            scl_out = 1'b0;
            if (c_reg==qutr) begin
               c_next     = 16'd0;
               state_next = S_HOLD;
            end
         end

         S_RESTART: begin // generate idle condition then go to start
            if (c_reg==half) begin
               c_next     = 16'd0;
               state_next = S_START1;
            end
         end

         S_STOP1: begin // stop condition
            sda_out = 1'b0;
            if (c_reg==half) begin
               c_next     = 16'd0;
               state_next = S_STOP2;
            end
         end

         default: begin // S_STOP2 (turnaround time)
            if (c_reg==half)
               state_next = S_IDLE;
         end
      endcase
   end

   assign done_tick = done_tick_i;
   assign ready    = ready_i;

endmodule
