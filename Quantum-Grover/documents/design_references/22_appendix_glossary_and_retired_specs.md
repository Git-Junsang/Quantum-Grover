# 22장. 부록: 용어집과 폐기된 규격

> [← 21장 DRAM Variant](21_dram_variant.md) · [index](index.md)

---

## 22.1 폐기된 규격

다음 값은 이전 설계에서 썼으나 현재 규격에는 적용되지 않습니다. 옛 문서나 `trash_bin/` 에서
마주치면 무시하고, 현행 설계의 근거로 인용하지 않습니다. 문서 검사기가 이 값들의 부활을
자동으로 잡습니다([16장 16.8절](16_verification_framework.md#168-자동-정합성-검사)).

| 항목 | 폐기된 값 | 현행 |
|---|---|---|
| number of qubits | 15 qubits (32,768 states) · 16 qubits, runtime `n_qubits` 가변 | 14 qubits (16,384 states) 고정 + `data_count` 만 runtime |
| amplitude 형식 | Q2.16 · Q1.17 · 18-bit amplitude | signed 23-bit, 22 fraction bits |
| 확장 후보 | 15 qubits · 16 qubits · 64 lanes | 14 qubits / 32 lanes로 굳힘 ([실험 11](../reports/11_rejected_extensions.md)) |
| CSR 간격 | 8-byte 제안안 (`grover_regs.h`) | 4 bytes, 38개 |
| CSR 이름 | `mode` `thr_a` `start` `cand` … | `CONTROL` `THRESHOLD_A` `COMMAND` `RESULT_INDEX` … |
| Bus Interface module | `grover_mmio` `grover_ahb_master` (15 qubits 시절 초안) | `bbht_grover_mmio` `bbht_ahb_loader` |
| data load | AHB `INCR16` burst, 16-bit `HSIZE` | AHB SINGLE, single outstanding, 32-bit |
| measurement | amplitude가 가장 큰 칸을 고름 (argmax) | Born-rule sampling (integer prefix sum) |
| oracle | solution index를 받아 그 자리를 뒤집음 | data와 threshold만 보고 predicate로 뒤집음 |
| checkpoint | 1칸 `j_cur` / `cache_j` + `cache_valid` (Single-Slot Checkpoint) | 3 checkpoint slots + policy DP (3-shot Lookahead) |
| enumeration 위치 | Accelerator Core 밖 상위 layer | Accelerator Core 안. Result FIFO 256칸 포함 |
| bus | AXI4-Lite · AXI-Stream | APB slave + AHB master. RVX 에 AXI-Stream shim이 없음 |
| SoC | MicroBlaze | RVX rvc_orca |
| 목표 chip | XC7S100 · Arty S7-50 | Arty A7-100T (`xc7a100tcsg324-1`) |
| 옛 GitHub revision | commit `7b96551` 의 15 qubits/32 lanes/Q2.16 wrapper 수치 | SoC 구조만 참고. 산술 · 폭은 14 qubits/22 fraction bits |

옛 source 배치도 지금은 없습니다. `src_v2/`(a Checkpoint-Capacity of 4, 4-shot Lookahead에서 freeze), `src_v3/`(Pass 2–Build Fusion fork), `src_f2/`(Two-Track
Execution), `src_comm/` · `src_ablation/`(Bus Interface와 ablation study 공통 source)는 2026-09-09 ~ 2026-09-13 사이에
`src/` 한 벌로 합쳤고, board와 byte 동일한 revision은 tag `board-verified-build-2026-09-07` 에 있습니다. tag 안의
directory 이름은 옛 이름 `hardware_bram/` 그대로입니다.

### 중간 단계였던 것

a Checkpoint-Capacity of 4에 4-shot Lookahead나 8-shot Lookahead를 쓴 두 configuration은 중간 단계입니다. 2026-09-01(8-shot Lookahead) · 2026-09-04(4-shot Lookahead) board benchmark 묶음은 그 시점
근거로 남겨 두었지만 최종 성능을 인용할 자리가 아닙니다. 두 묶음은 250쌍(50 seeds)이라 500 workloads campaign과 총합을 맞댈 수도 없습니다. CSR execution mode 이름 `K4H8_*` 도 2026-09-10 에
`CKPT_*` 로 바꿨습니다([13장 13.7절](13_csr_registers_and_execution_modes.md#137-predicate와-execution-mode)).

---

## 22.2 용어

모든 문서가 이 절의 용어를 씁니다. 기준은 다섯입니다.

- 용어는 영어로 씁니다. 한글은 조사 · 어미와 일반 동사 · 서술에만 쓰고, 용어 안에 한글을 섞지 않습니다.
- 한 개념에 용어 하나입니다. quantum measurement와 성능 측정이 겹치므로 성능 측정은 benchmark라고 씁니다.
- project가 만든 약자와 양을 대신하는 기호(K · H · E · M · n · N · j · m 등)는 본문 · 표 · 그림 · 수식 어디에도
  쓰지 않습니다. 분야 표준 약어(BBHT · FPGA · BRAM · DSP · LUT · FF · CSR · APB · AHB · AXI · DMA · FIFO · FSM ·
  LFSR · PRNG · CDF · DP · DFS · PE · RTL · SoC · UART · WNS · OOC · CDC)는 씁니다.
- 고유명사와 우리가 설계한 이름은 단어마다 대문자로 시작합니다. 나머지는 문장이나 제목 첫머리여도 소문자입니다.
- 값은 숫자와 단위로 씁니다(14 qubits, 4 PEs, 3-shot Lookahead). "number of ~"는 양을 정의할 때와 표 머리 ·
  graph 축에만 씁니다.

code identifier · directory · RVX platform 이름도 이 용어에 맞췄습니다(2026-10-28). benchmark 기록 · 기록 파일의 열 이름 ·
console 출력 형식 · 이미 낸 tag는 그 시점의 이름을 그대로 둡니다. 옛 이름을 읽는 법은 이 절 끝의 「옛 표기」와
「옛 code 이름」 표에 있습니다.

### 양

| 용어 | 뜻 | 본문 표기 | 확정값 |
|---|---|---|---|
| Checkpoint-Capacity | 한 번에 남겨 둘 수 있는 checkpoint의 최대 개수. checkpoint slot은 이 값과 무관하게 4개 | a Checkpoint-Capacity of 3 | 3 |
| Lookahead-Shots | Policy Engine이 지금 shot 뒤로 미리 계획에 넣는 shot 수 | 3-shot Lookahead | 3 |
| number of PEs | Iteration Datapath의 PE 수. PE 하나가 한 cycle에 row 하나(32 lanes)를 처리 | 4 PEs | 4 |
| number of qubits | state space를 이루는 qubit 수 | 14 qubits | 14 |
| number of states | 2를 number of qubits번 곱한 값 | 16,384 states | 16,384 |
| number of lanes | row 하나에 든 state 수 | 32 lanes | 32 |
| number of solutions | dataset에서 predicate를 만족하는 index 수 | 16 solutions | workload마다 다름 |
| number of iterations | 한 shot에서 돌리는 Grover iteration 수. sampling range 안에서 균등하게 뽑음 | 100 iterations | shot마다 다름 |
| sampling range | number of iterations를 뽑는 범위. shot이 실패할 때마다 growth factor만큼 커짐(28 entries ROM) | | |
| growth factor | sampling range를 키우는 비율 | | 6/5 |
| requested iterations | 뽑힌 number of iterations의 합(`REQUESTED_ITERATIONS`). checkpoint로 줄지 않는 algorithm 지표 | | |
| executed iterations | 실제로 돌린 Grover iteration 수(`EXECUTED_ITERATIONS`). checkpoint가 줄이는 대상 | | |
| fraction bits | amplitude에서 소수점 아래 bit 수 | 22 fraction bits | 22 (Q1.22) |
| data word width | data word의 bit 폭 | 16-bit | 16 |
| row weight | row 하나에 든 32 lanes amplitude square의 sum | | |
| total weight | 모든 row weight의 합 | | |

### 구성

구성은 Checkpoint-Capacity · Lookahead-Shots · number of PEs · Measurement Microarchitecture 네 값으로 정합니다.
이름이 있는 구성은 아래 표의 것뿐이고, 나머지는 네 값을 그대로 적습니다.

| 이름 | Checkpoint-Capacity | Lookahead-Shots | number of PEs | Measurement Microarchitecture | directory |
|---|:-:|:-:|:-:|---|---|
| Stage 1 | 0 | - | 1 | Single-Row Build · Linear Select | `capacity0_pes1_singlerow_linear` |
| Stage 2 | 4 | 4 | 1 | Single-Row Build · Linear Select | `capacity4_lookahead4_pes1_singlerow_linear` |
| Stage 3 | 4 | 4 | 4 | Single-Row Build · Linear Select | `capacity4_lookahead4_pes4_singlerow_linear` |
| Stage 4 | 3 | 3 | 4 | Single-Row Build · Linear Select | `capacity3_lookahead3_pes4_singlerow_linear` |
| Stage 5 | 3 | 3 | 4 | Dual-Row Build · Linear Select | `capacity3_lookahead3_pes4_dualrow_linear` |
| final configuration | 3 | 3 | 4 | Dual-Row Build · Two-Level Select | `final` |
| final configuration (200 MHz) | 3 | 3 | 4 | Dual-Row Build · Two-Level Select | `final_200mhz` |
| No-Checkpoint Baseline | 0 | - | 4 | Single-Row Build · Linear Select | `no_checkpoint_baseline` |

Six-Stage Ablation의 여섯째 단계는 final configuration과 같아서 따로 이름을 두지 않습니다. directory는 모두
`hardware_bram/configurations/<폴더>/`입니다.

### Measurement Microarchitecture

결과(뽑히는 index)는 같고 circuit과 cycle만 다른 Measurement Unit implementation을 Build 와 Select 두 축으로 부릅니다
([10장](10_measurement_unit_and_microarchitecture.md)).

| 축 | 값 | 뜻 |
|---|---|---|
| Build | Single-Row Build · Dual-Row Build · Triple-Row Build · Quad-Row Build | 한 cycle에 row weight를 만드는 row 수 1 · 2 · 3 · 4 |
| Select | Linear Select | 512 rows의 prefix sum을 차례로 봄 |
| Select | Two-Level Select | 16 groups의 group prefix sum을 먼저 보고 그 group의 32 rows만 봄 |

### policy search mode

| 값 | 이름 | 뜻 |
|:-:|---|---|
| 0 | Exhaustive DFS | 모든 action을 DFS로 search |
| 4 | Two-Request Bound Pruning | 다음 두 request의 relaxed lower bound로 pruning |
| 5 | Seed-First Branch and Bound | 모든 child의 lower bound를 먼저 보고 가장 작은 child를 정확히 푼 뒤 나머지를 pruning |
| 6 | Seed-First Branch and Bound with Single-Action Exit | 5에 더해, legal action이 하나면 하위 search 없이 결정 |

### 설계 이름

| 이름 | 뜻 |
|---|---|
| accelerator | Bus Interface와 Accelerator Core를 합친, RVX SoC 안의 IP 전체 |
| Accelerator Core | Grover · BBHT 계산을 하는 block |
| Bus Interface | APB CSR · AHB DMA · adapter 묶음. UART host protocol과 다른 것 ([7장](07_bus_interface.md)) |
| Iteration Datapath | Grover iteration을 계산하는 경로. PE 여러 개로 이루어짐 ([9장](09_iteration_datapath_and_number_of_pes.md)) |
| PE | Iteration Datapath 안에서 한 cycle에 row 하나를 처리하는 circuit 한 벌 |
| Measurement Unit | Born-rule sampling으로 index 하나를 뽑는 block. Build · Select · Reread 세 단계 ([10장](10_measurement_unit_and_microarchitecture.md)) |
| Measurement PRNG | Measurement Unit의 random number 발생기. xorshift64 |
| Iteration-Count LFSR | shot마다 number of iterations를 뽑는 LFSR |
| Iteration-Count Predictor | Iteration-Count LFSR의 복사본으로 앞으로 올 number of iterations를 미리 계산하는 장치 |
| Policy Engine | 어떤 checkpoint를 남길지 DP로 정하는 block ([11장](11_checkpoint_and_policy_engine.md)) |
| Policy Scheduler | 200T 실험에서 Policy Engine의 search를 나눠 돌리는 scheduler |
| Plan Queue | 예측한 계획을 담아 두었다가 shot이 실패하면 꺼내 쓰고, 예측이 틀리면 비우는 queue. hit · miss를 셉니다 |
| Checkpoint Planner · Checkpoint Executor · Segment Router | 계획을 checkpoint slot 배치로 바꾸고, segment 경계 sequence로 풀고, segment를 나누는 세 module |
| Shot Controller | shot 하나의 진행을 맡는 FSM |
| Result FIFO | enumeration 결과를 software가 CSR `FIFO_DATA`로 차례로 꺼내 가는 buffer |
| Found Mask | enumeration에서 이미 찾은 index를 표시하는 bit vector |
| Predicate Unit | data가 predicate를 만족하는지 판정하는 circuit. oracle과 solution check가 같이 씀 |
| DMA Engine | System SRAM의 dataset을 AHB로 읽어 오는 block |
| Restart mode | 매 shot을 uniform superposition에서 다시 시작하는 execution mode |
| Checkpoint mode | checkpoint를 쓰는 execution mode |
| Manual mode | firmware가 number of iterations를 직접 정하는 execution mode |
| Single-Slot Checkpoint | amplitude memory 자체를 checkpoint 하나로 쓰던 옛 구조. 지금은 CSR bit `burst_enable` 이름에만 남음 |
| Two-Track Execution | PE를 두 벌로 나눠 두 shot을 같이 돌리려던 시도. 채택하지 않음 ([실험 10](../reports/10_two_track_execution_and_pass2_build_fusion.md)) |
| Pass 2–Build Fusion | Pass 2와 Measurement Unit의 Build를 합치려던 시도. 채택하지 않음 ([실험 10](../reports/10_two_track_execution_and_pass2_build_fusion.md)) |
| BRAM Variant · DRAM Variant | 실패한 shot의 amplitude를 BRAM checkpoint로 재사용하는 variant와 모든 number of iterations의 amplitude를 DDR3에 두는 variant |
| Init · Pass 1 · Mean · Pass 2 | Grover iteration 한 번의 단계. RTL state 이름 `S_PASS1` 등은 식별자 |
| Build · Select · Reread | Measurement Unit의 세 단계 |
| Scan | Policy Engine이 후보를 훑는 단계 |
| Six-Stage Ablation | Stage 1부터 final configuration까지 하나씩 더하며 RTL cycle을 잰 ablation study ([실험 18](../reports/18_six_stage_ablation_comparison.md)) |
| Board-Verified Build | board에서 검증한 2026-09-07 final configuration build. 성능 인용의 기준 |
| Common500 · Predicate500 | 500 workloads로 software backend와 board를 맞댄 실험 · 그것을 네 predicate에 각각 건 2,000 workloads ([18장](18_predicate500_automated_test.md)) |

### 그 밖의 용어

| 용어 | 뜻 |
|---|---|
| BBHT | Boyer–Brassard–Høyer–Tapp. number of solutions를 모를 때의 Grover search ([3장](03_grover_and_bbht_algorithm.md)) |
| shot | BBHT의 한 번의 시도. number of iterations를 뽑아 돌리고, measurement 하고, solution check를 하는 한 덩어리 |
| shot cap | 한 run에서 허용하는 shot 수의 상한 (`TRIAL_LIMIT`) |
| BBHT trajectory | shot마다 뽑힌 number of iterations의 순서. RTL · board · reference model이 같아야 함 |
| solution check | measurement로 뽑은 index의 data를 predicate로 다시 검사하는 단계 |
| oracle | predicate를 만족하는 index의 amplitude sign을 뒤집는 단계. solution index를 모름 |
| diffusion operator | inversion about the mean |
| Born-rule sampling | amplitude square에 비례하는 probability로 index를 뽑는 것 |
| prefix sum | row weight를 앞에서부터 더한 값. normalization하지 않으므로 CDF가 아님 |
| predicate | `LT` `GT` `EQ` `RANGE` 네 조건. 전부 strict |
| padding | `DATA_COUNT` 이후 index. 값과 무관하게 항상 non-solution |
| row group | 4 PEs가 한 번에 처리하는 4 rows |
| memo table | Policy Engine DP의 부분 결과 저장소. Board-Verified Build는 3,279 entries, 최신 main은 381 entries |
| hit · miss | Plan Queue의 예측이 맞은 경우 · 틀린 경우 |
| paired comparison | 같은 seed로 Restart mode와 Checkpoint mode를 돌려 BBHT trajectory가 같고 executed iterations만 다른지 보는 verification |
| reference model | RTL과 비교하는 software model. cycle은 흉내 내지 않음 ([4장](04_software_reference_model_and_test_vectors.md)) |
| test vector | reference model이 낸 입력과 expected result 묶음 |
| expected result | Predicate500에서 reference model이 낸, 맞아야 하는 결과 |
| testbench · bench250 · bench500 | driver로 workload를 연달아 돌리는 Verilator BBHT trajectory testbench |
| benchmark | 성능 측정. quantum measurement와 구별 |
| evidence bundle | 실험 보고서가 링크하는 원자료 묶음(`evidence.md`) |
| configuration | 위 네 값으로 정한 하드웨어 구성 하나. software · 비용 · 사이클을 흉내 내는 것은 model |
| revision | 같은 configuration의 다른 RTL · board version |
| source of truth | 수치 · 규격의 원본 문서나 파일 |
| RVX | 이 project가 쓰는 SoC platform 생성 환경 (`/opt/rvx`) |
| ORCA | RVX의 RV32 core. 순수 software baseline의 주체 |
| user region | RVX SoC 안에 accelerator가 들어가는 자리 |
| W1P | 쓰면 1 cycle pulse만 나가는 CSR 성격 |
| RPOP | 읽기 완료가 곧 pop인 CSR 성격. `FIFO_DATA` 하나뿐 |
| OOC | Out-Of-Context synthesis. module 하나만 떼어 재는 방식 |
| WNS | Worst Negative Slack. timing 여유 |

### 옛 표기

이전 문서 · benchmark 기록 · tag · directory 이름 · code identifier에 남은 표기를 읽는 표입니다. 새 글에는 쓰지 않습니다.

| 옛 표기 | 지금 용어 |
|---|---|
| K · H · E | Checkpoint-Capacity · Lookahead-Shots · number of PEs (`K3` = a Checkpoint-Capacity of 3, `H3` = 3-shot Lookahead, `E4` = 4 PEs) |
| M0 · M1 · M2 · M3 (구성) | Single-Row Build · Linear Select / Dual-Row Build · Linear Select / Dual-Row Build · Two-Level Select / Triple-Row Build · Two-Level Select |
| M (workload) · Q · P · F · W | number of solutions · number of qubits · number of lanes · fraction bits · data word width 또는 total weight |
| n · N · j · m · λ | number of qubits · number of states · number of iterations · sampling range · growth factor |
| S (policy) · S1~S3 (실험 20) · W · T (실험 17) | policy search mode · pipeline stage 1~3 · worker · thread |
| Normal-E1 · K4/H4-E1 · K4/H4-E4 · K3/H3-E4 · K3/H3-E4-M1 · K3/H3-E4-M2 | Stage 1 · Stage 2 · Stage 3 · Stage 4 · Stage 5 · final configuration |
| Normal-E4 · `nocheckpoint` | No-Checkpoint Baseline |
| Normal · NORMAL · CKPT · MANUAL (옛 CSR 모드 이름 `NORMAL_SINGLE` 등) | Restart mode · Checkpoint mode · Manual mode |
| Main IP · 통신 계층 · 연산 경로 · 측정 경로 · 정책 엔진 | Accelerator Core · Bus Interface · Iteration Datapath · Measurement Unit · Policy Engine |
| 연산기 · engine | PE |
| J-LFSR · Shadow-J · plan FIFO · 측정 LFSR · AHB 적재기 · 판정기 · 샷 FSM | Iteration-Count LFSR · Iteration-Count Predictor · Plan Queue · Measurement PRNG · DMA Engine · Predicate Unit · Shot Controller |
| Burst (옛 구조) · 다중 엔진 · PASS2 융합 | Single-Slot Checkpoint · Two-Track Execution · Pass 2–Build Fusion |
| trial · attempt · 시도 · L_BBHT · 물리 반복 | shot · requested iterations · executed iterations |
| 골든 모델 · 기준모델 · 정답 벡터 · 실측 · 정본 | reference model · test vector · benchmark · Board-Verified Build 또는 source of truth |
| 갈래 · 판 · 모델(하드웨어 구성) · quad | variant · revision · configuration · row group |

### 옛 code 이름

2026-10-28에 바꾼 code identifier · directory · platform 이름입니다. 이전 commit · tag · 기록 안에서는 왼쪽 이름이 쓰입니다.
`hardware_bram/firmware/bbht_paper_bench/`와 `software/orca_grover_develop/apps/*/src/`는 board에서 잰 binary와 sha256이 같아야 해서
옛 이름 그대로입니다.

| 옛 이름 | 지금 이름 |
|---|---|
| `CKPT_K` · `POLICY_H_FUTURE` · `H_FUTURE` · `INTRA_ENGINES` | `CHECKPOINT_CAPACITY` · `LOOKAHEAD_SHOTS` · `NUMBER_OF_PES` |
| `MEAS_M1_ENABLE` · `MEAS_M3_ENABLE` · `MEAS_BUILD_ROWS` | `BUILD_ROWS_PER_CYCLE` 하나 (1 Single-Row ~ 4 Quad-Row Build. 옛 M1 = 2, M3 = 3) |
| `MEAS_M2_ENABLE` · `POLICY_EXACT_PRUNE` | `USE_TWO_LEVEL_SELECT` · `POLICY_SEARCH_MODE` |
| `CKPT_MANUAL_ENABLE` · `AUTO_SPEC_ENABLE` | `CHECKPOINT_MANUAL_ENABLE` · `SPECULATIVE_PLANNING_ENABLE` |
| CSR 모드 `NORMAL_SINGLE` · `NORMAL_ENUM` · `CKPT_SINGLE` · `CKPT_ENUM` | `RESTART_SINGLE` · `RESTART_ENUMERATION` · `CHECKPOINT_SINGLE` · `CHECKPOINT_ENUMERATION` |
| CSR `TRIAL_COUNT` · `L_BBHT` · `ACTUAL_ITER` | `SHOT_COUNT` · `REQUESTED_ITERATIONS` · `EXECUTED_ITERATIONS` |
| CSR `PLAN_FIFO_*` · `PLAN_FIFO_MISMATCH_COUNT` | `PLAN_QUEUE_*` · `PLAN_QUEUE_MISS_COUNT` |
| port · 신호 `trial_count` · `L_BBHT` · `actual_grover_iterations` · `plan_fifo_*` · `plan_fifo_mismatch_count` | `shot_count` · `requested_iterations` · `executed_iterations` · `plan_queue_*` · `plan_queue_miss_count` |
| module `grover_ckpt_plan_fifo` | `grover_ckpt_plan_queue` |
| `hardware_bram/models/hardware_bram_<model>/` | `hardware_bram/configurations/<configuration>/` (위 「구성」 표의 directory 열) |
| RVX platform `bbht_grover_upgrade` · `bbht_grover_200mhz` · `bbht_grover_nocheckpoint` · `bbht_grover_<model>` | `bbht_grover_final` · `bbht_grover_final_200mhz` · `bbht_grover_no_checkpoint_baseline` · `bbht_grover_<configuration>` |
| `software/golden_develop/` · `software/golden_data/` | `software/reference_model_develop/` · `software/reference_model_data/` |
| make 변수 `MODEL` · target `ports-models` · `lint-models` | `CONFIGURATION` · `ports-configurations` · `lint-configurations` |
| tag `board-k3h3-e4-m2` | 같은 commit에 `board-verified-build-2026-09-07` |

기록 파일의 열 이름(`trial_count` · `L_BBHT` · `actual_iter` 등)과 console 출력(`STAT trials= l_bbht= actual_iter=`)은 옛 기록과
맞대야 하므로 바꾸지 않았습니다. Vivado project directory(`vivado/vivado_bbht_grover_<옛 이름>/`)도 기록 묶음이라 그대로입니다.
