"""Compare RTL result dumps against golden-model expectations."""

from __future__ import annotations

import argparse
import json
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any, Iterable


DEFAULT_FIELDS = (
    "result_index",
    "trial_count",
    "L_BBHT",
    "actual_grover_iterations",
)


@dataclass(frozen=True)
class FieldComparison:
    field: str
    expected: Any
    actual: Any
    passed: bool


@dataclass(frozen=True)
class ComparisonReport:
    expected_file: str
    actual_file: str
    passed: bool
    fields: tuple[FieldComparison, ...]
    missing_expected: tuple[str, ...]
    missing_actual: tuple[str, ...]

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


def _flatten_candidate(payload: dict[str, Any]) -> dict[str, Any]:
    """Accept handoff, enumeration, and plain register-dump JSON layouts."""
    for key in ("result", "expected", "expected_result", "rtl_result"):
        value = payload.get(key)
        if isinstance(value, dict):
            merged = dict(payload)
            merged.update(value)
            return merged
    return payload


def _parse_scalar(text: str) -> Any:
    token = text.strip()
    lowered = token.lower()
    if lowered in {"true", "false"}:
        return lowered == "true"
    if lowered in {"none", "null"}:
        return None
    try:
        return int(token, 0)
    except ValueError:
        try:
            return float(token)
        except ValueError:
            return token


def load_result(path: str | Path) -> dict[str, Any]:
    path = Path(path)
    if path.suffix.lower() == ".json":
        payload = json.loads(path.read_text(encoding="utf-8"))
        if not isinstance(payload, dict):
            raise ValueError(f"{path} must contain a JSON object")
        return _flatten_candidate(payload)

    result: dict[str, Any] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        if "=" not in stripped:
            raise ValueError(f"invalid result line in {path}: {line!r}")
        key, value = stripped.split("=", 1)
        result[key.strip()] = _parse_scalar(value)
    return result


def compare_result_files(
    expected_file: str | Path,
    actual_file: str | Path,
    *,
    fields: Iterable[str] = DEFAULT_FIELDS,
) -> ComparisonReport:
    expected = load_result(expected_file)
    actual = load_result(actual_file)
    requested = tuple(fields)
    missing_expected = tuple(field for field in requested if field not in expected)
    missing_actual = tuple(field for field in requested if field not in actual)
    comparisons = tuple(
        FieldComparison(
            field=field,
            expected=expected[field],
            actual=actual[field],
            passed=expected[field] == actual[field],
        )
        for field in requested
        if field in expected and field in actual
    )
    passed = not missing_expected and not missing_actual and all(item.passed for item in comparisons)
    return ComparisonReport(
        expected_file=str(Path(expected_file).resolve()),
        actual_file=str(Path(actual_file).resolve()),
        passed=passed,
        fields=comparisons,
        missing_expected=missing_expected,
        missing_actual=missing_actual,
    )


def save_report(report: ComparisonReport, output_file: str | Path) -> Path:
    path = Path(output_file)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(report.to_dict(), indent=2, ensure_ascii=False), encoding="utf-8")
    return path


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("expected")
    parser.add_argument("actual")
    parser.add_argument("--fields", default=",".join(DEFAULT_FIELDS))
    parser.add_argument("--output", default="rtl_comparison_report.json")
    args = parser.parse_args()
    fields = tuple(item.strip() for item in args.fields.split(",") if item.strip())
    report = compare_result_files(args.expected, args.actual, fields=fields)
    save_report(report, args.output)
    print("PASS" if report.passed else "FAIL")
    return 0 if report.passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
