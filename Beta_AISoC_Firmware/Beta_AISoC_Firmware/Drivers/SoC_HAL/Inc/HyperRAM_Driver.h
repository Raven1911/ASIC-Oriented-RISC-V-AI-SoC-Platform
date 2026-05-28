#ifndef HYPERRAM_DRIVER_H
#define HYPERRAM_DRIVER_H

#include <soc_hal.h>
#include <stdint.h>
#include <stdbool.h>

// Định nghĩa phần cứng cố định cho SoC của bạn
#define HYPERRAM_0_BASE_ADDR 0x02005000U
#define HYPERRAM_1_BASE_ADDR 0x02005100U

#define HYPERRAM_MODE_ACCEL_Pos          0U
#define HYPERRAM_MODE_ACCEL_Msk          (0x1U << HYPERRAM_MODE_ACCEL_Pos)
#define HYPERRAM_DMAC_WRITE_WEIGHT_Pos   2U
#define HYPERRAM_DMAC_WRITE_WEIGHT_Msk   (0x7FFFU << HYPERRAM_DMAC_WRITE_WEIGHT_Pos)
#define HYPERRAM_DMAC_READ_WEIGHT_Pos    17U
#define HYPERRAM_DMAC_READ_WEIGHT_Msk    (0x7FFFU << HYPERRAM_DMAC_READ_WEIGHT_Pos)

typedef struct {
    volatile uint32_t *reg_cmd_upper;
    volatile uint32_t *reg_cmd_lower;
    volatile uint32_t *reg_config;
    volatile uint32_t *reg_control;
    volatile uint32_t *reg_status;
    volatile uint32_t *reg_mode;
} HyperRAM_Driver_t;

extern HyperRAM_Driver_t hyperram0;
extern HyperRAM_Driver_t hyperram1;

// Các API cấu hình và giao tiếp lõi
void HyperRAM_init(HyperRAM_Driver_t *drv, uint32_t base_addr);
void HyperRAM_set_cmd_addr(HyperRAM_Driver_t *drv, uint32_t cmd_addr_lower, uint16_t cmd_addr_upper);
void HyperRAM_set_config(HyperRAM_Driver_t *drv, uint8_t capture_shmoo, uint8_t recovery, uint8_t latency, uint8_t burst_len);
void HyperRAM_write_mode_register(HyperRAM_Driver_t *drv, uint32_t mode_config);
uint32_t HyperRAM_read_mode_register(HyperRAM_Driver_t *drv);
void HyperRAM_set_accel_mode(HyperRAM_Driver_t *drv, bool enable);
bool HyperRAM_is_accel_mode(HyperRAM_Driver_t *drv);
void HyperRAM_set_dmac_weights(HyperRAM_Driver_t *drv, uint16_t write_weight, uint16_t read_weight);
void HyperRAM_start(HyperRAM_Driver_t *drv);
void HyperRAM_write_byte(HyperRAM_Driver_t *drv, uint8_t data);
uint8_t HyperRAM_read_byte(HyperRAM_Driver_t *drv);
bool HyperRAM_is_start_ready(HyperRAM_Driver_t *drv);
bool HyperRAM_is_full(HyperRAM_Driver_t *drv);
bool HyperRAM_is_empty(HyperRAM_Driver_t *drv);
void HyperRAM_burst_write(HyperRAM_Driver_t *drv, const uint8_t *data, uint32_t size);
void HyperRAM_burst_read(HyperRAM_Driver_t *drv, uint8_t *data, uint32_t size);

#endif // HYPERRAM_DRIVER_H
