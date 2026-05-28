`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 04/16/2026 02:49:36 PM
// Design Name: 
// Module Name: skid_buffer
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


module skid_buffer #(
    parameter SBUF_TYPE  = 0,
    parameter DATA_WIDTH = 8
)(
    input                      clk,
    input                      rst_n,

    input  [DATA_WIDTH-1:0]    bwd_data_i,
    input                      bwd_valid_i,
    input                      fwd_ready_i,

    output [DATA_WIDTH-1:0]    fwd_data_o,
    output                     bwd_ready_o,
    output                     fwd_valid_o
);

generate

// ============================================================
// MODE 0 : FULL_REGISTERED
// ============================================================
if (SBUF_TYPE == 0) begin : FULL_REGISTERED

    reg  [DATA_WIDTH-1:0] skid_data_q, skid_data_d;
    reg  [DATA_WIDTH-1:0] out_data_q,  out_data_d;
    reg                   in_ready_q,  in_ready_d;
    reg                   out_valid_q, out_valid_d;

    wire in_hs;
    wire out_hs;

    assign fwd_data_o  = out_data_q;
    assign fwd_valid_o = out_valid_q;
    assign bwd_ready_o = in_ready_q;

    assign in_hs  = bwd_valid_i & bwd_ready_o;
    assign out_hs = fwd_valid_o & fwd_ready_i;

    always @(*) begin
        skid_data_d = skid_data_q;
        out_data_d  = out_data_q;
        in_ready_d  = in_ready_q;
        out_valid_d = out_valid_q;

        if (in_hs && out_hs) begin
            out_data_d = bwd_data_i;
        end
        else if (in_hs) begin
            if (out_valid_q) begin
                skid_data_d = bwd_data_i;
                in_ready_d  = 1'b0;
            end
            else begin
                out_data_d  = bwd_data_i;
                out_valid_d = 1'b1;
            end
        end
        else if (out_hs) begin
            if (in_ready_q) begin
                out_valid_d = 1'b0;
            end
            else begin
                out_data_d = skid_data_q;
                in_ready_d = 1'b1;
            end
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            out_valid_q <= 1'b0;
        end
        else begin
            out_data_q  <= out_data_d;
            out_valid_q <= out_valid_d;
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            in_ready_q <= 1'b1;
        end
        else begin
            skid_data_q <= skid_data_d;
            in_ready_q  <= in_ready_d;
        end
    end

end

// ============================================================
// MODE 1 : OPT_BWD_TIMING
// Requires external fifo module
// ============================================================
else if (SBUF_TYPE == 1) begin : OPT_BWD_TIMING

    wire                    in_ready_next;
    wire                    in_hs;
    wire                    out_hs;

    wire [DATA_WIDTH-1:0]   fifo_data_o;
    wire                    fifo_empty;
    wire                    fifo_full;
    wire                    fifo_almost_full;
    wire [2:0]              fifo_counter;
    wire                    fifo_wr_en;
    wire                    fifo_rd_en;

    reg  [DATA_WIDTH-1:0]   in_data_q;
    reg                     in_valid_q;
    reg                     in_ready_q;
    reg                     in_ready_dly_q;

    assign bwd_ready_o = in_ready_q;
    assign fwd_data_o  = fifo_empty ? in_data_q : fifo_data_o;
    assign fwd_valid_o = in_hs | (~fifo_empty);

    assign in_ready_next = ~(fifo_counter == 3'd2) & ~fifo_almost_full & ~fifo_full;

    assign in_hs  = in_ready_dly_q & in_valid_q;
    assign out_hs = fwd_ready_i & fwd_valid_o;

    assign fifo_wr_en = in_hs & ((~fifo_empty) | (~out_hs));
    assign fifo_rd_en = out_hs;

    fifo_n #(
        .DATA_WIDTH(DATA_WIDTH),
        .FF_TYPE(0),
        .FIFO_DEPTH(4)
    ) u_fifo (
        .clk            (clk),
        .data_i         (in_data_q),
        .data_o         (fifo_data_o),
        .rd_valid_i     (fifo_rd_en),
        .wr_valid_i     (fifo_wr_en),
        .clr_rd_i       (1'b0),
        .clr_ff_i       (1'b0),
        .empty_o        (fifo_empty),
        .full_o         (fifo_full),
        .almost_empty_o (),
        .almost_full_o  (fifo_almost_full),
        .counter        (fifo_counter),
        .rst_n          (rst_n)
    );

    always @(posedge clk) begin
        if (!rst_n)
            in_data_q <= {DATA_WIDTH{1'b0}};
        else
            in_data_q <= bwd_data_i;
    end

    always @(posedge clk) begin
        if (!rst_n)
            in_valid_q <= 1'b0;
        else
            in_valid_q <= bwd_valid_i;
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            in_ready_q     <= 1'b1;
            in_ready_dly_q <= 1'b1;
        end
        else begin
            in_ready_q     <= in_ready_next;
            in_ready_dly_q <= in_ready_q;
        end
    end

end

// ============================================================
// MODE 2 : LIGHT_WEIGHT
// ============================================================
else if (SBUF_TYPE == 2) begin : LIGHT_WEIGHT

    reg                  wr_ptr;
    reg                  rd_ptr;
    reg [DATA_WIDTH-1:0] buffer_q;

    wire in_hs;
    wire out_hs;

    assign fwd_data_o  = buffer_q;
    assign fwd_valid_o = wr_ptr ^ rd_ptr;
    assign bwd_ready_o = ~fwd_valid_o;

    assign in_hs  = bwd_valid_i & bwd_ready_o;
    assign out_hs = fwd_ready_i & fwd_valid_o;

    always @(posedge clk) begin
        if (!rst_n)
            wr_ptr <= 1'b0;
        else if (in_hs)
            wr_ptr <= ~wr_ptr;
    end

    always @(posedge clk) begin
        if (!rst_n)
            rd_ptr <= 1'b0;
        else if (out_hs)
            rd_ptr <= ~rd_ptr;
    end

    always @(posedge clk) begin
        if (!rst_n)
            buffer_q <= {DATA_WIDTH{1'b0}};
        else if (in_hs)
            buffer_q <= bwd_data_i;
    end

end

// ============================================================
// MODE 3 : OPT_FWD_TIMING
// Requires external sb_fifo module
// ============================================================
else if (SBUF_TYPE == 3) begin : OPT_FWD_TIMING

    localparam ACTIVE_ST  = 1'b0;
    localparam PASSIVE_ST = 1'b1;

    wire [DATA_WIDTH-1:0] fifo_data_o;
    wire                  fifo_rd_fire;
    wire                  fifo_has_data;

    wire                  use_backup;
    wire [DATA_WIDTH-1:0] out_data_next;
    wire                  out_valid_next;

    wire                  out_data_load;
    wire                  out_valid_load;
    wire                  out_data_int_load;
    wire                  out_valid_int_load;

    reg  [DATA_WIDTH-1:0] out_data_q;
    reg  [DATA_WIDTH-1:0] backup_data_q;
    reg                   backup_valid_q;
    reg                   out_valid_q;
    reg                   fwd_ready_q;
    reg                   state_q, state_d;

    assign fwd_data_o  = out_data_q;
    assign fwd_valid_o = out_valid_q;

    sb_fifo #(
        .DATA_WIDTH(DATA_WIDTH),
        .FIFO_DEPTH(2)
    ) u_sb_fifo (
        .clk        (clk),
        .data_i     (bwd_data_i),
        .data_o     (fifo_data_o),
        .rd_valid_i (fifo_rd_fire),
        .wr_valid_i (bwd_valid_i),
        .wr_ready_o (bwd_ready_o),
        .rd_ready_o (fifo_has_data),
        .rst_n      (rst_n)
    );

    assign use_backup      = (state_q == PASSIVE_ST) && (~fwd_ready_q);
    assign out_data_next   = use_backup ? backup_data_q  : fifo_data_o;
    assign out_valid_next  = (~(!out_valid_q && (state_q == PASSIVE_ST))) &
                             (use_backup ? backup_valid_q : fifo_has_data);

    assign out_data_int_load  = (state_q == ACTIVE_ST) & fifo_has_data;
    assign out_valid_int_load = out_data_int_load;

    assign out_data_load  = out_data_int_load  | fwd_ready_i;
    assign out_valid_load = out_valid_int_load | fwd_ready_i;

    assign fifo_rd_fire = (state_q == ACTIVE_ST) |
                          ((state_q == PASSIVE_ST) && fwd_ready_q && out_valid_q);

    always @(*) begin
        state_d = state_q;
        case (state_q)
            ACTIVE_ST: begin
                if (fifo_has_data)
                    state_d = PASSIVE_ST;
            end

            PASSIVE_ST: begin
                if (!out_valid_q)
                    state_d = ACTIVE_ST;
            end
        endcase
    end

    always @(posedge clk) begin
        if (out_data_load)
            out_data_q <= out_data_next;
    end

    always @(posedge clk) begin
        if (!rst_n)
            out_valid_q <= 1'b0;
        else if (out_valid_load)
            out_valid_q <= out_valid_next;
    end

    always @(posedge clk) begin
        if (!rst_n)
            fwd_ready_q <= 1'b0;
        else
            fwd_ready_q <= fwd_ready_i;
    end

    always @(posedge clk) begin
        if (!rst_n)
            backup_data_q <= {DATA_WIDTH{1'b0}};
        else if (fwd_ready_q)
            backup_data_q <= fifo_data_o;
    end

    always @(posedge clk) begin
        if (!rst_n)
            backup_valid_q <= 1'b0;
        else if (fwd_ready_q)
            backup_valid_q <= fifo_has_data & (~(!out_valid_q && (state_q == PASSIVE_ST)));
    end

    always @(posedge clk) begin
        if (!rst_n)
            state_q <= ACTIVE_ST;
        else
            state_q <= state_d;
    end

end

// ============================================================
// MODE 4 : BYPASS
// ============================================================
else if (SBUF_TYPE == 4) begin : BYPASS

    assign fwd_data_o  = bwd_data_i;
    assign fwd_valid_o = bwd_valid_i;
    assign bwd_ready_o = fwd_ready_i;

end

// ============================================================
// MODE 5 : HALF_REGISTERED
// ============================================================
else if (SBUF_TYPE == 5) begin : HALF_REGISTERED

    reg [DATA_WIDTH-1:0] buffer_q;
    reg                  out_valid_q;
    reg                  wr_ptr;
    reg                  rd_ptr;

    wire in_hs;
    wire out_hs;
    wire full;

    assign fwd_data_o  = buffer_q;
    assign fwd_valid_o = out_valid_q;

    assign full        = wr_ptr ^ rd_ptr;
    assign bwd_ready_o = out_hs | (~full);

    assign in_hs  = bwd_valid_i & bwd_ready_o;
    assign out_hs = fwd_valid_o & fwd_ready_i;

    always @(posedge clk) begin
        if (!rst_n)
            buffer_q <= {DATA_WIDTH{1'b0}};
        else if (in_hs)
            buffer_q <= bwd_data_i;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            out_valid_q <= 1'b0;
        else if (out_hs | in_hs)
            out_valid_q <= in_hs;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            wr_ptr <= 1'b0;
        else if (in_hs)
            wr_ptr <= ~wr_ptr;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            rd_ptr <= 1'b0;
        else if (out_hs)
            rd_ptr <= ~rd_ptr;
    end

end

endgenerate

endmodule


//    sync_fifo 
//        #(
//        .DATA_WIDTH(),
//        .FIFO_DEPTH(32)
//        ) fifo (
//        .clk(clk),
//        .data_i(),
//        .data_o(),
//        .rd_valid_i(),
//        .wr_valid_i(),
//        .empty_o(),
//        .full_o(),
//        .almost_empty_o(),
//        .almost_full_o(),
//        .rst_n(rst_n)
//        );