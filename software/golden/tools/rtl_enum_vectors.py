from __future__ import annotations

import hashlib
import json
from dataclasses import asdict
from pathlib import Path
from typing import Any

import numpy as np

from rtl_enum_campaign import (
    ENUM_PROFILE_MAP,
    EnumerationCampaignCase,
    build_enum_dataset,
)
from rtl_v07g import RtlV07gConfig
from rtl_v07g_enum import RtlV07gEnumerationConfig, enumerate_rtl_v07g


ENUM_VECTOR_CASES = (
    ("q14_eq_m1", "Q14", 16384, 1, "EQ", "HEAD", 1),
    ("q14_range_m4_pad50", "Q14", 8192, 4, "RANGE", "RANDOM", 4),
    ("q14_gt_m8_pad75", "Q14", 12288, 8, "GT", "RANDOM", 4),
    ("q14_lt_m0", "Q14", 4096, 0, "LT", "HEAD", None),
    ("q16_eq_m2", "Q16", 65536, 2, "EQ", "RANDOM", 2),
)


def export_enumeration_vectors(output_dir: str | Path) -> Path:
    root = Path(output_dir)
    root.mkdir(parents=True, exist_ok=True)
    manifest_cases: list[dict[str, Any]] = []
    for backend in ("SOFTWARE_RELOAD", "PROJECTED_MASK_MEM"):
        for ordinal, item in enumerate(ENUM_VECTOR_CASES, start=1):
            name, profile_name, data_count, target_count, oracle, layout, requested = item
            profile = ENUM_PROFILE_MAP[profile_name]
            seed = ordinal
            values, threshold_a, threshold_b, expected_indices = build_enum_dataset(
                profile.n,
                data_count,
                target_count,
                oracle,
                layout,
                seed,
            )
            case = EnumerationCampaignCase(
                case_id=f"{backend}-{name}",
                profile_name=profile_name,
                data_count=data_count,
                target_count=target_count,
                oracle_mode=oracle,
                backend=backend,
                layout=layout,
                burst_enable=True,
                requested_count=requested,
            )
            case_dir = root / backend.lower() / name
            case_dir.mkdir(parents=True, exist_ok=True)
            _write_signed_hex(case_dir / "data.hex", values, 16)
            config = RtlV07gConfig(
                profile=profile,
                data_count=data_count,
                predicate_mode=oracle,
                threshold_a=threshold_a,
                threshold_b=threshold_b,
                auto_shot=False,
                burst_enable=True,
                seed_j=(0x10203040 + seed) & 0xFFFFFFFF,
                seed_meas=(0x12345078 + seed) & 0xFFFFFFFF,
                trace_level="SUMMARY",
            )
            result = enumerate_rtl_v07g(
                values,
                RtlV07gEnumerationConfig(
                    search=config,
                    requested_count=requested,
                    exclude_backend=backend,
                    record_masks=True,
                ),
            )
            round_files: list[dict[str, Any]] = []
            for round_record in result.rounds:
                before_name = f"round_{round_record.round_index:03d}_mask_before.hex"
                after_name = f"round_{round_record.round_index:03d}_mask_after.hex"
                assert round_record.found_mask_before is not None
                assert round_record.found_mask_after is not None
                _write_mask_words(case_dir / before_name, round_record.found_mask_before)
                _write_mask_words(case_dir / after_name, round_record.found_mask_after)
                round_files.append(
                    {
                        "round_index": round_record.round_index,
                        "mask_before": before_name,
                        "mask_after": after_name,
                        "found_index": round_record.found_index,
                        "remaining_before": round_record.remaining_target_count_before,
                        "remaining_after": round_record.remaining_target_count_after,
                    }
                )
            payload = {
                "model_variant": (
                    "RTL_V07G_FW_ENUM_SOFTWARE_RELOAD"
                    if backend == "SOFTWARE_RELOAD"
                    else "RTL_V09_PROJECTED_ENUM_MASK_MEM"
                ),
                "rtl_validation_status": (
                    "CURRENT_V07G_COMPATIBLE"
                    if backend == "SOFTWARE_RELOAD"
                    else "PROJECTED_NOT_RTL_VALIDATED"
                ),
                "case": asdict(case),
                "threshold_a": threshold_a,
                "threshold_b": threshold_b,
                "expected_target_indices": expected_indices.astype(int).tolist(),
                "round_files": round_files,
                "result": result.to_dict(include_masks=False, include_attempts=True),
            }
            expected_path = case_dir / "expected_result.json"
            expected_path.write_text(
                json.dumps(payload, indent=2, ensure_ascii=True) + "\n",
                encoding="utf-8",
            )
            config_path = case_dir / "config.json"
            config_path.write_text(
                json.dumps(
                    {
                        "profile": profile.name,
                        "qubits": profile.qubits,
                        "parallelism": profile.parallelism,
                        "data_w": profile.data_w,
                        "frac_bits": profile.frac_bits,
                        "amp_w": profile.amp_w,
                        "predicate_mode": oracle,
                        "threshold_a": threshold_a,
                        "threshold_b": threshold_b,
                        "data_count": data_count,
                        "seed_j": config.seed_j,
                        "seed_meas": config.seed_meas,
                        "exclude_backend": backend,
                    },
                    indent=2,
                    ensure_ascii=True,
                )
                + "\n",
                encoding="utf-8",
            )
            manifest_cases.append(
                {
                    "name": name,
                    "backend": backend,
                    "directory": case_dir.relative_to(root).as_posix(),
                    "config": config_path.relative_to(root).as_posix(),
                    "expected_result": expected_path.relative_to(root).as_posix(),
                    "data_sha256": hashlib.sha256(values.tobytes()).hexdigest(),
                }
            )
    manifest = {
        "package": "RTL_ENUMERATION_GOLDEN_VECTORS",
        "mask_word_mapping": "row=index>>5, bit=index&31, little lane order",
        "cases": manifest_cases,
    }
    manifest_path = root / "manifest.json"
    manifest_path.write_text(
        json.dumps(manifest, indent=2, ensure_ascii=True) + "\n",
        encoding="utf-8",
    )
    return manifest_path


def _write_signed_hex(path: Path, values: np.ndarray, width: int) -> None:
    digits = (width + 3) // 4
    mask = (1 << width) - 1
    path.write_text(
        "".join(f"{int(value) & mask:0{digits}X}\n" for value in values),
        encoding="ascii",
    )


def _write_mask_words(path: Path, mask: np.ndarray) -> None:
    checked = np.asarray(mask, dtype=np.bool_)
    if checked.ndim != 1 or checked.size % 32:
        raise ValueError("mask length must be divisible by 32")
    words = []
    for row in checked.reshape(-1, 32):
        value = sum((1 << lane) for lane, bit in enumerate(row) if bit)
        words.append(f"{value:08X}\n")
    path.write_text("".join(words), encoding="ascii")


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description="Export enumeration vectors")
    parser.add_argument("output_dir")
    args = parser.parse_args()
    print(export_enumeration_vectors(args.output_dir))
