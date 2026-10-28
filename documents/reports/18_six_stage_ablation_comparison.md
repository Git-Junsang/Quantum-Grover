# 실험 18. Six-Stage Ablation configuration과 implementation 방식별 비교

> [← 실험 17 C++ · NumPy · Qiskit baseline 비교](17_cpp_numpy_qiskit_baselines.md) · [index](index.md) · [실험 19 ORCA · server software baseline과 FPGA 비교 →](19_orca_server_software_baseline.md)

---

| 확인한 것 | 근거의 축 |
|---|---|
| final configuration에 이르는 여섯 단계 각각의 몫. 같은 board 위 implementation 방식별 비교의 인용처 | RTL cycle (bench500, 연달아) · 200T board wall-clock time (100T resource 예산) |

이 실험은 "같은 hardware에서 implementation 방식만 바꾸면 얼마나 빨라지는가" 에 답합니다. final
configuration에 이르는 여섯 단계를 각각 독립된 build로 만들고, 같은 chip · 같은 SoC · 같은 app ·
같은 workload로 RTL과 board에서 잰 결과를 한곳에 모았습니다(2026-10-06~08).

각 기법이 **어떻게** 동작하는지는 기술문서 9~11장([9장](../design_references/09_iteration_datapath_and_number_of_pes.md) ·
[10장](../design_references/10_measurement_unit_and_microarchitecture.md) · [11장](../design_references/11_checkpoint_and_policy_engine.md)),
각 기법을 **왜** 골랐는지의 개별 실험은 [실험 05](05_checkpoint_policy_selection.md) ~ [실험 09](09_measurement_bottleneck_and_microarchitecture.md)에 있습니다.
이 실험은 그 기법들을 한 줄로 세운 이유와, 그 줄을 따라 잰 결과를 다룹니다.

---

## 왜 여섯 단계로 나눴나

### 비교의 원칙: 한 번에 하나만 바꾼다

host의 software와 FPGA를 맞대면 기계 구조도 implementation 방식도 달라서 무엇이 속도를 냈는지
가를 수 없습니다. 그래서 chip과 SoC를 고정하고 Accelerator Core의 compile parameter만 하나씩 바꿨습니다.
인접한 두 단계는 정확히 한 요인만 다르므로, 두 단계의 차이가 곧 그 요인의 효과입니다.

여섯 단계는 이렇게 쌓입니다.

| 단계 | 앞 단계에서 바꾼 것 | 줄이려는 비용 | 기법의 근거 |
|---|---|---|---|
| Stage 1 | (baseline) shot마다 uniform superposition에서 다시 iteration | — | [3장](../design_references/03_grover_and_bbht_algorithm.md) |
| Stage 2 | checkpoint 도입: 앞 shot의 amplitude를 저장해 재활용 | **executed iterations** | [11장](../design_references/11_checkpoint_and_policy_engine.md) · [실험 05](05_checkpoint_policy_selection.md) |
| Stage 3 | 1 PE → 4 PEs, 한 iteration의 512 rows를 4 rows씩 나눠 처리 | **iteration 한 번의 cycle** | [9장](../design_references/09_iteration_datapath_and_number_of_pes.md) · [실험 08](08_one_pe_profiling_and_four_pes.md) |
| Stage 4 | Checkpoint-Capacity 4 → 3, Lookahead-Shots 4 → 3 | **policy stall** | [실험 07](07_lookahead_shots_reduction.md) |
| Stage 5 | Measurement Unit의 Build를 cycle당 두 rows로 | **measurement segment(Build)** | [10장](../design_references/10_measurement_unit_and_microarchitecture.md) · [실험 09](09_measurement_bottleneck_and_microarchitecture.md) |
| final configuration | row 선택을 16 groups → 32 rows 두 단으로 | **measurement segment(Select)** | 같음 |

### 순서는 병목이 옮겨 간 순서다

단계의 순서는 임의가 아니라, 하나를 줄이면 다음 병목이 드러난 개발 순서를 따릅니다.

1. **checkpoint가 먼저입니다.** BBHT는 shot마다 uniform superposition에서 다시 시작하므로 앞 shot이 이미 지나온
   iteration을 매번 다시 합니다. 이 낭비를 없애는 것이 가장 큰 몫이라 첫 단계입니다.
2. **그다음 4 PEs입니다.** executed iterations를 줄이고 나니 남은 시간은 iteration 한 번의 512 rows streaming에 몰려
   있었습니다(1 PE에서 iteration 한 번 1,033 cycles 중 1,031). 같은 iteration의 row를 여러 PE가 나눠 처리하면
   줄어듭니다.
3. **Checkpoint-Capacity · Lookahead-Shots 축소는 4 PEs 뒤라야 이득입니다.** a Checkpoint-Capacity of 3 and 3-shot Lookahead는 policy stall을 줄이는 대신 executed iterations를 조금 더 씁니다.
   iteration 한 번이 비싼 1 PE에서는 손해이고, iteration이 싸진 4 PEs에서야 이득이 됩니다. 이 실험의 benchmark가 이를
   숫자로 보여 줍니다(「[단계별 손익](#단계별-손익)」).
4. **measurement 최적화가 마지막입니다.** 4 PEs가 iteration 시간을 줄이자 measurement가 절반을 넘는 병목이 됐습니다.
   Dual-Row Build는 4 PEs의 4 rows 동시 읽기 port를 measurement에도 쓰는 구조라 **4 PEs 없이는 켤 수 없습니다**(RTL이 4 PEs일
   때만 Dual-Row Build · Two-Level Select를 생성합니다). Two-Level Select는 Dual-Row Build 위에 얹은 선택 방식입니다.

### 누적 ablation study의 한계와 보완

ablation study는 앞 단계 위에 쌓으므로, 한 단계의 몫은 앞 단계들이 무엇을 이미 줄였는지에 따라 달라집니다.
예를 들어 Dual-Row Build · Two-Level Select의 몫이 큰 것은 4 PEs와 checkpoint가 다른 segment를 줄여 measurement의 비중이 커졌기 때문이기도
합니다. 이를 보완하는 정보가 두 가지 있습니다.

- **각 build의 mode0(Restart mode)은 number of PEs · Measurement Microarchitecture가 같고 checkpoint가 없는 configuration입니다.** checkpoint build를 Restart mode로
  돌리면 checkpoint hardware가 쉬는 경로로 돌고, 4 PEs에서는 checkpoint를 아예 뺀 build와 cycle까지
  같습니다([20장 20.3절](../design_references/20_no_checkpoint_baseline.md#203-accelerator-core에서-바꾼-것--4-pes를-checkpoint에서-떼어-냄)).
  그래서 여섯 build × 두 mode로 "checkpoint 없이 4 PEs만", "checkpoint 없이 4 PEs · Dual-Row Build · Two-Level Select" 같은 조합도
  같이 나옵니다(「[RTL cycle (bench500)](#rtl-cycle-bench500)」의 mode0 열).
- **Checkpoint-Capacity와 Lookahead-Shots를 따로 떼어 본 실험**이 [실험 07](07_lookahead_shots_reduction.md#checkpoint-capacity와-lookahead-shots를-따로-떼어-본-실험)에 있습니다. 다만 그 실험은 workload마다 따로 돌린
  RTL이라 「[단계별 손익](#단계별-손익)」의 주의를 함께 읽으십시오.

1 PE의 Restart mode는 checkpoint를 아예 뺀 `capacity0_pes1_singlerow_linear` build와 cycle이 조금 다릅니다(executed iterations · shot마다
2 cycles, 합계 0.18%). 1 PE는 checkpoint 유무에 따라 amplitude memory의 읽기 latency가 다르기 때문입니다
([`capacity0_pes1_singlerow_linear` bench500](../../hardware_bram/configurations/capacity0_pes1_singlerow_linear/results/2026-10-08_bench500/evidence.md)).
이 실험의 Stage 1 시간은 Six-Stage Ablation과 같은 정의인 `capacity4_lookahead4_pes1_singlerow_linear` build의 mode0입니다.

---

## 여섯 configuration과 변인 통제

여섯 단계는 `hardware_bram/configurations/`의 configuration directory 여섯 개입니다. configuration directory에는 adapter의 parameter
기본값과 RVX platform 정의만 있고, Accelerator Core를 포함한 RTL은 공용 `hardware_bram/src/` 한 벌입니다
([5장 5.2절](../design_references/05_hardware_architecture_overview.md#hardware-directory-tree와-bram-configuration)).

| 단계 | configuration | checkpoint | Checkpoint-Capacity | Lookahead-Shots | number of PEs | Dual-Row Build | Two-Level Select | RVX platform |
|---|---|:-:|:-:|:-:|:-:|:-:|:-:|---|
| Stage 1 | `capacity4_lookahead4_pes1_singlerow_linear` mode0 | 1 | 4 | 4 | 1 | 0 | 0 | `bbht_grover_capacity4_lookahead4_pes1_singlerow_linear` |
| Stage 2 | `capacity4_lookahead4_pes1_singlerow_linear` mode1 | 1 | 4 | 4 | 1 | 0 | 0 | 같음 |
| Stage 3 | `capacity4_lookahead4_pes4_singlerow_linear` | 1 | 4 | 4 | 4 | 0 | 0 | `bbht_grover_capacity4_lookahead4_pes4_singlerow_linear` |
| Stage 4 | `capacity3_lookahead3_pes4_singlerow_linear` | 1 | 3 | 3 | 4 | 0 | 0 | `bbht_grover_capacity3_lookahead3_pes4_singlerow_linear` |
| Stage 5 | `capacity3_lookahead3_pes4_dualrow_linear` | 1 | 3 | 3 | 4 | 1 | 0 | `bbht_grover_capacity3_lookahead3_pes4_dualrow_linear` |
| final configuration | `final` | 1 | 3 | 3 | 4 | 1 | 1 | `bbht_grover_final` |

a Checkpoint-Capacity of 3 and 3-shot Lookahead를 1 PE로 만든 configuration(`capacity3_lookahead3_pes1_singlerow_linear`)도 함께 쟀습니다. Six-Stage Ablation에는 없지만 Checkpoint-Capacity · Lookahead-Shots 축소가 1 PE와 4 PEs에서 반대로
작용하는 것을 보여 주는 대조군입니다.

configuration 사이에 같은 것과 다른 것입니다.

| 같은 것 | 다른 것 |
|---|---|
| 공용 RTL `hardware_bram/src/` (Bus Interface · Accelerator Core · 주변), SoC(ORCA 50 MHz · NoC · SRAM 128 KiB · UART), accelerator clock 100 MHz, Vivado 2026.1, app `bbht_paper_bench` · `bbht_console`, workload · seed 로스터, board 한 장(AX7A200B), 100T resource 예산 | adapter의 compile parameter(Checkpoint-Capacity · Lookahead-Shots · number of PEs · Measurement Microarchitecture)뿐 |

---

## verification 절차

여섯 configuration 모두 같은 단계를 거쳤습니다. 앞 단계가 다음 단계의 expected result가 되도록 순서를 잡았습니다.

| 순서 | 무엇 | 도구 | 판정 기준 | 결과 (여섯 모두) |
|:-:|---|---|---|---|
| 1 | port 계약 · lint · 실물 core 통신 계약 T1~T9 | `make -C hardware_bram/sim ports-configurations lint-configurations` · `real CONFIGURATION=` | 오류 0 | 통과 (2026-10-06) |
| 2 | RTL bench500: EQ 500 × 두 mode, board app과 같은 순서로 reset 없이 연달아 | `make … bench500 CONFIGURATION=` | BBHT trajectory 500/500, executed iterations가 Six-Stage Ablation과 같음 | 통과 (「[RTL cycle (bench500)](#rtl-cycle-bench500)」) |
| 3 | Arty 100T 실제 implementation | RVX `make imp` (arty-100t) | timing 통과 | 통과 (「[implementation 결과 (Arty 100T)](#implementation-결과-arty-100t)」) |
| 4 | 200T implementation, 100T resource 예산 | `/fpga-syn-rvx --budget-100t` | timing 통과, Available이 100T와 같음 | 통과 |
| 5 | board EQ 500 × 두 mode | `hardware_bram/sim/board_run.sh <configuration>` | bench500과 workload마다 논리 넷 · **cycle** 일치 | 1,000/1,000 (「[board benchmark — EQ 500](#board-benchmark--eq-500)」) |
| 6 | RTL Predicate500: 네 predicate × 500 × 두 mode | `make … predicate500 CONFIGURATION=` | reference model과 결과 · BBHT trajectory · executed iterations · predicate 판정 일치 | 4,000/4,000 |
| 7 | board Predicate500 | `board_run.sh <configuration> predicate500` | 6과 같은 기준, cycle은 RTL과 대조 | 4,000/4,000 (「[board benchmark — 네 predicate](#board-benchmark--네-predicate)」) |

a Checkpoint-Capacity of 4 and 4-shot Lookahead configuration의 checkpoint executed iterations는 reference model의 a Checkpoint-Capacity of 4 and 4-shot Lookahead policy로 낸 expected result 열(`actual_iter_k4h4`)과
맞댑니다. 이 열은 2026-10-08에 더했고, EQ sum 9,058이 Six-Stage Ablation의 a Checkpoint-Capacity of 4 and 4-shot Lookahead executed iterations와 같습니다.

---

## implementation 결과 (Arty 100T)

Arty A7-100T(`xc7a100tcsg324-1`)에 실제로 구현한 결과입니다. 여섯 모두 timing을 통과합니다.
checkpoint를 뺀 두 build(Stage 1 · No-Checkpoint Baseline)를 같이 놓아 checkpoint hardware의 값을 보입니다.

| configuration | build | WNS (ns) | SoC LUT | SoC BRAM tile | DSP | Accelerator Core LUT | Accelerator Core FF | Accelerator Core RAMB36 / RAMB18 |
|---|---|--:|--:|--:|--:|--:|--:|--:|
| Stage 1 | `capacity0_pes1_singlerow_linear` | +0.094 | 20,185 | 66 | 68 | 8,601 | 8,631 | 2 / 64 |
| Stage 2 | `capacity4_lookahead4_pes1_singlerow_linear` | +0.186 | 25,273 | 98 | 68 | 13,624 | 13,610 | 50 / 32 |
| a Checkpoint-Capacity of 3, 3-shot Lookahead and 1 PE | `capacity3_lookahead3_pes1_singlerow_linear` | +0.267 | 25,049 | 87 | 68 | 13,404 | 13,398 | 39 / 32 |
| No-Checkpoint Baseline | `no_checkpoint_baseline` | +0.193 | 38,133 | 111 | 68 | 24,846 | 21,650 | 47 / 64 |
| Stage 3 | `capacity4_lookahead4_pes4_singlerow_linear` | +0.193 | 42,495 | 115 | 68 | 29,080 | 25,820 | 51 / 64 |
| Stage 4 | `capacity3_lookahead3_pes4_singlerow_linear` | +0.083 | 42,277 | 115 | 68 | 28,842 | 25,617 | 51 / 64 |
| Stage 5 | `capacity3_lookahead3_pes4_dualrow_linear` | +0.056 | 45,347 | 116 | 132 | 32,419 | 28,178 | 52 / 64 |
| final configuration | `final` | +0.196 | 45,116 | 116 | 132 | 32,180 | 28,221 | 52 / 64 |

100T의 Available은 LUT 63,400 · FF 126,800 · BRAM tile 135 · DSP 240입니다. 가장 빠듯한 resource는
BRAM으로, 4 PEs 이상에서 85~86%입니다. BRAM을 쓰는 곳은 Accelerator Core와 system SRAM(RAMB36 32개) 둘뿐입니다.
`no_checkpoint_baseline`은 2026-09-25, `final`은 2026-09-16, 나머지는 2026-10-07~08 builds입니다. 같은
Vivado 2026.1 · 같은 흐름이지만 placement가 달라 LUT는 수백 개 단위로 흔들립니다(Stage 5와 final configuration의 LUT 역전이 그 예).
report와 200T build 수치는 [impl_6models](../../hardware_bram/results/2026-10-07_impl_6models/evidence.md)에 있습니다.

---

## RTL cycle (bench500)

`bench500`은 board app과 같은 순서(number of solutions 바깥 · seed 안쪽 · seed마다 Restart mode 다음 checkpoint)로 500 workloads를 **reset 없이 연달아** 돕니다. 그래서 checkpoint memo table state까지 board와 같아지고, 「[board benchmark — EQ 500](#board-benchmark--eq-500)」의
board cycle이 이 표와 workload마다 같습니다.

| configuration | mode0 Restart mode cycle | mode1 Checkpoint mode cycle | checkpoint executed iterations | policy stall |
|---|--:|--:|--:|--:|
| `capacity4_lookahead4_pes1_singlerow_linear` | 42,308,335 | 16,249,048 | 9,058 | 538,433 (3.31%) |
| `capacity3_lookahead3_pes1_singlerow_linear` | 42,308,335 | 16,386,112 | 9,582 | 104,009 (0.63%) |
| `capacity4_lookahead4_pes4_singlerow_linear` | 15,324,548 | 9,161,217 | 9,058 | 611,581 (6.68%) |
| `capacity3_lookahead3_pes4_singlerow_linear` | 15,324,548 | 8,812,672 | 9,582 | 116,695 (1.32%) |
| `capacity3_lookahead3_pes4_dualrow_linear` | 13,429,380 | 6,933,385 | 9,582 | 132,576 (1.91%) |
| `final` | 11,785,382 | 5,328,877 | 9,582 | 172,066 (3.23%) |

Restart mode executed iterations는 여섯 모두 31,424, 총 shot은 7,403입니다. executed iterations와 Stage 1 cycle은 Six-Stage
Ablation과 한 자리까지 같습니다. mode0 열은 number of PEs · Measurement Microarchitecture가 같고 checkpoint가 없는 configuration의 cycle입니다(「[왜 여섯 단계로 나눴나](#왜-여섯-단계로-나눴나)」).
근거: [bench500_6models](../../hardware_bram/results/2026-10-07_bench500_6models/evidence.md).

---

## board benchmark — EQ 500

원격 board AX7A200B 한 장에 여섯 build를 차례로 굽고 `bbht_paper_bench`로 잰 wall-clock time입니다
(2026-10-08). **여섯 모두 board cycle이 bench500과 workload마다 같습니다(각 1,000/1,000).**

| 단계 | build · mode | RTL cycle | board wall-clock time | Stage 1 대비 | 직전 단계 대비 |
|---|---|--:|--:|--:|--:|
| Stage 1 | `capacity4_lookahead4_pes1_singlerow_linear` mode0 | 42,308,335 | 425,322 µs | 1.000× | — |
| Stage 2 | `capacity4_lookahead4_pes1_singlerow_linear` mode1 | 16,249,048 | 164,725 µs | 2.582× | -61.27% |
| Stage 3 | `capacity4_lookahead4_pes4_singlerow_linear` mode1 | 9,161,217 | 93,841 µs | 4.532× | -43.03% |
| Stage 4 | `capacity3_lookahead3_pes4_singlerow_linear` mode1 | 8,812,672 | 90,350 µs | 4.707× | -3.72% |
| Stage 5 | `capacity3_lookahead3_pes4_dualrow_linear` mode1 | 6,933,385 | 71,551 µs | 5.944× | -20.81% |
| final configuration | `final` mode1 | 5,328,877 | 55,529 µs | 7.659× | -22.39% |

cycle 축의 speedup(7.939×)이 wall-clock time 축(7.659×)보다 큰 것은, 실행마다 붙는 고정 시간(명령 · 완료 확인)이
짧은 실행일수록 비중이 커서입니다. 두 축을 섞어 speedup을 만들지 마십시오. 대조군 `capacity3_lookahead3_pes1_singlerow_linear`는 Restart mode
425,310 µs · Checkpoint mode 166,103 µs입니다. 근거:
[board500_6models](../../hardware_bram/results/2026-10-08_board500_6models/evidence.md).

---

## board benchmark — 네 predicate

같은 여섯 build를 `bbht_console`과 host 도구 `bbht_predicate500.py`로 네 predicate(LT · GT · EQ · RANGE)
× 500 × 두 mode로 돌렸습니다(configuration당 4,000 실행, 28분).

| 단계 | build · mode | reference model 대비 | board wall-clock time sum | Stage 1 대비 |
|---|---|:-:|--:|--:|
| Stage 1 | `capacity4_lookahead4_pes1_singlerow_linear` mode0 | 2,000/2,000 | 1,695,140 µs | 1.000× |
| Stage 2 | `capacity4_lookahead4_pes1_singlerow_linear` mode1 | 2,000/2,000 | 655,650 µs | 2.585× |
| Stage 3 | `capacity4_lookahead4_pes4_singlerow_linear` mode1 | 2,000/2,000 | 375,555 µs | 4.514× |
| Stage 4 | `capacity3_lookahead3_pes4_singlerow_linear` mode1 | 2,000/2,000 | 360,952 µs | 4.696× |
| Stage 5 | `capacity3_lookahead3_pes4_dualrow_linear` mode1 | 2,000/2,000 | 286,397 µs | 5.919× |
| final configuration | `final` mode1 | 2,000/2,000 | 221,021 µs | 7.670× |

- 여섯 build의 Restart mode · Checkpoint mode 모두 결과 · BBHT trajectory · executed iterations · predicate 판정이 reference model과 실행마다
  같습니다(sum 24,000/24,000).
- Restart mode cycle은 여섯 모두 RTL Predicate500과 2,000/2,000 같습니다. Checkpoint mode cycle은
  1,828~1,853/2,000이 같고, 나머지는 대부분 memo table 청소 한 번만큼(a Checkpoint-Capacity of 3 and 3-shot Lookahead ±3,279, a Checkpoint-Capacity of 4 and 4-shot Lookahead ±4,372 cycles)
  다릅니다. board는 네 predicate를 이어 돌고 RTL harness는 predicate마다 따로 돌아 청소가 일어나는 실행이 다른
  것이고, 합계 차이는 0.1% 미만입니다.
- predicate별 최종 speedup은 7.59~7.78×로, **implementation 방식별 이득이 특정 predicate에 기대지 않습니다.**

근거: [board_predicate500_6models](../../hardware_bram/results/2026-10-08_board_predicate500_6models/evidence.md).

---

## 단계별 손익

board 시간(EQ 500)으로 얻은 것과 Accelerator Core resource(Arty 100T)로 낸 값을 나란히 놓으면 이렇습니다.

| 단계 | 시간 (직전 대비) | Accelerator Core LUT | Accelerator Core FF | BRAM tile (SoC) | DSP |
|---|--:|--:|--:|--:|--:|
| checkpoint 도입 (Stage 1 → Stage 2) | -61.27% | +5,023 | +4,979 | +32 | 0 |
| 1 PE → 4 PEs | -43.03% | +15,456 | +12,210 | +17 | 0 |
| a Checkpoint-Capacity of 4 and 4-shot Lookahead → a Checkpoint-Capacity of 3 and 3-shot Lookahead | -3.72% | -238 | -203 | 0 | 0 |
| Dual-Row Build | -20.81% | +3,577 | +2,561 | +1 | +64 |
| Two-Level Select | -22.39% | placement 차이 안 | placement 차이 안 | 0 | 0 |

- **checkpoint**는 32 BRAM tiles로 시간을 61% 줄입니다. 가장 효율이 좋은 단계입니다.
- **4 PEs**는 논리를 가장 많이 씁니다. Accelerator Core LUT가 두 배를 넘습니다.
- **Dual-Row Build**의 값은 DSP 64개(squarer 한 벌)입니다. **Two-Level Select**는 resource를 거의 늘리지 않고 measurement 선택을 바꿔
  시간을 22% 더 줄입니다. synthesis 수준에서는 final configuration이 Stage 5보다 LUT 183개 많았습니다([19장](../design_references/19_synthesis_implementation_bitstream.md)).

### Checkpoint-Capacity · Lookahead-Shots 축소는 4 PEs 뒤에서만 이득이다

a Checkpoint-Capacity of 3 and 3-shot Lookahead는 a Checkpoint-Capacity of 4 and 4-shot Lookahead보다 executed iterations를 524번 더 쓰는 대신 policy stall을 줄입니다. bench500으로 보면:

| | policy stall 감소 | executed iterations 증가 | 총 cycle 변화 | 늘어난 iteration 하나의 값 |
|---|--:|--:|--:|--:|
| 1 PE (`capacity4_lookahead4_pes1_singlerow_linear` → `capacity3_lookahead3_pes1_singlerow_linear`) | 434,424 | +524 | **+137,064 (느려짐)** | 약 1,091 cycles |
| 4 PEs (`capacity4_lookahead4_pes4_singlerow_linear` → `capacity3_lookahead3_pes4_singlerow_linear`) | 494,886 | +524 | **-348,545 (빨라짐)** | 약 279 cycles |

늘어난 iteration 하나의 값은 (총 cycle 변화 + policy stall 감소) ÷ 524로 구한 근사값입니다. 1 PE에서는 iteration
한 번이 비싸 policy stall을 줄인 몫을 넘어서고, 4 PEs에서는 iteration이 약 4분의 1로 싸져 축소가 이득이 됩니다.
board wall-clock time도 같은 방향입니다(1 PE 164,725 → 166,103 µs, 4 PEs 93,841 → 90,350 µs). Six-Stage Ablation에서 Checkpoint-Capacity · Lookahead-Shots 축소가
4 PEs 뒤에 오는 이유이고, [실험 07](07_lookahead_shots_reduction.md)의 "4 PEs 뒤의
재조정" 을 board에서 확인한 것입니다.

### workload마다 reset한 RTL은 Checkpoint-Capacity · Lookahead-Shots 축소의 몫을 크게 잰다

2026-09-08의 Six-Stage Ablation(iverilog, workload마다 새로 시작)은 Stage 3 → Stage 4를 -7.66%로
쟀지만, 연달아 도는 bench500과 board는 -3.80% · -3.72%입니다. 두 campaign의 checkpoint cycle 차이를
실행 수로 나누면 a Checkpoint-Capacity of 4 and 4-shot Lookahead 단계는 실행당 약 4,170~4,200, a Checkpoint-Capacity of 3 and 3-shot Lookahead 단계는 약 3,120~3,150 cycles로, memo table 청소
한 번의 값(a Checkpoint-Capacity of 4 and 4-shot Lookahead 4,372 · a Checkpoint-Capacity of 3 and 3-shot Lookahead 3,279, 「[board benchmark — 네 predicate](#board-benchmark--네-predicate)」)에 가깝습니다. workload마다 reset하면 매 실행이 memo table
청소를 치르고, a Checkpoint-Capacity of 4 and 4-shot Lookahead의 memo table이 더 커서 그만큼 불리하게 잡힙니다. 실행당 차이 약 1,093 cycles ×
500(약 55만)이 두 campaign의 Checkpoint-Capacity · Lookahead-Shots 몫 차이(약 51만 cycles)와 비슷합니다.

따라서 Checkpoint-Capacity · Lookahead-Shots 축소의 몫은 board와 같은 조건인 **-3.7%대를 인용하십시오.** [실험 07](07_lookahead_shots_reduction.md#checkpoint-capacity와-lookahead-shots를-따로-떼어-본-실험)의 Checkpoint-Capacity · Lookahead-Shots 단독 실험(1 PE,
workload마다 reset)도 같은 효과를 포함하고 있을 수 있습니다. 실행당 memo table 청소 값은 board · RTL cycle
차이에서 읽은 것이고, 파형으로 하나씩 확인하지는 않았습니다.

---

## 100T Board-Verified Build와의 대조

같은 app · 같은 workload로 2026-09-08에 Arty 100T에서 잰 Board-Verified Build(2026-09-07 build)와 workload마다
맞댔습니다.

| configuration | 논리 넷 | cycle | wall-clock time sum (100T → 200T) |
|---|:-:|:-:|--:|
| final configuration | 500/500 | **500/500 같음** | 55,798 → 55,529 µs (-0.48%) |
| a Checkpoint-Capacity of 4 and 4-shot Lookahead (`capacity4_lookahead4_pes1_singlerow_linear` mode1) | 500/500 | 실행마다 1~25 cycles 차이 | 164,897 → 164,725 µs (-0.10%) |
| Restart mode (`capacity4_lookahead4_pes1_singlerow_linear` mode0) | 500/500 | 실행마다 1~31 cycles 차이 | 425,502 → 425,322 µs (-0.04%) |

- final configuration은 board · Bus Interface · Vivado revision이 달라도 cycle까지 같습니다. wall-clock time은 실행마다
  -2~+2 µs로, 실행당 고정 시간이 약 0.5 µs 짧아진 만큼입니다.
- 2026-09-08의 Restart mode · a Checkpoint-Capacity of 4 and 4-shot Lookahead는 1 PE 시절의 옛 `capacity4_lookahead4_pes1_singlerow_linear` bitstream으로 쟀습니다. 현행 RTL이
  실행마다 몇 cycle 더 걸리지만 BBHT trajectory는 같습니다.
- Stage 1 → final configuration speedup은 100T 7.626×, 200T 7.659×입니다.

---

## 인용할 때

- 이 실험의 board 수치는 **200T board(100T resource 예산)의 wall-clock time 축**입니다. 성능 세 축의 source of truth는
  여전히 2026-09-07 build의 100T board evidence bundle이고([1장 1.5절](../design_references/01_project_overview.md#15-성능-지표와-인용-기준)),
  이 실험은 같은 board 위 **implementation 방식별 비교**의 인용처입니다. 두 evidence bundle을 섞어 speedup을 만들지 마십시오.
- RTL cycle은 「[RTL cycle (bench500)](#rtl-cycle-bench500)」(bench500, 연달아)에서 인용합니다. Six-Stage Ablation(workload마다 reset)과 섞지
  마십시오(「[단계별 손익](#단계별-손익)」).
- 합계를 인용할 때는 EQ 500인지 네 predicate 2,000인지 함께 적으십시오.
- Stage 1의 시간은 checkpoint build의 Restart mode이고, resource는 `capacity0_pes1_singlerow_linear` build입니다(「[왜 여섯 단계로 나눴나](#왜-여섯-단계로-나눴나)」).
- resource · timing은 Arty 100T report(「[implementation 결과 (Arty 100T)](#implementation-결과-arty-100t)」)에서 인용하고, 200T build의 WNS는 0 이상인지만 봅니다.
- 같은 chip의 ORCA software baseline은 새 baseline code로 다시 쟀습니다([실험 19](19_orca_server_software_baseline.md)).

---

## 다시 돌리는 법

```bash
# RTL
make -C hardware_bram/sim bench500 CONFIGURATION=<configuration> BENCH500_WL=/tmp/sjs_bench500_wl_<configuration>
make -C hardware_bram/sim predicate500 CONFIGURATION=<configuration> PRED500_WL=/tmp/sjs_pred500_wl_<configuration>

# 200T board (원격 sdsl-fpga). board 점유 전 허락, 끝나면 원상 복구
hardware_bram/configurations/<configuration>/rvx/install_to_platform.sh
/fpga-syn-rvx <platform> 100T 예산, 앱 bbht_paper_bench
hardware_bram/sim/board_run.sh <configuration>                    # EQ 500, bench500 과 자동 대조
hardware_bram/sim/board_run.sh <configuration> predicate500 3600   # 네 predicate
.claude/skills/fpga-flash/scripts/sdsl_fpga.sh restore --pcie
```

configuration마다 workload directory를 따로 주면 여러 configuration의 RTL testbench를 동시에 돌릴 수 있습니다. board 운용의 자세한
절차는 [17장 17.9절](../design_references/17_board_operation.md#179-원격-200t-board-ax7a200b)에 있습니다.
