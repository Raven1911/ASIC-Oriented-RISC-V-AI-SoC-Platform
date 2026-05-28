#include "../Inc/HyperRAM_Driver.h"

#ifdef HAL_HYPERRAM_MODULE_ENABLED

HyperRAM_Driver_t hyperram0;
HyperRAM_Driver_t hyperram1;

static void HyperRAM_delay(volatile int cycles) {
    while (cycles--) {
        __asm__ volatile("nop"); 
    }
}

void HyperRAM_init(HyperRAM_Driver_t *drv, uint32_t base_addr) {
    drv->reg_cmd_upper = (volatile uint32_t *)(base_addr + 0x00U);
    drv->reg_cmd_lower = (volatile uint32_t *)(base_addr + 0x04U);
    drv->reg_config    = (volatile uint32_t *)(base_addr + 0x08U);
    drv->reg_control   = (volatile uint32_t *)(base_addr + 0x0CU);
    drv->reg_status    = (volatile uint32_t *)(base_addr + 0x10U);
    drv->reg_mode      = (volatile uint32_t *)(base_addr + 0x14U);
}

void HyperRAM_set_cmd_addr(HyperRAM_Driver_t *drv, uint32_t cmd_addr_lower, uint16_t cmd_addr_upper) {
    *drv->reg_cmd_upper = (uint32_t)(cmd_addr_upper & 0xFFFFU);
    *drv->reg_cmd_lower = cmd_addr_lower;
}

void HyperRAM_set_config(HyperRAM_Driver_t *drv, uint8_t capture_shmoo, uint8_t recovery, uint8_t latency, uint8_t burst_len) {
    uint32_t config_val = ((uint32_t)(capture_shmoo & 0x3U) << 16) |
                          ((uint32_t)(recovery      & 0xFU) << 12) |
                          ((uint32_t)(latency       & 0xFU) <<  8) |
                          ((uint32_t)(burst_len     & 0xFFU) <<  0);   
    *drv->reg_config = config_val;
}

void HyperRAM_write_mode_register(HyperRAM_Driver_t *drv, uint32_t mode_config) {
    *drv->reg_mode = mode_config;
}

uint32_t HyperRAM_read_mode_register(HyperRAM_Driver_t *drv) {
    return *drv->reg_mode;
}

void HyperRAM_set_accel_mode(HyperRAM_Driver_t *drv, bool enable) {
    uint32_t mode_config = *drv->reg_mode;

    if (enable) {
        mode_config |= HYPERRAM_MODE_ACCEL_Msk;
    } else {
        mode_config &= ~HYPERRAM_MODE_ACCEL_Msk;
    }

    *drv->reg_mode = mode_config;
}

bool HyperRAM_is_accel_mode(HyperRAM_Driver_t *drv) {
    return (*drv->reg_mode & HYPERRAM_MODE_ACCEL_Msk) != 0U;
}

void HyperRAM_set_dmac_weights(HyperRAM_Driver_t *drv, uint16_t write_weight, uint16_t read_weight) {
    uint32_t mode_config = *drv->reg_mode;

    mode_config &= ~(HYPERRAM_DMAC_WRITE_WEIGHT_Msk | HYPERRAM_DMAC_READ_WEIGHT_Msk);
    mode_config |= ((uint32_t)(write_weight & 0x7FFFU) << HYPERRAM_DMAC_WRITE_WEIGHT_Pos);
    mode_config |= ((uint32_t)(read_weight  & 0x7FFFU) << HYPERRAM_DMAC_READ_WEIGHT_Pos);

    *drv->reg_mode = mode_config;
}

void HyperRAM_start(HyperRAM_Driver_t *drv) {
    if (HyperRAM_is_start_ready(drv)) {
        uint32_t control = *drv->reg_control;
        control |= (1U << 10);  
        *drv->reg_control = control;
        HyperRAM_delay(1);         
        control &= 0xFBFF;
        *drv->reg_control = control;
    }
}

void HyperRAM_write_byte(HyperRAM_Driver_t *drv, uint8_t data) {
    uint32_t control = *drv->reg_control;
    control &= ~0x1FFU;         
    control |= (1U << 8) | ((uint32_t)data & 0xFFU);  
    *drv->reg_control = control;
    HyperRAM_delay(1);
    control &= 0xFEFF;
    *drv->reg_control = control;
}

uint8_t HyperRAM_read_byte(HyperRAM_Driver_t *drv) {
    uint32_t status = *drv->reg_status;
    uint8_t data = (uint8_t)(status & 0xFFU);
    *drv->reg_control |= (1U << 9);       
    HyperRAM_delay(1);
    *drv->reg_control &= 0xFDFF;
    // HyperRAM_delay(1);
    return data;
}

bool HyperRAM_is_start_ready(HyperRAM_Driver_t *drv) {
    return (*drv->reg_status & (1U << 10)) != 0;
}

bool HyperRAM_is_full(HyperRAM_Driver_t *drv) {
    return (*drv->reg_status & (1U << 8)) != 0;
}

bool HyperRAM_is_empty(HyperRAM_Driver_t *drv) {
    return (*drv->reg_status & (1U << 9)) != 0;
}

void HyperRAM_burst_write(HyperRAM_Driver_t *drv, const uint8_t *data, uint32_t size) {
    for (uint32_t i = 0; i < size; ++i) {
        while (HyperRAM_is_full(drv)) {}  
        HyperRAM_write_byte(drv, data[i]);
    }
}

void HyperRAM_burst_read(HyperRAM_Driver_t *drv, uint8_t *data, uint32_t size) {
    for (uint32_t i = 0; i < size; ++i) {
        while (HyperRAM_is_empty(drv)) {} 
        data[i] = HyperRAM_read_byte(drv);
    }
}



#endif // HAL_HYPERRAM_MODULE_ENABLED
