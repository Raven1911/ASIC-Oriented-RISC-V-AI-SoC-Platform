#ifndef VIDEO_STREAMING_DRIVER_H
#define VIDEO_STREAMING_DRIVER_H

#include <soc_hal.h>
#include <stdint.h>
#include <stdbool.h>

/*
 * AXI-Lite base address of the video/resize block.
 *
 * All offsets below are 32-bit word offsets, not byte offsets:
 *   register_address = VIDEO_STREAMING_BASE_ADDR + offset * 4
 */
#define VIDEO_STREAMING_BASE_ADDR 0x02008000U

/*
 * Runtime register map matched to video_streaming_axi_lite_core.v.
 *
 * 0: resize configuration      [7:0] out_size, [15:8] scaled_h,
 *                              [23:16] pad_top, [24] output_bgr
 * 1: output pixel count        out_size * out_size
 * 2: X resize step             Q16.16, floor((IN_W << 16) / out_size)
 * 3: Y resize step             Q16.16, floor((IN_H << 16) / scaled_h)
 * 4: control                   [0] enable, [1] grant_request
 * 5: preprocessing LUT write   [1:0] channel, [9:2] addr,
 *                              [17:10] int8 data, [31] write pulse
 */
#define VIDEO_STREAMING_RESIZE_CFG_OFFSET 0x00U
#define VIDEO_STREAMING_OUT_PIXELS_OFFSET 0x01U
#define VIDEO_STREAMING_X_STEP_OFFSET     0x02U
#define VIDEO_STREAMING_Y_STEP_OFFSET     0x03U
#define VIDEO_STREAMING_CONTROL_OFFSET    0x04U
#define VIDEO_STREAMING_LUT_WRITE_OFFSET  0x05U

#define VIDEO_STREAMING_OUT_SIZE_Pos 0U
#define VIDEO_STREAMING_OUT_SIZE_Msk (0xFFU << VIDEO_STREAMING_OUT_SIZE_Pos)
#define VIDEO_STREAMING_SCALED_H_Pos 8U
#define VIDEO_STREAMING_SCALED_H_Msk (0xFFU << VIDEO_STREAMING_SCALED_H_Pos)
#define VIDEO_STREAMING_PAD_TOP_Pos 16U
#define VIDEO_STREAMING_PAD_TOP_Msk (0xFFU << VIDEO_STREAMING_PAD_TOP_Pos)
#define VIDEO_STREAMING_OUTPUT_BGR_Pos 24U
#define VIDEO_STREAMING_OUTPUT_BGR_Msk (0x1U << VIDEO_STREAMING_OUTPUT_BGR_Pos)

#define VIDEO_STREAMING_ENABLE_Pos 0U
#define VIDEO_STREAMING_ENABLE_Msk (0x1U << VIDEO_STREAMING_ENABLE_Pos)
#define VIDEO_STREAMING_GRANT_REQUEST_Pos 1U
#define VIDEO_STREAMING_GRANT_REQUEST_Msk (0x1U << VIDEO_STREAMING_GRANT_REQUEST_Pos)

#define VIDEO_STREAMING_LUT_CHANNEL_Pos 0U
#define VIDEO_STREAMING_LUT_CHANNEL_Msk (0x3U << VIDEO_STREAMING_LUT_CHANNEL_Pos)
#define VIDEO_STREAMING_LUT_ADDR_Pos 2U
#define VIDEO_STREAMING_LUT_ADDR_Msk (0xFFU << VIDEO_STREAMING_LUT_ADDR_Pos)
#define VIDEO_STREAMING_LUT_DATA_Pos 10U
#define VIDEO_STREAMING_LUT_DATA_Msk (0xFFU << VIDEO_STREAMING_LUT_DATA_Pos)
#define VIDEO_STREAMING_LUT_WRITE_Pos 31U
#define VIDEO_STREAMING_LUT_WRITE_Msk (0x1U << VIDEO_STREAMING_LUT_WRITE_Pos)

/*
 * Common resize presets for the current 640x480 camera input.
 *
 * The hardware counters are 8-bit, so out_size must be <= 255 unless the RTL
 * counters are widened later. These values should be written before enabling
 * video streaming and kept stable until the frame has finished.
 */
#define VIDEO_STREAMING_96_OUT_SIZE   96U
#define VIDEO_STREAMING_96_OUT_PIXELS 9216U
#define VIDEO_STREAMING_96_SCALED_H   72U
#define VIDEO_STREAMING_96_PAD_TOP    12U
#define VIDEO_STREAMING_96_X_STEP     436906U
#define VIDEO_STREAMING_96_Y_STEP     436906U

#define VIDEO_STREAMING_160_OUT_SIZE   160U
#define VIDEO_STREAMING_160_OUT_PIXELS 25600U
#define VIDEO_STREAMING_160_SCALED_H   120U
#define VIDEO_STREAMING_160_PAD_TOP    20U
#define VIDEO_STREAMING_160_X_STEP     262144U
#define VIDEO_STREAMING_160_Y_STEP     262144U

#define VIDEO_STREAMING_DEFAULT_OUT_SIZE   VIDEO_STREAMING_96_OUT_SIZE
#define VIDEO_STREAMING_DEFAULT_OUT_PIXELS VIDEO_STREAMING_96_OUT_PIXELS
#define VIDEO_STREAMING_DEFAULT_SCALED_H   VIDEO_STREAMING_96_SCALED_H
#define VIDEO_STREAMING_DEFAULT_PAD_TOP    VIDEO_STREAMING_96_PAD_TOP
#define VIDEO_STREAMING_DEFAULT_X_STEP     VIDEO_STREAMING_96_X_STEP
#define VIDEO_STREAMING_DEFAULT_Y_STEP     VIDEO_STREAMING_96_Y_STEP
#define VIDEO_STREAMING_DEFAULT_OUTPUT_BGR false

/*
 * Compatibility constants for old firmware that configured:
 *   q = clamp_int8(round_shift(pixel * scale_mult, scale_shift) + zero_point)
 *
 * New RTL no longer has multiplier/shift/zp ports. The driver converts these
 * constants into 3 identical 256-entry LUTs and writes them through REG5.
 */
#define VIDEO_STREAMING_DEFAULT_SCALE_MULT  714582423
#define VIDEO_STREAMING_DEFAULT_SCALE_SHIFT 25U
#define VIDEO_STREAMING_DEFAULT_ZERO_POINT  ((int8_t)0)

typedef enum {
    VIDEO_STREAMING_LUT_R = 0U,
    VIDEO_STREAMING_LUT_G = 1U,
    VIDEO_STREAMING_LUT_B = 2U
} VideoStreaming_LutChannel_t;

typedef struct {
    uint8_t  out_size;
    uint32_t out_pixels;
    uint8_t  scaled_h;
    uint8_t  pad_top;
    uint32_t x_step;
    uint32_t y_step;
    bool     output_bgr;
} VideoStreaming_ResizeConfig_t;

typedef struct {
    uint8_t shift;
    int32_t mult_r;
    int32_t mult_g;
    int32_t mult_b;
    int64_t offset_r;
    int64_t offset_g;
    int64_t offset_b;
} VideoStreaming_PreprocessConfig_t;

typedef struct {
    volatile uint32_t *base_ptr;

    /*
     * Shadow values for the legacy quantization API.
     *
     * The new RTL stores final int8 results in LUT RAM, so multiplier/shift/zp
     * are not readable from hardware anymore. These fields let old code save
     * and restore its quantization settings without changing the app layer.
     */
    int32_t legacy_scale_multiplier;
    uint8_t legacy_scale_shift;
    int8_t legacy_zero_point;
} VideoStreaming_Driver_t;

extern VideoStreaming_Driver_t video_streaming;

void VideoStreaming_init(VideoStreaming_Driver_t *drv, uint32_t base_addr);
void VideoStreaming_begin(void);

void VideoStreaming_write_reg(VideoStreaming_Driver_t *drv, uint32_t offset, uint32_t value);
uint32_t VideoStreaming_read_reg(VideoStreaming_Driver_t *drv, uint32_t offset);

void VideoStreaming_set_resize_config(VideoStreaming_Driver_t *drv, const VideoStreaming_ResizeConfig_t *config);
void VideoStreaming_get_resize_config(VideoStreaming_Driver_t *drv, VideoStreaming_ResizeConfig_t *config);
void VideoStreaming_load_default_resize_config(VideoStreaming_Driver_t *drv);

void VideoStreaming_set_preprocessing_lut_entry(VideoStreaming_Driver_t *drv,
                                                VideoStreaming_LutChannel_t channel,
                                                uint8_t addr,
                                                int8_t data);
void VideoStreaming_program_preprocessing_luts(VideoStreaming_Driver_t *drv,
                                               const VideoStreaming_PreprocessConfig_t *config);
void VideoStreaming_program_legacy_quantization_lut(VideoStreaming_Driver_t *drv,
                                                    int32_t multiplier,
                                                    uint8_t shift,
                                                    int8_t zero_point);

void VideoStreaming_set_scale_multiplier(VideoStreaming_Driver_t *drv, int32_t multiplier);
int32_t VideoStreaming_get_scale_multiplier(VideoStreaming_Driver_t *drv);

void VideoStreaming_set_scale_shift(VideoStreaming_Driver_t *drv, uint8_t shift);
uint8_t VideoStreaming_get_scale_shift(VideoStreaming_Driver_t *drv);

void VideoStreaming_set_zero_point(VideoStreaming_Driver_t *drv, int8_t zero_point);
int8_t VideoStreaming_get_zero_point(VideoStreaming_Driver_t *drv);

void VideoStreaming_set_quantization(VideoStreaming_Driver_t *drv, int32_t multiplier, uint8_t shift, int8_t zero_point);
void VideoStreaming_load_defaults(VideoStreaming_Driver_t *drv);

void VideoStreaming_enable(VideoStreaming_Driver_t *drv, bool enable);
bool VideoStreaming_is_enabled(VideoStreaming_Driver_t *drv);

void VideoStreaming_set_grant_request(VideoStreaming_Driver_t *drv, bool enable);
bool VideoStreaming_get_grant_request(VideoStreaming_Driver_t *drv);

#endif // VIDEO_STREAMING_DRIVER_H
