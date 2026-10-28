# final configuration — 200T board Predicate500 (네 predicate × 500 × 두 mode, 4,000/4,000)

## 무엇인가

원격 board AX7A200B 에 final configuration의 100T 예산 bitstream을 굽고 `bbht_console` 을 올린 뒤, 같은 원격 host에서
`software/host_fpga_develop/bbht_predicate500.py` 로 네 predicate × 500 workloads를 Restart mode · Checkpoint mode로 돌렸습니다
(2026-10-08 19:16~19:45 KST, `hardware_bram/sim/board_run.sh K3H3_E4_M2 predicate500`). benchmark 뒤 board는 원래 설계로 되돌렸습니다.

## 확정 수치

| mode | 실행 | reference model 대비 | RTL 대비 cycle | wall-clock time sum |
|---|--:|:-:|:-:|--:|
| Restart mode | 2,000 | 2,000/2,000 | 2,000/2,000 | 478,949 µs |
| Checkpoint mode | 2,000 | 2,000/2,000 | 1,831/2,000 | 221,021 µs |

20 datasets의 FNV-1a 도 reference model과 같습니다. predicate별 표는 `result.txt` 입니다.

- **100T board의 같은 benchmark(2026-10-04)와 거의 같습니다**: Restart mode 478,975 µs · Checkpoint mode 221,032 µs 였습니다
  ([실험 16](../../../../../../documents/reports/16_three_revisions_board_predicate500.md)).
- Checkpoint mode cycle 중 RTL 과 다른 169건은 대부분 ±3,279 cycles(memo table 청소 한 번)입니다. board는 네 predicate를 reset 없이 이어
  돌고 RTL harness는 predicate마다 따로 돌아 청소가 일어나는 실행이 다릅니다(11장 11.5절). 2026-10-04 에도 같은 이유로 1,769/2,000 이었습니다.

## 인용할 때

- board wall-clock time 축, 200T board입니다. 성능 세 축의 Board-Verified Build(100T, EQ 500)와 섞지 마십시오.
- 여섯 configuration을 맞댄 표는 [2026-10-08_board_predicate500_6models](../../../../../results/2026-10-08_board_predicate500_6models/evidence.md) 에 있습니다.

## file

| file | 내용 |
|---|---|
| `predicate500.csv` | 실행 4,000 rows (reference model 대조 열 포함) |
| `result.txt` | host 도구 출력 (predicate · mode별 sum과 판정) |
| `crosscheck.txt` | RTL Predicate500 과의 cycle 대조 |
| `sha256.txt` | 굽은 bitstream과 console hex hash |
