#!/usr/bin/env python3
"""Turn a program image into the memory files for the FPGA block RAMs.

    python3 scripts/fpga_hex.py program.bin out_dir [words]

Writes imem.hex (32-bit words) and dmem_b0..dmem_b3.hex (one byte lane each),
each padded to `words` lines (default 8192 = 32 KB).
"""
import sys
from pathlib import Path

binfile, outdir = Path(sys.argv[1]), Path(sys.argv[2])
words = int(sys.argv[3]) if len(sys.argv) > 3 else 8192
data = binfile.read_bytes()
if len(data) > 4 * words:
    sys.exit(f"program is {len(data)} bytes, memory is only {4 * words}")
data = data + bytes(4 * words - len(data))
outdir.mkdir(parents=True, exist_ok=True)
w = [int.from_bytes(data[i:i + 4], "little") for i in range(0, len(data), 4)]
(outdir / "imem.hex").write_text("".join(f"{x:08x}\n" for x in w))
for b in range(4):
    (outdir / f"dmem_b{b}.hex").write_text("".join(f"{(x >> (8 * b)) & 0xff:02x}\n" for x in w))
print(f"wrote {outdir}/imem.hex and dmem_b0..3.hex ({len(binfile.read_bytes())} bytes of program)")
