"""Semantic checks for v0.9.8 BBHT, K4/H4, and hardware Enumeration traces.

These checks do not solve the internal checkpoint policy.  They verify the
observable contract that the optimization is forbidden to change.
"""

from __future__ import annotations

from dataclasses import asdict, dataclass
from fractions import Fraction
from math import ceil
from typing import Any, Iterable, Sequence

import numpy as np

from rtl_v098_contract import V098_N_ENTRIES


V098_BBHT_LOGICAL_BUDGET = 576


def v098_m_bounds() -> tuple[int, ...]:
    """Q14 m sequence for m0=1, lambda=6/5, m_max=sqrt(N)=128."""

    maximum = 128
    value = Fraction(1, 1)
    result: list[int] = []
    while True:
        bound = min(ceil(value), maximum)
        result.append(bound)
        if bound == maximum:
            return tuple(result)
        value = min(value * Fraction(6, 5), Fraction(maximum, 1))


@dataclass(frozen=True)
class V098AttemptObservation:
    attempt: int
    requested_j: int
    result_index: int | None
    success: bool
    physical_iterations: int | None = None


@dataclass(frozen=True)
class V098TraceAudit:
    passed: bool
    trial_count: int
    L_BBHT: int
    termination_reason: str
    violations: tuple[str, ...]

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


def audit_bbht_attempts(
    attempts: Sequence[V098AttemptObservation],
    target_mask: np.ndarray,
    *,
    shot_cap: int = 100,
) -> V098TraceAudit:
    """Validate bounds, counters, result verification, and final termination."""

    mask = _validate_mask(target_mask)
    bounds = v098_m_bounds()
    violations: list[str] = []
    cumulative = 0
    termination = "INCOMPLETE"

    if len(attempts) > shot_cap:
        violations.append("attempt count exceeds shot_cap")
    for position, item in enumerate(attempts, start=1):
        if item.attempt != position:
            violations.append(f"attempt number {item.attempt} expected {position}")
        bound = bounds[min(position - 1, len(bounds) - 1)]
        if not 0 <= item.requested_j < bound:
            violations.append(
                f"attempt {position} requested_j={item.requested_j} outside [0,{bound})"
            )
        cumulative += item.requested_j
        if item.result_index is None:
            if item.success:
                violations.append(f"attempt {position} success has no result index")
        elif not 0 <= item.result_index < V098_N_ENTRIES:
            violations.append(f"attempt {position} result index out of range")
        elif item.success != bool(mask[item.result_index]):
            violations.append(f"attempt {position} success disagrees with Oracle")
        if item.physical_iterations is not None and item.physical_iterations < 0:
            violations.append(f"attempt {position} physical iterations are negative")
        if item.success:
            if position != len(attempts):
                violations.append("attempts continue after first verified success")
            termination = "SUCCESS"
            break
        if cumulative + 1 >= V098_BBHT_LOGICAL_BUDGET:
            termination = "BUDGET_LIMIT"
            if position != len(attempts):
                violations.append("attempts continue after logical budget")
            break
        if position >= shot_cap:
            termination = "SHOT_LIMIT"
            if position != len(attempts):
                violations.append("attempts continue after shot cap")
            break

    return V098TraceAudit(
        passed=not violations and termination != "INCOMPLETE",
        trial_count=len(attempts),
        L_BBHT=cumulative,
        termination_reason=termination,
        violations=tuple(violations),
    )


@dataclass(frozen=True)
class V098PairTraceAudit:
    passed: bool
    requested_j_match: bool
    measured_index_match: bool
    success_match: bool
    normal_physical_iterations: int
    k4h8_physical_iterations: int
    violations: tuple[str, ...]


def audit_normal_k4h8_attempt_pair(
    normal: Sequence[V098AttemptObservation],
    k4h8: Sequence[V098AttemptObservation],
) -> V098PairTraceAudit:
    """Require K4/H4 to preserve the exact logical and measurement trace.

    The function name is retained for compatibility with pre-H4 scripts.
    """

    requested_match = [x.requested_j for x in normal] == [x.requested_j for x in k4h8]
    measured_match = [x.result_index for x in normal] == [x.result_index for x in k4h8]
    success_match = [x.success for x in normal] == [x.success for x in k4h8]
    normal_physical = sum(
        x.requested_j if x.physical_iterations is None else x.physical_iterations
        for x in normal
    )
    k4_physical = sum(
        x.requested_j if x.physical_iterations is None else x.physical_iterations
        for x in k4h8
    )
    violations = []
    if not requested_match:
        violations.append("requested-j sequence changed")
    if not measured_match:
        violations.append("measurement index sequence changed")
    if not success_match:
        violations.append("success/failure sequence changed")
    if k4_physical > normal_physical:
        violations.append("K4/H4 physical work exceeds Normal")
    return V098PairTraceAudit(
        passed=not violations,
        requested_j_match=requested_match,
        measured_index_match=measured_match,
        success_match=success_match,
        normal_physical_iterations=normal_physical,
        k4h8_physical_iterations=k4_physical,
        violations=tuple(violations),
    )


# Canonical H4 spelling.  The older function remains source-compatible.
audit_normal_k4h4_attempt_pair = audit_normal_k4h8_attempt_pair


@dataclass(frozen=True)
class V098EnumerationAudit:
    passed: bool
    found_count: int
    duplicate_free: bool
    all_indices_are_targets: bool
    remaining_target_count: int
    oracle_epoch_changes: int
    violations: tuple[str, ...]

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


def audit_enumeration_fifo(
    initial_target_mask: np.ndarray,
    fifo_indices: Iterable[int],
    *,
    reported_found_count: int | None = None,
) -> V098EnumerationAudit:
    """Replay found-mask updates from FIFO output and validate unique results."""

    mask = _validate_mask(initial_target_mask)
    found_mask = np.zeros(V098_N_ENTRIES, dtype=np.bool_)
    values = [int(index) for index in fifo_indices]
    violations: list[str] = []
    all_targets = True
    for position, index in enumerate(values, start=1):
        if not 0 <= index < V098_N_ENTRIES:
            violations.append(f"FIFO item {position} index out of range")
            all_targets = False
            continue
        if not mask[index]:
            violations.append(f"FIFO item {position} is not an original target")
            all_targets = False
        if found_mask[index]:
            violations.append(f"FIFO item {position} duplicates index {index}")
        found_mask[index] = True
    duplicate_free = len(values) == len(set(values))
    if reported_found_count is not None and reported_found_count != len(set(values)):
        violations.append("FOUND_COUNT disagrees with unique FIFO results")
    remaining = int(np.count_nonzero(mask & ~found_mask))
    return V098EnumerationAudit(
        passed=not violations,
        found_count=len(set(values)),
        duplicate_free=duplicate_free,
        all_indices_are_targets=all_targets,
        remaining_target_count=remaining,
        oracle_epoch_changes=len(set(values)),
        violations=tuple(violations),
    )


def _validate_mask(mask: np.ndarray) -> np.ndarray:
    checked = np.asarray(mask)
    if checked.shape != (V098_N_ENTRIES,) or checked.dtype != np.bool_:
        raise ValueError("target_mask must be a boolean 16384-entry array")
    return checked
