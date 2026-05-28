#include "squeezenet_accel.h"

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

#define SQUEEZENET_SIZE_OPT __attribute__((noinline, optimize("Os")))

#define SQUEEZENET_LAYER_COUNT              26U
#define SQUEEZENET_POOL_COUNT               3U
#define SQUEEZENET_DMAC_WRITE_WEIGHT        1U
#define SQUEEZENET_DMAC_READ_WEIGHT         2U
#define SQUEEZENET_SUBMIT_WAIT_LIMIT        10000000U
#define SQUEEZENET_IRQ_WAIT_LIMIT           100000000U
#define SQUEEZENET_HRAM_DRAIN_WAIT_LIMIT    50000000U
#define SQUEEZENET_HRAM_DRAIN_STABLE_READS  128U
#define SQUEEZENET_HRAM_RW_BUF_BYTES        256U
#define SQUEEZENET_HRAM_BLOCK_CHUNK_BYTES   254U
#define SQUEEZENET_MAX_ROW_BYTES            47U
#define SQUEEZENET_MAX_POOL_INPUT_BYTES     (SQUEEZENET_MAX_ROW_BYTES * SQUEEZENET_MAX_ROW_BYTES)
#define SQUEEZENET_MAX_POOL_OUTPUT_EDGE     (SQUEEZENET_MAX_ROW_BYTES >> 1U)
#define SQUEEZENET_MAX_POOL_OUTPUT_BYTES    (SQUEEZENET_MAX_POOL_OUTPUT_EDGE * SQUEEZENET_MAX_POOL_OUTPUT_EDGE)
#define SQUEEZENET_LOWER_WRAP_MS            ((uint32_t)(0x100000000ULL / CYCLES_PER_MS))
#define SQUEEZENET_LOWER_WRAP_REM           ((uint32_t)(0x100000000ULL % CYCLES_PER_MS))
#define SQUEEZENET_PARAM_BYTES_RESERVED     732876U
#define SQUEEZENET_ACTIVATION_BYTES_RESERVED 257227U

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
} SqueezeNet_Layer_t;

typedef struct {
    const char *name;
    uint8_t after_layer_idx;
    uint16_t in_height;
    uint16_t channels;
    uint32_t input_base;
    uint32_t output_base;
} SqueezeNet_Pool_t;

static const SqueezeNet_Layer_t s_squeezenet_layers[SQUEEZENET_LAYER_COUNT] = {
    { "Conv1", 96U, 3U, 64U, 3U, 2U, 0U, 3U, 1U, 8U, 0U, 0U, 1728U, 27648U },
    { "Fire2_sq1x1", 23U, 64U, 16U, 1U, 1U, 0U, 4U, 1U, 16U, 27648U, 1984U, 3008U, 61504U },
    { "Fire2_exp1x1", 23U, 16U, 64U, 1U, 1U, 0U, 4U, 1U, 22U, 61504U, 3072U, 4096U, 69968U },
    { "Fire2_exp3x3", 23U, 16U, 64U, 3U, 1U, 1U, 4U, 1U, 8U, 61504U, 4352U, 13568U, 103824U },
    { "Fire3_sq1x1", 23U, 128U, 16U, 1U, 1U, 0U, 4U, 1U, 16U, 69968U, 13824U, 15872U, 137680U },
    { "Fire3_exp1x1", 23U, 16U, 64U, 1U, 1U, 0U, 4U, 1U, 22U, 137680U, 15936U, 16960U, 146144U },
    { "Fire3_exp3x3", 23U, 16U, 64U, 3U, 1U, 1U, 4U, 1U, 8U, 137680U, 17216U, 26432U, 180000U },
    { "Fire4_sq1x1", 11U, 128U, 32U, 1U, 1U, 0U, 4U, 1U, 16U, 146144U, 26688U, 30784U, 161632U },
    { "Fire4_exp1x1", 11U, 32U, 128U, 1U, 1U, 0U, 4U, 1U, 22U, 161632U, 30912U, 35008U, 165504U },
    { "Fire4_exp3x3", 11U, 32U, 128U, 3U, 1U, 1U, 4U, 1U, 8U, 161632U, 35520U, 72384U, 180992U },
    { "Fire5_sq1x1", 11U, 256U, 32U, 1U, 1U, 0U, 4U, 1U, 16U, 165504U, 72896U, 81088U, 196480U },
    { "Fire5_exp1x1", 11U, 32U, 128U, 1U, 1U, 0U, 4U, 1U, 22U, 196480U, 81216U, 85312U, 200352U },
    { "Fire5_exp3x3", 11U, 32U, 128U, 3U, 1U, 1U, 4U, 1U, 8U, 196480U, 85824U, 122688U, 215840U },
    { "Fire6_sq1x1", 5U, 256U, 48U, 1U, 1U, 0U, 4U, 1U, 24U, 200352U, 123200U, 135488U, 206752U },
    { "Fire6_exp1x1", 5U, 48U, 192U, 1U, 1U, 0U, 4U, 1U, 24U, 206752U, 135680U, 144896U, 207952U },
    { "Fire6_exp3x3", 5U, 48U, 192U, 3U, 1U, 1U, 4U, 1U, 8U, 206752U, 145664U, 228608U, 212752U },
    { "Fire7_sq1x1", 5U, 384U, 48U, 1U, 1U, 0U, 3U, 1U, 24U, 207952U, 229376U, 247808U, 217552U },
    { "Fire7_exp1x1", 5U, 48U, 192U, 1U, 1U, 0U, 4U, 1U, 24U, 217552U, 248000U, 257216U, 218752U },
    { "Fire7_exp3x3", 5U, 48U, 192U, 3U, 1U, 1U, 4U, 1U, 8U, 217552U, 257984U, 340928U, 223552U },
    { "Fire8_sq1x1", 5U, 384U, 64U, 1U, 1U, 0U, 3U, 1U, 22U, 218752U, 341696U, 366272U, 228352U },
    { "Fire8_exp1x1", 5U, 64U, 256U, 1U, 1U, 0U, 4U, 1U, 24U, 228352U, 366528U, 382912U, 229952U },
    { "Fire8_exp3x3", 5U, 64U, 256U, 3U, 1U, 1U, 4U, 1U, 8U, 228352U, 383936U, 531392U, 236352U },
    { "Fire9_sq1x1", 5U, 512U, 64U, 1U, 1U, 0U, 4U, 1U, 22U, 229952U, 532416U, 565184U, 242752U },
    { "Fire9_exp1x1", 5U, 64U, 256U, 1U, 1U, 0U, 4U, 1U, 24U, 242752U, 565440U, 581824U, 244352U },
    { "Fire9_exp3x3", 5U, 64U, 256U, 3U, 1U, 1U, 4U, 1U, 8U, 242752U, 582848U, 730304U, 250752U },
    { "Conv10", 5U, 512U, 3U, 1U, 1U, 0U, 4U, 1U, 3U, 244352U, 731328U, 732864U, 257152U },
};

static const SqueezeNet_Pool_t s_squeezenet_pools[SQUEEZENET_POOL_COUNT] = {
    { "MaxPool1", 0U, 47U,  64U,  27648U,  27648U },
    { "MaxPool2", 6U, 23U, 128U, 146144U, 146144U },
    { "MaxPool3", 12U, 11U, 256U, 200352U, 200352U },
};

static volatile bool s_squeezenet_irq_seen;
static uint8_t s_hyperram_rw_buf[SQUEEZENET_HRAM_RW_BUF_BYTES];
static uint8_t s_pool_channel_in[SQUEEZENET_MAX_POOL_INPUT_BYTES];
static uint8_t s_pool_channel_out[SQUEEZENET_MAX_POOL_OUTPUT_BYTES];
static uint8_t s_gap_row[SQUEEZENET_MAX_ROW_BYTES];
static volatile int32_t s_gap_sink;

static SQUEEZENET_SIZE_OPT void copy_u8_no_libcall(uint8_t *dst,
                                                   const uint8_t *src,
                                                   uint32_t size)
{
    volatile uint8_t *vdst = (volatile uint8_t *)dst;
    const volatile uint8_t *vsrc = (const volatile uint8_t *)src;

    for (uint32_t i = 0U; i < size; i++) {
        vdst[i] = vsrc[i];
    }
}

static SQUEEZENET_SIZE_OPT void print_u32_dec(uint32_t value)
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

static SQUEEZENET_SIZE_OPT tick_t ticks_elapsed(tick_t start, tick_t end)
{
    tick_t diff;

    diff.lower = end.lower - start.lower;
    diff.upper = (end.upper - start.upper) & COUNTER_MAX_UPPER;
    if (end.lower < start.lower) {
        diff.upper = (diff.upper - 1U) & COUNTER_MAX_UPPER;
    }

    return diff;
}

static SQUEEZENET_SIZE_OPT tick_t ticks_add(tick_t a, tick_t b)
{
    tick_t sum;

    sum.lower = a.lower + b.lower;
    sum.upper = (a.upper + b.upper) & COUNTER_MAX_UPPER;
    if (sum.lower < a.lower) {
        sum.upper = (sum.upper + 1U) & COUNTER_MAX_UPPER;
    }

    return sum;
}

static SQUEEZENET_SIZE_OPT uint32_t ticks_to_ms(tick_t ticks)
{
    uint32_t ms = ticks.upper * SQUEEZENET_LOWER_WRAP_MS + ticks.lower / CYCLES_PER_MS;
    uint32_t rem = ticks.upper * SQUEEZENET_LOWER_WRAP_REM + ticks.lower % CYCLES_PER_MS;

    ms += rem / CYCLES_PER_MS;
    return ms;
}

static SQUEEZENET_SIZE_OPT uint8_t tick_cycles_to_digits(tick_t ticks,
                                                         uint8_t *digits,
                                                         uint8_t max_digits)
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

static SQUEEZENET_SIZE_OPT void print_tick_cycles(tick_t ticks)
{
    uint8_t digits[20];
    uint8_t count = tick_cycles_to_digits(ticks, digits, sizeof(digits));

    while (count > 0U) {
        Uart_write((uint8_t)('0' + digits[--count]));
    }
}

static SQUEEZENET_SIZE_OPT void print_tick_metric(tick_t ticks)
{
    print_tick_cycles(ticks);
    Uart_print(" cycles (");
    print_u32_dec(ticks_to_ms(ticks));
    Uart_print(" ms)");
}

static SQUEEZENET_SIZE_OPT uint32_t ticks_to_u32_saturated(tick_t ticks)
{
    return (ticks.upper != 0U) ? 0xFFFFFFFFU : ticks.lower;
}

static SQUEEZENET_SIZE_OPT void print_cycles_per_unit(tick_t ticks, uint32_t units)
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

static SQUEEZENET_SIZE_OPT uint32_t layer_ofwidth(const SqueezeNet_Layer_t *layer)
{
    uint32_t padded = (uint32_t)layer->ifheight + ((uint32_t)layer->padding << 1U);
    uint32_t span = (padded >= layer->hf) ? (padded - (uint32_t)layer->hf) : 0U;

    return (span / (uint32_t)layer->stride) + 1U;
}

static SQUEEZENET_SIZE_OPT uint32_t layer_ofmap_bytes(const SqueezeNet_Layer_t *layer)
{
    uint32_t ofwidth = layer_ofwidth(layer);

    return ofwidth * ofwidth * (uint32_t)layer->ofchannel;
}

static SQUEEZENET_SIZE_OPT uint32_t layer_macs(const SqueezeNet_Layer_t *layer)
{
    return layer_ofmap_bytes(layer) *
           (uint32_t)layer->ifchannel *
           (uint32_t)layer->hf *
           (uint32_t)layer->hf;
}

static SQUEEZENET_SIZE_OPT uint32_t total_conv_macs(void)
{
    uint32_t total = 0U;

    for (uint32_t i = 0U; i < SQUEEZENET_LAYER_COUNT; i++) {
        total += layer_macs(&s_squeezenet_layers[i]);
    }

    return total;
}

static SQUEEZENET_SIZE_OPT void print_cnn_status(const char *prefix, uint32_t status)
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

static SQUEEZENET_SIZE_OPT void print_hyperram_status(const char *name,
                                                      HyperRAM_Driver_t *drv)
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

static SQUEEZENET_SIZE_OPT bool wait_hyperram_master_idle(const char *name,
                                                          HyperRAM_Driver_t *drv)
{
    uint32_t wait = SQUEEZENET_HRAM_DRAIN_WAIT_LIMIT;
    uint32_t stable = 0U;

    while (wait > 0U) {
        if (HyperRAM_is_start_ready(drv)) {
            stable++;
            if (stable >= SQUEEZENET_HRAM_DRAIN_STABLE_READS) {
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

static SQUEEZENET_SIZE_OPT bool hram_read_aligned(W95_HandleTypeDef *w95,
                                                  uint32_t addr,
                                                  uint8_t *dst,
                                                  uint32_t size)
{
    if (((addr & 1U) != 0U) || ((size & 1U) != 0U)) {
        return false;
    }

    W95_MemoryRead(w95, addr, dst, size, true);
    return true;
}

static SQUEEZENET_SIZE_OPT bool hram_write_aligned(W95_HandleTypeDef *w95,
                                                   uint32_t addr,
                                                   const uint8_t *src,
                                                   uint32_t size)
{
    if (((addr & 1U) != 0U) || ((size & 1U) != 0U)) {
        return false;
    }

    W95_MemoryWrite(w95, addr, src, size, true);
    return true;
}

static SQUEEZENET_SIZE_OPT bool hram_read_any(W95_HandleTypeDef *w95,
                                              uint32_t addr,
                                              uint8_t *dst,
                                              uint32_t size)
{
    uint32_t offset = addr & 1U;
    uint32_t aligned_addr = addr & ~1U;
    uint32_t aligned_size = (offset + size + 1U) & ~1U;

    if ((size == 0U) || (aligned_size > SQUEEZENET_HRAM_RW_BUF_BYTES)) {
        return false;
    }

    if (!hram_read_aligned(w95, aligned_addr, s_hyperram_rw_buf, aligned_size)) {
        return false;
    }

    copy_u8_no_libcall(dst, &s_hyperram_rw_buf[offset], size);

    return true;
}

static SQUEEZENET_SIZE_OPT bool hram_write_any(W95_HandleTypeDef *w95,
                                               uint32_t addr,
                                               const uint8_t *src,
                                               uint32_t size)
{
    uint32_t offset = addr & 1U;
    uint32_t aligned_addr = addr & ~1U;
    uint32_t aligned_size = (offset + size + 1U) & ~1U;

    if ((size == 0U) || (aligned_size > SQUEEZENET_HRAM_RW_BUF_BYTES)) {
        return false;
    }

    if ((offset != 0U) || ((size & 1U) != 0U)) {
        if (!hram_read_aligned(w95, aligned_addr, s_hyperram_rw_buf, aligned_size)) {
            return false;
        }
    }

    copy_u8_no_libcall(&s_hyperram_rw_buf[offset], src, size);

    return hram_write_aligned(w95, aligned_addr, s_hyperram_rw_buf, aligned_size);
}

static SQUEEZENET_SIZE_OPT bool hram_read_block_any(W95_HandleTypeDef *w95,
                                                    uint32_t addr,
                                                    uint8_t *dst,
                                                    uint32_t size)
{
    uint32_t done = 0U;

    while (done < size) {
        uint32_t chunk = size - done;

        if (chunk > SQUEEZENET_HRAM_BLOCK_CHUNK_BYTES) {
            chunk = SQUEEZENET_HRAM_BLOCK_CHUNK_BYTES;
        }
        if (!hram_read_any(w95, addr + done, &dst[done], chunk)) {
            return false;
        }
        done += chunk;
    }

    return true;
}

static SQUEEZENET_SIZE_OPT bool hram_write_block_any(W95_HandleTypeDef *w95,
                                                     uint32_t addr,
                                                     const uint8_t *src,
                                                     uint32_t size)
{
    uint32_t done = 0U;

    while (done < size) {
        uint32_t chunk = size - done;

        if (chunk > SQUEEZENET_HRAM_BLOCK_CHUNK_BYTES) {
            chunk = SQUEEZENET_HRAM_BLOCK_CHUNK_BYTES;
        }
        if (!hram_write_any(w95, addr + done, &src[done], chunk)) {
            return false;
        }
        done += chunk;
    }

    return true;
}

static void squeezenet_irq_handler(uint32_t irq_bit, void *context)
{
    (void)irq_bit;
    (void)context;
    s_squeezenet_irq_seen = true;
}

static SQUEEZENET_SIZE_OPT void fill_layer_config(const SqueezeNet_Layer_t *layer,
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

    /*
     * Placeholder quantization. Replace these fields from the exported INT8
     * model when real SqueezeNet weights/biases are packed.
     */
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

static SQUEEZENET_SIZE_OPT bool run_layer(uint8_t idx,
                                          const SqueezeNet_Layer_t *layer,
                                          tick_t *elapsed)
{
    CNN_Accel_LayerConfig_t config;
    tick_t start_tick;
    tick_t end_tick;
    uint32_t wait = SQUEEZENET_IRQ_WAIT_LIMIT;
    uint32_t status;
    bool done_seen = false;

    fill_layer_config(layer, &config);
    s_squeezenet_irq_seen = false;

    Uart_print("  Layer ");
    print_u32_dec((uint32_t)idx + 1U);
    Uart_print(" ");
    Uart_print(layer->name);
    Uart_print(": ");
    print_u32_dec(layer->ifheight);
    Uart_write('x');
    print_u32_dec(layer->ifheight);
    Uart_write('x');
    print_u32_dec(layer->ifchannel);
    Uart_print(" -> ");
    print_u32_dec(layer_ofwidth(layer));
    Uart_write('x');
    print_u32_dec(layer_ofwidth(layer));
    Uart_write('x');
    print_u32_dec(layer->ofchannel);
    Uart_println("");

    status = CNN_Accel_get_status(&cnn_accel);
    if ((status & CNN_ACCEL_STATUS_BUSY_Msk) != 0U) {
        print_cnn_status("    CNN busy before layer:", status);
        return false;
    }

    start_tick = read_tick();

    if (!CNN_Accel_submit_layer_config(&cnn_accel, &config, SQUEEZENET_SUBMIT_WAIT_LIMIT)) {
        print_cnn_status("    submit timeout:", CNN_Accel_get_status(&cnn_accel));
        return false;
    }

    CNN_Accel_start(&cnn_accel);

    while (wait > 0U) {
        status = CNN_Accel_get_status(&cnn_accel);
        if (s_squeezenet_irq_seen || ((status & CNN_ACCEL_STATUS_DONE_Msk) != 0U)) {
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
        print_cnn_status("    IRQ timeout:", status);
        print_hyperram_status("HR0", &hyperram0);
        print_hyperram_status("HR1", &hyperram1);
        return false;
    }

    if (!CNN_Accel_wait_idle(&cnn_accel, SQUEEZENET_SUBMIT_WAIT_LIMIT)) {
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

static SQUEEZENET_SIZE_OPT void print_layer_profile(const SqueezeNet_Layer_t *layer,
                                                    tick_t ticks)
{
    uint32_t macs = layer_macs(layer);

    Uart_println("    finished:");
    Uart_print("      Time         : ");
    print_tick_metric(ticks);
    Uart_println("");
    Uart_print("      Workload     : ");
    print_u32_dec(macs);
    Uart_println(" MACs");
    Uart_print("      Output bytes : ");
    print_u32_dec(layer_ofmap_bytes(layer));
    Uart_println("");
    Uart_print("      Cost         : ");
    print_cycles_per_unit(ticks, macs / 1000U);
    Uart_println(" cycles / 1000 MACs");
}

static SQUEEZENET_SIZE_OPT uint32_t pool_out_height(const SqueezeNet_Pool_t *pool)
{
    return (uint32_t)pool->in_height >> 1U;
}

static SQUEEZENET_SIZE_OPT uint32_t pool_output_bytes(const SqueezeNet_Pool_t *pool)
{
    uint32_t out_h = pool_out_height(pool);

    return out_h * out_h * (uint32_t)pool->channels;
}

static SQUEEZENET_SIZE_OPT bool run_pool(W95_HandleTypeDef *w95_read,
                                         W95_HandleTypeDef *w95_write,
                                         const SqueezeNet_Pool_t *pool,
                                         tick_t *elapsed)
{
    tick_t start_tick;
    tick_t end_tick;
    uint32_t in_h = pool->in_height;
    uint32_t out_h = pool_out_height(pool);
    uint32_t in_ch_bytes = in_h * in_h;
    uint32_t out_ch_bytes = out_h * out_h;

    if ((in_ch_bytes > SQUEEZENET_MAX_POOL_INPUT_BYTES) ||
        (out_ch_bytes > SQUEEZENET_MAX_POOL_OUTPUT_BYTES)) {
        return false;
    }

    Uart_print("  CPU ");
    Uart_print(pool->name);
    Uart_print(": ");
    print_u32_dec(pool->in_height);
    Uart_write('x');
    print_u32_dec(pool->in_height);
    Uart_write('x');
    print_u32_dec(pool->channels);
    Uart_print(" -> ");
    print_u32_dec(out_h);
    Uart_write('x');
    print_u32_dec(out_h);
    Uart_write('x');
    print_u32_dec(pool->channels);
    Uart_println("");

    start_tick = read_tick();

    for (uint32_t c = 0U; c < pool->channels; c++) {
        uint32_t in_ch_base = pool->input_base + c * in_ch_bytes;
        uint32_t out_ch_base = pool->output_base + c * out_ch_bytes;

        if (!hram_read_block_any(w95_read, in_ch_base, s_pool_channel_in, in_ch_bytes)) {
            return false;
        }

        for (uint32_t oy = 0U; oy < out_h; oy++) {
            uint32_t y0 = oy << 1U;
            uint32_t out_row_base = oy * out_h;

            for (uint32_t ox = 0U; ox < out_h; ox++) {
                uint32_t x0 = ox << 1U;
                int8_t max_value = (int8_t)-128;

                for (uint8_t ry = 0U; ry < 3U; ry++) {
                    uint32_t in_row_base = (y0 + (uint32_t)ry) * in_h;

                    for (uint8_t kx = 0U; kx < 3U; kx++) {
                        int8_t value = (int8_t)s_pool_channel_in[in_row_base + x0 + (uint32_t)kx];

                        if (value > max_value) {
                            max_value = value;
                        }
                    }
                }

                s_pool_channel_out[out_row_base + ox] = (uint8_t)max_value;
            }
        }

        if (!hram_write_block_any(w95_write, out_ch_base, s_pool_channel_out, out_ch_bytes)) {
            return false;
        }
    }

    end_tick = read_tick();
    *elapsed = ticks_elapsed(start_tick, end_tick);

    Uart_println("    finished:");
    Uart_print("      Time         : ");
    print_tick_metric(*elapsed);
    Uart_println("");
    Uart_print("      Output bytes : ");
    print_u32_dec(pool_output_bytes(pool));
    Uart_println("");
    return true;
}

static SQUEEZENET_SIZE_OPT bool run_global_avgpool(W95_HandleTypeDef *w95_read,
                                                   const SqueezeNet_Layer_t *layer,
                                                   tick_t *elapsed)
{
    tick_t start_tick;
    tick_t end_tick;
    uint32_t h = layer_ofwidth(layer);
    uint32_t ch_bytes = h * h;
    int32_t sink = 0;

    Uart_print("  CPU GlobalAvgPool: ");
    print_u32_dec(h);
    Uart_write('x');
    print_u32_dec(h);
    Uart_write('x');
    print_u32_dec(layer->ofchannel);
    Uart_print(" -> ");
    print_u32_dec(layer->ofchannel);
    Uart_println(" logits");

    start_tick = read_tick();

    for (uint32_t c = 0U; c < layer->ofchannel; c++) {
        int32_t sum = 0;
        uint32_t ch_base = layer->ofbaddr + c * ch_bytes;

        for (uint32_t y = 0U; y < h; y++) {
            if (!hram_read_any(w95_read, ch_base + y * h, s_gap_row, h)) {
                return false;
            }
            for (uint32_t x = 0U; x < h; x++) {
                sum += (int32_t)(int8_t)s_gap_row[x];
            }
        }
        sink += sum / (int32_t)ch_bytes;
    }

    s_gap_sink = sink;
    end_tick = read_tick();
    *elapsed = ticks_elapsed(start_tick, end_tick);

    Uart_println("    finished:");
    Uart_print("      Time         : ");
    print_tick_metric(*elapsed);
    Uart_println("");
    Uart_print("      Read bytes   : ");
    print_u32_dec(ch_bytes * (uint32_t)layer->ofchannel);
    Uart_println("");
    return true;
}

bool SqueezeNet_Accel_RunTimingOnly(void)
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
    uint32_t conv_macs = total_conv_macs();

    Uart_println("");
    Uart_println("=== Run SqueezeNet-96 accelerator timing ===");
    Uart_println("Timing-only path: no classification check and no payload validation.");
    Uart_println("Pipeline: conv layers on accelerator, max-pool/GAP on CPU.");
    Uart_print("  Conv head classes        : ");
    print_u32_dec(s_squeezenet_layers[SQUEEZENET_LAYER_COUNT - 1U].ofchannel);
    Uart_println("");
    Uart_print("  HR0 filter/bias reserved : ");
    print_u32_dec(SQUEEZENET_PARAM_BYTES_RESERVED);
    Uart_println(" bytes");
    Uart_print("  HR1 activation reserved  : ");
    print_u32_dec(SQUEEZENET_ACTIVATION_BYTES_RESERVED);
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

    if (!CNN_Accel_attach_irq(squeezenet_irq_handler, 0, IRQ_PRIORITY_DEFAULT)) {
        Uart_println("  CNN IRQ attach failed.");
        ok = false;
    }

    if (ok) {
        CNN_Accel_enable_irq();
        HyperRAM_set_dmac_weights(&hyperram0, SQUEEZENET_DMAC_WRITE_WEIGHT, SQUEEZENET_DMAC_READ_WEIGHT);
        HyperRAM_set_dmac_weights(&hyperram1, SQUEEZENET_DMAC_WRITE_WEIGHT, SQUEEZENET_DMAC_READ_WEIGHT);
        HyperRAM_set_accel_mode(&hyperram0, true);
        HyperRAM_set_accel_mode(&hyperram1, true);
        wall_start = read_tick();
    }

    for (uint8_t i = 0U; ok && (i < SQUEEZENET_LAYER_COUNT); i++) {
        tick_t elapsed;

        HyperRAM_set_accel_mode(&hyperram0, true);
        HyperRAM_set_accel_mode(&hyperram1, true);
        ok = run_layer(i, &s_squeezenet_layers[i], &elapsed);
        HyperRAM_set_accel_mode(&hyperram0, false);
        HyperRAM_set_accel_mode(&hyperram1, false);
        if (ok) {
            conv_ticks = ticks_add(conv_ticks, elapsed);
            print_layer_profile(&s_squeezenet_layers[i], elapsed);
        }

        if (ok && (next_pool < SQUEEZENET_POOL_COUNT) &&
            (s_squeezenet_pools[next_pool].after_layer_idx == i)) {
            ok = run_pool(&w95_h1_read, &w95_h1_write, &s_squeezenet_pools[next_pool], &elapsed);
            if (ok) {
                cpu_ticks = ticks_add(cpu_ticks, elapsed);
                next_pool++;
            } else {
                Uart_println("    MaxPool failed.");
            }
        }
    }

    if (ok) {
        tick_t elapsed;

        ok = run_global_avgpool(&w95_h1_read,
                                &s_squeezenet_layers[SQUEEZENET_LAYER_COUNT - 1U],
                                &elapsed);
        if (ok) {
            cpu_ticks = ticks_add(cpu_ticks, elapsed);
        } else {
            Uart_println("    GlobalAvgPool failed.");
        }
    }

    if (ok) {
        wall_ticks = ticks_elapsed(wall_start, read_tick());
        measured_ticks = ticks_add(conv_ticks, cpu_ticks);
        Uart_println("");
        Uart_println("SqueezeNet-96 timing summary:");
        Uart_print("  Accelerator conv layers : ");
        print_tick_metric(conv_ticks);
        Uart_println("");
        Uart_print("  Conv workload           : ");
        print_u32_dec(conv_macs);
        Uart_println(" MACs");
        Uart_print("  Conv average cost       : ");
        print_cycles_per_unit(conv_ticks, conv_macs / 1000U);
        Uart_println(" cycles / 1000 MACs");
        Uart_print("  CPU pool/GAP layers     : ");
        print_tick_metric(cpu_ticks);
        Uart_println("");
        Uart_print("  Full measured pipeline  : ");
        print_tick_metric(measured_ticks);
        Uart_println("  (conv + CPU post-processing)");
        Uart_print("  Wall section            : ");
        print_tick_metric(wall_ticks);
        Uart_println("  (includes UART/log overhead)");
    }

    CNN_Accel_disable_irq();
    HyperRAM_set_accel_mode(&hyperram0, false);
    HyperRAM_set_accel_mode(&hyperram1, false);
    VideoStreaming_set_grant_request(&video_streaming, old_video_grant);
    VideoStreaming_enable(&video_streaming, old_video_enable);

    Uart_println(ok ? "SqueezeNet-96 timing -> DONE" : "SqueezeNet-96 timing -> FAIL");
    return ok;
}
