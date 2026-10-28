# 실험 19. ORCA · server software baseline과 FPGA 비교

> [← 실험 18 Six-Stage Ablation configuration과 implementation 방식별 비교](18_six_stage_ablation_comparison.md) · [index](index.md) · [실험 20 final configuration을 200 MHz로 →](20_200mhz_implementation.md)

---

| 확인한 것 | 근거의 축 |
|---|---|
| 가속 효과를 말할 때 함께 밝힐 software baseline (ORCA core · server x86 core 하나) | 200T board ORCA wall-clock time · server wall-clock time · cycle |

accelerator를 쓰지 않는 C code로 같은 search를 돌려 FPGA와 맞댄 실험입니다. 같은 source를 두 곳에서 돌렸습니다.

1. 200T board(AX7A200B)의 ORCA core(RV32IM, 50 MHz)
2. server의 x86 core 하나

비교 상대는 같은 board에서 잰 final configuration의 Predicate500 입니다(2026-10-08,
[실험 18](18_six_stage_ablation_comparison.md)). workload는 셋 모두 네 predicate × 다섯 가지 number of solutions
× seed 100 = 2,000개로 같습니다. evidence bundle은
[sw_baseline_predicate500](../../software/orca_grover_result/2026-10-11_predicate500/2026-10-11_predicate500.md)입니다.

이 비교는 성능 세 축의 source of truth([1장 1.5절](../design_references/01_project_overview.md#15-성능-지표와-인용-기준))와 board · workload ·
baseline code가 다릅니다. 섞지 않는 규칙은 「[인용할 때](#인용할-때)」에 있습니다.

---

## 요약

- 같은 Grover/BBHT search를 세 곳에서 돌렸습니다. 200T board의 ORCA core(50 MHz), server의 x86 core 하나,
  같은 board의 FPGA accelerator final configuration(100 MHz)입니다. workload는 네 predicate × 다섯 가지 number of solutions × seed 100 = 2,000개로 같습니다.
- **세 곳의 결과가 2,000/2,000 같습니다.** 결과 index · shot count · requested iterations · executed iterations가 모두 같습니다(「[verification](#verification)」).
- **FPGA는 ORCA보다 wall-clock time으로 약 1.6만~2만× 빠릅니다.** algorithm 우위가 아니라 core 하나 대 32 lanes
  병렬과 clock 2×의 차이입니다(「[해석](#해석)」).
- **server x86 core 하나는 FPGA와 시간이 비슷합니다.** 전체로 1.15~1.34× 더 걸리고, 64 · 256 solutions에서는 FPGA보다
  빠릅니다(「[결과](#결과)」).

---

## 세 model

source는 [`software/orca_grover_develop/apps/`](../../software/orca_grover_develop/apps/)의 세 directory입니다. 세 directory의 source는 같고,
`src/baseline_config.h`의 `BBHT_MODEL` 한 줄만 다릅니다. directory 하나가 RVX app 하나입니다.

| model | directory | 계산 | checkpoint | SRAM 사용 |
|---|---|---|---|--:|
| ① naive | `orca_bbht_naive` | oracle은 대각 matrix, diffusion operator는 (2/number of states)J − I 밀집 matrix로 그대로 곱합니다. iteration 1회에 multiply-accumulate가 16,384² ≈ 2.7억 번입니다. measurement는 row를 처음부터 훑습니다 | 없음 | 173.4 KB |
| ② 최적화 + a Checkpoint-Capacity of 3 and 3-shot Lookahead | `orca_bbht_opt_k3h3` | ③과 같은 core에 checkpoint를 더했습니다 | a Checkpoint-Capacity of 3 and 3-shot Lookahead (최대 3개 보관, 다음 3 requests를 보고 결정) | 227.2 KB |
| ③ 최적화 Restart mode | `orca_bbht_opt_normal` | iteration 1회에 array를 한 번 훑고, solution(최대 256개)만 앞뒤로 보정합니다. measurement는 row weight의 prefix sum을 binary search합니다 | 없음 | 108.5 KB |

SRAM 사용은 RVX release build ELF의 끝 address입니다(1 KB = 1,024 bytes, stack 8 KB 포함).
② · ①은 128 KB를 넘으므로 SRAM 256 KB platform이 필요합니다(「[실행 환경](#실행-환경)」).

①은 **일부러 최적화하지 않은 baseline**입니다. 모든 row의 inner product가 사실 같은 값이지만 row마다 다시
계산하고, compiler가 재사용하지 못하게 막아 두었습니다. 최적화 효과를 보이는 보조 기준이고,
FPGA와 맞대는 주 기준은 ② · ③입니다. 이 구성은 같은 RVX SoC와 ORCA core에서 naive C와
최적화 C를 baseline으로 둔 Choi & Lee (AIMS Mathematics, 2024)를 따랐습니다.

② · ③은 결과를 바꾸지 않는 계산을 생략합니다. ①은 일부러 그대로 둡니다.

| 경우 | 생략하는 것 | 2,000개에서 |
|---|---|--:|
| ③ 0 iterations를 request | uniform superposition initialization과 prefix sum 계산 pass. uniform superposition을 바로 측정하고 prefix sum은 식으로 채웁니다 | shot 29,382번 중 8,870번 |
| ② 정확히 hit (request한 number of iterations의 state를 이미 보관) | 다음 number of iterations 예측과 policy 계산. hit면 policy 결과를 쓰지 않습니다 | 16,173번 |
| ② 보관 state를 다시 measurement | prefix sum 계산 pass. checkpoint마다 prefix sum(4 KB)을 같이 보관해 다시 씁니다. measurement random number는 매번 새로 뽑습니다 | 14,754번 |

---

## FPGA와 같게 맞춘 조건

모두 integer 연산이라, 같은 입력이면 결과 index · shot count · requested iterations · executed iterations가 FPGA와 같습니다(「[verification](#verification)」).

| 항목 | 값 |
|---|---|
| state | 16,384 states의 amplitude, Q1.22 signed int32 (uniform amplitude 32768) |
| 2 × mean | oracle 적용 후 sum을 2¹³으로 한 번에 round-half-to-even (정확히 반이면 짝수 쪽) |
| saturation | ±(2²² − 1) 대칭 |
| BBHT | sampling range 시작 1, growth factor 6/5, 상한 128 (28단계 integer table), BBHT budget 576, shot cap 100 |
| 종료 검사 순서 | 성공 → shot cap → BBHT budget (requested iterations + 1 ≥ 576) |
| number of iterations sampling | 32-bit LFSR (tap 31 · 21 · 1 · 0), 한 번 뽑을 때 7-step jump, 하위 byte & mask, sampling range 밖이면 다시 |
| measurement random number | xorshift64 (13, 7, 17), seed 확장 {s, s ^ 0x9E3779B9} |
| measurement | 32-lane row 단위로 row weight(\|a\|²의 sum)의 prefix sum을 쌓아 random number보다 커지는 첫 row → 그 row에서 첫 lane |
| workload | Predicate500 2,000개, board 실험과 같은 seed |

다른 점은 oracle 하나입니다. software는 dataset 값 16,384개 대신 "predicate를 만족하는 index 목록"
(`p500_workloads.h`)을 받고, 그 준비 시간은 measurement segment에서 빠집니다. FPGA는 iteration마다 data를 비교하므로
software 쪽이 조금 유리합니다.

---

## 실행 환경

| 항목 | ORCA board | server | FPGA |
|---|---|---|---|
| hardware | AX7A200B `xc7a200tfbg484-2`, 100T 예산 implementation([17장 17.9절](../design_references/17_board_operation.md#179-원격-200t-board-ax7a200b)) | Intel Core i5-14600K, P-core 하나에 고정 (`taskset`) | 같은 board, final configuration |
| clock | ORCA 50 MHz | benchmark 5.26~5.28 GHz (turbo) | accelerator 100 MHz |
| compile | RVX release, `riscv64-unknown-elf-gcc -O2 -march=rv32im` | `gcc 13.3.0 -O2`, `-march` 없음. 나머지 code 생성 option은 RVX와 같음 | — |
| 시간 | `bbht_search()` 앞뒤, RVX real-time clock(1 µs tick) | 같은 segment, `CLOCK_MONOTONIC_RAW` | `wall_us`: 같은 board real-time clock, `COMMAND` 직전 ~ DONE ([14장](../design_references/14_host_interface_and_uart_protocol.md)) |
| cycle | 시간 × 50 (환산) | 같은 segment의 user-space core cycle (perf_event, benchmark) | accelerator `cycle_count` |
| benchmark 횟수 | 1회 | ③ · ② 10회(workload별 median), ① 1회 | 1회 |
| benchmark 날짜 | 2026-10-11 | 2026-10-11~12 | 2026-10-08 |

### ORCA board의 두 platform

③은 FPGA benchmark에 쓴 final configuration bitstream(`bbht_grover_final`, SRAM 128 KB)에 app만 올려 쟀습니다. accelerator CSR은
건드리지 않습니다. ② · ①은 SRAM이 모자라, accelerator 없이 ORCA 하나와 SRAM 256 KB만 둔 platform
[`software/orca_grover_develop/rvx/orca_sw.xml`](../../software/orca_grover_develop/rvx/orca_sw.xml)을 따로 구현했습니다. 200T implementation은
WNS +6.688 ns이고, 100T 예산으로 Available이 100T와 같습니다.

두 platform에서 ③의 SMOKE와 CALIBRATE를 각각 돌려 보니 시간이 같았습니다(「[verification](#verification)」). core와 clock이 같으면
accelerator 유무와 SRAM 크기는 software 시간에 영향이 없습니다.

### server build

source는 손대지 않고, `main.c`가 쓰는 RVX header 셋만 [`software/orca_grover_develop/host_build/stub/`](../../software/orca_grover_develop/host_build/stub/)
로 바꿔 끼웁니다.

| header | board | server |
|---|---|---|
| `platform_info.h` | platform 정보 | 빈 header |
| `ervp_printf.h` | UART printf | `<stdio.h>` |
| `ervp_real_clock.h` | 1 µs 틱 counter | `CLOCK_MONOTONIC_RAW` µs를 돌려주고, 같은 segment의 core cycle을 모아 끝에 `HOST_CYCLES,<순번>,<사이클>`로 찍음 |

시간과 cycle은 **한 실행 file, 한 실행**에서 같이 잽니다. 시간용 · cycle용을 따로 build했을 때 `main.c`에
들어가는 header 차이만으로 function 배치가 바뀌어, 같은 계산이 ③ 0.644 / 0.553 초, ② 0.242 / 0.297 초로 달랐기
때문입니다. server 시간은 code 배치에 따라 이 정도(±15~20%) 흔들릴 수 있습니다.

---

## 결과

네 predicate 2,000개의 sum입니다.

| 실행 환경 | model | executed iterations | 시간 (µs) | cycle |
|---|---|--:|--:|--:|
| ORCA board | ③ 최적화 Restart mode | 125,106 | 9,512,428,962 (2시간 38분) | 475,621,448,100 (환산) |
| ORCA board | ② 최적화 + a Checkpoint-Capacity of 3 and 3-shot Lookahead | 37,659 | 3,511,780,574 (58.5분) | 175,589,028,700 (환산) |
| ORCA board | ① naive | 125,106 | **추정** 144,453,615,873,017 (약 4.58년) | 7,222,680,793,650,850 (환산) |
| server | ③ 최적화 Restart mode | 125,106 | 551,684 | 2,911,588,241 |
| server | ② 최적화 + a Checkpoint-Capacity of 3 and 3-shot Lookahead | 37,659 | 296,748 | 1,565,215,866 |
| server | ① naive | 125,106 | 12,802,056,514 (3시간 33분) | 67,272,196,979,632 |
| FPGA | Restart mode | 125,106 | 478,949 | 46,886,677 |
| FPGA | Checkpoint mode | 37,659 | 221,021 | 21,083,867 |

ORCA ①은 2,000개를 끝까지 돌릴 수 없어 단가로 추정했습니다. 추정은 "requested iterations × iteration 1회 시간 + shot count × measurement 1회
시간" 이고, ORCA 단가는 iteration 1회 1,154,636,860.5 µs(19.2분), measurement 1회 55,027 µs입니다. 이 식은 「[verification](#verification)」에서
확인했습니다.

### 시간 speedup

같은 mode끼리 맞댄 값입니다.

| 비교 | 전체 | 1 solution | 4 solutions | 16 solutions | 64 solutions | 256 solutions |
|---|--:|--:|--:|--:|--:|--:|
| ORCA ③ ÷ FPGA Restart mode | 19,861 | 21,708 | 20,080 | 18,089 | 15,494 | 12,227 |
| ORCA ② ÷ FPGA Checkpoint mode | 15,889 | 19,330 | 16,357 | 13,304 | 10,434 | 8,103 |
| server ③ ÷ FPGA Restart mode | 1.152 | 1.247 | 1.162 | 1.060 | 0.928 | 0.769 |
| server ② ÷ FPGA Checkpoint mode | 1.343 | 1.531 | 1.414 | 1.216 | 0.995 | 0.794 |

| 같은 환경 안에서 | ORCA board | server | FPGA |
|---|--:|--:|--:|
| checkpoint 효과 (③ ÷ ②, Restart mode ÷ Checkpoint mode) | 2.709 | 1.859 | 2.167 |
| 최적화 효과 (① ÷ ③) | 15,186 (추정 ÷ benchmark) | 23,205 | — |

같은 code를 ORCA와 server에서 돌린 시간 비는 ③ 17,243, ② 11,834, ① 11,284(추정 ÷ benchmark)입니다.

### cycle speedup

| 비교 | speedup |
|---|--:|
| ORCA ③ ÷ FPGA Restart mode | 10,144 |
| ORCA ② ÷ FPGA Checkpoint mode | 8,328 |
| server ③ ÷ FPGA Restart mode | 62.1 |
| server ② ÷ FPGA Checkpoint mode | 74.2 |

cycle 한 번의 길이는 ORCA 20 ns, accelerator 10 ns, server 약 0.19 ns로 셋이 다릅니다. cycle speedup은 "같은 일에
든 cycles"로만 읽습니다.

---

## verification

- **BBHT trajectory**: ORCA ③ · ②, server ①, server ③ · ② 각 10회가 모두 FPGA와 `seed_j` · `seed_meas` · `result_index` ·
  `trial_count` · `L_BBHT` · executed iterations에서 2,000/2,000 같습니다. ②의 executed iterations는 FPGA Checkpoint mode의 executed iterations와
  workload마다 같습니다. software의 a Checkpoint-Capacity of 3 and 3-shot Lookahead policy가 hardware Policy Engine([11장](../design_references/11_checkpoint_and_policy_engine.md))과 같은 executed
  iterations를 낸다는 뜻입니다.
- **platform 사이**: 같은 model이면 ORCA와 server의 시간 열을 뺀 모든 열(종료 사유, saturation 횟수 포함)이 같습니다.
- **ORCA platform 차이**: ③을 두 platform에서 돌린 값입니다. SMOKE는 762,498 µs로 같고, iteration 20회도
  1,283,366 µs로 같습니다. measurement 1회만 54,178 대 54,177 µs로 1 µs tick 차이입니다.
- **① 추정식**: ORCA에서 두 workload(256 solutions, seed 0의 GT · RANGE)를 끝까지 돌린 benchmark와 +0.0029% 차이입니다.
  server에서는 2,000개 전체 benchmark가 server 단가 추정과 +0.81% 차이입니다.

---

## 해석

- **ORCA ÷ FPGA의 만 단위 speedup은 algorithm 우위가 아닙니다.** 16,384 amplitudes의 state vector를 32-bit core 하나로 훑는
  것과 32 lanes로 훑는 것의 차이에 clock 2×가 곱해진 값입니다. oracle 준비가 software 쪽에서 빠지므로 software가
  조금 유리한 조건입니다.
- **server 한 core는 FPGA와 시간이 비슷합니다.** 전체로 server ③은 FPGA Restart mode의 1.15×, ②는 FPGA Checkpoint mode의
  1.34× 걸립니다. 64 · 256 solutions에서는 server가 FPGA보다 빠릅니다. server는 accelerator보다 clock이 약 53× 높은
  범용 core이고, `-O2`에서 `bbht_core.c`의 core loop 셋이 16-byte(SSE2) vector로 auto-vectorize됩니다(gcc
  `-fopt-info-vec` 보고. ①의 `bbht_naive.c`는 vectorize되지 않음). cycle로 보면 FPGA가 같은 일을 62~74×
  적은 clock으로 끝냅니다.
- **checkpoint 효과가 환경마다 다릅니다.** executed iterations는 세 환경 모두 125,106 → 37,659로 같이 줄지만, 시간은
  ORCA 2.709× · FPGA 2.167× · server 1.859× 줄었습니다. iteration 1회와 measurement 1회의 상대 비용이 환경마다 다르고,
  software ②는 measurement용 prefix sum도 재사용합니다(「[세 model](#세-model)」). 어느 쪽이 얼마를 차지하는지는 나눠 재지 않았습니다.

---

## 인용할 때

- **성능 세 축의 source of truth와 섞지 않습니다.** source of truth는 2026-09-07 build · 100T board · EQ 500이고, 그 ORCA 116,426×는
  옛 baseline `hardware_bram/firmware/orca_sw_baseline` (iteration 1회에 array를 두 번 훑음, checkpoint 없음) 대 final configuration
  Checkpoint mode입니다. 이 실험은 200T board · 네 predicate 2,000개 · 새 baseline이고 같은 mode끼리 맞댑니다.
- **server 비교를 함께 적습니다.** 가속 효과를 말할 때 ORCA speedup만 쓰지 말고, server 한 core가 FPGA와 비슷한
  시간에 끝난다는 「[결과](#결과)」 값을 같이 밝힙니다.
- ORCA ①은 추정값입니다. benchmark와 같은 열에 둘 때는 표시합니다.
- cycle 축과 시간 축을 섞어 speedup을 만들지 않습니다. 고전 선형 scan과는 비교하지 않습니다.

---

## 다시 재는 법

도구는 [`software/orca_grover_develop/`](../../software/orca_grover_develop/) 아래에 있습니다.

| file | 역할 |
|---|---|
| `rvx/orca_sw.xml` | ② · ① 용 RVX platform 정의 (accelerator 없음, SRAM 256 KB) |
| `tools/build_app.sh` | platform에 복사한 app의 `baseline_config.h` 기본값만 바꿔 release로 build. 저장소 원본은 그대로 |
| `tools/board_run.sh` | 200T board에 굽고 app을 올려 UART를 capture. 원격 쪽을 떼어 놓아 ssh가 끊겨도 benchmark가 계속됩니다 |
| `host_build/build_host.sh` · `host_build/stub/` | 같은 source를 server에서 build |
| `tools/compare.py` | ORCA · server log를 FPGA CSV와 workload마다 맞대고 합계 · verification을 냄 |

```bash
# ORCA board (② 예시). 먼저 rvx/orca_sw.xml 을 $RVX_MINI_HOME/platform/orca_sw/ 에 두고
# app 세 directory를 그 platform의 app/ 에 복사한 뒤 200T 로 구현합니다.
.claude/skills/fpga-syn-rvx/scripts/fpga_syn_rvx.sh start orca_sw --budget-100t --threads=1
software/orca_grover_develop/tools/build_app.sh <imp폴더> orca_bbht_opt_k3h3 PROFILE=1
software/orca_grover_develop/tools/board_run.sh start k3h3_full <bit> <imp폴더> orca_bbht_opt_k3h3 10800
software/orca_grover_develop/tools/board_run.sh fetch k3h3_full
.claude/skills/fpga-flash/scripts/sdsl_fpga.sh restore --pcie      # 끝나면 반드시

# server (③ 예시)
software/orca_grover_develop/host_build/build_host.sh orca_bbht_opt_normal normal_full PROFILE=1
taskset -c 4 /tmp/orca_host_bin/normal_full > normal_full_1.log
```

- RVX `make <앱>`의 기본은 debug(`-O1 -g`)입니다. `build_app.sh`는 release(`-O2`)를 강제하고 log에서 확인합니다.
- 200T implementation은 memory를 3~4 GB 씁니다. server의 다른 작업과 겹치면 Vivado가 OOM으로 죽으니 `--threads=1`로 돌립니다.
- board 점유는 ③ FULL 2시간 39분, ② FULL 59분, ① CALIBRATE 39분, ① 두 workload 58분이었습니다.

### profile과 설정

`src/baseline_config.h`의 macro입니다. `build_app.sh` · `build_host.sh`에는 `BBHT_`를 뗀 이름으로 넘깁니다.

| macro | 기본값 | 뜻 |
|---|---|---|
| `BBHT_MODEL` | directory마다 1 · 2 · 3 | model. directory와 맞춰져 있으니 바꾸지 않습니다 |
| `BBHT_PROFILE` | 0 | 0 SMOKE · 1 FULL · 2 CALIBRATE · 3 SUBSET |
| `BBHT_SEED_COUNT` | 100 | FULL에서 seed 0 ~ (값 − 1) |
| `BBHT_CALIB_ITERS` | 2 | CALIBRATE에서 잴 number of iterations |
| `BBHT_SUBSET_PRED_MASK` | 0xF | bit 0 LT · 1 GT · 2 EQ · 3 RANGE |
| `BBHT_SUBSET_M_MASK` | 0x10 | bit 0 1 solution · 1 4 solutions · 2 16 solutions · 3 64 solutions · 4 256 solutions |
| `BBHT_SUBSET_SEED_FIRST` · `_END` | 0 · 1 | SUBSET seed 범위 [FIRST, END) |

| profile | 실행 내용 |
|---|---|
| SMOKE | EQ, 256 solutions, seed 0 하나. expected result는 result 15288 · shot 8 · requested iterations 7 · executed iterations 7 (②는 3) |
| FULL | 네 predicate × 다섯 가지 number of solutions × seed `BBHT_SEED_COUNT`개 |
| CALIBRATE | EQ, 1 solution에서 iteration `BBHT_CALIB_ITERS` 회와 measurement 1회의 시간. `SW_CALIB_ITER` · `SW_CALIB_MEASURE` 줄 |
| SUBSET | mask와 seed 범위로 고른 일부. workload는 서로 독립이라 나눠 돌려도 FULL과 결과가 같습니다 |

### 출력 줄

workload 하나에 `SW_RUN` 한 줄입니다. 열은 `model, predicate, target_count, seed_index, seed_j, seed_meas,
success, result_index, trial_count, L_BBHT, actual_grover_iterations, termination, saturations, timer_hi, timer_lo`
이고, 시간은 `timer_hi × 2³² + timer_lo` µs입니다. `termination`은 0 성공 · 1 shot cap · 2 BBHT budget입니다. 옛
`orca_sw_baseline`과 달리 앞에 `model` · `predicate` 두 열이 있고 seed가 16진수라 옛 parsing script를 그대로
쓰지 않습니다. 끝 표시는 `[RVX/END] ORCA_BBHT_BASELINE`입니다.

---

## source 구조

```
main()
 ├─ oracle 준비 (solution bitset)                     ← 시간 밖
 ├─ timer 시작
 ├─ bbht_search()
 │    shot마다: number of iterations 뽑기 → state 계산 → measurement → 종료 검사
 │      state 계산   ③ 0 iterations 이면 uniform superposition 그대로, 아니면 bbht_core_opt_iterate × number of iterations
 │                   ① bbht_core_naive_iterate × number of iterations
 │                   ② bbht_k3h3_lookup: hit이면 보관 state 그대로
 │                      아니면 bbht_k3h3_execute (policy → 보관 state에서 Grover iteration을 이어 감)
 │      measurement  prefix sum 준비 (계산, 식, 또는 보관본 재사용) → bbht_sample_rows
 ├─ timer 끝
 └─ SW_RUN 출력                                       ← 시간 밖
```

| file | 내용 |
|---|---|
| `main.c` | entry point. profile별 실행, 시간 benchmark, 출력. RVX header는 이 file만 씁니다 |
| `baseline_config.h` | model과 profile 설정 |
| `bbht_q14.h` | constant, data type, function 선언 |
| `bbht_core.c` | number of iterations random number · measurement random number, sampling range 상한 table, round-half-to-even, oracle bitset, 최적화 core, measurement |
| `bbht_naive.c` | ① core: oracle 적용 뒤 row마다 16,384개 inner product |
| `bbht_k3h3.c` | ② hit 확인, policy, memory(24-bit 압축, 작업 buffer 상주, uniform superposition 재생성, checkpoint별 prefix sum) |
| `bbht_search.c` | BBHT search loop. 세 model 공통이고, ②는 hit하지 않았을 때만 다음 shot 3개의 number of iterations를 미리 계산해 policy에 넘깁니다 |
| `p500_workloads.h` | 생성 file: solution index 1,364개(20 datasets), seed 100쌍. 손으로 고치지 않습니다 |

heap(`malloc`)과 floating-point는 쓰지 않습니다. 큰 array는 모두 global입니다.
