#!/usr/bin/env python3
"""Run programs on the RV32I core and check them against Spike.

  python3 scripts/rv.py run     sw/build/hello.elf      run on the core, PASS/FAIL
  python3 scripts/rv.py compare sw/build/hello.elf      run on the core AND Spike, compare
                                                        every instruction
  python3 scripts/rv.py isa                             official rv32ui tests
  python3 scripts/rv.py random -n 1000                  random programs vs Spike

The core simulator must be built first (make sim). The compiler prefix comes
from the CROSS environment variable (default riscv-none-elf-).
"""
import argparse
import os
import random
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
# Which core to run: single, pipe, or pipe_nobtb (pipelined, no branch predictor).
CORE = os.environ.get("CORE", "single")
SIM = ROOT / "build" / CORE / "Vtb_core"
CROSS = os.environ.get("CROSS", "riscv-none-elf-")
SPIKE = os.environ.get("SPIKE", "spike")
LINKER = ROOT / "sw" / "linker.ld"
ISA_DIR = ROOT / "tests" / "riscv-tests" / "isa"
ENV_DIR = ROOT / "tests" / "env"
BUILD = ROOT / "tests" / "build"

CFLAGS = ["-march=rv32i", "-mabi=ilp32", "-nostdlib", "-nostartfiles", "-static",
          "-T", str(LINKER), "-Wl,--no-warn-rwx-segments"]

# rv32ui tests this core can't run: fence_i needs the Zifencei extension,
# ma_data tests misaligned accesses, which this core doesn't support.
ISA_SKIP = {"fence_i", "ma_data"}


def sh(cmd, **kw):
    return subprocess.run(cmd, capture_output=True, text=True, **kw)


# ---------------------------------------------------------------- build steps

def elf_to_hex(elf):
    """objcopy to raw binary, then one little-endian 32-bit word per line."""
    elf = Path(elf)
    binf, hexf = elf.with_suffix(".bin"), elf.with_suffix(".hex")
    r = sh([CROSS + "objcopy", "-O", "binary", str(elf), str(binf)])
    if r.returncode:
        sys.exit(r.stderr)
    data = binf.read_bytes()
    data += b"\x00" * (-len(data) % 4)
    with open(hexf, "w") as f:
        for i in range(0, len(data), 4):
            f.write(f"{int.from_bytes(data[i:i+4], 'little'):08x}\n")
    return hexf


def tohost_of(elf):
    r = sh([CROSS + "nm", str(elf)])
    for line in r.stdout.splitlines():
        parts = line.split()
        if len(parts) == 3 and parts[2] == "tohost":
            return parts[0]
    sys.exit(f"no tohost symbol in {elf}")


def compile_asm(src, elf, includes=()):
    cmd = [CROSS + "gcc", *CFLAGS]
    for inc in includes:
        cmd += ["-I", str(inc)]
    cmd += [str(src), "-o", str(elf)]
    r = sh(cmd)
    if r.returncode:
        sys.exit(f"compile failed: {src}\n{r.stderr}")


# ---------------------------------------------------------------- running

def run_core(elf, trace=None, max_cycles=1_000_000):
    """Run on the core. Returns (passed, result line)."""
    if not SIM.exists():
        sys.exit(f"{SIM} not found: run 'make sim' first")
    cmd = [str(SIM), f"+hex={elf_to_hex(elf)}", f"+tohost={tohost_of(elf)}",
           f"+max_cycles={max_cycles}"]
    if trace:
        cmd.append(f"+trace={trace}")
    r = sh(cmd)
    lines = r.stdout.splitlines()
    # The testbench's verdict is its last PASS/FAIL line (a program can print anything).
    result = next((l for l in reversed(lines) if l.startswith(("PASS", "FAIL", "ERROR:"))),
                  "FAIL: no result printed\n" + r.stdout + r.stderr)
    # Anything the program printed through the UART (skip Verilator's own report lines).
    printed = "\n".join(l for l in lines if l != result and not l.startswith("- "))
    return result.startswith("PASS"), result, printed


def run_spike(elf, trace):
    """Run on Spike, saving its commit log. Returns True if the program passed."""
    with open(trace, "w") as f:
        r = subprocess.run([SPIKE, "--isa=rv32i_zicsr", "--log-commits", str(elf)],
                           stderr=f, stdout=subprocess.PIPE, text=True, timeout=60)
    return r.returncode == 0


# ---------------------------------------------------------------- trace diff

LINE = re.compile(r"core\s+\d+:\s+\d+\s+0x([0-9a-f]+)\s+\(0x([0-9a-f]+)\)(.*)")
REG = re.compile(r"x(\d+)\s+0x([0-9a-f]+)")
MEM = re.compile(r"mem\s+0x([0-9a-f]+)(?:\s+0x([0-9a-f]+))?")


def parse_trace(path):
    """Each line -> (pc, inst, (rd, value) or None, (addr, store value or None) or None)."""
    out = []
    for text in Path(path).read_text().splitlines():
        m = LINE.match(text)
        if not m:
            continue
        pc, inst, rest = int(m.group(1), 16), int(m.group(2), 16), m.group(3)
        reg = REG.search(rest)
        mem = MEM.search(rest)
        out.append((pc, inst,
                    (int(reg.group(1)), int(reg.group(2), 16)) if reg else None,
                    (int(mem.group(1), 16), int(mem.group(2), 16) if mem.group(2) else None) if mem else None,
                    text))
    return out


def compare_traces(core_log, spike_log):
    """Compare the core's trace with Spike's, instruction by instruction.
    Returns None if they match, otherwise a description of the first difference."""
    core = parse_trace(core_log)
    spike = parse_trace(spike_log)
    # Spike runs a few boot ROM instructions at 0x1000 first; the core starts at 0x80000000.
    while spike and spike[0][0] != 0x80000000:
        spike.pop(0)
    if not core:
        return "core trace is empty"
    for i, c in enumerate(core):
        if i >= len(spike):
            return f"core ran {len(core)} instructions, Spike only {len(spike)}"
        s = spike[i]
        if c[:4] != s[:4]:
            ctx = "\n".join(f"      {core[j][4]}" for j in range(max(0, i - 3), i))
            return (f"first difference at instruction {i}\n"
                    f"  previous instructions (both agree):\n{ctx}\n"
                    f"  core : {c[4]}\n"
                    f"  spike: {s[4]}")
    return None


def compare(elf, tag=None):
    """Run elf on both, compare. Returns (ok, message)."""
    elf = Path(elf)
    tag = tag or elf.stem
    core_log = elf.with_name(tag + ".core.log")
    spike_log = elf.with_name(tag + ".spike.log")
    passed, result, _ = run_core(elf, trace=core_log)
    spike_ok = run_spike(elf, spike_log)
    diff = compare_traces(core_log, spike_log)
    if diff:
        return False, f"trace mismatch\n{diff}"
    if not passed:
        return False, f"traces match but the program failed: {result}"
    if not spike_ok:
        return False, "traces match but Spike reports failure"
    return True, f"{result}, trace matches Spike"


# ---------------------------------------------------------------- random programs

R_OPS = ["add", "sub", "sll", "slt", "sltu", "xor", "srl", "sra", "or", "and"]
I_OPS = ["addi", "slti", "sltiu", "xori", "ori", "andi"]
SH_OPS = ["slli", "srli", "srai"]
BR_OPS = ["beq", "bne", "blt", "bge", "bltu", "bgeu"]
LD_OPS = [("lb", 1), ("lh", 2), ("lw", 4), ("lbu", 1), ("lhu", 2)]
ST_OPS = [("sb", 1), ("sh", 2), ("sw", 4)]
DATA_BYTES = 1024


def gen_random(seed, length):
    """A random but always-legal RV32I program.
    x31 points at a 1 KB data region and is never overwritten, so every load
    and store stays in bounds. Branches and jumps only go forward, so the
    program always reaches the end."""
    r = random.Random(seed)
    # Half the programs use only 4 registers (plus x0). Instructions then
    # depend on each other constantly, which is what stresses forwarding and
    # stalls in a pipeline.
    if r.random() < 0.5:
        pool = r.sample(range(1, 31), 4) + [0]
        rd = lambda: r.choice(pool)
        rs = lambda: r.choice(pool)
    else:
        rd = lambda: r.randrange(0, 31)      # x0..x30 (writes to x0 test that it stays 0)
        rs = lambda: r.randrange(0, 32)      # any register
    fwd = lambda i: f"L{min(i + r.randint(1, 4), length)}"

    a = [f"# random program, seed {seed}",
         ".section .text.init", ".globl _start", "_start:",
         "  la x31, data"]
    for reg in range(1, 31):
        a.append(f"  li x{reg}, {r.getrandbits(32):#x}")

    kinds = ["r"] * 6 + ["i"] * 5 + ["sh"] * 2 + ["u"] + ["ld"] * 3 + ["st"] * 3 + \
            ["br"] * 3 + ["jal", "jalr", "fence"]
    for i in range(length):
        a.append(f"L{i}:")
        k = r.choice(kinds)
        if k == "r":
            a.append(f"  {r.choice(R_OPS)} x{rd()}, x{rs()}, x{rs()}")
        elif k == "i":
            a.append(f"  {r.choice(I_OPS)} x{rd()}, x{rs()}, {r.randint(-2048, 2047)}")
        elif k == "sh":
            a.append(f"  {r.choice(SH_OPS)} x{rd()}, x{rs()}, {r.randint(0, 31)}")
        elif k == "u":
            a.append(f"  {r.choice(['lui', 'auipc'])} x{rd()}, {r.getrandbits(20):#x}")
        elif k == "ld":
            op, size = r.choice(LD_OPS)
            a.append(f"  {op} x{rd()}, {r.randrange(0, DATA_BYTES, size)}(x31)")
        elif k == "st":
            op, size = r.choice(ST_OPS)
            a.append(f"  {op} x{rs()}, {r.randrange(0, DATA_BYTES, size)}(x31)")
        elif k == "br":
            a.append(f"  {r.choice(BR_OPS)} x{rs()}, x{rs()}, {fwd(i)}")
        elif k == "jal":
            a.append(f"  jal x{rd()}, {fwd(i)}")
        elif k == "jalr":
            t = r.randrange(1, 31)
            a.append(f"  la x{t}, {fwd(i)}")
            if r.random() < 0.3:                 # jalr must clear bit 0 of the target
                a.append(f"  addi x{t}, x{t}, 1")
            a.append(f"  jalr x{rd()}, 0(x{t})")
        else:
            a.append("  fence")
    a += [f"L{length}:",
          "  li x5, 1", "  la x6, tohost", "  sw x5, 0(x6)", "1: j 1b",
          ".data", ".align 4", "data:"]
    for _ in range(DATA_BYTES // 4):
        a.append(f"  .word {r.getrandbits(32):#x}")
    a += ['.section .tohost,"aw",@progbits', ".align 6", ".globl tohost", "tohost: .dword 0",
          ".align 6", ".globl fromhost", "fromhost: .dword 0", ""]
    return "\n".join(a)


# ---------------------------------------------------------------- commands

def cmd_run(args):
    passed, result, printed = run_core(args.elf, trace=args.trace, max_cycles=args.max_cycles)
    if printed.strip():
        print(printed)
    print(result)
    return 0 if passed else 1


def cmd_compare(args):
    ok, msg = compare(args.elf)
    print(("PASS: " if ok else "FAIL: ") + msg)
    return 0 if ok else 1


def cmd_isa(args):
    src_dir = ISA_DIR / "rv32ui"
    if not src_dir.exists():
        sys.exit("riscv-tests not found. Run:\n"
                 "  git clone https://github.com/riscv-software-src/riscv-tests tests/riscv-tests")
    out = BUILD / "isa"
    out.mkdir(parents=True, exist_ok=True)
    tests = sorted(p.stem for p in src_dir.glob("*.S") if p.stem not in ISA_SKIP)
    failed = []
    for t in tests:
        elf = out / f"{t}.elf"
        compile_asm(src_dir / f"{t}.S", elf, includes=[ENV_DIR, ISA_DIR / "macros" / "scalar"])
        ok, msg = compare(elf)
        print(f"  {t:8s} {'PASS' if ok else 'FAIL'}  {'' if ok else msg}")
        if not ok:
            failed.append(t)
    print(f"\n{len(tests) - len(failed)} of {len(tests)} rv32ui tests pass "
          f"(skipped: {', '.join(sorted(ISA_SKIP))})")
    return 1 if failed else 0


def cmd_random(args):
    out = BUILD / "random"
    out.mkdir(parents=True, exist_ok=True)
    first = args.seed if args.seed is not None else random.randrange(1_000_000)
    failed = []
    for n in range(args.n):
        seed = first + n
        src, elf = out / f"rand_{seed}.S", out / f"rand_{seed}.elf"
        src.write_text(gen_random(seed, args.length))
        compile_asm(src, elf)
        ok, msg = compare(elf)
        if ok:
            for f in out.glob(f"rand_{seed}.*"):
                f.unlink()
        else:
            failed.append(seed)
            print(f"seed {seed}: {msg}\n  program kept: {src}\n")
        if (n + 1) % 100 == 0:
            print(f"  {n + 1} programs, {len(failed)} failed")
    print(f"\n{args.n - len(failed)} of {args.n} random programs match Spike "
          f"(seeds {first} to {first + args.n - 1})")
    return 1 if failed else 0


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("run", help="run an ELF on the core")
    s.add_argument("elf")
    s.add_argument("--trace", help="write the core's commit log here")
    s.add_argument("--max-cycles", type=int, default=1_000_000, help="give up after this many cycles")
    s = sub.add_parser("compare", help="run an ELF on the core and on Spike and compare")
    s.add_argument("elf")
    sub.add_parser("isa", help="run the official rv32ui tests")
    s = sub.add_parser("random", help="random programs, compared against Spike")
    s.add_argument("-n", type=int, default=100, help="how many programs (default 100)")
    s.add_argument("--seed", type=int, help="first seed (default: random)")
    s.add_argument("--length", type=int, default=200, help="instructions per program")
    args = p.parse_args()
    return {"run": cmd_run, "compare": cmd_compare, "isa": cmd_isa, "random": cmd_random}[args.cmd](args)


if __name__ == "__main__":
    sys.exit(main())
