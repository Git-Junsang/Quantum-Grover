"""Measure host-side software costs that may affect the HW/SW partition."""

from __future__ import annotations

import csv
import json
import math
import statistics
import time
from pathlib import Path
from typing import Callable

import numpy as np

from search_modes import optimal_known_m_iterations


def _measure(operation: Callable[[], None], repetitions: int) -> dict[str, float]:
    samples = []
    for _ in range(repetitions):
        started = time.perf_counter_ns()
        operation()
        samples.append(time.perf_counter_ns() - started)
    ordered = sorted(samples)
    return {
        "repetitions": repetitions,
        "mean_ns": statistics.fmean(samples),
        "median_ns": statistics.median(samples),
        "p95_ns": float(ordered[min(len(ordered) - 1, math.ceil(.95 * len(ordered)) - 1)]),
        "min_ns": float(ordered[0]),
        "max_ns": float(ordered[-1]),
    }


def run_sw_cost_benchmark(output_dir: str | Path, repetitions: int = 1000) -> dict:
    output = Path(output_dir); output.mkdir(parents=True, exist_ok=True)
    rows = []
    for qubits in (14, 15, 16):
        n = 1 << qubits
        values = np.arange(n, dtype=np.int32).astype(np.int16)
        found = np.zeros(n, dtype=np.bool_)
        operations = {
            "known_m_j_calculation": lambda n=n: optimal_known_m_iterations(n, 1),
            "predicate_eq_mask": lambda values=values: np.equal(values, 0),
            "predicate_range_mask": lambda values=values: (values > -100) & (values < 100),
            "found_mask_update": lambda found=found: found.__setitem__(0, True),
            "dataset_copy_for_reload": lambda values=values: values.copy(),
        }
        local_repetitions = max(30, repetitions // max(1, n // (1 << 14)))
        for name, operation in operations.items():
            row = {"qubits": qubits, "n": n, "operation": name}
            row.update(_measure(operation, local_repetitions))
            rows.append(row)
    with (output / "sw_cost_raw.csv").open("w", newline="", encoding="utf-8-sig") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0])); writer.writeheader(); writer.writerows(rows)
    payload = {
        "platform": "PC Python/NumPy relative baseline only; not RVX firmware timing",
        "rows": rows,
    }
    (output / "sw_cost_summary.json").write_text(json.dumps(payload, indent=2), encoding="utf-8")
    lines = ["# PC Software Cost Baseline", "", "> 이 결과는 기능 간 상대비교용이다. RVX cycle 또는 FPGA latency로 해석하지 않는다.", "", "| Q | Operation | Median | P95 |", "|---:|---|---:|---:|"]
    for row in rows:
        lines.append(f"| {row['qubits']} | {row['operation']} | {row['median_ns']/1000:.3f} us | {row['p95_ns']/1000:.3f} us |")
    lines += ["", "최종 HW/SW 분할 판단에는 RVX cycle counter, MMIO 왕복, loader/DMA 시간을 별도로 측정해야 한다.", ""]
    (output / "PC_SW_Cost_Report.md").write_text("\n".join(lines), encoding="utf-8")
    return payload


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", nargs="?", default="results/sw_cost_benchmark")
    parser.add_argument("--repetitions", type=int, default=1000)
    args = parser.parse_args()
    print(json.dumps(run_sw_cost_benchmark(args.output, args.repetitions), indent=2))
