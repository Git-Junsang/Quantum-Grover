# Board-Verified Build core 250쌍 RTL testbench — board benchmark와 workload별 대조

## 무엇인가

`hardware_bram/src/` 의 Board-Verified Build core(final configuration)를 `make -C hardware_bram/sim bench250`
으로 250 workloads(1/4/16/64/256 solutions × 50 seeds)에 걸어 돌린 결과입니다. Bus Interface도
Board-Verified Build 그대로이고, 자극은 실제 driver(`bbht_grover_driver.c`)를 그대로 compile해 넣습니다.

돌린 목적은 두 가지입니다.

1. BBHT trajectory 불변식 — 같은 seed에서 Restart mode와 Checkpoint mode가 `trial_count`·`L_BBHT` 를
   같게 내는가. checkpoint는 amplitude를 어떻게 계산하느냐만 바꾸지 BBHT trajectory를
   바꾸지 않아야 합니다
2. board와 맞는가 — 2026-09-08 final configuration board benchmark의 앞 50 seeds와 workload별 대조

## 확정 수치

| 항목 | Restart mode | Checkpoint mode |
|---|---:|---:|
| executed iterations | 14,883 | 4,457 (-70.05%) |
| cycle | 5,648,298 | 2,563,403 (-54.62%) |
| policy stall | — | 93,297 (Checkpoint mode cycle의 3.64%) |
| 총 shot | 3,647 | 3,647 |
| Plan Queue miss | — | 0 |

BBHT trajectory 불변식 **250/250 일치**.

## board benchmark와의 대조 (2026-09-08 final configuration, 같은 core)

| 항목 | 일치 |
|---|---:|
| `result_index` | **250/250** |
| `trial_count` | **250/250** |
| `L_BBHT` | **250/250** |
| `actual_iter` | **250/250** |
| `cycle_count` | 230/250 |

cycle 합계는 simulation 2,563,403 대 board 2,556,312 으로 **+0.28%** 입니다. 어긋난
20건은 대부분 ±3,279 cycles이고, 이는 Six-Stage Ablation campaign이 board와 보이던
차이와 같은 크기입니다. board는 500 workloads를 연달아 돌아 checkpoint 준비
비용을 앞에서 한 번만 내는 데 비해 이쪽은 250개만 도는 차이로 보이지만,
**원인을 확정하지는 않았습니다.** 그래서 report는 cycle을 세어서 보여만 주고
실패로 잡지 않습니다.

BBHT trajectory 축(`result_index` · `trial_count` · `L_BBHT` · `actual_iter`)이 250/250 이라는 것이 이 testbench의 핵심입니다.
Six-Stage Ablation campaign은 같은 축에서 473/500 이 3,279 cycles 어긋났는데, 이쪽은 230/250 이
정확히 0 입니다 — driver로 연속 실행하는 이 harness가 board 실행 방식에 더
가깝기 때문으로 보입니다.

## 2026-09-04 Stage 2 묶음과는 무엇이 같고 다른가

| 항목 | board Stage 2 | 이 testbench final configuration | |
|---|---:|---:|---|
| 총 shot | 3,647 | 3,647 | **같아야 하고 같습니다** |
| Restart mode executed iterations | 14,883 | 14,883 | **같아야 하고 같습니다** |
| Checkpoint mode executed iterations | 4,247 | 4,457 | +4.94%. Checkpoint-Capacity 4 → 3이라 정상 |
| Restart mode cycle | 20,229,755 | 5,648,298 | -72.08%. core가 다릅니다 |
| Checkpoint mode cycle | 7,796,908 | 2,563,403 | -67.12%. core가 다릅니다 |

Checkpoint mode executed iterations가 4.94% 늘어난 것은 Six-Stage Ablation 이 500 workloads에서 본
a Checkpoint-Capacity of 4 · 4-shot Lookahead의 9,058 → a Checkpoint-Capacity of 3 · 3-shot Lookahead의 9,582 (+5.78%) 와 같은 방향·같은 크기입니다.

**Restart mode cycle을 board와 맞대 인용하지 마십시오.** 지금 `src/` 는 4 PEs와 Dual-Row Build ·
Two-Level Select가 compile돼 있고 `CHECKPOINT_ENABLE=1` 이라, mode0(Restart mode)도 Six-Stage
Ablation의 Stage 1과 다른 물건입니다. Stage 1은 `NUMBER_OF_PES=1`
build의 mode0 입니다.

## reference model과는 일치하지 않습니다

같은 250 workloads를 `software/reference_model_develop/models/` 의 reference model로 돌리면 답은 250/250 모두
유효한 solution이지만 BBHT trajectory는 다릅니다 (`result_index` 66/250, `trial_count` 36/250).
reference model이 Measurement PRNG의 random number 확장과 Checkpoint Planner를 **가정**으로 두고 있기
때문입니다 (`MEASUREMENT_ASSUMPTION` · `CHECKPOINT_ASSUMPTION`). reference model은
oracle·fixed-point·FIFO·종료 조건을 보는 의미 참조이지 BBHT trajectory 재현기가 아닙니다.

## file

| file | 내용 |
|---|---|
| `per_workload.csv` | 250 workloads × 2 modes 원본 (결과·BBHT trajectory·cycle·policy 계측) |
| `report.txt` | `sim/bench250_report.py` 출력 |
