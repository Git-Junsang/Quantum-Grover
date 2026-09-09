"""Frozen v0.9.8 software-visible contract for the BBHT/Grover accelerator.

This module intentionally contains no checkpoint-policy implementation.  It
describes the boundary that software, golden vectors, and RTL result checkers
must agree on.  The autonomous checkpoint policy is an internal Main-IP detail.
"""

from __future__ import annotations

from dataclasses import dataclass
from numbers import Integral
from typing import Any, Iterable

import numpy as np


V098_VERSION = "0.9.8"
V098_Q_BITS = 14
V098_N_ENTRIES = 1 << V098_Q_BITS
V098_PARALLELISM = 32
V098_DATA_W = 16
V098_FRAC_BITS = 22
V098_AMP_W = 23
V098_J_W = 7
V098_RESULT_W = 14
V098_FIFO_DEPTH = 256
V098_FIFO_COUNT_W = 9
V098_ACCEL_CLK_HZ = 100_000_000
V098_DEFAULT_SHOT_CAP = 100
V098_CHECKPOINT_K = 4
V098_POLICY_HORIZON = 8

PREDICATE_CODES = {"LT": 0, "GT": 1, "EQ": 2, "RANGE": 3}

CSR_OFFSETS = {
    "COMMAND": 0x000,
    "CONTROL": 0x004,
    "J_TARGET": 0x008,
    "THRESHOLD_A": 0x00C,
    "THRESHOLD_B": 0x010,
    "DATA_COUNT": 0x014,
    "SHOT_CAP": 0x018,
    "SEED_J": 0x01C,
    "SEED_MEAS": 0x020,
    "STATUS": 0x024,
    "RESULT_INDEX": 0x028,
    "TRIAL_COUNT": 0x02C,
    "L_BBHT": 0x030,
    "ACTUAL_ITER": 0x034,
    "CYCLE_COUNT": 0x038,
    "ENUM_CFG": 0x03C,
    "FIFO_DATA": 0x040,
    "FIFO_COUNT": 0x044,
    "FOUND_COUNT": 0x048,
    "CONSEC_FAIL": 0x04C,
    "MAX_FIFO_OCC": 0x050,
    "FIFO_STALL": 0x054,
    "DATA_ADDR": 0x058,
    "DMA_COMMAND": 0x05C,
    "DMA_STATUS": 0x060,
    "POLICY_CYCLES_TOTAL": 0x064,
    "POLICY_STALL_CYCLES": 0x068,
    "POLICY_ACTIONS_EVAL": 0x06C,
    "POLICY_MEMO_HIT": 0x070,
    "POLICY_MEMO_MISS": 0x074,
    "POLICY_MAX_LATENCY": 0x078,
    "PLAN_FIFO_LEVEL": 0x07C,
    "PLAN_FIFO_HIGHWATER": 0x080,
    "PLAN_FIFO_EMPTY_DEMAND": 0x084,
    "PLAN_FIFO_HIT_COUNT": 0x088,
    "PLAN_FIFO_MISMATCH_COUNT": 0x08C,
    "POLICY_COLD_SOLVE_COUNT": 0x090,
    "POLICY_SPEC_SOLVE_COUNT": 0x094,
}

STATUS_BITS = {
    "busy": 0,
    "load_busy": 1,
    "done_sticky": 2,
    "result_valid": 3,
    "config_error": 4,
    "shot_limit": 5,
    "budget_limit": 6,
    "amp_overflow": 7,
    "zero_weight_error": 8,
    "load_error": 9,
    "enum_done": 10,
    "fifo_empty": 11,
}

DMA_STATUS_BITS = {
    "dma_busy": 0,
    "dma_error": 1,
    "align_error": 2,
    "count_error": 3,
    "resp_error": 4,
    "busy_error": 5,
    "range_error": 6,
    "dma_done_sticky": 7,
}

# CSR 실행 모드. 체크포인트를 켠 쪽이 CKPT_* 입니다.
RUN_MODES = {
    "MANUAL_SINGLE": (False, False, False),
    "NORMAL_SINGLE": (True, False, False),
    "CKPT_SINGLE": (True, True, False),
    "NORMAL_ENUM": (True, False, True),
    "CKPT_ENUM": (True, True, True),
}

# 옛 이름. K 와 H 가 RTL 빌드 상수라 이름에 값을 박아 두면 빌드가 바뀔 때마다
# 틀려집니다 -- 실제로 K4/H4 를 거쳐 지금은 K3/H3 입니다. 옛 이름으로 부르는
# 스크립트를 위해 계속 받아 주되, 정본 이름은 위의 다섯입니다.
RUN_MODE_ALIASES = {
    "K4H8_SINGLE": "CKPT_SINGLE",
    "K4H8_ENUM": "CKPT_ENUM",
}


@dataclass(frozen=True)
class V098RuntimeConfig:
    """Validated runtime values written through the v0.9.8 CSR interface."""

    predicate_mode: str = "EQ"
    threshold_a: int = 0
    threshold_b: int = 0
    data_count: int = V098_N_ENTRIES
    auto_shot: bool = True
    burst_enable: bool = False
    enum_enable: bool = False
    fail_repeat_limit: int = 4
    j_target: int = 0
    shot_cap: int = V098_DEFAULT_SHOT_CAP
    seed_j: int = 0x10203040
    seed_meas: int = 0x12345078

    def __post_init__(self) -> None:
        object.__setattr__(self, "predicate_mode", self.predicate_mode.upper())
        if self.predicate_mode not in PREDICATE_CODES:
            raise ValueError(
                f"predicate_mode must be one of {sorted(PREDICATE_CODES)}"
            )
        _validate_signed16("threshold_a", self.threshold_a)
        _validate_signed16("threshold_b", self.threshold_b)
        if self.predicate_mode == "RANGE" and self.threshold_a >= self.threshold_b:
            raise ValueError("RANGE requires threshold_a < threshold_b")
        if not 1 <= self.data_count <= V098_N_ENTRIES:
            raise ValueError(f"data_count must be between 1 and {V098_N_ENTRIES}")
        for name in ("auto_shot", "burst_enable", "enum_enable"):
            if not isinstance(getattr(self, name), bool):
                raise TypeError(f"{name} must be boolean")
        if not 1 <= self.fail_repeat_limit <= 15:
            raise ValueError("fail_repeat_limit must be between 1 and 15")
        if not 0 <= self.j_target < (1 << V098_J_W):
            raise ValueError("j_target must fit unsigned 7-bit")
        if not 1 <= self.shot_cap <= 0xFFFF:
            raise ValueError("shot_cap must be between 1 and 65535")
        _validate_u32("seed_j", self.seed_j)
        _validate_u32("seed_meas", self.seed_meas)

    @classmethod
    def from_mode(cls, mode: str, **kwargs: Any) -> "V098RuntimeConfig":
        normalized = mode.upper()
        normalized = RUN_MODE_ALIASES.get(normalized, normalized)
        if normalized not in RUN_MODES:
            raise ValueError(f"mode must be one of {sorted(RUN_MODES)}")
        auto_shot, burst_enable, enum_enable = RUN_MODES[normalized]
        return cls(
            auto_shot=auto_shot,
            burst_enable=burst_enable,
            enum_enable=enum_enable,
            **kwargs,
        )

    @property
    def checkpoint_auto_enable(self) -> bool:
        return self.auto_shot and self.burst_enable

    @property
    def control_word(self) -> int:
        return (
            int(self.auto_shot)
            | (int(self.burst_enable) << 1)
            | (PREDICATE_CODES[self.predicate_mode] << 2)
        )

    @property
    def enum_cfg_word(self) -> int:
        return int(self.enum_enable) | (self.fail_repeat_limit << 4)

    def csr_write_values(self) -> dict[str, int]:
        """Return register values before COMMAND/DMA_COMMAND write pulses."""

        return {
            "CONTROL": self.control_word,
            "J_TARGET": self.j_target,
            "THRESHOLD_A": self.threshold_a & 0xFFFF,
            "THRESHOLD_B": self.threshold_b & 0xFFFF,
            "DATA_COUNT": self.data_count,
            "SHOT_CAP": self.shot_cap,
            "SEED_J": self.seed_j,
            "SEED_MEAS": self.seed_meas,
            "ENUM_CFG": self.enum_cfg_word,
        }


def decode_bits(value: int, definitions: dict[str, int]) -> dict[str, bool]:
    """Decode STATUS-like bit fields while preserving all named bits."""

    checked = _validate_u32("value", value)
    return {name: bool(checked & (1 << bit)) for name, bit in definitions.items()}


def decode_status(value: int) -> dict[str, bool]:
    return decode_bits(value, STATUS_BITS)


def decode_dma_status(value: int) -> dict[str, bool]:
    return decode_bits(value, DMA_STATUS_BITS)


def pack_signed16_ahb_words(values: Iterable[int]) -> np.ndarray:
    """Pack data[2k] into low16 and data[2k+1] into high16 of an AHB word."""

    checked = _as_signed16_vector(values)
    words = np.zeros((checked.size + 1) // 2, dtype=np.uint32)
    unsigned = checked.astype(np.uint16, copy=False).astype(np.uint32)
    words[:] = unsigned[0::2]
    if checked.size > 1:
        words[: checked.size // 2] |= unsigned[1::2] << np.uint32(16)
    return words


def unpack_signed16_ahb_words(words: Iterable[int], data_count: int) -> np.ndarray:
    """Inverse of :func:`pack_signed16_ahb_words` for a known DATA_COUNT."""

    if not 1 <= data_count <= V098_N_ENTRIES:
        raise ValueError(f"data_count must be between 1 and {V098_N_ENTRIES}")
    packed = np.asarray(list(words))
    if packed.ndim != 1 or not np.issubdtype(packed.dtype, np.integer):
        raise TypeError("words must be a one-dimensional integer sequence")
    required = (data_count + 1) // 2
    if packed.size != required:
        raise ValueError(f"expected {required} packed words, got {packed.size}")
    if np.any(packed < 0) or np.any(packed > 0xFFFFFFFF):
        raise ValueError("all packed words must fit unsigned 32-bit")
    packed = packed.astype(np.uint32, copy=False)
    raw = np.empty(packed.size * 2, dtype=np.uint16)
    raw[0::2] = packed & np.uint32(0xFFFF)
    raw[1::2] = packed >> np.uint32(16)
    return raw[:data_count].view(np.int16).copy()


def _as_signed16_vector(values: Iterable[int]) -> np.ndarray:
    checked = np.asarray(list(values))
    if checked.ndim != 1 or not np.issubdtype(checked.dtype, np.integer):
        raise TypeError("values must be a one-dimensional integer sequence")
    if checked.size < 1 or checked.size > V098_N_ENTRIES:
        raise ValueError(f"values must contain 1 to {V098_N_ENTRIES} elements")
    if np.any(checked < -32768) or np.any(checked > 32767):
        raise ValueError("all values must fit signed 16-bit")
    return checked.astype(np.int16, copy=False)


def _validate_signed16(name: str, value: int) -> None:
    if isinstance(value, bool) or not isinstance(value, Integral):
        raise TypeError(f"{name} must be an integer")
    if not -32768 <= int(value) <= 32767:
        raise ValueError(f"{name} must fit signed 16-bit")


def _validate_u32(name: str, value: int) -> int:
    if isinstance(value, bool) or not isinstance(value, Integral):
        raise TypeError(f"{name} must be an integer")
    checked = int(value)
    if not 0 <= checked <= 0xFFFFFFFF:
        raise ValueError(f"{name} must fit unsigned 32-bit")
    return checked
