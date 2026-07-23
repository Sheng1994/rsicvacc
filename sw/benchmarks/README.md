# Benchmarks

`fc16x4.c` implements a complete 16-input, four-output INT8 fully connected
layer. It executes a conventional RV32IM multiply/accumulate loop and an
accelerated path using 16 NN_DOTP4 plus four NN_REQUANT instructions. Both
paths include bias and identical requantization and are checked against the
independent Python output `[16, -4, 5, -2]`.

| Path | Cycles | Retired instructions |
|---|---:|---:|
| RV32IM software | 671 | 529 |
| NN coprocessor | 458 | 382 |

This is a measured 1.47x cycle ratio and 1.38x retired-instruction ratio. The
hardware counter reports exactly 20 arithmetic NN instructions. These are
deterministic RTL simulation measurements, not FPGA timing or board results.

## MAC-array FC16x4

`fc16x4_array.c` runs the same layer on the four-output array. It loads 16
activations and 64 weights into local buffers, launches one tile, verifies all
raw sums, adds bias, requantizes, and checks packed output `fe05fc10`.

RTL simulation confirms 64 MACs in four compute cycles (16 MAC/cycle). The
complete CPU-driven application takes 518 simulation cycles including buffer
loads, polling, reads, software bias/requant, and mailbox reporting. This is not
an FPGA timing measurement.

## Reproducible comparison

Run `make benchmark RISCV_PREFIX=riscv64-elf-`. It reports the RV32IM software
path, DOTP4/REQUANT path, CPU-command-loaded array path, and the standalone AXI
DMA ping-pong pipeline, followed by the MMIO-controlled CPU/DMA end-to-end case.
The standalone DMA microbenchmark remains separate from application timing.

`fc16x4_dma.c` is the full end-to-end case. The CV32E40X builds the tile in
shared RAM, programs MMIO at `0xf000`, waits for AXI DMA and array completion,
reads four accumulators, applies bias/requant, and checks the same output. With
deterministic AXI stalls the measured result is 673 software cycles versus 179
DMA-array cycles, or 3.75x. Both numbers are measured inside the same RV32
program; they remain RTL-simulation results rather than FPGA timing claims.

## MNIST INT8 inference

`scripts/prepare_mnist.py` trains a deterministic 784-to-10 softmax linear
classifier on the standard 60,000-image MNIST training set, quantizes pixels and
weights to signed INT8, and evaluates all 10,000 test images. The current fixed
seed model reaches 92.02% INT8 test accuracy.

`mnist_dma.c` classifies test image zero (label 7) with the DMA MAC array; the
RISC-V configures descriptors and reads results but does not copy tensor data.
The array uses 49 K tiles for each of three groups
of four output rows; the two unused rows in the final group use zero weights.
All ten signed INT32 scores agree exactly. The engine retains partial sums over
49 K tiles and masks the two unused rows in the final output group, so the MAC
counter reports exactly 7,840 useful operations. Run:

```sh
make test-mnist RISCV_PREFIX=riscv64-elf-
```

This is a real MNIST image inference in shared-memory RTL simulation, not an
FPGA accuracy or timing measurement. The linear model is intentionally small;
a CNN requires convolution/im2col and multi-layer scheduling.

The MicroZed deployment now uses a 10x16 array, so all ten class scores are
computed together and each 16-element tile needs one array issue. The measured
resident-weight hardware path is 1,110 cycles per image at 20 MHz.

With five four-beat gather bursts, autonomous tile sequencing, cross-tile
accumulation, and ping-pong overlap, the FPGA-wrapper simulation completes in
4,627 cycles. Hardware timing and throughput must be reported from the rebuilt
bitstream rather than inferred from simulation.
