# Six-Stage Ablation — RTL cycle campaign (500 workloads)

## 무엇인가

같은 source를 compile-time parameter만 바꿔 다섯 벌 만들고, 각각을 500 workloads에
걸어 `CSR_CYCLE_COUNT` 를 잰 cycle-accurate RTL simulation입니다. 우리 설계가
단계마다 무엇을 얼마나 벌었는지를 분리해 보여 주는 것이 목적입니다.

- workload: 1 · 4 · 16 · 64 · 256 solutions × 100 seeds = **500**
- configuration: 5벌. `k4h4_e1` 한 벌이 runtime mode0/mode1로 Stage 1과 Stage 2 두 단계를
  다 내주므로 **5 configurations × 500 = 2,500회 simulation → 여섯 단계 3,000 관측**
- simulator: iverilog + vvp

parameter는 넷뿐입니다.

| parameter | 뜻 |
|---|---|
| `CKPT_K` | checkpoint 몇 벌을 들고 있는가 (4 → 3) |
| `POLICY_H_FUTURE` | Policy Engine이 몇 shot 앞을 보는가 (4 → 3) |
| `INTRA_ENGINES` | Grover iteration 한 번에 협력하는 32-lane PE의 수 (1 PE → 4 PEs) |
| `MEAS_M1_ENABLE` · `MEAS_M2_ENABLE` | Measurement Unit 최적화 두 단계 (Dual-Row Build, Two-Level Select) |

## 확정 수치

| 단계 | 총 cycle | Stage 1 대비 | 직전 단계 대비 |
|---|---:|---:|---:|
| Stage 1 | 42,308,335 | 1.0000× | — |
| Stage 2 | 18,349,320 | 2.3057× | -56.63% |
| Stage 3 | 11,246,755 | 3.7618× | -38.71% |
| Stage 4 | 10,385,795 | 4.0737× | -7.66% |
| Stage 5 | 8,500,620 | 4.9771× | -18.15% |
| **final configuration** | **6,890,470** | **6.1401×** | **-18.94%** |

solution이 희소할수록 이득이 큽니다.

| number of solutions | Stage 1 | final configuration | speedup |
|---:|---:|---:|---:|
| 1 | 20,927,701 | 2,534,469 | 8.257× |
| 4 | 10,612,791 | 1,636,791 | 6.484× |
| 16 | 6,145,825 | 1,199,262 | 5.125× |
| 64 | 3,049,765 | 858,971 | 3.551× |
| 256 | 1,572,253 | 660,977 | 2.379× |

executed iterations는 Stage 1의 31,424에서 Stage 2 이후 9,058~9,582로 떨어집니다.
a Checkpoint-Capacity of 3, 3-shot Lookahead가 a Checkpoint-Capacity of 4, 4-shot Lookahead보다 executed iterations를 조금 더 쓰면서도(9,058 → 9,582) 총 cycle에서
이기는 것이 이 표의 핵심입니다 — Lookahead-Shots를 줄이면 policy 결정 비용이 줄어듭니다.

## verification

`validation.txt` 기준입니다.

- TB PASS log 2,500/2,500, workload 완료 500/500, 단계 관측 3,000/3,000
- 논리 동치 500/500, 불량 log 0
- 결정 anchor (256 solutions, seed 0): `18108 / 14898 / 12209 / 11100 / 9052 / 7045` 6단계 전부 일치

## 이 숫자를 쓸 때의 경계

**`6.1401x` 는 RTL cycle 축입니다.** board wall-clock time이 아닙니다. board 쪽
근거는 `hardware_bram/configurations/final/vivado/vivado_bbht_grover_fpga/2026-09-08_k3h3_e4_m2_board_500run/`
이고, 같은 BBHT trajectory를 따르지만 cycle 값 자체는 다릅니다 (그쪽 evidence.md 참조).

**재현 source는 tag `board-verified-build-2026-09-07` 에 있습니다.** ablation study용 공통 source와 top
5벌은 그 tag의 `hardware_bram/src_ablation/`, TB 는 `testbench/tb_publication_plusargs.v`,
runner는 `sim/run_publication.py` 입니다. 거기서 `make -C hardware_bram/sim anchor` 가
256 solutions · seed 0 하나로 여섯 단계 cycle을 정확 대조하고(2026-09-13 확인, 여섯 단계
전부 일치), `make -C hardware_bram/sim publication` 이 2,500회를 전부 돌려
`summary.csv` 의 총합과 맞댑니다. top들이 standalone 틀이라 main에서는 뺐습니다.
이 directory는 결과와 expected result만 보관합니다.

그 공통 source는 Board-Verified Build에 `MEAS_M1_ENABLE` · `MEAS_M2_ENABLE` switch를 더한 것이고,
2026-09-13부터 main의 `hardware_bram/src/` Accelerator Core가 바로 이것입니다(byte 동일).
두 switch를 다 1(기본)로 두면 Board-Verified Build와 동작이 같습니다 — 즉 Six-Stage Ablation의 마지막 칸이
`src/` 가 하는 일입니다.

## file

| file | 내용 |
|---|---|
| `summary.csv` | 여섯 단계 집계 (총합·mean·median·standard deviation·p95·speedup) |
| `by_target.csv` | number of solutions별로 쪼갠 같은 표 |
| `observations.csv` | 3,000 관측 원본 (workload × 단계) |
| `workload_wide.csv` | 500 workloads를 가로로 편 표 |
| `workloads.csv` · `seeds.csv` | workload 목록과 seed roster 100개 |
| `validation.txt` | campaign 무결성·anchor·freeze 점검 결과 |
