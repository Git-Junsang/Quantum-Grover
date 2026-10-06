# 네 술어 × 500 워크로드 RTL 벤치 — SW 기준모델과 4,000/4,000 일치

## 무엇인가

`hardware_bram/src/`(main 의 최신판, K3/H3-E4-M2)를 `make -C hardware_bram/sim predicate500`
으로 **LT · GT · EQ · RANGE 네 술어 각각에 500 워크로드**를 걸어 돌린 결과입니다.
Normal(`burst_enable=0`)과 체크포인트(`burst_enable=1`)를 같은 시드로 짝지어 돌려
실행은 모두 4,000 번입니다.

지금까지 실측 규모로 검증된 술어는 EQ 하나뿐이었습니다. 보드 500런과 Common500 이
전부 EQ 이고, LT · GT · RANGE 는 verilator 회귀(`tb_bbht_bram_top` H5 · C4 · C5)에서 몇
건만 돌았습니다. 이 묶음이 나머지 세 술어의 비교기 경로를 같은 규모로 채웁니다.

- 하네스: `testbench/tb_predicate500.cpp`. 통신 계층 + 어댑터 + Main IP 를 **실제 펌웨어
  드라이버**(`firmware/bbht_grover_driver.c`)로 APB/AHB 를 거쳐 두드립니다
- 자극: `software/rtl_vectors/tools/dump_predicate500_workload.py`
- 기댓값: `software/experiments/predicate500_benchmark/expected/predicate500_expected.csv`
  (Q1.22 bit-exact 기준모델 `V098AutomaticCore`)
- 순서: 술어마다 프로세스 하나. 데이터셋을 적재하고 시드 0~99 를 차례로, 시드마다
  Normal 다음 체크포인트. 보드 앱과 같은 순서입니다

## 워크로드

M = 1 / 4 / 16 / 64 / 256 × 공식 시드 100쌍 = 500 을 술어마다 씁니다. 시드 로스터는
보드 500런·Common500 과 같습니다.

| 술어 | 임계값 | 정답 값 구간 | 위치 시드 |
|---|---|---|---|
| LT | A = −16384 | [−32768, −16385] | 0x17A02026 |
| GT | A = 16383 | [16384, 32767] | 0x67A02026 |
| EQ | A = 12345 | 12345 | 0xA17E2026 |
| RANGE | A = −4096, B = 4096 (열린구간) | [−4095, 4095] | 0x3A4E2026 |

배경은 공식 벤치와 같은 xorshift32(0x5EED1234) 이고, 술어를 만족하는 배경 값은 비정답
쪽으로 접어 넣어서 심은 M 개가 정확히 정답입니다(규칙은
`software/models/common/benchmark_dataset.py` 의 `generate_predicate_image`). **EQ 는 공식
Common500 데이터셋과 바이트 단위로 같습니다** — 생성기가 스스로 확인하고, sha256 도
`dump_bench_workload.py` 가 못박은 값과 같습니다.

## 확정 수치

| 술어 | 모드 | 실행 | rc | result_index | 술어 검증 | trial_count | L_BBHT | actual_iter |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| LT | normal | 500 | 500/500 | 500/500 | 500/500 | 500/500 | 500/500 | 500/500 |
| LT | ckpt | 500 | 500/500 | 500/500 | 500/500 | 500/500 | 500/500 | 500/500 |
| GT | normal | 500 | 500/500 | 500/500 | 500/500 | 500/500 | 500/500 | 500/500 |
| GT | ckpt | 500 | 500/500 | 500/500 | 500/500 | 500/500 | 500/500 | 500/500 |
| EQ | normal | 500 | 500/500 | 500/500 | 500/500 | 500/500 | 500/500 | 500/500 |
| EQ | ckpt | 500 | 500/500 | 500/500 | 500/500 | 500/500 | 500/500 | 500/500 |
| RANGE | normal | 500 | 500/500 | 500/500 | 500/500 | 500/500 | 500/500 | 500/500 |
| RANGE | ckpt | 500 | 500/500 | 500/500 | 500/500 | 500/500 | 500/500 | 500/500 |

`actual_iter` 는 Normal 이 기준모델 `NORMAL`, 체크포인트가 `K3H3` 열과 맞댑니다.
4,000 실행 모두 정답을 찾았습니다(기준모델도 2,000/2,000 성공).

사이클(clk_accel 100 MHz 기준, 기준모델에는 없는 축):

| 술어 | Normal 사이클 | 체크포인트 사이클 | 배수 | Normal 물리 반복 | 체크포인트 물리 반복 |
|---|---:|---:|---:|---:|---:|
| LT | 11,625,100 | 5,274,562 | 2.2040x | 30,875 | 9,355 |
| GT | 12,241,889 | 5,456,355 | 2.2436x | 33,131 | 10,008 |
| EQ | 11,785,382 | 5,328,877 | 2.2116x | 31,424 | 9,582 |
| RANGE | 11,234,306 | 5,033,332 | 2.2320x | 29,676 | 8,714 |

M 별로 보면 네 술어가 같은 모양입니다 — 희소할수록(M 이 작을수록) 체크포인트 배수가
큽니다(M=1 에서 2.53~2.57x, M=256 에서 1.43~1.47x).

## 하네스가 믿을 만한가

EQ 1,000 실행(500 × 두 모드)이 [`2026-09-10_bench500_final_core/per_workload.csv`](../2026-09-10_bench500_final_core/per_workload.csv)
와 `result_index` 와 **사이클까지 1,000/1,000 같습니다.** 그 묶음은 보드 M2 실측과
사이클까지 500/500 맞은 근거라, 새 하네스가 같은 조건에서 같은 값을 낸다는 뜻입니다.
EQ 기댓값 500행도 보드 실측(`fpga_normal_per_run.csv` · `fpga_final_k3h3_e4_m2_per_run.csv`)과
네 축 모두 500/500 입니다.

## 인용할 때

- 이것은 **RTL 사이클 축**입니다. 보드 실경과 시간이나 Common500 소프트웨어 시간과
  배수를 만들지 마십시오(CLAUDE.md 2절).
- 체크포인트 사이클은 실행 이력에 달려 있습니다. 술어마다 프로세스를 새로 띄웠으므로
  리셋 뒤 첫 체크포인트 탐색의 memo 청소(3,279 사이클)가 술어마다 한 번씩 들어 있습니다.
- 보드에서 같은 워크로드를 돌리는 길은 `software/host/bbht_predicate500.py` 입니다.

## 재현

```bash
python3 software/experiments/predicate500_benchmark/run_predicate500_golden.py   # 기댓값 (30초)
make -C hardware_bram/sim predicate500                                           # 술어 넷 동시 (수 분)
```

## 파일

| 파일 | 내용 |
|---|---|
| `per_workload.csv` | 실행 4,000행. `predicate,m,seed_idx,mode,rc,result_index,result_value,trial,l_bbht,iter,cycles,status` |
| `report.txt` | `sim/predicate500_report.py --branch bram` 출력 |
