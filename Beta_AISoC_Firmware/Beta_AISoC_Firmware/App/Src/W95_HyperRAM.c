#include "W95_HyperRAM.h"

void W95_Init(W95_HandleTypeDef *hw95, HyperRAM_Driver_t *port, uint8_t lat, uint8_t rec, uint8_t cap_shmoo) {
    hw95->hram_port = port;
    hw95->latency = lat;
    hw95->recovery = rec;
    hw95->capture_shmoo = cap_shmoo;
}

bool W95_SetMemoryCommandAddress(HyperRAM_Driver_t *port, uint32_t byte_addr, uint16_t cmd_upper) {
    uint32_t word_addr;
    uint16_t ca_upper;
    uint32_t ca_lower;

    if ((port == 0) || ((byte_addr & 1U) != 0U)) {
        return false;
    }

    word_addr = byte_addr >> 1U;

    /*
     * W957A8MFYA5I memory access is addressed in 16-bit words. The HyperBus
     * CA packet carries word_addr[31:3] in CA[44:16] and word_addr[2:0] in
     * CA[2:0]; CA[15:3] must stay zero.
     */
    ca_upper = (uint16_t)((cmd_upper & 0xE000U) |
                          ((word_addr >> 19U) & 0x1FFFU));
    ca_lower = (((word_addr >> 3U) & 0xFFFFU) << 16) |
               (word_addr & 0x7U);

    HyperRAM_set_cmd_addr(port, ca_lower, ca_upper);
    return true;
}

void W95_MemoryWrite(W95_HandleTypeDef *hw95, uint32_t addr, const uint8_t *data, uint32_t size_bytes, bool is_linear) {
    // 1. Cập nhật thanh ghi Config cho Burst Length (Tính theo Half-Word = size/2)
    HyperRAM_set_config(hw95->hram_port, hw95->capture_shmoo, hw95->recovery, hw95->latency, (size_bytes / 2));

    // 2. Định nghĩa mã lệnh DDP/SDP của Winbond
    uint16_t cmd_upper = is_linear ? W95_CMD_MEM_WRITE_LINEAR : W95_CMD_MEM_WRITE_WRAP;

    // 3. Thực thi Transaction qua lõi SoC
    while (!HyperRAM_is_start_ready(hw95->hram_port));
    if (!W95_SetMemoryCommandAddress(hw95->hram_port, addr, cmd_upper)) {
        return;
    }
    HyperRAM_burst_write(hw95->hram_port, data, size_bytes);
    HyperRAM_start(hw95->hram_port);
}

void W95_MemoryRead(W95_HandleTypeDef *hw95, uint32_t addr, uint8_t *data, uint32_t size_bytes, bool is_linear) {
    HyperRAM_set_config(hw95->hram_port, hw95->capture_shmoo, hw95->recovery, hw95->latency, (size_bytes / 2));

    uint16_t cmd_upper = is_linear ? W95_CMD_MEM_READ_LINEAR : W95_CMD_MEM_READ_WRAP;

    while (!HyperRAM_is_start_ready(hw95->hram_port));
    if (!W95_SetMemoryCommandAddress(hw95->hram_port, addr, cmd_upper)) {
        return;
    }
    HyperRAM_start(hw95->hram_port);
    HyperRAM_burst_read(hw95->hram_port, data, size_bytes);
}
