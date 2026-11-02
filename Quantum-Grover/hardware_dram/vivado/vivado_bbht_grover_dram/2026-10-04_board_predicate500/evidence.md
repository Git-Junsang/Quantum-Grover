# 2026-10-04 board Predicate500 — DRAM Variant 첫 board 실행

## 결론

[`bitstream/2026-09-25_dram_axi/`](../../../bitstream/2026-09-25_dram_axi/evidence.md)를 board에
처음 굽고 네 predicate × 500 workloads를 Restart mode로 돌렸습니다(2,000 실행). **DDR3(MIG
`slow_dram`)가 실물에서 accelerator의 amplitude table로 쓰인 첫 기록입니다.**

- **2,000/2,000 HIT, software reference model과 네 축 2,000/2,000, predicate 판정 2,000/2,000.** executed iterations는
  expected result의 `actual_iter_dram_session` 열과 맞댔습니다(DRAM 표를 seed 사이에 이어 씀).
- 묶음 evidence가 "board에서 처음 볼 것" 으로 꼽은 둘이 모두 통과했습니다. DDR3 보정이
  돼서 `HOST_TIMEOUT`이 한 번도 없었고, amplitude table checkpoint slot(NoC address `0x0`부터 최대 6 MB)이
  software와 겹치지 않았습니다.
- cycle은 SoC RTL simulation(실제 NoC · DDR model)과 16실행에서 0~0.16% 안으로 맞고, AXI memory
  model 위 RTL testbench의 1.439×입니다. SoC simulation에서 본 "약 1.4×"가 실물에서도 그대로입니다.

## 무엇을 구웠나

| 항목 | 값 |
|---|---|
| bitstream | sha256 `4e0de663…cbc3fb2a` — 묶음 `sha256sums.txt`와 같음. board로 보낸 묶음(`board_3_dram.tar.gz`) 안의 것도 저장소와 같음 |
| app | `bbht_console.sram.hex` 2026-09-25 UART revision, sha256 `152cd1e9…43e0690b`. `ID` 응답 `platform=bbht_grover_dram` `fw=2026-09-25` |
| 날짜 | 결과 Excel 생성 시각 2026-10-04 05:15 (KST) 기준 |
| 순서 | smoke(네 predicate × number of solutions 다섯 × seed 0·1 = 40) → 본 실행 2,000. host가 `platform=`을 보고 Restart mode만 돌림 |

## 결과 (네 predicate × 500, `summary.csv`)

| predicate | wall-clock time | cycle | AXI model RTL 대비 cycle |
|---|---:|---:|---:|
| LT | 869,551 µs | 86,737,066 | 1.439× |
| GT | 881,608 µs | 87,941,591 | 1.439× |
| EQ | 871,268 µs | 86,907,655 | 1.439× |
| RANGE | 836,585 µs | 83,437,956 | 1.439× |
| sum | 3,459,012 µs | 345,024,268 | 1.439× |

같은 board · 같은 2,000 workloads에서 wall-clock time은 BRAM checkpoint revision의 Checkpoint mode(221,032 µs)의
15.65×, No-Checkpoint Baseline(621,210 µs)의 5.57×입니다. number of solutions별로는 checkpoint revision 대비
13.7~18.2×입니다. 32-bit DRAM 폭으로 checkpoint slot을 옮기는 값이고, 기술문서 21장 21.7.1절이 예상한
방향(AXI model에서 약 11×, board에서는 더 느림) 그대로입니다.

## 대조

| 상대 | BBHT trajectory | cycle |
|---|---|---|
| AXI memory model RTL testbench ([`2026-09-25_predicate500_axi`](../../../results/2026-09-25_predicate500_axi/evidence.md), `STALL_EN=0`) | 2,000/2,000 | 실행별 1.000~1.460×, 중앙값 1.435×. 13건은 같음 |
| SoC RTL simulation console 16실행 ([`2026-09-25_soc_rtl_predicate500`](../../../results/2026-09-25_soc_rtl_predicate500/evidence.md)) | 16/16 | board가 0~0.16% 많음. sum 1,443,546 대 1,441,611 |
| 이 session smoke 대 본 실행 (같은 workload 40) | 40/40 | 7/40 같고 나머지는 최대 0.033% 차이 |

bram 두 revision과 달리 **같은 workload를 다시 돌려도 cycle이 수십 cycle씩 달라집니다.** 실제
DDR3의 refresh · 보정 같은 latency가 실행마다 다른 것으로 보입니다. BBHT trajectory는 늘 같으므로
기능에는 영향이 없고, cycle을 인용할 때는 이 흔들림(0.1% 안팎)을 같이 적어야 합니다.

## 인용할 때

- board wall-clock time 축, workload Predicate500입니다. 성능 세 축의 source of truth인 Board-Verified Build 묶음(2026-09-08)과 speedup을
  섞지 마십시오.
- log의 `# amp_overflow (���…)` 4줄은 host decoding 문제로 깨진 것입니다(checkpoint revision
  묶음 참고). 결과 값과 무관합니다.

## file

| file | 내용 |
|---|---|
| `result.csv` · `result.xlsx` | 본 실행 2,000 rows |
| `result.log` | 본 실행 UART 주고받은 줄 전부 |
| `smoke.csv` · `smoke.log` | smoke 40 실행 |
| `summary.csv` | mode × predicate × number of solutions 묶음 sum · 중앙값 |
