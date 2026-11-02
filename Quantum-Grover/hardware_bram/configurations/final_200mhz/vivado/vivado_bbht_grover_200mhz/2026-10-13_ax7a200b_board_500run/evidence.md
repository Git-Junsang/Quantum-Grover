# final configuration 200 MHz revision — 200T board 500 runs (Restart mode 64,103 µs · Checkpoint mode 31,576 µs)

## 무엇인가

원격 board AX7A200B 에 200 MHz revision의 100T 예산 bitstream([implementation 묶음](../2026-10-12_ax7a200b_budget100t/evidence.md))을
굽고 `bbht_paper_bench` 를 올려, 500 workloads(1/4/16/64/256 solutions × 100 seeds, EQ)를 Restart mode(mode0)와
Checkpoint mode(mode1)로 돈 benchmark입니다. 2026-10-13 00:28 KST 에 `hardware_bram/sim/board_run.sh K3H3_E4_M2_200MHz` 로 쟀고,
benchmark 뒤 board는 원래 설계로 되돌렸습니다. app hex 는 100 MHz revision과 byte가 같습니다(`sha256.txt`).

## 확정 수치

| mode | executed iterations | cycle | wall-clock time | RTL 대비 |
|---|---:|---:|---:|:-:|
| mode0 Restart mode | 31,424 | 12,372,608 | **64,103 µs** | BBHT trajectory 500/500 · cycle 500/500 |
| mode1 Checkpoint mode | 9,582 | 5,868,798 | **31,576 µs** | BBHT trajectory 500/500 · cycle 500/500 |

app 자체 판정은 `BBHT PAPER BOARD BENCHMARK PASS` (`pair_fail=0`, `mismatch=0`, `plan_mismatch=0`), 오류 row(timeout ·
unexpected_error) 0 입니다. RTL 대비는 [200 MHz revision RTL Predicate500](../../../results/2026-10-12_predicate500_rtl/evidence.md)의
EQ 1,000 실행과 맞댄 것입니다. 같은 workload라 실행마다 대응됩니다.

같은 board에서 잰 100 MHz revision([2026-10-08 500 runs](../../../../final/vivado/vivado_bbht_grover_fpga/2026-10-08_ax7a200b_board_500run/evidence.md))과
맞대면 이렇습니다. BBHT trajectory(성공 · 결과 index · shot count · requested iterations · executed iterations · STATUS)는 두 mode 모두 500/500 같습니다.

| mode | cycle (100 → 200 MHz revision) | wall-clock time (100 → 200 MHz revision) | wall-clock time 비 |
|---|--:|--:|--:|
| Restart mode | 11,785,382 → 12,372,608 (×1.0498) | 120,077 → 64,103 µs | **1.873× 빠름** |
| Checkpoint mode | 5,328,877 → 5,868,798 (×1.1013) | 55,529 → 31,576 µs | **1.759× 빠름** |

Restart mode 대비 Checkpoint mode speedup은 이 revision에서 2.030×입니다(100 MHz revision 2.162×). Checkpoint mode 쪽 cycle이 더 많이 늘었기
때문입니다.

## 인용할 때

- **board wall-clock time 축, 200T board**입니다. 성능 세 축의 Board-Verified Build(2026-09-07 build, 100T)와 섞어 speedup을 만들지 마십시오.
- 100 MHz revision과의 speedup은 같은 board · 같은 app으로 잰 revision 사이 비교입니다.
- wall-clock time은 명령을 넣은 순간부터 DONE 을 본 순간까지의 RVX 실시간 clock(1 MHz) 값입니다. 설정 · DMA ·
  결과 읽기 · printf 는 빠져 있습니다.

## file

| file | 내용 |
|---|---|
| `uart.log` | board UART 원본. 줄 머리의 `\r` 만 뗐습니다 |
| `per_run.csv` | 실행 한 줄에 한 row (`parse_benchmark.py` 해석, 100 MHz revision `per_run.csv` 와 같은 열) |
| `summary.csv` | mode별 총계 |
| `crosscheck.txt` | 100 MHz revision board 500 runs · 200 MHz revision RTL 과의 대조 |
| `sha256.txt` | 굽은 bitstream과 app hex 의 hash |
