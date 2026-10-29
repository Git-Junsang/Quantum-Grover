#!/usr/bin/env python3
"""40-cell K/H heatmaps for M3 + seed-first policy (from kh40_m3.csv)."""
import csv, os
from pathlib import Path
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.colors import LinearSegmentedColormap, TwoSlopeNorm
from matplotlib.patches import Rectangle

H = Path(__file__).resolve().parent
TAG = os.environ.get("TAG", "m3")
BASE = os.environ.get("BASE", "4,680,014")
MLABEL = os.environ.get("MLABEL", "M3")
R = list(csv.DictReader(open(H / f"kh40_{TAG}.csv")))
KS, HS = range(1, 6), range(1, 9)

SURFACE, INK, INK2 = "#fcfcfb", "#0b0b0b", "#52514e"
SEQ = ["#cde2fb", "#9ec5f4", "#6da7ec", "#3987e5", "#256abf", "#184f95", "#0d366b"]
DIV = ["#1c5cab", "#3987e5", "#86b6ef", "#f0efec", "#f3a3a3", "#e66767", "#c62f2f"]
seq = LinearSegmentedColormap.from_list("seq", SEQ)
div = LinearSegmentedColormap.from_list("div", DIV)
MARK = {"measured": "M", "rtl+model": "R", "model": "E"}


def grid(mode, key):
    g = np.zeros((len(KS), len(HS)))
    lv = [[None] * len(HS) for _ in KS]
    for r in R:
        if r["mode"] == str(mode):
            i, j = int(r["k"]) - 1, int(r["h"]) - 1
            g[i, j] = float(r[key]); lv[i][j] = r
    return g, lv


def ink_for(rgba):
    lum = 0.2126 * rgba[0] + 0.7152 * rgba[1] + 0.0722 * rgba[2]
    return INK if lum > 0.55 else "#ffffff"


def panel(ax, g, lv, cmap, norm, fmt, title, cbar_label, outline=None):
    im = ax.imshow(g, cmap=cmap, norm=norm, aspect="auto")
    for i in range(len(KS)):
        for j in range(len(HS)):
            r = lv[i][j]
            c = ink_for(cmap(norm(g[i, j])))
            ax.text(j, i - 0.08, fmt(g[i, j], r), ha="center", va="center", fontsize=7.5, color=c)
            ax.text(j + 0.40, i + 0.36, MARK[r["level"]], ha="right", va="bottom", fontsize=5.5, color=c, alpha=0.85)
            if not r["hw"].startswith("yes"):
                hatch = "...." if r["hw"].startswith("partial") else "////"
                ax.add_patch(Rectangle((j - 0.5, i - 0.5), 1, 1, fill=False, hatch=hatch,
                                       edgecolor=(1, 1, 1, 0.35), linewidth=0))
    for (i, j) in (outline or []):
        ax.add_patch(Rectangle((j - 0.47, i - 0.47), 0.94, 0.94, fill=False, edgecolor=INK, linewidth=1.6))
    ax.set_xticks(range(len(HS)), [f"H{h}" for h in HS], fontsize=8, color=INK2)
    ax.set_yticks(range(len(KS)), [f"K{k}" for k in KS], fontsize=8, color=INK2)
    ax.tick_params(length=0)
    for s in ax.spines.values():
        s.set_visible(False)
    ax.set_title(title, fontsize=10, color=INK, loc="left", pad=6)
    cb = plt.colorbar(im, ax=ax, fraction=0.035, pad=0.02)
    cb.ax.tick_params(labelsize=7, colors=INK2, length=0)
    cb.outline.set_visible(False)
    cb.set_label(cbar_label, fontsize=7.5, color=INK2)


def best_feasible(mode):
    rows = [r for r in R if r["mode"] == str(mode) and r["hw"] == "yes"]
    b = min(rows, key=lambda r: int(r["total"]))
    return [(int(b["k"]) - 1, int(b["h"]) - 1)]


def figure(mode, path):
    fig, axs = plt.subplots(2, 2, figsize=(15, 8.2), facecolor=SURFACE)
    for ax in axs.flat:
        ax.set_facecolor(SURFACE)
    g, lv = grid(mode, "vs_m3_prune0_pct")
    # Clip the colour range so the -5..+13 % region stays readable; K1 (+54 %)
    # saturates.  Cell text always carries the exact value.
    lim = 6.0
    panel(axs[0, 0], g, lv, div, TwoSlopeNorm(0, -lim, lim),
          lambda v, r: f"{int(r['total'])/1e6:.3f}M\n{v:+.2f}%",
          f"Total checkpoint cycles vs {MLABEL} prune0 K3H3 ({BASE})", "change vs baseline (%), clipped at +/-6",
          outline=best_feasible(mode))
    g, lv = grid(mode, "phys_reduction_pct")
    panel(axs[0, 1], g, lv, seq, plt.Normalize(g.min(), g.max()),
          lambda v, r: f"{v:.1f}%", "Physical iteration reduction vs Normal (31,424)", "reduction (%)")
    g, lv = grid(mode, "policy_per_decision")
    panel(axs[1, 0], g, lv, seq, plt.Normalize(g.min(), g.max()),
          lambda v, r: f"{v:.0f}", "Policy cycles per decision (standalone RTL / model)", "cycles / decision")
    g, lv = grid(mode, "stall_pct")
    panel(axs[1, 1], g, lv, seq, plt.Normalize(0, g.max()),
          lambda v, r: f"{v:.1f}%", "Exposed policy stall share of total", "stall / total (%)")
    fig.suptitle(f"{MLABEL} + seed-first policy (EXACT_PRUNE={mode}), Common500, RTL cycle axis",
                 x=0.01, ha="left", fontsize=12, color=INK)
    fig.text(0.01, 0.008,
             "M measured (integrated bench500)    R standalone RTL + fitted stall model    E SW features + fitted models (leave-one-out: policy latency within +/-11 %, total within 0.30 % on M cells)    "
             "Outline: best buildable cell\n"
             "//// not buildable now (K1/K2: checkpoint RTL is K3/K4; K5: 5th amplitude slot exceeds 100T BRAM)    "
             ".... Shadow-J supplies 7 futures, so integrated H7/H8 make H6 choices",
             fontsize=7.5, color=INK2, ha="left")
    fig.tight_layout(rect=(0, 0.04, 1, 0.96))
    fig.savefig(path, dpi=160, facecolor=SURFACE)
    plt.close(fig)


if __name__ == "__main__":
    for m in os.environ.get("MODES", "5,6").split(","):
        figure(int(m), H / f"kh40_{TAG}_mode{m}.png")
    print("ok")
