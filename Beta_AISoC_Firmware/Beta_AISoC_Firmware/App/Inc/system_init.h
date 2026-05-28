#ifndef SYSTEM_INIT_H
#define SYSTEM_INIT_H

#include <stdint.h>
#include <stdbool.h>


/*
 * Khởi tạo toàn bộ hệ thống (Clock, Timer, UART, I2C, v.v.)
 * Gọi hàm này đầu tiên trong hàm main()
 */
void System_Init_All(void);

/*
 * Các hàm khởi tạo riêng lẻ (Tùy chọn: bạn có thể gọi từng hàm này
 * nếu muốn kiểm soát thứ tự khởi tạo chi tiết hơn trong main)
 */
void System_Init_Clocks(void);
void System_Init_Timers(void);
void System_Init_UART(void);
void System_Init_I2C(void);
void System_Init_GPIO(void);
void System_Init_VideoStreaming(void);
void System_Init_CNNAccel(void);


// Thêm các hàm khởi tạo khác nếu cần (vd: OSPI, HyperRAM)

// Xuất các biến toàn cục nếu cần thiết (ví dụ: các biến I2CDriver_t, UART_Driver_t...)
// extern I2CDriver_t i2c0;
// extern UART_Driver_t uart0;

#endif // SYSTEM_INIT_H
