#!/usr/bin/env python3
"""Method 1: exact search acceleration for the rolling restricted-B policy.

This experiment keeps the policy definition bit-for-bit unchanged and changes
only how the exact minimum is found.  It compares the committed memoized DFS
against a memoized depth-first branch-and-bound solver using a capacity-relaxed
admissible lower bound.

The relaxed machine keeps every checkpoint forever and deposits every legal
request-pool value encountered on a path.  Its checkpoint set is therefore a
superset of every capacity-K realization, so its remaining physical cost can
never exceed the real optimum.  Pruning against that bound is exact.
"""

from __future__ import annotations

import argparse
import csv
import json
from dataclasses import dataclass
from pathlib import Path

import kh_sweep


DEFAULT_OUT = (
    kh_sweep.ROOT / "hardware_bram/results/2026-10-26_policy_search_method1"
)


def parse_cells(text: str) -> list[tuple[int, int]]:
    cells: list[tuple[int, int]] = []
    for token in text.split(","):
        token = token.strip().lower()
        if not token:
            continue
        if "h" in token:
            k_text, h_text = token.removeprefix("k").split("h", 1)
        elif ":" in token:
            k_text, h_text = token.split(":", 1)
        else:
            raise ValueError(f"cell must look like K3H3 or 3:3: {token}")
        cell = (int(k_text), int(h_text))
        if cell[0] < 1 or cell[1] < 1:
            raise ValueError(f"K/H must be positive: {token}")
        cells.append(cell)
    if not cells:
        raise ValueError("at least one K/H cell is required")
    return sorted(set(cells))


@dataclass
class ExactStats:
    actions: int = 0
    states: int = 0
    memo_hits: int = 0
    pruned_actions: int = 0
    root_pruned_actions: int = 0
    bound_calls: int = 0
    # Hardware-cost counters for seed-first full-horizon evaluation.  A frame
    # with zero/one legal child needs neither a seed pre-scan nor a bound
    # pipeline transaction.  For the remaining frames, bound_candidates is
    # the number of candidates in the pre-scan and bound_fill_cycles is the
    # sum of the actually-live tail depths (a variable-depth tap can return
    # after that many H-pipeline stages).
    bound_frames: int = 0
    bound_candidates: int = 0
    bound_fill_cycles: int = 0


def relaxed_lower_bound(
    held: tuple[int, ...],
    window: tuple[int, ...],
    pool: tuple[int, ...],
    depth: int,
) -> int:
    """Admissible tail-cost bound obtained by removing the K-capacity limit."""
    checkpoints = set(held)
    cost = 0
    bounded_window = window if depth == 0 else window[:depth]
    for request in bounded_window:
        source = max((0, *(value for value in checkpoints if value <= request)))
        cost += request - source
        checkpoints.add(request)
        checkpoints.update(
            value for value in pool if source < value < request
        )
    return cost


def select_policy_action_bnb(
    held: tuple[int, ...],
    request: int,
    future: tuple[int, ...],
    capacity: int,
    order: str,
    bound_depth: int,
    seed_depth: int,
) -> tuple[int, tuple[int, ...], ExactStats]:
    """Return the exact legacy action using memoized branch-and-bound."""
    pool = tuple(dict.fromkeys((request, *future)))
    stats = ExactStats()
    memo: dict[tuple[tuple[int, ...], tuple[int, ...]], int] = {}
    bound_memo: dict[tuple[tuple[int, ...], tuple[int, ...]], int] = {}

    def bound(state: tuple[int, ...], window: tuple[int, ...]) -> int:
        key = (state, window)
        if key not in bound_memo:
            stats.bound_calls += 1
            bound_memo[key] = relaxed_lower_bound(
                state, window, pool, bound_depth
            )
        return bound_memo[key]

    def seed_bound(state: tuple[int, ...], window: tuple[int, ...]) -> int:
        return relaxed_lower_bound(state, window, pool, seed_depth)

    def window_cost(state: tuple[int, ...], window: tuple[int, ...]) -> int:
        key = (state, window)
        if key in memo:
            stats.memo_hits += 1
            return memo[key]
        if not window:
            return 0

        stats.states += 1
        head, rest = window[0], window[1:]
        source = max((0, *(value for value in state if value <= head)))
        immediate = head - source
        children = kh_sweep.next_states(capacity, state, source, head, pool)
        stats.actions += len(children)
        if order == "seed" and len(children) > 1 and rest:
            stats.bound_frames += 1
            stats.bound_candidates += len(children)
            stats.bound_fill_cycles += len(rest)
        candidates = [(bound(child, rest), child) for child in children]
        if order == "bound":
            candidates.sort()
        elif order == "seed" and candidates:
            seed = min(candidates, key=lambda item: (seed_bound(item[1], rest), item[1]))
            candidates = [seed, *(item for item in candidates if item != seed)]

        best: int | None = None
        for tail_lower, child in candidates:
            if best is not None and immediate + tail_lower >= best:
                stats.pruned_actions += 1
                continue
            candidate = immediate + window_cost(child, rest)
            if best is None or candidate < best:
                best = candidate

        if best is None:
            raise RuntimeError("exact branch-and-bound removed every child")
        memo[key] = best
        return best

    source = max((0, *(value for value in held if value <= request)))
    immediate = request - source
    roots = kh_sweep.next_states(capacity, held, source, request, pool)
    stats.actions += len(roots)
    if order == "seed" and len(roots) > 1 and future:
        stats.bound_frames += 1
        stats.bound_candidates += len(roots)
        stats.bound_fill_cycles += len(future)
    candidates: list[tuple[int, int, tuple[int, ...]]] = []
    for state in roots:
        segments = 1 + sum(source < value < request for value in state)
        candidates.append((bound(state, future), segments, state))
    if order == "bound":
        candidates.sort()
    elif order == "seed" and candidates:
        seed = min(
            candidates,
            key=lambda item: (seed_bound(item[2], future), item[1], item[2]),
        )
        candidates = [seed, *(item for item in candidates if item != seed)]

    best: tuple[int, int, tuple[int, ...]] | None = None
    for tail_lower, segments, state in candidates:
        lower_tuple = (immediate + tail_lower, segments, state)
        if best is not None and lower_tuple >= best:
            stats.root_pruned_actions += 1
            continue
        candidate = (
            immediate + window_cost(state, future),
            segments,
            state,
        )
        if best is None or candidate < best:
            best = candidate

    if best is None:
        raise RuntimeError("exact branch-and-bound removed every root action")
    return source, best[2], stats


def replay_cell(
    workloads: list[kh_sweep.Workload],
    capacity: int,
    horizon: int,
    order: str,
    bound_depth: int,
    seed_depth: int,
) -> dict[str, int | float | str]:
    baseline_actions = 0
    baseline_states = 0
    optimized_actions = 0
    optimized_states = 0
    optimized_hits = 0
    optimized_pruned = 0
    optimized_root_pruned = 0
    optimized_bound_calls = 0
    optimized_bound_frames = 0
    optimized_bound_candidates = 0
    optimized_bound_fill_cycles = 0
    physical = 0
    normal = 0
    decisions = 0

    for workload in workloads:
        held: tuple[int, ...] = ()
        for index, request in enumerate(workload.requested):
            future = tuple(workload.stream[index + 1 : index + horizon + 1])
            base_source, base_chosen, base_stats = kh_sweep.select_policy_action(
                held, request, future, capacity
            )
            opt_source, opt_chosen, opt_stats = select_policy_action_bnb(
                held, request, future, capacity, order, bound_depth, seed_depth
            )
            if (opt_source, opt_chosen) != (base_source, base_chosen):
                raise RuntimeError(
                    "exact mismatch "
                    f"K{capacity}H{horizon} M={workload.target_count} "
                    f"seed={workload.seed_index} decision={index}: "
                    f"baseline=({base_source},{base_chosen}) "
                    f"optimized=({opt_source},{opt_chosen})"
                )

            baseline_actions += base_stats.actions
            baseline_states += base_stats.states
            optimized_actions += opt_stats.actions
            optimized_states += opt_stats.states
            optimized_hits += opt_stats.memo_hits
            optimized_pruned += opt_stats.pruned_actions
            optimized_root_pruned += opt_stats.root_pruned_actions
            optimized_bound_calls += opt_stats.bound_calls
            optimized_bound_frames += opt_stats.bound_frames
            optimized_bound_candidates += opt_stats.bound_candidates
            optimized_bound_fill_cycles += opt_stats.bound_fill_cycles
            physical += request - opt_source
            normal += request
            decisions += 1
            held = opt_chosen

    return {
        "k": capacity,
        "h": horizon,
        "order": order,
        "bound_depth": "full" if bound_depth == 0 else bound_depth,
        "seed_depth": "full" if seed_depth == 0 else seed_depth,
        "workloads": len(workloads),
        "decisions": decisions,
        "normal_iterations": normal,
        "physical_iterations": physical,
        "physical_reduction_pct": 100.0 * (normal - physical) / normal,
        "baseline_actions": baseline_actions,
        "baseline_actions_per_decision": baseline_actions / decisions,
        "optimized_actions": optimized_actions,
        "optimized_actions_per_decision": optimized_actions / decisions,
        "action_reduction_pct": 100.0 * (
            baseline_actions - optimized_actions
        ) / baseline_actions,
        "baseline_states": baseline_states,
        "optimized_states": optimized_states,
        "state_reduction_pct": 100.0 * (
            baseline_states - optimized_states
        ) / baseline_states,
        "optimized_memo_hits": optimized_hits,
        "optimized_pruned_actions": optimized_pruned,
        "optimized_root_pruned_actions": optimized_root_pruned,
        "optimized_bound_calls": optimized_bound_calls,
        "optimized_bound_frames": optimized_bound_frames,
        "optimized_bound_candidates": optimized_bound_candidates,
        "optimized_bound_fill_cycles": optimized_bound_fill_cycles,
        "choice_mismatches": 0,
    }


def write_csv(path: Path, rows: list[dict[str, object]]) -> None:
    fieldnames: list[str] = []
    for row in rows:
        for key in row:
            if key not in fieldnames:
                fieldnames.append(key)
    with path.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--cells", default="K3H3,K4H4,K4H8,K5H5", type=parse_cells
    )
    parser.add_argument(
        "--order", choices=("canonical", "seed", "bound", "both"), default="both"
    )
    parser.add_argument(
        "--bound-depth", type=int, default=0,
        help="relaxed-bound lookahead; 0 uses the full remaining window",
    )
    parser.add_argument(
        "--seed-depth", type=int,
        help="lookahead used only to pick the first child; defaults to bound depth",
    )
    parser.add_argument("--trace", type=Path, default=kh_sweep.DEFAULT_TRACE)
    parser.add_argument("--roster", type=Path, default=kh_sweep.DEFAULT_ROSTER)
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT)
    parser.add_argument("--limit-workloads", type=int)
    args = parser.parse_args()
    if args.bound_depth < 0:
        parser.error("--bound-depth must be nonnegative")
    if args.seed_depth is None:
        args.seed_depth = args.bound_depth
    if args.seed_depth < 0:
        parser.error("--seed-depth must be nonnegative")

    max_h = max(h for _, h in args.cells)
    workloads = kh_sweep.load_workloads(
        args.trace, args.roster, max(max_h, 8), args.limit_workloads
    )
    orders = ("canonical", "bound") if args.order == "both" else (args.order,)
    rows: list[dict[str, object]] = []
    args.out.mkdir(parents=True, exist_ok=True)

    for capacity, horizon in args.cells:
        for order in orders:
            row = replay_cell(
                workloads, capacity, horizon, order,
                args.bound_depth, args.seed_depth,
            )
            rows.append(row)
            write_csv(args.out / "method1_search.csv", rows)
            print(
                f"K{capacity}H{horizon} {order}: "
                f"actions {row['baseline_actions_per_decision']:.2f} -> "
                f"{row['optimized_actions_per_decision']:.2f} "
                f"({row['action_reduction_pct']:.2f}% reduction), "
                f"states {row['state_reduction_pct']:.2f}% reduction, exact",
                flush=True,
            )

    manifest = {
        "method": "exact memoized depth-first branch-and-bound",
        "policy_changed": False,
        "lower_bound": "capacity-relaxed keep-all/deposit-all restricted-B",
        "lower_bound_depth": (
            "full" if args.bound_depth == 0 else args.bound_depth
        ),
        "seed_depth": "full" if args.seed_depth == 0 else args.seed_depth,
        "cells": [{"k": k, "h": h} for k, h in args.cells],
        "orders": list(orders),
        "workloads": len(workloads),
        "source_trace": str(args.trace),
        "choice_validation": "baseline source and chosen checkpoint tuple per decision",
    }
    (args.out / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"wrote {args.out / 'method1_search.csv'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
