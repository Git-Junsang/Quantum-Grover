#!/usr/bin/env python3
"""Reproducible K/H design-space sweep for the restricted-B policy.

The script deliberately keeps three evidence levels separate:

* algorithmic replay: exact policy choice and physical Grover iterations;
* standalone RTL: start-to-done policy cycles and evaluated actions;
* integrated RTL CSV: exposed policy stall and total accelerator cycles.

The requested-j trajectory is replayed from the committed bit-exact Common500
trace.  Checkpointing cannot change that trajectory, so every K/H cell sees
the same workload.  K=1..5 is supported by the software replay.  The current
RTL interface is honestly limited to K=3/4 and H<=8.
"""

from __future__ import annotations

import argparse
import csv
import json
import math
import os
import re
import statistics
import subprocess
import sys
from dataclasses import dataclass
from itertools import combinations
from pathlib import Path


HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
DEFAULT_TRACE = (
    ROOT
    / "software/pc_grover_result/2026-10-05_server/verification/runs"
    / "rtl_k4h4.jsonl"
)
DEFAULT_ROSTER = (
    ROOT
    / "software/testbench_data/2026-09-08_common500"
    / "official_board_seed_roster.h"
)
DEFAULT_OUT = ROOT / "hardware_bram/results/archive/design_space/2026-10-26_kh_sweep"
TB = ROOT / "hardware_bram/testbench/tb_policy_kh_sweep.sv"
POLICY_RTL = ROOT / "hardware_bram/src/grover_policy.v"
RTL_INCLUDE = ROOT / "hardware_bram/src"

M_BOUNDS = (
    1, 2, 2, 2, 3, 3, 3, 4, 5, 6, 7, 8, 9, 11,
    13, 16, 19, 23, 27, 32, 39, 47, 56, 67, 80, 96, 115, 128,
)
J_FALLBACK_SEED = 0xACE12345


def parse_range(text: str) -> list[int]:
    values: list[int] = []
    for part in text.split(","):
        part = part.strip()
        if not part:
            continue
        if "-" in part:
            lo, hi = (int(value) for value in part.split("-", 1))
            if hi < lo:
                raise ValueError(f"descending range is not allowed: {part}")
            values.extend(range(lo, hi + 1))
        else:
            values.append(int(part))
    result = sorted(set(values))
    if not result or result[0] < 1:
        raise ValueError("K/H values must be positive")
    return result


def lfsr_step(state: int) -> int:
    feedback = ((state >> 31) ^ (state >> 21) ^ (state >> 1) ^ state) & 1
    return ((state << 1) & 0xFFFFFFFF) | feedback


class JSource:
    def __init__(self, seed: int) -> None:
        checked = seed & 0xFFFFFFFF
        self.state = checked if checked else J_FALLBACK_SEED

    def draw_word(self) -> int:
        value = self.state
        for _ in range(7):
            self.state = lfsr_step(self.state)
        return value

    def draw_uniform(self, bound: int) -> int:
        bits = (bound - 1).bit_length()
        mask = (1 << bits) - 1 if bits else 0
        while True:
            candidate = (self.draw_word() & 0xFF) & mask
            if candidate < bound:
                return candidate


@dataclass(frozen=True)
class Workload:
    target_count: int
    seed_index: int
    requested: tuple[int, ...]
    stream: tuple[int, ...]


def load_roster(path: Path) -> list[tuple[int, int]]:
    pairs = re.findall(
        r"\{\s*(0x[0-9A-Fa-f]+)u?\s*,\s*(0x[0-9A-Fa-f]+)u?\s*\}",
        path.read_text(),
    )
    if not pairs:
        raise RuntimeError(f"no seed pairs found in {path}")
    return [(int(seed_j, 16), int(seed_meas, 16)) for seed_j, seed_meas in pairs]


def generate_stream(seed_j: int, count: int) -> tuple[int, ...]:
    source = JSource(seed_j)
    return tuple(
        source.draw_uniform(M_BOUNDS[min(round_index, len(M_BOUNDS) - 1)])
        for round_index in range(count)
    )


def load_workloads(
    trace_path: Path,
    roster_path: Path,
    max_h: int,
    limit: int | None,
) -> list[Workload]:
    roster = load_roster(roster_path)
    workloads: list[Workload] = []
    with trace_path.open() as handle:
        for line in handle:
            if not line.strip():
                continue
            item = json.loads(line)
            requested = tuple(int(attempt[0]) for attempt in item["attempts"])
            seed_index = int(item["seed_index"])
            stream = generate_stream(roster[seed_index][0], len(requested) + max_h)
            if stream[: len(requested)] != requested:
                raise RuntimeError(
                    f"J replay mismatch at M={item['target_count']} seed={seed_index}"
                )
            workloads.append(
                Workload(
                    target_count=int(item["target_count"]),
                    seed_index=seed_index,
                    requested=requested,
                    stream=stream,
                )
            )
            if limit is not None and len(workloads) >= limit:
                break
    if not workloads:
        raise RuntimeError(f"no workloads found in {trace_path}")
    return workloads


def deposit_options(
    capacity: int,
    source: int,
    request: int,
    pool: tuple[int, ...],
    held: tuple[int, ...],
) -> tuple[tuple[int, ...], ...]:
    in_path = sorted(
        value
        for value in set(pool)
        if source < value < request and value not in held
    )
    options: list[tuple[int, ...]] = [(request,)]
    for size in range(1, capacity):
        if size > len(in_path):
            break
        options.extend(
            tuple(sorted((*chosen, request)))
            for chosen in combinations(in_path, size)
        )
    return tuple(options)


def next_states(
    capacity: int,
    held: tuple[int, ...],
    source: int,
    request: int,
    pool: tuple[int, ...],
) -> tuple[tuple[int, ...], ...]:
    result: list[tuple[int, ...]] = []
    keep_pool = tuple(value for value in held if value != request)
    for deposit in deposit_options(capacity, source, request, pool, held):
        room = capacity - len(deposit)
        if room <= 0:
            result.append(tuple(sorted(deposit)))
        elif len(keep_pool) <= room:
            result.append(tuple(sorted((*keep_pool, *deposit))))
        else:
            result.extend(
                tuple(sorted((*keep, *deposit)))
                for keep in combinations(keep_pool, room)
            )
    return tuple(sorted(set(result)))


@dataclass
class SolveStats:
    actions: int = 0
    states: int = 0


def select_policy_action(
    held: tuple[int, ...],
    request: int,
    future: tuple[int, ...],
    capacity: int,
) -> tuple[int, tuple[int, ...], SolveStats]:
    pool = tuple(dict.fromkeys((request, *future)))
    stats = SolveStats()
    memo: dict[tuple[tuple[int, ...], tuple[int, ...]], int] = {}

    def window_cost(state: tuple[int, ...], window: tuple[int, ...]) -> int:
        key = (state, window)
        if key in memo:
            return memo[key]
        if not window:
            return 0
        stats.states += 1
        head, rest = window[0], window[1:]
        source = max((0, *(value for value in state if value <= head)))
        children = next_states(capacity, state, source, head, pool)
        stats.actions += len(children)
        value = min(
            head - source + window_cost(child, rest)
            for child in children
        )
        memo[key] = value
        return value

    source = max((0, *(value for value in held if value <= request)))
    roots = next_states(capacity, held, source, request, pool)
    stats.actions += len(roots)
    best: tuple[int, int, tuple[int, ...]] | None = None
    chosen = held
    for state in roots:
        segments = 1 + sum(source < value < request for value in state)
        candidate = (
            request - source + window_cost(state, future),
            segments,
            state,
        )
        if best is None or candidate < best:
            best = candidate
            chosen = state
    return source, chosen, stats


def replay_cell(
    workloads: list[Workload], capacity: int, horizon: int
) -> tuple[dict[str, float | int], list[tuple[int, list[int], int, tuple[int, ...]]]]:
    physical = 0
    normal = 0
    decisions = 0
    actions = 0
    states = 0
    trace_rows: list[tuple[int, list[int], int, tuple[int, ...]]] = []
    for workload in workloads:
        held: tuple[int, ...] = ()
        for index, request in enumerate(workload.requested):
            window = list(workload.stream[index : index + 9])
            if len(window) < 9:
                raise RuntimeError("internal J stream is shorter than the RTL window")
            future = tuple(window[1 : horizon + 1])
            source, chosen, solve = select_policy_action(
                held, request, future, capacity
            )
            physical += request - source
            normal += request
            decisions += 1
            actions += solve.actions
            states += solve.states
            trace_rows.append((1 if index == 0 else 0, window, source, chosen))
            held = chosen
    metrics: dict[str, float | int] = {
        "k": capacity,
        "h": horizon,
        "workloads": len(workloads),
        "decisions": decisions,
        "normal_iterations": normal,
        "physical_iterations": physical,
        "physical_reduction_pct": 100.0 * (normal - physical) / normal,
        "actions": actions,
        "actions_per_decision": actions / decisions,
        "states": states,
        "states_per_decision": states / decisions,
    }
    return metrics, trace_rows


def write_trace(
    path: Path,
    rows: list[tuple[int, list[int], int, tuple[int, ...]]],
) -> None:
    with path.open("w") as handle:
        for reset_slots, window, source, chosen in rows:
            padded = [*chosen, *([0] * (4 - len(chosen)))]
            fields = [reset_slots, *window, source, len(chosen), *padded[:4]]
            handle.write(" ".join(str(value) for value in fields) + "\n")


def run_rtl_cell(
    out_dir: Path,
    capacity: int,
    horizon: int,
    trace_path: Path,
    exact_prune: int,
    policy_rtl: Path = POLICY_RTL,
    rtl_include: Path = RTL_INCLUDE,
    testbench: Path = TB,
) -> dict[str, float | int]:
    build = (
        Path("/tmp")
        / f"bbht_policy_kh_{os.getpid()}_{capacity}_{horizon}_p{exact_prune}"
    )
    compile_cmd = [
        "iverilog", "-g2012", "-s", "tb_policy_kh_sweep",
        "-I", str(rtl_include),
        "-P", f"tb_policy_kh_sweep.CHECKPOINT_CAPACITY={capacity}",
        "-P", f"tb_policy_kh_sweep.LOOKAHEAD_SHOTS={horizon}",
        "-P", f"tb_policy_kh_sweep.EXACT_PRUNE={exact_prune}",
        "-o", str(build), str(testbench), str(policy_rtl),
    ]
    compiled = subprocess.run(compile_cmd, text=True, capture_output=True)
    if compiled.returncode:
        raise RuntimeError(f"iverilog K{capacity}H{horizon}:\n{compiled.stderr}")
    simulated = subprocess.run(
        ["vvp", str(build), f"+TRACE={trace_path}"],
        text=True,
        capture_output=True,
    )
    log_path = out_dir / f"rtl_p{exact_prune}_k{capacity}h{horizon}.log"
    log_path.write_text(simulated.stdout + simulated.stderr)
    try:
        build.unlink()
    except FileNotFoundError:
        pass
    summary_line = next(
        (line for line in simulated.stdout.splitlines() if line.startswith("SUMMARY,")),
        None,
    )
    if simulated.returncode or summary_line is None:
        raise RuntimeError(
            f"RTL K{capacity}H{horizon} failed; see {log_path}"
        )
    _, k, h, count, cycles, actions, maximum, errors = summary_line.split(",")
    if int(errors):
        raise RuntimeError(
            f"RTL K{capacity}H{horizon} had {errors} mismatches; see {log_path}"
        )
    count_i = int(count)
    return {
        "k": int(k),
        "h": int(h),
        "rtl_exact_prune": exact_prune,
        "rtl_decisions": count_i,
        "rtl_policy_cycles": int(cycles),
        "rtl_cycles_per_decision": int(cycles) / count_i,
        "rtl_policy_actions": int(actions),
        "rtl_actions_per_decision": int(actions) / count_i,
        "rtl_max_latency": int(maximum),
    }


def load_rtl_logs(path: Path) -> list[dict[str, float | int]]:
    """Collect successful standalone summaries already preserved in a directory."""
    rows: list[dict[str, float | int]] = []
    for log_path in sorted(path.glob("rtl*k*h*.log")):
        summary_line = next(
            (
                line
                for line in log_path.read_text().splitlines()
                if line.startswith("SUMMARY,")
            ),
            None,
        )
        if summary_line is None:
            continue
        _, k, h, count, cycles, actions, maximum, errors = summary_line.split(",")
        if int(errors):
            continue
        count_i = int(count)
        rows.append(
            {
                "k": int(k),
                "h": int(h),
                "rtl_exact_prune": (
                    int(match.group(1))
                    if (match := re.search(r"rtl_p(\d+)_", log_path.name))
                    else 0
                ),
                "rtl_decisions": count_i,
                "rtl_policy_cycles": int(cycles),
                "rtl_cycles_per_decision": int(cycles) / count_i,
                "rtl_policy_actions": int(actions),
                "rtl_actions_per_decision": int(actions) / count_i,
                "rtl_max_latency": int(maximum),
            }
        )
    return rows


def load_system_csv(path: Path, capacity: int, horizon: int) -> dict[str, float | int]:
    with path.open(newline="") as handle:
        rows = list(csv.DictReader(line for line in handle if not line.startswith("#")))
    checkpoint = [row for row in rows if row.get("mode", "").lower() != "normal"]
    normal = [row for row in rows if row.get("mode", "").lower() == "normal"]
    if not checkpoint:
        raise RuntimeError(f"no checkpoint rows in {path}")
    cycles = sum(int(row["cycles"]) for row in checkpoint)
    policy_cycles = sum(int(row["policy_cycles"]) for row in checkpoint)
    stall = sum(int(row["policy_stall"]) for row in checkpoint)
    decisions = sum(
        int(row.get("cold", 0)) + int(row.get("spec", 0)) for row in checkpoint
    )
    result: dict[str, float | int] = {
        "k": capacity,
        "h": horizon,
        "system_cycles": cycles,
        "system_policy_cycles": policy_cycles,
        "system_policy_decisions": decisions,
        "system_cycles_per_decision": policy_cycles / decisions if decisions else math.nan,
        "stall_cycles": stall,
        "stall_ratio_pct": 100.0 * stall / cycles,
    }
    if normal and len(normal) == len(checkpoint):
        normal_iter = sum(int(row["iter"]) for row in normal)
        ckpt_iter = sum(int(row["iter"]) for row in checkpoint)
        result["system_physical_reduction_pct"] = (
            100.0 * (normal_iter - ckpt_iter) / normal_iter
        )
    return result


def write_csv(path: Path, rows: list[dict[str, object]]) -> None:
    fields: list[str] = []
    for row in rows:
        for key in row:
            if key not in fields:
                fields.append(key)
    with path.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)


def plot_heatmap(
    path: Path,
    rows: list[dict[str, object]],
    k_values: list[int],
    h_values: list[int],
) -> None:
    os.environ.setdefault("MPLCONFIGDIR", "/tmp/matplotlib-kh-sweep")
    import matplotlib.pyplot as plt
    import numpy as np

    lookup = {(int(row["k"]), int(row["h"])): row for row in rows}
    has_integrated_stall = any(
        row.get("stall_ratio_pct") not in ("", None) for row in rows
    )
    third_panel = (
        ("stall_ratio_pct", "Integrated policy stall (%)", "OrRd")
        if has_integrated_stall
        else ("rtl_max_latency", "RTL worst-case latency (cycles)", "OrRd")
    )
    panels = [
        ("physical_reduction_pct", "Physical-iteration reduction (%)", "YlGn"),
        ("rtl_cycles_per_decision", "RTL policy latency (cycles/decision)", "YlOrRd"),
        third_panel,
    ]
    fig, axes = plt.subplots(1, 3, figsize=(15, 4.7), constrained_layout=True)
    for axis, (field, title, cmap) in zip(axes, panels):
        values = np.full((len(k_values), len(h_values)), np.nan)
        for yi, k_value in enumerate(k_values):
            for xi, h_value in enumerate(h_values):
                value = lookup.get((k_value, h_value), {}).get(field, "")
                if value not in ("", None):
                    values[yi, xi] = float(value)
        masked = np.ma.masked_invalid(values)
        image = axis.imshow(masked, origin="lower", aspect="auto", cmap=cmap)
        image.cmap.set_bad("#e6e6e6")
        axis.set_title(title)
        axis.set_xlabel("H (future horizon)")
        axis.set_ylabel("K (checkpoint capacity)")
        axis.set_xticks(range(len(h_values)), labels=h_values)
        axis.set_yticks(range(len(k_values)), labels=k_values)
        for yi in range(len(k_values)):
            for xi in range(len(h_values)):
                value = values[yi, xi]
                label = "n/a" if math.isnan(value) else f"{value:.1f}"
                axis.text(xi, yi, label, ha="center", va="center", fontsize=7)
        if not masked.mask.all():
            fig.colorbar(image, ax=axis, shrink=0.78)
    fig.suptitle("Restricted-B K/H design-space sweep")
    fig.savefig(path, dpi=180)
    fig.savefig(path.with_suffix(".svg"))
    plt.close(fig)


def parse_system_arg(text: str) -> tuple[int, int, Path]:
    match = re.fullmatch(r"(\d+),(\d+),(.+)", text)
    if not match:
        raise argparse.ArgumentTypeError("expected K,H,CSV_PATH")
    return int(match.group(1)), int(match.group(2)), Path(match.group(3))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--k", default="1-5", help="software K grid, e.g. 1-5")
    parser.add_argument("--h", default="1-8", help="software H grid, e.g. 1-8")
    parser.add_argument("--rtl-k", default="3-4", help="RTL-supported K grid")
    parser.add_argument("--rtl-h", default="1-8", help="RTL-supported H grid")
    parser.add_argument("--trace", type=Path, default=DEFAULT_TRACE)
    parser.add_argument("--roster", type=Path, default=DEFAULT_ROSTER)
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT)
    parser.add_argument("--limit-workloads", type=int)
    parser.add_argument("--run-rtl", action="store_true")
    parser.add_argument(
        "--rtl-exact-prune", type=int, default=0,
        help="grover_policy EXACT_PRUNE mode used for standalone RTL",
    )
    parser.add_argument(
        "--rtl-log-dir", action="append", type=Path, default=[],
        help="merge successful SUMMARY rows from an earlier standalone RTL run",
    )
    parser.add_argument(
        "--system", action="append", type=parse_system_arg, default=[],
        metavar="K,H,CSV", help="integrated RTL bench CSV (repeatable)",
    )
    args = parser.parse_args()

    k_values = parse_range(args.k)
    h_values = parse_range(args.h)
    rtl_k_values = parse_range(args.rtl_k)
    rtl_h_values = parse_range(args.rtl_h)
    if any(value not in (3, 4) for value in rtl_k_values):
        parser.error("the current RTL supports only K=3/4")
    if max(rtl_h_values) > 8:
        parser.error("the current RTL input window supports H<=8")
    if args.rtl_exact_prune not in range(7):
        parser.error("--rtl-exact-prune must be 0..6")
    if max(k_values) > 8 or max(h_values) > 16:
        parser.error("software safety limit is K<=8 and H<=16")

    args.out.mkdir(parents=True, exist_ok=True)
    workloads = load_workloads(
        args.trace, args.roster, max(max(h_values), 8), args.limit_workloads
    )
    rows: list[dict[str, object]] = []
    trace_paths: dict[tuple[int, int], Path] = {}
    for capacity in k_values:
        for horizon in h_values:
            metrics, trace_rows = replay_cell(workloads, capacity, horizon)
            rows.append(metrics)
            if capacity in rtl_k_values and horizon in rtl_h_values:
                trace_path = args.out / f"trace_k{capacity}h{horizon}.txt"
                write_trace(trace_path, trace_rows)
                trace_paths[(capacity, horizon)] = trace_path
            print(
                f"SW K{capacity}H{horizon}: physical={metrics['physical_iterations']} "
                f"reduction={metrics['physical_reduction_pct']:.2f}% "
                f"actions/decision={metrics['actions_per_decision']:.1f}",
                flush=True,
            )

    lookup = {(int(row["k"]), int(row["h"])): row for row in rows}
    loaded_rtl_rows: list[dict[str, object]] = []
    for log_dir in args.rtl_log_dir:
        for rtl in load_rtl_logs(log_dir):
            key = (int(rtl["k"]), int(rtl["h"]))
            if key in lookup:
                lookup[key].update(rtl)
                loaded_rtl_rows.append(rtl)
    if loaded_rtl_rows:
        write_csv(args.out / "rtl_latency.csv", loaded_rtl_rows)
    if args.run_rtl:
        rtl_rows: list[dict[str, object]] = []
        for capacity in rtl_k_values:
            for horizon in rtl_h_values:
                if (capacity, horizon) not in trace_paths:
                    continue
                rtl = run_rtl_cell(
                    args.out,
                    capacity,
                    horizon,
                    trace_paths[(capacity, horizon)],
                    args.rtl_exact_prune,
                )
                lookup[(capacity, horizon)].update(rtl)
                rtl_rows.append(rtl)
                # Preserve completed cells even if a later, larger cell finds
                # a mismatch or the long sweep is interrupted.
                write_csv(args.out / "rtl_latency.csv", rtl_rows)
                print(
                    f"RTL K{capacity}H{horizon}: "
                    f"{rtl['rtl_cycles_per_decision']:.1f} cycles/decision, "
                    f"max={rtl['rtl_max_latency']}",
                    flush=True,
                )

    for capacity, horizon, path in args.system:
        system = load_system_csv(path, capacity, horizon)
        if (capacity, horizon) not in lookup:
            lookup[(capacity, horizon)] = {"k": capacity, "h": horizon}
            rows.append(lookup[(capacity, horizon)])
        lookup[(capacity, horizon)].update(system)

    rows.sort(key=lambda row: (int(row["k"]), int(row["h"])))
    write_csv(args.out / "kh_sweep.csv", rows)
    plot_heatmap(args.out / "kh_heatmap.png", rows, k_values, h_values)
    manifest = {
        "workloads": len(workloads),
        "source_trace": str(args.trace),
        "seed_roster": str(args.roster),
        "software_k": k_values,
        "software_h": h_values,
        "rtl_run": bool(args.run_rtl),
        "rtl_exact_prune": args.rtl_exact_prune,
        "rtl_evidence_loaded": bool(args.run_rtl or loaded_rtl_rows),
        "rtl_log_dir": [str(path) for path in args.rtl_log_dir],
        "rtl_k": rtl_k_values,
        "rtl_h": rtl_h_values,
        "system_csv": [
            {"k": k, "h": h, "path": str(path)} for k, h, path in args.system
        ],
        "metric_note": {
            "rtl_cycles_per_decision": "start-to-done, memo clear included and amortized",
            "stall_ratio_pct": "integrated policy_stall / checkpoint total cycles",
        },
    }
    (args.out / "manifest.json").write_text(
        json.dumps(manifest, indent=2) + "\n"
    )
    print(f"wrote {args.out / 'kh_sweep.csv'}")
    print(f"wrote {args.out / 'kh_heatmap.png'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
