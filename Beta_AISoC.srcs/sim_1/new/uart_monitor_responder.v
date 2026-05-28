`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 03/10/2026 03:37:22 PM
// Design Name: 
// Module Name: uart_monitor_responder
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
module uart_monitor_responder #(
    parameter BAUD_RATE    = 115200,
    parameter CLK_FREQ     = 200_000_000,
    parameter TRIGGER_DATA = 8'h3F,                 // Kích hoạt khi nhận 0x3F
    parameter MEM_FILE     = "uart_monitor.mem",    // File chứa dữ liệu 0x11 0x22
    parameter MEM_DEPTH    = 47,                     // Số lượng byte phản hồi (46 byte)
    parameter PRINT_RX     = 1,
    parameter PRINT_TRIGGER = 1
)(
    input wire rx,  // Nối với chân TX của SoC
    output reg tx   // Nối với chân RX của SoC
);

    // Tính toán chu kỳ của 1 bit dựa trên Baud Rate (tính bằng ns)
    localparam real BIT_PERIOD = 1_000_000_000.0 / BAUD_RATE;

    reg [7:0] resp_memory [0:MEM_DEPTH-1];
    reg [7:0] rx_byte;
    reg       trigger_detected = 0;
    integer i, j, k;

    // --- KHỞI TẠO ---
    initial begin
        tx = 1'b1; // Trạng thái nghỉ của UART là mức cao
        
        // Xóa sạch bộ nhớ tạm
        for (k = 0; k < MEM_DEPTH; k = k + 1) resp_memory[k] = 8'h00;

        // Nạp dữ liệu phản hồi từ file HEX (Chứa 11 22)
        if (MEM_FILE != "") begin
            if (PRINT_TRIGGER) begin
                $display("[%t] UART_MONITOR: Loading response from %s", $time, MEM_FILE);
            end
            $readmemh(MEM_FILE, resp_memory);
        end
    end

    // --- TIẾN TRÌNH 1: LUÔN NHẬN VÀ HIỂN THỊ (Monitor) ---
    // Khối này chạy độc lập để bắt các byte Echo từ SoC gửi về
    always begin
        wait(rx == 1'b1); 
        @(negedge rx); // Chờ Start bit
        
        #(BIT_PERIOD / 2.0); // Nhảy đến giữa Start bit
        
        for (i = 0; i < 8; i = i + 1) begin
            #(BIT_PERIOD);
            rx_byte[i] = rx; // Nhận 8 bit dữ liệu
        end
        
        #(BIT_PERIOD); // Chờ hết Stop bit

        if (PRINT_RX) begin
            $write("%c", rx_byte);
            // $write(" [Monitor Recv: %02h (%c)] \n ", rx_byte, rx_byte);
            $fflush();
        end

        // Nếu nhận đúng mã trigger 0x3F, bật tín hiệu cho Tiến trình 2
        if (rx_byte == TRIGGER_DATA) begin
            trigger_detected <= 1;
            #(BIT_PERIOD); 
            trigger_detected <= 0;
        end
    end

    // --- TIẾN TRÌNH 2: PHẢN HỒI KHI CÓ TRIGGER (Responder) ---
    // Khối này chỉ chạy khi nhận được tín hiệu từ Tiến trình 1
    always @(posedge trigger_detected) begin
        if (PRINT_TRIGGER) begin
            $display("\n[%t] UART_MONITOR: Detect Trigger (0x%h). Sending bytes from file...", $time, TRIGGER_DATA);
        end
        send_response();
    end

    // --- TASK GỬI DỮ LIỆU ---
    task send_response;
        begin
            for (j = 0; j < MEM_DEPTH; j = j + 1) begin
                // Chỉ gửi byte nếu nó khác 00 (Tránh gửi các ô nhớ trống)
                if (resp_memory[j] != 8'h00) begin
                    send_byte(resp_memory[j]);
                end
                // send_byte(resp_memory[j]);
            end
        end
    endtask

    // Gửi 1 byte theo khung UART chuẩn
    task send_byte(input [7:0] data);
        integer b;
        begin
            tx = 1'b0; // Start bit
            #(BIT_PERIOD);
            
            for (b = 0; b < 8; b = b + 1) begin
                tx = data[b]; // Data bits (LSB first)
                #(BIT_PERIOD);
            end
            
            tx = 1'b1; // Stop bit
            #(BIT_PERIOD);
            #(BIT_PERIOD); // Khoảng nghỉ nhỏ giữa các byte
        end
    endtask

endmodule
