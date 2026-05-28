    .section .text
    .globl _start

    /*
     * ALL_CNN_C conv1 camera-IFMAP firmware for SoC simulation.
     *
     * This program is intentionally tiny and silent:
     *   - CPU configures video streaming so CNN IFBUF reads are granted to
     *     the camera/video path.
     *   - CPU programs one CNN conv1 layer.
     *   - CNN reads IFMAP from video, reads filter/bias from HyperRAM0,
     *     writes OFMAP to HyperRAM1, then raises IRQ bit 3.
     *   - IRQ handler stores 1 at address 0 and returns EOI.
     */

    .equ IRQ_FLAG_ADDR,        0x00000000

    .equ VIDEO_SCALE_MULT,     0x02008000
    .equ VIDEO_SCALE_SHIFT,    0x02008004
    .equ VIDEO_ZERO_POINT,     0x02008008
    .equ VIDEO_CONTROL,        0x0200800c
    .equ VIDEO_EN_GRANT,       0x00000003
    .equ VIDEO_EN_ONLY,        0x00000001

    .equ HRAM_MODE_ACCEL,      0x00040007
    .equ HRAM0_MODE_ADDR,      0x02005014
    .equ HRAM1_MODE_ADDR,      0x02005114

    .equ CNN_BASE,             0x02009000

    .equ CONV1_IF_H,           32
    .equ CONV1_IF_C,           3
    .equ CONV1_OF_C,           96
    .equ CONV1_K,              3
    .equ CONV1_STRIDE,         1
    .equ CONV1_PAD,            1
    .equ CONV1_IFPARR,         3
    .equ CONV1_OFTILE,         1
    .equ CONV1_OFPARR,         8
    .equ CONV1_IFBADDR,        0x00000000
    .equ CONV1_FLTBADDR,       0x00180000
    .equ CONV1_BIAS_BADDR,     0x00180A20
    .equ CONV1_OFBADDR,        0x00000C00
    .equ CONV1_MULT,           1455152256
    .equ CONV1_SHIFT,          38

_start:
    j       reset_main

    .org 0x10
irq_handler:
    li      t3, IRQ_FLAG_ADDR
    li      t4, 1
    sw      t4, 0(t3)
    .insn r 0x0b, 0, 2, x0, x0, x0      /* retirq */

    .org 0x20
reset_main:
    /* Clear the IRQ flag used by this tiny firmware. */
    sw      zero, IRQ_FLAG_ADDR(zero)

    /* Video path quantization for camera IFMAP: int8 = pixel - 128. */
    li      t0, VIDEO_SCALE_MULT
    li      t1, 1
    sw      t1, 0(t0)

    li      t0, VIDEO_SCALE_SHIFT
    sw      zero, 0(t0)

    li      t0, VIDEO_ZERO_POINT
    li      t1, 0x80
    sw      t1, 0(t0)

    /* Enable video and grant CNN IFBUF reads to the video block. */
    li      t0, VIDEO_CONTROL
    li      t1, VIDEO_EN_GRANT
    sw      t1, 0(t0)

    /* Short warmup window for the video block/frame buffer in simulation. */
    li      t2, 4096
video_warmup:
    addi    t2, t2, -1
    bnez    t2, video_warmup

    /* Set HyperRAM accel mode + DMAC weights on both controllers. */
    li      t0, HRAM0_MODE_ADDR
    li      t1, HRAM_MODE_ACCEL
    sw      t1, 0(t0)

    li      t0, HRAM1_MODE_ADDR
    sw      t1, 0(t0)

    /* Program CNN accelerator registers for ALL_CNN_C conv1. */
    li      t0, CNN_BASE

    li      t1, CONV1_IF_H
    sw      t1, 0x08(t0)         /* ifheight */
    li      t1, CONV1_IF_C
    sw      t1, 0x0c(t0)         /* ifchannel */
    li      t1, CONV1_OF_C
    sw      t1, 0x10(t0)         /* ofchannel */
    li      t1, CONV1_K
    sw      t1, 0x14(t0)         /* hf */
    li      t1, CONV1_STRIDE
    sw      t1, 0x18(t0)         /* stride */
    li      t1, CONV1_PAD
    sw      t1, 0x1c(t0)         /* padding */
    li      t1, CONV1_IFPARR
    sw      t1, 0x20(t0)         /* ifparr */
    li      t1, CONV1_OFTILE
    sw      t1, 0x24(t0)         /* oftile */
    li      t1, CONV1_OFPARR
    sw      t1, 0x28(t0)         /* ofparr */

    li      t1, CONV1_IFBADDR
    sw      t1, 0x2c(t0)         /* ifbaddr: ignored by video grant mux */
    li      t1, CONV1_FLTBADDR
    sw      t1, 0x30(t0)         /* fltbaddr: HyperRAM0 */
    li      t1, CONV1_BIAS_BADDR
    sw      t1, 0x34(t0)         /* bias_baddr: HyperRAM0 */
    li      t1, CONV1_OFBADDR
    sw      t1, 0x38(t0)         /* ofbaddr: HyperRAM1 */

    sw      zero, 0x3c(t0)       /* ifc_zp = 0 */
    sw      zero, 0x40(t0)       /* fltc_zp = 0 */
    li      t1, CONV1_MULT
    sw      t1, 0x44(t0)         /* mult */
    li      t1, CONV1_SHIFT
    sw      t1, 0x48(t0)         /* mult_shift */
    sw      zero, 0x4c(t0)       /* alphamult */
    sw      zero, 0x50(t0)       /* alphamult_shift */
    li      t1, 0x80
    sw      t1, 0x54(t0)         /* zpy = -128 */
    li      t1, 0x80
    sw      t1, 0x58(t0)         /* qmin = -128 */
    li      t1, 0x7f
    sw      t1, 0x5c(t0)         /* qmax = 127 */
    sw      zero, 0x60(t0)       /* is_leaky_relu */

    li      t1, 1
    sw      t1, 0x64(t0)         /* write_fifo: submit instruction table */

poll_accept:
    lw      t2, 0x04(t0)
    andi    t2, t2, 0x1
    bnez    t2, poll_accept

    /* Enable external IRQ bit 3 for CNN done. */
    li      t1, 0xfffffff7
    .insn r 0x0b, 0b110, 3, t2, t1, x0

    li      t1, 1
    sw      t1, 0x00(t0)         /* start accelerator */

wait_irq:
    lw      t1, IRQ_FLAG_ADDR(zero)
    beqz    t1, wait_irq

    /* Release the video grant after conv1 is complete. */
    li      t0, VIDEO_CONTROL
    li      t1, VIDEO_EN_ONLY
    sw      t1, 0(t0)

done_loop:
    j       done_loop
