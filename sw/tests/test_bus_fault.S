.section .text.start
.globl _start
.option norvc

.equ MAILBOX, 0x1000

_start:
  la t0, fault_handler
  csrw mtvec, t0
  csrwi mscratch, 0
  fence rw, rw

#if defined(TEST_LOAD_NMI)
  li t0, 0x4000
  lw t1, 0(t0)
#elif defined(TEST_STORE_NMI)
  li t0, 0x4004
  sw zero, 0(t0)
#elif defined(TEST_INSTR_FAULT)
  li t0, 0x0280
  jalr zero, 0(t0)
#else
#error Select one bus-fault scenario
#endif

1: nop
   j 1b

.align 7
fault_handler:
  csrr t0, mcause
#if defined(TEST_INSTR_FAULT)
  li t1, 24
  bne t0, t1, bad
  csrr t2, mtval
  bnez t2, bad
#elif defined(TEST_LOAD_NMI)
  li t1, 0x80000400
  bne t0, t1, bad
#elif defined(TEST_STORE_NMI)
  li t1, 0x80000401
  bne t0, t1, bad
#endif
  li t2, MAILBOX
  sw t0, 0(t2)
2: j 2b
bad:
  li t2, MAILBOX
  li t3, 0xdead0001
  sw t3, 0(t2)
3: j 3b
