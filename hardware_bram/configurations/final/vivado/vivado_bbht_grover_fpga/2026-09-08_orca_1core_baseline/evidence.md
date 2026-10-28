# ORCA 순수 software baseline — 같은 board, 같은 500 workloads

## 무엇인가

accelerator를 전혀 쓰지 않고 **RVX SoC의 ORCA core 한 개**로 같은 search를 돌린
baseline입니다. 같은 Arty A7-100T, 같은 500 workloads(1/4/16/64/256 solutions × 100 seeds),
같은 seed roster입니다. accelerator CSR은 건드리지 않고 `bbht_sw_run()` 호출 구간만
RVX 실시간 timer로 잽니다. core는 50 MHz입니다.

이것이 우리가 쓰는 **유일한 정당한 software 비교 대상**입니다 — 같은 chip,
같은 workload, 같은 seed, 같은 종료 조건. host의 state vector simulator와
비교하는 것과는 성격이 다릅니다.

## 확정 수치

| number of solutions | ORCA 1 core sum | final configuration sum | speedup |
|---:|---:|---:|---:|
| 1 | 3,395,866,056 µs | 22,818 µs | 148,824× |
| 4 | 1,630,049,877 | 13,748 | 118,566× |
| 16 | 886,874,406 | 9,432 | 94,028× |
| 64 | 400,041,946 | 5,942 | 67,324× |
| 256 | 183,505,720 | 3,858 | 47,565× |
| **전체** | **6,496,338,005** | **55,798** | **116,426×** |

중앙값은 ORCA 7,224,174 µs 대 final configuration 87.5 µs입니다.

## 이 숫자를 쓸 때의 경계

speedup이 십만 단위인 것은 software 쪽이 **16,384 states의 state vector를 32-bit core
하나로 iteration마다 전부 pass하기** 때문입니다. accelerator가 32 lanes로 한 번에
처리하는 일을 순차로 하는 데다, clock도 절반(50 MHz 대 100 MHz)입니다.
이 비교의 의미는 "emulation을 전용 hardware로 옮기면 이만큼 벌린다" 이지,
algorithm 우위가 아닙니다.

**고전 선형 scan과 비교한 것이 아닙니다.** 고전 scan은 16,384번 비교로 끝나므로
어느 쪽 emulation보다도 빠릅니다. 여기서 재는 것은 같은 quantum algorithm을
software로 흉내 낼 때와 hardware로 흉내 낼 때의 차이입니다.

그리고 이 speedup은 **wall-clock time** 축입니다. Six-Stage Ablation의 `6.1401x`는
RTL cycle 축이라 성격이 다릅니다. 두 숫자를 같은 문장에서 같은 종류인 것처럼
쓰지 마십시오.

## verification

`validation.txt` 기준입니다.

- 500 rows, 형식 오류 0, parsing 오류 0, key 중복 0
- 논리 오류 0, 성공 판정 오류 0, timer 오류 0
- final configuration 500 rows와 짝지음 500/500, 짝 논리 불일치 0

## file

| file | 내용 |
|---|---|
| `per_run.csv` | ORCA 500 runs 원본 |
| `paired.csv` | workload별 ORCA 대 final configuration 짝 비교 |
| `summary.csv` | number of solutions별 집계와 speedup |
| `validation.txt` | 무결성 점검 결과 |

baseline source는 `hardware_bram/firmware/orca_sw_baseline/`에 있습니다.
