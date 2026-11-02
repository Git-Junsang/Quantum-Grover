# BBHT/Grover multi-solution search accelerator 기술문서

> 중앙대학교 학부인턴 · LPSoC BBHT/Grover project
> RVX SoC accelerator + host UART 제어 (Arty A7-100T / Artix-7 `xc7a100tcsg324-1`)

---

## 1. 이 문서에 대하여

이 기술문서는 algorithm, software reference model, RTL, interface 계약, verification, board 운용, Vivado
implementation까지 확정된 설계를 한 벌로 설명합니다. 설계를 정하거나 확인하려고 돌린 실험은
[`reports/`](../reports/index.md)에 따로 모았고, 여기서는 link만 겁니다. 팀 안의 인수인계와 설계 검토가 주된
목적이고, 처음 code를 접하는 개발자도 이 문서만으로 system의 동작과 implementation을 따라갈 수 있도록
썼습니다. quantum computing 기초부터 필요하면 학습용 해설서
[`study_references/`](../study_references/index.md)의 index부터 읽는 편이 좋고,
algorithm을 이미 안다면 [3장](03_grover_and_bbht_algorithm.md)부터 읽어도 됩니다.

### 1.1 대상 독자

- project에 새로 합류해 전체 구조를 빠르게 파악해야 하는 팀원
- RTL module을 고치기 전에 그 module의 동작 · port · 계약을 확인하려는 개발자
- BBHT trajectory나 cycle이 어긋났을 때 data 형식 · memory map · verification 체계를 거슬러 올라가야 하는 사람
- board에 굽고 host에서 직접 명령을 넣어 보려는 사람

### 1.2 현재 문서 범위

기준 시점은 2026-10-11입니다.

| 영역 | state | 수록 |
|---|---|---|
| BRAM Variant final configuration (`hardware_bram/` 의 `final` configuration) RTL · verification | board benchmark 완료 (2026-09-08, Board-Verified Build, [실험 12](../reports/12_board_verified_build_500_runs.md)) | 1~19장 |
| Bus Interface revision | 2026-09-17 board에서 명령 왕복 확인 ([실험 15](../reports/15_revised_bus_interface_board_console.md)) | 7장 |
| 성능 세 축 (board 시간 · RTL cycle · ORCA 대비) | 2026-09-08 Board-Verified Build 기준 | 1장 · 15장 |
| 네 predicate × 500 workloads (Predicate500) | 세 revision RTL · SoC RTL simulation · board(2026-10-04, 8,000 runs, [실험 16](../reports/16_three_revisions_board_predicate500.md))까지 reference model과 일치 | 16장 · 18장 |
| No-Checkpoint Baseline (`no_checkpoint_baseline` configuration) | board run 2,000/2,000 (2026-10-04) | 20장 |
| DRAM Variant (`hardware_dram/`) | board run 2,000/2,000 (2026-10-04, DDR3 실물). enumeration · prefetch 없음 | 21장 |
| 설계 근거 실험, benchmark · 비교 실험 | 2026-08 reference model campaign ~ 2026-10-11 software baseline | [실험 보고서 index](../reports/index.md) |

---

## 2. 문서 구성

열 개 파트, 22개 장입니다. 순서대로 읽으면 개요에서 시작해 algorithm과 software, hardware,
interface 계약, 동작, verification과 운용, implementation, 다른 두 revision으로 이어집니다. 설계를 정하거나 확인한 실험
(설계 근거 · board benchmark · Six-Stage Ablation · software baseline)은 [실험 보고서 index](../reports/index.md)에 있습니다.

### Part Ⅰ. project와 환경

| 장 | file | 내용 |
|:-:|---|---|
| 1 | [project 개요](01_project_overview.md) | implementation 대상, 확정 spec, system layer, final configuration, 성능 세 축, board verification 이력 |
| 2 | [개발 환경과 toolchain](02_development_environment_and_toolchain.md) | 도구 version, Verilator regression, RVX platform 명령, Vivado · license, Qiskit 설치, 정합성 검사, 증상별 대처 |

### Part Ⅱ. algorithm과 software reference model

| 장 | file | 내용 |
|:-:|---|---|
| 3 | [Grover와 BBHT algorithm](03_grover_and_bbht_algorithm.md) | oracle · diffusion operator · Born-rule sampling, solution이 몇 개인지 모를 때의 BBHT, enumeration round와 Found Mask |
| 4 | [software reference model과 test vector](04_software_reference_model_and_test_vectors.md) | 세 layer의 reference model, Common500 · Predicate500 expected result, RTL test vector, Qiskit 대조법 |

### Part Ⅲ. hardware 큰 그림

| 장 | file | 내용 |
|:-:|---|---|
| 5 | [hardware architecture 개요](05_hardware_architecture_overview.md) | block 한 장, module layer · file 지도, hardware directory tree와 BRAM configuration 열 개 · tag, clock · reset 소유권, data 입출력, start 수락 조건 |
| 6 | [data 표현과 memory map](06_data_representation_and_memory_map.md) | signed16 입력, Q1.22 amplitude, 32 lanes mapping, bit width, iteration 산술, BRAM 배치, SRAM load, 비교 순서 |

### Part Ⅳ. RTL module 상세

| 장 | file | 내용 |
|:-:|---|---|
| 7 | [Bus Interface](07_bus_interface.md) | wrapper · mmio(APB) · loader(AHB) · adapter, 계약만 보고 쓴 implementation과 실물 대조, 남겨 둔 개선안 |
| 8 | [Accelerator Core 최상위와 BBHT 제어](08_accelerator_core_top_and_bbht_control.md) | module 지도, compile parameter 8개, Shot Controller, Iteration-Count LFSR, sampling range ROM, 종료 우선순위 |
| 9 | [Iteration Datapath와 4 PEs](09_iteration_datapath_and_number_of_pes.md) | Init/Pass 1/Mean/Pass 2, oracle · adder tree · diffusion operator, row group(4 rows) 분할 |
| 10 | [Measurement Unit과 Dual-Row Build · Two-Level Select](10_measurement_unit_and_microarchitecture.md) | Build/Select/Reread, integer Born-rule sampling 절차, Dual-Row Build, Two-Level Select |
| 11 | [checkpoint와 Policy Engine](11_checkpoint_and_policy_engine.md) | a Checkpoint-Capacity of 3 · segment 규약, 3-shot Lookahead DP policy, Iteration-Count Predictor, compact memo table과 initialization 이력, checkpoint / Lookahead와 연산 병렬도의 관계 |

### Part Ⅴ. interface 계약

| 장 | file | 내용 |
|:-:|---|---|
| 12 | [Accelerator Core port 계약](12_accelerator_core_port_contract.md) | 61 ports, search · DMA Engine transaction, checkpoint 계약 |
| 13 | [CSR register와 execution mode](13_csr_registers_and_execution_modes.md) | APB 38 maps, STATUS · DMA_STATUS bit, 다섯 execution mode, 생성 pipeline. `gen_csr.py` 가 생성 |
| 14 | [host interface와 UART protocol](14_host_interface_and_uart_protocol.md) | ASCII line 규약, 명령 · 응답 · 오류 token, host CLI 세 transport |

### Part Ⅵ. 동작과 timing

| 장 | file | 내용 |
|:-:|---|---|
| 15 | [동작 과정과 cycle 구성](15_operation_sequence_and_cycle_breakdown.md) | RUN 한 줄의 전체 sequence, cycle이 어디로 가는가, Six-Stage Ablation 기여 분해 |

### Part Ⅶ. verification과 board 운용

| 장 | file | 내용 |
|:-:|---|---|
| 16 | [verification 체계](16_verification_framework.md) | 여섯 층 verification, 네 predicate와 다른 두 revision의 verification, 자동 정합성 검사, 남은 verification 항목 |
| 17 | [board 운용](17_board_operation.md) | platform 설치, bitstream, board 연결 · UART, 굽기 · app load, 두 가지 app, 문제 해결 |
| 18 | [Predicate500 자동 test](18_predicate500_automated_test.md) | 네 predicate × 500 workloads, expected result, host 프로그램, Excel 결과, board 없이 시험하기 |

### Part Ⅷ. implementation

| 장 | file | 내용 |
|:-:|---|---|
| 19 | [synthesis · implementation · bitstream](19_synthesis_implementation_bitstream.md) | 두 build 비교, resource ablation study 다섯 configuration, OOC로 다시 잰 값, report 위치 |

### Part Ⅸ. 다른 두 revision

| 장 | file | 내용 |
|:-:|---|---|
| 20 | [checkpoint 없는 BRAM revision](20_no_checkpoint_baseline.md) | No-Checkpoint Baseline. 4 PEs를 checkpoint에서 떼어 낸 RTL 변경, verification, 최적화 유무 속도 |
| 21 | [DRAM Variant](21_dram_variant.md) | 모든 iteration의 amplitude를 DRAM에 저장. 32-bit AXI4 bridge, RVX `slow_dram`, 150 MHz NoC timing |

### Part Ⅹ. 부록

| 장 | file | 내용 |
|:-:|---|---|
| 22 | [부록: 용어집과 폐기된 규격](22_appendix_glossary_and_retired_specs.md) | 폐기된 값과 현행 값, 중간 단계, 용어 · 약어 |

---

## 3. 빠른 참조

자주 찾는 확정값입니다. 근거는 마지막 열의 장에 있습니다.

| 항목 | 값 | 근거 장 |
|---|---|---|
| board / FPGA | Arty A7-100T / `xc7a100tcsg324-1` (Artix-7) | [1장](01_project_overview.md) |
| qubit | 14 qubits (16,384 states) | [6장](06_data_representation_and_memory_map.md) |
| data word | 16-bit signed | [6장](06_data_representation_and_memory_map.md) |
| amplitude | 23-bit signed, Q1.22 계열, uniform amplitude raw 32768 | [6장](06_data_representation_and_memory_map.md) |
| parallelism | 32 lanes × 512 rows | [6장](06_data_representation_and_memory_map.md) |
| predicate | `LT` `GT` `EQ` `RANGE` (전부 strict) | [3장](03_grover_and_bbht_algorithm.md) |
| execution mode | `MANUAL_SINGLE` `RESTART_SINGLE` `CHECKPOINT_SINGLE` `RESTART_ENUMERATION` `CHECKPOINT_ENUMERATION` | [13장](13_csr_registers_and_execution_modes.md) |
| CSR | APB, base `0xE2020000`, 4-byte 간격, 32 bits, 38개 | [13장](13_csr_registers_and_execution_modes.md) |
| data load | AHB master SINGLE, single outstanding. SRAM `0xE0000000`~`0xE001FFFF` | [7장](07_bus_interface.md) |
| Result FIFO | 깊이 256 | [12장](12_accelerator_core_port_contract.md) |
| BBHT budget | `REQUESTED_ITERATIONS` 누적 576, 기본 shot cap 100 | [8장](08_accelerator_core_top_and_bbht_control.md) |
| clock | accelerator 100 MHz / system 50 MHz | [5장](05_hardware_architecture_overview.md) |
| final configuration | a Checkpoint-Capacity of 3, 3-shot Lookahead, 4 PEs, Dual-Row Build · Two-Level Select | [1장](01_project_overview.md) |
| 성능 세 축 | board wall-clock time · RTL cycle · ORCA 1 core 대비 (섞지 않음) | [1장 1.5절](01_project_overview.md#15-성능-지표와-인용-기준) |
| implementation resource · timing | full SoC implementation report | [19장](19_synthesis_implementation_bitstream.md) |
| checkpoint policy와 연산 병렬도의 관계 | 연산량 · 처리 속도 · policy overlap을 나누어 구성 비교 | [11장 11.8절](11_checkpoint_and_policy_engine.md#118-checkpoint-policy와-연산-병렬도의-관계) |

---

## 4. 문서 표기 규약

- signal · port · module 이름: code 식별자는 `cfg_predicate_mode`, `grover_bbht_shot_fsm`, `S_PASS1` 처럼
  씁니다.
- source 인용: 가능하면 [`bbht_grover_main_ip.v`](../../hardware_bram/src/bbht_grover_main_ip.v)
  처럼 실제 file을 상대 link로 겁니다. line 번호는 code 변경에 따라 달라지므로 module 이름이나 signal 이름을
  기준으로 찾습니다.
- 수식: 본문에 LaTeX를 쓰지 않고 code block이나 산문으로 풉니다.
- diagram: 본문에 mermaid fence를 직접 쓰지 않고 `<img>` 로 SVG · PNG를 참조합니다. 그림은
  [`diagrams/`](diagrams) 하나에 두고, mermaid source는 `diagrams/src/*.mmd` 에서
  [`render_diagrams.py`](render_diagrams.py) 로 render합니다.
- 성능 수치: board wall-clock time, RTL cycle, software 대비 중 어느 축인지 함께 적고, 다른 축을
  섞어 speedup을 만들지 않습니다([1장 1.5절](01_project_overview.md#15-성능-지표와-인용-기준)).
- 한 수치는 한 장에만 적습니다. 다른 장은 그 절로 링크합니다.
- 미확인: 검증하지 않은 항목은 해당 장에서 범위와 함께 밝힙니다.
- 13장은 `spec/gen_csr.py` 가 CSR source of truth JSON에서 생성합니다. 손으로 고치지 않습니다.

---

## 5. 이 문서와 다른 자료의 관계

자료 사이에 내용이 다르면 실제 source code와 evidence bundle(`evidence.md`)을 우선합니다. 그다음이 이
문서이고, 아래의 나머지는 보조 자료입니다.

| 자료 | 위치 | 용도 |
|---|---|---|
| `CLAUDE.md` | [../../CLAUDE.md](../../CLAUDE.md) | 작업 규칙과 정합성 기준. 무엇이 source of truth인지 여기서 정합니다 |
| 루트 README | [../../README.md](../../README.md) · [../../README.ko.md](../../README.ko.md) | project 소개와 빠른 시작 |
| 계약 source of truth | [`spec/`](../../spec/) | CSR JSON · port 계약 tsv |
| evidence bundle | 각 directory tree의 `results/` · `vivado/` · `bitstream/` | campaign별 `evidence.md` 와 원본 log |
| 실험 보고서 | [../reports/](../reports/index.md) | 설계를 정하거나 확인한 실험 01~19와 evidence bundle link |
| 학습용 해설서 | [../study_references/](../study_references/index.md) | quantum computing index · 1~18장 + 부록 A |
| 논문 원문 | [../papers/](../study_references/papers/) | BBHT · Grover 원문과 한국어 해설본 |
| 논문 목차 | [../papers/paper_outline.md](../study_references/papers/paper_outline.md) | 우리 논문(IEEE 양식)의 뼈대와 절마다 끌어올 장 · 실험 |

2026-08 reference model campaign 보고서, interface 감사 기록, source of truth 반입 기록, Pass 2 · Two-Track Execution benchmark,
그리고 Accelerator Core 최종 집약 설계 문서(v1.0.4)는 이 문서와 실험 보고서로 흡수했습니다. 설계 결정의 근거가 된
실험은 [실험 01~11](../reports/index.md#설계-근거-실험-0111)에, 폐기된 값은 [22장](22_appendix_glossary_and_retired_specs.md)에 남겼고 원본은
저장소 밖(`trash_bin/`)에 두었습니다.

---

*기준 시점: 2026-10-11 · 범위: 확정 설계 1~22장. 실험은 [`reports/`](../reports/index.md)*
