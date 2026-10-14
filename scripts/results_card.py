#!/usr/bin/env python3
"""Draw docs/img/results.png: CoreMark on the three cores plus verification numbers."""
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch

BG, PANEL, FG, MUTED, GRID = "#0f1117", "#171a23", "#e8eaf0", "#8b90a0", "#262a38"
cores = ["5-stage, no predictor", "5-stage + BTB"]
cpi = [1.432, 1.199]
ticks = [10.696, 8.953]
cols = ["#5b6070", "#4c8dff"]

fig = plt.figure(figsize=(12, 5.6), dpi=200)
fig.patch.set_facecolor(BG)
fig.text(0.04, 0.92, "rv32i-core  ·  results", color=FG, fontsize=18, fontweight="bold")
fig.text(0.04, 0.865, "CoreMark (10 iterations, GCC 13.2, -O2) on the pipelined core, and how the design was verified",
         color=MUTED, fontsize=9.5)

ax = fig.add_axes([0.04, 0.22, 0.47, 0.52])
ax.set_facecolor(BG)
y = [1, 0]
ax.barh(y, ticks, color=cols, height=0.42)
for yi, name in zip(y, cores):
    ax.text(0, yi + 0.33, name, color=FG, fontsize=10.5, fontweight='bold')
for yi, t, c in zip(y, ticks, cpi):
    ax.text(t + 0.15, yi, f"{t:.2f}M cycles   CPI {c:.3f}", color=FG, va="center", fontsize=10)
ax.set_yticks([])
ax.set_ylim(-0.4, 1.55)
ax.set_xlim(0, 14.5)
ax.set_xlabel("CoreMark cycles (millions, lower is better)", color=MUTED, fontsize=9)
ax.tick_params(colors=MUTED, length=0)
for s in ax.spines.values():
    s.set_visible(False)
ax.grid(axis="x", color=GRID, lw=0.6)
ax.set_axisbelow(True)
fig.text(0.04, 0.065, "64-entry BTB with 2-bit counters: 16% fewer cycles, CPI 1.432 → 1.199",
        color="#3ddc84", fontsize=10, fontweight="bold")

stats = [("40 / 40", "official rv32ui tests pass,\nevery instruction checked vs Spike"),
         ("1000 / 1000", "random programs match the\nSpike ISA simulator exactly"),
         ("616,628", "unit-test checks across\nALU, decoder, regfile, LSU, memory"),
         ("15 / 15", "deliberately planted bugs\ncaught by the test suite")]
x0, y0, w, h, gap = 0.565, 0.47, 0.19, 0.29, 0.02
for k, (big, small) in enumerate(stats):
    x = x0 + (k % 2) * (w + gap)
    yy = y0 - (k // 2) * (h + gap)
    fig.patches.append(FancyBboxPatch((x, yy), w, h, boxstyle="round,pad=0,rounding_size=0.015",
                                      transform=fig.transFigure, fc=PANEL, ec=GRID, lw=1))
    fig.text(x + 0.018, yy + h - 0.1, big, color=FG, fontsize=19, fontweight="bold")
    fig.text(x + 0.018, yy + 0.07, small, color=MUTED, fontsize=8.6, linespacing=1.4)
fig.text(0.565, 0.065, "RV32I · SystemVerilog · Verilator · forwarding, load-use stall, BTB · CI on GitHub Actions",
         color=MUTED, fontsize=8.5)
fig.savefig("docs/img/results.png", facecolor=BG)
print("wrote docs/img/results.png")
