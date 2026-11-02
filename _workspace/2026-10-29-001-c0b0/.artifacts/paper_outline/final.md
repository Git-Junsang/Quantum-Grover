# 논문 목차 (IEEE 양식)

IEEE Transactions / Conference 양식(IEEEtran)에 맞춘 논문 뼈대입니다. 대단원은 로마 숫자와
대문자 제목, 소단원은 `A.` `B.`, 그 아래는 `1)` `2)` 로 매깁니다. Abstract · Index Terms ·
Acknowledgment · References · Appendix 는 번호를 붙이지 않습니다.

각 절 옆의 "근거" 는 그 절을 쓸 때 참조할 기술문서 장과 benchmark 묶음입니다. 성능 수치는 세 축
(RTL cycle · board wall-clock time · software 대비)을 섞지 않고, 축마다 source of truth 묶음에서만 인용합니다
([1장 1.5절](../../design_references/01_project_overview.md#15-성능-지표와-인용-기준)).

---

## Title

**A Checkpointed Multi-Solution Grover Search Emulator with BBHT Scheduling on an Artix-7 RISC-V SoC**

(가제. 저자 · 소속: 중앙대학교 학부인턴 LPSoC BBHT/Grover 팀)

## Abstract

150~250 단어 한 문단. 문제(number of solutions를 모르는 multi-solution search의 FPGA emulation) → 방법(BBHT +
a Checkpoint-Capacity of 3 · 3-shot Lookahead policy · 4 PEs · Dual-Row Build와 Two-Level Select로 된 Measurement Microarchitecture) → platform(Arty A7-100T, RVX SoC,
14 qubits) → 결과(RTL cycle 6.1401×, board wall-clock time 7.626×, ORCA 1 core 대비 116,426× — 축 표기 필수)
→ verification(software reference model과 BBHT trajectory 500/500).

## Index Terms

Grover's algorithm, BBHT, quantum computing emulation, FPGA, fixed-point arithmetic,
checkpointing, RISC-V SoC, hardware accelerator

---

## I. INTRODUCTION

- A. Motivation — quantum algorithm verification용 hardware emulator의 필요
- B. Problem Statement — number of solutions를 모를 때 number of iterations를 정하는 문제와, shot 실패 시 amplitude 재계산 비용
- C. Contributions — 기여 항목 4~5개 (checkpoint · Policy Engine, 4 PEs, Dual-Row Build · Two-Level Select, bit-exact reference model, board benchmark)
- D. Paper Organization

근거: [1장](../../design_references/01_project_overview.md)

## II. BACKGROUND

- A. Grover's Algorithm
  - 1) Oracle and Diffusion Operators
  - 2) Born-Rule Sampling
- B. BBHT Algorithm for Unknown Number of Solutions
- C. Predicate Oracles: `LT` `GT` `EQ` `RANGE`
- D. Multi-Solution Enumeration and Found Mask

근거: [3장](../../design_references/03_grover_and_bbht_algorithm.md),
[해설서](../index.md)

## III. RELATED WORK

- A. FPGA-Based Quantum Circuit Emulators
- B. Grover Emulators on FPGA
- C. Software State-Vector Simulators (Qiskit Aer, NumPy)
- D. Fixed-Point Precision in Quantum Emulation
- E. Checkpointing and Recomputation Strategies

근거: [`bbht_related_work.md`](bbht_related_work.md),
[`references.md`](references.md)

## IV. SYSTEM ARCHITECTURE

- A. System Overview — host · UART · RVX SoC · Accelerator Core
- B. Data Representation
  - 1) Signed 16-Bit Input Data Words
  - 2) Q1.22 Amplitude Format
  - 3) 32-Lane Mapping and BRAM Layout
- C. Bus Interface and Host Protocol
  - 1) APB CSR Interface
  - 2) AHB DMA Engine
  - 3) UART Command Protocol
- D. Execution Modes

근거: [5장](../../design_references/05_hardware_architecture_overview.md),
[6장](../../design_references/06_data_representation_and_memory_map.md),
[7장](../../design_references/07_bus_interface.md),
[13장](../../design_references/13_csr_registers_and_execution_modes.md),
[14장](../../design_references/14_host_interface_and_uart_protocol.md)

## V. ACCELERATOR MICROARCHITECTURE

- A. BBHT Control and Shot Controller
- B. Iteration Datapath and Number of PEs
- C. Measurement Microarchitecture
- D. Amplitude Checkpointing
- E. Dynamic-Programming Policy Engine
  - 1) Iteration-Count Predictor Planning
  - 2) Memo Table and Reset Behavior

근거: [8장](../../design_references/08_accelerator_core_top_and_bbht_control.md),
[9장](../../design_references/09_iteration_datapath_and_number_of_pes.md),
[10장](../../design_references/10_measurement_unit_and_microarchitecture.md),
[11장](../../design_references/11_checkpoint_and_policy_engine.md),
[15장](../../design_references/15_operation_sequence_and_cycle_breakdown.md)

## VI. VERIFICATION METHODOLOGY

- A. Bit-Exact Software Reference Model
- B. RTL Simulation and Workload Testbenches
- C. SoC-Level RTL Co-Simulation
- D. Board-Level Validation

근거: [4장](../../design_references/04_software_reference_model_and_test_vectors.md),
[16장](../../design_references/16_verification_framework.md),
[18장](../../design_references/18_predicate500_automated_test.md),
board benchmark [실험 12](../../reports/12_board_verified_build_500_runs.md) · [실험 15](../../reports/15_revised_bus_interface_board_console.md) ·
[실험 16](../../reports/16_three_revisions_board_predicate500.md)

## VII. EXPERIMENTAL RESULTS

- A. Experimental Setup — board, clock, 500 workloads(1 · 4 · 16 · 64 · 256 solutions × 100 seeds)
- B. RTL Cycle Performance and Six-Stage Ablation
- C. Board Wall-Clock Performance
- D. Comparison with Software Baselines (ORCA 1-core, the same C on one host x86 core, Qiskit Aer, NumPy)
- E. Resource Utilization and Timing
- F. Comparison with Alternative Implementations
  - 1) No-Checkpoint Baseline
  - 2) DRAM Variant

근거:
[`2026-09-08_publication_6stage`](../../../hardware_bram/results/2026-09-08_publication_6stage/) (RTL cycle),
[`2026-09-08_k3h3_e4_m2_board_500run`](../../../hardware_bram/configurations/final/vivado/vivado_bbht_grover_fpga/2026-09-08_k3h3_e4_m2_board_500run/) (board wall-clock time),
[`2026-09-08_orca_1core_baseline`](../../../hardware_bram/configurations/final/vivado/vivado_bbht_grover_fpga/2026-09-08_orca_1core_baseline/) (software 대비),
[`2026-10-11_predicate500`](../../../software/orca_grover_result/2026-10-11_predicate500/2026-10-11_predicate500.md) (새 software baseline, ORCA board · server · FPGA, [실험 19](../../reports/19_orca_server_software_baseline.md)),
[실험 17](../../reports/17_cpp_numpy_qiskit_baselines.md) (C++ · NumPy · Qiskit baseline),
[실험 18](../../reports/18_six_stage_ablation_comparison.md) (같은 board의 Six-Stage Ablation build 비교),
[`2026-09-08_resource_ablation_5config`](../../../hardware_bram/results/2026-09-08_resource_ablation_5config/) (resource),
[`2026-09-11_common500`](../../../software/reference_model_data/2026-09-11_common500/2026-09-11_common500.md),
[19장](../../design_references/19_synthesis_implementation_bitstream.md),
[20장](../../design_references/20_no_checkpoint_baseline.md),
[21장](../../design_references/21_dram_variant.md)

## VIII. DISCUSSION

- A. Design Rationale — precision · Lookahead-Shots 선택 · 채택하지 않은 설계안
- B. Interpreting the Speedup — ORCA 대비 speedup은 32 lanes 병렬과 clock 2×에서 오며 algorithm 우위가 아님.
  같은 C 를 server x86 core 하나에서 돌리면 FPGA 와 시간이 비슷하다는 점을 함께 다룸
- C. Limitations — 14 qubits 상한, classical linear scan보다 느림, DRAM Variant의 enumeration · prefetch 부재

근거: 설계 근거 [실험 01 ~ 11](../../reports/index.md#실험-목록),
[실험 19](../../reports/19_orca_server_software_baseline.md)

## IX. CONCLUSION

요약과 향후 과제(두 variant 중 최종 선택, DRAM prefetch, qubit 확장).

---

## ACKNOWLEDGMENT

## REFERENCES

IEEE 번호식 `[1]` `[2]` … 인용 순서대로.
후보 목록: [`references.md`](references.md)

## APPENDIX

- A. CSR Register Map
- B. Glossary

근거: [13장](../../design_references/13_csr_registers_and_execution_modes.md),
[22장](../../design_references/22_appendix_glossary_and_retired_specs.md)

<!-- HUMANIZE-SUMMARY -->
<!--
{
  "원본_글자수": 6874,
  "최종_글자수": 6874,
  "경로": "light",
  "게이트_변경률": 0.0004,
  "등급": "B",
  "자체검증": "6/6 (보존 지시 대상의 교재 형식 제외)",
  "상태": "accept",
  "국소_보정_수": 0,
  "카테고리": [
    "D-14"
  ],
  "하이라이트": [
    {
      "rule": "D-14",
      "before": "그 절을 쓸 때 끌어올 기술문서 장과 benchmark 묶음입니다.",
      "after": "그 절을 쓸 때 참조할 기술문서 장과 benchmark 묶음입니다."
    }
  ],
  "잔존_finding": []
}
-->
