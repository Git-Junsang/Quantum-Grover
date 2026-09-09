"""Evaluate current and projected BBHT amplitude-cache policies in software."""

from __future__ import annotations

import csv
import json
import statistics
from collections import OrderedDict
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable

from rtl_enum_campaign import build_enum_dataset
from rtl_v07g import (
    RTL_PROFILE_Q14,
    RTL_PROFILE_Q16,
    RtlHardwareProfile,
    RtlV07gConfig,
    RtlV07gModel,
)


@dataclass(frozen=True)
class CacheSimulation:
    capacity: int
    logical_iterations: int
    physical_iterations: int
    saved_iterations: int
    exact_hits: int
    resume_hits: int
    misses: int


def simulate_checkpoint_cache(j_sequence: Iterable[int], capacity: int) -> CacheSimulation:
    """Use the largest cached state not beyond requested j; update with LRU."""
    if capacity < 0:
        raise ValueError("capacity cannot be negative")
    cache: OrderedDict[int, None] = OrderedDict()
    logical = physical = exact = resume = misses = 0
    for requested_j in j_sequence:
        requested_j = int(requested_j)
        logical += requested_j
        eligible = [cached_j for cached_j in cache if cached_j <= requested_j]
        if not eligible:
            start_j = 0
            misses += 1
        else:
            start_j = max(eligible)
            if start_j == requested_j:
                exact += 1
            else:
                resume += 1
            cache.move_to_end(start_j)
        physical += requested_j - start_j
        if capacity:
            cache[requested_j] = None
            cache.move_to_end(requested_j)
            while len(cache) > capacity:
                cache.popitem(last=False)
    return CacheSimulation(
        capacity=capacity,
        logical_iterations=logical,
        physical_iterations=physical,
        saved_iterations=logical - physical,
        exact_hits=exact,
        resume_hits=resume,
        misses=misses,
    )


def run_cache_candidate_analysis(
    output_dir: str | Path,
    *,
    seeds: int = 30,
) -> dict[str, Any]:
    output = Path(output_dir)
    output.mkdir(parents=True, exist_ok=True)
    raw: list[dict[str, Any]] = []
    for profile in (RTL_PROFILE_Q14, RTL_PROFILE_Q16):
        for target_count in (1, 4, 64, profile.n // 2):
            values, threshold_a, threshold_b, _ = build_enum_dataset(
                active_n=profile.n,
                data_count=profile.n,
                target_count=target_count,
                oracle_mode="EQ",
                layout="HEAD",
                seed=1,
            )
            for seed_offset in range(seeds):
                cfg = RtlV07gConfig(
                    predicate_mode="EQ",
                    threshold_a=threshold_a,
                    threshold_b=threshold_b,
                    data_count=profile.n,
                    auto_shot=True,
                    burst_enable=False,
                    seed_j=(0x10203040 + seed_offset) & 0xFFFFFFFF,
                    seed_meas=(0x12345078 + 7919 * seed_offset) & 0xFFFFFFFF,
                    trace_level="NONE",
                    profile=profile,
                )
                normal_model = RtlV07gModel(profile)
                normal_model.load_memory_image(values, data_count=profile.n)
                normal = normal_model.run(cfg)
                sequence = tuple(attempt.requested_j for attempt in normal.attempts)

                burst_model = RtlV07gModel(profile)
                burst_model.load_memory_image(values, data_count=profile.n)
                burst_cfg = RtlV07gConfig(**{
                    **cfg.__dict__, "burst_enable": True,
                })
                burst = burst_model.run(burst_cfg)
                for capacity in (0, 1, 2, 4):
                    simulated = simulate_checkpoint_cache(sequence, capacity)
                    row_weight_cycles_per_exact_hit = 2 * profile.rows + profile.parallelism
                    raw.append({
                        "profile": profile.name,
                        "qubits": profile.qubits,
                        "target_count": target_count,
                        "seed_index": seed_offset,
                        "success": normal.success,
                        "attempts": len(sequence),
                        "j_sequence": ",".join(map(str, sequence)),
                        "cache_entries": capacity,
                        "logical_iterations": simulated.logical_iterations,
                        "physical_iterations": simulated.physical_iterations,
                        "saved_iterations": simulated.saved_iterations,
                        "iteration_saving_rate": (
                            simulated.saved_iterations / simulated.logical_iterations
                            if simulated.logical_iterations else 0.0
                        ),
                        "exact_hits": simulated.exact_hits,
                        "resume_hits": simulated.resume_hits,
                        "misses": simulated.misses,
                        "projected_row_weight_cycles_saved": simulated.exact_hits * row_weight_cycles_per_exact_hit,
                        "actual_v07g_burst_physical_iterations": burst.actual_grover_iterations,
                        "capacity1_matches_v07g_burst": (
                            capacity != 1 or simulated.physical_iterations == burst.actual_grover_iterations
                        ),
                    })

    summary = _summarize(raw)
    _write_csv(output / "cache_raw.csv", raw)
    _write_csv(output / "cache_summary.csv", summary)
    payload = {
        "seed_count_per_condition": seeds,
        "raw_case_count": len(raw),
        "summary": summary,
        "notes": {
            "capacity_1": "Current amp_mem checkpoint policy, validated against the bit-exact v0.7g Burst model.",
            "capacity_2_4": "Software-only projected LRU checkpoint policies.",
            "row_weight": "Cycle saving is a lower-level estimate for exact-state hits, not synthesized timing.",
        },
    }
    (output / "cache_summary.json").write_text(
        json.dumps(payload, indent=2, ensure_ascii=False), encoding="utf-8"
    )
    (output / "Cache_Candidate_Analysis.md").write_text(
        _render_markdown(payload), encoding="utf-8"
    )
    _write_chart(output, summary)
    return payload


def _summarize(raw: list[dict[str, Any]]) -> list[dict[str, Any]]:
    keys = sorted({(r["profile"], r["target_count"], r["cache_entries"]) for r in raw})
    result = []
    for profile, target_count, capacity in keys:
        rows = [r for r in raw if (r["profile"], r["target_count"], r["cache_entries"]) == (profile, target_count, capacity)]
        result.append({
            "profile": profile,
            "target_count": target_count,
            "cache_entries": capacity,
            "trials": len(rows),
            "success_rate": statistics.fmean(float(r["success"]) for r in rows),
            "mean_attempts": statistics.fmean(r["attempts"] for r in rows),
            "mean_logical_iterations": statistics.fmean(r["logical_iterations"] for r in rows),
            "mean_physical_iterations": statistics.fmean(r["physical_iterations"] for r in rows),
            "mean_saved_iterations": statistics.fmean(r["saved_iterations"] for r in rows),
            "mean_iteration_saving_rate": statistics.fmean(r["iteration_saving_rate"] for r in rows),
            "mean_exact_hits": statistics.fmean(r["exact_hits"] for r in rows),
            "mean_resume_hits": statistics.fmean(r["resume_hits"] for r in rows),
            "capacity1_all_match_v07g": all(r["capacity1_matches_v07g_burst"] for r in rows),
        })
    return result


def _write_csv(path: Path, rows: list[dict[str, Any]]) -> None:
    with path.open("w", newline="", encoding="utf-8-sig") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
        writer.writeheader(); writer.writerows(rows)


def _write_chart(output: Path, rows: list[dict[str, Any]]) -> None:
    try:
        import matplotlib.pyplot as plt
    except ImportError:
        return
    fig, axes = plt.subplots(1, 2, figsize=(12, 4.5))
    for profile in sorted({r["profile"] for r in rows}):
        selected = [r for r in rows if r["profile"] == profile and r["target_count"] == 1]
        axes[0].plot([r["cache_entries"] for r in selected], [100*r["mean_iteration_saving_rate"] for r in selected], marker="o", label=profile)
    axes[0].set_title("Checkpoint saving rate, M=1")
    axes[0].set_xlabel("Cache entries"); axes[0].set_ylabel("Saved iterations (%)")
    axes[0].legend(); axes[0].grid(True, alpha=.3)
    q14 = [r for r in rows if r["profile"] == RTL_PROFILE_Q14.name and r["cache_entries"] in {1,2,4}]
    labels = sorted({r["target_count"] for r in q14})
    width = .24
    for offset, capacity in enumerate((1,2,4)):
        values = [next(r for r in q14 if r["target_count"] == m and r["cache_entries"] == capacity)["mean_iteration_saving_rate"]*100 for m in labels]
        axes[1].bar([i+(offset-1)*width for i in range(len(labels))], values, width=width, label=f"{capacity}-entry")
    axes[1].set_xticks(range(len(labels)), [str(x) for x in labels]); axes[1].set_xlabel("M")
    axes[1].set_ylabel("Saved iterations (%)"); axes[1].set_title("Q14 cache comparison"); axes[1].legend()
    fig.tight_layout(); fig.savefig(output / "cache_candidate_overview.png", dpi=180); plt.close(fig)


def _render_markdown(payload: dict[str, Any]) -> str:
    lines = [
        "# BBHT Cache Candidate Analysis", "",
        "> 1-entry는 현재 v0.7g Burst 동작과 교차검증했다. 2/4-entry 및 row-weight 수치는 v0.9 SW 추정이다.", "",
        "![Cache candidate overview](cache_candidate_overview.png)", "",
        "| Profile | M | Entries | Mean attempts | Mean physical iterations | Saving | v0.7g match |",
        "|---|---:|---:|---:|---:|---:|---|",
    ]
    for row in payload["summary"]:
        lines.append(f"| {row['profile']} | {row['target_count']} | {row['cache_entries']} | {row['mean_attempts']:.2f} | {row['mean_physical_iterations']:.2f} | {100*row['mean_iteration_saving_rate']:.2f}% | {row['capacity1_all_match_v07g'] if row['cache_entries']==1 else 'projected'} |")
    lines += ["", "## Meaning", "", "- Cache는 실패한 j를 금지하지 않는다. 동일한 표준 BBHT j 요청열을 유지하고 상태 계산만 재사용한다.", "- exact hit는 Grover iteration 0회로 같은 상태를 재사용한다.", "- 2/4-entry는 가까운 `j_cached <= j_requested` 상태에서 재개하는 후보 정책이다.", "- 알고리즘 출력 동등성은 같은 j와 측정 난수에서 확인하고, 최종 채택은 BRAM·timing 실측과 함께 결정한다.", ""]
    return "\n".join(lines)


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", nargs="?", default="results/cache_candidate_analysis")
    parser.add_argument("--seeds", type=int, default=30)
    args = parser.parse_args()
    print(json.dumps(run_cache_candidate_analysis(args.output, seeds=args.seeds), indent=2, ensure_ascii=False))
