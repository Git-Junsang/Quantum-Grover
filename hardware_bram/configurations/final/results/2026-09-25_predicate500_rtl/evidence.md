# 네 predicate × 500 workloads RTL testbench — software reference model과 4,000/4,000 일치

## 무엇인가

`hardware_bram/src/`(main의 최신 revision, final configuration)를 `make -C hardware_bram/sim predicate500`
으로 **LT · GT · EQ · RANGE 네 predicate 각각에 500 workloads**를 걸어 돌린 결과입니다.
Restart mode(`burst_enable=0`)와 Checkpoint mode(`burst_enable=1`)를 같은 seed로 짝지어 돌려
실행은 모두 4,000번입니다.

지금까지 benchmark 규모로 검증된 predicate는 EQ 하나뿐이었습니다. board 500 runs와 Common500이
전부 EQ이고, LT · GT · RANGE는 verilator regression(`tb_bbht_bram_top` H5 · C4 · C5)에서 몇
건만 돌았습니다. 이 묶음이 나머지 세 predicate의 comparator 경로를 같은 규모로 채웁니다.

- harness: `testbench/tb_predicate500.cpp`. Bus Interface + adapter + Accelerator Core를 **실제 firmware
  driver**(`firmware/bbht_grover_driver.c`)로 APB/AHB를 거쳐 두드립니다
- stimulus: `software/reference_model_develop/tb_stimulus/dump_predicate500_workload.py`
- expected result: `software/reference_model_data/2026-09-25_predicate500/predicate500_expected.csv`
  (Q1.22 bit-exact reference model `V098AutomaticCore`)
- 순서: predicate마다 process 하나. dataset을 load하고 seed 0~99를 차례로, seed마다
  Restart mode 다음 Checkpoint mode. board app과 같은 순서입니다

## workload

1 · 4 · 16 · 64 · 256 solutions × 공식 seed 100쌍 = 500 workloads를 predicate마다 씁니다. seed roster는
board 500 runs·Common500과 같습니다.

| predicate | threshold | solution 값 범위 | 위치 seed |
|---|---|---|---|
| LT | A = −16384 | [−32768, −16385] | 0x17A02026 |
| GT | A = 16383 | [16384, 32767] | 0x67A02026 |
| EQ | A = 12345 | 12345 | 0xA17E2026 |
| RANGE | A = −4096, B = 4096 (open interval) | [−4095, 4095] | 0x3A4E2026 |

배경은 공식 testbench와 같은 xorshift32(0x5EED1234)이고, predicate를 만족하는 배경 값은 non-solution
쪽으로 접어 넣어서 심은 자리만 정확히 solution입니다(규칙은
`software/reference_model_develop/models/common/benchmark_dataset.py` 의 `generate_predicate_image`). **EQ는 공식
Common500 dataset과 byte 단위로 같습니다** — 생성기가 스스로 확인하고, sha256도
`dump_bench_workload.py` 가 못박은 값과 같습니다.

## 확정 수치

| predicate | mode | 실행 | rc | result_index | predicate verification | trial_count | L_BBHT | actual_iter |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| LT | Restart mode | 500 | 500/500 | 500/500 | 500/500 | 500/500 | 500/500 | 500/500 |
| LT | Checkpoint mode | 500 | 500/500 | 500/500 | 500/500 | 500/500 | 500/500 | 500/500 |
| GT | Restart mode | 500 | 500/500 | 500/500 | 500/500 | 500/500 | 500/500 | 500/500 |
| GT | Checkpoint mode | 500 | 500/500 | 500/500 | 500/500 | 500/500 | 500/500 | 500/500 |
| EQ | Restart mode | 500 | 500/500 | 500/500 | 500/500 | 500/500 | 500/500 | 500/500 |
| EQ | Checkpoint mode | 500 | 500/500 | 500/500 | 500/500 | 500/500 | 500/500 | 500/500 |
| RANGE | Restart mode | 500 | 500/500 | 500/500 | 500/500 | 500/500 | 500/500 | 500/500 |
| RANGE | Checkpoint mode | 500 | 500/500 | 500/500 | 500/500 | 500/500 | 500/500 | 500/500 |

`actual_iter` 는 Restart mode가 expected result의 `NORMAL` 열, Checkpoint mode가 `K3H3` 열과 맞댑니다.
4,000 실행 모두 solution을 찾았습니다(reference model도 2,000/2,000 성공).

cycle(clk_accel 100 MHz 기준, reference model에는 없는 축):

| predicate | Restart mode cycle | Checkpoint mode cycle | speedup | Restart mode executed iterations | Checkpoint mode executed iterations |
|---|---:|---:|---:|---:|---:|
| LT | 11,625,100 | 5,274,562 | 2.2040× | 30,875 | 9,355 |
| GT | 12,241,889 | 5,456,355 | 2.2436× | 33,131 | 10,008 |
| EQ | 11,785,382 | 5,328,877 | 2.2116× | 31,424 | 9,582 |
| RANGE | 11,234,306 | 5,033,332 | 2.2320× | 29,676 | 8,714 |

number of solutions별로 보면 네 predicate가 같은 모양입니다 — 희소할수록(solution이 적을수록) Checkpoint mode의 speedup이
큽니다(1 solution에서 2.53~2.57×, 256 solutions에서 1.43~1.47×).

## harness가 믿을 만한가

EQ 1,000 실행(500 × 두 mode)이 [`2026-09-10_bench500_final_core/per_workload.csv`](../2026-09-10_bench500_final_core/per_workload.csv)
와 `result_index` 와 **cycle까지 1,000/1,000 같습니다.** 그 묶음은 board final configuration benchmark와
cycle까지 500/500 맞은 근거라, 새 harness가 같은 조건에서 같은 값을 낸다는 뜻입니다.
EQ expected result 500 rows도 board benchmark(`fpga_normal_per_run.csv` · `fpga_final_k3h3_e4_m2_per_run.csv`)와
네 축 모두 500/500입니다.

## 인용할 때

- 이것은 **RTL cycle 축**입니다. board wall-clock time이나 Common500 software 시간과
  speedup을 만들지 마십시오(CLAUDE.md 2절).
- Checkpoint mode cycle은 실행 이력에 달려 있습니다. predicate마다 process를 새로 띄웠으므로
  reset 뒤 첫 checkpoint search의 memo table 청소(3,279 cycles)가 predicate마다 한 번씩 들어 있습니다.
- board에서 같은 workload를 돌리는 길은 `software/host_fpga_develop/bbht_predicate500.py` 입니다.

## 재현

```bash
python3 software/reference_model_develop/predicate500/run_predicate500_golden.py   # 기댓값 (30초)
make -C hardware_bram/sim predicate500                                           # 술어 넷 동시 (수 분)
```

## file

| file | 내용 |
|---|---|
| `per_workload.csv` | 실행 4,000 rows. `predicate,m,seed_idx,mode,rc,result_index,result_value,trial,l_bbht,iter,cycles,status` |
| `report.txt` | `sim/predicate500_report.py --branch bram` 출력 |
