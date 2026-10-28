# 2026-10-04 board Predicate500 — checkpoint revision(final configuration) 네 predicate × 500

## 결론

2026-09-17에 board에서 확인한 Bus Interface 교체 revision bitstream에 2026-09-25 revision console을 올리고,
host 자동 test(`software/host_fpga_develop/bbht_predicate500.py`)로 **LT · GT · EQ · RANGE 각 500 workloads × Restart mode · Checkpoint mode = 4,000 실행**을 돌렸습니다.

- **4,000/4,000 HIT, software reference model과 네 축(`result_index` · `trial_count` · `L_BBHT` ·
  `actual_iter`) 4,000/4,000, predicate 판정 4,000/4,000.** LT · GT · RANGE가 실물에서 benchmark
  규모로 돈 것은 이번이 처음입니다.
- 같은 workload의 RTL testbench([`results/2026-09-25_predicate500_rtl/`](../../../results/2026-09-25_predicate500_rtl/evidence.md))와
  BBHT trajectory 4,000/4,000, cycle은 Restart mode 2,000/2,000 · Checkpoint mode 1,769/2,000이 같습니다.
  어긋난 231건은 memo table 청소가 끼는 실행이 달라서입니다(아래).
- **EQ 500은 Board-Verified Build 500 runs(2026-09-08)와 같은 dataset · 같은 seed입니다.** Checkpoint
  mode가 Board-Verified Build와 BBHT trajectory 500/500, cycle 442/500 같고, wall-clock time sum은 **55,963 µs 대
  55,798 µs (+0.30%)**입니다. cycle이 같은 442건은 wall-clock time도 ±3 µs 안입니다.
  Bus Interface 교체 revision의 wall-clock time이 Board-Verified Build와 같다는 첫 benchmark입니다.

## 무엇을 구웠나

| 항목 | 값 |
|---|---|
| bitstream | sha256 `1b67a070…52adc61` — [`bitstream/2026-09-25_console_predicate500/`](../../../bitstream/2026-09-25_console_predicate500/evidence.md) (2026-09-17 것과 byte 동일) |
| app | `bbht_console.sram.hex` 2026-09-25 UART revision, sha256 `fe8c9b1b…acfad2b2`. `ID` 응답 `csr_ver=0.9.8` `platform=bbht_grover_upgrade` `fw=2026-09-25` |
| host | `bbht_predicate500.py`, 115200 8N1. board로 보낸 묶음(`board_1_bram_checkpoint.tar.gz`)의 bitstream · hex hash는 저장소와 같습니다 |
| 날짜 | 결과 Excel 생성 시각 2026-10-04 05:15 (KST) 기준 |
| 순서 | smoke(네 predicate × 다섯 가지 number of solutions × seed 0·1 × 두 mode = 80 실행) → 본 실행 4,000. 그 사이 reset 없음(본 실행 첫 `ID` 가 `loaded=1`) |

## 결과 (네 predicate × 500, `summary.csv`)

| predicate | Restart mode wall-clock time | Checkpoint mode wall-clock time | speedup | Restart mode cycle | Checkpoint mode cycle |
|---|---:|---:|---:|---:|---:|
| LT | 118,770 µs | 55,192 µs | 2.152× | 11,625,100 | 5,265,100 |
| GT | 124,960 µs | 57,063 µs | 2.190× | 12,241,889 | 5,454,399 |
| EQ | 120,383 µs | 55,963 µs | 2.151× | 11,785,382 | 5,341,488 |
| RANGE | 114,862 µs | 52,814 µs | 2.175× | 11,234,306 | 5,029,190 |
| sum | 478,975 µs | 221,032 µs | **2.167×** | 46,886,677 | 21,090,177 |

executed iterations sum은 Restart mode 125,106 · Checkpoint mode 37,659입니다. wall-clock time은 실행마다
cycle 환산값보다 4~7 µs 깁니다(COMMAND 쓰기부터 DONE 확인까지의 driver 몫).

여기서 Restart mode는 이 bitstream의 `burst_enable=0` 입니다. 4 PEs와 Dual-Row Build · Two-Level Select가 켜져 있어
Board-Verified Build 500 runs의 Restart mode(Stage 1, 425,502 µs)와는 다른 configuration이고, 그 표와 맞대면 안
됩니다.

## 대조

| 상대 | BBHT trajectory | cycle |
|---|---|---|
| RTL testbench Predicate500 (4,000) | 4,000/4,000 | Restart mode 2,000/2,000, Checkpoint mode 1,769/2,000. sum 차이 −2,949 cycles (0.014%) |
| SoC RTL simulation console 16실행 ([`2026-09-25_soc_rtl_predicate500`](../../../results/2026-09-25_soc_rtl_predicate500/evidence.md)) | 16/16 | 15/16. 다른 1건(LT, 256 solutions, seed 0, Checkpoint mode)은 정확히 3,279 cycles — simulation은 reset 직후 첫 search |
| Board-Verified Build EQ 500 ([`2026-09-08_k3h3_e4_m2_board_500run`](../2026-09-08_k3h3_e4_m2_board_500run/evidence.md)) | 500/500 | 442/500, 다른 58건은 ±3,279 안(정확히 ±3,279가 13건) |
| 이 session smoke 대 본 실행 (같은 workload 80) | 80/80 | 75/80, 다른 5건은 ±2,700~3,279 |

**Checkpoint mode cycle이 어긋나는 이유.** Policy Engine은 reset 뒤 첫 시작과 epoch가 한 바퀴 돌
때 memo table BRAM을 지웁니다(`LOOKAHEAD_SHOTS × STATE_RANKS = 3,279` cycles, 기술문서 11장). RTL testbench는
predicate마다 새로 시작했고, board는 smoke부터 네 predicate까지 reset 없이 이어 돌았으므로 청소가
끼는 실행이 서로 밀립니다. 어긋남은 전부 Checkpoint mode에서만 나오고 sign을 바꿔 가며
상쇄됩니다. 차이가 3,279 cycles보다 작은 건은 청소가 그 실행의 다른 stall과 겹친 것으로 보이나
하나씩 확인하지는 않았습니다.

## board에서 새로 본 것

- console이 내는 `# amp_overflow (진단용, 결과는 유효)` 줄 34개가 log에서 `# amp_overflow (���…)`
  로 깨져 있습니다. host가 serial을 ascii로 풀었기 때문이고 결과 값과는 무관합니다.
  `software/host_fpga_develop/bbht_cli.py` 의 `SerialTransport` 를 UTF-8 증분 decoder로 고쳤습니다.
  이 묶음의 log는 고치기 전에 받은 원본 그대로입니다.

## 인용할 때

- 성능 세 축의 Board-Verified Build는 그대로 2026-09-08 묶음입니다. 이 묶음은 네 predicate로 넓힌 board benchmark이자,
  Bus Interface 교체 revision의 wall-clock time이 Board-Verified Build와 같다는 근거입니다.
- checkpoint revision과 No-Checkpoint Baseline의 board wall-clock time 비교는
  [`hardware_bram/configurations/no_checkpoint_baseline/vivado/.../2026-10-04_board_predicate500/`](../../../../no_checkpoint_baseline/vivado/vivado_bbht_grover_nocheckpoint/2026-10-04_board_predicate500/evidence.md)
  에 있습니다.

## file

| file | 내용 |
|---|---|
| `result.csv` · `result.xlsx` | 본 실행 4,000 rows. host 프로그램 출력 그대로 |
| `result.log` | 본 실행 UART 주고받은 줄 전부 |
| `smoke.csv` · `smoke.log` | 본 실행 전 smoke 80 실행 |
| `summary.csv` | `result.csv` 를 mode × predicate × number of solutions로 묶은 sum · median (실행 수 · 일치 수 · wall-clock time · cycle · executed iterations) |
