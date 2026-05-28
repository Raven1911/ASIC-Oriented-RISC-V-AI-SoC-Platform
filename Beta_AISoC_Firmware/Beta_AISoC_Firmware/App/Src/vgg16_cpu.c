#include "vgg16_cpu.h"

#include <stdint.h>

#include "flash_utils.h"
#include "timer.h"
#include "UART_Driver.h"

#define VGG16_CPU_SIZE_OPT __attribute__((noinline, optimize("Os")))

#ifndef VGG16_CPU_PROFILE_DIVISOR
#define VGG16_CPU_PROFILE_DIVISOR 1024U
#endif

#define VGG16_CPU_LAYER_COUNT      13U
#define VGG16_CPU_POOL_COUNT       5U
#define VGG16_CPU_TOTAL_MACS_TEXT  "15346630656"
#define VGG16_CPU_TOTAL_KMACS      15346630U
#define VGG16_CPU_LOWER_WRAP_MS    ((uint32_t)(0x100000000ULL / CYCLES_PER_MS))
#define VGG16_CPU_LOWER_WRAP_REM   ((uint32_t)(0x100000000ULL % CYCLES_PER_MS))

typedef struct {
    const char *name;
    uint16_t ifheight;
    uint16_t ifchannel;
    uint16_t ofchannel;
    uint8_t hf;
    uint8_t stride;
    uint8_t padding;
} VGG16_CPU_ConvLayer_t;

typedef struct {
    const char *name;
    uint16_t in_height;
    uint16_t channels;
} VGG16_CPU_PoolLayer_t;

static const VGG16_CPU_ConvLayer_t s_vgg16_cpu_layers[VGG16_CPU_LAYER_COUNT] = {
    { "Conv1_1", 224U,   3U,  64U, 3U, 1U, 1U },
    { "Conv1_2", 224U,  64U,  64U, 3U, 1U, 1U },
    { "Conv2_1", 112U,  64U, 128U, 3U, 1U, 1U },
    { "Conv2_2", 112U, 128U, 128U, 3U, 1U, 1U },
    { "Conv3_1",  56U, 128U, 256U, 3U, 1U, 1U },
    { "Conv3_2",  56U, 256U, 256U, 3U, 1U, 1U },
    { "Conv3_3",  56U, 256U, 256U, 3U, 1U, 1U },
    { "Conv4_1",  28U, 256U, 512U, 3U, 1U, 1U },
    { "Conv4_2",  28U, 512U, 512U, 3U, 1U, 1U },
    { "Conv4_3",  28U, 512U, 512U, 3U, 1U, 1U },
    { "Conv5_1",  14U, 512U, 512U, 3U, 1U, 1U },
    { "Conv5_2",  14U, 512U, 512U, 3U, 1U, 1U },
    { "Conv5_3",  14U, 512U, 512U, 3U, 1U, 1U },
};

static const VGG16_CPU_PoolLayer_t s_vgg16_cpu_pools[VGG16_CPU_POOL_COUNT] = {
    { "MaxPool1", 224U,  64U },
    { "MaxPool2", 112U, 128U },
    { "MaxPool3",  56U, 256U },
    { "MaxPool4",  28U, 512U },
    { "MaxPool5",  14U, 512U },
};

static const uint8_t s_vgg16_cpu_pool_after_conv[VGG16_CPU_POOL_COUNT] = {
    1U, 3U, 6U, 9U, 12U
};

static volatile int32_t s_vgg16_cpu_sink;

static VGG16_CPU_SIZE_OPT void print_u32_dec(uint32_t value)
{
    char text[10];
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

static VGG16_CPU_SIZE_OPT tick_t ticks_elapsed(tick_t start, tick_t end)
{
    tick_t diff;

    diff.lower = end.lower - start.lower;
    diff.upper = (end.upper - start.upper) & COUNTER_MAX_UPPER;
    if (end.lower < start.lower) {
        diff.upper = (diff.upper - 1U) & COUNTER_MAX_UPPER;
    }

    return diff;
}

static VGG16_CPU_SIZE_OPT tick_t ticks_add(tick_t a, tick_t b)
{
    tick_t sum;

    sum.lower = a.lower + b.lower;
    sum.upper = (a.upper + b.upper) & COUNTER_MAX_UPPER;
    if (sum.lower < a.lower) {
        sum.upper = (sum.upper + 1U) & COUNTER_MAX_UPPER;
    }

    return sum;
}

static VGG16_CPU_SIZE_OPT tick_t ticks_mul_u32(tick_t ticks, uint32_t factor)
{
    tick_t sum = {0U, 0U};

    for (uint32_t i = 0U; i < factor; i++) {
        sum = ticks_add(sum, ticks);
    }

    return sum;
}

static VGG16_CPU_SIZE_OPT uint32_t ticks_to_ms(tick_t ticks)
{
    uint32_t ms = ticks.upper * VGG16_CPU_LOWER_WRAP_MS + ticks.lower / CYCLES_PER_MS;
    uint32_t rem = ticks.upper * VGG16_CPU_LOWER_WRAP_REM + ticks.lower % CYCLES_PER_MS;

    ms += rem / CYCLES_PER_MS;
    return ms;
}

static VGG16_CPU_SIZE_OPT uint8_t tick_cycles_to_digits(tick_t ticks, uint8_t *digits, uint8_t max_digits)
{
    uint8_t count = 0U;
    uint32_t upper = ticks.upper & COUNTER_MAX_UPPER;
    uint32_t lower = ticks.lower;

    do {
        uint32_t q_upper = upper / 10U;
        uint32_t upper_rem = upper - q_upper * 10U;
        uint32_t q_lower = lower / 10U;
        uint32_t digit = lower - q_lower * 10U;

        for (uint32_t i = 0U; i < upper_rem; i++) {
            q_lower += 429496729U;
            digit += 6U;
            if (digit >= 10U) {
                digit -= 10U;
                q_lower++;
            }
        }

        digits[count++] = (uint8_t)digit;
        upper = q_upper;
        lower = q_lower;
    } while (((upper != 0U) || (lower != 0U)) && (count < max_digits));

    return count;
}

static VGG16_CPU_SIZE_OPT void print_tick_cycles(tick_t ticks)
{
    uint8_t digits[20];
    uint8_t count = tick_cycles_to_digits(ticks, digits, sizeof(digits));

    while (count > 0U) {
        Uart_write((uint8_t)('0' + digits[--count]));
    }
}

static VGG16_CPU_SIZE_OPT void print_tick_metric(tick_t ticks)
{
    print_tick_cycles(ticks);
    Uart_print(" cycles (");
    print_u32_dec(ticks_to_ms(ticks));
    Uart_print(" ms)");
}

static VGG16_CPU_SIZE_OPT uint32_t ticks_div_u32_rounded(tick_t ticks, uint32_t divisor)
{
    uint32_t quotient = 0U;
    uint32_t remainder = 0U;

    if (divisor == 0U) {
        return 0U;
    }

    for (int32_t bit = 49; bit >= 0; bit--) {
        uint32_t next_bit;

        if (bit >= 32) {
            next_bit = (ticks.upper >> (uint32_t)(bit - 32)) & 1U;
        } else {
            next_bit = (ticks.lower >> (uint32_t)bit) & 1U;
        }

        remainder = (remainder << 1U) | next_bit;
        if (remainder >= divisor) {
            remainder -= divisor;
            if (bit < 32) {
                quotient |= (1UL << (uint32_t)bit);
            } else {
                quotient = 0xFFFFFFFFU;
            }
        }
    }

    if ((quotient != 0xFFFFFFFFU) && (remainder >= ((divisor + 1U) >> 1U))) {
        quotient++;
    }

    return quotient;
}

static VGG16_CPU_SIZE_OPT void print_cycles_per_unit(tick_t ticks, uint32_t units)
{
    if (units == 0U) {
        Uart_print("n/a");
        return;
    }

    print_u32_dec(ticks_div_u32_rounded(ticks, units));
}

static VGG16_CPU_SIZE_OPT uint32_t conv_ofwidth(const VGG16_CPU_ConvLayer_t *layer)
{
    uint32_t padded = (uint32_t)layer->ifheight + ((uint32_t)layer->padding << 1U);
    uint32_t span = (padded >= layer->hf) ? (padded - (uint32_t)layer->hf) : 0U;

    return (span / (uint32_t)layer->stride) + 1U;
}

static VGG16_CPU_SIZE_OPT uint32_t conv_output_bytes(const VGG16_CPU_ConvLayer_t *layer)
{
    uint32_t ofwidth = conv_ofwidth(layer);

    return ofwidth * ofwidth * (uint32_t)layer->ofchannel;
}

static VGG16_CPU_SIZE_OPT uint32_t conv_macs(const VGG16_CPU_ConvLayer_t *layer)
{
    return conv_output_bytes(layer) *
           (uint32_t)layer->ifchannel *
           (uint32_t)layer->hf *
           (uint32_t)layer->hf;
}

static VGG16_CPU_SIZE_OPT uint32_t pool_output_bytes(const VGG16_CPU_PoolLayer_t *pool)
{
    uint32_t out_height = (uint32_t)pool->in_height >> 1U;

    return out_height * out_height * (uint32_t)pool->channels;
}

static VGG16_CPU_SIZE_OPT int8_t fake_ifmap_value(uint32_t addr)
{
    return (int8_t)((addr * 37U + (addr >> 7U) + 11U) & 0xFFU);
}

static VGG16_CPU_SIZE_OPT int8_t fake_weight_value(uint32_t addr)
{
    return (int8_t)((addr * 17U + (addr >> 5U) + 3U) & 0xFFU);
}

static VGG16_CPU_SIZE_OPT int8_t requantize_fake(int32_t acc)
{
    int32_t value = acc >> 12;

    if (value > 127) {
        value = 127;
    } else if (value < -128) {
        value = -128;
    }

    return (int8_t)value;
}

static VGG16_CPU_SIZE_OPT void cpu_run_conv_sample(const VGG16_CPU_ConvLayer_t *layer,
                                                   uint32_t sample_outputs)
{
    uint32_t ofwidth = conv_ofwidth(layer);
    uint32_t output_count = conv_output_bytes(layer);
    uint32_t in_ch_bytes = (uint32_t)layer->ifheight * (uint32_t)layer->ifheight;
    uint32_t kernel_ch_bytes = (uint32_t)layer->hf * (uint32_t)layer->hf;
    volatile int32_t sink = s_vgg16_cpu_sink;

    for (uint32_t sample = 0U; sample < sample_outputs; sample++) {
        uint32_t out_linear = (sample * output_count) / sample_outputs;
        uint32_t out_ch_bytes = ofwidth * ofwidth;
        uint32_t oc = out_linear / out_ch_bytes;
        uint32_t out_rem = out_linear - oc * out_ch_bytes;
        uint32_t oy = out_rem / ofwidth;
        uint32_t ox = out_rem - oy * ofwidth;
        int32_t acc = (int32_t)((oc * 13U) & 0x7FU) - 64;

        for (uint32_t ic = 0U; ic < layer->ifchannel; ic++) {
            for (uint32_t ky = 0U; ky < layer->hf; ky++) {
                int32_t iy = (int32_t)(oy * layer->stride + ky) - (int32_t)layer->padding;

                for (uint32_t kx = 0U; kx < layer->hf; kx++) {
                    int32_t ix = (int32_t)(ox * layer->stride + kx) - (int32_t)layer->padding;
                    int8_t input_value = 0;
                    uint32_t weight_addr;

                    if ((iy >= 0) && (iy < (int32_t)layer->ifheight) &&
                        (ix >= 0) && (ix < (int32_t)layer->ifheight)) {
                        uint32_t if_addr = ic * in_ch_bytes +
                                           (uint32_t)iy * (uint32_t)layer->ifheight +
                                           (uint32_t)ix;
                        input_value = fake_ifmap_value(if_addr);
                    }

                    weight_addr = ((oc * (uint32_t)layer->ifchannel + ic) * kernel_ch_bytes) +
                                  ky * (uint32_t)layer->hf + kx;
                    acc += (int32_t)input_value * (int32_t)fake_weight_value(weight_addr);
                }
            }
        }

        sink += (int32_t)requantize_fake(acc);
        sink ^= (int32_t)(out_linear + (oc << 4U));
    }

    s_vgg16_cpu_sink = sink;
}

static VGG16_CPU_SIZE_OPT void cpu_run_pool(const VGG16_CPU_PoolLayer_t *pool)
{
    uint32_t out_bytes = pool_output_bytes(pool);
    volatile uint32_t sink = (uint32_t)s_vgg16_cpu_sink;

    for (uint32_t i = 0U; i < out_bytes; i++) {
        uint8_t max_value = (uint8_t)(sink + i);
        uint8_t value = (uint8_t)(sink + (i * 3U));

        if (value > max_value) {
            max_value = value;
        }
        value = (uint8_t)(sink + (i * 5U));
        if (value > max_value) {
            max_value = value;
        }
        value = (uint8_t)(sink + (i * 7U));
        if (value > max_value) {
            max_value = value;
        }

        sink += max_value;
    }

    s_vgg16_cpu_sink = (int32_t)sink;
}

static VGG16_CPU_SIZE_OPT tick_t run_cpu_conv_layer(const VGG16_CPU_ConvLayer_t *layer,
                                                    tick_t *sample_ticks,
                                                    uint32_t *sample_outputs,
                                                    uint32_t *sample_macs)
{
    tick_t start_tick;
    tick_t elapsed;
    uint32_t macs = conv_macs(layer);
    uint32_t outputs = conv_output_bytes(layer);
    uint32_t macs_per_output = (uint32_t)layer->ifchannel *
                               (uint32_t)layer->hf *
                               (uint32_t)layer->hf;
    uint32_t divisor = VGG16_CPU_PROFILE_DIVISOR;

    if (divisor == 0U) {
        divisor = 1U;
    }

    *sample_outputs = outputs / divisor;
    if (*sample_outputs == 0U) {
        *sample_outputs = outputs;
        divisor = 1U;
    }
    *sample_macs = (*sample_outputs) * macs_per_output;

    start_tick = read_tick();
    cpu_run_conv_sample(layer, *sample_outputs);
    elapsed = ticks_elapsed(start_tick, read_tick());

    *sample_ticks = elapsed;
    return ticks_mul_u32(elapsed, divisor);
}

static VGG16_CPU_SIZE_OPT tick_t run_cpu_pool_layer(const VGG16_CPU_PoolLayer_t *pool)
{
    tick_t start_tick = read_tick();

    cpu_run_pool(pool);
    return ticks_elapsed(start_tick, read_tick());
}

bool VGG16_CPU_RunTimingOnly(void)
{
    uint8_t next_pool = 0U;
    tick_t conv_total = {0U, 0U};
    tick_t pool_total = {0U, 0U};
    tick_t wall_start;
    tick_t wall_ticks;

    Uart_println("");
    Uart_println("=== Run VGG16 CPU-only timing ===");
    Uart_println("Timing path: CPU conv workload + CPU max-pool workload, no correctness check.");
    Uart_print("  Conv profile divisor : ");
    print_u32_dec(VGG16_CPU_PROFILE_DIVISOR);
    Uart_println("");
    if (VGG16_CPU_PROFILE_DIVISOR != 1U) {
        Uart_println("  Conv cycles are projected from sampled real CPU conv loops.");
    }

    wall_start = read_tick();

    for (uint8_t i = 0U; i < VGG16_CPU_LAYER_COUNT; i++) {
        const VGG16_CPU_ConvLayer_t *layer = &s_vgg16_cpu_layers[i];
        tick_t sample_ticks;
        tick_t projected_ticks;
        uint32_t sample_outputs;
        uint32_t sample_macs;
        uint32_t macs = conv_macs(layer);

        Uart_print("  Layer ");
        print_u32_dec((uint32_t)i + 1U);
        Uart_write(' ');
        Uart_print(layer->name);
        Uart_print(": ");
        print_u32_dec(layer->ifheight);
        Uart_write('x');
        print_u32_dec(layer->ifheight);
        Uart_write('x');
        print_u32_dec(layer->ifchannel);
        Uart_print(" -> ");
        print_u32_dec(conv_ofwidth(layer));
        Uart_write('x');
        print_u32_dec(conv_ofwidth(layer));
        Uart_write('x');
        print_u32_dec(layer->ofchannel);
        Uart_println("");

        projected_ticks = run_cpu_conv_layer(layer, &sample_ticks, &sample_outputs, &sample_macs);
        conv_total = ticks_add(conv_total, projected_ticks);

        Uart_println("    finished:");
        if (VGG16_CPU_PROFILE_DIVISOR != 1U) {
            Uart_print("      Measured sample : ");
            print_tick_metric(sample_ticks);
            Uart_print(" for ");
            print_u32_dec(sample_outputs);
            Uart_print(" outputs / ");
            print_u32_dec(sample_macs);
            Uart_println(" MACs");
            Uart_print("      Projected time  : ");
        } else {
            Uart_print("      Time            : ");
        }
        print_tick_metric(projected_ticks);
        Uart_println("");
        Uart_print("      Workload        : ");
        print_u32_dec(macs);
        Uart_println(" MACs");
        Uart_print("      Output bytes    : ");
        print_u32_dec(conv_output_bytes(layer));
        Uart_println("");
        Uart_print("      Cost            : ");
        print_cycles_per_unit(projected_ticks, macs / 1000U);
        Uart_println(" cycles / 1000 MACs");

        if ((next_pool < VGG16_CPU_POOL_COUNT) &&
            (s_vgg16_cpu_pool_after_conv[next_pool] == i)) {
            const VGG16_CPU_PoolLayer_t *pool = &s_vgg16_cpu_pools[next_pool];
            tick_t pool_ticks;

            Uart_print("  CPU ");
            Uart_print(pool->name);
            Uart_print(": ");
            print_u32_dec(pool->in_height);
            Uart_write('x');
            print_u32_dec(pool->in_height);
            Uart_write('x');
            print_u32_dec(pool->channels);
            Uart_print(" -> ");
            print_u32_dec((uint32_t)pool->in_height >> 1U);
            Uart_write('x');
            print_u32_dec((uint32_t)pool->in_height >> 1U);
            Uart_write('x');
            print_u32_dec(pool->channels);
            Uart_println("");

            pool_ticks = run_cpu_pool_layer(pool);
            pool_total = ticks_add(pool_total, pool_ticks);

            Uart_println("    finished:");
            Uart_print("      Time            : ");
            print_tick_metric(pool_ticks);
            Uart_println("");
            Uart_print("      Output bytes    : ");
            print_u32_dec(pool_output_bytes(pool));
            Uart_println("");
            next_pool++;
        }
    }

    wall_ticks = ticks_elapsed(wall_start, read_tick());

    Uart_println("");
    Uart_println("VGG16 CPU-only timing summary:");
    Uart_print("  CPU conv layers      : ");
    print_tick_metric(conv_total);
    Uart_println("");
    Uart_print("  Conv workload        : ");
    Uart_println(VGG16_CPU_TOTAL_MACS_TEXT " MACs");
    Uart_print("  Conv average cost    : ");
    print_cycles_per_unit(conv_total, VGG16_CPU_TOTAL_KMACS);
    Uart_println(" cycles / 1000 MACs");
    Uart_print("  CPU max-pool layers  : ");
    print_tick_metric(pool_total);
    Uart_println("");
    Uart_print("  Full CPU pipeline    : ");
    print_tick_metric(ticks_add(conv_total, pool_total));
    Uart_println("  (conv + max-pool)");
    Uart_print("  Wall section         : ");
    print_tick_metric(wall_ticks);
    Uart_println("  (includes UART/log overhead)");

    Uart_print("  CPU sink             : 0x");
    Uart_print_hex_32((uint32_t)s_vgg16_cpu_sink);
    Uart_println("");
    Uart_println("VGG16 CPU-only timing -> DONE");
    return true;
}
