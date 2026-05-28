/**
 * @file picorv32_timer_hal.h
 * @brief Procedural Hardware Abstraction Layer for PicoRV32 Timer.
 * * SUMMARY:
 * Provides a clean API to configure and manage the hardware timer. 
 * Exposes a context-aware callback system for user applications.
 */

#ifndef PICORV32_TIMER_HAL_H
#define PICORV32_TIMER_HAL_H

#include <stdint.h>
#include <stdbool.h>

/**
 * @brief Timer Configuration Structure.
 * Holds the raw data needed to calculate hardware cycles.
 */
typedef struct {
    uint32_t ClockFreqHz; /*!< System clock frequency in Hz */
    uint32_t Prescaler;   /*!< Virtual clock divider. Freq = CPU_Freq / (Prescaler + 1) */
    uint32_t Period;      /*!< Number of virtual ticks before the interrupt fires */
    bool     AutoReload;  /*!< True to restart timer automatically inside the ISR */
} Timer_Config_t;

/* --- Initialization & Control APIs --- */

/**
 * @brief Populates the Timer_Config_t structure cleanly.
 */
void HAL_Timer_SetConfig(Timer_Config_t *config, uint32_t freq_hz, uint32_t prescaler, uint32_t period, bool reload);

/**
 * @brief Applies the configuration and prepares the hardware timer.
 */
void HAL_Timer_Init(const Timer_Config_t *config);

/**
 * @brief Unmasks the timer interrupt to begin counting.
 */
void HAL_Timer_Start(void);

/**
 * @brief Masks the timer interrupt and clears the hardware counter.
 */
void HAL_Timer_Stop(void);

/* --- User Callback System --- */

/**
 * @brief User application callback executed upon timer timeout.
 * * @param htim Pointer to the configuration structure of the timer that triggered the IRQ.
 * Provides context, essential for multi-timer architectures.
 * * @note This is a weak function. Redefine it in your main application logic.
 */
void HAL_Timer_TimeoutCallback(const Timer_Config_t *htim);

#endif // PICORV32_TIMER_HAL_H