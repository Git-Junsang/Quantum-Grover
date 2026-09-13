"""Executable BBHT/Enumeration reference for the frozen v0.9.8 contract.

The model implements the documented Q14 BBHT control flow, step-7 J LFSR,
Q1.22 Grover datapath, Born CDF sampling, semantic-preserving checkpoint reuse,
and found-mask Enumeration.

The measurement PRNG and final K3/H3 restricted-B policy follow the frozen RTL
equations. The legacy K4/H4 policy remains available for comparison. Policy
latency, plan-FIFO timing, E4/M2 timing, and cycle_count remain hardware timing
concerns and are intentionally not invented here.
"""

from __future__ import annotations

from dataclasses import asdict, dataclass
from functools import lru_cache
from itertools import combinations
from typing import Any, Iterable, Sequence

import numpy as np

from fixed_point_statevector import RTL_PROFILE_Q14, rtl_initial_state, rtl_run_core
from final_hardware_contract import (
    V098_CHECKPOINT_K,
    V098_LEGACY_CHECKPOINT_K,
    V098_LEGACY_POLICY_HORIZON,
    V098_N_ENTRIES,
    V098_POLICY_HORIZON,
    V098RuntimeConfig,
)
from benchmark_dataset import V098Dataset, v098_target_mask
from bbht_control_semantics import V098_BBHT_LOGICAL_BUDGET, v098_m_bounds


J_FALLBACK_SEED = 0xACE12345
MEAS_FALLBACK_SEED = 0xBEEFC0DE
MEAS_SEED_MIX = 0x9E3779B9
MASK64 = 0xFFFFFFFFFFFFFFFF
AUTO_COMPATIBILITY = "V0.9.8_Q14_BIT_EXACT_ALGORITHM_REFERENCE"
MEASUREMENT_ASSUMPTION = "RTL_EXACT_XORSHIFT64_13_7_17_MIXED_SEED_PRESTATE"
CHECKPOINT_ASSUMPTION = "RTL_RESTRICTED_B_K3_H3_PHYSICAL_ITER_BIT_EXACT_CYCLE_TIMING_EXCLUDED"
LEGACY_CHECKPOINT_ASSUMPTION = "RTL_RESTRICTED_B_K4_H4_PHYSICAL_ITER_BIT_EXACT_CYCLE_TIMING_EXCLUDED"
DRAM_ALL_J_ASSUMPTION = "PROJECTED_DRAM_ALL_J_STATE_LIBRARY_TIMING_EXCLUDED"


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
    """Bit-exact stream for ``grover_meas_prng64_adapter``."""

    def __init__(self, seed: int) -> None:
        checked = int(seed) & 0xFFFFFFFF
        effective = checked if checked else MEAS_FALLBACK_SEED
        self.state = ((effective << 32) | (effective ^ MEAS_SEED_MIX)) & MASK64

    def draw_block(self) -> int:
        block = self.state
        value = block
        value ^= (value << 13) & MASK64
        value ^= value >> 7
        value ^= (value << 17) & MASK64
        self.state = value & MASK64
        return block


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
    """Logical restricted-B rolling K/H checkpoint reference.

    It reproduces checkpoint contents and physical Grover work.  RTL policy
    solver latency and plan-FIFO availability are outside this state model.
    """

    def __init__(
        self,
        capacity: int = V098_CHECKPOINT_K,
        horizon: int = V098_POLICY_HORIZON,
    ) -> None:
        self.capacity = int(capacity)
        self.horizon = int(horizon)
        if not 1 <= self.capacity <= 4:
            raise ValueError("checkpoint capacity must be between 1 and 4")
        if not 1 <= self.horizon <= 8:
            raise ValueError("policy horizon must be between 1 and 8")
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
        before = self.positions
        source_j, next_positions = _select_policy_action(
            before,
            int(requested_j),
            tuple(int(value) for value in future_requested[: self.horizon]),
            self.capacity,
        )
        states = {slot.j: slot.state for slot in self.slots}
        if requested_j in states:
            return states[requested_j].copy(), 0, requested_j, before, 0

        state = (
            states[source_j].copy()
            if source_j in states
            else rtl_initial_state(RTL_PROFILE_Q14)
        )
        generated: dict[int, np.ndarray] = {}
        if 0 in next_positions and 0 not in states:
            generated[0] = rtl_initial_state(RTL_PROFILE_Q14)
        saturation_count = 0
        cursor = source_j
        boundaries = sorted(
            value
            for value in next_positions
            if value not in states and source_j < value <= requested_j
        )
        for boundary in boundaries:
            result = rtl_run_core(
                state,
                target_mask,
                boundary - cursor,
                starting_iteration=cursor,
                trace_level="NONE",
                profile=RTL_PROFILE_Q14,
            )
            state = result.encoded_amplitudes.copy()
            saturation_count += result.saturation_count
            generated[boundary] = state.copy()
            cursor = boundary
        if cursor != requested_j:
            raise RuntimeError("checkpoint policy did not materialize requested endpoint")

        new_slots = []
        for position in next_positions:
            checkpoint_state = states.get(position, generated.get(position))
            if checkpoint_state is None:
                raise RuntimeError(f"missing checkpoint state for j={position}")
            new_slots.append(_CheckpointSlot(position, checkpoint_state.copy()))
        self.slots = new_slots
        return state, requested_j - source_j, source_j, before, saturation_count


class V098AllJCheckpointReference:
    """Projected DRAM policy that retains every materialized Grover state.

    ``psi_0`` is treated as the free reset state.  When a request exceeds the
    largest stored ``j``, the model advances once and stores every intermediate
    state through the requested endpoint.  A later request at or below that
    endpoint is therefore an exact hit.  This changes only physical work and
    storage; it does not change the BBHT request stream or Born measurement.

    DRAM transfer latency and controller overlap are intentionally excluded.
    They require the final RTL/SoC memory interface and must not be invented by
    the algorithmic golden model.
    """

    def __init__(self) -> None:
        self.states: dict[int, np.ndarray] = {
            0: rtl_initial_state(RTL_PROFILE_Q14)
        }

    def invalidate(self) -> None:
        self.states = {0: rtl_initial_state(RTL_PROFILE_Q14)}

    @property
    def positions(self) -> tuple[int, ...]:
        return tuple(sorted(position for position in self.states if position > 0))

    def execute(
        self,
        requested_j: int,
        target_mask: np.ndarray,
        future_requested: Sequence[int],
    ) -> tuple[np.ndarray, int, int, tuple[int, ...], int]:
        del future_requested
        requested = int(requested_j)
        if not 0 <= requested < 128:
            raise ValueError("requested_j must be between 0 and 127")
        before = self.positions
        if requested in self.states:
            return self.states[requested].copy(), 0, requested, before, 0

        source_j = max(position for position in self.states if position < requested)
        state = self.states[source_j].copy()
        saturation_count = 0
        cursor = source_j
        while cursor < requested:
            result = rtl_run_core(
                state,
                target_mask,
                1,
                starting_iteration=cursor,
                trace_level="NONE",
                profile=RTL_PROFILE_Q14,
            )
            cursor += 1
            state = result.encoded_amplitudes.copy()
            saturation_count += result.saturation_count
            self.states[cursor] = state.copy()
        return state, requested - source_j, source_j, before, saturation_count


def _deposit_options(
    capacity: int,
    source: int,
    request: int,
    request_pool: tuple[int, ...],
    held: tuple[int, ...],
) -> tuple[tuple[int, ...], ...]:
    # Restricted-B may materialize only request-pool values strictly between
    # the closest predecessor and the requested endpoint.  Values already in
    # the physical checkpoint state are retained candidates, not deposits.
    in_path = sorted(
        {
            value
            for value in request_pool
            if source < value < request and value not in held
        }
    )
    options: list[tuple[int, ...]] = [(request,)]
    for size in range(1, capacity):
        if size > len(in_path):
            break
        for chosen in combinations(in_path, size):
            options.append(tuple(sorted((*chosen, request))))
    return tuple(options)


def _next_states(
    capacity: int,
    held: tuple[int, ...],
    source: int,
    request: int,
    request_pool: tuple[int, ...],
) -> tuple[tuple[int, ...], ...]:
    result: list[tuple[int, ...]] = []
    for deposit in _deposit_options(capacity, source, request, request_pool, held):
        # RTL excludes only the requested endpoint from the old checkpoint
        # set.  It then retains as many old checkpoints as remaining slots
        # permit, enumerating all combinations when a choice is required.
        keep_pool = tuple(value for value in held if value != request)
        room = capacity - len(deposit)
        if room <= 0:
            result.append(tuple(sorted(deposit)))
        elif len(keep_pool) <= room:
            result.append(tuple(sorted((*keep_pool, *deposit))))
        else:
            for keep in combinations(keep_pool, room):
                result.append(tuple(sorted((*keep, *deposit))))
    return tuple(sorted(set(result)))


@lru_cache(maxsize=1 << 20)
def _window_cost(
    capacity: int,
    held: tuple[int, ...],
    window: tuple[int, ...],
    request_pool: tuple[int, ...],
) -> int:
    if not window:
        return 0
    request, rest = window[0], window[1:]
    source = max((0, *(value for value in held if value <= request)))
    immediate = request - source
    # Non-root RTL frames minimize physical cost only.  Segment count and
    # canonical tuple ordering are deliberately not recursive tie-breaks.
    return int(
        min(
            immediate
            + _window_cost(capacity, state, rest, request_pool)
            for state in _next_states(
                capacity, held, source, request, request_pool
            )
        )
    )


def _select_policy_action(
    held: tuple[int, ...],
    request: int,
    future: tuple[int, ...],
    capacity: int,
) -> tuple[int, tuple[int, ...]]:
    request_pool = tuple(dict.fromkeys((request, *future)))
    source = max((0, *(value for value in held if value <= request)))
    immediate = request - source
    best: tuple[float, float, tuple[int, ...]] = (
        float("inf"),
        float("inf"),
        (),
    )
    chosen_state = held
    for state in _next_states(capacity, held, source, request, request_pool):
        tail_cost = _window_cost(capacity, state, future, request_pool)
        # Root-only tie-break from grover_policy.v:
        #   (total physical cost, immediate segment count, sorted S').
        segments = 1 + sum(source < value < request for value in state)
        candidate = (immediate + tail_cost, segments, state)
        if candidate < best:
            best = candidate
            chosen_state = state
    return source, chosen_state


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
    """State-vector BBHT and Enumeration reference.

    The historical class name is retained as a source-compatible API alias.
    """

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

        mode = "K3H3" if self.cfg.burst_enable else "NORMAL"
        if self.cfg.enum_enable:
            return self.run_enumeration(mode=mode, max_results=max_results)
        if max_results is not None:
            raise ValueError("max_results is valid only when enum_enable=True")
        return self.run_single(mode=mode)

    def run_single(self, *, mode: str = "NORMAL") -> V098AutoResult:
        normalized = _normalize_mode(mode)
        target_mask = v098_target_mask(self.dataset.memory_image, self.cfg)
        j_source = V098JRandomSource(self.cfg.seed_j)
        measurement_source = V098MeasurementRandomSource(self.cfg.seed_meas)
        checkpoint = _checkpoint_for_mode(normalized)
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
            checkpoint_assumption=_checkpoint_assumption(normalized),
        )

    def run_enumeration(
        self,
        *,
        mode: str = "NORMAL",
        max_results: int | None = None,
    ) -> V098EnumerationResult:
        normalized = _normalize_mode(mode)
        if max_results is not None and max_results < 1:
            raise ValueError("max_results must be positive")
        j_source = V098JRandomSource(self.cfg.seed_j)
        measurement_source = V098MeasurementRandomSource(self.cfg.seed_meas)
        checkpoint = _checkpoint_for_mode(normalized)
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
                # The RTL has one deterministic all-found condition: every
                # valid data address has entered found_mask.  It terminates
                # immediately after accepting the last FIFO result.
                if len(fifo) >= self.cfg.data_count:
                    reason = "ALL_VALID_DATA_FOUND"
                    break
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
        checkpoint: V098CheckpointReference | V098AllJCheckpointReference | None,
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
            future_count = checkpoint.horizon if isinstance(
                checkpoint, V098CheckpointReference
            ) else 0
            future = _predict_future_j(j_source, round_index + 1, future_count)
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


def _normalize_mode(mode: str) -> str:
    normalized = mode.upper()
    if normalized == "K4H8":
        return "K4H4"
    if normalized == "K3H3_E4_M2":
        return "K3H3"
    if normalized not in {"NORMAL", "K4H4", "K3H3", "DRAM_ALL_J"}:
        raise ValueError("mode must be NORMAL, K4H4, K3H3, or DRAM_ALL_J")
    return normalized


def _checkpoint_for_mode(
    mode: str,
) -> V098CheckpointReference | V098AllJCheckpointReference | None:
    if mode == "NORMAL":
        return None
    if mode == "K4H4":
        return V098CheckpointReference(
            capacity=V098_LEGACY_CHECKPOINT_K,
            horizon=V098_LEGACY_POLICY_HORIZON,
        )
    if mode == "K3H3":
        return V098CheckpointReference()
    if mode == "DRAM_ALL_J":
        return V098AllJCheckpointReference()
    raise ValueError(f"unsupported checkpoint mode: {mode}")


def _checkpoint_assumption(mode: str) -> str | None:
    if mode == "K4H4":
        return LEGACY_CHECKPOINT_ASSUMPTION
    if mode == "K3H3":
        return CHECKPOINT_ASSUMPTION
    if mode == "DRAM_ALL_J":
        return DRAM_ALL_J_ASSUMPTION
    return None


# Preferred public name.  V098AutomaticCore remains for existing callers.
V098BBHTCore = V098AutomaticCore


def attempts_to_dicts(attempts: Iterable[V098AutoAttempt]) -> list[dict[str, Any]]:
    return [item.to_dict() for item in attempts]
