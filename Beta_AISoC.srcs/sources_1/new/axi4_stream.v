`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 04/02/2026 11:42:54 AM
// Design Name: 
// Module Name: axi4_stream
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



module axi4_stream#(
    parameter DATA_WIDTH_BYTE = 1, // byte unit, 1: 8bit, 2: 16bit, 4: 32bit, 8: 64bit
    parameter SELECT_INTERFACE = 0, // 0: master interface, 1: slave interface
    parameter SIZE_FIFO = 8 // 2^SIZE_FIFO is the depth of FIFO
)(
    //generate port
    input                           aclk_i,
    input                           aresetn_i,
    /////////////////////////////////////////////////
    //master interface port
    /////////////////////////////////////////////////
    output                          m_tvalid_o,
    input                           m_tready_i,
    output  [DATA_WIDTH_BYTE*8-1:0] m_tdata_o,
    output  [DATA_WIDTH_BYTE-1:0]   m_tstrb_o,
    output  [DATA_WIDTH_BYTE-1:0]   m_tkeep_o,
    output                          m_tlast_o,
    output                          m_tid_o,

    //user master interface port
    output                          user_m_empty_o,
    output                          user_m_busy_o,
    input                           user_m_wr_data_i,
    input  [DATA_WIDTH_BYTE*8-1:0]  user_m_data_i,
    input  [DATA_WIDTH_BYTE-1:0]    user_m_tstrb_i,
    input  [DATA_WIDTH_BYTE-1:0]    user_m_tkeep_i,
    input                           user_m_tlast_i,
    input                           user_m_tid_i,
    /////////////////////////////////////////////////

    /////////////////////////////////////////////////
    //slave interface port
    /////////////////////////////////////////////////
    input                           s_tvalid_i,
    output                          s_tready_o,
    input  [DATA_WIDTH_BYTE*8-1:0]  s_tdata_i,
    input  [DATA_WIDTH_BYTE-1:0]    s_tstrb_i,
    input  [DATA_WIDTH_BYTE-1:0]    s_tkeep_i,
    input                           s_tlast_i,
    input                           s_tid_i,

    //user slave interface port
    output                          user_s_full_o,
    output                          user_s_ready_o,
    input                           user_s_rd_data_i,
    output  [DATA_WIDTH_BYTE*8-1:0] user_s_data_o,
    output  [DATA_WIDTH_BYTE-1:0]   user_s_tstrb_o,
    output  [DATA_WIDTH_BYTE-1:0]   user_s_tkeep_o,
    output                          user_s_tlast_o,
    output                          user_s_tid_o
    /////////////////////////////////////////////////
    );

    generate
        //master interface
        if (SELECT_INTERFACE == 0) begin
            
            wire empty_i, full_i, rd_fifo_o;
            wire [DATA_WIDTH_BYTE*8-1:0] fifo_m_tdata;
            wire [DATA_WIDTH_BYTE-1:0]   fifo_m_tstrb;
            wire [DATA_WIDTH_BYTE-1:0]   fifo_m_tkeep;
            wire                          fifo_m_tlast;
            wire                          fifo_m_tid;

            coordinator_master#(
                .DATA_WIDTH_BYTE(DATA_WIDTH_BYTE)
            )coordinator_master_uut(
                //port generate
                .m_tvalid_o(m_tvalid_o),
                .m_tready_i(m_tready_i),
                .user_m_busy_o(user_m_busy_o),
                .empty_i(empty_i),
                .full_i(full_i),
                .rd_fifo_o(rd_fifo_o)
            );

            // wire  [DATA_WIDTH_BYTE*8-1:0] wire_tdata;
            // wire  [DATA_WIDTH_BYTE-1:0]   wire_tstrb;
            // wire  [DATA_WIDTH_BYTE-1:0]   wire_tkeep;
            // wire                          wire_tlast;

            // register_DFF #(
            //     .SIZE_BITS(1 + DATA_WIDTH_BYTE + DATA_WIDTH_BYTE + (DATA_WIDTH_BYTE*8))
            // ) stage_delay_data (
            //     .clk_i(aclk_i),
            //     .resetn_i(aresetn_i),
            //     .D_i({user_m_tlast_i, user_m_tkeep_i, user_m_tstrb_i, user_m_data_i}),
            //     .Q_o({wire_tlast, wire_tkeep, wire_tstrb, wire_tdata})
            // );

            fifo_unit #(.ADDR_WIDTH(SIZE_FIFO), .DATA_WIDTH(2 + DATA_WIDTH_BYTE + DATA_WIDTH_BYTE + (DATA_WIDTH_BYTE*8))) buffer_uut(
                .clk(aclk_i), 
                .reset_n(aresetn_i),
                .wr(user_m_wr_data_i && !user_m_busy_o), 
                .rd(rd_fifo_o),
                // .wr_ptr(),
                // .rd_ptr(),
                .w_data({user_m_tid_i, user_m_tlast_i, user_m_tkeep_i, user_m_tstrb_i, user_m_data_i}),                //writing data
                .r_data({fifo_m_tid, fifo_m_tlast, fifo_m_tkeep, fifo_m_tstrb, fifo_m_tdata}),                    //reading data
                .full(full_i),
                .empty(empty_i)
            );

            assign user_m_empty_o = empty_i;
            assign m_tdata_o      = empty_i ? {(DATA_WIDTH_BYTE*8){1'b0}} : fifo_m_tdata;
            assign m_tstrb_o      = empty_i ? {DATA_WIDTH_BYTE{1'b0}}     : fifo_m_tstrb;
            assign m_tkeep_o      = empty_i ? {DATA_WIDTH_BYTE{1'b0}}     : fifo_m_tkeep;
            assign m_tlast_o      = empty_i ? 1'b0                        : fifo_m_tlast;
            assign m_tid_o        = empty_i ? 1'b0                        : fifo_m_tid;

            
        end

        //slave interface
        else if (SELECT_INTERFACE == 1) begin
            wire empty_i, full_i, wr_fifo_o;

            coordinator_slave#(
                .DATA_WIDTH_BYTE(DATA_WIDTH_BYTE)
            )coordinator_slave_uut(
                //port generate
                .s_tvalid_i(s_tvalid_i),
                .s_tready_o(s_tready_o),
                .user_s_ready_o(user_s_ready_o),
                .empty_i(empty_i),
                .full_i(full_i),
                .wr_fifo_o(wr_fifo_o)
            );

            

            fifo_unit #(.ADDR_WIDTH(SIZE_FIFO), .DATA_WIDTH(2 + DATA_WIDTH_BYTE + DATA_WIDTH_BYTE + (DATA_WIDTH_BYTE*8))) buffer_uut(
                .clk(aclk_i), 
                .reset_n(aresetn_i),
                .wr(wr_fifo_o), 
                .rd(user_s_rd_data_i && user_s_ready_o),
                // .wr_ptr(),
                // .rd_ptr(),
                .w_data({s_tid_i, s_tlast_i, s_tkeep_i, s_tstrb_i, s_tdata_i}),                                       //writing data
                .r_data({user_s_tid_o, user_s_tlast_o, user_s_tkeep_o, user_s_tstrb_o, user_s_data_o}),                    //reading data
                .full(full_i),
                .empty(empty_i)
            );
            
            assign user_s_full_o = full_i;

        end
    endgenerate



endmodule



module coordinator_master#(
    parameter DATA_WIDTH_BYTE = 2
)(
    /////////////////////////////////////////////////
    //port master interface
    /////////////////////////////////////////////////
    output                          m_tvalid_o,
    input                           m_tready_i,
    output                          user_m_busy_o,
    //port FIFO interface
    input                           empty_i,
    input                           full_i,
    output                          rd_fifo_o
);

    assign m_tvalid_o = !empty_i;
    assign rd_fifo_o = (m_tvalid_o == 1 && m_tready_i == 1) ? 1'b1 : 1'b0;
    assign user_m_busy_o = full_i;

endmodule


module coordinator_slave#(
    parameter DATA_WIDTH_BYTE = 2
)(
    /////////////////////////////////////////////////
    //port slave interface
    /////////////////////////////////////////////////
    input                           s_tvalid_i,
    output                          s_tready_o,
    
    output                          user_s_ready_o,


    //port FIFO interface
    input                           empty_i,
    input                           full_i,
    output                          wr_fifo_o

);
    assign s_tready_o = (!full_i && s_tvalid_i == 1) ? 1'b1 : 1'b0;
    assign wr_fifo_o = (s_tvalid_i == 1 && s_tready_o == 1) ? 1'b1 : 1'b0;
    assign user_s_ready_o = !empty_i;

endmodule




module decoder_1to2_axis_interface #(
    parameter DATA_WIDTH_BYTE = 1
)(
    //master interface port (Input từ Hyperbus FIFO)
    input                           m_tvalid_i,
    output                          m_tready_o,
    input  [DATA_WIDTH_BYTE*8-1:0]  m_tdata_i,
    input  [DATA_WIDTH_BYTE-1:0]    m_tstrb_i,
    input  [DATA_WIDTH_BYTE-1:0]    m_tkeep_i,
    input                           m_tlast_i,
    input                           m_tid_i,

    //slave interface port 0 (Output ra Accel AR0)
    output                          s_tvalid0_o,
    input                           s_tready0_i,
    output [DATA_WIDTH_BYTE*8-1:0]  s_tdata0_o,
    output [DATA_WIDTH_BYTE-1:0]    s_tstrb0_o,
    output [DATA_WIDTH_BYTE-1:0]    s_tkeep0_o,
    output                          s_tlast0_o,

    //slave interface port 1 (Output ra Accel AR1)
    output                          s_tvalid1_o,
    input                           s_tready1_i,
    output [DATA_WIDTH_BYTE*8-1:0]  s_tdata1_o,
    output [DATA_WIDTH_BYTE-1:0]    s_tstrb1_o,
    output [DATA_WIDTH_BYTE-1:0]    s_tkeep1_o,
    output                          s_tlast1_o
);

    // ==========================================
    // DEMUX LOGIC (Dựa vào m_tid_i)
    // ==========================================

    // 1. Phân luồng TVALID (Chiều đi tới Accel)
    // Chỉ báo Valid cho Kênh 0 nếu ID = 0, và Kênh 1 nếu ID = 1
    assign s_tvalid0_o = m_tvalid_i & (m_tid_i == 1'b0);
    assign s_tvalid1_o = m_tvalid_i & (m_tid_i == 1'b1);

    // 2. Phân luồng TREADY (Chiều ngược lại từ Accel về FIFO)
    // Master (FIFO) chỉ thấy trạng thái Ready của kênh đang được chọn bởi ID
    assign m_tready_o  = (m_tid_i == 1'b0) ? s_tready0_i : s_tready1_i;

    // 3. Broadcast Data & Sideband Signals (Tiết kiệm Logic)
    assign s_tdata0_o  = m_tdata_i;
    assign s_tdata1_o  = m_tdata_i;

    assign s_tstrb0_o  = m_tstrb_i;
    assign s_tstrb1_o  = m_tstrb_i;

    assign s_tkeep0_o  = m_tkeep_i;
    assign s_tkeep1_o  = m_tkeep_i;

    assign s_tlast0_o  = m_tlast_i;
    assign s_tlast1_o  = m_tlast_i;

endmodule
