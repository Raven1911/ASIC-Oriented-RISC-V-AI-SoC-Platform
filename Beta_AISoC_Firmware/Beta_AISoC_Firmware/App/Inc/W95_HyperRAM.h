#ifndef W95_HYPERRAM_H
#define W95_HYPERRAM_H

#include "HyperRAM_Driver.h"

// Winbond HyperBus Command/Address Bit Assignments
#define W95_CMD_MEM_WRITE_LINEAR 0x2000
#define W95_CMD_MEM_READ_LINEAR  0xA000
#define W95_CMD_MEM_WRITE_WRAP   0x0000
#define W95_CMD_MEM_READ_WRAP    0x8000

#define W95_CMD_REG_WRITE        0x6000
#define W95_CMD_REG_READ         0xE000

// Struct lưu trạng thái cấu hình của riêng từng chip Winbond
typedef struct {
    HyperRAM_Driver_t *hram_port; // Con trỏ trỏ tới cổng HyperRAM đang gắn chip này
    uint8_t latency;
    uint8_t recovery;
    uint8_t capture_shmoo;
} W95_HandleTypeDef;

// API dành riêng cho chip Winbond W95
void W95_Init(W95_HandleTypeDef *hw95, HyperRAM_Driver_t *port, uint8_t lat, uint8_t rec, uint8_t cap_shmoo);
bool W95_SetMemoryCommandAddress(HyperRAM_Driver_t *port, uint32_t byte_addr, uint16_t cmd_upper);
void W95_MemoryWrite(W95_HandleTypeDef *hw95, uint32_t addr, const uint8_t *data, uint32_t size_bytes, bool is_linear);
void W95_MemoryRead(W95_HandleTypeDef *hw95, uint32_t addr, uint8_t *data, uint32_t size_bytes, bool is_linear);

#endif // W95_HYPERRAM_H
