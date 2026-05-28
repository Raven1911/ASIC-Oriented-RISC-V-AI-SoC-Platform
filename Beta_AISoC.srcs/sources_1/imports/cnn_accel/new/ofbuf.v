`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 04/02/2026 10:01:44 AM
// Design Name: 
// Module Name: ofbuf
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


module ofbuf#(
    parameter DATA_WIDTH = 8, //Data dua vao FIFO
    parameter DEPTH = 896, //do sau FIFO
    parameter M = 2 //So luong FIFO
)(
    input                           clk,
    input                           rst_n,

    // Giao tiếp info layer
    input                           ofbuf_inf_vld_i,
    input       [23:0]              ofbuf_inf_ofbaddr_l0_i,     //dia chi bat dau store ofmap cua lane 0
    input       [23:0]              ofbuf_inf_ofbaddr_l1_i,     //dia chi bat dau store ofmap cua lane 1
    input       [7:0]               ofbuf_inf_ofwidth_i,        //chieu dai va chieu rong cua channel
    input       [15:0]              ofbuf_inf_ofsize_i,         //kich thuoc mot channel (width align*width)
    input       [6:0]               ofbuf_inf_ofblock_i,        //kich thuoc mot channel (width align*width)
    input       [4:0]               ofbuf_inf_ofc_bl_l0_i,      //so channel ofmap 1 block lane 0
    input       [4:0]               ofbuf_inf_ofc_bl_tail_l0_i, //so channel ofmap 1 block tail lane 0
    input       [4:0]               ofbuf_inf_ofc_bl_l1_i,      //so channel ofmap 1 block lane 1
    input       [4:0]               ofbuf_inf_ofc_bl_tail_l1_i, //so channel ofmap 1 block tail lane 1
    output                          ofbuf_inf_rdy_o,            //Khi nap het channel o block cuoi thi rdy len 1 hoac luc moi khoi dong

    // Tín hiệu DMA
    input                           ofbuf_dma_rdycfg_i,
    output                          ofbuf_dma_vldcfg_o,
    output      [7:0]               ofbuf_dma_burst_o, 
    output      [23:0]              ofbuf_dma_baddr_o,
    output                          ofbuf_dma_vld_o,
    output      [DATA_WIDTH-1:0]    ofbuf_dma_data_o,
    output                          ofbuf_dma_tlast_o,
    input                           ofbuf_dma_rdy_i,

    // Tín hiệu giao tiếp với khối khác
    input       [M-1:0]             ofbuf_comp_vld_i,           //2 khoi FIFO trong ofbuf nhan gia tri tuong ung
    output      [M-1:0]             ofbuf_comp_rdy_o,           //2 khoi FIFO trong ofbuf gui gia tri tuong ung
    input       [M*DATA_WIDTH-1:0]  ofbuf_comp_data_i          //2 khoi FIFO trong ofbuf nhan gia tri tuong ung
    );
    //2FIFO moi FIOFO 896 bytes
   
    reg     [23:0]              ofbaddr_l0_reg;     
    reg     [23:0]              ofbaddr_l1_reg;     
    reg     [7:0]               ofwidth_reg;        
    reg     [15:0]              ofsize_reg;         
    reg     [6:0]               ofblock_reg;        
    reg     [4:0]               ofc_bl_l0_reg;      
    reg     [4:0]               ofc_bl_tail_l0_reg; 
    reg     [4:0]               ofc_bl_l1_reg;      
    reg     [4:0]               ofc_bl_tail_l1_reg;    
    reg                         inf_rdy_dly;
    reg                         inf_rdy_dly2;
    reg     [7:0]               count_row_q;
    reg                         end_row_q;
    reg                         end_row_d_q;
    reg                         tlast_q;
    reg                         rdy_cfg_q;
    reg     [23:0]              baddr_cfg_q;
    wire     [23:0]             baddr_cfg_d;
    reg     [7:0]               burst_q;
    reg                         vld_cfg_dma_q;
    reg                         vld_dma_q;
    reg     [DATA_WIDTH-1:0]    data_dma_q;
    reg                         id_cfg_nxt_q;
    reg                         id_cfg_q;
    reg     [4:0]               cnt_ch_bl_0_q;
    reg                         end_block_0_q;
    reg     [4:0]               cnt_ch_bl_1_q;
    reg                         end_block_1_q;
    reg     [7:0]               cnt_height_q;
    reg     [6:0]               cnt_block_q;
    reg                         last_ifblock_q;
    reg     [23:0]              baddr_l0_q;
    reg     [23:0]              baddr_blnxt_l0_q;
    reg     [23:0]              baddr_l1_q;
    reg     [23:0]              baddr_blnxt_l1_q;
    reg                         vld_cfg_q;
    reg                         inf_rdy_q;
    reg                         last_height_q;
    wire                        rdy_fifo;
    wire    [DATA_WIDTH-1:0]    fifo_data_l0;
    wire                        fifo_full_l0;
    wire                        fifo_vld_l0;
    wire    [DATA_WIDTH-1:0]    fifo_data_l1;
    wire                        fifo_full_l1;
    wire                        fifo_vld_l1;
    wire                        vld_dma_d;
    wire                        tlast_d;
    wire    [DATA_WIDTH-1:0]    data_dma_d;
    wire                        id_cfg_nxt_d;
    wire                        change_config;
    wire                        last_cnt_ch_bl_0_w;
    wire                        last_cnt_ch_bl_1_w;
    wire                        change_id_w;
    wire    [7:0]               cnt_height_d;
    wire                        last_height;
    wire                        last_ifblock;
    wire    [6:0]               cnt_block_d;
    wire    [23:0]              baddr_l0_d;
    wire    [23:0]              baddr_blnxt_l0_d;
    wire    [23:0]              baddr_l1_d;
    wire    [23:0]              baddr_blnxt_l1_d;
    wire                        rst_vld_cfg;
    assign baddr_l0_d           = inf_rdy_dly2 ? ofbaddr_l0_reg : (last_cnt_ch_bl_0_w ? (last_height ? baddr_l0_q + burst_q : baddr_blnxt_l0_q) : (baddr_l0_q + ofsize_reg));  
    assign baddr_blnxt_l0_d     = inf_rdy_dly2 ? ofbaddr_l0_reg + burst_q : (last_height ? baddr_l0_q + {burst_q, 1'b0} : baddr_blnxt_l0_q + burst_q);
    assign baddr_l1_d           = inf_rdy_dly2 ? ofbaddr_l1_reg : (last_cnt_ch_bl_1_w ? (last_height ? baddr_l1_q + burst_q : baddr_blnxt_l1_q) : (baddr_l1_q + ofsize_reg));  
    assign baddr_blnxt_l1_d     = inf_rdy_dly2 ? ofbaddr_l1_reg + burst_q : (last_height ? baddr_l1_q + {burst_q, 1'b0} : baddr_blnxt_l1_q + burst_q);
    assign last_ifblock         = (cnt_block_q == ofblock_reg - 1);
    assign cnt_block_d          = last_ifblock ? 0 : cnt_block_q + 1;
    assign last_height          = cnt_height_q == ofwidth_reg - 1;
    assign cnt_height_d         = last_height ? 0 : cnt_height_q + 1;
    assign change_id_w          = inf_rdy_dly2 || (tlast_d && ofbuf_dma_rdy_i);
    assign id_cfg_nxt_d         = !(id_cfg_nxt_q || end_block_1_q);
    assign last_cnt_ch_bl_0_w   = (cnt_ch_bl_0_q == ofc_bl_l0_reg - 1) || ((cnt_ch_bl_0_q == ofc_bl_tail_l0_reg - 1) && last_ifblock_q);
    assign last_cnt_ch_bl_1_w   = (cnt_ch_bl_1_q == ofc_bl_l1_reg - 1) || ((cnt_ch_bl_1_q == ofc_bl_tail_l1_reg - 1) && last_ifblock_q);
    assign change_config        = rdy_cfg_q && (!vld_cfg_dma_q || ofbuf_dma_rdycfg_i) && vld_dma_d;
    assign vld_dma_d            = id_cfg_q ? fifo_vld_l1 : fifo_vld_l0;
    assign data_dma_d           = id_cfg_q ? fifo_data_l1 : fifo_data_l0;
    assign tlast_d              = ofwidth_reg[0] ? end_row_q : end_row_d_q;
    assign ofbuf_comp_rdy_o     = {!fifo_full_l1, !fifo_full_l0};
    assign rdy_fifo = !(rdy_cfg_q && vld_cfg_dma_q) &&
                  (!vld_dma_q ||
                   (ofbuf_dma_rdy_i && !(tlast_d && ofwidth_reg[0])));
    
    assign ofbuf_dma_burst_o    = burst_q;
    assign ofbuf_dma_baddr_o    = baddr_cfg_q;
    assign ofbuf_dma_vld_o      = vld_dma_q;
    assign ofbuf_dma_data_o     = data_dma_q;
    assign ofbuf_dma_tlast_o    = tlast_q;
    assign ofbuf_dma_vldcfg_o   = vld_cfg_dma_q; 
    assign ofbuf_inf_rdy_o      = inf_rdy_q;
    assign baddr_cfg_d          = id_cfg_nxt_d ? baddr_l1_q : baddr_l0_q;
    fifo_bram #(
        .WIDTH(DATA_WIDTH),
        .DEPTH(DEPTH)
    ) ofbuf_fifo0 (
        .clk(clk),
        .rst_n(rst_n),
        .wr_en(ofbuf_comp_vld_i[0]),
        .rd_en(rdy_fifo && !id_cfg_q),
        .clr(1'b0),
        .din(ofbuf_comp_data_i[DATA_WIDTH-1:0]),
        .dout(fifo_data_l0),
        .full(fifo_full_l0),
        .vld_o(fifo_vld_l0),
        .end_data()
    );
    fifo_bram #(
        .WIDTH(DATA_WIDTH),
        .DEPTH(DEPTH)
    ) ofbuf_fifo1 (
        .clk(clk),
        .rst_n(rst_n),
        .wr_en(ofbuf_comp_vld_i[1]),
        .rd_en(rdy_fifo && id_cfg_q),
        .clr(1'b0),
        .din(ofbuf_comp_data_i[2*DATA_WIDTH-1:DATA_WIDTH]),
        .dout(fifo_data_l1),
        .full(fifo_full_l1),
        .vld_o(fifo_vld_l1),
        .end_data()
    );

    always @(posedge clk) begin
        if(ofbuf_inf_rdy_o) begin
            ofbaddr_l0_reg          <=      ofbuf_inf_ofbaddr_l0_i; 
            ofbaddr_l1_reg          <=      ofbuf_inf_ofbaddr_l1_i;
            ofwidth_reg             <=      ofbuf_inf_ofwidth_i;
            ofsize_reg              <=      ofbuf_inf_ofsize_i; 
            ofblock_reg             <=      ofbuf_inf_ofblock_i;
            ofc_bl_l0_reg           <=      ofbuf_inf_ofc_bl_l0_i;  
            ofc_bl_tail_l0_reg      <=      ofbuf_inf_ofc_bl_tail_l0_i; 
            ofc_bl_l1_reg           <=      ofbuf_inf_ofc_bl_l1_i;  
            ofc_bl_tail_l1_reg      <=      ofbuf_inf_ofc_bl_tail_l1_i; 
        end
        inf_rdy_dly     <= ofbuf_inf_rdy_o && ofbuf_inf_vld_i;
        inf_rdy_dly2   <= inf_rdy_dly;
        burst_q         <= ofwidth_reg + ofwidth_reg[0];
        last_ifblock_q  <= last_ifblock && !ofbuf_inf_rdy_o;
        last_height_q   <= last_height && !ofbuf_inf_rdy_o;
    end

    always @(posedge clk) begin
        if(!rst_n) begin
            inf_rdy_q <= 1;
        end else begin 
            if(ofbuf_inf_vld_i) begin
                inf_rdy_q <= 1'b0;
            end else if(!(vld_cfg_q || vld_cfg_dma_q || vld_dma_q) && !inf_rdy_dly) begin
                inf_rdy_q <= 1;
            end
        end
    end

    always @(posedge clk) begin
        if(ofbuf_inf_rdy_o) begin
            count_row_q <= 0;
        end else if(rdy_fifo && vld_dma_d) begin //change end else if((rdy_fifo || !vld_dma_q) && vld_dma_d) begin
            count_row_q <= (count_row_q == ofwidth_reg - 1) ? 0 : count_row_q + 1;
        end
    end
    always @(posedge clk) begin
        if(ofbuf_inf_rdy_o) begin
            end_row_d_q <= 0;
        end else if((rdy_fifo || !vld_dma_q) && vld_dma_d) begin
            end_row_d_q <= (count_row_q + 1 == ofwidth_reg - 1);
        end
    end

    always @(posedge clk) begin
        if(ofbuf_inf_rdy_o) begin
            vld_dma_q   <= 0;
        end else if((rdy_cfg_q && vld_cfg_dma_q) || rdy_fifo || !vld_dma_q) begin
            vld_dma_q   <= vld_dma_d && !(rdy_cfg_q && vld_cfg_dma_q);
        end
    end
    always @(posedge clk) begin
        if((rdy_cfg_q && vld_cfg_dma_q) || rdy_fifo || !vld_dma_q) begin
            data_dma_q  <= data_dma_d;
        end
    end
    always @(posedge clk) begin
        if(ofbuf_inf_rdy_o) begin
            end_row_q   <= 0;
            tlast_q     <= 0;
        end else if(ofbuf_dma_rdy_i) begin
            tlast_q     <= tlast_d;
            end_row_q   <= end_row_d_q;
        end
    end
    always @(posedge clk) begin
        if(inf_rdy_dly || (tlast_d && ofbuf_dma_rdy_i)) begin 
            rdy_cfg_q <= 1;
        end else if(vld_cfg_q && vld_dma_d && change_config) begin //change end else if(vld_cfg_q && vld_dma_d && rdy_cfg_q) begin
            rdy_cfg_q <= 0;
        end
    end
    always @(posedge clk) begin
        if(vld_cfg_q && vld_dma_d && change_config) begin //change if(vld_cfg_q && vld_dma_d && rdy_cfg_q) begin
            vld_cfg_dma_q <= 1;
        end else if(ofbuf_dma_rdycfg_i || inf_rdy_q) begin
            vld_cfg_dma_q <= 0;
        end
    end
    always @(posedge clk) begin
        if(vld_cfg_q && vld_dma_d && change_config) begin //change if(vld_cfg_q && vld_dma_d && rdy_cfg_q) begin
            baddr_cfg_q <= baddr_cfg_d;
        end
    end
    always @(posedge clk) begin
        if(change_id_w) begin
            id_cfg_q <= id_cfg_nxt_q;
        end
    end
    
    //PREPARE NEXT CONFIG
    always @(posedge clk) begin
        if(ofbuf_inf_rdy_o) begin
            cnt_ch_bl_0_q <= 0;
        end else if(!id_cfg_nxt_d && change_config) begin
            cnt_ch_bl_0_q <= last_cnt_ch_bl_0_w ? 0 : cnt_ch_bl_0_q + 1;
        end
    end
    always @(posedge clk) begin
        if(ofbuf_inf_rdy_o) begin
            cnt_ch_bl_1_q <= 0;
        end else if(id_cfg_nxt_d && change_config) begin
            cnt_ch_bl_1_q <= last_cnt_ch_bl_1_w ? 0 : cnt_ch_bl_1_q + 1;
        end
    end
    always @(posedge clk) begin
        if(last_cnt_ch_bl_0_w && change_config && !id_cfg_nxt_d) begin
            end_block_0_q <= 1;
        end else if(inf_rdy_dly || (end_block_0_q && end_block_1_q)) begin
            end_block_0_q <= 0;
        end
    end
    always @(posedge clk) begin
        if((last_cnt_ch_bl_1_w && change_config && id_cfg_nxt_d) || !(|ofc_bl_l1_reg) || (last_ifblock_q && !(|ofc_bl_tail_l1_reg))) begin
            end_block_1_q <= 1;
        end else if(inf_rdy_dly || (end_block_0_q && end_block_1_q)) begin
            end_block_1_q <= 0;
        end
    end
    always @(posedge clk) begin
        if(ofbuf_inf_rdy_o) begin
            id_cfg_nxt_q <= 0;
        end else if(change_id_w) begin
            id_cfg_nxt_q <= id_cfg_nxt_d;
        end
    end
    always @(posedge clk) begin
        if(ofbuf_inf_rdy_o) begin
            cnt_height_q <= 0;
        end else if(end_block_0_q && end_block_1_q) begin
            cnt_height_q <= cnt_height_d;
        end
    end
    always @(posedge clk) begin
        if(ofbuf_inf_rdy_o) begin
            cnt_block_q <= 0;
        end else if(last_height && end_block_0_q && end_block_1_q) begin
            cnt_block_q <= cnt_block_d;
        end
    end
    always @(posedge clk) begin
        if((!id_cfg_nxt_d && change_config) || inf_rdy_dly2) begin
            baddr_l0_q <= baddr_l0_d;
        end
    end
    // always @(posedge clk) begin
    //     if(change_config || inf_rdy_dly2) begin
            
    //     end
    // end
    always @(posedge clk) begin
        if((id_cfg_nxt_d && change_config) || inf_rdy_dly2) begin
            baddr_l1_q <= baddr_l1_d;
        end
    end
    always @(posedge clk) begin
        if((!id_cfg_nxt_d && change_config && last_cnt_ch_bl_0_w) || inf_rdy_dly2) begin
            baddr_blnxt_l0_q <= baddr_blnxt_l0_d;
        end
    end
    always @(posedge clk) begin
        if((id_cfg_nxt_d && change_config && last_cnt_ch_bl_1_w) || inf_rdy_dly2) begin
            baddr_blnxt_l1_q <= baddr_blnxt_l1_d;
        end
    end
    posedge_detection f(
        .clk(clk),
        .rst_n(rst_n),
        .signal_i((last_ifblock_q && end_block_0_q && end_block_1_q && last_height_q)),
        .signal_o(rst_vld_cfg)
    );
    always @(posedge clk) begin
        if(ofbuf_inf_rdy_o || rst_vld_cfg) begin
            vld_cfg_q <= 0;
        end else if(inf_rdy_dly) begin
            vld_cfg_q <= 1;
        end
    end
endmodule

