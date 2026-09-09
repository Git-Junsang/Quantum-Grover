"""Export deterministic v0.9.8 automatic-core semantic reference cases.

The dataset, Oracle, Q1.22 datapath, BBHT m sequence, logical budget, and J
step-7 stream follow the frozen handoff.  Measurement seed expansion and the
restricted-B bridge-level checkpoint planner remain explicitly provisional until
the frozen Main-IP equations/source are supplied.  These artifacts are useful
for control-flow review and invariant checking; they must not be advertised as
final RTL bit-exact automatic-output vectors.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any, Sequence

import numpy as np

from rtl_v098_auto import (
    AUTO_COMPATIBILITY,
    CHECKPOINT_ASSUMPTION,
    MEASUREMENT_ASSUMPTION,
    V098AutomaticCore,
    V098JRandomSource,
)
from rtl_v098_contract import V098RuntimeConfig, V098_VERSION, pack_signed16_ahb_words
from rtl_v098_data import (
    V098Dataset,
    build_controlled_v098_dataset,
    build_official_board_benchmark_dataset,
)
from rtl_v098_semantics import (
    V098AttemptObservation,
    audit_bbht_attempts,
    audit_enumeration_fifo,
    audit_normal_ckpt_attempt_pair,
    v098_m_bounds,
)


@dataclass(frozen=True)
class V098AutoVectorCase:
    case_id: str
    predicate_mode: str
    data_count: int
    target_count: int
    layout: str = "HEAD"
    dataset_seed: int = 1
    seed_j: int = 0x10203040
    seed_meas: int = 0x12345078
    shot_cap: int = 100
    fail_repeat_limit: int = 4
    threshold_a: int | None = None
    threshold_b: int | None = None
    enumeration: bool = False
    max_results: int | None = None
    official_board_dataset: bool = False


DEFAULT_AUTO_CASES = (
    V098AutoVectorCase(
        "official_eq_m1", "EQ", 16384, 1, official_board_dataset=True
    ),
    V098AutoVectorCase(
        "official_eq_m4", "EQ", 16384, 4, official_board_dataset=True
    ),
    V098AutoVectorCase(
        "official_eq_m16", "EQ", 16384, 16, official_board_dataset=True
    ),
    V098AutoVectorCase(
        "official_eq_m64", "EQ", 16384, 64, official_board_dataset=True
    ),
    V098AutoVectorCase(
        "official_eq_m256", "EQ", 16384, 256, official_board_dataset=True
    ),
    V098AutoVectorCase("gt_pad50_m16", "GT", 8192, 16, "RANDOM", 11),
    V098AutoVectorCase("lt_odd_m64", "LT", 4097, 64, "BANK_STRIDED", 12),
    V098AutoVectorCase(
        "range_pad75_m256", "RANGE", 12288, 256, "RANDOM", 13, 0x10203041,
        0x12345079, 100, 4, -100, 100
    ),
    V098AutoVectorCase(
        "gt_signed_max_m0_shot4", "GT", 33, 0, "HEAD", 1, 0x10203042,
        0x1234507A, 4, 2, 32767
    ),
    V098AutoVectorCase(
        "eq_enum_m4", "EQ", 16384, 4, "BANK_STRIDED", 21, 0x10203043,
        0x1234507B, 100, 2, None, None, True, 4
    ),
    V098AutoVectorCase(
        "range_enum_m8_first4", "RANGE", 8192, 8, "RANDOM", 22,
        0x10203044, 0x1234507C, 100, 2, -10, 10, True, 4
    ),
)


def export_v098_auto_vectors(
    output_dir: str | Path,
    *,
    cases: Sequence[V098AutoVectorCase] = DEFAULT_AUTO_CASES,
) -> Path:
    root = Path(output_dir)
    root.mkdir(parents=True, exist_ok=True)
    manifest_cases: list[dict[str, Any]] = []

    for case in cases:
        dataset = _build_dataset(case)
        normal_cfg = _runtime_config(case, dataset, burst=False)
        k4_cfg = _runtime_config(case, dataset, burst=True)
        normal_core = V098AutomaticCore(dataset, normal_cfg)
        k4_core = V098AutomaticCore(dataset, k4_cfg)
        if case.enumeration:
            normal = normal_core.run_enumeration(
                mode="NORMAL", max_results=case.max_results
            )
            k4 = k4_core.run_enumeration(
                mode="CKPT", max_results=case.max_results
            )
        else:
            normal = normal_core.run_single(mode="NORMAL")
            k4 = k4_core.run_single(mode="CKPT")

        pair = audit_normal_ckpt_attempt_pair(
            _observations(normal.attempts), _observations(k4.attempts)
        )
        if not pair.passed:
            raise RuntimeError(f"{case.case_id}: Normal/K4 invariant failure {pair}")

        case_dir = root / case.case_id
        case_dir.mkdir(parents=True, exist_ok=True)
        _write_signed_hex(case_dir / "data_signed16.hex", dataset.valid_values, 16)
        _write_signed_hex(case_dir / "data_memory_image.hex", dataset.memory_image, 16)
        _write_unsigned_hex(
            case_dir / "data_ahb_words.hex",
            pack_signed16_ahb_words(dataset.valid_values),
            32,
        )
        _write_mask_words(case_dir / "initial_target_mask_p32.hex", dataset.target_mask)
        _write_json(
            case_dir / "expected_j_scheduler_first100.json",
            {
                "scope": "FROZEN_BIT_EXACT_J_STEP7",
                "seed_j": case.seed_j,
                "draws": _j_schedule_preview(case.seed_j, 100),
            },
        )
        _write_json(
            case_dir / "config.json",
            {
                "contract_version": V098_VERSION,
                "case": asdict(case),
                "normal_runtime": normal_cfg.csr_write_values(),
                "ckpt_runtime": k4_cfg.csr_write_values(),
                "target_indices": list(dataset.target_indices),
                "target_count": dataset.target_count,
            },
        )
        _write_json(
            case_dir / "expected_normal_semantic.json",
            {
                "scope": AUTO_COMPATIBILITY,
                "measurement_status": "PROVISIONAL_SEED_EXPANSION",
                "result": normal.to_dict(),
            },
        )
        _write_json(
            case_dir / "expected_ckpt_semantic.json",
            {
                "scope": AUTO_COMPATIBILITY,
                "measurement_status": "PROVISIONAL_SEED_EXPANSION",
                "checkpoint_status": "PROVISIONAL_ENDPOINT_REFERENCE",
                "result": k4.to_dict(),
            },
        )

        audits: dict[str, Any] = {"normal_ckpt_pair": asdict(pair)}
        if case.enumeration:
            audits["normal_enumeration"] = audit_enumeration_fifo(
                dataset.target_mask,
                normal.fifo_indices,
                reported_found_count=normal.found_count,
            ).to_dict()
            audits["ckpt_enumeration"] = audit_enumeration_fifo(
                dataset.target_mask,
                k4.fifo_indices,
                reported_found_count=k4.found_count,
            ).to_dict()
        else:
            audits["normal_bbht"] = audit_bbht_attempts(
                _observations(normal.attempts), dataset.target_mask,
                shot_cap=case.shot_cap,
            ).to_dict()
            audits["ckpt_bbht"] = audit_bbht_attempts(
                _observations(k4.attempts), dataset.target_mask,
                shot_cap=case.shot_cap,
            ).to_dict()
        _write_json(case_dir / "semantic_audit.json", audits)

        manifest_cases.append(
            {
                **asdict(case),
                "case_directory": case.case_id,
                "target_indices_sha256": hashlib.sha256(
                    np.asarray(dataset.target_indices, dtype="<u2").tobytes()
                ).hexdigest(),
                "normal_trial_count": normal.trial_count,
                "normal_L_BBHT": normal.L_BBHT,
                "normal_actual_iterations": normal.actual_grover_iterations,
                "ckpt_actual_iterations": k4.actual_grover_iterations,
                "pair_audit_pass": pair.passed,
            }
        )

    manifest = {
        "contract_version": V098_VERSION,
        "vector_scope": AUTO_COMPATIBILITY,
        "case_count": len(manifest_cases),
        "cases": manifest_cases,
        "frozen_exact_components": [
            "dataset and signed16 DMA image",
            "LT/GT/EQ/RANGE and DATA_COUNT/found-mask Oracle",
            "Q14/P32/Q1.22 manual requested-j datapath",
            "BBHT m0=1, lambda=6/5, m_max=128 and budget 576",
            "J LFSR feedback, pre-state draw, and ordinary step^7",
            "logical-vs-physical counter definitions",
            "Enumeration unique-target and Oracle-epoch invalidation",
        ],
        "provisional_components": [
            MEASUREMENT_ASSUMPTION,
            CHECKPOINT_ASSUMPTION,
        ],
        "rtl_bit_exact_use": (
            "Do not use automatic result_index/K4 physical counts as final RTL "
            "answers until the two provisional equations are replaced."
        ),
    }
    path = root / "manifest.json"
    _write_json(path, manifest)
    return path


def _build_dataset(case: V098AutoVectorCase) -> V098Dataset:
    if case.official_board_dataset:
        if case.predicate_mode != "EQ" or case.data_count != 16384:
            raise ValueError("official board dataset requires EQ and DATA_COUNT=16384")
        return build_official_board_benchmark_dataset(case.target_count)
    return build_controlled_v098_dataset(
        predicate_mode=case.predicate_mode,
        data_count=case.data_count,
        target_count=case.target_count,
        layout=case.layout,
        seed=case.dataset_seed,
        auto_shot=True,
        enum_enable=case.enumeration,
        fail_repeat_limit=case.fail_repeat_limit,
        threshold_a=case.threshold_a,
        threshold_b=case.threshold_b,
    )


def _runtime_config(
    case: V098AutoVectorCase, dataset: V098Dataset, *, burst: bool
) -> V098RuntimeConfig:
    return V098RuntimeConfig(
        predicate_mode=dataset.config.predicate_mode,
        threshold_a=dataset.config.threshold_a,
        threshold_b=dataset.config.threshold_b,
        data_count=dataset.config.data_count,
        auto_shot=True,
        burst_enable=burst,
        enum_enable=case.enumeration,
        fail_repeat_limit=case.fail_repeat_limit,
        shot_cap=case.shot_cap,
        seed_j=case.seed_j,
        seed_meas=case.seed_meas,
    )


def _observations(attempts: Sequence[Any]) -> list[V098AttemptObservation]:
    return [
        V098AttemptObservation(
            attempt=item.attempt,
            requested_j=item.requested_j,
            result_index=item.result_index,
            success=item.success,
            physical_iterations=item.physical_iterations,
        )
        for item in attempts
    ]


def _j_schedule_preview(seed: int, count: int) -> list[dict[str, Any]]:
    source = V098JRandomSource(seed)
    bounds = v098_m_bounds()
    result: list[dict[str, Any]] = []
    for round_index in range(count):
        bound = bounds[min(round_index, len(bounds) - 1)]
        requested_j, random_words = source.draw_uniform(bound)
        result.append(
            {
                "round_index": round_index,
                "m_bound": bound,
                "requested_j": requested_j,
                "random_words": list(random_words),
                "state_after_draw": source.state,
            }
        )
    return result


def _write_signed_hex(path: Path, values: np.ndarray, width: int) -> None:
    mask = (1 << width) - 1
    digits = (width + 3) // 4
    path.write_text(
        "".join(f"{int(value) & mask:0{digits}x}\n" for value in values),
        encoding="ascii",
    )


def _write_unsigned_hex(path: Path, values: np.ndarray, width: int) -> None:
    mask = (1 << width) - 1
    digits = (width + 3) // 4
    path.write_text(
        "".join(f"{int(value) & mask:0{digits}x}\n" for value in values),
        encoding="ascii",
    )


def _write_mask_words(path: Path, mask: np.ndarray) -> None:
    rows = np.asarray(mask, dtype=np.bool_).reshape(-1, 32)
    words = np.asarray(
        [sum(1 << lane for lane, bit in enumerate(row) if bit) for row in rows],
        dtype=np.uint32,
    )
    _write_unsigned_hex(path, words, 32)


def _write_json(path: Path, payload: Any) -> None:
    path.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "output", nargs="?", default="rtl_vectors/v098_automatic_semantic"
    )
    args = parser.parse_args()
    print(export_v098_auto_vectors(args.output))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
