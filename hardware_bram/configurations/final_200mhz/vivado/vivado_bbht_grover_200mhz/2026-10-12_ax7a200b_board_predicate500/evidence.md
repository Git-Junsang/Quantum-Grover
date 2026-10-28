# final configuration 200 MHz revision — 200T board Predicate500 (4,000/4,000, 100 MHz revision보다 1.87× · 1.75×)

## 무엇인가

원격 board AX7A200B 에 200 MHz revision의 100T 예산 bitstream([implementation 묶음](../2026-10-12_ax7a200b_budget100t/evidence.md))을
굽고 `bbht_console` 을 올린 뒤, 같은 원격 host에서 `software/host_fpga_develop/bbht_predicate500.py` 로 네 predicate ×
500 workloads를 Restart mode · Checkpoint mode로 돌렸습니다(2026-10-12 23:20~23:48 KST,
`hardware_bram/sim/board_run.sh K3H3_E4_M2_200MHz predicate500`). benchmark 뒤 board는 원래 설계로 되돌렸습니다.

console은 `platform=bbht_grover_200mhz`, `accel_clk_hz=200000000` 을 찍었습니다.

## 확정 수치

| mode | 실행 | reference model 대비 | RTL 대비 cycle | wall-clock time sum |
|---|--:|:-:|:-:|--:|
| Restart mode | 2,000 | 2,000/2,000 | 2,000/2,000 | 256,243 µs |
| Checkpoint mode | 2,000 | 2,000/2,000 | 1,831/2,000 | 126,222 µs |

20 datasets의 FNV-1a 도 reference model과 같습니다. predicate별 표는 `result.txt` 입니다.

같은 board에서 잰 100 MHz revision([2026-10-08 묶음](../../../../final/vivado/vivado_bbht_grover_fpga/2026-10-08_ax7a200b_board_predicate500/evidence.md))과
맞대면 이렇습니다. BBHT trajectory(결과 index · shot count · requested iterations · executed iterations)는 두 mode 모두 실행마다 같습니다.

| mode | cycle sum (100 → 200 MHz revision) | wall-clock time sum (100 → 200 MHz revision) | wall-clock time 비 |
|---|--:|--:|--:|
| Restart mode | 46,886,677 → 49,222,449 (×1.0498) | 478,949 → 256,243 µs | **1.869× 빠름** |
| Checkpoint mode | 21,083,867 → 23,223,865 (×1.1015) | 221,021 → 126,222 µs | **1.751× 빠름** |

clock이 2×가 되어도 2×가 안 되는 이유는 둘입니다. 하나는 pipeline register로 늘어난 cycle(×1.05 · ×1.10)이고,
다른 하나는 실행마다 붙는 driver · console overhead입니다. wall-clock time에서 cycle 환산값을 빼면 두 revision 모두 실행당
5 µs 안팎이 남고, 이 몫은 clock과 무관합니다.

- Checkpoint mode cycle 중 RTL 과 다른 169건은 대부분 ±3,279 cycles 안팎(memo table 청소 한 번)입니다. board는 네 predicate를
  reset 없이 이어 돌고 RTL harness는 predicate마다 따로 돌아 청소가 일어나는 실행이 다릅니다(11장 11.5절). 100 MHz revision의
  같은 benchmark도 1,831/2,000 이었습니다.

## 인용할 때

- board wall-clock time 축, 200T board입니다. 성능 세 축의 Board-Verified Build(100T, EQ 500)와 섞지 마십시오.
- 100 MHz revision과의 speedup은 같은 board · 같은 host 도구로 잰 revision 사이 비교입니다.
- 이 bitstream은 timing 여유가 +0.066 ns 입니다. 이 board · 이 benchmark에서 기능이 맞았다는 뜻이고, 온도나 전압 여유를
  따로 시험하지는 않았습니다.

## file

| file | 내용 |
|---|---|
| `predicate500.csv` | 실행 4,000 rows (reference model 대조 열 포함) |
| `result.txt` | host 도구 출력 (predicate · mode별 sum과 판정) |
| `crosscheck.txt` | RTL Predicate500 · 100 MHz revision board benchmark와의 대조 |
| `sha256.txt` | 굽은 bitstream과 console hex hash |
