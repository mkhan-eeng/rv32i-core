# Design Spec

## ISA
- RV32I only. FENCE is a no-op. ECALL and EBREAK stop the simulation.
- No CSRs, no traps, no misaligned loads or stores (flagged, and the simulation stops).
- Anything that isn't RV32I decodes as illegal and stops the simulation.

## Memory map
- Reset PC 0x8000_0000, the same as Spike, so traces line up.
- Separate instruction and data memories, both at 0x8000_0000, 32 KB each, loaded from the same image. Stores go to data memory only.
- Memory-mapped devices (modelled in the testbench):
  - 0x1000_0000 UART data: store a byte to print it
  - 0x1000_0004 UART status: reads 0 (always ready)
  - 0x1000_000C cycle counter: cycles since reset
- tohost: a program ends by storing to the `tohost` symbol. 1 = pass; (code << 1) | 1 = fail with that code.

## Cores
- One clock, synchronous active-high reset.
- `core` (single-cycle): fetch, decode, execute, memory and write-back in one cycle; memories read combinationally.
- `core_pipe` (5-stage): IF, ID, EX, MEM, WB.
  - Forwarding from EX/MEM and MEM/WB into EX; register-file bypass from WB into ID.
  - Load-use hazard: one stall cycle.
  - Branches and jumps resolve in EX. The next PC is guessed in IF; a wrong guess flushes IF/ID and ID/EX.
  - Branch target buffer: 64 entries (parameter `BTB_ENTRIES`, 0 disables it), indexed by PC[7:2], full-PC tag, 2-bit saturating counters. Trained in EX on branches and `jal`; a new entry starts weakly taken.
- Both cores have the same ports, including a retire port the testbench turns into a Spike-format commit log.
