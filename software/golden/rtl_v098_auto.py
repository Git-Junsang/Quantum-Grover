"""Executable automatic-core reference for the frozen v0.9.8 contract.

The model implements the documented Q14 BBHT control flow, step-7 J LFSR,
Q1.22 Grover datapath, Born CDF sampling, semantic-preserving checkpoint reuse,
and found-mask Enumeration.

Two details are intentionally labelled provisional because the delivered local
artifacts do not contain their complete bit equations: the 32-to-64-bit
measurement seed expansion and the restricted-B bridge-level K4/H8 planner.
They are isolated behind small classes so the frozen RTL equations can replace
them without changing the search model or vector format.
"""

from __future__ import annotations

from dataclasses import asdict, dataclass
from functools import lru_cache
from typing import Any, Iterable, Sequence

import numpy as np

from rtl_v07g import RTL_PROFILE_Q14, rtl_initial_state, rtl_run_core
from rtl_v098_contract import (
    V098_CHECKPOINT_K,
    V098_N_ENTRIES,
    V098_POLICY_HORIZON,
    V098RuntimeConfig,
)
from rtl_v098_data import V098Dataset, v098_target_mask
from rtl_v098_semantics import V098_BBHT_LOGICAL_BUDGET, v098_m_bounds


J_FALLBACK_SEED = 0xACE12345
MEAS_FALLBACK_SEED = 0xBEEFC0DE
AUTO_COMPATIBILITY = "V0.9.8_DOCUMENTED_SEMANTIC_REFERENCE"
MEASUREMENT_ASSUMPTION = "XORSHIFT64_13_7_17_DUPLICATED_32BIT_SEED"
CHECKPOINT_ASSUMPTION = "K4_ENDPOINT_ONLY_ROLLING_H8_REFERENCE"


def _lfsr_step(state: int) -> int:
    value = int(state) & 0xFFFFFFFF
    feedback = ((value >> 31) ^ (value >> 21) ^ (value >> 1) ^ value) & 1
    return ((value << 1) & 0xFFFFFFFF) | feedback


class V098JRandomSource:
    """Documented J stream: pre-state draw followed by ordinary step^7."""

    def __init__(self, seed: int) -> None:
        checked = int(seed) & 0xFFFFFFFF
        self.state = checked if checked else J_FALLBACK_SEED

    def clone(self) -> "V098JRandomSource":
        other = V098JRandomSource(1)
        other.state = self.state
        return other

    def draw_word(self) -> int:
        value = self.state
        for _ in range(7):
            self.state = _lfsr_step(self.state)
        return value

    def draw_uniform(self, bound: int) -> tuple[int, tuple[int, ...]]:
        if not 1 <= int(bound) <= 128:
            raise ValueError("bound must be between 1 and 128")
        bits = (int(bound) - 1).bit_length()
        mask = (1 << bits) - 1 if bits else 0
        draws: list[int] = []
        while True:
            word = self.draw_word()
            draws.append(word)
            candidate = (word & 0xFF) & mask
            if candidate < bound:
                return candidate, tuple(draws)


class V098MeasurementRandomSource:
    """Replaceable 64-bit measurement stream used by the semantic reference.

    The handoff states only that a 32-bit seed is expanded to a 64-bit xorshift
    state. Until the frozen RTL equation is available, the reference duplicates
    the effective 32-bit seed into both halves and applies xorshift64(13,7,17).
    """

    def __init__(self, seed: int) -> None:
        checked = int(seed) & 0xFFFFFFFF
        effective = checked if checked else MEAS_FALLBACK_SEED
        self.state = ((effective << 32) | effective) & 0xFFFFFFFFFFFFFFFF

    def draw_block(self) -> int:
        value = self.state
        value ^= (value << 13) & 0xFFFFFFFFFFFFFFFF
        value ^= value >> 7
        value ^= (value << 17) & 0xFFFFFFFFFFFFFFFF
        self.state = value & 0xFFFFFFFFFFFFFFFF
        return self.state


class V098MeasurementBlockSource:
    """Inject captured 64-bit RTL draw blocks into the exact CDF datapath."""

    def __init__(self, blocks: Iterable[int]) -> None:
        checked = tuple(int(value) for value in blocks)
        if not checked:
            raise ValueError("at least one measurement block is required")
        if any(value < 0 or value > 0xFFFFFFFFFFFFFFFF for value in checked):
            raise ValueError("measurement blocks must fit unsigned 64-bit")
        self._blocks = checked
        self._index = 0

    def draw_block(self) -> int:
        if self._index >= len(self._blocks):
            raise RuntimeError("measurement block trace was exhausted")
        value = self._blocks[self._index]
        self._index += 1
        return value


@dataclass(frozen=True)
class V098Measurement:
    result_index: int | None
    success: bool
    threshold: int | None
    total_weight: int
    selected_row: int | None
    selected_lane: int | None
    random_blocks: tuple[int, ...]


def measure_v098_state(
    encoded_amplitudes: np.ndarray,
    target_mask: np.ndarray,
    source: V098MeasurementRandomSource | V098MeasurementBlockSource,
) -> V098Measurement:
    encoded = np.asarray(encoded_amplitudes, dtype=np.int64)
    mask = np.asarray(target_mask)
    if encoded.shape != (V098_N_ENTRIES,):
        raise ValueError("encoded_amplitudes must contain 16384 entries")
    if mask.shape != encoded.shape or mask.dtype != np.bool_:
        raise ValueError("target_mask must be a boolean 16384-entry array")
    rows = encoded.reshape(-1, 32)
    squares = rows * rows
    row_weights = np.sum(squares, axis=1, dtype=np.int64)
    total_weight = int(np.sum(row_weights, dtype=np.int64))
    if total_weight == 0:
        return V098Measurement(None, False, None, 0, None, None, ())

    blocks: list[int] = []
    if total_weight == 1:
        threshold = 0
    else:
        width = (total_weight - 1).bit_length()
        candidate_mask = (1 << width) - 1
        while True:
            block = source.draw_block()
            blocks.append(block)
            high = (block >> 32) & 0xFFFFFFFF
            low = block & 0xFFFFFFFF
            candidate = ((high << 32) | low) & candidate_mask
            if candidate < total_weight:
                threshold = candidate
                break

    row_cdf = np.cumsum(row_weights, dtype=np.int64)
    row = int(np.searchsorted(row_cdf, threshold, side="right"))
    before = int(row_cdf[row - 1]) if row else 0
    lane_cdf = np.cumsum(squares[row], dtype=np.int64)
    lane = int(np.searchsorted(lane_cdf, threshold - before, side="right"))
    index = row * 32 + lane
    return V098Measurement(
        result_index=index,
        success=bool(mask[index]),
        threshold=threshold,
        total_weight=total_weight,
        selected_row=row,
        selected_lane=lane,
        random_blocks=tuple(blocks),
    )


@dataclass
class _CheckpointSlot:
    j: int
    state: np.ndarray


class V098CheckpointReference:
    """K4 endpoint checkpoint manager with rolling-H8 victim selection."""

    def __init__(self, capacity: int = V098_CHECKPOINT_K) -> None:
        self.capacity = int(capacity)
        self.slots: list[_CheckpointSlot] = []

    def invalidate(self) -> None:
        self.slots.clear()

    @property
    def positions(self) -> tuple[int, ...]:
        return tuple(sorted(slot.j for slot in self.slots))

    def execute(
        self,
        requested_j: int,
        target_mask: np.ndarray,
        future_requested: Sequence[int],
    ) -> tuple[np.ndarray, int, int, tuple[int, ...], int]:
        exact = next((slot for slot in self.slots if slot.j == requested_j), None)
        before = self.positions
        if exact is not None:
            return exact.state.copy(), 0, requested_j, before, 0

        predecessors = [slot for slot in self.slots if slot.j < requested_j]
        if predecessors:
            source = max(predecessors, key=lambda slot: slot.j)
            source_j = source.j
            start = source.state.copy()
            physical = requested_j - source_j
            result = rtl_run_core(
                start,
                target_mask,
                physical,
                starting_iteration=source_j,
                trace_level="NONE",
                profile=RTL_PROFILE_Q14,
            )
            source.j = requested_j
            source.state = result.encoded_amplitudes.copy()
            return (
                result.encoded_amplitudes,
                physical,
                source_j,
                before,
                result.saturation_count,
            )

        source_j = 0
        result = rtl_run_core(
            rtl_initial_state(RTL_PROFILE_Q14),
            target_mask,
            requested_j,
            trace_level="NONE",
            profile=RTL_PROFILE_Q14,
        )
        slot = _CheckpointSlot(requested_j, result.encoded_amplitudes.copy())
        if len(self.slots) < self.capacity:
            self.slots.append(slot)
        else:
            victim_j = _choose_victim(self.positions, requested_j, future_requested)
            victim_index = next(i for i, item in enumerate(self.slots) if item.j == victim_j)
            self.slots[victim_index] = slot
        return (
            result.encoded_amplitudes,
            requested_j,
            source_j,
            before,
            result.saturation_count,
        )


def _abstract_transition_options(
    positions: tuple[int, ...], requested_j: int, capacity: int
) -> tuple[tuple[int, tuple[int, ...]], ...]:
    values = list(positions)
    if requested_j in values:
        return ((0, positions),)
    predecessors = [value for value in values if value < requested_j]
    if predecessors:
        source = max(predecessors)
        values.remove(source)
        values.append(requested_j)
        return ((requested_j - source, tuple(sorted(values))),)
    if len(values) < capacity:
        return ((requested_j, tuple(sorted((*values, requested_j)))),)
    return tuple(
        (
            requested_j,
            tuple(sorted(requested_j if index == victim else value for index, value in enumerate(values))),
        )
        for victim in range(len(values))
    )


@lru_cache(maxsize=65536)
def _rolling_score(
    positions: tuple[int, ...], future: tuple[int, ...], capacity: int
) -> tuple[int, int, tuple[int, ...]]:
    if not future:
        return 0, 0, positions
    requested = future[0]
    candidates = []
    for cost, next_positions in _abstract_transition_options(
        positions, requested, capacity
    ):
        tail_cost, tail_segments, _ = _rolling_score(
            next_positions, future[1:], capacity
        )
        candidates.append(
            (
                cost + tail_cost,
                int(cost > 0) + tail_segments,
                next_positions,
            )
        )
    return min(candidates)


def _choose_victim(
    positions: tuple[int, ...], requested_j: int, future_requested: Sequence[int]
) -> int:
    scored = []
    for victim in positions:
        next_positions = tuple(sorted(requested_j if value == victim else value for value in positions))
        future_cost, segments, final_positions = _rolling_score(
            next_positions,
            tuple(int(value) for value in future_requested[:V098_POLICY_HORIZON]),
            len(positions),
        )
        scored.append((future_cost, segments, final_positions, victim))
    return min(scored)[3]


@dataclass(frozen=True)
class V098AutoAttempt:
    attempt: int
    episode: int
    round_index: int
    m_bound: int
    requested_j: int
    j_random_words: tuple[int, ...]
    checkpoint_positions_before: tuple[int, ...]
    checkpoint_positions_after: tuple[int, ...]
    source_j: int
    physical_iterations: int
    result_index: int | None
    success: bool
    measurement_threshold: int | None
    total_weight: int
    selected_row: int | None
    selected_lane: int | None
    measurement_random_blocks: tuple[int, ...]
    saturation_count: int
    episode_trial_count: int
    episode_L_BBHT: int
    cumulative_L_BBHT: int
    cumulative_physical_iterations: int

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


@dataclass(frozen=True)
class V098AutoResult:
    mode: str
    compatibility: str
    success: bool
    termination_reason: str
    result_index: int | None
    trial_count: int
    L_BBHT: int
    actual_grover_iterations: int
    attempts: tuple[V098AutoAttempt, ...]
    measurement_assumption: str = MEASUREMENT_ASSUMPTION
    checkpoint_assumption: str | None = None

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


@dataclass(frozen=True)
class V098EnumerationResult:
    mode: str
    compatibility: str
    termination_reason: str
    fifo_indices: tuple[int, ...]
    found_count: int
    consecutive_fail_count: int
    trial_count: int
    L_BBHT: int
    actual_grover_iterations: int
    oracle_epoch_changes: int
    attempts: tuple[V098AutoAttempt, ...]

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


class V098AutomaticCore:
    """State-vector automatic BBHT and Enumeration reference."""

    def __init__(self, dataset: V098Dataset, cfg: V098RuntimeConfig) -> None:
        if not cfg.auto_shot:
            raise ValueError("V098AutomaticCore requires auto_shot=True")
        dataset_key = (
            dataset.config.predicate_mode,
            dataset.config.threshold_a,
            dataset.config.threshold_b,
            dataset.config.data_count,
        )
        runtime_key = (
            cfg.predicate_mode,
            cfg.threshold_a,
            cfg.threshold_b,
            cfg.data_count,
        )
        if dataset_key != runtime_key:
            raise ValueError(
                "dataset and runtime predicate/threshold/DATA_COUNT must match"
            )
        self.dataset = dataset
        self.cfg = cfg

    def run_configured(
        self, *, max_results: int | None = None
    ) -> V098AutoResult | V098EnumerationResult:
        """Run the mode selected by CONTROL and ENUM_CFG-equivalent fields."""

        mode = "K4H8" if self.cfg.burst_enable else "NORMAL"
        if self.cfg.enum_enable:
            return self.run_enumeration(mode=mode, max_results=max_results)
        if max_results is not None:
            raise ValueError("max_results is valid only when enum_enable=True")
        return self.run_single(mode=mode)

    def run_single(self, *, mode: str = "NORMAL") -> V098AutoResult:
        normalized = mode.upper()
        if normalized not in {"NORMAL", "K4H8"}:
            raise ValueError("mode must be NORMAL or K4H8")
        target_mask = v098_target_mask(self.dataset.memory_image, self.cfg)
        j_source = V098JRandomSource(self.cfg.seed_j)
        measurement_source = V098MeasurementRandomSource(self.cfg.seed_meas)
        checkpoint = V098CheckpointReference() if normalized == "K4H8" else None
        attempts, success, reason = self._run_episode(
            target_mask,
            j_source,
            measurement_source,
            checkpoint,
            episode=1,
            global_attempt_offset=0,
            cumulative_l=0,
            cumulative_physical=0,
        )
        final = attempts[-1]
        return V098AutoResult(
            mode=normalized,
            compatibility=AUTO_COMPATIBILITY,
            success=success,
            termination_reason=reason,
            result_index=final.result_index if success else None,
            trial_count=len(attempts),
            L_BBHT=final.cumulative_L_BBHT,
            actual_grover_iterations=final.cumulative_physical_iterations,
            attempts=tuple(attempts),
            checkpoint_assumption=(CHECKPOINT_ASSUMPTION if checkpoint else None),
        )

    def run_enumeration(
        self,
        *,
        mode: str = "NORMAL",
        max_results: int | None = None,
    ) -> V098EnumerationResult:
        normalized = mode.upper()
        if normalized not in {"NORMAL", "K4H8"}:
            raise ValueError("mode must be NORMAL or K4H8")
        if max_results is not None and max_results < 1:
            raise ValueError("max_results must be positive")
        j_source = V098JRandomSource(self.cfg.seed_j)
        measurement_source = V098MeasurementRandomSource(self.cfg.seed_meas)
        checkpoint = V098CheckpointReference() if normalized == "K4H8" else None
        found = np.zeros(V098_N_ENTRIES, dtype=np.bool_)
        fifo: list[int] = []
        all_attempts: list[V098AutoAttempt] = []
        consecutive_fail = 0
        epoch_changes = 0
        episode = 0
        reason = "FAIL_REPEAT_LIMIT"

        while consecutive_fail < self.cfg.fail_repeat_limit:
            if max_results is not None and len(fifo) >= max_results:
                reason = "REQUESTED_COUNT"
                break
            episode += 1
            target_mask = v098_target_mask(
                self.dataset.memory_image, self.cfg, found_mask=found
            )
            cumulative_l = all_attempts[-1].cumulative_L_BBHT if all_attempts else 0
            cumulative_physical = (
                all_attempts[-1].cumulative_physical_iterations if all_attempts else 0
            )
            episode_attempts, success, _ = self._run_episode(
                target_mask,
                j_source,
                measurement_source,
                checkpoint,
                episode=episode,
                global_attempt_offset=len(all_attempts),
                cumulative_l=cumulative_l,
                cumulative_physical=cumulative_physical,
            )
            all_attempts.extend(episode_attempts)
            if success:
                index = episode_attempts[-1].result_index
                if index is None or found[index]:
                    raise RuntimeError("Enumeration produced an invalid duplicate success")
                found[index] = True
                fifo.append(index)
                consecutive_fail = 0
                epoch_changes += 1
                if checkpoint is not None:
                    checkpoint.invalidate()
            else:
                consecutive_fail += 1

        final_l = all_attempts[-1].cumulative_L_BBHT if all_attempts else 0
        final_physical = (
            all_attempts[-1].cumulative_physical_iterations if all_attempts else 0
        )
        return V098EnumerationResult(
            mode=normalized,
            compatibility=AUTO_COMPATIBILITY,
            termination_reason=reason,
            fifo_indices=tuple(fifo),
            found_count=len(fifo),
            consecutive_fail_count=consecutive_fail,
            trial_count=len(all_attempts),
            L_BBHT=final_l,
            actual_grover_iterations=final_physical,
            oracle_epoch_changes=epoch_changes,
            attempts=tuple(all_attempts),
        )

    def _run_episode(
        self,
        target_mask: np.ndarray,
        j_source: V098JRandomSource,
        measurement_source: V098MeasurementRandomSource,
        checkpoint: V098CheckpointReference | None,
        *,
        episode: int,
        global_attempt_offset: int,
        cumulative_l: int,
        cumulative_physical: int,
    ) -> tuple[list[V098AutoAttempt], bool, str]:
        attempts: list[V098AutoAttempt] = []
        bounds = v098_m_bounds()
        round_index = 0
        episode_l = 0
        while True:
            bound = bounds[min(round_index, len(bounds) - 1)]
            requested_j, random_words = j_source.draw_uniform(bound)
            future = _predict_future_j(j_source, round_index + 1, V098_POLICY_HORIZON)
            if checkpoint is None:
                before: tuple[int, ...] = ()
                source_j = 0
                core = rtl_run_core(
                    rtl_initial_state(RTL_PROFILE_Q14),
                    target_mask,
                    requested_j,
                    trace_level="NONE",
                    profile=RTL_PROFILE_Q14,
                )
                amplitudes = core.encoded_amplitudes
                physical = requested_j
                saturation_count = core.saturation_count
                after: tuple[int, ...] = ()
            else:
                (
                    amplitudes,
                    physical,
                    source_j,
                    before,
                    saturation_count,
                ) = checkpoint.execute(requested_j, target_mask, future)
                after = checkpoint.positions
            measurement = measure_v098_state(
                amplitudes, target_mask, measurement_source
            )
            episode_l += requested_j
            cumulative_l += requested_j
            cumulative_physical += physical
            attempts.append(
                V098AutoAttempt(
                    attempt=global_attempt_offset + len(attempts) + 1,
                    episode=episode,
                    round_index=round_index,
                    m_bound=bound,
                    requested_j=requested_j,
                    j_random_words=random_words,
                    checkpoint_positions_before=before,
                    checkpoint_positions_after=after,
                    source_j=source_j,
                    physical_iterations=physical,
                    result_index=measurement.result_index,
                    success=measurement.success,
                    measurement_threshold=measurement.threshold,
                    total_weight=measurement.total_weight,
                    selected_row=measurement.selected_row,
                    selected_lane=measurement.selected_lane,
                    measurement_random_blocks=measurement.random_blocks,
                    saturation_count=saturation_count,
                    episode_trial_count=len(attempts) + 1,
                    episode_L_BBHT=episode_l,
                    cumulative_L_BBHT=cumulative_l,
                    cumulative_physical_iterations=cumulative_physical,
                )
            )
            if measurement.success:
                return attempts, True, "SUCCESS"
            if len(attempts) >= self.cfg.shot_cap:
                return attempts, False, "SHOT_LIMIT"
            if episode_l + 1 >= V098_BBHT_LOGICAL_BUDGET:
                return attempts, False, "BUDGET_LIMIT"
            round_index = min(round_index + 1, len(bounds) - 1)


def _predict_future_j(
    source: V098JRandomSource, next_round: int, count: int
) -> tuple[int, ...]:
    clone = source.clone()
    bounds = v098_m_bounds()
    result = []
    round_index = next_round
    for _ in range(count):
        bound = bounds[min(round_index, len(bounds) - 1)]
        requested, _ = clone.draw_uniform(bound)
        result.append(requested)
        round_index = min(round_index + 1, len(bounds) - 1)
    return tuple(result)


def attempts_to_dicts(attempts: Iterable[V098AutoAttempt]) -> list[dict[str, Any]]:
    return [item.to_dict() for item in attempts]
