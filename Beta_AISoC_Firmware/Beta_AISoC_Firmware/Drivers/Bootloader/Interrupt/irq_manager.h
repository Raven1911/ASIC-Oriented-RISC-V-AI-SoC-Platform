/**
 * @file irq_manager.h
 * @brief Decoupled Interrupt Manager for PicoRV32.
 * * SUMMARY:
 * This module manages the routing of hardware interrupts to their respective 
 * peripheral drivers (HALs). It is completely independent and does not 
 * include any driver headers, ensuring a loosely coupled architecture.
 */

#ifndef PICORV32_IRQ_MANAGER_H
#define PICORV32_IRQ_MANAGER_H

#include <stdint.h>
#include "irq_ops.h" // Includes custom ISA macros: picorv32_getq, etc.

/* --- Hardware IRQ Bit Definitions --- */
#define IRQ_TIMER_BIT       0  /*!< IRQ mapping for the internal PicoRV32 Timer */
#define IRQ_UART_RX_BIT     1  /*!< IRQ mapping for UART Receive (Example) */
#define IRQ_GPIO_BIT        2  /*!< IRQ mapping for GPIO External (Example) */
// Add more IRQ bit definitions as needed

/**
 * @brief CPU Context Structure.
 * * This perfectly maps the 80-byte stack frame created by startup.S.
 * It allows the C code to inspect the state of the CPU at the exact 
 * moment the interrupt occurred.
 */
typedef struct {
    uint32_t t0_t2[3];    /* Offsets: 0, 4, 8 */
    uint32_t a0_a7[8];    /* Offsets: 12 to 40 */
    uint32_t t3_t6[4];    /* Offsets: 44 to 56 */
    uint32_t ra;          /* Offset: 60 (Return Address) */
    uint32_t mepc;        /* Offset: 64 (Exception PC from q0) */
    uint32_t pending_irq; /* Offset: 68 (IRQ source from q1) */
    uint32_t padding[2];  /* Offsets: 72, 76 (Alignment padding) */
} CPU_Context_t;

/* --- Core Dispatcher --- */
/**
 * @brief Central entry point for all interrupts.
 * * USAGE:
 * This function must be called from the low-level assembly interrupt vector 
 * (e.g., startup.S). It identifies the pending interrupt and routes execution 
 * to the corresponding driver's IRQ handler in O(1) time complexity.
 * * @param ctx Pointer to the CPU context structure.
 */
void irq_central_dispatcher(CPU_Context_t *ctx);

#endif // PICORV32_IRQ_MANAGER_H