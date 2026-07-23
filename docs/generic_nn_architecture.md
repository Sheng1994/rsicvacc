# Generic NN accelerator profile

The default MicroZed profile is a four-output, four-lane signed-INT8 GEMM tile
(16 MAC/cycle). It is intentionally smaller than the XC7Z020 maximum so that
CV32E40X, AXI infrastructure, debugging, and future post-processing retain
timing and area margin.

## General operations

The hardware primitive is `C[M,N] += A[M,K] * B[K,N]` expressed as output-row
groups and K tiles. It directly implements fully connected layers, batched
matrix multiplication, and 1x1 convolution. Standard convolution is supported
after software or hardware im2col; depthwise convolution is functional but is
not yet dataflow-optimized.

`ROWS` and `K_BLOCKS` remain elaboration parameters. Runtime controls select
one through four valid output rows and whether a tile clears or continues the
32-bit accumulator. This handles arbitrary output counts and K dimensions that
are multiples of 16; software pads the final K tile when required.

## FPGA-oriented memory structure

Each ping-pong bank is split into one activation memory and four independent
weight memories. Synchronous read registers feed the 16 multipliers. This avoids
requiring a five-read-port RAM and gives Vivado a legal banked-memory structure
for BRAM inference. The small default depth may still be implemented as FF/LUT
memory at the tool's discretion; only a real Vivado report determines mapping.

## Resource policy

Technology mapping with Yosys for Xilinx 7-series reports 16 DSP48E1 blocks for
the DMA/MMIO array datapath. A future eight-row profile would nominally require
32 multiplier lanes, but it is not the default until Vivado timing and complete
SoC utilization are known. Throughput is scaled first by eliminating software
control and memory stalls, then by increasing `ROWS`.

## Remaining generic-engine work

The next architectural layer is a hardware descriptor walker with independent
activation, weight, bias, and output addresses; automatic bank switching;
strides; final-tile masks; requant/ReLU; and AXI output writeback. The current
software-controlled interface is already correct for arbitrary tiled GEMM, but
does not yet hide all per-tile command overhead.
