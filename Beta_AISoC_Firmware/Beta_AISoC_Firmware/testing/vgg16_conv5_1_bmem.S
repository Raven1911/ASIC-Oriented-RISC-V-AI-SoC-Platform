    .section .text
    .globl _start

    /* ------------------------------------------------------------------ */
    /* VGG16 Conv5_1 – TB-only accelerator test (no UART output)          */
    /* Shape  : 14x14x512 -> 14x14x512, 3x3, stride=1, pad=1             */
    /* Params : ifparr=4  oftile=1  ofparr=6                              */
    /* Addrs  : real layer-11 pipeline addresses from vgg16_accel.c       */
    /*   ifbaddr    = 0x0085FC00 (HR1 – activation input)                 */
    /*   fltbaddr   = 0x0074A0C0 (HR0 – filter weights)                   */
    /*   bias_baddr = 0x0098A0C0 (HR0 – bias)                             */
    /*   ofbaddr    = 0x00878400 (HR1 – activation output)                */
    /* Quant  : timing-only, all zero except qmin=-128/qmax=127           */
    /* ------------------------------------------------------------------ */

    .equ CNN_BASE,        0x02009000
    .equ IRQ_FLAG_ADDR,   0x00000000   /* irq_handler writes 1 here */

    .equ HRAM_MODE_ACCEL, 0x00040007   /* accel_en | aw_w=1 | ar_w=2 */
    .equ HRAM0_MODE_ADDR, 0x02005014
    .equ HRAM1_MODE_ADDR, 0x02005114
    .equ VIDEO_GRANT_ADDR,0x0200800c

_start:
    j       reset_main

    /* ---- IRQ vector at 0x10 ----------------------------------------- */
    .org 0x10
irq_handler:
    li      t3, IRQ_FLAG_ADDR
    li      t4, 1
    sw      t4, 0(t3)                          /* set IRQ flag */
    .insn r 0x0b, 0, 2, x0, x0, x0            /* retirq */

    /* ---- Main at 0x20 ----------------------------------------------- */
    .org 0x20
reset_main:
    /* Clear IRQ flag */
    sw      zero, IRQ_FLAG_ADDR(zero)

    /* Disable video streaming grant */
    li      t0, VIDEO_GRANT_ADDR
    sw      zero, 0(t0)

    /* Set HyperRAM accel mode + DMAC weights on both controllers */
    li      t0, HRAM0_MODE_ADDR
    li      t1, HRAM_MODE_ACCEL
    sw      t1, 0(t0)
    li      t0, HRAM1_MODE_ADDR
    sw      t1, 0(t0)

    /* ---- Program CNN accelerator registers -------------------------- */
    li      t0, CNN_BASE

    li      t1, 14
    sw      t1, 0x08(t0)           /* ifheight  = 14      */
    li      t1, 512
    sw      t1, 0x0c(t0)           /* ifchannel = 512     */
    li      t1, 512
    sw      t1, 0x10(t0)           /* ofchannel = 512     */
    li      t1, 3
    sw      t1, 0x14(t0)           /* hf        = 3       */
    li      t1, 1
    sw      t1, 0x18(t0)           /* stride    = 1       */
    li      t1, 1
    sw      t1, 0x1c(t0)           /* padding   = 1       */
    li      t1, 4
    sw      t1, 0x20(t0)           /* ifparr    = 4       */
    li      t1, 1
    sw      t1, 0x24(t0)           /* oftile    = 1       */
    li      t1, 6
    sw      t1, 0x28(t0)           /* ofparr    = 6       */

    li      t1, 0x0085FC00
    sw      t1,  0x2c(t0)          /* ifbaddr   = 0x0085FC00 */
    li      t1, 0x0074A0C0
    sw      t1,  0x30(t0)          /* fltbaddr  = 0x0074A0C0 */
    li      t1, 0x0098A0C0
    sw      t1,  0x34(t0)          /* bias_baddr= 0x0098A0C0 */
    li      t1, 0x00878400
    sw      t1,  0x38(t0)          /* ofbaddr   = 0x00878400 */

    /* Quantization (timing-only: zeros, qmin=-128, qmax=127) */
    sw      zero, 0x3c(t0)         /* ifc_zp         = 0  */
    sw      zero, 0x40(t0)         /* fltc_zp        = 0  */
    sw      zero, 0x44(t0)         /* mult           = 0  */
    sw      zero, 0x48(t0)         /* mult_shift     = 0  */
    sw      zero, 0x4c(t0)         /* alphamult      = 0  */
    sw      zero, 0x50(t0)         /* alphamult_shift= 0  */
    sw      zero, 0x54(t0)         /* zpy            = 0  */
    li      t1, 0x80
    sw      t1,  0x58(t0)          /* qmin = -128 (0x80)  */
    li      t1, 0x7f
    sw      t1,  0x5c(t0)          /* qmax = 127          */
    sw      zero, 0x60(t0)         /* is_leaky_relu  = 0  */

    /* Submit instruction table */
    li      t1, 1
    sw      t1, 0x64(t0)           /* write_fifo          */

    /* Wait until TABLE_VALID clears (table accepted by accel) */
poll_accept:
    lw      t2, 0x04(t0)
    andi    t2, t2, 0x1
    bnez    t2, poll_accept

    /* Enable external IRQ bit 3 (CNN done) */
    li      t1, 0xfffffff7
    .insn r 0x0b, 0b110, 3, t2, t1, x0    /* PicoRV32 setq */

    /* Start accelerator */
    li      t1, 1
    sw      t1, 0x00(t0)

    /* Spin until IRQ handler sets flag at address 0 */
wait_irq:
    lw      t1, IRQ_FLAG_ADDR(zero)
    beqz    t1, wait_irq

    /* IRQ handler has already executed retirq here, so CPU EOI has pulsed.
     * Keep the CPU running for a short, deterministic window before halting
     * so the EOI pulse is easy to see in the waveform.
     */
    li      t2, 1024
post_eoi_delay:
    addi    t2, t2, -1
    bnez    t2, post_eoi_delay

    /* Done – halt in loop after EOI has been returned. */
done_loop:
    j       done_loop
