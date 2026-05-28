// `timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 03/04/2026 02:30:49 PM
// Design Name: 
// Module Name: Beta_AISoC_Unified_Vendor_tb
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
`timescale 1ps / 1ps  // Required resolution for the s27kl0641 HyperRAM model


// module Beta_AISoC_Unified_Vendor_tb;

//     //---------------------------------------------------------
//     // 1. Clock and Reset Signals
//     //---------------------------------------------------------
//     reg clk_p, clk_n;
//     reg reset_n;

//     //---------------------------------------------------------
//     // 2. SoC Peripheral Connections
//     //---------------------------------------------------------
//     reg [31:0]  irq_in;
//     wire[31:0]  eoi;

//     // rx0 is a wire because it is driven by the UART Monitor/Responder
//     wire        rx0; 
//     wire        tx0;
//     wire [1:0]  spi0_ss_n;
//     wire        spi0_clk, spi0_mosi, spi0_miso;
    
//     // Use tri for I2C to support multiple devices and pull-ups
//     tri         i2c0_scl, i2c0_sda;
    
//     // OSPI (HyperBus) signals for s27kl0641 RAM
//     wire [7:0]  ospi0_dq_io;
//     wire        ospi0_rwds_io;
//     wire        ospi0_hclk_p, ospi0_cs_n, ospi0_resetn;
    
//     wire [3:0]  gpo;
//     reg  [3:0]  gpi;
//     wire [7:0]  gpio_bus;
//     assign gpio_bus = {gpi,4'bz};
    
//     wire        trap0, trap1;

//     // I2C Bus Pull-up Resistors (Mandatory for I2C operation)
//     pullup(i2c0_scl);
//     pullup(i2c0_sda);

//     //---------------------------------------------------------
//     // 3. SoC Unit Under Test (UUT) Instance
//     //---------------------------------------------------------
//     Beta_AISoC Beta_AISoC_uut (
//         .clk_p(clk_p),
//         .clk_n(clk_n),
//         .resetn(reset_n),
//         .trap0(trap0),
//         .trap1(trap1),
//         // .irq(irq_in),
//         // .eoi(eoi),
//         .rx0(rx0),         // Receives data from UART Monitor
//         .tx0(tx0),         // Sends data to UART Monitor
//         .spi0_clk(spi0_clk),
//         .spi0_mosi(spi0_mosi),
//         .spi0_miso(spi0_miso),
//         .spi0_ss_n(spi0_ss_n),      
//         .i2c0_scl(i2c0_scl),
//         .i2c0_sda(i2c0_sda),
//         .ospi0_dq_io(ospi0_dq_io),
//         .ospi0_rwds_io(ospi0_rwds_io),
//         .ospi0_hclk_p(ospi0_hclk_p),
//         .ospi0_cs_n(ospi0_cs_n),
//         .ospi0_resetn(ospi0_resetn),
//         .gpio_io(gpio_bus)
//     );

//     //---------------------------------------------------------
//     // 4. Professional IC Models and Emulators
//     //---------------------------------------------------------
//     // UART Monitor & Responder Instance
//     uart_monitor_responder #(
//         .BAUD_RATE(115200),
//         .CLK_FREQ(200_000_000),
//         .TRIGGER_DATA(8'h3F),         // Trigger on '?'
//         .MEM_FILE("uart_monitor.mem"), // Hex response file
//         .MEM_DEPTH(64)
//     ) uart_mon_inst (
//         .rx(tx0), 
//         .tx(rx0)  
//     );

//     // I2C EEPROM Model (Configuration or Device ID storage)
//     i2c_eeprom_model #(
//         .I2C_ADR(7'h50),             // Default address 0x50
//         .MEM_SIZE(256),              // 256 Bytes capacity
//         .INIT_FILE("i2c_eeprom.mem") // Load initial data
//     ) eeprom_inst (
//         .scl(i2c0_scl),
//         .sda(i2c0_sda)
//     );

//     // HyperRAM Model (s27kl0641)
//     s27kl0641 #(
//         .UserPreload(0),
//         .mem_file_name("s27kl0641.mem")
//     ) dram_inst (
//         .DQ7(ospi0_dq_io[7]), .DQ6(ospi0_dq_io[6]), 
//         .DQ5(ospi0_dq_io[5]), .DQ4(ospi0_dq_io[4]),
//         .DQ3(ospi0_dq_io[3]), .DQ2(ospi0_dq_io[2]), 
//         .DQ1(ospi0_dq_io[1]), .DQ0(ospi0_dq_io[0]),
//         .RWDS(ospi0_rwds_io),
//         .CSNeg(ospi0_cs_n),
//         .CK(ospi0_hclk_p),
//         .RESETNeg(ospi0_resetn)
//     );

//     // SPI Flash Model (W25Q128JVxIM)
//     wire flash_wp_n = 1'b1;
//     wire flash_hold_n = 1'b1;
//     W25Q128JVxIM flash_inst (
//         .CSn(spi0_ss_n[0]),
//         .CLK(spi0_clk),
//         .DIO(spi0_mosi),
//         .DO(spi0_miso),
//         .WPn(flash_wp_n),
//         .HOLDn(flash_hold_n)
//     );

//     //---------------------------------------------------------
//     // 5. Clock Generation and Simulation Scenario
//     //---------------------------------------------------------
//     initial begin
//         clk_p = 0; clk_n = 1;
//         // forever #2.5 begin // 200 MHz (5ns period)
//         //     clk_p = ~clk_p;
//         //     clk_n = ~clk_p;
//         // end
//         forever #2500 begin // 200 MHz (5ns period)
//             clk_p = ~clk_p;
//             clk_n = ~clk_p;
//         end
//     end

//     initial begin
//         // Đợi 50000 chu kỳ xung nhịp clk_p
//         repeat (50000) @(posedge clk_p);
        
//         $display("[%t] Dang xuat du lieu RAM ra file doc theo Byte Address...", $time);
        
//         begin : DUMP_RAM_BLOCK
//             integer fd;
//             integer i;
//             integer byte_addr;
            
//             // 1. Mở file để ghi
//             fd = $fopen("output_data_s27kl0641.mem", "w");
            
//             $fdisplay(fd, "//# FILE NAY DUNG DE DOC BANG MAT (BYTE ADDRESS)");
//             $fdisplay(fd, "//# @Dia_chi_Byte   Du_lieu(16-bit)");
            
//             // 2. Quét toàn bộ dải địa chỉ của RAM
//             for (i = 0; i <= 25'h3FFFFF; i = i + 1) begin
                
//                 // Tính địa chỉ thật của phần cứng (1 Word = 2 Byte nên nhân 2)
//                 byte_addr = i * 2;
                
//                 // In ra địa chỉ Byte thực tế kèm dữ liệu ngay trên cùng 1 dòng
//                 $fdisplay(fd, "@%06X %04X", byte_addr, dram_inst.Mem[i][15:0]);
                
//             end
            
//             // 3. Đóng file
//             $fclose(fd);
//         end
//         $display("========== DA XUAT DU LIEU RAM RA FILE XONG ==========");
//     end

//     initial begin
//         // Initialize simulation state
//         reset_n = 0;
//         gpi     = 4'b1100;
//         irq_in  = 32'h0;

//         $display("[%t] Starting unified SoC simulation: UART Monitor, EEPROM, Flash, HyperRAM...", $time);
//         // 1. Ép RAM chạy biên dịch timing 100MHz giống tb4.v
//         dram_inst.SPEED100 = 1; 
        
//         // 2. GIỮ RESET CPU VÀ CHỜ RAM KHỞI ĐỘNG XONG MỚI ĐƯỢC BOOT
//         @ (posedge dram_inst.PoweredUp); 
//         $display("[%t] HyperRAM is Powered Up!", $time);

//         #100000; 
//         reset_n = 1;
//         $display("[%t] System Reset released. CPU is booting...", $time);

//         // Interrupt Trigger Demo
//         // #5000000;
//         // $display("[%t] Triggering Interrupt IRQ[3]...", $time);
//         // irq_in[3] = 1'b1;
//         // #2500000;
//         // irq_in[3] = 1'b0;

//         // Wait until CPU hits a trap or halts
//         wait(trap0 || trap1);
//         $display("[%t] Trap detected! Simulation terminated.", $time);
        
//         #50000;
//         $finish;
//     end

// endmodule


// // `timescale 1ps / 1ps  // Required resolution for the s27kl0641 HyperRAM model
// module Beta_AISoC_Unified_Vendor_tb;

//     //---------------------------------------------------------
//     // 1. Clock and Reset Signals
//     //---------------------------------------------------------
//     reg clk_p, clk_n;
//     reg reset_n;

//     //---------------------------------------------------------
//     // 2. SoC Peripheral Connections
//     //---------------------------------------------------------
//     reg [31:0]  irq_in;
//     wire[31:0]  eoi;

//     // UART
//     wire        uart0_rx, uart0_tx;
//     wire        uart1_rx, uart1_tx;

//     // SPI (Giả sử NSlave = 1 hoặc 2, khai báo [1:0] cho an toàn)
//     wire        spi0_ss_n;
//     wire        spi0_clk, spi0_mosi, spi0_miso;
    
//     wire        spi1_ss_n;
//     wire        spi1_clk, spi1_mosi, spi1_miso;
    
//     // I2C (Use tri for I2C to support multiple devices and pull-ups)
//     tri         i2c0_scl, i2c0_sda;
//     tri         i2c1_scl, i2c1_sda;
    
//     // OSPI 0 (HyperBus)
//     wire [7:0]  ospi0_dq_io;
//     wire        ospi0_rwds_io;
//     wire        ospi0_hclk_p, ospi0_cs_n, ospi0_resetn;

//     // OSPI 1 (HyperBus)
//     wire [7:0]  ospi1_dq_io;
//     wire        ospi1_rwds_io;
//     wire        ospi1_hclk_p, ospi1_cs_n, ospi1_resetn;
    
//     // GPIO
//     wire [3:0]  gpo;
//     reg  [3:0]  gpi;
//     wire [7:0]  gpio_bus;
//     assign gpio_bus = {gpi, 4'bz};
    
//     // TRAP
//     wire        trap0, trap1;

//     //---------------------------------------------------------
//     // I2C Bus Pull-up Resistors (Mandatory for I2C operation)
//     //---------------------------------------------------------
//     pullup(i2c0_scl); pullup(i2c0_sda);
//     pullup(i2c1_scl); pullup(i2c1_sda);


//     //---------------------------------------------------------
//     // 3. SoC Unit Under Test (UUT) Instance
//     //---------------------------------------------------------
//     Beta_AISoC Beta_AISoC_uut (
//         .clk_p(clk_p),
//         .clk_n(clk_n),
//         .resetn(reset_n),
        
//         .trap0(trap0),
//         .trap1(trap1),
//         // .irq(irq_in),
//         // .eoi(eoi),

//         // UART 0 & 1
//         .uart0_rx(uart0_rx),
//         .uart0_tx(uart0_tx),
//         .uart1_rx(uart1_rx),
//         .uart1_tx(uart1_tx),

//         // SPI 0 & 1
//         .spi0_clk(spi0_clk),
//         .spi0_mosi(spi0_mosi),
//         .spi0_miso(spi0_miso),
//         .spi0_ss_n(spi0_ss_n),      
        
//         .spi1_clk(spi1_clk),
//         .spi1_mosi(spi1_mosi),
//         .spi1_miso(spi1_miso),
//         .spi1_ss_n(spi1_ss_n),

//         // I2C 0 & 1
//         .i2c0_scl(i2c0_scl),
//         .i2c0_sda(i2c0_sda),
//         .i2c1_scl(i2c1_scl),
//         .i2c1_sda(i2c1_sda),

//         // OSPI 0 & 1
//         .ospi0_dq_io(ospi0_dq_io),
//         .ospi0_rwds_io(ospi0_rwds_io),
//         .ospi0_hclk_p(ospi0_hclk_p),
//         .ospi0_cs_n(ospi0_cs_n),
//         .ospi0_resetn(ospi0_resetn),

//         .ospi1_dq_io(ospi1_dq_io),
//         .ospi1_rwds_io(ospi1_rwds_io),
//         .ospi1_hclk_p(ospi1_hclk_p),
//         .ospi1_cs_n(ospi1_cs_n),
//         .ospi1_resetn(ospi1_resetn),

//         // GPIO
//         .gpio_io(gpio_bus)
//     );

//     //---------------------------------------------------------
//     // 4. Professional IC Models and Emulators (DUPLICATED)
//     //---------------------------------------------------------
    
//     // ===== UART Monitors =====
//     uart_monitor_responder #(
//         .BAUD_RATE(115200),
//         .CLK_FREQ(200_000_000),
//         .TRIGGER_DATA(8'h3F),         // Trigger on '?'
//         .MEM_FILE("uart_monitor.mem"), 
//         .MEM_DEPTH(64)
//     ) uart_mon_inst0 (
//         .rx(uart0_tx), 
//         .tx(uart0_rx)  
//     );

//     uart_monitor_responder #(
//         .BAUD_RATE(115200),
//         .CLK_FREQ(200_000_000),
//         .TRIGGER_DATA(8'h3F),         // Trigger on '?'
//         .MEM_FILE("uart_monitor.mem"), // Dùng chung hoặc tạo file uart_monitor1.mem
//         .MEM_DEPTH(64)
//     ) uart_mon_inst1 (
//         .rx(uart1_tx), 
//         .tx(uart1_rx)  
//     );

//     // ===== I2C EEPROMs =====
//     i2c_eeprom_model #(
//         .I2C_ADR(7'h50),             // Default address 0x50
//         .MEM_SIZE(256),              // 256 Bytes capacity
//         .INIT_FILE("i2c_eeprom.mem") 
//     ) eeprom_inst0 (
//         .scl(i2c0_scl),
//         .sda(i2c0_sda)
//     );

//     i2c_eeprom_model #(
//         .I2C_ADR(7'h50),             // Bus khác nhau nên vẫn có thể giữ địa chỉ 0x50
//         .MEM_SIZE(256),              
//         .INIT_FILE("i2c_eeprom.mem") // Có thể trỏ tới i2c_eeprom1.mem nếu cần data khác
//     ) eeprom_inst1 (
//         .scl(i2c1_scl),
//         .sda(i2c1_sda)
//     );

//     // ===== SPI Flash (W25Q128JVxIM) =====
//     wire flash0_wp_n = 1'b1;
//     wire flash0_hold_n = 1'b1;
//     W25Q128JVxIM flash_inst0 (
//         .CSn(spi0_ss_n),
//         .CLK(spi0_clk),
//         .DIO(spi0_mosi),
//         .DO(spi0_miso),
//         .WPn(flash0_wp_n),
//         .HOLDn(flash0_hold_n)
//     );

//     wire flash1_wp_n = 1'b1;
//     wire flash1_hold_n = 1'b1;
//     W25Q128JVxIM flash_inst1 (
//         .CSn(spi1_ss_n),
//         .CLK(spi1_clk),
//         .DIO(spi1_mosi),
//         .DO(spi1_miso),
//         .WPn(flash1_wp_n),
//         .HOLDn(flash1_hold_n)
//     );

//     // ===== HyperRAMs (s27kl0641) =====
//     s27kl0641 #(
//         .UserPreload(0),
//         .mem_file_name("s27kl0641.mem")
//     ) dram_inst0 (
//         .DQ7(ospi0_dq_io[7]), .DQ6(ospi0_dq_io[6]), 
//         .DQ5(ospi0_dq_io[5]), .DQ4(ospi0_dq_io[4]),
//         .DQ3(ospi0_dq_io[3]), .DQ2(ospi0_dq_io[2]), 
//         .DQ1(ospi0_dq_io[1]), .DQ0(ospi0_dq_io[0]),
//         .RWDS(ospi0_rwds_io),
//         .CSNeg(ospi0_cs_n),
//         .CK(ospi0_hclk_p),
//         .RESETNeg(ospi0_resetn)
//     );

//     s27kl0641 #(
//         .UserPreload(0),
//         .mem_file_name("s27kl0641.mem") // Hoặc trỏ tới s27kl0641_1.mem nếu cần RAM data khác
//     ) dram_inst1 (
//         .DQ7(ospi1_dq_io[7]), .DQ6(ospi1_dq_io[6]), 
//         .DQ5(ospi1_dq_io[5]), .DQ4(ospi1_dq_io[4]),
//         .DQ3(ospi1_dq_io[3]), .DQ2(ospi1_dq_io[2]), 
//         .DQ1(ospi1_dq_io[1]), .DQ0(ospi1_dq_io[0]),
//         .RWDS(ospi1_rwds_io),
//         .CSNeg(ospi1_cs_n),
//         .CK(ospi1_hclk_p),
//         .RESETNeg(ospi1_resetn)
//     );

//     //---------------------------------------------------------
//     // 5. Clock Generation and Simulation Scenario
//     //---------------------------------------------------------
//     initial begin
//         clk_p = 0; clk_n = 1;
//         // 200 MHz (5ns period / 5000ps) => Half period = 2500ps
//         forever #2500 begin 
//             clk_p = ~clk_p;
//             clk_n = ~clk_p;
//         end
//     end

//     // Dump RAM data
//     initial begin
//         // Đợi 50000 chu kỳ xung nhịp clk_p
//         repeat (500000) @(posedge clk_p);
        
//         $display("[%t] Dang xuat du lieu RAM ra file doc theo Byte Address...", $time);
        
//         begin : DUMP_RAM_BLOCK
//             integer fd0, fd1;
//             integer i;
//             integer byte_addr;
            
//             // 1. Mở file để ghi
//             fd0 = $fopen("output_data_s27kl0641_0.mem", "w");
//             fd1 = $fopen("output_data_s27kl0641_1.mem", "w");
            
//             $fdisplay(fd0, "//# FILE NAY DUNG DE DOC BANG MAT (BYTE ADDRESS) CHO OSPI 0");
//             $fdisplay(fd0, "//# @Dia_chi_Byte   Du_lieu(16-bit)");

//             $fdisplay(fd1, "//# FILE NAY DUNG DE DOC BANG MAT (BYTE ADDRESS) CHO OSPI 1");
//             $fdisplay(fd1, "//# @Dia_chi_Byte   Du_lieu(16-bit)");
            
//             // 2. Quét toàn bộ dải địa chỉ của RAM
//             for (i = 0; i <= 25'h3FFFFF; i = i + 1) begin
//                 byte_addr = i * 2;
//                 $fdisplay(fd0, "@%06X %04X", byte_addr, dram_inst0.Mem[i][15:0]);
//                 $fdisplay(fd1, "@%06X %04X", byte_addr, dram_inst1.Mem[i][15:0]);
//             end
            
//             // 3. Đóng file
//             $fclose(fd0);
//             $fclose(fd1);
//         end
//         $display("========== DA XUAT DU LIEU CUA CA 2 RAM RA FILE XONG ==========");
//     end

//     // Reset & Boot sequence
//     initial begin
//         // Initialize simulation state
//         reset_n = 0;
//         gpi     = 4'b1100;
//         irq_in  = 32'h0;

//         $display("[%t] Starting unified SoC simulation: UART Monitor, EEPROM, Flash, HyperRAM (DUAL INSTANCES)...", $time);
        
//         // 1. Ép RAM chạy biên dịch timing 100MHz
//         dram_inst0.SPEED100 = 1; 
//         dram_inst1.SPEED100 = 1; 
        
//         // 2. GIỮ RESET CPU VÀ CHỜ CẢ 2 RAM KHỞI ĐỘNG XONG MỚI ĐƯỢC BOOT
//         wait (dram_inst0.PoweredUp == 1 && dram_inst1.PoweredUp == 1);
//         $display("[%t] Both HyperRAMs are Powered Up!", $time);

//         #100000; 
//         @(posedge clk_p); // Đợi sườn lên của clock
//         #1200;            // Lệch đi 1.2ns (Không cho thay đổi trùng với sườn clock)
//         reset_n = 1;
//         $display("[%t] System Reset released. CPUs are booting...", $time);

//         // Wait until CPU hits a trap or halts
//         wait(trap0 || trap1);
//         $display("[%t] Trap detected! Simulation terminated.", $time);
        
//         #50000;
//         $finish;
//     end

// endmodule

// `timescale 1ps / 1ps  // Required resolution for the s27kl0641 HyperRAM model

module Beta_AISoC_Unified_Vendor_tb;
    //---------------------------------------------------------
    // 1. Clock and Reset Signals
    //---------------------------------------------------------
    reg clk_p, clk_n;
    reg reset_n;

    //---------------------------------------------------------
    // 2. SoC Peripheral Connections
    //---------------------------------------------------------
    reg [31:0]  irq_in;
    wire[31:0]  eoi;

    // UART
    wire        uart0_rx, uart0_tx;
    wire        uart1_rx, uart1_tx;

    // SPI (Giả sử NSlave = 1 hoặc 2, khai báo [1:0] cho an toàn)
    wire        spi0_ss_n;
    wire        spi0_clk, spi0_mosi, spi0_miso;
    
    wire        spi1_ss_n;
    wire        spi1_clk, spi1_mosi, spi1_miso;

    // I2C (Use tri for I2C to support multiple devices and pull-ups)
    tri         i2c0_scl, i2c0_sda;
    tri         i2c1_scl, i2c1_sda;

    // HyperRAM 0 (HyperBus)
    wire [7:0]  hyperram0_dq_io;
    wire        hyperram0_rwds_io;
    wire        hyperram0_hclk_p, hyperram0_cs_n, hyperram0_resetn;

    // HyperRAM 1 (HyperBus)
    wire [7:0]  hyperram1_dq_io;
    wire        hyperram1_rwds_io;
    wire        hyperram1_hclk_p, hyperram1_cs_n, hyperram1_resetn;
    
    // GPIO
    wire [3:0]  gpo;
    reg  [3:0]  gpi;
    wire [7:0]  gpio_bus;
    assign gpio_bus = {gpi, 4'bz};

    // TRAP
    wire        trap0, trap1;

    //---------------------------------------------------------
    // I2C Bus Pull-up Resistors (Mandatory for I2C operation)
    //---------------------------------------------------------
    pullup(i2c0_scl);
    pullup(i2c0_sda);
    pullup(i2c1_scl); pullup(i2c1_sda);


    //---------------------------------------------------------
    // 3. SoC Unit Under Test (UUT) Instance
    //---------------------------------------------------------
    Beta_AISoC Beta_AISoC_uut (
        .clk_p(clk_p),
        .clk_n(clk_n),
        .resetn(reset_n),
        
        .trap0(trap0),
        .trap1(trap1),
        // .irq(irq_in),
        // .eoi(eoi),

        // UART 0 & 1
        .uart0_rx(uart0_rx),
        .uart0_tx(uart0_tx),
        .uart1_rx(uart1_rx),
        .uart1_tx(uart1_tx),

        // SPI 0 & 1
        .spi0_clk(spi0_clk),
        .spi0_mosi(spi0_mosi),
        .spi0_miso(spi0_miso),
        .spi0_ss_n(spi0_ss_n),      
        
        .spi1_clk(spi1_clk),
        .spi1_mosi(spi1_mosi),
        .spi1_miso(spi1_miso),
        .spi1_ss_n(spi1_ss_n),

        // I2C 0 & 1
        .i2c0_scl(i2c0_scl),
        .i2c0_sda(i2c0_sda),
        .i2c1_scl(i2c1_scl),
        .i2c1_sda(i2c1_sda),

        // HyperRAM 0 & 1
        .hyperram0_dq_io(hyperram0_dq_io),
        .hyperram0_rwds_io(hyperram0_rwds_io),
        .hyperram0_hclk_p(hyperram0_hclk_p),
        .hyperram0_cs_n(hyperram0_cs_n),
        .hyperram0_resetn(hyperram0_resetn),

        .hyperram1_dq_io(hyperram1_dq_io),
        .hyperram1_rwds_io(hyperram1_rwds_io),
        .hyperram1_hclk_p(hyperram1_hclk_p),
        .hyperram1_cs_n(hyperram1_cs_n),
        .hyperram1_resetn(hyperram1_resetn),

        // GPIO
        .gpio_io(gpio_bus)
    );

    //---------------------------------------------------------
    // 4. Professional IC Models and Emulators (DUPLICATED)
    //---------------------------------------------------------
    
    // ===== UART Monitors =====
    uart_monitor_responder #(
        .BAUD_RATE(115200),
        .CLK_FREQ(200_000_000),
        .TRIGGER_DATA(8'h3F),         // Trigger on '?'
        .MEM_FILE("uart_monitor.mem"), 
        .MEM_DEPTH(64)
    ) uart_mon_inst0 (
        .rx(uart0_tx), 
        .tx(uart0_rx)  
    );

    uart_monitor_responder #(
        .BAUD_RATE(115200),
        .CLK_FREQ(200_000_000),
        .TRIGGER_DATA(8'h3F),         // Trigger on '?'
        .MEM_FILE("uart_monitor.mem"), // Dùng chung hoặc tạo file uart_monitor1.mem
        .MEM_DEPTH(64)
    ) uart_mon_inst1 (
        .rx(uart1_tx), 
        .tx(uart1_rx)  
    );

    // ===== I2C EEPROMs =====
    i2c_eeprom_model #(
        .I2C_ADR(7'h50),             // Default address 0x50
        .MEM_SIZE(256),              // 256 Bytes capacity
        .INIT_FILE("i2c_eeprom.mem") 
    ) eeprom_inst0 (
        .scl(i2c0_scl),
        .sda(i2c0_sda)
    );

    i2c_eeprom_model #(
        .I2C_ADR(7'h50),             // Bus khác nhau nên vẫn có thể giữ địa chỉ 0x50
        .MEM_SIZE(256),              
        .INIT_FILE("i2c_eeprom.mem") // Có thể trỏ tới i2c_eeprom1.mem nếu cần data khác
    ) eeprom_inst1 (
        .scl(i2c1_scl),
        .sda(i2c1_sda)
    );

    // ===== SPI Flash (W25Q128JVxIM) =====
    wire flash0_wp_n = 1'b1;
    wire flash0_hold_n = 1'b1;
    W25Q128JVxIM flash_inst0 (
        .CSn(spi0_ss_n),
        .CLK(spi0_clk),
        .DIO(spi0_mosi),
        .DO(spi0_miso),
        .WPn(flash0_wp_n),
        .HOLDn(flash0_hold_n)
    );

    wire flash1_wp_n = 1'b1;
    wire flash1_hold_n = 1'b1;
    W25Q128JVxIM flash_inst1 (
        .CSn(spi1_ss_n),
        .CLK(spi1_clk),
        .DIO(spi1_mosi),
        .DO(spi1_miso),
        .WPn(flash1_wp_n),
        .HOLDn(flash1_hold_n)
    );

    // ===== HyperRAMs (s27kl0641) =====
    s27kl0641 #(
        .UserPreload(0),
        .mem_file_name("s27kl0641.mem")
    ) dram_inst0 (
        .DQ7(hyperram0_dq_io[7]), .DQ6(hyperram0_dq_io[6]), 
        .DQ5(hyperram0_dq_io[5]), .DQ4(hyperram0_dq_io[4]),
        .DQ3(hyperram0_dq_io[3]), .DQ2(hyperram0_dq_io[2]), 
        .DQ1(hyperram0_dq_io[1]), .DQ0(hyperram0_dq_io[0]),
        .RWDS(hyperram0_rwds_io),
        .CSNeg(hyperram0_cs_n),
        .CK(hyperram0_hclk_p),
        .RESETNeg(hyperram0_resetn)
    );

    s27kl0641 #(
        .UserPreload(0),
        .mem_file_name("s27kl0641.mem") // Hoặc trỏ tới s27kl0641_1.mem nếu cần RAM data khác
    ) dram_inst1 (
        .DQ7(hyperram1_dq_io[7]), .DQ6(hyperram1_dq_io[6]), 
        .DQ5(hyperram1_dq_io[5]), .DQ4(hyperram1_dq_io[4]),
        .DQ3(hyperram1_dq_io[3]), .DQ2(hyperram1_dq_io[2]), 
        .DQ1(hyperram1_dq_io[1]), .DQ0(hyperram1_dq_io[0]),
        .RWDS(hyperram1_rwds_io),
        .CSNeg(hyperram1_cs_n),
        .CK(hyperram1_hclk_p),
        .RESETNeg(hyperram1_resetn)
    );

    //---------------------------------------------------------
    // 5. Clock Generation and Simulation Scenario
    //---------------------------------------------------------
    initial begin
        clk_p = 0;
        clk_n = 1;
        // 200 MHz (5ns period / 5000ps) => Half period = 2500ps
        forever #2500 begin 
            clk_p = ~clk_p;
            clk_n = ~clk_p;
        end
    end

    // Dump RAM data
    initial begin
        // Đợi 500000 chu kỳ xung nhịp clk_p
        repeat (500000) @(posedge clk_p);
        $display("[%t] Dang xuat du lieu RAM ra file doc theo Byte Address...", $time);
        begin : DUMP_RAM_BLOCK
            integer fd0, fd1;
            integer i;
            integer byte_addr;
            
            // 1. Mở file để ghi
            fd0 = $fopen("output_data_s27kl0641_0.mem", "w");
            fd1 = $fopen("output_data_s27kl0641_1.mem", "w");
            
            $fdisplay(fd0, "//# FILE NAY DUNG DE DOC BANG MAT (BYTE ADDRESS) CHO HYPERRAM 0");
            $fdisplay(fd0, "//# @Dia_chi_Byte   Du_lieu(16-bit)");

            $fdisplay(fd1, "//# FILE NAY DUNG DE DOC BANG MAT (BYTE ADDRESS) CHO HYPERRAM 1");
            $fdisplay(fd1, "//# @Dia_chi_Byte   Du_lieu(16-bit)");
            
            // 2. Quét toàn bộ dải địa chỉ của RAM
            for (i = 0; i <= 25'h3FFFFF; i = i + 1) begin
                byte_addr = i * 2;
                $fdisplay(fd0, "@%06X %04X", byte_addr, dram_inst0.Mem[i][15:0]);
                $fdisplay(fd1, "@%06X %04X", byte_addr, dram_inst1.Mem[i][15:0]);
            end
            
            // 3. Đóng file
            $fclose(fd0);
            $fclose(fd1);
        end
        $display("========== DA XUAT DU LIEU CUA CA 2 RAM RA FILE XONG ==========");
    end

    // Reset & Boot sequence
    initial begin
        // Initialize simulation state
        reset_n = 0;
        gpi     = 4'b1100;
        irq_in  = 32'h0;
        $display("[%t] Starting unified SoC simulation: UART Monitor, EEPROM, Flash, HyperRAM (DUAL INSTANCES)...", $time);

        // 1. Ép RAM chạy biên dịch timing 100MHz
        dram_inst0.SPEED100 = 1;
        dram_inst1.SPEED100 = 1; 
        
        // 2. GIỮ RESET CPU VÀ CHỜ CẢ 2 RAM KHỞI ĐỘNG XONG MỚI ĐƯỢC BOOT
        wait (dram_inst0.PoweredUp == 1 && dram_inst1.PoweredUp == 1);
        $display("[%t] Both HyperRAMs are Powered Up!", $time);

        #100000; 
        @(posedge clk_p);
        // Đợi sườn lên của clock
        #1200;
        // Lệch đi 1.2ns (Không cho thay đổi trùng với sườn clock)
        reset_n = 1;
        $display("[%t] System Reset released. CPUs are booting...", $time);

        // Wait until CPU hits a trap or halts
        wait(trap0 || trap1);
        $display("[%t] Trap detected! Simulation terminated.", $time);
        
        #50000;
        $finish;
    end

endmodule