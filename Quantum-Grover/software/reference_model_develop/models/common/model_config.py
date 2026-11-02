from __future__ import annotations

import json
import math
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any


ORACLE_MODES = {"EQ", "GT", "LT", "RANGE"}
SEARCH_MODES = {"KNOWN_M", "BBHT"}
ROUNDING_MODES = {"NEAREST", "TRUNC", "STOCHASTIC"}
OVERFLOW_MODES = {"SATURATE", "WRAP"}
TRACE_LEVELS = {"NONE", "SUMMARY", "FULL"}
ARITHMETIC_MODES = {"FLOAT64", "FIXED"}


@dataclass
class GroverConfig:
    """Serializable configuration shared by the golden model and RTL tests."""

    schema_version: str = "1.0"

    active_qubits: int = 3
    data_count: int = 8
    data_width: int = 16

    oracle_mode: str = "GT"
    criterion_a: int = 7
    criterion_b: int = 0
    requested_target_count: int | None = None
    max_enumerated_targets: int = 256

    search_mode: str = "BBHT"
    lambda_bbht: float = 6.0 / 5.0
    bbht_budget_factor: float = 4.5
    max_attempts: int = 100
    max_consecutive_failures: int = 3

    arithmetic_mode: str = "FLOAT64"

    amp_width: int = 18
    frac_bits: int = 17
    accumulator_margin: int = 0
    rounding: str = "NEAREST"
    overflow: str = "SATURATE"

    input_seed: int = 1
    bbht_seed: int = 2
    measurement_seed: int = 3
    rounding_seed: int = 4
    trace_level: str = "SUMMARY"

    def __post_init__(self) -> None:
        self.oracle_mode = self.oracle_mode.upper()
        self.search_mode = self.search_mode.upper()
        self.rounding = self.rounding.upper()
        self.overflow = self.overflow.upper()
        self.trace_level = self.trace_level.upper()
        self.arithmetic_mode = self.arithmetic_mode.upper()
        self.validate()

    @property
    def active_n(self) -> int:
        return 1 << self.active_qubits

    @property
    def signed_data_min(self) -> int:
        return -(1 << (self.data_width - 1))

    @property
    def signed_data_max(self) -> int:
        return (1 << (self.data_width - 1)) - 1

    def validate(self) -> None:
        if self.schema_version != "1.0":
            raise ValueError(f"unsupported schema_version: {self.schema_version}")

        if not 1 <= self.active_qubits <= 16:
            raise ValueError("active_qubits must be between 1 and 16")
        if not 1 <= self.data_count <= self.active_n:
            raise ValueError("data_count must be between 1 and active_n")
        if self.data_width != 16:
            raise ValueError("the agreed input data width is signed 16-bit")

        if self.oracle_mode not in ORACLE_MODES:
            raise ValueError(f"oracle_mode must be one of {sorted(ORACLE_MODES)}")
        self._validate_signed_value("criterion_a", self.criterion_a)
        if self.oracle_mode == "RANGE":
            self._validate_signed_value("criterion_b", self.criterion_b)
            if self.criterion_a >= self.criterion_b:
                raise ValueError("RANGE requires criterion_a < criterion_b")

        if self.requested_target_count is not None:
            if not 0 <= self.requested_target_count <= self.data_count:
                raise ValueError(
                    "requested_target_count must be between 0 and data_count"
                )
        if self.max_enumerated_targets < 1:
            raise ValueError("max_enumerated_targets must be at least 1")

        if self.search_mode not in SEARCH_MODES:
            raise ValueError(f"search_mode must be one of {sorted(SEARCH_MODES)}")
        if not 1.0 < self.lambda_bbht <= 2.0:
            raise ValueError("lambda_bbht must be greater than 1 and at most 2")
        if not math.isfinite(self.bbht_budget_factor) or self.bbht_budget_factor <= 0.0:
            raise ValueError("bbht_budget_factor must be finite and positive")
        if self.max_attempts < 1:
            raise ValueError("max_attempts must be at least 1")
        if self.max_consecutive_failures < 1:
            raise ValueError("max_consecutive_failures must be at least 1")

        if self.arithmetic_mode not in ARITHMETIC_MODES:
            raise ValueError(
                f"arithmetic_mode must be one of {sorted(ARITHMETIC_MODES)}"
            )

        if not 2 <= self.amp_width <= 64:
            raise ValueError("amp_width must be between 2 and 64")
        if not 0 < self.frac_bits < self.amp_width:
            raise ValueError("frac_bits must be between 1 and amp_width - 1")
        if self.accumulator_margin < 0:
            raise ValueError("accumulator_margin cannot be negative")
        if self.rounding not in ROUNDING_MODES:
            raise ValueError(f"rounding must be one of {sorted(ROUNDING_MODES)}")
        if self.overflow not in OVERFLOW_MODES:
            raise ValueError(f"overflow must be one of {sorted(OVERFLOW_MODES)}")

        for name, seed in (
            ("input_seed", self.input_seed),
            ("bbht_seed", self.bbht_seed),
            ("measurement_seed", self.measurement_seed),
            ("rounding_seed", self.rounding_seed),
        ):
            if seed < 0:
                raise ValueError(f"{name} must be non-negative")

        if self.trace_level not in TRACE_LEVELS:
            raise ValueError(f"trace_level must be one of {sorted(TRACE_LEVELS)}")

    def _validate_signed_value(self, name: str, value: int) -> None:
        if not self.signed_data_min <= value <= self.signed_data_max:
            raise ValueError(
                f"{name} must fit signed {self.data_width}-bit range "
                f"[{self.signed_data_min}, {self.signed_data_max}]"
            )

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)

    def to_json(self, path: str | Path) -> None:
        output_path = Path(path)
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_text(
            json.dumps(self.to_dict(), indent=2, ensure_ascii=True) + "\n",
            encoding="utf-8",
        )

    @classmethod
    def from_json(cls, path: str | Path) -> "GroverConfig":
        payload = json.loads(Path(path).read_text(encoding="utf-8"))
        if not isinstance(payload, dict):
            raise ValueError("configuration JSON must contain an object")
        return cls(**payload)
