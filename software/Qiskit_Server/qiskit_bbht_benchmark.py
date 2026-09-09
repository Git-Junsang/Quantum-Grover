"""Statistical Q14 BBHT comparison for NumPy, Qiskit, and later FPGA data."""

from __future__ import annotations

import argparse
import csv
import json
from collections import defaultdict
from pathlib import Path
from typing import Sequence

import numpy as np

from qiskit_bbht import run_v098_bbht_numpy, run_v098_bbht_qiskit
from qiskit_grover import package_versions, qiskit_available
from rtl_v098_data import build_controlled_v098_dataset


def run_bbht_benchmark(
    output_dir: str | Path,
    *,
    target_counts: Sequence[int],
    seeds: Sequence[int],
    shot_cap: int = 100,
    threads: int = 1,
    optimization_level: int = 0,
    include_qiskit: bool = True,
) -> Path:
    if not target_counts or not seeds:
        raise ValueError("target_counts and seeds cannot be empty")
    if include_qiskit and not qiskit_available():
        raise RuntimeError("Qiskit Aer is unavailable")

    root = Path(output_dir)
    root.mkdir(parents=True, exist_ok=True)
    raw = []
    attempts = []
    fpga = []

    for target_count in target_counts:
        dataset = build_controlled_v098_dataset(
            predicate_mode="EQ",
            data_count=16384,
            target_count=int(target_count),
            layout="HEAD",
            auto_shot=True,
        )
        data_dir = root / "fpga_inputs" / f"q14_m{target_count}"
        data_dir.mkdir(parents=True, exist_ok=True)
        data_path = data_dir / "data_signed16.hex"
        data_path.write_text(
            "".join(f"{int(value) & 0xFFFF:04x}\n" for value in dataset.memory_image),
            encoding="ascii",
        )
        prepared_cache: dict[int, object] = {}

        for seed in seeds:
            seed_j = int(seed) & 0xFFFFFFFF
            seed_meas = (int(seed) ^ 0xA5A55A5A) & 0xFFFFFFFF
            numpy_result = run_v098_bbht_numpy(
                dataset.target_mask,
                seed_j=seed_j,
                seed_measurement=seed_meas,
                shot_cap=shot_cap,
            )
            raw.append(_result_row(target_count, seed_j, seed_meas, "NUMPY_FLOAT64", numpy_result))
            attempts.extend(_attempt_rows(target_count, seed_j, "NUMPY_FLOAT64", numpy_result.attempts))

            if include_qiskit:
                qiskit_result = run_v098_bbht_qiskit(
                    dataset.target_mask,
                    seed_j=seed_j,
                    seed_measurement=seed_meas,
                    shot_cap=shot_cap,
                    optimization_level=optimization_level,
                    threads=threads,
                    prepared_cache=prepared_cache,
                )
                raw.append(_result_row(target_count, seed_j, seed_meas, "QISKIT_AER_STATEVECTOR", qiskit_result))
                attempts.extend(_attempt_rows(target_count, seed_j, "QISKIT_AER_STATEVECTOR", qiskit_result.attempts))

            fpga.append({
                "target_count": target_count,
                "seed_j": seed_j,
                "seed_meas": seed_meas,
                "data_file": str(data_path.relative_to(root)).replace("\\", "/"),
                "success": "",
                "termination_reason": "",
                "result_index": "",
                "trial_count": "",
                "L_BBHT": "",
                "actual_grover_iterations": "",
                "cycle_count": "",
            })

    summary = _summarize(raw)
    _write_csv(root / "bbht_raw.csv", raw)
    _write_csv(root / "bbht_attempts.csv", attempts)
    _write_csv(root / "bbht_summary.csv", summary)
    _write_csv(root / "bbht_fpga_results_template.csv", fpga)
    (root / "bbht_manifest.json").write_text(
        json.dumps({
            "profile": "v0.9.8 Q14/P32/F22",
            "algorithm": "m0=1, lambda=6/5, m_max=128, budget=576",
            "target_counts": list(target_counts),
            "seeds": list(seeds),
            "shot_cap": shot_cap,
            "packages": package_versions(),
            "comparison_rule": (
                "Compare final success rate, trial_count, L_BBHT, and runtime distributions. "
                "FPGA result_index is not required to match NumPy/Qiskit because its "
                "measurement RNG mapping is different."
            ),
        }, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    return root


def _result_row(target_count: int, seed_j: int, seed_meas: int, backend: str, result) -> dict[str, object]:
    execution = getattr(result, "execution_seconds", None)
    if execution is None:
        execution = result.qiskit_execution_seconds
    return {
        "target_count": target_count,
        "seed_j": seed_j,
        "seed_meas": seed_meas,
        "backend": backend,
        "success": int(result.success),
        "termination_reason": result.termination_reason,
        "result_index": "" if result.result_index is None else result.result_index,
        "trial_count": result.trial_count,
        "L_BBHT": result.L_BBHT,
        "execution_seconds": execution,
        "wall_seconds": result.wall_seconds,
        "build_seconds": getattr(result, "circuit_build_seconds", ""),
        "transpile_seconds": getattr(result, "transpile_seconds", ""),
    }


def _attempt_rows(target_count: int, seed_j: int, backend: str, attempt_records) -> list[dict[str, object]]:
    return [{
        "target_count": target_count,
        "seed_j": seed_j,
        "backend": backend,
        **item.to_dict(),
    } for item in attempt_records]


def _summarize(rows: Sequence[dict[str, object]]) -> list[dict[str, object]]:
    groups: dict[tuple[int, str], list[dict[str, object]]] = defaultdict(list)
    for row in rows:
        groups[(int(row["target_count"]), str(row["backend"]))].append(row)
    result = []
    for (target_count, backend), items in sorted(groups.items()):
        trials = np.asarray([item["trial_count"] for item in items], dtype=np.float64)
        logical = np.asarray([item["L_BBHT"] for item in items], dtype=np.float64)
        times = np.asarray([item["execution_seconds"] for item in items], dtype=np.float64)
        result.append({
            "target_count": target_count,
            "backend": backend,
            "seed_count": len(items),
            "final_success_rate": float(np.mean([item["success"] for item in items])),
            "median_trial_count": float(np.median(trials)),
            "p95_trial_count": float(np.percentile(trials, 95)),
            "median_L_BBHT": float(np.median(logical)),
            "p95_L_BBHT": float(np.percentile(logical, 95)),
            "median_execution_seconds": float(np.median(times)),
            "p95_execution_seconds": float(np.percentile(times, 95)),
        })
    return result


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


def _parse_ints(text: str) -> list[int]:
    return [int(item.strip(), 0) for item in text.split(",") if item.strip()]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", default="verification_results/qiskit_bbht")
    parser.add_argument("--targets", default="1,4,16,64,256")
    parser.add_argument("--seed-start", type=int, default=1)
    parser.add_argument("--seed-count", type=int, default=3)
    parser.add_argument("--shot-cap", type=int, default=100)
    parser.add_argument("--threads", type=int, default=1)
    parser.add_argument("--optimization-level", type=int, default=0)
    parser.add_argument("--skip-qiskit", action="store_true")
    args = parser.parse_args()
    seeds = list(range(args.seed_start, args.seed_start + args.seed_count))
    output = run_bbht_benchmark(
        args.output,
        target_counts=_parse_ints(args.targets),
        seeds=seeds,
        shot_cap=args.shot_cap,
        threads=args.threads,
        optimization_level=args.optimization_level,
        include_qiskit=not args.skip_qiskit,
    )
    print(output.resolve())


if __name__ == "__main__":
    main()
