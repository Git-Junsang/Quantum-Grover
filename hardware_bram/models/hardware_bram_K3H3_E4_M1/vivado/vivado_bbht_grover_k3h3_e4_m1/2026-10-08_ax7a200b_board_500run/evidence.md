# K3/H3-E4-M1 — 200T 보드 500런 (Normal 136,532 us · 체크포인트 71,551 us)

## 무엇인가

원격 보드 AX7A200B(`xc7a200tfbg484-2`)에 이 모델의 100T 예산 비트스트림
([구현 리포트](../2026-10-07_ax7a200b_budget100t/evidence.md))을 굽고, `bbht_paper_bench` 를 올려
500 워크로드(M = 1/4/16/64/256 × 시드 100, EQ)를 Normal(mode0)과 체크포인트(mode1)로 돈 실측입니다.
2026-10-08 18:36 KST, `hardware_bram/sim/board_run.sh` 의 절차(굽기 → UART 캡처 → OpenOCD 적재)로 쟀고,
측정 뒤 보드는 원래 설계로 되돌렸습니다. 굽은 실물은 [`../../../bitstream/2026-10-08_ax7a200b/`](../../../bitstream/2026-10-08_ax7a200b/evidence.md) 입니다.

## 확정 수치

| 모드 | 물리 반복 | 사이클 | 실경과 시간 | bench500 대비 |
|---|---:|---:|---:|:-:|
| mode0 Normal | 31,424 | 13,429,380 | **136,532 us** | 논리 500/500 · 사이클 500/500 |
| mode1 체크포인트 | 9,582 | 6,933,385 | **71,551 us** | 논리 500/500 · 사이클 500/500 |

앱 자체 판정은 `BBHT PAPER BOARD BENCHMARK PASS` (`pair_fail=0`, `mismatch=0`), 오류 행(timeout ·
unexpected_error) 0 입니다. bench500 은 [2026-10-07_bench500_6models](../../../../../results/2026-10-07_bench500_6models/evidence.md) 입니다.

## 인용할 때

- **보드 실경과 시간 축, 200T 보드**입니다. 모델 사이 비교는 같은 보드에서 잰
  [2026-10-08_board500_6models](../../../../../results/2026-10-08_board500_6models/evidence.md) 에서 합니다.
- 성능 세 축의 정본은 여전히 2026-09-07 빌드의 100T 보드 묶음입니다. 이 묶음과 섞어 배수를 만들지 마십시오.
- 실경과 시간은 명령을 넣은 순간부터 DONE 을 본 순간까지의 RVX 실시간 클럭(1 MHz) 값입니다. 설정 · DMA ·
  결과 읽기 · printf 는 빠져 있습니다.
- 사이클은 bench500 과 같으므로 RTL 사이클 축과 보드 사이클이 이 모델에서 일치합니다. 다만 다른 실행
  이력(콘솔 한 번 등)의 사이클과는 맞대지 마십시오(memo 청소, 11장 11.5절).

## 파일

| 파일 | 내용 |
|---|---|
| `uart.log` | 보드 UART 원본. 줄 머리의 `\r` 만 뗐습니다 |
| `per_run.csv` | 실행 한 줄에 한 행 (`parse_benchmark.py` 해석, 2026-09-08 `per_run_*.csv` 와 같은 열) |
| `summary.csv` | 모드별 총계 |
| `crosscheck.txt` | `board_vs_bench500.py --strict-cycles` 출력 |
| `sha256.txt` | 굽은 비트스트림과 앱 hex 의 해시 |
