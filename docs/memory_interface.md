# Memory interfaces

The subsystem exposes independent 32-bit instruction and data OBI-style
request/response ports. A request is accepted only when `req && gnt`; the
response arrives independently with `rvalid`, and `err` is meaningful in that
response cycle. The data interface includes write enable, four byte enables,
and 32-bit write data. Testbench memories may insert arbitrary grant and
response delay.

The configured PMA marks executable addresses `0x00000000..0x00000fff` as Main
memory and all other addresses as I/O. Naturally aligned byte, halfword, and
word accesses are allowed in I/O. Split misaligned I/O operations are rejected
inside the core before an external data request. Instruction response errors
produce precise cause 24; load/store response errors produce imprecise NMI
causes 1024/1025.

The NN coprocessor currently performs register-register operations only. Its
XIF memory request channel is tied inactive, so no NN instruction can directly
read or write system memory.
## DMA tile layout

The optional AXI read DMA consumes one 80-byte, naturally aligned tile:

| Word range | Contents |
|---|---|
| 0..3 | Four packed activation blocks (16 signed INT8 values) |
| 4..19 | Weight blocks in output-row-major order (64 signed INT8 values) |

Contiguous mode uses `ARSIZE=2`, `ARBURST=INCR`, and `ARLEN=19`. Gather mode
reads the same logical tile as five four-beat bursts (`ARLEN=3`): activation,
then four independently addressed weight rows. RRESP errors and early/late
RLAST invalidate the destination bank.

## DMA control registers

The CV32E40X accesses the DMA controller through naturally aligned MMIO at
`0x0000_f000`:

| Offset | Access | Meaning |
|---|---|---|
| 0x00 | RW | 32-bit AXI source address |
| 0x04 | W | bit0 DMA start, bit1 DMA bank, bit2 compute start, bit3 compute bank, bit4 accumulate, bit5 autonomous tile run |
| 0x08 | R | bit0 DMA busy, bit1 DMA done, bit2 error, bit3 compute busy, bit4 compute done, bits5/6 bank ready, bit7 autonomous busy, bit8 autonomous done |
| 0x0c | RW | Active output rows, 1 through 4 |
| 0x10..0x1c | R | Four signed 32-bit accumulators |
| 0x20/0x24 | R | Completed MAC count, low/high words |
| 0x28 | RW | Gather activation/image base address |
| 0x2c | RW | Gather weight base address |
| 0x30 | RW | Gather tile index (manual mode) |
| 0x34 | RW | First output row |
| 0x38 | RW | Gather enable |
| 0x3c | RW | Autonomous tile count (49 for MNIST) |
| 0x40 | R | bits0..2 weight-slot valid, bit3 weight hit, bit4 activation valid, bit5 activation hit |
| 0x44 | W | Invalidate selected cache slots (bits 2:0) |
| 0x48..0x50 | R | Model output-group tag stored in cache slots 0..2 |
| 0x54 | R | Replacement slot and hardware slot capacity (3 groups) |

Done and error status is sticky until the corresponding next start. In
autonomous mode the controller prefetches tile zero, overlaps subsequent DMA
transfers with MAC execution through alternating banks, and asserts bit8 only
after the final tile has been accumulated.

The accelerator-side weight cache stores four 32-bit row words as one 128-bit
line. Three tagged slots hold 49 tiles x four K blocks each. Models with three
or fewer four-output groups use full-resident mode automatically. Larger
models use tagged window mode: a miss selects a round-robin slot, fills that
group while computing, and records its model-group tag. Software may invalidate
slots after changing model weights; image changes do not invalidate weights.

The activation cache contains 196 32-bit words (784 bytes). Output group zero
fills it from shared BRAM for the current image. Later output groups read the
same activation blocks locally and bypass activation DMA whenever their weight
group is also resident. Starting output group zero invalidates and refills the
activation cache, while RISC-V-only reset leaves the weight cache intact.

## MicroZed MNIST 10x16 engine

The deployed MNIST wrapper uses `nn_mnist_accel_10x16`: ten output rows and
sixteen signed-INT8 input lanes execute 160 useful MACs per array cycle. One
128-bit activation line and ten independent 128-bit weight lines are read for
each of the 49 tiles. All ten accumulators are produced by one autonomous run;
there are no four-row output groups in this deployed configuration.

The command register at `0x04` uses bit 6 to start a 10x16 inference. Status
bit 7 is busy, bit 8 is done, and bit 9 reports resident weights. Accumulators
0 through 9 are mapped at `0x60..0x84`. Writing bit 0 to `0x44` invalidates the
resident model weights.
