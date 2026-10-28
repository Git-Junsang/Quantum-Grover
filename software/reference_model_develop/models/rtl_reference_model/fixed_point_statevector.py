from __future__ import annotations

from dataclasses import dataclass, field
from fractions import Fraction
from math import ceil
from numbers import Integral
from time import perf_counter_ns
from typing import Any

import numpy as np


RTL_DEFAULT_SHOT_CAP = 100
RTL_FALLBACK_J = 0xACE12345
RTL_FALLBACK_MEAS = 0xBEEFC0DE

RTL_PREDICATES = {"LT", "GT", "EQ", "RANGE"}
RTL_TRACE_LEVELS = {"NONE", "SUMMARY", "FULL"}


def _build_m_bounds(qubits: int) -> tuple[int, ...]:
    maximum = 1 << (qubits // 2)
    value = Fraction(1, 1)
    bounds: list[int] = []
    while True:
        bound = min(ceil(value), maximum)
        bounds.append(bound)
        if bound == maximum:
            return tuple(bounds)
        value = min(value * Fraction(6, 5), Fraction(maximum, 1))


@dataclass(frozen=True)
class RtlHardwareProfile:
    """Synthesis-time profile shared by the Q14 and projected Q16 models."""

    name: str
    qubits: int
    parallelism: int = 32
    data_w: int = 16
    frac_bits: int = 22
    amp_w: int = 23

    def __post_init__(self) -> None:
        if self.qubits not in {14, 16}:
            raise ValueError("the current RTL family supports Q14 or Q16")
        if self.parallelism != 32:
            raise ValueError("the current RTL family is frozen to P32")
        if self.frac_bits != 22 or self.amp_w != 23:
            raise ValueError("the current RTL family is frozen to signed Q1.22")

    @property
    def n(self) -> int:
        return 1 << self.qubits

    @property
    def logp(self) -> int:
        return self.parallelism.bit_length() - 1

    @property
    def rows(self) -> int:
        return self.n // self.parallelism

    @property
    def index_w(self) -> int:
        return self.qubits

    @property
    def data_count_w(self) -> int:
        return self.qubits + 1

    @property
    def row_addr_w(self) -> int:
        return self.qubits - self.logp

    @property
    def partial_sum_w(self) -> int:
        return self.amp_w + self.logp

    @property
    def acc_w(self) -> int:
        return self.amp_w + self.qubits + 2

    @property
    def two_mean_w(self) -> int:
        return self.amp_w + 2

    @property
    def diff_w(self) -> int:
        return self.amp_w + 2

    @property
    def square_w(self) -> int:
        return 2 * self.amp_w

    @property
    def row_weight_w(self) -> int:
        return self.square_w + self.logp

    @property
    def total_weight_w(self) -> int:
        return self.square_w + self.qubits

    @property
    def j_w(self) -> int:
        return self.qubits // 2

    @property
    def m_bound_w(self) -> int:
        return self.j_w + 1

    @property
    def sqrt_n(self) -> int:
        return 1 << (self.qubits // 2)

    @property
    def initial_amp_raw(self) -> int:
        return 1 << (self.frac_bits - self.qubits // 2)

    @property
    def amp_max(self) -> int:
        return (1 << (self.amp_w - 1)) - 1

    @property
    def amp_min(self) -> int:
        return -self.amp_max

    @property
    def bbht_budget(self) -> int:
        return (9 * self.sqrt_n) // 2

    @property
    def m_bounds(self) -> tuple[int, ...]:
        return _build_m_bounds(self.qubits)


RTL_PROFILE_Q14 = RtlHardwareProfile(name="RTL_V07G_Q14", qubits=14)
RTL_PROFILE_Q16 = RtlHardwareProfile(name="RTL_Q16_PROJECTED", qubits=16)

# Backward-compatible aliases for the delivered v0.7g Q14 handoff.
RTL_Q = RTL_PROFILE_Q14.qubits
RTL_N = RTL_PROFILE_Q14.n
RTL_P = RTL_PROFILE_Q14.parallelism
RTL_LOGP = RTL_PROFILE_Q14.logp
RTL_ROWS = RTL_PROFILE_Q14.rows
RTL_DATA_W = RTL_PROFILE_Q14.data_w
RTL_FRAC_BITS = RTL_PROFILE_Q14.frac_bits
RTL_AMP_W = RTL_PROFILE_Q14.amp_w
RTL_ACC_W = RTL_PROFILE_Q14.acc_w
RTL_TWO_MEAN_W = RTL_PROFILE_Q14.two_mean_w
RTL_DIFF_W = RTL_PROFILE_Q14.diff_w
RTL_J_W = RTL_PROFILE_Q14.j_w
RTL_INIT_AMP_RAW = RTL_PROFILE_Q14.initial_amp_raw
RTL_AMP_MAX = RTL_PROFILE_Q14.amp_max
RTL_AMP_MIN = RTL_PROFILE_Q14.amp_min
RTL_BBHT_BUDGET = RTL_PROFILE_Q14.bbht_budget
RTL_M_BOUNDS = RTL_PROFILE_Q14.m_bounds


@dataclass(frozen=True)
class RtlV07gConfig:
    """Runtime inputs visible at the v0.7g Main-IP boundary."""

    predicate_mode: str = "EQ"
    threshold_a: int = 0
    threshold_b: int = 0
    data_count: int = 4096
    auto_shot: bool = False
    j_target: int = 1
    burst_enable: bool = False
    shot_cap: int = RTL_DEFAULT_SHOT_CAP
    seed_j: int = 0x10203040
    seed_meas: int = 0x12345078
    trace_level: str = "SUMMARY"
    profile: RtlHardwareProfile = RTL_PROFILE_Q14

    def __post_init__(self) -> None:
        object.__setattr__(self, "predicate_mode", self.predicate_mode.upper())
        object.__setattr__(self, "trace_level", self.trace_level.upper())
        if not isinstance(self.profile, RtlHardwareProfile):
            raise TypeError("profile must be an RtlHardwareProfile")
        if self.predicate_mode not in RTL_PREDICATES:
            raise ValueError(f"predicate_mode must be one of {sorted(RTL_PREDICATES)}")
        _validate_signed16("threshold_a", self.threshold_a)
        _validate_signed16("threshold_b", self.threshold_b)
        if not 1 <= self.data_count <= self.profile.n:
            raise ValueError(
                f"data_count must be between 1 and {self.profile.n}"
            )
        if not isinstance(self.auto_shot, bool):
            raise TypeError("auto_shot must be boolean")
        if not isinstance(self.burst_enable, bool):
            raise TypeError("burst_enable must be boolean")
        if not 0 <= self.j_target < (1 << self.profile.j_w):
            raise ValueError(
                f"j_target must be between 0 and {(1 << self.profile.j_w) - 1}"
            )
        if not 1 <= self.shot_cap < (1 << 16):
            raise ValueError("shot_cap must fit unsigned 16-bit and be nonzero")
        for name, seed in (("seed_j", self.seed_j), ("seed_meas", self.seed_meas)):
            if isinstance(seed, bool) or not isinstance(seed, Integral):
                raise TypeError(f"{name} must be an integer")
            if not 0 <= int(seed) <= 0xFFFFFFFF:
                raise ValueError(f"{name} must fit unsigned 32-bit")
        if self.trace_level not in RTL_TRACE_LEVELS:
            raise ValueError(f"trace_level must be one of {sorted(RTL_TRACE_LEVELS)}")

    @property
    def semantic_key(self) -> tuple[str, int, int, int]:
        return (
            self.predicate_mode,
            self.threshold_a,
            self.threshold_b,
            self.data_count,
        )


@dataclass(frozen=True)
class RtlIterationTrace:
    """Integer datapath values for one physical Grover iteration."""

    iteration: int
    global_sum: int
    two_mean: int
    saturation_count: int
    row_partial_sums: np.ndarray | None = None
    amplitudes_before: np.ndarray | None = None
    amplitudes_after_oracle: np.ndarray | None = None
    amplitudes_after_diffusion: np.ndarray | None = None

    def to_dict(self) -> dict[str, Any]:
        return {
            "iteration": self.iteration,
            "global_sum": self.global_sum,
            "two_mean": self.two_mean,
            "saturation_count": self.saturation_count,
            "row_partial_sums": _optional_array_to_list(self.row_partial_sums),
            "amplitudes_before": _optional_array_to_list(self.amplitudes_before),
            "amplitudes_after_oracle": _optional_array_to_list(
                self.amplitudes_after_oracle
            ),
            "amplitudes_after_diffusion": _optional_array_to_list(
                self.amplitudes_after_diffusion
            ),
        }


@dataclass(frozen=True)
class RtlCoreResult:
    encoded_amplitudes: np.ndarray
    physical_iterations: int
    saturation_count: int
    trace: list[RtlIterationTrace]


@dataclass(frozen=True)
class RtlMeasurementResult:
    result_index: int | None
    selected_row: int | None
    selected_lane: int | None
    threshold: int | None
    total_weight: int
    random_draws: tuple[int, ...]
    success: bool
    expected_success_probability: float


@dataclass(frozen=True)
class RtlAttemptRecord:
    attempt: int
    m_bound: int
    requested_j: int
    physical_iterations: int
    cumulative_L_BBHT: int
    cumulative_physical_iterations: int
    result_index: int | None
    success: bool
    total_weight: int
    measurement_threshold: int | None
    selected_row: int | None
    selected_lane: int | None
    saturation_count: int
    measurement_random_draws: tuple[int, ...] = ()
    trace: list[RtlIterationTrace] = field(default_factory=list)

    def to_dict(self) -> dict[str, Any]:
        return {
            "attempt": self.attempt,
            "m_bound": self.m_bound,
            "requested_j": self.requested_j,
            "physical_iterations": self.physical_iterations,
            "cumulative_L_BBHT": self.cumulative_L_BBHT,
            "cumulative_physical_iterations": self.cumulative_physical_iterations,
            "result_index": self.result_index,
            "success": self.success,
            "total_weight": self.total_weight,
            "measurement_threshold": self.measurement_threshold,
            "selected_row": self.selected_row,
            "selected_lane": self.selected_lane,
            "saturation_count": self.saturation_count,
            "measurement_random_draws": list(self.measurement_random_draws),
            "trace": [item.to_dict() for item in self.trace],
        }


@dataclass(frozen=True)
class RtlRunTiming:
    oracle_mask_ms: float
    scheduler_ms: float
    core_ms: float
    measurement_ms: float
    controller_ms: float
    total_ms: float

    def to_dict(self) -> dict[str, float]:
        return {
            "oracle_mask_ms": self.oracle_mask_ms,
            "scheduler_ms": self.scheduler_ms,
            "core_ms": self.core_ms,
            "measurement_ms": self.measurement_ms,
            "controller_ms": self.controller_ms,
            "total_ms": self.total_ms,
        }


@dataclass(frozen=True)
class RtlSearchResult:
    success: bool
    result_index: int | None
    result_value: int | None
    termination_reason: str
    trial_count: int
    L_BBHT: int
    actual_grover_iterations: int
    attempts: list[RtlAttemptRecord]
    final_encoded_amplitudes: np.ndarray | None
    timing: RtlRunTiming

    def to_dict(
        self,
        *,
        include_amplitudes: bool = False,
        include_timing: bool = False,
    ) -> dict[str, Any]:
        payload = {
            "success": self.success,
            "result_index": self.result_index,
            "result_value": self.result_value,
            "termination_reason": self.termination_reason,
            "trial_count": self.trial_count,
            "L_BBHT": self.L_BBHT,
            "actual_grover_iterations": self.actual_grover_iterations,
            "attempts": [item.to_dict() for item in self.attempts],
            "final_encoded_amplitudes": (
                self.final_encoded_amplitudes.astype(int).tolist()
                if include_amplitudes and self.final_encoded_amplitudes is not None
                else None
            ),
        }
        if include_timing:
            payload["timing"] = self.timing.to_dict()
        return payload


class RtlLfsr32:
    """The exact pre-edge-state 32-bit LFSR used by v0.7g."""

    def __init__(self, seed: int, fallback_seed: int) -> None:
        checked_seed = _validate_u32("seed", seed)
        self._fallback_seed = _validate_u32("fallback_seed", fallback_seed)
        self.state = checked_seed if checked_seed != 0 else self._fallback_seed

    def draw(self) -> int:
        value = self.state
        feedback = (
            ((value >> 31) ^ (value >> 21) ^ (value >> 1) ^ value) & 1
        )
        self.state = ((value << 1) & 0xFFFFFFFF) | feedback
        return value


class RtlV07gModel:
    """Stateful bit-exact model of the v0.7g Main IP functional contract."""

    def __init__(self, profile: RtlHardwareProfile = RTL_PROFILE_Q14) -> None:
        if not isinstance(profile, RtlHardwareProfile):
            raise TypeError("profile must be an RtlHardwareProfile")
        self.profile = profile
        self._values = np.zeros(profile.n, dtype=np.int16)
        self._loaded_count = 0
        self._cache_valid = False
        self._cache_j = 0
        self._cache_state: np.ndarray | None = None
        self._semantic_key: tuple[str, int, int, int, bytes] | None = None

    @property
    def cache_valid(self) -> bool:
        return self._cache_valid

    @property
    def cache_j(self) -> int:
        return self._cache_j

    def load_dataset(self, values: np.ndarray, *, data_count: int | None = None) -> None:
        checked = np.asarray(values)
        if checked.ndim != 1:
            raise ValueError("values must be a one-dimensional array")
        if not np.issubdtype(checked.dtype, np.integer):
            raise TypeError("values must contain integers")
        count = int(checked.size if data_count is None else data_count)
        if not 1 <= count <= self.profile.n:
            raise ValueError(
                f"data_count must be between 1 and {self.profile.n}"
            )
        if checked.size != count:
            raise ValueError("values length must equal data_count")
        if np.any(checked < -32768) or np.any(checked > 32767):
            raise ValueError("all input values must fit signed 16-bit")

        self._values.fill(0)
        self._values[:count] = checked.astype(np.int16, copy=False)
        self._loaded_count = count
        self.invalidate_cache()

    def load_memory_image(self, values: np.ndarray, *, data_count: int) -> None:
        """Load all N slots while only data_count slots remain semantically valid."""

        checked = np.asarray(values)
        if checked.ndim != 1 or checked.size != self.profile.n:
            raise ValueError(f"memory image must contain {self.profile.n} values")
        if not np.issubdtype(checked.dtype, np.integer):
            raise TypeError("memory image must contain integers")
        if not 1 <= data_count <= self.profile.n:
            raise ValueError(
                f"data_count must be between 1 and {self.profile.n}"
            )
        if np.any(checked < -32768) or np.any(checked > 32767):
            raise ValueError("all input values must fit signed 16-bit")

        self._values[:] = checked.astype(np.int16, copy=False)
        self._loaded_count = int(data_count)
        self.invalidate_cache()

    def invalidate_cache(self) -> None:
        self._cache_valid = False
        self._cache_j = 0
        self._cache_state = None

    def run(
        self,
        cfg: RtlV07gConfig,
        *,
        exclude_mask: np.ndarray | None = None,
    ) -> RtlSearchResult:
        run_start_ns = perf_counter_ns()
        if self._loaded_count == 0:
            raise RuntimeError("a dataset must be loaded before run")
        if cfg.data_count != self._loaded_count:
            raise ValueError("cfg.data_count must equal the loaded dataset count")
        if cfg.profile != self.profile:
            raise ValueError("cfg.profile must match the model hardware profile")
        checked_exclude_mask = (
            np.zeros(self.profile.n, dtype=np.bool_)
            if exclude_mask is None
            else _validate_mask(exclude_mask, self.profile)
        )
        semantic_key = (
            *cfg.semantic_key,
            np.packbits(checked_exclude_mask, bitorder="little").tobytes(),
        )
        if self._semantic_key is not None and semantic_key != self._semantic_key:
            self.invalidate_cache()
        self._semantic_key = semantic_key

        mask_start_ns = perf_counter_ns()
        target_mask = rtl_target_mask(
            self._values,
            cfg,
            exclude_mask=checked_exclude_mask,
        )
        mask_ns = perf_counter_ns() - mask_start_ns
        lfsr_j = RtlLfsr32(cfg.seed_j, RTL_FALLBACK_J)
        lfsr_meas = RtlLfsr32(cfg.seed_meas, RTL_FALLBACK_MEAS)

        attempts: list[RtlAttemptRecord] = []
        round_idx = 0
        cumulative_l = 0
        cumulative_physical = 0
        termination_reason = "UNSPECIFIED"
        scheduler_ns = 0
        core_ns = 0
        measurement_ns = 0

        while True:
            scheduler_start_ns = perf_counter_ns()
            m_bound = self.profile.m_bounds[round_idx]
            requested_j = (
                rtl_draw_j(lfsr_j, m_bound, profile=self.profile)
                if cfg.auto_shot
                else cfg.j_target
            )
            cumulative_l += requested_j
            scheduler_ns += perf_counter_ns() - scheduler_start_ns

            core_start_ns = perf_counter_ns()
            core = self._run_requested_j(
                requested_j,
                target_mask,
                burst_enable=cfg.burst_enable,
                trace_level=cfg.trace_level,
            )
            core_ns += perf_counter_ns() - core_start_ns
            cumulative_physical += core.physical_iterations
            measurement_start_ns = perf_counter_ns()
            measurement = rtl_born_measure(
                core.encoded_amplitudes,
                target_mask,
                lfsr_meas,
                profile=self.profile,
            )
            measurement_ns += perf_counter_ns() - measurement_start_ns
            attempts.append(
                RtlAttemptRecord(
                    attempt=len(attempts) + 1,
                    m_bound=m_bound,
                    requested_j=requested_j,
                    physical_iterations=core.physical_iterations,
                    cumulative_L_BBHT=cumulative_l,
                    cumulative_physical_iterations=cumulative_physical,
                    result_index=measurement.result_index,
                    success=measurement.success,
                    total_weight=measurement.total_weight,
                    measurement_threshold=measurement.threshold,
                    selected_row=measurement.selected_row,
                    selected_lane=measurement.selected_lane,
                    saturation_count=core.saturation_count,
                    measurement_random_draws=measurement.random_draws,
                    trace=core.trace,
                )
            )

            if measurement.success:
                termination_reason = "SUCCESS"
                break
            if len(attempts) >= cfg.shot_cap:
                termination_reason = "SHOT_LIMIT"
                break
            if cumulative_l + 1 >= self.profile.bbht_budget:
                termination_reason = "BUDGET_LIMIT"
                break
            if not cfg.auto_shot:
                termination_reason = "MANUAL_FAIL"
                break
            round_idx = min(round_idx + 1, len(self.profile.m_bounds) - 1)

        final_measurement = attempts[-1]
        success = final_measurement.success
        index = final_measurement.result_index if success else None
        total_ns = perf_counter_ns() - run_start_ns
        measured_ns = mask_ns + scheduler_ns + core_ns + measurement_ns
        return RtlSearchResult(
            success=success,
            result_index=index,
            result_value=int(self._values[index]) if index is not None else None,
            termination_reason=termination_reason,
            trial_count=len(attempts),
            L_BBHT=cumulative_l,
            actual_grover_iterations=cumulative_physical,
            attempts=attempts,
            final_encoded_amplitudes=(
                self._cache_state.copy() if self._cache_state is not None else None
            ),
            timing=RtlRunTiming(
                oracle_mask_ms=_ns_to_ms(mask_ns),
                scheduler_ms=_ns_to_ms(scheduler_ns),
                core_ms=_ns_to_ms(core_ns),
                measurement_ms=_ns_to_ms(measurement_ns),
                controller_ms=_ns_to_ms(max(total_ns - measured_ns, 0)),
                total_ms=_ns_to_ms(total_ns),
            ),
        )

    def _run_requested_j(
        self,
        requested_j: int,
        target_mask: np.ndarray,
        *,
        burst_enable: bool,
        trace_level: str,
    ) -> RtlCoreResult:
        usable = (
            burst_enable
            and self._cache_valid
            and self._cache_state is not None
            and requested_j >= self._cache_j
        )
        if usable:
            start_state = self._cache_state.copy()
            starting_iteration = self._cache_j
            physical_iterations = requested_j - self._cache_j
        else:
            start_state = rtl_initial_state(self.profile)
            starting_iteration = 0
            physical_iterations = requested_j

        core = rtl_run_core(
            start_state,
            target_mask,
            physical_iterations,
            starting_iteration=starting_iteration,
            trace_level=trace_level,
            profile=self.profile,
        )
        self._cache_state = core.encoded_amplitudes.copy()
        self._cache_j = requested_j
        self._cache_valid = True
        return core


def rtl_initial_state(
    profile: RtlHardwareProfile = RTL_PROFILE_Q14,
) -> np.ndarray:
    return np.full(profile.n, profile.initial_amp_raw, dtype=np.int64)


def rtl_target_mask(
    values: np.ndarray,
    cfg: RtlV07gConfig,
    *,
    exclude_mask: np.ndarray | None = None,
) -> np.ndarray:
    checked = np.asarray(values)
    if checked.ndim != 1 or checked.size != cfg.profile.n:
        raise ValueError(
            "values must be a one-dimensional array of length "
            f"{cfg.profile.n}"
        )
    signed_values = checked.astype(np.int64, copy=False)
    if cfg.predicate_mode == "LT":
        matched = signed_values < cfg.threshold_a
    elif cfg.predicate_mode == "GT":
        matched = signed_values > cfg.threshold_a
    elif cfg.predicate_mode == "EQ":
        matched = signed_values == cfg.threshold_a
    else:
        matched = (signed_values > cfg.threshold_a) & (
            signed_values < cfg.threshold_b
        )
    valid = np.arange(cfg.profile.n, dtype=np.int64) < cfg.data_count
    result = np.asarray(matched & valid, dtype=np.bool_)
    if exclude_mask is not None:
        result &= ~_validate_mask(exclude_mask, cfg.profile)
    return result


def rtl_run_core(
    encoded_initial: np.ndarray,
    target_mask: np.ndarray,
    iterations: int,
    *,
    starting_iteration: int = 0,
    trace_level: str = "SUMMARY",
    profile: RtlHardwareProfile = RTL_PROFILE_Q14,
) -> RtlCoreResult:
    encoded = _validate_encoded_state(encoded_initial, profile)
    mask = _validate_mask(target_mask, profile)
    if isinstance(iterations, bool) or not isinstance(iterations, Integral):
        raise TypeError("iterations must be an integer")
    if iterations < 0:
        raise ValueError("iterations cannot be negative")
    level = trace_level.upper()
    if level not in RTL_TRACE_LEVELS:
        raise ValueError(f"trace_level must be one of {sorted(RTL_TRACE_LEVELS)}")

    traces: list[RtlIterationTrace] = []
    total_saturations = 0
    for local_iteration in range(1, int(iterations) + 1):
        before = encoded.copy()
        after_oracle = before.copy()
        after_oracle[mask] = -after_oracle[mask]

        rows = after_oracle.reshape(profile.rows, profile.parallelism)
        row_partial_sums = np.sum(rows, axis=1, dtype=np.int64)
        _validate_signed_width(
            row_partial_sums,
            profile.partial_sum_w,
            "row partial sum",
        )
        global_sum = int(np.sum(row_partial_sums, dtype=np.int64))
        _validate_signed_scalar(global_sum, profile.acc_w, "global sum")

        two_mean = rtl_round_shift_ties_even(global_sum, profile.qubits - 1)
        _validate_signed_scalar(two_mean, profile.two_mean_w, "two_mean")
        diff = np.asarray(two_mean - after_oracle, dtype=np.int64)
        _validate_signed_width(diff, profile.diff_w, "diffusion intermediate")
        sat_mask = (diff > profile.amp_max) | (diff < profile.amp_min)
        saturation_count = int(np.count_nonzero(sat_mask))
        after_diffusion = np.clip(diff, profile.amp_min, profile.amp_max).astype(
            np.int64,
            copy=False,
        )
        total_saturations += saturation_count

        if level != "NONE":
            full = level == "FULL"
            traces.append(
                RtlIterationTrace(
                    iteration=starting_iteration + local_iteration,
                    global_sum=global_sum,
                    two_mean=two_mean,
                    saturation_count=saturation_count,
                    row_partial_sums=(row_partial_sums.copy() if full else None),
                    amplitudes_before=(before if full else None),
                    amplitudes_after_oracle=(after_oracle if full else None),
                    amplitudes_after_diffusion=(
                        after_diffusion.copy() if full else None
                    ),
                )
            )
        encoded = after_diffusion

    return RtlCoreResult(
        encoded_amplitudes=encoded.copy(),
        physical_iterations=int(iterations),
        saturation_count=total_saturations,
        trace=traces,
    )


def rtl_round_shift_ties_even(value: int, shift: int) -> int:
    """Arithmetic right shift rounded to nearest, ties to an even result."""

    if isinstance(value, bool) or not isinstance(value, Integral):
        raise TypeError("value must be an integer")
    if isinstance(shift, bool) or not isinstance(shift, Integral):
        raise TypeError("shift must be an integer")
    if shift < 0:
        raise ValueError("shift cannot be negative")
    if shift == 0:
        return int(value)

    denominator = 1 << int(shift)
    quotient = int(value) // denominator
    remainder = int(value) - quotient * denominator
    doubled = remainder << 1
    if doubled > denominator or (doubled == denominator and (quotient & 1)):
        quotient += 1
    return quotient


def rtl_symmetric_saturate(
    value: int,
    profile: RtlHardwareProfile = RTL_PROFILE_Q14,
) -> tuple[int, bool]:
    checked = int(value)
    if checked > profile.amp_max:
        return profile.amp_max, True
    if checked < profile.amp_min:
        return profile.amp_min, True
    return checked, False


def rtl_draw_j(
    lfsr: RtlLfsr32,
    m_bound: int,
    *,
    profile: RtlHardwareProfile = RTL_PROFILE_Q14,
) -> int:
    if not 1 <= m_bound <= profile.sqrt_n:
        raise ValueError(
            f"m_bound must be between 1 and {profile.sqrt_n}"
        )
    k = (m_bound - 1).bit_length()
    mask = (1 << k) - 1 if k else 0
    while True:
        candidate = (lfsr.draw() & 0xFF) & mask
        if candidate < m_bound:
            return candidate


def rtl_born_measure(
    encoded_amplitudes: np.ndarray,
    target_mask: np.ndarray,
    lfsr: RtlLfsr32,
    *,
    profile: RtlHardwareProfile = RTL_PROFILE_Q14,
) -> RtlMeasurementResult:
    encoded = _validate_encoded_state(encoded_amplitudes, profile)
    mask = _validate_mask(target_mask, profile)
    rows = encoded.reshape(profile.rows, profile.parallelism)
    squares = np.asarray(rows * rows, dtype=np.int64)
    row_weights = np.sum(squares, axis=1, dtype=np.int64)
    total_weight = int(np.sum(row_weights, dtype=np.int64))
    _validate_unsigned_scalar(total_weight, profile.total_weight_w, "total weight")

    if total_weight == 0:
        return RtlMeasurementResult(
            result_index=None,
            selected_row=None,
            selected_lane=None,
            threshold=None,
            total_weight=0,
            random_draws=(),
            success=False,
            expected_success_probability=0.0,
        )

    draws: list[int] = []
    if total_weight == 1:
        threshold = 0
    else:
        k = (total_weight - 1).bit_length()
        low_mask = (1 << k) - 1
        while True:
            high = lfsr.draw()
            low = lfsr.draw()
            draws.extend((high, low))
            candidate = (((high << 32) | low) & low_mask)
            if candidate < total_weight:
                threshold = candidate
                break

    row_cdf = np.cumsum(row_weights, dtype=np.int64)
    selected_row = int(np.searchsorted(row_cdf, threshold, side="right"))
    cumulative_before = int(row_cdf[selected_row - 1]) if selected_row else 0
    local_threshold = threshold - cumulative_before
    lane_cdf = np.cumsum(squares[selected_row], dtype=np.int64)
    selected_lane = int(np.searchsorted(lane_cdf, local_threshold, side="right"))
    result_index = selected_row * profile.parallelism + selected_lane
    target_weight = int(np.sum((encoded[mask] * encoded[mask]), dtype=np.int64))
    return RtlMeasurementResult(
        result_index=result_index,
        selected_row=selected_row,
        selected_lane=selected_lane,
        threshold=threshold,
        total_weight=total_weight,
        random_draws=tuple(draws),
        success=bool(mask[result_index]),
        expected_success_probability=target_weight / total_weight,
    )


def p32_bank_row(
    index: int,
    profile: RtlHardwareProfile = RTL_PROFILE_Q14,
) -> tuple[int, int]:
    if isinstance(index, bool) or not isinstance(index, Integral):
        raise TypeError("index must be an integer")
    if not 0 <= int(index) < profile.n:
        raise ValueError(f"index must be between 0 and {profile.n - 1}")
    return (
        int(index) & (profile.parallelism - 1),
        int(index) >> profile.logp,
    )


def _validate_encoded_state(
    values: np.ndarray,
    profile: RtlHardwareProfile,
) -> np.ndarray:
    checked = np.asarray(values)
    if checked.ndim != 1 or checked.size != profile.n:
        raise ValueError(f"encoded amplitudes must have length {profile.n}")
    if not np.issubdtype(checked.dtype, np.integer):
        raise TypeError("encoded amplitudes must contain integers")
    converted = checked.astype(np.int64, copy=True)
    if np.any(converted < profile.amp_min) or np.any(converted > profile.amp_max):
        raise ValueError("encoded amplitude is outside the symmetric Q1.22 range")
    return converted


def _validate_mask(mask: np.ndarray, profile: RtlHardwareProfile) -> np.ndarray:
    checked = np.asarray(mask)
    if checked.ndim != 1 or checked.size != profile.n:
        raise ValueError(f"target_mask must have length {profile.n}")
    if checked.dtype != np.bool_:
        raise TypeError("target_mask must have boolean dtype")
    return checked


def _validate_signed_width(values: np.ndarray, width: int, label: str) -> None:
    minimum = -(1 << (width - 1))
    maximum = (1 << (width - 1)) - 1
    if np.any(values < minimum) or np.any(values > maximum):
        raise OverflowError(f"{label} exceeded signed {width}-bit range")


def _validate_signed_scalar(value: int, width: int, label: str) -> None:
    minimum = -(1 << (width - 1))
    maximum = (1 << (width - 1)) - 1
    if not minimum <= value <= maximum:
        raise OverflowError(f"{label} exceeded signed {width}-bit range")


def _validate_unsigned_scalar(value: int, width: int, label: str) -> None:
    if not 0 <= value < (1 << width):
        raise OverflowError(f"{label} exceeded unsigned {width}-bit range")


def _validate_signed16(name: str, value: int) -> None:
    if isinstance(value, bool) or not isinstance(value, Integral):
        raise TypeError(f"{name} must be an integer")
    if not -32768 <= int(value) <= 32767:
        raise ValueError(f"{name} must fit signed 16-bit")


def _validate_u32(name: str, value: int) -> int:
    if isinstance(value, bool) or not isinstance(value, Integral):
        raise TypeError(f"{name} must be an integer")
    converted = int(value)
    if not 0 <= converted <= 0xFFFFFFFF:
        raise ValueError(f"{name} must fit unsigned 32-bit")
    return converted


def _optional_array_to_list(values: np.ndarray | None) -> list[int] | None:
    return values.astype(int).tolist() if values is not None else None


def _ns_to_ms(value: int) -> float:
    return float(value) / 1_000_000.0
