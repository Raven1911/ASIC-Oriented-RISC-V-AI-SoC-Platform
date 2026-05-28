#include "OSPI_Driver.h"
#ifdef HAL_OSPI_MODULE_ENABLED

// Định nghĩa biến toàn cục
OSPI_Driver_t ospi;

// Hàm tạo trễ an toàn, ngăn trình biên dịch tối ưu hóa xóa bỏ vòng lặp
static void OSPI_delay(volatile int cycles) {
    while (cycles--) {
        __asm__ volatile("nop"); // Yêu cầu CPU chờ (tương thích ARM/RISC-V)
    }
}

void OSPI_init(OSPI_Driver_t *drv, uint32_t base_addr) {
    drv->reg_cmd_upper = (volatile uint32_t *)(base_addr + 0x00U);
    drv->reg_cmd_lower = (volatile uint32_t *)(base_addr + 0x04U);
    drv->reg_config    = (volatile uint32_t *)(base_addr + 0x08U);
    drv->reg_control   = (volatile uint32_t *)(base_addr + 0x0CU);
    drv->reg_status    = (volatile uint32_t *)(base_addr + 0x10U);
}

void OSPI_set_cmd_addr(OSPI_Driver_t *drv, uint32_t cmd_addr_lower, uint16_t cmd_addr_upper) {
    *drv->reg_cmd_upper = (uint32_t)(cmd_addr_upper & 0xFFFFU);
    *drv->reg_cmd_lower = cmd_addr_lower;
}

void OSPI_set_config(OSPI_Driver_t *drv, uint8_t capture_shmoo, uint8_t recovery, uint8_t latency, uint8_t burst_len) {
    // uint32_t config_val = ((uint32_t)(capture_shmoo & 0x3U) << 13) |
    //                       ((uint32_t)(recovery & 0xFU) << 9) |
    //                       ((uint32_t)(latency & 0xFU) << 5) |
    //                       ((uint32_t)(burst_len & 0x1FU));

    uint32_t config_val = ((uint32_t)(capture_shmoo & 0x3U) << 16) |
                          ((uint32_t)(recovery      & 0xFU) << 12) |
                          ((uint32_t)(latency       & 0xFU) <<  8) |
                          ((uint32_t)(burst_len     & 0xFFU) <<  0);   // ← 0xFFU thay vì 0x1FU

    *drv->reg_config = config_val;
}

void OSPI_start(OSPI_Driver_t *drv) {
    if (OSPI_is_start_ready(drv)) {
        uint32_t control = *drv->reg_control;
        control |= (1U << 10);  // Đặt start bit [10] lên 1
        *drv->reg_control = control;
        
        OSPI_delay(10);         // Trễ khoảng 1-2 chu kỳ xung nhịp
        
        // control &= ~(1U << 10); // Xóa start bit [10] về 0
        control &= 0xFBFF;
        *drv->reg_control = control;
    }
}

void OSPI_write_byte(OSPI_Driver_t *drv, uint8_t data) {
    uint32_t control = *drv->reg_control;
    control &= ~0x1FFU;         // Xóa dải bit [8:0] (wr và wdata)
    control |= (1U << 8) | ((uint32_t)data & 0xFFU);  // Set wr[8]=1 và wdata[7:0]
    *drv->reg_control = control;
    
    OSPI_delay(2);
    
    // control &= ~(1U << 8);      // Xóa wr[8] về 0
    control &= 0xFEFF;
    *drv->reg_control = control;
}

uint8_t OSPI_read_byte_idle(OSPI_Driver_t *drv) {
    uint32_t status = *drv->reg_status;
    return (uint8_t)(status & 0xFFU);
}

// uint8_t OSPI_read_byte(OSPI_Driver_t *drv) {

//     uint32_t control = *drv->reg_control;
//     control |= (1U << 9);       // Set rd bit [9]=1
//     *drv->reg_control = control;
    
//     OSPI_delay(2);
    
//     uint32_t status = *drv->reg_status;
//     uint8_t data = (uint8_t)(status & 0xFFU);
    
//     control &= ~(1U << 9);      // Xóa rd bit [9]=0
//     *drv->reg_control = control;
//     return data;
// }



uint8_t OSPI_read_byte(OSPI_Driver_t *drv) {
    // 1. Đọc dữ liệu HIỆN TẠI đang nằm sẵn ở cửa FIFO
    uint32_t status = *drv->reg_status;
    uint8_t data = (uint8_t)(status & 0xFFU);
    
    // 2. Kích hoạt chân rd (pop) để FIFO đẩy byte tiếp theo lên
    *drv->reg_control |= (1U << 9);       
    OSPI_delay(10);
    
    // 3. Xóa chân rd về 0
    // *drv->reg_control = 0;      
    *drv->reg_control &= 0xFDFF;
    // Trả về dữ liệu đã đọc ở bước 1
    OSPI_delay(10);
    
    return data;
}

bool OSPI_is_start_ready(OSPI_Driver_t *drv) {
    uint32_t status = *drv->reg_status;
    return (status & (1U << 10)) != 0;
}

bool OSPI_is_full(OSPI_Driver_t *drv) {
    uint32_t status = *drv->reg_status;
    return (status & (1U << 8)) != 0;
}

bool OSPI_is_empty(OSPI_Driver_t *drv) {
    uint32_t status = *drv->reg_status;
    return (status & (1U << 9)) != 0;
}

void OSPI_reset(OSPI_Driver_t *drv) {
    *drv->reg_cmd_upper = 0;
    *drv->reg_cmd_lower = 0;
    *drv->reg_config    = 0;
    *drv->reg_control   = 0;
}

void OSPI_burst_write(OSPI_Driver_t *drv, const uint8_t *data, uint32_t size) {
    for (uint32_t i = 0; i < size; ++i) {
        while (OSPI_is_full(drv)) {}  // Đợi đến khi FIFO Write hết đầy
        OSPI_write_byte(drv, data[i]);
    }
}

void OSPI_burst_read(OSPI_Driver_t *drv, uint8_t *data, uint32_t size) {
    for (uint32_t i = 0; i < size; ++i) {
        while (OSPI_is_empty(drv)) {} // Đợi đến khi có dữ liệu vào FIFO Read
        data[i] = OSPI_read_byte(drv);
    }
}

// void OSPI_burst_read(OSPI_Driver_t *drv, uint32_t *data, uint32_t size) {
//     for (uint32_t i = 0; i < size; ++i) {
//         // 1. Chờ đến khi có dữ liệu vào FIFO Read
//         while (OSPI_is_empty(drv)) {} 
        
//         // 2. LẤY DỮ LIỆU ĐANG NẰM SẴN Ở CỬA FIFO
//         data[i] = (uint8_t)(*drv->reg_status & 0xFFU);
        
//         // 3. POP: Kích hoạt chân rd để FIFO đẩy byte tiếp theo lên
//         *drv->reg_control = (1U << 9);
//         OSPI_delay(10);
//         *drv->reg_control = 0;
//     }
// }

#endif // HAL_OSPI_MODULE_ENABLED