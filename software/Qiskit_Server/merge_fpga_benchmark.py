"""Merge measured FPGA cycle counts into a three-way timing report."""

from __future__ import annotations

import argparse
import csv
from collections import defaultdict
from pathlib import Path
from typing import Sequence

import numpy as np

from rtl_v098_contract import V098_ACCEL_CLK_HZ


def merge_fpga_results(benchmark_dir: str | Path) -> tuple[Path, Path]:
    root = Path(benchmark_dir)
    software_path = root / "timing_summary.csv"
    hardware_path = root / "fpga_results_template.csv"
    if not software_path.is_file() or not hardware_path.is_file():
        raise FileNotFoundError("benchmark directory is missing summary or FPGA template")

    software = _read_csv(software_path)
    hardware = _read_csv(hardware_path)
    expected = {
        row["scenario_id"]: row["target_mask_sha256"]
        for row in software
        if row["backend"] == "NUMPY_FLOAT64"
    }
    cycles_by_scenario: dict[str, list[int]] = defaultdict(list)
    for row in hardware:
        if not row.get("cycle_count", "").strip():
            continue
        scenario_id = row["scenario_id"]
        if scenario_id not in expected:
            raise ValueError(f"unknown FPGA scenario_id: {scenario_id}")
        if row["target_mask_sha256"] != expected[scenario_id]:
            raise ValueError(f"target mask hash mismatch for {scenario_id}")
        cycles = int(row["cycle_count"])
        if cycles < 0:
            raise ValueError("cycle_count cannot be negative")
        cycles_by_scenario[scenario_id].append(cycles)

    combined = list(software)
    comparison_rows = []
    software_times = {
        (row["scenario_id"], row["backend"]): float(row["median_seconds"])
        for row in software
    }
    common_by_scenario = {
        row["scenario_id"]: row
        for row in software
        if row["backend"] == "NUMPY_FLOAT64"
    }
    for scenario_id, cycle_samples in sorted(cycles_by_scenario.items()):
        values = np.asarray(cycle_samples, dtype=np.float64)
        seconds = values / V098_ACCEL_CLK_HZ
        common = common_by_scenario[scenario_id]
        fpga_median = float(np.median(seconds))
        combined.append({
            **{key: common.get(key, "") for key in common},
            "backend": "FPGA_100MHZ",
            "sample_count": str(values.size),
            "median_seconds": fpga_median,
            "p95_seconds": float(np.percentile(seconds, 95)),
            "min_seconds": float(np.min(seconds)),
            "max_seconds": float(np.max(seconds)),
            "median_cycle_count": float(np.median(values)),
        })
        numpy_time = software_times[(scenario_id, "NUMPY_FLOAT64")]
        qiskit_time = software_times.get((scenario_id, "QISKIT_AER_STATEVECTOR"))
        comparison_rows.append({
            "scenario_id": scenario_id,
            "qubits": common["qubits"],
            "N": common["N"],
            "target_count": common["target_count"],
            "requested_j": common["requested_j"],
            "fpga_sample_count": int(values.size),
            "fpga_median_cycles": float(np.median(values)),
            "fpga_median_seconds": fpga_median,
            "numpy_median_seconds": numpy_time,
            "qiskit_median_seconds": "" if qiskit_time is None else qiskit_time,
            "fpga_speedup_vs_numpy": numpy_time / fpga_median if fpga_median else "",
            "fpga_speedup_vs_qiskit": (
                "" if qiskit_time is None or not fpga_median
                else qiskit_time / fpga_median
            ),
        })

    combined_path = root / "three_way_timing_summary.csv"
    comparison_path = root / "three_way_speedup.csv"
    _write_csv(combined_path, combined)
    _write_csv(comparison_path, comparison_rows)
    return combined_path, comparison_path


def _read_csv(path: Path) -> list[dict[str, str]]:
    with path.open(encoding="utf-8-sig", newline="") as handle:
        return list(csv.DictReader(handle))


def _write_csv(path: Path, rows: Sequence[dict[str, object]]) -> None:
    if not rows:
        path.write_text("", encoding="utf-8-sig")
        return
    fields: list[str] = []
    for row in rows:
        for key in row:
            if key not in fields:
                fields.append(key)
    with path.open("w", encoding="utf-8-sig", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("benchmark_dir")
    args = parser.parse_args()
    for output in merge_fpga_results(args.benchmark_dir):
        print(output.resolve())


if __name__ == "__main__":
    main()
