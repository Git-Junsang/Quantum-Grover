from __future__ import annotations

import json
from pathlib import Path
from typing import Any

import numpy as np

from rtl_v07g import (
    RTL_AMP_W,
    RTL_PROFILE_Q16,
    RtlSearchResult,
    RtlV07gConfig,
    RtlV07gModel,
)


HANDOFF_CASES = (
    ("normal_j1", 1, False, 120, 1),
    ("burst_j1", 1, True, 120, 0),
    ("normal_j4", 4, False, 120, 4),
    ("burst_j4", 4, True, 120, 0),
    ("normal_j8", 8, False, 480, 8),
    ("burst_j8", 8, True, 480, 0),
    ("normal_j6", 6, False, 480, 6),
    ("burst_j6", 6, True, 480, 0),
)

Q16_PROJECTED_CASES = (
    ("normal_j1", 1, False, 1),
    ("resume_j4", 4, True, 3),
    ("exact_hit_j4", 4, True, 0),
    ("restart_j2", 2, True, 2),
)


def replay_handoff_8cases(*, trace_level: str = "SUMMARY") -> list[RtlSearchResult]:
    """Reproduce the ordered Normal/Burst sequence supplied with v0.7g."""

    model = RtlV07gModel()
    model.load_dataset(np.zeros(4096, dtype=np.int16))
    results: list[RtlSearchResult] = []
    for _, requested_j, burst_enable, _, _ in HANDOFF_CASES:
        results.append(
            model.run(
                RtlV07gConfig(
                    data_count=4096,
                    predicate_mode="EQ",
                    threshold_a=0,
                    threshold_b=0,
                    auto_shot=False,
                    j_target=requested_j,
                    burst_enable=burst_enable,
                    shot_cap=100,
                    seed_j=0x10203040,
                    seed_meas=0x12345078,
                    trace_level=trace_level,
                )
            )
        )
    return results


def validate_handoff_8cases(results: list[RtlSearchResult]) -> None:
    if len(results) != len(HANDOFF_CASES):
        raise ValueError("exactly eight ordered results are required")
    for result, (name, requested_j, _, expected_index, expected_physical) in zip(
        results,
        HANDOFF_CASES,
    ):
        checks = {
            "success": result.success,
            "result_index": result.result_index == expected_index,
            "trial_count": result.trial_count == 1,
            "L_BBHT": result.L_BBHT == requested_j,
            "actual_grover_iterations": (
                result.actual_grover_iterations == expected_physical
            ),
            "total_weight": result.attempts[0].total_weight == (1 << 44),
        }
        failed = [label for label, passed in checks.items() if not passed]
        if failed:
            raise AssertionError(f"{name} failed: {', '.join(failed)}")


def export_handoff_8case_vectors(
    output_dir: str | Path,
    *,
    include_full_trace: bool = False,
) -> Path:
    """Write reproducible data, amplitude and expectation files for RTL TBs."""

    destination = Path(output_dir)
    destination.mkdir(parents=True, exist_ok=True)
    _write_signed_hex(destination / "data.hex", np.zeros(4096, dtype=np.int64), 16)

    trace_level = "FULL" if include_full_trace else "SUMMARY"
    results = replay_handoff_8cases(trace_level=trace_level)
    validate_handoff_8cases(results)

    cases: list[dict[str, Any]] = []
    for result, (name, requested_j, burst_enable, _, _) in zip(
        results,
        HANDOFF_CASES,
    ):
        case_dir = destination / name
        case_dir.mkdir(parents=True, exist_ok=True)
        assert result.final_encoded_amplitudes is not None
        _write_signed_hex(
            case_dir / "final_amp.hex",
            result.final_encoded_amplitudes,
            RTL_AMP_W,
        )

        attempt = result.attempts[0]
        if include_full_trace:
            for trace in attempt.trace:
                assert trace.amplitudes_after_oracle is not None
                assert trace.amplitudes_after_diffusion is not None
                assert trace.row_partial_sums is not None
                _write_signed_hex(
                    case_dir / f"iter_{trace.iteration:03d}_after_oracle.hex",
                    trace.amplitudes_after_oracle,
                    RTL_AMP_W,
                )
                _write_signed_hex(
                    case_dir / f"iter_{trace.iteration:03d}_after_diffusion.hex",
                    trace.amplitudes_after_diffusion,
                    RTL_AMP_W,
                )
                (case_dir / f"iter_{trace.iteration:03d}_summary.json").write_text(
                    json.dumps(
                        {
                            "iteration": trace.iteration,
                            "row_partial_sums": trace.row_partial_sums.astype(int).tolist(),
                            "global_sum": trace.global_sum,
                            "two_mean": trace.two_mean,
                            "saturation_count": trace.saturation_count,
                        },
                        indent=2,
                        ensure_ascii=True,
                    )
                    + "\n",
                    encoding="utf-8",
                )

        result_payload = result.to_dict(include_amplitudes=False)
        for attempt_payload in result_payload["attempts"]:
            for trace_payload in attempt_payload["trace"]:
                trace_payload["row_partial_sums"] = None
                trace_payload["amplitudes_before"] = None
                trace_payload["amplitudes_after_oracle"] = None
                trace_payload["amplitudes_after_diffusion"] = None
        expected = {
            "name": name,
            "j_target": requested_j,
            "burst_enable": burst_enable,
            **result_payload,
        }
        expected_path = case_dir / "expected_result.json"
        expected_path.write_text(
            json.dumps(expected, indent=2, ensure_ascii=True) + "\n",
            encoding="utf-8",
        )
        cases.append(
            {
                "name": name,
                "directory": name,
                "expected_result": expected_path.relative_to(destination).as_posix(),
            }
        )

    manifest = {
        "profile": "RTL_V07G",
        "dataset": "data.hex",
        "data_count": 4096,
        "cases": cases,
    }
    manifest_path = destination / "manifest.json"
    manifest_path.write_text(
        json.dumps(manifest, indent=2, ensure_ascii=True) + "\n",
        encoding="utf-8",
    )
    return manifest_path


def export_q16_projected_vectors(output_dir: str | Path) -> Path:
    """Export Q16 vectors derived from v0.7g rules, not from delivered Q16 RTL."""

    destination = Path(output_dir)
    destination.mkdir(parents=True, exist_ok=True)
    data_count = 4096
    _write_signed_hex(
        destination / "data.hex",
        np.zeros(data_count, dtype=np.int64),
        RTL_PROFILE_Q16.data_w,
    )

    model = RtlV07gModel(RTL_PROFILE_Q16)
    model.load_dataset(np.zeros(data_count, dtype=np.int16))
    cases: list[dict[str, Any]] = []
    for name, requested_j, burst_enable, expected_physical in Q16_PROJECTED_CASES:
        result = model.run(
            RtlV07gConfig(
                profile=RTL_PROFILE_Q16,
                data_count=data_count,
                predicate_mode="EQ",
                threshold_a=0,
                auto_shot=False,
                j_target=requested_j,
                burst_enable=burst_enable,
                seed_j=0x10203040,
                seed_meas=0x12345078,
                trace_level="SUMMARY",
            )
        )
        if result.actual_grover_iterations != expected_physical:
            raise AssertionError(
                f"{name}: expected {expected_physical} physical iterations, "
                f"got {result.actual_grover_iterations}"
            )
        assert result.final_encoded_amplitudes is not None
        case_dir = destination / name
        case_dir.mkdir(parents=True, exist_ok=True)
        _write_signed_hex(
            case_dir / "final_amp.hex",
            result.final_encoded_amplitudes,
            RTL_PROFILE_Q16.amp_w,
        )
        expected_path = case_dir / "expected_result.json"
        expected_path.write_text(
            json.dumps(
                {
                    "name": name,
                    "profile": RTL_PROFILE_Q16.name,
                    "rtl_validation_status": "PROJECTED_NOT_RTL_VALIDATED",
                    "j_target": requested_j,
                    "burst_enable": burst_enable,
                    **result.to_dict(include_amplitudes=False),
                },
                indent=2,
                ensure_ascii=True,
            )
            + "\n",
            encoding="utf-8",
        )
        cases.append(
            {
                "name": name,
                "directory": name,
                "expected_result": expected_path.relative_to(destination).as_posix(),
                "expected_physical_iterations": expected_physical,
            }
        )

    manifest = {
        "profile": RTL_PROFILE_Q16.name,
        "rtl_validation_status": "PROJECTED_NOT_RTL_VALIDATED",
        "derivation": "v0.7g Q14 arithmetic, P32 mapping, BBHT and cache rules",
        "dataset": "data.hex",
        "data_count": data_count,
        "active_n": RTL_PROFILE_Q16.n,
        "cases": cases,
    }
    manifest_path = destination / "manifest.json"
    manifest_path.write_text(
        json.dumps(manifest, indent=2, ensure_ascii=True) + "\n",
        encoding="utf-8",
    )
    return manifest_path


def _write_signed_hex(path: Path, values: np.ndarray, width: int) -> None:
    checked = np.asarray(values)
    if checked.ndim != 1 or not np.issubdtype(checked.dtype, np.integer):
        raise TypeError("hex values must be a one-dimensional integer array")
    digits = (width + 3) // 4
    mask = (1 << width) - 1
    path.write_text(
        "".join(f"{int(value) & mask:0{digits}X}\n" for value in checked),
        encoding="ascii",
    )
