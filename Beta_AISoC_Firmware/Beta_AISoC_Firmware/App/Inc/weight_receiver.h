#ifndef WEIGHT_RECEIVER_H
#define WEIGHT_RECEIVER_H

#include <stdint.h>

/*
 * Bootloader flash map:
 *   0x00000000          : boot metadata sector
 *   0x00001000..~0x11000: application image, max 64KB
 *
 * Keep NNoM weights far away from that lower flash area. 2MB leaves a large
 * guard band for future boot/app growth while still leaving 14MB for weights.
 */
#define WEIGHTS_FLASH_OFFSET 0x00200000U
#define WEIGHTS_ALLCNN_FLASH_OFFSET 0x00200000U
#define WEIGHTS_ALLCNNC96_QAT_SYMPAD_FLASH_OFFSET 0x00400000U

/* Dedicated sector just before the default weight region. */
#define WEIGHTS_METADATA_OFFSET_ADDR 0x001FF000U
#define WEIGHTS_ALLCNN_METADATA_OFFSET_ADDR 0x001FF000U
#define WEIGHTS_ALLCNNC96_QAT_SYMPAD_METADATA_OFFSET_ADDR 0x001FE000U

/* Reject host-provided offsets below this guard boundary. */
#define WEIGHTS_FLASH_MIN_OFFSET 0x00200000U

#define WEIGHTS_METADATA_MAGIC 0x53544757U
#define WEIGHTS_METADATA_VERSION 1U

typedef struct {
    uint32_t magic;
    uint32_t version;
    uint32_t base_offset;
    uint32_t size;
    uint32_t crc32;
} WeightMetadata_t;

void WeightReceiver_RunFlashLoader(void);
void receive_and_flash_weights(void);

#endif
