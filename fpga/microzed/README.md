# MicroZed XC7Z020 Stage B

The target device is `xc7z020clg400-1`. `synth_accelerator.tcl` synthesizes the
standalone PL accelerator with an AXI4-Lite control slave and a 32-bit AXI4 DMA
master before it is connected to the Zynq-7000 processing system.

Run on the supported Linux Vivado host with:

```sh
vivado -mode batch -source fpga/microzed/synth_accelerator.tcl
```

For the complete MicroZed processing-system design, install or reference the
official Avnet `microzed_7020:part0:1.4` board definition, then run:

```sh
vivado -mode batch -source fpga/microzed/build_system.tcl
vivado -mode batch -source fpga/microzed/implement_system.tcl
```

The Zynq PS accesses the accelerator control registers through GP0 at
`0x43c00000`. The accelerator's read-only DMA master reaches the low 1 GiB of
PS DDR through HP0. Both interfaces use the 100 MHz FCLK0 domain.

Board-level PS configuration, implementation, bitstream generation, and
hardware validation are separate acceptance points and must not be inferred
from standalone PL synthesis.
