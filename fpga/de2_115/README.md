# RV32I core on the Terasic DE2-115

The pipelined core running CoreMark on a Cyclone IV E (EP4CE115F29C7) at 50 MHz.

## What's here

| File | What it is |
| --- | --- |
| `de2_115_top.sv` | Board top level: core, memories, UART, cycle counter, LEDs, 7-segment displays |
| `fpga_mem.sv` | Instruction ROM and data RAM, written so Quartus maps them to M9K block RAM |
| `uart_tx.sv` | 115200 baud transmitter for the RS-232 port |
| `hex7seg.sv` | Hex digit to 7-segment |
| `tb_de2_115.sv` | Simulation of the whole board design (`make fpga_sim`) |
| `rv32i_de2_115.v` | **Generated** by `make fpga`: all of the above plus the core, converted to plain Verilog with sv2v so any Quartus version compiles it |
| `mem/*.hex` | **Generated** by `make fpga`: CoreMark (700 iterations) split into the instruction ROM and four data byte lanes |
| `rv32i_de2_115.qpf/.qsf` | Quartus project: device, files, pin assignments |
| `de2_115.sdc` | Timing: 50 MHz clock |

The generated files are committed, so you only need Quartus to build the board image.

## Build and run

1. Install Quartus II 13.0sp1 or newer, or Quartus Prime Lite (both free, both support Cyclone IV).
2. Open `rv32i_de2_115.qpf`, then Processing > Start Compilation.
3. Check timing: in the Compilation Report, open TimeQuest Timing Analyzer (called Timing Analyzer in Quartus Prime) > Slow 1200mV 85C Model > Fmax Summary. Fmax must be above 50 MHz.
4. Connect the board (USB Blaster port, power on), Tools > Programmer > Start. It uses `output_files/rv32i_de2_115.sof`.
5. The program starts on its own. Green LED 0 blinks while CoreMark runs (about 12 seconds), then:
   - green LED 8 on = pass, red LED 17 on = fail
   - the 7-segment displays show the CoreMark score x100 in decimal (e.g. `00005650` = 56.50 CoreMark)
6. Press KEY0 to run it again.

Switches SW1..SW0 pick what the displays show:

| SW1 SW0 | Display |
| --- | --- |
| 0 0 | CoreMark score x100 (decimal) |
| 0 1 | clock cycles for the run (hex) |
| 1 0 | instructions retired (hex) |
| 1 1 | branch mispredict flushes (hex) |

CPI on hardware = cycles / instructions. It should match simulation exactly, since the design is cycle-for-cycle identical.

To see CoreMark's full printout, connect the RS-232 port to a computer with a USB-to-RS232 cable and open a terminal at 115200 baud, 8N1.

## Memory map

| Address | |
| --- | --- |
| `0x8000_0000` | 32 KB RAM (instruction and data copies of the program image) |
| `0x1000_0000` | UART data: write a byte to send it |
| `0x1000_0004` | UART status: bit 0 = busy |
| `0x1000_000C` | cycle counter |
| `0x1000_0010` | 7-segment display register |
