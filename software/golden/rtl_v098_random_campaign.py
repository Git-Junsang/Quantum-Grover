"""Reproducible constrained-random verification for the v0.9.8 golden model.

The campaign keeps the 28 directed manual cases as permanent regression
anchors, then generates deterministic random combinations.  It stores compact
metadata and hashes for every case, full traces only for failures, and a small
materialized RTL sample.  Runs are append-only and resumable.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from dataclasses import asdict, dataclass, replace
from pathlib import Path
from time import perf_counter
from typing import Any, Iterable, Sequence

import numpy as np

from rtl_v07g import RTL_PROFILE_Q14, rtl_initial_state, rtl_run_core
from rtl_v098_auto import V098AutomaticCore
from rtl_v098_contract import V098_N_ENTRIES, V098RuntimeConfig
from rtl_v098_data import V098Dataset, build_controlled_v098_dataset
from rtl_v098_semantics import (
    V098AttemptObservation,
    audit_enumeration_fifo,
    audit_normal_ckpt_attempt_pair,
)
from rtl_v098_vectors import (
    DEFAULT_CORE_CASES,
    V098CoreVectorCase,
    export_v098_core_vectors,
)


PRESETS = {
    "SMOKE": dict(manual_cases=32, auto_cases=8, enumeration_cases=2, export_cases=4),
    "QUICK": dict(manual_cases=256, auto_cases=32, enumeration_cases=8, export_cases=16),
    "NIGHTLY": dict(
        manual_cases=10_000,
        auto_cases=512,
        enumeration_cases=64,
        export_cases=64,
    ),
    "MILESTONE": dict(
        manual_cases=100_000,
        auto_cases=4_096,
        enumeration_cases=256,
        export_cases=128,
    ),
}

PREDICATES = ("LT", "GT", "EQ", "RANGE")
LAYOUTS = ("HEAD", "TAIL", "BANK_STRIDED", "RANDOM")
EDGE_DATA_COUNTS = (
    1,
    2,
    31,
    32,
    33,
    63,
    64,
    65,
    4096,
    4097,
    8192,
    12288,
    16383,
    16384,
)
EDGE_J = (0, 1, 2, 3, 4, 7, 8, 15, 16, 31, 32, 63, 64, 99, 100, 126, 127)
EDGE_SIGNED = (-32768, -32767, -1, 0, 1, 32766, 32767)


@dataclass(frozen=True)
class V098RandomCampaignConfig:
    manual_cases: int = 256
    auto_cases: int = 32
    enumeration_cases: int = 8
    export_cases: int = 16
    root_seed: int = 0xC0DEC0DE
    auto_shot_cap: int = 32
    fail_repeat_limit: int = 2

    def __post_init__(self) -> None:
        if self.manual_cases < len(DEFAULT_CORE_CASES):
            raise ValueError(
                f"manual_cases must be at least {len(DEFAULT_CORE_CASES)}"
            )
        if not 0 <= self.auto_cases <= self.manual_cases:
            raise ValueError("auto_cases must be between 0 and manual_cases")
        if not 0 <= self.enumeration_cases <= self.auto_cases:
            raise ValueError("enumeration_cases must be between 0 and auto_cases")
        if not 0 <= self.export_cases <= self.manual_cases:
            raise ValueError("export_cases must be between 0 and manual_cases")
        if not 1 <= self.auto_shot_cap <= 0xFFFF:
            raise ValueError("auto_shot_cap must fit SHOT_CAP")
        if not 1 <= self.fail_repeat_limit <= 15:
            raise ValueError("fail_repeat_limit must be between 1 and 15")
        if not 0 <= self.root_seed <= 0xFFFFFFFFFFFFFFFF:
            raise ValueError("root_seed must fit unsigned 64-bit")

    @classmethod
    def from_preset(
        cls, preset: str = "QUICK", **overrides: Any
    ) -> "V098RandomCampaignConfig":
        normalized = preset.upper()
        if normalized not in PRESETS:
            raise ValueError(f"preset must be one of {sorted(PRESETS)}")
        values = dict(PRESETS[normalized])
        values.update(overrides)
        return cls(**values)


@dataclass(frozen=True)
class V098RandomCase:
    case_index: int
    case_id: str
    source: str
    predicate_mode: str
    data_count: int
    target_count: int
    requested_j: int
    layout: str
    dataset_seed: int
    seed_j: int
    seed_meas: int
    threshold_a: int | None = None
    threshold_b: int | None = None
    target_indices: tuple[int, ...] | None = None
    padding_mode: str = "SAFE"

    def to_dict(self) -> dict[str, Any]:
        payload = asdict(self)
        if self.target_indices is not None:
            payload["target_indices"] = list(self.target_indices)
        return payload

    @classmethod
    def from_dict(cls, payload: dict[str, Any]) -> "V098RandomCase":
        values = dict(payload)
        if values.get("target_indices") is not None:
            values["target_indices"] = tuple(values["target_indices"])
        return cls(**values)


def generate_v098_random_plan(
    cfg: V098RandomCampaignConfig,
) -> tuple[V098RandomCase, ...]:
    """Generate a stable case sequence; case i depends only on root_seed and i."""

    cases: list[V098RandomCase] = []
    for index, directed in enumerate(DEFAULT_CORE_CASES):
        if index >= cfg.manual_cases:
            break
        cases.append(_from_directed(index, directed, cfg.root_seed))
    # TAIL is a structural memory-layout axis. Keep it deterministic instead
    # of relying on a random draw to close the minimum coverage set.
    if len(cases) < cfg.manual_cases:
        index = len(cases)
        cases.append(_coverage_anchor(index, cfg.root_seed))
    for index in range(len(cases), cfg.manual_cases):
        rng = np.random.default_rng(_case_seed(cfg.root_seed, index))
        cases.append(_random_case(index, rng))
    return tuple(cases)


def run_v098_random_campaign(
    output_dir: str | Path,
    cfg: V098RandomCampaignConfig,
    *,
    resume: bool = False,
) -> Path:
    root = Path(output_dir)
    config_file = root / "campaign_config.json"
    plan_file = root / "cases.jsonl"
    manual_file = root / "manual_results.jsonl"
    auto_file = root / "auto_results.jsonl"
    if root.exists() and not resume:
        raise FileExistsError("output exists; use resume=True or a new directory")
    root.mkdir(parents=True, exist_ok=True)

    expected_config = asdict(cfg)
    if config_file.exists():
        actual_config = json.loads(config_file.read_text(encoding="utf-8"))
        if actual_config != expected_config:
            raise ValueError("resume configuration does not match existing campaign")
    else:
        _write_json(config_file, expected_config)

    plan = generate_v098_random_plan(cfg)
    if plan_file.exists():
        existing_plan = tuple(_read_cases(plan_file))
        if existing_plan != plan:
            raise ValueError("existing case plan does not match root_seed/config")
    else:
        _write_jsonl(plan_file, (case.to_dict() for case in plan))

    manual_done = _completed_indices(manual_file)
    with manual_file.open("a", encoding="utf-8", buffering=1) as stream:
        for case in plan:
            if case.case_index in manual_done:
                continue
            record = _run_manual_case(case)
            stream.write(json.dumps(record, ensure_ascii=False) + "\n")
            if not record["passed"]:
                _materialize_failure(root / "failures", case)

    auto_done = _completed_indices(auto_file)
    auto_plan = plan[: cfg.auto_cases]
    enum_eligible = [
        position
        for position, candidate in enumerate(auto_plan)
        if candidate.target_count > 0
    ]
    enum_indices = {
        enum_eligible[index]
        for index in _spread_indices(len(enum_eligible), cfg.enumeration_cases)
    }
    with auto_file.open("a", encoding="utf-8", buffering=1) as stream:
        for position, case in enumerate(auto_plan):
            if case.case_index in auto_done:
                continue
            record = _run_auto_case(
                case,
                cfg,
                enumeration=position in enum_indices,
            )
            stream.write(json.dumps(record, ensure_ascii=False) + "\n")
            if not record["passed"]:
                _materialize_failure(root / "failures", case)

    manual_records = list(_read_jsonl(manual_file))
    auto_records = list(_read_jsonl(auto_file))
    coverage = _coverage_report(plan, manual_records, auto_records, cfg)
    _write_json(root / "coverage.json", coverage)
    (root / "coverage.md").write_text(
        _render_coverage_markdown(coverage), encoding="utf-8"
    )

    if cfg.export_cases:
        sample_indices = _spread_indices(len(plan), cfg.export_cases)
        sample_cases = [plan[index] for index in sorted(sample_indices)]
        sample_root = root / "rtl_sample_vectors"
        if not sample_root.exists():
            materialize_v098_cases(sample_cases, sample_root)

    _write_json(
        root / "checkpoint.json",
        {
            "manual_completed": len(manual_records),
            "auto_completed": len(auto_records),
            "manual_failed": sum(not item["passed"] for item in manual_records),
            "auto_failed": sum(not item["passed"] for item in auto_records),
            "complete": (
                len(manual_records) == cfg.manual_cases
                and len(auto_records) == cfg.auto_cases
            ),
        },
    )
    return root / "coverage.md"


def materialize_v098_cases(
    cases: Sequence[V098RandomCase], output_dir: str | Path
) -> Path:
    vectors = tuple(_as_vector_case(case) for case in cases)
    return export_v098_core_vectors(output_dir, cases=vectors)


def materialize_v098_plan_indices(
    plan_file: str | Path,
    indices: Iterable[int],
    output_dir: str | Path,
) -> Path:
    plan = {case.case_index: case for case in _read_cases(Path(plan_file))}
    selected = []
    for index in indices:
        checked = int(index)
        if checked not in plan:
            raise ValueError(f"case index {checked} is not in the plan")
        selected.append(plan[checked])
    return materialize_v098_cases(selected, output_dir)


def _run_manual_case(case: V098RandomCase) -> dict[str, Any]:
    started = perf_counter()
    dataset = _build_case_dataset(case)
    result = rtl_run_core(
        rtl_initial_state(RTL_PROFILE_Q14),
        dataset.target_mask,
        case.requested_j,
        trace_level="SUMMARY",
        profile=RTL_PROFILE_Q14,
    )
    encoded = result.encoded_amplitudes
    target_values = encoded[dataset.target_mask]
    nontarget_values = encoded[~dataset.target_mask]
    target_uniform = target_values.size == 0 or np.unique(target_values).size == 1
    nontarget_uniform = (
        nontarget_values.size == 0 or np.unique(nontarget_values).size == 1
    )
    in_range = bool(
        np.all(encoded >= RTL_PROFILE_Q14.amp_min)
        and np.all(encoded <= RTL_PROFILE_Q14.amp_max)
    )
    squares = encoded * encoded
    total_weight = int(np.sum(squares, dtype=np.int64))
    target_weight = int(np.sum(squares[dataset.target_mask], dtype=np.int64))
    target_probability = target_weight / total_weight if total_weight else 0.0
    norm = total_weight / float(1 << (2 * RTL_PROFILE_Q14.frac_bits))
    tie_count = sum(
        trace.global_sum % (1 << (RTL_PROFILE_Q14.qubits - 1))
        == (1 << (RTL_PROFILE_Q14.qubits - 2))
        for trace in result.trace
    )
    passed = bool(
        dataset.target_count == case.target_count
        and target_uniform
        and nontarget_uniform
        and in_range
        and total_weight > 0
    )
    return {
        "case_index": case.case_index,
        "case_id": case.case_id,
        "passed": passed,
        "target_count": dataset.target_count,
        "requested_j": case.requested_j,
        "physical_iterations": result.physical_iterations,
        "saturation_count": result.saturation_count,
        "tie_to_even_input_count": tie_count,
        "target_uniform": bool(target_uniform),
        "nontarget_uniform": bool(nontarget_uniform),
        "amplitude_in_range": in_range,
        "target_probability": target_probability,
        "normalization_error": abs(norm - 1.0),
        "final_amp_sha256": _array_sha256(encoded),
        "elapsed_ms": (perf_counter() - started) * 1000.0,
    }


def _run_auto_case(
    case: V098RandomCase,
    campaign: V098RandomCampaignConfig,
    *,
    enumeration: bool,
) -> dict[str, Any]:
    started = perf_counter()
    dataset = _build_case_dataset(case)
    normal_cfg = _auto_runtime(case, dataset, campaign, burst=False, enum=enumeration)
    k4_cfg = _auto_runtime(case, dataset, campaign, burst=True, enum=enumeration)
    normal_core = V098AutomaticCore(dataset, normal_cfg)
    k4_core = V098AutomaticCore(dataset, k4_cfg)
    if enumeration and case.target_count > 0:
        requested = min(case.target_count, 4)
        normal = normal_core.run_enumeration(mode="NORMAL", max_results=requested)
        k4 = k4_core.run_enumeration(mode="CKPT", max_results=requested)
        normal_enum = audit_enumeration_fifo(
            dataset.target_mask,
            normal.fifo_indices,
            reported_found_count=normal.found_count,
        )
        k4_enum = audit_enumeration_fifo(
            dataset.target_mask,
            k4.fifo_indices,
            reported_found_count=k4.found_count,
        )
        enum_pass = normal_enum.passed and k4_enum.passed
    else:
        enumeration = False
        normal = normal_core.run_single(mode="NORMAL")
        k4 = k4_core.run_single(mode="CKPT")
        enum_pass = True
    pair = audit_normal_ckpt_attempt_pair(
        _observations(normal.attempts), _observations(k4.attempts)
    )
    passed = bool(pair.passed and enum_pass)
    return {
        "case_index": case.case_index,
        "case_id": case.case_id,
        "passed": passed,
        "enumeration": enumeration,
        "normal_k4_pair_audit": asdict(pair),
        "normal": normal.to_dict(),
        "ckpt": k4.to_dict(),
        "elapsed_ms": (perf_counter() - started) * 1000.0,
        "exactness": {
            "j_scheduler": "FROZEN_BIT_EXACT",
            "measurement": "PROVISIONAL_SEED_EXPANSION",
            "k4_policy": "PROVISIONAL_ENDPOINT_REFERENCE",
        },
    }


def _from_directed(
    index: int, case: V098CoreVectorCase, root_seed: int
) -> V098RandomCase:
    padding_mode = "POISON_TARGET" if case.padding_poison_value is not None else "SAFE"
    return V098RandomCase(
        case_index=index,
        case_id=f"dir_{index:06d}_{case.case_id}",
        source="DIRECTED",
        predicate_mode=case.predicate_mode,
        data_count=case.data_count,
        target_count=case.target_count,
        requested_j=case.requested_j,
        layout=case.layout,
        dataset_seed=case.seed,
        seed_j=_u32(_case_seed(root_seed ^ 0x4A4A, index)),
        seed_meas=_u32(_case_seed(root_seed ^ 0x5A5A, index)),
        threshold_a=case.threshold_a,
        threshold_b=case.threshold_b,
        target_indices=case.target_indices,
        padding_mode=padding_mode,
    )


def _coverage_anchor(index: int, root_seed: int) -> V098RandomCase:
    return V098RandomCase(
        case_index=index,
        case_id=f"anchor_{index:06d}_tail_dense",
        source="COVERAGE_ANCHOR",
        predicate_mode="EQ",
        data_count=64,
        target_count=63,
        requested_j=32,
        layout="TAIL",
        dataset_seed=_u32(_case_seed(root_seed ^ 0xA11CE, index)),
        seed_j=_u32(_case_seed(root_seed ^ 0x4A4A, index)),
        seed_meas=_u32(_case_seed(root_seed ^ 0x5A5A, index)),
        threshold_a=0,
        threshold_b=None,
        padding_mode="POISON_TARGET",
    )


def _random_case(index: int, rng: np.random.Generator) -> V098RandomCase:
    data_count = (
        int(rng.choice(EDGE_DATA_COUNTS))
        if rng.random() < 0.55
        else int(rng.integers(1, V098_N_ENTRIES + 1))
    )
    target_count = _choose_target_count(rng, data_count)
    predicate = str(rng.choice(PREDICATES))
    threshold_a, threshold_b = _choose_thresholds(rng, predicate, target_count)
    requested_j = (
        int(rng.choice(EDGE_J)) if rng.random() < 0.65 else int(rng.integers(0, 128))
    )
    layout = str(rng.choice(LAYOUTS))
    padding_mode = (
        "POISON_TARGET"
        if data_count < V098_N_ENTRIES and rng.random() < 0.5
        else "SAFE"
    )
    return V098RandomCase(
        case_index=index,
        case_id=f"rnd_{index:06d}",
        source="RANDOM",
        predicate_mode=predicate,
        data_count=data_count,
        target_count=target_count,
        requested_j=requested_j,
        layout=layout,
        dataset_seed=int(rng.integers(0, 1 << 32, dtype=np.uint64)),
        seed_j=int(rng.integers(0, 1 << 32, dtype=np.uint64)),
        seed_meas=int(rng.integers(0, 1 << 32, dtype=np.uint64)),
        threshold_a=threshold_a,
        threshold_b=threshold_b,
        padding_mode=padding_mode,
    )


def _choose_target_count(rng: np.random.Generator, data_count: int) -> int:
    candidates = {
        0,
        1,
        2,
        4,
        8,
        16,
        64,
        256,
        data_count // 100,
        data_count // 4,
        data_count // 2,
        (3 * data_count) // 4,
        max(data_count - 1, 0),
        data_count,
    }
    valid = sorted(value for value in candidates if 0 <= value <= data_count)
    if rng.random() < 0.8:
        return int(rng.choice(valid))
    return int(rng.integers(0, data_count + 1))


def _choose_thresholds(
    rng: np.random.Generator, predicate: str, target_count: int
) -> tuple[int | None, int | None]:
    if predicate == "RANGE":
        if rng.random() < 0.5:
            a, b = (
                (-32768, -32766),
                (-1, 1),
                (0, 2),
                (32765, 32767),
                (-32768, 32767),
            )[int(rng.integers(0, 5))]
        else:
            a = int(rng.integers(-32768, 32766))
            b = int(rng.integers(a + 2, 32768))
        return a, b
    if rng.random() < 0.55:
        value = int(rng.choice(EDGE_SIGNED))
    else:
        value = int(rng.integers(-32768, 32768))
    if target_count > 0 and predicate == "GT" and value == 32767:
        value = 32766
    if target_count > 0 and predicate == "LT" and value == -32768:
        value = -32767
    return value, None


def _build_case_dataset(case: V098RandomCase) -> V098Dataset:
    dataset = build_controlled_v098_dataset(
        predicate_mode=case.predicate_mode,
        data_count=case.data_count,
        target_count=case.target_count,
        layout=case.layout,
        seed=case.dataset_seed,
        auto_shot=True,
        threshold_a=case.threshold_a,
        threshold_b=case.threshold_b,
        target_indices=case.target_indices,
    )
    if case.padding_mode == "POISON_TARGET" and case.data_count < V098_N_ENTRIES:
        image = dataset.memory_image.copy()
        image[case.data_count :] = np.int16(_target_value(dataset.config))
        dataset = replace(dataset, memory_image=image)
    return dataset


def _auto_runtime(
    case: V098RandomCase,
    dataset: V098Dataset,
    campaign: V098RandomCampaignConfig,
    *,
    burst: bool,
    enum: bool,
) -> V098RuntimeConfig:
    return V098RuntimeConfig(
        predicate_mode=dataset.config.predicate_mode,
        threshold_a=dataset.config.threshold_a,
        threshold_b=dataset.config.threshold_b,
        data_count=dataset.config.data_count,
        auto_shot=True,
        burst_enable=burst,
        enum_enable=enum,
        fail_repeat_limit=campaign.fail_repeat_limit,
        shot_cap=campaign.auto_shot_cap,
        seed_j=case.seed_j,
        seed_meas=case.seed_meas,
    )


def _target_value(cfg: V098RuntimeConfig) -> int:
    if cfg.predicate_mode == "EQ":
        return cfg.threshold_a
    if cfg.predicate_mode == "GT":
        return min(cfg.threshold_a + 1, 32767)
    if cfg.predicate_mode == "LT":
        return max(cfg.threshold_a - 1, -32768)
    return cfg.threshold_a + 1


def _as_vector_case(case: V098RandomCase) -> V098CoreVectorCase:
    return V098CoreVectorCase(
        case_id=case.case_id,
        predicate_mode=case.predicate_mode,
        data_count=case.data_count,
        target_count=case.target_count,
        requested_j=case.requested_j,
        layout=case.layout,
        seed=case.dataset_seed,
        threshold_a=case.threshold_a,
        threshold_b=case.threshold_b,
        target_indices=case.target_indices,
        padding_poison_value=(
            _target_value(
                V098RuntimeConfig(
                    predicate_mode=case.predicate_mode,
                    threshold_a=(case.threshold_a if case.threshold_a is not None else (12345 if case.predicate_mode == "EQ" else (-1 if case.predicate_mode == "RANGE" else 0))),
                    threshold_b=(case.threshold_b if case.threshold_b is not None else (1 if case.predicate_mode == "RANGE" else 0)),
                    data_count=case.data_count,
                )
            )
            if case.padding_mode == "POISON_TARGET"
            else None
        ),
        # Full traces are permanent directed regression evidence. Random
        # vectors retain their input and final answer without duplicating
        # hundreds of large intermediate state arrays.
        trace_level=(
            "FULL"
            if case.source == "DIRECTED" and case.requested_j <= 8
            else "SUMMARY"
        ),
    )


def _coverage_report(
    plan: Sequence[V098RandomCase],
    manual: Sequence[dict[str, Any]],
    auto: Sequence[dict[str, Any]],
    cfg: V098RandomCampaignConfig,
) -> dict[str, Any]:
    bins: dict[str, dict[str, int]] = {
        "predicate": {},
        "data_count": {},
        "target_density": {},
        "requested_j": {},
        "layout": {},
        "padding": {},
        "threshold": {},
        "saturation": {},
        "ties_to_even": {},
        "auto_mode": {},
    }
    manual_by_index = {int(item["case_index"]): item for item in manual}
    for case in plan:
        _increment(bins["predicate"], case.predicate_mode)
        _increment(bins["data_count"], _data_count_bin(case.data_count))
        _increment(
            bins["target_density"],
            _target_density_bin(case.target_count, case.data_count),
        )
        _increment(bins["requested_j"], _j_bin(case.requested_j))
        _increment(bins["layout"], case.layout)
        _increment(
            bins["padding"],
            "NONE" if case.data_count == V098_N_ENTRIES else case.padding_mode,
        )
        _increment(bins["threshold"], _threshold_bin(case))
        record = manual_by_index.get(case.case_index)
        if record is not None:
            if "saturation_count" in record:
                _increment(
                    bins["saturation"],
                    "YES" if record["saturation_count"] else "NO",
                )
            if "tie_to_even_input_count" in record:
                _increment(
                    bins["ties_to_even"],
                    "YES" if record["tie_to_even_input_count"] else "NO",
                )
    for item in auto:
        _increment(bins["auto_mode"], "ENUMERATION" if item["enumeration"] else "SINGLE")

    critical = {
        "predicate": set(PREDICATES),
        "target_density": {"ZERO", "ONE", "SPARSE", "LOW", "MID", "DENSE", "ALL"},
        "requested_j": {"ZERO", "1_7", "8_31", "32_63", "64_99", "100_127"},
        "layout": set(LAYOUTS) | {"EXPLICIT"},
        "padding": {"NONE", "SAFE", "POISON_TARGET"},
        "saturation": {"NO", "YES"},
        "ties_to_even": {"NO", "YES"},
    }
    missing = {
        category: sorted(expected - set(bins[category]))
        for category, expected in critical.items()
        if expected - set(bins[category])
    }
    return {
        "config": asdict(cfg),
        "manual": {
            "planned": len(plan),
            "completed": len(manual),
            "passed": sum(bool(item["passed"]) for item in manual),
            "failed": sum(not item["passed"] for item in manual),
            "mean_elapsed_ms": (
                sum(float(item["elapsed_ms"]) for item in manual) / len(manual)
                if manual else 0.0
            ),
        },
        "automatic": {
            "planned": cfg.auto_cases,
            "completed": len(auto),
            "passed": sum(bool(item["passed"]) for item in auto),
            "failed": sum(not item["passed"] for item in auto),
            "enumeration_completed": sum(bool(item["enumeration"]) for item in auto),
        },
        "coverage_bins": bins,
        "missing_critical_bins": missing,
        "coverage_closed": not missing,
        "exactness": {
            "manual_datapath": "BIT_EXACT_REFERENCE",
            "j_scheduler": "FROZEN_BIT_EXACT",
            "automatic_measurement": "PROVISIONAL_SEED_EXPANSION",
            "ckpt_policy": "PROVISIONAL_ENDPOINT_REFERENCE",
        },
    }


def _render_coverage_markdown(report: dict[str, Any]) -> str:
    manual = report["manual"]
    auto = report["automatic"]
    lines = [
        "# v0.9.8 Constrained-Random 검증 결과",
        "",
        "## 실행 요약",
        "",
        "| 구분 | 계획 | 완료 | PASS | FAIL |",
        "| --- | ---: | ---: | ---: | ---: |",
        f"| 수동 bit-exact 코어 | {manual['planned']} | {manual['completed']} | {manual['passed']} | {manual['failed']} |",
        f"| 자동 의미 참조 | {auto['planned']} | {auto['completed']} | {auto['passed']} | {auto['failed']} |",
        "",
        f"- 수동 케이스 평균 Python 실행시간: `{manual['mean_elapsed_ms']:.3f} ms`",
        f"- Enumeration 자동 케이스: `{auto['enumeration_completed']}`",
        f"- 핵심 coverage closure: `{'PASS' if report['coverage_closed'] else 'OPEN'}`",
        "",
        "## Coverage bins",
        "",
    ]
    for category, values in report["coverage_bins"].items():
        lines += [f"### {category}", "", "| Bin | Count |", "| --- | ---: |"]
        for name, count in sorted(values.items()):
            lines.append(f"| `{name}` | {count} |")
        lines.append("")
    lines += ["## 미충족 핵심 bin", ""]
    if report["missing_critical_bins"]:
        for category, values in report["missing_critical_bins"].items():
            lines.append(f"- `{category}`: {', '.join(values)}")
    else:
        lines.append("- 없음")
    lines += [
        "",
        "## 해석 경계",
        "",
        "수동 진폭 결과와 J step-7 scheduler는 RTL bit-exact 기준이다. 자동 측정 결과와 체크포인트 physical work는 최종 Main-IP의 measurement seed 확장식 및 restricted-B planner 소스가 제공되기 전까지 의미 참조 결과다.",
        "",
    ]
    return "\n".join(lines)


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


def _materialize_failure(root: Path, case: V098RandomCase) -> None:
    destination = root / case.case_id
    if destination.exists():
        return
    materialize_v098_cases((case,), destination)


def _read_cases(path: Path) -> Iterable[V098RandomCase]:
    for payload in _read_jsonl(path):
        yield V098RandomCase.from_dict(payload)


def _read_jsonl(path: Path) -> Iterable[dict[str, Any]]:
    if not path.exists():
        return
    for line in path.read_text(encoding="utf-8").splitlines():
        if line.strip():
            yield json.loads(line)


def _completed_indices(path: Path) -> set[int]:
    return {int(item["case_index"]) for item in _read_jsonl(path)}


def _write_json(path: Path, payload: Any) -> None:
    path.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


def _write_jsonl(path: Path, payloads: Iterable[dict[str, Any]]) -> None:
    with path.open("w", encoding="utf-8") as stream:
        for payload in payloads:
            stream.write(json.dumps(payload, ensure_ascii=False) + "\n")


def _case_seed(root_seed: int, index: int) -> int:
    value = (int(root_seed) + 0x9E3779B97F4A7C15 * (index + 1)) & 0xFFFFFFFFFFFFFFFF
    value ^= value >> 30
    value = (value * 0xBF58476D1CE4E5B9) & 0xFFFFFFFFFFFFFFFF
    value ^= value >> 27
    value = (value * 0x94D049BB133111EB) & 0xFFFFFFFFFFFFFFFF
    return value ^ (value >> 31)


def _u32(value: int) -> int:
    return int(value) & 0xFFFFFFFF


def _array_sha256(values: np.ndarray) -> str:
    return hashlib.sha256(
        np.asarray(values).astype("<i8", copy=False).tobytes()
    ).hexdigest()


def _spread_indices(length: int, count: int) -> set[int]:
    if count <= 0 or length <= 0:
        return set()
    if count >= length:
        return set(range(length))
    return {int(value) for value in np.linspace(0, length - 1, count, dtype=int)}


def _increment(table: dict[str, int], key: str) -> None:
    table[key] = table.get(key, 0) + 1


def _data_count_bin(value: int) -> str:
    if value in {1, 2, 31, 32, 33, 63, 64, 65, 16383, 16384}:
        return f"EDGE_{value}"
    ratio = value / V098_N_ENTRIES
    if ratio <= 0.25:
        return "RANDOM_0_25"
    if ratio <= 0.5:
        return "RANDOM_25_50"
    if ratio <= 0.75:
        return "RANDOM_50_75"
    return "RANDOM_75_100"


def _target_density_bin(target_count: int, data_count: int) -> str:
    if target_count == 0:
        return "ZERO"
    if target_count == 1:
        return "ONE"
    if target_count == data_count:
        return "ALL"
    ratio = target_count / data_count
    if ratio <= 0.01:
        return "SPARSE"
    if ratio <= 0.25:
        return "LOW"
    if ratio <= 0.75:
        return "MID"
    return "DENSE"


def _j_bin(value: int) -> str:
    if value == 0:
        return "ZERO"
    if value <= 7:
        return "1_7"
    if value <= 31:
        return "8_31"
    if value <= 63:
        return "32_63"
    if value <= 99:
        return "64_99"
    return "100_127"


def _threshold_bin(case: V098RandomCase) -> str:
    values = [value for value in (case.threshold_a, case.threshold_b) if value is not None]
    if -32768 in values:
        return "HAS_MIN"
    if 32767 in values:
        return "HAS_MAX"
    if 0 in values:
        return "HAS_ZERO"
    if not values:
        return "DEFAULT"
    return "OTHER"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    run = sub.add_parser("run")
    run.add_argument("output")
    run.add_argument("--preset", choices=sorted(PRESETS), default="QUICK")
    run.add_argument("--seed", type=lambda x: int(x, 0), default=0xC0DEC0DE)
    run.add_argument("--manual-cases", type=int)
    run.add_argument("--auto-cases", type=int)
    run.add_argument("--enumeration-cases", type=int)
    run.add_argument("--export-cases", type=int)
    run.add_argument("--resume", action="store_true")
    materialize = sub.add_parser("materialize")
    materialize.add_argument("plan")
    materialize.add_argument("output")
    materialize.add_argument("--indices", required=True)
    args = parser.parse_args()
    if args.command == "run":
        overrides = {"root_seed": args.seed}
        for field in (
            "manual_cases",
            "auto_cases",
            "enumeration_cases",
            "export_cases",
        ):
            value = getattr(args, field)
            if value is not None:
                overrides[field] = value
        cfg = V098RandomCampaignConfig.from_preset(
            args.preset, **overrides
        )
        print(run_v098_random_campaign(args.output, cfg, resume=args.resume))
    else:
        indices = [int(value.strip()) for value in args.indices.split(",")]
        print(materialize_v098_plan_indices(args.plan, indices, args.output))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
