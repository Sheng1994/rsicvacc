.section .text.start
.globl _start
.option norvc
.equ MAILBOX, 0x1000

_start:
  # Counters reset to zero.
  .word 0x0200050b  # nn_read_count x10
  .word 0x0200158b  # nn_read_dotp4_count x11
  .word 0x0200260b  # nn_read_requant_count x12
  or x13, x10, x11
  or x13, x13, x12
  bnez x13, fail

  # Configure requant: multiplier=3, shift=1, zero_point=-2.
  li x8, 3
  .word 0x0004500b
  li x8, 1
  .word 0x0004600b
  li x8, -2
  .word 0x0004700b

  li x1, 0x04fd02ff
  li x2, 0x08070605
  .word 0x0020818b  # dotp4 x3,x1,x2 = 18
  li x8, -5
  .word 0x0004120b  # relu x4,x8 = 0 (consecutive NN)
  .word 0x0020828b  # dotp4 x5,x1,x2 = 18 (consecutive NN)
  addi x20, x3, 1  # ordinary instruction mixed between NN groups
  li x21, 19
  bne x20, x21, fail
  bnez x4, fail
  bne x3, x5, fail

  li x8, 5
  .word 0x0004430b  # requant x6,x8 = 6
  add x22, x6, x3
  li x23, 24
  bne x22, x23, fail
  .word 0x0004438b  # requant x7,x8 = 6
  bne x6, x7, fail

  # Five arithmetic NN instructions: 2 DOTP4, 1 RELU, 2 REQUANT.
  .word 0x0200050b
  .word 0x0200158b
  .word 0x0200260b
  li x13, 5
  bne x10, x13, fail
  li x13, 2
  bne x11, x13, fail
  bne x12, x13, fail

  li x24, MAILBOX
  li x25, 1
  sw x25, 0(x24)
1: j 1b
fail:
  li x24, MAILBOX
  li x25, 0xff
  sw x25, 0(x24)
2: j 2b
