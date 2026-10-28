# 200 MHz revision RTL — 100 MHz revision과 BBHT trajectory 4,000/4,000 일치, cycle +5.0% / +10.1%

## 무엇인가

`final_200mhz` configuration(final configuration을 `clk_accel` 200 MHz에 맞추려고 pipeline
register를 더한 RTL)을 `make -C hardware_bram/configurations/final_200mhz/sim predicate500`
으로 돌린 결과입니다. harness · stimulus · expected result는 final configuration의
[Predicate500 묶음](../../../final/results/2026-09-25_predicate500_rtl/evidence.md)과
같습니다. 네 predicate × 다섯 가지 number of solutions × 100 seeds를 Restart mode와 Checkpoint mode로 짝지어 4,000번 실행합니다.

이 revision이 RTL에 더한 것은 pipeline register뿐이라, 값은 그대로이고 latency만 늘어야 합니다. 그래서 두 가지를
봅니다.

1. software reference model과 맞는가 (`report.txt`)
2. 100 MHz revision과 실행마다 cycle 말고 전부 같은가 (`equiv.txt`)

2번의 기준은 같은 harness로 공용 `hardware_bram/src/` 를 돌린 결과입니다. 그 결과는 위 final
묶음의 `per_workload.csv` 와 cycle까지 4,000/4,000 같아서 따로 두지 않았습니다.

## 확정 수치

| 대조 | 결과 |
|---|---|
| software reference model (rc · result_index · predicate · trial_count · L_BBHT · actual_iter) | 8개 조합 모두 500/500 |
| 100 MHz revision과 cycle 외 전 열 (rc · result_index · result_value · trial · l_bbht · iter · status) | 4,000/4,000 |
| Bus Interface 계약 regression T1~T10 (`make real`, enumeration 포함) | 오류 0건 |
| driver co-simulation D1~D11 (`make driver`) | 오류 0건 |

cycle(RTL cycle 축). 시간 비는 cycle 비에 clock 비 1/2을 곱한 값이고 benchmark가 아닙니다.

| predicate | mode | 100 MHz revision | 200 MHz revision | cycle 비 | 시간 비 |
|---|---|---:|---:|---:|---:|
| LT | Restart mode | 11,625,100 | 12,204,253 | 1.0498 | 0.5249 |
| LT | Checkpoint mode | 5,274,562 | 5,809,649 | 1.1014 | 0.5507 |
| GT | Restart mode | 12,241,889 | 12,851,364 | 1.0498 | 0.5249 |
| GT | Checkpoint mode | 5,456,355 | 6,004,889 | 1.1005 | 0.5503 |
| EQ | Restart mode | 11,785,382 | 12,372,608 | 1.0498 | 0.5249 |
| EQ | Checkpoint mode | 5,328,877 | 5,868,798 | 1.1013 | 0.5507 |
| RANGE | Restart mode | 11,234,306 | 11,794,224 | 1.0498 | 0.5249 |
| RANGE | Checkpoint mode | 5,033,332 | 5,549,167 | 1.1025 | 0.5512 |
| sum | Restart mode | 46,886,677 | 49,222,449 | 1.0498 | 0.5249 |
| sum | Checkpoint mode | 21,093,126 | 23,232,503 | 1.1014 | 0.5507 |

Restart mode의 증가분은 iteration 한 번마다 붙는 고정 latency(memory 읽기 2→4 cycles, datapath · adder tree ·
Mean의 pipeline stage)와 Measurement Unit · solution check의 stall입니다. Checkpoint mode가 더 늘어나는 것은 Policy Engine이 action을 두 cycle에
하나씩 내고 pipeline stage를 더 거치기 때문입니다.

## 인용할 때

- RTL cycle 축입니다. board wall-clock time이 아니고, 이 revision은 board에서 잰 적이 없습니다.
- "시간 비"는 200 MHz로 실제 동작한다고 가정한 계산값입니다. board benchmark와 섞지 마십시오.
- Checkpoint mode cycle은 실행 이력에 달려 있습니다. predicate마다 process를 새로 띄웠으므로 memo table 청소가
  predicate마다 한 번 들어 있고, 100 MHz revision도 같은 조건입니다.

## 재현

```bash
make -C hardware_bram/configurations/final_200mhz/sim predicate500 predicate500-ref equiv
make -C hardware_bram/configurations/final_200mhz/sim real driver
```

Policy Engine에는 simulation 전용 검사(`POLICY_ASSERT`)가 두 개 있습니다. 빠른 조합 생성기가 원래 function과 다르거나,
non-root 결과가 연달아 같은 frame에 들어오면 표준출력에 찍힙니다. 이 실행에서는 한 번도 찍히지
않았습니다.

## file

| file | 내용 |
|---|---|
| `per_workload.csv` | 실행 4,000 rows. `predicate,m,seed_idx,mode,rc,result_index,result_value,trial,l_bbht,iter,cycles,status` |
| `report.txt` | `sim/predicate500_report.py --branch bram` 출력 |
| `equiv.txt` | `sim/equiv_check.py` 출력 (100 MHz revision 대조) |
| `regress.txt` | `make real` · `make driver` 의 항목별 결과 |
