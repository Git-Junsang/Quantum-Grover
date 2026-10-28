# 실험 10. Two-Track Execution과 Pass 2–Build Fusion: 채택하지 않은 두 시도

> [← 실험 09 measurement 병목과 Dual-Row Build · Two-Level Select](09_measurement_bottleneck_and_microarchitecture.md) · [index](index.md) · [실험 11 채택하지 않은 확장과 variant →](11_rejected_extensions.md)

---

| 정한 것 | 근거의 축 |
|---|---|
| request 열 분할 Two-Track Execution과 Pass 2–Build Fusion을 채택하지 않음 | RTL simulation 250쌍 · OOC synthesis |

2026-09-06에 우리 쪽에서 board에서 verification을 마친 Stage 2 build를 기준으로 "BRAM을 안 늘리면서 더 빠른 구성" 을
찾은 benchmark입니다. 수치는 모두 `xc7a100tcsg324-1` · OOC · 100 MHz이고, 250쌍 harness는 board benchmark와 여섯
지표가 0.00%로 일치하는 것을 먼저 확인했습니다.

## request 열을 두 track으로 가르는 Two-Track Execution (공유 · 분리 checkpoint slot)

BRAM budget은 full SoC의 135 BRAM tiles에서 RVX 본체 32 BRAM tiles를 뺀 103 BRAM tiles였습니다. checkpoint slot 하나가 RAMB36
11개라 Checkpoint-Capacity를 낮춰 사는 것은 BRAM뿐이었습니다.

| 구성 | BRAM tiles | +RVX | executed iterations | WNS | 논리 정합 |
|---|---:|---:|---:|---:|:-:|
| a Checkpoint-Capacity of 4 and 4-shot Lookahead 단일 (기준) | 66 | 98 | 4,214 | +0.060 | 기준 |
| 분리 checkpoint slot, a Checkpoint-Capacity of 4 × 2 tracks | 132 | 164 (초과) | 6,302 | −0.143 | 정합 |
| 분리 checkpoint slot, a Checkpoint-Capacity of 2 × 2 tracks | 88 | 120 | 6,583 | −0.412 | policy 미유도 |
| 공유 checkpoint slot, a Checkpoint-Capacity of 4 | 88 | 120 | 4,214 | −0.20 | BBHT trajectory collapse |

- request 열을 짝/홀로 가르면 executed iterations가 Checkpoint-Capacity와 무관하게 약 +50% 늘었습니다(분할 자체의 비용). 완벽히
  겹쳐 돌려도 이득의 천장이 −25%였고, implementation은 직렬 배분이라 대가만 치렀습니다.
- 공유 checkpoint slot 방식은 두 track의 policy가 서로의 checkpoint slot을 덮어써 `shot_count` · `requested_iterations`가 기준과
  어긋났습니다. 결과 index는 맞게 나와서 testbench는 오류 0건이었고, 그래서 이 구성이 낸 "8.6% 빠른"
  cycle은 amplitude가 깨져 search가 우연히 짧게 끝난 값입니다.
- 이중 구성의 timing 실패는 datapath가 아니라 두 track counter를 합치는 CSR 읽기 경로의 adder
  탓이었고, pipeline register 한 단을 넣자 회복했습니다.

남긴 교훈은 둘입니다. 공유 state의 소유권을 따지지 않으면 결과는 맞는 채로 성능 수치만 거짓이
되고, 그래서 verification은 paired comparison 불변식으로 해야 합니다. track을 가른다면 BBHT sequencer와 Measurement PRNG는
하나여야 하고, policy의 Lookahead에는 그 track이 실제로 받을 request만 담아야 합니다.

## Pass 2–Build Fusion

Born-rule sampling의 Build가 512 rows를 다시 읽는 대신, Pass 2가 새 amplitude row를 쓰는 그 cycle에 square · sum을
해 두어 rescan을 없애는 시도였습니다.

| 항목 (250쌍) | 기존 | Pass 2–Build Fusion | 차이 |
|---|---:|---:|---:|
| Restart mode · a Checkpoint-Capacity of 4 executed iterations | 14,883 · 4,247 | 14,883 · 4,247 | 0 |
| a Checkpoint-Capacity of 4 cycles | 7,796,908 | 7,018,034 | −9.99% |
| BRAM tile | 66 | 66 | 0 |
| DSP | 64 | 128 | +64 |
| WNS | +0.060 | +0.140 | |

executed iterations는 그대로 두고 Measurement Unit만 아꼈고 BRAM도 늘지 않았습니다. 다만 checkpoint 복원이 amplitude
memory에 쓰지 않고 읽기 checkpoint slot만 바꾸는 경우와, fallback한 Build가 row weight를 덮어쓰는 경우 두 가지
소유권 결함을 250쌍에서야 잡았습니다(27 shots testbench에서는 오류 0건). drain wait state가 없으면
결과는 맞은 채 hit rate만 조용히 0이 되는 문제도 있었습니다.

## Board-Verified Build가 같은 병목을 푼 방식

같은 두 병목을 Board-Verified Build는 다른 방식으로 풀었고, final configuration에는 그쪽 방식이 들어갔습니다.

| 병목 | 우리 시도 | Board-Verified Build |
|---|---|---|
| PE 병렬화 | request 열을 track으로 가름. executed iterations +50%, 소유권 문제 | Grover iteration 안에서 4 rows씩 가름(4 PEs). executed iterations 그대로, 소유권 문제 없음 ([실험 08](08_one_pe_profiling_and_four_pes.md)) |
| Measurement Unit | rescan을 없앰 (−9.99%, Stage 2 기준) | rescan을 남기고 싸게 만듦 (Dual-Row Build · Two-Level Select, Stage 4 대비 −33.7%) ([실험 09](09_measurement_bottleneck_and_microarchitecture.md)) |
| a Checkpoint-Capacity of 3에서의 policy | combinatorial rank function을 a Checkpoint-Capacity of 3용으로 다시 유도해야 한다며 막힘 | `STATE_RANKS = 1,093` stride를 그대로 두어 a Checkpoint-Capacity of 4 and 4-shot Lookahead를 bit 단위로 동일하게 유지하고 a Checkpoint-Capacity of 3은 좁은 index 범위만 방문 |

두 measurement 개선은 baseline이 달라 직접 맞대지 않습니다. rescan을 없애는 것과 싸게 만드는 것은
원리상 배타적이지 않지만 겹쳐 본 적은 없습니다. Measurement Unit을 빠르게 한 값은 어느 방법이든
DSP였습니다.
