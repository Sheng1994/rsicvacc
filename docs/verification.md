# Verification strategy

Verification will be added incrementally with the implementation:

1. Verilator lint and module-level cocotb/pytest tests.
2. Python reference models for signed INT8 operations and requantization.
3. Program-level RV32 bare-metal tests with randomized memory latency.
4. Protocol assertions, timeouts, trace output, and FST waveforms.
5. Yosys read/synthesis checks for relevant vendor-independent top levels.

Implemented program-level tests now include:

- RV32I add, taken/not-taken branch flow, and mailbox store;
- directed MUL, DIV, REM, divide-by-zero, and signed-overflow cases;
- `mscratch` CSR read/write/set/clear operations;
- illegal-instruction and M-mode ECALL exceptions with `mepc` advancement;
- Machine Timer interrupt entry, `mcause` checking, and `mret`;
- deterministic pseudo-random instruction/data grant and response latency on
  the basic program.
- end-to-end CV-X-IF `NN_DOTP4` issue, commit, result, and register writeback.
- directed end-to-end RELU, CLIP8, MAX4, and REQUANT tests, including signed
  values, saturation, configuration ordering, and rounding.
- C runtime startup, initialized data, BSS clearing, PASS reporting, and
  propagation of an expected nonzero status through the mailbox.
- RV32I logical operations, signed/unsigned shifts and comparisons, JAL link,
  odd-address JALR bit-zero clearing, x0 immutability, byte/halfword/word
  accesses with sign extension, and minstret advancement.
- PMA-contained misaligned word load/store faults, including an external OBI
  monitor proving that the offending accesses are not issued to the data bus.
- instruction bus fault (`mcause=24`, `mtval=0`) and independent imprecise load
  and store NMI signatures (`0x80000400` and `0x80000401`).

Implemented NN module/protocol tests include:

- 5,000 deterministic Python-reference vectors: 1,000 each for DOTP4, RELU,
  CLIP8, MAX4, and REQUANT;
- REQUANT midpoint rounding in both sign directions and shifts 0 through 31;
- illegal funct7 and wrong commit-ID rejection;
- commit kill with no result and killed configuration with no state change;
- seven-cycle result backpressure with stable valid, ID, and data;
- reset during WAIT_COMMIT and SEND_RESULT with no post-reset response;
- 64 consecutive transactions with changing IDs, destinations, and operands.
- commit-level counter checks across kill, reset, configuration, REQUANT, and
  64 DOTP4 transactions;
- CPU execution of consecutive and mixed NN/RV32 instructions, software reads
  of all three counters, and external trace-event accounting.
- a 16x4 INT8 fully connected application with independent Python outputs,
  software and NN implementations, bias/requantization, cycle/minstret
  measurement, and a hardware count of 20 arithmetic NN instructions.

The M-extension and trap tests use the deterministic single-cycle memory model
so failures can be attributed independently. Broader random-latency privileged
stress and bus-error injection remain future work.
## MNIST application

The MNIST regression regenerates a deterministic INT8 784x10 classifier,
checks its full 10,000-image Python accuracy, then loads one official test image
and 7,840 weights into shared simulation RAM. CV32E40X scalar inference and 147
MMIO/AXI DMA array tiles must produce identical ten-class scores and predict the
expected digit 7. Cross-tile accumulation keeps 49 partial tiles in hardware,
and active-row masking makes the MAC counter report exactly 7,840 useful MACs.
