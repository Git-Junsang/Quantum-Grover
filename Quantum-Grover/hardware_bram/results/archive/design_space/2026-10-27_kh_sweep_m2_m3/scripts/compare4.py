#!/usr/bin/env python3
"""Four-way K/H comparison: {M2, M3} x {prune0 (before), EXACT_PRUNE=6 (after)}.

Cell sources, in order of preference
  integrated bench500 CSV (measured)  -> value
  fitted model (kh40_<tag>.csv, after-only, K1/K2/K5) -> value marked "추정"
  otherwise -> "미실행"
"""
import csv
from pathlib import Path

S = Path("/tmp/claude-1000/-workspace/e2bf3af7-5088-4566-a65a-8c884cbf49eb/scratchpad")
BASE = 5_255_084  # M2 prune0 K3H3, current main RTL (memo compaction), integrated bench500

CONFIGS = [
    ("M2 최적화 전 (prune 0)", [S / "kh_m2/k{k}h{h}_p0.csv"], None),
    ("M3 최적화 전 (prune 0)", [S / "kh_m3p0/k{k}h{h}_p0.csv", S / "v2/b500/bench500_m3_p0.csv"], None),
    ("M3 최적화 후 (모드 6)", [S / "kh/k{k}h{h}_p6.csv"], "m3"),
    ("M2 최적화 후 (모드 6)", [S / "kh_m2/k{k}h{h}_p6.csv"], "m2"),
]


def measured(paths, k, h):
    for p in paths:
        p = Path(str(p).format(k=k, h=h))
        if "{k}" not in str(paths[0]) and (k, h) != (3, 3):
            continue
        if p.exists() and ("{k}" in str(p) or True):
            rows = [r for r in csv.DictReader(l for l in open(p) if not l.startswith("#"))
                    if r["mode"] != "normal"]
            if len(rows) == 500:
                return sum(int(r["cycles"]) for r in rows), sum(int(r["policy_stall"]) for r in rows)
    return None


def model(tag, k, h):
    if tag is None:
        return None
    f = S / f"h40/kh40_{tag}.csv"
    for r in csv.DictReader(open(f)):
        if r["mode"] == "6" and int(r["k"]) == k and int(r["h"]) == h and r["level"] == "model":
            return int(r["total"]), int(r["stall"])
    return None


def cell(cfg, k, h):
    name, paths, tag = cfg
    m = None
    for p in paths:
        pp = Path(str(p).format(k=k, h=h))
        if "{k}" not in str(p) and (k, h) != (3, 3):
            continue
        if pp.exists():
            rows = [r for r in csv.DictReader(l for l in open(pp) if not l.startswith("#"))
                    if r["mode"] != "normal"]
            if len(rows) == 500:
                m = (sum(int(r["cycles"]) for r in rows), sum(int(r["policy_stall"]) for r in rows), "실측")
                break
    if m is None:
        e = model(tag, k, h)
        if e:
            m = (*e, "추정")
    return m


def main():
    out = []
    lines = []
    for cfg in CONFIGS:
        lines.append(f"\n### {cfg[0]}\n")
        lines.append("| K \\ H | " + " | ".join(f"H{h}" for h in range(1, 9)) + " |")
        lines.append("|---|" + "---:|" * 8)
        for k in range(1, 6):
            cells = []
            for h in range(1, 9):
                c = cell(cfg, k, h)
                if c is None:
                    cells.append("미실행")
                    out.append(dict(config=cfg[0], k=k, h=h, total="", stall="", source="미실행"))
                    continue
                tot, st, src = c
                pct = 100 * (tot - BASE) / BASE
                tag = "" if src == "실측" else " (추정)"
                star = "†" if (k in (3, 4) and h >= 7) else ""
                cells.append(f"{tot:,} ({pct:+.1f}%){tag}{star}")
                out.append(dict(config=cfg[0], k=k, h=h, total=tot, stall=st, source=src))
            lines.append(f"| K{k} | " + " | ".join(cells) + " |")
    best = []
    for cfg in CONFIGS:
        rows = [r for r in out if r["config"] == cfg[0] and r["source"] == "실측" and r["h"] <= 6]
        if rows:
            b = min(rows, key=lambda r: r["total"])
            best.append((cfg[0], f"K{b['k']}H{b['h']}", b["total"], 100 * (b["total"] - BASE) / BASE, len(rows)))
    (S / "h40/compare4.md").write_text("\n".join(lines) + "\n")
    w = csv.DictWriter(open(S / "h40/compare4.csv", "w", newline=""), fieldnames=list(out[0]))
    w.writeheader(); w.writerows(out)
    print("\n".join(lines))
    print("\nBEST (measured, H<=6):")
    for b in best:
        print(f"  {b[0]}: {b[1]} {b[2]:,} ({b[3]:+.2f}%)  measured cells={b[4]}")


if __name__ == "__main__":
    main()
