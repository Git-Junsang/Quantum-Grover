#!/usr/bin/env python3
import csv
import sys
from collections import defaultdict
from pathlib import Path

def pct_reduce(base, new):
    if base == 0:
        return ""
    return 100.0 * (base - new) / base

def main():
    if len(sys.argv) != 2:
        print("usage: parse_benchmark.py <uart_log.txt>")
        raise SystemExit(2)

    log = Path(sys.argv[1])
    rows = []

    for raw in log.read_text(errors="ignore").splitlines():
        line = raw.strip()
        if line.startswith("# "):
            line = line[2:]
        if not line.startswith("RUN,"):
            continue
        p = next(csv.reader([line]))
        rows.append({
            "target_count": int(p[1]),
            "seed_id": int(p[2]),
            "seed_j": p[3],
            "seed_meas": p[4],
            "mode": p[5],
            "status": int(p[6]),
            "result_valid": int(p[7]),
            "result_index": int(p[8]),
            "result_is_target": int(p[9]),
            "trial_count": int(p[10]),
            "L_BBHT": int(p[11]),
            "actual_iter": int(p[12]),
            "cycle_count": int(p[13]),
            "policy_cycles": int(p[14]),
            "policy_stall": int(p[15]),
            "policy_actions": int(p[16]),
            "memo_hit": int(p[17]),
            "memo_miss": int(p[18]),
            "policy_max_lat": int(p[19]),
            "plan_level": int(p[20]),
            "plan_high": int(p[21]),
            "plan_empty": int(p[22]),
            "plan_hit": int(p[23]),
            "plan_mismatch": int(p[24]),
            "cold_solve": int(p[25]),
            "spec_solve": int(p[26]),
            "terminal_limit": int(p[27]),
            "unexpected_error": int(p[28]),
            "timeout": int(p[29]),
        })

    raw_csv = log.with_suffix(".raw.csv")
    with raw_csv.open("w", newline="") as f:
        if rows:
            w = csv.DictWriter(f, fieldnames=rows[0].keys())
            w.writeheader()
            w.writerows(rows)

    grouped = defaultdict(lambda: defaultdict(list))
    for r in rows:
        grouped[r["target_count"]][r["mode"]].append(r)

    summary_rows = []
    for tc in sorted(grouped):
        n = grouped[tc].get("NORMAL", [])
        k = grouped[tc].get("K4H8", [])
        if not n or not k:
            continue

        n_iter = sum(x["actual_iter"] for x in n)
        k_iter = sum(x["actual_iter"] for x in k)
        n_cycle = sum(x["cycle_count"] for x in n)
        k_cycle = sum(x["cycle_count"] for x in k)

        summary_rows.append({
            "target_count": tc,
            "runs_per_mode": min(len(n), len(k)),
            "normal_success": sum(x["result_valid"] and x["result_is_target"] for x in n),
            "k4_success": sum(x["result_valid"] and x["result_is_target"] for x in k),
            "normal_mean_iter": n_iter / len(n),
            "k4_mean_iter": k_iter / len(k),
            "iter_reduction_pct": pct_reduce(n_iter, k_iter),
            "normal_mean_cycle": n_cycle / len(n),
            "k4_mean_cycle": k_cycle / len(k),
            "cycle_reduction_pct": pct_reduce(n_cycle, k_cycle),
            "k4_plan_mismatch_sum": sum(x["plan_mismatch"] for x in k),
            "k4_mean_policy_stall": sum(x["policy_stall"] for x in k) / len(k),
        })

    summary_csv = log.with_suffix(".summary.csv")
    with summary_csv.open("w", newline="") as f:
        if summary_rows:
            w = csv.DictWriter(f, fieldnames=summary_rows[0].keys())
            w.writeheader()
            w.writerows(summary_rows)

    print(raw_csv)
    print(summary_csv)
    for r in summary_rows:
        print(
            f"T={r['target_count']:3d} "
            f"iter_reduction={r['iter_reduction_pct']:.2f}% "
            f"cycle_reduction={r['cycle_reduction_pct']:.2f}% "
            f"success={r['normal_success']}/{r['runs_per_mode']} "
            f"mismatch={r['k4_plan_mismatch_sum']}"
        )

if __name__ == "__main__":
    main()
