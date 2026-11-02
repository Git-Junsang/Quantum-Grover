# 해설서 index — quantum computing 시작하기

> [1장 qubit와 state →](01_qubits_and_states.md)
> **Part 0** — 이 글은 사전 지식이 필요 없습니다. 편하게 읽으세요.

---

quantum computer를 처음 배울 때 가장 먼저 드는 질문은 "이게 대체 왜 필요한가?"입니다. 이 글은 수식 없이, quantum computer가 어디에서 왔고 왜 만들어졌는지, 그리고 우리 project가 왜 하필 **Grover algorithm**을 다루는지를 이야기합니다. 이 글을 읽고 나면 [1장](01_qubits_and_states.md)부터 이어지는 수학이 "무엇을 향해 가는지" 감이 잡힐 것입니다.

---

## 1. computer는 어디서 왔는가

오늘날 우리가 쓰는 모든 computer의 기원은 1936년 영국 수학자 **Alan Turing**의 연구로 거슬러 올라갑니다. Turing은 애초에 편리한 기계를 만들려던 게 아니라, 독일 수학자 Hilbert가 던진 질문 — *"어떤 수학 명제가 증명 가능한지 판별하는 일반적인 algorithm이 존재하는가?"* — 에 답하려 했습니다.

이 질문에 답하려면 먼저 "**algorithm이란 무엇인가**"를 엄밀히 정의해야 했습니다. Turing은 사람이 종이와 연필로 계산할 때 하는 동작을 분석해, 그 모든 것을 흉내 낼 수 있는 하나의 가상 기계 — **Turing machine** — 을 제안했습니다. "algorithm이란 Turing machine이 수행할 수 있는 것"이라는 이 정의가 현대 computing의 토대가 되었고, 이후 수십억 대의 computer가 이 model 위에 만들어졌습니다.

---

## 2. Deutsch의 질문 — 물리학이 계산을 결정한다

Turing의 논증에는 미묘한 허점이 있었습니다. "사람이 종이에 하는 계산"이라는 비형식적 근거에 기대고 있었던 것이죠. 1985년 물리학자 **David Deutsch** 는 더 깊은 접근을 제안합니다.

> 모든 algorithm은 결국 **어떤 물리적 system**에서 수행된다 — 사람이든, 주판이든, electronic circuit든. 그렇다면 **다른 모든 물리 system을 효율적으로 simulation할 수 있는 단 하나의 범용 계산 장치**가 존재하는가?

이 질문이 중요한 이유는, 만약 그런 장치가 있다면 물리 법칙 자체로 그것이 진정한 universal computer임을 증명할 수 있기 때문입니다. 그런데 Deutsch가 이 질문을 파고들자 문제가 드러났습니다: **평범한 (고전) computer는 quantum mechanical system을 simulation하는 데 극도로 느리고 비효율적**이었습니다.

이 문제를 풀기 위해 Deutsch는 새로운 종류의 계산 장치, 곧 **quantum computer** 를 고안해야 했습니다. quantum computer는 classical computer가 하는 모든 것을 할 수 있으면서, quantum mechanical process도 효율적으로 simulation합니다.

💡 **비유**: classical computer로 quantum 세계를 simulation하는 것은, 물속 세계를 육지의 규칙만으로 설명하려는 것과 같습니다. 억지로는 되지만 터무니없이 느립니다. quantum computer는 아예 물속에서 헤엄치는 장치입니다.

---

## 3. classical computer가 quantum을 흉내 내기 힘든 이유

핵심만 짚어봅시다. 입자 여러 개로 이루어진 분자를 simulation한다고 합시다. 각 입자가 qubit인 것은 아니지만, 설명을 위해 그렇게 단순화하면, 이 system을 기술하는 데 **$2^{\text{number of qubits}}$개의 숫자(amplitude)** 가 필요합니다. 입자 하나가 늘 때마다 필요한 memory가 **두 배**로 뜁니다.

왜 하필 2의 거듭제곱일까요? 입자(qubit) 하나는 0과 1, 두 가지 state를 가집니다. 둘이 되면 가능한 조합은 00·01·10·11 — 네 가지이고, 이 **조합 하나하나마다 amplitude(숫자)가 한 개씩** 필요합니다. 셋이면 000…111로 여덟 가지죠. 입자를 하나 더 붙일 때마다 기존 조합이 각각 "새 입자가 0인 경우"와 "1인 경우"로 둘씩 쪼개지므로, 조합의 수가 정확히 두 배가 됩니다($2 \to 4 \to 8 \to \cdots \to 2^{\text{number of qubits}}$). 그래서 필요한 숫자의 개수가 곧 조합의 총 개수, 즉 $2^{\text{number of qubits}}$인 것입니다.

그런데 여기서 자연스러운 반문이 떠오릅니다. "입자마다 숫자 2개씩이면, 입자 수의 두 배만큼만 있으면 충분하지 않나?" 항상 그렇게 쓸 수는 없습니다. quantum의 중요한 성질이 여기서 드러납니다. state에는 "A는 이 state, B는 저 state"처럼 입자별로 따로 나눠 적을 수 **없는** 경우가 있습니다 — 예컨대 두 입자를 아무리 멀리 떨어뜨려 놓아도 측정하면 늘 똑같은 값이 나오도록 서로 묶인 state가 그렇습니다. 이 묶임을 **entanglement** 라 하는데, 이 상관관계를 온전히 담으려면 모든 조합의 숫자를 하나도 빠짐없이 들고 있어야 합니다. 그래서 압축이 원리적으로 불가능하고, 지수적 크기를 피할 수 없습니다. (entanglement는 [5장](05_multiple_qubits_and_entanglement.md)에서 제대로 배웁니다.)

- 입자 10개 → $2^{10} \approx 1{,}000$개 숫자
- 입자 50개 → $2^{50} \approx 10^{15}$개 (천조 개)
- 입자 300개 → $2^{300}$ → 우주의 원자 수보다 많음

실제 원자는 qubit보다 복잡해서 더 많은 숫자가 필요합니다. 그래서 작은 분자를 빼면 classical computer로는 quantum simulation이 사실상 불가능합니다. 반면 **quantum computer는 입자가 하나 늘 때마다 qubit 몇 개만 추가하면 됩니다** — 필요한 자원이 지수적 증가 대신 선형 증가에 그칩니다.

> 🔑 **quantum computer의 근본 강점**: "$2^{\text{number of qubits}}$개의 amplitude"를 classical computer는 memory에 일일이 저장해야 하지만, quantum computer는 그만큼의 qubit만으로 그 state를 **자연스럽게 담습니다**. 이 "지수적으로 많은 amplitude를 다루는 능력"이 [1장](01_qubits_and_states.md)의 superposition에서 시작됩니다.

---

## 4. quantum computer는 무엇을 잘하는가

quantum computer가 **모든** 문제를 빠르게 푸는 마법 상자는 아닙니다. 대부분의 문제에서는 classical computer와 큰 차이가 없습니다. 그러나 몇몇 특정 문제군에서는 극적으로 앞섭니다.

| algorithm                | 문제                       | classical            | quantum            | 향상                   |
| ----------------------- | -------------------------- | --------------- | --------------- | ---------------------- |
| **Shor**          | 큰 수의 소인수분해         | exponential time       | polynomial time       | 지수적 (RSA 암호 위협) |
| **Grover**        | 정렬 안 된 data에서 search | $O(\text{number of states})$        | $O(\sqrt{\text{number of states}})$ | quadratic        |
| **Deutsch-Jozsa** | function이 constant/balanced인지 판별  | $O(2^{\text{number of qubits}})$      | $O(1)$        | 지수적 (교육적 예제)   |
| quantum simulation         | 분자·물질 simulation      | 지수적으로 느림 | 효율적          | 지수적                 |

이 표에서 **Grover와 Deutsch-Jozsa** 가 이 해설서의 종착지입니다. Shor algorithm은 더 복잡해서 다루지 않지만, Grover를 이해하면 quantum algorithm의 핵심 아이디어 — **interference로 solution의 probability를 키우는 것** — 을 익힐 수 있습니다.

---

## 5. 이 project가 Grover를 다루는 이유

우리 project의 목표는 **Grover algorithm을 FPGA hardware로 emulation**하는 것입니다. 조금 더 구체적으로 말하면, FPGA 안의 memory에 data array `value[]` 를 올려 두고 **predicate를 만족하는 원소가 몇 번 칸에 있는지를 Grover 방식으로 찾아 주는 accelerator IP** 입니다. predicate는 네 가지를 지원합니다 — threshold보다 작은가($<$), 큰가($>$), 같은가($=$), 그리고 두 threshold 사이인가($a < x < b$). 한 번 호출하면 predicate를 만족하는 index **하나**를 돌려주고, 호출을 되풀이하면 predicate를 만족하는 원소를 **중복 없이 전부 enumeration**할 수도 있습니다. board는 Digilent **Arty A7-100T**(Xilinx Artix-7)이고, IP는 그 위에 올린 **RVX** RISC-V SoC에 붙습니다. host는 **UART** 너머에서 명령을 보내고 결과를 받아올 뿐이며, amplitude 계산은 전부 FPGA 안에서 끝납니다. 다루는 규모는 **14 qubits**, 곧 $2^{14} = 16{,}384$ states를 담는 array입니다.

그러면 왜 하필 Grover일까요?

1. **algorithm이 단순하면서도 깊다.** Shor처럼 복잡한 number theory 없이, gate 몇 개를 되풀이하는 것만으로 동작합니다. 그런데도 quantum algorithm의 핵심 — amplitude amplification·interference — 을 온전히 담고 있어 hardware로 구현하기에 이상적입니다.
2. **적용 범위가 넓다.** "정렬되지 않은 data에서 predicate를 만족하는 항목 찾기"는 곧 **threshold 비교 질의**입니다. sensor log에서 기준치를 넘는 이상치를 골라내기, 어떤 interval에 드는 값들만 뽑아내는 range query, 조건에 걸리는 후보를 하나씩 전부 열거하기 — 위에 적은 predicate 네 가지가 정확히 이 질의들에 대응합니다. threshold를 찾을 때마다 더 낮춰 가면 같은 circuit으로 minimum 찾기도 됩니다. (project의 `4. Grover 응용 논문` directory가 이런 응용의 예입니다.)
3. **다만 "이차 향상"은 우리 것이 아니다.** 여기서 한 가지를 구분해야 합니다. 앞 절 표의 $O(\sqrt{\text{number of states}})$ 은 **진짜 quantum computer**가 oracle을 몇 번 부르는지를 센 값입니다. 우리처럼 classical circuit으로 흉내 내면 iteration 한 번마다 amplitude array 전체를 처음부터 끝까지 훑어야 하고 그 iteration을 $\sqrt{\text{number of states}}$ 번쯤 되풀이하므로, 총비용은 오히려 $\text{number of states} \times \sqrt{\text{number of states}}$ 만큼이 됩니다. 같은 문제를 array 한 번 훑어 푸는 평범한 classical program보다 **느립니다.** 이 해설서 어디에도 "우리 IP가 classical linear scan보다 빠르다"는 문장은 없습니다.

그렇다면 왜 만들까요? 비교 대상을 살펴보면 이 작업의 목적을 알 수 있습니다. 우리와 **같은 일**을 하는 것, 즉 amplitude array를 memory에 펼쳐 놓고 매 iteration 전부 훑는 것은 classical linear scan이 아니라 **state vector simulator**입니다. 구체적으로는 Qiskit의 `AerSimulator` 나 NumPy로 짠 state vector code가 우리의 비교 대상입니다. 그리고 이 IP의 값어치는 애초에 속도 우위가 아니라, quantum algorithm이 실제로 어떻게 동작하는지를 **결정적이고 재현 가능하게 재현·검증하는 전용 hardware**라는 데 있습니다. 같은 random number seed를 주면 언제나 같은 결과가 나오고, 계산 도중의 amplitude array를 통째로 꺼내 손계산이나 software model과 한 bit씩 대조할 수 있습니다. 진짜 quantum hardware에서는 둘 다 불가능한 일입니다 — 관측하는 순간 state가 바뀌기 때문입니다.

대신 대가가 있습니다. 모든 state의 amplitude를 memory에 하나하나 펼쳐 놓아야 하므로 **qubit를 하나 늘릴 때마다 필요한 memory가 두 배**로 뜁니다. 14 qubits는 amplitude array를 여러 벌 저장하며 계산하는 우리 구조를 이 board에 구현할 수 있는 상한입니다.

> ❓ **emulation? 실제 quantum computer가 아니고?**: 그렇습니다. 진짜 quantum hardware는 비싸고 불안정합니다. 대신 FPGA로 quantum state vector의 진화를 **classical 방식으로 계산**해 algorithm의 동작을 재현·검증합니다. 그러려면 state vector를 숫자 array로 펼쳐 놓고, gate가 그 array에 하는 일 — predicate를 만족하는 칸의 **sign 반전**과 모든 칸의 **inversion about the mean** — 과 measurement를 수치로 정확히 구현해야 하고, 그 수학이 바로 이 해설서의 내용입니다. (project의 `2. Grover 논문 (LPSoC)`, `3. QCE-FPGA 논문` 이 이 emulation 기법을 다룹니다.)

---

## 6. 앞으로의 여정 — 장 목록과 읽는 법

이 해설서는 algorithm의 수학적 model — qubit·superposition·gate·measurement·oracle·amplitude amplification — 을 기초부터 배운 뒤(0~10장), 같은 개념이 memory map·fixed-point data word·FSM·bus interface로 구현되는 과정을 따라갑니다(11~18장). 확정된 숫자(board, number of qubits, amplitude 형식, final configuration 등)의 source of truth는 [15.4절 설계 결정표](15_paper_map_and_design_decisions.md#154-우리-project의-좌표--확정-설계-결정표)이며, 해설서 어느 장에 같은 값이 적혀 있든 어긋나면 15.4절을 기준으로 삼습니다.

### 장 목록

#### Part 0. 왜 quantum computer인가

| 장 | file | 무엇을 배우나 |
|----|------|--------------|
| — | [index — quantum computing 시작하기](index.md) (이 글) | computer의 기원, 왜 quantum computer인가, classical vs quantum, 이 project가 Grover를 다루는 이유 |


#### Part 1. quantum computing의 언어 (기초)

| 장 | file | 무엇을 배우나 |
|----|------|--------------|
| 1 | [qubit와 state](01_qubits_and_states.md) | bit vs qubit, state vector, computational basis $\|0\rangle\|1\rangle$, amplitude·superposition, normalization |
| 2 | [Dirac 표기법과 linear algebra](02_dirac_notation_and_linear_algebra.md) | ket·bra, inner product $\langle\phi\|\psi\rangle$, conjugate transpose(dagger), $\|+\rangle\|-\rangle$ basis |
| 3 | [단일 qubit gate](03_single_qubit_gates.md) | $X\|H\|Y\|Z$ gate, unitary matrix, circuit 표기, gate composition=matrix multiplication |
| 4 | [measurement](04_measurement.md) | computational basis measurement, Born rule($\|\alpha\|^2$), collapse, measurement 불가 정보, global phase |


#### Part 2. 여러 qubit와 circuit

| 장 | file | 무엇을 배우나 |
|----|------|--------------|
| 5 | [다중 qubit와 entanglement](05_multiple_qubits_and_entanglement.md) | tensor product, multi-qubit state의 $2^{\text{number of qubits}}$ dimension, CNOT, Bell state·entanglement, product state |
| 6 | [quantum circuit model과 universality](06_quantum_circuit_model_and_universality.md) | circuit 3단계, Hadamard로 uniform superposition 만들기, parallelism, universal gate·Toffoli, circuit의 순효과는 하나의 unitary |


#### Part 3. quantum algorithm (project 핵심)

| 장 | file | 무엇을 배우나 |
|----|------|--------------|
| 7 | [oracle과 phase kickback](07_oracle_and_phase_kickback.md) | oracle $U_f$, black box, phase kickback, conditional sign 반전 |
| 8 | [Deutsch–Jozsa algorithm](08_deutsch_jozsa_algorithm.md) | Balanced vs Constant, $H^{\otimes \text{number of qubits}}$ 수학, interference, 한 번에 판별 |
| 9 | [**Grover algorithm**](09_grover_algorithm.md) | amplitude amplification, inversion about the mean, diffusion operator, geometric rotation, number of iterations $\frac{\pi}{4}\sqrt{\text{number of states}}$, amplitude가 real number뿐인 이유, 어느 개념이 어느 장으로 가는가 |


#### Part 4. 참조

| 장 | file | 무엇을 배우나 |
|----|------|--------------|
| 10 | [용어정리와 cheat sheet](10_glossary_and_cheat_sheet.md) | 핵심 gate matrix·공식 요약, 용어집, 연습문제 답, 원문 대조표 |
| 부록 A | [수학 빠른 복습](A_math_review.md) | 이 해설서가 쓰는 complex number(conjugate·absolute value·$e^{i\theta}$)·linear algebra(vector·matrix multiplication·dagger) 최소 정리 |


> 여기서부터(Part 5~8)가 이 project가 **실제로 만드는 물건**입니다. 여섯 편의 논문(`papers/` 2·3·4번 directory)을 설계 질문별로 **함께** 읽으면서, 확정된 설계 결정을 하나씩 세워 나갑니다. 04·05·06은 이 project 지도교수 연구실(중앙대) 논문입니다.

#### Part 5. 이론에서 hardware로 — 뼈대

| 장 | file | 무엇을 배우나 |
|----|------|--------------|
| 11 | [state vector emulator — memory map과 resource 예산](11_state_vector_emulator.md) | ket → 세 개의 array(`amp`·`data`·`mask`), qubit 하나 = memory 두 배, amplitude를 어디에 둘 것인가, memory-bound의 두 얼굴, 32 lanes 병렬과 banking, cycle 비용 model, emulator가 숨기는 것 |
| 12 | [amplitude를 숫자로 — fixed-point와 Q1.22](12_fixed_point_and_precision.md) | 왜 floating-point를 안 쓰는가, Q format 명명 규약, 폭을 정할 때 재는 대상이 셋이라는 것, round-half-to-even, symmetric saturation·renormalization 없음, minimum fraction bits 공식과 그 전제, fraction bits를 공식이 아니라 재서 정한 과정 |


#### Part 6. datapath — 한 shot 안에서 벌어지는 일

| 장 | file | 무엇을 배우나 |
|----|------|--------------|
| 13 | [oracle과 diffusion operator — multiplier 없는 arithmetic](13_oracle_diffusion_measurement_datapath.md) | 한 iteration 안의 FSM, square-root unit 없이 $1/\sqrt{\text{number of states}}$ 만들기, predicate 4종이 subtractor 하나를 공유하는 방법, two's complement negate, $2\cdot\text{mean} - \text{amp}$ 가 circuit이 되는 순간, 2 passes의 필연성, 32 lanes accumulation 순서, multiplier가 있는 곳과 없는 곳 |
| 14 | [multiple solutions — Born-rule sampling과 enumeration](14_multiple_solutions_and_minimum_search.md) | solution이 여럿이어도 oracle에는 공짜인 이유, oracle은 predicate를 판정하는 circuit라는 것, amplitude 동률로 argmax가 무너지는 지점, Born-rule sampling을 circuit으로, group·row·lane 순의 hierarchical measurement(Dual-Row Build · Two-Level Select), Found Mask로 중복 없이 enumeration, 역주행 등 두 함정 |


#### Part 7. 설계 좌표

| 장 | file | 무엇을 배우나 |
|----|------|--------------|
| 15 | [논문 지도와 설계 결정표](15_paper_map_and_design_decisions.md) | 6편 계보도, **여덟 개의 대립축**, 확정 설계 결정표(**숫자의 source of truth**), platform과 resource 예산, **인용 시 주의할 오류 목록**, hardware 용어집 |


#### Part 8. shot 바깥 — 제어·system·verification

| 장 | file | 무엇을 배우나 |
|----|------|--------------|
| 16 | [몇 번 돌릴지 모를 때 — BBHT shot loop와 checkpoint](16_iteration_control_and_checkpoints.md) | 왜 solution이 몇 개인지 모르는 채 시작하는가(속도가 아니라 실기 충실도), BBHT(sampling range 1에서 시작 · growth factor 6/5), mean shot count가 스무 번을 넘는 이유, 바깥 FSM과 solution check, **a Checkpoint-Capacity of 3과 3-shot Lookahead policy**, 그 정당성, 무효화는 hardware가 한다 |
| 17 | [RVX SoC에 붙이기 — APB CSR · AHB DMA · UART](17_rvx_soc_integration.md) | accelerator는 혼자 서지 않는다, RVX(`rvc_orca`·`munoc`)가 무엇인가, APB와 AHB를 같이 쓰는 이유, CSR map, AHB master로 data load, host UART protocol, hardware와 firmware의 경계 |
| 18 | [무엇을 어떻게 증명하나 — 3단 reference model과 bit-exact](18_reference_model_verification.md) | 왜 verification이 설계의 일부인가, float64 → bit-exact fixed-point model → RTL의 3단 verification ladder, bit-exact가 성립하기 위한 조건, 9.4절 손계산이 첫 test vector, Born sampler와 checkpoint를 어떻게 검증하나, 잰 수치와 그 조건, toolchain과 directory |

### 읽는 순서

각 장은 바로 앞 장의 개념을 바탕으로 설명합니다. 순서대로 읽기를 권합니다. 특히 **superposition(1장) → gate(3장) → measurement(4장) → phase kickback(7장)** 은 Grover를 이해하는 데 필요한 4개의 기본 개념입니다. 0~10장이 quantum 이론이고, 11장부터는 그 이론을 실제 circuit으로 옮기는 이야기라 FPGA 기초(LUT·FF·BRAM·DSP)를 함께 가정합니다. 이론만 필요하다면 10장에서 멈춰도 됩니다.

```
처음 배우는 사람:               1장 → 2장 → ... → 9장  (순서대로)
linear algebra에 익숙한 사람:   1~2장 빠르게, 3장부터 정독
Grover만 급히 볼 사람:          1·3·4·5·6.2·7장 훑고 → 9장 (모르는 개념은 앞 장 참조)
hardware까지 갈 사람:           9장까지 마치고 → 11 → 12 → 13 → 14 → 16 → 17 → 18
                                (FPGA 배경이 있으면 11.5·11.6절은 훑고 넘어가도 됩니다)
```

**13장을 읽기 전에 12장의 내용이 필요합니다.** 13장은 amplitude 한 칸이 Q1.22 fixed-point라는 것, round-half-to-even이 어느 지점에서 일어난다는 것, 넘치면 saturation이 걸린다는 것을 전부 12장의 결정으로 **전제하고** 씁니다. 12장을 건너뛰면 13장의 shift 위치와 data word 폭이 근거 없는 숫자로 보입니다.

15장은 순서에 넣지 않았습니다. 참조용이라 11~14장을 읽은 뒤 아무 때나 펼치면 되고, 확정된 수치가 필요할 때마다 [15.4절](15_paper_map_and_design_decisions.md#154-우리-project의-좌표--확정-설계-결정표)로 돌아오게 됩니다. 다만 논문을 **인용하기 전에는** 반드시 [15.6절 정오표](15_paper_map_and_design_decisions.md#156-인용-시-주의--논문의-오류와-모호점)를 먼저 보세요.

각 장은 시작 부분에 **"이 장을 읽기 위한 준비"** 로 필요한 배경 지식을 링크합니다. 앞 장에서 배운 개념을 뒤 장에서 쓰도록 배치했습니다.

### 독자에게 가정하는 것

- **알고 있다고 가정**: complex number(magnitude·conjugate·$e^{i\theta}$), linear algebra(vector·matrix·matrix multiplication·transpose), classical logic gate(AND·OR·NOT·XOR), 기초 programming, big-O notation($O(n)$, $O(\log n)$).
- **처음이라고 가정하고 설명**: qubit·state·superposition, Dirac(bra-ket) 표기법, quantum gate와 unitary matrix, measurement와 collapse, entanglement, oracle·phase kickback, amplitude amplification, Grover·Deutsch-Jozsa algorithm. → 이 개념들을 **1장부터 차근차근** 설명합니다.
- **Part 5~8(11~18장)에서 추가로 가정**: FPGA 기초(LUT·FF·BRAM·DSP, RTL, clock). 이 project 사용자는 FPGA 경험이 있습니다. 이 배경이 없어도 1~10장(quantum 이론)은 그대로 읽을 수 있고, hardware 용어는 [15.7절 용어집](15_paper_map_and_design_decisions.md#157-hardware-용어집)에 모아 두었습니다.

> 이 정도 수학 배경이 없거나 오래 잊었다면, 먼저 [부록 A. 수학 빠른 복습](A_math_review.md) 을 보세요 — 이 해설서가 실제로 쓰는 complex number·linear algebra만 추려 두었습니다. 더 깊이 원하면 3Blue1Brown의 linear algebra 영상 시리즈와 complex number 기초를 권합니다. 원문 QCVC 에세이도 같은 배경을 가정합니다.

### 표기 약속

본 해설서는 이해를 돕기 위해 몇 가지 장치를 씁니다.

- **💡 비유 박스**: 추상적인 quantum 개념을 일상적인 비유로 풀어줍니다.
- **🔍 계산 따라가기**: 실제 vector·matrix 계산을 **한 줄 한 줄** 따라갑니다.
- **❓ 왜 이런가?**: 정의와 규칙의 이유·동기를 설명합니다.
- **⚠️ 흔한 오해 / 함정**: 처음 배울 때 헷갈리기 쉬운 지점을 짚습니다.
- **🔑 핵심**: 꼭 기억할 것.
- **✏️ 연습**: 스스로 확인해 볼 문제 (답은 [10장 cheat sheet](10_glossary_and_cheat_sheet.md) 또는 본문에).
- 수식은 LaTeX(`$...$`, `$$...$$`)로, state는 $|0\rangle$, $|\psi\rangle$ 처럼 ket으로 표기합니다.

### 다루지 않는 것

classical linear scan과의 속도 경쟁은 이 해설서의 주제가 아닙니다(5절). 그 밖에 두 가지 범위를 더 정해 둡니다. **minimum search는 주제가 아니라 확장입니다.** threshold를 계단처럼 낮춰 가며 minimum에 수렴시키는 Dürr–Høyer loop는 hardware에 넣지 않고 host firmware의 `while` 한 줄로 처리하기로 했습니다. 그래서 해설서에서도 [14.9절](14_multiple_solutions_and_minimum_search.md#149-확장--threshold를-낮추면-minimum-search) 한 절 분량입니다. superconducting·trapped-ion 같은 **quantum hardware의 물리**도 범위 밖입니다 — amplitude라는 숫자만 다루면 충분하다는 것이 [1.7절](01_qubits_and_states.md#17-물리적-실체는-잊어도-된다)의 결론입니다.

### 함께 보는 자료와 원문 출처

| 문서 | 위치 | 성격 |
|------|------|------|
| **학습 해설서 (본 문서)** | `study_references/` | 배경지식 + algorithm 해설 + 확정 설계, 읽고 배우는 **주교재** |
| 논문 해설본 | [../papers/papers_ko/](papers/papers_ko/) | 논문 6편의 한국어 해설, 원문 대조용 보조 자료 |
| 원문 논문·강의자료 | [../papers/](papers/) | 원본 PDF (기초이론 3편 + FPGA·응용 논문 6편) |
| 기술문서 | [../design_references/](../design_references/index.md) | 확정된 설계의 source of truth (RTL · port · CSR · 운용) |

해설서가 주교재이고 논문 해설본은 원문 대조용 보조 자료입니다. 그래서 각 장은 **자체 완결**이어야 하며, 해설본을 읽어야만 이해되는 서술을 남기지 않습니다.

이 해설서는 project `documents/study_references/papers/1. 양자컴퓨터 기초이론/` 의 세 자료를 학부생용으로 재구성·통합한 것입니다.

1. **Quantum Computing for the Very Curious** — Andy Matuschak & Michael Nielsen (quantum.country). qubit·gate·measurement·CNOT·entanglement·범용성의 기초. → 주로 1~6장.
2. **[양자컴퓨터 기초 이론] 5. 그로버 알고리즘과 도이치 알고리즘** — hgmin1159.github.io. oracle·amplitude amplification·Grover·Deutsch-Jozsa 개요. → 7~9장.
3. **양자 컴퓨팅 입문 (2) - Grover's Algorithm** — infossm.github.io (Samsung SW Membership). Grover의 엄밀한 유도(phase kickback·diffusion operator·geometric rotation·number of iterations). → 9장.

추가 참고 문헌: Sutor, R. (2019). *Dancing With Qubits*; Bernhardt, C. (2019). *Quantum Computing for Everyone*; Nielsen & Chuang, *Quantum Computation and Quantum Information*; Grover, L. K. (1996), *A fast quantum mechanical algorithm for database search*.

#### Part 5~8의 원문 — 논문 6편 (`papers/` 2·3·4번 directory)

Part 5~8은 아래 여섯 편을 설계 질문별로 가로질러 다룹니다. 각 편의 한국어 해설본과 원문 PDF 목록은 [논문 목록의 「보유 원문과 한국어 해설본」](papers/references.md#보유-원문과-한국어-해설본)에 있습니다(원문 대조용).

- **[04] Developing a Grover's Emulator on Standalone FPGAs** — Choi & W. Lee (중앙대), AIMS Math. 9(11), 2024. Grover 전용 최적화 4종 + RISC-V SoC. → 11·13장(설계도).
- **[05] Precision-aware Fixed-point Emulation of Grover's** — Choi 외, W. Lee 교신 (중앙대), Quantum Inf. Process. 25:214, 2026. truncation error 이론·minimum fraction bits 공식. → 12장.
- **[06] Standalone FPGA-Based QAOA Emulator** — Choi 외, W. Lee (중앙대), arXiv:2502.11316, 2025. 같은 골격의 QAOA emulator. → 11·13장(multiplier 대비).
- **[07] Towards Complete and Scalable Emulation (HPRC)** — El-Araby 외 (U. Kansas), IEEE TC 72(8), 2023. 외부 DDR로 32 qubits, C2Q initialization. → 11·12장(대조군).
- **[08] Generalized Grover's Algorithm for Multiple Phase Inversion States** — Byrnes, Forster, Tessler, PRL 120, 060501, 2018. diffusion operator 일반화. → [11.10절](11_state_vector_emulator.md#1110-emulator가-숨기는-것)(실기에서는 이득이지만 emulator에서는 손해가 되는 일반화) · [14.0절](14_multiple_solutions_and_minimum_search.md#140-기호-충돌-주의)(기호 충돌 주의).
- **[09] Quantum Minimum Searching for AUD in Wireless IoT** — Habibie 외 (INSA Lyon), IEEE IoT J. 11(12), 2024. Dürr–Høyer minimum search의 응용 사례. → [14.9절](14_multiple_solutions_and_minimum_search.md#149-확장--threshold를-낮추면-minimum-search) · [15장](15_paper_map_and_design_decisions.md)(**확장 참고 사례**로 강등 — 남는 것은 "oracle은 predicate를 판정한다"는 관점과 응용 사례 하나입니다).

여섯 편의 계보 바깥에서 설계 결정 하나의 근거가 되는 논문이 한 편 더 있습니다.

- **[BBHT] Tight bounds on quantum searching** — Boyer, Brassard, Høyer, Tapp (1998). solution이 몇 개인지 모르는 채 Grover를 돌리는 표준 절차(sampling range를 1에서 시작해 실패할 때마다 growth factor 6/5 = 1.2×로 키움)와 success probability lower bound의 **원전**. → [16.2절](16_iteration_control_and_checkpoints.md#162-bbht--무작위로-뽑는-number-of-iterations와-12-growth-factor). 09번 논문의 Algorithm 1·2도 이 절차를 옮겨 온 것이므로, **iteration schedule을 인용할 때는 09번이 아니라 1998년 원전을 인용하십시오.** 원문 PDF는 `papers/` 에 없습니다.

---

## 7. 학습 태도에 관한 한마디

원문 QCVC 에세이의 저자는 이렇게 말합니다:

> quantum computing을 이해하려면 반드시 **수학적 model에 익숙해져야 한다.** 화려한 비유 영상만으로는 몇 년을 봐도 진짜로 이해하지 못한다. 농구 이야기를 듣는 것과 실제로 농구를 하는 것이 다르듯이.

겁먹을 필요는 없습니다. 필요한 수학은 **complex number와 linear algebra(vector·matrix)** 뿐이고, 이 해설서는 계산을 한 줄씩 따라갑니다. 다만 눈으로만 읽지 말고, 종이에 직접 $H|0\rangle$ 을 계산해 보는 습관이 중요합니다.

💡 **비유**: 질문(연습문제)을 틀리는 것은 실패가 아니라 **가장 빠르게 배우는 순간**입니다. 어디를 모르는지 정확히 짚어주기 때문입니다. 틀린 부분을 찾아 다시 계산해 보세요.

---

## 8. 요약

- **computer의 기원**: Turing(1936)이 "algorithm=Turing machine이 하는 것"으로 정의 → 현대 computing의 토대.
- **Deutsch의 질문**: "모든 물리 system을 효율적으로 simulation하는 범용 장치가 있는가?" → classical computer는 quantum을 못 흉내 냄 → quantum computer의 탄생.
- **근본 강점**: 입자가 하나 늘 때마다 amplitude는 두 배. classical은 지수적으로 증가, quantum은 입자 수만큼의 qubit로 자연스럽게 담음.
- **잘하는 문제**: Shor(소인수분해, 지수적)·Grover(search, 이차)·quantum simulation. 만능은 아님.
- **이 project**: BRAM에 올린 data array에서 네 가지 predicate($<$·$>$·$=$·interval)를 만족하는 index를 찾아 주는 **Grover emulator IP**(Arty A7-100T + RVX SoC, 14 qubits). 하나를 돌려주거나 호출을 되풀이해 전부 enumeration합니다.
- **속도가 값어치가 아니다**: $O(\sqrt{\text{number of states}})$ 은 실제 quantum computer의 이야기이고, classical circuit으로 흉내 내면 classical linear scan보다 **느립니다.** 상대는 Qiskit `AerSimulator`·NumPy state vector code며, 이 IP의 값어치는 **결정적·재현 가능한 재현과 verification**에 있습니다.

다음 장에서는 이 모든 것의 출발점, **qubit** 가 정확히 무엇인지 — 왜 그 state가 "숫자"가 아니라 "vector"인지 — 부터 배웁니다.

---

> [1장 qubit와 state →](01_qubits_and_states.md)

<!-- HUMANIZE-SUMMARY -->
<!--
{
  "original_chars": 20847,
  "final_chars": 20860,
  "gate_change_rate": 0.0109,
  "grade": "A",
  "self_check": "6/6",
  "categories": [
    "A-18",
    "D-14",
    "D-2",
    "D-8"
  ],
  "highlights": [
    "진단 구간의 국소 윤문과 의미·용어 보존 확인"
  ],
  "remaining_findings": [],
  "baseline_gate_warning_count": 0,
  "finalize": "accept",
  "gate_exit_code": 0,
  "new_gate_warnings": 0
}
-->
