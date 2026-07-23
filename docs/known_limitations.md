# Known limitations

## Current

- The NN accelerator supports one in-flight operation. All five arithmetic
  instructions have deterministic Python-reference random-vector coverage.
- REQUANT configuration uses XIF custom configuration instructions because the
  selected CV32E40X release has no generic XIF custom-CSR access channel.
- NN counters are exposed as hardware outputs and low-32-bit custom reads rather
  than standard `csrr` addresses for the same XIF interface limitation. Counter
  overflow/high-half software reads are not implemented yet.
- Optimized C use of a custom counter-read result exposed a CV32E40X register
  visibility/ABI issue even though XIF trace carried the correct value. The FC
  application therefore reports the 64-bit subsystem counter and checks it
  against the expected 20 operations; assembly counter reads remain covered.
- Kill handling, result backpressure stability, in-flight reset, rejected
  encodings, and consecutive transactions have directed protocol tests.
- Only a deterministic one-cycle memory model and a basic add/branch/store
  program were present at milestone 2. Milestone 3 adds directed M-extension,
  CSR, illegal-instruction, ECALL, timer-interrupt, `mret`, and random-latency
  basic-program tests. Bus-error injection and random-latency trap stress remain
  pending.
- An early combined M/trap/random-latency stress program produced unstable
  dependent-DIV/control-flow behavior. The final regression separates these
  concerns and inserts explicit scheduling gaps in directed DIV/REM checks.
  Back-to-back DIV-result consumer coverage remains an open verification item;
  no CPU RTL workaround has been applied.
- Aligned byte/halfword/word accesses and the broad RV32I baseline are covered.
  Directed misaligned-access no-bus-request checks now pass using the official
  PMA I/O-region behavior. Instruction bus faults and load/store bus-error NMIs
  are now injected and checked independently. Data-fault NMIs are intentionally
  treated as unrecoverable, matching the upstream core documentation.
- The upstream CV32E40X RTL emits Verilator warnings in the selected
  configuration. The reference tree is not modified to silence them.
- Yosys checks cover the complete project-owned NN arithmetic datapath;
  stock Yosys does not directly elaborate the complete SystemVerilog-interface
  based CV32E40X integration without an additional frontend.
- FST waveform generation is not enabled yet.
- Vivado 2026.1 synthesis, implementation, DRC, bitstream generation, and XSA
  export pass for the MicroZed XC7Z020 target at 100 MHz. The design has not
  yet been programmed onto physical hardware, so PS DDR initialization, DMA
  coherency, Linux/userspace access, power, and application behavior remain
  unverified on the board.
- The official Avnet MicroZed 7020 v1.4 PS preset emits negative DDR DQS skew
  warnings for lanes 0 and 1. These values come from the board preset and are
  retained; successful physical DDR testing is required before acceptance.
- The current 160-byte ping-pong tile store maps to registers because it is too
  small to use a BRAM efficiently. A larger configurable tile depth still
  needs a dedicated BRAM inference template.
- Implemented DRC has no errors. It reports advisory DSP input/output pipeline
  warnings and generated AXI protocol-converter LUT/no-load warnings with no
  related violations. Timing is met at 100 MHz, but these warnings remain
  documented rather than suppressed.
