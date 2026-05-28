#ifndef SQUEEZENET1_1_IMAGENET_ACCEL_H
#define SQUEEZENET1_1_IMAGENET_ACCEL_H

#include <stdbool.h>
#include <stdint.h>

#define SQUEEZENET1_1_IMAGENET_INPUT_IFMAP_ADDR   0U
#define SQUEEZENET1_1_IMAGENET_INPUT_IFMAP_BYTES  150528U
#define SQUEEZENET1_1_IMAGENET_INPUT_RAW_BYTES    150528U
#define SQUEEZENET1_1_IMAGENET_INPUT_HEIGHT       224U
#define SQUEEZENET1_1_IMAGENET_INPUT_WIDTH        224U
#define SQUEEZENET1_1_IMAGENET_INPUT_CHANNELS     3U
#define SQUEEZENET1_1_IMAGENET_INPUT_ROW_STRIDE   224U

#define SQUEEZENET1_1_IMAGENET_FINAL_OFMAP_ADDR  4477760U
#define SQUEEZENET1_1_IMAGENET_FINAL_OFMAP_BYTES 182000U
#define SQUEEZENET1_1_IMAGENET_FINAL_OFMAP_RAW_BYTES 169000U
#define SQUEEZENET1_1_IMAGENET_FINAL_CHANNELS    1000U

/*
 * Generated accelerator path. Before calling RunPreparedInput, place the
 * model input tensor in HyperRAM1 at the generated layer-1 IFBADDR and
 * load the generated packed weight blob into HyperRAM0 at offset 0.
 * Static-image helper copies a preprocessed CHW int8 IFMAP from SPI flash into HyperRAM1.
 */
bool Squeezenet11Imagenet_Accel_RunTimingOnly(void);
bool Squeezenet11Imagenet_Accel_RunPreparedInput(int32_t *logits_out, uint32_t logits_count);
bool Squeezenet11Imagenet_Accel_RunStaticImageFromFlash(void);
uint32_t Squeezenet11Imagenet_Accel_FinalOfmapAddr(void);
uint32_t Squeezenet11Imagenet_Accel_FinalOfmapBytes(void);

#endif /* SQUEEZENET1_1_IMAGENET_ACCEL_H */
