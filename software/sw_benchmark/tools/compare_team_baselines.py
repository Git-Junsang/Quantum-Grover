"""compare_team_baselines.py : team NumPy/Qiskit code vs our baselines, same workloads, same clock.

Answers "is the team code wasting time, and does it time the same thing we do?"
On the same Common500 workloads (EQ 12345) it measures:

  1. Grover core per iteration
       team  numpy_grover_backend.run_grover(mask, j, trace_level="NONE")
       ours  numpy_baseline.NumpyEngine.evolve(j)
  2. Whole BBHT search (wall time of one search, j draws + core + measurement)
       team  bbht_qiskit_runner.run_v098_bbht_numpy / run_v098_bbht_qiskit
             (the functions the team's run_common500_benchmark.py calls)
       ours  bbht_float_common.bbht with NumpyEngine / QiskitEngine
     plus what each side reports as "execution time" (the team's timing_scope).
  3. Logical agreement (result_index, trial_count, L_BBHT) between team and ours.
     The team runners quantize the float state to Q1.22 and use the integer RTL
     sampler; ours use the float sampler of the C++ float model, so per-seed
     paths are expected to differ (both are valid BBHT runs).

  python3 tools/compare_team_baselines.py --seeds 10 --qiskit-seeds 2
"""
from __future__ import annotations

import argparse
import statistics
import sys
import time

import numpy as np

from repo_paths import BASELINES_DIR, COMMON500, use_golden

use_golden()   # also puts software/models/numpy_model and qiskit_model on the path
sys.path.insert(0, str(BASELINES_DIR))
from bbht_float_common import bbht, load_roster  # noqa: E402
from numpy_baseline import NumpyEngine  # noqa: E402


def per_iteration_core(mask, j=64, reps=20):
    from numpy_grover_backend import run_grover
    eng = NumpyEngine(mask)
    run_grover(mask, j, trace_level="NONE")
    eng.evolve(j)
    t0 = time.perf_counter()
    for _ in range(reps):
        run_grover(mask, j, trace_level="NONE")
    team = (time.perf_counter() - t0) / reps / j
    t0 = time.perf_counter()
    for _ in range(reps):
        eng.evolve(j)
    ours = (time.perf_counter() - t0) / reps / j
    return team, ours


def compare_search(kind, mask, roster):
    from bbht_qiskit_runner import run_v098_bbht_numpy, run_v098_bbht_qiskit
    if kind == "numpy":
        eng = NumpyEngine(mask)
        team_call = lambda sj, sm: run_v098_bbht_numpy(mask, seed_j=sj, seed_measurement=sm)
        team_exec = lambda r: r.execution_seconds
    else:
        from qiskit_baseline import QiskitEngine
        eng = QiskitEngine(mask, 1)
        cache = {}
        team_call = lambda sj, sm: run_v098_bbht_qiskit(mask, seed_j=sj, seed_measurement=sm, prepared_cache=cache)
        team_exec = lambda r: r.qiskit_execution_seconds
    t_team, t_ours, x_team, x_ours, same, l_team, l_ours = [], [], [], [], 0, 0, 0
    for _, sj, sm in roster:
        team_call(sj, sm)                       # warm-up: both sides build their circuits here
        bbht(eng, mask, sj, sm, "normal", None)
        t0 = time.perf_counter()
        rt = team_call(sj, sm)
        t_team.append(time.perf_counter() - t0)
        x_team.append(team_exec(rt))
        t0 = time.perf_counter()
        ro = bbht(eng, mask, sj, sm, "normal", None)
        t_ours.append(time.perf_counter() - t0)
        x_ours.append(ro[6] / 1e9)
        same += (rt.result_index, rt.trial_count, rt.L_BBHT) == (ro[2], ro[3], ro[4])
        l_team += rt.L_BBHT
        l_ours += ro[4]
    return sum(t_team), sum(t_ours), sum(x_team), sum(x_ours), same, l_team, l_ours


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--targets", default="1,16,256")
    ap.add_argument("--seeds", type=int, default=10, help="NumPy: first K seeds per M")
    ap.add_argument("--qiskit-seeds", type=int, default=2, help="Qiskit: first K seeds per M (0 = skip)")
    a = ap.parse_args()
    targets = [int(x) for x in a.targets.split(",")]
    roster = load_roster(COMMON500, a.seeds)
    masks = {m: np.fromfile(COMMON500 / "datasets" / f"dataset_target_{m}.bin", dtype="<i2") == 12345 for m in targets}

    team_it, ours_it = per_iteration_core(masks[targets[0]])
    print("## 1. NumPy Grover core, per iteration (j=64, 20 reps)\n")
    print("| code | us / iteration |\n| --- | ---: |")
    print(f"| team run_grover | {team_it * 1e6:.1f} |\n| ours NumpyEngine.evolve | {ours_it * 1e6:.1f} |")
    print(f"\nteam / ours = {team_it / ours_it:.2f}x\n")

    print("## 2. Whole BBHT search, same workloads (warm-up excluded)\n")
    print("Paths differ (different samplers), so the Grover work differs too: compare time per Grover iteration.\n")
    print("| backend | workloads | iterations team / ours | team search us/iter | ours search us/iter | "
          "team / ours | team 'execution' us/iter | ours compute us/iter | same path |")
    print("| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |")
    runs = [("numpy", roster)]
    if a.qiskit_seeds:
        runs.append(("qiskit", roster[: a.qiskit_seeds]))
    for kind, ros in runs:
        tot = [0.0] * 4
        same = n = lt = lo = 0
        for m in targets:
            r = compare_search(kind, masks[m], ros)
            tot = [x + y for x, y in zip(tot, r[:4])]
            same += r[4]
            lt += r[5]
            lo += r[6]
            n += len(ros)
        st, so, xt, xo = tot[0] / lt * 1e6, tot[1] / lo * 1e6, tot[2] / lt * 1e6, tot[3] / lo * 1e6
        print(f"| {kind} | {n} | {lt} / {lo} | {st:.1f} | {so:.1f} | {st/so:.2f}x | {xt:.1f} | {xo:.1f} | {same}/{n} |")
    print("\n'execution' = what the team runner reports: NumPy core time only (NUMPY_CORE_ONLY) or the "
          "Aer run() wall time (AER_EXECUTION_ONLY). Ours: compute_ns (NumPy core / Aer C++ simulation time).")
    print("Same path: identical (result_index, trial_count, L_BBHT). The samplers differ by design (see doc).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
