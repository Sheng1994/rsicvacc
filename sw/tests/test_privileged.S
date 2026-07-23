.section .text.start
.globl _start
.option norvc

.equ MAILBOX,      0x00001000
.equ IRQ_ACK,      0x00001004
.equ ILLEGAL_SEEN, 0x00001008
.equ ECALL_SEEN,   0x0000100c
.equ IRQ_SEEN,     0x00001010
.equ IRQ_ARM,      0x00001014

.macro FAIL code
  li   t0, MAILBOX
  li   t1, \code
  sw   t1, 0(t0)
99:
  j    99b
.endm

_start:
  # Install a direct-mode Machine trap vector.
  la   t0, trap_handler
  csrw mtvec, t0

  # CSR read/write, set, and clear behavior using mscratch.
  li   t0, 0x12345000
  csrw mscratch, t0
  csrr t1, mscratch
  bne  t0, t1, fail_csr_rw
  li   t2, 0x0000000f
  csrs mscratch, t2
  csrr t1, mscratch
  li   t3, 0x1234500f
  bne  t1, t3, fail_csr_set
  li   t2, 0x0000000c
  csrc mscratch, t2
  csrr t1, mscratch
  li   t3, 0x12345003
  bne  t1, t3, fail_csr_clear
  csrw mscratch, zero

  # Illegal instruction must trap, skip exactly one 32-bit instruction,
  # and return through mret.
  .word 0xffffffff
after_illegal:
  csrr t1, mscratch
  li   t2, 1
  bne  t1, t2, fail_illegal

  # A custom-0 instruction with reserved nonzero funct7 must also be illegal.
  csrw mscratch, zero
  .word 0x0620818b
after_illegal_custom:
  csrr t1, mscratch
  li   t2, 1
  bne  t1, t2, fail_illegal

  # ECALL from M-mode must report cause 11 and resume after the ECALL.
  ecall
after_ecall:
  csrr t1, mscratch
  li   t2, 2
  bne  t1, t2, fail_ecall

  # Ask the testbench to raise a level-sensitive Machine Timer interrupt.
  li   t0, IRQ_ARM
  li   t1, 1
  sw   t1, 0(t0)
  li   t1, (1 << 7)
  csrs mie, t1
  li   t1, (1 << 3)
  csrs mstatus, t1

wait_irq:
  csrr t1, mscratch
  li   t2, 3
  bne  t1, t2, wait_irq

  csrci mstatus, 8
  li   t0, MAILBOX
  li   t1, 1
  sw   t1, 0(t0)
done:
  j    done

fail_csr_rw:       FAIL 0x10
fail_csr_set:      FAIL 0x11
fail_csr_clear:    FAIL 0x12
fail_illegal:      FAIL 0x30
fail_ecall:        FAIL 0x31

.align 7
trap_handler:
  csrr t0, mcause
  bltz t0, trap_interrupt

  li   t1, 2
  beq  t0, t1, trap_illegal
  li   t1, 11
  beq  t0, t1, trap_ecall
  FAIL 0x40

trap_illegal:
  li   t1, 1
  csrw mscratch, t1
  j    trap_skip

trap_ecall:
  li   t1, 2
  csrw mscratch, t1

trap_skip:
  fence rw, rw
  csrr t0, mepc
  addi t0, t0, 4
  csrw mepc, t0
  mret

trap_interrupt:
  li   t1, 0x80000007
  bne  t0, t1, trap_bad_irq
  li   t1, 3
  csrw mscratch, t1
  mret

trap_bad_irq:
  FAIL 0x41
