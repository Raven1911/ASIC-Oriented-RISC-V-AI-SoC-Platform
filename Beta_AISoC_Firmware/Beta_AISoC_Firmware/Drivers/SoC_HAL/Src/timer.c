#include "../Inc/timer.h"
#ifdef HAL_TIMER_MODULE_ENABLED

void timer_init(void)
{
    go();
}

void pause(void)
{
    volatile uint32_t *ctrl = (uint32_t *)(TIMER0_BASE_ADDR + TIMER_CONTROL_OFFSET * 4);
    *ctrl &= ~TIMER_CONTROL_START_Msk;
}

void go(void)
{
    volatile uint32_t *ctrl = (uint32_t *)(TIMER0_BASE_ADDR + TIMER_CONTROL_OFFSET * 4);
    *ctrl |= TIMER_CONTROL_START_Msk;
}

void clear(void)
{
    volatile uint32_t *ctrl = (uint32_t *)(TIMER0_BASE_ADDR + TIMER_CONTROL_OFFSET * 4);
    *ctrl |= TIMER_CONTROL_CLEAR_Msk;
    *ctrl &= ~TIMER_CONTROL_CLEAR_Msk;
}

tick_t read_tick(void)
{
    volatile uint32_t *lower_reg = (uint32_t *)(TIMER0_BASE_ADDR + TIMER_COUNTER_LOWER_OFFSET * 4);
    volatile uint32_t *upper_reg = (uint32_t *)(TIMER0_BASE_ADDR + TIMER_COUNTER_UPPER_OFFSET * 4);

    tick_t tick;
    tick.lower = *lower_reg;
    tick.upper = *upper_reg;

    return tick;
}

int compare_ticks(tick_t a, tick_t b)
{
    if (a.upper != b.upper)
        return (a.upper > b.upper) ? 1 : -1;
    if (a.lower != b.lower)
        return (a.lower > b.lower) ? 1 : -1;
    return 0;
}

tick_t subtract_ticks(tick_t a, tick_t b)
{
    tick_t result;
    result.lower = a.lower - b.lower;
    result.upper = a.upper - b.upper;

    if (a.lower < b.lower)
        result.upper--;

    return result;
}

tick_t add_ticks(tick_t a, tick_t b)
{
    tick_t result;
    result.lower = a.lower + b.lower;
    result.upper = a.upper + b.upper;

    if (result.lower < a.lower)
        result.upper++;

    result.upper &= COUNTER_MAX_UPPER;

    return result;
}

tick_t subtract_with_wraparound(tick_t a, tick_t b)
{
    if (compare_ticks(a, b) >= 0)
        return subtract_ticks(a, b);

    tick_t max = {0, COUNTER_MAX_UPPER + 1};
    tick_t wrapped = add_ticks(a, max);
    return subtract_ticks(wrapped, b);
}

uint32_t micros(void)
{
    tick_t tick = read_tick();
    return (tick.lower * 5U) / 1000U;
}

uint32_t millis(void)
{
    tick_t tick = read_tick();
    return tick.lower / CYCLES_PER_MS;
}

void delay(uint32_t ms)
{
    tick_t start = read_tick();
    uint32_t target_ticks = ms * CYCLES_PER_MS;

    while (1)
    {
        tick_t current = read_tick();
        tick_t elapsed = subtract_with_wraparound(current, start);

        if (elapsed.lower >= target_ticks)
            break;
    }
}

void delayMicroseconds(uint32_t us)
{
    uint32_t start = micros();

    while (1)
    {
        uint32_t current = micros();
        uint32_t elapsed;

        if (current >= start)
            elapsed = current - start;
        else
            elapsed = (0xFFFFFFFFU - start) + current + 1U;

        if (elapsed >= us)
            break;
    }
}

#endif // HAL_TIMER_MODULE_ENABLED