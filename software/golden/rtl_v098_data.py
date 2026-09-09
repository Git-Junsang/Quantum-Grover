"""Exact-M dataset construction and Oracle ground truth for v0.9.8."""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np

from rtl_v098_contract import V098_N_ENTRIES, V098RuntimeConfig


V098_LAYOUTS = {"HEAD", "TAIL", "BANK_STRIDED", "RANDOM", "EXPLICIT"}
OFFICIAL_BENCHMARK_TARGET_COUNTS = {1, 4, 16, 64, 256}
OFFICIAL_BACKGROUND_SEED = 0x5EED1234
OFFICIAL_TARGET_POSITION_SEED = 0xA17E2026
OFFICIAL_TARGET_VALUE = 12345


@dataclass(frozen=True)
class V098Dataset:
    """A full N-slot image plus the exact valid target set."""

    memory_image: np.ndarray
    valid_values: np.ndarray
    target_mask: np.ndarray
    target_indices: tuple[int, ...]
    config: V098RuntimeConfig
    layout: str
    seed: int

    @property
    def target_count(self) -> int:
        return len(self.target_indices)


def build_controlled_v098_dataset(
    *,
    predicate_mode: str,
    data_count: int,
    target_count: int,
    layout: str = "HEAD",
    seed: int = 1,
    auto_shot: bool = True,
    burst_enable: bool = False,
    enum_enable: bool = False,
    fail_repeat_limit: int = 4,
    threshold_a: int | None = None,
    threshold_b: int | None = None,
    target_indices: tuple[int, ...] | None = None,
) -> V098Dataset:
    """Create a deterministic signed16 dataset with exactly ``target_count`` hits."""

    normalized_mode = predicate_mode.upper()
    normalized_layout = layout.upper()
    if normalized_layout not in V098_LAYOUTS:
        raise ValueError(f"layout must be one of {sorted(V098_LAYOUTS)}")
    if not 0 <= target_count <= data_count:
        raise ValueError("target_count must be between 0 and data_count")

    target_value, nontarget_value, resolved_a, resolved_b = _predicate_values(
        normalized_mode,
        threshold_a=threshold_a,
        threshold_b=threshold_b,
    )
    cfg = V098RuntimeConfig(
        predicate_mode=normalized_mode,
        threshold_a=resolved_a,
        threshold_b=resolved_b,
        data_count=data_count,
        auto_shot=auto_shot,
        burst_enable=burst_enable,
        enum_enable=enum_enable,
        fail_repeat_limit=fail_repeat_limit,
    )
    if target_indices is not None:
        if normalized_layout != "EXPLICIT":
            raise ValueError("target_indices requires layout='EXPLICIT'")
        selected = np.asarray(target_indices, dtype=np.int64)
        if selected.ndim != 1 or selected.size != target_count:
            raise ValueError("target_indices length must equal target_count")
        if np.unique(selected).size != selected.size:
            raise ValueError("target_indices must be unique")
        if np.any(selected < 0) or np.any(selected >= data_count):
            raise ValueError("target_indices must be within DATA_COUNT")
        selected = np.sort(selected)
    elif normalized_layout == "EXPLICIT":
        raise ValueError("layout='EXPLICIT' requires target_indices")
    elif normalized_layout == "HEAD":
        selected = np.arange(target_count, dtype=np.int64)
    elif normalized_layout == "TAIL":
        selected = np.arange(data_count - target_count, data_count, dtype=np.int64)
    elif normalized_layout == "BANK_STRIDED":
        if target_count == 0:
            selected = np.empty(0, dtype=np.int64)
        else:
            selected = np.linspace(
                0, data_count - 1, num=target_count, dtype=np.int64
            )
            if np.unique(selected).size != selected.size:
                raise RuntimeError("BANK_STRIDED could not create unique targets")
    else:
        rng = np.random.default_rng(seed)
        selected = np.sort(
            rng.choice(data_count, size=target_count, replace=False).astype(np.int64)
        )

    valid_values = np.full(data_count, nontarget_value, dtype=np.int16)
    valid_values[selected] = np.int16(target_value)
    memory_image = np.full(V098_N_ENTRIES, nontarget_value, dtype=np.int16)
    memory_image[:data_count] = valid_values
    mask = v098_target_mask(memory_image, cfg)
    indices = tuple(int(index) for index in np.flatnonzero(mask))
    if len(indices) != target_count:
        raise RuntimeError(
            f"controlled dataset requested M={target_count}, generated M={len(indices)}"
        )
    return V098Dataset(
        memory_image=memory_image,
        valid_values=valid_values,
        target_mask=mask,
        target_indices=indices,
        config=cfg,
        layout=normalized_layout,
        seed=int(seed),
    )


def v098_target_mask(
    memory_image: np.ndarray,
    cfg: V098RuntimeConfig,
    *,
    found_mask: np.ndarray | None = None,
) -> np.ndarray:
    """Evaluate predicate && valid && !found for the final Q14 search space."""

    values = np.asarray(memory_image)
    if values.ndim != 1 or values.size != V098_N_ENTRIES:
        raise ValueError(f"memory_image must contain {V098_N_ENTRIES} entries")
    if not np.issubdtype(values.dtype, np.integer):
        raise TypeError("memory_image must contain integers")
    if np.any(values < -32768) or np.any(values > 32767):
        raise ValueError("memory_image values must fit signed 16-bit")

    mode = cfg.predicate_mode
    if mode == "EQ":
        matched = values == cfg.threshold_a
    elif mode == "GT":
        matched = values > cfg.threshold_a
    elif mode == "LT":
        matched = values < cfg.threshold_a
    elif mode == "RANGE":
        matched = (values > cfg.threshold_a) & (values < cfg.threshold_b)
    else:  # Config validation makes this unreachable.
        raise RuntimeError(f"unsupported predicate {mode}")

    valid = np.arange(V098_N_ENTRIES) < cfg.data_count
    result = np.asarray(matched & valid, dtype=np.bool_)
    if found_mask is not None:
        checked_found = np.asarray(found_mask)
        if checked_found.shape != result.shape or checked_found.dtype != np.bool_:
            raise ValueError("found_mask must be a boolean N-entry array")
        result &= ~checked_found
    return result


def xorshift32(state: int) -> int:
    """Exact dataset-generator xorshift32 used by the board benchmark app."""

    checked = int(state) & 0xFFFFFFFF
    if checked == 0:
        checked = 0x6D2B79F5
    checked ^= (checked << 13) & 0xFFFFFFFF
    checked ^= checked >> 17
    checked ^= (checked << 5) & 0xFFFFFFFF
    return checked & 0xFFFFFFFF


def build_official_board_benchmark_dataset(target_count: int) -> V098Dataset:
    """Reproduce the frozen 2026-09-01 Q14/EQ board benchmark dataset."""

    if target_count not in OFFICIAL_BENCHMARK_TARGET_COUNTS:
        raise ValueError(
            "official target_count must be one of "
            f"{sorted(OFFICIAL_BENCHMARK_TARGET_COUNTS)}"
        )
    state = OFFICIAL_BACKGROUND_SEED
    unsigned = np.empty(V098_N_ENTRIES, dtype=np.uint16)
    for index in range(V098_N_ENTRIES):
        state = xorshift32(state)
        value = state & 0xFFFF
        if value == OFFICIAL_TARGET_VALUE:
            value ^= 1
        unsigned[index] = value

    state = OFFICIAL_TARGET_POSITION_SEED
    selected: list[int] = []
    used: set[int] = set()
    while len(selected) < max(OFFICIAL_BENCHMARK_TARGET_COUNTS):
        state = xorshift32(state)
        index = state & (V098_N_ENTRIES - 1)
        if index not in used:
            used.add(index)
            selected.append(index)
    target_indices = selected[:target_count]
    unsigned[target_indices] = OFFICIAL_TARGET_VALUE
    values = unsigned.view(np.int16).copy()
    cfg = V098RuntimeConfig(
        predicate_mode="EQ",
        threshold_a=OFFICIAL_TARGET_VALUE,
        threshold_b=0,
        data_count=V098_N_ENTRIES,
        auto_shot=True,
    )
    mask = v098_target_mask(values, cfg)
    actual = tuple(int(index) for index in np.flatnonzero(mask))
    if set(actual) != set(target_indices) or len(actual) != target_count:
        raise RuntimeError("official benchmark dataset target reproduction failed")
    return V098Dataset(
        memory_image=values.copy(),
        valid_values=values,
        target_mask=mask,
        target_indices=tuple(target_indices),
        config=cfg,
        layout="OFFICIAL_NESTED_RANDOM",
        seed=OFFICIAL_BACKGROUND_SEED,
    )


def _predicate_values(
    mode: str,
    *,
    threshold_a: int | None = None,
    threshold_b: int | None = None,
) -> tuple[int, int, int, int]:
    default_a = 12345 if mode == "EQ" else (-1 if mode == "RANGE" else 0)
    default_b = 1 if mode == "RANGE" else 0
    a = default_a if threshold_a is None else int(threshold_a)
    b = default_b if threshold_b is None else int(threshold_b)
    if not -32768 <= a <= 32767 or not -32768 <= b <= 32767:
        raise ValueError("thresholds must fit signed 16-bit")
    if mode == "EQ":
        nontarget = a + 1 if a < 32767 else a - 1
        return a, nontarget, a, b
    if mode == "GT":
        if a == 32767:
            return a, a, a, b
        return a + 1, a, a, b
    if mode == "LT":
        if a == -32768:
            return a, a, a, b
        return a - 1, a, a, b
    if mode == "RANGE":
        if a >= b:
            raise ValueError("RANGE requires threshold_a < threshold_b")
        if b - a < 2:
            raise ValueError("RANGE must contain at least one signed integer")
        return a + 1, a, a, b
    raise ValueError("predicate_mode must be LT, GT, EQ, or RANGE")
