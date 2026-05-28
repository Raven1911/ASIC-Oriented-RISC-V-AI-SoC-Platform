`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 01/30/2026 03:10:00 PM
// Design Name: 
// Module Name: GPIO_axi_lite_core
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



module GPIO_axi_lite_core #(
    parameter NUM_MASTERS = 1,
    parameter ADDR_WIDTH = 32,          // Address width
    parameter DATA_WIDTH = 32,          // Data width
    parameter TRANS_W_STRB_W = 4,       // width strobe
    parameter TRANS_WR_RESP_W = 2,      // width response
    parameter TRANS_PROT      = 3,
    parameter CYCLE_CLOCK = 2,

    //config register timer
    parameter [ADDR_WIDTH-1:0] ADDR_REGISTERS_0= 32'h0200_7000,
    parameter [ADDR_WIDTH-1:0] ADDR_REGISTERS_1= 32'h0200_7004,
    parameter [ADDR_WIDTH-1:0] ADDR_REGISTERS_2= 32'h0200_7008,
    parameter WIDTH_PORT = 8
)(  
    input clk,
    input resetn,

    // AXI-Lite Write Address Channels
    input       [ADDR_WIDTH-1:0]        i_axi_awaddr,
    input                               i_axi_awvalid,
    output                              o_axi_awready,
    input       [TRANS_PROT-1:0]        i_axi_awprot,

    // AXI-Lite Write Data Channel
    input       [DATA_WIDTH-1:0]        i_axi_wdata,
    input       [TRANS_W_STRB_W-1:0]    i_axi_wstrb,
    input                               i_axi_wvalid,
    output                              o_axi_wready,

    // AXI-Lite Write Response Channels
    output      [TRANS_WR_RESP_W-1:0]   o_axi_bresp,
    output                              o_axi_bvalid,
    input                               i_axi_bready,

    // AXI-Lite Read Address Channels
    input       [ADDR_WIDTH-1:0]        i_axi_araddr,
    input                               i_axi_arvalid,
    output                              o_axi_arready,
    input       [TRANS_PROT-1:0]        i_axi_arprot,

    // AXI4-Lite Read Data Channel
    output      [DATA_WIDTH-1:0]        o_axi_rdata,
    output                              o_axi_rvalid,
    output      [TRANS_WR_RESP_W-1:0]   o_axi_rresp,
    input                               i_axi_rready,


    // GPIO Interface
    inout   tri [WIDTH_PORT-1:0]        gpio_io 

    );

    //signals to connect
    //wire [3:0] o_wen;
    wire [ADDR_WIDTH-1:0] o_addr_w;
    wire [ADDR_WIDTH-1:0] o_addr_r;                
    wire [DATA_WIDTH-1:0] o_data_w;
    wire [DATA_WIDTH-1:0] i_data_r;

    wire o_wr_w;
    wire o_rd_r;

    // signal declaration
    wire wr_reg0;
    wire wr_reg1;
    wire rd_reg0;
    wire rd_reg1;


    reg  we;
    reg  [WIDTH_PORT-1:0] define_io;
    reg  [WIDTH_PORT-1:0] write_port;
    wire [WIDTH_PORT-1:0] read_port;


    // decoding
    assign wr_reg0       = (o_wr_w && (o_addr_w[31:0] == ADDR_REGISTERS_0)) ? 1 : 0;
    assign wr_reg1       = (o_wr_w && (o_addr_w[31:0] == ADDR_REGISTERS_1)) ? 1 : 0;
    assign rd_reg0       = (o_rd_r && (o_addr_r[31:0] == ADDR_REGISTERS_0)) ? 1 : 0;
    assign rd_reg1       = (o_rd_r && (o_addr_r[31:0] == ADDR_REGISTERS_1)) ? 1 : 0;


    // write data
    always @(posedge clk or negedge resetn) begin
        if (~resetn) begin
            we <= 1'b0;
            define_io <= 0;
            write_port <= 0;
        end else begin
            we <= (wr_reg0) ? o_data_w[8] : we;
            define_io <= (wr_reg0) ? o_data_w[7:0] : define_io;
            write_port <= (wr_reg1) ? o_data_w[7:0] : write_port;
        end
    end


    // read data  
    // assign i_data_r =   (rd_reg0) ?  {23'b0, we, define_io} : 
    //                     (rd_reg1) ?  {24'b0, write_port} : {24'b0, read_port};

    // GPIO
    assign i_data_r =
        (o_addr_r[31:0] == ADDR_REGISTERS_0) ? {23'b0, we, define_io} :
        (o_addr_r[31:0] == ADDR_REGISTERS_1) ? {24'b0, write_port} :
        (o_addr_r[31:0] == ADDR_REGISTERS_2) ? {24'b0, read_port} :
                                            32'b0;
    


    // instantiate GPIO core
    GPIO_core #(
        .WIDTH_PORT(WIDTH_PORT)
    ) GPIO_core_uut (
        .clk_i         (clk),
        .resetn_i      (resetn),
        .we_i          (we),
        .define_io_i   (define_io),
        .write_port_i  (write_port),
        .read_port_o   (read_port),
        .gpio_io       (gpio_io)
    );

    axi_lite_slave_interface #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .TRANS_W_STRB_W(TRANS_W_STRB_W),
        .TRANS_WR_RESP_W(TRANS_WR_RESP_W),
        .TRANS_PROT(TRANS_PROT),
        .CYCLE_CLOCK(CYCLE_CLOCK),
        .NUM_MASTERS(NUM_MASTERS)
    ) timer_axi_lite_interface (
        .clk_i(clk),
        .resetn_i(resetn),

        .i_axi_awaddr(i_axi_awaddr),
        .i_axi_awvalid(i_axi_awvalid),
        .o_axi_awready(o_axi_awready),
        .i_axi_awprot(i_axi_awprot),

        .i_axi_wdata(i_axi_wdata),
        .i_axi_wstrb(i_axi_wstrb),
        .i_axi_wvalid(i_axi_wvalid),
        .o_axi_wready(o_axi_wready),

        .o_axi_bresp(o_axi_bresp),
        .o_axi_bvalid(o_axi_bvalid),
        .i_axi_bready(i_axi_bready),

        .i_axi_araddr(i_axi_araddr),
        .i_axi_arvalid(i_axi_arvalid),
        .o_axi_arready(o_axi_arready),
        .i_axi_arprot(i_axi_arprot),

        .o_axi_rdata(o_axi_rdata),
        .o_axi_rvalid(o_axi_rvalid),
        .o_axi_rresp(o_axi_rresp),
        .i_axi_rready(i_axi_rready),

        .o_addr_w(o_addr_w),
        .o_awprot_w(),

        .o_wen(),       
        .o_data_w(o_data_w),
        .o_write_data_w(o_wr_w),

        .i_bresp_w('b00),

        .o_addr_r(o_addr_r),
        .o_arprot_r(),
        
        .i_data_r(i_data_r),
        .i_rresp_r('b00),
        .o_read_data_r(o_rd_r)
    );

endmodule





module GPIO_core#(
    parameter WIDTH_PORT = 8
)(
    input                    clk_i,
    input                    resetn_i,

    input                    we_i,          // Write Enable cho GPO
    input   [WIDTH_PORT-1:0] define_io_i,   // 1: Output, 0: Input (Tri-state control)
    input   [WIDTH_PORT-1:0] write_port_i,  
    output  [WIDTH_PORT-1:0] read_port_o,

    inout   [WIDTH_PORT-1:0] gpio_io

    );


    // Dây nối nội bộ giữa các module
    wire [WIDTH_PORT-1:0] gpo_to_tri;
    wire [WIDTH_PORT-1:0] tri_to_gpi;

    // 1. Instance module GPO: Lưu trữ dữ liệu xuất ra
    GPO #(.WIDTH_PORT(WIDTH_PORT)) u_gpo (
        .clk_i      (clk_i),
        .resetn_i    (resetn_i),
        .we_i       (we_i),
        .write_port (write_port_i),
        .gpo_o      (gpo_to_tri)
    );

    // 2. Điều khiển Tri-state Buffer cho từng bit
    // Nếu select_io = 1: chân gpio_io là OUTPUT, xuất giá trị từ GPO
    // Nếu select_io = 0: chân gpio_io là INPUT (High-Z), để nhận tín hiệu ngoài
    genvar i;
    generate
        for (i = 0; i < WIDTH_PORT; i = i + 1) begin : gpio_tri_state
            assign gpio_io[i] = (define_io_i[i]) ? gpo_to_tri[i] : 1'bz;
        end
    endgenerate

    // 3. Tín hiệu đi vào GPI là giá trị thực tế trên chân pin
    assign tri_to_gpi = gpio_io;

    // 4. Instance module GPI: Đồng bộ dữ liệu đọc về để khử metastability
    GPI #(.WIDTH_PORT(WIDTH_PORT)) u_gpi (
        .clk_i      (clk_i),
        .resetn_i    (resetn_i),
        .gpi_i      (tri_to_gpi),
        .read_port  (read_port_o)
    );

endmodule


module GPO #(
    parameter WIDTH_PORT = 8
)(  
    input                    clk_i,
    input                    resetn_i,
    input                    we_i,         
    input   [WIDTH_PORT-1:0] write_port,
    output  [WIDTH_PORT-1:0] gpo_o
);

    reg [WIDTH_PORT-1:0] buf_reg;

    always @(posedge clk_i or negedge resetn_i) begin
        if (!resetn_i) begin
            buf_reg <= {WIDTH_PORT{1'b0}};
        end else if (we_i) begin  
            buf_reg <= write_port;
        end
    end

    assign gpo_o = buf_reg;

endmodule



module GPI #(
    parameter WIDTH_PORT = 8
)(  
    input                    clk_i,
    input                    resetn_i,
    input   [WIDTH_PORT-1:0] gpi_i,
    output  [WIDTH_PORT-1:0] read_port
);

    reg [WIDTH_PORT-1:0] sync_reg_1;
    reg [WIDTH_PORT-1:0] sync_reg_2;

    always @(posedge clk_i or negedge resetn_i) begin
        if (!resetn_i) begin
            sync_reg_1 <= {WIDTH_PORT{1'b0}};
            sync_reg_2 <= {WIDTH_PORT{1'b0}};
        end else begin
            sync_reg_1 <= gpi_i;      
            sync_reg_2 <= sync_reg_1; 
        end
    end

    // Output lấy từ tầng thứ 2
    assign read_port = sync_reg_2;

endmodule