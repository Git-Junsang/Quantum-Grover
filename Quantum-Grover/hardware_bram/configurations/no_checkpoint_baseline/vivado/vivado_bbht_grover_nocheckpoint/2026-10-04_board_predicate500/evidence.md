# 2026-10-04 board Predicate500 — No-Checkpoint Baseline 첫 board 실행

## 결론

[`bitstream/2026-09-25_nocheckpoint/`](../../../bitstream/2026-09-25_nocheckpoint/evidence.md)
를 board에 처음 굽고 네 predicate × 500 workloads를 Restart mode로 돌렸습니다(2,000 실행).

- **2,000/2,000 HIT, software reference model과 네 축 2,000/2,000, predicate 판정 2,000/2,000.**
- RTL testbench([`results/2026-09-25_predicate500_rtl/`](../../../results/2026-09-25_predicate500_rtl/evidence.md))와
  **cycle까지 2,000/2,000 같습니다.** SoC RTL simulation console 16실행과도 cycle 16/16,
  smoke 40 과 본 실행도 40/40 같습니다. checkpoint가 없어 실행 이력에 따라 cycle이 달라질
  곳이 없습니다.
- **같은 board에서 final configuration이 No-Checkpoint Baseline보다 wall-clock time으로 2.810× 빠릅니다**
  (621,210 µs 대 221,032 µs). RTL cycle speedup 2.897×와 같은 방향이고, board cycle로 나눈
  분해도 RTL 과 같습니다(Dual-Row Build/Two-Level Select 1.3033× × checkpoint 2.2232×).

## 무엇을 구웠나

| 항목 | 값 |
|---|---|
| bitstream | sha256 `68b7963f…086819d4` — 묶음 `sha256sums.txt` 와 같음. board로 보낸 묶음(`board_2_bram_nocheckpoint.tar.gz`) 안의 것도 저장소와 같음 |
| app | `bbht_console.sram.hex` 2026-09-25 UART revision, sha256 `a6fc27a5…72307e7c`. `ID` 응답 `platform=bbht_grover_nocheckpoint` `fw=2026-09-25` |
| 날짜 | 결과 Excel file 생성 시각 2026-10-04 05:15 (KST) 기준 |
| 순서 | smoke(네 predicate × number of solutions 다섯 가지 × seed 0·1 = 40) → 본 실행 2,000. host가 `platform=` 을 보고 Restart mode만 돌림 |

## 결과 (네 predicate × 500, `summary.csv`)

| predicate | No-Checkpoint Baseline wall-clock time | No-Checkpoint Baseline cycle | final configuration Checkpoint mode wall-clock time | wall-clock time speedup | cycle speedup |
|---|---:|---:|---:|---:|---:|
| LT | 154,395 µs | 15,185,717 | 55,192 µs | 2.797× | 2.884× |
| GT | 160,986 µs | 15,847,085 | 57,063 µs | 2.821× | 2.905× |
| EQ | 155,771 µs | 15,324,548 | 55,963 µs | 2.783× | 2.869× |
| RANGE | 150,058 µs | 14,752,240 | 52,814 µs | 2.841× | 2.933× |
| sum | 621,210 µs | 61,109,590 | 221,032 µs | **2.810×** | **2.897×** |

number of solutions별(네 predicate sum): 1 solution에서 2.998×, 4 solutions에서 2.861×, 16 solutions에서 2.699×, 64 solutions에서 2.501×,
256 solutions에서 2.250×로, 희소할수록 checkpoint 몫이 큽니다. RTL 에서 본 경향과 같습니다.

wall-clock time speedup이 cycle speedup보다 조금 작은 것은 실행마다 붙는 고정 4~7 µs 때문입니다.
final configuration 쪽 실행이 짧아서 그 비중이 더 큽니다.

| 같은 board · 같은 2,000 workloads | wall-clock time sum | cycle sum | No-Checkpoint Baseline 대비 (wall-clock time / cycle) |
|---|---:|---:|---:|
| No-Checkpoint Baseline (4 PEs) | 621,210 µs | 61,109,590 | 1.000× / 1.000× |
| final configuration Restart mode (4 PEs · Dual-Row Build · Two-Level Select) | 478,975 µs | 46,886,677 | 1.297× / 1.303× |
| final configuration Checkpoint mode | 221,032 µs | 21,090,177 | 2.810× / 2.897× |

final configuration 수치의 근거는
[`hardware_bram/configurations/final/vivado/.../2026-10-04_board_predicate500/`](../../../../final/vivado/vivado_bbht_grover_fpga/2026-10-04_board_predicate500/evidence.md)
입니다. 두 configuration은 서로 다른 bitstream을 같은 board에 차례로 구워 같은 host program으로
돌렸습니다.

## 인용할 때

- 이것은 **board wall-clock time 축**이고 workload는 Predicate500(네 predicate)입니다. 성능 세 축의
  Board-Verified Build(2026-09-08, EQ 500, Stage 1 대비 7.626×)와는 기준 configuration이 달라 speedup을 섞으면
  안 됩니다.
- log의 `# amp_overflow (���…)` 17줄은 host decoding 문제로 깨진 것입니다(final configuration
  묶음 참고). 결과 값과 무관합니다.

## file

| file | 내용 |
|---|---|
| `result.csv` · `result.xlsx` | 본 실행 2,000 rows |
| `result.log` | 본 실행 UART 주고받은 줄 전부 |
| `smoke.csv` · `smoke.log` | smoke 40 실행 |
| `summary.csv` | mode × predicate × number of solutions 묶음 sum · median |
