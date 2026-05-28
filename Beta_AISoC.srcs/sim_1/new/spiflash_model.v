`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 03/04/2026 12:08:02 PM
// Design Name: 
// Module Name: spiflash_model
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


//================================================================
// Sub-Module: SPI Winbond Model Logic
//================================================================
module spiflash_model (
    input        cs_n,
    input        sck,
    input        mosi,
    output reg   miso
);
    reg [7:0]  mem [0:1023]; 
    reg [7:0]  shift_in;     // Thanh ghi nhận (MOSI)
    reg [7:0]  data_buffer;  // Thanh ghi dịch gửi (MISO)
    reg [31:0] bit_count;
    reg [23:0] addr;
    reg [2:0]  state;

    localparam IDLE = 0, CMD = 1, ADDR = 2, DATA = 3;

    initial begin
        state = IDLE;
        miso  = 1'bz;
    end
    initial begin
        $readmemh("spi_flash_data.mem", mem);
    end

    // Khi giải phóng Chip Select
    always @(posedge cs_n) begin
        state       <= IDLE;
        miso        <= 1'bz;
        bit_count   <= 0;
        data_buffer <= 8'h00;
    end

    //--- 1. Logic Nạp dữ liệu vào Thanh ghi (Cạnh lên SCK) ---
    always @(posedge sck) begin
        if (!cs_n) begin
            bit_count <= bit_count + 1;
            shift_in  <= {shift_in[6:0], mosi};

            case (state)
                IDLE: state <= CMD;

                CMD: begin
                    if (bit_count == 7) begin 
                        if ({shift_in[6:0], mosi} == 8'h03) begin
                            state <= ADDR;
                            bit_count <= 0;
                        end else begin
                            state <= IDLE;
                        end
                    end
                end

                ADDR: begin
                    // Đợi đủ 24 xung clock địa chỉ
                    if (bit_count == 23) begin
                        // FIX CỨNG ĐỊA CHỈ VỀ 0
                        addr  <= 24'h000000; 
                        state <= DATA;
                        bit_count <= 0;
                        // Nạp byte đầu tiên (mem[0]) vào thanh ghi đệm ngay lập tức
                        data_buffer <= mem[0]; 
                    end
                end

                DATA: begin
                    // Sau khi Master đã lấy đủ 8 bit của byte hiện tại
                    if (bit_count == 7) begin
                        addr <= addr + 1;
                        bit_count <= 0;
                        // Nạp byte tiếp theo từ bộ nhớ vào thanh ghi dịch
                        data_buffer <= mem[addr + 1];
                    end
                end
            endcase
        end
    end

    //--- 2. Logic Dịch bit ra ngoài (Cạnh xuống SCK) ---
    // Tuân thủ SPI Mode 0: Shift out trên cạnh xuống, Master sample trên cạnh lên.
    
    always @(negedge sck) begin
        if (!cs_n && state == DATA) begin
            // Đẩy bit cao nhất (MSB) của thanh ghi dịch ra chân MISO
            miso <= data_buffer[7];
            
            // Thực hiện dịch trái thanh ghi để chuẩn bị bit tiếp theo
            // Lưu ý: data_buffer đã được nạp giá trị mới ở cạnh lên trước đó 
            // hoặc khi vừa chuyển từ ADDR sang DATA.
            data_buffer <= {data_buffer[6:0], 1'b0};
        end else begin
            miso <= 1'bz;
        end
    end

endmodule   
