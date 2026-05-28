#ifndef OSPI_DRIVER_H
#define OSPI_DRIVER_H

#include <soc_hal.h>
#include <stdint.h>
#include <stdbool.h>

// CA bit structure:
// bit47: 1=read, 0=write
// bit46: Address space: 0=memory, 1=register
// bit45: Burst type: 0=wrap, 1=linear
// bit44-16:Row & Upper Column Address (24 bits): A31-A3
// bit15-3: reverse for future use
// bit2-0: Lower Column Address A2-A0. identify exactly word (half-page 16bit) that starts the transaction.

// Example: CA = 0x0000800000000024 means:
// - bit47=1: read operation
// - bit46=0: memory space
// - bit45=0: wrap burst
// - bit44-16=0x000000: Row & Upper Column Address = 0x000000
// - bit2-0=0b100: Lower Column Address = 0x4 

// in file mem address @00000000 in line 0 each line address is increament. So address 0x0000004 is the line 4th. 
// if the burst length is 16 (half-page), the transaction will read 16 half-words (32 bytes) starting from address 0x0000004, 
// which covers lines 4 to 15 and 0 to 3 (since wrap burst is used) in the memory.
// each byte in line will read when the edge of RWDS is detected, both rise and fall edge (DDR). 
// So in one cycle of RWDS, 2 bytes (1 half-word) will be read. For burst length of 16 half-words, it will take 16 cycles of RWDS to complete the transaction.

// Mặc định địa chỉ Base của Module theo phần cứng
#define OSPI_BASE_ADDR 0x02005000U

typedef struct {
    volatile uint32_t *reg_cmd_upper; // 0x00: cmd_addr[47:32] (16 bits)
    volatile uint32_t *reg_cmd_lower; // 0x04: cmd_addr[31:0]
    volatile uint32_t *reg_config;    // 0x08: capture_shmoo/recovery/latency/burst_len
    volatile uint32_t *reg_control;   // 0x0C: start/rd/wr/wdata
    volatile uint32_t *reg_status;    // 0x10: start_rdy/empty/full/rdata
} OSPI_Driver_t;

// ========================================================
// REGISTER 2 (0x0200_5008) - CONFIG REGISTER (MỚI)
// ========================================================
// [7:0]   : burst_len      (8 bit)   ← ĐÃ MỞ RỘNG
// [11:8]  : latency        (4 bit)
// [15:12] : recovery       (4 bit)
// [17:16] : capture_shmoo  (2 bit)

// Khai báo biến toàn cục
extern OSPI_Driver_t ospi;

// Các nguyên mẫu hàm
void OSPI_init(OSPI_Driver_t *drv, uint32_t base_addr);
void OSPI_set_cmd_addr(OSPI_Driver_t *drv, uint32_t cmd_addr_lower, uint16_t cmd_addr_upper);
void OSPI_set_config(OSPI_Driver_t *drv, uint8_t capture_shmoo, uint8_t recovery, uint8_t latency, uint8_t burst_len);
void OSPI_start(OSPI_Driver_t *drv);
void OSPI_write_byte(OSPI_Driver_t *drv, uint8_t data);
uint8_t OSPI_read_byte_idle(OSPI_Driver_t *drv);
uint8_t OSPI_read_byte(OSPI_Driver_t *drv);
bool OSPI_is_start_ready(OSPI_Driver_t *drv);
bool OSPI_is_full(OSPI_Driver_t *drv);
bool OSPI_is_empty(OSPI_Driver_t *drv);
void OSPI_reset(OSPI_Driver_t *drv);
void OSPI_burst_write(OSPI_Driver_t *drv, const uint8_t *data, uint32_t size);
void OSPI_burst_read(OSPI_Driver_t *drv, uint8_t *data, uint32_t size);


#endif // OSPI_DRIVER_H