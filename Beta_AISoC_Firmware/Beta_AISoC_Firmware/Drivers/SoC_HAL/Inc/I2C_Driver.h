#ifndef I2C_DRIVER_H
#define I2C_DRIVER_H

#include "soc_hal.h"

// Base address and registers
#define I2C0_BASE_ADDR   0x02004000U
#define I2C1_BASE_ADDR   0x02004100U
// #define I2C2_BASE_ADDR   0x02004200U
#define I2C_BASE_ADDR    I2C0_BASE_ADDR
#define I2C_DATA_REG     (I2C_BASE_ADDR + 0x00000000U)  // READ: data and status (ack, ready, dout)
#define I2C_DVSR_REG     (I2C_BASE_ADDR + 0x00000004U)  // WRITE: divisor register (dvsr)
#define I2C_CMD_REG      (I2C_BASE_ADDR + 0x00000008U)  // WRITE: command and input data (cmd, din)

// Status bit definitions
#define I2C_READY        (1U << 8)  // Bit 8: ready
#define I2C_ACK          (1U << 9)  // Bit 9: ack
#define I2C_DATA_MASK    0xFFU      // Bit [7:0]: dout (8-bit data)

// Command definitions
#define I2C_CMD_START    0x00U
#define I2C_CMD_WRITE    0x01U
#define I2C_CMD_READ     0x02U
#define I2C_CMD_STOP     0x03U
#define I2C_CMD_RESTART  0x04U

typedef struct {
    volatile uint32_t* base_addr;
} I2CDriver_t;

extern I2CDriver_t i2c0;
extern I2CDriver_t i2c1;
// extern I2CDriver_t i2c2;

// Initialize driver with base address
void I2C_driver_init(I2CDriver_t* drv, uint32_t base);

// Configure I2C with system clock frequency and desired I2C frequency
void I2C_init(I2CDriver_t* drv, uint32_t clk_freq, uint32_t i2c_freq);

// Select slave by 7-bit address and read/write mode (false=write, true=read), with optional ACK check
void I2C_select_slave(I2CDriver_t* drv, uint8_t slave_addr_7bit, bool read_mode, bool check_ack);

// Send one byte
void I2C_write(I2CDriver_t* drv, uint8_t data);

// Read one byte; returns -1 if not ready, LSB of din as NACK
int16_t I2C_read(I2CDriver_t* drv, bool nack);

// Check if I2C is ready
bool I2C_is_ready(I2CDriver_t* drv);

// Send a null-terminated string
void I2C_write_string(I2CDriver_t* drv, const char* str);

// Check ACK (true if acknowledged, i.e. ack bit == 0)
bool I2C_check_ack(I2CDriver_t* drv);

// Send STOP condition
void I2C_stop(I2CDriver_t* drv);

// Send RESTART condition
void I2C_restart(I2CDriver_t* drv);

// Complete write transaction (start, address, data, stop), with optional ACK check
bool I2C_write_transaction(I2CDriver_t* drv, uint8_t slave_addr_7bit, const uint8_t* data, uint32_t length, bool check_ack);

// Complete read transaction (start, address, data, stop), with optional ACK check
bool I2C_read_transaction(I2CDriver_t* drv, uint8_t slave_addr_7bit, uint8_t* buffer, uint32_t length, bool check_ack);

#endif // I2C_DRIVER_H
