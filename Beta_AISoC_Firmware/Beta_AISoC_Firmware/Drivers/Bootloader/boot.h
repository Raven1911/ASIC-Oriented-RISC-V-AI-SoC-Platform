/**
 * @file boot.h
 * @author Tran Nhat Minh
 * @brief Advanced Bootloader Protocol Definitions for PicoRV32 Custom SoC (FPGA)
 * @version 3.4 (Final: Flash-to-IMEM Loading, Double Validation, Timeout)
 */

#ifndef BOOT_H
#define BOOT_H

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

/* ========================================================================== */
/* SYSTEM CONFIGURATION                                                       */
/* ========================================================================== */
/* CPU Frequency in Hz. Adjust this to match your FPGA synthesis clock */
#define CPU_FREQ_HZ               200000000U  // 200 MHz
/* Time to wait for Host command before booting existing application */
#define BOOT_WAIT_TIME_MS         2000U     
/* Reset the UART frame parser if a partial frame stalls. */
#define BOOT_FRAME_TIMEOUT_MS     100U
/*
 * 0: rely on final firmware CRC32 verification after all chunks are written.
 * 1: also read back every written chunk immediately. Safer, but much slower.
 */
#ifndef BOOT_WRITE_READBACK_VERIFY
#define BOOT_WRITE_READBACK_VERIFY 0
#endif

/* ========================================================================== */
/* PROTOCOL CONSTANTS (PROT-BOOT-H v3.4)                                      */
/* ========================================================================== */
#define FRAME_SOF                 0xA5
#define FRAME_EOF                 0x55
#define MAX_PAYLOAD_SIZE          1024
#define MAX_RESPONSE_CACHE_SIZE   32

/* --- Command Opcodes (Host -> Target) --- */
#define CMD_INFO                  0x02  /* Declare firmware metadata */
#define CMD_ERASE                 0x03  /* Prepare/Erase flash sectors */
#define CMD_WRITE                 0x04  /* Transfer binary data block */
#define CMD_VERIFY                0x05  /* Trigger CRC32 check & commit */
#define CMD_JUMP                  0x06  /* Handover execution to IMEM */
#define CMD_GET_CAP               0x07  /* Discover SoC capabilities */

/* --- Status Codes (Target -> Host) --- */
#define STATUS_ACK                0x79  /* Acknowledge / Success */
#define STATUS_NACK               0x1F  /* Frame Format / CRC Error */
#define STATUS_BUSY               0x22  /* Hardware is busy (e.g., Erasing) */
#define STATUS_ERROR              0xEE  /* Execution / Logic Error */

/* --- Error Categories & Specific Codes --- */
#define ERR_CAT_COMM              0x01
#define ERR_CAT_LOGIC             0x02
#define ERR_CAT_FLASH             0x03

#define ERR_CODE_PAYLOAD_OVR      0x05  /* Payload exceeds MAX_PAYLOAD_SIZE */
#define ERR_CODE_CRC_FAIL         0x06  /* Packet CRC16 or Image CRC32 mismatch */
#define ERR_CODE_VERIFY_FAIL      0x03  /* Written data mismatch (Readback fail) */
#define ERR_CODE_ERASE_FAIL       0x04  /* Flash sector erase timeout/fail */

/* ========================================================================== */
/* HARDWARE & MEMORY MAP CONFIGURATION                                        */
/* ========================================================================== */
#define SOC_FLASH_SIZE            (16 * 1024 * 1024) /* 16MB SPI Flash */
#define SOC_SECTOR_SIZE           4096
#define SOC_PAGE_SIZE             256
#define APPLICATION_MAX_SIZE      (64 * 1024)
#define BOOTLOADER_VERSION        0x0304

/* --- Flash Memory Layout --- */
/* Sector 0 is reserved strictly for Metadata to prevent partial boot */
#define BOOT_FLASH_META_OFFSET    0x00000000U 
/* Sector 1 and onwards are used for storing the actual application binary */
#define BOOT_FLASH_IMAGE_OFFSET   0x00001000U 

/* --- Metadata Configuration (Sector 0) --- */
#define VALID_MAGIC_WORD          0xA5A55A5A
#define META_STATUS_OFFSET        (BOOT_FLASH_META_OFFSET + 0U)
#define META_SIZE_OFFSET          (BOOT_FLASH_META_OFFSET + 4U)

/* --- Application boot image format stored at BOOT_FLASH_IMAGE_OFFSET --- */
#define BOOT_IMAGE_MAGIC          0x31494142U /* "BAI1" */
#define BOOT_IMAGE_VERSION        1U
#define BOOT_IMAGE_HEADER_SIZE    24U
#define BOOT_IMAGE_SEGMENT_SIZE   20U
#define BOOT_IMAGE_MAX_SEGMENTS   4U

#define BOOT_SEG_LOAD_IMEM        1U
#define BOOT_SEG_LOAD_DMEM        2U
#define BOOT_SEG_ZERO_DMEM        3U

#define APP_IMEM_ORIGIN           0x01100000U
#define APP_IMEM_SIZE             0x00010000U
#define APP_DMEM_ORIGIN           0x00000000U
#define APP_DMEM_SIZE             0x0000E000U

/* ========================================================================== */
/* DATA STRUCTURES                                                            */
/* ========================================================================== */
typedef enum {
    STATE_WAIT_SOF,
    STATE_WAIT_HEADER,
    STATE_WAIT_PAYLOAD,
    STATE_WAIT_CRC,
    STATE_WAIT_EOF
} BootState_t;

typedef struct {
    uint8_t  seq;
    uint8_t  cmd;
    uint16_t len;
    uint8_t  payload[MAX_PAYLOAD_SIZE];
    uint16_t crc_received;
} BootFrame_t;

typedef struct {
    uint32_t kind;
    uint32_t flags;
    uint32_t flash_offset;
    uint32_t dst_addr;
    uint32_t size;
} BootImageSegment_t;

#endif /* BOOT_H */
