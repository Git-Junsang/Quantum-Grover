from __future__ import annotations

import csv
import json
import statistics
from collections import Counter
from pathlib import Path
from typing import Any, Iterable, Sequence


RAW_CSV_LIMIT_BYTES = 128 * 1024 * 1024


def finalize_campaign_streaming(
    root: str | Path,
    cases: Sequence[Any] | None = None,
) -> dict[str, Any]:
    """Finalize a campaign without loading multi-gigabyte JSONL files in memory."""

    destination = Path(root)
    trial_path = destination / "trials.jsonl"
    attempt_path = destination / "attempts.jsonl"
    summaries: dict[str, dict[str, Any]] = {}
    termination_counts: Counter[str] = Counter()
    pending_padding: dict[tuple[Any, ...], dict[str, Any]] = {}
    padding_count = 0
    padding_mismatches = 0
    completed = 0
    success_count = 0
    expected_outcome_passes = 0
    mask_failures = 0
    padding_failures = 0
    total_time_ms = 0.0

    padding_fields = [
        "profile_name",
        "data_count",
        "target_count",
        "oracle_mode",
        "target_layout",
        "search_variant",
        "trial_index",
        "identical",
        "safe_total_ms",
        "poison_total_ms",
    ]
    with (destination / "padding_comparison.csv").open(
        "w", newline="", encoding="utf-8-sig"
    ) as padding_handle:
        padding_writer = csv.DictWriter(padding_handle, fieldnames=padding_fields)
        padding_writer.writeheader()
        for item in _iter_jsonl(trial_path):
            completed += 1
            success = bool(item["success"])
            target_count = int(item["target_count"])
            success_count += int(success)
            expected_outcome_passes += int(success if target_count > 0 else not success)
            mask_failures += int(not bool(item["mask_match"]))
            padding_failures += int(int(item["padding_target_count"]) != 0)
            trial_time = float(item["trial_total_ms"])
            total_time_ms += trial_time
            termination_counts[str(item["termination_reason"])] += 1
            _update_case_summary(summaries, item)

            if int(item["padding_count"]) == 0:
                continue
            key = (
                item["profile_name"],
                item["data_count"],
                item["target_count"],
                item["oracle_mode"],
                item["target_layout"],
                item["search_variant"],
                item["trial_index"],
            )
            pattern = str(item["padding_pattern"])
            peer = pending_padding.get(key)
            if peer is None:
                pending_padding[key] = {
                    "pattern": pattern,
                    "mask_hash": item["mask_hash"],
                    "amplitude_hash": item["amplitude_hash"],
                    "result_index": item["result_index"],
                    "termination_reason": item["termination_reason"],
                    "trial_total_ms": item["trial_total_ms"],
                }
                continue
            if peer["pattern"] == pattern:
                raise ValueError(f"duplicate padding pattern for comparison key {key!r}")
            identical = (
                peer["mask_hash"] == item["mask_hash"]
                and peer["amplitude_hash"] == item["amplitude_hash"]
                and peer["result_index"] == item["result_index"]
                and peer["termination_reason"] == item["termination_reason"]
            )
            safe_ms = peer["trial_total_ms"] if peer["pattern"] == "SAFE" else item["trial_total_ms"]
            poison_ms = peer["trial_total_ms"] if peer["pattern"] == "POISON" else item["trial_total_ms"]
            padding_writer.writerow(
                {
                    "profile_name": key[0],
                    "data_count": key[1],
                    "target_count": key[2],
                    "oracle_mode": key[3],
                    "target_layout": key[4],
                    "search_variant": key[5],
                    "trial_index": key[6],
                    "identical": identical,
                    "safe_total_ms": safe_ms,
                    "poison_total_ms": poison_ms,
                }
            )
            padding_count += 1
            padding_mismatches += int(not identical)
            del pending_padding[key]

    if pending_padding:
        raise ValueError(f"unpaired SAFE/POISON records: {len(pending_padding)}")

    summary_rows = [_finish_case_summary(value) for value in summaries.values()]
    summary_rows.sort(key=lambda row: str(row["case_id"]))
    _write_csv(destination / "case_summary.csv", summary_rows)
    _write_csv(
        destination / "termination_summary.csv",
        [
            {"termination_reason": reason, "count": count}
            for reason, count in sorted(termination_counts.items())
        ],
    )

    attempt_count = _count_jsonl_records(attempt_path)
    raw_csv_written = False
    if trial_path.stat().st_size + attempt_path.stat().st_size <= RAW_CSV_LIMIT_BYTES:
        _jsonl_to_csv(trial_path, destination / "trials.csv")
        _jsonl_to_csv(attempt_path, destination / "attempts.csv")
        raw_csv_written = True

    report = {
        "case_count": len(cases) if cases is not None else len(summary_rows),
        "completed_execution_count": completed,
        "attempt_count": attempt_count,
        "success_count": success_count,
        "expected_outcome_pass_count": expected_outcome_passes,
        "expected_outcome_pass_rate": expected_outcome_passes / completed if completed else 0.0,
        "mask_failure_count": mask_failures,
        "padding_failure_count": padding_failures,
        "padding_comparison_count": padding_count,
        "padding_mismatch_count": padding_mismatches,
        "mean_trial_total_ms": total_time_ms / completed if completed else 0.0,
        "raw_csv_written": raw_csv_written,
        "raw_jsonl_retained": True,
        "termination_counts": dict(sorted(termination_counts.items())),
    }
    _write_json(destination / "summary.json", report)
    (destination / "report.md").write_text(
        _markdown_report(report, len(summary_rows)), encoding="utf-8"
    )
    return report


def iter_completed_trial_keys(path: Path) -> Iterable[tuple[str, int]]:
    for item in _iter_jsonl(path):
        yield str(item["case_id"]), int(item["trial_index"])


def _update_case_summary(groups: dict[str, dict[str, Any]], item: dict[str, Any]) -> None:
    case_id = str(item["case_id"])
    group = groups.get(case_id)
    if group is None:
        group = {
            "first": item,
            "times": [],
            "trials": 0,
            "successes": 0,
            "expected_passes": 0,
            "attempts": 0.0,
            "logical": 0.0,
            "physical": 0.0,
            "cache_saved": 0.0,
            "l2": 0.0,
            "phase_l2": 0.0,
            "probability_l2": 0.0,
            "success_probability_error": 0.0,
            "normalization_error": 0.0,
            "saturations": 0,
            "components": Counter(),
        }
        groups[case_id] = group
    group["trials"] += 1
    group["successes"] += int(bool(item["success"]))
    group["expected_passes"] += int(
        bool(item["success"]) if int(item["target_count"]) > 0 else not bool(item["success"])
    )
    group["times"].append(float(item["trial_total_ms"]))
    group["attempts"] += float(item["attempt_count"])
    group["logical"] += float(item["logical_grover_iterations"])
    group["physical"] += float(item["physical_grover_iterations"])
    group["cache_saved"] += float(item["cache_saved_iterations"])
    group["l2"] += float(item.get("l2_error", 0.0))
    group["phase_l2"] += float(item.get("phase_aligned_l2_error", 0.0))
    group["probability_l2"] += float(item.get("probability_distribution_l2_error", 0.0))
    group["success_probability_error"] += float(item.get("success_probability_error", 0.0))
    group["normalization_error"] += float(item.get("fixed_normalization_error", 0.0))
    group["saturations"] += int(item.get("saturation_count", 0))
    for field in (
        "input_generation_ms",
        "data_load_ms",
        "oracle_precheck_ms",
        "oracle_mask_ms",
        "scheduler_ms",
        "core_ms",
        "measurement_ms",
        "controller_ms",
    ):
        group["components"][field] += float(item.get(field, 0.0))


def _finish_case_summary(group: dict[str, Any]) -> dict[str, Any]:
    first = group["first"]
    count = int(group["trials"])
    times = group["times"]
    row = {
        key: first[key]
        for key in (
            "case_id",
            "profile_name",
            "active_n",
            "data_count_ratio",
            "data_count",
            "padding_count",
            "target_count",
            "target_density_data",
            "target_density_search",
            "oracle_mode",
            "padding_pattern",
            "target_layout",
            "search_variant",
        )
    }
    row.update(
        {
            "trials": count,
            "success_rate": group["successes"] / count,
            "expected_outcome_pass_rate": group["expected_passes"] / count,
            "mean_attempts": group["attempts"] / count,
            "mean_logical_iterations": group["logical"] / count,
            "mean_physical_iterations": group["physical"] / count,
            "mean_cache_saved_iterations": group["cache_saved"] / count,
            "cache_saving_rate": group["cache_saved"] / group["logical"] if group["logical"] else 0.0,
            "mean_trial_total_ms": statistics.fmean(times),
            "median_trial_total_ms": statistics.median(times),
            "p95_trial_total_ms": _percentile(times, 95.0),
            "min_trial_total_ms": min(times),
            "max_trial_total_ms": max(times),
            "mean_l2_error": group["l2"] / count,
            "mean_phase_aligned_l2_error": group["phase_l2"] / count,
            "mean_probability_distribution_l2_error": group["probability_l2"] / count,
            "mean_success_probability_error": group["success_probability_error"] / count,
            "mean_fixed_normalization_error": group["normalization_error"] / count,
            "saturation_count": group["saturations"],
        }
    )
    for field, total in group["components"].items():
        row[f"mean_{field}"] = total / count
    return row


def _iter_jsonl(path: Path) -> Iterable[dict[str, Any]]:
    if not path.exists():
        return
    with path.open("r", encoding="utf-8") as handle:
        for line_number, line in enumerate(handle, start=1):
            if not line.strip():
                continue
            try:
                yield json.loads(line)
            except json.JSONDecodeError as exc:
                raise ValueError(f"invalid JSONL at {path}:{line_number}") from exc


def _count_jsonl_records(path: Path) -> int:
    if not path.exists():
        return 0
    count = 0
    last_byte = b""
    with path.open("rb") as handle:
        while chunk := handle.read(8 * 1024 * 1024):
            count += chunk.count(b"\n")
            last_byte = chunk[-1:]
    return count + int(bool(last_byte) and last_byte != b"\n")


def _jsonl_to_csv(source: Path, destination: Path) -> None:
    records = _iter_jsonl(source)
    first = next(records, None)
    if first is None:
        destination.write_text("", encoding="utf-8")
        return
    with destination.open("w", newline="", encoding="utf-8-sig") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(first), extrasaction="ignore")
        writer.writeheader()
        writer.writerow(first)
        writer.writerows(records)


def _write_csv(path: Path, rows: Sequence[dict[str, Any]]) -> None:
    if not rows:
        path.write_text("", encoding="utf-8")
        return
    fields: list[str] = []
    for row in rows:
        for field in row:
            if field not in fields:
                fields.append(field)
    with path.open("w", newline="", encoding="utf-8-sig") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)


def _write_json(path: Path, payload: dict[str, Any]) -> None:
    path.write_text(json.dumps(payload, indent=2, ensure_ascii=True) + "\n", encoding="utf-8")


def _percentile(values: Sequence[float], percentile: float) -> float:
    ordered = sorted(values)
    if len(ordered) == 1:
        return float(ordered[0])
    position = (len(ordered) - 1) * percentile / 100.0
    lower = int(position)
    upper = min(lower + 1, len(ordered) - 1)
    fraction = position - lower
    return ordered[lower] * (1.0 - fraction) + ordered[upper] * fraction


def _markdown_report(report: dict[str, Any], summary_count: int) -> str:
    raw_csv_note = (
        "Small-run raw CSV files were generated."
        if report["raw_csv_written"]
        else "Raw JSONL files were retained; duplicate multi-gigabyte raw CSV files were intentionally omitted."
    )
    return "\n".join(
        [
            "# RTL Golden Campaign Report",
            "",
            f"- Cases: {report['case_count']:,}",
            f"- Executions: {report['completed_execution_count']:,}",
            f"- Attempts: {report['attempt_count']:,}",
            f"- Expected-outcome pass rate: {report['expected_outcome_pass_rate']:.6%}",
            f"- Mask failures: {report['mask_failure_count']:,}",
            f"- Padding failures: {report['padding_failure_count']:,}",
            f"- SAFE/POISON mismatches: {report['padding_mismatch_count']:,}",
            f"- Mean software trial time: {report['mean_trial_total_ms']:.6f} ms",
            "",
            f"Case summaries: `case_summary.csv` ({summary_count:,} rows)",
            "",
            raw_csv_note,
            "",
            "> Timing values are host software-model runtimes, not measured FPGA wall-clock performance.",
            "",
        ]
    )
