"""Compare v0.9.8 RTL/board dumps and amplitude files with golden artifacts."""

from __future__ import annotations

import argparse
import json
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any, Iterable

from rtl_output_compare import load_result


SINGLE_FIELDS = (
    "result_index",
    "trial_count",
    "L_BBHT",
    "actual_grover_iterations",
)
ENUM_FIELDS = (
    "found_count",
    "trial_count",
    "L_BBHT",
    "actual_grover_iterations",
    "fifo_stall_cycles",
)
K4_TELEMETRY_FIELDS = (
    "plan_fifo_mismatch_count",
    "policy_cycles_total",
    "policy_stall_cycles",
    "policy_actions_eval",
    "policy_memo_hit",
    "policy_memo_miss",
    "policy_max_latency",
    "plan_fifo_hit_count",
    "policy_cold_solve_count",
    "policy_spec_solve_count",
)

ALIASES = {
    "actual_iter": "actual_grover_iterations",
    "ACTUAL_ITER": "actual_grover_iterations",
    "l_bbht": "L_BBHT",
    "cycle": "cycle_count",
    "mismatch": "plan_fifo_mismatch_count",
}


@dataclass(frozen=True)
class ValueMismatch:
    field: str
    expected: Any
    actual: Any


@dataclass(frozen=True)
class RuntimeComparison:
    passed: bool
    fields: tuple[str, ...]
    mismatches: tuple[ValueMismatch, ...]
    missing_expected: tuple[str, ...]
    missing_actual: tuple[str, ...]

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


@dataclass(frozen=True)
class HexComparison:
    passed: bool
    expected_count: int
    actual_count: int
    mismatch_count: int
    first_mismatch_index: int | None
    expected_first_value: str | None
    actual_first_value: str | None

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


def normalize_runtime_payload(payload: dict[str, Any]) -> dict[str, Any]:
    result = dict(payload)
    for old, new in ALIASES.items():
        if old in result and new not in result:
            result[new] = result[old]
    for container in ("result", "expected", "expected_result", "rtl_result", "counters"):
        nested = result.get(container)
        if isinstance(nested, dict):
            result.update(normalize_runtime_payload(nested))
    return result


def compare_runtime_files(
    expected_file: str | Path,
    actual_file: str | Path,
    *,
    fields: Iterable[str] = SINGLE_FIELDS,
) -> RuntimeComparison:
    expected = normalize_runtime_payload(load_result(expected_file))
    actual = normalize_runtime_payload(load_result(actual_file))
    requested = tuple(fields)
    missing_expected = tuple(field for field in requested if field not in expected)
    missing_actual = tuple(field for field in requested if field not in actual)
    mismatches = tuple(
        ValueMismatch(field, expected[field], actual[field])
        for field in requested
        if field in expected and field in actual and expected[field] != actual[field]
    )
    return RuntimeComparison(
        passed=not missing_expected and not missing_actual and not mismatches,
        fields=requested,
        mismatches=mismatches,
        missing_expected=missing_expected,
        missing_actual=missing_actual,
    )


def compare_hex_files(expected_file: str | Path, actual_file: str | Path) -> HexComparison:
    expected = _hex_lines(expected_file)
    actual = _hex_lines(actual_file)
    overlap = min(len(expected), len(actual))
    mismatch_indices = [index for index in range(overlap) if expected[index] != actual[index]]
    mismatch_count = len(mismatch_indices) + abs(len(expected) - len(actual))
    first = mismatch_indices[0] if mismatch_indices else (overlap if len(expected) != len(actual) else None)
    return HexComparison(
        passed=mismatch_count == 0,
        expected_count=len(expected),
        actual_count=len(actual),
        mismatch_count=mismatch_count,
        first_mismatch_index=first,
        expected_first_value=expected[first] if first is not None and first < len(expected) else None,
        actual_first_value=actual[first] if first is not None and first < len(actual) else None,
    )


def _hex_lines(path: str | Path) -> list[str]:
    result = []
    for raw in Path(path).read_text(encoding="ascii").splitlines():
        token = raw.strip().lower().replace("_", "")
        if not token or token.startswith("#") or token.startswith("//"):
            continue
        int(token, 16)
        result.append(token.lstrip("0") or "0")
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    runtime = sub.add_parser("runtime")
    runtime.add_argument("expected")
    runtime.add_argument("actual")
    runtime.add_argument("--fields", default=",".join(SINGLE_FIELDS))
    runtime.add_argument("--output", default="v098_comparison.json")
    hexdump = sub.add_parser("hex")
    hexdump.add_argument("expected")
    hexdump.add_argument("actual")
    hexdump.add_argument("--output", default="v098_comparison.json")
    args = parser.parse_args()
    if args.command == "runtime":
        fields = tuple(x.strip() for x in args.fields.split(",") if x.strip())
        report: Any = compare_runtime_files(args.expected, args.actual, fields=fields)
    else:
        report = compare_hex_files(args.expected, args.actual)
    Path(args.output).write_text(
        json.dumps(report.to_dict(), indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    print("PASS" if report.passed else "FAIL")
    return 0 if report.passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
