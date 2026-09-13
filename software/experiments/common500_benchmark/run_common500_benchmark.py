"""Run the final Q14 common-workload comparison and merge board evidence.

The campaign uses the exact five datasets and 100 seed pairs used by the
2026-09-08 board benchmark.  Results are appended after every backend run, so
an interrupted server job can resume without discarding completed work.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import platform
import re
import sys
from collections import defaultdict
from dataclasses import asdict, dataclass, replace
from datetime import datetime, timezone
from pathlib import Path
from statistics import median
from time import perf_counter
from typing import Iterable, Sequence

import numpy as np

from bbht_qiskit_runner import run_v098_bbht_numpy, run_v098_bbht_qiskit
from qiskit_grover_backend import package_versions, qiskit_available
from checkpoint_bbht_model import V098AutomaticCore
from benchmark_dataset import build_official_board_benchmark_dataset


TARGET_COUNTS = (1, 4, 16, 64, 256)
SOFTWARE_BACKENDS = (
    "NUMPY_FLOAT64",
    "QISKIT_AER_STATEVECTOR",
    "RTL_FIXED_NORMAL",
    "SOFTWARE_K4H4",
    "SOFTWARE_K3H3",
)
FPGA_BACKENDS = (
    "FPGA_NORMAL_E1",
    "FPGA_K4H4_E1",
    "FPGA_K3H3_E4_M2",
)


@dataclass(frozen=True)
class SeedPair:
    seed_index: int
    seed_j: int
    seed_meas: int


def load_seed_roster(path: str | Path) -> tuple[SeedPair, ...]:
    text = Path(path).read_text(encoding="utf-8")
    pairs = re.findall(r"\{\s*(0x[0-9A-Fa-f]+)u?\s*,\s*(0x[0-9A-Fa-f]+)u?\s*\}", text)
    if not pairs:
        raise ValueError(f"no seed pairs found in {path}")
    return tuple(
        SeedPair(index, int(seed_j, 16), int(seed_meas, 16))
        for index, (seed_j, seed_meas) in enumerate(pairs)
    )


def run_common500(
    output_dir: str | Path,
    input_dir: str | Path,
    *,
    target_counts: Sequence[int] = TARGET_COUNTS,
    seed_limit: int | None = None,
    include_qiskit: bool = True,
    include_fixed_models: bool = True,
    threads: int = 1,
    optimization_level: int = 0,
) -> Path:
    root = Path(output_dir)
    inputs = Path(input_dir)
    root.mkdir(parents=True, exist_ok=True)
    _validate_inputs(inputs)
    if include_qiskit and not qiskit_available():
        raise RuntimeError("Qiskit Aer is unavailable; install requirements-qiskit.txt")

    roster = load_seed_roster(inputs / "official_board_seed_roster.h")
    if seed_limit is not None:
        if seed_limit < 1:
            raise ValueError("seed_limit must be positive")
        roster = roster[:seed_limit]
    targets = tuple(int(value) for value in target_counts)
    if any(value not in TARGET_COUNTS for value in targets):
        raise ValueError(f"target_counts must be selected from {TARGET_COUNTS}")

    journal = root / "software_resume_records.jsonl"
    completed = _load_journal(journal)
    prepared_by_target: dict[int, dict[int, object]] = defaultdict(dict)

    workload_total = len(targets) * len(roster)
    workload_number = 0
    for target_count in targets:
        dataset = build_official_board_benchmark_dataset(target_count)
        _verify_dataset_binary(inputs, target_count, dataset.memory_image)
        for pair in roster:
            workload_number += 1
            cfg = replace(
                dataset.config,
                seed_j=pair.seed_j,
                seed_meas=pair.seed_meas,
                shot_cap=100,
            )
            common = {
                "target_count": target_count,
                "seed_index": pair.seed_index,
                "seed_j": f"0x{pair.seed_j:08x}",
                "seed_meas": f"0x{pair.seed_meas:08x}",
            }

            key = (target_count, pair.seed_index, "NUMPY_FLOAT64")
            if key not in completed:
                result = run_v098_bbht_numpy(
                    dataset.target_mask,
                    seed_j=pair.seed_j,
                    seed_measurement=pair.seed_meas,
                    shot_cap=100,
                )
                _append_jsonl(journal, _software_row(common, key[2], result))
                completed.add(key)

            if include_qiskit:
                key = (target_count, pair.seed_index, "QISKIT_AER_STATEVECTOR")
                if key not in completed:
                    result = run_v098_bbht_qiskit(
                        dataset.target_mask,
                        seed_j=pair.seed_j,
                        seed_measurement=pair.seed_meas,
                        shot_cap=100,
                        optimization_level=optimization_level,
                        threads=threads,
                        prepared_cache=prepared_by_target[target_count],
                    )
                    _append_jsonl(journal, _software_row(common, key[2], result))
                    completed.add(key)

            if include_fixed_models:
                for backend, mode in (
                    ("RTL_FIXED_NORMAL", "NORMAL"),
                    ("SOFTWARE_K4H4", "K4H4"),
                    ("SOFTWARE_K3H3", "K3H3"),
                ):
                    key = (target_count, pair.seed_index, backend)
                    if key in completed:
                        continue
                    started = perf_counter()
                    result = V098AutomaticCore(dataset, cfg).run_single(mode=mode)
                    elapsed = perf_counter() - started
                    _append_jsonl(
                        journal,
                        _software_row(common, backend, result, measured_seconds=elapsed),
                    )
                    completed.add(key)
            print(
                f"[{workload_number}/{workload_total}] "
                f"M={target_count} seed_index={pair.seed_index} complete",
                flush=True,
            )

    software_rows = _read_jsonl(journal)
    board_rows = _load_board_rows(inputs, targets, roster)
    all_rows = software_rows + board_rows
    _write_csv(root / "common500_all_backend_results.csv", all_rows)
    _write_csv(root / "common500_summary_by_target_count.csv", _summarize(all_rows))
    checks = _build_correctness_checks(all_rows)
    _write_csv(root / "common500_workload_correctness.csv", checks)
    _write_csv(root / "fpga_configuration_speedup.csv", _fpga_speedups(all_rows))
    _write_csv(root / "checkpoint_model_fpga_iteration_delta.csv", _policy_model_deltas(all_rows))
    _write_report(root, all_rows, checks, targets, roster)
    _write_svg_charts(root, all_rows)
    _write_manifest(root, inputs, targets, roster, include_qiskit, include_fixed_models)
    return root


def _software_row(
    common: dict[str, object],
    backend: str,
    result,
    *,
    measured_seconds: float | None = None,
) -> dict[str, object]:
    execution_seconds = getattr(result, "execution_seconds", None)
    if execution_seconds is None:
        execution_seconds = getattr(result, "qiskit_execution_seconds", None)
    return {
        **common,
        "backend": backend,
        "platform": "SERVER_CPU",
        "timing_scope": (
            "AER_EXECUTION_ONLY" if backend.startswith("QISKIT")
            else "NUMPY_CORE_ONLY" if backend.startswith("NUMPY")
            else "PYTHON_FIXED_MODEL_WALL"
        ),
        "success": int(result.success),
        "termination_reason": result.termination_reason,
        "result_index": "" if result.result_index is None else result.result_index,
        "trial_count": result.trial_count,
        "L_BBHT": result.L_BBHT,
        "actual_grover_iterations": getattr(result, "actual_grover_iterations", ""),
        "cycle_count": "",
        "elapsed_us": "",
        "execution_seconds": (
            measured_seconds if measured_seconds is not None
            else "" if execution_seconds is None else execution_seconds
        ),
        "wall_seconds": (
            measured_seconds if measured_seconds is not None
            else getattr(result, "wall_seconds", "")
        ),
        "build_seconds": getattr(result, "circuit_build_seconds", ""),
        "transpile_seconds": getattr(result, "transpile_seconds", ""),
    }


def _load_board_rows(
    inputs: Path,
    targets: Sequence[int],
    roster: Sequence[SeedPair],
) -> list[dict[str, object]]:
    allowed = {(m, pair.seed_index) for m in targets for pair in roster}
    result: list[dict[str, object]] = []
    files = {
        "FPGA_NORMAL_E1": "fpga_normal_per_run.csv",
        "FPGA_K4H4_E1": "fpga_checkpoint_k4h4_per_run.csv",
        "FPGA_K3H3_E4_M2": "fpga_final_k3h3_e4_m2_per_run.csv",
    }
    for backend, filename in files.items():
        with (inputs / "fpga" / filename).open(encoding="utf-8-sig", newline="") as handle:
            for row in csv.DictReader(handle):
                key = (int(row["target_count"]), int(row["seed_index"]))
                if key not in allowed:
                    continue
                result.append({
                    "target_count": key[0],
                    "seed_index": key[1],
                    "seed_j": row["seed_j"].lower(),
                    "seed_meas": row["seed_meas"].lower(),
                    "backend": backend,
                    "platform": "ARTY_A7_100T_100MHZ",
                    "timing_scope": "BOARD_COMMAND_TO_RESULT_ELAPSED",
                    "success": int(row["success"]),
                    "termination_reason": "SUCCESS" if int(row["success"]) else row["terminal_limit"],
                    "result_index": row["result_index"],
                    "trial_count": row["trial_count"],
                    "L_BBHT": row["l_bbht"],
                    "actual_grover_iterations": row["actual_iter"],
                    "cycle_count": row["cycle_count"],
                    "elapsed_us": row["elapsed_us"],
                    "execution_seconds": float(row["elapsed_us"]) / 1_000_000.0,
                    "wall_seconds": "",
                    "build_seconds": "",
                    "transpile_seconds": "",
                })
    expected = len(allowed) * len(files)
    if len(result) != expected:
        raise ValueError(f"expected {expected} FPGA rows, found {len(result)}")
    return result


def _build_correctness_checks(rows: Sequence[dict[str, object]]) -> list[dict[str, object]]:
    grouped: dict[tuple[int, int], dict[str, dict[str, object]]] = defaultdict(dict)
    for row in rows:
        grouped[(int(row["target_count"]), int(row["seed_index"]))][str(row["backend"])] = row
    checks = []
    for (target_count, seed_index), items in sorted(grouped.items()):
        fixed = items.get("RTL_FIXED_NORMAL")
        numpy_row = items.get("NUMPY_FLOAT64")
        qiskit_row = items.get("QISKIT_AER_STATEVECTOR")
        board_normal = items.get("FPGA_NORMAL_E1")
        software_k4 = items.get("SOFTWARE_K4H4")
        board_k4 = items.get("FPGA_K4H4_E1")
        software_k3 = items.get("SOFTWARE_K3H3")
        board_k3 = items.get("FPGA_K3H3_E4_M2")
        checks.append({
            "target_count": target_count,
            "seed_index": seed_index,
            "numpy_qiskit_logical_match": _same(numpy_row, qiskit_row, ("result_index", "trial_count", "L_BBHT")),
            "fixed_fpga_normal_match": _same(fixed, board_normal, ("result_index", "trial_count", "L_BBHT", "actual_grover_iterations")),
            "software_k4_fpga_k4_logical_match": _same(software_k4, board_k4, ("result_index", "trial_count", "L_BBHT")),
            "software_k4_fpga_k4_physical_iter_match": _same(software_k4, board_k4, ("actual_grover_iterations",)),
            "software_k3_fpga_k3_logical_match": _same(software_k3, board_k3, ("result_index", "trial_count", "L_BBHT")),
            "software_k3_fpga_k3_physical_iter_match": _same(software_k3, board_k3, ("actual_grover_iterations",)),
            "all_fpga_logical_match": _same(board_normal, board_k4, ("result_index", "trial_count", "L_BBHT")) and _same(board_normal, board_k3, ("result_index", "trial_count", "L_BBHT")),
        })
    return checks


def _same(left, right, fields: Iterable[str]) -> bool | str:
    if left is None or right is None:
        return "NOT_RUN"
    return all(str(left[field]) == str(right[field]) for field in fields)


def _summarize(rows: Sequence[dict[str, object]]) -> list[dict[str, object]]:
    groups: dict[tuple[int, str], list[dict[str, object]]] = defaultdict(list)
    for row in rows:
        groups[(int(row["target_count"]), str(row["backend"]))].append(row)
    result = []
    for (target_count, backend), items in sorted(groups.items()):
        trials = [int(item["trial_count"]) for item in items]
        logical = [int(item["L_BBHT"]) for item in items]
        physical = [int(item["actual_grover_iterations"]) for item in items if str(item["actual_grover_iterations"]) != ""]
        times = [float(item["execution_seconds"]) for item in items if str(item["execution_seconds"]) != ""]
        result.append({
            "target_count": target_count,
            "backend": backend,
            "runs": len(items),
            "success_rate": sum(int(item["success"]) for item in items) / len(items),
            "median_trial_count": median(trials),
            "p95_trial_count": _percentile(trials, 95),
            "median_L_BBHT": median(logical),
            "p95_L_BBHT": _percentile(logical, 95),
            "median_actual_grover_iterations": median(physical) if physical else "",
            "p95_actual_grover_iterations": _percentile(physical, 95) if physical else "",
            "median_execution_seconds": median(times) if times else "",
            "p95_execution_seconds": _percentile(times, 95) if times else "",
            "timing_scope": items[0]["timing_scope"],
        })
    return result


def _fpga_speedups(rows: Sequence[dict[str, object]]) -> list[dict[str, object]]:
    grouped: dict[tuple[int, int], dict[str, float]] = defaultdict(dict)
    for row in rows:
        if str(row["backend"]) in FPGA_BACKENDS:
            grouped[(int(row["target_count"]), int(row["seed_index"]))][str(row["backend"])] = float(row["elapsed_us"])
    result = []
    for target_count in TARGET_COUNTS:
        items = [value for (m, _), value in grouped.items() if m == target_count]
        if not items:
            continue
        normal = [item["FPGA_NORMAL_E1"] for item in items]
        k4 = [item["FPGA_K4H4_E1"] for item in items]
        k3 = [item["FPGA_K3H3_E4_M2"] for item in items]
        result.append({
            "target_count": target_count,
            "runs": len(items),
            "normal_sum_us": sum(normal),
            "k4_sum_us": sum(k4),
            "k3_sum_us": sum(k3),
            "normal_over_k4_total_speedup": sum(normal) / sum(k4),
            "normal_over_k3_total_speedup": sum(normal) / sum(k3),
            "k4_over_k3_total_speedup": sum(k4) / sum(k3),
            "normal_median_us": median(normal),
            "k4_median_us": median(k4),
            "k3_median_us": median(k3),
        })
    return result


def _policy_model_deltas(
    rows: Sequence[dict[str, object]],
) -> list[dict[str, object]]:
    """Expose checkpoint-model agreement without mixing it into speed claims."""

    grouped: dict[tuple[int, int], dict[str, dict[str, object]]] = defaultdict(dict)
    for row in rows:
        grouped[(int(row["target_count"]), int(row["seed_index"]))][
            str(row["backend"])
        ] = row

    pairs = (
        ("K4H4", "SOFTWARE_K4H4", "FPGA_K4H4_E1"),
        ("K3H3", "SOFTWARE_K3H3", "FPGA_K3H3_E4_M2"),
    )
    result: list[dict[str, object]] = []
    for (target_count, seed_index), items in sorted(grouped.items()):
        for policy, software_name, fpga_name in pairs:
            software = items.get(software_name)
            fpga = items.get(fpga_name)
            if software is None or fpga is None:
                continue
            software_iter = int(software["actual_grover_iterations"])
            fpga_iter = int(fpga["actual_grover_iterations"])
            result.append({
                "target_count": target_count,
                "seed_index": seed_index,
                "policy": policy,
                "software_actual_grover_iterations": software_iter,
                "fpga_actual_grover_iterations": fpga_iter,
                "delta": software_iter - fpga_iter,
                "exact_match": int(software_iter == fpga_iter),
            })
    return result


def _write_report(root: Path, rows, checks, targets, roster) -> None:
    summaries = _summarize(rows)
    speedups = _fpga_speedups(rows)
    check_names = [key for key in checks[0] if key not in {"target_count", "seed_index"}] if checks else []
    check_lines = []
    for name in check_names:
        values = [item[name] for item in checks]
        passed = sum(value is True for value in values)
        not_run = sum(value == "NOT_RUN" for value in values)
        check_lines.append(f"| `{name}` | {passed}/{len(values) - not_run} | {not_run} |")
    fpga_lines = [
        "| M | Normal total (us) | K4/H4 total (us) | K3/H3-E4-M2 total (us) | Normal/K3 speedup | K4/K3 speedup |",
        "| ---: | ---: | ---: | ---: | ---: | ---: |",
    ]
    for item in speedups:
        fpga_lines.append(
            f"| {item['target_count']} | {item['normal_sum_us']:.0f} | {item['k4_sum_us']:.0f} | "
            f"{item['k3_sum_us']:.0f} | {item['normal_over_k3_total_speedup']:.3f}x | "
            f"{item['k4_over_k3_total_speedup']:.3f}x |"
        )
    backend_lines = [
        "| M | Backend | Runs | Success | Median trial | Median L_BBHT | Median runtime (s) | Scope |",
        "| ---: | --- | ---: | ---: | ---: | ---: | ---: | --- |",
    ]
    for item in summaries:
        runtime = item["median_execution_seconds"]
        runtime_text = "-" if runtime == "" else f"{float(runtime):.9f}"
        backend_lines.append(
            f"| {item['target_count']} | `{item['backend']}` | {item['runs']} | "
            f"{item['success_rate']:.3f} | {item['median_trial_count']} | {item['median_L_BBHT']} | "
            f"{runtime_text} | `{item['timing_scope']}` |"
        )
    report = f"""# Q14 BBHT 공통 500-workload 비교 결과

## 1. 실험 계약

| 항목 | 값 |
| --- | --- |
| 검색공간 | Q14, N=16,384 |
| 데이터 | signed 16-bit, 공식 보드 dataset |
| Oracle | EQ, target value 0xA55A |
| M | {', '.join(map(str, targets))} |
| seed | 공식 roster {len(roster)}쌍 |
| 공통 workload | {len(targets) * len(roster)}개 |
| BBHT | m0=1, lambda=6/5, m_max=128, logical budget=576 |
| 진폭 기준모델 | signed Q1.22, AMP_W=23 |

## 2. 비교 대상

| 분류 | Backend | 역할 |
| --- | --- | --- |
| SW | `NUMPY_FLOAT64` | 직접 상태벡터 Float64 기준선 |
| SW | `QISKIT_AER_STATEVECTOR` | 범용 양자 시뮬레이터 기준선 |
| Golden | `RTL_FIXED_NORMAL` | Q1.22 bit-exact Normal 기준 |
| Golden | `SOFTWARE_K4H4` | 과거 K4/H4 checkpoint 정책 기준 |
| Golden | `SOFTWARE_K3H3` | 최종 K3/H3 checkpoint 정책 기준 |
| FPGA | `FPGA_NORMAL_E1` | 팀원 보드 실측 Normal |
| FPGA | `FPGA_K4H4_E1` | 팀원 보드 실측 K4/H4 |
| FPGA | `FPGA_K3H3_E4_M2` | 팀원 보드 실측 최종 구성 |

## 3. 정합성

| 검사 | PASS/실행 | 미실행 |
| --- | ---: | ---: |
{chr(10).join(check_lines)}

`actual_grover_iterations`는 checkpoint 정책이 실제로 수행한 Grover 반복 수다.
동일 정책의 Golden과 FPGA 값은 정확히 일치해야 한다. 정책 solver 지연,
plan FIFO stall, E4/M2 datapath 최적화는 이 값이 아니라 FPGA `cycle_count`에
반영된다. workload별 물리 반복 수 차이는 `checkpoint_model_fpga_iteration_delta.csv`에 기록한다.

## 4. FPGA 실행시간

{chr(10).join(fpga_lines)}

![FPGA 실행시간](fpga_runtime_by_target_count.svg)

## 5. Backend별 결과

{chr(10).join(backend_lines)}

![소프트웨어 실행시간](software_runtime_by_target_count.svg)

## 6. 해석 규칙

- 동일 seed에서 `requested_j`, 측정 CDF, 결과 index를 비교한다.
- K4/H4와 K3/H3 checkpoint는 논리 결과를 바꾸면 안 되며 Golden과 FPGA의 `actual_grover_iterations`도 같아야 한다.
- E4/M2는 FPGA datapath와 measurement cycle 최적화이므로 소프트웨어 K3/H3의 벽시계 시간으로 대체하지 않는다.
- FPGA 시간은 보드 command-to-result, NumPy는 core 계산, Qiskit은 Aer execution이다. 서로 다른 플랫폼의 절대시간 비율은 참고값이며, FPGA 내부 구성 간 speedup만 직접 성능 주장에 사용한다.
- Qiskit build/transpile 시간은 원시 결과의 별도 열에 남긴다.
"""
    (root / "common500_validation_report.md").write_text(report, encoding="utf-8")


def _write_svg_charts(root: Path, rows: Sequence[dict[str, object]]) -> None:
    summary = _summarize(rows)
    fpga = [item for item in summary if item["backend"] in FPGA_BACKENDS]
    software = [item for item in summary if item["backend"] in {"NUMPY_FLOAT64", "QISKIT_AER_STATEVECTOR"}]
    _bar_svg(root / "fpga_runtime_by_target_count.svg", fpga, "FPGA median elapsed time", "median_execution_seconds")
    _bar_svg(root / "software_runtime_by_target_count.svg", software, "Server median execution time", "median_execution_seconds")


def _bar_svg(path: Path, rows: Sequence[dict[str, object]], title: str, field: str) -> None:
    width, height = 1100, 520
    margin_left, margin_bottom, margin_top = 90, 100, 60
    plot_w, plot_h = width - margin_left - 30, height - margin_bottom - margin_top
    values = [float(row[field]) for row in rows if row[field] != ""]
    maximum = max(values, default=1.0)
    count = max(len(rows), 1)
    bar_w = max(3, plot_w / count * 0.72)
    colors = {name: color for name, color in zip(
        (*FPGA_BACKENDS, "NUMPY_FLOAT64", "QISKIT_AER_STATEVECTOR"),
        ("#64748b", "#0f766e", "#b45309", "#2563eb", "#7c3aed"),
    )}
    parts = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">',
        '<rect width="100%" height="100%" fill="white"/>',
        f'<text x="{width/2}" y="32" text-anchor="middle" font-family="Arial" font-size="22" font-weight="bold">{title}</text>',
        f'<line x1="{margin_left}" y1="{margin_top+plot_h}" x2="{margin_left+plot_w}" y2="{margin_top+plot_h}" stroke="#334155"/>',
    ]
    for index, row in enumerate(rows):
        value = float(row[field])
        x = margin_left + (index + 0.5) * plot_w / count - bar_w / 2
        h = 0 if maximum == 0 else value / maximum * plot_h
        y = margin_top + plot_h - h
        backend = str(row["backend"])
        parts.append(f'<rect x="{x:.2f}" y="{y:.2f}" width="{bar_w:.2f}" height="{h:.2f}" fill="{colors.get(backend, "#475569")}"/>')
        parts.append(f'<text x="{x+bar_w/2:.2f}" y="{y-5:.2f}" text-anchor="middle" font-family="Arial" font-size="10">{value:.6g}</text>')
        label = f"M{row['target_count']} {backend.replace('FPGA_', '').replace('_STATEVECTOR', '')}"
        parts.append(f'<text transform="translate({x+bar_w/2:.2f},{margin_top+plot_h+12}) rotate(60)" font-family="Arial" font-size="9">{label}</text>')
    parts.append('</svg>')
    path.write_text("\n".join(parts), encoding="utf-8")


def _write_manifest(root, inputs, targets, roster, include_qiskit, include_fixed) -> None:
    files = [inputs / "official_board_seed_roster.h", *(inputs / "datasets" / f"dataset_target_{m}.bin" for m in targets)]
    manifest = {
        "created_utc": datetime.now(timezone.utc).isoformat(),
        "python": sys.version,
        "platform": platform.platform(),
        "packages": package_versions(),
        "target_counts": list(targets),
        "seed_count": len(roster),
        "workload_count": len(targets) * len(roster),
        "include_qiskit": include_qiskit,
        "include_fixed_models": include_fixed,
        "input_sha256": {path.name: _sha256(path) for path in files},
    }
    (root / "experiment_manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def _validate_inputs(inputs: Path) -> None:
    required = [
        inputs / "official_board_seed_roster.h",
        inputs / "fpga" / "fpga_normal_per_run.csv",
        inputs / "fpga" / "fpga_checkpoint_k4h4_per_run.csv",
        inputs / "fpga" / "fpga_final_k3h3_e4_m2_per_run.csv",
        *(inputs / "datasets" / f"dataset_target_{m}.bin" for m in TARGET_COUNTS),
    ]
    missing = [str(path) for path in required if not path.is_file()]
    if missing:
        raise FileNotFoundError("missing benchmark inputs:\n" + "\n".join(missing))


def _verify_dataset_binary(inputs: Path, target_count: int, expected: np.ndarray) -> None:
    path = inputs / "datasets" / f"dataset_target_{target_count}.bin"
    actual = np.fromfile(path, dtype="<i2")
    if not np.array_equal(actual, np.asarray(expected, dtype=np.int16)):
        raise ValueError(f"official dataset mismatch: {path}")


def _load_journal(path: Path) -> set[tuple[int, int, str]]:
    return {
        (int(row["target_count"]), int(row["seed_index"]), str(row["backend"]))
        for row in _read_jsonl(path)
    }


def _read_jsonl(path: Path) -> list[dict[str, object]]:
    if not path.exists():
        return []
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]


def _append_jsonl(path: Path, row: dict[str, object]) -> None:
    with path.open("a", encoding="utf-8", newline="\n") as handle:
        handle.write(json.dumps(row, ensure_ascii=False, separators=(",", ":")) + "\n")
        handle.flush()


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


def _percentile(values: Sequence[int | float], percentile: float) -> float:
    return float(np.percentile(np.asarray(values, dtype=np.float64), percentile))


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def _parse_targets(text: str) -> tuple[int, ...]:
    return tuple(int(item.strip(), 0) for item in text.split(",") if item.strip())


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--inputs", required=True, help="common500 input directory")
    parser.add_argument("--output", default="verification_results/common500")
    parser.add_argument("--targets", default=",".join(map(str, TARGET_COUNTS)))
    parser.add_argument("--seed-limit", type=int)
    parser.add_argument("--threads", type=int, default=1)
    parser.add_argument("--optimization-level", type=int, default=0)
    parser.add_argument("--skip-qiskit", action="store_true")
    parser.add_argument("--skip-fixed", action="store_true")
    args = parser.parse_args()
    result = run_common500(
        args.output,
        args.inputs,
        target_counts=_parse_targets(args.targets),
        seed_limit=args.seed_limit,
        include_qiskit=not args.skip_qiskit,
        include_fixed_models=not args.skip_fixed,
        threads=args.threads,
        optimization_level=args.optimization_level,
    )
    print(result.resolve())


if __name__ == "__main__":
    main()
