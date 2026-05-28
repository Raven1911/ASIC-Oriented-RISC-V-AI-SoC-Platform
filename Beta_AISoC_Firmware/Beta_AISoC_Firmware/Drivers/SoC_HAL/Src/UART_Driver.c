// #include "../Inc/UART_Driver.h"

// #ifdef HAL_UART_MODULE_ENABLED

// #define UART_DVSR_MASK 0x000007FFU

// Uart_t uart_0;

// /* ========================================================================= */
// /* INTERNAL HELPERS                                */
// /* ========================================================================= */

// static uint32_t uart_is_valid(Uart_t *uart)
// {
//     return (uart != NULL) && (uart->regs != NULL) ? 1U : 0U;
// }

// static void write_reg(Uart_t *uart, uint32_t word_offset, uint32_t value)
// {
//     if (uart_is_valid(uart))
//     {
//         uart->regs[word_offset] = value;
//     }
// }

// static uint32_t read_reg(Uart_t *uart, uint32_t word_offset)
// {
//     if (uart_is_valid(uart))
//     {
//         return uart->regs[word_offset];
//     }
//     return 0xFFFFFFFFU;
// }

// static uint32_t read_rx_status(Uart_t *uart) 
// {
//     return read_reg(uart, UART_RX_STATUS_REG_WORD_OFFSET);
// }

// static uint32_t read_tx_status(Uart_t *uart) 
// {
//     return read_reg(uart, UART_TX_STATUS_REG_WORD_OFFSET);
// }

// /* ========================================================================= */
// /* LOW-LEVEL FUNCTIONS                             */
// /* ========================================================================= */

// void Uart_create(Uart_t *uart, uint32_t base_hw_addr)
// {
//     if (uart != NULL)
//     {
//         uart->regs = (volatile uint32_t *)base_hw_addr;
//     }
// }

// void Uart_create_default(Uart_t *uart)
// {
//     Uart_create(uart, UART_BASE_ADDR);
// }

// void Uart_init_baudrate(Uart_t *uart, uint32_t baud_rate)
// {
//     uint32_t term;
//     uint32_t dvsr = 0U;

//     if (!uart_is_valid(uart) || (baud_rate == 0U) || (SYS_CLK_FREQ == 0U))
//     {
//         return;
//     }

//     term = SYS_CLK_FREQ / (16U * baud_rate);
//     if (term > 0U)
//     {
//         dvsr = term - 1U;
//     }

//     write_reg(uart, UART_DVSR_REG_WORD_OFFSET, dvsr & UART_DVSR_MASK);
// }

// uint32_t Uart_is_tx_full(Uart_t *uart)
// {
//     if (!uart_is_valid(uart)) return 1U; // Assume full if invalid to prevent hanging
    
//     // Check if TX_FULL bit is 1
//     return ((read_tx_status(uart) & UART_TX_FULL) != 0U) ? 1U : 0U;
// }

// uint32_t Uart_is_rx_empty(Uart_t *uart)
// {
//     if (!uart_is_valid(uart)) return 1U; // Assume empty if invalid
    
//     // Check if RX_EMPTY bit is 1
//     return ((read_rx_status(uart) & UART_RX_EMPTY) != 0U) ? 1U : 0U;
// }

// void Uart_write_byte(Uart_t *uart, uint32_t data)
// {
//     if (!uart_is_valid(uart)) return;

//     // Wait blocking while TX FIFO is full
//     while (Uart_is_tx_full(uart))
//     {
//         // CPU waits here, no NOPs needed if hardware ready works properly
//     }

//     write_reg(uart, UART_TX_REG_WORD_OFFSET, data & UART_DATA_MASK);
// }

// uint8_t Uart_read_byte(Uart_t *uart, uint8_t *data)
// {
//     uint32_t status;

//     if (!uart_is_valid(uart) || data == NULL) return 0; // 0: Không thành công

//     // Đọc phần cứng đúng 1 lần duy nhất để lấy cả Data lẫn Cờ
//     status = read_rx_status(uart);
    
//     // Kiểm tra cờ RX_EMPTY (Bit 8). Nếu khác 0 tức là FIFO rỗng
//     if ((status & UART_RX_EMPTY) != 0U)
//     {
//         return 0; // Trả về 0 (False) báo hiệu chưa có data
//     }

//     // Nếu có data, tách lấy 8 bit và lưu vào con trỏ
//     *data = (uint8_t)(status & UART_DATA_MASK);
//     return 1; // Trả về 1 (True) báo hiệu đã đọc được dữ liệu hợp lệ
// }

// void Uart_write_string(Uart_t *uart, const char *str)
// {
//     if (!uart_is_valid(uart) || (str == NULL)) return;

//     while (*str != '\0')
//     {
//         Uart_write_byte(uart, (uint32_t)(*str));
//         str++;
//     }
// }

// /* ========================================================================= */
// /* HIGH-LEVEL (ARDUINO-STYLE)                      */
// /* ========================================================================= */

// void Uart_begin(uint32_t baud_rate)
// {
//     Uart_create_default(&uart_0);
//     Uart_init_baudrate(&uart_0, baud_rate);
// }

// void Uart_write(uint32_t data)
// {
//     Uart_write_byte(&uart_0, data);
// }

// uint8_t Uart_read(uint8_t *data)
// {
//     return Uart_read_byte(&uart_0, data);
// }
// uint32_t Uart_available(void)
// {
//     return (Uart_is_rx_empty(&uart_0) == 0U) ? 1U : 0U;
// }

// void Uart_print(const char *str)
// {
//     Uart_write_string(&uart_0, str);
// }

// void Uart_println(const char *str)
// {
//     if (str == NULL) return;

//     Uart_write_string(&uart_0, str);
//     Uart_write_byte(&uart_0, (uint32_t)'\n');
//     // Uart_write_byte(&uart_0, (uint32_t)'\r'); 
// }

// #endif // HAL_UART_MODULE_ENABLED


#include "../Inc/UART_Driver.h"

#ifdef HAL_UART_MODULE_ENABLED

#define UART_DVSR_MASK 0x000007FFU

Uart_t uart_0;
Uart_t uart_1;
// Uart_t uart_2;

/* ========================================================================= */
/* INTERNAL HELPERS                                                          */
/* ========================================================================= */

static bool uart_is_valid(Uart_t *uart)
{
    return (uart != NULL) && (uart->regs != NULL);
}

// Giữ uint32_t cho word_offset và value để ghi/đọc chuẩn 32-bit qua AXI-Lite
static void write_reg(Uart_t *uart, uint32_t word_offset, uint32_t value)
{
    if (uart_is_valid(uart))
    {
        uart->regs[word_offset] = value;
    }
}

static uint32_t read_reg(Uart_t *uart, uint32_t word_offset)
{
    if (uart_is_valid(uart))
    {
        return uart->regs[word_offset];
    }
    return 0xFFFFFFFFU;
}

static uint32_t read_rx_status(Uart_t *uart) 
{
    return read_reg(uart, UART_RX_STATUS_REG_WORD_OFFSET);
}

static uint32_t read_tx_status(Uart_t *uart) 
{
    return read_reg(uart, UART_TX_STATUS_REG_WORD_OFFSET);
}

/* ========================================================================= */
/* LOW-LEVEL FUNCTIONS                                                       */
/* ========================================================================= */

void Uart_create(Uart_t *uart, uint32_t base_hw_addr)
{
    if (uart != NULL)
    {
        uart->regs = (volatile uint32_t *)base_hw_addr;
    }
}

void Uart_create_default(Uart_t *uart)
{
    Uart_create(uart, UART_BASE_ADDR);
}

void Uart_init_baudrate(Uart_t *uart, uint32_t baud_rate)
{
    uint32_t term;
    uint32_t dvsr = 0U;

    if (!uart_is_valid(uart) || (baud_rate == 0U) || (SYS_CLK_FREQ == 0U))
    {
        return;
    }

    term = SYS_CLK_FREQ / (16U * baud_rate);
    if (term > 0U)
    {
        dvsr = term - 1U;
    }

    write_reg(uart, UART_DVSR_REG_WORD_OFFSET, dvsr & UART_DVSR_MASK);
}

bool Uart_is_tx_full(Uart_t *uart)
{
    if (!uart_is_valid(uart)) return true; // Trả về true nếu con trỏ lỗi để chống treo
    
    // Check nếu bit TX_FULL là 1
    return ((read_tx_status(uart) & UART_TX_FULL) != 0U);
}

bool Uart_is_rx_empty(Uart_t *uart)
{
    if (!uart_is_valid(uart)) return true; // Trả về true nếu con trỏ lỗi
    
    // Check nếu bit RX_EMPTY là 1
    return ((read_rx_status(uart) & UART_RX_EMPTY) != 0U);
}

void Uart_write_byte(Uart_t *uart, uint8_t data)
{
    if (!uart_is_valid(uart)) return;

    // Chờ đến khi TX FIFO không còn đầy
    while (Uart_is_tx_full(uart))
    {
    }

    // Ép kiểu (uint32_t)data trước khi truyền cho hàm write_reg 32-bit
    write_reg(uart, UART_TX_REG_WORD_OFFSET, (uint32_t)data & UART_DATA_MASK);
}

bool Uart_read_byte(Uart_t *uart, uint8_t *data)
{
    uint32_t status;

    if (!uart_is_valid(uart) || data == NULL) return false;

    // Đọc phần cứng đúng 1 lần duy nhất để lấy cả Data lẫn Cờ
    status = read_rx_status(uart);
    
    // Kiểm tra cờ RX_EMPTY (Bit 8). Nếu khác 0 tức là FIFO rỗng
    if ((status & UART_RX_EMPTY) != 0U)
    {
        return false; 
    }

    // Nếu có data, tách lấy 8 bit và lưu vào con trỏ
    *data = (uint8_t)(status & UART_DATA_MASK);
    return true; 
}

void Uart_write_string(Uart_t *uart, const char *str)
{
    if (!uart_is_valid(uart) || (str == NULL)) return;

    while (*str != '\0')
    {
        Uart_write_byte(uart, (uint8_t)(*str));
        str++;
    }
}

/* ========================================================================= */
/* HIGH-LEVEL (ARDUINO-STYLE)                                                */
/* ========================================================================= */

void Uart_begin(uint32_t baud_rate)
{
    Uart_create_default(&uart_0);
    Uart_init_baudrate(&uart_0, baud_rate);
}

void Uart_end(void)
{
    uart_0.regs = NULL;
}

void Uart_write(uint8_t data)
{
    Uart_write_byte(&uart_0, data);
}

bool Uart_read(uint8_t *data)
{
    return Uart_read_byte(&uart_0, data);
}

bool Uart_available(void)
{
    return !Uart_is_rx_empty(&uart_0);
}

void Uart_print(const char *str)
{
    Uart_write_string(&uart_0, str);
}

void Uart_println(const char *str)
{
    if (str == NULL) return;

    Uart_write_string(&uart_0, str);
    Uart_write_byte(&uart_0, (uint8_t)'\r');
    Uart_write_byte(&uart_0, (uint8_t)'\n');
}

#endif // HAL_UART_MODULE_ENABLED
