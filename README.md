# RV32I Pipelined Core

![CI](https://github.com/mkhan-eeng/rv32i-core/actions/workflows/ci.yml/badge.svg)

A RISC-V (RV32I) processor in SystemVerilog, with two implementations that share one test flow:

- **Single-cycle core** (`rtl/core.sv`): every instruction completes in one clock. The simple reference.
- **5-stage pipelined core** (`rtl/core_pipe.sv`): IF, ID, EX, MEM, WB with forwarding, load-use stalls, branch resolution in EX and a 64-entry branch target buffer with 2-bit counters.

Every program run on either core is compared **instruction by instruction** against [Spike](https://github.com/riscv-software-src/riscv-isa-sim), the official RISC-V reference simulator: same PC, same instruction, same register written with the same value, same memory stores.

## Results

| | Single-cycle | Pipelined, no predictor | Pipelined + BTB |
| --- | --- | --- | --- |
| Official riscv-tests (rv32ui) | 40 / 40 | 40 / 40 | 40 / 40 |
| Random programs, trace-matched with Spike | 1000 / 1000 | 1000 / 1000 | 1000 / 1000 |
| CoreMark CPI | 1.000 | 1.432 | **1.188** |
| CoreMark iterations per MHz (simulated) | 1.34 | 0.93 | 1.13 |
| Load-use stall cycles | 0 | 203,923 | 203,923 |
| Pipeline flushes | 0 | 1,518,415 | 601,052 |

CoreMark: 10 iterations, `-O2 -march=rv32i`, GCC 13.2, cycles counted in simulation. Its CRCs match the official performance-run values. This is not an official CoreMark score (that needs a 10-second run on real hardware).

The branch target buffer removes 60% of flushes and brings CPI from 1.43 to 1.19. The single-cycle core has CPI 1.0, but its clock period has to fit the entire datapath; the pipeline exists to raise the clock frequency, which gets measured once the design is on an FPGA.

**Unit tests** (each module against an independently written reference model):

| Module | Checks | Method |
| --- | --- | --- |
| ALU | 101,440 | Edge cases + random, vs. a 64-bit integer model |
| Register file | 10,068 | Random writes/reads vs. a model array |
| Immediate generator | 100,022 | Real instructions + random encode/decode round trips |
| Decoder | 300,054 | Spec MASK/MATCH table: every instruction, near-miss illegal encodings, random words |
| Load/store unit | 100,033 | Byte-level model of every load and store at every offset |
| Memory | 5,011 | Program load, byte-enabled writes, out-of-range accesses |

## Pipeline

```
        IF              ID               EX                MEM            WB
   +----------+   +------------+   +--------------+   +-----------+   +--------+
   | PC, BTB  |-->| decode,    |-->| ALU, branch  |-->| load /    |-->| write  |
   | imem     |   | regfile,   |   | compare,     |   | store     |   | rd,    |
   | predict  |   | immgen     |   | next PC      |   | (LSU)     |   | retire |
   +----------+   +------------+   +--------------+   +-----------+   +--------+
        ^               |  ^             ^   ^  |            |              |
        |   load-use    |  +--- regfile bypass  |   forward  |              |
        |   stall ------+                |   +--|--- MEM ----+              |
        |                                +------|--- WB ------------------- +
        +---------- redirect + flush on a wrong guess -----+
```

- **Forwarding:** results go from EX/MEM and MEM/WB straight back to EX.
- **Load-use stall:** a load followed by an instruction that needs its result waits one cycle.
- **Control:** IF guesses the next PC (BTB hit and counter says taken, else PC+4). EX computes the real one; on a mismatch it redirects and flushes the two younger instructions.

## Verification

1. **Unit tests** for every module, each against a reference model written differently from the RTL, so the two can't share a bug.
2. **riscv-tests:** the official rv32ui suite, run with a minimal environment (`tests/env/riscv_test.h`) since this core has no CSRs. `fence_i` (needs Zifencei) and `ma_data` (misaligned accesses) are skipped.
3. **Differential testing:** `scripts/rv.py` generates random, always-legal RV32I programs (half of them confined to 4 registers so instructions depend on each other constantly), runs each on the core and on Spike, and compares the commit traces line by line.
4. **Mutation testing:** bugs were planted on purpose to prove the tests catch them. Every one was caught:

| Planted bug | Caught by |
| --- | --- |
| SRA without `$signed` | ALU unit test |
| Writable x0 | Register file unit test |
| Swapped B-format immediate bits; missing sign extension | Immediate generator unit test |
| `addi` decoded as `sub` when immediate bit 30 is set | Decoder unit test |
| `lb` without sign extension | LSU unit test |
| JALR not clearing bit 0 | Random programs (14 of 20 failed) |
| BLTU compared as signed | riscv-tests + random programs |
| No EX/MEM forwarding; no MEM/WB forwarding | riscv-tests + random programs |
| No load-use stall | riscv-tests + random programs |
| No register-file bypass | riscv-tests + random programs |
| No flush after a wrong guess | riscv-tests + random programs |

**Real bugs found during development:**

- Linking with `-Ttext` put the ELF header below 0x8000_0000, so Spike refused to load programs. Fixed with a proper linker script.
- The testbench released reset on the same clock edge it started tracing, so the first instruction was missing from the trace. Fixed by releasing reset just after a clock edge.
- Newer Verilator flagged random-test variables declared with a value inside a loop: SystemVerilog gives those their value only once. Fixed by declaring and assigning separately.

## Running it

Needs Verilator 5, a RISC-V GCC (`riscv-none-elf-` by default; set `CROSS=` for another prefix), Spike, Python 3.

```
make deps        # download riscv-tests and CoreMark (once)
make test        # unit tests
make lint
make hello       # sw/hello.c on the pipelined core, compared with Spike
make isa         # rv32ui tests
make random N=1000
make coremark    # all three cores
make check       # lint + test + hello + isa + random
```

`CORE=single`, `CORE=pipe` (default) or `CORE=pipe_nobtb` picks the core.

## Layout

```
rtl/      rv_pkg (shared types), alu, regfile, immgen, decoder, lsu, mem,
          core (single-cycle), core_pipe (5-stage)
tb/       a self-checking testbench per module, and tb_core for whole programs
sw/       linker script, startup code, hello.c, CoreMark port
scripts/  rv.py: run, compare with Spike, riscv-tests, random programs
tests/    test environment for riscv-tests (suites download into here)
docs/     spec.md: design decisions
```

## Next

- FPGA: block-RAM memories, a real UART, timing constraints, measured Fmax.
- Zicsr and machine-mode traps, then the official architecture tests (ACT4).
- M extension (hardware multiply/divide) and a return-address stack for `jalr`.
- The same core through LibreLane on SKY130, to GDS.
