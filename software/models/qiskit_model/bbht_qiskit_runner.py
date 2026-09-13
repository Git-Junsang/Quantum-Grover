"""Qiskit-backed implementation of the frozen v0.9.8 BBHT control flow."""

from __future__ import annotations

from dataclasses import asdict, dataclass
from time import perf_counter

import numpy as np

from numpy_grover_backend import run_grover
from qiskit_grover_backend import execute_prepared, prepare_requested_j
from checkpoint_bbht_model import (
    V098JRandomSource,
    V098MeasurementRandomSource,
    measure_v098_state,
)
from bbht_control_semantics import V098_BBHT_LOGICAL_BUDGET, v098_m_bounds


@dataclass(frozen=True)
class QiskitBBHTAttempt:
    attempt: int
    m_bound: int
    requested_j: int
    result_index: int
    success: bool
    target_probability: float
    execution_seconds: float
    measurement_threshold: int | None
    measurement_total_weight: int
    measurement_random_blocks: tuple[int, ...]

    def to_dict(self) -> dict[str, object]:
        return asdict(self)


@dataclass(frozen=True)
class QiskitBBHTResult:
    success: bool
    termination_reason: str
    result_index: int | None
    trial_count: int
    L_BBHT: int
    qiskit_execution_seconds: float
    circuit_build_seconds: float
    transpile_seconds: float
    wall_seconds: float
    compiled_j_values: tuple[int, ...]
    attempts: tuple[QiskitBBHTAttempt, ...]

    def to_dict(self) -> dict[str, object]:
        return asdict(self)


@dataclass(frozen=True)
class NumpyBBHTResult:
    success: bool
    termination_reason: str
    result_index: int | None
    trial_count: int
    L_BBHT: int
    execution_seconds: float
    wall_seconds: float
    attempts: tuple[QiskitBBHTAttempt, ...]

    def to_dict(self) -> dict[str, object]:
        return asdict(self)


def run_v098_bbht_qiskit(
    target_mask: np.ndarray,
    *,
    seed_j: int,
    seed_measurement: int,
    shot_cap: int = 100,
    optimization_level: int = 0,
    threads: int = 1,
    prepared_cache: dict[int, object] | None = None,
) -> QiskitBBHTResult:
    """Run standard BBHT with Qiskit statevectors for each fresh attempt.

    The J stream, m bounds, measurement PRNG, and integer CDF mapping match
    v0.9.8.  Qiskit's Float64 state is quantized to Q1.22 only at the
    measurement boundary.  M is never supplied to the scheduler.
    """

    mask = np.asarray(target_mask)
    if mask.shape != (16384,) or mask.dtype != np.bool_:
        raise ValueError("v0.9.8 BBHT requires a boolean Q14 target mask")
    if not 1 <= shot_cap <= 0xFFFF:
        raise ValueError("shot_cap must be between 1 and 65535")

    started_wall = perf_counter()
    j_source = V098JRandomSource(seed_j)
    measurement_source = V098MeasurementRandomSource(seed_measurement)
    bounds = v098_m_bounds()
    prepared_by_j = {} if prepared_cache is None else prepared_cache
    attempts = []
    logical_iterations = 0
    build_seconds = 0.0
    transpile_seconds = 0.0
    execute_seconds = 0.0

    for attempt_number in range(1, shot_cap + 1):
        bound = bounds[min(attempt_number - 1, len(bounds) - 1)]
        requested_j, _ = j_source.draw_uniform(bound)
        if requested_j not in prepared_by_j:
            prepared = prepare_requested_j(
                mask,
                requested_j,
                optimization_level=optimization_level,
                threads=threads,
            )
            prepared_by_j[requested_j] = prepared
            build_seconds += prepared.build_seconds
            transpile_seconds += prepared.transpile_seconds
        result = execute_prepared(prepared_by_j[requested_j])
        execute_seconds += result.execution_seconds
        measurement = _measure_float_state(result.amplitudes, mask, measurement_source)
        if measurement.result_index is None:
            raise RuntimeError("Qiskit state produced zero measurement weight")
        index = measurement.result_index
        success = measurement.success
        logical_iterations += requested_j
        attempts.append(QiskitBBHTAttempt(
            attempt=attempt_number,
            m_bound=bound,
            requested_j=requested_j,
            result_index=index,
            success=success,
            target_probability=result.target_probability,
            execution_seconds=result.execution_seconds,
            measurement_threshold=measurement.threshold,
            measurement_total_weight=measurement.total_weight,
            measurement_random_blocks=measurement.random_blocks,
        ))
        if success:
            reason = "SUCCESS"
            break
        if logical_iterations + 1 >= V098_BBHT_LOGICAL_BUDGET:
            reason = "BUDGET_LIMIT"
            break
    else:
        reason = "SHOT_LIMIT"

    wall_seconds = perf_counter() - started_wall
    final_success = bool(attempts[-1].success)
    return QiskitBBHTResult(
        success=final_success,
        termination_reason=reason,
        result_index=attempts[-1].result_index if final_success else None,
        trial_count=len(attempts),
        L_BBHT=logical_iterations,
        qiskit_execution_seconds=execute_seconds,
        circuit_build_seconds=build_seconds,
        transpile_seconds=transpile_seconds,
        wall_seconds=wall_seconds,
        compiled_j_values=tuple(sorted(prepared_by_j)),
        attempts=tuple(attempts),
    )


def run_v098_bbht_numpy(
    target_mask: np.ndarray,
    *,
    seed_j: int,
    seed_measurement: int,
    shot_cap: int = 100,
) -> NumpyBBHTResult:
    """Run the same v0.9.8 BBHT controller with the NumPy Float64 core."""

    mask = np.asarray(target_mask)
    if mask.shape != (16384,) or mask.dtype != np.bool_:
        raise ValueError("v0.9.8 BBHT requires a boolean Q14 target mask")
    if not 1 <= shot_cap <= 0xFFFF:
        raise ValueError("shot_cap must be between 1 and 65535")

    started_wall = perf_counter()
    j_source = V098JRandomSource(seed_j)
    measurement_source = V098MeasurementRandomSource(seed_measurement)
    bounds = v098_m_bounds()
    attempts = []
    logical_iterations = 0
    execute_seconds = 0.0

    for attempt_number in range(1, shot_cap + 1):
        bound = bounds[min(attempt_number - 1, len(bounds) - 1)]
        requested_j, _ = j_source.draw_uniform(bound)
        started = perf_counter()
        result = run_grover(mask, requested_j, trace_level="NONE")
        elapsed = perf_counter() - started
        execute_seconds += elapsed
        measurement = _measure_float_state(result.amplitudes, mask, measurement_source)
        if measurement.result_index is None:
            raise RuntimeError("NumPy state produced zero measurement weight")
        index = measurement.result_index
        success = measurement.success
        logical_iterations += requested_j
        attempts.append(QiskitBBHTAttempt(
            attempt=attempt_number,
            m_bound=bound,
            requested_j=requested_j,
            result_index=index,
            success=success,
            target_probability=result.target_probability,
            execution_seconds=elapsed,
            measurement_threshold=measurement.threshold,
            measurement_total_weight=measurement.total_weight,
            measurement_random_blocks=measurement.random_blocks,
        ))
        if success:
            reason = "SUCCESS"
            break
        if logical_iterations + 1 >= V098_BBHT_LOGICAL_BUDGET:
            reason = "BUDGET_LIMIT"
            break
    else:
        reason = "SHOT_LIMIT"

    return NumpyBBHTResult(
        success=bool(attempts[-1].success),
        termination_reason=reason,
        result_index=attempts[-1].result_index if attempts[-1].success else None,
        trial_count=len(attempts),
        L_BBHT=logical_iterations,
        execution_seconds=execute_seconds,
        wall_seconds=perf_counter() - started_wall,
        attempts=tuple(attempts),
    )


def _measure_float_state(
    amplitudes: np.ndarray,
    target_mask: np.ndarray,
    source: V098MeasurementRandomSource,
):
    """Apply the FPGA Q1.22 weight/CDF sampler to a Float64 state.

    Grover states are real up to a physically irrelevant global phase.  The
    magnitude therefore gives the same Born weights while avoiding a false
    mismatch when Qiskit returns a globally phase-rotated state.
    """

    state = np.asarray(amplitudes, dtype=np.complex128)
    scale = 1 << 22
    positive_maximum = scale - 1
    encoded = np.rint(np.abs(state) * scale).astype(np.int64)
    encoded = np.clip(encoded, 0, positive_maximum)
    return measure_v098_state(encoded, target_mask, source)
