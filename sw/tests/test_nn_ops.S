.section .text.start
.globl _start
.option norvc

.equ MAILBOX_ADDR, 0x00001000

_start:
  # RELU(-5) = 0, RELU(7) = 7
  li x1, -5
  .word 0x0000918b
  bnez x3, fail
  li x1, 7
  .word 0x0000918b
  li x4, 7
  bne x3, x4, fail

  # CLIP8(200) = 127, CLIP8(-200) = -128
  li x1, 200
  .word 0x0000a18b
  li x4, 127
  bne x3, x4, fail
  li x1, -200
  .word 0x0000a18b
  li x4, -128
  bne x3, x4, fail

  # MAX4 over signed bytes {-8, -2, -1, -5} = -1
  li x1, 0xfbfffef8
  .word 0x0000b18b
  li x4, -1
  bne x3, x4, fail

  # Configure multiplier=3, shift=1, zero_point=-2.
  li x1, 3
  .word 0x0000d00b
  li x1, 1
  .word 0x0000e00b
  li x1, -2
  .word 0x0000f00b

  # REQUANT(5) = round_away(15 / 2) - 2 = 6.
  li x1, 5
  .word 0x0000c18b
  li x4, 6
  bne x3, x4, fail

  # Positive saturation: round(100 * 3 / 2) - 2 = 148 -> 127.
  li x1, 100
  .word 0x0000c18b
  li x4, 127
  bne x3, x4, fail

pass:
  li x5, MAILBOX_ADDR
  li x6, 1
  sw x6, 0(x5)
1: j 1b

fail:
  li x5, MAILBOX_ADDR
  li x6, 0xff
  sw x6, 0(x5)
2: j 2b
