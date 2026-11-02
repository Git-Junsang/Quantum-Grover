# DRAM Variant + AXI4 bridge — 네 predicate × 500 workloads가 software reference model과 2,000/2,000 일치

## 무엇인가

board에 들어가는 DRAM Variant RTL 전체를 `make -C hardware_dram/sim predicate500` 으로
**LT · GT · EQ · RANGE 네 predicate × 500 workloads**에 걸어 돌린 결과입니다. 이 variant를 처음으로
**AXI4까지** 이어서 검증한 묶음입니다.

```
드라이버(bbht_grover_driver.c) --APB/AHB--> bbht_dram_axi_top --AXI4 32b--> axi4_mem_model
                                            └ bbht_dram_top (통신 계층 + DRAM Main IP)
                                            └ grover_dram_axi_bridge (736b 행 <-> 32b 워드)
```

- 최상단 `src/bbht_dram_axi_top.v` 는 RVX platform `bbht_grover_dram` 의 user region이
  무는 바로 그 module입니다. board와 다른 것은 AXI 뒤쪽(NoC + MIG 대신 model) 하나입니다
- harness `testbench/tb_dram_predicate500.cpp` 는 hardware_bram의 `tb_predicate500.cpp` 와
  stimulus·driver 호출·CSV 형식이 같습니다. mode는 Restart mode 하나입니다 — 이 variant에는
  checkpoint가 없고 `burst_enable` 은 계약 호환용으로 무시됩니다
- stimulus와 expected result는 hardware_bram과 같은 file입니다
  (`software/reference_model_data/2026-09-25_predicate500/`)
- AXI model은 두 벌로 돌렸습니다. 기본(AR latency 20, B latency 8, backpressure 없음)과
  `AXI_STALL=1`(awready · wready · arready · rvalid에 LFSR로 불규칙한 빈틈)

## 확정 수치

두 벌 모두 같은 결과입니다.

| predicate | 실행 | rc | result_index | predicate verification | trial_count | L_BBHT | actual_iter |
|---|---:|---:|---:|---:|---:|---:|---:|
| LT | 500 | 500/500 | 500/500 | 500/500 | 500/500 | 500/500 | 500/500 |
| GT | 500 | 500/500 | 500/500 | 500/500 | 500/500 | 500/500 | 500/500 |
| EQ | 500 | 500/500 | 500/500 | 500/500 | 500/500 | 500/500 | 500/500 |
| RANGE | 500 | 500/500 | 500/500 | 500/500 | 500/500 | 500/500 | 500/500 |

AXI 심판(`axi4_mem_model`)은 네 process 모두 **protocol 위반 0, 16 beat 초과 burst 0,
한 번도 안 쓴 data word 읽기 0**, bridge `axi_error` 0입니다. 쓰기 burst 153,824~195,776개,
읽기 burst 3,029,376~3,165,536개를 predicate마다 주고받았습니다.

### actual_iter는 무엇과 맞대는가

DRAM 표는 **dataset load나 predicate 변경 때만** 버려집니다. seed가 바뀌어도 살아 있어서,
한 dataset에서 seed 0~99를 차례로 돌면 앞 seed가 키운 checkpoint slot을 뒤 seed가 그대로
복원합니다. 그래서 search마다 표를 비우는 reference model의 `DRAM_ALL_J` 가 아니라, 같은 순서로
표 하나를 이어 쓰는 `actual_iter_dram_session` 열과 맞댑니다(reference model에
`run_single(checkpoint=...)` 인자를 더해 만든 열). 첫 smoke에서 `DRAM_ALL_J` 와 맞대
12건 중 6건이 어긋난 것이 이 차이였고, session 열로 바꾼 뒤 전부 맞았습니다.

EQ의 session executed iterations sum은 **245**로, 추상 port 위에서 잰
[`2026-09-10_bench500_dram_vs_bram`](../2026-09-10_bench500_dram_vs_bram/evidence.md) 의 값과
같습니다. 같은 BBHT trajectory를 AXI를 거쳐서도 그대로 냅니다.

## cycle — 32-bit AXI가 드는 값

| predicate | cycle (기본 latency) | cycle (backpressure) | executed iterations |
|---|---:|---:|---:|
| LT | 60,268,229 | 79,929,941 | 253 |
| GT | 61,099,761 | 81,114,978 | 266 |
| EQ | 60,376,263 | 80,016,593 | 245 |
| RANGE | 58,002,373 | 76,619,462 | 209 |

### bridge revision — 16 beat burst

이 묶음의 CSV · `report.txt` 는 **최종 bridge**(burst 최대 16 beat, AW/AR 네 개까지
띄움, W는 awlen queue로 `wlast`)의 값입니다. bridge는 같은 날 두 번 바뀌었습니다.

| revision | burst | 바꾼 이유 | 이 표의 cycle |
|---|---|---|---|
| 1 | 256 beat, 둘까지 띄움 | — | 위 표와 같음 |
| 2 | 256 beat, `w_left` 를 한 cycle 늦게 계산 | 100 MHz에서 `w_left` 경로가 2.1 ns 모자람 | predicate마다 약 1만 더 (0.02%) |
| **3 (최종)** | **16 beat, 넷까지 띄움, awlen queue** | SoC RTL simulation에서 RVX NoC가 16 beat 넘는 쓰기를 쪼개고 조각마다 B를 돌려줘 첫 search가 멈춤 | **위 표. revision 1과 한 cycle도 다르지 않음** |

revision 3은 burst 수가 16×(한 checkpoint slot 46 → 736)지만 AW/AR을 넷까지 띄워 throughput이 revision 1과
같고, W 쪽에서 길이 계산이 빠져 revision 2의 빈 cycle도 없습니다. AXI model은 이제 16 beat를
넘는 burst를 오류로 세고(`MAX_BEATS`), 두 벌 모두 오류 0입니다. 세 revision 모두 BBHT trajectory
여섯 축은 2,000/2,000이었습니다. 경위는
[기술문서 21장](../../../documents/design_references/21_dram_variant.md)
3절에 있습니다.

추상 port에 한 cycle 한 row(736 bits)짜리 model을 물렸던 2026-09-10 묶음은 EQ가
9,380,081 cycles였습니다. 32-bit AXI로는 한 row가 23 data words라, 한 checkpoint slot(512 rows)을 옮기는 데
최소 11,776 cycles가 듭니다. 그래서 같은 BBHT trajectory가 약 6.4× 길어졌고, 같은 workload의 BRAM Variant
Checkpoint mode(EQ 5,328,877 cycles, [`../../../hardware_bram/configurations/final/results/2026-09-25_predicate500_rtl/`](../../../hardware_bram/configurations/final/results/2026-09-25_predicate500_rtl/evidence.md))
보다 약 11× 느립니다. board에서는 NoC를 50 MHz system clock으로 건너고 MIG도 32-bit AXI라
이보다 더 느릴 것입니다 — 이 variant가 Board-Verified Build를 이기려면 AXI 폭부터 넓혀야 한다는 뜻입니다.
RVX가 Arty A7-100T에 주는 DRAM은 32-bit `slow_dram` 하나뿐이어서(`fast_dram` 은 이 board용
설정이 없음) 이번에는 이 폭으로 붙였습니다.

## 인용할 때

- **RTL cycle 축**이고 AXI 뒤쪽이 model입니다. board 성능 근거가 아닙니다.
- 정확성(여섯 축 2,000/2,000)은 AXI model의 latency·backpressure와 무관하게 성립합니다.
- enumeration(`enum_enable=1`)는 이 variant에서 여전히 `config_error` 입니다. single search만 검증했습니다.

## 재현

```bash
python3 software/reference_model_develop/predicate500/run_predicate500_golden.py
make -C hardware_dram/sim predicate500              # 기본 지연
make -C hardware_dram/sim predicate500 AXI_STALL=1  # 백프레셔
```

## file

| file | 내용 |
|---|---|
| `per_workload_stall0.csv` | 기본 latency 2,000 rows (형식은 hardware_bram 묶음과 같음) |
| `per_workload_stall1.csv` | backpressure 2,000 rows |
| `report.txt` | 두 벌의 AXI 심판 줄과 `predicate500_report.py --branch dram` 출력 |
