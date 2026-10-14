#!/usr/bin/env python3
"""Draw a pipeline diagram and a waveform from a +pipeview log.

    python3 scripts/pipeview.py build/demo.pv sw/build/pipeline_demo.dump docs/img

The log has one line per cycle (written by tb_core with +pipeview=<file>):
    cycle pc_f ifid.pc idex.pc exmem.pc memwb.pc stall flush
where "-" is a bubble. stall/flush are what the core decided in that cycle,
so they take effect at the next clock edge.
"""
import re
import sys
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch, Rectangle

STAGES = ["IF", "ID", "EX", "MEM", "WB"]
COL = {"IF": "#4c8dff", "ID": "#8a63ff", "EX": "#ff8a3d", "MEM": "#2fbf9b", "WB": "#e5c04a"}
BG, FG, MUTED, GRID = "#0f1117", "#e8eaf0", "#8b90a0", "#232634"
STALL, FLUSH = "#ff5c7a", "#5b6070"
MONO = "DejaVu Sans Mono"


def load_log(path):
    rows = []
    for line in Path(path).read_text().splitlines():
        f = line.split()
        if len(f) != 8:
            continue
        pcs = [None if x == "-" else int(x, 16) for x in f[1:6]]
        rows.append({"cycle": int(f[0]), "pcs": pcs, "stall": f[6] == "1", "flush": f[7] == "1"})
    return rows


def load_disasm(path):
    dis = {}
    for line in Path(path).read_text().splitlines():
        m = re.match(r"\s*([0-9a-f]{8}):\s+[0-9a-f]{8}\s+(.*)", line)
        if m:
            text = m.group(2).split("#")[0].strip()
            text = re.sub(r"\s+", " ", text)
            text = re.sub(r"(\w+) ", lambda mm: mm.group(1).ljust(5) + " ", text, count=1)
            dis[int(m.group(1), 16)] = re.sub(r" <[^>]+>", "", text)
    return dis


def track(rows):
    """Follow each fetched instruction through the stages.

    Returns a list of instances: {pc, cells: {cycle: (stage, kind)}, squashed}
    where kind is "run", "stall" (held in place) or "flushed".
    """
    inst = []
    occ_prev = [None] * 5
    prev = None
    for r in rows:
        c, pcs = r["cycle"], r["pcs"]
        occ = [None] * 5
        if prev is None:
            occ[0] = len(inst)
            inst.append({"pc": pcs[0], "cells": {}, "squashed": False})
        else:
            st, fl = prev["stall"], prev["flush"]
            # WB, MEM, EX take whatever moved forward, if the log says a valid instruction is there
            for s in (4, 3, 2):
                src = occ_prev[s - 1]
                if pcs[s] is not None and src is not None and inst[src]["pc"] == pcs[s] and not (s == 2 and st):
                    occ[s] = src
            if fl:
                for s in (0, 1):
                    if occ_prev[s] is not None and occ_prev[s] not in occ:
                        inst[occ_prev[s]]["squashed"] = True
            if st:
                occ[1], occ[0] = occ_prev[1], occ_prev[0]
            else:
                if not fl and occ_prev[0] is not None and pcs[1] is not None:
                    occ[1] = occ_prev[0]
                occ[0] = len(inst)
                inst.append({"pc": pcs[0], "cells": {}, "squashed": False})
        for s, i in enumerate(occ):
            if i is not None:
                held = prev is not None and prev["stall"] and s in (0, 1) and occ_prev[s] == i
                inst[i]["cells"][c] = (STAGES[s], "stall" if held else "run")
        if r["flush"]:
            for s in (0, 1):
                if occ[s] is not None:
                    inst[occ[s]]["cells"][c] = (STAGES[s], "doomed")
        occ_prev, prev = occ, r
    return inst


def pipeline_diagram(rows, dis, out, max_cycle=None):
    inst = track(rows)
    last = max_cycle or rows[-1]["cycle"]
    # keep instructions that finished or were flushed, and drop the self-loop tail
    keep = [i for i in inst if i["cells"] and min(i["cells"]) <= last
            and (i["squashed"] or "EX" in [s for s, _ in i["cells"].values()])]
    n, first = len(keep), rows[0]["cycle"]
    cw, rh, left = 0.42, 0.42, 3.4
    W = left + (last - first + 1) * cw + 0.4
    H = 1.6 + n * rh + 1.0
    fig = plt.figure(figsize=(W, H), dpi=200)
    fig.patch.set_facecolor(BG)
    ax = fig.add_axes([0, 0, 1, 1])
    ax.set_xlim(0, W)
    ax.set_ylim(H, 0)
    ax.axis("off")

    ax.text(0.3, 0.45, "rv32i-core  ·  5-stage pipeline, cycle by cycle", color=FG,
            fontsize=15, fontweight="bold", va="center")
    ax.text(0.3, 0.85, "Real Verilator simulation of a 4-iteration array-sum loop. "
            "Load-use stalls, branch mispredict flushes, and BTB predictions are visible.",
            color=MUTED, fontsize=8.5, va="center")

    top = 1.45
    for c in range(first, last + 1):
        x = left + (c - first) * cw
        ax.text(x + cw / 2, top - 0.15, str(c), color=MUTED, fontsize=6, ha="center", fontfamily=MONO)
        ax.add_line(plt.Line2D([x, x], [top, top + n * rh], color=GRID, lw=0.5))

    for k, i in enumerate(keep):
        y = top + k * rh
        label = f"{i['pc'] & 0xffff:04x}  {dis.get(i['pc'], '?')}"
        ax.text(0.3, y + rh / 2, label, color=MUTED if i["squashed"] else FG, fontsize=7.2,
                va="center", fontfamily=MONO)
        for c, (s, kind) in sorted(i["cells"].items()):
            if c > last:
                continue
            x = left + (c - first) * cw
            if i["squashed"]:
                face, txt, ec = BG, FLUSH, FLUSH
            elif kind == "stall":
                face, txt, ec = STALL, BG, STALL
            else:
                face, txt, ec = COL[s], BG, COL[s]
            box = FancyBboxPatch((x + 0.025, y + 0.04), cw - 0.05, rh - 0.08,
                                 boxstyle="round,pad=0,rounding_size=0.06",
                                 fc=face, ec=ec, lw=0.8, ls="--" if i["squashed"] else "-")
            ax.add_patch(box)
            ax.text(x + cw / 2, y + rh / 2, s, color=txt, fontsize=5.6, ha="center", va="center",
                    fontweight="bold", fontfamily=MONO)
        mnem = dis.get(i["pc"], "").split(" ")[0]
        if not i["squashed"] and mnem in ("beq", "bne", "blt", "bge", "bltu", "bgeu", "beqz", "bnez", "j", "jal", "jalr"):
            nxt = keep[k + 1] if k + 1 < n else None
            xs = left + (max(c for c in i["cells"] if c <= last) - first + 1) * cw + 0.12
            if nxt is not None and nxt["squashed"]:
                note, colr = "mispredict: EX redirects, 2 wrong-path instrs flushed", "#ffb454"
            else:
                note, colr = "predicted correctly by BTB: zero bubbles", "#3ddc84"
            if xs < W - 2.5:
                ax.text(xs, y + rh / 2, note, color=colr, fontsize=6.8, va="center", style="italic")
        if not i["squashed"] and any(kind == "stall" for _, kind in i["cells"].values()) and "ID" == i["cells"][sorted(c for c, v in i["cells"].items() if v[1] == "stall")[0]][0]:
            xs = left + (max(i["cells"]) - first + 1) * cw + 0.12
            ax.text(xs, y + rh / 2, "load-use: waits 1 cycle for lw data", color=STALL, fontsize=6.8,
                    va="center", style="italic")
        if i["squashed"]:
            xs = left + (max(i["cells"]) - first + 1) * cw + 0.08
            ax.text(xs, y + rh / 2, "flushed", color=FLUSH, fontsize=6.5, va="center", style="italic")

    # legend
    ly = top + n * rh + 0.45
    x = 0.3
    for name, colr, dashed in [(s, COL[s], False) for s in STAGES] + [("stall (load-use)", STALL, False),
                                                                     ("flushed (mispredict)", FLUSH, True)]:
        ax.add_patch(FancyBboxPatch((x, ly - 0.11), 0.22, 0.22, boxstyle="round,pad=0,rounding_size=0.04",
                                    fc=BG if dashed else colr, ec=colr, ls="--" if dashed else "-"))
        ax.text(x + 0.32, ly, name, color=FG, fontsize=7.5, va="center")
        x += 0.32 + 0.065 * len(name) + 0.3
    fig.savefig(out, facecolor=BG)
    plt.close(fig)


def waveform(rows, dis, out, max_cycle=None):
    last = max_cycle or rows[-1]["cycle"]
    rows = [r for r in rows if r["cycle"] <= last]
    first = rows[0]["cycle"]
    sigs = ["clk", "pc_f", "IF/ID", "ID/EX", "EX/MEM", "MEM/WB", "stall", "flush"]
    cw, rh, left = 0.5, 0.5, 1.4
    W = left + len(rows) * cw + 0.4
    H = 1.3 + len(sigs) * rh + 0.3
    fig = plt.figure(figsize=(W, H), dpi=200)
    fig.patch.set_facecolor(BG)
    ax = fig.add_axes([0, 0, 1, 1])
    ax.set_xlim(0, W)
    ax.set_ylim(H, 0)
    ax.axis("off")
    ax.text(0.3, 0.42, "rv32i-core  ·  pipeline waveform", color=FG, fontsize=15, fontweight="bold", va="center")
    ax.text(0.3, 0.8, "PC in each pipeline register per cycle (low 16 bits). Gaps are bubbles.",
            color=MUTED, fontsize=8.5, va="center")
    top = 1.15
    green, amber = "#3ddc84", "#ffcc4d"
    for j, name in enumerate(sigs):
        y = top + j * rh
        ax.text(0.3, y + rh / 2, name, color=FG, fontsize=8, va="center", fontfamily=MONO)
        ylo, yhi = y + rh * 0.8, y + rh * 0.2
        if name == "clk":
            xs, ys = [], []
            for k in range(len(rows)):
                x = left + k * cw
                xs += [x, x, x + cw / 2, x + cw / 2]
                ys += [ylo, yhi, yhi, ylo]
            ax.plot(xs + [left + len(rows) * cw], ys + [ylo], color=green, lw=1)
            continue
        if name in ("stall", "flush"):
            key = name
            xs, ys = [left], []
            for k, r in enumerate(rows):
                v = yhi if r[key] else ylo
                ys += [v, v]
                xs += [left + (k + 1) * cw, left + (k + 1) * cw]
            ax.plot(xs[:-1], ys, color=STALL if name == "stall" else amber, lw=1.2)
            continue
        idx = sigs.index(name) - 1
        vals = [r["pcs"][idx] for r in rows]
        k = 0
        while k < len(vals):
            e = k
            while e + 1 < len(vals) and vals[e + 1] == vals[k]:
                e += 1
            x0, x1 = left + k * cw, left + (e + 1) * cw
            ym = y + rh / 2
            if vals[k] is None:
                ax.plot([x0, x1], [ym, ym], color="#c0504d", lw=1)
            else:
                d = 0.06
                ax.fill([x0, x0 + d, x1 - d, x1, x1 - d, x0 + d], [ym, yhi, yhi, ym, ylo, ylo],
                        fc="#1b2a22", ec=green, lw=0.9)
                ax.text((x0 + x1) / 2, ym, f"{vals[k] & 0xffff:04x}", color=green, fontsize=5.4,
                        ha="center", va="center", fontfamily=MONO)
            k = e + 1
    for k in range(len(rows) + 1):
        x = left + k * cw
        ax.add_line(plt.Line2D([x, x], [top, top + len(sigs) * rh], color=GRID, lw=0.4, zorder=0))
    fig.savefig(out, facecolor=BG)
    plt.close(fig)


if __name__ == "__main__":
    log, dump, outdir = sys.argv[1], sys.argv[2], Path(sys.argv[3])
    outdir.mkdir(parents=True, exist_ok=True)
    rows, dis = load_log(log), load_disasm(dump)
    pipeline_diagram(rows, dis, outdir / "pipeline.png")
    waveform(rows, dis, outdir / "waveform.png", max_cycle=34)
    print(f"wrote {outdir / 'pipeline.png'} and {outdir / 'waveform.png'}")
