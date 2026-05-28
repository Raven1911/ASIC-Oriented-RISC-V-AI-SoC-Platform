`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// BRAM-friendly rewrite of fltbuf_cache
// - Keeps the same interface and cycle behavior as the original module
// - Refactors the RAM access into a cleaner single-address synchronous read style
//////////////////////////////////////////////////////////////////////////////////

module fltbuf_cache #(
    parameter WIDTH = 8,
    parameter DEPTH = 224 * 12
)(
    input               clk,
    input               rst_n,
    input               wr_en,
    input               rd_en,
    input [WIDTH-1:0]   din,
    input [WIDTH-1:0]   zp,
    input               clear_rd,
    input               clear_rd_wr,
    output [WIDTH-1:0]  dout,

    output              full,
    output              vld_o,
    output              end_data
);

    localparam PTR_W = $clog2(DEPTH);
    reg [PTR_W-1:0] wr_ptr, rd_ptr;
    reg [WIDTH-1:0] mem_out;
    reg mem_vld;
    // Hint the synthesizer to prefer BRAM.
    (* ram_style = "block" *) reg [WIDTH-1:0] mem [0:DEPTH-1];
    assign vld_o    = wr_ptr != rd_ptr;
    assign end_data = (rd_ptr + 1) == wr_ptr;
    assign full     = 1'b0;
    always @(posedge clk) begin
        if (!rst_n) begin
            wr_ptr    <= {PTR_W{1'b0}};
            rd_ptr    <= {PTR_W{1'b0}};
            mem_vld   <= 0;
        end else begin
            if (clear_rd_wr) begin
                wr_ptr    <= {PTR_W{1'b0}};
                rd_ptr    <= {PTR_W{1'b0}};
            end else begin
                // Write-side state.
                if (wr_en) begin
                    wr_ptr   <= wr_ptr + 1;
                end

                // Read / prefetch control.
                if (clear_rd) begin
                    rd_ptr    <= 0;
                end else if (rd_en && vld_o) begin
                    rd_ptr    <= rd_ptr + 1;
                end
            end
            mem_vld <= vld_o;
        end
        
    end

    // ==========================================
    // RAM DATAPATH
    // ==========================================
    
    always @(posedge clk) begin
        if (wr_en) begin
            mem[wr_ptr] <= din;
        end
        mem_out <= mem[rd_ptr];
        
    end
    assign dout = mem_vld ? mem_out : zp;
endmodule
