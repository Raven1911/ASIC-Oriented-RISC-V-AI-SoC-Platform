/*
 * startup.s - RISC-V Startup Code
 * Compatible with the "Safe" Linker Script containing .stack and NOLOAD sections.
 */

.section .text.entry
.global _start

/* Declare external symbols provided by the Linker Script */
.extern _estack             /* Top of the Stack (End of RAM) */
.extern __global_pointer$   /* Global Pointer */
.extern _sidata             /* Start of data in Flash (LMA) */
.extern _sdata              /* Start of data in RAM (VMA) */
.extern _edata              /* End of data in RAM */
.extern _sbss               /* Start of BSS in RAM */
.extern _ebss               /* End of BSS in RAM */

/* Declare external functions */
.extern main
.weak SystemInit            /* Allow linking even if SystemInit is missing */

_start:

/* .option push
.option norelax
    la gp, __global_pointer$
.option pop */

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
     * 5. Copy Data Section (Flash -> RAM)
     * Copy initialized global variables from LMA (_sidata) to VMA (_sdata).
     * -------------------------------------------------------------------------- */
    la a0, _sdata       /* a0 = Destination Start (RAM) */
    la a1, _edata       /* a1 = Destination End (RAM) */
    la a2, _sidata      /* a2 = Source Start (Flash) */

    /* Check if data section is empty */
    bge a0, a1, zero_bss_loop

copy_data_loop:
    lw t0, 0(a2)        /* Load word from Flash */
    sw t0, 0(a0)        /* Store word to RAM */
    addi a0, a0, 4      /* Increment destination pointer */
    addi a2, a2, 4      /* Increment source pointer */
    blt a0, a1, copy_data_loop

    /* --------------------------------------------------------------------------
     * 6. Zero BSS Section
     * Initialize uninitialized global variables to 0.
     * -------------------------------------------------------------------------- */
zero_bss_loop:
    la a0, _sbss        /* a0 = BSS Start */
    la a1, _ebss        /* a1 = BSS End */

    /* Check if BSS section is empty */
    bge a0, a1, call_main

fill_bss_loop:
    sw zero, 0(a0)      /* Write 0 to RAM */
    addi a0, a0, 4      /* Increment pointer */
    blt a0, a1, fill_bss_loop

    /* --------------------------------------------------------------------------
     * 7. Jump to Main
     * -------------------------------------------------------------------------- */
call_main:
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
    