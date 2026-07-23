OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY
{
  CODE (rx)  : ORIGIN = 0x00000000, LENGTH = 4K
  DATA (rwx) : ORIGIN = 0x00002000, LENGTH = 56K
}

SECTIONS
{
  PROVIDE(__global_pointer$ = ORIGIN(DATA) + 0x800);
  .text : {
    KEEP(*(.text.start))
    *(.text .text.*)
  } > CODE

  .rodata : { *(.rodata .rodata.*) } > CODE

  .data : ALIGN(4) {
    __data_start = .;
    *(.sdata .sdata.*)
    *(.data .data.*)
    __data_end = .;
  } > DATA

  .bss (NOLOAD) : ALIGN(4) {
    __bss_start = .;
    *(.sbss .sbss.*)
    *(.bss .bss.* COMMON)
    __bss_end = .;
  } > DATA

  . = ALIGN(16);
  __heap_start = .;
  __stack_top = ORIGIN(DATA) + LENGTH(DATA);

  ASSERT(SIZEOF(.text) + SIZEOF(.rodata) <= LENGTH(CODE), "code exceeds pre-mailbox region")
  ASSERT(__heap_start < __stack_top, "data/bss exceeds RAM")
}
