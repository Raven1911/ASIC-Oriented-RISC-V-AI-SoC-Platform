#ifndef TIMER_H
#define TIMER_H

#include <soc_hal.h>

#define TIMER0_BASE_ADDR 0x02006000U

#define TIMER_COUNTER_UPPER_OFFSET 0x00U
#define TIMER_COUNTER_LOWER_OFFSET 0x01U
#define TIMER_CONTROL_OFFSET       0x02U

#define TIMER_CONTROL_START_Pos (0U)
#define TIMER_CONTROL_START_Msk (0x1U << TIMER_CONTROL_START_Pos)
#define TIMER_CONTROL_CLEAR_Pos (1U)
#define TIMER_CONTROL_CLEAR_Msk (0x1U << TIMER_CONTROL_CLEAR_Pos)

#define COUNTER_WIDTH     50U
#define COUNTER_MAX_LOWER 0xFFFFFFFFU
#define COUNTER_MAX_UPPER ((1U << 18) - 1U)

typedef struct {
    uint32_t lower;
    uint32_t upper;
} tick_t;

void timer_init(void);
void pause(void);
void go(void);
void clear(void);

tick_t read_tick(void);

uint32_t micros(void);
uint32_t millis(void);

void delay(uint32_t ms);
void delayMicroseconds(uint32_t us);

#endif // TIMER_H