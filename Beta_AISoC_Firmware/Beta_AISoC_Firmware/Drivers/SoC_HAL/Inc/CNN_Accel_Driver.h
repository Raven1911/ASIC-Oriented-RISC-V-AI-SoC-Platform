#ifndef CNN_ACCEL_DRIVER_H
#define CNN_ACCEL_DRIVER_H

#include <soc_hal.h>
#include <stdint.h>
#include <stdbool.h>

#define CNN_ACCEL_BASE_ADDR 0x02009000U

#define CNN_ACCEL_START_WORD_OFFSET             0x00U
#define CNN_ACCEL_STATUS_WORD_OFFSET            0x01U
#define CNN_ACCEL_IFHEIGHT_WORD_OFFSET          0x02U
#define CNN_ACCEL_IFCHANNEL_WORD_OFFSET         0x03U
#define CNN_ACCEL_OFCHANNEL_WORD_OFFSET         0x04U
#define CNN_ACCEL_HF_WORD_OFFSET                0x05U
#define CNN_ACCEL_STRIDE_WORD_OFFSET            0x06U
#define CNN_ACCEL_PADDING_WORD_OFFSET           0x07U
#define CNN_ACCEL_IFPARR_WORD_OFFSET            0x08U
#define CNN_ACCEL_OFTILE_WORD_OFFSET            0x09U
#define CNN_ACCEL_OFPARR_WORD_OFFSET            0x0AU
#define CNN_ACCEL_IFBADDR_WORD_OFFSET           0x0BU
#define CNN_ACCEL_FLTBADDR_WORD_OFFSET          0x0CU
#define CNN_ACCEL_BIAS_BADDR_WORD_OFFSET        0x0DU
#define CNN_ACCEL_OFBADDR_WORD_OFFSET           0x0EU
#define CNN_ACCEL_IFC_ZP_WORD_OFFSET            0x0FU
#define CNN_ACCEL_FLTC_ZP_WORD_OFFSET           0x10U
#define CNN_ACCEL_MULT_WORD_OFFSET              0x11U
#define CNN_ACCEL_MULT_SHIFT_WORD_OFFSET        0x12U
#define CNN_ACCEL_ALPHAMULT_WORD_OFFSET         0x13U
#define CNN_ACCEL_ALPHAMULT_SHIFT_WORD_OFFSET   0x14U
#define CNN_ACCEL_ZPY_WORD_OFFSET               0x15U
#define CNN_ACCEL_QMIN_WORD_OFFSET              0x16U
#define CNN_ACCEL_QMAX_WORD_OFFSET              0x17U
#define CNN_ACCEL_IS_LEAKY_RELU_WORD_OFFSET     0x18U
#define CNN_ACCEL_WRITE_FIFO_WORD_OFFSET        0x19U

#define CNN_ACCEL_STATUS_TABLE_VALID_Pos 0U
#define CNN_ACCEL_STATUS_TABLE_VALID_Msk (0x1U << CNN_ACCEL_STATUS_TABLE_VALID_Pos)
#define CNN_ACCEL_STATUS_TABLE_READY_Pos 1U
#define CNN_ACCEL_STATUS_TABLE_READY_Msk (0x1U << CNN_ACCEL_STATUS_TABLE_READY_Pos)
#define CNN_ACCEL_STATUS_BUSY_Pos        2U
#define CNN_ACCEL_STATUS_BUSY_Msk        (0x1U << CNN_ACCEL_STATUS_BUSY_Pos)
#define CNN_ACCEL_STATUS_DONE_Pos        3U
#define CNN_ACCEL_STATUS_DONE_Msk        (0x1U << CNN_ACCEL_STATUS_DONE_Pos)
#define CNN_ACCEL_STATUS_START_Pos       4U
#define CNN_ACCEL_STATUS_START_Msk       (0x1U << CNN_ACCEL_STATUS_START_Pos)

#ifdef IRQ_EXTERNAL0_BIT
#define CNN_ACCEL_IRQ_BIT IRQ_EXTERNAL0_BIT
#else
#define CNN_ACCEL_IRQ_BIT 3U
#endif
#define CNN_ACCEL_TIMEOUT_FOREVER 0xFFFFFFFFU

typedef struct {
    volatile uint32_t *base_ptr;
} CNN_Accel_Driver_t;

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
    int32_t  alphamult;
    uint8_t  alphamult_shift;
    int8_t   zpy;
    int8_t   qmin;
    int8_t   qmax;
    bool     is_leaky_relu;
} CNN_Accel_LayerConfig_t;

extern CNN_Accel_Driver_t cnn_accel;

void CNN_Accel_init(CNN_Accel_Driver_t *drv, uint32_t base_addr);
void CNN_Accel_begin(void);

void CNN_Accel_write_reg(CNN_Accel_Driver_t *drv, uint32_t word_offset, uint32_t value);
uint32_t CNN_Accel_read_reg(CNN_Accel_Driver_t *drv, uint32_t word_offset);
uint32_t CNN_Accel_get_status(CNN_Accel_Driver_t *drv);

bool CNN_Accel_is_table_valid(CNN_Accel_Driver_t *drv);
bool CNN_Accel_is_table_ready(CNN_Accel_Driver_t *drv);
bool CNN_Accel_is_busy(CNN_Accel_Driver_t *drv);
bool CNN_Accel_is_done(CNN_Accel_Driver_t *drv);

void CNN_Accel_load_layer_config(CNN_Accel_Driver_t *drv, const CNN_Accel_LayerConfig_t *config);
void CNN_Accel_commit_layer_config(CNN_Accel_Driver_t *drv);
bool CNN_Accel_submit_layer_config(CNN_Accel_Driver_t *drv, const CNN_Accel_LayerConfig_t *config, uint32_t timeout);

void CNN_Accel_start(CNN_Accel_Driver_t *drv);
bool CNN_Accel_wait_table_ready(CNN_Accel_Driver_t *drv, uint32_t timeout);
bool CNN_Accel_wait_layer_accepted(CNN_Accel_Driver_t *drv, uint32_t timeout);
bool CNN_Accel_wait_done(CNN_Accel_Driver_t *drv, uint32_t timeout);
bool CNN_Accel_wait_idle(CNN_Accel_Driver_t *drv, uint32_t timeout);

#ifdef HAL_INTERRUPT_MODULE_ENABLED
bool CNN_Accel_attach_irq(IRQ_Handler_t handler, void *context, uint8_t priority);
void CNN_Accel_enable_irq(void);
void CNN_Accel_disable_irq(void);
#endif

#endif // CNN_ACCEL_DRIVER_H
