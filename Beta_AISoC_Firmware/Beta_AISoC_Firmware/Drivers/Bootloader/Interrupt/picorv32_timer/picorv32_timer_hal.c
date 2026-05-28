/**
 * @file picorv32_timer_hal.c
 * @brief Implementation of the Timer HAL and its internal ISR logic.
 */

/*
 * Legacy bootloader-only PicoRV32 timer HAL.
 *
 * Disabled because bootloader now uses the shared SoC HAL interrupt driver:
 *   Drivers/SoC_HAL/Inc/Interrupt_Driver.h
 *   Drivers/SoC_HAL/Src/Interrupt_Driver.c
 *
 * Keep this file for reference/regression checks. Change 0 to 1 if you want to
 * temporarily restore the old bootloader timer interrupt stack.
 */
#if 0

#include "picorv32_timer_hal.h"
#include "../irq_manager.h" // Needed ONLY for IRQ_TIMER_BIT definition and ISA macros
#include <stddef.h>

/* ========================================================================= */
/* INTERNAL DRIVER STATE                                                     */
/* ========================================================================= */

static uint32_t g_active_reload_cycles = 0;
static bool     g_active_auto_reload   = false;

/* Store a pointer to the user's config to pass as context into the callback */
static const Timer_Config_t *g_current_config_ptr = NULL;

/* ========================================================================= */
/* PUBLIC APIs                                                               */
/* ========================================================================= */

void HAL_Timer_SetConfig(Timer_Config_t *config, uint32_t freq_hz, uint32_t prescaler, uint32_t period, bool reload) {
    if (config != NULL) {
        config->ClockFreqHz = freq_hz;
        config->Prescaler   = prescaler;
        config->Period      = period;
        config->AutoReload  = reload;
    }
}

void HAL_Timer_Init(const Timer_Config_t *config) {
    if (config == NULL) return;

    /* Save the configuration pointer for context-aware callbacks */
    g_current_config_ptr = config;

    /* Calculate hardware cycles: Cycles = (Prescaler + 1) * Period */
    g_active_reload_cycles = (config->Prescaler + 1) * config->Period;
    g_active_auto_reload   = config->AutoReload;
    
    /* Pre-load the custom hardware timer register */
    picorv32_timer(g_active_reload_cycles);
}

void HAL_Timer_Start(void) {
    /* Clear bit 0 in the interrupt mask to ENABLE the timer */
    uint32_t mask = picorv32_maskirq(0xFFFFFFFF);
    picorv32_maskirq(mask & ~(1 << IRQ_TIMER_BIT));
}

void HAL_Timer_Stop(void) {
    /* Set bit 0 in the interrupt mask to DISABLE the timer */
    uint32_t mask = picorv32_maskirq(0xFFFFFFFF);
    picorv32_maskirq(mask | (1 << IRQ_TIMER_BIT));
    picorv32_timer(0);
}

/* ========================================================================= */
/* INTERRUPT SERVICE ROUTINE (ISR)                                           */
/* ========================================================================= */

/**
 * @brief Default weak implementation of the user callback.
 */
__attribute__((weak)) void HAL_Timer_TimeoutCallback(const Timer_Config_t *htim) {
    /* Suppress unused parameter warning */
    (void)htim;
}

/**
 * @brief Driver-level IRQ Handler.
 * * * This overrides the weak function defined in irq_manager.c.
 * * It isolates the user from hardware-specific tasks like auto-reloading.
 */
void HAL_Timer_IRQHandler(void) {
    /* 1. Execute User Application Logic with context */
    HAL_Timer_TimeoutCallback(g_current_config_ptr);

    /* 2. Handle hardware auto-reload internally */
    if (g_active_auto_reload) {
        picorv32_timer(g_active_reload_cycles);
    }
}

#endif
