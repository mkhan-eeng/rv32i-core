/* Memory layout for the RV32I core and for Spike.
   One 32 KB RAM at 0x80000000. Code first, then constants,
   then initialized data, then tohost/fromhost, then zeroed data.
   The stack starts at the top of RAM and grows down. */
OUTPUT_ARCH("riscv")
ENTRY(_start)

MEMORY
{
  RAM (rwx) : ORIGIN = 0x80000000, LENGTH = 32K
}

SECTIONS
{
  .text : {
    *(.text.init)              /* crt0 startup code, must be first */
    *(.text .text.*)
  } > RAM

  .rodata : {
    *(.rodata .rodata.* .srodata .srodata.*)
  } > RAM

  .data : {
    *(.data .data.* .sdata .sdata.*)
  } > RAM

  .tohost : ALIGN(64) {
    *(.tohost)                 /* Spike and the testbench watch this */
  } > RAM

  .bss (NOLOAD) : ALIGN(4) {
    _bss_start = .;
    *(.bss .bss.* .sbss .sbss.* COMMON)
    . = ALIGN(4);
    _bss_end = .;
  } > RAM

  _stack_top = ORIGIN(RAM) + LENGTH(RAM);
}
