"""verify_cpp_rtl_vs_golden_common500.py : C++ model B vs team golden model vs 09/08 board (Common500).

For every workload and policy the script checks, attempt by attempt:
requested_j, source_j, physical iterations, integer CDF threshold, result index
and success. It also checks result_index / trial_count / L_BBHT /
actual_grover_iterations against the FPGA per-run CSVs.
"""
from __future__ import annotations

import argparse
import csv
import json
import sys
from dataclasses import replace
from pathlib import Path

from repo_paths import COMMON500_FPGA, use_golden


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--runs", required=True, help="dir with rtl_<policy>.csv/.jsonl (grover_bench --trace)")
    ap.add_argument("--policies", default="normal,k4h4,k3h3")
    args = ap.parse_args()
    use_golden()
    from benchmark_dataset import build_official_board_benchmark_dataset
    from checkpoint_bbht_model import V098AutomaticCore

    board_files = {
        "normal": "fpga_normal_per_run.csv",
        "k4h4": "fpga_checkpoint_k4h4_per_run.csv",
        "k3h3": "fpga_final_k3h3_e4_m2_per_run.csv",
    }
    ok = True
    for policy in args.policies.split(","):
        traces = {}
        for line in open(Path(args.runs) / f"rtl_{policy}.jsonl"):
            rec = json.loads(line)
            traces[(rec["target_count"], rec["seed_index"])] = rec["attempts"]
        cpp_rows = {(int(r["target_count"]), int(r["seed_index"])): r
                    for r in csv.DictReader(open(Path(args.runs) / f"rtl_{policy}.csv"))}
        board = {(int(r["target_count"]), int(r["seed_index"])): r
                 for r in csv.DictReader(open(COMMON500_FPGA / board_files[policy], encoding="utf-8-sig"))}
        datasets = {}
        attempt_total = attempt_bad = wl_bad = board_bad = 0
        for (m, s), attempts in sorted(traces.items()):
            if m not in datasets:
                datasets[m] = build_official_board_benchmark_dataset(m)
            ds = datasets[m]
            row = cpp_rows[(m, s)]
            cfg = replace(ds.config, seed_j=int(row["seed_j"], 16), seed_meas=int(row["seed_meas"], 16), shot_cap=100)
            py = V098AutomaticCore(ds, cfg).run_single(mode=policy.upper())
            py_att = [[a.requested_j, a.source_j, a.physical_iterations, a.measurement_threshold,
                       a.result_index, int(a.success)] for a in py.attempts]
            attempt_total += len(py_att)
            if py_att != attempts:
                attempt_bad += 1
                if attempt_bad <= 3:
                    for i, (x, y) in enumerate(zip(py_att, attempts)):
                        if x != y:
                            print(f"  [{policy}] M={m} seed={s} attempt {i}: python={x} cpp={y}")
                            break
            cpp_key = (row["result_index"], row["trial_count"], row["L_BBHT"], row["actual_grover_iterations"])
            py_key = (str(py.result_index), str(py.trial_count), str(py.L_BBHT), str(py.actual_grover_iterations))
            if cpp_key != py_key:
                wl_bad += 1
            b = board[(m, s)]
            if cpp_key != (b["result_index"], b["trial_count"], b["l_bbht"], b["actual_iter"]):
                board_bad += 1
        n = len(traces)
        print(f"{policy}: workloads {n}, attempts {attempt_total}, "
              f"attempt-trace mismatches {attempt_bad}, workload mismatches vs Python {wl_bad}, "
              f"vs FPGA board {board_bad}")
        ok &= attempt_bad == 0 and wl_bad == 0 and board_bad == 0
    print("PASS" if ok else "FAIL")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
