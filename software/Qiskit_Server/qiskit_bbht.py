"""Qiskit-backed implementation of the frozen v0.9.8 BBHT control flow."""

from __future__ import annotations

from dataclasses import asdict, dataclass
from time import perf_counter

import numpy as np

from grover_core_float import run_grover
from qiskit_grover import execute_prepared, prepare_requested_j
from rtl_v098_auto import V098JRandomSource
from rtl_v098_semantics import V098_BBHT_LOGICAL_BUDGET, v098_m_bounds


@dataclass(frozen=True)
class QiskitBBHTAttempt:
    attempt: int
    m_bound: int
    requested_j: int
    result_index: int
    success: bool
    target_probability: float
    execution_seconds: float

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

    The J stream and m bounds match v0.9.8.  Measurement uses an independent
    NumPy Born sampler, so individual result indices are not expected to match
    the FPGA xorshift64 stream.  M is never supplied to the scheduler.
    """

    mask = np.asarray(target_mask)
    if mask.shape != (16384,) or mask.dtype != np.bool_:
        raise ValueError("v0.9.8 BBHT requires a boolean Q14 target mask")
    if not 1 <= shot_cap <= 0xFFFF:
        raise ValueError("shot_cap must be between 1 and 65535")

    started_wall = perf_counter()
    j_source = V098JRandomSource(seed_j)
    measurement_rng = np.random.default_rng(seed_measurement)
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
        probabilities = np.square(np.abs(result.amplitudes), dtype=np.float64)
        probabilities /= np.sum(probabilities, dtype=np.float64)
        index = int(measurement_rng.choice(mask.size, p=probabilities))
        success = bool(mask[index])
        logical_iterations += requested_j
        attempts.append(QiskitBBHTAttempt(
            attempt=attempt_number,
            m_bound=bound,
            requested_j=requested_j,
            result_index=index,
            success=success,
            target_probability=result.target_probability,
            execution_seconds=result.execution_seconds,
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
    measurement_rng = np.random.default_rng(seed_measurement)
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
        probabilities = np.square(result.amplitudes, dtype=np.float64)
        probabilities /= np.sum(probabilities, dtype=np.float64)
        index = int(measurement_rng.choice(mask.size, p=probabilities))
        success = bool(mask[index])
        logical_iterations += requested_j
        attempts.append(QiskitBBHTAttempt(
            attempt=attempt_number,
            m_bound=bound,
            requested_j=requested_j,
            result_index=index,
            success=success,
            target_probability=result.target_probability,
            execution_seconds=elapsed,
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
