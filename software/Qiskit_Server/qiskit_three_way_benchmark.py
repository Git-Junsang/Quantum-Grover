"""Reproducible NumPy/Qiskit/FPGA requested-j comparison package.

NumPy and Qiskit are executed here.  The frozen Q14 FPGA rows are emitted as
an empty template so board measurements can be added without changing the
scenario definition or silently mixing unlike workloads.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import math
import platform
from dataclasses import asdict, dataclass
from pathlib import Path
from time import perf_counter
from typing import Iterable, Sequence

import numpy as np

from grover_core_float import run_grover
from qiskit_grover import (
    compare_with_reference,
    execute_prepared,
    package_versions,
    prepare_requested_j,
    qiskit_available,
)
from rtl_v098_contract import V098_N_ENTRIES, V098_Q_BITS
from rtl_v098_data import build_controlled_v098_dataset


@dataclass(frozen=True)
class ComparisonScenario:
    scenario_id: str
    qubits: int
    target_count: int
    requested_j: int
    predicate_mode: str = "EQ"
    data_count: int | None = None
    layout: str = "HEAD"
    seed: int = 1

    @property
    def n(self) -> int:
        return 1 << self.qubits

    @property
    def resolved_data_count(self) -> int:
        return self.n if self.data_count is None else self.data_count

    def validate(self) -> None:
        if not 1 <= self.qubits <= V098_Q_BITS:
            raise ValueError("qubits must be between 1 and 14")
        if not 1 <= self.resolved_data_count <= self.n:
            raise ValueError("data_count must be between 1 and N")
        if not 0 <= self.target_count <= self.resolved_data_count:
            raise ValueError("target_count must be between 0 and DATA_COUNT")
        if not 0 <= self.requested_j <= 127:
            raise ValueError("requested_j must fit the unsigned 7-bit field")
        if self.predicate_mode.upper() not in {"EQ", "GT", "LT", "RANGE"}:
            raise ValueError("predicate_mode must be EQ, GT, LT, or RANGE")


def optimal_known_m_iterations(n: int, target_count: int) -> int:
    if not 0 <= target_count <= n:
        raise ValueError("target_count must be between 0 and N")
    if target_count in (0, n):
        return 0
    theta = math.asin(math.sqrt(target_count / n))
    continuous_iterations = math.pi / (4.0 * theta) - 0.5
    return max(0, math.floor(continuous_iterations + 0.5 + 1e-12))


def make_scenarios(
    qubits_values: Sequence[int],
    target_counts: Sequence[int],
) -> list[ComparisonScenario]:
    scenarios = []
    for qubits in qubits_values:
        n = 1 << int(qubits)
        for target_count in target_counts:
            if not 0 <= int(target_count) <= n:
                continue
            requested_j = optimal_known_m_iterations(n, int(target_count))
            scenarios.append(ComparisonScenario(
                scenario_id=f"q{qubits}_m{target_count}_j{requested_j}",
                qubits=int(qubits),
                target_count=int(target_count),
                requested_j=requested_j,
            ))
    if not scenarios:
        raise ValueError("no valid scenario combinations")
    return scenarios


def run_three_way_benchmark(
    output_dir: str | Path,
    scenarios: Sequence[ComparisonScenario],
    *,
    repeats: int = 5,
    warmups: int = 1,
    qiskit_threads: int = 1,
    optimization_level: int = 0,
    include_qiskit: bool = True,
) -> Path:
    if repeats < 1 or warmups < 0:
        raise ValueError("repeats must be positive and warmups cannot be negative")
    if include_qiskit and not qiskit_available():
        raise RuntimeError("Qiskit Aer is unavailable; install requirements-qiskit.txt")

    root = Path(output_dir)
    root.mkdir(parents=True, exist_ok=True)
    raw_rows: list[dict[str, object]] = []
    summaries: list[dict[str, object]] = []
    hardware_rows: list[dict[str, object]] = []
    scenario_rows: list[dict[str, object]] = []

    for scenario in scenarios:
        scenario.validate()
        input_started = perf_counter()
        mask, data_path = _scenario_inputs(root, scenario)
        shared_input_prepare_seconds = perf_counter() - input_started
        mask_hash = hashlib.sha256(mask.tobytes()).hexdigest()
        common = {
            "scenario_id": scenario.scenario_id,
            "qubits": scenario.qubits,
            "N": scenario.n,
            "data_count": scenario.resolved_data_count,
            "target_count": scenario.target_count,
            "requested_j": scenario.requested_j,
            "predicate_mode": scenario.predicate_mode,
            "target_mask_sha256": mask_hash,
            "shared_input_prepare_seconds": shared_input_prepare_seconds,
        }

        for _ in range(warmups):
            run_grover(mask, scenario.requested_j, trace_level="NONE")
        numpy_times = []
        reference = None
        for repeat in range(repeats):
            started = perf_counter()
            reference = run_grover(mask, scenario.requested_j, trace_level="NONE")
            seconds = perf_counter() - started
            numpy_times.append(seconds)
            raw_rows.append({
                **common,
                "backend": "NUMPY_FLOAT64",
                "repeat": repeat,
                "execution_seconds": seconds,
                "target_probability": reference.target_probability,
                "norm": reference.norm,
                "phase_aligned_l2_vs_numpy": 0.0,
                "success_probability_error_vs_numpy": 0.0,
            })
        assert reference is not None
        summaries.append(_summary_row(common, "NUMPY_FLOAT64", numpy_times))

        qiskit_build = None
        qiskit_transpile = None
        qiskit_depth = None
        if include_qiskit:
            prepared = prepare_requested_j(
                mask,
                scenario.requested_j,
                optimization_level=optimization_level,
                threads=qiskit_threads,
            )
            qiskit_build = prepared.build_seconds
            qiskit_transpile = prepared.transpile_seconds
            qiskit_depth = prepared.transpiled_depth
            for _ in range(warmups):
                execute_prepared(prepared)
            qiskit_times = []
            for repeat in range(repeats):
                candidate = execute_prepared(prepared)
                comparison = compare_with_reference(
                    reference.amplitudes,
                    candidate.amplitudes,
                    mask,
                )
                qiskit_times.append(candidate.execution_seconds)
                raw_rows.append({
                    **common,
                    "backend": "QISKIT_AER_STATEVECTOR",
                    "repeat": repeat,
                    "execution_seconds": candidate.execution_seconds,
                    "target_probability": candidate.target_probability,
                    "norm": candidate.norm,
                    "phase_aligned_l2_vs_numpy": comparison.phase_aligned_l2_error,
                    "success_probability_error_vs_numpy": comparison.success_probability_error,
                })
            row = _summary_row(common, "QISKIT_AER_STATEVECTOR", qiskit_times)
            row.update({
                "build_seconds": qiskit_build,
                "transpile_seconds": qiskit_transpile,
                "transpiled_depth": qiskit_depth,
                "cold_start_total_seconds": (
                    qiskit_build
                    + qiskit_transpile
                    + float(row["median_seconds"])
                ),
            })
            summaries.append(row)

        scenario_rows.append({
            **asdict(scenario),
            "N": scenario.n,
            "resolved_data_count": scenario.resolved_data_count,
            "target_mask_sha256": mask_hash,
            "hardware_compatible": scenario.qubits == V098_Q_BITS,
            "hardware_data_file": data_path,
            "qiskit_build_seconds": qiskit_build,
            "qiskit_transpile_seconds": qiskit_transpile,
            "qiskit_transpiled_depth": qiskit_depth,
        })
        if scenario.qubits == V098_Q_BITS:
            hardware_rows.append({
                **common,
                "data_file": data_path,
                "expected_target_probability_float64": reference.target_probability,
                "cycle_count": "",
                "dma_load_cycles_optional": "",
                "csr_setup_cycles_optional": "",
                "initialization_cycles_optional": "",
                "grover_cycles_optional": "",
                "measurement_verify_cycles_optional": "",
                "result_read_cycles_optional": "",
                "hardware_seconds_100mhz": "",
                "result_index": "",
                "trial_count": "",
                "L_BBHT": "",
                "actual_grover_iterations": "",
                "pass_fail": "",
            })

    _write_csv(root / "raw_timings.csv", raw_rows)
    _write_csv(root / "timing_summary.csv", summaries)
    _write_csv(root / "fpga_results_template.csv", hardware_rows)
    (root / "scenarios.json").write_text(
        json.dumps(scenario_rows, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    manifest = {
        "comparison_scope": "requested-j statevector kernel",
        "common_boundary": "same N, M, requested_j, and target_mask",
        "timing_policy": {
            "numpy": "run_grover wall time",
            "qiskit_build": "logical circuit construction, reported separately",
            "qiskit_transpile": "Aer transpilation, reported separately",
            "qiskit_execution": "prepared Aer circuit execution only",
            "fpga": "fill CYCLE_COUNT and divide by 100 MHz",
        },
        "measurement_warning": (
            "Exact statevector metrics are comparable. Sampled result_index is not "
            "seed-identical across NumPy, Qiskit, and FPGA RNG implementations."
        ),
        "repeats": repeats,
        "warmups": warmups,
        "qiskit_threads": qiskit_threads,
        "optimization_level": optimization_level,
        "environment": {
            "python": platform.python_version(),
            "platform": platform.platform(),
            "packages": package_versions(),
        },
        "files": {
            "raw": "raw_timings.csv",
            "summary": "timing_summary.csv",
            "fpga_template": "fpga_results_template.csv",
            "scenarios": "scenarios.json",
        },
    }
    (root / "benchmark_manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    return root


def _scenario_inputs(root: Path, scenario: ComparisonScenario) -> tuple[np.ndarray, str]:
    if scenario.qubits != V098_Q_BITS:
        mask = np.zeros(scenario.n, dtype=np.bool_)
        mask[:scenario.target_count] = True
        return mask, ""

    dataset = build_controlled_v098_dataset(
        predicate_mode=scenario.predicate_mode,
        data_count=scenario.resolved_data_count,
        target_count=scenario.target_count,
        layout=scenario.layout,
        seed=scenario.seed,
        auto_shot=False,
    )
    case_dir = root / "fpga_inputs" / scenario.scenario_id
    case_dir.mkdir(parents=True, exist_ok=True)
    path = case_dir / "data_signed16.hex"
    _write_signed16_hex(path, dataset.memory_image)
    return dataset.target_mask, str(path.relative_to(root)).replace("\\", "/")


def _write_signed16_hex(path: Path, values: np.ndarray) -> None:
    path.write_text(
        "".join(f"{int(value) & 0xFFFF:04x}\n" for value in values),
        encoding="ascii",
    )


def _summary_row(
    common: dict[str, object], backend: str, samples: Iterable[float]
) -> dict[str, object]:
    values = np.asarray(tuple(samples), dtype=np.float64)
    return {
        **common,
        "backend": backend,
        "sample_count": int(values.size),
        "median_seconds": float(np.median(values)),
        "p95_seconds": float(np.percentile(values, 95)),
        "min_seconds": float(np.min(values)),
        "max_seconds": float(np.max(values)),
    }


def _write_csv(path: Path, rows: Sequence[dict[str, object]]) -> None:
    if not rows:
        path.write_text("", encoding="utf-8-sig")
        return
    fieldnames: list[str] = []
    for row in rows:
        for key in row:
            if key not in fieldnames:
                fieldnames.append(key)
    with path.open("w", encoding="utf-8-sig", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


def _parse_ints(text: str) -> list[int]:
    return [int(item.strip()) for item in text.split(",") if item.strip()]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", default="verification_results/qiskit_three_way")
    parser.add_argument("--preset", choices=("SMOKE", "SERVER"), default="SMOKE")
    parser.add_argument("--qubits", default=None, help="comma-separated Q values")
    parser.add_argument("--targets", default=None, help="comma-separated M values")
    parser.add_argument("--repeats", type=int, default=None)
    parser.add_argument("--warmups", type=int, default=1)
    parser.add_argument("--threads", type=int, default=1)
    parser.add_argument("--optimization-level", type=int, default=0)
    parser.add_argument("--skip-qiskit", action="store_true")
    args = parser.parse_args()

    defaults = {
        "SMOKE": ([6, 8], [1, 4], 3),
        "SERVER": ([8, 10, 12, 14], [1, 4, 16, 64, 256], 10),
    }
    default_q, default_m, default_repeats = defaults[args.preset]
    qubits = default_q if args.qubits is None else _parse_ints(args.qubits)
    targets = default_m if args.targets is None else _parse_ints(args.targets)
    repeats = default_repeats if args.repeats is None else args.repeats
    scenarios = make_scenarios(qubits, targets)
    output = run_three_way_benchmark(
        args.output,
        scenarios,
        repeats=repeats,
        warmups=args.warmups,
        qiskit_threads=args.threads,
        optimization_level=args.optimization_level,
        include_qiskit=not args.skip_qiskit,
    )
    print(output.resolve())


if __name__ == "__main__":
    main()
