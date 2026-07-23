.section .text.start
.globl _start
.option norvc

.equ MAILBOX, 0x00001000
.macro FAIL code
  li t0, MAILBOX
  li t1, \code
  sw t1, 0(t0)
1: j 1b
.endm

_start:
  li t0, -7
  li t1, 3
  mul t2, t0, t1
  nop
  li t3, -21
  bne t2, t3, fail_mul

  div t2, t0, t1
  nop
  li t3, -2
  bne t2, t3, fail_div

  rem t2, t0, t1
  nop
  li t3, -1
  bne t2, t3, fail_rem

  div t2, t0, zero
  nop
  li t3, -1
  bne t2, t3, fail_div_zero

  li t0, 0x80000000
  li t1, -1
  div t2, t0, t1
  nop
  nop
  bne t2, t0, fail_div_overflow
  rem t2, t0, t1
  nop
  nop
  bnez t2, fail_rem_overflow

  li t0, MAILBOX
  li t1, 1
  sw t1, 0(t0)
2: j 2b

fail_mul:          FAIL 0x20
fail_div:          FAIL 0x21
fail_rem:          FAIL 0x22
fail_div_zero:     FAIL 0x23
fail_div_overflow: FAIL 0x24
fail_rem_overflow: FAIL 0x25
