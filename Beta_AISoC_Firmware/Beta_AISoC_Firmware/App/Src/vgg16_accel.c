#include "vgg16_accel.h"

#include <stdint.h>

#include "CNN_Accel_Driver.h"
#include "flash_utils.h"
#include "HyperRAM_Driver.h"
#include "Interrupt_Driver.h"
#include "timer.h"
#include "UART_Driver.h"
#include "VideoStreaming_Driver.h"
#include "W95_HyperRAM.h"
#include "weight_hyperram_loader.h"

#define VGG16_SIZE_OPT __attribute__((noinline, optimize("Os")))

#define VGG16_LAYER_COUNT              13U
#define VGG16_POOL_LAYER_COUNT         5U
#define VGG16_DMAC_WRITE_WEIGHT        1U
#define VGG16_DMAC_READ_WEIGHT         2U
#define VGG16_SUBMIT_WAIT_LIMIT        10000000U
#define VGG16_IRQ_WAIT_LIMIT           100000000U
#define VGG16_HRAM_DRAIN_WAIT_LIMIT    50000000U
#define VGG16_HRAM_DRAIN_STABLE_READS  128U
#define VGG16_HRAM_CPU_CHUNK_BYTES     256U
#define VGG16_LOWER_WRAP_MS            ((uint32_t)(0x100000000ULL / CYCLES_PER_MS))
#define VGG16_LOWER_WRAP_REM           ((uint32_t)(0x100000000ULL % CYCLES_PER_MS))
#define VGG16_TOTAL_MACS_TEXT          "15346630656"
#define VGG16_TOTAL_KMACS              15346630U
#define VGG16_PARAM_BYTES              14727360U
#define VGG16_ACTIVATION_BYTES         9182208U
#define VGG16_POOL_BYTES               2709504U
#define VGG16_DUMMY_CPU_MAXPOOL        1U

typedef struct {
    const char *name;
    uint8_t  ifheight;
    uint16_t ifchannel;
    uint16_t ofchannel;
    uint8_t  hf;
    uint8_t  stride;
    uint8_t  padding;
    uint8_t  ifparr;
    uint8_t  oftile;
    uint8_t  ofparr;
    uint32_t ifbaddr;
    uint32_t fltbaddr;
    uint32_t bias_baddr;
    uint32_t ofbaddr;
} VGG16_Layer_t;

typedef struct {
    const char *name;
    uint8_t after_conv_idx;
    uint16_t in_height;
    uint16_t channels;
    uint32_t input_base;
    uint32_t output_base;
    bool write_output;
} VGG16_PoolLayer_t;

static const VGG16_Layer_t s_vgg16_layers[VGG16_LAYER_COUNT] = {
    { "Conv1_1", 224U,   3U,  64U, 3U, 1U, 1U, 3U, 1U, 8U,       0U,        0U,     1728U,  150528U },
    { "Conv1_2", 224U,  64U,  64U, 3U, 1U, 1U, 4U, 1U, 8U,  150528U,     1984U,    38848U, 3361792U },
    { "Conv2_1", 112U,  64U, 128U, 3U, 1U, 1U, 4U, 1U, 8U, 3361792U,    39104U,   112832U, 4164608U },
    { "Conv2_2", 112U, 128U, 128U, 3U, 1U, 1U, 4U, 1U, 8U, 4164608U,   113344U,   260800U, 5770240U },
    { "Conv3_1",  56U, 128U, 256U, 3U, 1U, 1U, 4U, 1U, 8U, 5770240U,   261312U,   556224U, 6171648U },
    { "Conv3_2",  56U, 256U, 256U, 3U, 1U, 1U, 4U, 1U, 8U, 6171648U,   557248U,  1147072U, 6974464U },
    { "Conv3_3",  56U, 256U, 256U, 3U, 1U, 1U, 4U, 1U, 8U, 6974464U,  1148096U,  1737920U, 7777280U },
    { "Conv4_1",  28U, 256U, 512U, 3U, 1U, 1U, 4U, 1U, 8U, 7777280U,  1738944U,  2918592U, 7977984U },
    { "Conv4_2",  28U, 512U, 512U, 3U, 1U, 1U, 4U, 1U, 8U, 7977984U,  2920640U,  5279936U, 8379392U },
    { "Conv4_3",  28U, 512U, 512U, 3U, 1U, 1U, 4U, 1U, 8U, 8379392U,  5281984U,  7641280U, 8780800U },
    { "Conv5_1",  14U, 512U, 512U, 3U, 1U, 1U, 4U, 1U, 8U, 8780800U,  7643328U, 10002624U, 8881152U },
    { "Conv5_2",  14U, 512U, 512U, 3U, 1U, 1U, 4U, 1U, 8U, 8881152U, 10004672U, 12363968U, 8981504U },
    { "Conv5_3",  14U, 512U, 512U, 3U, 1U, 1U, 4U, 1U, 8U, 8981504U, 12366016U, 14725312U, 9081856U },
};

static const VGG16_PoolLayer_t s_vgg16_pools[VGG16_POOL_LAYER_COUNT] = {
    { "MaxPool1",  1U, 224U,  64U, 3361792U, 3361792U, true  },
    { "MaxPool2",  3U, 112U, 128U, 5770240U, 5770240U, true  },
    { "MaxPool3",  6U,  56U, 256U, 7777280U, 7777280U, true  },
    { "MaxPool4",  9U,  28U, 512U, 8780800U, 8780800U, true  },
    { "MaxPool5", 12U,  14U, 512U, 9081856U, 9081856U, true  },
};

static const VGG16_Layer_t s_vgg16_layer11_low_addr = {
    "Conv5_1_low_addr", 14U, 512U, 512U, 3U, 1U, 1U, 4U, 1U, 8U,
    0U, 0U, 1728U, 150528U
};

static volatile bool s_vgg16_irq_seen;
static bool s_vgg16_debug_status;
static uint8_t s_pool_row0[224];
static uint8_t s_pool_row1[224];
static uint8_t s_pool_out_row[112];
static uint8_t s_pool_in_ch0[196];
static uint8_t s_pool_in_ch1[196];
static uint8_t s_pool_out_pair[98];
static uint8_t s_debug_fill_buf[VGG16_HRAM_CPU_CHUNK_BYTES];

static VGG16_SIZE_OPT void print_u32_dec(uint32_t value)
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

static VGG16_SIZE_OPT tick_t ticks_elapsed(tick_t start, tick_t end)
{
    tick_t diff;

    diff.lower = end.lower - start.lower;
    diff.upper = (end.upper - start.upper) & COUNTER_MAX_UPPER;
    if (end.lower < start.lower) {
        diff.upper = (diff.upper - 1U) & COUNTER_MAX_UPPER;
    }

    return diff;
}

static VGG16_SIZE_OPT tick_t ticks_add(tick_t a, tick_t b)
{
    tick_t sum;

    sum.lower = a.lower + b.lower;
    sum.upper = (a.upper + b.upper) & COUNTER_MAX_UPPER;
    if (sum.lower < a.lower) {
        sum.upper = (sum.upper + 1U) & COUNTER_MAX_UPPER;
    }

    return sum;
}

static VGG16_SIZE_OPT uint32_t ticks_to_ms(tick_t ticks)
{
    uint32_t ms = ticks.upper * VGG16_LOWER_WRAP_MS + ticks.lower / CYCLES_PER_MS;
    uint32_t rem = ticks.upper * VGG16_LOWER_WRAP_REM + ticks.lower % CYCLES_PER_MS;

    ms += rem / CYCLES_PER_MS;
    return ms;
}

static VGG16_SIZE_OPT uint8_t tick_cycles_to_digits(tick_t ticks, uint8_t *digits, uint8_t max_digits)
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

static VGG16_SIZE_OPT void print_tick_cycles(tick_t ticks)
{
    uint8_t digits[20];
    uint8_t count = tick_cycles_to_digits(ticks, digits, sizeof(digits));

    while (count > 0U) {
        Uart_write((uint8_t)('0' + digits[--count]));
    }
}

static VGG16_SIZE_OPT void print_tick_metric(tick_t ticks)
{
    print_tick_cycles(ticks);
    Uart_print(" cycles (");
    print_u32_dec(ticks_to_ms(ticks));
    Uart_print(" ms)");
}

static VGG16_SIZE_OPT uint32_t ticks_to_u32_saturated(tick_t ticks)
{
    return (ticks.upper != 0U) ? 0xFFFFFFFFU : ticks.lower;
}

static VGG16_SIZE_OPT void print_cycles_per_unit(tick_t ticks, uint32_t units)
{
    uint32_t cycles;

    if (units == 0U) {
        Uart_print("n/a");
        return;
    }

    if (ticks.upper != 0U) {
        Uart_write('>');
    }
    cycles = ticks_to_u32_saturated(ticks);
    print_u32_dec((cycles + (units >> 1U)) / units);
}

static VGG16_SIZE_OPT uint32_t vgg16_ofwidth(const VGG16_Layer_t *layer)
{
    uint32_t padded = (uint32_t)layer->ifheight + ((uint32_t)layer->padding << 1U);
    uint32_t span = (padded >= layer->hf) ? (padded - (uint32_t)layer->hf) : 0U;

    return (span / (uint32_t)layer->stride) + 1U;
}

static VGG16_SIZE_OPT uint32_t vgg16_ofmap_bytes(const VGG16_Layer_t *layer)
{
    uint32_t ofwidth = vgg16_ofwidth(layer);

    return ofwidth * ofwidth * (uint32_t)layer->ofchannel;
}

static VGG16_SIZE_OPT uint32_t vgg16_layer_macs(const VGG16_Layer_t *layer)
{
    return vgg16_ofmap_bytes(layer) *
           (uint32_t)layer->ifchannel *
           (uint32_t)layer->hf *
           (uint32_t)layer->hf;
}

static VGG16_SIZE_OPT void print_cnn_status(const char *prefix, uint32_t status)
{
    Uart_print(prefix);
    Uart_print(" STATUS=0x");
    Uart_print_hex_32(status);
    Uart_print(" busy=");
    Uart_write((status & CNN_ACCEL_STATUS_BUSY_Msk) != 0U ? '1' : '0');
    Uart_print(" done=");
    Uart_write((status & CNN_ACCEL_STATUS_DONE_Msk) != 0U ? '1' : '0');
    Uart_print(" table_rdy=");
    Uart_write((status & CNN_ACCEL_STATUS_TABLE_READY_Msk) != 0U ? '1' : '0');
    Uart_println("");
}

static VGG16_SIZE_OPT void print_hyperram_status(const char *name, HyperRAM_Driver_t *drv)
{
    uint32_t mode = HyperRAM_read_mode_register(drv);
    uint32_t status = *drv->reg_status;

    Uart_print("  ");
    Uart_print(name);
    Uart_print(" mode=0x");
    Uart_print_hex_32(mode);
    Uart_print(" status=0x");
    Uart_print_hex_32(status);
    Uart_println("");
}

static VGG16_SIZE_OPT bool wait_hyperram_master_idle(const char *name, HyperRAM_Driver_t *drv)
{
    uint32_t wait = VGG16_HRAM_DRAIN_WAIT_LIMIT;
    uint32_t stable = 0U;

    while (wait > 0U) {
        if (HyperRAM_is_start_ready(drv)) {
            stable++;
            if (stable >= VGG16_HRAM_DRAIN_STABLE_READS) {
                return true;
            }
        } else {
            stable = 0U;
        }
        wait--;
    }

    Uart_print("  ");
    Uart_print(name);
    Uart_println(" drain timeout.");
    print_hyperram_status(name, drv);
    return false;
}

static VGG16_SIZE_OPT bool hram_read_bytes(W95_HandleTypeDef *w95,
                                           uint32_t addr,
                                           uint8_t *dst,
                                           uint32_t size)
{
    uint32_t done = 0U;

    if (((addr & 1U) != 0U) || ((size & 1U) != 0U)) {
        return false;
    }

    while (done < size) {
        uint32_t chunk = size - done;
        if (chunk > VGG16_HRAM_CPU_CHUNK_BYTES) {
            chunk = VGG16_HRAM_CPU_CHUNK_BYTES;
        }

        W95_MemoryRead(w95, addr + done, dst + done, chunk, true);
        done += chunk;
    }

    return true;
}

static VGG16_SIZE_OPT bool hram_write_bytes(W95_HandleTypeDef *w95,
                                            uint32_t addr,
                                            const uint8_t *src,
                                            uint32_t size)
{
    uint32_t done = 0U;

    if (((addr & 1U) != 0U) || ((size & 1U) != 0U)) {
        return false;
    }

    while (done < size) {
        uint32_t chunk = size - done;
        if (chunk > VGG16_HRAM_CPU_CHUNK_BYTES) {
            chunk = VGG16_HRAM_CPU_CHUNK_BYTES;
        }

        W95_MemoryWrite(w95, addr + done, src + done, chunk, true);
        done += chunk;
    }

    return true;
}

static VGG16_SIZE_OPT bool fill_hyperram1_region(W95_HandleTypeDef *w95,
                                                 uint32_t addr,
                                                 uint32_t size)
{
    uint32_t done = 0U;

    if (((addr & 1U) != 0U) || ((size & 1U) != 0U)) {
        return false;
    }

    while (done < size) {
        uint32_t chunk = size - done;

        if (chunk > VGG16_HRAM_CPU_CHUNK_BYTES) {
            chunk = VGG16_HRAM_CPU_CHUNK_BYTES;
        }
        for (uint32_t i = 0U; i < chunk; i++) {
            s_debug_fill_buf[i] = (uint8_t)((done + i) & 0xFFU);
        }
        if (!hram_write_bytes(w95, addr + done, s_debug_fill_buf, chunk)) {
            return false;
        }
        done += chunk;
    }

    return true;
}

static void vgg16_irq_handler(uint32_t irq_bit, void *context)
{
    (void)irq_bit;
    (void)context;
    s_vgg16_irq_seen = true;
}

static VGG16_SIZE_OPT void fill_layer_config(const VGG16_Layer_t *layer,
                                             CNN_Accel_LayerConfig_t *config)
{
    config->ifheight = layer->ifheight;
    config->ifchannel = layer->ifchannel;
    config->ofchannel = layer->ofchannel;
    config->hf = layer->hf;
    config->stride = layer->stride;
    config->padding = layer->padding;
    config->ifparr = layer->ifparr;
    config->oftile = layer->oftile;
    config->ofparr = layer->ofparr;
    config->ifbaddr = layer->ifbaddr;
    config->fltbaddr = layer->fltbaddr;
    config->bias_baddr = layer->bias_baddr;
    config->ofbaddr = layer->ofbaddr;
    config->ifc_zp = 0;
    config->fltc_zp = 0;
    config->mult = 0;
    config->mult_shift = 0U;
    config->alphamult = 0;
    config->alphamult_shift = 0U;
    config->zpy = 0;
    config->qmin = (int8_t)-128;
    config->qmax = (int8_t)127;
    config->is_leaky_relu = false;
}

static VGG16_SIZE_OPT bool run_vgg16_layer_config(uint8_t display_idx,
                                                  const VGG16_Layer_t *layer,
                                                  tick_t *elapsed)
{
    CNN_Accel_LayerConfig_t config;
    tick_t start_tick;
    tick_t end_tick;
    uint32_t wait = VGG16_IRQ_WAIT_LIMIT;
    uint32_t status;
    bool done_seen = false;

    fill_layer_config(layer, &config);
    s_vgg16_irq_seen = false;

    Uart_print("  Layer ");
    print_u32_dec((uint32_t)display_idx + 1U);
    Uart_print(" ");
    Uart_print(layer->name);
    Uart_print(": ");
    print_u32_dec(layer->ifheight);
    Uart_write('x');
    print_u32_dec(layer->ifheight);
    Uart_write('x');
    print_u32_dec(layer->ifchannel);
    Uart_print(" -> ");
    print_u32_dec(vgg16_ofwidth(layer));
    Uart_write('x');
    print_u32_dec(vgg16_ofwidth(layer));
    Uart_write('x');
    print_u32_dec(layer->ofchannel);
    Uart_println("");

    status = CNN_Accel_get_status(&cnn_accel);
    if (s_vgg16_debug_status) {
        print_cnn_status("    before submit:", status);
    }
    if ((status & CNN_ACCEL_STATUS_BUSY_Msk) != 0U) {
        print_cnn_status("    CNN busy before layer:", status);
        Uart_println("    Reset SoC before rerunning a layer-only debug command.");
        return false;
    }

    start_tick = read_tick();

    if (!CNN_Accel_submit_layer_config(&cnn_accel, &config, VGG16_SUBMIT_WAIT_LIMIT)) {
        print_cnn_status("    submit timeout:", CNN_Accel_get_status(&cnn_accel));
        return false;
    }
    if (s_vgg16_debug_status) {
        print_cnn_status("    after submit:", CNN_Accel_get_status(&cnn_accel));
    }

    CNN_Accel_start(&cnn_accel);
    if (s_vgg16_debug_status) {
        print_cnn_status("    after start:", CNN_Accel_get_status(&cnn_accel));
    }

    while (wait > 0U) {
        status = CNN_Accel_get_status(&cnn_accel);
        if (s_vgg16_irq_seen || ((status & CNN_ACCEL_STATUS_DONE_Msk) != 0U)) {
            done_seen = true;
            break;
        }
        wait--;
    }

    status = CNN_Accel_get_status(&cnn_accel);
    if ((status & CNN_ACCEL_STATUS_DONE_Msk) != 0U) {
        done_seen = true;
    }

    if (!done_seen) {
        print_cnn_status("    IRQ timeout:", CNN_Accel_get_status(&cnn_accel));
        print_hyperram_status("HR0", &hyperram0);
        print_hyperram_status("HR1", &hyperram1);
        return false;
    }

    if (!CNN_Accel_wait_idle(&cnn_accel, VGG16_SUBMIT_WAIT_LIMIT)) {
        print_cnn_status("    idle timeout:", CNN_Accel_get_status(&cnn_accel));
        return false;
    }

    if (!wait_hyperram_master_idle("HR1", &hyperram1)) {
        return false;
    }

    end_tick = read_tick();
    *elapsed = ticks_elapsed(start_tick, end_tick);
    return true;
}

static VGG16_SIZE_OPT bool run_vgg16_layer(uint8_t idx, tick_t *elapsed)
{
    return run_vgg16_layer_config(idx, &s_vgg16_layers[idx], elapsed);
}

static VGG16_SIZE_OPT void print_layer_profile(const VGG16_Layer_t *layer, tick_t ticks)
{
    uint32_t macs = vgg16_layer_macs(layer);

    Uart_println("    finished:");
    Uart_print("      Time         : ");
    print_tick_metric(ticks);
    Uart_println("");
    Uart_print("      Workload     : ");
    print_u32_dec(macs);
    Uart_println(" MACs");
    Uart_print("      Output bytes : ");
    print_u32_dec(vgg16_ofmap_bytes(layer));
    Uart_println("");
    Uart_print("      Cost         : ");
    print_cycles_per_unit(ticks, macs / 1000U);
    Uart_println(" cycles / 1000 MACs");
}

static VGG16_SIZE_OPT void print_layer_addresses(const VGG16_Layer_t *layer)
{
    Uart_print("    IFMAP=0x");
    Uart_print_hex_32(layer->ifbaddr);
    Uart_print(" FLT=0x");
    Uart_print_hex_32(layer->fltbaddr);
    Uart_print(" BIAS=0x");
    Uart_print_hex_32(layer->bias_baddr);
    Uart_print(" OFMAP=0x");
    Uart_print_hex_32(layer->ofbaddr);
    Uart_println("");
}

static VGG16_SIZE_OPT uint32_t pool_output_bytes(const VGG16_PoolLayer_t *pool)
{
    uint32_t out_height = (uint32_t)pool->in_height >> 1U;

    return out_height * out_height * (uint32_t)pool->channels;
}

static VGG16_SIZE_OPT bool run_even_width_pool(W95_HandleTypeDef *w95,
                                               W95_HandleTypeDef *w95_write,
                                               const VGG16_PoolLayer_t *pool)
{
    uint32_t in_height = pool->in_height;
    uint32_t out_height = in_height >> 1U;
    uint32_t in_ch_bytes = in_height * in_height;
    uint32_t out_ch_bytes = out_height * out_height;

    for (uint32_t c = 0U; c < pool->channels; c++) {
        uint32_t in_ch_base = pool->input_base + c * in_ch_bytes;
        uint32_t out_ch_base = pool->output_base + c * out_ch_bytes;

        for (uint32_t oy = 0U; oy < out_height; oy++) {
            uint32_t row0_addr = in_ch_base + (oy << 1U) * in_height;
            uint32_t row1_addr = row0_addr + in_height;
            uint32_t out_addr = out_ch_base + oy * out_height;

            if (!hram_read_bytes(w95, row0_addr, s_pool_row0, in_height) ||
                !hram_read_bytes(w95, row1_addr, s_pool_row1, in_height)) {
                return false;
            }

            for (uint32_t ox = 0U; ox < out_height; ox++) {
                uint32_t ix = ox << 1U;
                uint8_t max_value = s_pool_row0[ix];
                uint8_t value = s_pool_row0[ix + 1U];

                if (value > max_value) {
                    max_value = value;
                }
                value = s_pool_row1[ix];
                if (value > max_value) {
                    max_value = value;
                }
                value = s_pool_row1[ix + 1U];
                if (value > max_value) {
                    max_value = value;
                }
                s_pool_out_row[ox] = max_value;
            }

            if (pool->write_output && !hram_write_bytes(w95_write, out_addr, s_pool_out_row, out_height)) {
                return false;
            }
        }
    }

    return true;
}

static VGG16_SIZE_OPT bool run_pool5_odd_width(W95_HandleTypeDef *w95,
                                               W95_HandleTypeDef *w95_write,
                                               const VGG16_PoolLayer_t *pool)
{
    uint32_t in_height = pool->in_height;
    uint32_t out_height = in_height >> 1U;
    uint32_t in_ch_bytes = in_height * in_height;
    uint32_t out_ch_bytes = out_height * out_height;

    for (uint32_t c = 0U; c < pool->channels; c += 2U) {
        uint32_t pair_count = ((uint32_t)pool->channels - c) >= 2U ? 2U : 1U;

        for (uint32_t lane = 0U; lane < pair_count; lane++) {
            uint8_t *in_ch = (lane == 0U) ? s_pool_in_ch0 : s_pool_in_ch1;
            uint32_t ch_base = pool->input_base + (c + lane) * in_ch_bytes;

            if (!hram_read_bytes(w95, ch_base, in_ch, in_ch_bytes)) {
                return false;
            }

            for (uint32_t oy = 0U; oy < out_height; oy++) {
                for (uint32_t ox = 0U; ox < out_height; ox++) {
                    uint32_t iy = oy << 1U;
                    uint32_t ix = ox << 1U;
                    uint8_t max_value = in_ch[iy * in_height + ix];
                    uint8_t value = in_ch[iy * in_height + ix + 1U];

                    if (value > max_value) {
                        max_value = value;
                    }
                    value = in_ch[(iy + 1U) * in_height + ix];
                    if (value > max_value) {
                        max_value = value;
                    }
                    value = in_ch[(iy + 1U) * in_height + ix + 1U];
                    if (value > max_value) {
                        max_value = value;
                    }
                    s_pool_out_pair[lane * out_ch_bytes + oy * out_height + ox] = max_value;
                }
            }
        }

        if (pool->write_output) {
            uint32_t out_addr = pool->output_base + c * out_ch_bytes;
            uint32_t write_size = pair_count * out_ch_bytes;

            if ((write_size & 1U) != 0U) {
                s_pool_out_pair[write_size] = 0U;
                write_size++;
            }
            if (!hram_write_bytes(w95_write, out_addr, s_pool_out_pair, write_size)) {
                return false;
            }
        }
    }

    return true;
}

static VGG16_SIZE_OPT bool run_vgg16_pool(W95_HandleTypeDef *w95_read,
                                          W95_HandleTypeDef *w95_write,
                                          const VGG16_PoolLayer_t *pool,
                                          tick_t *elapsed)
{
    tick_t start_tick;
    tick_t end_tick;
    bool ok;

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

    start_tick = read_tick();
    if (VGG16_DUMMY_CPU_MAXPOOL != 0U) {
        (void)w95_read;
        (void)w95_write;
        ok = true;
    } else if (((uint32_t)pool->in_height >> 1U) & 1U) {
        ok = run_pool5_odd_width(w95_read, w95_write, pool);
    } else {
        ok = run_even_width_pool(w95_read, w95_write, pool);
    }
    end_tick = read_tick();

    *elapsed = ticks_elapsed(start_tick, end_tick);
    if (!ok) {
        Uart_print("    ");
        Uart_print(pool->name);
        Uart_println(" failed.");
        return false;
    }

    Uart_println("    finished:");
    if (VGG16_DUMMY_CPU_MAXPOOL != 0U) {
        Uart_println("      Mode         : dummy, skipped HyperRAM read/write");
    }
    Uart_print("      Time         : ");
    print_tick_metric(*elapsed);
    Uart_println("");
    Uart_print("      Output bytes : ");
    print_u32_dec(pool_output_bytes(pool));
    Uart_println("");
    return true;
}

bool VGG16_Accel_RunTimingOnly(void)
{
    bool ok = true;
    bool old_video_enable;
    bool old_video_grant;
    uint8_t next_pool = 0U;
    W95_HandleTypeDef w95_h1_read;
    W95_HandleTypeDef w95_h1_write;
    tick_t conv_ticks = {0U, 0U};
    tick_t cpu_ticks = {0U, 0U};
    tick_t wall_start = {0U, 0U};
    tick_t wall_ticks = {0U, 0U};
    tick_t measured_ticks;

    Uart_println("");
    Uart_println("=== Run VGG16 CPU + accelerator timing ===");
    Uart_println("Timing-only path: no classification check and no payload validation.");
    Uart_println("Pipeline: 13 conv layers on accelerator, 5 max-pool layers on CPU.");
    Uart_print("  HR0 filter/bias footprint : ");
    print_u32_dec(VGG16_PARAM_BYTES);
    Uart_println(" bytes");
    Uart_print("  HR1 activation footprint  : ");
    print_u32_dec(VGG16_ACTIVATION_BYTES);
    Uart_println(" bytes");

    HyperRAM_init(&hyperram0, HYPERRAM_0_BASE_ADDR);
    HyperRAM_init(&hyperram1, HYPERRAM_1_BASE_ADDR);
    HyperRAM_set_accel_mode(&hyperram0, false);
    HyperRAM_set_accel_mode(&hyperram1, false);
    W95_Init(&w95_h1_read,
             &hyperram1,
             WEIGHT_HYPERRAM1_READ_LATENCY,
             WEIGHT_HYPERRAM1_READ_RECOVERY,
             WEIGHT_HYPERRAM1_READ_CAPTURE_SHMOO);
    W95_Init(&w95_h1_write,
             &hyperram1,
             WEIGHT_HYPERRAM1_WRITE_LATENCY,
             WEIGHT_HYPERRAM1_WRITE_RECOVERY,
             WEIGHT_HYPERRAM1_WRITE_CAPTURE_SHMOO);

    old_video_enable = VideoStreaming_is_enabled(&video_streaming);
    old_video_grant = VideoStreaming_get_grant_request(&video_streaming);
    VideoStreaming_enable(&video_streaming, false);
    VideoStreaming_set_grant_request(&video_streaming, false);

    if (!CNN_Accel_attach_irq(vgg16_irq_handler, 0, IRQ_PRIORITY_DEFAULT)) {
        Uart_println("  CNN IRQ attach failed.");
        ok = false;
    }

    if (ok) {
        CNN_Accel_enable_irq();
        HyperRAM_set_dmac_weights(&hyperram0, VGG16_DMAC_WRITE_WEIGHT, VGG16_DMAC_READ_WEIGHT);
        HyperRAM_set_dmac_weights(&hyperram1, VGG16_DMAC_WRITE_WEIGHT, VGG16_DMAC_READ_WEIGHT);
        HyperRAM_set_accel_mode(&hyperram0, true);
        HyperRAM_set_accel_mode(&hyperram1, true);
        wall_start = read_tick();
    }

    for (uint8_t i = 0U; ok && (i < VGG16_LAYER_COUNT); i++) {
        tick_t elapsed;

        HyperRAM_set_accel_mode(&hyperram0, true);
        HyperRAM_set_accel_mode(&hyperram1, true);
        ok = run_vgg16_layer(i, &elapsed);
        HyperRAM_set_accel_mode(&hyperram0, false);
        HyperRAM_set_accel_mode(&hyperram1, false);
        if (ok) {
            conv_ticks = ticks_add(conv_ticks, elapsed);
            print_layer_profile(&s_vgg16_layers[i], elapsed);
        }

        if (ok && (next_pool < VGG16_POOL_LAYER_COUNT) &&
            (s_vgg16_pools[next_pool].after_conv_idx == i)) {
            ok = run_vgg16_pool(&w95_h1_read, &w95_h1_write, &s_vgg16_pools[next_pool], &elapsed);
            if (ok) {
                cpu_ticks = ticks_add(cpu_ticks, elapsed);
                next_pool++;
            }
        }
    }

    if (ok) {
        wall_ticks = ticks_elapsed(wall_start, read_tick());
        measured_ticks = ticks_add(conv_ticks, cpu_ticks);
        Uart_println("");
        Uart_println("VGG16 timing summary:");
        Uart_print("  Accelerator conv layers : ");
        print_tick_metric(conv_ticks);
        Uart_println("");
        Uart_print("  Conv workload           : ");
        Uart_println(VGG16_TOTAL_MACS_TEXT " MACs");
        Uart_print("  Conv average cost       : ");
        print_cycles_per_unit(conv_ticks, VGG16_TOTAL_KMACS);
        Uart_println(" cycles / 1000 MACs");
        Uart_print("  CPU max-pool layers     : ");
        print_tick_metric(cpu_ticks);
        Uart_println("");
        Uart_print("  CPU max-pool output     : ");
        print_u32_dec(VGG16_POOL_BYTES);
        Uart_println(" bytes");
        Uart_print("  Full measured pipeline  : ");
        print_tick_metric(measured_ticks);
        Uart_println("  (conv + CPU max-pool)");
        Uart_print("  Wall section            : ");
        print_tick_metric(wall_ticks);
        Uart_println("  (includes UART/log overhead)");
    }

    CNN_Accel_disable_irq();
    HyperRAM_set_accel_mode(&hyperram0, false);
    HyperRAM_set_accel_mode(&hyperram1, false);
    VideoStreaming_set_grant_request(&video_streaming, old_video_grant);
    VideoStreaming_enable(&video_streaming, old_video_enable);

    Uart_println(ok ? "VGG16 CPU + accel timing -> DONE" : "VGG16 CPU + accel timing -> FAIL");
    return ok;
}

bool VGG16_Accel_RunLayer12Only(void)
{
    bool ok = true;
    bool old_video_enable;
    bool old_video_grant;
    tick_t elapsed = {0U, 0U};
    const uint8_t layer_idx = 11U;

    Uart_println("");
    Uart_println("=== Run VGG16 layer 12 only ===");
    Uart_println("Timing/debug path: no dependency preparation and no correctness check.");
    print_layer_addresses(&s_vgg16_layers[layer_idx]);

    HyperRAM_init(&hyperram0, HYPERRAM_0_BASE_ADDR);
    HyperRAM_init(&hyperram1, HYPERRAM_1_BASE_ADDR);
    HyperRAM_set_accel_mode(&hyperram0, false);
    HyperRAM_set_accel_mode(&hyperram1, false);

    old_video_enable = VideoStreaming_is_enabled(&video_streaming);
    old_video_grant = VideoStreaming_get_grant_request(&video_streaming);
    VideoStreaming_enable(&video_streaming, false);
    VideoStreaming_set_grant_request(&video_streaming, false);

    if (!CNN_Accel_attach_irq(vgg16_irq_handler, 0, IRQ_PRIORITY_DEFAULT)) {
        Uart_println("  CNN IRQ attach failed.");
        ok = false;
    }

    if (ok) {
        CNN_Accel_enable_irq();
        HyperRAM_set_dmac_weights(&hyperram0, VGG16_DMAC_WRITE_WEIGHT, VGG16_DMAC_READ_WEIGHT);
        HyperRAM_set_dmac_weights(&hyperram1, VGG16_DMAC_WRITE_WEIGHT, VGG16_DMAC_READ_WEIGHT);
        HyperRAM_set_accel_mode(&hyperram0, true);
        HyperRAM_set_accel_mode(&hyperram1, true);

        s_vgg16_debug_status = true;
        ok = run_vgg16_layer(layer_idx, &elapsed);
        s_vgg16_debug_status = false;

        HyperRAM_set_accel_mode(&hyperram0, false);
        HyperRAM_set_accel_mode(&hyperram1, false);
    }

    if (ok) {
        print_layer_profile(&s_vgg16_layers[layer_idx], elapsed);
    }

    CNN_Accel_disable_irq();
    HyperRAM_set_accel_mode(&hyperram0, false);
    HyperRAM_set_accel_mode(&hyperram1, false);
    VideoStreaming_set_grant_request(&video_streaming, old_video_grant);
    VideoStreaming_enable(&video_streaming, old_video_enable);

    Uart_println(ok ? "VGG16 layer 12 only -> DONE" : "VGG16 layer 12 only -> FAIL");
    return ok;
}

bool VGG16_Accel_RunLayer11Only(void)
{
    bool ok = true;
    bool old_video_enable;
    bool old_video_grant;
    tick_t elapsed = {0U, 0U};
    const uint8_t layer_idx = 10U;

    Uart_println("");
    Uart_println("=== Run VGG16 layer 11 only ===");
    Uart_println("Timing/debug path: no dependency preparation and no correctness check.");
    print_layer_addresses(&s_vgg16_layers[layer_idx]);

    HyperRAM_init(&hyperram0, HYPERRAM_0_BASE_ADDR);
    HyperRAM_init(&hyperram1, HYPERRAM_1_BASE_ADDR);
    HyperRAM_set_accel_mode(&hyperram0, false);
    HyperRAM_set_accel_mode(&hyperram1, false);

    old_video_enable = VideoStreaming_is_enabled(&video_streaming);
    old_video_grant = VideoStreaming_get_grant_request(&video_streaming);
    VideoStreaming_enable(&video_streaming, false);
    VideoStreaming_set_grant_request(&video_streaming, false);

    if (!CNN_Accel_attach_irq(vgg16_irq_handler, 0, IRQ_PRIORITY_DEFAULT)) {
        Uart_println("  CNN IRQ attach failed.");
        ok = false;
    }

    if (ok) {
        CNN_Accel_enable_irq();
        HyperRAM_set_dmac_weights(&hyperram0, VGG16_DMAC_WRITE_WEIGHT, VGG16_DMAC_READ_WEIGHT);
        HyperRAM_set_dmac_weights(&hyperram1, VGG16_DMAC_WRITE_WEIGHT, VGG16_DMAC_READ_WEIGHT);
        HyperRAM_set_accel_mode(&hyperram0, true);
        HyperRAM_set_accel_mode(&hyperram1, true);

        s_vgg16_debug_status = true;
        ok = run_vgg16_layer(layer_idx, &elapsed);
        s_vgg16_debug_status = false;

        HyperRAM_set_accel_mode(&hyperram0, false);
        HyperRAM_set_accel_mode(&hyperram1, false);
    }

    if (ok) {
        print_layer_profile(&s_vgg16_layers[layer_idx], elapsed);
    }

    CNN_Accel_disable_irq();
    HyperRAM_set_accel_mode(&hyperram0, false);
    HyperRAM_set_accel_mode(&hyperram1, false);
    VideoStreaming_set_grant_request(&video_streaming, old_video_grant);
    VideoStreaming_enable(&video_streaming, old_video_enable);

    Uart_println(ok ? "VGG16 layer 11 only -> DONE" : "VGG16 layer 11 only -> FAIL");
    return ok;
}

bool VGG16_Accel_RunLayer11WithFakeInput(void)
{
    bool ok = true;
    bool old_video_enable;
    bool old_video_grant;
    tick_t elapsed = {0U, 0U};
    const uint8_t layer_idx = 10U;
    const VGG16_Layer_t *layer = &s_vgg16_layers[layer_idx];
    W95_HandleTypeDef w95_h1_write;

    Uart_println("");
    Uart_println("=== Run VGG16 layer 11 with fake IFMAP ===");
    Uart_println("Debug path: CPU fills layer 11 IFMAP in HR1 before starting accel.");
    print_layer_addresses(layer);

    HyperRAM_init(&hyperram0, HYPERRAM_0_BASE_ADDR);
    HyperRAM_init(&hyperram1, HYPERRAM_1_BASE_ADDR);
    HyperRAM_set_accel_mode(&hyperram0, false);
    HyperRAM_set_accel_mode(&hyperram1, false);
    W95_Init(&w95_h1_write,
             &hyperram1,
             WEIGHT_HYPERRAM1_WRITE_LATENCY,
             WEIGHT_HYPERRAM1_WRITE_RECOVERY,
             WEIGHT_HYPERRAM1_WRITE_CAPTURE_SHMOO);

    old_video_enable = VideoStreaming_is_enabled(&video_streaming);
    old_video_grant = VideoStreaming_get_grant_request(&video_streaming);
    VideoStreaming_enable(&video_streaming, false);
    VideoStreaming_set_grant_request(&video_streaming, false);

    Uart_print("  Fill IFMAP bytes: ");
    print_u32_dec((uint32_t)layer->ifheight * (uint32_t)layer->ifheight * (uint32_t)layer->ifchannel);
    Uart_println("");
    if (!fill_hyperram1_region(&w95_h1_write,
                               layer->ifbaddr,
                               (uint32_t)layer->ifheight * (uint32_t)layer->ifheight * (uint32_t)layer->ifchannel)) {
        Uart_println("  IFMAP fill failed.");
        ok = false;
    }

    if (ok && !CNN_Accel_attach_irq(vgg16_irq_handler, 0, IRQ_PRIORITY_DEFAULT)) {
        Uart_println("  CNN IRQ attach failed.");
        ok = false;
    }

    if (ok) {
        CNN_Accel_enable_irq();
        HyperRAM_set_dmac_weights(&hyperram0, VGG16_DMAC_WRITE_WEIGHT, VGG16_DMAC_READ_WEIGHT);
        HyperRAM_set_dmac_weights(&hyperram1, VGG16_DMAC_WRITE_WEIGHT, VGG16_DMAC_READ_WEIGHT);
        HyperRAM_set_accel_mode(&hyperram0, true);
        HyperRAM_set_accel_mode(&hyperram1, true);

        s_vgg16_debug_status = true;
        ok = run_vgg16_layer(layer_idx, &elapsed);
        s_vgg16_debug_status = false;

        HyperRAM_set_accel_mode(&hyperram0, false);
        HyperRAM_set_accel_mode(&hyperram1, false);
    }

    if (ok) {
        print_layer_profile(layer, elapsed);
    }

    CNN_Accel_disable_irq();
    HyperRAM_set_accel_mode(&hyperram0, false);
    HyperRAM_set_accel_mode(&hyperram1, false);
    VideoStreaming_set_grant_request(&video_streaming, old_video_grant);
    VideoStreaming_enable(&video_streaming, old_video_enable);

    Uart_println(ok ? "VGG16 layer 11 fake IFMAP -> DONE" : "VGG16 layer 11 fake IFMAP -> FAIL");
    return ok;
}

bool VGG16_Accel_RunLayer11LowAddress(void)
{
    bool ok = true;
    bool old_video_enable;
    bool old_video_grant;
    tick_t elapsed = {0U, 0U};
    const uint8_t display_idx = 10U;
    const VGG16_Layer_t *layer = &s_vgg16_layer11_low_addr;

    Uart_println("");
    Uart_println("=== Run VGG16 layer 11 shape with low addresses ===");
    Uart_println("Debug path: same Conv5_1 shape, but IF/FLT/BIAS/OF use low HRAM addresses.");
    print_layer_addresses(layer);

    HyperRAM_init(&hyperram0, HYPERRAM_0_BASE_ADDR);
    HyperRAM_init(&hyperram1, HYPERRAM_1_BASE_ADDR);
    HyperRAM_set_accel_mode(&hyperram0, false);
    HyperRAM_set_accel_mode(&hyperram1, false);

    old_video_enable = VideoStreaming_is_enabled(&video_streaming);
    old_video_grant = VideoStreaming_get_grant_request(&video_streaming);
    VideoStreaming_enable(&video_streaming, false);
    VideoStreaming_set_grant_request(&video_streaming, false);

    if (!CNN_Accel_attach_irq(vgg16_irq_handler, 0, IRQ_PRIORITY_DEFAULT)) {
        Uart_println("  CNN IRQ attach failed.");
        ok = false;
    }

    if (ok) {
        CNN_Accel_enable_irq();
        HyperRAM_set_dmac_weights(&hyperram0, VGG16_DMAC_WRITE_WEIGHT, VGG16_DMAC_READ_WEIGHT);
        HyperRAM_set_dmac_weights(&hyperram1, VGG16_DMAC_WRITE_WEIGHT, VGG16_DMAC_READ_WEIGHT);
        HyperRAM_set_accel_mode(&hyperram0, true);
        HyperRAM_set_accel_mode(&hyperram1, true);

        s_vgg16_debug_status = true;
        ok = run_vgg16_layer_config(display_idx, layer, &elapsed);
        s_vgg16_debug_status = false;

        HyperRAM_set_accel_mode(&hyperram0, false);
        HyperRAM_set_accel_mode(&hyperram1, false);
    }

    if (ok) {
        print_layer_profile(layer, elapsed);
    }

    CNN_Accel_disable_irq();
    HyperRAM_set_accel_mode(&hyperram0, false);
    HyperRAM_set_accel_mode(&hyperram1, false);
    VideoStreaming_set_grant_request(&video_streaming, old_video_grant);
    VideoStreaming_enable(&video_streaming, old_video_enable);

    Uart_println(ok ? "VGG16 layer 11 low-address -> DONE" : "VGG16 layer 11 low-address -> FAIL");
    return ok;
}

bool VGG16_Accel_RunLayer10ThenLayer11LowAddress(void)
{
    bool ok = true;
    bool old_video_enable;
    bool old_video_grant;
    tick_t elapsed = {0U, 0U};

    Uart_println("");
    Uart_println("=== Run VGG16 layer 10 warm-up, then layer 11 low-address ===");
    Uart_println("Debug path: checks whether Conv5_1 shape needs a previous accel layer.");
    Uart_println("  Warm-up layer:");
    print_layer_addresses(&s_vgg16_layers[9]);
    Uart_println("  Test layer:");
    print_layer_addresses(&s_vgg16_layer11_low_addr);

    HyperRAM_init(&hyperram0, HYPERRAM_0_BASE_ADDR);
    HyperRAM_init(&hyperram1, HYPERRAM_1_BASE_ADDR);
    HyperRAM_set_accel_mode(&hyperram0, false);
    HyperRAM_set_accel_mode(&hyperram1, false);

    old_video_enable = VideoStreaming_is_enabled(&video_streaming);
    old_video_grant = VideoStreaming_get_grant_request(&video_streaming);
    VideoStreaming_enable(&video_streaming, false);
    VideoStreaming_set_grant_request(&video_streaming, false);

    if (!CNN_Accel_attach_irq(vgg16_irq_handler, 0, IRQ_PRIORITY_DEFAULT)) {
        Uart_println("  CNN IRQ attach failed.");
        ok = false;
    }

    if (ok) {
        CNN_Accel_enable_irq();
        HyperRAM_set_dmac_weights(&hyperram0, VGG16_DMAC_WRITE_WEIGHT, VGG16_DMAC_READ_WEIGHT);
        HyperRAM_set_dmac_weights(&hyperram1, VGG16_DMAC_WRITE_WEIGHT, VGG16_DMAC_READ_WEIGHT);
        HyperRAM_set_accel_mode(&hyperram0, true);
        HyperRAM_set_accel_mode(&hyperram1, true);

        s_vgg16_debug_status = true;
        ok = run_vgg16_layer(9U, &elapsed);
        if (ok) {
            print_layer_profile(&s_vgg16_layers[9], elapsed);
            ok = run_vgg16_layer_config(10U, &s_vgg16_layer11_low_addr, &elapsed);
        }
        s_vgg16_debug_status = false;

        HyperRAM_set_accel_mode(&hyperram0, false);
        HyperRAM_set_accel_mode(&hyperram1, false);
    }

    if (ok) {
        print_layer_profile(&s_vgg16_layer11_low_addr, elapsed);
    }

    CNN_Accel_disable_irq();
    HyperRAM_set_accel_mode(&hyperram0, false);
    HyperRAM_set_accel_mode(&hyperram1, false);
    VideoStreaming_set_grant_request(&video_streaming, old_video_grant);
    VideoStreaming_enable(&video_streaming, old_video_enable);

    Uart_println(ok ? "VGG16 warm-up + layer 11 low-address -> DONE" :
                      "VGG16 warm-up + layer 11 low-address -> FAIL");
    return ok;
}

bool VGG16_Accel_RunLayer10ThenTwoLowAddress(void)
{
    bool ok = true;
    bool old_video_enable;
    bool old_video_grant;
    tick_t elapsed = {0U, 0U};

    Uart_println("");
    Uart_println("=== Run VGG16 layer 10, then two low-address 14x14 layers ===");
    Uart_println("Debug path: checks whether consecutive Conv5-shaped layers hang.");
    Uart_println("  Warm-up layer:");
    print_layer_addresses(&s_vgg16_layers[9]);
    Uart_println("  Low-address Conv5-shaped layer:");
    print_layer_addresses(&s_vgg16_layer11_low_addr);

    HyperRAM_init(&hyperram0, HYPERRAM_0_BASE_ADDR);
    HyperRAM_init(&hyperram1, HYPERRAM_1_BASE_ADDR);
    HyperRAM_set_accel_mode(&hyperram0, false);
    HyperRAM_set_accel_mode(&hyperram1, false);

    old_video_enable = VideoStreaming_is_enabled(&video_streaming);
    old_video_grant = VideoStreaming_get_grant_request(&video_streaming);
    VideoStreaming_enable(&video_streaming, false);
    VideoStreaming_set_grant_request(&video_streaming, false);

    if (!CNN_Accel_attach_irq(vgg16_irq_handler, 0, IRQ_PRIORITY_DEFAULT)) {
        Uart_println("  CNN IRQ attach failed.");
        ok = false;
    }

    if (ok) {
        CNN_Accel_enable_irq();
        HyperRAM_set_dmac_weights(&hyperram0, VGG16_DMAC_WRITE_WEIGHT, VGG16_DMAC_READ_WEIGHT);
        HyperRAM_set_dmac_weights(&hyperram1, VGG16_DMAC_WRITE_WEIGHT, VGG16_DMAC_READ_WEIGHT);
        HyperRAM_set_accel_mode(&hyperram0, true);
        HyperRAM_set_accel_mode(&hyperram1, true);

        s_vgg16_debug_status = true;
        ok = run_vgg16_layer(9U, &elapsed);
        if (ok) {
            print_layer_profile(&s_vgg16_layers[9], elapsed);
            Uart_println("  First low-address Conv5-shaped run:");
            ok = run_vgg16_layer_config(10U, &s_vgg16_layer11_low_addr, &elapsed);
        }
        if (ok) {
            print_layer_profile(&s_vgg16_layer11_low_addr, elapsed);
            Uart_println("  Second low-address Conv5-shaped run:");
            ok = run_vgg16_layer_config(11U, &s_vgg16_layer11_low_addr, &elapsed);
        }
        s_vgg16_debug_status = false;

        HyperRAM_set_accel_mode(&hyperram0, false);
        HyperRAM_set_accel_mode(&hyperram1, false);
    }

    if (ok) {
        print_layer_profile(&s_vgg16_layer11_low_addr, elapsed);
    }

    CNN_Accel_disable_irq();
    HyperRAM_set_accel_mode(&hyperram0, false);
    HyperRAM_set_accel_mode(&hyperram1, false);
    VideoStreaming_set_grant_request(&video_streaming, old_video_grant);
    VideoStreaming_enable(&video_streaming, old_video_enable);

    Uart_println(ok ? "VGG16 warm-up + two low-address layers -> DONE" :
                      "VGG16 warm-up + two low-address layers -> FAIL");
    return ok;
}
