#ifndef WEIGHT_HYPERRAM_LOADER_H
#define WEIGHT_HYPERRAM_LOADER_H

#include <stdbool.h>
#include <stdint.h>

#include "weight_receiver.h"

#define WEIGHT_HYPERRAM_BANK_0 0U
#define WEIGHT_HYPERRAM_BANK_1 1U

/* ==========================================================================
 * User Editable Config
 * --------------------------------------------------------------------------
 * Change this block when a model uses a different flash source, HyperRAM bank,
 * HyperRAM destination range, or per-port timing.
 * ========================================================================== */

/* Destination HyperRAM chip: WEIGHT_HYPERRAM_BANK_0 or WEIGHT_HYPERRAM_BANK_1. */
#ifndef WEIGHT_HYPERRAM_BANK
#define WEIGHT_HYPERRAM_BANK                       WEIGHT_HYPERRAM_BANK_0
#endif

/* Flash source map. Use metadata after UART weight update, or manual values. */
#ifndef WEIGHT_HYPERRAM_USE_FLASH_METADATA
#define WEIGHT_HYPERRAM_USE_FLASH_METADATA         1U
#endif

#ifndef WEIGHT_HYPERRAM_METADATA_OFFSET_ADDR
#define WEIGHT_HYPERRAM_METADATA_OFFSET_ADDR       WEIGHTS_METADATA_OFFSET_ADDR
#endif

#ifndef WEIGHT_HYPERRAM_MANUAL_FLASH_OFFSET
#define WEIGHT_HYPERRAM_MANUAL_FLASH_OFFSET        WEIGHTS_FLASH_OFFSET
#endif

#ifndef WEIGHT_HYPERRAM_MANUAL_FLASH_SIZE
#define WEIGHT_HYPERRAM_MANUAL_FLASH_SIZE          0U
#endif

#ifndef WEIGHT_HYPERRAM_MANUAL_CRC32
#define WEIGHT_HYPERRAM_MANUAL_CRC32               0U
#endif

/*
 * Model HyperRAM destination map. End address is exclusive.
 * The payload may contain weights, biases, and metadata in one contiguous blob.
 */
#ifndef WEIGHT_HYPERRAM_DRAM_BASE_ADDR
#define WEIGHT_HYPERRAM_DRAM_BASE_ADDR             0x00000000U
#endif

#ifndef WEIGHT_HYPERRAM_DRAM_END_ADDR
#define WEIGHT_HYPERRAM_DRAM_END_ADDR              0x00200000U
#endif

/*
 * Transfer behavior. W957A8MFYA5I is a 16-bit HyperRAM, so keep every
 * transaction start address even. 256 bytes is intentionally conservative:
 * it is far below the 255-halfword hardware maximum and keeps chunk starts
 * aligned to clean boundaries.
 */
#ifndef WEIGHT_HYPERRAM_COPY_CHUNK_BYTES
#define WEIGHT_HYPERRAM_COPY_CHUNK_BYTES           256U
#endif

#ifndef WEIGHT_HYPERRAM_VERIFY_FLASH_TO_HRAM
#define WEIGHT_HYPERRAM_VERIFY_FLASH_TO_HRAM       1U
#endif

#ifndef WEIGHT_HYPERRAM_LOG_ENABLED
#define WEIGHT_HYPERRAM_LOG_ENABLED                1U
#endif

/* Bytes to dump around the first mismatch when CRC verification fails. */
#ifndef WEIGHT_HYPERRAM_DEBUG_DUMP_BYTES
#define WEIGHT_HYPERRAM_DEBUG_DUMP_BYTES           64U
#endif

/* Bytes to dump from both Flash and HyperRAM after a successful verify. */
#ifndef WEIGHT_HYPERRAM_SUCCESS_DUMP_BYTES
#define WEIGHT_HYPERRAM_SUCCESS_DUMP_BYTES         64U
#endif

#ifndef WEIGHT_HYPERRAM_READY_TIMEOUT
#define WEIGHT_HYPERRAM_READY_TIMEOUT              10000000U
#endif

/* Separate timing knobs for each HyperRAM chip and access direction. */
#ifndef WEIGHT_HYPERRAM0_WRITE_CAPTURE_SHMOO
#define WEIGHT_HYPERRAM0_WRITE_CAPTURE_SHMOO       2U
#endif

#ifndef WEIGHT_HYPERRAM0_WRITE_RECOVERY
#define WEIGHT_HYPERRAM0_WRITE_RECOVERY            0U
#endif

#ifndef WEIGHT_HYPERRAM0_WRITE_LATENCY
#define WEIGHT_HYPERRAM0_WRITE_LATENCY             7U
#endif

#ifndef WEIGHT_HYPERRAM0_READ_CAPTURE_SHMOO
#define WEIGHT_HYPERRAM0_READ_CAPTURE_SHMOO        2U
#endif

#ifndef WEIGHT_HYPERRAM0_READ_RECOVERY
#define WEIGHT_HYPERRAM0_READ_RECOVERY             0U
#endif

#ifndef WEIGHT_HYPERRAM0_READ_LATENCY
#define WEIGHT_HYPERRAM0_READ_LATENCY              7U
#endif

#ifndef WEIGHT_HYPERRAM1_WRITE_CAPTURE_SHMOO
#define WEIGHT_HYPERRAM1_WRITE_CAPTURE_SHMOO       2U
#endif

#ifndef WEIGHT_HYPERRAM1_WRITE_RECOVERY
#define WEIGHT_HYPERRAM1_WRITE_RECOVERY            0U
#endif

#ifndef WEIGHT_HYPERRAM1_WRITE_LATENCY
#define WEIGHT_HYPERRAM1_WRITE_LATENCY             7U
#endif

#ifndef WEIGHT_HYPERRAM1_READ_CAPTURE_SHMOO
#define WEIGHT_HYPERRAM1_READ_CAPTURE_SHMOO        1U
#endif

#ifndef WEIGHT_HYPERRAM1_READ_RECOVERY
#define WEIGHT_HYPERRAM1_READ_RECOVERY             0U
#endif

#ifndef WEIGHT_HYPERRAM1_READ_LATENCY
#define WEIGHT_HYPERRAM1_READ_LATENCY              7U
#endif

/* ============================ End User Config ============================ */

typedef struct {
    uint8_t bank;
    uint32_t flash_offset;
    uint32_t flash_size;
    uint32_t flash_crc32;
    uint32_t dram_base;
    uint32_t dram_end;
} WeightHyperRAM_LoadInfo_t;

bool WeightHyperRAM_LoadWeightsFromFlash(void);
bool WeightHyperRAM_LoadWeightsFromFlashEx(WeightHyperRAM_LoadInfo_t *info_out);
bool WeightHyperRAM_LoadWeightsFromFlashMetadata(uint32_t metadata_offset,
                                                 WeightHyperRAM_LoadInfo_t *info_out);
void WeightHyperRAM_RunFlashToHyperRAMLoader(void);
void WeightHyperRAM_RunFlashToHyperRAMLoaderMetadata(uint32_t metadata_offset);
bool WeightHyperRAM_WriteBuffer(uint32_t dram_addr, const uint8_t *data, uint32_t size);
bool WeightHyperRAM_ReadBuffer(uint32_t dram_addr, uint8_t *data, uint32_t size);
bool WeightHyperRAM_Crc32(uint32_t dram_addr, uint32_t size, uint32_t *crc32_out);
bool WeightHyperRAM_VerifyFlashToHyperRAM(const WeightHyperRAM_LoadInfo_t *info,
                                          uint32_t *flash_crc32_out,
                                          uint32_t *hram_crc32_out);

#endif
