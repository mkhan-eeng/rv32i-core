OUTPUT_ARCH("riscv")
ENTRY(_start)
SECTIONS
{
  . = 0x80000000;
  .text : { *(.text.init) *(.text*) }
  .tohost : { *(.tohost) }
  .data : { *(.data*) *(.rodata*) }
  .bss : { *(.bss*) }
}
