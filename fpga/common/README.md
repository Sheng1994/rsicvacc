# Common FPGA adapters

The vendor-independent Stage B datapath is implemented by
`rtl/nn_axi_read_dma.sv` and `rtl/nn_dma_mac_array.sv`.

The AXI4 read master supports a contiguous 20-word tile and an MNIST gather
mode. Gather mode issues five four-beat INCR bursts: one activation region and
one weight region for each of four output rows. Two inferred-memory banks let
DMA fill the next tile while the four-output MAC array consumes the current
tile. An autonomous MMIO sequencer alternates the banks over a configurable
tile count, so software starts an entire output group rather than every tile.

The design supports AXI read-channel backpressure, checks RRESP and RLAST, and
invalidates a bank after a transfer error. It intentionally exposes only the
AXI read channels because results remain in four local accumulators. A board
wrapper may map the inferred memories to BRAM and connect the master to a Zynq
HP port or AXI interconnect.
