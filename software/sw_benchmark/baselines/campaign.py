"""campaign.py : the measurement loop shared by every Python backend.

numpy_baseline.py, qiskit_baseline.py and golden_baseline.py differ only in how
one search runs. This module does the rest exactly like grover_bench (C++):

  * workloads   Common500 (EQ 12345) or one Predicate500 predicate, M = 1/4/16/64/256,
                the first K seed pairs of the official roster
  * per dataset prep_ns = median of >= 5 timed loads (copied to its workloads)
  * per workload 1 warm-up search, then --reps timed searches, median search_ns
  * --workers W  throughput mode: W processes (fork), each pinned to one CPU of
                 the process mask, pull workloads from a shared queue; the summary
                 reports searches per second over the campaign wall time
  * CSV / JSON  same columns as grover_bench, so summarize_results.py merges them

A backend supplies a Backend object:
  name, precision                               CSV labels
  open_dataset(m) -> (ctx, prep_ns)             load + mask (+ engine) for one dataset
  search(ctx, seed_j, seed_meas)                one BBHT search ->
        (success, reason, index, trials, L, physical, compute_ns, engine_call_ns)
  build_ns(ctx) -> int                          circuit build total for the dataset (Qiskit)
"""
from __future__ import annotations

import argparse
import csv
import json
import multiprocessing as mp
import os
import platform
import re
import statistics
import sys
import time
from pathlib import Path

BENCH_ROOT = Path(__file__).resolve().parents[1]          # software/sw_benchmark
SOFTWARE = BENCH_ROOT.parent                               # team SW tree (read only)
DEFAULT_COMMON500 = SOFTWARE / "experiments" / "common500_benchmark" / "inputs"
DEFAULT_P500_DATASETS = BENCH_ROOT / "data" / "predicate500_datasets"
# Predicate500 oracle thresholds (models/common/benchmark_dataset.py PREDICATE500_SPECS)
PREDICATE500_THRESHOLDS = {"LT": (-16384, 0), "GT": (16383, 0), "EQ": (12345, 0), "RANGE": (-4096, 4096)}


def add_common_args(ap: argparse.ArgumentParser, policies, default_reps: int) -> None:
    ap.add_argument("--policy", choices=policies, default="normal")
    ap.add_argument("--inputs", default=str(DEFAULT_COMMON500),
                    help="seed roster + Common500 datasets (software/experiments/common500_benchmark/inputs)")
    ap.add_argument("--pred", choices=tuple(PREDICATE500_THRESHOLDS),
                    help="Predicate500 predicate; default = Common500 EQ 12345")
    ap.add_argument("--a", type=int, help="threshold A (default: Predicate500 value)")
    ap.add_argument("--b", type=int, help="threshold B, RANGE only (default: Predicate500 value)")
    ap.add_argument("--datasets", default=str(DEFAULT_P500_DATASETS), help="dir with dataset_<PRED>_target_<M>.bin")
    ap.add_argument("--targets", default="1,4,16,64,256")
    ap.add_argument("--seeds", type=int, default=100, help="first K seed pairs of the roster")
    ap.add_argument("--reps", type=int, default=default_reps, help="timed repetitions after 1 warm-up")
    ap.add_argument("--workers", type=int, default=1, help="throughput mode: W processes, one per CPU")
    ap.add_argument("--out", default="baseline.csv")
    ap.add_argument("--summary", default="baseline.json")


def resolve_oracle(args):
    pred = args.pred or "EQ"
    da, db = PREDICATE500_THRESHOLDS[pred] if args.pred else (12345, 0)
    return pred, (da if args.a is None else args.a), (db if args.b is None else args.b)


def dataset_path(args, pred: str, m: int) -> Path:
    return (Path(args.datasets) / f"dataset_{pred}_target_{m}.bin" if args.pred
            else Path(args.inputs) / "datasets" / f"dataset_target_{m}.bin")


def load_roster(inputs: Path, limit: int):
    text = (Path(inputs) / "official_board_seed_roster.h").read_text()
    pairs = re.findall(r"\{\s*(0x[0-9A-Fa-f]+)u?\s*,\s*(0x[0-9A-Fa-f]+)u?\s*\}", text)
    return [(i, int(a, 16), int(b, 16)) for i, (a, b) in enumerate(pairs)][:limit]


def timed_prep(fn, reps: int):
    """Run fn() max(5, reps) times; return (last result, median ns)."""
    out, ts = None, []
    for _ in range(max(5, reps)):
        t0 = time.perf_counter_ns()
        out = fn()
        ts.append(time.perf_counter_ns() - t0)
    return out, int(statistics.median(ts))


# ------------------------------------------------------------ worker side
_BACKEND = None     # set before the pool forks; inherited by the workers
_REPS = 1
_CTX: dict = {}     # per process: m -> (ctx, prep_ns)
_CPU_COUNTER = None


def _measure(m: int, sj: int, sm: int):
    if m not in _CTX:
        _CTX[m] = _BACKEND.open_dataset(m)
    ctx, prep = _CTX[m]
    _BACKEND.search(ctx, sj, sm)                     # warm-up
    searches, computes, calls, res = [], [], [], None
    for _ in range(_REPS):
        t0 = time.perf_counter_ns()
        r = _BACKEND.search(ctx, sj, sm)
        searches.append(time.perf_counter_ns() - t0)
        computes.append(r[6])
        calls.append(r[7])
        res = res or r
    return res, searches, computes, calls, prep


def _pool_init(cpus):
    with _CPU_COUNTER.get_lock():
        k = _CPU_COUNTER.value
        _CPU_COUNTER.value += 1
    if cpus:
        os.sched_setaffinity(0, {cpus[k % len(cpus)]})


def _pool_task(task):
    m, idx, sj, sm = task
    return (m, idx, sj, sm), _measure(m, sj, sm)


# ------------------------------------------------------------ driver
def run_campaign(backend, args, pred: str, a: int, b: int, extra_env=None) -> int:
    global _BACKEND, _REPS, _CPU_COUNTER
    _BACKEND, _REPS = backend, args.reps
    roster = load_roster(args.inputs, args.seeds)
    targets = [int(x) for x in args.targets.split(",")]
    tasks = [(m, idx, sj, sm) for m in targets for idx, sj, sm in roster]
    cpus = sorted(os.sched_getaffinity(0))
    if args.workers > len(cpus):
        raise SystemExit(f"--workers {args.workers} needs that many CPUs; only {len(cpus)} are available")

    results = {}
    wall0 = time.perf_counter_ns()
    if args.workers <= 1:
        for t in tasks:
            results[t] = _measure(t[0], t[2], t[3])
            if t[1] == roster[-1][0]:
                print(f"{backend.name} {pred} M={t[0]} done", flush=True)
    else:
        _CPU_COUNTER = mp.get_context("fork").Value("i", 0)
        with mp.get_context("fork").Pool(args.workers, initializer=_pool_init, initargs=(cpus,)) as pool:
            for key, r in pool.imap_unordered(_pool_task, tasks, chunksize=1):
                results[key] = r
    wall = time.perf_counter_ns() - wall0

    # build_ns (Qiskit circuits) is known per dataset only in the single-process run
    build_per = {}
    if args.workers <= 1:
        for m in targets:
            build_per[m] = backend.build_ns(_CTX[m][0]) // len(roster) if m in _CTX else 0

    rows = []
    for t in tasks:
        m, idx, sj, sm = t
        res, searches, computes, calls, prep = results[t]
        ok, reason, ridx, trials, L, phys, _, _ = res
        search = int(statistics.median(searches))
        bpw = build_per.get(m, 0)
        rows.append({
            "predicate": pred, "threshold_a": a, "threshold_b": b if pred == "RANGE" else 0,
            "target_count": m, "seed_index": idx, "seed_j": f"0x{sj:08x}", "seed_meas": f"0x{sm:08x}",
            "backend": backend.name, "policy": args.policy, "precision": backend.precision,
            "threads": getattr(args, "threads", 1), "workers": args.workers, "reps": args.reps,
            "success": int(ok), "termination_reason": reason,
            "result_index": "" if ridx is None else ridx, "trial_count": trials, "L_BBHT": L,
            "actual_grover_iterations": phys, "compute_ns": int(statistics.median(computes)),
            "search_ns": search, "search_ns_min": min(searches), "prep_ns": prep,
            "build_ns": bpw, "e2e_ns": prep + bpw + search, "engine_call_ns": int(statistics.median(calls)),
        })

    with open(args.out, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0]))
        w.writeheader()
        w.writerows(rows)
    per = {}
    for r in rows:
        p = per.setdefault(str(r["target_count"]), {"search_ns_sum": 0, "compute_ns_sum": 0, "e2e_ns_sum": 0})
        p["search_ns_sum"] += r["search_ns"]
        p["compute_ns_sum"] += r["compute_ns"]
        p["e2e_ns_sum"] += r["e2e_ns"]
    env = {"python": sys.version.split()[0], "platform": platform.platform(), "cpu": platform.processor(),
           "process_cpus": cpus}
    try:
        import numpy as np
        env["numpy"] = np.__version__
    except ImportError:
        pass
    env.update(extra_env(args) if extra_env else {})
    n_searches = len(rows) * (args.reps + 1)
    summary = {
        "backend": backend.name, "policy": args.policy, "predicate": pred,
        "threads": getattr(args, "threads", 1), "workers": args.workers, "reps": args.reps,
        "workloads": len(rows), "success": sum(r["success"] for r in rows),
        "trials": sum(r["trial_count"] for r in rows), "L_BBHT": sum(r["L_BBHT"] for r in rows),
        "physical_iterations": sum(r["actual_grover_iterations"] for r in rows),
        "campaign_wall_ns": wall, "campaign_wall_note": "warm-up + reps + prep for all workloads",
        "throughput_searches_per_s": round(n_searches / (wall / 1e9), 1), "per_target": per,
        "search_ns_sum": sum(r["search_ns"] for r in rows), "compute_ns_sum": sum(r["compute_ns"] for r in rows),
        "e2e_ns_sum_per_workload_load": sum(r["e2e_ns"] for r in rows), "environment": env,
    }
    Path(args.summary).write_text(json.dumps(summary, indent=2) + "\n")
    print(f"{backend.name} {pred} W{args.workers}: success {summary['success']}/{len(rows)} "
          f"trials {summary['trials']} L {summary['L_BBHT']} physical {summary['physical_iterations']} "
          f"search_sum {summary['search_ns_sum']/1e6:.1f} ms compute_sum {summary['compute_ns_sum']/1e6:.1f} ms "
          f"throughput {summary['throughput_searches_per_s']:.0f}/s", flush=True)
    return 0
