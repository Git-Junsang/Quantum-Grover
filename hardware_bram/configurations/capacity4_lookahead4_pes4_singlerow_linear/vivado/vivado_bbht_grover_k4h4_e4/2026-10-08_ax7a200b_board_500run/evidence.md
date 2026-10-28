# Stage 3 — 200T board 500 runs (Restart mode 155,476 µs · Checkpoint mode 93,841 µs)

## 무엇인가

원격 board AX7A200B(`xc7a200tfbg484-2`)에 이 configuration의 100T 예산 bitstream
([implementation report](../2026-10-07_ax7a200b_budget100t/evidence.md))을 굽고, `bbht_paper_bench`를 올려
500 workloads(1/4/16/64/256 solutions × 100 seeds, EQ)를 Restart mode(mode0)와 Checkpoint mode(mode1)로 돈 benchmark입니다.
2026-10-08 18:35 KST, `hardware_bram/sim/board_run.sh`의 절차(굽기 → UART capture → OpenOCD load)로 쟀고,
benchmark 뒤 board는 원래 설계로 되돌렸습니다. 굽은 실물은 [`../../../bitstream/2026-10-08_ax7a200b/`](../../../bitstream/2026-10-08_ax7a200b/evidence.md)입니다.

## 확정 수치

| mode | executed iterations | cycle | wall-clock time | bench500 대비 |
|---|---:|---:|---:|:-:|
| mode0 Restart mode | 31,424 | 15,324,548 | **155,476 µs** | 논리 500/500 · cycle 500/500 |
| mode1 Checkpoint mode | 9,058 | 9,161,217 | **93,841 µs** | 논리 500/500 · cycle 500/500 |

app 자체 판정은 `BBHT PAPER BOARD BENCHMARK PASS` (`pair_fail=0`, `mismatch=0`), 오류 row(timeout ·
unexpected_error) 0입니다. bench500은 [2026-10-07_bench500_6models](../../../../../results/2026-10-07_bench500_6models/evidence.md)입니다.

## 인용할 때

- **board wall-clock time 축, 200T board**입니다. configuration 사이 비교는 같은 board에서 잰
  [2026-10-08_board500_6models](../../../../../results/2026-10-08_board500_6models/evidence.md)에서 합니다.
- 성능 세 축의 source of truth는 여전히 Board-Verified Build(2026-09-07)의 100T board 묶음입니다. 이 묶음과 섞어 speedup을 만들지 마십시오.
- wall-clock time은 명령을 넣은 순간부터 DONE을 본 순간까지의 RVX 실시간 clock(1 MHz) 값입니다. 설정 · DMA ·
  결과 읽기 · printf는 빠져 있습니다.
- cycle은 bench500과 같으므로 RTL cycle 축과 board cycle이 이 configuration에서 일치합니다. 다만 다른 실행
  이력(console 한 번 등)의 cycle과는 맞대지 마십시오(memo table 청소, 11장 11.5절).

## file

| file | 내용 |
|---|---|
| `uart.log` | board UART 원본. 줄 머리의 `\r`만 뗐습니다 |
| `per_run.csv` | 실행 한 줄에 한 row (`parse_benchmark.py` 해석, 2026-09-08 `per_run_*.csv`와 같은 열) |
| `summary.csv` | mode별 총계 |
| `crosscheck.txt` | `board_vs_bench500.py --strict-cycles` 출력 |
| `sha256.txt` | 굽은 bitstream과 app hex의 hash |
