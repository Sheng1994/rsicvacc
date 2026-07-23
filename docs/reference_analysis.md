# Reference analysis

## CV32E40X baseline

- Upstream: `https://github.com/openhwgroup/cv32e40x.git`
- Fixed tag: `0.10.0`
- Commit: `18c88fd78a37f270c8301c552f5fd0f564d0ab20`
- Local location: `references/cv32e40x`
- License: Solderpad Hardware License 0.51 in the upstream `LICENSE` file;
  individual newer files may state Solderpad Hardware License 2.0.

The reference tree is an unmodified shallow clone at a detached tagged commit.
Project-owned integration logic lives under `rtl/`, never inside the reference
tree.

## Relevant architecture

CV32E40X is a four-stage, in-order RV32 core. The selected configuration uses
RV32I, the M extension, Zicsr, basic Machine-mode interrupts, and CORE-V-XIF.
Atomic, bit-manipulation, CLIC, and debug features are disabled in the project
wrapper.

The core exposes separate instruction and data OBI ports. Instruction fetch
may have more than one outstanding request, so future randomized memory models
must preserve response ordering and must not assume the core waits for each
response before issuing the next request.

CORE-V-XIF is integrated through SystemVerilog interfaces for compressed,
issue, commit, memory, memory-result, and result channels. This project will
initially use only issue, commit, and result for register-register NN
instructions. All interface width parameters are defined once in the subsystem
wrapper and shared by the core, interface instance, and coprocessor.

## Clock gating

Upstream provides a simulation-only clock gate but requires integrators to
provide a technology-specific implementation for synthesis. The project uses
a vendor-independent latch-and-AND model in `rtl/cv32e40x_clock_gate.sv` for
Stage A. Any later FPGA replacement stays in the FPGA adapter layer.

## Other requested references

The guidance also names xif_copro, X-HEEP, CFU Playground, Ibex, and
riscv-formal. Those trees have not been imported because the current milestone
does not require them and the architecture explicitly prohibits assembling a
CPU from multiple implementations. If inspected later, they remain read-only
and are used only for interface or verification comparisons.
