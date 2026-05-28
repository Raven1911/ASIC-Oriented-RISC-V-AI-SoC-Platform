#include "conv1_test.h"

#include <stdint.h>

#include "conv1_test_vectors.h"
#include "flash_utils.h"
#include "HyperRAM_Driver.h"
#include "UART_Driver.h"
#include "W95_HyperRAM.h"
#include "weight_hyperram_loader.h"

#define CONV1_INPUT_W             28U
#define CONV1_INPUT_H             28U
#define CONV1_INPUT_C             1U
#define CONV1_OUTPUT_W            28U
#define CONV1_OUTPUT_H            28U
#define CONV1_OUTPUT_C            8U
#define CONV1_KERNEL_W            3U
#define CONV1_KERNEL_H            3U
#define CONV1_PADDING             1U

/*
 * Layer metadata copied from feature/nnom-custom:App/Src/layer_metadata.c
 * First entry: { 0, 72, 33608, 32 }  // conv2d_1
 *
 * These are byte offsets inside the contiguous weights blob after it has been
 * loaded to HyperRAM0 by menu command 2.2.
 */
#define CONV1_WEIGHT_OFFSET       0U
#define CONV1_WEIGHT_SIZE         72U
#define CONV1_BIAS_OFFSET         33608U
#define CONV1_BIAS_SIZE           32U
#define CONV1_IN_ZP               (-128)
#define CONV1_OUT_ZP              (-128)
#define CONV1_WEIGHT_ZP           0
#define CONV1_MULTIPLIER          1584375552
#define CONV1_SHIFT               39
#define CONV1_PRINT_SAMPLE_COUNT  64U

static uint8_t conv1_weight_bytes[CONV1_WEIGHT_SIZE];
static uint8_t conv1_bias_bytes[CONV1_BIAS_SIZE];
static int32_t conv1_bias[CONV1_OUTPUT_C];
static int8_t conv1_output_chw[CONV1_TEST_GOLDEN_SIZE];

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

static bool read_conv1_params_from_hyperram0(void)
{
    W95_HandleTypeDef w95_chip0;

    HyperRAM_init(&hyperram0, HYPERRAM_0_BASE_ADDR);
    W95_Init(&w95_chip0,
             &hyperram0,
             WEIGHT_HYPERRAM0_READ_LATENCY,
             WEIGHT_HYPERRAM0_READ_RECOVERY,
             WEIGHT_HYPERRAM0_READ_CAPTURE_SHMOO);

    /* Read conv2d_1 int8 weights from HyperRAM0 blob offset 0. */
    W95_MemoryRead(&w95_chip0,
                   CONV1_WEIGHT_OFFSET,
                   conv1_weight_bytes,
                   CONV1_WEIGHT_SIZE,
                   true);

    /* Read conv2d_1 int32 bias from HyperRAM0 blob offset 33608. */
    W95_MemoryRead(&w95_chip0,
                   CONV1_BIAS_OFFSET,
                   conv1_bias_bytes,
                   CONV1_BIAS_SIZE,
                   true);

    /*
     * The current weights.hex stores int32 bias values in network/MSB-first
     * byte order, for example 44 is stored as 00 00 00 2C.
     */
    for (uint32_t i = 0U; i < CONV1_OUTPUT_C; i++) {
        conv1_bias[i] = read_i32_be(&conv1_bias_bytes[i * 4U]);
    }

    return true;
}

static void run_conv1_cpu_reference(void)
{
    for (uint32_t oc = 0U; oc < CONV1_OUTPUT_C; oc++) {
        for (uint32_t y = 0U; y < CONV1_OUTPUT_H; y++) {
            for (uint32_t x = 0U; x < CONV1_OUTPUT_W; x++) {
                int32_t acc = conv1_bias[oc];

                for (uint32_t ky = 0U; ky < CONV1_KERNEL_H; ky++) {
                    for (uint32_t kx = 0U; kx < CONV1_KERNEL_W; kx++) {
                        int32_t in_y = (int32_t)y + (int32_t)ky - (int32_t)CONV1_PADDING;
                        int32_t in_x = (int32_t)x + (int32_t)kx - (int32_t)CONV1_PADDING;

                        if ((in_y >= 0) && (in_y < (int32_t)CONV1_INPUT_H) &&
                            (in_x >= 0) && (in_x < (int32_t)CONV1_INPUT_W)) {
                            uint32_t in_idx = ((uint32_t)in_y * CONV1_INPUT_W) + (uint32_t)in_x;
                            uint32_t wt_idx = (oc * CONV1_KERNEL_H * CONV1_KERNEL_W) +
                                              (ky * CONV1_KERNEL_W) + kx;
                            int32_t input_value = (int32_t)conv1_test_input_nhwc[in_idx];
                            int32_t weight_value = (int32_t)((int8_t)conv1_weight_bytes[wt_idx]);

                            acc += (input_value - CONV1_IN_ZP) *
                                   (weight_value - CONV1_WEIGHT_ZP);
                        }
                    }
                }

                int64_t scaled = (int64_t)acc * (int64_t)CONV1_MULTIPLIER;
                int32_t requantized = (int32_t)((scaled + ((int64_t)1 << (CONV1_SHIFT - 1))) >> CONV1_SHIFT);
                int32_t final_value = requantized + CONV1_OUT_ZP;
                uint32_t out_idx = (oc * CONV1_OUTPUT_H * CONV1_OUTPUT_W) +
                                   (y * CONV1_OUTPUT_W) + x;

                conv1_output_chw[out_idx] = saturate_i8(final_value);
            }
        }
    }
}

static void print_conv1_params_summary(void)
{
    Uart_println("Conv1 params loaded from HyperRAM0:");
    Uart_print("  Weight offset : 0x");
    print_hex32(CONV1_WEIGHT_OFFSET);
    Uart_println("");
    Uart_print("  Weight size   : ");
    print_u32_dec(CONV1_WEIGHT_SIZE);
    Uart_println(" bytes");
    Uart_print("  Bias offset   : 0x");
    print_hex32(CONV1_BIAS_OFFSET);
    Uart_println("");
    Uart_print("  Bias values   :");
    for (uint32_t i = 0U; i < CONV1_OUTPUT_C; i++) {
        Uart_write(' ');
        print_i32_dec(conv1_bias[i]);
    }
    Uart_println("");
}

static int8_t output_chw_at(uint32_t offset)
{
    return conv1_output_chw[offset];
}

static int8_t output_nhwc_at(uint32_t offset)
{
    uint32_t pixel = offset / CONV1_OUTPUT_C;
    uint32_t oc = offset % CONV1_OUTPUT_C;

    return conv1_output_chw[(oc * CONV1_OUTPUT_H * CONV1_OUTPUT_W) + pixel];
}

static int8_t golden_nhwc_at(uint32_t offset)
{
    uint32_t pixel = offset / CONV1_OUTPUT_C;
    uint32_t oc = offset % CONV1_OUTPUT_C;

    return conv1_test_golden_chw[(oc * CONV1_OUTPUT_H * CONV1_OUTPUT_W) + pixel];
}

static void print_sample_row(const char *label, bool nhwc_layout)
{
    Uart_print(label);
    Uart_print(":");

    for (uint32_t i = 0U; i < CONV1_PRINT_SAMPLE_COUNT; i++) {
        int8_t value = nhwc_layout ? output_nhwc_at(i) : output_chw_at(i);

        Uart_write(' ');
        print_i32_dec((int32_t)value);
    }

    Uart_println("");
}

static void print_golden_sample_row(void)
{
    Uart_print("  Golden NHWC first ");
    print_u32_dec(CONV1_PRINT_SAMPLE_COUNT);
    Uart_print(":");

    for (uint32_t i = 0U; i < CONV1_PRINT_SAMPLE_COUNT; i++) {
        Uart_write(' ');
        print_i32_dec((int32_t)golden_nhwc_at(i));
    }

    Uart_println("");
}

static bool compare_with_golden(void)
{
    uint32_t mismatch_count = 0U;
    uint32_t first_mismatch = 0U;

    for (uint32_t i = 0U; i < CONV1_TEST_GOLDEN_SIZE; i++) {
        if (conv1_output_chw[i] != conv1_test_golden_chw[i]) {
            if (mismatch_count == 0U) {
                first_mismatch = i;
            }
            mismatch_count++;
        }
    }

    Uart_println("Conv1 golden comparison:");
    Uart_print("  Compared values: ");
    print_u32_dec(CONV1_TEST_GOLDEN_SIZE);
    Uart_println(" int8 values (CHW)");

    if (mismatch_count == 0U) {
        Uart_println("  Result: PASS");
        return true;
    }

    Uart_println("  Result: FAILED");
    Uart_print("  Mismatch count: ");
    print_u32_dec(mismatch_count);
    Uart_println("");
    Uart_print("  First mismatch offset: ");
    print_u32_dec(first_mismatch);
    Uart_println("");
    Uart_print("    Expected: ");
    print_i32_dec((int32_t)conv1_test_golden_chw[first_mismatch]);
    Uart_println("");
    Uart_print("    Actual  : ");
    print_i32_dec((int32_t)conv1_output_chw[first_mismatch]);
    Uart_println("");

    return false;
}

bool Conv1_Test_RunFromHyperRAM0(void)
{
    Uart_println("");
    Uart_println("=======================================================");
    Uart_println("    STARTING CONV1 TEST FROM HYPERRAM0");
    Uart_println("=======================================================");
    Uart_println("Prerequisite: run 2.2 first to load weights into HyperRAM0.");

    if (!read_conv1_params_from_hyperram0()) {
        Uart_println("Failed to read Conv1 params from HyperRAM0.");
        return false;
    }

    print_conv1_params_summary();
    run_conv1_cpu_reference();

    Uart_println("Conv1 output sample:");
    print_sample_row("  Output NHWC first 64", true);
    print_golden_sample_row();
    print_sample_row("  Output CHW  first 64", false);

    return compare_with_golden();
}
