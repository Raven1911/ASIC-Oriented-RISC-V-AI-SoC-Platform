#include "squeezenet1_1_imagenet_accel.h"

#include <stdint.h>

#include "CNN_Accel_Driver.h"
#include "HyperRAM_Driver.h"
#include "Interrupt_Driver.h"
#include "timer.h"
#include "UART_Driver.h"
#include "flash_utils.h"
#include "W95_HyperRAM.h"
#include "weight_hyperram_loader.h"

#define SQUEEZENET1_1_IMAGENET_SIZE_OPT __attribute__((noinline, optimize("Os")))

#define SQUEEZENET1_1_IMAGENET_LAYER_COUNT               26U
#define SQUEEZENET1_1_IMAGENET_CPU_OP_COUNT              3U
#define SQUEEZENET1_1_IMAGENET_CPU_OP_TABLE_LEN          3U
#define SQUEEZENET1_1_IMAGENET_EXEC_STEP_COUNT           29U
#define SQUEEZENET1_1_IMAGENET_EXEC_STEP_TABLE_LEN       29U
#define SQUEEZENET1_1_IMAGENET_CPU_MAX_INPUTS            1U
#define SQUEEZENET1_1_IMAGENET_CPU_IN_CHANNEL_BYTES      12432U
#define SQUEEZENET1_1_IMAGENET_CPU_OUT_CHANNEL_BYTES     3080U
#define SQUEEZENET1_1_IMAGENET_HRAM_RW_BUF_BYTES         510U
#define SQUEEZENET1_1_IMAGENET_HRAM_BLOCK_CHUNK_BYTES    510U
#define SQUEEZENET1_1_IMAGENET_CPU_PROGRESS_LOG          0U
#define SQUEEZENET1_1_IMAGENET_DMAC_WRITE_WEIGHT         1U
#define SQUEEZENET1_1_IMAGENET_DMAC_READ_WEIGHT          2U
#define SQUEEZENET1_1_IMAGENET_SUBMIT_WAIT_LIMIT         10000000U
#define SQUEEZENET1_1_IMAGENET_IRQ_WAIT_LIMIT            100000000U
#define SQUEEZENET1_1_IMAGENET_HRAM_DRAIN_WAIT_LIMIT     50000000U
#define SQUEEZENET1_1_IMAGENET_HRAM_CPU_WAIT_LIMIT       5000000U
#define SQUEEZENET1_1_IMAGENET_HRAM_DRAIN_STABLE_READS   128U
#define SQUEEZENET1_1_IMAGENET_PARAM_BYTES_RESERVED      1247328U
#define SQUEEZENET1_1_IMAGENET_ACTIVATION_BYTES_RESERVED 4659760U
#define SQUEEZENET1_1_IMAGENET_HAS_FINAL_GAP             1U
#define SQUEEZENET1_1_IMAGENET_FINAL_ROW_BYTES           14U
#define SQUEEZENET1_1_IMAGENET_LOWER_WRAP_MS             ((uint32_t)(0x100000000ULL / CYCLES_PER_MS))
#define SQUEEZENET1_1_IMAGENET_LOWER_WRAP_REM            ((uint32_t)(0x100000000ULL % CYCLES_PER_MS))


#define SQUEEZENET1_1_IMAGENET_STATIC_INPUT_FLASH_OFFSET  0x340000U
#define SQUEEZENET1_1_IMAGENET_STATIC_INPUT_BYTES         150528U
#define SQUEEZENET1_1_IMAGENET_STATIC_INPUT_CRC32         0xB7C9402CU
#define SQUEEZENET1_1_IMAGENET_STATIC_GOLDEN_TOP1         258U
#define SQUEEZENET1_1_IMAGENET_STATIC_GOLDEN_VALUE        107
#define SQUEEZENET1_1_IMAGENET_STATIC_FLASH_CHUNK_BYTES   256U
#define SQUEEZENET1_1_IMAGENET_STATIC_TENSOR_REF_COUNT    29U


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
    uint16_t ifrow_stride;
    uint16_t ofrow_stride;
    int8_t   ifc_zp;
    int8_t   fltc_zp;
    int32_t  mult;
    uint8_t  mult_shift;
    int8_t   zpy;
    int8_t   qmin;
    int8_t   qmax;
    bool     is_leaky_relu;
} Squeezenet11Imagenet_Layer_t;

typedef enum {
    CPU_OP_MAX_POOL_2D = 0,
    CPU_OP_CONCATENATION = 1
} Squeezenet11Imagenet_CpuOpKind_t;

typedef struct {
    uint32_t addr;
    uint16_t height;
    uint16_t width;
    uint16_t channels;
    uint16_t row_stride;
} Squeezenet11Imagenet_TensorView_t;

typedef struct {
    const char *name;
    Squeezenet11Imagenet_CpuOpKind_t kind;
    uint8_t input_count;
    Squeezenet11Imagenet_TensorView_t inputs[SQUEEZENET1_1_IMAGENET_CPU_MAX_INPUTS];
    Squeezenet11Imagenet_TensorView_t output;
    uint8_t filter_h;
    uint8_t filter_w;
    uint8_t stride_h;
    uint8_t stride_w;
    uint8_t pad_top;
    uint8_t pad_left;
    int8_t qmin;
    int8_t qmax;
} Squeezenet11Imagenet_CpuOp_t;

typedef enum {
    EXEC_STEP_ACCEL_CONV = 0,
    EXEC_STEP_CPU_OP = 1
} Squeezenet11Imagenet_ExecStepKind_t;

typedef struct {
    Squeezenet11Imagenet_ExecStepKind_t kind;
    uint16_t index;
} Squeezenet11Imagenet_ExecStep_t;

typedef struct {

    W95_HandleTypeDef w95_h1_read;
    W95_HandleTypeDef w95_h1_write;
} Squeezenet11Imagenet_RunContext_t;

static const Squeezenet11Imagenet_Layer_t s_squeezenet1_1_imagenet_layers[SQUEEZENET1_1_IMAGENET_LAYER_COUNT] = {
    { "Conv1", 224U, 3U, 64U, 3U, 2U, 0U, 3U, 1U, 8U, 0U, 0U, 1728U, 150528U, 224U, 112U, -14, 0, 6034646, 31U, -128, -128, 127, false },
    { "Conv2", 55U, 64U, 16U, 1U, 1U, 0U, 4U, 1U, 16U, 946176U, 1984U, 3008U, 1143296U, 56U, 56U, -128, 0, 9465998, 31U, -128, -128, 127, false },
    { "Conv3", 55U, 16U, 64U, 1U, 1U, 0U, 4U, 1U, 22U, 1143296U, 3072U, 4096U, 1586816U, 56U, 56U, -128, 0, 19765734, 31U, -128, -128, 127, false },
    { "Conv4", 55U, 16U, 64U, 3U, 1U, 1U, 4U, 1U, 8U, 1143296U, 4352U, 13568U, 1783936U, 56U, 56U, -128, 0, 17426383, 31U, -128, -128, 127, false },
    { "Conv5", 55U, 128U, 16U, 1U, 1U, 0U, 4U, 1U, 16U, 1586816U, 13824U, 15872U, 1981056U, 56U, 56U, -128, 0, 10782026, 31U, -128, -128, 127, false },
    { "Conv6", 55U, 16U, 64U, 1U, 1U, 0U, 4U, 1U, 22U, 1981056U, 15936U, 16960U, 2424576U, 56U, 56U, -128, 0, 14612969, 31U, -128, -128, 127, false },
    { "Conv7", 55U, 16U, 64U, 3U, 1U, 1U, 4U, 1U, 8U, 1981056U, 17216U, 26432U, 2621696U, 56U, 56U, -128, 0, 8758567, 31U, -128, -128, 127, false },
    { "Conv8", 27U, 128U, 32U, 1U, 1U, 0U, 4U, 1U, 16U, 2818816U, 26688U, 30784U, 2915584U, 28U, 28U, -128, 0, 9097461, 31U, -128, -128, 127, false },
    { "Conv9", 27U, 32U, 128U, 1U, 1U, 0U, 4U, 1U, 22U, 2915584U, 30912U, 35008U, 3133312U, 28U, 28U, -128, 0, 9992344, 31U, -128, -128, 127, false },
    { "Conv10", 27U, 32U, 128U, 3U, 1U, 1U, 4U, 1U, 8U, 2915584U, 35520U, 72384U, 3230080U, 28U, 28U, -128, 0, 8659129, 31U, -128, -128, 127, false },
    { "Conv11", 27U, 256U, 32U, 1U, 1U, 0U, 4U, 1U, 16U, 3133312U, 72896U, 81088U, 3326848U, 28U, 28U, -128, 0, 13623468, 31U, -128, -128, 127, false },
    { "Conv12", 27U, 32U, 128U, 1U, 1U, 0U, 4U, 1U, 22U, 3326848U, 81216U, 85312U, 3544576U, 28U, 28U, -128, 0, 13552295, 31U, -128, -128, 127, false },
    { "Conv13", 27U, 32U, 128U, 3U, 1U, 1U, 4U, 1U, 8U, 3326848U, 85824U, 122688U, 3641344U, 28U, 28U, -128, 0, 9823483, 31U, -128, -128, 127, false },
    { "Conv14", 13U, 256U, 48U, 1U, 1U, 0U, 4U, 1U, 24U, 3738112U, 123200U, 135488U, 3784704U, 14U, 14U, -128, 0, 7119978, 31U, -128, -128, 127, false },
    { "Conv15", 13U, 48U, 192U, 1U, 1U, 0U, 4U, 1U, 24U, 3784704U, 135680U, 144896U, 3863328U, 14U, 14U, -128, 0, 13560223, 31U, -128, -128, 127, false },
    { "Conv16", 13U, 48U, 192U, 3U, 1U, 1U, 4U, 1U, 8U, 3784704U, 145664U, 228608U, 3898272U, 14U, 14U, -128, 0, 18845066, 31U, -128, -128, 127, false },
    { "Conv17", 13U, 384U, 48U, 1U, 1U, 0U, 4U, 1U, 24U, 3863328U, 229376U, 247808U, 3933216U, 14U, 14U, -128, 0, 6718491, 31U, -128, -128, 127, false },
    { "Conv18", 13U, 48U, 192U, 1U, 1U, 0U, 4U, 1U, 24U, 3933216U, 248000U, 257216U, 4011840U, 14U, 14U, -128, 0, 18758802, 31U, -128, -128, 127, false },
    { "Conv19", 13U, 48U, 192U, 3U, 1U, 1U, 4U, 1U, 8U, 3933216U, 257984U, 340928U, 4046784U, 14U, 14U, -128, 0, 10658528, 31U, -128, -128, 127, false },
    { "Conv20", 13U, 384U, 64U, 1U, 1U, 0U, 4U, 1U, 22U, 4011840U, 341696U, 366272U, 4081728U, 14U, 14U, -128, 0, 6251369, 31U, -128, -128, 127, false },
    { "Conv21", 13U, 64U, 256U, 1U, 1U, 0U, 4U, 1U, 24U, 4081728U, 366528U, 382912U, 4186560U, 14U, 14U, -128, 0, 16040124, 31U, -128, -128, 127, false },
    { "Conv22", 13U, 64U, 256U, 3U, 1U, 1U, 4U, 1U, 8U, 4081728U, 383936U, 531392U, 4233152U, 14U, 14U, -128, 0, 12759153, 31U, -128, -128, 127, false },
    { "Conv23", 13U, 512U, 64U, 1U, 1U, 0U, 3U, 1U, 22U, 4186560U, 532416U, 565184U, 4279744U, 14U, 14U, -128, 0, 7552582, 31U, -128, -128, 127, false },
    { "Conv24", 13U, 64U, 256U, 1U, 1U, 0U, 4U, 1U, 24U, 4279744U, 565440U, 581824U, 4384576U, 14U, 14U, -128, 0, 23118510, 31U, -128, -128, 127, false },
    { "Conv25", 13U, 64U, 256U, 3U, 1U, 1U, 4U, 1U, 8U, 4279744U, 582848U, 730304U, 4431168U, 14U, 14U, -128, 0, 13562459, 31U, -128, -128, 127, false },
    { "Conv26", 13U, 512U, 1000U, 1U, 1U, 0U, 3U, 1U, 24U, 4384576U, 731328U, 1243328U, 4477760U, 14U, 14U, -128, 0, 9790725, 31U, -128, -128, 127, false }
};

static const Squeezenet11Imagenet_CpuOp_t s_squeezenet1_1_imagenet_cpu_ops[SQUEEZENET1_1_IMAGENET_CPU_OP_TABLE_LEN] = {
    { "MaxPool1", CPU_OP_MAX_POOL_2D, 1U, { { 150528U, 111U, 111U, 64U, 112U } }, { 946176U, 55U, 55U, 64U, 56U }, 3U, 3U, 2U, 2U, 0U, 0U, -128, 127 },
    { "MaxPool2", CPU_OP_MAX_POOL_2D, 1U, { { 2424576U, 55U, 55U, 128U, 56U } }, { 2818816U, 27U, 27U, 128U, 28U }, 3U, 3U, 2U, 2U, 0U, 0U, -128, 127 },
    { "MaxPool3", CPU_OP_MAX_POOL_2D, 1U, { { 3544576U, 27U, 27U, 256U, 28U } }, { 3738112U, 13U, 13U, 256U, 14U }, 3U, 3U, 2U, 2U, 0U, 0U, -128, 127 }
};

static const Squeezenet11Imagenet_ExecStep_t s_squeezenet1_1_imagenet_exec_steps[SQUEEZENET1_1_IMAGENET_EXEC_STEP_TABLE_LEN] = {
    { EXEC_STEP_ACCEL_CONV, 0U },
    { EXEC_STEP_CPU_OP, 0U },
    { EXEC_STEP_ACCEL_CONV, 1U },
    { EXEC_STEP_ACCEL_CONV, 2U },
    { EXEC_STEP_ACCEL_CONV, 3U },
    { EXEC_STEP_ACCEL_CONV, 4U },
    { EXEC_STEP_ACCEL_CONV, 5U },
    { EXEC_STEP_ACCEL_CONV, 6U },
    { EXEC_STEP_CPU_OP, 1U },
    { EXEC_STEP_ACCEL_CONV, 7U },
    { EXEC_STEP_ACCEL_CONV, 8U },
    { EXEC_STEP_ACCEL_CONV, 9U },
    { EXEC_STEP_ACCEL_CONV, 10U },
    { EXEC_STEP_ACCEL_CONV, 11U },
    { EXEC_STEP_ACCEL_CONV, 12U },
    { EXEC_STEP_CPU_OP, 2U },
    { EXEC_STEP_ACCEL_CONV, 13U },
    { EXEC_STEP_ACCEL_CONV, 14U },
    { EXEC_STEP_ACCEL_CONV, 15U },
    { EXEC_STEP_ACCEL_CONV, 16U },
    { EXEC_STEP_ACCEL_CONV, 17U },
    { EXEC_STEP_ACCEL_CONV, 18U },
    { EXEC_STEP_ACCEL_CONV, 19U },
    { EXEC_STEP_ACCEL_CONV, 20U },
    { EXEC_STEP_ACCEL_CONV, 21U },
    { EXEC_STEP_ACCEL_CONV, 22U },
    { EXEC_STEP_ACCEL_CONV, 23U },
    { EXEC_STEP_ACCEL_CONV, 24U },
    { EXEC_STEP_ACCEL_CONV, 25U }
};

static volatile bool s_squeezenet1_1_imagenet_irq_seen;
static uint8_t s_squeezenet1_1_imagenet_gap_row[SQUEEZENET1_1_IMAGENET_FINAL_ROW_BYTES + 1U];
static uint8_t s_squeezenet1_1_imagenet_cpu_channel_in[SQUEEZENET1_1_IMAGENET_CPU_IN_CHANNEL_BYTES + 1U];
static uint8_t s_squeezenet1_1_imagenet_cpu_channel_out[SQUEEZENET1_1_IMAGENET_CPU_OUT_CHANNEL_BYTES + 1U];
static uint8_t s_squeezenet1_1_imagenet_hyperram_rw_buf[SQUEEZENET1_1_IMAGENET_HRAM_RW_BUF_BYTES];
static int32_t s_squeezenet1_1_imagenet_logits[SQUEEZENET1_1_IMAGENET_FINAL_CHANNELS];

typedef struct {
    const char *name;
    uint16_t tensor;
    uint32_t addr;
    uint16_t height;
    uint16_t width;
    uint16_t channels;
    uint16_t row_stride;
    uint32_t logical_bytes;
    uint32_t crc32;
} Squeezenet11Imagenet_StaticTensorRef_t;

static const Squeezenet11Imagenet_StaticTensorRef_t s_squeezenet1_1_imagenet_static_tensor_refs[29U] = {
    { "Conv1", 54U, 0x00024C00U, 111U, 111U, 64U, 112U, 788544U, 0x615022CFU },
    { "MaxPool1", 55U, 0x000E7000U, 55U, 55U, 64U, 56U, 193600U, 0x50125961U },
    { "Conv2", 56U, 0x00117200U, 55U, 55U, 16U, 56U, 48400U, 0x94B0F792U },
    { "Conv3", 57U, 0x00183680U, 55U, 55U, 64U, 56U, 193600U, 0x893CB23BU },
    { "Conv4", 58U, 0x001B3880U, 55U, 55U, 64U, 56U, 193600U, 0xC4931835U },
    { "Conv5", 60U, 0x001E3A80U, 55U, 55U, 16U, 56U, 48400U, 0xA015B067U },
    { "Conv6", 61U, 0x0024FF00U, 55U, 55U, 64U, 56U, 193600U, 0x24CFDC0FU },
    { "Conv7", 62U, 0x00280100U, 55U, 55U, 64U, 56U, 193600U, 0x4C4780B1U },
    { "MaxPool2", 64U, 0x002B0300U, 27U, 27U, 128U, 28U, 93312U, 0x542EA217U },
    { "Conv8", 65U, 0x002C7D00U, 27U, 27U, 32U, 28U, 23328U, 0x25BC4ACFU },
    { "Conv9", 66U, 0x002FCF80U, 27U, 27U, 128U, 28U, 93312U, 0x96A3ABF3U },
    { "Conv10", 67U, 0x00314980U, 27U, 27U, 128U, 28U, 93312U, 0xB4886591U },
    { "Conv11", 69U, 0x0032C380U, 27U, 27U, 32U, 28U, 23328U, 0xC684B997U },
    { "Conv12", 70U, 0x00361600U, 27U, 27U, 128U, 28U, 93312U, 0xB2A939A8U },
    { "Conv13", 71U, 0x00379000U, 27U, 27U, 128U, 28U, 93312U, 0xDA11140BU },
    { "MaxPool3", 73U, 0x00390A00U, 13U, 13U, 256U, 14U, 43264U, 0x667BC60BU },
    { "Conv14", 74U, 0x0039C000U, 13U, 13U, 48U, 14U, 8112U, 0x59AE5501U },
    { "Conv15", 75U, 0x003AF320U, 13U, 13U, 192U, 14U, 32448U, 0x2D4BE946U },
    { "Conv16", 76U, 0x003B7BA0U, 13U, 13U, 192U, 14U, 32448U, 0x1CBF5D0CU },
    { "Conv17", 78U, 0x003C0420U, 13U, 13U, 48U, 14U, 8112U, 0x18923227U },
    { "Conv18", 79U, 0x003D3740U, 13U, 13U, 192U, 14U, 32448U, 0x91F13366U },
    { "Conv19", 80U, 0x003DBFC0U, 13U, 13U, 192U, 14U, 32448U, 0xA7EC6BC8U },
    { "Conv20", 82U, 0x003E4840U, 13U, 13U, 64U, 14U, 10816U, 0xD49E2D4FU },
    { "Conv21", 83U, 0x003FE1C0U, 13U, 13U, 256U, 14U, 43264U, 0xDFA9D3FCU },
    { "Conv22", 84U, 0x004097C0U, 13U, 13U, 256U, 14U, 43264U, 0x3998D68DU },
    { "Conv23", 86U, 0x00414DC0U, 13U, 13U, 64U, 14U, 10816U, 0x2FFA3CD7U },
    { "Conv24", 87U, 0x0042E740U, 13U, 13U, 256U, 14U, 43264U, 0x75C1786AU },
    { "Conv25", 88U, 0x00439D40U, 13U, 13U, 256U, 14U, 43264U, 0xDEE16D81U },
    { "Conv26", 90U, 0x00445340U, 13U, 13U, 1000U, 14U, 169000U, 0xB99B9161U }
};

static uint8_t s_squeezenet1_1_imagenet_static_flash_buf[SQUEEZENET1_1_IMAGENET_STATIC_FLASH_CHUNK_BYTES];
static volatile int32_t s_squeezenet1_1_imagenet_gap_sink;

static SQUEEZENET1_1_IMAGENET_SIZE_OPT void print_u32_dec(uint32_t value)
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

static SQUEEZENET1_1_IMAGENET_SIZE_OPT void print_i32_dec(int32_t value)
{
    uint32_t magnitude;

    if (value < 0) {
        Uart_write('-');
        magnitude = (uint32_t)(-(value + 1)) + 1U;
    } else {
        magnitude = (uint32_t)value;
    }

    print_u32_dec(magnitude);
}

static SQUEEZENET1_1_IMAGENET_SIZE_OPT tick_t ticks_elapsed(tick_t start, tick_t end)
{
    tick_t diff;

    diff.lower = end.lower - start.lower;
    diff.upper = (end.upper - start.upper) & COUNTER_MAX_UPPER;
    if (end.lower < start.lower) {
        diff.upper = (diff.upper - 1U) & COUNTER_MAX_UPPER;
    }

    return diff;
}

static SQUEEZENET1_1_IMAGENET_SIZE_OPT tick_t ticks_add(tick_t a, tick_t b)
{
    tick_t sum;

    sum.lower = a.lower + b.lower;
    sum.upper = (a.upper + b.upper) & COUNTER_MAX_UPPER;
    if (sum.lower < a.lower) {
        sum.upper = (sum.upper + 1U) & COUNTER_MAX_UPPER;
    }

    return sum;
}

static SQUEEZENET1_1_IMAGENET_SIZE_OPT uint32_t ticks_to_ms(tick_t ticks)
{
    uint32_t ms = ticks.upper * SQUEEZENET1_1_IMAGENET_LOWER_WRAP_MS + ticks.lower / CYCLES_PER_MS;
    uint32_t rem = ticks.upper * SQUEEZENET1_1_IMAGENET_LOWER_WRAP_REM + ticks.lower % CYCLES_PER_MS;

    ms += rem / CYCLES_PER_MS;
    return ms;
}

static SQUEEZENET1_1_IMAGENET_SIZE_OPT uint8_t tick_cycles_to_digits(tick_t ticks, uint8_t *digits, uint8_t max_digits)
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

static SQUEEZENET1_1_IMAGENET_SIZE_OPT void print_tick_cycles(tick_t ticks)
{
    uint8_t digits[20];
    uint8_t count = tick_cycles_to_digits(ticks, digits, sizeof(digits));

    while (count > 0U) {
        Uart_write((uint8_t)('0' + digits[--count]));
    }
}

static SQUEEZENET1_1_IMAGENET_SIZE_OPT void print_tick_metric(tick_t ticks)
{
    print_tick_cycles(ticks);
    Uart_print(" cycles (");
    print_u32_dec(ticks_to_ms(ticks));
    Uart_print(" ms)");
}

static SQUEEZENET1_1_IMAGENET_SIZE_OPT uint32_t ticks_to_u32_saturated(tick_t ticks)
{
    return (ticks.upper != 0U) ? 0xFFFFFFFFU : ticks.lower;
}

static SQUEEZENET1_1_IMAGENET_SIZE_OPT void print_cycles_per_unit(tick_t ticks, uint32_t units)
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

static SQUEEZENET1_1_IMAGENET_SIZE_OPT void print_hex_32(uint32_t value)
{
    static const char hex[] = "0123456789ABCDEF";

    for (int8_t shift = 28; shift >= 0; shift -= 4) {
        Uart_write((uint8_t)hex[(value >> (uint32_t)shift) & 0x0FU]);
    }
}

static SQUEEZENET1_1_IMAGENET_SIZE_OPT void copy_u8_no_libcall(uint8_t *dst,
                                                const uint8_t *src,
                                                uint32_t size)
{
    volatile uint8_t *vdst = (volatile uint8_t *)dst;
    const volatile uint8_t *vsrc = (const volatile uint8_t *)src;

    for (uint32_t i = 0U; i < size; i++) {
        vdst[i] = vsrc[i];
    }
}

static SQUEEZENET1_1_IMAGENET_SIZE_OPT uint32_t layer_ofwidth(const Squeezenet11Imagenet_Layer_t *layer)
{
    uint32_t padded = (uint32_t)layer->ifheight + ((uint32_t)layer->padding << 1U);
    uint32_t span = (padded >= layer->hf) ? (padded - (uint32_t)layer->hf) : 0U;

    return (span / (uint32_t)layer->stride) + 1U;
}

static SQUEEZENET1_1_IMAGENET_SIZE_OPT uint32_t layer_ofmap_bytes(const Squeezenet11Imagenet_Layer_t *layer)
{
    uint32_t ofwidth = layer_ofwidth(layer);

    return ofwidth * ofwidth * (uint32_t)layer->ofchannel;
}

static SQUEEZENET1_1_IMAGENET_SIZE_OPT uint32_t layer_ofmap_storage_bytes(const Squeezenet11Imagenet_Layer_t *layer)
{
    uint32_t ofwidth = layer_ofwidth(layer);

    return (uint32_t)layer->ofchannel * ofwidth * (uint32_t)layer->ofrow_stride;
}

static SQUEEZENET1_1_IMAGENET_SIZE_OPT uint32_t layer_macs(const Squeezenet11Imagenet_Layer_t *layer)
{
    return layer_ofmap_bytes(layer) *
           (uint32_t)layer->ifchannel *
           (uint32_t)layer->hf *
           (uint32_t)layer->hf;
}

static SQUEEZENET1_1_IMAGENET_SIZE_OPT uint32_t total_conv_macs(void)
{
    uint32_t total = 0U;

    for (uint32_t i = 0U; i < SQUEEZENET1_1_IMAGENET_LAYER_COUNT; i++) {
        total += layer_macs(&s_squeezenet1_1_imagenet_layers[i]);
    }

    return total;
}

static SQUEEZENET1_1_IMAGENET_SIZE_OPT void print_cnn_status(const char *prefix, uint32_t status)
{
    Uart_print(prefix);
    Uart_print(" STATUS=0x");
    print_hex_32(status);
    Uart_print(" busy=");
    Uart_write((status & CNN_ACCEL_STATUS_BUSY_Msk) != 0U ? '1' : '0');
    Uart_print(" done=");
    Uart_write((status & CNN_ACCEL_STATUS_DONE_Msk) != 0U ? '1' : '0');
    Uart_print(" table_rdy=");
    Uart_write((status & CNN_ACCEL_STATUS_TABLE_READY_Msk) != 0U ? '1' : '0');
    Uart_println("");
}

static SQUEEZENET1_1_IMAGENET_SIZE_OPT void print_hyperram_status(const char *name, HyperRAM_Driver_t *drv)
{
    uint32_t mode = HyperRAM_read_mode_register(drv);
    uint32_t status = *drv->reg_status;

    Uart_print("  ");
    Uart_print(name);
    Uart_print(" mode=0x");
    print_hex_32(mode);
    Uart_print(" status=0x");
    print_hex_32(status);
    Uart_println("");
}

static SQUEEZENET1_1_IMAGENET_SIZE_OPT bool wait_hyperram_master_idle(const char *name, HyperRAM_Driver_t *drv)
{
    uint32_t wait = SQUEEZENET1_1_IMAGENET_HRAM_DRAIN_WAIT_LIMIT;
    uint32_t stable = 0U;

    while (wait > 0U) {
        if (HyperRAM_is_start_ready(drv)) {
            stable++;
            if (stable >= SQUEEZENET1_1_IMAGENET_HRAM_DRAIN_STABLE_READS) {
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

static SQUEEZENET1_1_IMAGENET_SIZE_OPT bool wait_hyperram_start_ready(const char *name, HyperRAM_Driver_t *drv)
{
    uint32_t wait = SQUEEZENET1_1_IMAGENET_HRAM_CPU_WAIT_LIMIT;

    while (wait > 0U) {
        if (HyperRAM_is_start_ready(drv)) {
            return true;
        }
        wait--;
    }

    Uart_print("  ");
    Uart_print(name);
    Uart_println(" start-ready timeout.");
    print_hyperram_status(name, drv);
    return false;
}

static SQUEEZENET1_1_IMAGENET_SIZE_OPT bool hram_write_byte_checked(const char *name,
                                                     HyperRAM_Driver_t *drv,
                                                     uint8_t data)
{
    uint32_t wait = SQUEEZENET1_1_IMAGENET_HRAM_CPU_WAIT_LIMIT;

    while (HyperRAM_is_full(drv)) {
        if (wait == 0U) {
            Uart_print("  ");
            Uart_print(name);
            Uart_println(" write FIFO timeout.");
            print_hyperram_status(name, drv);
            return false;
        }
        wait--;
    }

    HyperRAM_write_byte(drv, data);
    return true;
}

static SQUEEZENET1_1_IMAGENET_SIZE_OPT bool hram_read_byte_checked(const char *name,
                                                    HyperRAM_Driver_t *drv,
                                                    uint8_t *data)
{
    uint32_t wait = SQUEEZENET1_1_IMAGENET_HRAM_CPU_WAIT_LIMIT;

    while (HyperRAM_is_empty(drv)) {
        if (wait == 0U) {
            Uart_print("  ");
            Uart_print(name);
            Uart_println(" read FIFO timeout.");
            print_hyperram_status(name, drv);
            return false;
        }
        wait--;
    }

    *data = HyperRAM_read_byte(drv);
    return true;
}

static SQUEEZENET1_1_IMAGENET_SIZE_OPT bool hram_burst_write_checked(const char *name,
                                                      HyperRAM_Driver_t *drv,
                                                      const uint8_t *src,
                                                      uint32_t size)
{
    for (uint32_t i = 0U; i < size; i++) {
        if (!hram_write_byte_checked(name, drv, src[i])) {
            return false;
        }
    }
    return true;
}

static SQUEEZENET1_1_IMAGENET_SIZE_OPT bool hram_burst_read_checked(const char *name,
                                                     HyperRAM_Driver_t *drv,
                                                     uint8_t *dst,
                                                     uint32_t size)
{
    for (uint32_t i = 0U; i < size; i++) {
        if (!hram_read_byte_checked(name, drv, &dst[i])) {
            return false;
        }
    }
    return true;
}

static SQUEEZENET1_1_IMAGENET_SIZE_OPT bool hram_read_aligned(W95_HandleTypeDef *w95,
                                               uint32_t addr,
                                               uint8_t *dst,
                                               uint32_t size)
{
    if (((addr & 1U) != 0U) || ((size & 1U) != 0U) || (size == 0U) || ((size / 2U) > 255U)) {
        return false;
    }

    HyperRAM_set_config(w95->hram_port,
                        w95->capture_shmoo,
                        w95->recovery,
                        w95->latency,
                        (uint8_t)(size / 2U));
    if (!wait_hyperram_start_ready("HRAM read", w95->hram_port)) {
        return false;
    }
    if (!W95_SetMemoryCommandAddress(w95->hram_port, addr, W95_CMD_MEM_READ_LINEAR)) {
        Uart_println("  HRAM read address setup failed.");
        return false;
    }
    HyperRAM_start(w95->hram_port);
    return hram_burst_read_checked("HRAM read", w95->hram_port, dst, size);
}

static SQUEEZENET1_1_IMAGENET_SIZE_OPT bool hram_write_aligned(W95_HandleTypeDef *w95,
                                                uint32_t addr,
                                                const uint8_t *src,
                                                uint32_t size)
{
    if (((addr & 1U) != 0U) || ((size & 1U) != 0U) || (size == 0U) || ((size / 2U) > 255U)) {
        return false;
    }

    HyperRAM_set_config(w95->hram_port,
                        w95->capture_shmoo,
                        w95->recovery,
                        w95->latency,
                        (uint8_t)(size / 2U));
    if (!wait_hyperram_start_ready("HRAM write", w95->hram_port)) {
        return false;
    }
    if (!W95_SetMemoryCommandAddress(w95->hram_port, addr, W95_CMD_MEM_WRITE_LINEAR)) {
        Uart_println("  HRAM write address setup failed.");
        return false;
    }
    if (!hram_burst_write_checked("HRAM write", w95->hram_port, src, size)) {
        return false;
    }
    HyperRAM_start(w95->hram_port);
    return true;
}

static SQUEEZENET1_1_IMAGENET_SIZE_OPT bool hram_read_any(W95_HandleTypeDef *w95,
                                           uint32_t addr,
                                           uint8_t *dst,
                                           uint32_t size)
{
    uint32_t offset = addr & 1U;
    uint32_t aligned_addr = addr & ~1U;
    uint32_t aligned_size = (offset + size + 1U) & ~1U;

    if ((size == 0U) || (aligned_size > SQUEEZENET1_1_IMAGENET_HRAM_RW_BUF_BYTES)) {
        return false;
    }

    if (!hram_read_aligned(w95, aligned_addr, s_squeezenet1_1_imagenet_hyperram_rw_buf, aligned_size)) {
        return false;
    }

    copy_u8_no_libcall(dst, &s_squeezenet1_1_imagenet_hyperram_rw_buf[offset], size);
    return true;
}

static SQUEEZENET1_1_IMAGENET_SIZE_OPT bool hram_write_any(W95_HandleTypeDef *w95,
                                            uint32_t addr,
                                            const uint8_t *src,
                                            uint32_t size)
{
    uint32_t offset = addr & 1U;
    uint32_t aligned_addr = addr & ~1U;
    uint32_t aligned_size = (offset + size + 1U) & ~1U;

    if ((size == 0U) || (aligned_size > SQUEEZENET1_1_IMAGENET_HRAM_RW_BUF_BYTES)) {
        return false;
    }

    if ((offset != 0U) || ((size & 1U) != 0U)) {
        if (!hram_read_aligned(w95, aligned_addr, s_squeezenet1_1_imagenet_hyperram_rw_buf, aligned_size)) {
            return false;
        }
    }

    copy_u8_no_libcall(&s_squeezenet1_1_imagenet_hyperram_rw_buf[offset], src, size);
    return hram_write_aligned(w95, aligned_addr, s_squeezenet1_1_imagenet_hyperram_rw_buf, aligned_size);
}

static SQUEEZENET1_1_IMAGENET_SIZE_OPT bool hram_read_block_any(W95_HandleTypeDef *w95,
                                                 uint32_t addr,
                                                 uint8_t *dst,
                                                 uint32_t size)
{
    uint32_t done = 0U;

    while (done < size) {
        uint32_t chunk = size - done;

        if (chunk > SQUEEZENET1_1_IMAGENET_HRAM_BLOCK_CHUNK_BYTES) {
            chunk = SQUEEZENET1_1_IMAGENET_HRAM_BLOCK_CHUNK_BYTES;
        }
        if (!hram_read_any(w95, addr + done, &dst[done], chunk)) {
            return false;
        }
        done += chunk;
    }

    return true;
}

static SQUEEZENET1_1_IMAGENET_SIZE_OPT bool hram_write_block_any(W95_HandleTypeDef *w95,
                                                  uint32_t addr,
                                                  const uint8_t *src,
                                                  uint32_t size)
{
    uint32_t done = 0U;

    while (done < size) {
        uint32_t chunk = size - done;

        if (chunk > SQUEEZENET1_1_IMAGENET_HRAM_BLOCK_CHUNK_BYTES) {
            chunk = SQUEEZENET1_1_IMAGENET_HRAM_BLOCK_CHUNK_BYTES;
        }
        if (!hram_write_any(w95, addr + done, &src[done], chunk)) {
            return false;
        }
        done += chunk;
    }

    return true;
}

static void squeezenet1_1_imagenet_irq_handler(uint32_t irq_bit, void *context)
{
    (void)irq_bit;
    (void)context;
    s_squeezenet1_1_imagenet_irq_seen = true;
}

static SQUEEZENET1_1_IMAGENET_SIZE_OPT void fill_layer_config(const Squeezenet11Imagenet_Layer_t *layer,
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

static SQUEEZENET1_1_IMAGENET_SIZE_OPT void print_layer_config(const Squeezenet11Imagenet_Layer_t *layer)
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
    Uart_print("      row stride if/of : ");
    print_u32_dec(layer->ifrow_stride);
    Uart_write('/');
    print_u32_dec(layer->ofrow_stride);
    Uart_println("");
}

static SQUEEZENET1_1_IMAGENET_SIZE_OPT bool run_layer(uint8_t idx,
                                       const Squeezenet11Imagenet_Layer_t *layer,
                                       bool verbose,
                                       tick_t *elapsed)
{
    CNN_Accel_LayerConfig_t config;
    tick_t start_tick;
    tick_t end_tick;
    uint32_t wait = SQUEEZENET1_1_IMAGENET_IRQ_WAIT_LIMIT;
    uint32_t status;
    bool done_seen = false;

    fill_layer_config(layer, &config);
    s_squeezenet1_1_imagenet_irq_seen = false;

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

    if (!CNN_Accel_submit_layer_config(&cnn_accel, &config, SQUEEZENET1_1_IMAGENET_SUBMIT_WAIT_LIMIT)) {
        print_cnn_status("    submit timeout:", CNN_Accel_get_status(&cnn_accel));
        return false;
    }

    CNN_Accel_start(&cnn_accel);

    while (wait > 0U) {
        status = CNN_Accel_get_status(&cnn_accel);
        if (s_squeezenet1_1_imagenet_irq_seen || ((status & CNN_ACCEL_STATUS_DONE_Msk) != 0U)) {
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

    if (!CNN_Accel_wait_idle(&cnn_accel, SQUEEZENET1_1_IMAGENET_SUBMIT_WAIT_LIMIT)) {
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

static SQUEEZENET1_1_IMAGENET_SIZE_OPT void print_layer_profile(const Squeezenet11Imagenet_Layer_t *layer, tick_t ticks)
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

static SQUEEZENET1_1_IMAGENET_SIZE_OPT uint32_t tensor_channel_bytes(const Squeezenet11Imagenet_TensorView_t *view)
{
    return (uint32_t)view->height * (uint32_t)view->row_stride;
}

static SQUEEZENET1_1_IMAGENET_SIZE_OPT void clear_u8_buffer(uint8_t *dst, uint32_t size)
{
    for (uint32_t i = 0U; i < size; i++) {
        dst[i] = 0U;
    }
}

static SQUEEZENET1_1_IMAGENET_SIZE_OPT int8_t clamp_i8(int32_t value, int8_t qmin, int8_t qmax)
{
    if (value < (int32_t)qmin) {
        return qmin;
    }
    if (value > (int32_t)qmax) {
        return qmax;
    }
    return (int8_t)value;
}

static SQUEEZENET1_1_IMAGENET_SIZE_OPT bool run_cpu_maxpool(W95_HandleTypeDef *w95_read,
                                             W95_HandleTypeDef *w95_write,
                                             const Squeezenet11Imagenet_CpuOp_t *op,
                                             bool verbose)
{
    const Squeezenet11Imagenet_TensorView_t *input = &op->inputs[0];
    const Squeezenet11Imagenet_TensorView_t *output = &op->output;
    uint32_t in_channel_bytes = tensor_channel_bytes(input);
    uint32_t out_channel_bytes = tensor_channel_bytes(output);

    if ((in_channel_bytes > SQUEEZENET1_1_IMAGENET_CPU_IN_CHANNEL_BYTES) ||
        (out_channel_bytes > SQUEEZENET1_1_IMAGENET_CPU_OUT_CHANNEL_BYTES)) {
        return false;
    }

    for (uint32_t c = 0U; c < input->channels; c++) {
        uint32_t in_ch_base = input->addr + c * in_channel_bytes;
        uint32_t out_ch_base = output->addr + c * out_channel_bytes;

        if (verbose && (SQUEEZENET1_1_IMAGENET_CPU_PROGRESS_LOG != 0U) &&
            (((c & 7U) == 0U) || ((c + 1U) == input->channels))) {
            Uart_print("    channel ");
            print_u32_dec(c + 1U);
            Uart_write('/');
            print_u32_dec(input->channels);
            Uart_println("");
        }

        if (!hram_read_block_any(w95_read, in_ch_base, s_squeezenet1_1_imagenet_cpu_channel_in, in_channel_bytes)) {
            Uart_print("    MaxPool HRAM read failed at channel ");
            print_u32_dec(c + 1U);
            Uart_println("");
            return false;
        }

        clear_u8_buffer(s_squeezenet1_1_imagenet_cpu_channel_out, out_channel_bytes);
        for (uint32_t oy = 0U; oy < output->height; oy++) {
            uint32_t out_row_base = oy * (uint32_t)output->row_stride;

            for (uint32_t ox = 0U; ox < output->width; ox++) {
                int8_t max_value = (int8_t)-128;
                bool seen = false;

                for (uint32_t ky = 0U; ky < op->filter_h; ky++) {
                    int32_t iy = (int32_t)(oy * (uint32_t)op->stride_h + ky) - (int32_t)op->pad_top;

                    if ((iy < 0) || ((uint32_t)iy >= input->height)) {
                        continue;
                    }

                    for (uint32_t kx = 0U; kx < op->filter_w; kx++) {
                        int32_t ix = (int32_t)(ox * (uint32_t)op->stride_w + kx) - (int32_t)op->pad_left;
                        int8_t value;

                        if ((ix < 0) || ((uint32_t)ix >= input->width)) {
                            continue;
                        }

                        value = (int8_t)s_squeezenet1_1_imagenet_cpu_channel_in[(uint32_t)iy * (uint32_t)input->row_stride + (uint32_t)ix];
                        if ((!seen) || (value > max_value)) {
                            max_value = value;
                            seen = true;
                        }
                    }
                }

                if (!seen) {
                    max_value = (int8_t)-128;
                }
                s_squeezenet1_1_imagenet_cpu_channel_out[out_row_base + ox] = (uint8_t)clamp_i8(max_value, op->qmin, op->qmax);
            }
        }

        if (!hram_write_block_any(w95_write, out_ch_base, s_squeezenet1_1_imagenet_cpu_channel_out, out_channel_bytes)) {
            Uart_print("    MaxPool HRAM write failed at channel ");
            print_u32_dec(c + 1U);
            Uart_println("");
            return false;
        }
    }

    return true;
}

static SQUEEZENET1_1_IMAGENET_SIZE_OPT bool run_cpu_concat(W95_HandleTypeDef *w95_read,
                                            W95_HandleTypeDef *w95_write,
                                            const Squeezenet11Imagenet_CpuOp_t *op,
                                            bool verbose)
{
    const Squeezenet11Imagenet_TensorView_t *output = &op->output;
    uint32_t out_channel_bytes = tensor_channel_bytes(output);
    uint32_t out_channel = 0U;

    if (out_channel_bytes > SQUEEZENET1_1_IMAGENET_CPU_OUT_CHANNEL_BYTES) {
        return false;
    }

    for (uint32_t input_idx = 0U; input_idx < op->input_count; input_idx++) {
        const Squeezenet11Imagenet_TensorView_t *input = &op->inputs[input_idx];
        uint32_t in_channel_bytes = tensor_channel_bytes(input);

        if (in_channel_bytes > SQUEEZENET1_1_IMAGENET_CPU_IN_CHANNEL_BYTES) {
            return false;
        }

        for (uint32_t c = 0U; c < input->channels; c++) {
            uint32_t in_ch_base = input->addr + c * in_channel_bytes;
            uint32_t out_ch_base = output->addr + out_channel * out_channel_bytes;

            if (verbose && (SQUEEZENET1_1_IMAGENET_CPU_PROGRESS_LOG != 0U) &&
                (((out_channel & 31U) == 0U) || ((out_channel + 1U) == output->channels))) {
                Uart_print("    concat channel ");
                print_u32_dec(out_channel + 1U);
                Uart_write('/');
                print_u32_dec(output->channels);
                Uart_println("");
            }

            if (!hram_read_block_any(w95_read, in_ch_base, s_squeezenet1_1_imagenet_cpu_channel_in, in_channel_bytes)) {
                Uart_print("    Concat HRAM read failed at channel ");
                print_u32_dec(out_channel + 1U);
                Uart_println("");
                return false;
            }

            if ((input->height == output->height) &&
                (input->width == output->width) &&
                (input->row_stride == output->row_stride)) {
                if (!hram_write_block_any(w95_write, out_ch_base, s_squeezenet1_1_imagenet_cpu_channel_in, in_channel_bytes)) {
                    Uart_print("    Concat HRAM write failed at channel ");
                    print_u32_dec(out_channel + 1U);
                    Uart_println("");
                    return false;
                }
            } else {
                clear_u8_buffer(s_squeezenet1_1_imagenet_cpu_channel_out, out_channel_bytes);
                for (uint32_t y = 0U; y < input->height && y < output->height; y++) {
                    copy_u8_no_libcall(&s_squeezenet1_1_imagenet_cpu_channel_out[y * (uint32_t)output->row_stride],
                                       &s_squeezenet1_1_imagenet_cpu_channel_in[y * (uint32_t)input->row_stride],
                                       (input->width < output->width) ? input->width : output->width);
                }
                if (!hram_write_block_any(w95_write, out_ch_base, s_squeezenet1_1_imagenet_cpu_channel_out, out_channel_bytes)) {
                    Uart_print("    Concat HRAM write failed at channel ");
                    print_u32_dec(out_channel + 1U);
                    Uart_println("");
                    return false;
                }
            }

            out_channel++;
        }
    }

    return out_channel == output->channels;
}

static SQUEEZENET1_1_IMAGENET_SIZE_OPT bool run_cpu_op(Squeezenet11Imagenet_RunContext_t *context,
                                        uint8_t idx,
                                        const Squeezenet11Imagenet_CpuOp_t *op,
                                        bool verbose,
                                        tick_t *elapsed)
{
    tick_t start_tick;
    tick_t end_tick;
    bool ok = false;

    if (verbose) {
        Uart_print("  CPU ");
        Uart_print(op->name);
        Uart_print(": ");
        print_u32_dec(op->output.height);
        Uart_write('x');
        print_u32_dec(op->output.width);
        Uart_write('x');
        print_u32_dec(op->output.channels);
        Uart_println("");
        (void)idx;
    }

    start_tick = read_tick();
    if (op->kind == CPU_OP_MAX_POOL_2D) {
        ok = run_cpu_maxpool(&context->w95_h1_read, &context->w95_h1_write, op, verbose);
    } else if (op->kind == CPU_OP_CONCATENATION) {
        ok = run_cpu_concat(&context->w95_h1_read, &context->w95_h1_write, op, verbose);
    }
    end_tick = read_tick();
    *elapsed = ticks_elapsed(start_tick, end_tick);

    if (verbose && ok) {
        Uart_println("    finished:");
        Uart_print("      Time         : ");
        print_tick_metric(*elapsed);
        Uart_println("");
        Uart_print("      Output bytes : ");
        print_u32_dec(tensor_channel_bytes(&op->output) * (uint32_t)op->output.channels);
        Uart_println("");
    }

    return ok;
}

static SQUEEZENET1_1_IMAGENET_SIZE_OPT bool run_global_avgpool(W95_HandleTypeDef *w95_read,
                                                const Squeezenet11Imagenet_Layer_t *layer,
                                                bool verbose,
                                                int32_t *logits_out,
                                                uint32_t logits_count,
                                                tick_t *elapsed)
{
    tick_t start_tick;
    tick_t end_tick;
    uint32_t h = layer_ofwidth(layer);
    uint32_t ch_bytes = h * h;
    uint32_t ch_stride = h * (uint32_t)layer->ofrow_stride;
    int32_t sink = 0;

    if (SQUEEZENET1_1_IMAGENET_HAS_FINAL_GAP == 0U) {
        elapsed->lower = 0U;
        elapsed->upper = 0U;
        return true;
    }
    if ((logits_out == 0) || (logits_count < (uint32_t)layer->ofchannel) || (h > SQUEEZENET1_1_IMAGENET_FINAL_ROW_BYTES)) {
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
        uint32_t ch_base = layer->ofbaddr + c * ch_stride;

        for (uint32_t y = 0U; y < h; y++) {
            if (!hram_read_block_any(w95_read,
                                     ch_base + y * (uint32_t)layer->ofrow_stride,
                                     s_squeezenet1_1_imagenet_gap_row,
                                     layer->ofrow_stride)) {
                return false;
            }
            for (uint32_t x = 0U; x < h; x++) {
                sum += (int32_t)(int8_t)s_squeezenet1_1_imagenet_gap_row[x] - (int32_t)layer->zpy;
            }
        }
        sum /= (int32_t)ch_bytes;
        logits_out[c] = sum;
        sink += sum;
    }

    s_squeezenet1_1_imagenet_gap_sink = sink;
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

static SQUEEZENET1_1_IMAGENET_SIZE_OPT bool begin_run_context(Squeezenet11Imagenet_RunContext_t *context)
{
    CNN_Accel_begin();
    HyperRAM_init(&hyperram0, HYPERRAM_0_BASE_ADDR);
    HyperRAM_init(&hyperram1, HYPERRAM_1_BASE_ADDR);
    HyperRAM_set_accel_mode(&hyperram0, false);
    HyperRAM_set_accel_mode(&hyperram1, false);
    W95_Init(&context->w95_h1_read,
             &hyperram1,
             WEIGHT_HYPERRAM1_READ_LATENCY,
             WEIGHT_HYPERRAM1_READ_RECOVERY,
             WEIGHT_HYPERRAM1_READ_CAPTURE_SHMOO);
    W95_Init(&context->w95_h1_write,
             &hyperram1,
             WEIGHT_HYPERRAM1_WRITE_LATENCY,
             WEIGHT_HYPERRAM1_WRITE_RECOVERY,
             WEIGHT_HYPERRAM1_WRITE_CAPTURE_SHMOO);


    if (!CNN_Accel_attach_irq(squeezenet1_1_imagenet_irq_handler, 0, IRQ_PRIORITY_DEFAULT)) {
        Uart_println("  CNN IRQ attach failed.");
        return false;
    }

    CNN_Accel_enable_irq();
    HyperRAM_set_dmac_weights(&hyperram0, SQUEEZENET1_1_IMAGENET_DMAC_WRITE_WEIGHT, SQUEEZENET1_1_IMAGENET_DMAC_READ_WEIGHT);
    HyperRAM_set_dmac_weights(&hyperram1, SQUEEZENET1_1_IMAGENET_DMAC_WRITE_WEIGHT, SQUEEZENET1_1_IMAGENET_DMAC_READ_WEIGHT);
    return true;
}

static SQUEEZENET1_1_IMAGENET_SIZE_OPT void end_run_context(void)
{
    CNN_Accel_disable_irq();
    HyperRAM_set_accel_mode(&hyperram0, false);
    HyperRAM_set_accel_mode(&hyperram1, false);

}

static SQUEEZENET1_1_IMAGENET_SIZE_OPT bool run_model_once(Squeezenet11Imagenet_RunContext_t *context,
                                            bool verbose,

                                            int32_t *logits_out,
                                            uint32_t logits_count,
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

    for (uint16_t step_idx = 0U; ok && (step_idx < SQUEEZENET1_1_IMAGENET_EXEC_STEP_COUNT); step_idx++) {
        const Squeezenet11Imagenet_ExecStep_t *step = &s_squeezenet1_1_imagenet_exec_steps[step_idx];
        tick_t elapsed;

        if (step->kind == EXEC_STEP_ACCEL_CONV) {
            uint8_t layer_idx = (uint8_t)step->index;

            HyperRAM_set_accel_mode(&hyperram0, true);
            HyperRAM_set_accel_mode(&hyperram1, true);

            ok = run_layer(layer_idx, &s_squeezenet1_1_imagenet_layers[layer_idx], verbose, &elapsed);

            HyperRAM_set_accel_mode(&hyperram0, false);
            HyperRAM_set_accel_mode(&hyperram1, false);
            if (ok) {
                *conv_ticks = ticks_add(*conv_ticks, elapsed);
                if (verbose) {
                    print_layer_profile(&s_squeezenet1_1_imagenet_layers[layer_idx], elapsed);
                }
            }
        } else if (step->kind == EXEC_STEP_CPU_OP) {
            uint8_t cpu_idx = (uint8_t)step->index;

            HyperRAM_set_accel_mode(&hyperram0, false);
            HyperRAM_set_accel_mode(&hyperram1, false);
            ok = run_cpu_op(context, cpu_idx, &s_squeezenet1_1_imagenet_cpu_ops[cpu_idx], verbose, &elapsed);
            if (ok) {
                *cpu_ticks = ticks_add(*cpu_ticks, elapsed);
            } else {
                Uart_println("    CPU fallback op failed.");
            }
        }
    }

    if (ok) {
        tick_t elapsed;

        ok = run_global_avgpool(&context->w95_h1_read,
                                &s_squeezenet1_1_imagenet_layers[SQUEEZENET1_1_IMAGENET_LAYER_COUNT - 1U],
                                verbose,
                                logits_out,
                                logits_count,
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

bool Squeezenet11Imagenet_Accel_RunTimingOnly(void)
{
    bool ok;
    Squeezenet11Imagenet_RunContext_t context;
    tick_t conv_ticks = {0U, 0U};
    tick_t cpu_ticks = {0U, 0U};
    tick_t wall_ticks = {0U, 0U};
    tick_t measured_ticks;
    uint32_t conv_macs = total_conv_macs();
    int32_t *logits = s_squeezenet1_1_imagenet_logits;

    Uart_println("");
    Uart_println("=== Run Squeezenet11Imagenet accelerator timing ===");
    Uart_println("Prepared-input path: load IFMAP in HyperRAM1 and packed params in HyperRAM0 before running.");
    Uart_print("  Conv layers              : ");
    print_u32_dec(SQUEEZENET1_1_IMAGENET_LAYER_COUNT);
    Uart_println("");
    Uart_print("  HR0 filter/bias reserved : ");
    print_u32_dec(SQUEEZENET1_1_IMAGENET_PARAM_BYTES_RESERVED);
    Uart_println(" bytes");
    Uart_print("  HR1 activation reserved  : ");
    print_u32_dec(SQUEEZENET1_1_IMAGENET_ACTIVATION_BYTES_RESERVED);
    Uart_println(" bytes");
    Uart_print("  Conv workload            : ");
    print_u32_dec(conv_macs);
    Uart_println(" MACs");

    ok = begin_run_context(&context);
    if (ok) {
        ok = run_model_once(&context,
                            true,
                            
                            (SQUEEZENET1_1_IMAGENET_HAS_FINAL_GAP != 0U) ? logits : 0,
                            SQUEEZENET1_1_IMAGENET_FINAL_CHANNELS,
                            &conv_ticks,
                            &cpu_ticks,
                            &wall_ticks);
    }

    if (ok) {
        measured_ticks = ticks_add(conv_ticks, cpu_ticks);
        Uart_println("");
        Uart_println("Squeezenet11Imagenet timing summary:");
        Uart_print("  Accelerator conv layers : ");
        print_tick_metric(conv_ticks);
        Uart_println("");
        Uart_print("  Conv average cost       : ");
        print_cycles_per_unit(conv_ticks, conv_macs / 1000U);
        Uart_println(" cycles / 1000 MACs");
        Uart_print("  CPU fallback/post       : ");
        print_tick_metric(cpu_ticks);
        Uart_println("");
        Uart_print("  Full measured pipeline  : ");
        print_tick_metric(measured_ticks);
        Uart_println("");
        Uart_print("  Wall section            : ");
        print_tick_metric(wall_ticks);
        Uart_println("  (includes UART/log overhead)");
    }

    end_run_context();

    Uart_println(ok ? "Squeezenet11Imagenet timing -> DONE" : "Squeezenet11Imagenet timing -> FAIL");
    return ok;
}




static SQUEEZENET1_1_IMAGENET_SIZE_OPT uint32_t argmax_i32(const int32_t *values, uint32_t count)
{
    uint32_t best = 0U;

    for (uint32_t i = 1U; i < count; i++) {
        if (values[i] > values[best]) {
            best = i;
        }
    }

    return best;
}

static SQUEEZENET1_1_IMAGENET_SIZE_OPT void print_static_top5(const int32_t *logits, uint32_t count)
{
    uint32_t selected[5] = {0U, 0U, 0U, 0U, 0U};
    uint32_t selected_count = 0U;

    for (uint32_t rank = 0U; (rank < 5U) && (rank < count); rank++) {
        uint32_t best = 0U;
        bool best_valid = false;

        for (uint32_t i = 0U; i < count; i++) {
            bool used = false;

            for (uint32_t j = 0U; j < selected_count; j++) {
                if (selected[j] == i) {
                    used = true;
                    break;
                }
            }
            if (used) {
                continue;
            }
            if ((!best_valid) || (logits[i] > logits[best])) {
                best = i;
                best_valid = true;
            }
        }

        if (!best_valid) {
            break;
        }
        selected[selected_count++] = best;
        if (rank != 0U) {
            Uart_print(", ");
        }
        print_u32_dec(best);
        Uart_write(':');
        print_i32_dec(logits[best]);
    }
}

static SQUEEZENET1_1_IMAGENET_SIZE_OPT bool load_static_input_from_flash(Squeezenet11Imagenet_RunContext_t *context)
{
    uint32_t crc;
    uint32_t copied = 0U;
    uint32_t next_progress = 0U;

    Uart_println("  Static input: checking flash CRC...");
    crc = flash_crc32(SQUEEZENET1_1_IMAGENET_STATIC_INPUT_FLASH_OFFSET, SQUEEZENET1_1_IMAGENET_STATIC_INPUT_BYTES);
    if (crc != SQUEEZENET1_1_IMAGENET_STATIC_INPUT_CRC32) {
        Uart_print("Static input CRC mismatch flash=0x");
        print_hex_32(crc);
        Uart_print(" expected=0x");
        print_hex_32(SQUEEZENET1_1_IMAGENET_STATIC_INPUT_CRC32);
        Uart_println("");
        return false;
    }
    Uart_println("  Static input: CRC OK.");
    Uart_println("  Static input: copying flash -> HRAM1...");

    while (copied < SQUEEZENET1_1_IMAGENET_STATIC_INPUT_BYTES) {
        uint32_t chunk = SQUEEZENET1_1_IMAGENET_STATIC_INPUT_BYTES - copied;

        if (chunk > SQUEEZENET1_1_IMAGENET_STATIC_FLASH_CHUNK_BYTES) {
            chunk = SQUEEZENET1_1_IMAGENET_STATIC_FLASH_CHUNK_BYTES;
        }
        flash_read_data(SQUEEZENET1_1_IMAGENET_STATIC_INPUT_FLASH_OFFSET + copied,
                        s_squeezenet1_1_imagenet_static_flash_buf,
                        chunk);
        if (!hram_write_block_any(&context->w95_h1_write,
                                  SQUEEZENET1_1_IMAGENET_INPUT_IFMAP_ADDR + copied,
                                  s_squeezenet1_1_imagenet_static_flash_buf,
                                  chunk)) {
            Uart_println("Static input HRAM1 write failed.");
            return false;
        }
        copied += chunk;
        if (copied >= next_progress) {
            Uart_print("    copied ");
            print_u32_dec(copied);
            Uart_print("/");
            print_u32_dec(SQUEEZENET1_1_IMAGENET_STATIC_INPUT_BYTES);
            Uart_println(" bytes");
            next_progress += 32768U;
        }
    }

    Uart_println("  Static input: copy complete.");
    return true;
}

static SQUEEZENET1_1_IMAGENET_SIZE_OPT uint32_t static_crc32_update(uint32_t crc, uint8_t byte)
{
    crc ^= byte;
    for (uint8_t bit = 0U; bit < 8U; bit++) {
        crc = (crc >> 1) ^ ((uint32_t)(-((int32_t)(crc & 1U))) & 0xEDB88320U);
    }
    return crc;
}

static SQUEEZENET1_1_IMAGENET_SIZE_OPT bool static_tensor_crc32(W95_HandleTypeDef *w95_read,
                                                 const Squeezenet11Imagenet_StaticTensorRef_t *ref,
                                                 uint32_t *crc32_out)
{
    uint32_t crc = 0xFFFFFFFFU;

    if ((ref == 0) || (crc32_out == 0) || (ref->row_stride > SQUEEZENET1_1_IMAGENET_HRAM_RW_BUF_BYTES)) {
        return false;
    }

    for (uint32_t c = 0U; c < ref->channels; c++) {
        uint32_t ch_base = ref->addr + c * (uint32_t)ref->height * (uint32_t)ref->row_stride;

        for (uint32_t y = 0U; y < ref->height; y++) {
            if (!hram_read_block_any(w95_read,
                                     ch_base + y * (uint32_t)ref->row_stride,
                                     s_squeezenet1_1_imagenet_hyperram_rw_buf,
                                     ref->row_stride)) {
                return false;
            }
            for (uint32_t x = 0U; x < ref->width; x++) {
                crc = static_crc32_update(crc, s_squeezenet1_1_imagenet_hyperram_rw_buf[x]);
            }
        }
    }

    *crc32_out = ~crc;
    return true;
}

static SQUEEZENET1_1_IMAGENET_SIZE_OPT bool static_tensor_channel_crc32(W95_HandleTypeDef *w95_read,
                                                         const Squeezenet11Imagenet_StaticTensorRef_t *ref,
                                                         uint32_t channel,
                                                         uint32_t *crc32_out)
{
    uint32_t crc = 0xFFFFFFFFU;

    if ((ref == 0) ||
        (crc32_out == 0) ||
        (channel >= ref->channels) ||
        (ref->row_stride > SQUEEZENET1_1_IMAGENET_HRAM_RW_BUF_BYTES)) {
        return false;
    }

    uint32_t ch_base = ref->addr + channel * (uint32_t)ref->height * (uint32_t)ref->row_stride;

    for (uint32_t y = 0U; y < ref->height; y++) {
        if (!hram_read_block_any(w95_read,
                                 ch_base + y * (uint32_t)ref->row_stride,
                                 s_squeezenet1_1_imagenet_hyperram_rw_buf,
                                 ref->row_stride)) {
            return false;
        }
        for (uint32_t x = 0U; x < ref->width; x++) {
            crc = static_crc32_update(crc, s_squeezenet1_1_imagenet_hyperram_rw_buf[x]);
        }
    }

    *crc32_out = ~crc;
    return true;
}

static SQUEEZENET1_1_IMAGENET_SIZE_OPT bool check_static_intermediate_refs(Squeezenet11Imagenet_RunContext_t *context)
{
    if (SQUEEZENET1_1_IMAGENET_STATIC_TENSOR_REF_COUNT == 0U) {
        Uart_println("STATIC_INTERMEDIATE no golden refs");
        return true;
    }

    Uart_println("STATIC_INTERMEDIATE checking CRCs...");
    for (uint32_t i = 0U; i < SQUEEZENET1_1_IMAGENET_STATIC_TENSOR_REF_COUNT; i++) {
        const Squeezenet11Imagenet_StaticTensorRef_t *ref = &s_squeezenet1_1_imagenet_static_tensor_refs[i];
        uint32_t crc = 0U;

        if (!static_tensor_crc32(&context->w95_h1_read, ref, &crc)) {
            Uart_print("STATIC_INTERMEDIATE read_fail name=");
            Uart_print(ref->name);
            Uart_print(" tensor=");
            print_u32_dec(ref->tensor);
            Uart_println("");
            return false;
        }

        if (crc != ref->crc32) {
            Uart_print("STATIC_INTERMEDIATE first_mismatch name=");
            Uart_print(ref->name);
            Uart_print(" tensor=");
            print_u32_dec(ref->tensor);
            Uart_print(" addr=0x");
            print_hex_32(ref->addr);
            Uart_print(" bytes=");
            print_u32_dec(ref->logical_bytes);
            Uart_print(" crc=0x");
            print_hex_32(crc);
            Uart_print(" expected=0x");
            print_hex_32(ref->crc32);
            Uart_println("");
            Uart_println("STATIC_INTERMEDIATE channel CRC dump:");
            uint32_t dump_channels = ref->channels;
            if (dump_channels > 64U) {
                dump_channels = 64U;
            }
            for (uint32_t ch = 0U; ch < dump_channels; ch++) {
                uint32_t ch_crc = 0U;
                Uart_print("  ch=");
                print_u32_dec(ch);
                Uart_print(" crc=0x");
                if (static_tensor_channel_crc32(&context->w95_h1_read, ref, ch, &ch_crc)) {
                    print_hex_32(ch_crc);
                } else {
                    Uart_print("READ_FAIL");
                }
                Uart_println("");
            }
            if (ref->channels > dump_channels) {
                Uart_print("  ... truncated at ");
                print_u32_dec(dump_channels);
                Uart_print("/");
                print_u32_dec(ref->channels);
                Uart_println(" channels");
            }
            return false;
        }
    }

    Uart_println("STATIC_INTERMEDIATE all CRCs PASS");
    return true;
}

static SQUEEZENET1_1_IMAGENET_SIZE_OPT void print_static_result(const int32_t *logits, uint32_t count)
{
    uint32_t predicted = argmax_i32(logits, count);

    Uart_print("STATIC_RESULT class=");
    print_u32_dec(predicted);
    Uart_print(" value=");
    print_i32_dec(logits[predicted]);
    Uart_print(" expected=");
    if (SQUEEZENET1_1_IMAGENET_STATIC_GOLDEN_TOP1 == 0xFFFFFFFFU) {
        Uart_print("n/a");
    } else {
        print_u32_dec(SQUEEZENET1_1_IMAGENET_STATIC_GOLDEN_TOP1);
        Uart_print(" expected_value=");
        print_i32_dec(SQUEEZENET1_1_IMAGENET_STATIC_GOLDEN_VALUE);
        Uart_print((predicted == SQUEEZENET1_1_IMAGENET_STATIC_GOLDEN_TOP1) ? " PASS" : " FAIL");
    }
    Uart_println("");
    Uart_print("STATIC_TOP5 ");
    print_static_top5(logits, count);
    Uart_println("");
}

bool Squeezenet11Imagenet_Accel_RunStaticImageFromFlash(void)
{
    bool ok;
    Squeezenet11Imagenet_RunContext_t context;
    tick_t conv_ticks = {0U, 0U};
    tick_t cpu_ticks = {0U, 0U};
    tick_t wall_ticks = {0U, 0U};
    int32_t *logits = s_squeezenet1_1_imagenet_logits;

    Uart_println("");
    Uart_println("=== Run Squeezenet11Imagenet static image from flash ===");
    Uart_print("  Static input flash : 0x");
    print_hex_32(SQUEEZENET1_1_IMAGENET_STATIC_INPUT_FLASH_OFFSET);
    Uart_print(", ");
    print_u32_dec(SQUEEZENET1_1_IMAGENET_STATIC_INPUT_BYTES);
    Uart_println(" bytes");
    Uart_print("  Input HRAM1 addr   : ");
    print_u32_dec(SQUEEZENET1_1_IMAGENET_INPUT_IFMAP_ADDR);
    Uart_println("");

    Uart_println("  Begin run context...");
    ok = begin_run_context(&context);
    Uart_println(ok ? "  Run context OK." : "  Run context failed.");
    if (ok) {
        ok = load_static_input_from_flash(&context);
    }
    if (ok) {
        Uart_println("  Running model...");
        ok = run_model_once(&context,
                            false,
                            
                            logits,
                            SQUEEZENET1_1_IMAGENET_FINAL_CHANNELS,
                            &conv_ticks,
                            &cpu_ticks,
                            &wall_ticks);
    }

    if (ok) {
        print_static_result(logits, SQUEEZENET1_1_IMAGENET_FINAL_CHANNELS);
        (void)check_static_intermediate_refs(&context);
        Uart_print("  Conv ticks         : ");
        print_tick_metric(conv_ticks);
        Uart_println("");
        Uart_print("  CPU fallback ticks : ");
        print_tick_metric(cpu_ticks);
        Uart_println("");
        Uart_print("  Wall ticks         : ");
        print_tick_metric(wall_ticks);
        Uart_println("");
    }

    end_run_context();

    Uart_println(ok ? "Squeezenet11Imagenet static image -> DONE" : "Squeezenet11Imagenet static image -> FAIL");
    return ok;
}


bool Squeezenet11Imagenet_Accel_RunPreparedInput(int32_t *logits_out, uint32_t logits_count)
{
    bool ok;
    Squeezenet11Imagenet_RunContext_t context;
    tick_t conv_ticks;
    tick_t cpu_ticks;
    tick_t wall_ticks;

    ok = begin_run_context(&context);
    if (ok) {
        ok = run_model_once(&context,
                            false,
                            
                            logits_out,
                            logits_count,
                            &conv_ticks,
                            &cpu_ticks,
                            &wall_ticks);
    }

    end_run_context();
    return ok;
}

uint32_t Squeezenet11Imagenet_Accel_FinalOfmapAddr(void)
{
    return s_squeezenet1_1_imagenet_layers[SQUEEZENET1_1_IMAGENET_LAYER_COUNT - 1U].ofbaddr;
}

uint32_t Squeezenet11Imagenet_Accel_FinalOfmapBytes(void)
{
    return layer_ofmap_storage_bytes(&s_squeezenet1_1_imagenet_layers[SQUEEZENET1_1_IMAGENET_LAYER_COUNT - 1U]);
}
