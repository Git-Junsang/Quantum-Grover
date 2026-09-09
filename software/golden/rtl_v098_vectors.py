"""Export v0.9.8 manual-core golden vectors without guessing final PRNG/policy RTL.

The fixed-point Grover datapath is frozen from the validated Q14/P32/F22
implementation.  Manual-j vectors therefore remain bit-exact and are suitable
for checking Oracle, mean, diffusion, saturation, memory mapping, and padding.
Autonomous J/measurement/K4-H8 outputs require the frozen Main-IP source or an
RTL/board trace and are deliberately not fabricated here.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any, Sequence

import numpy as np

from rtl_v07g import RTL_PROFILE_Q14, rtl_initial_state, rtl_run_core
from rtl_v098_contract import (
    V098_AMP_W,
    V098_FRAC_BITS,
    V098_N_ENTRIES,
    V098_VERSION,
    pack_signed16_ahb_words,
)
from rtl_v098_data import V098Dataset, build_controlled_v098_dataset


@dataclass(frozen=True)
class V098CoreVectorCase:
    case_id: str
    predicate_mode: str
    data_count: int
    target_count: int
    requested_j: int
    layout: str = "HEAD"
    seed: int = 1
    threshold_a: int | None = None
    threshold_b: int | None = None
    target_indices: tuple[int, ...] | None = None
    padding_poison_value: int | None = None
    trace_level: str = "FULL"


DEFAULT_CORE_CASES = (
    V098CoreVectorCase("eq_m1_j0", "EQ", 16384, 1, 0),
    V098CoreVectorCase("eq_m1_j1", "EQ", 16384, 1, 1),
    V098CoreVectorCase("eq_m1_j4", "EQ", 16384, 1, 4),
    V098CoreVectorCase("eq_m1_j8", "EQ", 16384, 1, 8),
    V098CoreVectorCase("gt_m4_pad50_j4", "GT", 8192, 4, 4, "RANDOM", 11),
    V098CoreVectorCase("lt_m16_pad75_j8", "LT", 12288, 16, 8, "RANDOM", 12),
    V098CoreVectorCase("range_m8_odd_j6", "RANGE", 4097, 8, 6, "RANDOM", 13),
    V098CoreVectorCase("eq_m0_pad25_j1", "EQ", 4096, 0, 1),
    V098CoreVectorCase(
        "eq_min_lane31_j2", "EQ", 64, 1, 2, "EXPLICIT", 1,
        -32768, None, (31,),
    ),
    V098CoreVectorCase(
        "eq_max_lane32_j2", "EQ", 64, 1, 2, "EXPLICIT", 1,
        32767, None, (32,),
    ),
    V098CoreVectorCase(
        "eq_last_index_j1", "EQ", 16384, 1, 1, "EXPLICIT", 1,
        -1, None, (16383,),
    ),
    V098CoreVectorCase(
        "eq_d31_tail_j1", "EQ", 31, 1, 1, "EXPLICIT", 1,
        7, None, (30,),
    ),
    V098CoreVectorCase(
        "eq_d32_lane31_j1", "EQ", 32, 1, 1, "EXPLICIT", 1,
        7, None, (31,),
    ),
    V098CoreVectorCase(
        "eq_d33_lane32_j1", "EQ", 33, 1, 1, "EXPLICIT", 1,
        7, None, (32,),
    ),
    V098CoreVectorCase(
        "gt_min_d33_m4_j2", "GT", 33, 4, 2, "EXPLICIT", 1,
        -32768, None, (0, 15, 31, 32),
    ),
    V098CoreVectorCase(
        "gt_max_m0_j1", "GT", 64, 0, 1, "HEAD", 1, 32767,
    ),
    V098CoreVectorCase(
        "lt_min_m0_j1", "LT", 64, 0, 1, "HEAD", 1, -32768,
    ),
    V098CoreVectorCase(
        "lt_max_d33_m4_j2", "LT", 33, 4, 2, "EXPLICIT", 1,
        32767, None, (0, 15, 31, 32),
    ),
    V098CoreVectorCase(
        "range_narrow_m2_j2", "RANGE", 64, 2, 2, "EXPLICIT", 1,
        -1, 1, (31, 32),
    ),
    V098CoreVectorCase(
        "range_wide_m4_j4", "RANGE", 16383, 4, 4, "EXPLICIT", 1,
        -32768, 32767, (0, 31, 32, 16382),
    ),
    V098CoreVectorCase(
        "eq_padding_poison_d33_j1", "EQ", 33, 1, 1, "EXPLICIT", 1,
        12345, None, (0,), 12345,
    ),
    V098CoreVectorCase(
        "eq_data_count1_m1_j1", "EQ", 1, 1, 1, "EXPLICIT", 1,
        12345, None, (0,),
    ),
    V098CoreVectorCase(
        "eq_mhalf_j1", "EQ", 16384, 8192, 1, "BANK_STRIDED", 1,
        None, None, None, None, "SUMMARY",
    ),
    V098CoreVectorCase(
        "eq_mall_j1", "EQ", 16384, 16384, 1, "HEAD", 1,
        None, None, None, None, "SUMMARY",
    ),
    V098CoreVectorCase(
        "eq_m1_j16", "EQ", 16384, 1, 16, "HEAD", 1,
        None, None, None, None, "SUMMARY",
    ),
    V098CoreVectorCase(
        "eq_m1_j64", "EQ", 16384, 1, 64, "HEAD", 1,
        None, None, None, None, "SUMMARY",
    ),
    V098CoreVectorCase(
        "eq_m1_j100_peak", "EQ", 16384, 1, 100, "HEAD", 1,
        None, None, None, None, "SUMMARY",
    ),
    V098CoreVectorCase(
        "eq_m1_j127_max", "EQ", 16384, 1, 127, "HEAD", 1,
        None, None, None, None, "SUMMARY",
    ),
)


def export_v098_core_vectors(
    output_dir: str | Path,
    *,
    cases: Sequence[V098CoreVectorCase] = DEFAULT_CORE_CASES,
) -> Path:
    root = Path(output_dir)
    root.mkdir(parents=True, exist_ok=True)
    manifest_cases: list[dict[str, Any]] = []

    for case in cases:
        dataset = build_controlled_v098_dataset(
            predicate_mode=case.predicate_mode,
            data_count=case.data_count,
            target_count=case.target_count,
            layout=case.layout,
            seed=case.seed,
            auto_shot=False,
            threshold_a=case.threshold_a,
            threshold_b=case.threshold_b,
            target_indices=case.target_indices,
        )
        if case.padding_poison_value is not None:
            poisoned = dataset.memory_image.copy()
            poisoned[case.data_count:] = np.int16(case.padding_poison_value)
            dataset = V098Dataset(
                memory_image=poisoned,
                valid_values=dataset.valid_values,
                target_mask=dataset.target_mask,
                target_indices=dataset.target_indices,
                config=dataset.config,
                layout=dataset.layout,
                seed=dataset.seed,
            )
        initial = rtl_initial_state(RTL_PROFILE_Q14)
        result = rtl_run_core(
            initial,
            dataset.target_mask,
            case.requested_j,
            trace_level=case.trace_level,
            profile=RTL_PROFILE_Q14,
        )
        case_dir = root / case.case_id
        case_dir.mkdir(parents=True, exist_ok=True)

        _write_signed_hex(case_dir / "data_signed16.hex", dataset.valid_values, 16)
        _write_signed_hex(case_dir / "data_memory_image.hex", dataset.memory_image, 16)
        _write_unsigned_hex(
            case_dir / "data_ahb_words.hex",
            pack_signed16_ahb_words(dataset.valid_values),
            32,
        )
        _write_mask_words(case_dir / "target_mask_p32.hex", dataset.target_mask)
        _write_signed_hex(
            case_dir / "initial_amp.hex", initial, V098_AMP_W
        )
        _write_signed_hex(
            case_dir / "expected_final_amp.hex",
            result.encoded_amplitudes,
            V098_AMP_W,
        )

        trace_rows: list[dict[str, Any]] = []
        for trace in result.trace:
            prefix = f"iter_{trace.iteration:03d}"
            if trace.amplitudes_after_oracle is not None:
                _write_signed_hex(
                    case_dir / f"{prefix}_after_oracle.hex",
                    trace.amplitudes_after_oracle,
                    V098_AMP_W,
                )
            if trace.amplitudes_after_diffusion is not None:
                _write_signed_hex(
                    case_dir / f"{prefix}_after_diffusion.hex",
                    trace.amplitudes_after_diffusion,
                    V098_AMP_W,
                )
            if trace.row_partial_sums is not None:
                _write_signed_hex(
                    case_dir / f"{prefix}_row_partial_sum.hex",
                    trace.row_partial_sums,
                    RTL_PROFILE_Q14.partial_sum_w,
                )
            trace_rows.append(
                {
                    "iteration": trace.iteration,
                    "global_sum": trace.global_sum,
                    "two_mean": trace.two_mean,
                    "saturation_count": trace.saturation_count,
                }
            )

        config_payload = {
            "contract_version": V098_VERSION,
            "case": asdict(case),
            "runtime_config": {
                "predicate_mode": dataset.config.predicate_mode,
                "threshold_a": dataset.config.threshold_a,
                "threshold_b": dataset.config.threshold_b,
                "data_count": dataset.config.data_count,
                "j_target": case.requested_j,
                "auto_shot": 0,
                "burst_enable": 0,
                "enum_enable": 0,
            },
            "profile": {
                "qubits": 14,
                "n": V098_N_ENTRIES,
                "parallelism": 32,
                "frac_bits": V098_FRAC_BITS,
                "amp_w": V098_AMP_W,
            },
        }
        expected_payload = {
            "scope": "MANUAL_CORE_BIT_EXACT",
            "target_count": dataset.target_count,
            "target_indices": list(dataset.target_indices),
            "requested_j": case.requested_j,
            "physical_iterations": result.physical_iterations,
            "saturation_count": result.saturation_count,
            "final_amp_sha256": _array_sha256(result.encoded_amplitudes),
            "trace": trace_rows,
            "excluded_from_claim": [
                "v0.9.8 autonomous J PRNG",
                "v0.9.8 measurement PRNG",
                "K4/H8 policy telemetry",
                "cycle_count",
            ],
        }
        _write_json(case_dir / "config.json", config_payload)
        _write_json(case_dir / "expected_core.json", expected_payload)
        manifest_cases.append(
            {
                **asdict(case),
                "target_indices": list(dataset.target_indices),
                "case_directory": case.case_id,
                "expected_final_amp_sha256": expected_payload["final_amp_sha256"],
            }
        )

    manifest = {
        "contract_version": V098_VERSION,
        "vector_scope": "Q14/P32/F22 manual Grover datapath",
        "case_count": len(manifest_cases),
        "cases": manifest_cases,
        "verified_components": [
            "signed16 dataset order and padding",
            "LT/GT/EQ/RANGE open-interval target mask",
            "Q1.22 fixed-point Oracle/mean/diffusion/saturation",
            "P32 target-mask and row mapping",
        ],
        "not_claimed_without_frozen_main_ip_source": [
            "v0.9.8 J/measurement random stream bit sequence",
            "K4/H8 restricted-B/Rolling-H8/Shadow-J decisions",
            "policy/plan telemetry and cycle_count",
        ],
    }
    manifest_path = root / "manifest.json"
    _write_json(manifest_path, manifest)
    return manifest_path


def _write_signed_hex(path: Path, values: np.ndarray | None, width: int) -> None:
    if values is None:
        raise ValueError(f"cannot write missing values to {path.name}")
    mask = (1 << width) - 1
    digits = (width + 3) // 4
    path.write_text(
        "".join(f"{int(value) & mask:0{digits}x}\n" for value in values),
        encoding="ascii",
    )


def _write_unsigned_hex(path: Path, values: np.ndarray, width: int) -> None:
    digits = (width + 3) // 4
    maximum = (1 << width) - 1
    path.write_text(
        "".join(f"{int(value) & maximum:0{digits}x}\n" for value in values),
        encoding="ascii",
    )


def _write_mask_words(path: Path, mask: np.ndarray) -> None:
    rows = np.asarray(mask, dtype=np.bool_).reshape(-1, 32)
    words = np.array(
        [sum((1 << lane) for lane, bit in enumerate(row) if bit) for row in rows],
        dtype=np.uint32,
    )
    _write_unsigned_hex(path, words, 32)


def _array_sha256(values: np.ndarray) -> str:
    return hashlib.sha256(np.asarray(values).astype("<i8", copy=False).tobytes()).hexdigest()


def _write_json(path: Path, payload: Any) -> None:
    path.write_text(
        json.dumps(payload, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", nargs="?", default="rtl_vectors/v098_manual_core")
    args = parser.parse_args()
    print(export_v098_core_vectors(args.output))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
