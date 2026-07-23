.section .text.start
.globl _start
.option norvc

.equ MAILBOX_ADDR, 0x1000
.equ SCRATCH_ADDR, 0x0300

_start:
  # x0 must ignore writes.
  li x1, 123
  addi x0, x1, 7
  bnez x0, fail

  # Arithmetic and logical operations.
  li x1, 0x55aa00ff
  li x2, 0x0f0ff0f0
  and x3, x1, x2
  li x4, 0x050a00f0
  bne x3, x4, fail
  or x3, x1, x2
  li x4, 0x5faff0ff
  bne x3, x4, fail
  xor x3, x1, x2
  li x4, 0x5aa5f00f
  bne x3, x4, fail

  li x1, -8
  srai x3, x1, 2
  li x4, -2
  bne x3, x4, fail
  srli x3, x1, 28
  li x4, 15
  bne x3, x4, fail
  li x1, 1
  slli x3, x1, 31
  li x4, 0x80000000
  bne x3, x4, fail
  slt x3, x4, x1
  li x5, 1
  bne x3, x5, fail
  sltu x3, x4, x1
  bnez x3, fail

  # JAL must set the link register and skip the failure branch.
  jal x6, jal_target
  j fail
jal_target:
  la x7, jal_target
  addi x7, x7, -4
  bne x6, x7, fail

  # JALR must clear target address bit zero.
  la x8, jalr_target
  ori x8, x8, 1
  jalr x9, 0(x8)
  j fail
jalr_target:
  andi x10, x8, 1
  beqz x10, fail       # Ensure the supplied address really was odd.

  # Byte, halfword and word stores/loads with sign and zero extension.
  li x11, SCRATCH_ADDR
  li x12, 0x80ff7f01
  sw x12, 0(x11)
  lb x13, 2(x11)
  li x14, -1
  bne x13, x14, fail
  lbu x13, 2(x11)
  li x14, 255
  bne x13, x14, fail
  lh x13, 2(x11)
  li x14, 0xffff80ff
  bne x13, x14, fail
  lhu x13, 2(x11)
  li x14, 0x80ff
  bne x13, x14, fail

  li x15, 0xaa
  sb x15, 1(x11)
  lbu x13, 1(x11)
  bne x13, x15, fail
  li x15, 0x1234
  sh x15, 2(x11)
  lhu x13, 2(x11)
  bne x13, x15, fail

  # minstret must advance across successfully retired instructions.
  csrr x16, minstret
  nop
  nop
  nop
  nop
  csrr x17, minstret
  sub x18, x17, x16
  li x19, 4
  bltu x18, x19, fail

pass:
  li x20, MAILBOX_ADDR
  li x21, 1
  sw x21, 0(x20)
1: j 1b

fail:
  li x20, MAILBOX_ADDR
  li x21, 0xff
  sw x21, 0(x20)
2: j 2b
