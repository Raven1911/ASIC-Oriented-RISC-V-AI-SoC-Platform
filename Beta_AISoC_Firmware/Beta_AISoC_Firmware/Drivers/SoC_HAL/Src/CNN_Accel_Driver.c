#include "CNN_Accel_Driver.h"

#ifdef HAL_CNN_ACCEL_MODULE_ENABLED

CNN_Accel_Driver_t cnn_accel;

static bool CNN_Accel_wait_status(CNN_Accel_Driver_t *drv, uint32_t mask, bool set, uint32_t timeout)
{
    while (((CNN_Accel_get_status(drv) & mask) != 0U) != set) {
        if (timeout != CNN_ACCEL_TIMEOUT_FOREVER) {
            if (timeout == 0U) {
                return false;
            }
            timeout--;
        }
    }

    return true;
}

void CNN_Accel_init(CNN_Accel_Driver_t *drv, uint32_t base_addr)
{
    drv->base_ptr = (volatile uint32_t *)base_addr;
}

void CNN_Accel_begin(void)
{
    CNN_Accel_init(&cnn_accel, CNN_ACCEL_BASE_ADDR);
}

void CNN_Accel_write_reg(CNN_Accel_Driver_t *drv, uint32_t word_offset, uint32_t value)
{
    drv->base_ptr[word_offset] = value;
}

uint32_t CNN_Accel_read_reg(CNN_Accel_Driver_t *drv, uint32_t word_offset)
{
    return drv->base_ptr[word_offset];
}

uint32_t CNN_Accel_get_status(CNN_Accel_Driver_t *drv)
{
    return CNN_Accel_read_reg(drv, CNN_ACCEL_STATUS_WORD_OFFSET);
}

bool CNN_Accel_is_table_valid(CNN_Accel_Driver_t *drv)
{
    return (CNN_Accel_get_status(drv) & CNN_ACCEL_STATUS_TABLE_VALID_Msk) != 0U;
}

bool CNN_Accel_is_table_ready(CNN_Accel_Driver_t *drv)
{
    return (CNN_Accel_get_status(drv) & CNN_ACCEL_STATUS_TABLE_READY_Msk) != 0U;
}

bool CNN_Accel_is_busy(CNN_Accel_Driver_t *drv)
{
    return (CNN_Accel_get_status(drv) & CNN_ACCEL_STATUS_BUSY_Msk) != 0U;
}

bool CNN_Accel_is_done(CNN_Accel_Driver_t *drv)
{
    return (CNN_Accel_get_status(drv) & CNN_ACCEL_STATUS_DONE_Msk) != 0U;
}

void CNN_Accel_load_layer_config(CNN_Accel_Driver_t *drv, const CNN_Accel_LayerConfig_t *config)
{
    if (config == 0) {
        return;
    }

    CNN_Accel_write_reg(drv, CNN_ACCEL_IFHEIGHT_WORD_OFFSET,        (uint32_t)config->ifheight);
    CNN_Accel_write_reg(drv, CNN_ACCEL_IFCHANNEL_WORD_OFFSET,       (uint32_t)(config->ifchannel & 0x7FFU));
    CNN_Accel_write_reg(drv, CNN_ACCEL_OFCHANNEL_WORD_OFFSET,       (uint32_t)(config->ofchannel & 0x7FFU));
    CNN_Accel_write_reg(drv, CNN_ACCEL_HF_WORD_OFFSET,              (uint32_t)(config->hf & 0x0FU));
    CNN_Accel_write_reg(drv, CNN_ACCEL_STRIDE_WORD_OFFSET,          (uint32_t)(config->stride & 0x07U));
    CNN_Accel_write_reg(drv, CNN_ACCEL_PADDING_WORD_OFFSET,         (uint32_t)(config->padding & 0x03U));
    CNN_Accel_write_reg(drv, CNN_ACCEL_IFPARR_WORD_OFFSET,          (uint32_t)(config->ifparr & 0x07U));
    CNN_Accel_write_reg(drv, CNN_ACCEL_OFTILE_WORD_OFFSET,          (uint32_t)(config->oftile & 0x03U));
    CNN_Accel_write_reg(drv, CNN_ACCEL_OFPARR_WORD_OFFSET,          (uint32_t)(config->ofparr & 0x1FU));
    CNN_Accel_write_reg(drv, CNN_ACCEL_IFBADDR_WORD_OFFSET,         config->ifbaddr & 0x00FFFFFFU);
    CNN_Accel_write_reg(drv, CNN_ACCEL_FLTBADDR_WORD_OFFSET,        config->fltbaddr & 0x00FFFFFFU);
    CNN_Accel_write_reg(drv, CNN_ACCEL_BIAS_BADDR_WORD_OFFSET,      config->bias_baddr & 0x00FFFFFFU);
    CNN_Accel_write_reg(drv, CNN_ACCEL_OFBADDR_WORD_OFFSET,         config->ofbaddr & 0x00FFFFFFU);
    CNN_Accel_write_reg(drv, CNN_ACCEL_IFC_ZP_WORD_OFFSET,          (uint32_t)(uint8_t)config->ifc_zp);
    CNN_Accel_write_reg(drv, CNN_ACCEL_FLTC_ZP_WORD_OFFSET,         (uint32_t)(uint8_t)config->fltc_zp);
    CNN_Accel_write_reg(drv, CNN_ACCEL_MULT_WORD_OFFSET,            (uint32_t)config->mult);
    CNN_Accel_write_reg(drv, CNN_ACCEL_MULT_SHIFT_WORD_OFFSET,      (uint32_t)(config->mult_shift & 0x3FU));
    CNN_Accel_write_reg(drv, CNN_ACCEL_ALPHAMULT_WORD_OFFSET,       (uint32_t)config->alphamult);
    CNN_Accel_write_reg(drv, CNN_ACCEL_ALPHAMULT_SHIFT_WORD_OFFSET, (uint32_t)(config->alphamult_shift & 0x3FU));
    CNN_Accel_write_reg(drv, CNN_ACCEL_ZPY_WORD_OFFSET,             (uint32_t)(uint8_t)config->zpy);
    CNN_Accel_write_reg(drv, CNN_ACCEL_QMIN_WORD_OFFSET,            (uint32_t)(uint8_t)config->qmin);
    CNN_Accel_write_reg(drv, CNN_ACCEL_QMAX_WORD_OFFSET,            (uint32_t)(uint8_t)config->qmax);
    CNN_Accel_write_reg(drv, CNN_ACCEL_IS_LEAKY_RELU_WORD_OFFSET,   config->is_leaky_relu ? 1U : 0U);
}

void CNN_Accel_commit_layer_config(CNN_Accel_Driver_t *drv)
{
    CNN_Accel_write_reg(drv, CNN_ACCEL_WRITE_FIFO_WORD_OFFSET, 1U);
}

bool CNN_Accel_submit_layer_config(CNN_Accel_Driver_t *drv, const CNN_Accel_LayerConfig_t *config, uint32_t timeout)
{
    if (!CNN_Accel_wait_table_ready(drv, timeout)) {
        return false;
    }

    CNN_Accel_load_layer_config(drv, config);
    CNN_Accel_commit_layer_config(drv);

    return CNN_Accel_wait_layer_accepted(drv, timeout);
}

void CNN_Accel_start(CNN_Accel_Driver_t *drv)
{
    CNN_Accel_write_reg(drv, CNN_ACCEL_START_WORD_OFFSET, 1U);
}

bool CNN_Accel_wait_table_ready(CNN_Accel_Driver_t *drv, uint32_t timeout)
{
    return CNN_Accel_wait_status(drv, CNN_ACCEL_STATUS_TABLE_READY_Msk, true, timeout);
}

bool CNN_Accel_wait_layer_accepted(CNN_Accel_Driver_t *drv, uint32_t timeout)
{
    return CNN_Accel_wait_status(drv, CNN_ACCEL_STATUS_TABLE_VALID_Msk, false, timeout);
}

bool CNN_Accel_wait_done(CNN_Accel_Driver_t *drv, uint32_t timeout)
{
    return CNN_Accel_wait_status(drv, CNN_ACCEL_STATUS_DONE_Msk, true, timeout);
}

bool CNN_Accel_wait_idle(CNN_Accel_Driver_t *drv, uint32_t timeout)
{
    return CNN_Accel_wait_status(drv, CNN_ACCEL_STATUS_BUSY_Msk, false, timeout);
}

#ifdef HAL_INTERRUPT_MODULE_ENABLED
bool CNN_Accel_attach_irq(IRQ_Handler_t handler, void *context, uint8_t priority)
{
    return IRQ_Attach(CNN_ACCEL_IRQ_BIT, handler, context, priority);
}

void CNN_Accel_enable_irq(void)
{
    IRQ_Enable(CNN_ACCEL_IRQ_BIT);
}

void CNN_Accel_disable_irq(void)
{
    IRQ_Disable(CNN_ACCEL_IRQ_BIT);
}
#endif

#endif // HAL_CNN_ACCEL_MODULE_ENABLED
