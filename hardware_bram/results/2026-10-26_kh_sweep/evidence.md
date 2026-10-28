# Checkpoint-Capacity · Lookahead-Shots policy design space sweep 근거

## 범위

- workload: Common500의 bit-exact request BBHT trajectory 500개
- policy 결정: 7,403회
- software exact sweep: Checkpoint-Capacity 1~5, Lookahead-Shots 1~8
- standalone RTL sweep: 현재 interface가 지원하는 Checkpoint-Capacity 3~4, Lookahead-Shots 1~8
- integrated stall: 4 PEs · Single-Row Build · Linear Select로 조건이 같은 기존 bench500의 두 configuration(a Checkpoint-Capacity of 3, 3-shot Lookahead / a Checkpoint-Capacity of 4, 4-shot Lookahead)

`kh_sweep.csv`가 source of truth 표이고 `kh_heatmap.png`와 `kh_heatmap.svg`는 그 표를
그린 것입니다. 회색 `n/a`는 추정값이 아니라 아직 implementation이나 benchmark를 하지 않은 cell입니다.

## benchmark 지표 정의

- `physical_reduction_pct`: 같은 request BBHT trajectory의 Restart mode executed iterations 대비 감소율
- `actions_per_decision`: exact restricted-B DP가 평가한 transition 수 / policy 결정 수
- `rtl_cycles_per_decision`: standalone RTL의 `start`부터 `done`까지 총 clock / 결정 수
- `rtl_max_latency`: 한 결정의 최대 `start`→`done` clock
- `stall_ratio_pct`: integrated RTL의 `policy_stall / checkpoint total cycles`

standalone RTL mean에는 최초 memo table 청소와 8-bit epoch 순환 청소가 실제 발생 빈도로
포함됩니다. a Checkpoint-Capacity of 3, 3-shot Lookahead는 compact 381-entry memo table이고, 나머지 cell은 현재 legacy 1,093-rank
stride를 사용하므로 Lookahead-Shots 사이의 mean 비교에는 현재 implementation의 initialization 비용도 포함됩니다.
stall 1.32%와 6.68%는 Checkpoint-Capacity · Lookahead-Shots만 비교하려고 Dual-Row Build · Two-Level Select를 끈 2026-10-07 4 PEs ablation study
값입니다. a Checkpoint-Capacity of 3, 3-shot Lookahead의 memo table 압축 전 integrated run이므로 현재 RTL의 새 stall 확정값이
아니며, final configuration 수치와도 섞지 않습니다.

## 주요 값

| Checkpoint-Capacity | Lookahead-Shots | executed iterations 감소 | actions/decision | RTL cycles/decision | 최대 latency | integrated stall |
|:-:|:-:|---:|---:|---:|---:|---:|
| 3 | 3 | 69.51% | 22.7 | 159.8 | 811 | 1.32% |
| 3 | 4 | 70.17% | 42.3 | 275.7 | 5,289 | 재지 않음 |
| 3 | 8 | 70.56% | 318.8 | 1,339.5 | 13,228 | 재지 않음 |
| 4 | 4 | 71.17% | 78.2 | 383.8 | 6,532 | 6.68% |
| 4 | 5 | 71.63% | 157.3 | 664.9 | 10,967 | 재지 않음 |
| 4 | 8 | 71.95% | 985.1 | 2,916.9 | 39,622 | 재지 않음 |
| 5 | 5 | 71.94% | 294.6 | RTL 미구현 | RTL 미구현 | RTL 미구현 |

a Checkpoint-Capacity of 5, 5-shot Lookahead는 a Checkpoint-Capacity of 4, 4-shot Lookahead보다 executed iterations 감소율이 0.77%p 높지만 software action 수는 3.77×입니다.
a Checkpoint-Capacity of 3, 3-shot Lookahead 대비로는 2.43%p 높고 action 수는 12.99×입니다. a Checkpoint-Capacity of 5, 5-shot Lookahead를 hardware 후보로
삼으려면 search 구조를 바꾸거나 deadline-aware 실행을 별도 실험으로 두어야 합니다.

## sweep 중 발견해 수정한 8-shot Lookahead 결함

1. 8-shot Lookahead에서 `j_window[8]` 대신 `j_window[7]`을 다시 읽던 고정 case index
2. 8 × 1,093 = 8,744 memo table entries에 필요한 다섯 번째 2,048-word bank 누락

수정 뒤 a Checkpoint-Capacity of 3, 8-shot Lookahead와 a Checkpoint-Capacity of 4, 8-shot Lookahead를 포함한 standalone RTL 16 cells 모두 7,403회 policy 결정에서
software exact policy와 source/next-set/action count가 일치했습니다.

## 재현

```bash
python3 hardware_bram/sim/kh_sweep.py \
  --k 1-5 --h 1-8 --rtl-k 3-4 --rtl-h 1-8 --run-rtl \
  --system 3,3,hardware_bram/results/2026-10-07_bench500_6models/k3h3_e4.csv \
  --system 4,4,hardware_bram/results/2026-10-07_bench500_6models/k4h4_e4.csv \
  --out hardware_bram/results/2026-10-26_kh_sweep
```

전체 RTL grid는 Icarus에서 오래 걸립니다. 중간 완료 cell은 `rtl_latency.csv`와
`rtl_k*h*.log`로 즉시 보존됩니다.
