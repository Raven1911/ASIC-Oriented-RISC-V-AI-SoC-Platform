#include "allcnn_cifar10_accel.h"

#include <stdint.h>

#include "allcnn_cifar10.h"
#include "CNN_Accel_Driver.h"
#include "flash_utils.h"
#include "HyperRAM_Driver.h"
#include "Interrupt_Driver.h"
#include "timer.h"
#include "UART_Driver.h"
#include "VideoStreaming_Driver.h"
#include "W95_HyperRAM.h"
#include "weight_hyperram_loader.h"

#define ACCEL_SIZE_OPT __attribute__((noinline, optimize("Os,no-tree-loop-distribute-patterns")))

#define ACCEL_CONV1_IN_H              32U
#define ACCEL_CONV1_IN_W              32U
#define ACCEL_CONV1_IN_C              3U
#define ACCEL_CONV1_OUT_H             32U
#define ACCEL_CONV1_OUT_W             32U
#define ACCEL_CONV1_OUT_C             96U
#define ACCEL_CONV1_K                 3U
#define ACCEL_CONV1_STRIDE            1U
#define ACCEL_CONV1_PADDING           1U

#define ACCEL_CONV1_WEIGHT_OFFSET     4U
#define ACCEL_CONV1_WEIGHT_SIZE       2592U
#define ACCEL_CONV1_BIAS_OFFSET       1368484U
#define ACCEL_CONV1_BIAS_SIZE         384U
#define ACCEL_ALLCNN_BLOB_BYTES       1373516U

#define ACCEL_CONV1_IN_ZP             ((int8_t)0)
#define ACCEL_CONV1_WEIGHT_ZP         ((int8_t)0)
#define ACCEL_CONV1_OUT_ZP            ((int8_t)-128)
#define ACCEL_CONV1_MULT              1455152256
#define ACCEL_CONV1_SHIFT             38U
#define ACCEL_CONV1_QMIN              ((int8_t)-128)
#define ACCEL_CONV1_QMAX              ((int8_t)127)

#define ACCEL_VIDEO_IFMAP_SCALE_MULT  714582423
#define ACCEL_VIDEO_IFMAP_SCALE_SHIFT 25U
#define ACCEL_VIDEO_IFMAP_ZP          ((int8_t)0)
#define ACCEL_VIDEO_IFMAP_WARMUP_MS   100U

#define ACCEL_CONV1_VERIFY_OUT_C      ACCEL_CONV1_OUT_C
#define ACCEL_CONV1_VERIFY_OUT_H      ACCEL_CONV1_OUT_H

#define ACCEL_IFPARR                  3U
#define ACCEL_OFPARR                  8U
#define ACCEL_OFTILE                  1U
#define ACCEL_M                       2U
#define ACCEL_MAX_OUT_C               192U
#define ACCEL_FULL_LAYER_COUNT        9U
#define ACCEL_MAX_ROWS_PER_LANE       16U
#define ACCEL_MAX_OFTILE              4U
#define ACCEL_MAX_FILTERS_PER_BURST   32U
#define ACCEL_PACK_BUF_BYTES          512U
#define ACCEL_FULL_GROUP_BUF_BYTES    18432U
#define ACCEL_FULL_FILTER_BUF_BYTES   1728U
#define ACCEL_HRAM_CHUNK_BYTES        256U

#define ACCEL_FULL_HRAM0_PARAM_BASE   0x00180000U
#define ACCEL_HRAM1_IFMAP_BASE        0x00000000U
#define ACCEL_HRAM1_OFMAP_BASE        0x00000C00U
#define ACCEL_HRAM0_FLT_BASE          (ACCEL_FULL_HRAM0_PARAM_BASE + 0x00000000U)
#define ACCEL_HRAM0_BIAS_BASE         (ACCEL_FULL_HRAM0_PARAM_BASE + 0x00000A20U)
#define ACCEL_FULL_FINAL_OFMAP_BASE   0x00057C00U
#define ACCEL_FULL_FINAL_OFMAP_HW     6U
#define ACCEL_FULL_FINAL_OFMAP_C      10U
#define ACCEL_FULL_AVGPOOL_IN_ZP      ((int8_t)-128)
#define ACCEL_FULL_AVGPOOL_OUT_ZP     ((int8_t)-128)
#define ACCEL_FULL_AVGPOOL_MULT       1779742231
#define ACCEL_FULL_AVGPOOL_SHIFT      34U

#define ACCEL_IRQ_WAIT_LIMIT          20000000U
#define ACCEL_SUBMIT_WAIT_LIMIT       10000000U
#define ACCEL_OFBUF_POST_IRQ_DELAY    0U
#define ACCEL_HRAM_DRAIN_WAIT_LIMIT   1000000U
#define ACCEL_HRAM_DRAIN_STABLE_READS 64U
#define ACCEL_DMAC_WRITE_WEIGHT       1U
#define ACCEL_DMAC_READ_WEIGHT        2U
#define ACCEL_LOWER_WRAP_MS           ((uint32_t)(0x100000000ULL / CYCLES_PER_MS))
#define ACCEL_LOWER_WRAP_REM          ((uint32_t)(0x100000000ULL % CYCLES_PER_MS))

#define ACCEL_UART_STREAM_SOF         0xC5U
#define ACCEL_UART_STREAM_EOF         0x5CU
#define ACCEL_UART_STREAM_MAX_PAYLOAD 1024U
#define ACCEL_UART_STREAM_TIMEOUT_MS  5000U
#define ACCEL_UART_STREAM_FRAME_MS    200U
#define ACCEL_UART_STREAM_ACK         0x79U
#define ACCEL_UART_STREAM_NACK        0x1FU
#define ACCEL_UART_STREAM_ERROR       0xEEU
#define ACCEL_UART_STREAM_CMD_INFO    0x01U
#define ACCEL_UART_STREAM_CMD_DATA    0x02U
#define ACCEL_UART_STREAM_CMD_RUN     0x03U
#define ACCEL_UART_STREAM_CMD_END     0x04U
#define ACCEL_UART_STREAM_ERR_LENGTH  0x01U
#define ACCEL_UART_STREAM_ERR_STATE   0x02U
#define ACCEL_UART_STREAM_ERR_CRC     0x03U
#define ACCEL_UART_STREAM_ERR_RUN     0x04U
#define ACCEL_UART_STREAM_ERR_ADDR    0x05U
#define ACCEL_UART_STREAM_IMAGE_BYTES (ACCEL_CONV1_IN_H * ACCEL_CONV1_IN_W * ACCEL_CONV1_IN_C)

typedef struct {
    uint32_t weight_offset;
    uint32_t weight_size;
    uint32_t bias_offset;
    uint32_t bias_size;
} AccelRawParamMeta_t;

typedef struct {
    uint8_t seq;
    uint8_t cmd;
    uint16_t len;
    uint8_t payload[ACCEL_UART_STREAM_MAX_PAYLOAD];
} AccelStreamFrame_t;

typedef struct {
    bool active;
    uint32_t image_index;
    uint32_t expected_crc32;
    uint32_t received_bytes;
    uint8_t expected_label;
} AccelStreamSession_t;

typedef struct {
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
} AccelFullLayer_t;

static const AccelRawParamMeta_t s_full_raw_meta[ACCEL_FULL_LAYER_COUNT] = {
    {       4U,   2592U, 1368484U,  384U },
    {    2596U,  82944U, 1368868U,  384U },
    {   85540U,  82944U, 1369252U,  384U },
    {  168484U, 165888U, 1369636U,  768U },
    {  334372U, 331776U, 1370404U,  768U },
    {  666148U, 331776U, 1371172U,  768U },
    {  997924U, 331776U, 1371940U,  768U },
    { 1329700U,  36864U, 1372708U,  768U },
    { 1366564U,   1920U, 1373476U,   40U },
};

static const AccelFullLayer_t s_full_layers[ACCEL_FULL_LAYER_COUNT] = {
    { 32U,   3U,  96U, 3U, 1U, 1U, 3U, 1U,  8U,      0U,       0U,    2592U,   3072U,     0,    0, 1455152256, 38U, -128, -128, 127 },
    { 32U,  96U,  96U, 3U, 1U, 1U, 3U, 1U,  8U,   3072U,    2976U,   85920U, 101376U,  -128,    0, 1129969408, 40U, -128, -128, 127 },
    { 32U,  96U,  96U, 3U, 2U, 1U, 3U, 1U,  8U, 101376U,   86304U,  169248U, 199680U,  -128,    0, 1793910272, 41U, -128, -128, 127 },
    { 16U,  96U, 192U, 3U, 1U, 1U, 3U, 1U,  8U, 199680U,  169632U,  335520U, 224256U,  -128,    0, 1090411904, 41U, -128, -128, 127 },
    { 16U, 192U, 192U, 3U, 1U, 1U, 3U, 1U,  8U, 224256U,  336288U,  668064U, 273408U,  -128,    0, 1923875712, 40U, -128, -128, 127 },
    { 16U, 192U, 192U, 3U, 2U, 1U, 4U, 1U,  8U, 273408U,  668832U, 1000608U, 322560U,  -128,    0, 1852283136, 40U, -128, -128, 127 },
    {  8U, 192U, 192U, 3U, 1U, 0U, 3U, 1U,  8U, 322560U, 1001376U, 1333152U, 334848U,  -128,    0, 1241329664, 40U, -128, -128, 127 },
    {  6U, 192U, 192U, 1U, 1U, 0U, 2U, 1U, 24U, 334848U, 1333920U, 1370784U, 347136U,  -128,    0, 1540656768, 39U, -128, -128, 127 },
    {  6U, 192U,  10U, 1U, 1U, 0U, 2U, 1U, 10U, 347136U, 1371552U, 1373472U, 359424U,  -128,    0, 1289010560, 39U, -128, -128, 127 },
};

static uint8_t s_conv1_weight[ACCEL_CONV1_WEIGHT_SIZE];
static int32_t s_conv1_bias[ACCEL_CONV1_OUT_C];
static uint8_t s_pack_buf[ACCEL_PACK_BUF_BYTES];
static uint8_t s_readback_buf[ACCEL_PACK_BUF_BYTES];
static uint8_t s_full_group_buf[ACCEL_FULL_GROUP_BUF_BYTES];
static uint8_t s_full_filter_buf[ACCEL_FULL_FILTER_BUF_BYTES];
static uint8_t s_accel_row[ACCEL_CONV1_OUT_W];
static int16_t s_slot_ch[ACCEL_M][ACCEL_MAX_ROWS_PER_LANE][ACCEL_MAX_OFTILE];
static uint8_t s_lane_rows[ACCEL_M];
static int16_t s_lane_seq[ACCEL_M][ACCEL_MAX_OUT_C];
static uint8_t s_lane_seq_used[ACCEL_M][ACCEL_MAX_OUT_C];
static AccelStreamFrame_t s_stream_frame;
static AccelStreamSession_t s_stream_session;
static volatile bool s_accel_irq_seen;
static bool s_conv1_payload_ready;
static bool s_full_payload_ready;
static bool s_conv1_source_params_ready;

static bool cnn_status_has(uint32_t status, uint32_t mask)
{
    return (status & mask) != 0U;
}

static ACCEL_SIZE_OPT void print_cnn_status(const char *prefix, uint32_t status)
{
    Uart_print(prefix);
    Uart_print(" STATUS=0x");
    Uart_print_hex_32(status);
    Uart_print(" table_vld=");
    Uart_write(cnn_status_has(status, CNN_ACCEL_STATUS_TABLE_VALID_Msk) ? '1' : '0');
    Uart_print(" table_rdy=");
    Uart_write(cnn_status_has(status, CNN_ACCEL_STATUS_TABLE_READY_Msk) ? '1' : '0');
    Uart_print(" busy=");
    Uart_write(cnn_status_has(status, CNN_ACCEL_STATUS_BUSY_Msk) ? '1' : '0');
    Uart_print(" done=");
    Uart_write(cnn_status_has(status, CNN_ACCEL_STATUS_DONE_Msk) ? '1' : '0');
    Uart_print(" start=");
    Uart_write(cnn_status_has(status, CNN_ACCEL_STATUS_START_Msk) ? '1' : '0');
    Uart_println("");
}

static ACCEL_SIZE_OPT void print_u32_dec(uint32_t value)
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

static ACCEL_SIZE_OPT void print_i32_dec(int32_t value)
{
    if (value < 0) {
        uint32_t magnitude = (uint32_t)(-(value + 1)) + 1U;
        Uart_write('-');
        print_u32_dec(magnitude);
    } else {
        print_u32_dec((uint32_t)value);
    }
}

static ACCEL_SIZE_OPT tick_t accel_elapsed_ticks(tick_t start, tick_t end)
{
    tick_t diff;

    diff.lower = end.lower - start.lower;
    diff.upper = (end.upper - start.upper) & COUNTER_MAX_UPPER;
    if (end.lower < start.lower) {
        diff.upper = (diff.upper - 1U) & COUNTER_MAX_UPPER;
    }

    return diff;
}

static ACCEL_SIZE_OPT tick_t accel_add_ticks(tick_t a, tick_t b)
{
    tick_t sum;

    sum.lower = a.lower + b.lower;
    sum.upper = (a.upper + b.upper) & COUNTER_MAX_UPPER;
    if (sum.lower < a.lower) {
        sum.upper = (sum.upper + 1U) & COUNTER_MAX_UPPER;
    }

    return sum;
}

static ACCEL_SIZE_OPT uint32_t accel_ticks_to_ms(tick_t ticks)
{
    uint32_t ms = ticks.upper * ACCEL_LOWER_WRAP_MS + ticks.lower / CYCLES_PER_MS;
    uint32_t rem = ticks.upper * ACCEL_LOWER_WRAP_REM + ticks.lower % CYCLES_PER_MS;

    ms += rem / CYCLES_PER_MS;
    return ms;
}

static ACCEL_SIZE_OPT uint8_t accel_tick_cycles_to_decimal_digits(tick_t ticks,
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

static ACCEL_SIZE_OPT void print_tick_cycles_dec(tick_t ticks)
{
    uint8_t digits[20];
    uint8_t count = accel_tick_cycles_to_decimal_digits(ticks, digits, sizeof(digits));

    while (count > 0U) {
        Uart_write((uint8_t)('0' + digits[--count]));
    }
}

static ACCEL_SIZE_OPT uint32_t accel_ticks_to_u32_saturated(tick_t ticks)
{
    return (ticks.upper != 0U) ? 0xFFFFFFFFU : ticks.lower;
}

static ACCEL_SIZE_OPT void print_cycles_per_unit(tick_t ticks, uint32_t units)
{
    uint32_t cycles;

    if (units == 0U) {
        Uart_print("n/a");
        return;
    }

    if (ticks.upper != 0U) {
        Uart_write('>');
    }
    cycles = accel_ticks_to_u32_saturated(ticks);
    print_u32_dec((cycles + (units >> 1U)) / units);
}

static ACCEL_SIZE_OPT void print_tick_metric(tick_t ticks)
{
    print_tick_cycles_dec(ticks);
    Uart_print(" cycles (");
    print_u32_dec(accel_ticks_to_ms(ticks));
    Uart_print(" ms)");
}

static ACCEL_SIZE_OPT void print_hyperram_mode(const char *name, HyperRAM_Driver_t *drv)
{
    uint32_t mode = HyperRAM_read_mode_register(drv);

    Uart_print("  ");
    Uart_print(name);
    Uart_print(" mode=0x");
    Uart_print_hex_32(mode);
    Uart_print(" accel=");
    print_u32_dec((mode & HYPERRAM_MODE_ACCEL_Msk) != 0U ? 1U : 0U);
    Uart_print(" wr_w=");
    print_u32_dec((mode & HYPERRAM_DMAC_WRITE_WEIGHT_Msk) >> HYPERRAM_DMAC_WRITE_WEIGHT_Pos);
    Uart_print(" rd_w=");
    print_u32_dec((mode & HYPERRAM_DMAC_READ_WEIGHT_Msk) >> HYPERRAM_DMAC_READ_WEIGHT_Pos);
    Uart_println("");
}

static ACCEL_SIZE_OPT void print_hyperram_status(const char *name, HyperRAM_Driver_t *drv)
{
    uint32_t status = *drv->reg_status;

    Uart_print("  ");
    Uart_print(name);
    Uart_print(" status=0x");
    Uart_print_hex_32(status);
    Uart_print(" start_rdy=");
    print_u32_dec((status >> 10) & 1U);
    Uart_print(" empty=");
    print_u32_dec((status >> 9) & 1U);
    Uart_print(" full=");
    print_u32_dec((status >> 8) & 1U);
    Uart_print(" data=0x");
    Uart_print_hex_32(status & 0xFFU);
    Uart_println("");
}

static ACCEL_SIZE_OPT bool wait_hyperram_master_idle(const char *name, HyperRAM_Driver_t *drv)
{
    uint32_t wait = ACCEL_HRAM_DRAIN_WAIT_LIMIT;
    uint32_t stable = 0U;

    while (wait > 0U) {
        if (HyperRAM_is_start_ready(drv)) {
            stable++;
            if (stable >= ACCEL_HRAM_DRAIN_STABLE_READS) {
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

static ACCEL_SIZE_OPT bool drain_ofbuf_to_hyperram1(void)
{
    volatile uint32_t delay = ACCEL_OFBUF_POST_IRQ_DELAY;

#if ACCEL_OFBUF_POST_IRQ_DELAY > 0U
    while (delay > 0U) {
        __asm__ volatile("nop");
        delay--;
    }
#else
    (void)delay;
#endif

    return wait_hyperram_master_idle("HR1", &hyperram1);
}

static ACCEL_SIZE_OPT void print_conv1_config(const CNN_Accel_LayerConfig_t *config)
{
    Uart_print("  CFG if=");
    print_u32_dec(config->ifheight);
    Uart_write('x');
    print_u32_dec(config->ifheight);
    Uart_write('x');
    print_u32_dec(config->ifchannel);
    Uart_print(" of=");
    print_u32_dec(config->ofchannel);
    Uart_print(" hf=");
    print_u32_dec(config->hf);
    Uart_print(" stride=");
    print_u32_dec(config->stride);
    Uart_print(" pad=");
    print_u32_dec(config->padding);
    Uart_print(" ifparr=");
    print_u32_dec(config->ifparr);
    Uart_print(" ofparr=");
    print_u32_dec(config->ofparr);
    Uart_print(" oftile=");
    print_u32_dec(config->oftile);
    Uart_println("");

    Uart_print("  ADDR if=0x");
    Uart_print_hex_32(config->ifbaddr);
    Uart_print(" flt=0x");
    Uart_print_hex_32(config->fltbaddr);
    Uart_print(" bias=0x");
    Uart_print_hex_32(config->bias_baddr);
    Uart_print(" of=0x");
    Uart_print_hex_32(config->ofbaddr);
    Uart_println("");
}

static uint32_t ceil_div_u32(uint32_t a, uint32_t b)
{
    return (a + b - 1U) / b;
}

static uint32_t min_u32(uint32_t a, uint32_t b)
{
    return (a < b) ? a : b;
}

static ACCEL_SIZE_OPT bool hram_read_bytes(W95_HandleTypeDef *w95, uint32_t addr, uint8_t *dst, uint32_t size)
{
    uint32_t done = 0U;

    if (((addr | size) & 1U) != 0U) {
        return false;
    }

    while (done < size) {
        uint32_t chunk = size - done;
        if (chunk > ACCEL_HRAM_CHUNK_BYTES) {
            chunk = ACCEL_HRAM_CHUNK_BYTES;
        }
        if ((chunk & 1U) != 0U) {
            return false;
        }
        W95_MemoryRead(w95, addr + done, dst + done, chunk, true);
        done += chunk;
    }

    return true;
}

static ACCEL_SIZE_OPT bool hram_write_bytes(W95_HandleTypeDef *w95, uint32_t addr, const uint8_t *src, uint32_t size)
{
    uint32_t done = 0U;

    if (((addr | size) & 1U) != 0U) {
        return false;
    }

    while (done < size) {
        uint32_t chunk = size - done;
        if (chunk > ACCEL_HRAM_CHUNK_BYTES) {
            chunk = ACCEL_HRAM_CHUNK_BYTES;
        }
        if ((chunk & 1U) != 0U) {
            return false;
        }
        W95_MemoryWrite(w95, addr + done, src + done, chunk, true);
        done += chunk;
    }

    return true;
}

static ACCEL_SIZE_OPT bool hram_read_bytes_unaligned(W95_HandleTypeDef *w95, uint32_t addr, uint8_t *dst, uint32_t size)
{
    uint32_t done = 0U;

    while (done < size) {
        uint32_t chunk = size - done;
        uint32_t aligned_addr;
        uint32_t aligned_end;
        uint32_t aligned_size;
        uint32_t offset;

        if (chunk > (ACCEL_PACK_BUF_BYTES - 2U)) {
            chunk = ACCEL_PACK_BUF_BYTES - 2U;
        }

        aligned_addr = (addr + done) & ~1U;
        aligned_end = (addr + done + chunk + 1U) & ~1U;
        aligned_size = aligned_end - aligned_addr;
        offset = (addr + done) - aligned_addr;

        if (!hram_read_bytes(w95, aligned_addr, s_readback_buf, aligned_size)) {
            return false;
        }
        for (uint32_t i = 0U; i < chunk; i++) {
            dst[done + i] = s_readback_buf[offset + i];
        }
        done += chunk;
    }

    return true;
}

static ACCEL_SIZE_OPT bool read_conv1_source_params(W95_HandleTypeDef *w95_h0_read)
{
    uint32_t blob_size = 0U;

    s_conv1_source_params_ready = false;

    if (!hram_read_bytes(w95_h0_read, 0U, (uint8_t *)&blob_size, sizeof(blob_size))) {
        return false;
    }

    Uart_print("  Weight blob size header: 0x");
    Uart_print_hex_32(blob_size);
    Uart_println("");
    if (blob_size != ACCEL_ALLCNN_BLOB_BYTES) {
        Uart_println("  Warning: weight header.");
        return false;
    }

    if (!hram_read_bytes(w95_h0_read,
                         ACCEL_CONV1_WEIGHT_OFFSET,
                         s_conv1_weight,
                         ACCEL_CONV1_WEIGHT_SIZE)) {
        return false;
    }

    if (!hram_read_bytes(w95_h0_read,
                         ACCEL_CONV1_BIAS_OFFSET,
                         (uint8_t *)s_conv1_bias,
                         ACCEL_CONV1_BIAS_SIZE)) {
        return false;
    }

    s_conv1_source_params_ready = true;
    return true;
}

static ACCEL_SIZE_OPT void build_output_channel_slots(uint32_t group_start, uint32_t group_cols)
{
    uint32_t full_cols = ACCEL_CONV1_OUT_C / ACCEL_OFPARR;
    uint32_t tail_slots = ACCEL_CONV1_OUT_C % ACCEL_OFPARR;
    uint32_t lane_count[ACCEL_M];
    uint32_t lane_base[ACCEL_M];
    uint32_t lane_seq_count[ACCEL_M];
    uint32_t red_need[ACCEL_MAX_OFTILE];
    uint32_t block_id = group_start / ACCEL_OFTILE;
    uint32_t block_real;

    for (uint32_t lane = 0U; lane < ACCEL_M; lane++) {
        s_lane_rows[lane] = 0U;
        for (uint32_t r = lane; r < ACCEL_OFPARR; r += ACCEL_M) {
            s_lane_rows[lane]++;
        }
    }

    for (uint32_t lane = 0U; lane < ACCEL_M; lane++) {
        lane_count[lane] = full_cols * (uint32_t)s_lane_rows[lane];
        if (tail_slots > lane) {
            lane_count[lane] += ceil_div_u32(tail_slots - lane, ACCEL_M);
        }
    }

    lane_base[0] = 0U;
    for (uint32_t lane = 1U; lane < ACCEL_M; lane++) {
        lane_base[lane] = lane_base[lane - 1U] + lane_count[lane - 1U];
    }

    block_real = ACCEL_CONV1_OUT_C - block_id * ACCEL_OFTILE * ACCEL_OFPARR;
    if (block_real > ACCEL_OFTILE * ACCEL_OFPARR) {
        block_real = ACCEL_OFTILE * ACCEL_OFPARR;
    }

    for (uint32_t col = 0U; col < group_cols; col++) {
        red_need[col] = min_u32(ACCEL_OFPARR, block_real);
        block_real -= red_need[col];
    }

    for (uint32_t lane = 0U; lane < ACCEL_M; lane++) {
        lane_seq_count[lane] = 0U;
        for (uint32_t r = 0U; r < ACCEL_MAX_ROWS_PER_LANE; r++) {
            for (uint32_t col = 0U; col < ACCEL_MAX_OFTILE; col++) {
                s_slot_ch[lane][r][col] = -1;
            }
        }
        for (uint32_t i = 0U; i < ACCEL_CONV1_OUT_C; i++) {
            s_lane_seq[lane][i] = -1;
            s_lane_seq_used[lane][i] = 0U;
        }
    }

    for (uint32_t lane = 0U; lane < ACCEL_M; lane++) {
        for (uint32_t r = 0U; r < s_lane_rows[lane]; r++) {
            for (uint32_t col = 0U; col < group_cols; col++) {
                uint32_t idx_in_lane = lane_base[lane]
                                     + (uint32_t)s_lane_rows[lane] * group_start
                                     + r * group_cols
                                     + col;
                if ((idx_in_lane < lane_base[lane] + lane_count[lane]) &&
                    (idx_in_lane < ACCEL_CONV1_OUT_C)) {
                    uint32_t pos = lane_seq_count[lane]++;
                    s_lane_seq[lane][pos] = (int16_t)idx_in_lane;
                }
            }
        }
    }

    for (uint32_t col = 0U; col < group_cols; col++) {
        uint32_t need = red_need[col];

        for (uint32_t lane = 0U; lane < ACCEL_M; lane++) {
            for (uint32_t r = 0U; r < s_lane_rows[lane]; r++) {
                uint32_t seq_pos = r * group_cols + col;
                if ((need > 0U) &&
                    (seq_pos < lane_seq_count[lane]) &&
                    (s_lane_seq_used[lane][seq_pos] == 0U)) {
                    s_slot_ch[lane][r][col] = s_lane_seq[lane][seq_pos];
                    s_lane_seq_used[lane][seq_pos] = 1U;
                    need--;
                }
            }
        }

        while (need > 0U) {
            bool placed = false;
            for (uint32_t lane = 0U; (lane < ACCEL_M) && !placed; lane++) {
                for (uint32_t seq_pos = 0U; (seq_pos < lane_seq_count[lane]) && !placed; seq_pos++) {
                    if (s_lane_seq_used[lane][seq_pos] != 0U) {
                        continue;
                    }
                    for (uint32_t r = 0U; (r < s_lane_rows[lane]) && !placed; r++) {
                        if (s_slot_ch[lane][r][col] < 0) {
                            s_slot_ch[lane][r][col] = s_lane_seq[lane][seq_pos];
                            s_lane_seq_used[lane][seq_pos] = 1U;
                            need--;
                            placed = true;
                        }
                    }
                }
            }
            if (!placed) {
                break;
            }
        }
    }
}

static ACCEL_SIZE_OPT bool build_layer_output_channel_slots(const AccelFullLayer_t *layer,
                                             uint32_t group_start,
                                             uint32_t group_cols)
{
    uint32_t full_cols = layer->ofchannel / layer->ofparr;
    uint32_t tail_slots = layer->ofchannel % layer->ofparr;
    uint32_t lane_count[ACCEL_M];
    uint32_t lane_base[ACCEL_M];
    uint32_t lane_seq_count[ACCEL_M];
    uint32_t red_need[ACCEL_MAX_OFTILE];
    uint32_t block_id = group_start / layer->oftile;
    uint32_t block_real;

    if ((layer->ofchannel > ACCEL_MAX_OUT_C) ||
        (layer->ofparr > (ACCEL_MAX_ROWS_PER_LANE * ACCEL_M)) ||
        (group_cols > ACCEL_MAX_OFTILE)) {
        return false;
    }

    for (uint32_t lane = 0U; lane < ACCEL_M; lane++) {
        s_lane_rows[lane] = 0U;
        for (uint32_t r = lane; r < layer->ofparr; r += ACCEL_M) {
            s_lane_rows[lane]++;
        }
    }

    for (uint32_t lane = 0U; lane < ACCEL_M; lane++) {
        lane_count[lane] = full_cols * (uint32_t)s_lane_rows[lane];
        if (tail_slots > lane) {
            lane_count[lane] += ceil_div_u32(tail_slots - lane, ACCEL_M);
        }
    }

    lane_base[0] = 0U;
    for (uint32_t lane = 1U; lane < ACCEL_M; lane++) {
        lane_base[lane] = lane_base[lane - 1U] + lane_count[lane - 1U];
    }

    block_real = layer->ofchannel - block_id * layer->oftile * layer->ofparr;
    if (block_real > layer->oftile * layer->ofparr) {
        block_real = layer->oftile * layer->ofparr;
    }

    for (uint32_t col = 0U; col < group_cols; col++) {
        red_need[col] = min_u32(layer->ofparr, block_real);
        block_real -= red_need[col];
    }

    for (uint32_t lane = 0U; lane < ACCEL_M; lane++) {
        lane_seq_count[lane] = 0U;
        for (uint32_t r = 0U; r < ACCEL_MAX_ROWS_PER_LANE; r++) {
            for (uint32_t col = 0U; col < ACCEL_MAX_OFTILE; col++) {
                s_slot_ch[lane][r][col] = -1;
            }
        }
        for (uint32_t i = 0U; i < layer->ofchannel; i++) {
            s_lane_seq[lane][i] = -1;
            s_lane_seq_used[lane][i] = 0U;
        }
    }

    for (uint32_t lane = 0U; lane < ACCEL_M; lane++) {
        for (uint32_t r = 0U; r < s_lane_rows[lane]; r++) {
            for (uint32_t col = 0U; col < group_cols; col++) {
                uint32_t idx_in_lane = lane_base[lane]
                                     + (uint32_t)s_lane_rows[lane] * group_start
                                     + r * group_cols
                                     + col;
                if ((idx_in_lane < lane_base[lane] + lane_count[lane]) &&
                    (idx_in_lane < layer->ofchannel)) {
                    uint32_t pos = lane_seq_count[lane]++;
                    s_lane_seq[lane][pos] = (int16_t)idx_in_lane;
                }
            }
        }
    }

    for (uint32_t col = 0U; col < group_cols; col++) {
        uint32_t need = red_need[col];

        for (uint32_t lane = 0U; lane < ACCEL_M; lane++) {
            for (uint32_t r = 0U; r < s_lane_rows[lane]; r++) {
                uint32_t seq_pos = r * group_cols + col;
                if ((need > 0U) &&
                    (seq_pos < lane_seq_count[lane]) &&
                    (s_lane_seq_used[lane][seq_pos] == 0U)) {
                    s_slot_ch[lane][r][col] = s_lane_seq[lane][seq_pos];
                    s_lane_seq_used[lane][seq_pos] = 1U;
                    need--;
                }
            }
        }

        while (need > 0U) {
            bool placed = false;
            for (uint32_t lane = 0U; (lane < ACCEL_M) && !placed; lane++) {
                for (uint32_t seq_pos = 0U; (seq_pos < lane_seq_count[lane]) && !placed; seq_pos++) {
                    if (s_lane_seq_used[lane][seq_pos] != 0U) {
                        continue;
                    }
                    for (uint32_t r = 0U; (r < s_lane_rows[lane]) && !placed; r++) {
                        if (s_slot_ch[lane][r][col] < 0) {
                            s_slot_ch[lane][r][col] = s_lane_seq[lane][seq_pos];
                            s_lane_seq_used[lane][seq_pos] = 1U;
                            need--;
                            placed = true;
                        }
                    }
                }
            }
            if (!placed) {
                break;
            }
        }
    }

    return true;
}

static ACCEL_SIZE_OPT bool write_cat_image_to_hyperram1(W95_HandleTypeDef *w95_h1_write)
{
    const int8_t *image = AllCNN_CIFAR10_GetTestImageHWC();

    if (image == 0) {
        return false;
    }

    for (uint32_t c = 0U; c < ACCEL_CONV1_IN_C; c++) {
        for (uint32_t y = 0U; y < ACCEL_CONV1_IN_H; y++) {
            for (uint32_t x = 0U; x < ACCEL_CONV1_IN_W; x++) {
                s_pack_buf[x] = (uint8_t)image[y * (ACCEL_CONV1_IN_W * ACCEL_CONV1_IN_C) +
                                                x * ACCEL_CONV1_IN_C + c];
            }

            if (!hram_write_bytes(w95_h1_write,
                                  ACCEL_HRAM1_IFMAP_BASE +
                                  c * ACCEL_CONV1_IN_H * ACCEL_CONV1_IN_W +
                                  y * ACCEL_CONV1_IN_W,
                                  s_pack_buf,
                                  ACCEL_CONV1_IN_W)) {
                return false;
            }
        }
    }

    return true;
}

static ACCEL_SIZE_OPT bool build_filter_packet(uint32_t group_start,
                                uint32_t group_cols,
                                uint32_t cg,
                                uint32_t col,
                                uint32_t *packet_size)
{
    uint32_t cp = min_u32(ACCEL_IFPARR, ACCEL_CONV1_IN_C - cg);
    uint16_t filters[ACCEL_MAX_FILTERS_PER_BURST];
    uint32_t filter_count = 0U;
    uint32_t pos = 0U;

    build_output_channel_slots(group_start, group_cols);

    for (uint32_t lane = 0U; lane < ACCEL_M; lane++) {
        for (uint32_t r = 0U; r < s_lane_rows[lane]; r++) {
            int16_t f = s_slot_ch[lane][r][col];
            if ((f >= 0) && ((uint32_t)f < ACCEL_CONV1_OUT_C)) {
                if (filter_count >= ACCEL_MAX_FILTERS_PER_BURST) {
                    return false;
                }
                filters[filter_count++] = (uint16_t)f;
            }
        }
    }

    for (uint32_t bf = 0U; bf < filter_count; bf++) {
        uint32_t f = filters[bf];
        for (uint32_t c_local = 0U; c_local < cp; c_local++) {
            for (uint32_t ky = 0U; ky < ACCEL_CONV1_K; ky++) {
                for (uint32_t kx = 0U; kx < ACCEL_CONV1_K; kx++) {
                    uint32_t src_idx = f * (ACCEL_CONV1_K * ACCEL_CONV1_K * ACCEL_CONV1_IN_C) +
                                       (ky * ACCEL_CONV1_K + kx) * ACCEL_CONV1_IN_C +
                                       (cg + c_local);
                    if (pos >= sizeof(s_pack_buf)) {
                        return false;
                    }
                    s_pack_buf[pos++] = s_conv1_weight[src_idx];
                }
            }
        }
    }

    if ((pos & 1U) != 0U) {
        if (pos >= sizeof(s_pack_buf)) {
            return false;
        }
        s_pack_buf[pos++] = 0xFFU;
    }

    *packet_size = pos;
    return true;
}

static ACCEL_SIZE_OPT bool pack_conv1_weights_to_hyperram0(W95_HandleTypeDef *w95_h0_write)
{
    uint32_t write_addr = ACCEL_HRAM0_FLT_BASE;
    uint32_t total_cols = ceil_div_u32(ACCEL_CONV1_OUT_C, ACCEL_OFPARR);

    for (uint32_t group_start = 0U; group_start < total_cols; group_start += ACCEL_OFTILE) {
        uint32_t group_cols = min_u32(ACCEL_OFTILE, total_cols - group_start);

        for (uint32_t cg = 0U; cg < ACCEL_CONV1_IN_C; cg += ACCEL_IFPARR) {
            for (uint32_t col = 0U; col < group_cols; col++) {
                uint32_t packet_size = 0U;

                if (!build_filter_packet(group_start, group_cols, cg, col, &packet_size)) {
                    return false;
                }
                if (!hram_write_bytes(w95_h0_write, write_addr, s_pack_buf, packet_size)) {
                    return false;
                }
                write_addr += packet_size;
            }
        }
    }

    return true;
}

static void append_i32_bias_stream(uint8_t *dst, uint32_t *pos, int32_t value)
{
    uint32_t raw = (uint32_t)value;

    /*
     * bias_buffer.v shifts incoming bytes toward the MSB before committing the
     * 32-bit bias word, so the DMA byte stream must present MSB first.
     */
    dst[(*pos)++] = (uint8_t)((raw >> 24U) & 0xFFU);
    dst[(*pos)++] = (uint8_t)((raw >> 16U) & 0xFFU);
    dst[(*pos)++] = (uint8_t)((raw >> 8U) & 0xFFU);
    dst[(*pos)++] = (uint8_t)(raw & 0xFFU);
}

static ACCEL_SIZE_OPT bool build_bias_packet(uint32_t group_start, uint32_t group_cols, uint32_t *packet_size)
{
    uint32_t pos = 0U;
    uint32_t real_bias_count = 0U;

    build_output_channel_slots(group_start, group_cols);

    for (uint32_t lane = 0U; lane < ACCEL_M; lane++) {
        for (uint32_t r = 0U; r < s_lane_rows[lane]; r++) {
            for (uint32_t col = 0U; col < group_cols; col++) {
                int16_t ch = s_slot_ch[lane][r][col];
                if ((ch >= 0) && ((uint32_t)ch < ACCEL_CONV1_OUT_C)) {
                    if ((pos + 4U) > sizeof(s_pack_buf)) {
                        return false;
                    }
                    append_i32_bias_stream(s_pack_buf, &pos, s_conv1_bias[(uint32_t)ch]);
                    real_bias_count++;
                }
            }
        }
    }

    if ((real_bias_count & 1U) != 0U) {
        if ((pos + 4U) > sizeof(s_pack_buf)) {
            return false;
        }
        append_i32_bias_stream(s_pack_buf, &pos, 0);
    }

    *packet_size = pos;
    return true;
}

static ACCEL_SIZE_OPT bool pack_conv1_bias_to_hyperram0(W95_HandleTypeDef *w95_h0_write)
{
    uint32_t write_addr = ACCEL_HRAM0_BIAS_BASE;
    uint32_t total_cols = ceil_div_u32(ACCEL_CONV1_OUT_C, ACCEL_OFPARR);

    for (uint32_t group_start = 0U; group_start < total_cols; group_start += ACCEL_OFTILE) {
        uint32_t group_cols = min_u32(ACCEL_OFTILE, total_cols - group_start);
        uint32_t packet_size = 0U;

        if (!build_bias_packet(group_start, group_cols, &packet_size)) {
            return false;
        }
        if (!hram_write_bytes(w95_h0_write, write_addr, s_pack_buf, packet_size)) {
            return false;
        }
        write_addr += packet_size;
    }

    return true;
}

static ACCEL_SIZE_OPT bool verify_readback_silent(W95_HandleTypeDef *w95,
                                   uint32_t addr,
                                   const uint8_t *expected,
                                   uint32_t size,
                                   uint32_t *bad_offset)
{
    if ((size == 0U) || (size > ACCEL_PACK_BUF_BYTES)) {
        return false;
    }

    if (!hram_read_bytes(w95, addr, s_readback_buf, size)) {
        return false;
    }

    for (uint32_t i = 0U; i < size; i++) {
        if (expected[i] != s_readback_buf[i]) {
            if (bad_offset != 0) {
                *bad_offset = i;
            }
            return false;
        }
    }

    return true;
}

static ACCEL_SIZE_OPT void print_verify_pass(const char *label, uint32_t bytes)
{
    Uart_print("  Verify ");
    Uart_print(label);
    Uart_print(": OK bytes=0x");
    Uart_print_hex_32(bytes);
    Uart_println("");
}

static ACCEL_SIZE_OPT void print_verify_fail(const char *label, uint32_t addr, uint32_t bad_offset)
{
    Uart_print("  Verify ");
    Uart_print(label);
    Uart_print(" mismatch/read fail at 0x");
    Uart_print_hex_32(addr + bad_offset);
    Uart_println("");
}

static ACCEL_SIZE_OPT bool verify_region_against_buffer(W95_HandleTypeDef *w95,
                                         uint32_t addr,
                                         const uint8_t *expected,
                                         uint32_t size,
                                         const char *label)
{
    uint32_t done = 0U;

    while (done < size) {
        uint32_t chunk = size - done;
        if (chunk > ACCEL_PACK_BUF_BYTES) {
            chunk = ACCEL_PACK_BUF_BYTES;
        }
        if (!hram_read_bytes(w95, addr + done, s_readback_buf, chunk)) {
            print_verify_fail(label, addr + done, 0U);
            return false;
        }
        for (uint32_t i = 0U; i < chunk; i++) {
            if (s_readback_buf[i] != expected[done + i]) {
                print_verify_fail(label, addr + done, i);
                return false;
            }
        }
        done += chunk;
    }

    return true;
}

static ACCEL_SIZE_OPT bool verify_conv1_ifmap_full(W95_HandleTypeDef *w95_h1_read, uint32_t *verified_bytes)
{
    const int8_t *image = AllCNN_CIFAR10_GetTestImageHWC();

    if (image == 0) {
        return false;
    }

    *verified_bytes = 0U;
    for (uint32_t c = 0U; c < ACCEL_CONV1_IN_C; c++) {
        for (uint32_t y = 0U; y < ACCEL_CONV1_IN_H; y++) {
            uint32_t bad_offset = 0U;
            uint32_t addr = ACCEL_HRAM1_IFMAP_BASE +
                            c * ACCEL_CONV1_IN_H * ACCEL_CONV1_IN_W +
                            y * ACCEL_CONV1_IN_W;

            for (uint32_t x = 0U; x < ACCEL_CONV1_IN_W; x++) {
                s_pack_buf[x] = (uint8_t)image[y * (ACCEL_CONV1_IN_W * ACCEL_CONV1_IN_C) +
                                                x * ACCEL_CONV1_IN_C + c];
            }
            if (!verify_readback_silent(w95_h1_read,
                                        addr,
                                        s_pack_buf,
                                        ACCEL_CONV1_IN_W,
                                        &bad_offset)) {
                print_verify_fail("IFMAP full", addr, bad_offset);
                return false;
            }
            *verified_bytes += ACCEL_CONV1_IN_W;
        }
    }

    return true;
}

static ACCEL_SIZE_OPT bool verify_conv1_filters_full(W95_HandleTypeDef *w95_h0_read, uint32_t *verified_bytes)
{
    uint32_t read_addr = ACCEL_HRAM0_FLT_BASE;
    uint32_t total_cols = ceil_div_u32(ACCEL_CONV1_OUT_C, ACCEL_OFPARR);

    *verified_bytes = 0U;
    for (uint32_t group_start = 0U; group_start < total_cols; group_start += ACCEL_OFTILE) {
        uint32_t group_cols = min_u32(ACCEL_OFTILE, total_cols - group_start);

        for (uint32_t cg = 0U; cg < ACCEL_CONV1_IN_C; cg += ACCEL_IFPARR) {
            for (uint32_t col = 0U; col < group_cols; col++) {
                uint32_t packet_size = 0U;
                uint32_t bad_offset = 0U;

                if (!build_filter_packet(group_start, group_cols, cg, col, &packet_size)) {
                    return false;
                }
                if (!verify_readback_silent(w95_h0_read, read_addr, s_pack_buf, packet_size, &bad_offset)) {
                    print_verify_fail("FLT full", read_addr, bad_offset);
                    return false;
                }
                read_addr += packet_size;
                *verified_bytes += packet_size;
            }
        }
    }

    return true;
}

static ACCEL_SIZE_OPT bool verify_conv1_bias_full(W95_HandleTypeDef *w95_h0_read, uint32_t *verified_bytes)
{
    uint32_t read_addr = ACCEL_HRAM0_BIAS_BASE;
    uint32_t total_cols = ceil_div_u32(ACCEL_CONV1_OUT_C, ACCEL_OFPARR);

    *verified_bytes = 0U;
    for (uint32_t group_start = 0U; group_start < total_cols; group_start += ACCEL_OFTILE) {
        uint32_t group_cols = min_u32(ACCEL_OFTILE, total_cols - group_start);
        uint32_t packet_size = 0U;
        uint32_t bad_offset = 0U;

        if (!build_bias_packet(group_start, group_cols, &packet_size)) {
            return false;
        }
        if (!verify_readback_silent(w95_h0_read, read_addr, s_pack_buf, packet_size, &bad_offset)) {
            print_verify_fail("BIAS full", read_addr, bad_offset);
            return false;
        }
        read_addr += packet_size;
        *verified_bytes += packet_size;
    }

    return true;
}

static ACCEL_SIZE_OPT bool verify_conv1_payload(W95_HandleTypeDef *w95_h0_read, W95_HandleTypeDef *w95_h1_read)
{
    const uint32_t expected_ifmap_bytes = ACCEL_CONV1_IN_H * ACCEL_CONV1_IN_W * ACCEL_CONV1_IN_C;
    uint32_t ifmap_bytes = 0U;
    uint32_t filter_bytes = 0U;
    uint32_t bias_bytes = 0U;

    Uart_println("Verify accel payloads:");

    if (!verify_conv1_ifmap_full(w95_h1_read, &ifmap_bytes)) {
        return false;
    }
    if (ifmap_bytes != expected_ifmap_bytes) {
        Uart_println("  IFMAP count fail.");
        return false;
    }
    print_verify_pass("IFMAP full", ifmap_bytes);

    if (!verify_conv1_filters_full(w95_h0_read, &filter_bytes)) {
        return false;
    }
    if (filter_bytes != ACCEL_CONV1_WEIGHT_SIZE) {
        Uart_println("  FLT count fail.");
        return false;
    }
    print_verify_pass("FLT full", filter_bytes);

    if (!verify_conv1_bias_full(w95_h0_read, &bias_bytes)) {
        return false;
    }
    if (bias_bytes != ACCEL_CONV1_BIAS_SIZE) {
        Uart_println("  BIAS count fail.");
        return false;
    }
    print_verify_pass("BIAS full", bias_bytes);

    return true;
}

static ACCEL_SIZE_OPT uint32_t full_layer_ofwidth(const AccelFullLayer_t *layer)
{
    uint32_t padded = (uint32_t)layer->ifheight + ((uint32_t)layer->padding << 1U);
    uint32_t span = (padded >= layer->hf) ? (padded - (uint32_t)layer->hf) : 0U;
    return (span / (uint32_t)layer->stride) + 1U;
}

static ACCEL_SIZE_OPT uint32_t full_layer_ifmap_bytes(const AccelFullLayer_t *layer)
{
    return (uint32_t)layer->ifheight * (uint32_t)layer->ifheight * (uint32_t)layer->ifchannel;
}

static ACCEL_SIZE_OPT uint32_t full_layer_ofmap_bytes(const AccelFullLayer_t *layer)
{
    uint32_t ofwidth = full_layer_ofwidth(layer);
    return ofwidth * ofwidth * (uint32_t)layer->ofchannel;
}

static ACCEL_SIZE_OPT uint32_t full_layer_macs(const AccelFullLayer_t *layer)
{
    return full_layer_ofmap_bytes(layer) *
           (uint32_t)layer->ifchannel *
           (uint32_t)layer->hf *
           (uint32_t)layer->hf;
}

static ACCEL_SIZE_OPT void print_cycles_per_kmac(tick_t ticks, uint32_t macs)
{
    print_cycles_per_unit(ticks, macs / 1000U);
}

static ACCEL_SIZE_OPT void print_layer_profile(uint8_t layer_idx,
                                               const AccelFullLayer_t *layer,
                                               tick_t ticks)
{
    uint32_t macs = full_layer_macs(layer);
    uint32_t out_bytes = full_layer_ofmap_bytes(layer);

    Uart_print("  Layer ");
    print_u32_dec((uint32_t)layer_idx + 1U);
    Uart_println(" finished:");

    Uart_print("    Time               : ");
    print_tick_metric(ticks);
    Uart_println("");

    Uart_print("    Workload           : ");
    print_u32_dec(macs);
    Uart_println(" MACs");

    Uart_print("    Output bytes       : ");
    print_u32_dec(out_bytes);
    Uart_println("");

    Uart_print("    Cost               : ");
    print_cycles_per_kmac(ticks, macs);
    Uart_println(" cycles / 1000 MACs");
}

static ACCEL_SIZE_OPT void print_full_profile_summary(tick_t conv_ticks,
                                                      tick_t avgpool_ticks,
                                                      tick_t profile_sum,
                                                      tick_t wall_ticks,
                                                      uint32_t total_macs)
{
    Uart_println("");
    Uart_println("Accel performance summary (lower cost is better):");

    Uart_println("  Accelerator conv layers:");
    Uart_print("    Time               : ");
    print_tick_metric(conv_ticks);
    Uart_println("");
    Uart_print("    Workload           : ");
    print_u32_dec(total_macs);
    Uart_println(" MACs");
    Uart_print("    Cost               : ");
    print_cycles_per_kmac(conv_ticks, total_macs);
    Uart_println(" cycles / 1000 MACs");

    Uart_println("  Global average pool (CPU):");
    Uart_print("    Time               : ");
    print_tick_metric(avgpool_ticks);
    Uart_println("");

    Uart_println("  Model total from measured stages:");
    Uart_print("    Time               : ");
    print_tick_metric(profile_sum);
    Uart_println("  (conv + avgpool)");

    Uart_println("  Wall-clock section:");
    Uart_print("    Time               : ");
    print_tick_metric(wall_ticks);
    Uart_println("  (includes UART/log overhead)");
}

static ACCEL_SIZE_OPT bool build_full_filter_group(W95_HandleTypeDef *w95_h0_read,
                                    const AccelRawParamMeta_t *meta,
                                    const AccelFullLayer_t *layer,
                                    uint32_t group_start,
                                    uint32_t group_cols,
                                    uint32_t *group_size)
{
    uint32_t iftiles = ceil_div_u32(layer->ifchannel, layer->ifparr);
    uint32_t packet_offsets[96];
    uint32_t packet_sizes[96];
    uint16_t filters[ACCEL_MAX_FILTERS_PER_BURST];
    uint32_t filter_count = 0U;
    uint32_t filter_span = (uint32_t)layer->hf * (uint32_t)layer->hf * (uint32_t)layer->ifchannel;
    uint32_t total_size = 0U;

    if ((iftiles > 96U) || (filter_span > ACCEL_FULL_FILTER_BUF_BYTES)) {
        return false;
    }
    if (!build_layer_output_channel_slots(layer, group_start, group_cols)) {
        return false;
    }

    for (uint32_t col = 0U; col < group_cols; col++) {
        for (uint32_t lane = 0U; lane < ACCEL_M; lane++) {
            for (uint32_t r = 0U; r < s_lane_rows[lane]; r++) {
                int16_t f = s_slot_ch[lane][r][col];
                if ((f >= 0) && ((uint32_t)f < layer->ofchannel)) {
                    if (filter_count >= ACCEL_MAX_FILTERS_PER_BURST) {
                        return false;
                    }
                    filters[filter_count++] = (uint16_t)f;
                }
            }
        }
    }

    for (uint32_t tile = 0U; tile < iftiles; tile++) {
        uint32_t cg = tile * (uint32_t)layer->ifparr;
        uint32_t cp = min_u32(layer->ifparr, (uint32_t)layer->ifchannel - cg);
        uint32_t raw_packet_size = cp * filter_count * (uint32_t)layer->hf * (uint32_t)layer->hf;
        uint32_t packet_size = raw_packet_size + (raw_packet_size & 1U);

        packet_offsets[tile] = total_size;
        packet_sizes[tile] = packet_size;
        total_size += packet_size;
    }

    if (total_size > ACCEL_FULL_GROUP_BUF_BYTES) {
        return false;
    }
    for (uint32_t i = 0U; i < total_size; i++) {
        s_full_group_buf[i] = 0xFFU;
    }

    for (uint32_t bf = 0U; bf < filter_count; bf++) {
        uint32_t f = filters[bf];
        uint32_t raw_filter_addr = meta->weight_offset + f * filter_span;

        if (!hram_read_bytes_unaligned(w95_h0_read, raw_filter_addr, s_full_filter_buf, filter_span)) {
            return false;
        }

        for (uint32_t tile = 0U; tile < iftiles; tile++) {
            uint32_t cg = tile * (uint32_t)layer->ifparr;
            uint32_t cp = min_u32(layer->ifparr, (uint32_t)layer->ifchannel - cg);
            uint32_t pos = packet_offsets[tile]
                         + bf * cp * (uint32_t)layer->hf * (uint32_t)layer->hf;

            if ((pos + cp * (uint32_t)layer->hf * (uint32_t)layer->hf) >
                (packet_offsets[tile] + packet_sizes[tile])) {
                return false;
            }

            for (uint32_t c_local = 0U; c_local < cp; c_local++) {
                for (uint32_t ky = 0U; ky < layer->hf; ky++) {
                    for (uint32_t kx = 0U; kx < layer->hf; kx++) {
                        uint32_t src_idx = (ky * (uint32_t)layer->hf + kx) *
                                           (uint32_t)layer->ifchannel +
                                           cg + c_local;
                        s_full_group_buf[pos++] = s_full_filter_buf[src_idx];
                    }
                }
            }
        }
    }

    *group_size = total_size;
    return true;
}

static ACCEL_SIZE_OPT bool pack_full_layer_weights(W95_HandleTypeDef *w95_h0_read,
                                    W95_HandleTypeDef *w95_h0_write,
                                    uint8_t layer_idx)
{
    const AccelFullLayer_t *layer = &s_full_layers[layer_idx];
    const AccelRawParamMeta_t *meta = &s_full_raw_meta[layer_idx];
    uint32_t write_addr = ACCEL_FULL_HRAM0_PARAM_BASE + layer->fltbaddr;
    uint32_t total_cols = ceil_div_u32(layer->ofchannel, layer->ofparr);
    uint32_t written = 0U;

    for (uint32_t group_start = 0U; group_start < total_cols; group_start += layer->oftile) {
        uint32_t group_cols = min_u32(layer->oftile, total_cols - group_start);
        uint32_t group_size = 0U;

        if (!build_full_filter_group(w95_h0_read, meta, layer, group_start, group_cols, &group_size)) {
            return false;
        }
        if (!hram_write_bytes(w95_h0_write, write_addr, s_full_group_buf, group_size)) {
            return false;
        }
        if (!verify_region_against_buffer(w95_h0_read, write_addr, s_full_group_buf, group_size, "FULL FLT")) {
            return false;
        }
        write_addr += group_size;
        written += group_size;
    }

    return written == meta->weight_size;
}

static ACCEL_SIZE_OPT bool build_full_bias_packet(W95_HandleTypeDef *w95_h0_read,
                                   const AccelRawParamMeta_t *meta,
                                   const AccelFullLayer_t *layer,
                                   uint32_t group_start,
                                   uint32_t group_cols,
                                   uint32_t *packet_size)
{
    uint32_t pos = 0U;
    uint32_t real_bias_count = 0U;

    if (!build_layer_output_channel_slots(layer, group_start, group_cols)) {
        return false;
    }

    for (uint32_t lane = 0U; lane < ACCEL_M; lane++) {
        for (uint32_t r = 0U; r < s_lane_rows[lane]; r++) {
            for (uint32_t col = 0U; col < group_cols; col++) {
                int16_t ch = s_slot_ch[lane][r][col];
                if ((ch >= 0) && ((uint32_t)ch < layer->ofchannel)) {
                    uint8_t raw_bias[4];
                    int32_t bias_value;

                    if ((pos + 4U) > ACCEL_PACK_BUF_BYTES) {
                        return false;
                    }
                    if (!hram_read_bytes(w95_h0_read,
                                         meta->bias_offset + (uint32_t)ch * 4U,
                                         raw_bias,
                                         4U)) {
                        return false;
                    }
                    bias_value = (int32_t)((uint32_t)raw_bias[0] |
                                           ((uint32_t)raw_bias[1] << 8U) |
                                           ((uint32_t)raw_bias[2] << 16U) |
                                           ((uint32_t)raw_bias[3] << 24U));
                    append_i32_bias_stream(s_pack_buf, &pos, bias_value);
                    real_bias_count++;
                }
            }
        }
    }

    if ((real_bias_count & 1U) != 0U) {
        if ((pos + 4U) > ACCEL_PACK_BUF_BYTES) {
            return false;
        }
        append_i32_bias_stream(s_pack_buf, &pos, 0);
    }

    *packet_size = pos;
    return true;
}

static ACCEL_SIZE_OPT bool pack_full_layer_bias(W95_HandleTypeDef *w95_h0_read,
                                 W95_HandleTypeDef *w95_h0_write,
                                 uint8_t layer_idx)
{
    const AccelFullLayer_t *layer = &s_full_layers[layer_idx];
    const AccelRawParamMeta_t *meta = &s_full_raw_meta[layer_idx];
    uint32_t write_addr = ACCEL_FULL_HRAM0_PARAM_BASE + layer->bias_baddr;
    uint32_t total_cols = ceil_div_u32(layer->ofchannel, layer->ofparr);
    uint32_t written = 0U;

    for (uint32_t group_start = 0U; group_start < total_cols; group_start += layer->oftile) {
        uint32_t group_cols = min_u32(layer->oftile, total_cols - group_start);
        uint32_t packet_size = 0U;

        if (!build_full_bias_packet(w95_h0_read, meta, layer, group_start, group_cols, &packet_size)) {
            return false;
        }
        if (!hram_write_bytes(w95_h0_write, write_addr, s_pack_buf, packet_size)) {
            return false;
        }
        if (!verify_readback_silent(w95_h0_read, write_addr, s_pack_buf, packet_size, 0)) {
            print_verify_fail("FULL BIAS", write_addr, 0U);
            return false;
        }
        write_addr += packet_size;
        written += packet_size;
    }

    return written == meta->bias_size;
}

static ACCEL_SIZE_OPT bool pack_full_layer_params(W95_HandleTypeDef *w95_h0_read,
                                   W95_HandleTypeDef *w95_h0_write,
                                   uint8_t layer_idx)
{
    Uart_print("  L");
    print_u32_dec((uint32_t)layer_idx + 1U);
    Uart_print(" pack params...");

    if (!pack_full_layer_weights(w95_h0_read, w95_h0_write, layer_idx)) {
        Uart_println(" FLT fail");
        return false;
    }
    if (!pack_full_layer_bias(w95_h0_read, w95_h0_write, layer_idx)) {
        Uart_println(" BIAS fail");
        return false;
    }

    Uart_println(" OK");
    return true;
}

static int32_t clamp_i64_to_i32(int64_t value)
{
    if (value > 2147483647LL) {
        return 2147483647;
    }
    if (value < (-2147483647LL - 1LL)) {
        return (int32_t)0x80000000UL;
    }
    return (int32_t)value;
}

static int8_t clamp_i32_to_i8(int32_t value)
{
    if (value > (int32_t)ACCEL_CONV1_QMAX) {
        return ACCEL_CONV1_QMAX;
    }
    if (value < (int32_t)ACCEL_CONV1_QMIN) {
        return ACCEL_CONV1_QMIN;
    }
    return (int8_t)value;
}

static ACCEL_SIZE_OPT int8_t quantize_like_accel(int32_t acc)
{
    int64_t scaled = (int64_t)acc * (int64_t)ACCEL_CONV1_MULT;
    int32_t shifted;
    int32_t activated;
    int32_t with_zp;

    if (ACCEL_CONV1_SHIFT > 0U) {
        scaled += (1LL << (ACCEL_CONV1_SHIFT - 1U));
        if (scaled < 0) {
            scaled -= 1LL;
        }
        scaled >>= ACCEL_CONV1_SHIFT;
    }

    shifted = clamp_i64_to_i32(scaled);
    activated = (shifted < 0) ? 0 : shifted;
    with_zp = activated + (int32_t)ACCEL_CONV1_OUT_ZP;

    return clamp_i32_to_i8(with_zp);
}

static ACCEL_SIZE_OPT int8_t requantize_i8(int32_t acc, int32_t mult, uint8_t shift, int8_t out_zp)
{
    int64_t scaled = (int64_t)acc * (int64_t)mult;
    int32_t shifted;
    int32_t with_zp;

    if (shift > 0U) {
        scaled += (1LL << (shift - 1U));
        if (scaled < 0) {
            scaled -= 1LL;
        }
        scaled >>= shift;
    }

    shifted = clamp_i64_to_i32(scaled);
    with_zp = shifted + (int32_t)out_zp;

    return clamp_i32_to_i8(with_zp);
}

static ACCEL_SIZE_OPT int8_t cpu_conv1_value(const int8_t *image, uint32_t oc, uint32_t oy, uint32_t ox)
{
    int32_t acc = s_conv1_bias[oc];

    for (uint32_t ky = 0U; ky < ACCEL_CONV1_K; ky++) {
        for (uint32_t kx = 0U; kx < ACCEL_CONV1_K; kx++) {
            int32_t in_y = (int32_t)oy + (int32_t)ky - (int32_t)ACCEL_CONV1_PADDING;
            int32_t in_x = (int32_t)ox + (int32_t)kx - (int32_t)ACCEL_CONV1_PADDING;

            if ((in_y < 0) || (in_y >= (int32_t)ACCEL_CONV1_IN_H) ||
                (in_x < 0) || (in_x >= (int32_t)ACCEL_CONV1_IN_W)) {
                continue;
            }

            for (uint32_t ic = 0U; ic < ACCEL_CONV1_IN_C; ic++) {
                uint32_t in_idx = (uint32_t)in_y * (ACCEL_CONV1_IN_W * ACCEL_CONV1_IN_C) +
                                  (uint32_t)in_x * ACCEL_CONV1_IN_C +
                                  ic;
                uint32_t wt_idx = oc * (ACCEL_CONV1_K * ACCEL_CONV1_K * ACCEL_CONV1_IN_C) +
                                  (ky * ACCEL_CONV1_K + kx) * ACCEL_CONV1_IN_C +
                                  ic;
                int32_t in_delta = (int32_t)image[in_idx] - (int32_t)ACCEL_CONV1_IN_ZP;
                int32_t wt_delta = (int32_t)((int8_t)s_conv1_weight[wt_idx]) -
                                   (int32_t)ACCEL_CONV1_WEIGHT_ZP;

                acc += in_delta * wt_delta;
            }
        }
    }

    return quantize_like_accel(acc);
}

static void cnn_accel_irq_handler(uint32_t irq_bit, void *context)
{
    (void)irq_bit;
    (void)context;
    s_accel_irq_seen = true;
}

static ACCEL_SIZE_OPT bool run_accel_layer(void)
{
    CNN_Accel_LayerConfig_t config;
    uint32_t status;
    uint32_t wait = ACCEL_IRQ_WAIT_LIMIT;
    bool done_seen = false;

    config.ifheight = ACCEL_CONV1_IN_H;
    config.ifchannel = ACCEL_CONV1_IN_C;
    config.ofchannel = ACCEL_CONV1_OUT_C;
    config.hf = ACCEL_CONV1_K;
    config.stride = ACCEL_CONV1_STRIDE;
    config.padding = ACCEL_CONV1_PADDING;
    config.ifparr = ACCEL_IFPARR;
    config.oftile = ACCEL_OFTILE;
    config.ofparr = ACCEL_OFPARR;
    config.ifbaddr = ACCEL_HRAM1_IFMAP_BASE;
    config.fltbaddr = ACCEL_HRAM0_FLT_BASE;
    config.bias_baddr = ACCEL_HRAM0_BIAS_BASE;
    config.ofbaddr = ACCEL_HRAM1_OFMAP_BASE;
    config.ifc_zp = ACCEL_CONV1_IN_ZP;
    config.fltc_zp = ACCEL_CONV1_WEIGHT_ZP;
    config.mult = ACCEL_CONV1_MULT;
    config.mult_shift = ACCEL_CONV1_SHIFT;
    config.alphamult = 0;
    config.alphamult_shift = 0;
    config.zpy = ACCEL_CONV1_OUT_ZP;
    config.qmin = ACCEL_CONV1_QMIN;
    config.qmax = ACCEL_CONV1_QMAX;
    config.is_leaky_relu = false;

    s_accel_irq_seen = false;
    print_conv1_config(&config);

    status = CNN_Accel_get_status(&cnn_accel);
    print_cnn_status("  Before submit:", status);
    if (cnn_status_has(status, CNN_ACCEL_STATUS_BUSY_Msk)) {
        Uart_println("  CNN busy.");
        return false;
    }

    if (!CNN_Accel_attach_irq(cnn_accel_irq_handler, 0, IRQ_PRIORITY_DEFAULT)) {
        Uart_println("  IRQ attach fail.");
        return false;
    }
    CNN_Accel_enable_irq();
    Uart_print("  CNN IRQ bit: ");
    print_u32_dec(CNN_ACCEL_IRQ_BIT);
    Uart_print("  mask after enable: 0x");
    Uart_print_hex_32(IRQ_GetMask());
    Uart_println("");

    if (!CNN_Accel_submit_layer_config(&cnn_accel, &config, ACCEL_SUBMIT_WAIT_LIMIT)) {
        print_cnn_status("  CNN config submit timeout:", CNN_Accel_get_status(&cnn_accel));
        CNN_Accel_disable_irq();
        return false;
    }
    print_cnn_status("  After submit:", CNN_Accel_get_status(&cnn_accel));

    CNN_Accel_start(&cnn_accel);
    print_cnn_status("  After start:", CNN_Accel_get_status(&cnn_accel));

    while (wait > 0U) {
        status = CNN_Accel_get_status(&cnn_accel);
        if (cnn_status_has(status, CNN_ACCEL_STATUS_DONE_Msk) || s_accel_irq_seen) {
            done_seen = true;
            break;
        }
        wait--;
    }

    status = CNN_Accel_get_status(&cnn_accel);
    if (cnn_status_has(status, CNN_ACCEL_STATUS_DONE_Msk)) {
        done_seen = true;
    }

    CNN_Accel_disable_irq();

    if (!done_seen) {
        print_cnn_status("  CNN accel timeout:", status);
        print_hyperram_mode("HR0", &hyperram0);
        print_hyperram_status("HR0", &hyperram0);
        print_hyperram_mode("HR1", &hyperram1);
        print_hyperram_status("HR1", &hyperram1);
        return false;
    }

    if (s_accel_irq_seen) {
        Uart_println("  CNN accel IRQ received.");
    } else {
        Uart_println("  Done but no IRQ handler.");
    }
    print_cnn_status("  Final accel:", status);

    return true;
}

static ACCEL_SIZE_OPT void fill_full_layer_config(uint8_t layer_idx, CNN_Accel_LayerConfig_t *config)
{
    const AccelFullLayer_t *layer = &s_full_layers[layer_idx];

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
    config->fltbaddr = ACCEL_FULL_HRAM0_PARAM_BASE + layer->fltbaddr;
    config->bias_baddr = ACCEL_FULL_HRAM0_PARAM_BASE + layer->bias_baddr;
    config->ofbaddr = layer->ofbaddr;
    config->ifc_zp = layer->ifc_zp;
    config->fltc_zp = layer->fltc_zp;
    config->mult = layer->mult;
    config->mult_shift = layer->mult_shift;
    config->alphamult = 0;
    config->alphamult_shift = 0;
    config->zpy = layer->zpy;
    config->qmin = layer->qmin;
    config->qmax = layer->qmax;
    config->is_leaky_relu = false;
}

static ACCEL_SIZE_OPT bool run_full_accel_layer(uint8_t layer_idx)
{
    CNN_Accel_LayerConfig_t config;
    uint32_t status;
    uint32_t wait = ACCEL_IRQ_WAIT_LIMIT;

    fill_full_layer_config(layer_idx, &config);
    s_accel_irq_seen = false;

    if (!CNN_Accel_submit_layer_config(&cnn_accel, &config, ACCEL_SUBMIT_WAIT_LIMIT)) {
        print_cnn_status("    submit timeout:", CNN_Accel_get_status(&cnn_accel));
        return false;
    }

    CNN_Accel_start(&cnn_accel);

    while ((wait > 0U) && !s_accel_irq_seen) {
        wait--;
    }

    status = CNN_Accel_get_status(&cnn_accel);
    if (!s_accel_irq_seen) {
        print_cnn_status("    IRQ timeout:", status);
        return false;
    }

    if (!CNN_Accel_wait_idle(&cnn_accel, ACCEL_SUBMIT_WAIT_LIMIT)) {
        print_cnn_status("    idle timeout:", CNN_Accel_get_status(&cnn_accel));
        return false;
    }

    return true;
}

static ACCEL_SIZE_OPT bool read_full_logits(W95_HandleTypeDef *w95_h1_read, int8_t logits[ACCEL_FULL_FINAL_OFMAP_C])
{
    for (uint32_t c = 0U; c < ACCEL_FULL_FINAL_OFMAP_C; c++) {
        int32_t sum = 0;
        uint32_t channel_base = ACCEL_FULL_FINAL_OFMAP_BASE +
                                c * ACCEL_FULL_FINAL_OFMAP_HW * ACCEL_FULL_FINAL_OFMAP_HW;

        for (uint32_t y = 0U; y < ACCEL_FULL_FINAL_OFMAP_HW; y++) {
            uint32_t row_addr = channel_base + y * ACCEL_FULL_FINAL_OFMAP_HW;
            if (!hram_read_bytes(w95_h1_read, row_addr, s_pack_buf, ACCEL_FULL_FINAL_OFMAP_HW)) {
                return false;
            }
            for (uint32_t x = 0U; x < ACCEL_FULL_FINAL_OFMAP_HW; x++) {
                sum += (int32_t)(int8_t)s_pack_buf[x] - (int32_t)ACCEL_FULL_AVGPOOL_IN_ZP;
            }
        }

        logits[c] = requantize_i8(sum,
                                  ACCEL_FULL_AVGPOOL_MULT,
                                  ACCEL_FULL_AVGPOOL_SHIFT,
                                  ACCEL_FULL_AVGPOOL_OUT_ZP);
    }

    return true;
}

static ACCEL_SIZE_OPT void print_full_logits(const int8_t logits[ACCEL_FULL_FINAL_OFMAP_C])
{
    uint32_t best = 0U;

    for (uint32_t i = 0U; i < ACCEL_FULL_FINAL_OFMAP_C; i++) {
        if (logits[i] > logits[best]) {
            best = i;
        }
    }

    Uart_print("Predicted: ");
    print_u32_dec(best);
    Uart_println("");
    Uart_println("Expected : 3 (cat)");
}

static ACCEL_SIZE_OPT uint8_t best_logit_index(const int8_t logits[ACCEL_FULL_FINAL_OFMAP_C])
{
    uint8_t best = 0U;

    for (uint8_t i = 1U; i < ACCEL_FULL_FINAL_OFMAP_C; i++) {
        if (logits[i] > logits[best]) {
            best = i;
        }
    }

    return best;
}

static ACCEL_SIZE_OPT uint16_t stream_crc16_byte(uint16_t crc, uint8_t data)
{
    crc ^= ((uint16_t)data << 8);
    for (uint8_t bit = 0U; bit < 8U; bit++) {
        if ((crc & 0x8000U) != 0U) {
            crc = (uint16_t)((crc << 1) ^ 0x1021U);
        } else {
            crc <<= 1;
        }
    }
    return crc;
}

static ACCEL_SIZE_OPT uint16_t stream_crc16_block(uint16_t init_crc, const uint8_t *data, uint32_t length)
{
    uint16_t crc = init_crc;

    for (uint32_t i = 0U; i < length; i++) {
        crc = stream_crc16_byte(crc, data[i]);
    }

    return crc;
}

static ACCEL_SIZE_OPT uint32_t stream_crc32_byte(uint32_t crc, uint8_t data)
{
    crc ^= (uint32_t)data;
    for (uint8_t bit = 0U; bit < 8U; bit++) {
        if ((crc & 1U) != 0U) {
            crc = (crc >> 1U) ^ 0xEDB88320U;
        } else {
            crc >>= 1U;
        }
    }
    return crc;
}

static ACCEL_SIZE_OPT uint32_t stream_crc32_block(uint32_t init_crc, const uint8_t *data, uint32_t length)
{
    uint32_t crc = init_crc;

    for (uint32_t i = 0U; i < length; i++) {
        crc = stream_crc32_byte(crc, data[i]);
    }

    return crc;
}

static ACCEL_SIZE_OPT uint32_t stream_read_le32(const uint8_t *data)
{
    return ((uint32_t)data[0]) |
           ((uint32_t)data[1] << 8) |
           ((uint32_t)data[2] << 16) |
           ((uint32_t)data[3] << 24);
}

static ACCEL_SIZE_OPT void stream_write_le32(uint8_t *data, uint32_t value)
{
    data[0] = (uint8_t)(value & 0xFFU);
    data[1] = (uint8_t)((value >> 8) & 0xFFU);
    data[2] = (uint8_t)((value >> 16) & 0xFFU);
    data[3] = (uint8_t)((value >> 24) & 0xFFU);
}

static ACCEL_SIZE_OPT void stream_write_le16(uint8_t *data, uint16_t value)
{
    data[0] = (uint8_t)(value & 0xFFU);
    data[1] = (uint8_t)((value >> 8) & 0xFFU);
}

static ACCEL_SIZE_OPT bool stream_uart_read_timeout(uint8_t *data, uint32_t timeout_ms)
{
    uint32_t start = millis();

    while (!Uart_read(data)) {
        if ((uint32_t)(millis() - start) >= timeout_ms) {
            return false;
        }
    }

    return true;
}

static ACCEL_SIZE_OPT void stream_send_response(uint8_t seq, uint8_t status, const uint8_t *data, uint16_t len)
{
    uint8_t header[5];
    uint16_t crc;

    header[0] = ACCEL_UART_STREAM_SOF;
    header[1] = seq;
    header[2] = status;
    header[3] = (uint8_t)(len & 0xFFU);
    header[4] = (uint8_t)((len >> 8) & 0xFFU);

    crc = stream_crc16_block(0xFFFFU, &header[1], 4U);
    if ((data != 0) && (len > 0U)) {
        crc = stream_crc16_block(crc, data, len);
    }

    for (uint8_t i = 0U; i < sizeof(header); i++) {
        Uart_write(header[i]);
    }
    for (uint16_t i = 0U; i < len; i++) {
        Uart_write(data[i]);
    }
    Uart_write((uint8_t)(crc & 0xFFU));
    Uart_write((uint8_t)((crc >> 8) & 0xFFU));
    Uart_write(ACCEL_UART_STREAM_EOF);
}

static ACCEL_SIZE_OPT void stream_send_error(uint8_t seq, uint8_t code, uint32_t info)
{
    uint8_t payload[5];

    payload[0] = code;
    stream_write_le32(&payload[1], info);
    stream_send_response(seq, ACCEL_UART_STREAM_ERROR, payload, sizeof(payload));
}

static ACCEL_SIZE_OPT bool stream_receive_frame(AccelStreamFrame_t *frame)
{
    uint8_t byte;
    uint8_t header[4];
    uint8_t crc_l;
    uint8_t crc_h;
    uint8_t eof;
    uint16_t calculated_crc;
    uint16_t received_crc;

    do {
        if (!stream_uart_read_timeout(&byte, ACCEL_UART_STREAM_TIMEOUT_MS)) {
            return false;
        }
    } while (byte != ACCEL_UART_STREAM_SOF);

    for (uint8_t i = 0U; i < sizeof(header); i++) {
        if (!stream_uart_read_timeout(&header[i], ACCEL_UART_STREAM_FRAME_MS)) {
            return false;
        }
    }

    frame->seq = header[0];
    frame->cmd = header[1];
    frame->len = (uint16_t)header[2] | ((uint16_t)header[3] << 8);

    if (frame->len > ACCEL_UART_STREAM_MAX_PAYLOAD) {
        stream_send_response(frame->seq, ACCEL_UART_STREAM_NACK, 0, 0U);
        return false;
    }

    for (uint16_t i = 0U; i < frame->len; i++) {
        if (!stream_uart_read_timeout(&frame->payload[i], ACCEL_UART_STREAM_FRAME_MS)) {
            stream_send_response(frame->seq, ACCEL_UART_STREAM_NACK, 0, 0U);
            return false;
        }
    }

    if (!stream_uart_read_timeout(&crc_l, ACCEL_UART_STREAM_FRAME_MS) ||
        !stream_uart_read_timeout(&crc_h, ACCEL_UART_STREAM_FRAME_MS) ||
        !stream_uart_read_timeout(&eof, ACCEL_UART_STREAM_FRAME_MS)) {
        stream_send_response(frame->seq, ACCEL_UART_STREAM_NACK, 0, 0U);
        return false;
    }

    calculated_crc = stream_crc16_block(0xFFFFU, header, sizeof(header));
    calculated_crc = stream_crc16_block(calculated_crc, frame->payload, frame->len);
    received_crc = (uint16_t)crc_l | ((uint16_t)crc_h << 8);
    if ((eof != ACCEL_UART_STREAM_EOF) || (calculated_crc != received_crc)) {
        stream_send_response(frame->seq, ACCEL_UART_STREAM_NACK, 0, 0U);
        return false;
    }

    return true;
}

static ACCEL_SIZE_OPT bool stream_crc32_hyperram1_ifmap(W95_HandleTypeDef *w95_h1_read, uint32_t *crc_out)
{
    uint32_t done = 0U;
    uint32_t crc = 0xFFFFFFFFU;

    while (done < ACCEL_UART_STREAM_IMAGE_BYTES) {
        uint32_t chunk = ACCEL_UART_STREAM_IMAGE_BYTES - done;
        if (chunk > ACCEL_PACK_BUF_BYTES) {
            chunk = ACCEL_PACK_BUF_BYTES;
        }
        if (!hram_read_bytes(w95_h1_read, ACCEL_HRAM1_IFMAP_BASE + done, s_pack_buf, chunk)) {
            return false;
        }
        crc = stream_crc32_block(crc, s_pack_buf, chunk);
        done += chunk;
    }

    *crc_out = crc ^ 0xFFFFFFFFU;
    return true;
}

static ACCEL_SIZE_OPT bool run_full_model_for_stream(W95_HandleTypeDef *w95_h1_read,
                                                     uint8_t *prediction,
                                                     tick_t *conv_ticks,
                                                     tick_t *avgpool_ticks)
{
    int8_t logits[ACCEL_FULL_FINAL_OFMAP_C];
    bool ok = true;

    conv_ticks->lower = 0U;
    conv_ticks->upper = 0U;
    avgpool_ticks->lower = 0U;
    avgpool_ticks->upper = 0U;

    for (uint8_t i = 0U; ok && (i < ACCEL_FULL_LAYER_COUNT); i++) {
        tick_t start_tick;
        tick_t end_tick;

        HyperRAM_set_accel_mode(&hyperram0, true);
        HyperRAM_set_accel_mode(&hyperram1, true);
        start_tick = read_tick();
        ok = run_full_accel_layer(i);
        if (ok) {
            ok = drain_ofbuf_to_hyperram1();
        }
        end_tick = read_tick();
        HyperRAM_set_accel_mode(&hyperram0, false);
        HyperRAM_set_accel_mode(&hyperram1, false);

        if (ok) {
            *conv_ticks = accel_add_ticks(*conv_ticks, accel_elapsed_ticks(start_tick, end_tick));
        }
    }

    if (ok) {
        tick_t start_tick = read_tick();
        ok = read_full_logits(w95_h1_read, logits);
        *avgpool_ticks = accel_elapsed_ticks(start_tick, read_tick());
    }

    if (ok) {
        *prediction = best_logit_index(logits);
    }

    HyperRAM_set_accel_mode(&hyperram0, false);
    HyperRAM_set_accel_mode(&hyperram1, false);
    return ok;
}

static ACCEL_SIZE_OPT void stream_send_run_result(uint8_t seq,
                                                  uint8_t expected_label,
                                                  uint8_t prediction,
                                                  uint32_t crc32,
                                                  tick_t conv_ticks,
                                                  tick_t avgpool_ticks)
{
    uint8_t payload[28];

    stream_write_le32(&payload[0], s_stream_session.image_index);
    payload[4] = expected_label;
    payload[5] = prediction;
    payload[6] = (expected_label == prediction) ? 1U : 0U;
    payload[7] = 0U;
    stream_write_le32(&payload[8], crc32);
    stream_write_le32(&payload[12], conv_ticks.lower);
    stream_write_le32(&payload[16], conv_ticks.upper);
    stream_write_le32(&payload[20], avgpool_ticks.lower);
    stream_write_le32(&payload[24], avgpool_ticks.upper);

    stream_send_response(seq, ACCEL_UART_STREAM_ACK, payload, sizeof(payload));
}

static ACCEL_SIZE_OPT bool compare_accel_output(W95_HandleTypeDef *w95_h1_read)
{
    const int8_t *image = AllCNN_CIFAR10_GetTestImageHWC();
    uint32_t mismatches = 0U;
    uint32_t max_abs_diff = 0U;
    uint32_t first_oc = 0U;
    uint32_t first_y = 0U;
    uint32_t first_x = 0U;
    int8_t first_expected = 0;
    int8_t first_actual = 0;

    if (image == 0) {
        return false;
    }

    for (uint32_t oc = 0U; oc < ACCEL_CONV1_VERIFY_OUT_C; oc++) {
        for (uint32_t y = 0U; y < ACCEL_CONV1_VERIFY_OUT_H; y++) {
            uint32_t addr = ACCEL_HRAM1_OFMAP_BASE +
                            oc * ACCEL_CONV1_OUT_H * ACCEL_CONV1_OUT_W +
                            y * ACCEL_CONV1_OUT_W;

            if (!hram_read_bytes(w95_h1_read, addr, s_accel_row, ACCEL_CONV1_OUT_W)) {
                return false;
            }

            for (uint32_t x = 0U; x < ACCEL_CONV1_OUT_W; x++) {
                int8_t expected = cpu_conv1_value(image, oc, y, x);
                int8_t actual = (int8_t)s_accel_row[x];
                int32_t diff = (int32_t)actual - (int32_t)expected;
                uint32_t abs_diff = (diff < 0) ? (uint32_t)(-diff) : (uint32_t)diff;

                if (abs_diff > max_abs_diff) {
                    max_abs_diff = abs_diff;
                }

                if (actual != expected) {
                    if (mismatches == 0U) {
                        first_oc = oc;
                        first_y = y;
                        first_x = x;
                        first_expected = expected;
                        first_actual = actual;
                    }
                    mismatches++;
                }
            }
        }
    }

    Uart_println("");
    Uart_println("Conv1 accel vs CPU golden:");
    Uart_print("  Mismatches : ");
    print_u32_dec(mismatches);
    Uart_print(" / ");
    print_u32_dec(ACCEL_CONV1_VERIFY_OUT_H * ACCEL_CONV1_OUT_W * ACCEL_CONV1_VERIFY_OUT_C);
    Uart_println("");
    Uart_print("  Max |diff| : ");
    print_u32_dec(max_abs_diff);
    Uart_println("");

    if (mismatches != 0U) {
        Uart_print("  First mismatch oc=");
        print_u32_dec(first_oc);
        Uart_print(" y=");
        print_u32_dec(first_y);
        Uart_print(" x=");
        print_u32_dec(first_x);
        Uart_print(" expected=");
        print_i32_dec((int32_t)first_expected);
        Uart_print(" actual=");
        print_i32_dec((int32_t)first_actual);
        Uart_println("");

        {
            uint32_t row_addr = ACCEL_HRAM1_OFMAP_BASE +
                                first_oc * ACCEL_CONV1_OUT_H * ACCEL_CONV1_OUT_W +
                                first_y * ACCEL_CONV1_OUT_W;

            Uart_print("  First mismatch row addr=0x");
            Uart_print_hex_32(row_addr);
            Uart_println("");

            Uart_print("  Row accel: [");
            if (!hram_read_bytes(w95_h1_read, row_addr, s_accel_row, ACCEL_CONV1_OUT_W)) {
                return false;
            }
            for (uint32_t i = 0U; i < 16U; i++) {
                print_i32_dec((int32_t)(int8_t)s_accel_row[i]);
                if (i != 15U) {
                    Uart_write(',');
                }
            }
            Uart_println("]");

            Uart_print("  Row CPU  : [");
            for (uint32_t i = 0U; i < 16U; i++) {
                print_i32_dec((int32_t)cpu_conv1_value(image, first_oc, first_y, i));
                if (i != 15U) {
                    Uart_write(',');
                }
            }
            Uart_println("]");
        }
    }

    Uart_print("  Sample oc0 row0 accel: [");
    if (!hram_read_bytes(w95_h1_read, ACCEL_HRAM1_OFMAP_BASE, s_accel_row, ACCEL_CONV1_OUT_W)) {
        return false;
    }
    for (uint32_t i = 0U; i < 16U; i++) {
        print_i32_dec((int32_t)(int8_t)s_accel_row[i]);
        if (i != 15U) {
            Uart_write(',');
        }
    }
    Uart_println("]");

    Uart_print("  Sample oc0 row0 CPU  : [");
    for (uint32_t i = 0U; i < 16U; i++) {
        print_i32_dec((int32_t)cpu_conv1_value(image, 0U, 0U, i));
        if (i != 15U) {
            Uart_write(',');
        }
    }
    Uart_println("]");

    return mismatches == 0U;
}

ACCEL_SIZE_OPT bool AllCNN_CIFAR10_Accel_PrepareFullPayload(void)
{
    WeightHyperRAM_LoadInfo_t load_info;
    W95_HandleTypeDef w95_h0_read;
    W95_HandleTypeDef w95_h0_write;
    W95_HandleTypeDef w95_h1_read;
    W95_HandleTypeDef w95_h1_write;
    bool old_video_enable;
    bool old_video_grant;
    uint32_t blob_size = 0U;
    uint32_t ifmap_bytes = 0U;
    bool ok = true;

    Uart_println("");
    Uart_println("=== Prepare ALL_CNN_C full accel payload ===");
    Uart_println("Packing full payload from the HyperRAM0 weight blob. Alpha params forced to 0.");

    s_conv1_payload_ready = false;
    s_full_payload_ready = false;
    s_conv1_source_params_ready = false;

    if (!WeightHyperRAM_LoadWeightsFromFlashMetadata(WEIGHTS_ALLCNN_METADATA_OFFSET_ADDR,
                                                     &load_info)) {
        Uart_println("Failed to load ALLCNN weights from flash.");
        return false;
    }
    if (load_info.flash_size != ACCEL_ALLCNN_BLOB_BYTES) {
        Uart_println("Unexpected ALLCNN weight size.");
        return false;
    }

    HyperRAM_init(&hyperram0, HYPERRAM_0_BASE_ADDR);
    HyperRAM_init(&hyperram1, HYPERRAM_1_BASE_ADDR);
    HyperRAM_set_accel_mode(&hyperram0, false);
    HyperRAM_set_accel_mode(&hyperram1, false);

    W95_Init(&w95_h0_read,
             &hyperram0,
             WEIGHT_HYPERRAM0_READ_LATENCY,
             WEIGHT_HYPERRAM0_READ_RECOVERY,
             WEIGHT_HYPERRAM0_READ_CAPTURE_SHMOO);
    W95_Init(&w95_h0_write,
             &hyperram0,
             WEIGHT_HYPERRAM0_WRITE_LATENCY,
             WEIGHT_HYPERRAM0_WRITE_RECOVERY,
             WEIGHT_HYPERRAM0_WRITE_CAPTURE_SHMOO);
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

    if (!hram_read_bytes(&w95_h0_read, 0U, (uint8_t *)&blob_size, sizeof(blob_size))) {
        ok = false;
    }
    if (ok) {
        Uart_print("  Raw weight blob header: 0x");
        Uart_print_hex_32(blob_size);
        Uart_println("");
        if (blob_size != ACCEL_ALLCNN_BLOB_BYTES) {
            Uart_println("  Warning: unexpected weight blob header.");
        }
    }

    if (ok) {
        Uart_print("  Packed HR0 base: 0x");
        Uart_print_hex_32(ACCEL_FULL_HRAM0_PARAM_BASE);
        Uart_println("");
        Uart_println("  Write cat image to HR1 IFMAP...");
        ok = write_cat_image_to_hyperram1(&w95_h1_write);
    }
    if (ok) {
        ok = verify_conv1_ifmap_full(&w95_h1_read, &ifmap_bytes);
    }
    if (ok) {
        print_verify_pass("FULL IFMAP L1", ifmap_bytes);
    }

    for (uint8_t i = 0U; ok && (i < ACCEL_FULL_LAYER_COUNT); i++) {
        ok = pack_full_layer_params(&w95_h0_read, &w95_h0_write, i);
    }

    VideoStreaming_set_grant_request(&video_streaming, old_video_grant);
    VideoStreaming_enable(&video_streaming, old_video_enable);

    if (!ok) {
        Uart_println("Full payload -> FAIL");
        return false;
    }

    s_full_payload_ready = true;
    Uart_println("Full payload -> PASS");
    Uart_println("Run 4.4 for 9 conv layers, or 4.5 for UART accuracy stream.");

    return true;
}

static ACCEL_SIZE_OPT bool run_full_model_with_ifmap_source(bool use_camera_ifmap)
{
    W95_HandleTypeDef w95_h1_read;
    bool old_video_enable;
    bool old_video_grant;
    int32_t old_video_mult;
    uint8_t old_video_shift;
    int8_t old_video_zp;
    bool ok = true;
    int8_t logits[ACCEL_FULL_FINAL_OFMAP_C];
    tick_t conv_ticks = { 0U, 0U };
    tick_t avgpool_ticks = { 0U, 0U };
    tick_t profile_sum;
    tick_t wall_start = { 0U, 0U };
    tick_t wall_ticks = { 0U, 0U };
    uint32_t total_macs = 0U;

    Uart_println("");
    if (use_camera_ifmap) {
        Uart_println("=== Run ALL_CNN_C full hardware accelerator (camera IFMAP layer 1) ===");
        Uart_println("Run 1.1, then 4.3 first. ALLCNN weights load from flash automatically.");
    } else {
        Uart_println("=== Run ALL_CNN_C full hardware accelerator ===");
        Uart_println("Runs with the current HyperRAM payload.");
    }

    if (!s_full_payload_ready) {
        if (use_camera_ifmap) {
            Uart_println("Full accel payload not prepared. Run 4.3.");
            return false;
        }

        Uart_println("Warning: full accel payload not prepared in this boot.");
        Uart_println("Running anyway with current HyperRAM contents.");
    }

    HyperRAM_init(&hyperram0, HYPERRAM_0_BASE_ADDR);
    HyperRAM_init(&hyperram1, HYPERRAM_1_BASE_ADDR);
    HyperRAM_set_accel_mode(&hyperram0, false);
    HyperRAM_set_accel_mode(&hyperram1, false);

    W95_Init(&w95_h1_read,
             &hyperram1,
             WEIGHT_HYPERRAM1_READ_LATENCY,
             WEIGHT_HYPERRAM1_READ_RECOVERY,
             WEIGHT_HYPERRAM1_READ_CAPTURE_SHMOO);

    old_video_enable = VideoStreaming_is_enabled(&video_streaming);
    old_video_grant = VideoStreaming_get_grant_request(&video_streaming);
    old_video_mult = VideoStreaming_get_scale_multiplier(&video_streaming);
    old_video_shift = VideoStreaming_get_scale_shift(&video_streaming);
    old_video_zp = VideoStreaming_get_zero_point(&video_streaming);

    VideoStreaming_set_grant_request(&video_streaming, false);
    if (use_camera_ifmap) {
        VideoStreaming_set_quantization(&video_streaming,
                                        ACCEL_VIDEO_IFMAP_SCALE_MULT,
                                        ACCEL_VIDEO_IFMAP_SCALE_SHIFT,
                                        ACCEL_VIDEO_IFMAP_ZP);
        VideoStreaming_enable(&video_streaming, true);
        delay(ACCEL_VIDEO_IFMAP_WARMUP_MS);
    } else {
        VideoStreaming_enable(&video_streaming, false);
    }

    if (!CNN_Accel_attach_irq(cnn_accel_irq_handler, 0, IRQ_PRIORITY_DEFAULT)) {
        Uart_println("  CNN IRQ attach failed.");
        ok = false;
    }
    if (ok) {
        CNN_Accel_enable_irq();
        HyperRAM_set_dmac_weights(&hyperram0, ACCEL_DMAC_WRITE_WEIGHT, ACCEL_DMAC_READ_WEIGHT);
        HyperRAM_set_dmac_weights(&hyperram1, ACCEL_DMAC_WRITE_WEIGHT, ACCEL_DMAC_READ_WEIGHT);
        wall_start = read_tick();
    }

    for (uint8_t i = 0U; ok && (i < ACCEL_FULL_LAYER_COUNT); i++) {
        tick_t start_tick;
        tick_t end_tick;
        tick_t elapsed_tick;

        HyperRAM_set_accel_mode(&hyperram0, true);
        HyperRAM_set_accel_mode(&hyperram1, true);

        Uart_print("  Layer ");
        print_u32_dec((uint32_t)i + 1U);
        Uart_print(": input ");
        print_u32_dec(s_full_layers[i].ifheight);
        Uart_write('x');
        print_u32_dec(s_full_layers[i].ifheight);
        Uart_print("x");
        print_u32_dec(s_full_layers[i].ifchannel);
        Uart_print(" -> output ");
        print_u32_dec(full_layer_ofwidth(&s_full_layers[i]));
        Uart_write('x');
        print_u32_dec(full_layer_ofwidth(&s_full_layers[i]));
        Uart_print("x");
        print_u32_dec(s_full_layers[i].ofchannel);
        Uart_println("");

        if (use_camera_ifmap) {
            VideoStreaming_set_grant_request(&video_streaming, i == 0U);
            if (i == 0U) {
                Uart_println("    IFMAP source: camera/video stream");
            } else if (i == 1U) {
                Uart_println("    IFMAP source: HyperRAM1 activation buffers");
            }
        }

        start_tick = read_tick();
        ok = run_full_accel_layer(i);
        if (use_camera_ifmap && (i == 0U)) {
            VideoStreaming_set_grant_request(&video_streaming, false);
        }
        if (ok) {
            ok = drain_ofbuf_to_hyperram1();
        }
        end_tick = read_tick();
        elapsed_tick = accel_elapsed_ticks(start_tick, end_tick);

        HyperRAM_set_accel_mode(&hyperram0, false);
        HyperRAM_set_accel_mode(&hyperram1, false);

        if (ok) {
            conv_ticks = accel_add_ticks(conv_ticks, elapsed_tick);
            total_macs += full_layer_macs(&s_full_layers[i]);
            print_layer_profile(i, &s_full_layers[i], elapsed_tick);
        }
    }

    CNN_Accel_disable_irq();
    VideoStreaming_set_grant_request(&video_streaming, false);
    HyperRAM_set_accel_mode(&hyperram0, false);
    HyperRAM_set_accel_mode(&hyperram1, false);

    if (ok) {
        tick_t avgpool_start;
        tick_t avgpool_end;

        Uart_println("GlobalAvgPool 6x6x10...");
        avgpool_start = read_tick();
        ok = read_full_logits(&w95_h1_read, logits);
        avgpool_end = read_tick();
        avgpool_ticks = accel_elapsed_ticks(avgpool_start, avgpool_end);
        wall_ticks = accel_elapsed_ticks(wall_start, avgpool_end);
    }
    if (ok) {
        print_full_logits(logits);
        profile_sum = accel_add_ticks(conv_ticks, avgpool_ticks);
        print_full_profile_summary(conv_ticks,
                                   avgpool_ticks,
                                   profile_sum,
                                   wall_ticks,
                                   total_macs);
    }

    VideoStreaming_set_quantization(&video_streaming,
                                    old_video_mult,
                                    old_video_shift,
                                    old_video_zp);
    VideoStreaming_enable(&video_streaming, old_video_enable);
    VideoStreaming_set_grant_request(&video_streaming, old_video_grant);

    Uart_println(ok ? "Full accel -> DONE" : "Full accel -> FAIL");

    return ok;
}

ACCEL_SIZE_OPT bool AllCNN_CIFAR10_Accel_RunFullModel(void)
{
    return run_full_model_with_ifmap_source(false);
}

ACCEL_SIZE_OPT bool AllCNN_CIFAR10_Accel_RunFullModelCameraIfmap(void)
{
    return run_full_model_with_ifmap_source(true);
}

ACCEL_SIZE_OPT bool AllCNN_CIFAR10_Accel_RunUartAccuracyStream(void)
{
    W95_HandleTypeDef w95_h1_read;
    W95_HandleTypeDef w95_h1_write;
    bool old_video_enable;
    bool old_video_grant;
    bool ok = true;
    bool done = false;

    Uart_println("");
    Uart_println("=== ALL_CNN_C UART accuracy stream ===");
    Uart_println("Run 2.2, then 4.3 first. Host sends 32x32x3 int8 images.");

    if (!s_full_payload_ready) {
        Uart_println("Full accel payload not prepared. Run 4.3.");
        return false;
    }

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

    if (!CNN_Accel_attach_irq(cnn_accel_irq_handler, 0, IRQ_PRIORITY_DEFAULT)) {
        Uart_println("  CNN IRQ attach failed.");
        VideoStreaming_set_grant_request(&video_streaming, old_video_grant);
        VideoStreaming_enable(&video_streaming, old_video_enable);
        return false;
    }

    CNN_Accel_enable_irq();
    HyperRAM_set_dmac_weights(&hyperram0, ACCEL_DMAC_WRITE_WEIGHT, ACCEL_DMAC_READ_WEIGHT);
    HyperRAM_set_dmac_weights(&hyperram1, ACCEL_DMAC_WRITE_WEIGHT, ACCEL_DMAC_READ_WEIGHT);
    s_stream_session.active = false;

    Uart_println("ACC_STREAM_READY");

    while (!done) {
        uint8_t *payload = s_stream_frame.payload;

        if (!stream_receive_frame(&s_stream_frame)) {
            continue;
        }

        switch (s_stream_frame.cmd) {
        case ACCEL_UART_STREAM_CMD_INFO: {
            uint32_t image_size;

            if (s_stream_frame.len != 13U) {
                stream_send_error(s_stream_frame.seq, ACCEL_UART_STREAM_ERR_LENGTH, s_stream_frame.len);
                break;
            }

            image_size = stream_read_le32(&payload[5]);
            if (image_size != ACCEL_UART_STREAM_IMAGE_BYTES) {
                stream_send_error(s_stream_frame.seq, ACCEL_UART_STREAM_ERR_LENGTH, image_size);
                break;
            }

            s_stream_session.active = true;
            s_stream_session.image_index = stream_read_le32(&payload[0]);
            s_stream_session.expected_label = payload[4];
            s_stream_session.expected_crc32 = stream_read_le32(&payload[9]);
            s_stream_session.received_bytes = 0U;
            stream_send_response(s_stream_frame.seq, ACCEL_UART_STREAM_ACK, 0, 0U);
            break;
        }

        case ACCEL_UART_STREAM_CMD_DATA: {
            uint32_t offset;
            uint32_t data_len;

            if (!s_stream_session.active || (s_stream_frame.len < 4U)) {
                stream_send_error(s_stream_frame.seq, ACCEL_UART_STREAM_ERR_STATE, s_stream_frame.len);
                break;
            }

            offset = stream_read_le32(&payload[0]);
            data_len = (uint32_t)s_stream_frame.len - 4U;
            if ((offset != s_stream_session.received_bytes) ||
                ((offset | data_len) & 1U) != 0U ||
                (data_len == 0U) ||
                (offset > ACCEL_UART_STREAM_IMAGE_BYTES) ||
                (data_len > (ACCEL_UART_STREAM_IMAGE_BYTES - offset))) {
                stream_send_error(s_stream_frame.seq, ACCEL_UART_STREAM_ERR_ADDR, offset);
                break;
            }

            if (!hram_write_bytes(&w95_h1_write,
                                  ACCEL_HRAM1_IFMAP_BASE + offset,
                                  &payload[4],
                                  data_len)) {
                stream_send_error(s_stream_frame.seq, ACCEL_UART_STREAM_ERR_ADDR, offset);
                break;
            }

            s_stream_session.received_bytes += data_len;
            stream_send_response(s_stream_frame.seq, ACCEL_UART_STREAM_ACK, 0, 0U);
            break;
        }

        case ACCEL_UART_STREAM_CMD_RUN: {
            uint32_t crc32 = 0U;
            uint8_t prediction = 0U;
            tick_t conv_ticks;
            tick_t avgpool_ticks;

            if (!s_stream_session.active ||
                (s_stream_session.received_bytes != ACCEL_UART_STREAM_IMAGE_BYTES)) {
                stream_send_error(s_stream_frame.seq,
                                  ACCEL_UART_STREAM_ERR_STATE,
                                  s_stream_session.received_bytes);
                break;
            }

            if (!stream_crc32_hyperram1_ifmap(&w95_h1_read, &crc32)) {
                stream_send_error(s_stream_frame.seq, ACCEL_UART_STREAM_ERR_CRC, 0U);
                break;
            }

            if (crc32 != s_stream_session.expected_crc32) {
                stream_send_error(s_stream_frame.seq, ACCEL_UART_STREAM_ERR_CRC, crc32);
                break;
            }

            if (!run_full_model_for_stream(&w95_h1_read, &prediction, &conv_ticks, &avgpool_ticks)) {
                stream_send_error(s_stream_frame.seq,
                                  ACCEL_UART_STREAM_ERR_RUN,
                                  CNN_Accel_get_status(&cnn_accel));
                ok = false;
                break;
            }

            stream_send_run_result(s_stream_frame.seq,
                                   s_stream_session.expected_label,
                                   prediction,
                                   crc32,
                                   conv_ticks,
                                   avgpool_ticks);
            s_stream_session.active = false;
            break;
        }

        case ACCEL_UART_STREAM_CMD_END:
            stream_send_response(s_stream_frame.seq, ACCEL_UART_STREAM_ACK, 0, 0U);
            done = true;
            break;

        default:
            stream_send_error(s_stream_frame.seq, ACCEL_UART_STREAM_ERR_STATE, s_stream_frame.cmd);
            break;
        }
    }

    CNN_Accel_disable_irq();
    HyperRAM_set_accel_mode(&hyperram0, false);
    HyperRAM_set_accel_mode(&hyperram1, false);
    VideoStreaming_set_grant_request(&video_streaming, old_video_grant);
    VideoStreaming_enable(&video_streaming, old_video_enable);
    Uart_println("ACC_STREAM_DONE");

    return ok;
}

ACCEL_SIZE_OPT bool AllCNN_CIFAR10_Accel_PrepareConv1Payload(void)
{
    WeightHyperRAM_LoadInfo_t load_info;
    W95_HandleTypeDef w95_h0_read;
    W95_HandleTypeDef w95_h0_write;
    W95_HandleTypeDef w95_h1_read;
    W95_HandleTypeDef w95_h1_write;
    bool old_video_enable;
    bool old_video_grant;
    bool ok;

    Uart_println("");
    Uart_println("=== Prepare Conv1 accel payload ===");
    Uart_println("ALLCNN weights are loaded from flash automatically.");

    s_conv1_payload_ready = false;
    s_full_payload_ready = false;
    s_conv1_source_params_ready = false;

    if (!WeightHyperRAM_LoadWeightsFromFlashMetadata(WEIGHTS_ALLCNN_METADATA_OFFSET_ADDR,
                                                     &load_info)) {
        Uart_println("Failed to load ALLCNN weights from flash.");
        return false;
    }
    if (load_info.flash_size != ACCEL_ALLCNN_BLOB_BYTES) {
        Uart_println("Unexpected ALLCNN weight size.");
        return false;
    }

    HyperRAM_init(&hyperram0, HYPERRAM_0_BASE_ADDR);
    HyperRAM_init(&hyperram1, HYPERRAM_1_BASE_ADDR);
    HyperRAM_set_accel_mode(&hyperram0, false);
    HyperRAM_set_accel_mode(&hyperram1, false);

    W95_Init(&w95_h0_read,
             &hyperram0,
             WEIGHT_HYPERRAM0_READ_LATENCY,
             WEIGHT_HYPERRAM0_READ_RECOVERY,
             WEIGHT_HYPERRAM0_READ_CAPTURE_SHMOO);
    W95_Init(&w95_h0_write,
             &hyperram0,
             WEIGHT_HYPERRAM0_WRITE_LATENCY,
             WEIGHT_HYPERRAM0_WRITE_RECOVERY,
             WEIGHT_HYPERRAM0_WRITE_CAPTURE_SHMOO);
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

    Uart_println("");
    Uart_println("Preparing payloads:");
    Uart_print("  IFMAP  HyperRAM1 @ 0x");
    Uart_print_hex_32(ACCEL_HRAM1_IFMAP_BASE);
    Uart_println(" (cat image, CHW)");
    Uart_print("  OFMAP  HyperRAM1 @ 0x");
    Uart_print_hex_32(ACCEL_HRAM1_OFMAP_BASE);
    Uart_println("");
    Uart_print("  FLT    HyperRAM0 @ 0x");
    Uart_print_hex_32(ACCEL_HRAM0_FLT_BASE);
    Uart_println(" (accel packed)");
    Uart_print("  BIAS   HyperRAM0 @ 0x");
    Uart_print_hex_32(ACCEL_HRAM0_BIAS_BASE);
    Uart_println(" (accel packed)");
    Uart_print("  Parallel config: ifparr=");
    print_u32_dec(ACCEL_IFPARR);
    Uart_print(" ofparr=");
    print_u32_dec(ACCEL_OFPARR);
    Uart_print(" oftile=");
    print_u32_dec(ACCEL_OFTILE);
    Uart_println("");

    ok = read_conv1_source_params(&w95_h0_read);
    if (ok) {
        ok = write_cat_image_to_hyperram1(&w95_h1_write);
    }
    if (ok) {
        uint32_t ifmap_bytes = 0U;
        ok = verify_conv1_ifmap_full(&w95_h1_read, &ifmap_bytes);
        if (ok) {
            print_verify_pass("CONV1 IFMAP", ifmap_bytes);
        }
    }
    if (ok) {
        ok = pack_full_layer_params(&w95_h0_read, &w95_h0_write, 0U);
    }

    if (!ok) {
        Uart_println("Payload prep failed.");
        VideoStreaming_set_grant_request(&video_streaming, old_video_grant);
        VideoStreaming_enable(&video_streaming, old_video_enable);
        return false;
    }

    s_conv1_payload_ready = true;

    VideoStreaming_set_grant_request(&video_streaming, old_video_grant);
    VideoStreaming_enable(&video_streaming, old_video_enable);

    Uart_println("Conv1 payload -> PASS");
    Uart_println("Run 3.3 to start Conv1.");

    return true;
}

ACCEL_SIZE_OPT bool AllCNN_CIFAR10_Accel_RunConv1Bringup(void)
{
    W95_HandleTypeDef w95_h0_read;
    W95_HandleTypeDef w95_h1_read;
    bool old_video_enable;
    bool old_video_grant;
    bool ok;
    tick_t start_tick;
    tick_t end_tick;

    Uart_println("");
    Uart_println("=== Run Conv1 hardware accelerator ===");
    Uart_println("Run 2.2, then 2.3 first.");

    if (!s_conv1_payload_ready) {
        Uart_println("Conv1 payload not ready. Run 2.3.");
        return false;
    }

    HyperRAM_init(&hyperram0, HYPERRAM_0_BASE_ADDR);
    HyperRAM_init(&hyperram1, HYPERRAM_1_BASE_ADDR);
    HyperRAM_set_accel_mode(&hyperram0, false);
    HyperRAM_set_accel_mode(&hyperram1, false);

    W95_Init(&w95_h0_read,
             &hyperram0,
             WEIGHT_HYPERRAM0_READ_LATENCY,
             WEIGHT_HYPERRAM0_READ_RECOVERY,
             WEIGHT_HYPERRAM0_READ_CAPTURE_SHMOO);
    W95_Init(&w95_h1_read,
             &hyperram1,
             WEIGHT_HYPERRAM1_READ_LATENCY,
             WEIGHT_HYPERRAM1_READ_RECOVERY,
             WEIGHT_HYPERRAM1_READ_CAPTURE_SHMOO);

    if (!s_conv1_source_params_ready) {
        if (!read_conv1_source_params(&w95_h0_read)) {
            Uart_println("Conv1 source params not ready.");
            return false;
        }
    }

    old_video_enable = VideoStreaming_is_enabled(&video_streaming);
    old_video_grant = VideoStreaming_get_grant_request(&video_streaming);
    VideoStreaming_enable(&video_streaming, false);
    VideoStreaming_set_grant_request(&video_streaming, false);

    HyperRAM_set_dmac_weights(&hyperram0, ACCEL_DMAC_WRITE_WEIGHT, ACCEL_DMAC_READ_WEIGHT);
    HyperRAM_set_dmac_weights(&hyperram1, ACCEL_DMAC_WRITE_WEIGHT, ACCEL_DMAC_READ_WEIGHT);
    HyperRAM_set_accel_mode(&hyperram0, true);
    HyperRAM_set_accel_mode(&hyperram1, true);
    print_hyperram_mode("HR0", &hyperram0);
    print_hyperram_mode("HR1", &hyperram1);

    Uart_println("");
    Uart_println("Starting CNN accel conv1...");
    start_tick = read_tick();
    ok = run_accel_layer();
    end_tick = read_tick();

    if (ok) {
        ok = drain_ofbuf_to_hyperram1();
    }

    HyperRAM_set_accel_mode(&hyperram0, false);
    HyperRAM_set_accel_mode(&hyperram1, false);

    if (!ok) {
        Uart_println("CNN accel conv1 failed.");
        VideoStreaming_set_grant_request(&video_streaming, old_video_grant);
        VideoStreaming_enable(&video_streaming, old_video_enable);
        return false;
    }

    Uart_print("CNN accel conv1 done. cycles=0x");
    Uart_print_hex_32(end_tick.upper - start_tick.upper);
    Uart_print_hex_32(end_tick.lower - start_tick.lower);
    Uart_println("");

    ok = compare_accel_output(&w95_h1_read);

    VideoStreaming_set_grant_request(&video_streaming, old_video_grant);
    VideoStreaming_enable(&video_streaming, old_video_enable);

    Uart_println(ok ? "Conv1 hardware bring-up -> PASS" : "Conv1 hardware bring-up -> FAIL");

    return ok;
}
