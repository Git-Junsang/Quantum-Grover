"""bbht_float_common.py : everything the NumPy and Qiskit baselines share.

Only the state-vector engine differs between numpy_baseline.py and
qiskit_baseline.py. This module holds the BBHT search itself; campaign.py holds
the measurement loop. Both run exactly the same search and are timed exactly
the same way as the C++ runner (grover_bench):

  * J stream       32-bit LFSR, pre-state word then 7 steps per draw
  * m bounds       m0=1, lambda=6/5, m_max=128; logical budget 576; shot cap 100
  * stop rules     SUCCESS, then shot cap, then budget (golden _run_episode order)
  * measurement    xorshift64(13,7,17) -> uniform double -> |a|^2 inverse CDF over
                   128 groups x 128 (the C++ FloatCore sampler)
  * policies       normal | allj | k3h3 | k4h4 (1:1 port of the golden policy code)
  * timing tiers   compute_ns / search_ns / prep_ns / build_ns / e2e_ns
                   (warm-up 1 + reps, median), same names as grover_bench
  * CSV / JSON     same columns as grover_bench, so tools/summarize_results.py
                   merges every backend

Engine interface (implemented by NumpyEngine and QiskitEngine):
  base                       backend name prefix ("NUMPY", "QISKIT_AER")
  ensure(j)                  normal policy: build what j needs (counted in build_ns)
  evolve(j) -> prob          normal policy: H^q|0> then j iterations, |a|^2
  run(state, k, saves)       k iterations from state (None = H^q|0>), returns the
                             states after each count in `saves` (ascending)
  run_all(state, src, req)   all-j: states src+1 .. req
  release(state)             a checkpoint state is no longer used (buffer reuse)
  prob(state) -> |a|^2
  compute_ns                 accumulated pure state-vector evolution time
  call_ns                    accumulated wall time of the engine calls (>= compute_ns;
                             Qiskit: includes Aer's Python-side circuit conversion)
  build_ns                   accumulated circuit build time (Qiskit)
"""
from __future__ import annotations

import argparse
import os
import sys
from functools import lru_cache
from itertools import combinations
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import campaign  # noqa: E402


N = 16384
Q = 14
M_BOUNDS = (1, 2, 2, 2, 3, 3, 3, 4, 5, 6, 7, 8, 9, 11, 13, 16, 19, 23, 27, 32, 39, 47, 56, 67, 80, 96, 115, 128)
BUDGET = 576
SHOT_CAP = 100
MASK64 = (1 << 64) - 1
POLICY_KH = {"k3h3": (3, 3), "k4h4": (4, 4)}


# ------------------------------------------------------------ random streams
class JSource:
    def __init__(self, seed: int) -> None:
        self.state = seed & 0xFFFFFFFF or 0xACE12345

    def clone(self) -> "JSource":
        c = JSource.__new__(JSource)
        c.state = self.state
        return c

    def draw_uniform(self, bound: int) -> int:
        bits = (bound - 1).bit_length()
        mask = (1 << bits) - 1 if bits else 0
        while True:
            value = s = self.state
            for _ in range(7):
                fb = ((s >> 31) ^ (s >> 21) ^ (s >> 1) ^ s) & 1
                s = ((s << 1) & 0xFFFFFFFF) | fb
            self.state = s
            cand = (value & 0xFF) & mask
            if cand < bound:
                return cand


def m_bound(rnd: int) -> int:
    return M_BOUNDS[min(rnd, len(M_BOUNDS) - 1)]


def predict_future_j(js: JSource, next_round: int, count: int) -> tuple[int, ...]:
    clone, out, r = js.clone(), [], next_round
    for _ in range(count):
        out.append(clone.draw_uniform(m_bound(r)))
        r = min(r + 1, len(M_BOUNDS) - 1)
    return tuple(out)


class MeasSource:
    def __init__(self, seed: int) -> None:
        e = seed & 0xFFFFFFFF or 0xBEEFC0DE
        self.state = ((e << 32) | (e ^ 0x9E3779B9)) & MASK64

    def draw_unit(self) -> float:
        block = v = self.state
        v ^= (v << 13) & MASK64
        v ^= v >> 7
        v ^= (v << 17) & MASK64
        self.state = v
        return (block >> 11) * 2.0 ** -53


# --------------------------------------------------------------- measurement
GROUPS = GSIZE = 128


def prepare(prob: np.ndarray):
    """Group CDF over 128 groups of 128 (same structure as the C++ FloatCore sampler)."""
    return prob, np.cumsum(prob.reshape(GROUPS, GSIZE).sum(axis=1))


def sample(prep, rng: MeasSource) -> int:
    prob, gcdf = prep
    t = rng.draw_unit() * gcdf[-1]
    g = min(int(np.searchsorted(gcdf, t, side="right")), GROUPS - 1)
    base = gcdf[g - 1] if g else 0.0
    cum = base + np.cumsum(prob[g * GSIZE:(g + 1) * GSIZE])
    return g * GSIZE + min(int(np.searchsorted(cum, t, side="right")), GSIZE - 1)


# ------------------------------------------------- K/H checkpoint policy
# 1:1 port of checkpoint_bbht_model.py (_deposit_options, _next_states,
# _window_cost, _select_policy_action). Decisions depend only on j values.
def _deposit_options(capacity, source, request, pool, held):
    in_path = sorted({v for v in pool if source < v < request and v not in held})
    options = [(request,)]
    for size in range(1, capacity):
        if size > len(in_path):
            break
        for chosen in combinations(in_path, size):
            options.append(tuple(sorted((*chosen, request))))
    return options


def _next_states(capacity, held, source, request, pool):
    result = []
    keep_pool = tuple(v for v in held if v != request)
    for deposit in _deposit_options(capacity, source, request, pool, held):
        room = capacity - len(deposit)
        if room <= 0:
            result.append(tuple(sorted(deposit)))
        elif len(keep_pool) <= room:
            result.append(tuple(sorted((*keep_pool, *deposit))))
        else:
            for keep in combinations(keep_pool, room):
                result.append(tuple(sorted((*keep, *deposit))))
    return tuple(sorted(set(result)))


@lru_cache(maxsize=1 << 20)
def _window_cost(capacity, held, window, pool):
    if not window:
        return 0
    request, rest = window[0], window[1:]
    source = max((0, *(v for v in held if v <= request)))
    return min(request - source + _window_cost(capacity, s, rest, pool)
               for s in _next_states(capacity, held, source, request, pool))


def select_policy_action(held, request, future, capacity):
    pool = tuple(dict.fromkeys((request, *future)))
    source = max((0, *(v for v in held if v <= request)))
    best, chosen = (float("inf"), float("inf"), ()), held
    for state in _next_states(capacity, held, source, request, pool):
        segments = 1 + sum(source < v < request for v in state)
        cand = (request - source + _window_cost(capacity, state, future, pool), segments, state)
        if cand < best:   # root tie-break of grover_policy.v: (cost, segments, sorted S')
            best, chosen = cand, state
    return source, chosen


class KHCheckpoint:
    """V098CheckpointReference over a float engine. A stored state of None = H^q|0>."""

    def __init__(self, capacity: int, horizon: int, engine) -> None:
        self.capacity, self.horizon, self.engine, self.slots = capacity, horizon, engine, {}

    def invalidate(self) -> None:
        for st in self.slots.values():
            self.engine.release(st)
        self.slots = {}

    def execute(self, engine, requested: int, future: tuple[int, ...]):
        held = tuple(sorted(self.slots))
        source, next_pos = select_policy_action(held, requested, future[: self.horizon], self.capacity)
        if requested in self.slots:           # exact hit: measure the stored state
            return self.slots[requested], 0, requested
        start = self.slots[source] if source in self.slots else None
        generated = {}
        if 0 in next_pos and 0 not in self.slots:
            generated[0] = None
        bounds = sorted(v for v in next_pos if v not in self.slots and source < v <= requested)
        state = start
        if bounds:
            if bounds[-1] != requested:
                raise RuntimeError("checkpoint policy did not materialize requested endpoint")
            states = engine.run(start, requested - source, [b - source for b in bounds])
            generated.update(zip(bounds, states))
            state = states[-1]
        elif source != requested:
            raise RuntimeError("checkpoint policy did not materialize requested endpoint")
        new = {}
        for p in next_pos:
            if p in self.slots:
                new[p] = self.slots[p]
            elif p in generated:
                new[p] = generated[p]
            else:
                raise RuntimeError(f"missing checkpoint state for j={p}")
        for p, st in self.slots.items():   # dropped checkpoints go back to the buffer pool
            if p not in new:
                self.engine.release(st)
        self.slots = new
        return state, requested - source, source


class AllJCheckpoint:
    """V098AllJCheckpointReference: every materialized state is kept for the search."""
    horizon = 0

    def __init__(self, engine=None) -> None:
        self.invalidate()

    def invalidate(self) -> None:
        self.lib, self.top, self.cdf = {0: None}, 0, {}

    def execute(self, engine, requested: int, future=()):
        if requested <= self.top:
            return self.lib[requested], 0, requested
        source = self.top
        states = engine.run_all(self.lib[source], source, requested)
        for i, s in enumerate(states, 1):
            self.lib[source + i] = s
        self.top = requested
        return self.lib[requested], requested - source, source


def make_executor(policy: str, engine):
    if policy == "allj":
        return AllJCheckpoint(engine)
    if policy in POLICY_KH:
        return KHCheckpoint(*POLICY_KH[policy], engine)
    return None


# --------------------------------------------------------------- BBHT search
def bbht(engine, mask: np.ndarray, seed_j: int, seed_meas: int, policy: str, ex):
    """One BBHT search.

    Returns (success, reason, index, trials, L, physical, compute_ns, engine_call_ns).
    """
    js, ms = JSource(seed_j), MeasSource(seed_meas)
    if ex is not None:
        ex.invalidate()
    c0, k0 = engine.compute_ns, engine.call_ns
    L = trials = rnd = physical = 0
    while True:
        j = js.draw_uniform(m_bound(rnd))
        if policy == "normal":
            engine.ensure(j)
            cdf = prepare(engine.evolve(j))
            physical += j
        elif policy == "allj":
            state, phys, _ = ex.execute(engine, j)
            physical += phys
            cdf = ex.cdf.get(j)
            if cdf is None:
                cdf = ex.cdf[j] = prepare(engine.prob(state))
        else:
            future = predict_future_j(js, rnd + 1, ex.horizon)
            state, phys, _ = ex.execute(engine, j, future)
            physical += phys
            cdf = prepare(engine.prob(state))
        idx = sample(cdf, ms)
        L += j
        trials += 1
        t = (engine.compute_ns - c0, engine.call_ns - k0)
        if mask[idx]:
            return (True, "SUCCESS", idx, trials, L, physical, *t)
        if trials >= SHOT_CAP:
            return (False, "SHOT_LIMIT", None, trials, L, physical, *t)
        if L + 1 >= BUDGET:
            return (False, "BUDGET_LIMIT", None, trials, L, physical, *t)
        rnd = min(rnd + 1, len(M_BOUNDS) - 1)


# ------------------------------------------------------------ inputs
def target_mask(data: np.ndarray, pred: str, a: int, b: int) -> np.ndarray:
    """Same oracle as the RTL (v098_target_mask); RANGE is strict a < x < b."""
    if pred == "LT":
        return data < a
    if pred == "GT":
        return data > a
    if pred == "EQ":
        return data == a
    return (data > a) & (data < b)


# ------------------------------------------------------------ campaign / CLI
class FloatBackend:
    """campaign.py backend for a float state-vector engine (NumpyEngine, QiskitEngine)."""

    def __init__(self, engine_cls, args, pred: str, a: int, b: int) -> None:
        self.engine_cls, self.args, self.pred, self.a, self.b = engine_cls, args, pred, a, b
        self.name = f"{engine_cls.base}_{args.policy.upper()}_F64"
        self.precision = "f64"

    def open_dataset(self, m: int):
        path = campaign.dataset_path(self.args, self.pred, m)
        mask, prep = campaign.timed_prep(
            lambda: target_mask(np.fromfile(path, dtype="<i2"), self.pred, self.a, self.b), self.args.reps)
        if int(mask.sum()) != m:
            raise RuntimeError(f"mask count mismatch for M={m}")
        engine = self.engine_cls(mask, getattr(self.args, "threads", 1))
        return (engine, mask, make_executor(self.args.policy, engine)), prep

    def search(self, ctx, seed_j: int, seed_meas: int):
        engine, mask, ex = ctx
        return bbht(engine, mask, seed_j, seed_meas, self.args.policy, ex)

    def build_ns(self, ctx) -> int:
        return ctx[0].build_ns


def run_cli(engine_cls, doc: str, extra_env=None, default_reps: int = 3, allow_workers: bool = True) -> int:
    ap = argparse.ArgumentParser(description=doc, formatter_class=argparse.RawDescriptionHelpFormatter)
    campaign.add_common_args(ap, ("normal", "allj", "k3h3", "k4h4"), default_reps)
    ap.add_argument("--threads", type=int, default=1, help="engine threads (Qiskit Aer); NumPy uses 1")
    args = ap.parse_args()
    if args.workers > 1 and not allow_workers:
        ap.error("--workers is not supported for this backend (use --threads)")
    os.environ.setdefault("OPENBLAS_NUM_THREADS", "1")
    pred, a, b = campaign.resolve_oracle(args)
    return campaign.run_campaign(FloatBackend(engine_cls, args, pred, a, b), args, pred, a, b, extra_env)
