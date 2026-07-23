.section .text.start
.globl _start
.option norvc

.equ MAILBOX,       0x1000
.equ MONITOR_ARM,   0x1020
.equ MONITOR_STOP,  0x1024
.equ MISALIGN_ADDR, 0x1101
.equ BUS_LOAD_ADDR, 0x4000
.equ BUS_STORE_ADDR,0x4004
.equ IFETCH_ADDR,   0x0280

.macro EXPECT cause, address, recovery
  li s0, \cause
  li s1, \address
  la s3, \recovery
.endm

_start:
  la t0, trap_handler
  csrw mtvec, t0
  li s2, 0

  # Misaligned load must trap without issuing a data OBI request.
  EXPECT 5, 0, after_misaligned_load
  li t0, MONITOR_ARM
  sw s0, 0(t0)
  li t0, MISALIGN_ADDR
  lw t1, 0(t0)
  j fail_no_trap
after_misaligned_load:

  # Misaligned store must also be contained before the bus.
  EXPECT 7, 0, after_misaligned_store
  li t0, MONITOR_ARM
  sw s0, 0(t0)
  li t0, MISALIGN_ADDR
  sw t1, 0(t0)
  j fail_no_trap
after_misaligned_store:
  li t0, 2
  bne s2, t0, fail_bad_count
  li t0, MAILBOX
  li t1, 1
  sw t1, 0(t0)
misaligned_done:
  j misaligned_done

  # Retained for a future dedicated fault/NMI testbench; unreachable here.

  # Testbench injects errors for these aligned data transactions.
  EXPECT 5, BUS_LOAD_ADDR, after_load_fault
  li t0, BUS_LOAD_ADDR
  lw t1, 0(t0)
  j fail_no_trap
after_load_fault:

  EXPECT 7, BUS_STORE_ADDR, after_store_fault
  li t0, BUS_STORE_ADDR
  sw zero, 0(t0)
  j fail_no_trap
after_store_fault:

  # Instruction response at IFETCH_ADDR is returned with err=1.
  EXPECT 1, IFETCH_ADDR, after_instr_fault
  li t0, IFETCH_ADDR
  jalr zero, 0(t0)
  j fail_no_trap
after_instr_fault:
  li t0, 5
  bne s2, t0, fail_bad_count
  li t0, MAILBOX
  li t1, 1
  sw t1, 0(t0)
1: j 1b

fail_no_trap:
  li t2, 0x51
  j fail
fail_bad_count:
  li t2, 0x52
fail:
  li t0, MAILBOX
  sw t2, 0(t0)
2: j 2b

.align 7
trap_handler:
  csrr t0, mcause
  bne t0, s0, trap_bad_cause
  csrr t0, mtval
  bne t0, s1, trap_bad_tval
  addi s2, s2, 1

  # Stop the external no-request monitor after misalignment traps.
  li t0, 5
  beq s0, t0, trap_stop_monitor
  li t0, 7
  beq s0, t0, trap_stop_monitor
  csrw mepc, s3
  mret

trap_stop_monitor:
  li t0, MONITOR_STOP
  sw zero, 0(t0)
  csrw mepc, s3
  mret

trap_bad_cause:
  li t2, 0x53
  j fail
trap_bad_tval:
  li t2, 0x54
  j fail
