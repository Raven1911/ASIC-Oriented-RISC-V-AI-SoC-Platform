#include "../Inc/I2C_Driver.h"
#ifdef HAL_I2C_MODULE_ENABLED

I2CDriver_t i2c0;
I2CDriver_t i2c1;
// I2CDriver_t i2c2;

static void write_reg(I2CDriver_t* drv, uint32_t offset, uint32_t value) {
    *(drv->base_addr + (offset - I2C_BASE_ADDR) / 4) = value;
}

static uint32_t read_reg(I2CDriver_t* drv, uint32_t offset) {
    return *(drv->base_addr + (offset - I2C_BASE_ADDR) / 4);
}

void I2C_driver_init(I2CDriver_t* drv, uint32_t base) {
    drv->base_addr = (volatile uint32_t*)base;
}

void I2C_init(I2CDriver_t* drv, uint32_t clk_freq, uint32_t i2c_freq) {
    uint16_t dvsr = (uint16_t)(clk_freq / (4 * i2c_freq) - 1);
    write_reg(drv, I2C_DVSR_REG, (uint32_t)dvsr);
}

void I2C_select_slave(I2CDriver_t* drv, uint8_t slave_addr_7bit, bool read_mode, bool check_ack) {
    write_reg(drv, I2C_CMD_REG, (uint32_t)I2C_CMD_START << 8);
    while (!(read_reg(drv, I2C_DATA_REG) & I2C_READY)) {}

    uint8_t full_addr = (uint8_t)((slave_addr_7bit << 1) | (read_mode ? 1 : 0));
    uint32_t cmd_data = ((uint32_t)I2C_CMD_WRITE << 8) | full_addr;
    write_reg(drv, I2C_CMD_REG, cmd_data);
    while (!(read_reg(drv, I2C_DATA_REG) & I2C_READY)) {}
    if (check_ack && !I2C_check_ack(drv)) {
        I2C_stop(drv);
    }
}

void I2C_write(I2CDriver_t* drv, uint8_t data) {
    while (!(read_reg(drv, I2C_DATA_REG) & I2C_READY)) {}
    uint32_t cmd_data = ((uint32_t)I2C_CMD_WRITE << 8) | data;
    write_reg(drv, I2C_CMD_REG, cmd_data);
}

int16_t I2C_read(I2CDriver_t* drv, bool nack) {
    if (!(read_reg(drv, I2C_DATA_REG) & I2C_READY)) {
        return -1;
    }
    uint32_t cmd_data = ((uint32_t)I2C_CMD_READ << 8) | (nack ? 1U : 0U);
    write_reg(drv, I2C_CMD_REG, cmd_data);
    while (!(read_reg(drv, I2C_DATA_REG) & I2C_READY)) {}
    uint32_t status = read_reg(drv, I2C_DATA_REG);
    return (int16_t)(status & I2C_DATA_MASK);
}

bool I2C_is_ready(I2CDriver_t* drv) {
    return (read_reg(drv, I2C_DATA_REG) & I2C_READY) != 0;
}

void I2C_write_string(I2CDriver_t* drv, const char* str) {
    while (*str) {
        I2C_write(drv, (uint8_t)*str++);
    }
}

bool I2C_check_ack(I2CDriver_t* drv) {
    return (read_reg(drv, I2C_DATA_REG) & I2C_ACK) == 0;
}

void I2C_stop(I2CDriver_t* drv) {
    while (!(read_reg(drv, I2C_DATA_REG) & I2C_READY)) {}
    write_reg(drv, I2C_CMD_REG, (uint32_t)I2C_CMD_STOP << 8);
    while (!(read_reg(drv, I2C_DATA_REG) & I2C_READY)) {}
}

void I2C_restart(I2CDriver_t* drv) {
    while (!(read_reg(drv, I2C_DATA_REG) & I2C_READY)) {}
    write_reg(drv, I2C_CMD_REG, (uint32_t)I2C_CMD_RESTART << 8);
    while (!(read_reg(drv, I2C_DATA_REG) & I2C_READY)) {}
}

bool I2C_write_transaction(I2CDriver_t* drv, uint8_t slave_addr_7bit, const uint8_t* data, uint32_t length, bool check_ack) {
    I2C_select_slave(drv, slave_addr_7bit, false, check_ack);
    if (check_ack && !I2C_check_ack(drv)) return false;

    for (uint32_t i = 0; i < length; ++i) {
        I2C_write(drv, data[i]);
        while (!I2C_is_ready(drv)) {}
        if (check_ack && !I2C_check_ack(drv)) {
            I2C_stop(drv);
            return false;
        }
    }
    I2C_stop(drv);
    return true;
}

bool I2C_read_transaction(I2CDriver_t* drv, uint8_t slave_addr_7bit, uint8_t* buffer, uint32_t length, bool check_ack) {
    I2C_select_slave(drv, slave_addr_7bit, true, check_ack);
    if (check_ack && !I2C_check_ack(drv)) return false;

    for (uint32_t i = 0; i < length; ++i) {
        bool nack = (i == length - 1);
        int16_t data = I2C_read(drv, nack);
        if (data == -1) {
            I2C_stop(drv);
            return false;
        }
        buffer[i] = (uint8_t)data;
    }
    I2C_stop(drv);
    return true;
}

#endif // HAL_I2C_MODULE_ENABLED
