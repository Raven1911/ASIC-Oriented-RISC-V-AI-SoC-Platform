#include "Interrupt_Driver.h"

#ifdef HAL_INTERRUPT_MODULE_ENABLED

typedef struct {
    IRQ_Handler_t handler; /* Hàm sẽ được gọi khi IRQ bit này pending. */
    void *context;         /* Con trỏ user truyền vào, giúp handler biết đang phục vụ instance nào. */
    uint8_t priority;      /* Số nhỏ hơn nghĩa là ưu tiên cao hơn. */
} IRQ_Slot_t;

static IRQ_Slot_t irq_slots[32]; /* Bảng routing cho tối đa 32 IRQ bit của PicoRV32. */

static uint8_t g_timer_priority = IRQ_PRIORITY_HIGHEST; /* Timer thường nên ưu tiên cao. */
static uint32_t g_active_reload_cycles = 0U;            /* Giá trị counter sẽ nạp vào custom timer. */
static bool g_active_auto_reload = false;               /* true thì ISR tự nạp lại counter sau callback. */
static const Timer_Config_t *g_current_timer_config = 0; /* Context truyền vào HAL_Timer_TimeoutCallback. */

static int32_t IRQ_SelectNext(uint32_t pending)
{
    int32_t selected = -1; /* -1 nghĩa là chưa chọn được IRQ nào. */
    uint8_t selected_priority = IRQ_PRIORITY_LOWEST;

    /*
     * PicoRV32 chỉ đưa cho ta một pending bitmask. Software tự quyết thứ tự xử lý.
     * Vòng lặp này scan toàn bộ 32 bit và chọn bit có priority nhỏ nhất.
     * Nếu hai IRQ cùng priority, bit thấp hơn thắng vì được scan trước.
     */
    for (uint32_t bit = 0U; bit < 32U; ++bit) {
        if ((pending & IRQ_BIT(bit)) == 0U) {
            continue; /* Bit này không pending, bỏ qua. */
        }

        uint8_t priority = irq_slots[bit].priority;
        if (selected < 0 || priority < selected_priority) {
            selected = (int32_t)bit;
            selected_priority = priority;
        }
    }

    return selected;
}

static void HAL_Timer_IRQAdapter(uint32_t irq_bit, void *context)
{
    /* Adapter để timer cũng đi qua bảng IRQ chung nhưng vẫn giữ API HAL_Timer_IRQHandler. */
    (void)irq_bit;
    (void)context;
    HAL_Timer_IRQHandler();
}

void IRQ_Init(void)
{
    /* Đưa toàn bộ bảng handler về trạng thái sạch trước khi enable IRQ. */
    for (uint32_t bit = 0U; bit < 32U; ++bit) {
        irq_slots[bit].handler = 0;
        irq_slots[bit].context = 0;
        irq_slots[bit].priority = IRQ_PRIORITY_DEFAULT;
    }

    IRQ_DisableAll(); /* Mặc định khóa hết IRQ để user chủ động enable từng nguồn. */
}

bool IRQ_Attach(uint32_t irq_bit, IRQ_Handler_t handler, void *context, uint8_t priority)
{
    if (irq_bit >= 32U || handler == 0) {
        return false; /* Bảo vệ khỏi bit ngoài range hoặc handler NULL. */
    }

    irq_slots[irq_bit].handler = handler;
    irq_slots[irq_bit].context = context;
    irq_slots[irq_bit].priority = priority;
    return true;
}

void IRQ_Detach(uint32_t irq_bit)
{
    if (irq_bit < 32U) {
        irq_slots[irq_bit].handler = 0; /* Không tự disable IRQ để user tùy chính sách. */
        irq_slots[irq_bit].context = 0;
        irq_slots[irq_bit].priority = IRQ_PRIORITY_DEFAULT;
    }
}

bool IRQ_SetPriority(uint32_t irq_bit, uint8_t priority)
{
    if (irq_bit >= 32U) {
        return false;
    }

    irq_slots[irq_bit].priority = priority;
    return true;
}

uint8_t IRQ_GetPriority(uint32_t irq_bit)
{
    if (irq_bit >= 32U) {
        return IRQ_PRIORITY_LOWEST;
    }

    return irq_slots[irq_bit].priority;
}

void IRQ_Enable(uint32_t irq_bit)
{
    if (irq_bit < 32U) {
        IRQ_EnableMask(IRQ_BIT(irq_bit)); /* mask bit = 0 là enable trong PicoRV32. */
    }
}

void IRQ_Disable(uint32_t irq_bit)
{
    if (irq_bit < 32U) {
        IRQ_DisableMask(IRQ_BIT(irq_bit)); /* mask bit = 1 là disable trong PicoRV32. */
    }
}

void IRQ_EnableMask(uint32_t irq_mask)
{
    uint32_t mask = picorv32_maskirq(0xFFFFFFFFU); /* Lấy mask cũ bằng cách tạm disable hết. */
    picorv32_maskirq(mask & ~irq_mask);            /* Clear các bit cần enable rồi ghi lại. */
}

void IRQ_DisableMask(uint32_t irq_mask)
{
    uint32_t mask = picorv32_maskirq(0xFFFFFFFFU); /* Lấy mask cũ bằng cách tạm disable hết. */
    picorv32_maskirq(mask | irq_mask);             /* Set các bit cần disable rồi ghi lại. */
}

void IRQ_DisableAll(void)
{
    picorv32_maskirq(0xFFFFFFFFU);
}

uint32_t IRQ_GetMask(void)
{
    uint32_t mask = picorv32_maskirq(0xFFFFFFFFU); /* Custom instruction trả về mask cũ. */
    picorv32_maskirq(mask);                        /* Khôi phục lại mask vừa đọc. */
    return mask;
}

uint32_t IRQ_SetMask(uint32_t mask)
{
    return picorv32_maskirq(mask);
}

uint32_t IRQ_Wait(void)
{
    return picorv32_waitirq();
}

void irq_central_dispatcher(CPU_Context_t *ctx)
{
    if (ctx == 0) {
        return;
    }

    uint32_t pending = ctx->pending_irq; /* q1 snapshot do assembly wrapper lưu vào stack. */

    /*
     * Xử lý hết các bit pending trong snapshot này theo priority.
     * Nếu trong lúc đang xử lý lại phát sinh IRQ mới, PicoRV32 sẽ pending lại và vào
     * interrupt lần sau sau khi retirq, trừ khi nguồn đó đã được clear/mask đúng cách.
     */
    while (pending != 0U) {
        int32_t irq_bit = IRQ_SelectNext(pending);
        if (irq_bit < 0) {
            break;
        }

        if (irq_slots[irq_bit].handler != 0) {
            irq_slots[irq_bit].handler((uint32_t)irq_bit, irq_slots[irq_bit].context);
        } else {
            HAL_IRQ_UnhandledCallback((uint32_t)irq_bit); /* Cho app log/debug nếu quên gắn handler. */
        }

        pending &= ~IRQ_BIT((uint32_t)irq_bit); /* Xóa bit đã xử lý khỏi snapshot software. */
    }
}

void HAL_Timer_SetConfig(Timer_Config_t *config, uint32_t freq_hz, uint32_t prescaler, uint32_t period, bool reload)
{
    if (config != 0) {
        config->ClockFreqHz = freq_hz;
        config->Prescaler = prescaler;
        config->Period = period;
        config->AutoReload = reload;
    }
}

void HAL_Timer_Init(const Timer_Config_t *config)
{
    if (config == 0) {
        return;
    }

    g_current_timer_config = config; /* Lưu pointer để callback biết config nào fire. */
    g_active_reload_cycles = (config->Prescaler + 1U) * config->Period; /* Pico timer nhận cycle thật. */
    g_active_auto_reload = config->AutoReload;

    IRQ_Attach(IRQ_TIMER_BIT, HAL_Timer_IRQAdapter, 0, g_timer_priority); /* Đăng ký timer vào dispatcher. */
    picorv32_timer(g_active_reload_cycles); /* Nạp counter nhưng chưa chắc enable nếu mask bit 0 còn set. */
}

void HAL_Timer_SetPriority(uint8_t priority)
{
    g_timer_priority = priority;             /* Lưu cho trường hợp gọi trước HAL_Timer_Init. */
    IRQ_SetPriority(IRQ_TIMER_BIT, priority); /* Cập nhật ngay nếu timer đã attach. */
}

void HAL_Timer_Start(void)
{
    IRQ_Enable(IRQ_TIMER_BIT); /* Clear mask bit 0, timer đếm về 0 sẽ tạo IRQ. */
}

void HAL_Timer_Stop(void)
{
    IRQ_Disable(IRQ_TIMER_BIT); /* Chặn timer IRQ trước. */
    picorv32_timer(0U);         /* Tắt counter nội bộ. */
}

void HAL_Timer_IRQHandler(void)
{
    HAL_Timer_TimeoutCallback(g_current_timer_config); /* User override hàm weak này trong app. */

    if (g_active_auto_reload) {
        picorv32_timer(g_active_reload_cycles); /* Nạp lại để tạo periodic interrupt. */
    }
}

__attribute__((weak)) void HAL_Timer_TimeoutCallback(const Timer_Config_t *htim)
{
    (void)htim;
}

__attribute__((weak)) void HAL_IRQ_UnhandledCallback(uint32_t irq_bit)
{
    (void)irq_bit;
}

#endif // HAL_INTERRUPT_MODULE_ENABLED
