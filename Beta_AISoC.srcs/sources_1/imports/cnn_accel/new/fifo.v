module fifo_n
#(
    parameter  DATA_WIDTH    = 8,
    parameter  FIFO_DEPTH    = 32,
    parameter  FF_TYPE       = 0,
    parameter  FF_NUM        = 2,
    parameter  ADDR_WIDTH    = $clog2(FIFO_DEPTH)
)
(
    input                       clk,
    input   [DATA_WIDTH - 1:0]  data_i,
    output  [DATA_WIDTH - 1:0]  data_o,
    input                       wr_valid_i,
    input                       rd_valid_i,
    input                       clr_rd_i,
    input                       clr_ff_i,
    output                      empty_o,
    output                      full_o,
    output                      almost_empty_o,
    output                      almost_full_o,
    output  [ADDR_WIDTH:0]      counter,
    input                       rst_n
);

generate
// ============================================================
// MODE 0 : FIFO thường, data_o đọc thẳng từ memory.
// ============================================================
if (FF_TYPE == 0) begin : gen_mode_0
    reg  [DATA_WIDTH - 1:0]  buffer [0:FIFO_DEPTH - 1];
    
    // Đếm tuyệt đối để tính số lượng phần tử (occupancy)
    reg  [ADDR_WIDTH:0]      wr_cnt;
    reg  [ADDR_WIDTH:0]      rd_cnt;
    
    // Con trỏ chạy vòng quanh phục vụ index bộ nhớ (tránh phép %)
    reg  [ADDR_WIDTH-1:0]    wr_ptr;
    reg  [ADDR_WIDTH-1:0]    rd_ptr;

    wire [ADDR_WIDTH:0]      wr_cnt_d;
    wire [ADDR_WIDTH:0]      rd_cnt_d;
    wire [ADDR_WIDTH-1:0]    wr_ptr_d;
    wire [ADDR_WIDTH-1:0]    rd_ptr_d;

    wire [ADDR_WIDTH:0]      occ_count;
    wire                     wr_fire;
    wire                     rd_fire;

    assign wr_cnt_d = wr_cnt + 1'b1;
    assign rd_cnt_d = rd_cnt + 1'b1;
    
    // Mux quay vòng con trỏ khi chạm mốc FIFO_DEPTH - 1
    assign wr_ptr_d = (wr_ptr == FIFO_DEPTH - 1) ? {ADDR_WIDTH{1'b0}} : wr_ptr + 1'b1;
    assign rd_ptr_d = (rd_ptr == FIFO_DEPTH - 1) ? {ADDR_WIDTH{1'b0}} : rd_ptr + 1'b1;
    
    assign occ_count        = wr_cnt - rd_cnt;
    assign counter          = occ_count;
    
    assign empty_o          = (occ_count == 0);
    assign almost_empty_o   = (occ_count == 1);
    assign full_o           = (occ_count >= FIFO_DEPTH);
    assign almost_full_o    = (occ_count >= (FIFO_DEPTH - 1));
    
    assign wr_fire          = wr_valid_i && !full_o;
    assign rd_fire          = rd_valid_i && !empty_o;
    
    assign data_o           = empty_o ? {DATA_WIDTH{1'b0}} : buffer[rd_ptr];

    always @(posedge clk) begin
        if (wr_fire) begin
            buffer[wr_ptr] <= data_i;
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            wr_cnt <= 0;
            wr_ptr <= 0;
        end else if (clr_ff_i) begin
            wr_cnt <= 0;
            wr_ptr <= 0;
        end else if (wr_fire) begin
            wr_cnt <= wr_cnt_d;
            wr_ptr <= wr_ptr_d;
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            rd_cnt <= 0;
            rd_ptr <= 0;
        end else if (clr_ff_i || clr_rd_i) begin
            rd_cnt <= 0;
            rd_ptr <= 0;
        end else if (rd_fire) begin
            rd_cnt <= rd_cnt_d;
            rd_ptr <= rd_ptr_d;
        end
    end
end

// ============================================================
// MODE 1 : FIFO kiểu BRAM + 1 FF output + bypass.
// ============================================================
else if (FF_TYPE == 1) begin : gen_mode_1
    reg  [DATA_WIDTH - 1:0]  memory [0:FIFO_DEPTH - 1];
    
    reg  [ADDR_WIDTH:0]      wr_cnt;
    reg  [ADDR_WIDTH:0]      rd_cnt;
    reg  [ADDR_WIDTH-1:0]    wr_ptr;
    reg  [ADDR_WIDTH-1:0]    rd_ptr;
    
    reg  [DATA_WIDTH - 1:0]  data_q;
    reg                      data_vld;
    
    wire [ADDR_WIDTH:0]      wr_cnt_d;
    wire [ADDR_WIDTH:0]      rd_cnt_d;
    wire [ADDR_WIDTH-1:0]    wr_ptr_d;
    wire [ADDR_WIDTH-1:0]    rd_ptr_d;

    wire [ADDR_WIDTH:0]      mem_count;
    wire [ADDR_WIDTH:0]      total_count;
    wire                     mem_vld;
    wire                     wr_fire;
    wire                     out_take;
    wire                     fetch_from_mem;
    wire                     fetch_from_bypass;

    assign wr_cnt_d         = wr_cnt + 1'b1;
    assign rd_cnt_d         = rd_cnt + 1'b1;
    assign wr_ptr_d         = (wr_ptr == FIFO_DEPTH - 1) ? {ADDR_WIDTH{1'b0}} : wr_ptr + 1'b1;
    assign rd_ptr_d         = (rd_ptr == FIFO_DEPTH - 1) ? {ADDR_WIDTH{1'b0}} : rd_ptr + 1'b1;

    assign mem_count        = wr_cnt - rd_cnt;
    assign mem_vld          = (mem_count != 0);
    assign total_count      = mem_count + data_vld;
    assign counter          = total_count;
    
    assign empty_o          = !data_vld;
    assign almost_empty_o   = (total_count == 1);
    assign full_o           = (total_count >= FIFO_DEPTH);
    assign almost_full_o    = (total_count >= (FIFO_DEPTH - 1));
    
    assign wr_fire          = wr_valid_i && !full_o;
    assign out_take         = rd_valid_i || !data_vld;
    assign fetch_from_mem   = out_take && mem_vld;
    assign fetch_from_bypass= out_take && !mem_vld && wr_fire;
    
    assign data_o           = data_vld ? data_q : {DATA_WIDTH{1'b0}};

    always @(posedge clk) begin
        if (wr_fire) begin
            memory[wr_ptr] <= data_i;
        end
    end

    always @(posedge clk) begin
        if (fetch_from_mem) begin
            data_q <= memory[rd_ptr];
        end else if (fetch_from_bypass) begin
            data_q <= data_i;
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            wr_cnt <= 0;
            wr_ptr <= 0;
        end else if (clr_ff_i) begin
            wr_cnt <= 0;
            wr_ptr <= 0;
        end else if (wr_fire) begin
            wr_cnt <= wr_cnt_d;
            wr_ptr <= wr_ptr_d;
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            rd_cnt <= 0;
            rd_ptr <= 0;
        end else if (clr_ff_i || clr_rd_i) begin
            rd_cnt <= 0;
            rd_ptr <= 0;
        end else if (fetch_from_mem || fetch_from_bypass) begin
            rd_cnt <= rd_cnt_d;
            rd_ptr <= rd_ptr_d;
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            data_vld <= 1'b0;
        end else if (clr_ff_i || clr_rd_i) begin
            data_vld <= 1'b0;
        end else if (out_take) begin
            if (mem_vld) begin
                data_vld <= 1'b1;
            end else if (wr_fire) begin
                data_vld <= 1'b1;
            end else begin
                data_vld <= 1'b0;
            end
        end
    end
end

// ============================================================
// MODE 2 : FIFO kiểu BRAM + FF_NUM FF output.
// ============================================================
else begin : gen_mode_2
    reg  [DATA_WIDTH - 1:0]  memory [0:FIFO_DEPTH - 1];
    
    reg  [ADDR_WIDTH:0]      wr_cnt;
    reg  [ADDR_WIDTH:0]      rd_cnt;
    reg  [ADDR_WIDTH-1:0]    wr_ptr;
    reg  [ADDR_WIDTH-1:0]    rd_ptr;
    
    reg  [DATA_WIDTH - 1:0]  data_q [0:FF_NUM-1];
    reg  [FF_NUM-1:0]        data_vld;
    
    wire [ADDR_WIDTH:0]      wr_cnt_d;
    wire [ADDR_WIDTH:0]      rd_cnt_d;
    wire [ADDR_WIDTH-1:0]    wr_ptr_d;
    wire [ADDR_WIDTH-1:0]    rd_ptr_d;

    wire [ADDR_WIDTH:0]      mem_count;
    wire [ADDR_WIDTH:0]      ff_count;
    wire [ADDR_WIDTH:0]      total_count;
    wire                     mem_vld;
    wire                     wr_fire;
    wire [FF_NUM-1:0]        ff_hsk;
    
    // Mảng tổ hợp dùng để đếm thay cho vòng lặp trong function
    wire [ADDR_WIDTH:0]      sum_vld [0:FF_NUM];

    genvar i, ff;

    assign wr_cnt_d         = wr_cnt + 1'b1;
    assign rd_cnt_d         = rd_cnt + 1'b1;
    assign wr_ptr_d         = (wr_ptr == FIFO_DEPTH - 1) ? {ADDR_WIDTH{1'b0}} : wr_ptr + 1'b1;
    assign rd_ptr_d         = (rd_ptr == FIFO_DEPTH - 1) ? {ADDR_WIDTH{1'b0}} : rd_ptr + 1'b1;

    assign mem_count        = wr_cnt - rd_cnt;
    assign mem_vld          = (mem_count != 0);

    // Tính tổng số valid FF bằng logic tổ hợp (Adder Tree)
    assign sum_vld[0] = {(ADDR_WIDTH+1){1'b0}};
    for (i = 0; i < FF_NUM; i = i + 1) begin : gen_vld_count
        assign sum_vld[i+1] = sum_vld[i] + data_vld[i];
    end
    assign ff_count         = sum_vld[FF_NUM];

    assign total_count      = mem_count + ff_count;
    assign counter          = total_count;
    
    assign empty_o          = !data_vld[FF_NUM-1];
    assign almost_empty_o   = (total_count == 1);
    assign full_o           = (total_count >= FIFO_DEPTH);
    assign almost_full_o    = (total_count >= (FIFO_DEPTH - 1));
    
    assign wr_fire          = wr_valid_i && !full_o;
    assign data_o           = data_vld[FF_NUM-1] ? data_q[FF_NUM-1] : {DATA_WIDTH{1'b0}};
    
    assign ff_hsk[FF_NUM-1] = rd_valid_i || !data_vld[FF_NUM-1];
    
    for (ff = 0; ff < FF_NUM - 1; ff = ff + 1) begin : gen_ff_hsk
        assign ff_hsk[ff] = ff_hsk[ff+1] || !data_vld[ff];
    end

    always @(posedge clk) begin
        if (wr_fire) begin
            memory[wr_ptr] <= data_i;
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            data_vld[0] <= 1'b0;
        end else if (clr_ff_i || clr_rd_i) begin
            data_vld[0] <= 1'b0;
        end else if (ff_hsk[0]) begin
            data_vld[0] <= mem_vld;
        end
    end

    always @(posedge clk) begin
        if (ff_hsk[0] && mem_vld) begin
            data_q[0] <= memory[rd_ptr];
        end
    end

    for (ff = 1; ff < FF_NUM; ff = ff + 1) begin : gen_ff_pipe
        always @(posedge clk) begin
            if (!rst_n) begin
                data_vld[ff] <= 1'b0;
            end else if (clr_ff_i || clr_rd_i) begin
                data_vld[ff] <= 1'b0;
            end else if (ff_hsk[ff]) begin
                data_vld[ff] <= data_vld[ff-1];
            end
        end

        always @(posedge clk) begin
            if (ff_hsk[ff] && data_vld[ff-1]) begin
                data_q[ff] <= data_q[ff-1];
            end
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            wr_cnt <= 0;
            wr_ptr <= 0;
        end else if (clr_ff_i) begin
            wr_cnt <= 0;
            wr_ptr <= 0;
        end else if (wr_fire) begin
            wr_cnt <= wr_cnt_d;
            wr_ptr <= wr_ptr_d;
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            rd_cnt <= 0;
            rd_ptr <= 0;
        end else if (clr_ff_i || clr_rd_i) begin
            rd_cnt <= 0;
            rd_ptr <= 0;
        end else if (ff_hsk[0] && mem_vld) begin
            rd_cnt <= rd_cnt_d;
            rd_ptr <= rd_ptr_d;
        end
    end
end
endgenerate

endmodule