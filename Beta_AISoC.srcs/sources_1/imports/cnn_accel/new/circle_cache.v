`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 04/05/2026 06:54:46 PM
// Design Name: 
// Module Name: circle_cache
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


module circle_cache #(
    parameter WIDTH     = 8,
    parameter DEPTH     = 16
)(
    input              clk,
    input              rst_n,
    input              wr_en,
    input              rd_en,
    input              clr,
    input  [3:0]       inf_hf_i,
    input  [WIDTH-1:0] zp,
    input  [WIDTH-1:0] din,
    output [WIDTH-1:0] dout,
    output             vld_o
);

    // 1. Khai báo bộ nhớ (Không reset để dễ dàng map vào LUTRAM/Block RAM)
    reg [WIDTH-1:0] mem [0:DEPTH-1];

    // 2. Khai báo con trỏ ghi và đọc
    reg [3:0]       wr_ptr;
    reg [3:0]       rd_ptr;

    // 3. Khai báo thanh ghi cho Output (đảm bảo output là Flip-Flop)
    reg [WIDTH-1:0] dout_reg;
    reg             vld_o_reg;

    // 4. Logic tính toán vòng lặp cho con trỏ (Quay về 0 khi chạm mốc hf - 1)
    wire [3:0]      rd_ptr_next;
    wire [3:0]      wr_ptr_next;

    assign rd_ptr_next = (rd_ptr >= inf_hf_i - 4'd1) ? 4'd0 : (rd_ptr + 4'd1);
    assign wr_ptr_next = wr_ptr + 4'd1;

    // ==========================================
    // KHỐI LOGIC GHI (WRITE)
    // ==========================================
    always @(posedge clk) begin
        if (!rst_n) begin
            wr_ptr <= 4'd0;
        end else if (clr) begin
            wr_ptr <= 4'd0;
        end else if (wr_en) begin
            wr_ptr <= wr_ptr_next;
        end
    end

    // Ghi dữ liệu vào memory
    always @(posedge clk) begin
        if (wr_en) begin
            mem[wr_ptr] <= din;
        end
    end

    // ==========================================
    // KHỐI LOGIC ĐỌC (READ)
    // ==========================================
    always @(posedge clk) begin
        if (!rst_n) begin
            rd_ptr <= 4'd0;
        end else if (clr) begin
            rd_ptr <= 4'd0;
        end else if (rd_en) begin
            rd_ptr <= rd_ptr_next;
        end
    end

    // ==========================================
    // KHỐI LOGIC FWFT (Đảm bảo độ trễ 0 chu kỳ khi rd_en = 1)
    // ==========================================
    always @(posedge clk) begin
        if (rd_en) begin
            // ĐANG ĐỌC: Nạp sẵn dữ liệu của địa chỉ TIẾP THEO vào dout.
            // Nếu địa chỉ tiếp theo đang được ghi đúng vào chu kỳ này -> Lấy trực tiếp din (Bypass).
            if (wr_en && (wr_ptr == rd_ptr_next)) begin
                dout_reg <= din;
            end else begin
                dout_reg <= mem[rd_ptr_next];
            end
        end else begin
            // KHÔNG ĐỌC: Giữ nguyên dout chờ user đọc.
            // Nhưng nếu User đang ghi vào CHÍNH địa chỉ mà rd_ptr đang trỏ tới -> Cập nhật dout ngay lập tức để "rơi thẳng" ra ngoài.
            if (wr_en && (wr_ptr == rd_ptr)) begin
                dout_reg <= din;
            end
        end
    end

    // ==========================================
    // KHỐI LOGIC VALID OUT
    // ==========================================
    always @(posedge clk) begin
        if (!rst_n) begin
            vld_o_reg <= 1'b0;
        end else if (clr) begin
            vld_o_reg <= 1'b0;
        end else if (wr_en) begin
            // Theo như bạn đảm bảo "luôn có đủ hf data", cờ vld_o sẽ bật lên 1 
            // ngay khi có dữ liệu đầu tiên được ghi vào và giữ nguyên đến khi bị clear.
            vld_o_reg <= 1'b1; 
        end
    end

    // Gán Flip-Flop ra output
    assign dout  = vld_o ? dout_reg : zp;
    assign vld_o = vld_o_reg;

endmodule