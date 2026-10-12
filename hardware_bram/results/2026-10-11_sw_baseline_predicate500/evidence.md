# SW 기준선 — ORCA 보드 · 서버 · FPGA, Predicate500 2,000개

## 무엇인가

가속기를 쓰지 않는 같은 C 코드(`software/orca_sw/`, 모델 ① naive · ② 최적화 + K3H3 · ③ 최적화 Normal)를
두 곳에서 돌려 FPGA 가속기와 워크로드마다 맞댄 묶음입니다.

1. **ORCA 보드**: 200T 보드(AX7A200B)의 ORCA 코어(RV32IM, 50 MHz). 2026-10-11 측정.
2. **서버**: 같은 소스를 이 서버의 x86 코어 하나에서. RVX 헤더 셋만 바꿔 끼웠습니다. 2026-10-11~12 측정.
3. **FPGA**: 같은 보드의 K3/H3-E4-M2 가속기, 2026-10-08 측정
   ([ax7a200b_board_predicate500](../../models/hardware_bram_K3H3_E4_M2/vivado/vivado_bbht_grover_fpga/2026-10-08_ax7a200b_board_predicate500/evidence.md)).
   ③ · ① 은 FPGA `normal` 모드, ② 는 `ckpt` 모드와 짝입니다.

워크로드는 셋 모두 네 술어(LT · GT · EQ · RANGE) × M 5종(1 · 4 · 16 · 64 · 256) × seed 100 = 2,000개이고
seed 가 같습니다. 정수 연산만 쓰므로 결과 인덱스 · 시도 수 · L · 실제 반복이 세 곳에서 같아야 하고, 실제로
같습니다(검증 절).

## 확정 수치

네 술어 2,000개의 합입니다. 시간은 탐색 시작부터 결과까지(아래 조건 절).

| 실행 환경 | 모델 | 실제 반복 | 시간 (us) | 사이클 | 사이클 출처 |
|---|---|--:|--:|--:|---|
| ORCA 보드 | ③ 최적화 Normal | 125,106 | 9,512,428,962 (2시간 38분) | 475,621,448,100 | us × 50 환산 |
| ORCA 보드 | ② 최적화 + K3H3 | 37,659 | 3,511,780,574 (58.5분) | 175,589,028,700 | us × 50 환산 |
| ORCA 보드 | ① naive | 125,106 | **추정** 144,453,615,873,017 (약 4.58년) | 7,222,680,793,650,850 | us × 50 환산 |
| 서버 | ③ 최적화 Normal | 125,106 | 551,684 | 2,911,588,241 | perf 코어 사이클 실측 |
| 서버 | ② 최적화 + K3H3 | 37,659 | 296,748 | 1,565,215,866 | perf 코어 사이클 실측 |
| 서버 | ① naive | 125,106 | 12,802,056,514 (3시간 33분) | 67,272,196,979,632 | perf 코어 사이클 실측 |
| FPGA | K3/H3-E4-M2 normal | 125,106 | 478,949 (`wall_us`) | 46,886,677 | 가속기 `cycle_count` (100 MHz) |
| FPGA | K3/H3-E4-M2 ckpt | 37,659 | 221,021 (`wall_us`) | 21,083,867 | 가속기 `cycle_count` (100 MHz) |

서버 ③ · ② 는 10번 돌린 실행의 워크로드별 중앙값의 합입니다. 10번의 합계는 ③ 551,665~559,398 us,
② 296,042~298,042 us 였습니다(`host_repeats.csv`). 서버 사이클을 시간으로 나누면 5.26~5.28 GHz 로,
P 코어 최대 클럭(5.3 GHz)과 맞습니다.

### 배수 — 시간 축

같은 모드끼리 맞댄 값입니다.

| 비교 | 전체 | M=1 | M=4 | M=16 | M=64 | M=256 |
|---|--:|--:|--:|--:|--:|--:|
| ORCA ③ ÷ FPGA normal | 19,861 | 21,708 | 20,080 | 18,089 | 15,494 | 12,227 |
| ORCA ② ÷ FPGA ckpt | 15,889 | 19,330 | 16,357 | 13,304 | 10,434 | 8,103 |
| 서버 ③ ÷ FPGA normal | 1.152 | 1.247 | 1.162 | 1.060 | 0.928 | 0.769 |
| 서버 ② ÷ FPGA ckpt | 1.343 | 1.531 | 1.414 | 1.216 | 0.995 | 0.794 |

| 같은 환경 안에서 | ORCA 보드 | 서버 | FPGA |
|---|--:|--:|--:|
| Normal ÷ 체크포인트 (③ ÷ ②, normal ÷ ckpt) | 2.709 | 1.859 | 2.167 |
| naive ÷ 최적화 (① ÷ ③) | 15,186 (추정 ÷ 실측) | 23,205 | — |

| 같은 코드, ORCA ÷ 서버 | ③ | ② | ① |
|---|--:|--:|--:|
| 시간 배수 | 17,243 | 11,834 | 11,284 (추정 ÷ 실측) |

### 배수 — 사이클 축

| 비교 | 배수 |
|---|--:|
| ORCA ③ 사이클 ÷ FPGA normal 사이클 | 10,144 |
| ORCA ② 사이클 ÷ FPGA ckpt 사이클 | 8,328 |
| 서버 ③ 사이클 ÷ FPGA normal 사이클 | 62.1 |
| 서버 ② 사이클 ÷ FPGA ckpt 사이클 | 74.2 |

사이클 한 번의 길이가 셋 모두 다릅니다(ORCA 20 ns, 가속기 10 ns, 서버 약 0.19 ns). 사이클 배수는
"같은 일에 든 클럭 수" 로만 읽으십시오.

## 조건

| 항목 | ORCA 보드 | 서버 | FPGA (2026-10-08) |
|---|---|---|---|
| 하드웨어 | AX7A200B `xc7a200tfbg484-2`, 100T 예산 구현 | Intel Core i5-14600K, P 코어 하나에 고정 (③ · ② cpu 4, ① cpu 6) | 같은 보드 |
| 클럭 | ORCA 50 MHz | 실측 5.26~5.28 GHz (터보) | 가속기 100 MHz, ORCA 50 MHz |
| 컴파일 | RVX release, `riscv64-unknown-elf-gcc -O2 -march=rv32im` | `gcc 13.3.0 -O2` (x86-64 기본, `-march` 없음). 나머지 코드 생성 옵션은 RVX 와 같음 | — |
| RVX 플랫폼 | ③ `bbht_grover_upgrade` (M2 비트스트림, SRAM 128 KB, 가속기 미사용) · ② ① `orca_sw` (가속기 없음, SRAM 256 KB) | — | `bbht_grover_upgrade` |
| 시간 구간 | `bbht_search()` 호출 앞뒤, RVX 실시간 클럭(1 MHz) | 같은 구간, `CLOCK_MONOTONIC_RAW` us | `wall_us`: 같은 보드 실시간 클럭으로 `COMMAND` 직전 ~ DONE |
| 사이클 | 시간 × 50 (환산) | 같은 구간의 사용자 공간 코어 사이클 (perf_event) | 가속기 `cycle_count` |
| 오라클 | 미리 만든 타겟 목록. 준비 시간 제외 | 같음 | 반복마다 데이터 16,384개 비교 |
| 반복 측정 | 1회 | ③ · ② 10회 (중앙값), ① 1회 | 1회 |

- `orca_sw` 플랫폼 정의는 `software/orca_sw/rvx/orca_sw.xml` 입니다. 200T 구현은 WNS +6.688 ns · WHS +0.042 ns,
  100T 예산으로 Available 이 100T 와 같고, BRAM 64 타일을 씁니다. 비트스트림은 저장소에 두지 않고 해시만
  `sha256.txt` 에 남겼습니다.
- ③ 은 가속기가 들어 있는 M2 비트스트림에서, ② · ① 은 `orca_sw` 에서 쟀습니다. ② · ① 은 정적 메모리가
  128 KB 를 넘기 때문입니다. 두 플랫폼에서 ③ 의 SMOKE · CALIBRATE 시간이 같아 플랫폼 차이는 시간에 영향이 없습니다(검증 절).
- 서버 실행 파일의 머리줄 `SW_TIMING_SOURCE,RVX_REAL_CLOCK` · `SW_TIMING_CORE_CLK_HZ,50000000` 은 `main.c` 의
  고정 문자열이라 서버에서도 그대로 찍힙니다. 서버 조건은 이 표가 정본입니다.

## 검증

`validation.txt` 기준입니다.

- **궤적**: ORCA ③ · ②, 서버 ①, 서버 ③ · ② 각 10회가 모두 FPGA 와 seed_j · seed_meas · result_index ·
  trial_count · L_BBHT · actual_iter 에서 2,000/2,000 같습니다. ② 의 실제 반복 37,659 는 FPGA ckpt 의
  물리 반복과 워크로드마다 같습니다.
- **플랫폼 사이**: 같은 모델이면 ORCA 와 서버의 시간 열을 뺀 모든 열(종료 사유, 포화 수 포함)이 2,000/2,000
  같습니다. 서버 ① 은 ORCA ③ 과 궤적이 같습니다(① 도 Normal).
- **플랫폼 차이 없음**: ③ 을 M2 비트스트림과 `orca_sw` 비트스트림에서 각각 돌린 값입니다.
  SMOKE 762,498 us = 762,498 us, CALIBRATE 반복 20회 1,283,366 us = 1,283,366 us, 측정 1회 54,178 us 대 54,177 us(1 us 틱 차이).
- **① 추정식**: 추정 = L × 반복 1회 시간 + 시도 수 × 측정 1회 시간. ORCA 단가는 반복 1,154,636,860.5 us,
  측정 55,027 us 입니다(`orca/naive_calib.log`). ORCA SUBSET 두 워크로드(GT · RANGE, M=256, seed 0)를 끝까지
  돌린 실측과 +0.0029% 차이, 서버 ① FULL 실측과 서버 단가 추정은 +0.81% 차이입니다.
- 보드 · 서버 실행 모두 `SW_SUMMARY,pass=2000,total=2000` 입니다.

## 인용할 때

- **성능 세 축의 정본과 섞지 마십시오.** 정본은 2026-09-07 빌드 · 100T 보드 · EQ 500 입니다
  ([1장 1.5절](../../../documents/design_references/01_프로젝트_개요.md#15-성능-지표와-인용-기준)). 이 묶음은 200T 보드 ·
  네 술어 2,000개라 1.5절의 ORCA 116,426x 와 배수를 맞대지 않습니다. 그 116,426x 는 옛 기준선
  (`orca_sw_baseline`, 반복 1회에 배열을 두 번 훑음, EQ 500, 체크포인트 없음) 대 M2 체크포인트이고, 이 묶음은 같은
  모드끼리 맞댄 값입니다.
- **ORCA ÷ FPGA 의 만 단위 배수는 알고리즘 우위가 아닙니다.** 16,384 상태벡터를 32비트 코어 하나로 훑는 것과
  P = 32 레인으로 훑는 것의 차이에 클럭 2배가 곱해진 값이고, 오라클 준비가 SW 쪽에서 빠져 SW 가 조금 유리합니다.
- **서버 한 코어는 FPGA 와 시간이 비슷합니다.** 전체로 ③ 은 FPGA normal 의 1.15배, ② 는 FPGA ckpt 의 1.34배이고,
  M = 64 · 256 에서는 서버가 FPGA 실경과보다 빠릅니다. 클럭이 약 53배 높은 범용 코어라는 점과 같이 적으십시오.
  가속 주장을 할 때는 이 비교를 빼지 마십시오.
- **서버 시간은 코드 배치에 ±15~20% 흔들립니다.** 시간용과 사이클용 실행 파일을 따로 빌드했을 때(그 차이는
  `main.c` 가 넣는 헤더뿐) 같은 계산이 ③ 0.644 / 0.553 초, ② 0.242 / 0.297 초로 달랐습니다. 이 묶음의 값은
  시간과 사이클을 한 실행 파일 · 한 실행에서 같이 잰 것입니다.
- **ORCA ① 은 추정값입니다.** 실측과 같은 열에 둘 때는 추정임을 표시하십시오.
- 사이클 축과 시간 축을 섞어 배수를 만들지 마십시오. 고전 선형 스캔과는 비교하지 않습니다.

## 파일

| 파일 | 내용 |
|---|---|
| `summary.csv` | 실행 환경 × 모델 × 묶음(전체, M 별)의 시도 · L · 실제 반복 · 시간 · 사이클 합 |
| `per_run.csv` | 워크로드 2,000개마다 궤적과 여덟 실행의 시간 · 사이클 (서버 ③ · ② 는 10회 중앙값, ORCA ① 은 추정) |
| `host_repeats.csv` | 서버 ③ · ② 10회 각각의 합계 |
| `validation.txt` | 형식 · 궤적 · 플랫폼 사이 대조와 ① 추정식 확인 |
| `sha256.txt` | 비트스트림 두 개, 측정마다 올린 앱 hex, 소스 |
| `orca/` | 보드 UART 원본. `normal_full` · `k3h3_full` · `naive_calib` · `naive_subset`, 플랫폼 대조용 `normal_smoke(_m2)` · `normal_calib(_m2)` · `k3h3_smoke` |
| `host/` | 서버 실행 원본. `normal_full_1..10` · `k3h3_full_1..10` · `naive_full` · `naive_calib_1..3` |

## 다시 재는 법

```bash
# 비교표 다시 만들기 (이 폴더에서)
python3 ../../../software/orca_sw/tools/compare.py \
  --fpga ../../models/hardware_bram_K3H3_E4_M2/vivado/vivado_bbht_grover_fpga/2026-10-08_ax7a200b_board_predicate500/predicate500.csv \
  --out . --orca-normal orca/normal_full.log --orca-k3h3 orca/k3h3_full.log \
  --orca-naive-calib orca/naive_calib.log --orca-naive-subset orca/naive_subset.log \
  --host-normal host/normal_full_{1..10}.log --host-k3h3 host/k3h3_full_{1..10}.log \
  --host-naive host/naive_full.log --host-naive-calib host/naive_calib_{1..3}.log

# 서버 (예: ③ FULL)
software/orca_sw/host/build_host.sh orca_bbht_opt_normal normal_full PROFILE=1
taskset -c 4 /tmp/orca_host_bin/normal_full > normal_full_1.log

# ORCA 보드: 플랫폼 설치 · 200T 구현 · 앱 빌드 · 측정 (자세한 순서는 각 스크립트 머리말)
#   rvx/orca_sw.xml 을 $RVX_MINI_HOME/platform/orca_sw/ 에 두고 /fpga-syn-rvx start orca_sw --budget-100t
software/orca_sw/tools/build_app.sh <imp폴더> orca_bbht_opt_k3h3 PROFILE=1
software/orca_sw/tools/board_run.sh start k3h3_full <bit> <imp폴더> orca_bbht_opt_k3h3 10800
software/orca_sw/tools/board_run.sh fetch k3h3_full
.claude/skills/fpga-flash/scripts/sdsl_fpga.sh restore --pcie      # 끝나면 반드시
```

보드 점유 시간은 ③ FULL 2시간 39분, ② FULL 59분, ① CALIBRATE 39분, ① SUBSET(두 워크로드) 58분이었습니다.
