from __future__ import annotations

from dataclasses import asdict, dataclass, field
from typing import Any

import numpy as np


ENUMERATION_TERMINATION_REASONS = {
    "ALL_FOUND",
    "REQUESTED_COUNT",
    "NO_TARGETS_REMAIN",
    "FAIL_LIMIT",
    "MAX_ATTEMPTS",
    "TOO_MANY",
    "NOT_STARTED",
}

SEARCH_TERMINATION_REASONS = {
    "SUCCESS",
    "NO_TARGET",
    "MEASUREMENT_FAILURE",
    "BBHT_BUDGET",
    "MAX_ATTEMPTS",
    "UNSPECIFIED",
}


def _validate_probability(name: str, value: float) -> None:
    tolerance = 1e-12
    if not -tolerance <= value <= 1.0 + tolerance:
        raise ValueError(f"{name} must be between 0 and 1")


@dataclass
class IterationSummary:
    """Compact numerical record for one completed Grover iteration."""

    iteration: int
    oracle_sum: float
    oracle_mean: float
    target_probability: float
    norm: float

    target_amp_min: float | None = None
    target_amp_max: float | None = None
    nontarget_amp_min: float | None = None
    nontarget_amp_max: float | None = None

    overflow_count: int = 0
    saturation_count: int = 0

    def __post_init__(self) -> None:
        if self.iteration < 1:
            raise ValueError("iteration must be at least 1")
        _validate_probability("target_probability", self.target_probability)
        if self.norm < 0.0:
            raise ValueError("norm cannot be negative")
        if self.overflow_count < 0:
            raise ValueError("overflow_count cannot be negative")
        if self.saturation_count < 0:
            raise ValueError("saturation_count cannot be negative")
        self._validate_amplitude_range(
            "target", self.target_amp_min, self.target_amp_max
        )
        self._validate_amplitude_range(
            "nontarget", self.nontarget_amp_min, self.nontarget_amp_max
        )

    @staticmethod
    def _validate_amplitude_range(
        label: str,
        minimum: float | None,
        maximum: float | None,
    ) -> None:
        if (minimum is None) != (maximum is None):
            raise ValueError(
                f"{label} amplitude minimum and maximum must both be set or both be None"
            )
        if minimum is not None and maximum is not None and minimum > maximum:
            raise ValueError(f"{label} amplitude minimum cannot exceed maximum")

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


@dataclass
class FullIterationTrace:
    """Full amplitude snapshots for one Grover iteration."""

    iteration: int
    amplitudes_before: np.ndarray
    amplitudes_after_oracle: np.ndarray
    amplitudes_after_diffusion: np.ndarray

    def __post_init__(self) -> None:
        if self.iteration < 1:
            raise ValueError("iteration must be at least 1")

        arrays = (
            self.amplitudes_before,
            self.amplitudes_after_oracle,
            self.amplitudes_after_diffusion,
        )
        if any(item.ndim != 1 for item in arrays):
            raise ValueError("full trace amplitude arrays must be one-dimensional")
        if self.amplitudes_before.size == 0:
            raise ValueError("full trace amplitude arrays cannot be empty")
        if len({item.size for item in arrays}) != 1:
            raise ValueError("full trace amplitude arrays must have equal length")

    def to_dict(self) -> dict[str, Any]:
        return {
            "iteration": self.iteration,
            "amplitudes_before": self.amplitudes_before.tolist(),
            "amplitudes_after_oracle": self.amplitudes_after_oracle.tolist(),
            "amplitudes_after_diffusion": self.amplitudes_after_diffusion.tolist(),
        }


@dataclass
class FixedIterationTrace:
    """Stored-width integer values for one bit-exact RTL iteration."""

    iteration: int
    amplitudes_before: np.ndarray
    amplitudes_after_oracle: np.ndarray
    mean_encoded: int
    amplitudes_after_diffusion: np.ndarray
    overflow_count: int
    saturation_count: int

    def __post_init__(self) -> None:
        if self.iteration < 1:
            raise ValueError("iteration must be at least 1")
        arrays = (
            self.amplitudes_before,
            self.amplitudes_after_oracle,
            self.amplitudes_after_diffusion,
        )
        if any(item.ndim != 1 for item in arrays):
            raise ValueError("encoded trace arrays must be one-dimensional")
        if self.amplitudes_before.size == 0:
            raise ValueError("encoded trace arrays cannot be empty")
        if len({item.size for item in arrays}) != 1:
            raise ValueError("encoded trace arrays must have equal length")
        if any(not np.issubdtype(item.dtype, np.integer) for item in arrays):
            raise TypeError("encoded trace arrays must contain integers")
        if self.overflow_count < 0 or self.saturation_count < 0:
            raise ValueError("fixed-point event counts cannot be negative")

    def to_dict(self) -> dict[str, Any]:
        return {
            "iteration": self.iteration,
            "amplitudes_before": self.amplitudes_before.astype(int).tolist(),
            "amplitudes_after_oracle": self.amplitudes_after_oracle.astype(int).tolist(),
            "mean_encoded": int(self.mean_encoded),
            "amplitudes_after_diffusion": self.amplitudes_after_diffusion.astype(int).tolist(),
            "overflow_count": self.overflow_count,
            "saturation_count": self.saturation_count,
        }


@dataclass
class AttemptRecord:
    """Record of one Known-M or BBHT measurement attempt."""

    attempt: int
    m_bound: float
    selected_iterations: int
    cumulative_grover_iterations: int
    oracle_calls: int

    measured_index: int | None
    measured_value: int | None
    success: bool
    expected_success_probability: float
    trace: list[IterationSummary] = field(default_factory=list)
    full_trace: list[FullIterationTrace] = field(default_factory=list)
    encoded_trace: list[FixedIterationTrace] = field(default_factory=list)
    initial_amplitude_encoded: int | None = None
    final_encoded_amplitudes: np.ndarray | None = None
    accumulator_width: int | None = None
    fixed_overflow_count: int = 0
    fixed_saturation_count: int = 0
    core_runtime_ms: float = 0.0
    measurement_runtime_ms: float = 0.0

    def __post_init__(self) -> None:
        if self.attempt < 1:
            raise ValueError("attempt must be at least 1")
        if self.m_bound < 1.0:
            raise ValueError("m_bound must be at least 1")
        if self.selected_iterations < 0:
            raise ValueError("selected_iterations cannot be negative")
        if self.cumulative_grover_iterations < self.selected_iterations:
            raise ValueError(
                "cumulative_grover_iterations cannot be smaller than selected_iterations"
            )
        if self.oracle_calls < 0:
            raise ValueError("oracle_calls cannot be negative")
        if self.measured_index is not None and self.measured_index < 0:
            raise ValueError("measured_index cannot be negative")
        if self.success and self.measured_index is None:
            raise ValueError("a successful attempt must have a measured_index")
        _validate_probability(
            "expected_success_probability", self.expected_success_probability
        )

        if self.trace:
            self._validate_trace_iterations(self.trace, "trace")
        if self.full_trace:
            if not self.trace:
                raise ValueError("full_trace requires matching summary trace records")
            self._validate_trace_iterations(self.full_trace, "full_trace")
        if self.encoded_trace:
            if not self.trace:
                raise ValueError("encoded_trace requires matching summary trace records")
            self._validate_trace_iterations(self.encoded_trace, "encoded_trace")

        metadata = (
            self.initial_amplitude_encoded,
            self.final_encoded_amplitudes,
            self.accumulator_width,
        )
        if any(item is not None for item in metadata) and not all(
            item is not None for item in metadata
        ):
            raise ValueError("fixed-point attempt metadata must be provided together")
        if self.final_encoded_amplitudes is not None:
            encoded = np.asarray(self.final_encoded_amplitudes)
            if encoded.ndim != 1 or encoded.size == 0:
                raise ValueError("final_encoded_amplitudes must be a nonempty 1D array")
            if not np.issubdtype(encoded.dtype, np.integer):
                raise TypeError("final_encoded_amplitudes must contain integers")
        if self.accumulator_width is not None and self.accumulator_width < 2:
            raise ValueError("accumulator_width must be at least 2")
        if self.fixed_overflow_count < 0 or self.fixed_saturation_count < 0:
            raise ValueError("fixed-point event counts cannot be negative")
        if self.core_runtime_ms < 0.0 or self.measurement_runtime_ms < 0.0:
            raise ValueError("attempt runtimes cannot be negative")
        if any(item > 0 for item in (self.fixed_overflow_count, self.fixed_saturation_count)):
            if self.initial_amplitude_encoded is None:
                raise ValueError("fixed-point event counts require fixed-point metadata")

    def to_dict(self) -> dict[str, Any]:
        return {
            "attempt": self.attempt,
            "m_bound": self.m_bound,
            "selected_iterations": self.selected_iterations,
            "cumulative_grover_iterations": self.cumulative_grover_iterations,
            "oracle_calls": self.oracle_calls,
            "measured_index": self.measured_index,
            "measured_value": self.measured_value,
            "success": self.success,
            "expected_success_probability": self.expected_success_probability,
            "trace": [item.to_dict() for item in self.trace],
            "full_trace": [item.to_dict() for item in self.full_trace],
            "encoded_trace": [item.to_dict() for item in self.encoded_trace],
            "initial_amplitude_encoded": self.initial_amplitude_encoded,
            "final_encoded_amplitudes": (
                self.final_encoded_amplitudes.astype(int).tolist()
                if self.final_encoded_amplitudes is not None
                else None
            ),
            "accumulator_width": self.accumulator_width,
            "fixed_overflow_count": self.fixed_overflow_count,
            "fixed_saturation_count": self.fixed_saturation_count,
        }

    def _validate_trace_iterations(
        self,
        records: list[IterationSummary] | list[FullIterationTrace] | list[FixedIterationTrace],
        label: str,
    ) -> None:
        if len(records) != self.selected_iterations:
            raise ValueError(
                f"{label} length must match selected_iterations when trace is present"
            )
        expected = list(range(1, self.selected_iterations + 1))
        actual = [item.iteration for item in records]
        if actual != expected:
            raise ValueError(f"{label} iterations must run from 1 to selected_iterations")


@dataclass
class SearchResult:
    """Result of one complete Known-M or BBHT search."""

    success: bool
    measured_index: int | None
    measured_value: int | None
    total_grover_iterations: int
    total_oracle_calls: int
    attempts: list[AttemptRecord] = field(default_factory=list)
    termination_reason: str = "UNSPECIFIED"
    oracle_preparation_ms: float = 0.0

    def __post_init__(self) -> None:
        self.termination_reason = self.termination_reason.upper()
        if self.termination_reason not in SEARCH_TERMINATION_REASONS:
            raise ValueError(
                "termination_reason must be one of "
                f"{sorted(SEARCH_TERMINATION_REASONS)}"
            )
        if self.total_grover_iterations < 0:
            raise ValueError("total_grover_iterations cannot be negative")
        if self.total_oracle_calls < 0:
            raise ValueError("total_oracle_calls cannot be negative")
        if self.oracle_preparation_ms < 0.0:
            raise ValueError("oracle_preparation_ms cannot be negative")
        if self.measured_index is not None and self.measured_index < 0:
            raise ValueError("measured_index cannot be negative")
        if self.success and (
            self.measured_index is None or self.measured_value is None
        ):
            raise ValueError(
                "a successful search must have a measured_index and measured_value"
            )
        if not self.success and (
            self.measured_index is not None or self.measured_value is not None
        ):
            raise ValueError(
                "an unsuccessful search cannot expose a final measured answer"
            )
        if self.attempts:
            final_attempt = self.attempts[-1]
            if self.total_grover_iterations != final_attempt.cumulative_grover_iterations:
                raise ValueError(
                    "total_grover_iterations must match the final attempt record"
                )
            summed_oracle_calls = sum(item.oracle_calls for item in self.attempts)
            if self.total_oracle_calls != summed_oracle_calls:
                raise ValueError(
                    "total_oracle_calls must equal the sum of attempt oracle calls"
                )
            if self.success != final_attempt.success:
                raise ValueError("success must match the final attempt's success")
            if self.success and (
                self.measured_index != final_attempt.measured_index
                or self.measured_value != final_attempt.measured_value
            ):
                raise ValueError(
                    "measured_index and measured_value must match the final attempt"
                )

    @property
    def attempt_count(self) -> int:
        return len(self.attempts)

    def to_dict(self) -> dict[str, Any]:
        return {
            "success": self.success,
            "measured_index": self.measured_index,
            "measured_value": self.measured_value,
            "total_grover_iterations": self.total_grover_iterations,
            "total_oracle_calls": self.total_oracle_calls,
            "attempts": [item.to_dict() for item in self.attempts],
            "termination_reason": self.termination_reason,
        }


@dataclass
class EnumerationResult:
    """Result of repeatedly searching while excluding already found targets."""

    found_indices: list[int]
    rounds: list[SearchResult]
    total_grover_iterations: int
    total_oracle_calls: int
    consecutive_failures: int
    termination_reason: str

    def __post_init__(self) -> None:
        self.termination_reason = self.termination_reason.upper()
        if self.termination_reason not in ENUMERATION_TERMINATION_REASONS:
            raise ValueError(
                "termination_reason must be one of "
                f"{sorted(ENUMERATION_TERMINATION_REASONS)}"
            )
        if any(index < 0 for index in self.found_indices):
            raise ValueError("found indices cannot be negative")
        if len(self.found_indices) != len(set(self.found_indices)):
            raise ValueError("found_indices cannot contain duplicates")
        if self.total_grover_iterations < 0:
            raise ValueError("total_grover_iterations cannot be negative")
        if self.total_oracle_calls < 0:
            raise ValueError("total_oracle_calls cannot be negative")
        if self.consecutive_failures < 0:
            raise ValueError("consecutive_failures cannot be negative")

        summed_iterations = sum(item.total_grover_iterations for item in self.rounds)
        if self.total_grover_iterations != summed_iterations:
            raise ValueError(
                "total_grover_iterations must equal the sum of all search rounds"
            )
        summed_oracle_calls = sum(item.total_oracle_calls for item in self.rounds)
        if self.total_oracle_calls != summed_oracle_calls:
            raise ValueError(
                "total_oracle_calls must equal the sum of all search rounds"
            )

        successful_indices = [
            item.measured_index for item in self.rounds if item.success
        ]
        if successful_indices != self.found_indices:
            raise ValueError(
                "found_indices must match successful search rounds in order"
            )

        trailing_failures = 0
        for item in reversed(self.rounds):
            if item.success:
                break
            trailing_failures += 1
        if self.consecutive_failures != trailing_failures:
            raise ValueError(
                "consecutive_failures must match trailing failed search rounds"
            )

    @property
    def found_count(self) -> int:
        return len(self.found_indices)

    def to_dict(self) -> dict[str, Any]:
        return {
            "found_indices": list(self.found_indices),
            "rounds": [item.to_dict() for item in self.rounds],
            "total_grover_iterations": self.total_grover_iterations,
            "total_oracle_calls": self.total_oracle_calls,
            "consecutive_failures": self.consecutive_failures,
            "termination_reason": self.termination_reason,
        }
