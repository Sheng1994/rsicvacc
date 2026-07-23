.section .text.start
.globl _start
.option norvc

.equ MAILBOX_ADDR, 0x00001000
.equ PASS_VALUE,   0x00000001
.equ FAIL_VALUE,   0x000000ff

_start:
  li   x1, 1
  li   x2, 2
  add  x3, x1, x2
  li   x4, 3
  bne  x3, x4, fail

  # Verify a taken branch skips the failure path.
  beq  x3, x4, pass
  j    fail

pass:
  li   x5, MAILBOX_ADDR
  li   x6, PASS_VALUE
  sw   x6, 0(x5)
1:
  j    1b

fail:
  li   x5, MAILBOX_ADDR
  li   x6, FAIL_VALUE
  sw   x6, 0(x5)
2:
  j    2b
