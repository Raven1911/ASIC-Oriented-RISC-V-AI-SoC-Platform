/**
 * @file boot.c
 * @brief Bootloader Core Implementation for PicoRV32
 * Features: Dummy Consume, Hardware CS Control, Burst Read, Duplicate Seq ARQ.
 */

#include "boot.h"
#include "../SoC_HAL/Inc/UART_Driver.h"
#include "../SoC_HAL/Inc/SPI_Driver.h"
#include "../SoC_HAL/Inc/mem.h"
#include "../SoC_HAL/Inc/timer.h"

/* ========================================================================== */
/* HARDWARE DEPENDENT MACROS: SPI CHIP SELECT                                 */
/* ========================================================================== */
#define SPI_CS_LOW()   spi_set_slave(SPI_SLAVE_0);
#define SPI_CS_HIGH()  spi_set_slave(0U);
#define FLASH_BUSY_POLL_LIMIT 10000000U

/* ========================================================================== */
/* PRIVATE VARIABLES                                                          */
/* ========================================================================== */
BootFrame_t current_frame;
BootState_t current_state = STATE_WAIT_SOF;
uint16_t bytes_ptr = 0;

/* Protocol tracking variables */
uint8_t  last_valid_seq = 0xFF; /* For duplicate frame detection */
uint16_t running_crc    = 0xFFFF;
bool     flag_oversize  = false;
uint32_t last_frame_rx_ms = 0;

uint8_t  last_response_status = STATUS_ACK;
uint16_t last_response_len = 0;
uint8_t  last_response_data[MAX_RESPONSE_CACHE_SIZE];
bool     last_response_valid = false;

/* Session metadata declared by Host */
uint32_t fw_image_size = 0;
uint32_t fw_image_crc  = 0;

void boot_send_response(uint8_t status, const uint8_t *data, uint16_t len);

static void boot_reset_rx_state(void) {
    current_state = STATE_WAIT_SOF;
    bytes_ptr = 0;
    running_crc = 0xFFFF;
    flag_oversize = false;
}

static bool boot_current_frame_has_seq(void) {
    return (current_state != STATE_WAIT_SOF) &&
           ((current_state != STATE_WAIT_HEADER) || (bytes_ptr > 0));
}

static void boot_check_frame_timeout(void) {
    if (current_state != STATE_WAIT_SOF) {
        uint32_t now = millis();
        if ((now - last_frame_rx_ms) > BOOT_FRAME_TIMEOUT_MS) {
            if (boot_current_frame_has_seq()) {
                boot_send_response(STATUS_NACK, NULL, 0);
            }
            boot_reset_rx_state();
        }
    }
}

/* ========================================================================== */
/* PROGRESSIVE CRC-16-CCITT                                                   */
/* ========================================================================== */
/**
 * @brief Calculates CRC progressively byte-by-byte. Highly efficient for FSM.
 */
uint16_t boot_crc16_byte(uint16_t crc, uint8_t data) {
    crc ^= (uint16_t)data << 8;
    for (uint8_t i = 0; i < 8; i++) {
        if (crc & 0x8000) crc = (crc << 1) ^ 0x1021;
        else crc <<= 1;
    }
    return crc;
}

/* Block CRC for Host response */
uint16_t boot_crc16_block(uint16_t init_crc, const uint8_t *data, uint32_t length) {
    uint16_t crc = init_crc;
    for (uint32_t i = 0; i < length; i++) {
        crc = boot_crc16_byte(crc, data[i]);
    }
    return crc;
}

/* ========================================================================== */
/* LOW-LEVEL SPI FLASH WRAPPERS (W25Q Series with CS Framing & Burst Read)    */
/* ========================================================================== */
void flash_write_enable(void) {
    SPI_CS_LOW();
    spi_transfer(0x06); /* WREN */
    SPI_CS_HIGH();
}

bool flash_wait_busy(void) {
    uint8_t status;
    for (uint32_t timeout = 0; timeout < FLASH_BUSY_POLL_LIMIT; timeout++) {
        SPI_CS_LOW();
        spi_transfer(0x05); /* Read Status Register-1 */
        status = spi_transfer(0xFF);
        SPI_CS_HIGH();
        if ((status & 0x01) == 0) {
            return true;
        }
    }
    return false;
}

bool flash_erase_sector(uint32_t addr) {
    flash_write_enable();
    SPI_CS_LOW();
    spi_transfer(0x20); /* Sector Erase (4KB) */
    spi_transfer((addr >> 16) & 0xFF);
    spi_transfer((addr >> 8) & 0xFF);
    spi_transfer(addr & 0xFF);
    SPI_CS_HIGH();
    return flash_wait_busy();
}

bool flash_page_program(uint32_t addr, const uint8_t *data, uint16_t len) {
    flash_write_enable();
    SPI_CS_LOW();
    spi_transfer(0x02); /* Page Program */
    spi_transfer((addr >> 16) & 0xFF);
    spi_transfer((addr >> 8) & 0xFF);
    spi_transfer(addr & 0xFF);
    for (uint16_t i = 0; i < len; i++) {
        spi_transfer(data[i]);
    }
    SPI_CS_HIGH();
    return flash_wait_busy();
}

/**
 * @brief Fast CRC32 computation directly from Flash using Continuous Read.
 */
uint32_t boot_crc32_flash(uint32_t start_addr, uint32_t length) {
    uint32_t crc = 0xFFFFFFFF;
    
    SPI_CS_LOW();
    spi_transfer(0x03); /* Normal Read Data */
    spi_transfer((start_addr >> 16) & 0xFF);
    spi_transfer((start_addr >> 8) & 0xFF);
    spi_transfer(start_addr & 0xFF);

    /* Stream bytes continuously without toggling CS */
    for (uint32_t i = 0; i < length; i++) {
        uint8_t byte = spi_transfer(0xFF);
        crc ^= byte;
        for (uint8_t j = 0; j < 8; j++) {
            crc = (crc >> 1) ^ (-(int32_t)(crc & 1) & 0xEDB88320);
        }
    }
    SPI_CS_HIGH();
    return ~crc;
}

/* ========================================================================== */
/* COMMUNICATION HELPERS                                                      */
/* ========================================================================== */
void boot_send_response(uint8_t status, const uint8_t *data, uint16_t len) {
    // Uart_write((uint8_t)0x99); /* Debug: Sending Response */
    uint8_t header[5] = {FRAME_SOF, current_frame.seq, status, (uint8_t)len, (uint8_t)(len >> 8)};
    
    uint16_t crc = boot_crc16_block(0xFFFF, &header[1], 4); 
    if (len > 0 && data != NULL) {
        crc = boot_crc16_block(crc, data, len);
    }
    
    for(int i = 0; i < 5; i++) Uart_write(header[i]);
    if (len > 0 && data != NULL) {
        for(int i = 0; i < len; i++) Uart_write(data[i]);
    }
    Uart_write((uint8_t)crc);
    Uart_write((uint8_t)(crc >> 8));
    Uart_write(FRAME_EOF);
}

void boot_cache_response(uint8_t status, const uint8_t *data, uint16_t len) {
    last_response_status = status;
    last_response_len = 0;
    last_response_valid = true;

    if (len > 0 && data != NULL) {
        uint16_t cached_len = (len <= MAX_RESPONSE_CACHE_SIZE) ? len : MAX_RESPONSE_CACHE_SIZE;
        for (uint16_t i = 0; i < cached_len; i++) {
            last_response_data[i] = data[i];
        }
        last_response_len = cached_len;
    }
}

void boot_send_cached_response(uint8_t status, const uint8_t *data, uint16_t len) {
    boot_cache_response(status, data, len);
    boot_send_response(status, data, len);
}

void boot_replay_last_response(void) {
    if (last_response_valid) {
        boot_send_response(last_response_status,
                           last_response_len > 0 ? last_response_data : NULL,
                           last_response_len);
    } else {
        boot_send_response(STATUS_ACK, NULL, 0);
    }
}

void boot_send_error(uint8_t cat, uint8_t code, uint32_t info) {
    uint8_t err[6] = {cat, code, (uint8_t)info, (uint8_t)(info>>8), (uint8_t)(info>>16), (uint8_t)(info>>24)};
    boot_send_cached_response(STATUS_ERROR, err, 6);
}

/* ========================================================================== */
/* EXECUTION & MEMORY MAPPING LOGIC                                           */
/* ========================================================================== */
static uint32_t boot_align4(uint32_t value) {
    return (value + 3U) & ~3U;
}

static uint32_t flash_read_u32_le(uint32_t addr) {
    uint32_t value = 0;

    SPI_CS_LOW();
    spi_transfer(0x03);
    spi_transfer((addr >> 16) & 0xFF);
    spi_transfer((addr >> 8) & 0xFF);
    spi_transfer(addr & 0xFF);

    value |= (uint32_t)spi_transfer(0xFF);
    value |= (uint32_t)spi_transfer(0xFF) << 8;
    value |= (uint32_t)spi_transfer(0xFF) << 16;
    value |= (uint32_t)spi_transfer(0xFF) << 24;
    SPI_CS_HIGH();

    return value;
}

static bool range_contains(uint32_t base, uint32_t length, uint32_t addr, uint32_t size) {
    uint32_t base_end = base + length;
    uint32_t addr_end = addr + size;

    if (addr_end < addr || base_end < base) {
        return false;
    }

    return (addr >= base) && (addr_end <= base_end);
}

static bool boot_segment_is_valid(const BootImageSegment_t *segment, uint32_t image_size) {
    if ((segment->dst_addr & 3U) != 0U) {
        return false;
    }

    if (segment->kind == BOOT_SEG_LOAD_IMEM) {
        uint32_t padded_size = boot_align4(segment->size);
        if (!range_contains(APP_IMEM_ORIGIN, APP_IMEM_SIZE, segment->dst_addr, padded_size)) {
            return false;
        }
        if (segment->flash_offset > image_size || padded_size > (image_size - segment->flash_offset)) {
            return false;
        }
        return true;
    }

    if (segment->kind == BOOT_SEG_LOAD_DMEM) {
        uint32_t padded_size = boot_align4(segment->size);
        if (!range_contains(APP_DMEM_ORIGIN, APP_DMEM_SIZE, segment->dst_addr, padded_size)) {
            return false;
        }
        if (segment->flash_offset > image_size || padded_size > (image_size - segment->flash_offset)) {
            return false;
        }
        return true;
    }

    if (segment->kind == BOOT_SEG_ZERO_DMEM) {
        uint32_t padded_size = boot_align4(segment->size);
        return range_contains(APP_DMEM_ORIGIN, APP_DMEM_SIZE, segment->dst_addr, padded_size);
    }

    return false;
}

static void boot_store_word(uint32_t addr, uint32_t value) {
    __asm__ volatile ("sw %1, 0(%0)" :: "r"(addr), "r"(value) : "memory");
}

static void boot_load_segment_from_flash(const BootImageSegment_t *segment) {
    uint32_t src_addr = BOOT_FLASH_IMAGE_OFFSET + segment->flash_offset;
    uint32_t copied = 0;

    SPI_CS_LOW();
    spi_transfer(0x03);
    spi_transfer((src_addr >> 16) & 0xFF);
    spi_transfer((src_addr >> 8) & 0xFF);
    spi_transfer(src_addr & 0xFF);

    while (copied < segment->size) {
        uint32_t word = 0;
        word |= (uint32_t)spi_transfer(0xFF);
        word |= (uint32_t)spi_transfer(0xFF) << 8;
        word |= (uint32_t)spi_transfer(0xFF) << 16;
        word |= (uint32_t)spi_transfer(0xFF) << 24;

        boot_store_word(segment->dst_addr + copied, word);
        copied += 4U;
    }

    SPI_CS_HIGH();
}

static void boot_zero_segment(const BootImageSegment_t *segment) {
    uint32_t cleared = 0;
    uint32_t size = boot_align4(segment->size);

    while (cleared < size) {
        boot_store_word(segment->dst_addr + cleared, 0U);
        cleared += 4U;
    }
}

__attribute__((noreturn)) static void boot_jump_to(uint32_t entry_addr) {
    __asm__ volatile ("jr %0" :: "r"(entry_addr) : "memory");
    while (1) {}
}

bool load_flash_to_imem(void) {
    uint32_t status_word = flash_read_u32_le(META_STATUS_OFFSET);
    uint32_t image_size = flash_read_u32_le(META_SIZE_OFFSET);
    BootImageSegment_t segments[BOOT_IMAGE_MAX_SEGMENTS];

    if (status_word != VALID_MAGIC_WORD || image_size == 0 || image_size > APPLICATION_MAX_SIZE) {
        return false;
    }

    uint32_t magic = flash_read_u32_le(BOOT_FLASH_IMAGE_OFFSET + 0U);
    uint32_t version = flash_read_u32_le(BOOT_FLASH_IMAGE_OFFSET + 4U);
    uint32_t payload_offset = flash_read_u32_le(BOOT_FLASH_IMAGE_OFFSET + 8U);
    uint32_t segment_count = flash_read_u32_le(BOOT_FLASH_IMAGE_OFFSET + 12U);
    uint32_t entry_addr = flash_read_u32_le(BOOT_FLASH_IMAGE_OFFSET + 16U);

    if (magic != BOOT_IMAGE_MAGIC ||
        version != BOOT_IMAGE_VERSION ||
        segment_count == 0U ||
        segment_count > BOOT_IMAGE_MAX_SEGMENTS ||
        payload_offset > image_size ||
        !range_contains(APP_IMEM_ORIGIN, APP_IMEM_SIZE, entry_addr, 4U)) {
        return false;
    }

    uint32_t descriptor_end = BOOT_IMAGE_HEADER_SIZE + (segment_count * BOOT_IMAGE_SEGMENT_SIZE);
    if (payload_offset < descriptor_end) {
        return false;
    }

    for (uint32_t i = 0; i < segment_count; i++) {
        uint32_t desc_addr = BOOT_FLASH_IMAGE_OFFSET + BOOT_IMAGE_HEADER_SIZE + (i * BOOT_IMAGE_SEGMENT_SIZE);
        segments[i].kind = flash_read_u32_le(desc_addr + 0U);
        segments[i].flags = flash_read_u32_le(desc_addr + 4U);
        segments[i].flash_offset = flash_read_u32_le(desc_addr + 8U);
        segments[i].dst_addr = flash_read_u32_le(desc_addr + 12U);
        segments[i].size = flash_read_u32_le(desc_addr + 16U);

        if (!boot_segment_is_valid(&segments[i], image_size)) {
            return false;
        }

        if ((segments[i].kind == BOOT_SEG_LOAD_IMEM ||
             segments[i].kind == BOOT_SEG_LOAD_DMEM) &&
            segments[i].flash_offset < payload_offset) {
            return false;
        }
    }

    for (uint32_t i = 0; i < segment_count; i++) {
        if (segments[i].kind == BOOT_SEG_LOAD_IMEM) {
            boot_load_segment_from_flash(&segments[i]);
        }
    }

    for (uint32_t i = 0; i < segment_count; i++) {
        if (segments[i].kind == BOOT_SEG_LOAD_DMEM) {
            boot_load_segment_from_flash(&segments[i]);
        }
    }

    for (uint32_t i = 0; i < segment_count; i++) {
        if (segments[i].kind == BOOT_SEG_ZERO_DMEM) {
            boot_zero_segment(&segments[i]);
        }
    }

    boot_jump_to(entry_addr);
}

void execute_app(void) {
    boot_jump_to(APPLICATION_START_ADDRESS);
}

/* ========================================================================== */
/* COMMAND HANDLERS                                                           */
/* ========================================================================== */

uint8_t cap[14];
void handle_get_cap(void) {
    // Uart_write((uint8_t)0x98); /* Debug: Sending Response */
    // uint8_t cap[14];
    
    /* BOOTLOADER_VERSION (uint16_t at offset 0) */
    cap[0] = (uint8_t)(BOOTLOADER_VERSION & 0xFF);
    cap[1] = (uint8_t)((BOOTLOADER_VERSION >> 8) & 0xFF);
    
    /* SOC_FLASH_SIZE (uint32_t at offset 2) */
    cap[2] = (uint8_t)(SOC_FLASH_SIZE & 0xFF);
    cap[3] = (uint8_t)((SOC_FLASH_SIZE >> 8) & 0xFF);
    cap[4] = (uint8_t)((SOC_FLASH_SIZE >> 16) & 0xFF);
    cap[5] = (uint8_t)((SOC_FLASH_SIZE >> 24) & 0xFF);
    
    /* SOC_SECTOR_SIZE (uint16_t at offset 6) */
    cap[6] = (uint8_t)(SOC_SECTOR_SIZE & 0xFF);
    cap[7] = (uint8_t)((SOC_SECTOR_SIZE >> 8) & 0xFF);
    
    /* SOC_PAGE_SIZE (uint16_t at offset 8) */
    cap[8] = (uint8_t)(SOC_PAGE_SIZE & 0xFF);
    cap[9] = (uint8_t)((SOC_PAGE_SIZE >> 8) & 0xFF);
    
    /* APPLICATION_START_ADDRESS (uint32_t at offset 10) */
    cap[10] = (uint8_t)(APPLICATION_START_ADDRESS & 0xFF);
    cap[11] = (uint8_t)((APPLICATION_START_ADDRESS >> 8) & 0xFF);
    cap[12] = (uint8_t)((APPLICATION_START_ADDRESS >> 16) & 0xFF);
    cap[13] = (uint8_t)((APPLICATION_START_ADDRESS >> 24) & 0xFF);
    
    boot_send_cached_response(STATUS_ACK, cap, 14);
}

void handle_info(void) {
    fw_image_size = (uint32_t)current_frame.payload[0]
                  | ((uint32_t)current_frame.payload[1] << 8)
                  | ((uint32_t)current_frame.payload[2] << 16)
                  | ((uint32_t)current_frame.payload[3] << 24);
    
    fw_image_crc  = (uint32_t)current_frame.payload[4]
                  | ((uint32_t)current_frame.payload[5] << 8)
                  | ((uint32_t)current_frame.payload[6] << 16)
                  | ((uint32_t)current_frame.payload[7] << 24);

    if (fw_image_size == 0 || fw_image_size > APPLICATION_MAX_SIZE) {
        boot_send_error(ERR_CAT_LOGIC, ERR_CODE_PAYLOAD_OVR, fw_image_size);
        return;
    }
    
    boot_send_cached_response(STATUS_ACK, NULL, 0);
}

void handle_erase(void) {
    uint32_t requested_size = *(uint32_t*)&current_frame.payload[4];
    uint32_t addr = BOOT_FLASH_IMAGE_OFFSET; 

    if (requested_size == 0 || requested_size > APPLICATION_MAX_SIZE) {
        boot_send_error(ERR_CAT_LOGIC, ERR_CODE_PAYLOAD_OVR, requested_size);
        return;
    }
    
    uint32_t end_addr = addr + requested_size;
    while (addr < end_addr) {
        if (!flash_erase_sector(addr)) {
            boot_send_error(ERR_CAT_FLASH, ERR_CODE_ERASE_FAIL, addr);
            return;
        }
        addr += SOC_SECTOR_SIZE;
    }
    boot_send_cached_response(STATUS_ACK, NULL, 0);
}

void handle_write(void) {
    uint32_t offset = *(uint32_t*)&current_frame.payload[0]; // Lưu ý
    uint16_t data_len = current_frame.len - 4;
    uint32_t abs_addr = BOOT_FLASH_IMAGE_OFFSET + offset;

    if (offset > fw_image_size || data_len > (fw_image_size - offset)) {
        boot_send_error(ERR_CAT_LOGIC, ERR_CODE_PAYLOAD_OVR, offset + data_len);
        return;
    }

    uint32_t current_addr = abs_addr;
    uint8_t *data_ptr = &current_frame.payload[4];
    uint16_t remaining_len = data_len;

    /* 1. Safe Page Program with Boundary Wrap-around Protection */
    while (remaining_len > 0) {
        uint16_t bytes_to_page_end = SOC_PAGE_SIZE - (current_addr % SOC_PAGE_SIZE);
        uint16_t chunk_len = (remaining_len < bytes_to_page_end) ? remaining_len : bytes_to_page_end;

        if (!flash_page_program(current_addr, data_ptr, chunk_len)) {
            boot_send_error(ERR_CAT_FLASH, ERR_CODE_ERASE_FAIL, current_addr);
            return;
        }

        current_addr += chunk_len;
        data_ptr += chunk_len;
        remaining_len -= chunk_len;
    }

    /* 2. Optional immediate readback verification (Burst Mode).
     * The final CMD_VERIFY CRC32 still checks the complete firmware image.
     */
#if BOOT_WRITE_READBACK_VERIFY
    SPI_CS_LOW();
    spi_transfer(0x03);
    spi_transfer((abs_addr >> 16) & 0xFF);
    spi_transfer((abs_addr >> 8) & 0xFF);
    spi_transfer(abs_addr & 0xFF);
    
    for(uint16_t i = 0; i < data_len; i++) {
        uint8_t readback = spi_transfer(0xFF);
        if (readback != current_frame.payload[4 + i]) {
            SPI_CS_HIGH(); /* Always release CS on error */
            boot_send_error(ERR_CAT_FLASH, ERR_CODE_VERIFY_FAIL, abs_addr + i);
            return;
        }
    }
    SPI_CS_HIGH();
#endif
    
    boot_send_cached_response(STATUS_ACK, NULL, 0);
}

void handle_verify_and_commit(void) {
    uint32_t calculated_crc = boot_crc32_flash(BOOT_FLASH_IMAGE_OFFSET, fw_image_size);
    
    if (calculated_crc == fw_image_crc) {
        if (!flash_erase_sector(BOOT_FLASH_META_OFFSET)) {
            boot_send_error(ERR_CAT_FLASH, ERR_CODE_ERASE_FAIL, BOOT_FLASH_META_OFFSET);
            return;
        }
        
        uint32_t magic = VALID_MAGIC_WORD;
        if (!flash_page_program(META_STATUS_OFFSET, (uint8_t*)&magic, 4) ||
            !flash_page_program(META_SIZE_OFFSET, (uint8_t*)&fw_image_size, 4)) {
            boot_send_error(ERR_CAT_FLASH, ERR_CODE_ERASE_FAIL, BOOT_FLASH_META_OFFSET);
            return;
        }
        
        boot_send_cached_response(STATUS_ACK, (uint8_t*)&calculated_crc, 4);
    } else {
        boot_send_error(ERR_CAT_LOGIC, ERR_CODE_CRC_FAIL, calculated_crc);
    }
}

void handle_load_and_jump(void) {
    boot_send_cached_response(STATUS_ACK, NULL, 0);
    if (load_flash_to_imem()) execute_app();                           
}

bool boot_validate_command_length(void) {
    if (current_frame.cmd == CMD_GET_CAP) return current_frame.len == 0;
    if (current_frame.cmd == CMD_INFO)    return current_frame.len == 14;
    if (current_frame.cmd == CMD_ERASE)   return current_frame.len == 8;
    if (current_frame.cmd == CMD_WRITE)   return current_frame.len >= 4;
    if (current_frame.cmd == CMD_VERIFY)  return current_frame.len == 0;
    if (current_frame.cmd == CMD_JUMP)    return current_frame.len == 0;
    return true;
}

/* ========================================================================== */
/* PROTOCOL STATE MACHINE (INLINE FOR ZERO CALL OVERHEAD)                     */
/* ========================================================================== */
/**
 * @brief Core UART byte processor. Declared 'inline' to be flattened 
 * directly into the while(1) loop in main() for maximum CPU efficiency.
 */
void boot_process(uint8_t rx_byte) {
    boot_check_frame_timeout();
    last_frame_rx_ms = millis();

    if (current_state == STATE_WAIT_SOF) {
        if (rx_byte == FRAME_SOF) {
            current_state = STATE_WAIT_HEADER;
            bytes_ptr = 0;
            running_crc = 0xFFFF;
            flag_oversize = false;
            // Uart_write((uint8_t)0x01); /* Debug: Received SOF */
        }
        return;
    }
    if (current_state == STATE_WAIT_HEADER) {
        /* Progressive CRC calculation */
        running_crc = boot_crc16_byte(running_crc, rx_byte);

        if (bytes_ptr == 0)      current_frame.seq = rx_byte;
        else if (bytes_ptr == 1) current_frame.cmd = rx_byte;
        else if (bytes_ptr == 2) current_frame.len = (uint16_t)rx_byte;
        else if (bytes_ptr == 3) {
            current_frame.len |= (uint16_t)rx_byte << 8;
            
            /* A corrupted length can otherwise trap the FSM waiting for bytes
             * that will never arrive. Reject early and resync on the next SOF.
             */
            if (current_frame.len > MAX_PAYLOAD_SIZE) {
                boot_send_response(STATUS_NACK, NULL, 0);
                boot_reset_rx_state();
                return;
            }
            current_state = (current_frame.len > 0) ? STATE_WAIT_PAYLOAD : STATE_WAIT_CRC;
            bytes_ptr = 0;
            // Uart_write((uint8_t)0x02); /* Debug: Received Header */
            return;
        }
        bytes_ptr++;
        return;
    }
    if (current_state == STATE_WAIT_PAYLOAD) {
        running_crc = boot_crc16_byte(running_crc, rx_byte);
        
        /* Only buffer data if it fits, preventing RAM overflow */
        if (!flag_oversize && bytes_ptr < MAX_PAYLOAD_SIZE) {
            current_frame.payload[bytes_ptr] = rx_byte;
        }
        
        bytes_ptr++;
        if (bytes_ptr >= current_frame.len) {
            current_state = STATE_WAIT_CRC;
            bytes_ptr = 0;
            // Uart_write((uint8_t)0x03); /* Debug: Received Payload */
        }
        return;
    }
    if (current_state == STATE_WAIT_CRC) {
        if (bytes_ptr == 0) current_frame.crc_received = (uint16_t)rx_byte;
        else {
            current_frame.crc_received |= (uint16_t)rx_byte << 8;
            current_state = STATE_WAIT_EOF;
            // Uart_write((uint8_t)0x04); /* Debug: Received CRC */
        }
        bytes_ptr++;
        return;
    }
    if (current_state == STATE_WAIT_EOF) {
        if (rx_byte == FRAME_EOF) {
            /* 1. Check Channel Integrity (Noise) */
            if (running_crc != current_frame.crc_received) {
                boot_send_response(STATUS_NACK, NULL, 0); /* Ask Host to Retry */
            } 
            /* 2. Check Logic/Application Errors */
            else {
                if (flag_oversize) {
                    /* Host intentionally sent oversized frame */
                    boot_send_error(ERR_CAT_LOGIC, ERR_CODE_PAYLOAD_OVR, current_frame.len);
                }
                else if (current_frame.seq == last_valid_seq) {
                    /* Duplicate frame (Host missed ACK). Replay the previous
                     * response so data-bearing ACKs like GET_CAP/VERIFY survive.
                     */
                    boot_replay_last_response();
                } 
                else {
                    /* 3. Execute Valid Command */
                    last_valid_seq = current_frame.seq;
                    
                    if (!boot_validate_command_length()) {
                        boot_send_error(ERR_CAT_LOGIC, ERR_CODE_PAYLOAD_OVR, current_frame.len);
                    } else if (current_frame.cmd == CMD_GET_CAP) {
                        handle_get_cap();
                    } else if (current_frame.cmd == CMD_INFO) {
                        handle_info();
                    } else if (current_frame.cmd == CMD_ERASE) {
                        handle_erase();
                    } else if (current_frame.cmd == CMD_WRITE) {
                        handle_write();
                    } else if (current_frame.cmd == CMD_VERIFY) {
                        handle_verify_and_commit();
                    } else if (current_frame.cmd == CMD_JUMP) {
                        handle_load_and_jump();
                    } else {
                        boot_send_error(ERR_CAT_LOGIC, 0xFF, current_frame.cmd);
                    }
                }
            }
        } else {
            /* Missing EOF due to byte shift/loss */
            boot_send_response(STATUS_NACK, NULL, 0); 
        }
        boot_reset_rx_state();
    }
}

/* ========================================================================== */
/* ENTRY POINT                                                                */
/* ========================================================================== */

int main(void) {
    Uart_begin(230400);
    spi_begin();
    timer_init();

    uint8_t rx_byte;
    bool update_requested = false;

    clear();
    go();
    
    /* PHASE 1: Await Host Command (Timeout Window) */
    while (millis() < BOOT_WAIT_TIME_MS) {
        if (Uart_read(&rx_byte)) {
            if (rx_byte == FRAME_SOF) {
                update_requested = true;
                current_state = STATE_WAIT_HEADER;
                bytes_ptr = 0;
                running_crc = 0xFFFF;
                flag_oversize = false;
                last_frame_rx_ms = millis();
                break;
            }
        }
    }

    pause();

    /* PHASE 2: Normal Boot (No update requested) */
    if (!update_requested) {
        if (load_flash_to_imem()) {
            execute_app(); /* Handover control silently */
        } 
    }

    /* PHASE 3: Infinite Update Loop */
    while (1) {
        if (Uart_read(&rx_byte)) {
            /* Handled inline, ZERO function call overhead */
            boot_process(rx_byte);
        } else {
            boot_check_frame_timeout();
        }
    }
    
    return 0;
}
