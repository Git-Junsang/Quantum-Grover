# 논문 목차 (IEEE 양식)

IEEE Transactions / Conference 양식(IEEEtran)에 맞춘 논문 뼈대입니다. 대단원은 로마 숫자와
대문자 제목, 소단원은 `A.` `B.`, 그 아래는 `1)` `2)` 로 매깁니다. Abstract · Index Terms ·
Acknowledgment · References · Appendix 는 번호를 붙이지 않습니다.

각 절 옆의 "근거" 는 그 절을 쓸 때 끌어올 기술문서 장과 실측 묶음입니다. 성능 수치는 세 축
(RTL 사이클 · 보드 실경과 시간 · 소프트웨어 대비)을 섞지 않고, 축마다 정본 묶음에서만 인용합니다
([1장 1.5절](../design_references/01_프로젝트_개요.md#15-성능-지표와-인용-기준)).

---

## Title

**A Checkpointed Multi-Target Grover Search Emulator with BBHT Scheduling on an Artix-7 RISC-V SoC**

(가제. 저자 · 소속: 중앙대학교 학부인턴 LPSoC BBHT/Grover 팀)

## Abstract

150~250 단어 한 문단. 문제(정답 수를 모르는 다중 타겟 탐색의 FPGA 에뮬레이션) → 방법(BBHT +
체크포인트 K3 · 정책 지평 H3 · 연산기 E4 · 측정 최적화 M2) → 플랫폼(Arty A7-100T, RVX SoC,
Q = 14) → 결과(RTL 사이클 6.1401x, 보드 실경과 7.626x, ORCA 1코어 대비 116,426x — 축 표기 필수)
→ 검증(소프트웨어 기준모델과 궤적 500/500).

## Index Terms

Grover's algorithm, BBHT, quantum computing emulation, FPGA, fixed-point arithmetic,
checkpointing, RISC-V SoC, hardware accelerator

---

## I. INTRODUCTION

- A. Motivation — 양자 알고리즘 검증용 하드웨어 에뮬레이터의 필요
- B. Problem Statement — 정답 수 M 을 모를 때의 반복 횟수 문제와 실패 시 진폭 재계산 비용
- C. Contributions — 기여 항목 4~5개 (체크포인트 · 정책 엔진, E4, M1/M2, 비트 단위 기준모델, 보드 실측)
- D. Paper Organization

근거: [1장](../design_references/01_프로젝트_개요.md)

## II. BACKGROUND

- A. Grover's Algorithm
  - 1) Oracle and Diffusion Operators
  - 2) Born-Rule Measurement
- B. BBHT Algorithm for Unknown Number of Solutions
- C. Predicate Oracles: `LT` `GT` `EQ` `RANGE`
- D. Multi-Target Enumeration and Found-Mask

근거: [3장](../design_references/03_Grover와_BBHT_알고리즘.md),
[해설서](../study_references/00_양자컴퓨팅_시작하기.md)

## III. RELATED WORK

- A. FPGA-Based Quantum Circuit Emulators
- B. Grover Emulators on FPGA
- C. Software State-Vector Simulators (Qiskit Aer, NumPy)
- D. Fixed-Point Precision in Quantum Emulation
- E. Checkpointing and Recomputation Strategies

근거: [`bbht_related_work.md`](../papers/bbht_related_work.md),
[`references.md`](../papers/references.md)

## IV. SYSTEM ARCHITECTURE

- A. System Overview — 호스트 PC · UART · RVX SoC · Main IP
- B. Data Representation
  - 1) Signed 16-bit Input Words
  - 2) Q1.22 Amplitude Format
  - 3) P = 32 Lane Mapping and BRAM Layout
- C. Host and Communication Layer
  - 1) APB CSR Interface
  - 2) AHB Data Loader
  - 3) UART Command Protocol
- D. Execution Modes

근거: [5장](../design_references/05_하드웨어_아키텍처_개요.md),
[6장](../design_references/06_데이터_표현과_메모리_맵.md),
[7장](../design_references/07_통신_계층.md),
[13장](../design_references/13_CSR_레지스터와_실행_모드.md),
[14장](../design_references/14_호스트_인터페이스와_UART_프로토콜.md)

## V. ACCELERATOR MICROARCHITECTURE

- A. BBHT Control and Shot FSM
- B. Iteration Datapath and Quad-Engine Parallelism (E4)
- C. Measurement Path Optimization (M1, M2)
- D. Amplitude Checkpointing (K3)
- E. Dynamic-Programming Policy Engine (H3)
  - 1) Shadow-J Planning
  - 2) Memo BRAM and Reset Behavior

근거: [8장](../design_references/08_Main_IP_최상위와_BBHT_제어.md),
[9장](../design_references/09_연산_경로와_E4.md),
[10장](../design_references/10_측정_경로와_M1_M2.md),
[11장](../design_references/11_체크포인트와_정책_엔진.md),
[15장](../design_references/15_동작_과정과_사이클_구성.md)

## VI. VERIFICATION METHODOLOGY

- A. Bit-Exact Software Reference Model
- B. RTL Simulation and Workload Benches
- C. SoC-Level RTL Co-Simulation
- D. Board-Level Validation

근거: [4장](../design_references/04_소프트웨어_기준모델과_정답_벡터.md),
[16장](../design_references/16_검증_체계.md),
[18장](../design_references/18_보드_확인과_실측.md),
[19장](../design_references/19_Predicate500_자동_테스트.md)

## VII. EXPERIMENTAL RESULTS

- A. Experimental Setup — 보드, 클럭, 500 워크로드(M = 1/4/16/64/256 × 시드 100)
- B. RTL Cycle Performance and Six-Stage Ablation
- C. Board Wall-Clock Performance
- D. Comparison with Software Baselines (ORCA 1-core, Qiskit Aer, NumPy)
- E. Resource Utilization and Timing
- F. Comparison with Alternative Implementations
  - 1) Non-Checkpointed BRAM Baseline (Normal-E4)
  - 2) DRAM-Backed Variant

근거:
[`2026-09-08_publication_6stage`](../../hardware_bram/results/2026-09-08_publication_6stage/) (RTL 사이클),
[`2026-09-08_k3h3_e4_m2_board_500run`](../../hardware_bram/models/hardware_bram_K3H3_E4_M2/vivado/vivado_bbht_grover_fpga/2026-09-08_k3h3_e4_m2_board_500run/) (보드 실경과),
[`2026-09-08_orca_1core_baseline`](../../hardware_bram/models/hardware_bram_K3H3_E4_M2/vivado/vivado_bbht_grover_fpga/2026-09-08_orca_1core_baseline/) (소프트웨어 대비),
[`2026-09-08_resource_ablation_5config`](../../hardware_bram/results/2026-09-08_resource_ablation_5config/) (자원),
[`common500_final`](../../software/results/common500_final/common500_validation_report.md),
[20장](../design_references/20_합성_구현_비트스트림.md),
[21장](../design_references/21_체크포인트_없는_BRAM_판.md),
[22장](../design_references/22_DRAM_갈래.md)

## VIII. DISCUSSION

- A. Design Rationale — 정밀도 · H 선택 · 채택하지 않은 시도
- B. Interpreting the Speedup — ORCA 대비 배수는 P = 32 병렬과 클럭 2배에서 오며 알고리즘 우위가 아님
- C. Limitations — Q = 14 상한, 고전 선형 스캔보다 느림, DRAM 갈래의 열거 · 프리페치 부재

근거: [23장](../design_references/23_설계_근거_실험.md)

## IX. CONCLUSION

요약과 향후 과제(두 갈래 중 최종 선택, DRAM 프리페치, 큐비트 확장).

---

## ACKNOWLEDGMENT

## REFERENCES

IEEE 번호식 `[1]` `[2]` … 인용 순서대로.
후보 목록: [`references.md`](../papers/references.md)

## APPENDIX

- A. CSR Register Map
- B. Glossary

근거: [13장](../design_references/13_CSR_레지스터와_실행_모드.md),
[24장](../design_references/24_부록_용어집과_폐기된_규격.md)
