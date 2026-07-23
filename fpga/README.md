# FPGA Stage B

This tree contains the vendor boundary and validated MicroZed XC7Z020 build
flow. Vivado 2026.1 completes synthesis, implementation, DRC, bitstream, and
XSA generation for the PS7 + GP0 control + HP0 DMA design at 100 MHz.

Physical board programming and runtime validation have not yet been performed.
The generated artifacts are therefore implementation outputs, not proof of
working DDR/DMA/application behavior on hardware.
