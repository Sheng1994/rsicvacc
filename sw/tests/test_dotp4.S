.section .text.start
.globl _start
.option norvc

.equ MAILBOX_ADDR, 0x00001000
.equ PASS_VALUE,   0x00000001
.equ FAIL_VALUE,   0x000000ff

_start:
  # Signed bytes: {-1, 2, -3, 4} dot {5, 6, 7, 8} = 18.
  li   x1, 0x04fd02ff
  li   x2, 0x08070605
  .word 0x0020818b  # nn_dotp4 x3, x1, x2
  li   x4, 18
  bne  x3, x4, fail

pass:
  li   x5, MAILBOX_ADDR
  li   x6, PASS_VALUE
  sw   x6, 0(x5)
1: j 1b

fail:
  li   x5, MAILBOX_ADDR
  li   x6, FAIL_VALUE
  sw   x6, 0(x5)
2: j 2b
