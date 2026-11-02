# 15장. 논문 지도와 설계 결정표

> [← 14장 multiple solutions — Born-rule sampling과 enumeration](14_multiple_solutions_and_minimum_search.md) · [index](index.md) · [16장 몇 번 돌릴지 모를 때 — BBHT shot loop와 checkpoint →](16_iteration_control_and_checkpoints.md)
> **이 장을 읽기 위한 준비**: [11장 state vector emulator](11_state_vector_emulator.md) · [12장 fixed-point와 Q1.22](12_fixed_point_and_precision.md) · [13장 oracle과 diffusion operator](13_oracle_diffusion_measurement_datapath.md) · [14장 multiple solutions](14_multiple_solutions_and_minimum_search.md).
> **성격**: 참조용(Part 7). 여섯 논문의 관계를 지도로 펼치고, **확정된 설계값을 한 표에 모읍니다.** 10장이 1~9장(quantum 이론)의 cheat sheet라면, 이 장은 hardware 쪽의 cheat sheet입니다.

---

이 장은 앞 장들에서 배운 내용을 **지도 한 장과 표 몇 개**로 압축한 참조 자료입니다. 논문을 다시 읽으러 갈 때, 설계 결정을 되짚을 때, 그리고 무엇보다 — 논문을 **인용하기 전에** 펼쳐 보세요. [15.6절](#156-인용-시-주의--논문의-오류와-모호점)이 "1차 자료도 틀린다"는 것을 실물 목록으로 보여줍니다.

이 장의 숫자는 board에서 검증된 **final configuration**(Board-Verified Build: 2026-09-07 build, 2026-09-08 benchmark)을 따릅니다. 해설서 초판은 2026-08-15 에 설계를 한 번 확정했지만, 그 뒤 RTL을 실제로 짓고 board에 올리면서 number of qubits·amplitude 형식·checkpoint 구조가 바뀌었습니다. [15.4절](#154-우리-project의-좌표--확정-설계-결정표)이 그 최종값의 해설서 안 **단일 출처(source of truth)** 이고, 해설서 어느 장에 같은 숫자가 적혀 있든 어긋나면 15.4절을 기준으로 합니다. 해설서 바깥까지 포함한 저장소 전체의 기준은 board build 그 자체이고, 이 표는 그것을 해설서의 언어로 옮긴 것입니다.

---

## 15.1 여섯 논문 한눈에

| # | 논문 | 출처 | 한 줄 | 우리와의 거리 |
|:-:|------|------|-------|---------------|
| 04 | Developing a Grover's Emulator on Standalone FPGAs | **중앙대**, AIMS Math. 2024 | Grover 전용 최적화 4종 + RISC-V SoC 통합 | **직계 설계도** |
| 05 | Precision-aware Fixed-point Emulation | **중앙대**, QIP 2026 | truncation error $O(2^{\text{number of qubits}-\text{fraction bits}})$ 증명 + minimum fraction bits 공식 | **bit width 판단의 나침반** |
| 06 | Standalone FPGA QAOA Emulator | **중앙대**, arXiv 2025 | 같은 골격을 QAOA로 (multiplier 대비) | multiplier 없는 이유 |
| 07 | Towards Complete & Scalable Emulation (HPRC) | Kansas, IEEE TC 2023 | 외부 DDR로 32 qubits, C2Q initialization | **대조군** (반대 진영) |
| 08 | Generalized Grover for Multiple Phase Inversion | PRL 2018 | diffusion operator를 multiple solutions로 일반화 | 이론 배경 (implementation X) |
| 09 | Quantum Minimum Searching for AUD in IoT | INSA Lyon, IEEE IoT J. 2024 | minimum search(DHA)를 무선 사용자 탐지에 | **확장 참고 사례** |

핵심 사실 하나: **04·05·06은 이 project 지도교수 연구실(중앙대 이우주 교수님)의 논문**입니다. 특히 04번은 우리가 만들려는 것과 정확히 같은 물건(state vector를 fixed-point memory에 두고 oracle+diffusion operator를 FSM으로 $\sqrt{\text{number of states}}$ 번 도는 emulator)이라, 참고문헌이 아니라 사실상 **설계도**에 가깝습니다.

이번 개정에서는 09번의 참조 비중을 줄였습니다. 이전 판은 09번을 14장의 원문처럼 다뤘지만, 우리 accelerator는 threshold를 계단처럼 낮추는 바깥 loop를 hardware에 넣지 않고 host firmware의 `while` 한 줄로 처리하기로 했고([14.9](14_multiple_solutions_and_minimum_search.md#149-확장--threshold를-낮추면-minimum-search)·[17.7](17_rvx_soc_integration.md#177-hardware와-firmware의-경계)), iteration schedule의 근거도 09번이 아니라 아래 15.2절의 BBHT 원전으로 옮겼습니다. 09번이 여전히 남기는 것은 **"oracle은 index가 아니라 predicate를 판정한다"** 는 관점 하나와, 그 관점을 실제 응용에 적용한 사례 하나입니다. 이 두 내용을 참고하려고 인용합니다.

---

## 15.2 계보도 — 누가 누구를 딛고 섰나

여섯 논문은 서로 인용하며 **연관된 연구 흐름**을 이룹니다.

<img src="diagrams/15_lineage.svg" width="640" alt="여섯 논문의 계보: 04를 중심으로 05·06이 위성, 07은 대조군, 08·09는 응용축">

- **04 → 06 → 05** 가 중앙대 연구실의 3부작입니다. 04번(Grover emulator)이 뿌리이고, 06번이 그 설계 철학을 QAOA라는 다른 algorithm으로 옮겼으며, 05번이 04번의 fixed-point precision 문제에 이론적 근거를 댔습니다. 04번이 중심이고 05·06은 그와 관련된 연구입니다.
- **07** 은 반대 진영(미국 Kansas 대학, HPC accelerator 계보)에서 온 **대조항**입니다. on-chip resource 대신 외부 DDR을, fixed-point 대신 floating-point를 택해 우리와 정반대의 선택을 합니다 — 그래서 12장에서 선택의 근거를 비교할 때 참고합니다.
- **08·09** 는 algorithm 축의 확장입니다. 08번은 Grover 자체의 이론적 일반화(FPGA 무관), 09번은 Grover를 통신 문제에 응용한 사례입니다.

04번의 최적화 4종 중 기법 1(imaginary part 제거)과 기법 3(matrix multiplication 분해)의 **착상 자체는 선행연구 인용**입니다(각각 Ionescu 2019, Bag 2022). 04번의 실제 기여는 이들을 통합·정리하고 SoC로 만들고 자동 생성 tool(QEX)까지 붙인 데 있습니다. 그런데 04번은 자기가 인용한 그 선행연구와 정량 비교를 하지 않습니다 — 논문을 읽을 때 감안할 점입니다.

덧붙여, 이 여섯 편에는 공통으로 참고한 선행연구가 하나 더 있습니다 — Pilch–Długopolski(2018)의 범용 FPGA quantum emulator입니다. 04·05·06·07번이 **모두** 이 논문을 인용합니다(각각 참고문헌 [18]·[48]·[11]·[41]). 여섯 편의 계보도에는 그리지 않았지만, FPGA quantum emulator라는 분야의 공통 출발점 격이라 알아 둘 값어치가 있습니다(더 읽을거리는 [15.9절](#159-여섯-논문-너머--더-읽을거리)).

이 계보 밖에도 우리 설계 결정 하나의 직접적인 근거가 되는 논문이 한 편 있습니다. **Boyer·Brassard·Høyer·Tapp(1998), _Tight bounds on quantum searching_** — solution이 몇 개인지 모르는 채로 Grover를 돌리는 표준 절차(이른바 BBHT)의 원전입니다. 우리가 쓰는 schedule, 곧 sampling range를 1에서 시작해 실패할 때마다 growth factor 6/5(1.2×)로 넓히는 방식이 전부 이 논문에서 나왔습니다. 09번 논문의 Algorithm 1·2도 이 절차를 그대로 옮겨 온 것이고 — 옮기는 과정에서 한 줄이 빠졌습니다([15.6절](#156-인용-시-주의--논문의-오류와-모호점)). 그러니 iteration schedule을 인용할 때는 09번이 아니라 1998년 원전을 인용하십시오.

---

## 15.3 여덟 개의 대립축

Part 5~8의 각 장은 사실 "설계 질문 하나"였고, 그 질문마다 논문들이 다른 답을 냈습니다. 그 대립을 한 표로 모읍니다. 굵게 표시한 것이 우리 좌표입니다.

| 축 | 질문 | 답들 | 다룬 곳 |
|:-:|------|------|:------:|
| **A** | state vector를 어디에 두는가 | register array(04·06, 6~9 qubits) ↔ **on-chip BRAM, row 32 lanes × 4 PEs(우리, 14 qubits)** ↔ 외부 DDR(07, 32 qubits) | [11.4](11_state_vector_emulator.md#114-amplitude를-어디에-둘-것인가) · [15.5](#155-확정-platform과-resource-예산) |
| **B** | 수를 어떻게 담는가 | **fixed-point(04·05·우리)** ↔ float32(07). minimum fraction bits 공식(05) | [12장](12_fixed_point_and_precision.md) |
| **C** | multiplier를 어떻게 없애는가 | **2의 거듭제곱은 shift → diffusion operator DSP 0개(04·우리)** ↔ 임의 각도 CORDIC(06) | [13.5](13_oracle_diffusion_measurement_datapath.md#135-diffusion-operator--2mean--amp가-circuit이-되는-순간) · [13.8](13_oracle_diffusion_measurement_datapath.md#138-multiplier는-어디에-있고-어디에-없는가) |
| **D** | measurement를 어떻게 하는가 | **Born-rule sampling(04의 WRNG · 우리 — 단 우리는 integer 정확 계산과 group→row→lane layer 선택)** ↔ argmax(우리가 기각) ↔ Q2C 미해결(07) | [14.3](14_multiple_solutions_and_minimum_search.md#143-amplitude-동률--argmax가-무너지는-지점) · [14.4](14_multiple_solutions_and_minimum_search.md#144-born-rule-sampling--probability를-circuit으로) |
| **E** | oracle은 무엇인가 | index를 안다(04) ↔ **predicate를 판정한다(09·우리)** | [13.3](13_oracle_diffusion_measurement_datapath.md#133-oracle--predicate-4종이-subtractor-하나를-공유한다) · [14.2](14_multiple_solutions_and_minimum_search.md#142-oracle은-solution을-아는-circuit이-아니다) |
| **F** | 실기 vs emulator 비용 | 실기에서 싼 것이 emulator에서 비싸고, 그 반대도 참 | [11.9](11_state_vector_emulator.md#119-emulator가-실기보다-쉬운-것들) · [11.10](11_state_vector_emulator.md#1110-emulator가-숨기는-것) |
| **G** | iteration을 몇 번 돌릴지 어떻게 정하는가 | number of solutions를 안다고 두고 $\text{optimal number of iterations}=\frac{\pi}{4}\sqrt{\text{number of states}/\text{number of solutions}}$(04·08·09) ↔ **BBHT로 모르는 채 시작(우리)** ↔ quantum counting(QPE, 우리가 기각) | [16.1](16_iteration_control_and_checkpoints.md#161-왜-solution이-몇-개인지-모르는가) · [16.2](16_iteration_control_and_checkpoints.md#162-bbht--무작위로-뽑는-number-of-iterations와-12-growth-factor) |
| **H** | shot 사이에 state를 버리는가 남기는가 | shot마다 버리고 Init부터(여섯 논문 전부) ↔ **state를 세 벌 남겨 두고 policy가 고른 지점에서 차이만큼만 전진(우리)** | [16.5](16_iteration_control_and_checkpoints.md#165-checkpoint--measurement가-읽기-전용이라는-사실에서) · [16.6](16_iteration_control_and_checkpoints.md#166-왜-결과가-달라지지-않는가) |

앞의 여섯 축(A~F)은 논문들끼리 갈리는 자리이고, 뒤의 둘은 성격이 다릅니다. G축은 여섯 논문이 대체로 "solution이 몇 개인지는 주어진 것"으로 놓고 지나가 버린 자리라 우리가 직접 세워야 했고, **H축은 여섯 논문 어디에도 없습니다.** shot을 여러 번 수행하는 구조 자체가 G축을 세운 뒤에야 생기고, 실기 quantum에서는 measurement가 state를 collapse시켜 애초에 물음이 성립하지 않기 때문입니다. emulator에서만 물을 수 있는 질문이고, 이 project가 내놓는 답이 [checkpoint](16_iteration_control_and_checkpoints.md#165-checkpoint--measurement가-읽기-전용이라는-사실에서)입니다. board에서 잰 가속의 가장 큰 몫도 이 축에서 나왔습니다.

---

## 15.4 우리 project의 좌표 — 확정 설계 결정표

**이 표가 해설서 안에서 이 project 숫자의 source of truth입니다.** 다른 장이 같은 값을 본문에 다시 적어 두는 것은 읽는 도중에 link를 따라가지 않아도 되게 하려는 배려일 뿐이고, 값이 어긋나면 여기가 기준입니다.

다만 순서를 오해하지 마십시오. **이 장은 뒤 세 장(16·17·18)의 결론을 미리 모은 색인이며, 왜 그렇게 정했는지의 근거는 그쪽에 있습니다.** 표의 각 줄에 있는 "상세" 열이 그 근거를 가리킵니다. 표만 읽고 이유까지 안다고 생각하면, 나중에 설계를 바꿔야 할 때 무엇을 다시 계산해야 하는지 알 수 없게 됩니다.

| 결정 | 우리 선택 | 따른 논문 | 버린 것 | 근거 | 상세 |
|------|-----------|:---------:|---------|------|:----:|
| amplitude 표현 | **실수 전용** | 04 | imaginary part array | 초기 uniform superposition이 실수 + oracle이 $\pm1$ + diffusion operator가 실수 선형 → amplitude가 실수를 벗어나지 않음. memory가 절반 | [9.8](09_grover_algorithm.md#98-전체-그림-정리--amplitude는-왜-real-number뿐인가) · [11.2](11_state_vector_emulator.md#112-세-개의-array--ampdatamask) |
| number format | **fixed-point** | 04·05 | 07의 float32 | 실수 전용이라 동적 범위가 좁고, diffusion operator가 shift·subtraction만으로 닫힘. 지수·normalization circuit이 통째로 불필요 | [12.1](12_fixed_point_and_precision.md#121-왜-floating-point를-안-쓰는가) · [12.9](12_fixed_point_and_precision.md#129-반론--fixed-point는-부정확하다) |
| number of qubits | **14 qubits** (16,384 states) | — | 더 많은 qubit | $1/\sqrt{\text{number of states}} = 2^{-7}$ 이 정확. checkpoint slot까지 on-chip에 들어가는 천장이고, 22 fraction bits로 probability $\ell_2 \le 10^{-5}$ 가 되는 크기 | [11.4](11_state_vector_emulator.md#114-amplitude를-어디에-둘-것인가) · [12.7](12_fixed_point_and_precision.md#127-몇-bit면-되나--minimum-fraction-bits-공식과-그-전제) |
| data word width | **23 bits, Q1.22**, round-half-to-even, symmetric saturation(중간값은 25 bits), renormalization 없음 | 05(방향) | 04의 30 bits, 저장 data word의 integer bits 확장 | 되쓰는 값은 수학적으로 $\le 1$ 이라 중간값만 넓히면 됨. fraction bits 충분성은 공식이 아니라 benchmark(전 실행 error $< 10^{-3}$) | [12.3](12_fixed_point_and_precision.md#123-integer-bits는-몇-bit인가--재는-대상이-셋이다) · [12.4](12_fixed_point_and_precision.md#124-rounding--왜-half-to-even인가) · [12.5](12_fixed_point_and_precision.md#125-overflow-policy--saturationwraparound-금지renormalization-없음) · [12.7](12_fixed_point_and_precision.md#127-몇-bit면-되나--minimum-fraction-bits-공식과-그-전제) |
| 저장 | **전부 on-chip BRAM**, Accelerator Core 84 BRAM tiles (amplitude·checkpoint RAMB36 44 · `data_mem` RAMB18 64 · `found_mask` 2 · measurement 2 · policy 4) | 04 | 07의 외부 DDR, register array | 14 qubits면 checkpoint slot까지 on-chip에 들어감. DDR latency·controller도, register의 LUT 폭발도 피함 | [11.4](11_state_vector_emulator.md#114-amplitude를-어디에-둘-것인가) · [15.5](#155-확정-platform과-resource-예산) |
| 병렬도 | **row당 32 lanes × 4 PEs** = cycle당 128칸. index 하위 5 bits가 lane, row 번호 하위 2 bits가 row phase bank | — | crossbar·permutation network | 순차 streaming이라 충돌 0. routing 비용이 붙지 않음 | [11.7](11_state_vector_emulator.md#117-병렬도와-banking) · [13.7](13_oracle_diffusion_measurement_datapath.md#137-32-lane-datapath와-accumulation-순서) |
| diffusion operator | **$2\cdot\text{mean}-\text{amp}$, 0 multipliers** | 04 | 08의 일반화 $P_S$ | number of states가 2의 거듭제곱이라 2×mean을 accumulator의 13칸(number of qubits − 1) arithmetic right shift **한 번**으로 만들고, 나머지는 subtraction. 일반화는 (08번 표기로) $O(N\cdot D)$ 손해 | [13.5](13_oracle_diffusion_measurement_datapath.md#135-diffusion-operator--2mean--amp가-circuit이-되는-순간) · [13.8](13_oracle_diffusion_measurement_datapath.md#138-multiplier는-어디에-있고-어디에-없는가) |
| measurement | **Born-rule sampling**, integer 정확 계산, 64-bit random number rejection sampling, group(16) → row(32) → lane(32). Build는 cycle당 2 rows(Dual-Row Build), row 선택은 16×32 layer(Two-Level Select). DSP 128개 | 04(WRNG) | argmax | solution들의 amplitude가 매 iteration **정확히 같아** argmax는 늘 같은 index 하나만 반환 → enumeration이 원리적으로 불가능 | [14.3](14_multiple_solutions_and_minimum_search.md#143-amplitude-동률--argmax가-무너지는-지점) · [14.4](14_multiple_solutions_and_minimum_search.md#144-born-rule-sampling--probability를-circuit으로) · [14.5](14_multiple_solutions_and_minimum_search.md#145-2단-병렬-measurement) |
| oracle | **predicate 4종 판정**($<$, $>$, $=$, 범위) + `DATA_COUNT` 밖은 항상 non-solution | 09 | index hardcoding, comparator IP | solution을 모르는 것이 정상. $\text{value}-\text{thr}$ 의 MSB 하나가 $<$ 의 답이라 subtractor 하나를 4종이 공유 | [13.3](13_oracle_diffusion_measurement_datapath.md#133-oracle--predicate-4종이-subtractor-하나를-공유한다) · [14.2](14_multiple_solutions_and_minimum_search.md#142-oracle은-solution을-아는-circuit이-아니다) |
| number of iterations | **BBHT가 기본**(sampling range는 1에서 시작, growth factor 6/5, 28항 ROM, sampling range 상한 128 $=\sqrt{\text{number of states}}$), 보호 한도는 shot cap 100 · BBHT budget 576 | BBHT(1998)·09 | quantum counting(QPE) | solution이 몇 개인지는 predicate·threshold·data에 의존해 사전에 알 수 없음. QPE는 complex number를 강제해 실수 datapath가 무너짐 | [16.1](16_iteration_control_and_checkpoints.md#161-왜-solution이-몇-개인지-모르는가) · [16.2](16_iteration_control_and_checkpoints.md#162-bbht--무작위로-뽑는-number-of-iterations와-12-growth-factor) · [16.3](16_iteration_control_and_checkpoints.md#163-shot-통계--mean이-20-shots를-넘는-이유) |
| shot loop | **BBHT autonomous mode**(hardware 바깥 FSM)가 기본, firmware가 number of iterations를 정하는 **Manual mode** 병존 | — | 한쪽만 두는 안 | autonomous mode는 shot마다의 CSR 왕복을 없애고, Manual mode는 solution이 몇 개인지 아는 조건의 비교와 reference model과의 한 shot 단위 대조에 계속 필요 | [16.4](16_iteration_control_and_checkpoints.md#164-바깥-fsm--shot-loop와-solution-check) · [17.7](17_rvx_soc_integration.md#177-hardware와-firmware의-경계) |
| checkpoint | **a Checkpoint-Capacity of 3 + 3-shot Lookahead DP policy**, 가장 가까운 앞선 state에서 차이만큼 전진. 500 workloads executed iterations −69.5% | — (우리 고유) | 1칸 checkpoint(초판), a Checkpoint-Capacity of 4 and 4-shot Lookahead·a Checkpoint-Capacity of 4 and 8-shot Lookahead, 되감기, `hit[]` caching | Born-rule sampling이 amplitude를 읽기만 하므로 실패한 shot의 state가 그대로 남음. $(D\!\cdot\!O)^{\text{number of iterations}}$ 의 associative law로 결과가 bit 단위로 동일. Checkpoint-Capacity·Lookahead-Shots를 줄이면 결정 비용이 줄어 오히려 빠름 | [16.5](16_iteration_control_and_checkpoints.md#165-checkpoint--measurement가-읽기-전용이라는-사실에서) · [16.6](16_iteration_control_and_checkpoints.md#166-왜-결과가-달라지지-않는가) · [16.8](16_iteration_control_and_checkpoints.md#168-기각한-대안) |
| enumeration mode | **`found_mask` 16,384 × 1-bit**, predicate $\wedge\ \lnot\text{found}[i]$, 결과 **FIFO 256칸**(가득 차면 멈춤), BBHT 실패 **3연속**(기본값)으로 종료 | — | 결과를 host가 걸러내기, 별도 포기 signal | mask를 걸면 solution 집합이 줄어든 **새 문제**를 다시 푸는 것이라 중복이 원천 차단됨 | [14.7](14_multiple_solutions_and_minimum_search.md#147-enumeration-mode--mask로-중복-없이) · [16.7](16_iteration_control_and_checkpoints.md#167-무효화는-hardware가-한다) |
| SoC 형태 | **RVX `rvc_orca`** + APB slave(CSR 38개, 4-byte 간격) + AHB master(SINGLE load), host는 UART | 04(RISC-V SoC) | MicroBlaze, AXI4-Lite, AXI-Stream, INCR16 burst | 제어는 register 몇 개라 APB로 충분하고, data load는 master가 필요해 AHB. RVX에는 AXI-Stream shim이 없음 | [17.3](17_rvx_soc_integration.md#173-왜-apb와-ahb를-같이-쓰나) · [17.4](17_rvx_soc_integration.md#174-csr-map) · [17.5](17_rvx_soc_integration.md#175-data-load--ahb-master) |
| verification | **단계별 verification**(float64·Qiskit → Q1.22 bit-exact reference model → RTL → board), 합격 기준 **bit-exact**와 BBHT trajectory 일치 | 05 | 눈으로 waveform 확인 | 층을 나눠야 "algorithm이 틀렸나 / 수 표현이 틀렸나 / circuit이 틀렸나"를 분리해 물을 수 있음. reference model과 board가 500/500 일치 | [18.2](18_reference_model_verification.md#182-3단-verification-ladder) · [18.3](18_reference_model_verification.md#183-bit-exact가-성립하기-위한-조건) |

초판이 이 표 밖에 미정으로 남겨 두었던 아홉 가지는 이제 전부 정해졌습니다. 무엇이 어떻게 정해졌는지는 [15.8절](#158-되돌아보며)에 모았습니다.

---

## 15.5 확정 platform과 resource 예산

| 항목 | 값 |
|------|-----|
| board | **Arty A7-100T**, part `xc7a100tcsg324-1` (Artix-7) |
| board resource | BRAM36 **135개** · DSP **240개** · LUT 63,400 |
| number of qubits | **14 qubits** (16,384 states) |
| data word | 16-bit signed |
| clock | accelerator **100 MHz**(전용 clock `clk_accel`) / RISC-V core와 bus 50 MHz |
| SoC · bus | RVX(`rvc_orca` RV32 · `munoc` interconnect), APB slave + AHB master |
| host | PC ─ UART ─ RISC-V app ─ CSR ─ accelerator |
| configuration | **final configuration** — a Checkpoint-Capacity of 3 · 3-shot Lookahead · 4 PEs · Dual-Row Build · Two-Level Select |

**이전 판의 XC7S100은 폐기합니다.** RVX에 `xc7s100` imp class 가 없기 때문이고, 이 판단은 그대로입니다.

resource는 이제 추정이 아니라 **2026-09-07 implementation report의 실제 값**입니다.

| 부분 | LUT | FF | BRAM tile | DSP |
|------|----:|----:|----:|----:|
| Accelerator Core (`u_main_ip`) | 32,242 | 28,223 | 84 | 128 |
| Bus Interface · RVX SoC 나머지 | 13,042 | 17,000 | 32 | 4 |
| **board 전체** | **45,284 / 63,400** | **45,223 / 126,800** | **116 / 135** | **132 / 240** |

Accelerator Core의 84 BRAM tiles는 amplitude·checkpoint memory(RAMB36 44개, state 한 벌이 11개이고 checkpoint slot 네 벌 분량), `data_mem`(RAMB18 64개 = 32 tiles), `found_mask`·measurement row weight·policy memo table(RAMB36 2·2·4개)입니다. SoC 몫 32 tiles는 대부분 system SRAM 128 KB입니다. qubit를 하나 늘리면 state 한 벌이 두 배가 되어 amplitude·checkpoint memory만 88개가 되고 board를 넘깁니다([11.4절](11_state_vector_emulator.md#114-amplitude를-어디에-둘-것인가)).

DSP 사용처는 둘로 갈립니다. diffusion operator·oracle·Init 경로에는 multiplier가 **하나도** 없고, Measurement Unit에만 23×23 squarer(DSP 2개씩)가 32 lanes × 두 벌, 즉 **DSP 128개**가 잡힙니다. synthesis report에 DSP가 잡혔다고 잘못 짠 것이 아닙니다 — Born-rule sampling을 쓰기로 한 순간 정상적으로 예상되는 값입니다. timing은 100 MHz에서 닫혔습니다(WNS +0.126 ns).

시간은 축을 나눠 적어야 합니다. **RTL cycle 축**으로, Grover iteration 한 번이 약 268 cycles(100 MHz에서 2.7 µs)이고, 14 qubits · 1 solution search 한 번이 mean 25,345 cycles(약 0.25 ms)입니다. 매 shot 처음부터 도는 Restart mode는 같은 조건에서 mean 209,277 cycles이었습니다. 500 workloads 전체로는 42,308,335 → 6,890,470 cycles, **6.1401×**입니다. **board wall-clock time 축**으로는 같은 500 workloads가 Restart mode 425,502 µs → 55,798 µs, **7.626×**입니다. 두 축은 BBHT trajectory가 500/500 같지만 cycle 값 자체가 달라, 섞어 speedup을 만들면 안 됩니다.

이 숫자들을 고전 선형 scan과 나란히 놓지 마십시오. `value[]` 를 한 번 훑는 데는 128 rows를 읽는 128 cycles 남짓이면 끝납니다. emulation 비용이 $O\big(\text{number of states}\cdot\sqrt{\text{number of states}/\text{number of solutions}}\big)$ 이라 원리적으로 그렇게 됩니다 — Grover의 $\sqrt{\text{number of states}}$ 이득은 **실기 quantum**의 이야기이고, amplitude array를 전부 훑어야 하는 emulator에는 해당하지 않습니다. 우리 accelerator의 비교 대상은 같은 일을 하는 **Qiskit AerSimulator·NumPy state vector simulator**, 그리고 같은 board 위에서 accelerator를 끄고 RISC-V core 하나로 같은 계산을 돌린 **순수 software baseline**입니다. 마지막 것과의 차이는 wall-clock time으로 116,426×인데, 이는 32 lanes 병렬과 두 배 빠른 clock 덕이지 algorithm 우위가 아닙니다. 값어치는 속도 우위가 아니라 **quantum algorithm의 동작을 결정적이고 재현 가능하게 재현·검증하는 전용 hardware**라는 데 있습니다.

비교의 공정성에 관한 주의도 하나 — 04번의 resource 수치(LUT/FF)는 RISC-V SoC infrastructure를 포함한 값이라, 우리가 accelerator만 따로 재면 훨씬 작게 나옵니다. 게다가 04번 논문 스스로 "Vivado의 cross-optimization 때문에 이론적 역산이 불가능하다"고 경고합니다. 그러니 우리 수치를 04번과 나란히 놓을 때는 **무엇을 포함한 값인지**를 반드시 밝혀야 부당한 비교를 피할 수 있습니다. 위 표가 Accelerator Core와 board 전체를 따로 적은 이유가 이것입니다.

---

## 15.6 인용 시 주의 — 논문의 오류와 모호점

여섯 논문을 원문과 한 줄씩 대조한 결과, 전부에 인용할 때 주의해야 할 오류·모호점이 있었습니다. "논문은 옳다"고 믿고 베끼면 circuit이 동작하지 않거나 틀린 값을 인용하게 됩니다. 특히 ★ 표시는 **그대로 옮기면 결과가 틀어지는** 것들입니다.

| 논문 | 오류·모호점 | 인용 시 대응 |
|:-:|------|------|
| 04 | ★ pseudocode 오타 다수: `>> NUM_STATE`(→`NUM_QUBIT`), `amp_state` index 누락, `i-1 << k` 괄호(operator 우선순위) | **그대로 짜면 동작 안 함** — 직접 고쳐서 |
| 04 | ★ magic number 2개 LSB 어긋남: `0x2D41_3CCE`(→`…CCD`), `0x1_1C58_31AC`(→`…AE`) | 직접 계산해 넣을 것([13.2](13_oracle_diffusion_measurement_datapath.md#132-init--uniform-amplitude를-square-root-unit-없이)·[16.2](16_iteration_control_and_checkpoints.md#162-bbht--무작위로-뽑는-number-of-iterations와-12-growth-factor)) |
| 04 | Table 1의 Pauli-$Y$ = $\begin{bmatrix}0&-i\\i&1\end{bmatrix}$ (→ 우하단 0) | [3장](03_single_qubit_gates.md)과 충돌 — 3장이 옳음 |
| 04 | "2 qubits~6에서 error $2^{-12}$ 이하"가 Table 3과 모순 (2 qubits는 $2^{-4}$) | 본문 서술 인용 금지, Table 3 값 사용 |
| 04 | "4 qubits $p=3$ → $\epsilon_r=0.4\%$"가 자기 식과 모순 (실제 0.024%; 0.4%는 $p=2$) | 이 수치 인용 금지 |
| 04 | Table 6 단위 불명("clock cycles"인데 값이 10.21) | 비율(191×)만 유효, 절대값 인용 주의 |
| 04 | Theorem 6 증명이 실제 algorithm(shift) 아닌 나눗셈 version을 증명 — 정리 형식이 장식적 | "정리+증명"을 근거로 신뢰하지 말 것 |
| 05 | 12 qubits · 28 fraction bits의 $\ell_2$ 가 세 곳에서 다름 (7.49 / 7.492 / 7.493 ×$10^{-6}$) | reference model 목표값을 하나로 지정 후 재현 |
| 05 | solution amplitude $\alpha_S\approx n_s^{-1}$ (→ $n_s^{-1/2}$ 로 보임) | solution이 여럿인 경우로 확장 시 직접 재유도 |
| 05 | $r_{\text{num\_q}}$ 가 2.04→2.24로 drift하는데 설명 없음 | qubit가 더 많은 쪽으로 외삽 시 safety margin 주의 |
| 06 | ★ 식 (6)에서 $l$ 과 $(i,j)$ 의 역할이 뒤바뀌어 인쇄 | §IV-B code가 정답지 |
| 06 | 852× vs 854× (초록/서론 불일치), Fig.1 caption $\gamma\leftrightarrow\beta$ | 두 값 병기 |
| 07 | 식 (21) `2n`을 `2^n`으로 오독하기 쉬움; `n_{d-1}`은 아래첨자(multiplication 아님) | 지수 아님에 주의 |
| 07 | Fig. 8의 (b)·(c)가 caption과 뒤바뀌어 배치 | 그림·caption 대조 확인 |
| 07 | "32 qubits가 memory 천장"은 논문에 없는 추정 | 논문 주장으로 인용 금지 |
| 08 | **초록은 $\alpha\approx 1$, 본문은 $\alpha\approx 0.9$** | 반드시 병기 |
| 08 | 식 (6) $\delta_{nn'}$ 이 원문엔 $\delta_{nn}$ 으로 인쇄 (논문 오타로 판단) | 주석 달고 인용 |
| 09 | ★ 식 (9)(12)의 sign 규약이 본문과 어긋남 — 그대로면 **minimum 아닌 maximum** | sign은 우리가 정하고 simulation으로 verification([13.3](13_oracle_diffusion_measurement_datapath.md#133-oracle--predicate-4종이-subtractor-하나를-공유한다)) |
| 09 | ★ Algorithm 2(DHA)에 sampling range 갱신 줄 누락 (BBHT에만 있음) | 본문 기준으로 sampling range 증가 직접 추가([16.2](16_iteration_control_and_checkpoints.md#162-bbht--무작위로-뽑는-number-of-iterations와-12-growth-factor)) |
| 09 | $N$(사용자 수)과 $K=2^N$(search space) 혼동 위험 | [14.0절](14_multiple_solutions_and_minimum_search.md#140-기호-충돌-주의) 표기 통일 규약 적용 |

이 목록에서 확인하듯 **1차 자료도 틀립니다** — 그러니 hardware로 옮기기 전에 반드시 원문을 의심하고, 수치는 직접 계산해 보고, sign은 simulation으로 확인하라는 것입니다. 예를 들어 04번의 pseudocode를 그대로 옮기면 circuit이 동작하지 않습니다.

---

## 15.7 hardware 용어집

hardware 쪽에서 처음 나온 용어들을 모았습니다(quantum 이론 용어는 [10.5절](10_glossary_and_cheat_sheet.md#105-용어집)에 있습니다).

| 용어 | 뜻 | 장 |
|------|-----|:--:|
| emulation | 전용 hardware(FPGA)로 state vector 계산을 가속하는 것. software simulation과 대비 | [11장](11_state_vector_emulator.md) |
| LUT | look-up table. FPGA의 조합 logic resource. **연산 logic**이 여기 잡힘 | [11.5](11_state_vector_emulator.md#115-register의-진짜-대가) |
| FF | flip-flop. FPGA의 순차(저장) resource. **register 저장**이 여기 잡힘 | [11.5](11_state_vector_emulator.md#115-register의-진짜-대가) |
| BRAM | block RAM. FPGA 안의 block memory. port 수만큼만 동시에 접근. RAMB36 port 하나는 최대 72-bit 폭 | [11.4](11_state_vector_emulator.md#114-amplitude를-어디에-둘-것인가) |
| DSP | 전용 multiplier block. 우리는 Measurement Unit에만 128개를 씀 | [13.8](13_oracle_diffusion_measurement_datapath.md#138-multiplier는-어디에-있고-어디에-없는가) |
| row · lane | 연속한 index 32개가 row 하나, 그 안의 한 칸이 lane. index 하위 5 bits가 lane | [11.7](11_state_vector_emulator.md#117-병렬도와-banking) |
| banking | array를 여러 memory로 쪼개 한 cycle에 여러 칸을 읽는 것. 우리는 row 번호 하위 2 bits로 4 banks 중 하나를 고름 | [11.7](11_state_vector_emulator.md#117-병렬도와-banking) |
| PE · number of PEs | Iteration Datapath에서 한 cycle에 row 하나를 처리하는 circuit 한 벌과 그 개수. final configuration은 4 PEs | [13.1](13_oracle_diffusion_measurement_datapath.md#131-한-iteration-안의-fsm) |
| Dual-Row Build · Two-Level Select | Measurement Unit에서 한 cycle에 2 rows의 row weight를 만드는 Build와, 16 groups → 32 rows 두 단으로 고르는 Select. final configuration의 Measurement Microarchitecture | [14.5](14_multiple_solutions_and_minimum_search.md#145-2단-병렬-measurement) |
| memory-bound | 속도가 산술이 아니라 memory bandwidth · port에 묶인 state | [11.6](11_state_vector_emulator.md#116-memory-bound의-두-얼굴--용량과-port) |
| fixed-point | 소수점 위치를 고정해 integer처럼 다루는 수 표현 | [12.2](12_fixed_point_and_precision.md#122-fixed-point와-q-format-명명-규약) |
| Q format | `Q<integer bits>.<fraction bits>`. sign은 integer bits에 포함 → 우리는 Q1.22 | [12.2](12_fixed_point_and_precision.md#122-fixed-point와-q-format-명명-규약) |
| round-half-to-even | 정확히 0.5인 값을 짝수 쪽으로 보내 rounding 편향을 없애는 규칙 | [12.4](12_fixed_point_and_precision.md#124-rounding--왜-half-to-even인가) |
| saturation | 표현 범위를 넘으면 wraparound 대신 maximum · minimum에 붙이는 처리. 우리는 symmetric saturation | [12.5](12_fixed_point_and_precision.md#125-overflow-policy--saturationwraparound-금지renormalization-없음) |
| truncation error | fraction bits가 유한해 아래 bit가 잘려 나가며 생기는 error | [12.6](12_fixed_point_and_precision.md#126-error는-어떻게-자라나) |
| FSM | finite-state machine. state를 순서대로 밟으며 제어하는 circuit. emulator의 골격 | [13.1](13_oracle_diffusion_measurement_datapath.md#131-한-iteration-안의-fsm) |
| datapath | data가 흐르며 연산되는 경로(adder · shifter · comparator 등) | [13장](13_oracle_diffusion_measurement_datapath.md) |
| pipeline | 연산을 여러 단으로 나눠 매 cycle 하나씩 흘려 throughput을 높이는 구조 | [13.7](13_oracle_diffusion_measurement_datapath.md#137-32-lane-datapath와-accumulation-순서) |
| CORDIC | shift와 addition만으로 임의 각도 회전을 계산하는 algorithm. 우리는 쓰지 않음 | [13.8](13_oracle_diffusion_measurement_datapath.md#138-multiplier는-어디에-있고-어디에-없는가) |
| Born-rule sampling | amplitude square에 비례하는 probability로 index 하나를 뽑는 measurement. 우리 방식 | [14.4](14_multiple_solutions_and_minimum_search.md#144-born-rule-sampling--probability를-circuit으로) |
| prefix sum | 앞에서부터 차례로 더한 partial sum. 우리 Measurement Unit은 row weight의 prefix sum을 32 rows마다 group prefix sum으로 적어 두고 group → row → lane 순으로 좁혀 감 | [14.5](14_multiple_solutions_and_minimum_search.md#145-2단-병렬-measurement) |
| rejection sampling | 넓은 범위에서 뽑아 원하는 범위 밖이면 버리고 다시 뽑아 정확한 균등분포를 얻는 방법. number of iterations를 뽑을 때와 Measurement PRNG 둘 다 씀 | [14.4](14_multiple_solutions_and_minimum_search.md#144-born-rule-sampling--probability를-circuit으로) · [16.2](16_iteration_control_and_checkpoints.md#162-bbht--무작위로-뽑는-number-of-iterations와-12-growth-factor) |
| argmax | array에서 maximum의 **index**를 찾는 것. amplitude 동률 때문에 **기각한** measurement 방식 | [14.3](14_multiple_solutions_and_minimum_search.md#143-amplitude-동률--argmax가-무너지는-지점) |
| weighted random number generator | probability distribution을 따라 뽑는 random number 발생기(04번 논문의 measurement). 우리와 같은 방식 | [14.4](14_multiple_solutions_and_minimum_search.md#144-born-rule-sampling--probability를-circuit으로) |
| LFSR | linear-feedback shift register. shift와 XOR만으로 만드는 의사난수 발생기. Iteration-Count LFSR이 씀 | [16.2](16_iteration_control_and_checkpoints.md#162-bbht--무작위로-뽑는-number-of-iterations와-12-growth-factor) |
| BBHT | Boyer–Brassard–Høyer–Tapp. number of solutions를 모를 때 쓰는 iteration 스케줄(sampling range를 growth factor 6/5씩 키움) | [16.2](16_iteration_control_and_checkpoints.md#162-bbht--무작위로-뽑는-number-of-iterations와-12-growth-factor) |
| checkpoint | 실패한 shot의 amplitude state를 몇 벌 남겨 두었다가 가장 가까운 것에서 이어 도는 기법. 우리는 a Checkpoint-Capacity of 3 | [16.5](16_iteration_control_and_checkpoints.md#165-checkpoint--measurement가-읽기-전용이라는-사실에서) |
| policy | 앞으로 올 request 몇 개를 보고 checkpoint에 무엇을 남길지 정하는 규칙. Policy Engine이 계산. 우리는 3-shot Lookahead | [16.5](16_iteration_control_and_checkpoints.md#165-checkpoint--measurement가-읽기-전용이라는-사실에서) |
| SoC | system-on-chip. CPU · memory · 주변장치 · accelerator를 한 chip에 담은 system | [17.2](17_rvx_soc_integration.md#172-rvx가-무엇인가) |
| CSR | control/status register. software가 읽고 쓰는 제어 · status register. APB로 접근 | [17.4](17_rvx_soc_integration.md#174-csr-map) |
| APB · AHB | 저속 · 단순 bus와, master를 둘 수 있는 고속 bus. 제어는 APB, data load는 AHB | [17.3](17_rvx_soc_integration.md#173-왜-apb와-ahb를-같이-쓰나) |
| bit-exact | 두 implementation의 출력이 bit 하나까지 같음. reference model과 RTL의 합격 기준 | [18.3](18_reference_model_verification.md#183-bit-exact가-성립하기-위한-조건) |
| classical-to-quantum loading | 고전 data를 quantum amplitude로 싣는 initialization. 07번 논문의 절반 | [11.9](11_state_vector_emulator.md#119-emulator가-실기보다-쉬운-것들) |

---

## 15.8 되돌아보며

여기까지 이론을 **hardware로 구현**하는 과정을 살펴보았습니다. state vector가 array가 되고(11장), amplitude가 Q1.22 fixed-point 숫자가 되고(12장), oracle과 diffusion operator가 multiplier 없는 datapath가 되고(13장), measurement가 probability를 뽑는 circuit이 되어 enumeration까지 열린(14장) 과정을 따라왔습니다. 각 과정에서 여섯 논문의 선택을 비교했습니다.

이제 여러분은 04번 논문을 "설계도"로 읽을 수 있고, 07번의 반대 선택이 왜 그럴듯한지 판단할 수 있으며, 논문의 수치를 그대로 믿지 않고 검증할 수 있습니다. 그리고 [15.4절](#154-우리-project의-좌표--확정-설계-결정표)의 표는 이제 계획이 아니라 **board에서 동작을 확인한 설계의 기록**입니다.

초판은 아홉 가지를 **미정**으로 열어 두었습니다. RTL을 짓고 board에 올리면서 전부 정해졌고, 어떻게 정해졌는지를 그대로 적어 둡니다. 앞의 넷은 [16.9절](16_iteration_control_and_checkpoints.md#169-초판의-미정-넷은-이렇게-정해졌다)이, 뒤의 다섯은 [17.8절](17_rvx_soc_integration.md#178-초판의-미정-다섯은-이렇게-정해졌다)이 자세히 다룹니다.

1. **solution이 없을 때의 종료 조건** — array를 고전적으로 훑어 확정하지 않고, shot cap 100과 BBHT budget 576 중 먼저 닿는 쪽으로 끝냅니다. enumeration mode는 이 "실패로 끝난 BBHT"가 연속 3번(기본값)이면 끝냅니다.
2. **$\text{number of iterations} \sim U[0,\ \text{sampling range})$ 의 균등성** — LFSR 후보를 경계 이상이면 버리고 다시 뽑는 rejection sampling으로 정확한 균등을 얻습니다.
3. **random number 소비 규약** — number of iterations 쪽은 32-bit Iteration-Count LFSR로 후보마다 한 번(버린 후보 포함) 추첨하고, measurement 쪽은 독립인 Measurement PRNG(64-bit xorshift)로 rejection sampling 후보마다 64-bit block 하나를 씁니다. group → row → lane 선택은 한 random number의 잔여를 이어 씁니다. reference model과 RTL이 이 규약을 똑같이 따르고, 500 workloads 전부에서 BBHT trajectory가 같습니다.
4. **$\text{sampling range} \leftarrow \min(1.2\cdot\text{sampling range},\ \sqrt{\text{number of states}})$ 의 hardware 산술** — 28항 ROM입니다. 14 qubits에서 $\sqrt{\text{number of states}} = 128$ 이 정확한 integer라 clamp가 깔끔합니다.
5. **enumeration 결과 반환 경로** — accelerator 안의 Result FIFO 256칸. 가득 차면 hardware가 멈추고 firmware가 돌고 있는 동안에도 뽑습니다.
6. **`M_max` 값** — 별도의 포기 signal을 두지 않았습니다. 상한은 FIFO 깊이가 사실상 정하고, 그 이상은 firmware가 비우는 속도의 문제입니다.
7. **RVX SoC의 실제 resource 점유** — implementation report로 실측했습니다. SoC 몫은 32 BRAM tiles이고, board 전체가 116 / 135입니다.
8. **CSR map** — 32-bit register 38개, 4-byte 간격으로 확정했습니다.
9. **실제 clock** — accelerator 전용 100 MHz clock을 두고, RISC-V core와 bus는 50 MHz로 둡니다. 두 clock domain 사이의 경계 처리는 RVX가 생성하는 비동기 bridge가 맡습니다.

남은 큰 결정은 하나입니다. 이 해설서가 설명한 BRAM Variant(checkpoint 방식)와, number of iterations마다의 amplitude를 DRAM에 전량 저장해 두는 DRAM Variant 가운데 무엇을 최종으로 할지입니다. DRAM Variant는 RTL 초안과 regression까지 있고 물리 DRAM 연결과 board verification이 남아 있습니다([16.8절](16_iteration_control_and_checkpoints.md#168-기각한-대안)).

원문을 한 편씩 처음부터 끝까지 읽고 싶다면, 각 논문의 한국어 해설본이 [`../papers/papers_ko/`](papers/papers_ko/)에 있습니다(원문 대조용). 이 해설서(study_references)가 **주교재**이고, 그쪽은 원문을 옆에 두고 볼 때의 보조 자료입니다.

---

## 15.9 여섯 논문 너머 — 더 읽을거리

이 해설서의 중심 자료는 여섯 편이지만 같은 문제(quantum algorithm을 고전 hardware로 흉내 내기)를 다른 각도에서 다룬 논문이 많습니다. 함께 참고한, 여섯 편 밖의 자료들을 여기 모읍니다.

먼저 전체적인 분류를 보면, 지금까지 당연한 듯 쓴 "state vector를 array로 펼쳐 계산"하는 방식은 사실 **유일한 길이 아니라 세 갈래 중 하나**입니다. Cicero 외(2025) survey는 algorithm 수준 simulation을 **Schrödinger식(state vector)·Feynman식(path sum)·tensor network** 으로 나눕니다. 우리 Grover emulator는 전형적인 Schrödinger식으로, 셋 중 memory를 가장 많이 쓰지만($2^{\text{number of qubits}}$ amplitudes를 전부 저장) implementation이 가장 단순합니다. tensor network는 qubit가 많고 circuit이 얕을 때 소수의 출력 amplitude만 뽑아 훨씬 효율적이지만, Grover는 iteration마다 amplitude 전체를 건드리는 깊은 circuit이라 tensor network의 이점이 약해집니다 — 즉 Grover에 state vector 방식을 쓰는 데에는 이런 근거가 있습니다.

| 논문 | 무엇을 더하나 | 본문 연결 |
|------|---------------|:--------:|
| **Boyer, Brassard, Høyer, Tapp (1998)** — Tight bounds on quantum searching | **BBHT의 원전.** solution이 몇 개인지 모를 때의 iteration schedule(growth factor 6/5)과 success probability의 lower bound가 여기서 나옴 | [15.2](#152-계보도--누가-누구를-딛고-섰나) · [16.2](16_iteration_control_and_checkpoints.md#162-bbht--무작위로-뽑는-number-of-iterations와-12-growth-factor) |
| **Pilch & Długopolski (2018)** — FPGA quantum emulator | 04·05·06·07이 공통 인용하는 **baseline**. qubit=지수 hardware의 benchmark(2 qubits 8k → 3 qubits 25k ALM). hardware von Neumann measurement | [15.2](#152-계보도--누가-누구를-딛고-섰나) · [14.6](14_multiple_solutions_and_minimum_search.md#146-기각한-대안들) |
| **Frank 외 (2009)** — SEQCSim | 저장 대신 **재계산**으로 memory를 $O(s+t)$ 로 (공간–시간 맞바꿈). 단 Grover엔 자멸적 | [11.3](11_state_vector_emulator.md#113-qubit-하나--memory-두-배) |
| **Tiwari 외 (2026)** — 30 qubits HBM simulator | memory-bound의 다음 수 = **HBM**. bank interleaving + BRAM→HBM 성능 절벽 benchmark | [11.6](11_state_vector_emulator.md#116-memory-bound의-두-얼굴--용량과-port) |
| **Belfore (2024)** — Scalable FPGA Architecture | 병렬화의 **제3비용 = routing**(Beneš permutation network가 logic 36%). 순차 streaming인 우리는 회피 | [11.7](11_state_vector_emulator.md#117-병렬도와-banking) |
| **Cicero 외 (2025)** — simulation survey | 방식 3분류(Schrödinger/Feynman/tensor network), FPGA의 두 역할(emulation↔acceleration) | [11장](11_state_vector_emulator.md) · 위 문단 |
| **Häner 외 (2016)** — High-Performance Emulation | "emulation vs simulation" 용어의 원전. 단 이들의 "emulation"은 QFT→FFT 같은 **software 지름길** 뜻이라 우리(state vector를 hardware에 펼침)와 다른 갈래 | — |
| **AMARETTO (2024)** — 저가 FPGA emulator | **algorithm을 RTL에 고정(04·우리)** vs **gate를 명령어로 실행**(butterfly amplitude pair 선택, KV260에서 16 qubits)의 대조 | — |

이 논문들의 원문 PDF는 [`../papers/5. 추가 수집 (OpenAlex)/`](papers/5.%20추가%20수집%20(OpenAlex)/)에, 더 넓은 목록은 [`../papers/references.md`](papers/references.md)에 있습니다. 다만 이들은 여섯 편처럼 정독·검증한 자료가 **아니라 보조 참고 자료**이니 인용하기 전에는 원문을 직접 확인하세요.

---

## 15.10 이 장의 요약

- 여섯 논문의 지형은 **04번이 중심**입니다. 05·06은 그 위성이고, 07은 반대 진영의 대조군, 08은 이론 배경, 09는 oracle을 predicate 판정으로 넓힌 **확장 참고 사례**입니다. iteration schedule의 근거는 09번이 아니라 BBHT 원전(1998)입니다.
- 논문들이 갈라지는 자리를 여덟 개의 축으로 정리했고, 그중 **H축("shot 사이에 state를 버리는가 남기는가")은 여섯 논문 어디에도 없는 우리 고유의 축**입니다. 우리 답은 a Checkpoint-Capacity of 3과 3-shot Lookahead policy입니다.
- [15.4절](#154-우리-project의-좌표--확정-설계-결정표)이 해설서 안에서 **이 project 숫자의 source of truth**입니다. board에서 검증된 final configuration을 따르고, 근거는 표의 각 줄이 가리키는 뒤 장들에 있습니다.
- platform은 **Arty A7-100T · 14 qubits · accelerator 100 MHz** 입니다. Accelerator Core가 84 BRAM tiles · 128 DSPs(전부 Measurement Unit), board 전체가 BRAM 116 / 135 · DSP 132 / 240이고 timing은 닫혔습니다. 성능은 RTL cycle 6.1401×와 board wall-clock time 7.626×로 **축을 나눠** 적습니다.
- [15.6절](#156-인용-시-주의--논문의-오류와-모호점)은 인용 전에 반드시 펼쳐 볼 정오표입니다. **1차 자료도 틀립니다.**
- 초판의 미정 아홉 가지는 **전부 정해졌습니다**([15.8절](#158-되돌아보며)). 남은 큰 결정은 BRAM Variant와 DRAM Variant 중 하나를 고르는 일입니다.

---

> [← 14장 multiple solutions — Born-rule sampling과 enumeration](14_multiple_solutions_and_minimum_search.md) · [index](index.md) · [16장 몇 번 돌릴지 모를 때 →](16_iteration_control_and_checkpoints.md)

<!-- HUMANIZE-SUMMARY -->
<!--
{
  "원본_글자수": 32774,
  "최종_글자수": 32695,
  "경로": "heavy",
  "게이트_변경률": 0.007,
  "등급": "B",
  "자체검증": "6/6 (보존 지시 대상의 교재 형식 제외)",
  "상태": "corrected",
  "국소_보정_수": 2,
  "카테고리": [
    "C-8",
    "D-14",
    "D-2",
    "D-8"
  ],
  "하이라이트": [
    {
      "rule": "C-8",
      "before": "이 장은 새 내용을 배우는 곳이 아니라, 앞 장들을 가로지르며 얻은 것을 **지도 한 장과 표 몇 개**로 압축하는 참조 자료입니다.",
      "after": "이 장은 앞 장들에서 배운 내용을 **지도 한 장과 표 몇 개**로 압축한 참조 자료입니다."
    },
    {
      "rule": "D-14",
      "before": "어긋나면 15.4절이 이깁니다.",
      "after": "어긋나면 15.4절을 기준으로 합니다."
    }
  ],
  "잔존_finding": []
}
-->
