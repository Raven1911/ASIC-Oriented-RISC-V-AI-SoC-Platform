/*
 * @file startup.S
 * @brief Professional RISC-V Startup Code and IRQ Wrapper for PicoRV32.
 * * SUMMARY:
 * This file handles the initial boot sequence (data/bss initialization) 
 * and provides a robust, ABI-compliant hardware interrupt wrapper that 
 * safely transitions execution to the C-level central dispatcher.
 */

#include "./Interrupt/custom_ops.S"

/* ========================================================================= */
/* VECTOR TABLE                                                              */
/* ========================================================================= */
.section .vectors, "ax"
.global _vectors

_vectors:
    /* 0x00: Reset Vector - Jump to early boot sequence */
    j _start            
    
    /* 0x10: Interrupt Vector - Hardware jumps here on IRQ */
    .org 0x10           
    j irq_wrapper

/* ========================================================================= */
/* HARDWARE INTERRUPT WRAPPER                                                */
/* ========================================================================= */
.align 4
irq_wrapper:
    /* * 1. Allocate Stack Frame
     * Reserve 80 bytes on the stack. 80 is divisible by 16, ensuring strict 
     * compliance with the RISC-V ABI for 16-byte stack alignment.
     */
    addi sp, sp, -80

    /* * 2. Save Caller-Saved Registers & Return Address
     * We must save all registers that C functions are allowed to modify.
     * We also save 'ra' (Return Address) directly to the stack.
     */
    sw t0,   0(sp)
    sw t1,   4(sp)
    sw t2,   8(sp)
    sw a0,  12(sp)
    sw a1,  16(sp)
    sw a2,  20(sp)
    sw a3,  24(sp)
    sw a4,  28(sp)
    sw a5,  32(sp)
    sw a6,  36(sp)
    sw a7,  40(sp)
    sw t3,  44(sp)
    sw t4,  48(sp)
    sw t5,  52(sp)
    sw t6,  56(sp)
    sw ra,  60(sp) /* Storing x1 (ra) directly */

    /* * 3. Save PicoRV32 Specific Context (EPC and IRQ Source)
     * - q0 holds the Exception Program Counter (EPC) where the IRQ occurred.
     * - q1 holds the pending IRQ bitmask.
     * Saving these to the stack prevents corruption if nested interrupts 
     * occur or if the C code modifies them.
     */
    picorv32_getq_insn(t0, q0)
    sw t0, 64(sp)
    
    picorv32_getq_insn(t0, q1)
    sw t0, 68(sp)
    
    /* Note: 72(sp) and 76(sp) are left unused as padding for 16-byte alignment */

    /* * 4. Pass Context to C Dispatcher
     * Move the current stack pointer into a0. This passes a pointer to our 
     * saved registers as the first argument to the C function.
     */
    mv a0, sp
    
    /* * 5. Call Central Dispatcher
     * Use 'call' (auipc + jalr) instead of 'jal' to prevent relocation errors 
     * if the firmware grows larger than 1MB.
     */
    .extern irq_central_dispatcher
    call irq_central_dispatcher

    /* * 6. Restore PicoRV32 Specific Context
     * Restore the Return PC to q0 safely from the stack.
     */
    lw t0, 64(sp)
    picorv32_setq_insn(q0, t0)

    /* * 7. Restore Caller-Saved Registers & Return Address
     */
    lw t0,   0(sp)
    lw t1,   4(sp)
    lw t2,   8(sp)
    lw a0,  12(sp)
    lw a1,  16(sp)
    lw a2,  20(sp)
    lw a3,  24(sp)
    lw a4,  28(sp)
    lw a5,  32(sp)
    lw a6,  36(sp)
    lw a7,  40(sp)
    lw t3,  44(sp)
    lw t4,  48(sp)
    lw t5,  52(sp)
    lw t6,  56(sp)
    lw ra,  60(sp)

    /* * 8. Free Stack Frame and Return
     */
    addi sp, sp, 80
    picorv32_retirq_insn()

/*
 * Bootloader normally keeps all IRQ sources masked. This weak fallback keeps the
 * IRQ wrapper linkable without pulling the full interrupt HAL into the boot
 * image. If a real dispatcher is linked, it overrides this stub.
 */
.weak irq_central_dispatcher
irq_central_dispatcher:
    ret

/* ========================================================================= */
/* RESET HANDLER & C-RUNTIME INITIALIZATION                                  */
/* ========================================================================= */
.section .text.entry
.global _start
_start:
    /* 1. Initialize Stack Pointer (Address defined in linker script) */
    la sp, _estack

    /* 2. Initialize Global Pointer (Crucial for C global variable access) */
    .option push
    .option norelax
    la gp, __global_pointer$
    .option pop

    /* 3. Copy Initialized Data from Flash to RAM (.data section) */
    la a0, _sdata
    la a1, _edata
    la a2, _sidata
    bge a0, a1, zero_bss_start
copy_data_loop:
    lw t0, 0(a2)
    sw t0, 0(a0)
    addi a0, a0, 4
    addi a2, a2, 4
    blt a0, a1, copy_data_loop

zero_bss_start:
    /* 4. Zero out the Uninitialized Data segment (.bss section) */
    la a0, _sbss
    la a1, _ebss
    bge a0, a1, call_main
fill_bss_loop:
    sw zero, 0(a0)
    addi a0, a0, 4
    blt a0, a1, fill_bss_loop

call_main:
    /* * 5. Disable all interrupts before jumping to main.
     * Setting the mask to 0xFFFFFFFF (-1) disables everything on PicoRV32.
     */
    li t0, -1
    picorv32_maskirq_insn(zero, t0)
    
    /* 6. Jump to C Application */
    call main

loop_forever:
    /* 7. Safety trap if main() ever returns */
    j loop_forever
