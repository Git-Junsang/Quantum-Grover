"""qiskit_baseline.py : model C, Qiskit Aer statevector reference baseline.

Same search, sampler, policies and timing as every other backend
(bbht_float_common.py); only the state-vector engine is a Qiskit circuit run
on AerSimulator(method="statevector", precision="double").

Circuit (same construction as the team's build_requested_j_circuit):
  H^q, then per Grover iteration: DiagonalGate(oracle signs), H^q,
  DiagonalGate(reflection about |0>), H^q, then save_statevector.
  The one-iteration block is transpiled once (optimization_level=0) and reused.

  normal      one circuit per requested j, built once per dataset   QISKIT_AER_NORMAL_F64
  allj        resume circuits: set_statevector(stored state) ->      QISKIT_AER_ALLJ_F64
  k3h3/k4h4   k iterations -> save_statevector at every position     QISKIT_AER_K3H3_F64 ...
              the policy keeps. Built once per (k, save pattern); at run time only
              the initial state is swapped in (O(1)).
  Resuming from a stored state is an emulator technique (a real device cannot
  copy a quantum state): the policy rows show the policy inside a circuit
  simulator, not a circuit a quantum device could run.

Timing (per workload, ns):
  compute_ns       Aer's own simulation time (Result.results[0].time_taken), i.e.
                   the state-vector evolution in Aer's C++ engine
  engine_call_ns   wall time of backend.run(...).result(): compute + Aer's Python-side
                   circuit conversion, which checks every one of the 16,384 diagonal
                   entries of both DiagonalGates for every iteration (about 70% of the
                   call at 14 qubits; a Qiskit library cost, kept in search_ns)
  build_ns         circuit build + transpile, amortized over the dataset's workloads

Threads: --threads T sets max_parallel_threads=T and, for T > 1,
statevector_parallel_threshold=1 (Aer's default of 14 keeps a 14-qubit run
single-threaded).

  python3 baselines/qiskit_baseline.py --policy normal --threads 1 --reps 1 --out qiskit.csv
"""
from __future__ import annotations

import sys
import time
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
from bbht_float_common import N, Q, run_cli  # noqa: E402


class QiskitEngine:
    base = "QISKIT_AER"

    def __init__(self, mask: np.ndarray, threads: int = 1) -> None:
        from qiskit import QuantumCircuit, transpile
        from qiskit.circuit.library import DiagonalGate
        from qiskit_aer import AerSimulator
        from qiskit_aer.library import SetStatevector
        self._QC, self._Set = QuantumCircuit, SetStatevector
        self.build_ns = 0
        self.compute_ns = 0
        self.call_ns = 0
        self.uniform_prob = np.full(N, 1.0 / N)
        t0 = time.perf_counter_ns()
        opts = {"statevector_parallel_threshold": 1} if threads > 1 else {}
        self.backend = AerSimulator(method="statevector", device="CPU", precision="double",
                                    max_parallel_threads=threads, **opts)
        oracle = np.ones(N, dtype=np.complex128)
        oracle[mask] = -1.0
        zero = np.full(N, -1.0, dtype=np.complex128)
        zero[0] = 1.0
        it = QuantumCircuit(Q)
        it.append(DiagonalGate(oracle), range(Q))
        it.h(range(Q))
        it.append(DiagonalGate(zero), range(Q))
        it.h(range(Q))
        self.body = list(transpile(it, self.backend, optimization_level=0).data)
        self.normal = {}   # j -> circuit
        self.resume = {}   # (from_uniform, k, saves) -> circuit
        self.build_ns += time.perf_counter_ns() - t0

    def _circuit(self, from_uniform: bool, k: int, saves: tuple[int, ...]):
        c = self._QC(Q)
        if from_uniform:
            c.h(range(Q))
        else:   # placeholder initial state, replaced at run time
            c.append(self._Set(np.full(N, 1.0 / np.sqrt(N), dtype=np.complex128)), range(Q))
        want = set(saves)
        for i in range(1, k + 1):
            for ins in self.body:
                c._append(ins)
            if i in want:
                c.save_statevector(label=f"s{i}")
        if k == 0 and 0 in want:
            c.save_statevector(label="s0")
        return c

    def _execute(self, c, labels):
        t0 = time.perf_counter_ns()
        res = self.backend.run(c).result()
        data = res.data(0)
        out = [np.asarray(data[label]) for label in labels]
        self.call_ns += time.perf_counter_ns() - t0
        self.compute_ns += int(res.results[0].time_taken * 1e9)
        return out

    # ---- normal policy
    def ensure(self, j: int) -> None:
        if j not in self.normal:   # built once per dataset; the warm-up search builds them
            t0 = time.perf_counter_ns()
            self.normal[j] = self._circuit(True, j, (j,))
            self.build_ns += time.perf_counter_ns() - t0

    def evolve(self, j: int) -> np.ndarray:
        (amp,) = self._execute(self.normal[j], (f"s{j}",))
        return np.abs(amp) ** 2

    # ---- checkpoint policies
    def run(self, state, k: int, saves: list[int]) -> list[np.ndarray]:
        key = (state is None, k, tuple(saves))
        c = self.resume.get(key)
        if c is None:
            t0 = time.perf_counter_ns()
            c = self.resume[key] = self._circuit(state is None, k, tuple(saves))
            self.build_ns += time.perf_counter_ns() - t0
        if state is not None:   # O(1): swap in the stored state as the initial state
            c.data[0] = c.data[0].replace(operation=self._Set(state))
        return self._execute(c, [f"s{i}" for i in saves])

    def run_all(self, state, source: int, requested: int) -> list[np.ndarray]:
        return self.run(state, requested - source, list(range(1, requested - source + 1)))

    def release(self, state) -> None:
        pass

    def prob(self, state) -> np.ndarray:
        return self.uniform_prob if state is None else np.abs(state) ** 2


def qiskit_env(args) -> dict:
    import qiskit
    import qiskit_aer
    return {"qiskit": qiskit.__version__, "qiskit_aer": qiskit_aer.__version__,
            "aer_statevector_parallel_threshold": 1 if args.threads > 1 else "default (14)"}


if __name__ == "__main__":
    raise SystemExit(run_cli(QiskitEngine, __doc__, extra_env=qiskit_env, default_reps=1, allow_workers=False))
