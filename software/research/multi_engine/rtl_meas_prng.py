#!/usr/bin/env python3
"""
측정용 64비트 PRNG 를 실물 RTL 식 그대로 옮긴 것.

`software/golden/rtl_v098_auto.py` 의 `V098MeasurementRandomSource` 는 스스로
provisional 이라고 적어 두었습니다. 모듈 머리말이 이렇게 말합니다.

    "the delivered local artifacts do not contain their complete bit equations:
     the 32-to-64-bit measurement seed expansion and the restricted-B
     bridge-level checkpoint planner. They are isolated behind small classes so the
     frozen RTL equations can replace them without changing the search model."

그 RTL 이 이제 `hardware_bram/src_v2/grover_bbht.v` 에 있습니다
(`grover_meas_prng64_adapter`). 여기서 두 가지가 갈립니다.

1. 시드 확장
     RTL   expand_seed64(s) = {e, e ^ 32'h9E37_79B9}      e = (s==0) ? 폴백 : s
     기존  (e << 32) | e                                   상위·하위 같은 값
   하위 절반에 golden-ratio 상수를 XOR 하는 것이 빠져 있었습니다. RTL 주석이
   이 상수를 두는 이유를 적어 두었습니다 -- 0 이 아니므로 확장된 64비트
   상태가 절대 0 이 될 수 없습니다.

2. 블록 소비 순서
     RTL   rnd 는 **현재** state 의 절반입니다. HI(state[63:32]) 를 먼저 주고,
           LO(state[31:0]) 를 준 뒤에야 xorshift64 로 한 번 전진합니다.
           따라서 첫 블록은 확장된 시드 그 자체입니다.
     기존  draw_block() 이 먼저 전진하고 그 결과를 돌려주어 첫 블록을 건너뜁니다.

두 곳을 맞추면 2026-09-01 보드 벤치마크의 Normal 250 workload 물리 반복이
14,883 로 정확히 재현됩니다 (고치기 전 15,268).

xorshift64 다항식(13,7,17)과 HI->LO 를 이어 붙여 dynamic-width rejection 을
하는 CDF 경로는 원래 모델이 이미 RTL 과 같으므로 건드리지 않습니다.
"""
from __future__ import annotations

MEAS_FALLBACK_SEED = 0xBEEFC0DE
SEED_MIX = 0x9E3779B9
MASK64 = 0xFFFFFFFFFFFFFFFF


class RTLMeasurementRandomSource:
    """grover_meas_prng64_adapter 와 같은 64비트 블록 스트림."""

    def __init__(self, seed: int) -> None:
        effective = int(seed) & 0xFFFFFFFF
        if effective == 0:
            effective = MEAS_FALLBACK_SEED
        self.state = ((effective << 32) | (effective ^ SEED_MIX)) & MASK64

    def draw_block(self) -> int:
        """현재 블록을 돌려주고 그 다음에 전진합니다 (RTL 의 HI->LO->advance)."""
        block = self.state
        value = block
        value ^= (value << 13) & MASK64
        value ^= value >> 7
        value ^= (value << 17) & MASK64
        self.state = value & MASK64
        return block


def install() -> None:
    """골든 모델의 provisional 측정 소스를 이걸로 갈아 끼웁니다.

    `software/golden/` 파일 자체는 고치지 않습니다. 그쪽은 두 하드웨어 갈래가
    공유하는 정본이라, 바꾸려면 저장된 검증 벡터 재생성까지 같이 가야 합니다.
    """
    import rtl_v098_auto

    rtl_v098_auto.V098MeasurementRandomSource = RTLMeasurementRandomSource


if __name__ == "__main__":
    source = RTLMeasurementRandomSource(0x24370DF2)
    print("seed 0x24370DF2 의 앞 4블록")
    for index in range(4):
        print(f"  block[{index}] = 0x{source.draw_block():016X}")
