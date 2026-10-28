"""Exact-M dataset construction and Oracle ground truth for v0.9.8."""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np

from final_hardware_contract import V098_N_ENTRIES, V098RuntimeConfig


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
    fail_repeat_limit: int = 3,
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


# ---------------------------------------------------------------------------
# Predicate500 -- 네 술어 각각에 Common500 과 같은 모양(M 다섯 개 x 시드 100쌍)의
# 워크로드를 만드는 생성기.
#
# 보드 펌웨어(bbht_console 의 GEN PRED=...)가 똑같은 정수 연산으로 같은 배열을
# 만듭니다. 그래서 데이터셋 32 KiB 를 UART 로 보낼 필요가 없고, 호스트는 보드가
# 만든 배열의 FNV-1a 해시(SUM 명령)만 여기 값과 맞대면 됩니다. 이 함수와
# hardware_bram/firmware/bbht_console/src/main.c 의 gen_dataset() 은 한 쌍이니
# 한쪽을 고치면 다른 쪽도 고치십시오.
#
# 규칙 (모든 산술은 부호 있는 16비트 값 s 위에서, mod 는 음이 아닌 나머지)
#   배경   raw = xorshift32(bg) & 0xFFFF 를 차례로 뽑습니다.
#          EQ    raw == A(16비트) 이면 raw ^= 1            (기존 GEN 과 같음)
#          LT    s <  A      이면 s = A + ((s + 32768) mod (32768 - A))  -> [A, 32767]
#          GT    s >  A      이면 s = -32768 + ((s - A - 1) mod (A + 32769)) -> [-32768, A]
#          RANGE A < s < B   이면 s = B + ((s - A - 1) mod (32768 - B))    -> [B, 32767]
#          즉 배경은 어느 칸도 술어를 만족하지 않습니다.
#   목표   위치는 xorshift32(pos) mod count 를 차례로 뽑고, 이미 목표인 칸이면
#          건너뜁니다. 값은 EQ 이면 A, 나머지는 따로 도는 값 스트림
#          (시드 pos ^ 0x9E3779B9)에서 lo + (xorshift32(val) mod size) 로 뽑아
#          목표 구간 안에 흩뿌립니다.
#               LT     [-32768, A-1]    GT  [A+1, 32767]    RANGE [A+1, B-1]
#
# EQ 는 기존 GEN 과 규칙이 같아서 기본 시드로 만들면 공식 Common500 데이터셋과
# 바이트 단위로 같습니다 (build_predicate_benchmark_dataset 이 스스로 확인합니다).
# LT/GT/RANGE 는 위치 시드를 술어마다 달리 두어 정답 위치도 서로 다릅니다.
# ---------------------------------------------------------------------------
PREDICATE500_BACKGROUND_SEED = OFFICIAL_BACKGROUND_SEED
PREDICATE500_VALUE_SEED_MIX = 0x9E3779B9
PREDICATE500_SPECS = {
    # 술어: (A, B, 위치 시드)
    "LT": (-16384, 0, 0x17A02026),
    "GT": (16383, 0, 0x67A02026),
    "EQ": (OFFICIAL_TARGET_VALUE, 0, OFFICIAL_TARGET_POSITION_SEED),
    "RANGE": (-4096, 4096, 0x3A4E2026),
}
PREDICATE500_ORDER = ("LT", "GT", "EQ", "RANGE")


def _to_s16(value: int) -> int:
    value &= 0xFFFF
    return value - 0x10000 if value & 0x8000 else value


def predicate_hit(mode: str, value: int, a: int, b: int) -> bool:
    """RTL grover_predicate 와 같은 부호 있는 비교."""

    if mode == "LT":
        return value < a
    if mode == "GT":
        return value > a
    if mode == "EQ":
        return value == a
    if mode == "RANGE":
        return a < value < b
    raise ValueError(f"unsupported predicate {mode}")


def _check_predicate_thresholds(mode: str, a: int, b: int) -> tuple[int, int]:
    """목표 구간 [lo, lo+size) 를 돌려줍니다. 빈 구간이면 ValueError."""

    if not -32768 <= a <= 32767 or not -32768 <= b <= 32767:
        raise ValueError("thresholds must fit signed 16-bit")
    if mode == "LT":
        if a == -32768:
            raise ValueError("LT with A=-32768 has no target value")
        return -32768, a + 32768
    if mode == "GT":
        if a == 32767:
            raise ValueError("GT with A=32767 has no target value")
        return a + 1, 32767 - a
    if mode == "RANGE":
        if b - a < 2:
            raise ValueError("RANGE needs at least one integer in (A, B)")
        return a + 1, b - a - 1
    if mode == "EQ":
        return a, 1
    raise ValueError(f"unsupported predicate {mode}")


def generate_predicate_image(
    mode: str,
    a: int,
    b: int,
    target_count: int,
    *,
    count: int = V098_N_ENTRIES,
    bg_seed: int = PREDICATE500_BACKGROUND_SEED,
    pos_seed: int,
) -> list[int]:
    """펌웨어 GEN 과 같은 순서로 count 칸짜리 부호 있는 16비트 목록을 만듭니다."""

    mode = mode.upper()
    lo, size = _check_predicate_thresholds(mode, a, b)
    if not 1 <= count <= V098_N_ENTRIES:
        raise ValueError(f"count must be between 1 and {V098_N_ENTRIES}")
    if not 0 <= target_count <= count:
        raise ValueError("target_count must be between 0 and count")

    data = [0] * count
    state = bg_seed & 0xFFFFFFFF
    for index in range(count):
        state = xorshift32(state)
        raw = state & 0xFFFF
        if mode == "EQ":
            if raw == (a & 0xFFFF):
                raw ^= 1
            data[index] = _to_s16(raw)
            continue
        s = _to_s16(raw)
        if mode == "LT" and s < a:
            s = a + (s + 32768) % (32768 - a)
        elif mode == "GT" and s > a:
            s = -32768 + (s - a - 1) % (a + 32769)
        elif mode == "RANGE" and a < s < b:
            s = b + (s - a - 1) % (32768 - b)
        data[index] = s

    state = pos_seed & 0xFFFFFFFF
    value_state = (pos_seed ^ PREDICATE500_VALUE_SEED_MIX) & 0xFFFFFFFF
    placed = guard = 0
    while placed < target_count and guard < 100000:
        state = xorshift32(state)
        index = state % count
        guard += 1
        if predicate_hit(mode, data[index], a, b):
            continue
        if mode == "EQ":
            data[index] = a
        else:
            value_state = xorshift32(value_state)
            data[index] = lo + value_state % size
        placed += 1
    if placed != target_count:
        raise RuntimeError("target placement guard exhausted")
    return data


def fnv1a32_s16(values) -> int:
    """16비트 값을 little-endian 바이트로 늘어놓은 FNV-1a 32. 펌웨어 SUM 과 같음."""

    h = 0x811C9DC5
    for value in values:
        v = int(value) & 0xFFFF
        for byte in (v & 0xFF, v >> 8):
            h ^= byte
            h = (h * 0x01000193) & 0xFFFFFFFF
    return h


def build_predicate_benchmark_dataset(mode: str, target_count: int) -> V098Dataset:
    """Predicate500 워크로드 하나. 술어 네 개 x M 다섯 개 중 하나를 만듭니다."""

    mode = mode.upper()
    if mode not in PREDICATE500_SPECS:
        raise ValueError(f"mode must be one of {PREDICATE500_ORDER}")
    if target_count not in OFFICIAL_BENCHMARK_TARGET_COUNTS:
        raise ValueError(
            "target_count must be one of "
            f"{sorted(OFFICIAL_BENCHMARK_TARGET_COUNTS)}"
        )
    a, b, pos_seed = PREDICATE500_SPECS[mode]
    values = np.asarray(
        generate_predicate_image(mode, a, b, target_count, pos_seed=pos_seed),
        dtype=np.int16,
    )
    cfg = V098RuntimeConfig(
        predicate_mode=mode,
        threshold_a=a,
        threshold_b=b,
        data_count=V098_N_ENTRIES,
        auto_shot=True,
    )
    mask = v098_target_mask(values, cfg)
    indices = tuple(int(index) for index in np.flatnonzero(mask))
    if len(indices) != target_count:
        raise RuntimeError(
            f"{mode} M={target_count}: generated {len(indices)} targets"
        )
    if mode == "EQ":
        official = build_official_board_benchmark_dataset(target_count)
        if not np.array_equal(official.memory_image, values):
            raise RuntimeError("EQ predicate dataset diverged from the official dataset")
    return V098Dataset(
        memory_image=values.copy(),
        valid_values=values,
        target_mask=mask,
        target_indices=indices,
        config=cfg,
        layout="PREDICATE500",
        seed=PREDICATE500_BACKGROUND_SEED,
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
