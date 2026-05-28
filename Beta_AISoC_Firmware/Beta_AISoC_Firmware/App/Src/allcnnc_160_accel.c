#include "allcnnc_160_accel.h"

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

#define ALLCNNC160_SIZE_OPT __attribute__((noinline, optimize("Os")))

#define ALLCNNC160_LAYER_COUNT               15U
#define ALLCNNC160_DMAC_WRITE_WEIGHT         1U
#define ALLCNNC160_DMAC_READ_WEIGHT          2U
#define ALLCNNC160_SUBMIT_WAIT_LIMIT         10000000U
#define ALLCNNC160_IRQ_WAIT_LIMIT            100000000U
#define ALLCNNC160_HRAM_DRAIN_WAIT_LIMIT     50000000U
#define ALLCNNC160_HRAM_DRAIN_STABLE_READS   128U
#define ALLCNNC160_VIDEO_WARMUP_MS           100U
#define ALLCNNC160_FINAL_ROW_BYTES           10U
#define ALLCNNC160_PARAM_BYTES_RESERVED      1574572U
#define ALLCNNC160_ACTIVATION_BYTES_RESERVED 3693100U
#define ALLCNNC160_LOWER_WRAP_MS             ((uint32_t)(0x100000000ULL / CYCLES_PER_MS))
#define ALLCNNC160_LOWER_WRAP_REM            ((uint32_t)(0x100000000ULL % CYCLES_PER_MS))

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
    int8_t   ifc_zp;
    int8_t   fltc_zp;
    int32_t  mult;
    uint8_t  mult_shift;
    int8_t   zpy;
    int8_t   qmin;
    int8_t   qmax;
    bool     is_leaky_relu;
} AllCNNC160_Layer_t;

typedef struct {
    bool old_video_enable;
    bool old_video_grant;
    W95_HandleTypeDef w95_h1_read;
} AllCNNC160_RunContext_t;

static const AllCNNC160_Layer_t s_allcnnc160_layers[ALLCNNC160_LAYER_COUNT] = {
    { "Conv1",  160U,   3U,  32U, 3U, 1U, 1U, 3U, 1U,  8U,       0U,       0U,     864U,   76800U,  -29,   0, 15574178, 31U, -128, -128, 127, false },
    { "Conv2",  160U,  32U,  32U, 3U, 1U, 1U, 4U, 1U,  8U,   76800U,     992U,   10208U,  896000U, -128,   0,  9680999, 31U, -128, -128, 127, false },
    { "Conv3",  160U,  32U,  64U, 3U, 2U, 1U, 4U, 1U,  8U,  896000U,   10336U,   28768U, 1715200U, -128,   0,  5206464, 31U, -128, -128, 127, false },
    { "Conv4",   80U,  64U,  64U, 3U, 1U, 1U, 4U, 1U,  8U, 1715200U,   29024U,   65888U, 2124800U, -128,   0,  3066080, 31U, -128, -128, 127, false },
    { "Conv5",   80U,  64U,  64U, 3U, 1U, 1U, 4U, 1U,  8U, 2124800U,   66144U,  103008U, 2534400U, -128,   0,  3654338, 31U, -128, -128, 127, false },
    { "Conv6",   80U,  64U,  96U, 3U, 2U, 1U, 4U, 1U,  8U, 2534400U,  103264U,  158560U, 2944000U, -128,   0,  3744344, 31U, -128, -128, 127, false },
    { "Conv7",   40U,  96U,  96U, 3U, 1U, 1U, 3U, 1U,  8U, 2944000U,  158944U,  241888U, 3097600U, -128,   0,  2451837, 31U, -128, -128, 127, false },
    { "Conv8",   40U,  96U, 128U, 3U, 1U, 1U, 3U, 1U,  8U, 3097600U,  242272U,  352864U, 3251200U, -128,   0,  2644252, 31U, -128, -128, 127, false },
    { "Conv9",   40U, 128U, 128U, 3U, 2U, 1U, 4U, 1U,  8U, 3251200U,  353376U,  500832U, 3456000U, -128,   0,  2079880, 31U, -128, -128, 127, false },
    { "Conv10",  20U, 128U, 128U, 3U, 1U, 1U, 4U, 1U,  8U, 3456000U,  501344U,  648800U, 3507200U, -128,   0,  1824581, 31U, -128, -128, 127, false },
    { "Conv11",  20U, 128U, 192U, 3U, 1U, 1U, 4U, 1U,  8U, 3507200U,  649312U,  870496U, 3558400U, -128,   0,  2350214, 31U, -128, -128, 127, false },
    { "Conv12",  20U, 192U, 192U, 3U, 2U, 1U, 4U, 1U,  8U, 3558400U,  871264U, 1203040U, 3635200U, -128,   0,  2358843, 31U, -128, -128, 127, false },
    { "Conv13",  10U, 192U, 192U, 3U, 1U, 1U, 4U, 1U,  8U, 3635200U, 1203808U, 1535584U, 3654400U, -128,   0,  2144944, 31U, -128, -128, 127, false },
    { "Conv14",  10U, 192U, 192U, 1U, 1U, 0U, 4U, 1U, 24U, 3654400U, 1536352U, 1573216U, 3673600U, -128,   0,  6865615, 31U, -128, -128, 127, false },
    { "Conv15",  10U, 192U,   3U, 1U, 1U, 0U, 4U, 1U,  3U, 3673600U, 1573984U, 1574560U, 3692800U, -128,   0,   637054, 31U,  -10, -128, 127, true },
};

static volatile bool s_allcnnc160_irq_seen;
static uint8_t s_allcnnc160_gap_row[ALLCNNC160_FINAL_ROW_BYTES];
static volatile int32_t s_allcnnc160_gap_sink;
static const char *const s_allcnnc160_labels[] = { "paper", "rock", "scissors" };

static ALLCNNC160_SIZE_OPT void print_u32_dec(uint32_t value)
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

static ALLCNNC160_SIZE_OPT void print_i32_dec(int32_t value)
{
    if (value < 0) {
        uint32_t magnitude = (uint32_t)(-(value + 1)) + 1U;
        Uart_write('-');
        print_u32_dec(magnitude);
    } else {
        print_u32_dec((uint32_t)value);
    }
}

static ALLCNNC160_SIZE_OPT tick_t ticks_elapsed(tick_t start, tick_t end)
{
    tick_t diff;

    diff.lower = end.lower - start.lower;
    diff.upper = (end.upper - start.upper) & COUNTER_MAX_UPPER;
    if (end.lower < start.lower) {
        diff.upper = (diff.upper - 1U) & COUNTER_MAX_UPPER;
    }

    return diff;
}

static ALLCNNC160_SIZE_OPT tick_t ticks_add(tick_t a, tick_t b)
{
    tick_t sum;

    sum.lower = a.lower + b.lower;
    sum.upper = (a.upper + b.upper) & COUNTER_MAX_UPPER;
    if (sum.lower < a.lower) {
        sum.upper = (sum.upper + 1U) & COUNTER_MAX_UPPER;
    }

    return sum;
}

static ALLCNNC160_SIZE_OPT uint32_t ticks_to_ms(tick_t ticks)
{
    uint32_t ms = ticks.upper * ALLCNNC160_LOWER_WRAP_MS + ticks.lower / CYCLES_PER_MS;
    uint32_t rem = ticks.upper * ALLCNNC160_LOWER_WRAP_REM + ticks.lower % CYCLES_PER_MS;

    ms += rem / CYCLES_PER_MS;
    return ms;
}

static ALLCNNC160_SIZE_OPT uint8_t tick_cycles_to_digits(tick_t ticks,
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

static ALLCNNC160_SIZE_OPT void print_tick_cycles(tick_t ticks)
{
    uint8_t digits[20];
    uint8_t count = tick_cycles_to_digits(ticks, digits, sizeof(digits));

    while (count > 0U) {
        Uart_write((uint8_t)('0' + digits[--count]));
    }
}

static ALLCNNC160_SIZE_OPT void print_tick_metric(tick_t ticks)
{
    print_tick_cycles(ticks);
    Uart_print(" cycles (");
    print_u32_dec(ticks_to_ms(ticks));
    Uart_print(" ms)");
}

static ALLCNNC160_SIZE_OPT uint32_t ticks_to_u32_saturated(tick_t ticks)
{
    return (ticks.upper != 0U) ? 0xFFFFFFFFU : ticks.lower;
}

static ALLCNNC160_SIZE_OPT void print_cycles_per_unit(tick_t ticks, uint32_t units)
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

static ALLCNNC160_SIZE_OPT uint32_t layer_ofwidth(const AllCNNC160_Layer_t *layer)
{
    uint32_t padded = (uint32_t)layer->ifheight + ((uint32_t)layer->padding << 1U);
    uint32_t span = (padded >= layer->hf) ? (padded - (uint32_t)layer->hf) : 0U;

    return (span / (uint32_t)layer->stride) + 1U;
}

static ALLCNNC160_SIZE_OPT uint32_t layer_ofmap_bytes(const AllCNNC160_Layer_t *layer)
{
    uint32_t ofwidth = layer_ofwidth(layer);

    return ofwidth * ofwidth * (uint32_t)layer->ofchannel;
}

static ALLCNNC160_SIZE_OPT uint32_t layer_macs(const AllCNNC160_Layer_t *layer)
{
    return layer_ofmap_bytes(layer) *
           (uint32_t)layer->ifchannel *
           (uint32_t)layer->hf *
           (uint32_t)layer->hf;
}

static ALLCNNC160_SIZE_OPT uint32_t total_conv_macs(void)
{
    uint32_t total = 0U;

    for (uint32_t i = 0U; i < ALLCNNC160_LAYER_COUNT; i++) {
        total += layer_macs(&s_allcnnc160_layers[i]);
    }

    return total;
}

static ALLCNNC160_SIZE_OPT void print_cnn_status(const char *prefix, uint32_t status)
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

static ALLCNNC160_SIZE_OPT void print_hyperram_status(const char *name,
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

static ALLCNNC160_SIZE_OPT bool wait_hyperram_master_idle(const char *name,
                                                          HyperRAM_Driver_t *drv)
{
    uint32_t wait = ALLCNNC160_HRAM_DRAIN_WAIT_LIMIT;
    uint32_t stable = 0U;

    while (wait > 0U) {
        if (HyperRAM_is_start_ready(drv)) {
            stable++;
            if (stable >= ALLCNNC160_HRAM_DRAIN_STABLE_READS) {
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

static void allcnnc160_irq_handler(uint32_t irq_bit, void *context)
{
    (void)irq_bit;
    (void)context;
    s_allcnnc160_irq_seen = true;
}

static ALLCNNC160_SIZE_OPT void fill_layer_config(const AllCNNC160_Layer_t *layer,
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

    config->ifc_zp = layer->ifc_zp;
    config->fltc_zp = layer->fltc_zp;
    config->mult = layer->mult;
    config->mult_shift = layer->mult_shift;
    config->alphamult = layer->is_leaky_relu ? 1 : 0;
    config->alphamult_shift = 0U;
    config->zpy = layer->zpy;
    config->qmin = layer->qmin;
    config->qmax = layer->qmax;
    config->is_leaky_relu = layer->is_leaky_relu;
}

static ALLCNNC160_SIZE_OPT void print_layer_config(const AllCNNC160_Layer_t *layer)
{
    Uart_print("      cfg k/s/p    : ");
    print_u32_dec(layer->hf);
    Uart_write('/');
    print_u32_dec(layer->stride);
    Uart_write('/');
    print_u32_dec(layer->padding);
    Uart_print("  Nip/Npass/Nfp=");
    print_u32_dec(layer->ifparr);
    Uart_write('/');
    print_u32_dec(layer->oftile);
    Uart_write('/');
    print_u32_dec(layer->ofparr);
    Uart_println("");
    Uart_print("      addr if/flt/bias/of: ");
    print_u32_dec(layer->ifbaddr);
    Uart_write('/');
    print_u32_dec(layer->fltbaddr);
    Uart_write('/');
    print_u32_dec(layer->bias_baddr);
    Uart_write('/');
    print_u32_dec(layer->ofbaddr);
    Uart_println("");
}

static ALLCNNC160_SIZE_OPT bool run_layer(uint8_t idx,
                                          const AllCNNC160_Layer_t *layer,
                                          bool verbose,
                                          tick_t *elapsed)
{
    CNN_Accel_LayerConfig_t config;
    tick_t start_tick;
    tick_t end_tick;
    uint32_t wait = ALLCNNC160_IRQ_WAIT_LIMIT;
    uint32_t status;
    bool done_seen = false;

    fill_layer_config(layer, &config);
    s_allcnnc160_irq_seen = false;

    if (verbose) {
        Uart_print("  Layer ");
        print_u32_dec((uint32_t)idx + 1U);
        Uart_write(' ');
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
        print_layer_config(layer);
    }

    status = CNN_Accel_get_status(&cnn_accel);
    if ((status & CNN_ACCEL_STATUS_BUSY_Msk) != 0U) {
        print_cnn_status("    CNN busy before layer:", status);
        return false;
    }

    start_tick = read_tick();

    if (!CNN_Accel_submit_layer_config(&cnn_accel, &config, ALLCNNC160_SUBMIT_WAIT_LIMIT)) {
        print_cnn_status("    submit timeout:", CNN_Accel_get_status(&cnn_accel));
        return false;
    }

    CNN_Accel_start(&cnn_accel);

    while (wait > 0U) {
        status = CNN_Accel_get_status(&cnn_accel);
        if (s_allcnnc160_irq_seen || ((status & CNN_ACCEL_STATUS_DONE_Msk) != 0U)) {
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

    if (!CNN_Accel_wait_idle(&cnn_accel, ALLCNNC160_SUBMIT_WAIT_LIMIT)) {
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

static ALLCNNC160_SIZE_OPT void print_layer_profile(const AllCNNC160_Layer_t *layer,
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

static ALLCNNC160_SIZE_OPT bool run_global_avgpool(W95_HandleTypeDef *w95_read,
                                                   const AllCNNC160_Layer_t *layer,
                                                   bool verbose,
                                                   int32_t *logits_out,
                                                   tick_t *elapsed)
{
    tick_t start_tick;
    tick_t end_tick;
    uint32_t h = layer_ofwidth(layer);
    uint32_t ch_bytes = h * h;
    int32_t sink = 0;

    if (h > ALLCNNC160_FINAL_ROW_BYTES) {
        return false;
    }

    if (verbose) {
        Uart_print("  CPU GlobalAvgPool: ");
        print_u32_dec(h);
        Uart_write('x');
        print_u32_dec(h);
        Uart_write('x');
        print_u32_dec(layer->ofchannel);
        Uart_print(" -> ");
        print_u32_dec(layer->ofchannel);
        Uart_println(" logits");
    }

    start_tick = read_tick();

    for (uint32_t c = 0U; c < layer->ofchannel; c++) {
        int32_t sum = 0;
        uint32_t ch_base = layer->ofbaddr + c * ch_bytes;

        for (uint32_t y = 0U; y < h; y++) {
            W95_MemoryRead(w95_read, ch_base + y * h, s_allcnnc160_gap_row, h, true);
            for (uint32_t x = 0U; x < h; x++) {
                sum += (int32_t)(int8_t)s_allcnnc160_gap_row[x] - (int32_t)layer->zpy;
            }
        }
        sum /= (int32_t)ch_bytes;
        if (logits_out != 0) {
            logits_out[c] = sum;
        }
        sink += sum;
    }

    s_allcnnc160_gap_sink = sink;
    end_tick = read_tick();
    *elapsed = ticks_elapsed(start_tick, end_tick);

    if (verbose) {
        Uart_println("    finished:");
        Uart_print("      Time         : ");
        print_tick_metric(*elapsed);
        Uart_println("");
        Uart_print("      Read bytes   : ");
        print_u32_dec(ch_bytes * (uint32_t)layer->ofchannel);
        Uart_println("");
    }
    return true;
}

static ALLCNNC160_SIZE_OPT bool begin_run_context(AllCNNC160_RunContext_t *context,
                                                     bool use_camera_ifmap)
{
    HyperRAM_init(&hyperram0, HYPERRAM_0_BASE_ADDR);
    HyperRAM_init(&hyperram1, HYPERRAM_1_BASE_ADDR);
    HyperRAM_set_accel_mode(&hyperram0, false);
    HyperRAM_set_accel_mode(&hyperram1, false);
    W95_Init(&context->w95_h1_read,
             &hyperram1,
             WEIGHT_HYPERRAM1_READ_LATENCY,
             WEIGHT_HYPERRAM1_READ_RECOVERY,
             WEIGHT_HYPERRAM1_READ_CAPTURE_SHMOO);

    context->old_video_enable = VideoStreaming_is_enabled(&video_streaming);
    context->old_video_grant = VideoStreaming_get_grant_request(&video_streaming);
    VideoStreaming_set_grant_request(&video_streaming, false);
    VideoStreaming_enable(&video_streaming, use_camera_ifmap);
    if (use_camera_ifmap) {
        delay(ALLCNNC160_VIDEO_WARMUP_MS);
    }

    if (!CNN_Accel_attach_irq(allcnnc160_irq_handler, 0, IRQ_PRIORITY_DEFAULT)) {
        Uart_println("  CNN IRQ attach failed.");
        return false;
    }

    CNN_Accel_enable_irq();
    HyperRAM_set_dmac_weights(&hyperram0, ALLCNNC160_DMAC_WRITE_WEIGHT, ALLCNNC160_DMAC_READ_WEIGHT);
    HyperRAM_set_dmac_weights(&hyperram1, ALLCNNC160_DMAC_WRITE_WEIGHT, ALLCNNC160_DMAC_READ_WEIGHT);
    return true;
}

static ALLCNNC160_SIZE_OPT void end_run_context(const AllCNNC160_RunContext_t *context)
{
    CNN_Accel_disable_irq();
    HyperRAM_set_accel_mode(&hyperram0, false);
    HyperRAM_set_accel_mode(&hyperram1, false);
    VideoStreaming_set_grant_request(&video_streaming, context->old_video_grant);
    VideoStreaming_enable(&video_streaming, context->old_video_enable);
}

static ALLCNNC160_SIZE_OPT bool run_model_once(AllCNNC160_RunContext_t *context,
                                               bool verbose,
                                               bool use_camera_ifmap,
                                               int32_t *logits_out,
                                               tick_t *conv_ticks,
                                               tick_t *cpu_ticks,
                                               tick_t *wall_ticks)
{
    bool ok = true;
    tick_t wall_start;

    conv_ticks->lower = 0U;
    conv_ticks->upper = 0U;
    cpu_ticks->lower = 0U;
    cpu_ticks->upper = 0U;
    wall_ticks->lower = 0U;
    wall_ticks->upper = 0U;

    HyperRAM_set_accel_mode(&hyperram0, true);
    HyperRAM_set_accel_mode(&hyperram1, true);
    wall_start = read_tick();

    for (uint8_t i = 0U; ok && (i < ALLCNNC160_LAYER_COUNT); i++) {
        tick_t elapsed;

        HyperRAM_set_accel_mode(&hyperram0, true);
        HyperRAM_set_accel_mode(&hyperram1, true);
        if (use_camera_ifmap && (i == 0U)) {
            VideoStreaming_set_grant_request(&video_streaming, true);
        }
        ok = run_layer(i, &s_allcnnc160_layers[i], verbose, &elapsed);
        if (use_camera_ifmap && (i == 0U)) {
            VideoStreaming_set_grant_request(&video_streaming, false);
        }
        HyperRAM_set_accel_mode(&hyperram0, false);
        HyperRAM_set_accel_mode(&hyperram1, false);
        if (ok) {
            *conv_ticks = ticks_add(*conv_ticks, elapsed);
            if (verbose) {
                print_layer_profile(&s_allcnnc160_layers[i], elapsed);
            }
        }
    }

    if (ok) {
        tick_t elapsed;

        ok = run_global_avgpool(&context->w95_h1_read,
                                &s_allcnnc160_layers[ALLCNNC160_LAYER_COUNT - 1U],
                                verbose,
                                logits_out,
                                &elapsed);
        if (ok) {
            *cpu_ticks = ticks_add(*cpu_ticks, elapsed);
        } else {
            Uart_println("    GlobalAvgPool failed.");
        }
    }

    if (ok) {
        *wall_ticks = ticks_elapsed(wall_start, read_tick());
    }

    return ok;
}

bool AllCNNC160_Accel_RunTimingOnly(void)
{
    bool ok;
    AllCNNC160_RunContext_t context;
    tick_t conv_ticks = {0U, 0U};
    tick_t cpu_ticks = {0U, 0U};
    tick_t wall_ticks = {0U, 0U};
    tick_t measured_ticks;
    uint32_t conv_macs = total_conv_macs();

    Uart_println("");
    Uart_println("=== Run ALL-CNN-C-160 accelerator timing ===");
    Uart_println("Timing-only path: no classification check and no payload validation.");
    Uart_println("Pipeline: camera IFMAP, conv layers on accelerator, final GAP on CPU.");
    Uart_print("  Conv layers              : ");
    print_u32_dec(ALLCNNC160_LAYER_COUNT);
    Uart_println("");
    Uart_print("  Conv head classes        : ");
    print_u32_dec(s_allcnnc160_layers[ALLCNNC160_LAYER_COUNT - 1U].ofchannel);
    Uart_println("");
    Uart_print("  HR0 filter/bias reserved : ");
    print_u32_dec(ALLCNNC160_PARAM_BYTES_RESERVED);
    Uart_println(" bytes");
    Uart_print("  HR1 activation reserved  : ");
    print_u32_dec(ALLCNNC160_ACTIVATION_BYTES_RESERVED);
    Uart_println(" bytes");
    Uart_print("  Conv workload            : ");
    print_u32_dec(conv_macs);
    Uart_println(" MACs");

    ok = begin_run_context(&context, true);
    if (ok) {
        ok = run_model_once(&context, true, true, 0, &conv_ticks, &cpu_ticks, &wall_ticks);
    }

    if (ok) {
        measured_ticks = ticks_add(conv_ticks, cpu_ticks);
        Uart_println("");
        Uart_println("ALL-CNN-C-160 timing summary:");
        Uart_print("  Accelerator conv layers : ");
        print_tick_metric(conv_ticks);
        Uart_println("");
        Uart_print("  Conv workload           : ");
        print_u32_dec(conv_macs);
        Uart_println(" MACs");
        Uart_print("  Conv average cost       : ");
        print_cycles_per_unit(conv_ticks, conv_macs / 1000U);
        Uart_println(" cycles / 1000 MACs");
        Uart_print("  CPU GAP layer           : ");
        print_tick_metric(cpu_ticks);
        Uart_println("");
        Uart_print("  Full measured pipeline  : ");
        print_tick_metric(measured_ticks);
        Uart_println("  (conv + CPU post-processing)");
        Uart_print("  Wall section            : ");
        print_tick_metric(wall_ticks);
        Uart_println("  (includes UART/log overhead)");
    }

    end_run_context(&context);

    Uart_println(ok ? "ALL-CNN-C-160 timing -> DONE" : "ALL-CNN-C-160 timing -> FAIL");
    return ok;
}

static ALLCNNC160_SIZE_OPT uint8_t argmax_logits(const int32_t *logits)
{
    uint8_t best = 0U;

    for (uint8_t i = 1U; i < 3U; i++) {
        if (logits[i] > logits[best]) {
            best = i;
        }
    }

    return best;
}

static ALLCNNC160_SIZE_OPT void print_result_line(const int32_t *logits,
                                                   tick_t conv_ticks,
                                                   tick_t cpu_ticks,
                                                   tick_t wall_ticks)
{
    uint8_t label = argmax_logits(logits);
    tick_t total_ticks = ticks_add(conv_ticks, cpu_ticks);

    Uart_write('\r');
    Uart_print("SOC_RESULT label=");
    Uart_print(s_allcnnc160_labels[label]);
    Uart_print(" logits=");
    print_i32_dec(logits[0]);
    Uart_write(',');
    print_i32_dec(logits[1]);
    Uart_write(',');
    print_i32_dec(logits[2]);
    Uart_print(" conv_ms=");
    print_u32_dec(ticks_to_ms(conv_ticks));
    Uart_print(" cpu_ms=");
    print_u32_dec(ticks_to_ms(cpu_ticks));
    Uart_print(" total_ms=");
    print_u32_dec(ticks_to_ms(total_ticks));
    Uart_print(" wall_ms=");
    print_u32_dec(ticks_to_ms(wall_ticks));
    Uart_print("   ");
    Uart_write('\r');
}

bool AllCNNC160_Accel_RunCameraResultLoop(void)
{
    AllCNNC160_RunContext_t context;
    bool ok;

    Uart_println("");
    Uart_println("Camera result loop, q to stop:");

    ok = begin_run_context(&context, true);

    while (ok) {
        tick_t conv_ticks;
        tick_t cpu_ticks;
        tick_t wall_ticks;
        int32_t logits[3];
        uint8_t rx_data;

        ok = run_model_once(&context, false, true, logits, &conv_ticks, &cpu_ticks, &wall_ticks);
        if (!ok) {
            break;
        }

        print_result_line(logits, conv_ticks, cpu_ticks, wall_ticks);

        if (Uart_read(&rx_data) && ((rx_data == 'q') || (rx_data == 'Q'))) {
            break;
        }
    }

    Uart_println("");
    end_run_context(&context);
    Uart_println(ok ? "ALL-CNN-C-160 camera loop -> DONE" : "ALL-CNN-C-160 camera loop -> FAIL");
    return ok;
}
