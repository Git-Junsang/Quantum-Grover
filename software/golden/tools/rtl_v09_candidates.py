"""Software-only accuracy and scale estimates for v0.9 candidate profiles.

Nothing in this module claims synthesis results. It reuses the delivered RTL
integer equations while varying Q, P, and F, then labels resource/cycle numbers
as first-order estimates until Vivado replaces them.
"""

from __future__ import annotations

import csv
import json
import math
from dataclasses import asdict, dataclass
from pathlib import Path
from time import perf_counter
from typing import Any

import numpy as np

from metrics import assess_argmax_target, compare_amplitudes, fixed_probability_values
from rtl_v07g import _build_m_bounds, rtl_run_core
from search_modes import optimal_known_m_iterations


@dataclass(frozen=True)
class CandidateProfile:
    name: str
    qubits: int
    parallelism: int
    frac_bits: int
    data_w: int = 16

    def __post_init__(self) -> None:
        if self.qubits not in {14, 15, 16}:
            raise ValueError("candidate qubits must be 14, 15, or 16")
        if self.parallelism not in {32, 64}:
            raise ValueError("candidate parallelism must be 32 or 64")
        if self.parallelism & (self.parallelism - 1):
            raise ValueError("parallelism must be a power of two")
        if not 1 <= self.frac_bits <= 30:
            raise ValueError("frac_bits must be between 1 and 30")

    @property
    def amp_w(self) -> int: return self.frac_bits + 1
    @property
    def n(self) -> int: return 1 << self.qubits
    @property
    def logp(self) -> int: return self.parallelism.bit_length() - 1
    @property
    def rows(self) -> int: return self.n // self.parallelism
    @property
    def index_w(self) -> int: return self.qubits
    @property
    def partial_sum_w(self) -> int: return self.amp_w + self.logp
    @property
    def acc_w(self) -> int: return self.amp_w + self.qubits + 2
    @property
    def two_mean_w(self) -> int: return self.amp_w + 2
    @property
    def diff_w(self) -> int: return self.amp_w + 2
    @property
    def square_w(self) -> int: return 2 * self.amp_w
    @property
    def row_weight_w(self) -> int: return self.square_w + self.logp
    @property
    def total_weight_w(self) -> int: return self.square_w + self.qubits
    @property
    def j_w(self) -> int: return self.qubits // 2
    @property
    def m_bound_w(self) -> int: return self.j_w + 1
    @property
    def sqrt_n(self) -> int: return 1 << (self.qubits // 2)
    @property
    def initial_amp_raw(self) -> int:
        return int(round((1.0 / math.sqrt(self.n)) * (1 << self.frac_bits)))
    @property
    def amp_max(self) -> int: return (1 << (self.amp_w - 1)) - 1
    @property
    def amp_min(self) -> int: return -self.amp_max
    @property
    def bbht_budget(self) -> int: return (9 * self.sqrt_n) // 2
    @property
    def m_bounds(self) -> tuple[int, ...]: return _build_m_bounds(self.qubits)


def ideal_amplitudes(n: int, target_count: int, iterations: int) -> np.ndarray:
    if not 0 <= target_count <= n:
        raise ValueError("target_count must be between 0 and n")
    amplitudes = np.full(n, 1.0 / math.sqrt(n), dtype=np.float64)
    if target_count in {0, n}:
        return amplitudes
    theta = math.asin(math.sqrt(target_count / n))
    angle = (2 * iterations + 1) * theta
    amplitudes[:target_count] = math.sin(angle) / math.sqrt(target_count)
    amplitudes[target_count:] = math.cos(angle) / math.sqrt(n - target_count)
    return amplitudes


def run_precision_scale_analysis(output_dir: str | Path) -> dict[str, Any]:
    output = Path(output_dir)
    output.mkdir(parents=True, exist_ok=True)
    precision_rows: list[dict[str, Any]] = []
    scale_rows: list[dict[str, Any]] = []

    for qubits in (14, 15, 16):
        n = 1 << qubits
        target_counts = (1, 4, 64, n // 2)
        for frac_bits in (20, 21, 22, 24):
            profile = CandidateProfile(
                name=f"Q{qubits}_P32_F{frac_bits}",
                qubits=qubits,
                parallelism=32,
                frac_bits=frac_bits,
            )
            initial = np.full(n, profile.initial_amp_raw, dtype=np.int64)
            for target_count in target_counts:
                mask = np.zeros(n, dtype=np.bool_)
                mask[:target_count] = True
                iterations = optimal_known_m_iterations(n, target_count)
                started = perf_counter()
                fixed = rtl_run_core(
                    initial, mask, iterations, trace_level="NONE", profile=profile
                )
                elapsed = perf_counter() - started
                decoded = fixed.encoded_amplitudes.astype(np.float64) / (1 << frac_bits)
                reference = ideal_amplitudes(n, target_count, iterations)
                metrics = compare_amplitudes(
                    reference,
                    decoded,
                    mask,
                    candidate_probabilities_for_l2=fixed_probability_values(
                        fixed.encoded_amplitudes, frac_bits
                    ),
                    saturation_count=fixed.saturation_count,
                )
                argmax = assess_argmax_target(decoded, mask)
                precision_rows.append({
                    "profile": profile.name,
                    "qubits": qubits,
                    "n": n,
                    "parallelism": 32,
                    "frac_bits": frac_bits,
                    "amp_w": profile.amp_w,
                    "target_count": target_count,
                    "iterations": iterations,
                    "argmax_outcome": argmax.outcome,
                    "argmax_pass": argmax.target_dominant,
                    "amplitude_l2_error": metrics.l2_error,
                    "phase_aligned_l2_error": metrics.phase_aligned_l2_error,
                    "probability_l2_error": metrics.probability_distribution_l2_error,
                    "success_probability_error": metrics.success_probability_error,
                    "normalization_error": metrics.fixed_normalization_error,
                    "saturation_count": fixed.saturation_count,
                    "python_seconds": elapsed,
                })

    for qubits, parallelism in ((14, 32), (15, 32), (16, 32), (14, 64)):
        profile = CandidateProfile(
            name=f"Q{qubits}_P{parallelism}_F22",
            qubits=qubits,
            parallelism=parallelism,
            frac_bits=22,
        )
        amp_bits = profile.n * profile.amp_w
        data_bits = profile.n * profile.data_w
        scale_rows.append({
            "profile": profile.name,
            "status": "SOFTWARE_ESTIMATE_NOT_SYNTHESIS",
            "qubits": qubits,
            "n": profile.n,
            "parallelism": parallelism,
            "rows_per_pass": profile.rows,
            "amp_state_bytes": math.ceil(amp_bits / 8),
            "data_bytes": math.ceil(data_bits / 8),
            "amp_raw_bram36_lower_bound": math.ceil(amp_bits / 36864),
            "data_raw_bram36_lower_bound": math.ceil(data_bits / 36864),
            "grover_two_pass_min_cycles": 2 * profile.rows,
            "born_two_stage_min_cycles": 2 * profile.rows + parallelism,
            "p_lane_dsp_first_order": 2 * parallelism,
        })

    _write_csv(output / "precision_candidates.csv", precision_rows)
    _write_csv(output / "scale_candidates.csv", scale_rows)
    summary = _build_summary(precision_rows, scale_rows)
    (output / "candidate_summary.json").write_text(
        json.dumps(summary, indent=2, ensure_ascii=False), encoding="utf-8"
    )
    (output / "V09_Precision_Scale_Analysis.md").write_text(
        _render_markdown(summary, precision_rows, scale_rows), encoding="utf-8"
    )
    _write_charts(output, precision_rows, scale_rows)
    return summary


def _build_summary(
    precision_rows: list[dict[str, Any]], scale_rows: list[dict[str, Any]]
) -> dict[str, Any]:
    minima: list[dict[str, Any]] = []
    for qubits in (14, 15, 16):
        rows = [row for row in precision_rows if row["qubits"] == qubits]
        for threshold in (1e-3, 1e-5):
            passing = []
            for frac_bits in (20, 21, 22, 24):
                group = [row for row in rows if row["frac_bits"] == frac_bits]
                if group and all(row["probability_l2_error"] <= threshold for row in group):
                    passing.append(frac_bits)
            minima.append({
                "qubits": qubits,
                "probability_l2_threshold": threshold,
                "minimum_tested_frac_bits": min(passing) if passing else None,
            })
    return {
        "precision_cases": len(precision_rows),
        "scale_profiles": len(scale_rows),
        "tested_fraction_bits": [20, 21, 22, 24],
        "tested_target_counts": "1, 4, 64, N/2",
        "precision_minima": minima,
        "warning": "Scale/resource/cycle values are first-order software estimates, not Vivado measurements.",
    }


def _write_csv(path: Path, rows: list[dict[str, Any]]) -> None:
    with path.open("w", newline="", encoding="utf-8-sig") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def _write_charts(output: Path, precision_rows: list[dict[str, Any]], scale_rows: list[dict[str, Any]]) -> None:
    try:
        import matplotlib.pyplot as plt
    except ImportError:
        return
    fig, axes = plt.subplots(1, 3, figsize=(14, 4.5))
    for qubits in (14, 15, 16):
        rows = [r for r in precision_rows if r["qubits"] == qubits and r["target_count"] == 1]
        axes[0].semilogy([r["frac_bits"] for r in rows], [max(r["probability_l2_error"], 1e-18) for r in rows], marker="o", label=f"Q{qubits}")
        axes[1].semilogy([r["frac_bits"] for r in rows], [max(r["phase_aligned_l2_error"], 1e-18) for r in rows], marker="o", label=f"Q{qubits}")
    axes[0].set_title("Probability L2, M=1")
    axes[1].set_title("Phase-aligned amplitude L2, M=1")
    axes[0].set_xlabel("Fraction bits F"); axes[1].set_xlabel("Fraction bits F")
    axes[0].grid(True, alpha=.3); axes[1].grid(True, alpha=.3)
    axes[0].legend(); axes[1].legend()
    axes[2].bar([r["profile"] for r in scale_rows], [r["amp_state_bytes"] / 1024 for r in scale_rows])
    axes[2].set_title("Amplitude state raw size")
    axes[2].set_ylabel("KiB"); axes[2].tick_params(axis="x", rotation=30)
    fig.tight_layout()
    fig.savefig(output / "precision_scale_overview.png", dpi=180)
    plt.close(fig)


def _render_markdown(summary: dict[str, Any], precision_rows: list[dict[str, Any]], scale_rows: list[dict[str, Any]]) -> str:
    lines = [
        "# v0.9 Precision and Scale Candidate Analysis", "",
        "> `Q14/P32/F22`만 전달 RTL 기준선이다. 나머지는 동일 정수식으로 계산한 SW 후보이며 합성 결과가 아니다.", "",
        "## Coverage", "",
        f"- Precision cases: **{summary['precision_cases']}**",
        "- Q: `14, 15, 16`; F: `20, 21, 22, 24`; M: `1, 4, 64, N/2`",
        "- Scale profiles: `Q14/P32`, `Q15/P32`, `Q16/P32`, `Q14/P64`", "",
        "![Precision and scale overview](precision_scale_overview.png)", "",
        "## Precision thresholds", "",
        "| Q | Probability L2 threshold | Minimum tested F |", "|---:|---:|---:|",
    ]
    for row in summary["precision_minima"]:
        value = row["minimum_tested_frac_bits"]
        lines.append(f"| {row['qubits']} | {row['probability_l2_threshold']:.0e} | {value if value is not None else 'not met'} |")
    lines += ["", "## Scale estimates", "", "| Profile | N | P | Amp state | Rows/pass | Grover 2-pass minimum |", "|---|---:|---:|---:|---:|---:|"]
    for row in scale_rows:
        lines.append(f"| {row['profile']} | {row['n']:,} | {row['parallelism']} | {row['amp_state_bytes']/1024:.1f} KiB | {row['rows_per_pass']:,} | {row['grover_two_pass_min_cycles']:,} cycles |")
    lines += ["", "## Interpretation", "", "- 정확도 값은 RTL의 ties-to-even 평균 계산과 symmetric saturation을 재사용한다.", "- cycle은 파이프라인 stall, FSM overhead, BRAM latency를 제외한 하한이다.", "- BRAM은 raw bit capacity 하한이며 bank width/depth packing 손실을 포함하지 않는다.", "- 최종 채택은 Vivado synthesis/implementation의 자원, WNS/WHS, power 결과로 결정한다.", ""]
    return "\n".join(lines)


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", nargs="?", default="results/v09_candidate_analysis")
    args = parser.parse_args()
    print(json.dumps(run_precision_scale_analysis(args.output), indent=2, ensure_ascii=False))
