# 실험 20. final configuration을 200 MHz로

> [← 실험 19 ORCA · server software baseline과 FPGA 비교](19_orca_server_software_baseline.md) · [index](index.md) · [실험 21 a Checkpoint-Capacity of 3 and 3-shot Lookahead policy memo table 압축 →](21_policy_memo_table_compaction.md)

---

| 확인한 것 | 근거의 축 |
|---|---|
| final configuration을 `clk_accel` 200 MHz로 구현할 수 있는가 | Vivado implementation report (200T, 100T 예산) |
| 값과 BBHT trajectory가 100 MHz revision과 같은가, cycle은 얼마나 늘었나 | RTL cycle |
| board에서 실제로 얼마나 빨라지나 | board wall-clock time (200T board, 100 MHz revision과 revision 사이 비교) |

100 MHz revision은 200T(100T 예산) implementation에서 setup slack이 +0.052 ns였습니다
([2026-10-07 report](../../hardware_bram/configurations/final/vivado/vivado_bbht_grover_fpga/2026-10-07_ax7a200b_budget100t/evidence.md)).
PLL만 200 MHz로 바꾸면 timing이 깨지므로 RTL에 pipeline register를 더했습니다. 고친 RTL은 공용
`hardware_bram/src/`가 아니라 새 configuration directory
[`final_200mhz`](../../hardware_bram/configurations/final_200mhz/)의 `src/`에
두었습니다(「[source를 어디에 두었나](#source를-어디에-두었나)」).

---

## 요약

- pipeline register만 더했습니다. 계산식 · 비교 순서 · random number 소비 · policy 결정은 그대로입니다.
- **100 MHz revision과 실행 4,000 번이 cycle 말고 전부 같습니다.** 결과 index · shot count · requested iterations · executed
  iterations · STATUS를 실행마다 맞댔습니다. software reference model과도 4,000/4,000입니다.
- cycle은 Restart mode +5.0 %, Checkpoint mode +10.1 % 늘었습니다. 200 MHz로 돌면 같은 일을 하는 시간이 100 MHz
  revision의 0.525× · 0.551×라는 계산이 나옵니다(RTL cycle 축, benchmark 아님).
- RVX SoC 전체를 100T 예산으로 구현해 **WNS +0.066 ns, WHS +0.051 ns로 timing이 맞았습니다.**
- 원격 200T board에서 네 predicate Predicate500 4,000 실행이 reference model과 모두 맞았습니다. 같은 board의 100 MHz revision보다
  wall-clock time이 **Restart mode 1.869×, Checkpoint mode 1.751×** 빠릅니다.

---

## 무엇이 깨졌나

200 MHz(주기 5 ns)로 처음 placement · routing했을 때 WNS -2.538 ns, failing endpoint 27,275개였습니다(Accelerator Core와 Bus Interface만
OOC로 implementation, 200T). 원인은 크게 둘이었습니다.

| 종류 | 예 |
|---|---|
| logic level이 깊은 경로 | Policy Engine의 memo table hit 판정 → miss 처리, combination generator, measurement의 61-bit prefix sum 비교, adder tree 3단 |
| routing만 긴 경로 (logic level 0~1, routing 5~6 ns) | register 하나에서 128 lanes · BRAM 44개로 퍼지는 threshold · valid · memory address |

두 번째가 컸습니다. lane과 BRAM이 chip 전체에 흩어져 있어서, register 하나가 모든 lane에 닿는 데만 5 ns가
넘었습니다.

---

## 바꾼 것

원칙은 하나입니다. **pipeline register는 값을 바꾸지 않고 latency만 늘린다.** latency가 늘면 그 signal을 기다리는 쪽이
같은 만큼 늦게 받도록 맞췄고, 순환 경로(한 cycle 안에서 끝나야 하는 갱신)는 계산을 다른 꼴로 바꾸거나
throughput을 낮췄습니다.

### broadcast signal은 register tree로

| signal | 방법 |
|---|---|
| 실행 설정(predicate · threshold · data_count · enum), 2×mean | 시작 뒤 한참 동안 바뀌지 않는 값이라 latency가 상관없습니다. 4-lane group마다, 다시 lane마다 사본 |
| datapath의 valid · op · row group 번호 | 원래 있던 latency 단(발행 뒤 2 · 3 · 4 cycles)을 그대로 복제 단으로 씀. latency가 늘지 않습니다 |
| memory request(address · EN · 쓰기) | 2단 register tree. checkpoint memory는 RAMB36 열(같은 lane을 담는 4개) 단위 → RAMB36마다, data memory는 4-bank group → RAMB18마다 |

register tree를 나누는 단위가 중요했습니다. 처음에는 row group · phase bank 단위로 나눴는데 routing이 여전히 4~5 ns였습니다.
lane b는 네 row group 모두 data bank b 옆에 놓이므로 "lane 번호" 단위로 나누자 풀렸습니다.

### memory 읽기 2 → 4 cycles

request register tree 2단이 붙어 checkpoint · data · found-mask memory 읽기가 4 cycles이 되었습니다. controller의 발행 tag,
measurement의 row group tag와 단일 row Reread, verification 대기를 모두 4 cycles에 맞췄습니다. 쓰기도 두 cycle 늦게 들어가지만
pass 경계(Pass 1 → Mean → Pass 2, Pass 2 → 다음 Pass 1, iteration → measurement)마다 마지막 쓰기와 다음 첫 읽기 사이가 한
cycle 이상 남습니다.

### Iteration Datapath

| 100 MHz | 200 MHz |
|---|---|
| pipeline stage 1 predicate · amplitude latch → oracle register → 출력 | pipeline stage 1 predicate · padding · amplitude → pipeline stage 2 hit와 25-bit subtraction 하나 → pipeline stage 3 saturation · 출력 선택 |
| adder tree 3단 + register + 2단(accumulator와 같은 cycle) | 단마다 register (5단) |
| Mean 1 cycle | 3 cycles (네 accumulator sum → round-half-to-even) |

Pass 1의 oracle(sign 반전)은 `0 − amplitude`를, Pass 2는 `2×mean − amplitude`를 같은 subtractor로 계산합니다. oracle 출력은
그 결과의 하위 23 bits이고 `grover_oracle_flip`의 값과 같습니다.

### measurement

| 자리 | 바꾼 것 |
|---|---|
| square · row weight | DSP 앞뒤 register(AREG/BREG · MREG · PREG), adder tree 단마다 register |
| Build prefix sum | 두 row weight를 먼저 register에, 60-bit prefix sum은 carry-select. group prefix sum과 total weight는 prefix sum register에서 한 cycle 뒤 |
| row · lane · group scan | "prefix sum + row weight > random number" 대신 남은 random number(random number − prefix sum)를 들고 "row weight > 남은 random number"를 봅니다. 남은 random number − row weight 한 번의 borrow가 곧 판정이라 addition 뒤 비교가 사라지고, 60-bit subtraction은 carry-select (30-bit 두 쪽) |
| lane 선택 | 32:1 mux 대신 32개 square를 돌리는 rotating register |
| rejection sampling | bit_length(total weight − 1)를 두 단으로, 수락 비교는 별도 state |

### Policy Engine

| 자리 | 바꾼 것 | 대가 |
|---|---|---|
| memo table BRAM → hit 판정 | BRAM 출력 뒤 RTL의 `H` 단에서 hit/miss를 register로 판정 | speculative planning pipeline 1단 |
| combination generator | 다음 조합을 두 cycles에 걸쳐 계산. a Checkpoint-Capacity of 3에서는 subset이 2개 이하라 `mask & −mask`로 최하위 bit를 바로 얻음 | action을 두 cycles에 하나 |
| root 평가 | 4개 sorting network를 단마다 나누고, (cost, number of segments, 정렬된 다음 checkpoint set) lexicographic 비교를 46-bit key 비교 하나로 | 단 2개 |
| non-root · leaf best 갱신 | 읽기 · 비교를 한 단 앞에서 | 단 1개 |
| rank · memo table address | 두 단으로 | 단 1개 |
| PREP · Build · FINISH | state 하나에 몰린 계산을 state 여럿으로 | frame마다 몇 cycle |

action이 두 cycles에 하나라 같은 frame의 non-root 결과가 연달아 오지 않습니다. best 갱신을 두 단으로 나눌 수
있었던 이유이고, simulation에서는 이것을 검사하는 문장이 4,000 실행 동안 한 번도 찍히지 않았습니다.

### Accelerator Core 제어 · DMA Engine

| 자리 | 바꾼 것 |
|---|---|
| 시작 수락 | register로. 설정 CSR은 COMMAND보다 APB 전송 하나 이상 먼저 쓰이므로 값이 같습니다 |
| 설정 변경 · `run_config_ok` · 한계 판정 | 미리 계산한 register. 읽는 state 앞에 wait state 하나 |
| Plan Queue | head와 일치 비교를 한 cycle 전에 register로, flush도 한 cycle 늦게 |
| Checkpoint Planner · Checkpoint Executor | Checkpoint Planner는 입력 · 1단 · 2단을 각각 register(4 cycles), Checkpoint Executor는 첫 segment 거리를 미리 계산(2 cycles) |
| Iteration-Count Predictor | 후보 하나를 두 cycles에. 같은 순서의 연산을 반 속도로 |
| DMA Engine · load 제어 | address 범위 · 개수 검사를 CSR 값에서 두 단으로 미리 계산, 쓰기 개수 saturation 비교를 단순화 |

Plan Queue와 speculative planning 결과의 만남은 100 MHz revision에도 있는 cycle 경쟁입니다(speculative planning 결과가 request보다 먼저 왔는가).
어느 쪽으로 가도 같은 결정론적 policy를 풀기 때문에 쓰이는 계획은 같고, executed iterations도 같습니다.

---

## verification

근거: [200 MHz revision RTL evidence bundle](../../hardware_bram/configurations/final_200mhz/results/2026-10-12_predicate500_rtl/evidence.md).

| 대조 | 결과 |
|---|---|
| software reference model (rc · result_index · predicate · trial_count · L_BBHT · actual_iter) | 4,000/4,000 |
| 100 MHz revision과 cycle 외 전 열 | 4,000/4,000 |
| 통신 계약 regression T1~T10 (enumeration 포함) · driver co-simulation D1~D11 | 오류 0건 |

수정마다 이 세 가지를 다시 돌렸습니다. harness가 실행 2,000 번(seed 100)을 1분 안에 끝내서 가능했습니다.

---

## implementation

### OOC 회차별 수정

Accelerator Core와 Bus Interface만 OOC로 묶어 5 ns 제약으로 placement · routing하면서 고쳤습니다. base · it1은 200T 전체, it2 부터는
실제 build와 같은 100T 예산입니다. base~it5는 작업 PC, it6 부터는 원격 server `sdsl-fpga`에서 돌렸습니다(둘 다 Vivado 2026.1).

| revision | WNS (ns) | TNS (ns) | failing endpoint | 무엇을 넣었나 |
|---|---:|---:|---:|---|
| base | -2.538 | -24,806 | 27,275 | 100 MHz revision 그대로 |
| it1 | -2.619 | -6,282 | 8,484 | memory request register, datapath 3단, measurement |
| it2 | -1.394 | -948 | 2,879 | Policy Engine `H` 단 · combination generator 2 cycles · 분할 |
| it4 | -0.691 | -201 | 917 | broadcast register tree, 시작 수락 · DMA Engine · BBHT |
| it7 | -0.573 | -32 | 266 | lane 기준 register tree, 열 기준 memory register tree, carry-select |
| it8 | -0.124 | -1.7 | 46 | Checkpoint Planner · Plan Queue · group scan |
| it8s | **+0.089** | 0 | 0 | it8 + 강한 placement · routing directive |

"강한 directive"는 `place_design -directive ExtraTimingOpt`, `phys_opt_design -directive AggressiveExplore`,
`route_design -directive AggressiveExplore`, routing 뒤 `phys_opt_design`입니다. 같은 RTL도 실행마다 WNS가 0.1 ns
안팎 흔들립니다(it9s는 endpoint 하나가 -0.022 ns).

### SoC 전체

Accelerator Core · Bus Interface에 RVX SoC 전체(ORCA core · NoC · peripheral)를 더해 같은 100T 예산으로 구현했습니다. 예산 영역을
SoC와 나눠 쓰는 만큼 OOC보다 빡빡해서, placement 직후 WNS는 -0.326 ns였습니다. placement 뒤 `phys_opt_design`이 -0.025 ns
까지 줄였고 routing이 +0.066 ns로 닫았습니다. Vivado는 원격 server `sdsl-fpga`에서 돌렸습니다
([implementation evidence bundle](../../hardware_bram/configurations/final_200mhz/vivado/vivado_bbht_grover_200mhz/2026-10-12_ax7a200b_budget100t/evidence.md)).

| 항목 | 100 MHz revision (2026-10-07) | 200 MHz revision |
|---|--:|--:|
| setup WNS / hold WHS | +0.052 / +0.030 ns | +0.066 / +0.051 ns |
| LUT / FF | 45,316 / 45,210 | 44,573 / 66,870 |
| BRAM tile / DSP | 116 / 132 | 116 / 132 |
| Accelerator Core LUT / FF | 32,234 / 28,221 | 32,855 / 49,830 |
| Slice | 15,118 / 15,850 | 15,288 / 15,850 |
| 전력 (추정, 활동률 없음) | 0.59 W | 1.43 W |

100 MHz revision은 기본 directive로, 200 MHz revision은 강한 directive로 구현했으므로 WNS 값끼리는 맞대지 않습니다.

### board

원격 200T board에 굽고 `bbht_console`로 네 predicate × 500 workloads를 두 mode로 돌렸습니다
([board evidence bundle](../../hardware_bram/configurations/final_200mhz/vivado/vivado_bbht_grover_200mhz/2026-10-12_ax7a200b_board_predicate500/evidence.md)).

| mode | reference model 대비 | RTL 대비 cycle | wall-clock time sum (100 → 200 MHz revision) | wall-clock time 비 |
|---|:-:|:-:|--:|--:|
| Restart mode | 2,000/2,000 | 2,000/2,000 | 478,949 → 256,243 µs | 1.869× 빠름 |
| Checkpoint mode | 2,000/2,000 | 1,831/2,000 | 221,021 → 126,222 µs | 1.751× 빠름 |

Checkpoint mode cycle이 RTL과 다른 169건은 memo table 청소 시점 차이이고, 100 MHz revision의 같은 benchmark도 1,831/2,000이었습니다.

`bbht_paper_bench` 500 runs(EQ, 500 workloads × 두 mode)도 같은 board에서 돌렸습니다
([500 runs evidence bundle](../../hardware_bram/configurations/final_200mhz/vivado/vivado_bbht_grover_200mhz/2026-10-13_ax7a200b_board_500run/evidence.md)).
app 판정은 PASS이고, board cycle이 200 MHz revision RTL과 두 mode 모두 500/500 같습니다.

| mode | wall-clock time sum (100 → 200 MHz revision) | wall-clock time 비 |
|---|--:|--:|
| Restart mode | 120,077 → 64,103 µs | 1.873× 빠름 |
| Checkpoint mode | 55,529 → 31,576 µs | 1.759× 빠름 |
BBHT trajectory는 100 MHz revision board benchmark와도 실행마다 같습니다. 2×에 못 미치는 것은 늘어난 cycle과, 실행마다 붙는 5 µs 안팎의
driver · console overhead 때문입니다.

---

## 비용

| 비용 | 크기 |
|---|---|
| cycle | Restart mode ×1.050, Checkpoint mode ×1.101. memory 읽기 2 → 4 cycles과 단마다 더한 register, Policy Engine이 action을 두 cycles에 하나 내는 몫 |
| FF | Accelerator Core 28,221 → 49,830 (+77 %). Slice를 96 % 씁니다 |
| 전력 추정 | 0.59 → 1.43 W (clock 2×와 FF 증가) |
| timing slack | +0.066 ns. RTL이나 directive를 바꾸면 다시 맞춰야 합니다 |
| source 관리 | Accelerator Core가 두 벌(공용 · 이 configuration)입니다 (「source를 어디에 두었나」) |

Checkpoint mode 쪽 증가분(×1.10)의 대부분은 Policy Engine의 throughput을 반으로 낮춘 몫입니다. 이것을 되찾으면 Checkpoint mode도
Restart mode 수준(×1.05)에 가까워지지만, combination generator 순환 경로를 한 cycle에 다시 넣어야 해서 slack 0.066 ns 안에서는 시도하지
않았습니다.

---

## source를 어디에 두었나

다른 configuration은 adapter 하나만 갖고 Accelerator Core는 공용 `hardware_bram/src/`를 씁니다
([5장 5.2절](../design_references/05_hardware_architecture_overview.md#52-module-layer와-file-지도)). 이 revision은 사용자 요청에 따라
고친 RTL을 configuration directory `src/`에 두었습니다. 공용 source와 같은 이름의 file은 이쪽 것이 이깁니다.

| 쓰는 곳 | 방법 |
|---|---|
| simulation | configuration `sim/Makefile`이 file마다 configuration `src/`에 있으면 그것을, 없으면 공용 것을 씀 |
| RVX | configuration `rvx/install_to_platform.sh`가 공용 설치 뒤 configuration `src/`의 RTL로 덮어씀 |

그래서 이 revision의 cycle을 다른 configuration과 맞댈 때는 RTL이 다르다는 것을 함께 밝혀야 합니다. 공용 source로 옮기면
다른 configuration 열 개도 cycle이 바뀌므로, 옮길지는 따로 정할 일입니다.

---

## 하지 않은 것

- 온도 · 전압 여유는 시험하지 않았습니다. slack 0.066 ns로 이 board에서 기능이 맞았다는 것까지입니다.
- Arty 100T로는 구현하지 않았습니다.
- RVX SoC RTL simulation(Questa, `bbht_console` script)은 돌리지 않았습니다. verilator harness는 Bus Interface + Accelerator Core까지입니다.
- 공용 `hardware_bram/src/`와 다른 configuration은 건드리지 않았습니다.

---

## 인용할 때

- cycle은 RTL cycle 축입니다. "시간 비" 0.525 · 0.551은 clock 비를 곱한 계산값이고, board에서 잰 값은 0.535 · 0.571
  (1.869× · 1.751×)입니다. 둘을 섞지 마십시오.
- 1.869× · 1.751×(Predicate500), 1.873× · 1.759×(500 runs)는 같은 200T board 위 revision 사이 비교입니다.
- timing · resource는 200T에 100T 예산을 건 build의 값입니다. Board-Verified Build의 Arty 100T report와 맞대지 마십시오.
- 성능 세 축([1장 1.5절](../design_references/01_project_overview.md#15-성능-지표와-인용-기준))은 이 revision과 무관합니다.

---

## 다시 돌리는 법

```bash
M=hardware_bram/configurations/final_200mhz
make -C $M/sim predicate500 predicate500-ref equiv real driver    # RTL (몇 분)
$M/rvx/install_to_platform.sh                                      # RVX platform bbht_grover_final_200mhz
hardware_bram/sim/board_run.sh final_200mhz predicate500 3600  # board 네 predicate (30분쯤)
hardware_bram/sim/board_run.sh final_200mhz                    # board 500런 (15초쯤)
```

placement · routing 흐름과 원격 build 조건은 [implementation evidence bundle](../../hardware_bram/configurations/final_200mhz/vivado/vivado_bbht_grover_200mhz/2026-10-12_ax7a200b_budget100t/build_info.txt), board에
굽는 절차는 [bitstream evidence bundle](../../hardware_bram/configurations/final_200mhz/bitstream/2026-10-12_ax7a200b/evidence.md)에 있습니다.
