# 실험 보고서 index

> [기술문서 index](../design_references/index.md) · [실험 01 reference models campaign: 기능 정합성 →](01_reference_model_campaign.md)

---

설계를 확정하기 위해 돌린 실험을 한 편에 하나씩 모은 곳입니다. file 이름은 `<번호>_<실험명>.md`이고 번호는 01부터 매깁니다. 이 index에는 번호를 붙이지 않습니다.

`documents/`의 세 directory는 이렇게 나뉩니다. 같은 내용은 한 곳에만 적고 다른 곳은 링크합니다.

| directory | 무엇 | 예 |
|---|---|---|
| [`study_references/`](../study_references/index.md) | 공부용 해설서 | qubit · Grover algorithm · fixed-point |
| [`design_references/`](../design_references/index.md) | 확정된 설계와 그 source of truth 수치 | RTL 구조 · port · CSR · 운용 절차 · 성능 세 축 |
| `reports/` (이 directory) | 설계를 정하거나 확인하려고 돌린 실험 | precision 분석 · policy 선정 · board benchmark · baseline 비교 |

실험마다 원자료는 각 directory tree의 `results/` · `vivado/` · `bitstream/`에 있는 evidence bundle(`evidence.md`)이고, 실험
보고서는 그 묶음을 링크합니다. 설계 문서가 "왜 이렇게 정했나"를 말할 때는 해당 실험으로 링크합니다.

---

## results 탐색

2026-10-29에 `hardware_bram/results/`를 두 번 정리했습니다. 첫 정리에서 중간 개발 묶음 28개를
`archive/` 아래로 옮겨 최상위를 59개에서 31개로 줄였고, 두 번째 정리에서 실험 21~33의 evidence 묶음,
200T implementation pipeline 기록, 문서가 인용하지 않는 중간 묶음까지 20개를 더 옮겨 12개로 줄였습니다. 최상위에는 2026-09 benchmark,
실험 18의 Six-Stage Ablation, 실험 34~37의 Parameterized RTL 묶음만 남습니다. 전체 경로는
[catalog.json](../../hardware_bram/results/catalog.json), 이동 전후 경로와 파일 보존 확인은
[첫 정리 기록](../../hardware_bram/results/archive/2026-10-29_organization/evidence.md)과
[두 번째 정리 기록](../../hardware_bram/results/archive/2026-10-29_organization_round2/evidence.md)에 있습니다.

| 찾을 결과 | 입구 |
|---|---|
| iteration / measurement engine 확장 verification | [실험 37 evidence](../../hardware_bram/results/2026-10-29_generalized_e20_m11/evidence.md) |
| 최신 full Common500 · policy heatmap | [실험 36 evidence](../../hardware_bram/results/2026-10-29_generalized_common500/evidence.md) |
| Main IP integration · 경계와 복구 verification | [실험 35 evidence](../../hardware_bram/results/2026-10-28_generalized_main_integration/evidence.md) |
| 독립 parameterized RTL block verification | [실험 34 evidence](../../hardware_bram/results/2026-10-28_parameterized_rtl/evidence.md) |
| 직전 production policy optimization | [실험 31 evidence](../../hardware_bram/results/archive/policy_optimization/2026-10-28_policy_scan_parallel_verified/evidence.md) |
| 기존 200T implementation pipeline 기록 | [timing evidence](../../hardware_bram/results/archive/implementation_pipeline/2026-10-28_policy_rank_timing/evidence.md) |

`archive/`의 `design_space/`, `policy_search/`, `policy_optimization/`, `policy_unpipeline/`,
`parameterized_blocks/`, `implementation_pipeline/`은 중간 개발 결과를 주제별로 묶습니다. 묶음의 날짜·이름과 원자료는
유지합니다. 과거 log·CSV·JSON 안의 실행 경로는 당시 기록이므로 수정하지 않았습니다.
독립 block unit test의 새 출력은 `/tmp/`에 생성하여 과거 evidence를 덮어쓰지 않습니다.
이번 정리에서 background implementation의 상태는 조회하지 않았습니다.

---

## 실험 목록

### 설계 근거 실험 (01~11)

확정 설계의 결정마다 그것을 낳은 실험입니다. 출처는 2026-08 reference model campaign 보고서, Accelerator Core 담당(PJK)의
최종 집약 설계 문서 v1.0.4(2026-09-09), 2026-09-06 우리 쪽 Two-Track Execution · Pass 2–Build Fusion benchmark이고, 원본은 저장소에 두지
않았습니다.

| 번호 | 실험 | 정한 것 |
|:-:|---|---|
| 01 | [reference model campaign: 기능 정합성](01_reference_model_campaign.md) | padding gate, predicate comparator 하나, paired comparison 불변식으로 verification |
| 02 | [amplitude precision: 14 qubits와 22 fraction bits](02_amplitude_precision.md) | 14 qubits · 22 fraction bits · symmetric saturation |
| 03 | [random number seed coverage](03_random_seed_coverage.md) | regression용 seed와 통계용 seed를 분리 |
| 04 | [enumeration 두 방식 비교](04_enumeration_method_comparison.md) | enumeration은 Found Mask 방식, Accelerator Core 안 |
| 05 | [checkpoint policy algorithm 선정](05_checkpoint_policy_selection.md) | checkpoint 도입, Rolling Lookahead Exact DP policy, 동점 규칙 |
| 06 | [checkpoint memory packing](06_checkpoint_memory_packing.md) | checkpoint slot당 RAMB36 11개 packing, future-only memo table |
| 07 | [Lookahead-Shots를 줄인 이유: 8 → 6 → 4 → 3 shots](07_lookahead_shots_reduction.md) | Lookahead를 8 → 4 → 3 shots로 줄임, a Checkpoint-Capacity of 3 |
| 08 | [1 PE profiling과 4 PEs](08_one_pe_profiling_and_four_pes.md) | Grover iteration 안에서 4 rows를 병렬로 처리(4 PEs) |
| 09 | [measurement 병목과 Dual-Row Build · Two-Level Select](09_measurement_bottleneck_and_microarchitecture.md) | Measurement Unit Dual-Row Build · Two-Level Select |
| 10 | [Two-Track Execution과 Pass 2–Build Fusion: 채택하지 않은 두 시도](10_two_track_execution_and_pass2_build_fusion.md) | request 열 분할 Two-Track Execution과 Pass 2–Build Fusion을 채택하지 않음 |
| 11 | [채택하지 않은 확장과 variant](11_rejected_extensions.md) | 15 qubits · 16 qubits · 64 lanes 확장과 그 밖의 variant를 채택하지 않음 |

### benchmark · 비교 실험 (12~37)

확정 설계를 실물 board와 baseline에 맞대 확인한 실험입니다. 시간순입니다.

| 번호 | 실험 | 날짜 | 확인한 것 |
|:-:|---|---|---|
| 12 | [Board-Verified Build 500 workloads](12_board_verified_build_500_runs.md) | 2026-09-08 | 성능 세 축의 Board-Verified Build 묶음 |
| 13 | [Accelerator Core 최종 발표 (v1.3)](13_accelerator_core_final_presentation.md) | 2026-09-10 | Accelerator Core 담당의 최종 발표: implementation 범위, Six-Stage Ablation, Measurement Unit anchor, standalone resource, 재현 package |
| 14 | [Common500 software · FPGA 비교](14_common500_software_fpga_comparison.md) | 2026-09-11 | reference model · NumPy · Qiskit과 board 세 구성의 Common500 정합성 |
| 15 | [Bus Interface revision board console](15_revised_bus_interface_board_console.md) | 2026-09-17 | Bus Interface revision이 실물에서 SoC simulation과 같은 결과를 내는가 |
| 16 | [세 revision의 board Predicate500](16_three_revisions_board_predicate500.md) | 2026-10-04 | 세 revision이 실물에서 reference model과 같은가, revision 사이 speedup |
| 17 | [C++ · NumPy · Qiskit baseline 비교](17_cpp_numpy_qiskit_baselines.md) | 2026-10-05 | 최적화한 CPU software 대비 FPGA의 위치 |
| 18 | [Six-Stage Ablation configuration과 implementation 방식별 비교](18_six_stage_ablation_comparison.md) | 2026-10-06~08 | 여섯 단계 각각의 몫 (200T board) |
| 19 | [ORCA · server software baseline과 FPGA 비교](19_orca_server_software_baseline.md) | 2026-10-11 | 같은 C code를 ORCA와 server core 하나에서 돌린 baseline |
| 20 | [final configuration을 200 MHz로](20_200mhz_implementation.md) | 2026-10-12 | final configuration을 accelerator clock 200 MHz로 구현하고 200T board에서 잰 값 |
| 21 | [a Checkpoint-Capacity of 3 and 3-shot Lookahead policy memo table 압축](21_policy_memo_table_compaction.md) | 2026-10-26 | 도달 가능한 state만 저장해 memo table initialization을 3,279→381 clocks로 단축 |
| 22 | [Checkpoint-Capacity · Lookahead-Shots policy design space와 결정 latency](22_checkpoint_capacity_lookahead_shots_design_space.md) | 2026-10-26 | Checkpoint-Capacity 1~5 · Lookahead-Shots 1~8의 executed iterations 감소율과 Checkpoint-Capacity 3~4 · Lookahead-Shots 1~8의 실제 policy 결정 clock을 따로 benchmark |
| 23 | [방법 1: policy 불변 exact search 가속](23_policy_search_method_1.md) | 2026-10-26 | memoized DFS의 exact lower-bound pruning과 RTL on/off 결과 |
| 24 | [full-bound seed-first 40 cells 예측](24_seed_first_branch_and_bound_40_cell_prediction.md) | 2026-10-26 | Checkpoint-Capacity 1~5 · Lookahead-Shots 1~8의 exact search와 policy · system cycle 예측 |
| 25 | [Triple-Row Build와 a Checkpoint-Capacity of 5의 resource · 총 cycle 사전 검토](25_triple_row_build_capacity_5_resource_review.md) | 2026-10-26 | Triple-Row Build의 속도 · resource와 a Checkpoint-Capacity of 5에서 4 PEs의 BRAM bandwidth 한계 |
| 26 | [seed-first policy search RTL](26_policy_seed_first_rtl.md) | 2026-10-27 | exact policy의 search 가속과 Dual-Row Build · Triple-Row Build 구성별 Checkpoint-Capacity · Lookahead-Shots 비교, 100T implementation |
| 27 | [200T 기준 parameter 실험 자동화](27_200t_parameter_automation.md) | 2026-10-27 | Policy Scheduler 구상, 7 · 8-shot Lookahead 전달 수정, Quad-Row Build와 설정 기반 RTL · OOC · heatmap |
| 28 | [policy 단일 후보의 lower bound 대기 제거](28_policy_single_action_exit.md) | 2026-10-28 | Seed-First Branch and Bound with Single-Action Exit의 조기 반환, exhaustive search 비교와 Common500 RTL cycle verification |
| 29 | [policy segment별 병렬 lower bound](29_policy_per_segment_parallel_lower_bound.md) | 2026-10-28 | seed 재발행 생략, Lookahead-Shots와 무관한 lower bound 응답 latency, exhaustive search · Common500 RTL verification |
| 30 | [policy 후보 병렬 검사와 실행 시작 단축](30_policy_parallel_action_check_and_faster_start.md) | 2026-10-28 | Build 조기 반환, Scan cache와 4-lane bound 검사, Policy Scheduler 준비 단계 단축 |
| 31 | [policy 최적성 조기 종료와 병렬 Scan](31_policy_optimality_early_exit_and_parallel_scan.md) | 2026-10-28 | seed 최적성 증명, suffix 직접 계산, 4개 Scan과 cache 선행 읽기 |
| 32 | [a Checkpoint-Capacity of 3 and 3-shot Lookahead 전체 실행 성능 재확인](32_capacity_3_lookahead_3_performance_recheck.md) | 2026-10-28 | Common500 재실행, policy 계산량과 실제 stall·전체 실행 이득 비교 |
| 33 | [최신 policy Two-Level Select 구성의 200T·board pipeline](33_latest_policy_two_level_select_200t_board_pipeline.md) | 2026-10-28 | 기존 Dual-Row Build · Two-Level Select 구성에 최신 policy search mode(Seed-First Branch and Bound with Single-Action Exit) 연결, 단일 구성의 simulation·implementation·board verification 제출 |
| 34 | [Parameterized RTL 개발](34_parameterized_rtl_development.md) | 2026-10-28 | 단일 설정의 parameter 폭 policy와 독립 memory/iteration/square 블록 검증; 후속 Main IP 통합은 실험 35 |
| 35 | [Parameterized Main IP integration](35_parameterized_main_ip_scheduler_integration.md) | 2026-10-29 | Scheduler · Planner · Executor와 실제 연산 경로 연결, 선택 조합 · checkpoint/FIFO 경계 · warm restart · flush 복구 검증 |
| 36 | [Generalized Common500과 policy heatmap](36_generalized_common500_and_policy_heatmaps.md) | 2026-10-29 | generic solver 단축, 동일 입력 old/new RTL 검증, 고정 병렬도 full Common500 parameter campaign |
| 37 | [Iteration / measurement engine 범위 확장](37_expanded_iteration_and_measurement_engines.md) | 2026-10-29 | 가변 BUILD, 임의 정수 engine 수, 최대 parameter의 Main IP 검증과 후속 memory · resource 선정 순서 |

---

## board benchmark 묶음

board에서 잰 묶음과 각각을 성능 인용에 쓰는 범위입니다.

| 날짜 | 무엇 | 성능 인용 | 실험 |
|---|---|:-:|:-:|
| 2026-09-08 | 500 workloads 세 구성 (Restart mode · a Checkpoint-Capacity of 4 and 4-shot Lookahead · final configuration) + ORCA baseline | source of truth | [12](12_board_verified_build_500_runs.md) |
| 2026-09-17 | Bus Interface revision bitstream의 console 명령 왕복 | 아니오 | [15](15_revised_bus_interface_board_console.md) |
| 2026-10-04 | 세 revision(final configuration · No-Checkpoint Baseline · DRAM Variant)의 Predicate500, 8,000 runs | revision 사이 비교만 | [16](16_three_revisions_board_predicate500.md) |
| 2026-10-08 | 원격 200T board에서 Six-Stage Ablation 여섯 build의 EQ 500 (6,000 runs)과 네 predicate Predicate500 (24,000 runs) | revision 사이 비교만 | [18](18_six_stage_ablation_comparison.md) |
| 2026-10-11 | 원격 200T board의 ORCA에서 새 software baseline 세 model의 Predicate500 (server 실행과 함께) | software 대비만 | [19](19_orca_server_software_baseline.md) |
| 2026-10-12~13 | 원격 200T board에서 200 MHz revision의 네 predicate Predicate500 (4,000 runs)과 EQ 500 workloads (1,000 runs) | revision 사이 비교만 | [20](20_200mhz_implementation.md) |

성능 세 축은 전부 2026-09-08 묶음에서 나오고, 값은
[1장 1.5절](../design_references/01_project_overview.md#15-성능-지표와-인용-기준) 한 곳에 있습니다. 2026-09-17은
"Bus Interface revision이 실물에서 도는가"를 본 것이고 workload가 하나뿐입니다. 2026-10-04는 네 predicate로 넓힌 workload에서 세
revision을 같은 board에 차례로 구워 맞댄 것입니다. 같은 board 위의 revision 사이 speedup은 거기서 인용하지만, 기준 구성이
다르므로 2026-09-08의 세 축과 섞지 않습니다. 2026-10-08은 원격 200T board(AX7A200B)에 100T resource budget으로 구현한
여섯 build를 같은 app으로 잰 것이고, implementation 방식별 비교의 인용처입니다.

---

## benchmark 값을 읽을 때 주의

- **실험마다 축이 다릅니다.** Python reference model 실행 · RTL simulation cycle · board benchmark를 보고서마다 밝혀 두었고,
  축이 다른 수치를 섞어 speedup을 만들지 않습니다.
- **설계 근거 실험(01~11)의 수치는 결정의 근거이지 현재 성능이 아닙니다.** 많은 실험이 a Checkpoint-Capacity of 4 and 8-shot Lookahead · a Checkpoint-Capacity of 4 and 4-shot Lookahead 같은 중간
  단계나 checkpoint slot 하나짜리 옛 구조(Single-Slot Checkpoint) 위에서 돌았습니다. 현재 성능은
  [1장 1.5절](../design_references/01_project_overview.md#15-성능-지표와-인용-기준)에서 인용합니다.
- **console의 `us=`는 wall-clock time이 아닙니다.** firmware가 `bbht_cycles_to_us(cycle_count)`로 cycle에서 환산한
  값(100 MHz 기준)이라 simulation에서도 같은 값이 나옵니다. 2026-09-17 묶음은 wall-clock time의 근거로 쓰지 않습니다.
  wall-clock time은 2026-09-25 revision의 console app부터 나오는 `wall_us`(board 실시간 clock 1 MHz, board 500 runs Board-Verified Build와 같은 benchmark 경계)입니다.
- **checkpoint cycle은 board 500 runs 표와 직접 비교할 수 없습니다.** console의 Checkpoint mode 두 줄은 cycle이 서로
  다른데(20,935 대 17,847) 두 값 모두 simulation과 같습니다. reset 뒤 첫 search만 memo table 청소를 치르기 때문입니다
  ([11장 11.5절](../design_references/11_checkpoint_and_policy_engine.md#115-memo-table-initialization-3279--381-cycles)). 논리 네 축은 같아야 하고,
  cycle은 직전에 무엇을 돌렸는지와 함께 보아야 합니다.
