/*
 * startup.s - RISC-V Startup Code with PicoRV32 IRQ vector.
 * Reset vector is placed at PROGADDR_RESET, IRQ vector at PROGADDR_IRQ.
 */

.section .vectors, "ax"
.global _vectors

_vectors:
    /* 0x00: CPU reset enters here, then jumps to normal C runtime init. */
    j _start

    /* 0x10: PicoRV32 jumps here on IRQ when PROGADDR_IRQ = RESET + 0x10. */
    .org 0x10
    j irq_wrapper

.align 4
irq_wrapper:
    /*
     * Save caller-saved registers plus ra. This matches CPU_Context_t in
     * Interrupt_Driver.h, so irq_central_dispatcher() can read q0/q1 context.
     */
    addi sp, sp, -80

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
    sw ra,  60(sp)

    /*
     * PicoRV32 q0 = interrupted PC, q1 = pending IRQ bitmask.
     * .insn r opcode, funct3, funct7, rd, rs1, rs2
     */
    .insn r 0x0b, 0b100, 0, t0, x0, x0
    sw t0, 64(sp)

    .insn r 0x0b, 0b100, 0, t0, x1, x0
    sw t0, 68(sp)

    mv a0, sp
    .extern irq_central_dispatcher
    call irq_central_dispatcher

    /* Restore interrupted PC back to q0 before retirq. */
    lw t0, 64(sp)
    .insn r 0x0b, 0b010, 1, x0, t0, x0

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

    addi sp, sp, 80

    /* PicoRV32 retirq custom instruction. */
    .insn r 0x0b, 0, 2, x0, x0, x0

.section .text.entry
.global _start

/* Declare external symbols provided by the Linker Script */
.extern _estack             /* Top of the Stack (End of RAM) */
.extern __global_pointer$   /* Global Pointer */

/* Declare external functions */
.extern main
.weak SystemInit            /* Allow linking even if SystemInit is missing */

_start:

    .option push
    .option norelax
    la gp, __global_pointer$
    .option pop

    /* --------------------------------------------------------------------------
     * 3. Initialize Stack Pointer (sp)
     * Load the address defined in the .stack section of the linker script.
     * -------------------------------------------------------------------------- */
    la sp, _estack

    /* --------------------------------------------------------------------------
     * 4. Call SystemInit
     * Initialize clocks, watchdogs, and the trap vector table.
     * -------------------------------------------------------------------------- */
    /* call SystemInit */

    /* --------------------------------------------------------------------------
     * 5. DMEM initialization is owned by the bootloader.
     * The segmented boot image loads .data directly to DMEM and zeroes .bss
     * before jumping here, avoiding duplicated .data storage in IMEM.
     * -------------------------------------------------------------------------- */

    /* --------------------------------------------------------------------------
     * 6. Jump to Main
     * -------------------------------------------------------------------------- */
call_main:
    /*
     * Start app with all IRQ sources masked. Application code should call
     * IRQ_Init(), attach handlers, then enable selected IRQ bits.
     */
    li t0, -1
    .insn r 0x0b, 0b110, 3, x0, t0, x0

    jal ra, main

    /* --------------------------------------------------------------------------
     * 8. Loop Forever
     * If main() returns (which shouldn't happen), loop indefinitely.
     * -------------------------------------------------------------------------- */
loop_forever:
    j loop_forever

/*
 * Stub for SystemInit in case the user hasn't defined it in C.
 */
SystemInit_Stub:
    ret
    
