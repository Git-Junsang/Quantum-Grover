"""Batch-compare v0.9.8 manual-core RTL dumps with golden vectors.

The RTL output directory must contain one subdirectory per manifest case. By
default, each subdirectory supplies ``actual_final_amp.hex``. The comparison
is exact: line count and every encoded Q1.22 amplitude word must match.
"""

from __future__ import annotations

import argparse
import json
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any

from rtl_v098_compare import HexComparison, compare_hex_files


@dataclass(frozen=True)
class BatchCaseComparison:
    case_id: str
    passed: bool
    expected_file: str
    actual_file: str
    missing_actual: bool
    comparison: HexComparison | None

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


@dataclass(frozen=True)
class BatchComparison:
    passed: bool
    case_count: int
    passed_count: int
    failed_count: int
    missing_count: int
    cases: tuple[BatchCaseComparison, ...]

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


def compare_vector_campaign(
    vector_root: str | Path,
    actual_root: str | Path,
    *,
    actual_name: str = "actual_final_amp.hex",
) -> BatchComparison:
    """Compare every case listed in ``vector_root/manifest.json``."""

    golden = Path(vector_root)
    actual = Path(actual_root)
    manifest_path = golden / "manifest.json"
    if not manifest_path.is_file():
        raise FileNotFoundError(f"missing vector manifest: {manifest_path}")
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    cases = manifest.get("cases")
    if not isinstance(cases, list) or not cases:
        raise ValueError("vector manifest must contain a non-empty cases list")

    results: list[BatchCaseComparison] = []
    for case in cases:
        case_id = str(case["case_id"])
        expected_file = golden / case_id / "expected_final_amp.hex"
        actual_file = actual / case_id / actual_name
        if not expected_file.is_file():
            raise FileNotFoundError(f"missing golden amplitude file: {expected_file}")
        if not actual_file.is_file():
            results.append(
                BatchCaseComparison(
                    case_id=case_id,
                    passed=False,
                    expected_file=str(expected_file),
                    actual_file=str(actual_file),
                    missing_actual=True,
                    comparison=None,
                )
            )
            continue
        comparison = compare_hex_files(expected_file, actual_file)
        results.append(
            BatchCaseComparison(
                case_id=case_id,
                passed=comparison.passed,
                expected_file=str(expected_file),
                actual_file=str(actual_file),
                missing_actual=False,
                comparison=comparison,
            )
        )

    passed_count = sum(item.passed for item in results)
    missing_count = sum(item.missing_actual for item in results)
    return BatchComparison(
        passed=passed_count == len(results),
        case_count=len(results),
        passed_count=passed_count,
        failed_count=len(results) - passed_count,
        missing_count=missing_count,
        cases=tuple(results),
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("vector_root")
    parser.add_argument("actual_root")
    parser.add_argument("--actual-name", default="actual_final_amp.hex")
    parser.add_argument("--output", default="v098_batch_comparison.json")
    args = parser.parse_args()
    report = compare_vector_campaign(
        args.vector_root,
        args.actual_root,
        actual_name=args.actual_name,
    )
    Path(args.output).write_text(
        json.dumps(report.to_dict(), indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    print(
        f"{'PASS' if report.passed else 'FAIL'} "
        f"{report.passed_count}/{report.case_count} "
        f"(missing={report.missing_count})"
    )
    return 0 if report.passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
