"""numpy_baseline.py : model D, NumPy float64 reference baseline.

Same search, sampler, policies and timing as every other backend
(bbht_float_common.py); only the state-vector engine is NumPy:

  iteration   a *= sign (oracle), a = 2*mean(a) - a (inversion about the mean),
              in place on one preallocated array, no per-iteration allocation
  normal      fresh H^q|0> for every attempt               NUMPY_NORMAL_F64
  allj        library rows lib[j] = G^j|s>, each computed   NUMPY_ALLJ_F64
              straight from the previous row (out of place, no copies)
  k3h3/k4h4   checkpoint buffers come from a reuse pool     NUMPY_K3H3_F64 / NUMPY_K4H4_F64

NumPy runs on one core (OPENBLAS_NUM_THREADS=1; the element-wise kernels are
single-threaded anyway).

  python3 baselines/numpy_baseline.py --policy normal --reps 3 --out numpy.csv --summary numpy.json
  python3 baselines/numpy_baseline.py --policy k3h3 --pred RANGE --out numpy_range.csv
"""
from __future__ import annotations

import sys
import time
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
from bbht_float_common import N, run_cli  # noqa: E402


class NumpyEngine:
    base = "NUMPY"

    def __init__(self, mask: np.ndarray, threads: int = 1) -> None:
        self.sign = np.where(mask, -1.0, 1.0)
        self.a0 = 1.0 / np.sqrt(N)
        self.a = np.empty(N)                     # working vector (normal / checkpoint runs)
        self.uniform = np.full(N, self.a0)       # H^q|0>
        self.uniform_prob = np.full(N, 1.0 / N)
        self.lib = np.empty((128, N))            # all-j library, row j = G^j|s>
        self.pool: list[np.ndarray] = []         # reusable checkpoint buffers
        self.build_ns = 0
        self.compute_ns = 0

    @property
    def call_ns(self) -> int:   # NumPy calls are the computation itself
        return self.compute_ns

    # ---- normal policy
    def ensure(self, j: int) -> None:
        pass

    def evolve(self, j: int) -> np.ndarray:
        t0 = time.perf_counter_ns()
        a, s = self.a, self.sign
        a.fill(self.a0)
        for _ in range(j):
            np.multiply(a, s, out=a)
            m2 = 2.0 * a.sum() / N
            np.subtract(m2, a, out=a)
        p = a * a
        self.compute_ns += time.perf_counter_ns() - t0
        return p

    # ---- checkpoint policies
    def run(self, state, k: int, saves: list[int]) -> list[np.ndarray]:
        t0 = time.perf_counter_ns()
        a, s = self.a, self.sign
        np.copyto(a, self.uniform if state is None else state)
        out, want = [], iter(saves)
        nxt = next(want, None)
        for i in range(1, k + 1):
            np.multiply(a, s, out=a)
            m2 = 2.0 * a.sum() / N
            np.subtract(m2, a, out=a)
            if i == nxt:
                buf = self.pool.pop() if self.pool else np.empty(N)
                np.copyto(buf, a)
                out.append(buf)
                nxt = next(want, None)
        self.compute_ns += time.perf_counter_ns() - t0
        return out

    def run_all(self, state, source: int, requested: int) -> list[np.ndarray]:
        t0 = time.perf_counter_ns()
        s, lib = self.sign, self.lib
        src = self.uniform if state is None else state
        for j in range(source + 1, requested + 1):
            dst = lib[j]
            np.multiply(src, s, out=dst)
            m2 = 2.0 * dst.sum() / N
            np.subtract(m2, dst, out=dst)
            src = dst
        self.compute_ns += time.perf_counter_ns() - t0
        return [lib[j] for j in range(source + 1, requested + 1)]

    def release(self, state) -> None:
        if state is not None:
            self.pool.append(state)

    def prob(self, state) -> np.ndarray:
        return self.uniform_prob if state is None else state * state


if __name__ == "__main__":
    raise SystemExit(run_cli(NumpyEngine, __doc__))
