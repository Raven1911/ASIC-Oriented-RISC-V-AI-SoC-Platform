#include "tinyalexnet_mnist.h"

#include <stdint.h>

#include "conv1_test_vectors.h"
#include "flash_utils.h"
#include "HyperRAM_Driver.h"
#include "UART_Driver.h"
#include "W95_HyperRAM.h"
#include "weight_hyperram_loader.h"

#define TINY_MNIST_INPUT_W              28U
#define TINY_MNIST_INPUT_H              28U
#define TINY_MNIST_INPUT_C              1U
#define TINY_KERNEL_3X3                 3U
#define TINY_CONV_PADDING_SAME          1U
#define TINY_POOL_KERNEL                2U
#define TINY_POOL_STRIDE                2U
#define TINY_MAX_ACTIVATION_BYTES       6272U
#define TINY_MAX_WEIGHT_BYTES           9216U
#define TINY_MAX_BIAS_BYTES             256U
#define TINY_MAX_BIAS_VALUES            64U
#define TINY_HYPERRAM_READ_CHUNK_BYTES  256U
#define TINY_FINAL_OUTPUT_COUNT         10U

typedef struct {
    const char *name;
    uint32_t weight_offset;
    uint32_t weight_size;
    uint32_t bias_offset;
    uint32_t bias_size;
    uint16_t input_w;
    uint16_t input_h;
    uint16_t input_c;
    uint16_t output_c;
    int32_t input_zp;
    int32_t output_zp;
    int32_t weight_zp;
    int32_t multiplier;
    int32_t shift;
} TinyConvLayer_t;

typedef struct {
    const char *name;
    uint32_t weight_offset;
    uint32_t weight_size;
    uint32_t bias_offset;
    uint32_t bias_size;
    uint16_t input_len;
    uint16_t output_len;
    int32_t input_zp;
    int32_t output_zp;
    int32_t weight_zp;
    int32_t multiplier;
    int32_t shift;
} TinyDenseLayer_t;

/*
 * TinyAlexNet MNIST blob map, copied from feature/nnom-custom:
 * App/Src/layer_metadata.c. Offsets are byte offsets inside the contiguous
 * weights.hex payload after command 2.2 copies it from SPI flash to HyperRAM0.
 */
static const TinyConvLayer_t tiny_conv_layers[] = {
    { "conv2d_1",   0U,    72U, 33608U,  32U, 28U, 28U,  1U,  8U, -128, -128, 0, 1584375552, 39 },
    { "conv2d_1_2", 72U, 1152U, 33640U,  64U, 14U, 14U,  8U, 16U, -128, -128, 0, 2060900352, 40 },
    { "conv2d_2_1", 1224U, 4608U, 33704U, 128U,  7U,  7U, 16U, 32U, -128, -128, 0, 1106776576, 39 },
    { "conv2d_3_1", 5832U, 9216U, 33832U, 128U,  7U,  7U, 32U, 32U, -128, -128, 0, 1298824320, 40 },
    { "conv2d_4_1", 15048U, 4608U, 33960U, 64U,  7U,  7U, 32U, 16U, -128, -128, 0, 1969629440, 40 },
};

static const TinyDenseLayer_t tiny_dense_layers[] = {
    { "dense_1",   19656U, 9216U, 34024U, 256U, 144U, 64U, -128, -128, 0, 1273516800, 39 },
    { "dense_1_2", 28872U, 4096U, 34280U, 256U,  64U, 64U, -128, -128, 0, 1902607104, 39 },
    { "dense_2_1", 32968U,  640U, 34536U,  40U,  64U, 10U, -128,   33, 0, 1438216832, 40 },
};

/*
 * Final Dense10 logits for the MNIST sample in conv1_test_vectors.c.
 * Generated on the host from feature/nnom-custom TFLite-extracted weights,
 * after validating Conv1..Conv5 against the branch TFLite golden outputs.
 * Regenerate this vector when weights.hex or the test input changes.
 */
static const int8_t tiny_final_golden_logits[TINY_FINAL_OUTPUT_COUNT] = {
    -37, 20, -19, 110, -81, 40, -116, -62, 61, 25
};

static int8_t tiny_act_a[TINY_MAX_ACTIVATION_BYTES];
static int8_t tiny_act_b[TINY_MAX_ACTIVATION_BYTES];
static uint8_t tiny_weight_bytes[TINY_MAX_WEIGHT_BYTES];
static uint8_t tiny_bias_bytes[TINY_MAX_BIAS_BYTES];
static int32_t tiny_bias[TINY_MAX_BIAS_VALUES];

static void print_u32_dec(uint32_t value)
{
    char text[11];
    uint32_t pos = 0U;

    if (value == 0U) {
        Uart_write('0');
        return;
    }

    while ((value > 0U) && (pos < sizeof(text))) {
        text[pos++] = (char)('0' + (value % 10U));
        value /= 10U;
    }

    while (pos > 0U) {
        Uart_write((uint8_t)text[--pos]);
    }
}

static void print_i32_dec(int32_t value)
{
    if (value < 0) {
        uint32_t magnitude = (uint32_t)(-(value + 1)) + 1U;

        Uart_write('-');
        print_u32_dec(magnitude);
    } else {
        print_u32_dec((uint32_t)value);
    }
}

static void print_hex32(uint32_t value)
{
    Uart_print_hex_32(value);
}

static int8_t saturate_i8(int32_t value)
{
    if (value > 127) {
        return 127;
    }

    if (value < -128) {
        return -128;
    }

    return (int8_t)value;
}

static int32_t read_i32_be(const uint8_t *data)
{
    uint32_t raw = ((uint32_t)data[0] << 24U) |
                   ((uint32_t)data[1] << 16U) |
                   ((uint32_t)data[2] << 8U) |
                   ((uint32_t)data[3]);

    return (int32_t)raw;
}

static int32_t requantize_i32_to_i8(int32_t acc, int32_t multiplier, int32_t shift, int32_t output_zp)
{
    int64_t scaled = (int64_t)acc * (int64_t)multiplier;
    int32_t requantized;

    if (shift > 0) {
        scaled += ((int64_t)1 << ((uint32_t)shift - 1U));
        requantized = (int32_t)(scaled >> (uint32_t)shift);
    } else {
        requantized = (int32_t)scaled;
    }

    return requantized + output_zp;
}

static void init_hyperram0_reader(W95_HandleTypeDef *w95)
{
    HyperRAM_init(&hyperram0, HYPERRAM_0_BASE_ADDR);
    W95_Init(w95,
             &hyperram0,
             WEIGHT_HYPERRAM0_READ_LATENCY,
             WEIGHT_HYPERRAM0_READ_RECOVERY,
             WEIGHT_HYPERRAM0_READ_CAPTURE_SHMOO);
}

static bool read_hyperram0_bytes(W95_HandleTypeDef *w95, uint32_t addr, uint8_t *data, uint32_t size)
{
    uint32_t done = 0U;

    if (((addr & 1U) != 0U) || ((size & 1U) != 0U)) {
        return false;
    }

    while (done < size) {
        uint32_t chunk = size - done;

        if (chunk > TINY_HYPERRAM_READ_CHUNK_BYTES) {
            chunk = TINY_HYPERRAM_READ_CHUNK_BYTES;
        }

        W95_MemoryRead(w95, addr + done, &data[done], chunk, true);
        done += chunk;
    }

    return true;
}

static bool load_conv_params(W95_HandleTypeDef *w95, const TinyConvLayer_t *layer)
{
    uint32_t bias_count = layer->bias_size / 4U;

    if ((layer->weight_size > TINY_MAX_WEIGHT_BYTES) ||
        (layer->bias_size > TINY_MAX_BIAS_BYTES) ||
        (bias_count > TINY_MAX_BIAS_VALUES)) {
        return false;
    }

    if (!read_hyperram0_bytes(w95, layer->weight_offset, tiny_weight_bytes, layer->weight_size)) {
        return false;
    }

    if (!read_hyperram0_bytes(w95, layer->bias_offset, tiny_bias_bytes, layer->bias_size)) {
        return false;
    }

    for (uint32_t i = 0U; i < bias_count; i++) {
        tiny_bias[i] = read_i32_be(&tiny_bias_bytes[i * 4U]);
    }

    return true;
}

static bool load_dense_params(W95_HandleTypeDef *w95, const TinyDenseLayer_t *layer)
{
    uint32_t bias_count = layer->bias_size / 4U;

    if ((layer->weight_size > TINY_MAX_WEIGHT_BYTES) ||
        (layer->bias_size > TINY_MAX_BIAS_BYTES) ||
        (bias_count > TINY_MAX_BIAS_VALUES)) {
        return false;
    }

    if (!read_hyperram0_bytes(w95, layer->weight_offset, tiny_weight_bytes, layer->weight_size)) {
        return false;
    }

    if (!read_hyperram0_bytes(w95, layer->bias_offset, tiny_bias_bytes, layer->bias_size)) {
        return false;
    }

    for (uint32_t i = 0U; i < bias_count; i++) {
        tiny_bias[i] = read_i32_be(&tiny_bias_bytes[i * 4U]);
    }

    return true;
}

static void print_layer_loaded(const char *name, uint32_t weight_offset, uint32_t bias_offset)
{
    Uart_print("  ");
    Uart_print(name);
    Uart_print(" params: W@0x");
    print_hex32(weight_offset);
    Uart_print(" B@0x");
    print_hex32(bias_offset);
    Uart_println("");
}

static void run_conv3x3_same_chw(const int8_t *input, int8_t *output, const TinyConvLayer_t *layer)
{
    uint32_t input_plane = (uint32_t)layer->input_h * (uint32_t)layer->input_w;
    uint32_t output_w = layer->input_w;
    uint32_t output_h = layer->input_h;
    uint32_t kernel_area = TINY_KERNEL_3X3 * TINY_KERNEL_3X3;

    for (uint32_t oc = 0U; oc < layer->output_c; oc++) {
        for (uint32_t y = 0U; y < output_h; y++) {
            for (uint32_t x = 0U; x < output_w; x++) {
                int32_t acc = tiny_bias[oc];

                for (uint32_t ic = 0U; ic < layer->input_c; ic++) {
                    for (uint32_t ky = 0U; ky < TINY_KERNEL_3X3; ky++) {
                        for (uint32_t kx = 0U; kx < TINY_KERNEL_3X3; kx++) {
                            int32_t in_y = (int32_t)y + (int32_t)ky - (int32_t)TINY_CONV_PADDING_SAME;
                            int32_t in_x = (int32_t)x + (int32_t)kx - (int32_t)TINY_CONV_PADDING_SAME;

                            if ((in_y >= 0) && (in_y < (int32_t)layer->input_h) &&
                                (in_x >= 0) && (in_x < (int32_t)layer->input_w)) {
                                uint32_t input_idx = (ic * input_plane) +
                                                     ((uint32_t)in_y * layer->input_w) +
                                                     (uint32_t)in_x;
                                uint32_t weight_idx = (oc * kernel_area * layer->input_c) +
                                                      (ky * TINY_KERNEL_3X3 * layer->input_c) +
                                                      (kx * layer->input_c) + ic;
                                int32_t input_value = (int32_t)input[input_idx];
                                int32_t weight_value = (int32_t)((int8_t)tiny_weight_bytes[weight_idx]);

                                acc += (input_value - layer->input_zp) *
                                       (weight_value - layer->weight_zp);
                            }
                        }
                    }
                }

                output[(oc * output_h * output_w) + (y * output_w) + x] =
                    saturate_i8(requantize_i32_to_i8(acc,
                                                     layer->multiplier,
                                                     layer->shift,
                                                     layer->output_zp));
            }
        }
    }
}

static void run_maxpool2x2_valid_chw(const int8_t *input,
                                     int8_t *output,
                                     uint32_t input_w,
                                     uint32_t input_h,
                                     uint32_t channels)
{
    uint32_t output_w = ((input_w - TINY_POOL_KERNEL) / TINY_POOL_STRIDE) + 1U;
    uint32_t output_h = ((input_h - TINY_POOL_KERNEL) / TINY_POOL_STRIDE) + 1U;
    uint32_t input_plane = input_w * input_h;
    uint32_t output_plane = output_w * output_h;

    for (uint32_t c = 0U; c < channels; c++) {
        for (uint32_t oy = 0U; oy < output_h; oy++) {
            for (uint32_t ox = 0U; ox < output_w; ox++) {
                int8_t max_value = -128;

                for (uint32_t ky = 0U; ky < TINY_POOL_KERNEL; ky++) {
                    for (uint32_t kx = 0U; kx < TINY_POOL_KERNEL; kx++) {
                        uint32_t iy = (oy * TINY_POOL_STRIDE) + ky;
                        uint32_t ix = (ox * TINY_POOL_STRIDE) + kx;
                        int8_t value = input[(c * input_plane) + (iy * input_w) + ix];

                        if (value > max_value) {
                            max_value = value;
                        }
                    }
                }

                output[(c * output_plane) + (oy * output_w) + ox] = max_value;
            }
        }
    }
}

static void flatten_chw_to_nhwc_vector(const int8_t *input,
                                       int8_t *output,
                                       uint32_t width,
                                       uint32_t height,
                                       uint32_t channels)
{
    uint32_t out_idx = 0U;
    uint32_t plane = width * height;

    for (uint32_t y = 0U; y < height; y++) {
        for (uint32_t x = 0U; x < width; x++) {
            for (uint32_t c = 0U; c < channels; c++) {
                output[out_idx++] = input[(c * plane) + (y * width) + x];
            }
        }
    }
}

static void run_dense(const int8_t *input, int8_t *output, const TinyDenseLayer_t *layer)
{
    for (uint32_t out = 0U; out < layer->output_len; out++) {
        int32_t acc = tiny_bias[out];

        for (uint32_t i = 0U; i < layer->input_len; i++) {
            int32_t input_value = (int32_t)input[i];
            int32_t weight_value = (int32_t)((int8_t)tiny_weight_bytes[(out * layer->input_len) + i]);

            acc += (input_value - layer->input_zp) *
                   (weight_value - layer->weight_zp);
        }

        output[out] = saturate_i8(requantize_i32_to_i8(acc,
                                                       layer->multiplier,
                                                       layer->shift,
                                                       layer->output_zp));
    }
}

static void copy_mnist_input_to_chw_buffer(void)
{
    /*
     * The test image is 28x28x1, so NHWC and CHW contain the same linear data.
     * Later camera input can replace this copy step after preprocessing to int8.
     */
    for (uint32_t i = 0U; i < CONV1_TEST_INPUT_SIZE; i++) {
        tiny_act_a[i] = conv1_test_input_nhwc[i];
    }
}

static void print_int8_vector(const char *label, const int8_t *values, uint32_t count)
{
    Uart_print(label);
    for (uint32_t i = 0U; i < count; i++) {
        Uart_write(' ');
        print_i32_dec((int32_t)values[i]);
    }
    Uart_println("");
}

static uint32_t argmax_i8(const int8_t *values, uint32_t count)
{
    uint32_t best_idx = 0U;
    int8_t best_value = values[0];

    for (uint32_t i = 1U; i < count; i++) {
        if (values[i] > best_value) {
            best_idx = i;
            best_value = values[i];
        }
    }

    return best_idx;
}

static bool compare_final_with_golden(const int8_t *logits)
{
    uint32_t mismatch_count = 0U;
    uint32_t first_mismatch = 0U;
    uint32_t predicted = argmax_i8(logits, TINY_FINAL_OUTPUT_COUNT);
    uint32_t golden_predicted = argmax_i8(tiny_final_golden_logits, TINY_FINAL_OUTPUT_COUNT);

    for (uint32_t i = 0U; i < TINY_FINAL_OUTPUT_COUNT; i++) {
        if (logits[i] != tiny_final_golden_logits[i]) {
            if (mismatch_count == 0U) {
                first_mismatch = i;
            }
            mismatch_count++;
        }
    }

    Uart_println("TinyAlexNet golden comparison:");
    print_int8_vector("  Golden logits int8:", tiny_final_golden_logits, TINY_FINAL_OUTPUT_COUNT);
    Uart_print("  Golden predicted digit: ");
    print_u32_dec(golden_predicted);
    Uart_println("");

    if ((mismatch_count == 0U) && (predicted == golden_predicted)) {
        Uart_println("  Result: PASS");
        return true;
    }

    Uart_println("  Result: FAILED");
    Uart_print("  Mismatch count: ");
    print_u32_dec(mismatch_count);
    Uart_println("");

    if (mismatch_count > 0U) {
        Uart_print("  First mismatch index: ");
        print_u32_dec(first_mismatch);
        Uart_println("");
        Uart_print("    Expected: ");
        print_i32_dec((int32_t)tiny_final_golden_logits[first_mismatch]);
        Uart_println("");
        Uart_print("    Actual  : ");
        print_i32_dec((int32_t)logits[first_mismatch]);
        Uart_println("");
    }

    return false;
}

bool TinyAlexNetMNIST_RunFromHyperRAM0(void)
{
    W95_HandleTypeDef w95_chip0;

    Uart_println("");
    Uart_println("=======================================================");
    Uart_println("    STARTING TINYALEXNET MNIST FROM HYPERRAM0");
    Uart_println("=======================================================");
    Uart_println("Prerequisite: run 2.2 first to load TinyAlexNet weights into HyperRAM0.");
    Uart_println("Model: Conv8-Pool-Conv16-Pool-Conv32-Conv32-Conv16-Pool-Dense64-Dense64-Dense10");

    init_hyperram0_reader(&w95_chip0);
    copy_mnist_input_to_chw_buffer();

    if (!load_conv_params(&w95_chip0, &tiny_conv_layers[0])) {
        Uart_println("Failed to load conv2d_1 params.");
        return false;
    }
    print_layer_loaded(tiny_conv_layers[0].name,
                       tiny_conv_layers[0].weight_offset,
                       tiny_conv_layers[0].bias_offset);
    run_conv3x3_same_chw(tiny_act_a, tiny_act_b, &tiny_conv_layers[0]);
    run_maxpool2x2_valid_chw(tiny_act_b, tiny_act_a, 28U, 28U, 8U);

    if (!load_conv_params(&w95_chip0, &tiny_conv_layers[1])) {
        Uart_println("Failed to load conv2d_1_2 params.");
        return false;
    }
    print_layer_loaded(tiny_conv_layers[1].name,
                       tiny_conv_layers[1].weight_offset,
                       tiny_conv_layers[1].bias_offset);
    run_conv3x3_same_chw(tiny_act_a, tiny_act_b, &tiny_conv_layers[1]);
    run_maxpool2x2_valid_chw(tiny_act_b, tiny_act_a, 14U, 14U, 16U);

    if (!load_conv_params(&w95_chip0, &tiny_conv_layers[2])) {
        Uart_println("Failed to load conv2d_2_1 params.");
        return false;
    }
    print_layer_loaded(tiny_conv_layers[2].name,
                       tiny_conv_layers[2].weight_offset,
                       tiny_conv_layers[2].bias_offset);
    run_conv3x3_same_chw(tiny_act_a, tiny_act_b, &tiny_conv_layers[2]);

    if (!load_conv_params(&w95_chip0, &tiny_conv_layers[3])) {
        Uart_println("Failed to load conv2d_3_1 params.");
        return false;
    }
    print_layer_loaded(tiny_conv_layers[3].name,
                       tiny_conv_layers[3].weight_offset,
                       tiny_conv_layers[3].bias_offset);
    run_conv3x3_same_chw(tiny_act_b, tiny_act_a, &tiny_conv_layers[3]);

    if (!load_conv_params(&w95_chip0, &tiny_conv_layers[4])) {
        Uart_println("Failed to load conv2d_4_1 params.");
        return false;
    }
    print_layer_loaded(tiny_conv_layers[4].name,
                       tiny_conv_layers[4].weight_offset,
                       tiny_conv_layers[4].bias_offset);
    run_conv3x3_same_chw(tiny_act_a, tiny_act_b, &tiny_conv_layers[4]);
    run_maxpool2x2_valid_chw(tiny_act_b, tiny_act_a, 7U, 7U, 16U);

    flatten_chw_to_nhwc_vector(tiny_act_a, tiny_act_b, 3U, 3U, 16U);

    if (!load_dense_params(&w95_chip0, &tiny_dense_layers[0])) {
        Uart_println("Failed to load dense_1 params.");
        return false;
    }
    print_layer_loaded(tiny_dense_layers[0].name,
                       tiny_dense_layers[0].weight_offset,
                       tiny_dense_layers[0].bias_offset);
    run_dense(tiny_act_b, tiny_act_a, &tiny_dense_layers[0]);

    if (!load_dense_params(&w95_chip0, &tiny_dense_layers[1])) {
        Uart_println("Failed to load dense_1_2 params.");
        return false;
    }
    print_layer_loaded(tiny_dense_layers[1].name,
                       tiny_dense_layers[1].weight_offset,
                       tiny_dense_layers[1].bias_offset);
    run_dense(tiny_act_a, tiny_act_b, &tiny_dense_layers[1]);

    if (!load_dense_params(&w95_chip0, &tiny_dense_layers[2])) {
        Uart_println("Failed to load dense_2_1 params.");
        return false;
    }
    print_layer_loaded(tiny_dense_layers[2].name,
                       tiny_dense_layers[2].weight_offset,
                       tiny_dense_layers[2].bias_offset);
    run_dense(tiny_act_b, tiny_act_a, &tiny_dense_layers[2]);

    Uart_println("TinyAlexNet MNIST output:");
    print_int8_vector("  Logits int8:", tiny_act_a, TINY_FINAL_OUTPUT_COUNT);
    Uart_print("  Predicted digit: ");
    print_u32_dec(argmax_i8(tiny_act_a, TINY_FINAL_OUTPUT_COUNT));
    Uart_println("");

    return compare_final_with_golden(tiny_act_a);
}
