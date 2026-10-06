"""golden_baseline.py : model G, the team's Python golden model, timed like every other backend.

Runs software/models/rtl_reference_model/checkpoint_bbht_model.py
(V098AutomaticCore.run_single) unchanged, from the team folder, on the same
workloads and with the same timing tiers as the other backends (campaign.py).
It is RTL-exact (signed Q1.22, integer sampler), so its trajectories and
physical iterations equal the FPGA and the C++ RTL-exact model (B) workload by
workload; run_all.sh checks that.

  normal | k3h3 | k4h4 | allj   -> run_single(mode="NORMAL" | "K3H3" | "K4H4" | "DRAM_ALL_J")
  backend names                     GOLDEN_PY_NORMAL, GOLDEN_PY_K3H3, ...

Timing (per workload, ns):
  search_ns       run_single() wall time: the golden model's own per-search work
                  (oracle mask from the dataset image, j draws, Q1.22 iterations,
                  checkpoint policy, integer Born measurement)
  compute_ns      time inside rtl_run_core (the Q1.22 Grover iterations). Measured
                  by wrapping the module attribute checkpoint_bbht_model.rtl_run_core
                  in memory; no team file is changed
  prep_ns         building the dataset with the team generator (benchmark_dataset.py)
  --workers W     throughput mode: W processes, one per CPU (campaign.py)

The golden model is a correctness reference written for clarity, not speed (Python
integers / NumPy int64). Its time shows what a straightforward Python RTL model
costs; it is not a SW speed baseline.

  python3 baselines/golden_baseline.py --policy k3h3 --pred EQ --reps 1 --out g.csv --summary g.json
"""
from __future__ import annotations

import argparse
import sys
import time
from dataclasses import replace
from pathlib import Path

sys.dont_write_bytecode = True   # never write __pycache__ into the team folders
HERE = Path(__file__).resolve().parent
SOFTWARE = HERE.parents[1]
sys.path.insert(0, str(HERE))
for d in ("models/common", "models/rtl_reference_model"):
    sys.path.insert(0, str(SOFTWARE / d))

import campaign  # noqa: E402
import checkpoint_bbht_model as golden  # noqa: E402
from benchmark_dataset import (  # noqa: E402
    build_official_board_benchmark_dataset,
    build_predicate_benchmark_dataset,
)

MODES = {"normal": "NORMAL", "k3h3": "K3H3", "k4h4": "K4H4", "allj": "DRAM_ALL_J"}

# compute_ns: time spent in the Q1.22 core. The golden module calls rtl_run_core by
# its module-level name, so wrapping that attribute (in this process only) sees
# every call from NORMAL and from both checkpoint references.
_CORE_NS = [0]
_rtl_run_core = golden.rtl_run_core


def _timed_rtl_run_core(*args, **kwargs):
    t0 = time.perf_counter_ns()
    try:
        return _rtl_run_core(*args, **kwargs)
    finally:
        _CORE_NS[0] += time.perf_counter_ns() - t0


golden.rtl_run_core = _timed_rtl_run_core


class GoldenBackend:
    precision = "q1.22"

    def __init__(self, args, pred: str, a: int, b: int) -> None:
        self.args, self.pred = args, pred
        self.mode = MODES[args.policy]
        self.name = f"GOLDEN_PY_{args.policy.upper()}"
        if args.pred and (a, b) != campaign.PREDICATE500_THRESHOLDS[pred]:
            raise SystemExit("golden_baseline uses the Predicate500 thresholds of the team generator")

    def open_dataset(self, m: int):
        if self.args.pred:
            build = lambda: build_predicate_benchmark_dataset(self.pred, m)
        else:
            build = lambda: build_official_board_benchmark_dataset(m)
        ds, prep = campaign.timed_prep(build, self.args.reps)
        return ds, prep

    def search(self, ds, seed_j: int, seed_meas: int):
        cfg = replace(ds.config, seed_j=seed_j, seed_meas=seed_meas, shot_cap=100)
        c0 = _CORE_NS[0]
        t0 = time.perf_counter_ns()
        r = golden.V098AutomaticCore(ds, cfg).run_single(mode=self.mode)
        call = time.perf_counter_ns() - t0
        return (r.success, r.termination_reason, r.result_index, r.trial_count, r.L_BBHT,
                r.actual_grover_iterations, _CORE_NS[0] - c0, call)

    def build_ns(self, ds) -> int:
        return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    campaign.add_common_args(ap, tuple(MODES), default_reps=1)
    args = ap.parse_args()
    pred, a, b = campaign.resolve_oracle(args)
    return campaign.run_campaign(GoldenBackend(args, pred, a, b), args, pred, a, b)


if __name__ == "__main__":
    raise SystemExit(main())
