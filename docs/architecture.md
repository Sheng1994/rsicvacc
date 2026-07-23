# Architecture status

The selected architecture is a CV32E40X RV32IM_Zicsr Machine Mode CPU with an
independent INT8 NN coprocessor connected through CV-X-IF. Instruction and data
memory use separate, latency-tolerant request/response interfaces. FPGA-facing
BRAM or AXI logic remains outside the CPU and NN cores.

The milestone-4 integration uses these fixed CV-X-IF parameters:

- two 32-bit source operands;
- four-bit transaction ID;
- 32-bit memory, register-read, and register-write widths;
- no coprocessor memory transactions in the initial design.

`rtl/cv32e40x_subsystem.sv` enables XIF and connects a single-entry NN
coprocessor. It accepts DOTP4, waits for the matching commit, discards killed
work, and holds its result until the CPU accepts it. Other encodings are
rejected and retain the core's illegal-instruction behavior.

The subsystem exposes 64-bit NN instruction/DOTP4/REQUANT counters and a
one-cycle commit trace containing transaction ID, operation, kill status, and
captured result. Trace events include accepted arithmetic, configuration, and
counter-read commits, including killed commits, so external verification can
reconstruct protocol activity.

The smoke-test memory implements one-cycle OBI responses and a mailbox at
address `0x00001000`. A separate testbench supplies deterministic random OBI
stalls; bus-error injection remains pending.

## 4-output MAC array

The coprocessor also contains a parameterized `nn_mac_array`, while retaining
all original scalar/SIMD instructions. Its default datapath computes four
outputs in parallel with four signed INT8 multipliers per output: 16 MAC per
active cycle. Local scratchpads hold 16 activations and 4x16 weights; commands
load them, launch computation, poll completion, and read four 32-bit sums.

The current local buffers are loaded explicitly by CPU commands. They provide a
verified compute tile, not a claimed DMA implementation. A later FPGA wrapper
can attach BRAM and AXI/DMA without changing the array datapath.

## AXI DMA and ping-pong mode

`nn_dma_mac_array` provides the Stage B streaming version of the tile. An AXI4
read burst loads a complete 80-byte tile into bank 0 or bank 1. The scheduler
allows a transfer to the inactive bank while the active bank supplies 16 MAC
per cycle to the array. Each bank has an explicit ready bit that is cleared on
compute claim, a new DMA claim, reset, or an AXI/RLAST error.

The buffers use synthesizable inferred arrays so Vivado can map them to BRAM.
The macOS/Yosys tests validate RTL behavior only; actual BRAM inference, AXI
interconnect configuration, Fmax, and Zynq PS memory bandwidth require Vivado.

The simulation SoC maps DMA control registers at `0x0000_f000` and connects
both the CPU OBI memory path and DMA AXI read path to one shared RAM model. This
provides a verified software-to-hardware chain: CV32E40X MMIO configuration,
AXI burst, ping-pong bank fill, MAC execution, status polling, and result read.
