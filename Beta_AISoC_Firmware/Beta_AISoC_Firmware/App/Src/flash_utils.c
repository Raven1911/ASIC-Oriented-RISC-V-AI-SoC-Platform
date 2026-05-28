#include "flash_utils.h"

#include "SPI_Driver.h"
#include "UART_Driver.h"

#define SPI_CS_LOW()   spi_set_slave(SPI_SLAVE_0)
#define SPI_CS_HIGH()  spi_set_slave(0U)
#define FLASH_BUSY_POLL_LIMIT 10000000U

void flash_write_enable(void)
{
    SPI_CS_LOW();
    spi_transfer(0x06U);
    SPI_CS_HIGH();
}

bool flash_wait_busy(void)
{
    uint8_t status;

    for (uint32_t timeout = 0; timeout < FLASH_BUSY_POLL_LIMIT; timeout++) {
        SPI_CS_LOW();
        spi_transfer(0x05U);
        status = spi_transfer(0xFFU);
        SPI_CS_HIGH();

        if ((status & 0x01U) == 0U) {
            return true;
        }
    }

    return false;
}

bool flash_erase_sector(uint32_t addr)
{
    flash_write_enable();

    SPI_CS_LOW();
    spi_transfer(0x20U);
    spi_transfer((uint8_t)((addr >> 16) & 0xFFU));
    spi_transfer((uint8_t)((addr >> 8) & 0xFFU));
    spi_transfer((uint8_t)(addr & 0xFFU));
    SPI_CS_HIGH();

    return flash_wait_busy();
}

bool flash_page_program(uint32_t addr, const uint8_t *data, uint16_t len)
{
    flash_write_enable();

    SPI_CS_LOW();
    spi_transfer(0x02U);
    spi_transfer((uint8_t)((addr >> 16) & 0xFFU));
    spi_transfer((uint8_t)((addr >> 8) & 0xFFU));
    spi_transfer((uint8_t)(addr & 0xFFU));

    for (uint16_t i = 0; i < len; i++) {
        spi_transfer(data[i]);
    }

    SPI_CS_HIGH();
    return flash_wait_busy();
}

void flash_read_data(uint32_t addr, uint8_t *buffer, uint32_t len)
{
    SPI_CS_LOW();
    spi_transfer(0x03U);
    spi_transfer((uint8_t)((addr >> 16) & 0xFFU));
    spi_transfer((uint8_t)((addr >> 8) & 0xFFU));
    spi_transfer((uint8_t)(addr & 0xFFU));

    for (uint32_t i = 0; i < len; i++) {
        buffer[i] = spi_transfer(0xFFU);
    }

    SPI_CS_HIGH();
}

uint32_t flash_crc32(uint32_t start_addr, uint32_t length)
{
    uint32_t crc = 0xFFFFFFFFU;

    SPI_CS_LOW();
    spi_transfer(0x03U);
    spi_transfer((uint8_t)((start_addr >> 16) & 0xFFU));
    spi_transfer((uint8_t)((start_addr >> 8) & 0xFFU));
    spi_transfer((uint8_t)(start_addr & 0xFFU));

    for (uint32_t i = 0; i < length; i++) {
        uint8_t byte = spi_transfer(0xFFU);
        crc ^= byte;
        for (uint8_t bit = 0; bit < 8U; bit++) {
            crc = (crc >> 1) ^ ((uint32_t)(-((int32_t)(crc & 1U))) & 0xEDB88320U);
        }
    }

    SPI_CS_HIGH();
    return ~crc;
}

void Uart_print_hex_32(uint32_t val)
{
    char buf[9];

    for (int i = 7; i >= 0; i--) {
        uint8_t nibble = (uint8_t)(val & 0xFU);
        buf[i] = (char)((nibble < 10U) ? ('0' + nibble) : ('A' + nibble - 10U));
        val >>= 4;
    }

    buf[8] = '\0';
    Uart_print(buf);
}
