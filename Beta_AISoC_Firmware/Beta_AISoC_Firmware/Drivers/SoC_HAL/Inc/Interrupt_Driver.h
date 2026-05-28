#ifndef INTERRUPT_DRIVER_H
#define INTERRUPT_DRIVER_H

#include <stdint.h>
#include <stdbool.h>
#include "../../../App/Inc/soc_hal_config.h"

/*
 * PicoRV32 gom toàn bộ interrupt thành một vector duy nhất. Khi có interrupt,
 * CPU nhảy tới PROGADDR_IRQ và đặt bitmask nguồn interrupt vào q1.
 *
 * Các bit 0..2 là nguồn nội bộ của PicoRV32:
 *   bit 0: timer bên trong PicoRV32, dùng bằng custom instruction timer
 *   bit 1: ebreak
 *   bit 2: bus error
 *
 * Vì vậy các ngoại vi memory-mapped của SoC nên nối từ bit 3 trở đi.
 */
#define IRQ_TIMER_BIT         0U  /* Timer IRQ nội bộ của PicoRV32. */
#define IRQ_EBREAK_BIT        1U  /* IRQ khi gặp lệnh ebreak nếu core bật nguồn này. */
#define IRQ_BUSERROR_BIT      2U  /* IRQ lỗi bus/memory transaction. */
#define IRQ_EXTERNAL_BASE_BIT 3U  /* Bit đầu tiên nên dùng cho ngoại vi tự thiết kế. */

#define IRQ_EXTERNAL0_BIT     3U  /* Alias tiện dùng cho irq[3]. */
#define IRQ_EXTERNAL1_BIT     4U  /* Alias tiện dùng cho irq[4]. */
#define IRQ_EXTERNAL2_BIT     5U  /* Alias tiện dùng cho irq[5]. */
#define IRQ_EXTERNAL3_BIT     6U  /* Alias tiện dùng cho irq[6]. */
#define IRQ_EXTERNAL4_BIT     7U  /* Alias tiện dùng cho irq[7]. */

#define IRQ_BIT(bit)          (1UL << (bit)) /* Chuyển số bit thành mask, ví dụ bit 3 -> 0x8. */

/*
 * Priority chỉ do software dispatcher xử lý, không phải phần cứng PicoRV32.
 * Số càng nhỏ càng ưu tiên cao. Nếu nhiều IRQ pending cùng lúc, dispatcher
 * chọn priority cao nhất trước; nếu bằng nhau thì bit nhỏ hơn được chọn trước.
 */
#define IRQ_PRIORITY_HIGHEST  0U
#define IRQ_PRIORITY_DEFAULT  128U
#define IRQ_PRIORITY_LOWEST   255U

/* Kiểu callback chung cho mọi nguồn IRQ ngoài timer wrapper. */
typedef void (*IRQ_Handler_t)(uint32_t irq_bit, void *context);

/*
 * Layout này phải khớp với stack frame mà irq_wrapper trong startup lưu lại.
 * Dispatcher chỉ cần pending_irq, nhưng giữ đủ context để sau này debug/mở rộng.
 */
typedef struct {
    uint32_t t0_t2[3];    /* t0, t1, t2 được lưu ở offset 0..8. */
    uint32_t a0_a7[8];    /* a0..a7 được lưu ở offset 12..40. */
    uint32_t t3_t6[4];    /* t3..t6 được lưu ở offset 44..56. */
    uint32_t ra;          /* Return address thường của C ABI. */
    uint32_t mepc;        /* PC nơi CPU đang chạy trước khi interrupt xảy ra, lấy từ q0. */
    uint32_t pending_irq; /* Bitmask nguồn interrupt đang pending, lấy từ q1. */
    uint32_t padding[2];  /* Giữ stack frame align 16 byte. */
} CPU_Context_t;

/* Cấu hình cho timer IRQ nội bộ của PicoRV32. */
typedef struct {
    uint32_t ClockFreqHz; /* Clock CPU, hiện chủ yếu để người dùng đọc/ngữ nghĩa config. */
    uint32_t Prescaler;   /* Chia ảo trong software: cycles = (Prescaler + 1) * Period. */
    uint32_t Period;      /* Số tick sau prescaler ảo trước khi timer IRQ fire. */
    bool AutoReload;      /* true: ISR tự nạp lại timer; false: one-shot. */
} Timer_Config_t;

/* Đọc q-register của PicoRV32. q0 thường là return PC, q1 là pending IRQ. */
#define picorv32_getq(qs) ({ \
    uint32_t __rd_val; \
    __asm__ volatile (".insn r 0x0b, 0b100, 0, %0, x%1, x0" \
                      : "=r"(__rd_val) : "i"(qs)); \
    __rd_val; \
})

/* Ghi q-register của PicoRV32, thường dùng để restore q0 trước retirq. */
#define picorv32_setq(qd, rs) \
    __asm__ volatile (".insn r 0x0b, 0b010, 1, x%0, %1, x0" \
                      : : "i"(qd), "r"(rs))

/* Return khỏi IRQ. Hàm này thường chỉ gọi ở assembly wrapper, không gọi trong app. */
static inline void picorv32_retirq(void)
{
    __asm__ volatile (".insn r 0x0b, 0, 2, x0, x0, x0");
}

/*
 * Đặt interrupt mask của PicoRV32.
 * Quy ước PicoRV32: bit mask = 1 nghĩa là disable IRQ đó, bit mask = 0 là enable.
 * Hàm trả về mask cũ, nên có thể dùng để read-modify-write.
 */
static inline uint32_t picorv32_maskirq(uint32_t mask)
{
    uint32_t old_mask;
    __asm__ volatile (".insn r 0x0b, 0b110, 3, %0, %1, x0"
                      : "=r"(old_mask) : "r"(mask));
    return old_mask;
}

/* Chờ tới khi có IRQ pending. Phù hợp cho vòng sleep/idle đơn giản. */
static inline uint32_t picorv32_waitirq(void)
{
    uint32_t irqs;
    __asm__ volatile (".insn r 0x0b, 0b100, 4, %0, x0, x0"
                      : "=r"(irqs));
    return irqs;
}

/* Ghi timer counter nội bộ PicoRV32. Khi counter đếm về 0 thì set IRQ bit 0. */
static inline uint32_t picorv32_timer(uint32_t val)
{
    uint32_t old_val;
    __asm__ volatile (".insn r 0x0b, 0b110, 5, %0, %1, x0"
                      : "=r"(old_val) : "r"(val));
    return old_val;
}

void IRQ_Init(void); /* Reset bảng handler/priority và mask toàn bộ IRQ. */
bool IRQ_Attach(uint32_t irq_bit, IRQ_Handler_t handler, void *context, uint8_t priority); /* Gắn handler cho một IRQ bit. */
void IRQ_Detach(uint32_t irq_bit); /* Gỡ handler, đưa priority về mặc định. */
bool IRQ_SetPriority(uint32_t irq_bit, uint8_t priority); /* Đổi priority cho IRQ đã/đang dùng. */
uint8_t IRQ_GetPriority(uint32_t irq_bit); /* Đọc priority hiện tại. */

void IRQ_Enable(uint32_t irq_bit); /* Enable một IRQ bit bằng cách clear mask bit. */
void IRQ_Disable(uint32_t irq_bit); /* Disable một IRQ bit bằng cách set mask bit. */
void IRQ_EnableMask(uint32_t irq_mask); /* Enable nhiều IRQ cùng lúc bằng mask. */
void IRQ_DisableMask(uint32_t irq_mask); /* Disable nhiều IRQ cùng lúc bằng mask. */
void IRQ_DisableAll(void); /* Disable tất cả IRQ. */
uint32_t IRQ_GetMask(void); /* Đọc mask hiện tại của PicoRV32. */
uint32_t IRQ_SetMask(uint32_t mask); /* Ghi mask trực tiếp, trả về mask cũ. */
uint32_t IRQ_Wait(void); /* Gọi waitirq, trả về pending mask đánh thức CPU. */

void irq_central_dispatcher(CPU_Context_t *ctx); /* Hàm C được irq_wrapper gọi sau khi save context. */

void HAL_Timer_SetConfig(Timer_Config_t *config, uint32_t freq_hz, uint32_t prescaler, uint32_t period, bool reload); /* Điền cấu hình timer. */
void HAL_Timer_Init(const Timer_Config_t *config); /* Nạp counter timer và đăng ký handler bit 0. */
void HAL_Timer_SetPriority(uint8_t priority); /* Đặt priority cho timer IRQ. */
void HAL_Timer_Start(void); /* Enable IRQ bit 0. */
void HAL_Timer_Stop(void); /* Disable IRQ bit 0 và tắt counter timer. */
void HAL_Timer_IRQHandler(void); /* Handler nội bộ cho timer, gọi callback người dùng. */
void HAL_Timer_TimeoutCallback(const Timer_Config_t *htim); /* Callback weak: định nghĩa lại trong app. */

void HAL_IRQ_UnhandledCallback(uint32_t irq_bit); /* Callback weak khi có IRQ chưa gắn handler. */

#endif // INTERRUPT_DRIVER_H
