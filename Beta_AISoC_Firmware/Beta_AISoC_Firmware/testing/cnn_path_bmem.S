    .section .text
    .globl _start

    .equ UART0_BASE,      0x02002000
    .equ UART_TX_STATUS,  0x04
    .equ UART_DVSR,       0x08
    .equ UART_TX_DATA,    0x0c
    .equ UART_TX_FULL,    0x200
    .equ UART_DVSR_115200, 107

    .equ CNN_BASE,        0x02009000
    .equ IRQ_FLAG_ADDR,   0x00000000

_start:
    j       reset_main

    .org 0x10
irq_handler:
    li      t3, IRQ_FLAG_ADDR
    li      t4, 1
    sw      t4, 0(t3)
    .insn r 0x0b, 0, 2, x0, x0, x0  /* retirq */

    .org 0x20
reset_main:
    /* UART0 debug output for this tiny TB program. */
    li      t0, UART0_BASE
    li      t1, UART_DVSR_115200
    sw      t1, UART_DVSR(t0)
    la      a0, msg_start
    jal     ra, uart_puts

    /* IRQ handler stores 1 here after PicoRV32 accepts accel IRQ bit 3. */
    li      t0, IRQ_FLAG_ADDR
    sw      zero, 0(t0)

    /* Static-image test: make sure video does not own the IFBUF path. */
    li      t0, 0x0200800c
    sw      zero, 0(t0)

    /* Enable accelerator DMAC routing on both HyperRAM controllers.
     * mode[0]      = accel mode enable
     * mode[16:2]   = write/AW arbitration weight = 1
     * mode[31:17]  = read/AR arbitration weight = 2
     * mode[1]      = keep hardware default reserved bit high
     */
    li      t0, 0x02005014
    li      t1, 0x00040007
    sw      t1, 0(t0)

    li      t0, 0x02005114
    sw      t1, 0(t0)

    /* Program CNN conv1 layer registers. */
    li      t0, 0x02009000

    li      t1, 32
    sw      t1, 0x08(t0)     /* ifheight */
    li      t1, 3
    sw      t1, 0x0c(t0)     /* ifchannel */
    li      t1, 96
    sw      t1, 0x10(t0)     /* ofchannel */
    li      t1, 3
    sw      t1, 0x14(t0)     /* hf */
    li      t1, 1
    sw      t1, 0x18(t0)     /* stride */
    li      t1, 1
    sw      t1, 0x1c(t0)     /* padding */
    li      t1, 3
    sw      t1, 0x20(t0)     /* ifparr */
    li      t1, 1
    sw      t1, 0x24(t0)     /* oftile */
    li      t1, 8
    sw      t1, 0x28(t0)     /* ofparr */

    li      t1, 0x00000000
    sw      t1, 0x2c(t0)     /* ifbaddr: HyperRAM1 IFMAP */
    li      t1, 0x00180000
    sw      t1, 0x30(t0)     /* fltbaddr: HyperRAM0 FLT */
    li      t1, 0x00180A20
    sw      t1, 0x34(t0)     /* bias_baddr: HyperRAM0 BIAS */
    li      t1, 0x00000C00
    sw      t1, 0x38(t0)     /* ofbaddr: HyperRAM1 OFMAP */

    li      t1, 0
    sw      t1, 0x3c(t0)     /* ifc_zp */
    li      t1, 0
    sw      t1, 0x40(t0)     /* fltc_zp */
    li      t1, 1455152256
    sw      t1, 0x44(t0)     /* mult */
    li      t1, 38
    sw      t1, 0x48(t0)     /* mult_shift */
    li      t1, 0
    sw      t1, 0x4c(t0)     /* alphamult */
    li      t1, 0
    sw      t1, 0x50(t0)     /* alphamult_shift */
    li      t1, 0x80
    sw      t1, 0x54(t0)     /* zpy = -128 as int8 */
    li      t1, 0x80
    sw      t1, 0x58(t0)     /* qmin = -128 as int8 */
    li      t1, 0x7f
    sw      t1, 0x5c(t0)     /* qmax = 127 */
    li      t1, 0
    sw      t1, 0x60(t0)     /* is_leaky_relu */

    li      t1, 1
    sw      t1, 0x64(t0)     /* write_fifo: submit instruction table */

    li      t2, 256
wait_table_accept:
    addi    t2, t2, -1
    bnez    t2, wait_table_accept

    /* Enable external IRQ bit 3 for the accelerator done interrupt.
     * PicoRV32 uses mask bit 0 = enabled, 1 = disabled.
     */
    li      t1, 0xfffffff7
    .insn r 0x0b, 0b110, 3, t2, t1, x0

    li      t1, 1
    sw      t1, 0x00(t0)     /* start accelerator */

wait_irq_flag:
    li      t3, IRQ_FLAG_ADDR
    lw      t1, 0(t3)
    beqz    t1, wait_irq_flag

    la      a0, msg_irq
    jal     ra, uart_puts

    li      t0, CNN_BASE
    lw      a0, 0x04(t0)     /* final status after EOI cleared done */
    jal     ra, uart_print_hex32

    la      a0, msg_done
    jal     ra, uart_puts

done_loop:
    j       done_loop

uart_putc:
    li      t0, UART0_BASE
uart_putc_wait:
    lw      t1, UART_TX_STATUS(t0)
    andi    t1, t1, UART_TX_FULL
    bnez    t1, uart_putc_wait
    sw      a0, UART_TX_DATA(t0)
    ret

uart_puts:
    li      t0, UART0_BASE
uart_puts_loop:
    lbu     t1, 0(a0)
    beqz    t1, uart_puts_done
uart_puts_wait:
    lw      t2, UART_TX_STATUS(t0)
    andi    t2, t2, UART_TX_FULL
    bnez    t2, uart_puts_wait
    sw      t1, UART_TX_DATA(t0)
    addi    a0, a0, 1
    j       uart_puts_loop
uart_puts_done:
    ret

uart_print_hex32:
    mv      t5, ra
    mv      t3, a0
    li      t4, 8
uart_hex_loop:
    srli    t6, t3, 28
    li      a0, 10
    bltu    t6, a0, uart_hex_digit
    addi    a0, t6, 55      /* 'A' - 10 */
    j       uart_hex_put
uart_hex_digit:
    addi    a0, t6, 48      /* '0' */
uart_hex_put:
    jal     ra, uart_putc
    slli    t3, t3, 4
    addi    t4, t4, -1
    bnez    t4, uart_hex_loop
    mv      ra, t5
    ret

    .align 2
msg_start:
    .asciz "\nCNN\n"
msg_irq:
    .asciz "IRQ S=0x"
msg_done:
    .asciz "\nOK\n"
