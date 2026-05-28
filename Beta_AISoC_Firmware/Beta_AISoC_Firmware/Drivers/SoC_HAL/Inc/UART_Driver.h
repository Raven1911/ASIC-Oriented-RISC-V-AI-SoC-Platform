// #ifndef UART_DRIVER_H
// #define UART_DRIVER_H

// #include <stdint.h>
// #include <stddef.h>
// #include "soc_hal.h"

// /* --- Configuration --- */
// #define UART_BASE_ADDR 0x02002000U
// #define UART_BAUD_RATE 115200U

// /* --- Register Word Offsets --- */
// #define UART_RX_STATUS_REG_WORD_OFFSET 0 // [Read] Bit 8: RX_EMPTY, Bits [7:0]: RX Data
// #define UART_TX_STATUS_REG_WORD_OFFSET 1 // [Read] Bit 9: TX_FULL
// #define UART_DVSR_REG_WORD_OFFSET      2 // [Write] Baud rate divisor
// #define UART_TX_REG_WORD_OFFSET        3 // [Write] Transmit Data

// /* --- Bit Definitions --- */
// #define UART_TX_FULL   (1U << 9)   // Bit 9 (10th position)
// #define UART_RX_EMPTY  (1U << 8)   // Bit 8 (9th position)
// #define UART_DATA_MASK 0x000000FFU // 8-bit Data Mask

// /* --- Data Structures --- */
// typedef struct
// {
//     volatile uint32_t *regs;
// } Uart_t;

// extern Uart_t uart_0;

// /* --- High-Level API Prototypes --- */

// void     Uart_begin(uint32_t baud_rate);
// void     Uart_write(uint32_t data);
// uint8_t  Uart_read(uint8_t *data);
// uint32_t Uart_available(void);
// void     Uart_print(const char *str);
// void     Uart_println(const char *str);

// /* --- Low-Level API Prototypes --- */

// void     Uart_create(Uart_t *uart, uint32_t base_hw_addr);
// void     Uart_create_default(Uart_t *uart);
// void     Uart_init_baudrate(Uart_t *uart, uint32_t baud_rate);
// void     Uart_write_byte(Uart_t *uart, uint32_t data);
// uint8_t  Uart_read_byte(Uart_t *uart, uint8_t *data);
// uint32_t Uart_is_tx_full(Uart_t *uart);
// uint32_t Uart_is_rx_empty(Uart_t *uart);
// void     Uart_write_string(Uart_t *uart, const char *str);

// #endif // UART_DRIVER_H


#ifndef UART_DRIVER_H
#define UART_DRIVER_H

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h> // Thêm thư viện bool
#include "soc_hal.h"

/* --- Configuration --- */
#define UART0_BASE_ADDR 0x02002000U
#define UART1_BASE_ADDR 0x02002100U
// #define UART2_BASE_ADDR 0x02002200U
#define UART_BASE_ADDR UART0_BASE_ADDR
#define UART_BAUD_RATE 230400U

/* --- Register Word Offsets --- */
#define UART_RX_STATUS_REG_WORD_OFFSET 0 // [Read] Bit 8: RX_EMPTY, Bits [7:0]: RX Data
#define UART_TX_STATUS_REG_WORD_OFFSET 1 // [Read] Bit 9: TX_FULL
#define UART_DVSR_REG_WORD_OFFSET      2 // [Write] Baud rate divisor
#define UART_TX_REG_WORD_OFFSET        3 // [Write] Transmit Data

/* --- Bit Definitions --- */
#define UART_TX_FULL   (1U << 9)   // Bit 9 (10th position)
#define UART_RX_EMPTY  (1U << 8)   // Bit 8 (9th position)
#define UART_DATA_MASK 0x000000FFU // 8-bit Data Mask

/* --- Data Structures --- */
typedef struct
{
    volatile uint32_t *regs;
} Uart_t;

extern Uart_t uart_0;
extern Uart_t uart_1;
// extern Uart_t uart_2;

/* --- High-Level API Prototypes --- */

void     Uart_begin(uint32_t baud_rate);
void     Uart_end(void);
void     Uart_write(uint8_t data);        // Đổi thành uint8_t
bool     Uart_read(uint8_t *data);        // Trả về bool (true nếu có data)
bool     Uart_available(void);            // Trả về bool
void     Uart_print(const char *str);
void     Uart_println(const char *str);

/* --- Low-Level API Prototypes --- */

void     Uart_create(Uart_t *uart, uint32_t base_hw_addr);
void     Uart_create_default(Uart_t *uart);
void     Uart_init_baudrate(Uart_t *uart, uint32_t baud_rate);
void     Uart_write_byte(Uart_t *uart, uint8_t data); // Đổi thành uint8_t
bool     Uart_read_byte(Uart_t *uart, uint8_t *data); // Trả về bool
bool     Uart_is_tx_full(Uart_t *uart);               // Trả về bool
bool     Uart_is_rx_empty(Uart_t *uart);              // Trả về bool
void     Uart_write_string(Uart_t *uart, const char *str);

#endif // UART_DRIVER_H
