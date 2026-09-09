from __future__ import annotations

from dataclasses import dataclass
from numbers import Integral

import numpy as np

from models import FullIterationTrace, IterationSummary
from trace import TraceRecorder


@dataclass(frozen=True)
class GroverFloatResult:
    """Output of one independently initialized Float64 Grover run."""

    amplitudes: np.ndarray
    iterations: int
    target_count: int
    target_probability: float
    norm: float
    trace: list[IterationSummary]
    full_trace: list[FullIterationTrace]


def initialize_uniform_state(active_n: int) -> np.ndarray:
    """Create the uniform superposition used at the start of every attempt."""

    _validate_active_n(active_n)
    amplitude = 1.0 / np.sqrt(float(active_n))
    return np.full(active_n, amplitude, dtype=np.float64)


def apply_phase_oracle(
    amplitudes: np.ndarray,
    target_mask: np.ndarray,
) -> np.ndarray:
    """Flip the sign of every target amplitude without changing the input."""

    checked_amplitudes, checked_mask = _validate_state(amplitudes, target_mask)
    result = checked_amplitudes.copy()
    result[checked_mask] *= -1.0
    return result


def apply_diffusion(amplitudes: np.ndarray) -> np.ndarray:
    """Apply inversion about the mean: A_next[i] = 2 * mean(A) - A[i]."""

    checked = _validate_amplitudes(amplitudes)
    mean = float(np.mean(checked, dtype=np.float64))
    return 2.0 * mean - checked


def run_grover(
    target_mask: np.ndarray,
    iterations: int,
    *,
    trace_level: str = "SUMMARY",
) -> GroverFloatResult:
    """Initialize uniformly and execute exactly ``iterations`` Grover rounds."""

    checked_mask = _validate_target_mask(target_mask)
    _validate_iterations(iterations)

    amplitudes = initialize_uniform_state(checked_mask.size)
    recorder = TraceRecorder(trace_level)

    for iteration in range(1, int(iterations) + 1):
        before = amplitudes
        after_oracle = apply_phase_oracle(before, checked_mask)
        amplitudes = apply_diffusion(after_oracle)
        recorder.record(
            iteration=iteration,
            amplitudes_before=before,
            amplitudes_after_oracle=after_oracle,
            amplitudes_after_diffusion=amplitudes,
            target_mask=checked_mask,
        )

    probabilities = np.square(amplitudes, dtype=np.float64)
    return GroverFloatResult(
        amplitudes=amplitudes.copy(),
        iterations=int(iterations),
        target_count=int(np.count_nonzero(checked_mask)),
        target_probability=float(
            np.sum(probabilities[checked_mask], dtype=np.float64)
        ),
        norm=float(np.sum(probabilities, dtype=np.float64)),
        trace=list(recorder.summaries),
        full_trace=list(recorder.full_records),
    )


def theoretical_success_probability(
    active_n: int,
    target_count: int,
    iterations: int,
) -> float:
    """Return sin^2((2j+1)theta), including M=0 and M=N edge cases."""

    _validate_active_n(active_n)
    _validate_iterations(iterations)
    if isinstance(target_count, bool) or not isinstance(target_count, Integral):
        raise TypeError("target_count must be an integer")
    if not 0 <= target_count <= active_n:
        raise ValueError("target_count must be between 0 and active_n")
    if target_count == 0:
        return 0.0
    if target_count == active_n:
        return 1.0

    theta = np.arcsin(np.sqrt(float(target_count) / float(active_n)))
    angle = (2 * int(iterations) + 1) * theta
    return float(np.sin(angle) ** 2)


def _validate_active_n(active_n: int) -> None:
    if isinstance(active_n, bool) or not isinstance(active_n, Integral):
        raise TypeError("active_n must be an integer")
    if active_n < 2 or active_n & (active_n - 1):
        raise ValueError("active_n must be a power of two and at least 2")


def _validate_iterations(iterations: int) -> None:
    if isinstance(iterations, bool) or not isinstance(iterations, Integral):
        raise TypeError("iterations must be an integer")
    if iterations < 0:
        raise ValueError("iterations cannot be negative")


def _validate_amplitudes(amplitudes: np.ndarray) -> np.ndarray:
    checked = np.asarray(amplitudes, dtype=np.float64)
    if checked.ndim != 1:
        raise ValueError("amplitudes must be a one-dimensional array")
    if checked.size < 2 or checked.size & (checked.size - 1):
        raise ValueError("amplitudes length must be a power of two and at least 2")
    if not np.all(np.isfinite(checked)):
        raise ValueError("amplitudes must contain only finite values")
    return checked


def _validate_target_mask(target_mask: np.ndarray) -> np.ndarray:
    checked = np.asarray(target_mask)
    if checked.ndim != 1:
        raise ValueError("target_mask must be a one-dimensional array")
    if checked.dtype != np.bool_:
        raise TypeError("target_mask must have boolean dtype")
    _validate_active_n(checked.size)
    return checked


def _validate_state(
    amplitudes: np.ndarray,
    target_mask: np.ndarray,
) -> tuple[np.ndarray, np.ndarray]:
    checked_amplitudes = _validate_amplitudes(amplitudes)
    checked_mask = _validate_target_mask(target_mask)
    if checked_amplitudes.size != checked_mask.size:
        raise ValueError("amplitudes and target_mask must have equal length")
    return checked_amplitudes, checked_mask
