/**
 * @file irq_ops.h
 * @brief Custom Instruction Set Architecture (ISA) extensions for PicoRV32 Interrupts.
 * * SUMMARY:
 * This header provides C-level access to the non-standard RISC-V instructions 
 * implemented in the PicoRV32 core. These instructions are primarily used for 
 * low-level interrupt handling, register management (q-registers), and 
 * hardware timer control.
 * * All instructions use the 'custom-0' opcode (0x0B).
 */

#ifndef PICORV32_INSTR_H
#define PICORV32_INSTR_H

#include <stdint.h>

/**
 * @brief Read a value from a custom q-register into a general-purpose register.
 * * USAGE: 
 * uint32_t val = picorv32_getq(1); // Reads from q1
 * * @param qs The source q-register index (0, 1, 2, or 3).
 * @return The 32-bit value stored in the specified q-register.
 */
#define picorv32_getq(qs) ({ \
    uint32_t __rd_val; \
    __asm__ volatile (".insn r 0x0b, 0b100, 0, %0, x%1, x0" \
                      : "=r"(__rd_val) : "i"(qs)); \
    __rd_val; \
})

/**
 * @brief Write a value from a general-purpose register to a custom q-register.
 * * USAGE: 
 * picorv32_setq(2, 0xDEADBEEF); // Writes 0xDEADBEEF to q2
 * * @param qd The destination q-register index (0, 1, 2, or 3).
 * @param rs The 32-bit value to be written.
 */
#define picorv32_setq(qd, rs) \
    __asm__ volatile (".insn r 0x0b, 0b010, 1, x%0, %1, x0" \
                      : : "i"(qd), "r"(rs))

/**
 * @brief Return from an Interrupt Request (IRQ) handler.
 * * USAGE: 
 * Call this at the end of your ISR to resume normal execution.
 * picorv32_retirq();
 */
static inline void picorv32_retirq(void) {
    __asm__ volatile (".insn r 0x0b, 0, 2, x0, x0, x0");
}

/**
 * @brief Set the interrupt mask and retrieve the previous mask value.
 * * USAGE: 
 * uint32_t old_mask = picorv32_maskirq(0xFFFFFFFF); // Disable all IRQs
 * * @param mask The new interrupt mask (bit set = disabled).
 * @return The previous interrupt mask value.
 */
static inline uint32_t picorv32_maskirq(uint32_t mask) {
    uint32_t old_mask;
    __asm__ volatile (".insn r 0x0b, 0b110, 3, %0, %1, x0" \
                      : "=r"(old_mask) : "r"(mask));
    return old_mask;
}

/**
 * @brief Wait for an interrupt to occur (low-power sleep).
 * * USAGE: 
 * uint32_t pending = picorv32_waitirq(); // Blocks until an IRQ fires
 * * @return The bitmask of pending interrupts that woke the CPU.
 */
static inline uint32_t picorv32_waitirq(void) {
    uint32_t irqs;
    __asm__ volatile (".insn r 0x0b, 0b100, 4, %0, x0, x0" \
                      : "=r"(irqs));
    return irqs;
}

/**
 * @brief Configure or read the internal hardware timer.
 * * USAGE: 
 * picorv32_timer(1000); // Set timer to trigger after 1000 cycles
 * * @param val The timeout value in clock cycles. Set to 0 to disable.
 * @return The previous timer value.
 */
static inline uint32_t picorv32_timer(uint32_t val) {
    uint32_t old_val;
    __asm__ volatile (".insn r 0x0b, 0b110, 5, %0, %1, x0" \
                      : "=r"(old_val) : "r"(val));
    return old_val;
}

#endif // PICORV32_INSTR_H