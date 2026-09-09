from __future__ import annotations

from typing import Any

import numpy as np

from config import TRACE_LEVELS
from models import FullIterationTrace, IterationSummary


class TraceRecorder:
    """Records no trace, numerical summaries, or complete amplitude snapshots."""

    def __init__(self, trace_level: str = "SUMMARY") -> None:
        normalized_level = trace_level.upper()
        if normalized_level not in TRACE_LEVELS:
            raise ValueError(f"trace_level must be one of {sorted(TRACE_LEVELS)}")

        self.trace_level = normalized_level
        self.summaries: list[IterationSummary] = []
        self.full_records: list[FullIterationTrace] = []
        self._next_iteration = 1

    def record(
        self,
        *,
        iteration: int,
        amplitudes_before: np.ndarray,
        amplitudes_after_oracle: np.ndarray,
        amplitudes_after_diffusion: np.ndarray,
        target_mask: np.ndarray,
        overflow_count: int = 0,
        saturation_count: int = 0,
    ) -> IterationSummary | None:
        if iteration != self._next_iteration:
            raise ValueError(
                f"iteration must be recorded in order; expected {self._next_iteration}"
            )

        before, after_oracle, after_diffusion, mask = self._validate_arrays(
            amplitudes_before,
            amplitudes_after_oracle,
            amplitudes_after_diffusion,
            target_mask,
        )
        self._next_iteration += 1

        if self.trace_level == "NONE":
            return None

        target_amplitudes = after_diffusion[mask]
        nontarget_amplitudes = after_diffusion[~mask]

        target_min, target_max = self._range_or_none(target_amplitudes)
        nontarget_min, nontarget_max = self._range_or_none(nontarget_amplitudes)

        oracle_sum = float(np.sum(after_oracle, dtype=np.float64))
        oracle_mean = oracle_sum / after_oracle.size
        squared = np.square(after_diffusion, dtype=np.float64)
        norm = float(np.sum(squared, dtype=np.float64))
        target_weight = float(np.sum(squared[mask], dtype=np.float64))
        target_probability = target_weight / norm if norm > 0.0 else 0.0

        summary = IterationSummary(
            iteration=iteration,
            oracle_sum=oracle_sum,
            oracle_mean=oracle_mean,
            target_probability=target_probability,
            norm=norm,
            target_amp_min=target_min,
            target_amp_max=target_max,
            nontarget_amp_min=nontarget_min,
            nontarget_amp_max=nontarget_max,
            overflow_count=overflow_count,
            saturation_count=saturation_count,
        )
        self.summaries.append(summary)

        if self.trace_level == "FULL":
            self.full_records.append(
                FullIterationTrace(
                    iteration=iteration,
                    amplitudes_before=before.copy(),
                    amplitudes_after_oracle=after_oracle.copy(),
                    amplitudes_after_diffusion=after_diffusion.copy(),
                )
            )

        return summary

    @property
    def iteration_count(self) -> int:
        return len(self.summaries)

    def clear(self) -> None:
        self.summaries.clear()
        self.full_records.clear()
        self._next_iteration = 1

    def summary_dicts(self) -> list[dict[str, Any]]:
        return [item.to_dict() for item in self.summaries]

    @staticmethod
    def _validate_arrays(
        amplitudes_before: np.ndarray,
        amplitudes_after_oracle: np.ndarray,
        amplitudes_after_diffusion: np.ndarray,
        target_mask: np.ndarray,
    ) -> tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray]:
        before = np.asarray(amplitudes_before)
        after_oracle = np.asarray(amplitudes_after_oracle)
        after_diffusion = np.asarray(amplitudes_after_diffusion)
        mask = np.asarray(target_mask, dtype=np.bool_)

        arrays = (before, after_oracle, after_diffusion, mask)
        if any(item.ndim != 1 for item in arrays):
            raise ValueError("amplitude arrays and target_mask must be one-dimensional")
        if before.size == 0:
            raise ValueError("amplitude arrays cannot be empty")
        if not (
            before.size
            == after_oracle.size
            == after_diffusion.size
            == mask.size
        ):
            raise ValueError("amplitude arrays and target_mask must have equal length")

        return before, after_oracle, after_diffusion, mask

    @staticmethod
    def _range_or_none(values: np.ndarray) -> tuple[float | None, float | None]:
        if values.size == 0:
            return None, None
        return float(np.min(values)), float(np.max(values))
