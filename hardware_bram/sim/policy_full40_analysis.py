#!/usr/bin/env python3
"""Estimate full-bound seed-first policy/system cost over K=1..5, H=1..8.

The exact-search work counters come from policy_search_method1.py.  This file
does not change the policy or production RTL; it turns those counters into a
transparent cycle/resource estimate for the proposed low-storage two-pass
hardware schedule.
"""

from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path

import numpy as np


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_SEARCH = (
    ROOT / "hardware_bram/results/archive/policy_search/2026-10-26_policy_search_full40_seedfull"
    / "method1_search.csv"
)
DEFAULT_BASELINE = (
    ROOT / "hardware_bram/results/archive/design_space/2026-10-26_kh_sweep/kh_sweep.csv"
)
DEFAULT_OUT = (
    ROOT / "hardware_bram/results/archive/policy_search/2026-10-26_policy_search_full40_seedfull"
)

# Measured integrated K3H3-E4-M2 Common500 anchor.
REF_TOTAL = 5_328_877
REF_ITERATIONS = 9_582
REF_STALL = 172_066
REF_STANDALONE_POLICY = 1_183_308
ITERATION_CYCLES = 268


def read_rows(path: Path) -> list[dict[str, str]]:
    with path.open(newline="") as handle:
        return list(csv.DictReader(handle))


def write_rows(path: Path, rows: list[dict[str, object]]) -> None:
    fields: list[str] = []
    for row in rows:
        for key in row:
            if key not in fields:
                fields.append(key)
    with path.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)


def fit_core_cycle_model(
    baseline_rows: list[dict[str, str]],
) -> tuple[np.ndarray, float]:
    rtl = [row for row in baseline_rows if row.get("rtl_policy_cycles")]
    matrix = np.asarray(
        [
            [float(row["actions"]), float(row["states"]), float(row["decisions"])]
            for row in rtl
        ]
    )
    observed = np.asarray([float(row["rtl_policy_cycles"]) for row in rtl])
    coefficients, *_ = np.linalg.lstsq(matrix, observed, rcond=None)
    predicted = matrix @ coefficients
    r2 = 1.0 - float(np.sum((observed - predicted) ** 2)) / float(
        np.sum((observed - np.mean(observed)) ** 2)
    )
    return coefficients, r2


def make_heatmap(path: Path, rows: list[dict[str, object]]) -> None:
    import os

    os.environ.setdefault("MPLCONFIGDIR", "/tmp/matplotlib-full40")
    import matplotlib.pyplot as plt
    from matplotlib.colors import TwoSlopeNorm

    lookup = {(int(row["k"]), int(row["h"])): row for row in rows}
    panels = (
        ("action_reduction_pct", "Exact-search action reduction (%)", "YlGn"),
        ("policy_cycles_replay_est", "Policy cycles, pre-scan included", "YlOrRd"),
        ("system_delta_vs_fullbound_k3h3", "System cycles saved vs full-bound K3H3", "RdYlGn"),
    )
    fig, axes = plt.subplots(1, 3, figsize=(16, 4.8), constrained_layout=True)
    for axis, (field, title, cmap) in zip(axes, panels):
        values = np.asarray(
            [
                [float(lookup[(k, h)][field]) for h in range(1, 9)]
                for k in range(1, 6)
            ]
        )
        norm = None
        if field == "system_delta_vs_fullbound_k3h3":
            norm = TwoSlopeNorm(
                vmin=float(np.min(values)), vcenter=0.0, vmax=float(np.max(values))
            )
        image = axis.imshow(
            values, origin="lower", aspect="auto", cmap=cmap, norm=norm
        )
        axis.set_title(title)
        axis.set_xlabel("H")
        axis.set_ylabel("K")
        axis.set_xticks(range(8), labels=range(1, 9))
        axis.set_yticks(range(5), labels=range(1, 6))
        for yi in range(5):
            for xi in range(8):
                value = values[yi, xi]
                label = f"{value:.0f}" if field != "action_reduction_pct" else f"{value:.1f}"
                axis.text(xi, yi, label, ha="center", va="center", fontsize=6.5)
        fig.colorbar(image, ax=axis, shrink=0.78)
    fig.suptitle("Full-horizon admissible bound + seed-first exact DFS (Common500)")
    fig.savefig(path, dpi=180)
    fig.savefig(path.with_suffix(".svg"))
    plt.close(fig)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--search", type=Path, default=DEFAULT_SEARCH)
    parser.add_argument("--baseline", type=Path, default=DEFAULT_BASELINE)
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT)
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)

    search_rows = read_rows(args.search)
    baseline_rows = read_rows(args.baseline)
    coefficient, r2 = fit_core_cycle_model(baseline_rows)
    action_coef, state_coef, decision_coef = (float(value) for value in coefficient)

    fixed_cycles = REF_TOTAL - ITERATION_CYCLES * REF_ITERATIONS - REF_STALL
    stall_exposure = REF_STALL / REF_STANDALONE_POLICY
    rows: list[dict[str, object]] = []
    for source in search_rows:
        k = int(source["k"])
        h = int(source["h"])
        actions = int(source["optimized_actions"])
        states = int(source["optimized_states"])
        decisions = int(source["decisions"])
        bound_candidates = int(source["optimized_bound_candidates"])
        bound_fill = int(source["optimized_bound_fill_cycles"])
        core = (
            action_coef * actions
            + state_coef * states
            + decision_coef * decisions
        )
        # Both schedules first issue every candidate to pick the seed.  The
        # cached schedule stores every bound.  The selected low-storage schedule
        # regenerates canonical actions after the seed and pays a second drain
        # latency, while its one/cycle issue overlaps the modeled DFS action pass.
        cached = core + bound_candidates + bound_fill
        replay = core + bound_candidates + 2 * bound_fill

        universe = k + h + 1
        # Structural estimate for a balanced 7-bit predecessor max tree,
        # interval/deposit comparisons, 11-bit cost update, relaxed/original
        # masks and valid/tag registers.  Controller/action-generator cost and
        # the existing memo are deliberately excluded.
        pipeline_lut = h * (24 * universe + 32)
        pipeline_ff = h * (2 * universe + 14)

        physical = int(source["physical_iterations"])
        stall_est = replay * stall_exposure
        total_est = fixed_cycles + ITERATION_CYCLES * physical + stall_est
        stall_break_even = REF_TOTAL - fixed_cycles - ITERATION_CYCLES * physical
        row: dict[str, object] = dict(source)
        row.update(
            {
                "core_cycle_est": round(core),
                "policy_cycles_cached_est": round(cached),
                "policy_cycles_replay_est": round(replay),
                "policy_cycles_per_decision_replay_est": replay / decisions,
                "bound_pipeline_universe": universe,
                "bound_pipeline_lut_est": pipeline_lut,
                "bound_pipeline_lut_low": round(0.75 * pipeline_lut),
                "bound_pipeline_lut_high": round(1.25 * pipeline_lut),
                "bound_pipeline_ff_est": pipeline_ff,
                "system_stall_est": round(stall_est),
                "system_stall_break_even_vs_measured_k3h3": round(stall_break_even),
                "system_total_est": round(total_est),
                "system_delta_vs_measured_k3h3": round(REF_TOTAL - total_est),
                "rtl_kh_interface_supported": int(k in (3, 4) and h <= 8),
            }
        )
        rows.append(row)

    k3h3 = next(row for row in rows if int(row["k"]) == 3 and int(row["h"]) == 3)
    fair_reference = int(k3h3["system_total_est"])
    for row in rows:
        delta = fair_reference - int(row["system_total_est"])
        row["system_delta_vs_fullbound_k3h3"] = delta
        row["better_than_measured_k3h3"] = int(
            int(row["system_total_est"]) < REF_TOTAL
        )
        row["better_than_fullbound_k3h3"] = int(delta > 0)
        row["selected_current_rtl_range"] = int(
            delta > 0 and int(row["rtl_kh_interface_supported"]) != 0
        )

    rows.sort(key=lambda row: (int(row["k"]), int(row["h"])))
    write_rows(args.out / "full40_estimates.csv", rows)
    write_rows(
        args.out / "survivors_vs_fullbound_k3h3.csv",
        [row for row in rows if int(row["better_than_fullbound_k3h3"])],
    )
    make_heatmap(args.out / "full40_estimates_heatmap.png", rows)

    manifest = {
        "policy_changed": False,
        "choice_mismatches": sum(int(row["choice_mismatches"]) for row in rows),
        "workloads": 500,
        "decisions": 7403,
        "cycle_model": {
            "formula": "a*optimized_actions + b*optimized_states + c*decisions",
            "a": action_coef,
            "b": state_coef,
            "c": decision_coef,
            "fit_cells": "unoptimized standalone RTL K3/K4, H1..8",
            "r_squared": r2,
            "low_storage_replay": "core + bound_candidates + 2*bound_fill_cycles",
        },
        "system_model": {
            "measured_reference": "K3H3-E4-M2 Common500",
            "reference_total": REF_TOTAL,
            "reference_iterations": REF_ITERATIONS,
            "reference_stall": REF_STALL,
            "iteration_cycles": ITERATION_CYCLES,
            "fixed_cycles": fixed_cycles,
            "stall_exposure": stall_exposure,
            "warning": "aggregate estimate; integrated RTL is required for final stall",
        },
        "pipeline_resource_model": {
            "universe": "U=K+H+1",
            "lut": "H*(24*U+32), report +/-25%",
            "ff": "H*(2*U+14)",
            "scope": "bound pipeline only; excludes controller, action generator and memo",
            "vivado_status": "not synthesized: valid Vivado license unavailable",
        },
        "fair_reference_total_fullbound_k3h3": fair_reference,
    }
    (args.out / "analysis_manifest.json").write_text(
        json.dumps(manifest, indent=2) + "\n"
    )
    print(f"fit R2={r2:.6f}; full-bound K3H3 total={fair_reference}")
    print(f"wrote {args.out / 'full40_estimates.csv'}")
    print(f"wrote {args.out / 'survivors_vs_fullbound_k3h3.csv'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
