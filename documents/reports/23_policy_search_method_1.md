# 실험 23. 방법 1: policy 불변 exact search 가속

> [← 실험 22](22_checkpoint_capacity_lookahead_shots_design_space.md) · [실험 보고서 index](index.md)

## 목표

Restricted-B, Rolling Lookahead, Iteration-Count Predictor와 root tie-break를 바꾸지 않고 동일한
checkpoint 결정을 더 적은 hardware cycle에 계산하는 것이 목표입니다.
기준 search는 Exhaustive DFS(top-down DFS와 stage/state cost memo table)입니다.

## software exact prototype

Checkpoint-Capacity 제한을 제거하고 합법적으로 만날 수 있는 checkpoint를 모두 유지하는
relaxed machine의 비용을 admissible lower bound로 사용했습니다. 모든 pruning은
현재 best보다 좋아질 수 없음이 증명된 경우에만 수행합니다. Common500의 7,403개
결정마다 기존 source와 다음 checkpoint tuple을 직접 비교했고 mismatch는 0건입니다.

대표 결과는 다음과 같습니다. `canonical/full`은 현재 action 순서를 유지하고 남은
전체 window relaxed bound를 사용합니다. `seed1/bound2`는 1단계 bound가 가장 좋은
action을 먼저 평가하고 2단계 relaxed bound로 pruning합니다.

| Checkpoint-Capacity | Lookahead-Shots | 기존 actions/결정 | canonical/full | 감소율 | seed1/bound2 | 감소율 |
|:-:|:-:|---:|---:|---:|---:|---:|
| 3 | 3 | 22.68 | 11.21 | 50.56% | 10.64 | 53.07% |
| 4 | 4 | 78.23 | 21.89 | 72.02% | 30.33 | 61.23% |
| 4 | 8 | 985.09 | 213.43 | 78.33% | 486.96 | 50.57% |
| 5 | 5 | 294.60 | 43.85 | 85.12% | 108.21 | 63.27% |

전체 bound로 가장 좋은 action 하나만 먼저 실행하는 `seed/full`은 a Checkpoint-Capacity of 4 and 8-shot Lookahead를
27.43 actions/결정까지 줄였지만, Lookahead 전체 단계의 bound를 1 action/cycle로 계산하려면
깊은 pipeline이 필요합니다.

## 첫 RTL: 1단계 bound

추가 BRAM 없이 memo table miss child의 다음 request 필수 비용만 계산했습니다.

```text
LB = current immediate
   + next_j - max(child checkpoint <= next_j)
```

non-root에서는 `LB >= frame best`, root에서는 tie-break를 보존하기 위해
`LB > root best`일 때만 child DFS를 생략합니다. Common500 standalone RTL 결과는
다음과 같습니다.

| Checkpoint-Capacity | Lookahead-Shots | action 변화 | 총 policy cycle 변화 | 최대 latency 변화 | 선택 오류 |
|:-:|:-:|---:|---:|---:|---:|
| 3 | 3 | -16.36% | -8.74% | -4.93% | 0 |
| 4 | 4 | -17.61% | -7.20% | +2.77% | 0 |
| 4 | 8 | -6.90% | **+8.60%** | **+11.98%** | 0 |

a Checkpoint-Capacity of 4 and 8-shot Lookahead에서는 action 수가 줄어도 총 cycle이 악화됐습니다. pruning한 state에는 exact
memo table value를 기록할 수 없으므로 다른 parent에서 같은 state를 만나면 memo table miss와
pipeline flush가 반복되기 때문입니다. 따라서 1단계 RTL pruning은 기본값을 꺼
두었고 최종 최적화로 채택하지 않습니다.

## 채택 RTL: memo table 앞 2단계 early-prune

실패 원인은 bound가 약해서가 아니라 pruning 위치가 memo table 응답 뒤였기 때문입니다.
따라서 action이 canonical sort/memo pipeline에 들어가기 전에 다음 두 request의 relaxed
lower bound를 계산하도록 옮겼습니다. pruning된 action은 memo table miss도, younger request
flush도 만들지 않습니다. request-pool maximum은 9단 직렬 비교가 아니라 균형 max-tree로
구성했습니다.

| Checkpoint-Capacity | Lookahead-Shots | 총 policy cycle | 감소율 | actions | 감소율 | 최대 latency | 감소율 | 오류 |
|:-:|:-:|---:|---:|---:|---:|---:|---:|---:|
| 3 | 3 | 1,183,308→933,966 | 21.07% | 167,908→128,208 | 23.64% | 811→701 | 13.56% | 0 |
| 4 | 4 | 2,841,616→1,985,090 | 30.14% | 579,120→404,606 | 30.13% | 6,532→6,257 | 4.21% | 0 |
| 4 | 8 | 21,593,720→18,354,629 | 15.00% | 7,292,597→6,659,765 | 8.68% | 39,622→33,582 | 15.24% | 0 |

Accelerator Core는 `POLICY_SEARCH_MODE=4`(Two-Request Bound Pruning)로 이 mode를 명시적으로 사용합니다. 공용 policy module의
기본값은 0으로 두어 기존 직접 instantiation은 보존합니다. Vivado 실행 file은 있지만
유효한 license가 없어 새 OOC synthesis와 100 MHz timing은 아직 확인하지 못했습니다.
따라서 cycle 수준에서만 채택한 것이며 board bitstream 성능 주장에는 아직 사용할 수 없습니다.

## 최적화 후 Checkpoint-Capacity · Lookahead-Shots 전체 sweep

Common500의 동일한 500 workload, 7,403 policy 결정을 사용해 RTL 지원 범위인
Checkpoint-Capacity 3 · 4와 Lookahead-Shots 1~8을 모두 다시 실행했습니다. `cycles/결정`은 policy `start`부터 `done`까지이며
memo table epoch initialization 비용도 포함합니다. 모든 cell의 선택 mismatch는 0건입니다.

| Checkpoint-Capacity | Lookahead-Shots | executed iterations 감소율 | 기존 cycles/결정 | 방법 1 cycles/결정 | latency 감소율 | 방법 1 최대 cycles |
|:-:|:-:|---:|---:|---:|---:|---:|
| 3 | 1 | 62.85% | 55.8 | 55.8 | 0.00% | 1,205 |
| 3 | 2 | 67.45% | 102.1 | 91.6 | 10.31% | 2,371 |
| 3 | 3 | 69.51% | 159.8 | 126.2 | 21.07% | 701 |
| 3 | 4 | 70.17% | 275.7 | 218.1 | 20.88% | 5,209 |
| 3 | 5 | 70.45% | 427.4 | 348.2 | 18.54% | 7,253 |
| 3 | 6 | 70.49% | 639.8 | 542.0 | 15.29% | 9,115 |
| 3 | 7 | 70.58% | 935.1 | 816.9 | 12.63% | 10,893 |
| 3 | 8 | 70.56% | 1,339.5 | 1,194.4 | 10.83% | 12,992 |
| 4 | 1 | 64.36% | 58.7 | 58.3 | 0.66% | 1,248 |
| 4 | 2 | 68.27% | 115.2 | 97.5 | 15.41% | 2,491 |
| 4 | 3 | 70.39% | 215.2 | 153.4 | 28.72% | 3,653 |
| 4 | 4 | 71.17% | 383.8 | 268.1 | 30.14% | 6,257 |
| 4 | 5 | 71.63% | 664.9 | 486.6 | 26.81% | 10,502 |
| 4 | 6 | 71.88% | 1,112.1 | 866.6 | 22.07% | 14,606 |
| 4 | 7 | 71.97% | 1,812.4 | 1,485.4 | 18.04% | 22,824 |
| 4 | 8 | 71.95% | 2,916.9 | 2,479.4 | 15.00% | 33,582 |

Lookahead-Shots가 커질수록 executed iterations 감소율은 빠르게 포화되지만 search latency는 계속 증가합니다.
예를 들어 a Checkpoint-Capacity of 4에서 4-shot Lookahead→8-shot Lookahead는 executed iterations 감소율이 71.17%→71.95%로 0.78%p만
좋아지는 반면 mean policy latency는 268.1→2,479.4 cycles로 9.25×가 됩니다. 따라서
현재 data에서는 4-shot Lookahead 또는 5-shot Lookahead가 실용 후보이며, 8-shot Lookahead는 정확도/감소율 heatmap만 보고
선택해서는 안 됩니다.

## Accelerator Core 통합 regression

`final` Bus Interface/driver regression T1~T10, D1~D11도 오류 0건으로 통과했습니다.
T10의 Checkpoint mode 실행 한 건에서는 총 accelerator 40,014 cycles, policy 5,321 cycles,
demand stall 821 cycles였습니다. 즉 이 사례의 stall은 policy 시간의 15.43%, 전체
accelerator 시간의 2.05%입니다. 이는 단일 regression 사례이므로 Common500 전체 stall
비율로 일반화하지 않습니다.

## 재현 자료

- software comparator: `hardware_bram/sim/policy_search_method1.py`
- 전체 exact 결과: `hardware_bram/results/2026-10-26_policy_search_method1/method1_search.csv`
- RTL on/off 결과: `hardware_bram/results/2026-10-26_policy_search_method1/rtl_prune1.csv`
- 채택 early-prune 결과: `hardware_bram/results/2026-10-26_policy_search_method1/rtl_early2.csv`
- 전체 Checkpoint-Capacity · Lookahead-Shots CSV: `hardware_bram/results/2026-10-26_kh_sweep_method1/kh_sweep.csv`
- 전체 Checkpoint-Capacity · Lookahead-Shots heatmap: `hardware_bram/results/2026-10-26_kh_sweep_method1/kh_heatmap.png`
- 깊이별 결과: 같은 날짜의 `policy_search_method1_depth*`, `*_seed*` directory
