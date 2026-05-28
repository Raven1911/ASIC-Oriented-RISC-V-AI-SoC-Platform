#ifndef FLASH_UTILS_H
#define FLASH_UTILS_H

#include <stdint.h>
#include <stdbool.h>

#define SOC_SECTOR_SIZE 4096U
#define SOC_PAGE_SIZE 256U
#define SOC_FLASH_SIZE (16U * 1024U * 1024U)

void flash_write_enable(void);
bool flash_wait_busy(void);
bool flash_erase_sector(uint32_t addr);
bool flash_page_program(uint32_t addr, const uint8_t *data, uint16_t len);
void flash_read_data(uint32_t addr, uint8_t *buffer, uint32_t len);
uint32_t flash_crc32(uint32_t start_addr, uint32_t length);
void Uart_print_hex_32(uint32_t val);

#endif
