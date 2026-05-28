/**
 * @file irq_manager.c
 * @brief Implementation of the O(1) Interrupt Dispatcher.
 */

/*
 * Legacy bootloader-only IRQ manager.
 *
 * Disabled because bootloader now uses the shared SoC HAL interrupt driver:
 *   Drivers/SoC_HAL/Inc/Interrupt_Driver.h
 *   Drivers/SoC_HAL/Src/Interrupt_Driver.c
 *
 * Keep this file for reference/regression checks. Change 0 to 1 if you want to
 * temporarily restore the old bootloader interrupt stack.
 */
#if 0

#include "irq_manager.h"
#include <stddef.h>

/* ========================================================================= */
/* DRIVER IRQ HANDLERS (WEAK DECLARATIONS)                                   */
/* ========================================================================= */

/* * These are weak declarations. If a specific driver (e.g., timer_hal.c) 
 * is included in the build and defines a function with the same name, 
 * the linker will automatically use the driver's function instead of these empty ones.
 * This guarantees zero dependencies between the Manager and the HALs.
 */
__attribute__((weak)) void HAL_Timer_IRQHandler(void) { /* Default: Empty */ }
__attribute__((weak)) void HAL_UART_IRQHandler(void)  { /* Default: Empty */ }
__attribute__((weak)) void HAL_GPIO_IRQHandler(void)  { /* Default: Empty */ }

/* ========================================================================= */
/* INTERRUPT VECTOR TABLE (LOOK-UP TABLE)                                    */
/* ========================================================================= */

/**
 * @brief Look-up table mapping IRQ bit indices to their respective handlers.
 */
static void (*const irq_vector_table[32])(void) = {
    HAL_Timer_IRQHandler,   /* Index 0: mapped to IRQ_TIMER_BIT */
    HAL_UART_IRQHandler,    /* Index 1: mapped to IRQ_UART_RX_BIT */
    HAL_GPIO_IRQHandler,    /* Index 2: mapped to IRQ_GPIO_BIT */
    /* Indices 3 to 31 are implicitly initialized to NULL if not specified */
};

/* ========================================================================= */
/* CENTRAL DISPATCHER                                                        */
/* ========================================================================= */

static inline uint32_t fast_software_ctz(uint32_t x); // Forward declaration of the software CTZ function

void irq_central_dispatcher(CPU_Context_t *ctx) {
    /* Retrieve the bitmask of pending interrupts from PicoRV32's q1 register */
    uint32_t pending_irqs = ctx->pending_irq;

    /* Process all pending interrupts in O(1) time per active bit */
    while (pending_irqs != 0) {
        /* __builtin_ctz counts trailing zeros, effectively finding the lowest set bit index.
           Example: If pending_irqs = 0b0101 (Bits 0 and 2 set), ctz returns 0. */
        uint32_t irq_num = fast_software_ctz(pending_irqs);

        /* Safety check before dereferencing the function pointer */
        if (irq_num < 32 && irq_vector_table[irq_num] != NULL) {
            irq_vector_table[irq_num](); /* Route to the Driver */
        }

        /* Clear the processed bit to move on to the next pending interrupt (if any) */
        pending_irqs &= ~(1 << irq_num);
    }
}

/* ========================================================================= */
/* INTERNAL HELPER FUNCTIONS                                                 */
/* ========================================================================= */

/**
 * @brief Fast software implementation of Count Trailing Zeros (CTZ).
 * * SUMMARY:
 * Solves the '__ctzsi2' linker error on basic RISC-V cores lacking the Zbb 
 * bit-manipulation extension. Uses a deterministic binary-search approach.
 * * @param x The 32-bit integer to analyze (must be non-zero).
 * @return The number of trailing zero bits (0 to 31).
 */
static inline uint32_t fast_software_ctz(uint32_t x) {
    uint32_t count = 0;
    
    if ((x & 0x0000FFFF) == 0) { count += 16; x >>= 16; }
    if ((x & 0x000000FF) == 0) { count +=  8; x >>=  8; }
    if ((x & 0x0000000F) == 0) { count +=  4; x >>=  4; }
    if ((x & 0x00000003) == 0) { count +=  2; x >>=  2; }
    if ((x & 0x00000001) == 0) { count +=  1; }
    
    return count;
}

#endif
