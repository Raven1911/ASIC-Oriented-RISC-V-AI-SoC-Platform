#include "VideoStreaming_Driver.h"

#ifdef HAL_VIDEO_STREAMING_MODULE_ENABLED

VideoStreaming_Driver_t video_streaming;

static int8_t VideoStreaming_clamp_i64_to_i8(int64_t value)
{
    if (value > 127) {
        return (int8_t)127;
    }
    if (value < -128) {
        return (int8_t)-128;
    }

    return (int8_t)value;
}

static int64_t VideoStreaming_round_shift_i64(int64_t value, uint8_t shift)
{
    int64_t round_value;

    if (shift > 63U) {
        shift = 63U;
    }

    if (shift == 0U) {
        return value;
    }

    /*
     * Match the RTL/testbench rounding rule:
     *   stage3 = value + (1 << (shift - 1)) - ((value < 0) ? 1 : 0)
     *   result = stage3 >>> shift
     *
     * The subtract-1 term keeps negative values rounded the same way as the
     * signed arithmetic shifter in Verilog.
     */
    round_value = ((int64_t)1) << (shift - 1U);
    value = value + round_value - ((value < 0) ? 1 : 0);

    return value >> shift;
}

static int8_t VideoStreaming_calc_preprocess_entry(uint8_t pixel,
                                                   int32_t mult,
                                                   int64_t offset,
                                                   uint8_t shift)
{
    int64_t stage1 = (int64_t)pixel * (int64_t)mult;
    int64_t stage2 = stage1 + offset;
    int64_t stage3 = VideoStreaming_round_shift_i64(stage2, shift);

    return VideoStreaming_clamp_i64_to_i8(stage3);
}

static int8_t VideoStreaming_calc_legacy_quant_entry(uint8_t pixel,
                                                     int32_t multiplier,
                                                     uint8_t shift,
                                                     int8_t zero_point)
{
    int64_t scaled = (int64_t)pixel * (int64_t)multiplier;
    int64_t shifted = VideoStreaming_round_shift_i64(scaled, shift);

    shifted += (int64_t)zero_point;

    return VideoStreaming_clamp_i64_to_i8(shifted);
}

static uint32_t VideoStreaming_pack_resize_cfg(const VideoStreaming_ResizeConfig_t *config)
{
    uint32_t value = 0U;

    value |= ((uint32_t)config->out_size << VIDEO_STREAMING_OUT_SIZE_Pos) & VIDEO_STREAMING_OUT_SIZE_Msk;
    value |= ((uint32_t)config->scaled_h << VIDEO_STREAMING_SCALED_H_Pos) & VIDEO_STREAMING_SCALED_H_Msk;
    value |= ((uint32_t)config->pad_top << VIDEO_STREAMING_PAD_TOP_Pos) & VIDEO_STREAMING_PAD_TOP_Msk;
    if (config->output_bgr) {
        value |= VIDEO_STREAMING_OUTPUT_BGR_Msk;
    }

    return value;
}

void VideoStreaming_init(VideoStreaming_Driver_t *drv, uint32_t base_addr)
{
    drv->base_ptr = (volatile uint32_t *)base_addr;
    drv->legacy_scale_multiplier = VIDEO_STREAMING_DEFAULT_SCALE_MULT;
    drv->legacy_scale_shift = VIDEO_STREAMING_DEFAULT_SCALE_SHIFT;
    drv->legacy_zero_point = VIDEO_STREAMING_DEFAULT_ZERO_POINT;
}

void VideoStreaming_begin(void)
{
    VideoStreaming_init(&video_streaming, VIDEO_STREAMING_BASE_ADDR);
}

void VideoStreaming_write_reg(VideoStreaming_Driver_t *drv, uint32_t offset, uint32_t value)
{
    drv->base_ptr[offset] = value;
}

uint32_t VideoStreaming_read_reg(VideoStreaming_Driver_t *drv, uint32_t offset)
{
    return drv->base_ptr[offset];
}

void VideoStreaming_set_resize_config(VideoStreaming_Driver_t *drv, const VideoStreaming_ResizeConfig_t *config)
{
    if (config == 0) {
        return;
    }

    /*
     * Write these while video is disabled or idle. The RTL expects all resize
     * registers to remain stable during a frame.
     */
    VideoStreaming_write_reg(drv, VIDEO_STREAMING_RESIZE_CFG_OFFSET, VideoStreaming_pack_resize_cfg(config));
    VideoStreaming_write_reg(drv, VIDEO_STREAMING_OUT_PIXELS_OFFSET, config->out_pixels);
    VideoStreaming_write_reg(drv, VIDEO_STREAMING_X_STEP_OFFSET, config->x_step);
    VideoStreaming_write_reg(drv, VIDEO_STREAMING_Y_STEP_OFFSET, config->y_step);
}

void VideoStreaming_get_resize_config(VideoStreaming_Driver_t *drv, VideoStreaming_ResizeConfig_t *config)
{
    uint32_t resize_cfg;

    if (config == 0) {
        return;
    }

    resize_cfg = VideoStreaming_read_reg(drv, VIDEO_STREAMING_RESIZE_CFG_OFFSET);

    config->out_size = (uint8_t)((resize_cfg & VIDEO_STREAMING_OUT_SIZE_Msk) >> VIDEO_STREAMING_OUT_SIZE_Pos);
    config->scaled_h = (uint8_t)((resize_cfg & VIDEO_STREAMING_SCALED_H_Msk) >> VIDEO_STREAMING_SCALED_H_Pos);
    config->pad_top = (uint8_t)((resize_cfg & VIDEO_STREAMING_PAD_TOP_Msk) >> VIDEO_STREAMING_PAD_TOP_Pos);
    config->output_bgr = (resize_cfg & VIDEO_STREAMING_OUTPUT_BGR_Msk) != 0U;
    config->out_pixels = VideoStreaming_read_reg(drv, VIDEO_STREAMING_OUT_PIXELS_OFFSET);
    config->x_step = VideoStreaming_read_reg(drv, VIDEO_STREAMING_X_STEP_OFFSET);
    config->y_step = VideoStreaming_read_reg(drv, VIDEO_STREAMING_Y_STEP_OFFSET);
}

void VideoStreaming_load_default_resize_config(VideoStreaming_Driver_t *drv)
{
    const VideoStreaming_ResizeConfig_t config = {
        VIDEO_STREAMING_DEFAULT_OUT_SIZE,
        VIDEO_STREAMING_DEFAULT_OUT_PIXELS,
        VIDEO_STREAMING_DEFAULT_SCALED_H,
        VIDEO_STREAMING_DEFAULT_PAD_TOP,
        VIDEO_STREAMING_DEFAULT_X_STEP,
        VIDEO_STREAMING_DEFAULT_Y_STEP,
        VIDEO_STREAMING_DEFAULT_OUTPUT_BGR
    };

    VideoStreaming_set_resize_config(drv, &config);
}

void VideoStreaming_set_preprocessing_lut_entry(VideoStreaming_Driver_t *drv,
                                                VideoStreaming_LutChannel_t channel,
                                                uint8_t addr,
                                                int8_t data)
{
    uint32_t value;

    /*
     * REG5 is a write-only command register in the RTL. One 32-bit store with
     * bit31=1 produces one-cycle preproc_lut_wr_en_i and writes one entry.
     *
     * Channel:
     *   0 = R, 1 = G, 2 = B. Channel 3 is ignored by RTL.
     *
     * Data is int8, but packed as its raw two's-complement byte.
     */
    value = VIDEO_STREAMING_LUT_WRITE_Msk;
    value |= (((uint32_t)channel << VIDEO_STREAMING_LUT_CHANNEL_Pos) & VIDEO_STREAMING_LUT_CHANNEL_Msk);
    value |= (((uint32_t)addr << VIDEO_STREAMING_LUT_ADDR_Pos) & VIDEO_STREAMING_LUT_ADDR_Msk);
    value |= (((uint32_t)(uint8_t)data << VIDEO_STREAMING_LUT_DATA_Pos) & VIDEO_STREAMING_LUT_DATA_Msk);

    VideoStreaming_write_reg(drv, VIDEO_STREAMING_LUT_WRITE_OFFSET, value);
}

void VideoStreaming_program_preprocessing_luts(VideoStreaming_Driver_t *drv,
                                               const VideoStreaming_PreprocessConfig_t *config)
{
    uint32_t pixel;
    int8_t lut_r;
    int8_t lut_g;
    int8_t lut_b;

    if (config == 0) {
        return;
    }

    /*
     * CPU only needs to run this once after reset or when the model's
     * preprocessing constants change. Do not call this while resize is reading
     * a frame, because the LUT RAM is also used by the image pipeline.
     */
    for (pixel = 0U; pixel < 256U; pixel++) {
        lut_r = VideoStreaming_calc_preprocess_entry((uint8_t)pixel,
                                                     config->mult_r,
                                                     config->offset_r,
                                                     config->shift);
        lut_g = VideoStreaming_calc_preprocess_entry((uint8_t)pixel,
                                                     config->mult_g,
                                                     config->offset_g,
                                                     config->shift);
        lut_b = VideoStreaming_calc_preprocess_entry((uint8_t)pixel,
                                                     config->mult_b,
                                                     config->offset_b,
                                                     config->shift);

        VideoStreaming_set_preprocessing_lut_entry(drv, VIDEO_STREAMING_LUT_R, (uint8_t)pixel, lut_r);
        VideoStreaming_set_preprocessing_lut_entry(drv, VIDEO_STREAMING_LUT_G, (uint8_t)pixel, lut_g);
        VideoStreaming_set_preprocessing_lut_entry(drv, VIDEO_STREAMING_LUT_B, (uint8_t)pixel, lut_b);
    }
}

void VideoStreaming_program_legacy_quantization_lut(VideoStreaming_Driver_t *drv,
                                                    int32_t multiplier,
                                                    uint8_t shift,
                                                    int8_t zero_point)
{
    uint32_t pixel;
    int8_t value;

    /*
     * Compatibility path for the old single multiplier/shift/zp interface.
     * The same 256-entry curve is written to R/G/B, reproducing the old
     * channel-independent quantization behavior without hardware multipliers.
     */
    for (pixel = 0U; pixel < 256U; pixel++) {
        value = VideoStreaming_calc_legacy_quant_entry((uint8_t)pixel,
                                                       multiplier,
                                                       shift,
                                                       zero_point);

        VideoStreaming_set_preprocessing_lut_entry(drv, VIDEO_STREAMING_LUT_R, (uint8_t)pixel, value);
        VideoStreaming_set_preprocessing_lut_entry(drv, VIDEO_STREAMING_LUT_G, (uint8_t)pixel, value);
        VideoStreaming_set_preprocessing_lut_entry(drv, VIDEO_STREAMING_LUT_B, (uint8_t)pixel, value);
    }
}

void VideoStreaming_set_scale_multiplier(VideoStreaming_Driver_t *drv, int32_t multiplier)
{
    drv->legacy_scale_multiplier = multiplier;
    VideoStreaming_program_legacy_quantization_lut(drv,
                                                   drv->legacy_scale_multiplier,
                                                   drv->legacy_scale_shift,
                                                   drv->legacy_zero_point);
}

int32_t VideoStreaming_get_scale_multiplier(VideoStreaming_Driver_t *drv)
{
    return drv->legacy_scale_multiplier;
}

void VideoStreaming_set_scale_shift(VideoStreaming_Driver_t *drv, uint8_t shift)
{
    drv->legacy_scale_shift = shift & 0x3FU;
    VideoStreaming_program_legacy_quantization_lut(drv,
                                                   drv->legacy_scale_multiplier,
                                                   drv->legacy_scale_shift,
                                                   drv->legacy_zero_point);
}

uint8_t VideoStreaming_get_scale_shift(VideoStreaming_Driver_t *drv)
{
    return drv->legacy_scale_shift;
}

void VideoStreaming_set_zero_point(VideoStreaming_Driver_t *drv, int8_t zero_point)
{
    drv->legacy_zero_point = zero_point;
    VideoStreaming_program_legacy_quantization_lut(drv,
                                                   drv->legacy_scale_multiplier,
                                                   drv->legacy_scale_shift,
                                                   drv->legacy_zero_point);
}

int8_t VideoStreaming_get_zero_point(VideoStreaming_Driver_t *drv)
{
    return drv->legacy_zero_point;
}

void VideoStreaming_set_quantization(VideoStreaming_Driver_t *drv, int32_t multiplier, uint8_t shift, int8_t zero_point)
{
    drv->legacy_scale_multiplier = multiplier;
    drv->legacy_scale_shift = shift & 0x3FU;
    drv->legacy_zero_point = zero_point;

    VideoStreaming_program_legacy_quantization_lut(drv,
                                                   drv->legacy_scale_multiplier,
                                                   drv->legacy_scale_shift,
                                                   drv->legacy_zero_point);
}

void VideoStreaming_load_defaults(VideoStreaming_Driver_t *drv)
{
    VideoStreaming_load_default_resize_config(drv);
    VideoStreaming_set_quantization(drv,
                                    VIDEO_STREAMING_DEFAULT_SCALE_MULT,
                                    VIDEO_STREAMING_DEFAULT_SCALE_SHIFT,
                                    VIDEO_STREAMING_DEFAULT_ZERO_POINT);
    VideoStreaming_enable(drv, true);
    VideoStreaming_set_grant_request(drv, false);
}

void VideoStreaming_enable(VideoStreaming_Driver_t *drv, bool enable)
{
    uint32_t control = VideoStreaming_read_reg(drv, VIDEO_STREAMING_CONTROL_OFFSET);

    if (enable) {
        control |= VIDEO_STREAMING_ENABLE_Msk;
    } else {
        control &= ~VIDEO_STREAMING_ENABLE_Msk;
    }

    VideoStreaming_write_reg(drv, VIDEO_STREAMING_CONTROL_OFFSET, control);
}

bool VideoStreaming_is_enabled(VideoStreaming_Driver_t *drv)
{
    return (VideoStreaming_read_reg(drv, VIDEO_STREAMING_CONTROL_OFFSET) & VIDEO_STREAMING_ENABLE_Msk) != 0U;
}

void VideoStreaming_set_grant_request(VideoStreaming_Driver_t *drv, bool enable)
{
    uint32_t control = VideoStreaming_read_reg(drv, VIDEO_STREAMING_CONTROL_OFFSET);

    if (enable) {
        control |= VIDEO_STREAMING_GRANT_REQUEST_Msk;
    } else {
        control &= ~VIDEO_STREAMING_GRANT_REQUEST_Msk;
    }

    VideoStreaming_write_reg(drv, VIDEO_STREAMING_CONTROL_OFFSET, control);
}

bool VideoStreaming_get_grant_request(VideoStreaming_Driver_t *drv)
{
    return (VideoStreaming_read_reg(drv, VIDEO_STREAMING_CONTROL_OFFSET) & VIDEO_STREAMING_GRANT_REQUEST_Msk) != 0U;
}

#endif // HAL_VIDEO_STREAMING_MODULE_ENABLED
