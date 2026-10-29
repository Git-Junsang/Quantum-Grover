# 실험 25. Triple-Row Build와 a Checkpoint-Capacity of 5의 resource · 총 cycles 사전 검토

> 기준일 2026-10-26. 이 문서는 RTL implementation 전 구조 계산이다. Triple-Row Build는 세 번째
> `square32` squarer로 measurement Build를 3 rows/cycle로 처리하는 것으로 정의한다.
> a Checkpoint-Capacity of 5는 policy 숫자만 5로 바꾸는 것이 아니라 다섯 번째 **checkpoint slot**(실제 amplitude 저장)까지
> 보존하는 것으로 정의한다.

## 결론

- **Triple-Row Build 단독은 논리 resource 수로는 들어간다.** DSP는 132→196/240, BRAM은
  보수적으로 116→117/135이고, Common500 총 cycles은 5,328,877에서
  약 **4,699,622~4,714,737**로 줄 것으로 예상된다. 감소율은
  **11.52~11.81%**, throughput speedup은 약 **1.130~1.134×**다.
- 다만 현재 implementation이 이미 slice 14,971/15,850(94.45%)이므로 Triple-Row Build의 LUT가
  총량 한도 안에 있어도 **100T placement · routing은 고위험**이다. synthesis/implementation 전에는
  “들어간다”고 확정할 수 없다.
- **a Checkpoint-Capacity of 5를 4 PEs와 같은 4 rows/cycle로 만드는 full-speed configuration은 100T에 들어가지
  않는다.** a Checkpoint-Capacity of 5 and 5-shot Lookahead+Triple-Row Build의 예상 BRAM은 약 156/135, a Checkpoint-Capacity of 5 and 6-shot Lookahead+Triple-Row Build는 약 158/135다.
- 11 RAMB36짜리 fifth-slot을 저대역폭 cold storage로 두는 구성은 용량상
  a Checkpoint-Capacity of 5 and 5-shot Lookahead+Triple-Row Build 127/135까지 낮출 수 있지만, hot/cold 교환 1회가 약 512 cycles다.
  a Checkpoint-Capacity of 5 and 5-shot Lookahead가 a Checkpoint-Capacity of 4 and 5-shot Lookahead보다 얻는 총 cycles 이득은 약 25,418 cycles뿐이어서 **약 50회
  swap이면 이득이 사라진다.** 따라서 현재 우선순위는 a Checkpoint-Capacity of 5가 아니라 Triple-Row Build 또는
  a Checkpoint-Capacity of 4 and 5-shot Lookahead다.

## 1. 기준값

Arty A7-100T의 실제 final configuration implementation과 Common500 RTL benchmark를 기준으로 한다.

| 항목 | 기준 |
|---|---:|
| 총 cycles | 5,328,877 |
| policy 결정/shot | 7,403 |
| executed iterations | 9,582 |
| policy stall | 172,066 |
| SoC LUT | 45,116 / 63,400 |
| SoC FF | 45,210 / 126,800 |
| SoC BRAM tile | 116 / 135 |
| SoC DSP | 132 / 240 |
| Slice | 14,971 / 15,850 (94.45%) |

## 2. Triple-Row Build 총 cycles

현재 final configuration의 Build는 512 rows를 2 rows/cycle로 처리하므로 256 cycles/shot이다.
세 번째 `square32`를 더하면 다음과 같다.

```text
Triple-Row Build = ceil(512 / 3) = 171 cycles/shot
절감             = 256 - 171 = 85 cycles/shot
raw 절감         = 85 × 7,403 = 629,255 cycles
```

measurement가 짧아지면 policy가 실행 뒤에 드러나는 비율이 조금 늘 수 있다. Stage 5 → final configuration
benchmark에서 총 cycles은 1,604,508 줄었고 policy stall은 39,490 늘었다. 이를 이용한
경험적 노출 손실률은 2.402%이며, Triple-Row Build의 순절감은 약 614,140 cycles다.

| 계산 | 예상 총 cycles | 현재 대비 감소 | speedup |
|---|---:|---:|---:|
| stall 증가 없음 | 4,699,622 | 629,255 (11.81%) | 1.134× |
| Stage 5 → final configuration 노출률 적용 | 4,714,737 | 614,140 (11.52%) | 1.130× |

Seed-First Branch and Bound policy까지 적용한 a Checkpoint-Capacity of 3 and 3-shot Lookahead 기준 5,242,686에는 Triple-Row Build를 더했을 때
4,613,431~4,628,546 cycles다. 현재 benchmark 5,328,877 대비 13.14~13.43% 감소다.

Triple-Row Build는 measurement만 줄이며 executed iterations와 세 축 policy의 objective function,
후보 집합, tie-break를 바꾸지 않는다.

## 3. Triple-Row Build resource

실제 Stage 4 → Stage 5(Dual-Row Build) 증가량은 SoC 기준 LUT +3,070, FF +2,561, BRAM +1,
DSP +64였다. 세 번째 squarer는 같은 DSP 64개와 pipeline을 한 벌 더 쓰고,
3-way dispatch와 세 번째 row-weight bank가 필요하다. placement 전 범위는 다음처럼
잡는다.

| resource | Triple-Row Build 추가 예상 | Triple-Row Build 전체 예상 | 100T 사용률 |
|---|---:|---:|---:|
| LUT | +3,500~4,500 | 48,616~49,616 | 76.7~78.3% |
| FF | +2,600~3,500 | 47,810~48,710 | 37.7~38.4% |
| BRAM tile | +1 | 117 | 86.7% |
| DSP | +64 | 196 | 81.7% |

표의 primitive 총량에는 여유가 있지만 slice는 현재 879개만 남았다. LUT/FF의
control set, DSP/BRAM 열 주변 congestion, 736-bit data 경로 때문에 빈 LUT가 그대로
사용 가능한 slice 여유를 뜻하지 않는다. 따라서 Triple-Row Build의 판정은 **resource 수 PASS,
place/route 고위험**이다.

현재 source의 compact a Checkpoint-Capacity of 3 and 3-shot Lookahead memo table이 의도대로 4 RAMB36에서 1 RAMB18로 줄면 BRAM은
위 보수값보다 3.5 tile 낮아질 수 있다. 이 절감은 아직 같은 조건의 최종 implementation
report가 없으므로 위 표에는 반영하지 않았다.

## 4. a Checkpoint-Capacity of 5 저장 용량과 4 PEs bandwidth

현재 4 PEs checkpoint memory는 다음 구조다.

```text
phase 0: 네 checkpoint slot의 row 4q+0, depth 4×128 = 512
phase 1: 네 checkpoint slot의 row 4q+1, depth 4×128 = 512
phase 2: 네 checkpoint slot의 row 4q+2, depth 4×128 = 512
phase 3: 네 checkpoint slot의 row 4q+3, depth 4×128 = 512

각 phase = 512×736 = 11 RAMB36
현재 네 phase의 sum = 44 RAMB36
```

현재 RTL의 physical slot address와 metadata mask도 각각 2 bits와 4 bits라 a Checkpoint-Capacity of 5는
parameter 한 줄 변경이 아니라 memory, Checkpoint Planner, Checkpoint Executor interface 확장이다.

그래서 한 checkpoint state의 순수 저장 bit 수는 약 11 RAMB36이지만, 다섯 번째
state를 같은 4 rows/cycle read+write bandwidth로 붙일 때 11개만 추가할 수는 없다.

- 기존 phase를 640×736으로 늘리면 RAM 깊이 경계 때문에 약 84~88 RAMB36이
  필요하다. 현재 44개 대비 **+40~44**다.
- fifth slot만 별도 4-phase bank로 붙이면 **+44 RAMB36**이다.
- +11 RAMB36은 fifth slot을 1 row/cycle cold storage로 둘 때의 용량 lower bound다.
  이 경우 실행 전에 네 hot slot 중 하나와 state를 교환해야 한다.

따라서 아래 두 종류를 구분해야 한다.

| a Checkpoint-Capacity of 5 방식 | checkpoint 추가 | a Checkpoint-Capacity of 5 and 5-shot Lookahead+Triple-Row Build SoC BRAM | 판정 |
|---|---:|---:|---|
| full-speed 4 PEs, repacking | +40 | 약 156 / 135 | 불가 |
| full-speed 4 PEs, fifth 4-phase 별도 | +44 | 약 160 / 135 | 불가 |
| cold fifth slot, 1 row/cycle | +11 | 약 127 / 135 | 용량상 가능, swap latency 큼 |

여기서 156은 기존 116에서 legacy policy memo table 4 RAMB36을 a Checkpoint-Capacity of 5 and 5-shot Lookahead dense memo table
3 RAMB36으로 교체(-1), full-speed checkpoint +40, Triple-Row Build row-weight +1을 적용한 값이다.
a Checkpoint-Capacity of 5 and 6-shot Lookahead memo table은 최소 5 RAMB36이라 같은 계산으로 약 158/135다.

## 5. a Checkpoint-Capacity of 5 policy memo table lower bound

새 dense rank를 만든다는 가정에서 a Checkpoint-Capacity of 5의 stage별 state 수는
(Checkpoint-Capacity + Lookahead-Shots + 1)개 중 0~5개를 고르는 combination 수의 sum이고, entry는 그 값에 Lookahead-Shots를 곱한 수다. 18-bit entry, RAMB36당
2,048 entry로 계산한 최소량이다.

| Lookahead-Shots | entry | policy RAMB36 최소 | cold fifth slot + Triple-Row Build SoC BRAM |
|---:|---:|---:|---:|
| 1 | 120 | 1 | 125 / 135 |
| 2 | 438 | 1 | 125 / 135 |
| 3 | 1,146 | 1 | 125 / 135 |
| 4 | 2,552 | 2 | 126 / 135 |
| 5 | 5,120 | 3 | 127 / 135 |
| 6 | 9,516 | 5 | 129 / 135 |
| 7 | 16,660 | 9 | 133 / 135 |
| 8 | 27,784 | 14 | 138 / 135 |

이 표조차 cold storage 가정이다. 8-shot Lookahead는 저장 용량만으로도 초과하고 7-shot Lookahead는 2 tile만
남아 implementation 여유가 없다. full-speed 4 PEs의 a Checkpoint-Capacity of 5는 Lookahead-Shots와 무관하게 checkpoint bandwidth에서
이미 초과한다.

## 6. a Checkpoint-Capacity of 5의 가상 성능과 현실적인 비교

full-speed 4 PEs가 들어간다고 가정한 기존 full-bound model에 Triple-Row Build 순절감 범위를
적용하면 다음과 같다. 이는 **resource 제약과 cold swap을 무시한 상한 성능**이다.

| Checkpoint-Capacity | Lookahead-Shots | Dual-Row Build · Two-Level Select full-bound | Triple-Row Build 가상 총 cycles | 현재 benchmark 대비 감소 |
|:-:|:-:|---:|---:|---:|
| 3 | 3 | 5,242,686 | 4,613,431~4,628,546 | 13.14~13.43% |
| 4 | 5 | 5,110,637 | 4,481,382~4,496,497 | 15.62~15.91% |
| 5 | 5 | 5,085,219 | 4,455,964~4,471,079 | 16.10~16.38% |
| 5 | 6 | 5,083,988 | 4,454,733~4,469,848 | 16.12~16.40% |

a Checkpoint-Capacity of 5 and 5-shot Lookahead는 a Checkpoint-Capacity of 4 and 5-shot Lookahead보다 25,418 cycles, a Checkpoint-Capacity of 5 and 6-shot Lookahead는 a Checkpoint-Capacity of 5 and 5-shot Lookahead보다 1,231 cycles만 빠르다. cold
fifth-slot swap 1회를 512 cycles로 보면 a Checkpoint-Capacity of 5 and 5-shot Lookahead의 a Checkpoint-Capacity of 4 and 5-shot Lookahead 대비 이득은 50회 미만의
swap에서만 유지된다. 7,403번의 policy 결정 동안 다섯 번째 checkpoint가 실제로
유용하려면 50회보다 훨씬 자주 접근될 가능성이 높으므로 cold a Checkpoint-Capacity of 5는 불리하다.

## 7. 최종 판단과 다음 순서

1. Triple-Row Build는 policy 세 축을 바꾸지 않고 약 11.5~11.8% 총 cycles을 줄일 가능성이 있다.
2. Triple-Row Build의 DSP·BRAM 총량은 가능하지만 slice 94.45% 때문에 먼저 OOC synthesis와 100T
   place/route를 해야 한다.
3. a Checkpoint-Capacity of 5 full-speed는 100T BRAM상 불가하다. 기존의 “+11 RAMB36”은 저장 용량
   lower bound일 뿐 4 PEs bandwidth 비용이 아니다.
4. 성능/resource 균형 후보는 **Triple-Row Build+a Checkpoint-Capacity of 4 and 5-shot Lookahead**다. 기존 네 hot checkpoint를 그대로 써서
   a Checkpoint-Capacity of 5의 memory bandwidth 문제를 피하며, 가상 a Checkpoint-Capacity of 5 and 5-shot Lookahead보다 약 25k cycles(0.48%)만 느리다.
5. a Checkpoint-Capacity of 5를 논문 heatmap용 software/policy 결과로 유지하는 것은 가능하지만, 100T
   full-speed implementation 후보로 표기하면 안 된다.

## 근거 file

- `documents/reports/09_measurement_bottleneck_and_microarchitecture.md`
- `documents/reports/18_six_stage_ablation_comparison.md`
- `documents/reports/24_seed_first_branch_and_bound_40_cell_prediction.md`
- `hardware_bram/src/grover_checkpoint.v`
- `hardware_bram/src/grover_policy.v`
- `hardware_bram/results/archive/policy_search/2026-10-26_policy_search_full40_seedfull/full40_estimates.csv`
