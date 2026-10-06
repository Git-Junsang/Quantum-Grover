"""summarize_results.py : merge every backend CSV with the FPGA board results and write the comparison report.

Two workload sets:
  --workload common500   (default) EQ 12345, 500 workloads. FPGA rows come from
                         software/experiments/common500_benchmark/inputs/fpga/*.csv (2026-09-08 board 500-run).
  --workload predicate500  LT/GT/EQ/RANGE x 500 = 2,000 workloads. FPGA rows come
                         from the 2026-10-04 board result.csv files (--board).

Two FPGA references, so every SW number is read against both:
  policy ref    = FPGA with the K3/H3 checkpoint policy (K3/H3-E4-M2)
  standard ref  = FPGA running standard BBHT, no checkpoint policy
                  (common500: Normal-E1; predicate500: NORMAL on the E4-M2 bitstream)
The SW main baseline (standard BBHT, no policy) is compared like-for-like with the
standard ref; the policy ref shows the whole design.

Speedups are ratios of TOTAL search time over exactly the same workloads
(Hoefler & Belli: summarize costs, not ratios).

Outputs (in --out-dir): all_backends.csv, summary_by_backend.csv, report.md
"""
from __future__ import annotations

import argparse
import csv
import json
from collections import defaultdict
from pathlib import Path
from statistics import median

from scipy.stats import ks_2samp, mannwhitneyu

from repo_paths import BOARD_P500_FILES, COMMON500_FPGA as COMMON500_FPGA_DIR

TARGETS = (1, 4, 16, 64, 256)
PREDICATES = ("LT", "GT", "EQ", "RANGE")
COMMON500_FPGA = {
    "FPGA_NORMAL_E1": "fpga_normal_per_run.csv",
    "FPGA_K4H4_E1": "fpga_checkpoint_k4h4_per_run.csv",
    "FPGA_K3H3_E4_M2": "fpga_final_k3h3_e4_m2_per_run.csv",
}
BOARD_NAMES = {   # (branch, mode) in the 10/04 board result.csv
    ("bram", "ckpt"): "FPGA_K3H3_E4_M2",
    ("bram", "normal"): "FPGA_NORMAL_E4_M2",
    ("nocheckpoint", "normal"): "FPGA_NOCKPT_NORMAL_E4",
    ("dram", "normal"): "FPGA_DRAM_ALLJ_SESSION",
}


def key(r):
    return r.get("predicate") or "EQ", int(r["target_count"]), int(r["seed_index"])


def traj(r):
    return str(r["result_index"]), str(r["trial_count"]), str(r["L_BBHT"])


def load_runs(run_dir: Path) -> dict[str, dict]:
    """grover_bench / numpy_baseline / qiskit_baseline CSVs; per-predicate files of one backend are merged."""
    out: dict[str, dict] = {}
    for path in sorted(run_dir.glob("*.csv")):
        rows = list(csv.DictReader(open(path)))
        if not rows or "search_ns" not in rows[0]:
            continue
        name = rows[0]["backend"]
        if rows[0].get("threads", "1") not in ("", "1"):
            name += f"_T{rows[0]['threads']}"
        if rows[0].get("workers", "1") not in ("", "1"):
            name += f"_W{rows[0]['workers']}"
        js = path.with_suffix(".json")
        meta = json.loads(js.read_text()) if js.exists() else {}
        b = out.setdefault(name, {"rows": [], "files": [], "metas": []})
        b["rows"].extend(rows)
        b["files"].append(path.name)
        b["metas"].append(meta)
    return out


def load_common500_fpga(fpga_dir: Path) -> dict[str, dict]:
    out = {}
    for name, fn in COMMON500_FPGA.items():
        rows = []
        for r in csv.DictReader(open(fpga_dir / fn, encoding="utf-8-sig")):
            rows.append({
                "predicate": "EQ", "target_count": r["target_count"], "seed_index": r["seed_index"],
                "result_index": r["result_index"], "trial_count": r["trial_count"], "L_BBHT": r["l_bbht"],
                "actual_grover_iterations": r["actual_iter"], "success": r["success"],
                "search_ns": str(int(float(r["elapsed_us"]) * 1000)), "compute_ns": "", "e2e_ns": "",
            })
        out[name] = {"rows": rows, "files": [fn], "metas": []}
    return out


def load_board_results(paths: list[str]) -> dict[str, dict]:
    out: dict[str, dict] = {}
    for p in paths:
        for r in csv.DictReader(open(p, encoding="utf-8-sig")):
            name = BOARD_NAMES[(r["branch"], r["mode"])]
            b = out.setdefault(name, {"rows": [], "files": [p], "metas": []})
            b["rows"].append({
                "predicate": r["predicate"], "target_count": r["target_count"], "seed_index": r["seed_index"],
                "result_index": r["result_index"], "trial_count": r["trial_count"], "L_BBHT": r["L_BBHT"],
                "actual_grover_iterations": r["actual_iter"], "success": int(r["outcome"] == "HIT"),
                "search_ns": str(int(float(r["wall_us"]) * 1000)), "compute_ns": "", "e2e_ns": "",
            })
    return out


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--runs", required=True, help="dir with SW CSVs (+ .json summaries)")
    ap.add_argument("--workload", choices=("common500", "predicate500"), default="common500")
    ap.add_argument("--fpga-common500", default=str(COMMON500_FPGA_DIR), help="09/08 board per-run CSVs (common500)")
    ap.add_argument("--board", nargs="*", default=[str(p) for p in BOARD_P500_FILES],
                    help="10/04 board result.csv files (predicate500)")
    ap.add_argument("--out-dir", required=True)
    ap.add_argument("--env-note", default="")
    a = ap.parse_args()
    out = Path(a.out_dir)
    out.mkdir(parents=True, exist_ok=True)

    if a.workload == "common500":
        fpga = load_common500_fpga(Path(a.fpga_common500))
        policy_ref, std_ref = "FPGA_K3H3_E4_M2", "FPGA_NORMAL_E1"
        fpga_note = ("Arty A7-100T, 2026-09-08 board 500-run (EQ). Standard ref = Normal-E1 "
                     "(different bitstream from K3/H3-E4-M2).")
    else:
        fpga = load_board_results(a.board)
        policy_ref, std_ref = "FPGA_K3H3_E4_M2", "FPGA_NORMAL_E4_M2"
        fpga_note = ("Arty A7-100T, 2026-10-04 board Predicate500. K3/H3-E4-M2 and NORMAL (E4-M2) come from "
                     "the same bitstream (burst_enable 1/0); NOCKPT = Normal-E4 build; DRAM = DDR3 all-j table.")
    backends = {**fpga, **load_runs(Path(a.runs))}

    # ------------------------------------------------------------ per-M tables
    summary, totals = [], {}
    for name, b in backends.items():
        rows = b["rows"]
        tot = {"search": 0, "compute": 0, "e2e": 0, "n": len(rows)}
        groups = defaultdict(list)
        for r in rows:
            groups[(r.get("predicate") or "EQ", int(r["target_count"]))].append(r)
        for (pred, m), rs in sorted(groups.items()):
            s = [int(r["search_ns"]) for r in rs]
            c = [int(r["compute_ns"]) for r in rs if r.get("compute_ns")]
            e = [int(r["e2e_ns"]) for r in rs if r.get("e2e_ns")]
            summary.append({
                "backend": name, "predicate": pred, "target_count": m, "runs": len(rs),
                "success_rate": sum(int(r["success"]) for r in rs) / len(rs),
                "median_trial_count": median(int(r["trial_count"]) for r in rs),
                "median_L_BBHT": median(int(r["L_BBHT"]) for r in rs),
                "sum_physical_iterations": sum(int(r["actual_grover_iterations"] or 0) for r in rs),
                "search_ms_sum": sum(s) / 1e6, "search_us_median": median(s) / 1e3,
                "compute_ms_sum": sum(c) / 1e6 if c else "", "e2e_ms_sum": sum(e) / 1e6 if e else "",
            })
            tot["search"] += sum(s); tot["compute"] += sum(c); tot["e2e"] += sum(e)
        totals[name] = tot
    with open(out / "summary_by_backend.csv", "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(summary[0]))
        w.writeheader(); w.writerows(summary)
    common = ["backend", "predicate", "target_count", "seed_index", "success", "result_index", "trial_count",
              "L_BBHT", "actual_grover_iterations", "compute_ns", "search_ns", "e2e_ns"]
    with open(out / "all_backends.csv", "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=common)
        w.writeheader()
        for name, b in backends.items():
            for r in b["rows"]:
                w.writerow({**{k: r.get(k, "") for k in common}, "backend": name, "predicate": key(r)[0]})

    # ------------------------------------------------------------- timing
    pol_t = {key(r): int(r["search_ns"]) for r in backends[policy_ref]["rows"]}
    std_t = {key(r): int(r["search_ns"]) for r in backends[std_ref]["rows"]}
    t_lines = ["| Backend | runs | search total (ms) | compute total (ms) | E2E total (ms) | "
               f"FPGA {policy_ref.replace('FPGA_', '')} is faster by | FPGA {std_ref.replace('FPGA_', '')} is faster by |",
               "| --- | ---: | ---: | ---: | ---: | ---: | ---: |"]
    for name, t in sorted(totals.items(), key=lambda kv: kv[1]["search"] / max(kv[1]["n"], 1)):
        rows = backends[name]["rows"]
        comp = f"{t['compute']/1e6:.1f}" if t["compute"] else "-"
        e2e = f"{t['e2e']/1e6:.1f}" if t["e2e"] else "-"
        pk = [key(r) for r in rows if key(r) in pol_t]
        sk = [key(r) for r in rows if key(r) in std_t]
        sel = {key(r): int(r["search_ns"]) for r in rows}
        r1 = f"{sum(sel[k] for k in pk) / sum(pol_t[k] for k in pk):.2f}x" if pk else "-"
        r2 = f"{sum(sel[k] for k in sk) / sum(std_t[k] for k in sk):.2f}x" if sk else "-"
        t_lines.append(f"| `{name}` | {t['n']} | {t['search']/1e6:.1f} | {comp} | {e2e} | {r1} | {r2} |")

    # ---------------------------------------------------------- throughput
    pol_total = sum(pol_t.values())
    fpga_thr = len(pol_t) / (pol_total / 1e9)
    thr_lines = ["| Backend | workers | searches per second | FPGA K3/H3 is faster by |", "| --- | ---: | ---: | ---: |",
                 f"| `{policy_ref}` | 1 engine | {fpga_thr:,.0f} | 1.00x |"]
    for name, b in sorted(backends.items()):
        # one summary JSON per predicate file: pool searches and wall time over all of them
        ms = [m for m in b["metas"] if m.get("throughput_searches_per_s") and m.get("campaign_wall_ns")
              and int(m.get("workers", 1)) > 1]
        if not ms:
            continue
        searches = sum(m["throughput_searches_per_s"] * m["campaign_wall_ns"] / 1e9 for m in ms)
        t = searches / (sum(m["campaign_wall_ns"] for m in ms) / 1e9)
        n = sum(int(m.get("workloads", 0)) for m in ms)
        thr_lines.append(f"| `{name}` ({n} workloads) | {ms[0]['workers']} | {t:,.0f} | {fpga_thr / t:.2f}x |")

    # --------------------------------------------------------- equivalence
    ref_traj = {key(r): traj(r) for r in backends[std_ref]["rows"]}
    float_ref = ("NUMPY_NORMAL_F64" if "NUMPY_NORMAL_F64" in backends else None) or \
        next((n for n in backends if n.startswith("NUMPY")), None) or \
        next((n for n in backends if n.startswith("CPP_SW_BEST_NORMAL_F64")), None)
    float_traj = {key(r): traj(r) for r in backends[float_ref]["rows"]} if float_ref else {}
    eq_lines = [f"| Backend | = FPGA trajectory | = float trajectory (`{float_ref}`) |", "| --- | ---: | ---: |"]
    for name, b in backends.items():
        rows = b["rows"]
        f_ok = sum(traj(r) == ref_traj.get(key(r)) for r in rows)
        fl_ok = sum(traj(r) == float_traj.get(key(r)) for r in rows)
        eq_lines.append(f"| `{name}` | {f_ok}/{len(rows)} | {fl_ok}/{len(rows)} |")

    # ----------------------------------------------- float vs RTL distributions
    dist_lines = ["| predicate | M | float success | FPGA success | trials median float / FPGA | "
                  "Mann-Whitney p (trials) | KS p (L_BBHT) |", "| --- | ---: | ---: | ---: | --- | ---: | ---: |"]
    low_p = 0
    if float_ref:
        fr, rr = defaultdict(list), defaultdict(list)
        for r in backends[float_ref]["rows"]:
            fr[key(r)[:2]].append(r)
        for r in backends[std_ref]["rows"]:
            rr[key(r)[:2]].append(r)
        for g in sorted(fr):
            if g not in rr:
                continue
            ft = [int(r["trial_count"]) for r in fr[g]]; rt = [int(r["trial_count"]) for r in rr[g]]
            fl = [int(r["L_BBHT"]) for r in fr[g]]; rl = [int(r["L_BBHT"]) for r in rr[g]]
            p_mw, p_ks = mannwhitneyu(ft, rt).pvalue, ks_2samp(fl, rl).pvalue
            low_p += (p_mw < 0.05) + (p_ks < 0.05)
            dist_lines.append(f"| {g[0]} | {g[1]} | {sum(int(r['success']) for r in fr[g])}/{len(ft)} | "
                              f"{sum(int(r['success']) for r in rr[g])}/{len(rt)} | {median(ft)} / {median(rt)} | "
                              f"{p_mw:.3f} | {p_ks:.3f} |")

    report = f"""# {a.workload} backend comparison

SW environment: {a.env_note or 'see each summary json'}.
FPGA: {fpga_note} Board time = command-to-DONE (DMA load, CSR config and readback excluded).
SW: search_ns = whole BBHT search with the dataset loaded and the oracle mask built.
SW suffixes: `_T<n>` = one search split over n cores (latency mode); `_W<n>` = n searches in parallel (throughput).
`CPP_SW_BEST_K3H3_*_T4` / `CPP_RTL_EXACT_K3H3_T4` = SW counterpart of K3/H3-E4-M2 (K3H3 policy, 4 cores per iteration, hierarchical sampler).
"is faster by" = backend total search time / FPGA total over the same workloads (>1: the FPGA is faster).

## Timing (totals over the same workloads)

{chr(10).join(t_lines)}

## Throughput (multi-core, workloads in parallel)

{chr(10).join(thr_lines)}

## Equivalence

Trajectory = (result_index, trial_count, L_BBHT) per workload; FPGA reference = `{std_ref}`.

{chr(10).join(eq_lines)}

## Float vs fixed-point (FPGA) distributions

Float and Q1.22 state vectors sample different trajectories per seed, so distributions are compared
(two-sided; p > 0.05 = no detectable difference). Tests with p < 0.05: {low_p} of {2 * (len(dist_lines) - 2)}
(about {0.05 * 2 * (len(dist_lines) - 2):.1f} expected by chance).

{chr(10).join(dist_lines)}
"""
    (out / "report.md").write_text(report)
    print(report)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
