# DRAM 갈래 + AXI4 브리지 — 네 술어 × 500 워크로드가 SW 기준모델과 2,000/2,000 일치

## 무엇인가

보드에 들어가는 DRAM 갈래 RTL 전체를 `make -C hardware_dram/sim predicate500` 으로
**LT · GT · EQ · RANGE 네 술어 × 500 워크로드**에 걸어 돌린 결과입니다. 이 갈래를 처음으로
**AXI4 까지** 이어서 검증한 묶음입니다.

```
드라이버(bbht_grover_driver.c) --APB/AHB--> bbht_dram_axi_top --AXI4 32b--> axi4_mem_model
                                            └ bbht_dram_top (통신 계층 + DRAM Main IP)
                                            └ grover_dram_axi_bridge (736b 행 <-> 32b 워드)
```

- 최상단 `src/bbht_dram_axi_top.v` 는 RVX 플랫폼 `bbht_grover_dram` 의 user region 이
  무는 바로 그 모듈입니다. 보드와 다른 것은 AXI 뒤쪽(NoC + MIG 대신 모델) 하나입니다
- 하네스 `testbench/tb_dram_predicate500.cpp` 는 hardware_bram 의 `tb_predicate500.cpp` 와
  자극·드라이버 호출·CSV 형식이 같습니다. 모드는 NORMAL 하나입니다 — 이 갈래에는
  체크포인트가 없고 `burst_enable` 은 계약 호환용으로 무시됩니다
- 자극과 기댓값은 hardware_bram 과 같은 파일입니다
  (`software/experiments/predicate500_benchmark/expected/`)
- AXI 모델은 두 벌로 돌렸습니다. 기본(AR 지연 20, B 지연 8, 백프레셔 없음)과
  `AXI_STALL=1`(awready · wready · arready · rvalid 에 LFSR 로 불규칙한 빈틈)

## 확정 수치

두 벌 모두 같은 결과입니다.

| 술어 | 실행 | rc | result_index | 술어 검증 | trial_count | L_BBHT | actual_iter |
|---|---:|---:|---:|---:|---:|---:|---:|
| LT | 500 | 500/500 | 500/500 | 500/500 | 500/500 | 500/500 | 500/500 |
| GT | 500 | 500/500 | 500/500 | 500/500 | 500/500 | 500/500 | 500/500 |
| EQ | 500 | 500/500 | 500/500 | 500/500 | 500/500 | 500/500 | 500/500 |
| RANGE | 500 | 500/500 | 500/500 | 500/500 | 500/500 | 500/500 | 500/500 |

AXI 심판(`axi4_mem_model`)은 네 프로세스 모두 **프로토콜 위반 0, 16 beat 초과 버스트 0,
한 번도 안 쓴 워드 읽기 0**, 브리지 `axi_error` 0 입니다. 쓰기 버스트 153,824~195,776 개,
읽기 버스트 3,029,376~3,165,536 개를 술어마다 주고받았습니다.

### actual_iter 는 무엇과 맞대는가

DRAM 표는 **데이터셋 적재나 술어 변경 때만** 버려집니다. 시드가 바뀌어도 살아 있어서,
한 데이터셋에서 시드 0~99 를 차례로 돌면 앞 시드가 키운 슬롯을 뒤 시드가 그대로
복원합니다. 그래서 탐색마다 표를 비우는 기준모델의 `DRAM_ALL_J` 가 아니라, 같은 순서로
표 하나를 이어 쓰는 `actual_iter_dram_session` 열과 맞댑니다(기준모델에
`run_single(checkpoint=...)` 인자를 더해 만든 열). 첫 스모크에서 `DRAM_ALL_J` 와 맞대
12건 중 6건이 어긋난 것이 이 차이였고, 세션 열로 바꾼 뒤 전부 맞았습니다.

EQ 의 세션 물리 반복 합은 **245** 로, 추상 포트 위에서 잰
[`2026-09-10_bench500_dram_vs_bram`](../2026-09-10_bench500_dram_vs_bram/evidence.md) 의 값과
같습니다. 같은 궤적을 AXI 를 거쳐서도 그대로 냅니다.

## 사이클 — 32비트 AXI 가 드는 값

| 술어 | 사이클 (기본 지연) | 사이클 (백프레셔) | 물리 반복 |
|---|---:|---:|---:|
| LT | 60,268,229 | 79,929,941 | 253 |
| GT | 61,099,761 | 81,114,978 | 266 |
| EQ | 60,376,263 | 80,016,593 | 245 |
| RANGE | 58,002,373 | 76,619,462 | 209 |

### 브리지 판 — 16 beat 버스트

이 묶음의 CSV · `report.txt` 는 **최종 브리지**(버스트 최대 16 beat, AW/AR 네 개까지
띄움, W 는 awlen 큐로 `wlast`)의 값입니다. 브리지는 같은 날 두 번 바뀌었습니다.

| 판 | 버스트 | 바꾼 이유 | 이 표의 사이클 |
|---|---|---|---|
| 1 | 256 beat, 둘까지 띄움 | — | 위 표와 같음 |
| 2 | 256 beat, `w_left` 를 한 사이클 늦게 계산 | 100 MHz 에서 `w_left` 경로가 2.1 ns 모자람 | 술어마다 약 1만 더 (0.02%) |
| **3 (최종)** | **16 beat, 넷까지 띄움, awlen 큐** | SoC RTL 시뮬에서 RVX NoC 가 16 beat 넘는 쓰기를 쪼개고 조각마다 B 를 돌려줘 첫 탐색이 멈춤 | **위 표. 판 1 과 한 사이클도 다르지 않음** |

판 3 은 버스트 수가 16배(한 슬롯 46 → 736)지만 AW/AR 을 넷까지 띄워 처리량이 판 1 과
같고, W 쪽에서 길이 계산이 빠져 판 2 의 빈 사이클도 없습니다. AXI 모델은 이제 16 beat 를
넘는 버스트를 오류로 세고(`MAX_BEATS`), 두 벌 모두 오류 0 입니다. 세 판 모두 궤적
여섯 축은 2,000/2,000 이었습니다. 경위는
[기술문서 22장](../../../documents/design_references/22_DRAM_갈래.md)
3절에 있습니다.

추상 포트에 한 사이클 한 행(736비트)짜리 모델을 물렸던 2026-09-10 묶음은 EQ 가
9,380,081 사이클이었습니다. 32비트 AXI 로는 한 행이 23워드라, 한 슬롯(512행) 을 옮기는 데
최소 11,776 사이클이 듭니다. 그래서 같은 궤적이 약 6.4배 길어졌고, 같은 워크로드의 bram
체크포인트(EQ 5,328,877 사이클, [`../../../hardware_bram/models/hardware_bram_K3H3_E4_M2/results/2026-09-25_predicate500_rtl/`](../../../hardware_bram/models/hardware_bram_K3H3_E4_M2/results/2026-09-25_predicate500_rtl/evidence.md))
보다 약 11배 느립니다. 보드에서는 NoC 를 50 MHz 시스템 클럭으로 건너고 MIG 도 32비트 AXI 라
이보다 더 느릴 것입니다 — 이 갈래가 정본을 이기려면 AXI 폭부터 넓혀야 한다는 뜻입니다.
RVX 가 Arty A7-100T 에 주는 DRAM 은 32비트 `slow_dram` 하나뿐이어서(`fast_dram` 은 이 보드용
설정이 없음) 이번에는 이 폭으로 붙였습니다.

## 인용할 때

- **RTL 사이클 축**이고 AXI 뒤쪽이 모델입니다. 보드 성능 근거가 아닙니다.
- 정확성(여섯 축 2,000/2,000)은 AXI 모델의 지연·백프레셔와 무관하게 성립합니다.
- 열거(`enum_enable=1`)는 이 갈래에서 여전히 `config_error` 입니다. 단일 탐색만 검증했습니다.

## 재현

```bash
python3 software/experiments/predicate500_benchmark/run_predicate500_golden.py
make -C hardware_dram/sim predicate500              # 기본 지연
make -C hardware_dram/sim predicate500 AXI_STALL=1  # 백프레셔
```

## 파일

| 파일 | 내용 |
|---|---|
| `per_workload_stall0.csv` | 기본 지연 2,000행 (형식은 hardware_bram 묶음과 같음) |
| `per_workload_stall1.csv` | 백프레셔 2,000행 |
| `report.txt` | 두 벌의 AXI 심판 줄과 `predicate500_report.py --branch dram` 출력 |
