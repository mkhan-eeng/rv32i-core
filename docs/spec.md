# Design Spec

- ISA: RV32I only. FENCE is a no-op. ECALL/EBREAK stop simulation.
- Reset PC: 0x8000_0000 (matches Spike).
- Memory: separate instruction and data memories, both mapped at 0x8000_0000, 32 KB each, loaded from the same image. Stores go to data memory only.
- MMIO at 0x1000_0000: UART data, UART status, LEDs, cycle counter.
- Misaligned loads/stores: not supported.
- One clock, synchronous active-high reset.
