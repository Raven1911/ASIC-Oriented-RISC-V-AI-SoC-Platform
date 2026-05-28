#include "system_init.h"

// Include tất cả các thư viện cần thiết cho việc khởi tạo
#include "soc_hal.h"
#include "UART_Driver.h"


// Định nghĩa các biến toàn cục cho các driver nếu cần (nếu chúng chưa được định nghĩa ở nơi khác)
// I2CDriver_t i2c0;
// UART_Driver_t uart0;

/*
 * Hàm tiện ích để khởi tạo toàn bộ hệ thống
 */
void System_Init_All(void) {
    // 2. Khởi tạo Timer (cần thiết cho các hàm delay)
    System_Init_Timers();

#ifdef HAL_INTERRUPT_MODULE_ENABLED
    IRQ_Init();
#endif
    
    // 3. Khởi tạo GPIO (thường cần thiết trước khi cấu hình các chân chức năng)
    System_Init_GPIO();
    
    // 4. Khởi tạo UART (để có thể in log debug sớm nhất có thể)
    System_Init_UART();
    Uart_println("System initialization started...");
    
    // 5. Khởi tạo các ngoại vi khác (I2C, SPI, OSPI, v.v.)
    System_Init_I2C();
    // System_Init_OSPI();
    // System_Init_HyperRAM();
    System_Init_VideoStreaming();
    System_Init_CNNAccel();
    
    Uart_println("System initialization completed successfully.");
}


void System_Init_Timers(void) {
    // Khởi tạo các timer cơ bản
    timer_init();
}

void System_Init_UART(void) {
    // Khởi tạo UART
    // Ví dụ:
    // Uart_create_default(&uart0, ...);
    Uart_begin(UART_BAUD_RATE);
}

void System_Init_I2C(void) {
    uint32_t i2c_freq = 100000;     // 100 kHz I2C clock
    // I2CDriver_t i2c0;
    I2C_driver_init(&i2c0, I2C_BASE_ADDR);
    I2C_init(&i2c0, SYS_CLK_FREQ, i2c_freq);

}

void System_Init_GPIO(void) {
    // Khởi tạo GPIO driver
    gpio_init();
    
    // Bạn cũng có thể đặt các cấu hình pinMode ban đầu ở đây nếu muốn
    // Ví dụ:
    // pinMode(0, 1); // D0 là output
    // pinMode(4, 0); // D4 là input
}

void System_Init_VideoStreaming(void) {
    VideoStreaming_begin();
    VideoStreaming_load_defaults(&video_streaming);
    VideoStreaming_enable(&video_streaming, false);
    VideoStreaming_set_grant_request(&video_streaming, false);
}

void System_Init_CNNAccel(void) {
#ifdef HAL_CNN_ACCEL_MODULE_ENABLED
    CNN_Accel_begin();
#endif
}
