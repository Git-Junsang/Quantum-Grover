# 11장. state vector emulator — memory map과 resource 예산

> [← 10장 용어 정리와 cheat sheet](10_glossary_and_cheat_sheet.md) · [index](index.md) · [12장 amplitude를 숫자로 — fixed-point와 Q1.22 →](12_fixed_point_and_precision.md)
> **이 장을 읽기 위한 준비**: [1장 amplitude·superposition](01_qubits_and_states.md), [5장 tensor product·$2^{\text{number of qubits}}$ dimension](05_multiple_qubits_and_entanglement.md), [9장 Grover](09_grover_algorithm.md). FPGA 기초 용어(LUT·FF·BRAM·DSP)는 [15.7절 hardware 용어집](15_paper_map_and_design_decisions.md#157-hardware-용어집)에 모아 두었습니다.

---

10장까지 우리는 **quantum algorithm이 수학적으로 무엇을 하는지**를 배웠습니다. 이제 방향을 바꿉니다. 여기서부터(Part 5)는 그 algorithm을 **classical hardware(FPGA)로 흉내 내는 기계** — 이 project의 실제 목표물 — 를 만드는 과정입니다. 새로 배우는 논문은 여섯 편이고, 이 장은 그 여섯 편이 공유하는 **기본적인 질문 하나**에서 출발합니다: *quantum computer가 없는데 어떻게 quantum algorithm을 "돌린다"는 걸까요?*

답은 단순합니다. state는 결국 **숫자 array**(amplitude vector)이고, gate는 그 array에 가하는 **산술 연산**입니다. 진짜 quantum computer가 물리적으로 하는 일을, classical computer는 그 숫자 array를 memory에 펼쳐 놓고 계산으로 재현합니다. 이것이 **state vector emulation**이고, 이 장은 그 원리와 **비용**을 다룹니다. 비용을 알아야 이 방식으로 다룰 수 있는 qubit 수가 왜 제한되는지 알 수 있고, board에서 검증된 우리 IP가 실제로 몇 개의 BRAM과 몇 cycle을 쓰는지도 이 장에서 숫자로 확인합니다.

---

## 11.1 emulation·simulation·진짜 quantum computer

세 단어가 자주 뒤섞여 쓰이니 먼저 정리하겠습니다. 07번 논문(El-Araby 외, IEEE TC 2023)의 용법을 따릅니다.

- **진짜 quantum computer**: 물리적 qubit(초전도 circuit·이온 등)가 실제로 superposition·entanglement·interference를 겪습니다. amplitude는 어디에도 "저장"되지 않고 물리 state 그 자체입니다.
- **simulation**: software로 state vector를 계산합니다. 보통 CPU/GPU에서 Qiskit 같은 library로 돌립니다. 유연하지만 느립니다.
- **emulation**: **전용 hardware(FPGA)** 로 state vector 계산을 circuit 수준에서 가속합니다. simulation과 하는 일(숫자 array 계산)은 같지만, software가 아니라 **맞춤 datapath**로 처리한다는 점이 다릅니다.

셋 중 뒤의 둘은 **똑같이 classical computer가 숫자 array를 계산**합니다. 차이는 "얼마나 빠른 hardware로 하느냐"뿐입니다. 우리 project가 만드는 것은 세 번째 — **FPGA emulator**입니다.

우리 설계의 구체적인 구성을 먼저 살펴보겠습니다. 이 IP는 독립적으로 동작하는 chip이 아니라 **RVX SoC 안에 얹히는 accelerator**입니다. 제어 register(CSR)는 **APB slave**로 노출되어 RISC-V core가 명령·threshold·state를 읽고 쓰고, search 대상 data는 IP가 **AHB master**가 되어 직접 실어 옵니다. host는 **UART** 너머에서 RISC-V app에게 명령을 보낼 뿐, amplitude array를 한 칸도 만지지 않습니다. 즉 연산은 전부 IP 안에서 끝나고 host는 시작·정지·결과 회수만 합니다(자세한 것은 [17장](17_rvx_soc_integration.md)).

여기서는 emulator가 quantum computer가 아니라는 사실을 반드시 구분해야 합니다. **quantum 이득($O(\sqrt{\text{number of states}})$ 같은)을 물리적으로 누리지 못합니다.** Grover iteration 한 번이 이미 모든 amplitude를 두 번 훑으므로 총비용은 $O\big(\text{number of states}\cdot\sqrt{\text{number of states}/\text{number of solutions}}\big)$ 이고, 이것은 같은 문제를 classical program이 array 한 번 훑어 푸는 $O(\text{number of states})$ 보다 **느립니다.** 이 사실을 흐리지 마십시오 — 우리 IP를 classical linear scan과 나란히 놓고 속도를 자랑하는 문장은 이 해설서 어디에도 없습니다.

그럼 무엇과 비교해야 할까요. 같은 일을 하는 것, 즉 **state vector simulator**입니다. 구체적으로는 Qiskit의 `AerSimulator` 나 NumPy로 짠 state vector code가 우리의 비교 대상입니다. 그쪽도 모든 amplitude를 memory에 펼쳐 놓고 매 iteration 전부 훑으니, 우리와 같은 $O\big(\text{number of states}\cdot\sqrt{\text{number of states}/\text{number of solutions}}\big)$ 이 듭니다. 다만 그 일을 범용 CPU의 명령어로 하느냐 전용 datapath로 하느냐가 다를 뿐이죠. 같은 board 위에서 accelerator를 끄고 RISC-V core 하나로 같은 계산을 돌린 순수 software baseline도 정당한 대조군입니다([18.8절](18_reference_model_verification.md#188-잰-수치와-그-조건)). 그리고 이 IP의 값어치는 애초에 속도 우위가 아니라, **quantum algorithm의 동작을 결정적이고 재현 가능하게 재현·검증하는 전용 hardware**라는 데 있습니다. 같은 seed를 주면 같은 shot 수열과 같은 후보가 나오고, amplitude array는 언제든 덤프해 software reference model과 bit 단위로 대조할 수 있습니다([18장](18_reference_model_verification.md)). 실제 quantum computer에서는 둘 다 불가능한 일입니다.

한 가지 더 짚어 둘 것이 있습니다. 문헌에서 "FPGA로 quantum을 다룬다"는 말은 사실 두 방식으로 갈립니다 — FPGA 자체가 quantum computer 역할을 맡고 host가 거기에 접속해 쓰는 방식과, 무거운 state vector 연산만 FPGA로 떼어내 가속하는 보조 accelerator 방식입니다(Cicero 외 2025 survey). 우리 IP는 뒤쪽입니다. 용어에는 주의가 필요합니다. 이 survey는 앞의 것을 "emulation", 뒤의 것을 "acceleration"이라 불러, 07번을 따라 "emulation = FPGA 가속 simulation"으로 써 온 이 해설서와 이름이 정반대입니다. 문헌마다 같은 단어가 다른 것을 가리킬 수 있다는 점을 기억해 두세요.

---

## 11.2 세 개의 array — amp·data·mask

9장에서 Grover의 시작 state를 이렇게 썼습니다:

$$|\psi\rangle = H^{\otimes \text{number of qubits}}|0\rangle^{\otimes \text{number of qubits}} = \frac{1}{\sqrt{\text{number of states}}}\sum_{x=0}^{\text{number of states}-1}|x\rangle$$

이 ket을 hardware에서 계산하려면 hardware가 다루는 **memory에 담긴 숫자**로 표현해야 합니다. 그래서 emulator는 이 state를 **amplitude array**로 펼칩니다:

$$|\psi\rangle = \sum_{i=0}^{\text{number of states}-1}\alpha_i|i\rangle \;\longrightarrow\; \texttt{amp\_mem}[0..\text{number of states}-1] = [\alpha_0,\ \alpha_1,\ \dots,\ \alpha_{\text{number of states}-1}]$$

`amp_mem[i]` 는 computational basis state $|i\rangle$ 의 amplitude $\alpha_i$ 를 담는 memory 한 칸입니다. uniform superposition은 이 array의 **모든 칸을 $\frac{1}{\sqrt{\text{number of states}}}$ 로 채우는 것**과 정확히 같습니다.

그런데 우리 IP에는 array가 하나가 아니라 **셋**입니다. 우리가 푸는 문제가 추상적인 "표시된 state 찾기"가 아니라 **memory에 담긴 data 중 predicate를 만족하는 index 찾기**이기 때문입니다.

| array | data word width | 깊이 | 담는 것 | 누가 건드리나 |
|---|---|:-:|---|---|
| `amp_mem` | **23b** (Q1.22) | 16,384 | amplitude $\alpha_i$ | Init·oracle·diffusion operator가 **씁니다**. measurement는 읽기만 |
| `data_mem` | **16b signed** | 16,384 | search 대상 값 `value[i]` | host가 load. IP는 **읽기만** |
| `found_mask` | **1b** | 16,384 | 이미 찾은 solution 표시 `found[i]` | enumeration mode에서 solution이 하나 나올 때마다 한 bit씩 |

<img src="diagrams/11_memory_map.svg" width="760" alt="index 14 bits가 row 번호 9 bits와 lane 번호 5 bits로 갈리고, amplitude·checkpoint memory(checkpoint slot 4벌, RAMB36 44개)·data_mem(RAMB18 64개)·found_mask(RAMB36 2개)로 이어지며 Accelerator Core 합계 84 tile, board 전체 116/135 tile">

amplitude 폭을 왜 23 bits로 잡았는지는 [12장](12_fixed_point_and_precision.md)이 통째로 답합니다. 여기서는 array가 셋이라는 사실과, 그중 amplitude만 쓰기 대상이라는 사실만 기억해 두면 됩니다 — 뒤의 사실은 [16.5절](16_iteration_control_and_checkpoints.md#165-checkpoint--measurement가-읽기-전용이라는-사실에서) checkpoint의 근거가 됩니다. 하나 미리 적어 두면, 실제 chip 안의 `amp_mem` 은 한 벌이 아닙니다. amplitude array 여러 벌을 같은 memory에 두고 그중 하나에서 계산을 이어 가는 **checkpoint slot** 구조인데, 그 이유는 16장이 설명합니다.

이제 gate가 array 연산이 되는 모습을 봅니다. 9장에서 본 Grover 한 바퀴 $G = U_\psi U_f$ 는 다음과 같은 연산이 됩니다.

**oracle $U_f$.** 9장에서는 "solution index의 amplitude를 뒤집는다"고 썼습니다. 그것은 답을 이미 아는 사람의 서술입니다. 우리 circuit은 solution index를 **모릅니다.** circuit이 가진 것은 threshold와 predicate뿐이고, 하는 일은 이것입니다:

$$\texttt{amp\_mem}[i] \;\leftarrow\; -\,\texttt{amp\_mem}[i] \quad \text{if } \mathrm{pred}\big(\texttt{data\_mem}[i],\ \texttt{thr}\big)$$

predicate $\mathrm{pred}$ 는 네 종류입니다 — `value < thr_a`, `value > thr_a`, `value == thr_a`, 그리고 범위 `thr_a < value < thr_b`. predicate를 만족하는 칸이 하나일 수도 수백 개일 수도 있고, circuit은 **몇 개인지조차 모른 채** array 전체를 훑으며 칸마다 판정합니다. 이 명제 — **oracle은 solution을 아는 circuit이 아니라 predicate를 판정하는 circuit** — 는 해설서 전체에서 일관되게 따르는 설명이고, [14.2절](14_multiple_solutions_and_minimum_search.md#142-oracle은-solution을-아는-circuit이-아니다)에서 다시 다룹니다. predicate가 실제로 어떤 gate가 되는지는 [13.3절](13_oracle_diffusion_measurement_datapath.md#133-oracle--predicate-4종이-subtractor-하나를-공유한다)입니다.

**diffusion operator $U_\psi$.** 이쪽은 predicate와 무관하게 전 칸에 똑같이 걸립니다 — inversion about the mean `amp_mem[i] ← 2*mean - amp_mem[i]` 입니다. index를 가리지 않으므로 data를 볼 필요조차 없습니다.

즉 ket과 unitary matrix로 쓰던 모든 것이, emulator에서는 **array에 대한 산술**로 표현됩니다. Part 5 이후에는 이 대응 관계를 바탕으로 설명합니다.

---

## 11.3 qubit 하나 = memory 두 배

이 구조의 가장 중요한 성질은 **비용이 number of qubits에 지수적**이라는 것입니다. 5장에서 qubit가 여럿인 state의 dimension이 $2^{\text{number of qubits}}$ 임을 배웠습니다. amplitude를 명시적으로 펼치면, array 크기가 곧 number of states이고 $\text{number of states} = 2^{\text{number of qubits}}$ 입니다:

| number of qubits | number of states |
|:---:|:---:|
| 4 | 16 |
| 10 | 1,024 |
| **14** | **16,384** ← 우리 IP |
| 20 | 약 100만 |
| 30 | 약 10억 |

qubit를 **하나** 늘릴 때마다 저장해야 할 amplitude가 **두 배**가 됩니다. 진짜 quantum computer라면 qubit 하나를 추가하는 것이 state space를 두 배로 키우는 "공짜 지수 이득"이지만, emulator에서는 정반대로 **memory·연산이 두 배로 드는 지수 비용**입니다. qubit를 늘리는 것이 아니라 memory를 지수적으로 늘리는 구조인 셈이고, 이것이 emulator가 넘을 수 없는 근본 한계입니다.

엄밀히 말하면 이 지수 비용은 물리 법칙이 아니라 **우리가 택한 방식의 결과**입니다. 복잡도 이론에는 amplitude를 저장하는 대신 필요할 때마다 다시 계산해 memory를 number of qubits에 선형($O(s+t)$)으로 줄이는 공간–시간 맞바꿈이 알려져 있습니다(Frank 외 2009, SEQCSim). 다만 그 대가로 이번엔 **시간**이 지수적으로 늘어나고, 특히 Grover에는 불리합니다 — diffusion operator가 매 iteration amplitude **전체**의 mean을 요구하므로 결국 모든 amplitude가 동시에 필요하고, "한 번에 하나씩 재계산"하는 그 방식과 정면으로 충돌하기 때문입니다. 그래서 우리는 memory를 사용하는 state vector 전개를 택합니다 — 부담을 다른 resource로 옮길 수는 있어도, Grover accelerator에서는 그 맞바꿈이 손해입니다.

그래서 이 분야의 모든 논문은 사실상 **"이 지수 벽을 몇 qubit까지 미룰 수 있는가"** 의 경쟁입니다. 그리고 그 경쟁의 첫 갈림길이 바로 다음 절 — amplitude를 **어디에** 저장할 것인가입니다.

---

## 11.4 amplitude를 어디에 둘 것인가

FPGA에는 숫자를 저장할 곳이 여러 종류이고, 어느 곳을 고르느냐가 다룰 수 있는 qubit 수를 결정합니다. 여섯 논문과 우리 설계는 세 가지 저장 방식을 씁니다.

<img src="diagrams/11_storage_tradeoff.svg" width="640" alt="state vector 저장 방식의 세 storage layer: register / BRAM / 외부 DDR">

| 저장 위치 | 누가 | 접근 방식 | number of qubits |
|---|---|---|:---:|
| **register array**(FF/LUT) | 04, 06 | 모든 amplitude를 온칩 register에 — 한 cycle에 전부 병렬 접근 | **6** (04, Kintex) · **8~9** (06) |
| **온칩 BRAM** | **우리 IP** | 32칸짜리 row 단위로 저장하고 매 cycle 4 rows(128칸)씩 순차 streaming | **14** |
| **외부 DDR memory** | 07 | board에 붙은 대용량 DRAM에 — 순차 streaming | **32** |

세 방식의 차이는 **속도와 용량의 맞바꿈**입니다. register는 가장 빨라서(모든 칸을 같은 cycle에 읽고 씀) 연산을 극단적으로 병렬화할 수 있지만, FPGA에 register는 적으므로 금방 바닥납니다. 외부 DDR은 수 GB로 방대하지만 한 번에 몇 data word씩만 읽어 와야 해서 순차 처리를 강요합니다. 07번 논문이 32 qubits라는 압도적 규모를 달성한 것은 순전히 **외부 DDR4를 썼기 때문**입니다(16GB DIMM × 4). 04·06이 한 자릿수 qubit에 머문 것은 반대로 **전부 온칩 register에 저장했기 때문**이고요.

우리는 가운데를 골랐습니다. 이 선택의 이유를 먼저 살펴보겠습니다. **board에서 검증된 우리 IP에는 외부 DDR이 등장하지 않습니다.** 첫째, 14 qubits라면 세 array가 checkpoint slot까지 포함해 온칩에 전부 들어갑니다 — 용량이 충분하므로 외부에 둘 필요가 없고, DRAM controller와 그 latency를 감출 buffer 구조는 통째로 순수한 추가 비용입니다. 둘째, 그리고 이쪽이 더 결정적인데, 우리는 amplitude만이 아니라 **data array까지** 온칩에 둬야 합니다. oracle이 한 cycle에 128칸을 판정하려면 `value[i]` 128개가 amplitude 128칸과 **같은 cycle에** 나와야 하기 때문입니다. 외부 DRAM 한 channel로는 그런 접근을 줄 수 없습니다. (저장소에는 iteration마다 amplitude를 DRAM에 전량 저장하는 두 번째 variant인 DRAM Variant(`hardware_dram`)가 초안으로 있지만, 거기서도 계산 자체는 BRAM 위에서 하고 DRAM은 amplitude 보관 창고로만 씁니다. Board-Verified Build는 이 장이 다루는 BRAM Variant입니다.)

그 대가로 우리는 용량 예산을 빡빡하게 씁니다. 2026-09-07 implementation report에서 잰 실제 사용량은 이렇습니다(값의 source of truth는 [15.4절](15_paper_map_and_design_decisions.md#154-우리-project의-좌표--확정-설계-결정표)):

| block | 구성 | BRAM |
|---|---|--:|
| amplitude · checkpoint memory | state 한 벌 = 512 rows × 736-bit = RAMB36 11개. row phase 4 banks에 checkpoint slot 4벌 | RAMB36 44 |
| `data_mem` | 4 rows 동시 읽기용 | RAMB18 64 (= 32 tile) |
| `found_mask` | 16,384 × 1-bit, 4 rows 동시 | RAMB36 2 |
| measurement용 row-weight memory | 512 × 51-bit | RAMB36 2 |
| checkpoint policy memo table | 16장의 policy 표 | RAMB36 4 |
| **Accelerator Core 계** | | **84 tile** |
| RVX SoC | system SRAM 128 KB 가 대부분 | 32 tile |
| **board 전체** | | **116 / 135** |

board는 Arty A7-100T(`xc7a100tcsg324-1`)이고 BRAM tile(BRAM36)이 **135개** 있습니다. 116개를 쓰니 남는 것이 19개입니다. 여기서 qubit를 하나 늘리면 어떻게 될까요. state 한 벌이 두 배(RAMB36 22개)가 되어 checkpoint slot 4벌만 88개, `data_mem` 도 64 tile 로 불어나 Accelerator Core 계가 대략 160 tile, board 전체를 넘깁니다(구조를 그대로 둔 채 깊이만 두 배로 잡은 추정입니다). 즉 **이 구조와 이 board에서 14 qubits가 천장**입니다. 14 qubits로 굳힌 근거는 이 resource 계산 하나가 아니라 precision benchmark도 함께인데, 그쪽은 [12.7절](12_fixed_point_and_precision.md#127-몇-bit면-되나--minimum-fraction-bits-공식과-그-전제)에 있습니다.

> ⚠️ 여기서 흔히 하는 오해를 하나 짚고 갑니다. "register에 두니까 resource(LUT)가 터진다"는 설명은 **틀렸습니다.** 다음 절이 이 오해를 data로 반박합니다.

---

## 11.5 register의 진짜 대가

04번 논문은 qubit를 늘리며 FPGA resource 사용량을 실측했습니다. Kintex UltraScale+ board 기준으로, 4 qubits에서 6 qubits로 갈 때 두 resource가 이렇게 움직입니다:

| resource | 4 qubits | 6 qubits | 배율 |
|---|---:|---:|:---:|
| **FF**(flip-flop = 저장) | 16,606 | 19,852 | **1.20×** |
| **LUT**(lookup table = 연산 logic) | 15,386 | 303,993 | **19.8×** |

이 결과에서 원인을 구분할 수 있습니다. 만약 resource 폭발의 원인이 "amplitude를 register에 저장하는 것"이라면, **저장을 담당하는 FF가 폭증해야 합니다.** 그런데 FF는 겨우 1.2× 늘었습니다. 폭증한 것은 **LUT** — 즉 **연산 logic**입니다.

원인은 저장이 아니라 **병렬 연산 unit**입니다. 04번 논문은 $O(\text{number of states})$ 짜리 연산(amplitude 전체를 더하는 accumulation, 전체를 비교하는 measurement 등)을 **한두 cycle에 끝내려고** adder·comparator·shifter를 number of states에 비례해 통째로 펼쳐 놓습니다. qubit가 하나 늘면 number of states가 두 배가 되고, 그만큼 연산 unit도 두 배가 되어 LUT 사용량이 지수적으로 늘어납니다. 논문 스스로 "늘어난 연산 부담을 실행 시간이 아니라 hardware resource로 떠넘겼다"고 밝힙니다(이 맞바꿈은 11.7절에서 우리 선택과 나란히 놓고 다시 봅니다).

<img src="diagrams/11_lut_ff_growth.svg" width="560" alt="04번 논문 자원 증가: FF는 평평, LUT는 급등">

06번 논문(같은 연구실의 QAOA emulator)이 이 현상을 더 선명하게 보여줍니다. 8~9 qubits에서 한계에 부딪히는데, 그 시점에 **DSP(multiplier)는 전체의 3.8%밖에 안 쓰고** LUT가 먼저 100%를 넘겨 버립니다. multiplication resource에는 여유가 있는데 연산 logic routing이 한계에 이른 것입니다.

이 구분이 왜 중요할까요? 우리가 만약 "register 대신 BRAM에 두면 resource가 해결된다"고 착각하면 원인을 잘못 판단하기 때문입니다. BRAM에 두는 진짜 효과는 **저장 압박 해소**가 아니라, amplitude를 한꺼번에 병렬 접근할 수 없게 만들어 **연산을 순차화하도록 강제**하는 것입니다 — 그래서 병렬 unit이 줄고 LUT가 회수됩니다. 대가는 속도(cycle 증가)이고요. 즉 저장 위치 선택은 **저장 용량 문제가 아니라 병렬성 예산 문제**입니다. 우리 IP의 resource 기록이 이것을 그대로 보여 줍니다 — iteration 한 번에 협력하는 PE를 1 PE에서 4 PEs로 늘렸을 때(16장), memory는 그대로인데 Accelerator Core의 LUT가 13,804에서 30,294로 2.2× 뛰었습니다(synthesis 기준). 병렬도를 높이면 logic 사용량도 늘어납니다.

---

## 11.6 memory-bound의 두 얼굴 — 용량과 port

07번 논문의 핵심 주장이자 이 분야를 관통하는 진단입니다. **memory-bound**란, 계산의 속도가 산술 능력이 아니라 **memory에서 data를 꺼내 오는 능력**에 제한되는 상황을 뜻합니다.

비유하자면 이렇습니다. 요리사(연산 unit)를 아무리 늘려도, 재료(amplitude)를 냉장고(memory)에서 꺼내 오는 문 하나가 좁으면 요리 속도는 그 문이 결정합니다. emulator에서 diffusion operator 한 번은 모든 amplitude를 읽어야 하는데, number of states가 지수적으로 크니 결국 "amplitude를 얼마나 빨리 실어 나르느냐"가 전체 속도를 지배합니다. multiplier(DSP)를 더 넣는 것은 속도 개선으로 이어지지 않는 경우가 많습니다 — 06번에서 DSP가 3.8%만 쓰인 것도 같은 이야기입니다.

이 진단에 대한 최근의 응답은 "bandwidth 자체를 높이자"입니다. 07번이 외부 DDR4에서 "memory-bound다"로 멈춘 지점을, 2026년 C-DAC의 Alveo U55C implementation(Tiwari 외)은 이 제약을 완화합니다 — DDR4보다 약 10× 빠른 **HBM**(high-bandwidth memory, 460 GB/s)을 16 banks로 나누고, amplitude $i$ 를 `i mod 16` 번째 bank에 분산해(연속된 amplitude를 서로 다른 bank로) 병렬로 읽습니다. 이렇게 30 qubits(amplitude 약 10.7억 개, 8 GB)를 단일 FPGA에서 돌렸습니다. 특히 눈길을 끄는 것은 이들이 관측한 **성능 절벽**입니다 — 12 qubits에서 13 qubits로 넘어가는 순간 state vector가 온칩 BRAM을 넘쳐 HBM으로 밀려나며 실행 시간이 81% 튑니다. 11.4에서 개념으로만 이야기한 "storage layer의 경계"가 benchmark graph에 그대로 찍힌 셈입니다. (다만 이 논문은 Grover 전용이 아닌 범용·complex number simulator이고 아직 비심사 preprint이며, number of qubits 자체는 07번의 32를 넘지 않습니다 — 새로운 것은 규모가 아니라 HBM이라는 storage layer와 bank 병렬 구조입니다.)

그렇다면 우리는 어떨까요. 우리 IP는 계산 중에 외부 memory를 쓰지 않으므로 **bandwidth는 병목이 아닙니다.** 온칩 BRAM은 요청한 cycle에 답을 줍니다. 그 대신 memory-bound는 서로 다른 두 가지 제약으로 나타납니다.

**첫째는 용량 천장입니다.** Accelerator Core가 84 tile, SoC가 32 tile로 board 135 tile 중 116 tile을 씁니다(11.4). qubit 하나가 memory 두 배이므로 15 qubits는 곧바로 예산 밖입니다. 07번이 "온칩 resource에만 의존해서 2~7 qubits에 갇혔다"고 지적한 그 한계가 우리에게도 적용됩니다. 다만 register 대신 BRAM에, 그것도 23-bit amplitude 셋을 69-bit 폭에 빈틈없이 담아(12.8절) 상한을 14까지 높인 것이고, **number of qubits의 상한을 정하는 것은 연산 circuit이 아니라 memory 용량**이라는 구조는 똑같습니다. 우리 경우는 checkpoint slot(16장)이 amplitude array를 여러 벌 요구하기 때문에 이 천장이 한층 더 빨리 옵니다.

**둘째는 port 천장입니다.** BRAM 하나에는 port가 둘뿐입니다. 한 cycle에 amplitude 128칸을 읽고 쓰고 싶으면 방법이 하나뿐입니다 — array를 여러 개의 독립된 block로 쪼개 폭을 넓히는 것. 즉 우리 병렬도의 상한을 정하는 것도 adder 개수나 DSP가 아니라 **memory의 number of ports와 port width**입니다. "multiplier를 늘려도 소용없다"는 07번의 진단이 우리 조건에서는 **"lane을 늘리려면 memory를 넓혀야 하고, 폭을 넓히면 필요한 BRAM 개수가 늘어난다"** 로 번역됩니다. 다음 절이 그 계산입니다.

---

## 11.7 병렬도와 banking

우리 IP는 amplitude를 **row** 단위로 다룹니다. 한 row는 연속된 index **32개**, 곧 **32 lanes**이고, row 하나의 32칸이 한 번에 읽히고 한 번에 써집니다. index를 row와 lane으로 나누는 규칙은 가장 단순한 것을 씁니다 — **index의 하위 5 bits가 lane 번호, 상위 9 bits가 row 번호**입니다(14 qubits):

$$i = \underbrace{\texttt{row}[8{:}0]}_{\text{row } 0\ldots511} \ \Vert\ \underbrace{\texttt{lane}[4{:}0]}_{\text{lane } 0\ldots31}$$

이렇게 잘라 두면 array를 훑는 일이 row 번호 counter 하나로 끝납니다. row $r$ 를 읽으면 index $32r \ldots 32r+31$ 이 한꺼번에 나오고, 두 lane이 서로 다른 address를 동시에 원하는 일이 원리적으로 일어나지 않으니 **충돌이 0**입니다.

row 하나는 memory data word 하나입니다. amplitude 32칸 × 23-bit = **736 bits**짜리 data word죠. BRAM 한 개는 이렇게 넓은 data word를 담지 못하므로 여러 개를 옆으로 붙입니다. 7 시리즈의 RAMB36은 한 port를 최대 72-bit 폭으로 쓸 수 있고, 23-bit lane 셋이 69 bits라 거기에 딱 들어갑니다. 그래서 32 lanes는 RAMB36 **11개**(3 lanes짜리 10개 + 2 lanes짜리 1개)에 담기고, 이것이 amplitude state 한 벌의 값입니다.

여기에 한 겹이 더 붙습니다. final configuration은 Grover iteration 한 번 안에서 **4 PEs**(PE 하나가 32 lanes)가 협력해 **한 cycle에 4 rows**를 처리합니다. 4 rows를 동시에 읽으려면 row들을 **row phase**로 나눠 네 개의 bank에 흩어 둡니다 — row 번호의 하위 2 bits가 bank를, 나머지 7 bits가 bank 안 address를 정합니다. cycle $c$ 에는 네 bank가 모두 같은 address $c$ 를 읽어 row $4c, 4c+1, 4c+2, 4c+3$ 이 한꺼번에 나옵니다. 512 rows가 128 cycles에 끝나고, 여기서도 충돌은 원리적으로 0입니다.

다른 simulator에서는 "충돌 0"을 만들기 위해 추가 비용이 듭니다. 범용 gate simulator는 임의의 qubit에 임의의 gate를 걸어야 하므로 amplitude를 bank 사이로 **재배치**해야 하고, 그러려면 crossbar나 permutation network가 필요합니다. Belfore(2024)의 확장형 FPGA architecture는 그 **Beneš permutation network 하나에 전체 logic의 36%** 를 씁니다. 우리는 그 36%를 통째로 쓰지 않습니다. Grover의 두 연산이 둘 다 index 순서를 건드리지 않는 **순차 streaming**이기 때문입니다 — oracle은 index $i$ 의 amplitude를 index $i$ 의 data로 판정하고, diffusion operator는 모든 칸에 같은 값을 적용합니다. algorithm의 규칙성 덕분에 이 project에서는 적은 비용으로 logic를 절약합니다.

row 구조는 resource 계산도 바꿉니다. [12.8절](12_fixed_point_and_precision.md#128-data-word와-bram-환산)의 표는 **용량**만 센 것이었는데, 실제로 잡히는 BRAM 개수는 data word를 몇 개로 쪼갰느냐가 함께 정합니다. state 한 벌이 RAMB36 11개인 것은 폭(736 bits)이 정한 값이고, 깊이 512 rows는 RAMB36 한 개의 깊이(72-bit 폭에서 512)와 딱 맞습니다. 그래서 **13 qubits나 12 qubits로 낮춰도 개수가 줄지 않습니다** — 512 rows가 256 rows·128 rows로 줄 뿐 폭은 그대로라, BRAM을 절반만 채운 채 11개를 그대로 사용하기 때문입니다. resource 계산을 지배하는 것이 number of states가 아니라 **폭(number of lanes × data word width)** 인 범위인 셈이고, resource까지 아끼며 축소하려면 number of qubits가 아니라 **number of lanes를 함께 낮춰야** 합니다.

마지막으로 04번 논문과의 차이를 살펴보겠습니다. 11.5에서 본 04번의 전략은 연산 unit을 **number of states에 비례해 펼치는 것**이었습니다. 64 states(6 qubits) 이하에서만 성립하는 architecture입니다. 14 qubits에 그대로 적용하면 adder·comparator를 16,384벌 펼치라는 뜻이고, LUT 19.8× 곡선을 그대로 연장하면 어떤 FPGA로도 불가능합니다. 우리는 정반대를 택했습니다 — unit을 number of states가 아니라 **constant 128개**(32 lanes × 4 PEs)만 두고 array를 $\text{number of states}/128$ cycles에 걸쳐 흘려 보냅니다. 그러면 logic resource는 number of qubits와 **무관하게 일정**하고, 늘어나는 것은 시간뿐입니다. 04번이 시간을 resource로 바꿨다면 우리는 resource를 시간으로 되바꾼 것이고, 그 시간이 얼마인지가 다음 절입니다.

---

## 11.8 cycle 비용 model

병렬도를 정하고 나면 이 IP의 시간은 전부 **pass** 단위로 셀 수 있습니다. pass 하나는 array를 처음부터 끝까지 한 번 훑는 것입니다. 1 PE면 한 cycle에 1 row라 512 cycles, final configuration(4 PEs)이면 한 cycle에 4 rows라 128 cycles입니다.

실제 cycle은 이 이상값에 pipeline 채우기·mean 확정·measurement 같은 고정비가 붙습니다. 그래서 여기서는 이론값 대신, 500 workloads RTL campaign(Six-Stage Ablation, 16.3절)의 총 cycle을 "number of iterations × iteration당 비용 + number of shots × shot당 비용 + constant"라는 직선에 맞춘 값을 적습니다. coefficient of determination $R^2$ 가 모든 configuration에서 0.99 이상이라 이 model이 실제 cycle을 거의 그대로 설명합니다.

| 단위 | Stage 1 (1 PE, measurement 최적화 없음) | final configuration | 근거 |
|---|--:|--:|---|
| pass 1회 (array 한 번 훑기) | 512 | 128 | 512 rows ÷ cycle당 rows |
| **Grover iteration 1회 = 2 passes + 고정비** | **≈ 1,033** | **≈ 268** | [13.6](13_oracle_diffusion_measurement_datapath.md#136-왜-2-passes인가) · campaign 직선 맞춤 |
| shot 1회의 나머지 (Init·measurement·solution check·policy) | ≈ 1,327 | ≈ 354 | [14.5](14_multiple_solutions_and_minimum_search.md#145-2단-병렬-measurement) · campaign 직선 맞춤 |

iteration 하나가 왜 하필 두 pass인지는 [13.6절](13_oracle_diffusion_measurement_datapath.md#136-왜-2-passes인가)의 주제입니다. 짧게만 적으면, diffusion operator가 요구하는 mean은 **모든 amplitude를 다 더해야** 나오므로 "전부 읽어 더하는 pass"와 "그 값으로 되쓰는 pass"가 순서상 겹칠 수 없습니다. oracle은 이 model에서 **별도의 항이 아닙니다** — Pass 1이 amplitude를 읽어 되쓰는 김에 predicate 판정 결과대로 sign을 뒤집으므로 cycle을 더 쓰지 않습니다.

여기까지가 **한 shot** 안쪽의 비용입니다. 그런데 Grover는 몇 번 돌릴지를 미리 알 수 없고(number of solutions를 모르기 때문입니다), 그래서 실제 실행 시간에는 **number of shots가 곱해집니다.** 이 multiplication이 [16장](16_iteration_control_and_checkpoints.md)의 주제입니다. 결과만 미리 적어 두면, 14 qubits · 1 solution인 100 workloads에서 mean **22.7 shots**(median 23)가 들고, requested iterations가 mean 173.5 iterations입니다. 매 shot 처음부터 도는 Restart mode는 그 173.5 iterations를 전부 물리적으로 돌려 mean 209,277 cycles(100 MHz에서 약 2.1 ms)이고, final configuration은 checkpoint 덕에 executed iterations를 mean 51.9 iterations로 줄이고 4 PEs와 measurement 최적화까지 더해 mean 25,345 cycles(약 0.25 ms)입니다. 이 값은 **RTL cycle 축**입니다 — board에서 잰 wall-clock time은 다른 축이라 섞어 speedup을 만들면 안 됩니다(18.8절). 그리고 이 숫자가 "data를 고전적으로 한 번 훑는 비용"(128 rows를 읽는 128 cycles 남짓)보다 훨씬 크다는 사실도 함께 봐야 합니다(11.1). 우리의 목표는 속도 우위를 내세우는 데 있지 않습니다.

---

## 11.9 emulator가 실기보다 쉬운 것들

emulator는 진짜 quantum computer의 흉내이지만, 어떤 면에서는 **진짜보다 훨씬 편합니다.** 실제 quantum computer에서 값비싼 여러 연산이, classical array 계산에서는 공짜에 가깝기 때문입니다. 이 역설은 응용 논문(08·09)을 읽을 때 특히 중요하니 미리 정리해 둡니다.

- **phase 반전.** 실기에서 특정 computational basis state의 phase만 뒤집으려면 multi-controlled $Z$ gate가 필요하고, 이는 qubit가 늘수록 비싸집니다(08번 논문이 다루는 일반화된 phase 반전은 별도의 보조 circuit block까지 요구합니다). emulator에서는 sign을 뒤집는 two's complement negate 한 줄이 전부입니다([13.4절](13_oracle_diffusion_measurement_datapath.md#134-sign-반전--twos-complement-negate-한-번)). 다만 "그래서 1 cycle에 끝난다"고 쓰면 틀립니다 — 우리 oracle은 solution index를 모르므로 **모든 칸을 훑으며 predicate를 판정**해야 하고, 128 lanes로도 16,384 / 128 = 128 cycles입니다. 정확한 서술은 "gate 비용이 사라지고 scan 비용만 남는다"이고, 그 scan이 diffusion operator의 accumulation pass와 같은 pass라 **oracle이 따로 더 쓰는 cycle은 없습니다**(11.8).
- **되돌리기(uncomputation).** 실기에서는 ancilla qubit를 쓴 뒤 entanglement를 풀려고 circuit을 **역순으로 다시 실행**해야 합니다(09번 논문의 oracle은 $A_f\to N_f\to U_\delta$ 를 걸고 다시 역순으로 풀어 circuit depth가 두 배가 됩니다). emulator에서는 그냥 array를 **덮어쓰면** 끝이라 되돌리기 자체가 불필요합니다.
- **ancilla qubit와 phase kickback.** 7장에서 본 phase kickback은 $|-\rangle$ state의 ancilla qubit가 있어야 성립합니다. 실기에서는 이 ancilla qubit를 실제로 마련하고 관리해야 하지만, emulator에서는 "sign을 뒤집는다"는 **결과만 array에 직접 쓰면** 되므로 ancilla qubit가 필요 없습니다.
- **state initialization.** 07번 논문은 논문의 **절반가량을 "classical data를 state로 싣는(Classical-to-Quantum, C2Q)" 문제**에 씁니다. 임의의 data를 amplitude로 encoding하는 circuit이 algorithm 본체보다 깊어질 만큼 어려운 문제이기 때문입니다. 그런데 Grover의 초기 state는 **uniform superposition** — 모든 칸을 같은 값으로 채우는 `memset` 한 번입니다. Grover는 이 최대 난제를 **구조적으로 우회**합니다.
- **중간 state 관찰.** 실기에서 계산 도중 state를 들여다보면 measurement가 되어 superposition이 collapse합니다(4장). emulator에서는 array를 언제든 덤프해 볼 수 있어 debugging이 자유롭고, 이것이 11.1에서 말한 "verification 가능성"의 실체입니다.

이 마지막 항목에는 **일부러 사용하지 않는 간단한 방법**이 있습니다. oracle 직후의 amplitude array에서 sign이 음수인 칸이 곧 solution 집합이므로, 그 array를 한 번 훑기만 하면 iteration도 measurement도 없이 solution을 **전부** 얻을 수 있습니다. 이것은 Grover가 아니라 classical scan이고, 그 사실이 바로 [11.10절](#1110-emulator가-숨기는-것)이 말하는 왜곡의 극단입니다. 그래서 이 경로는 **동작 경로에 넣지 않습니다.** 실기라면 measurement 전까지 amplitude를 볼 수 없고 measurement하면 collapse하므로, 우리도 그 제약을 스스로 지켜야 재현한 것이 algorithm이 됩니다 — 결과가 밖으로 나가는 길이 measurement 한 곳뿐이고, 중간 amplitude는 verification용 덤프로만 꺼내는 이유가 이것입니다.

---

## 11.10 emulator가 숨기는 것

편한 만큼 위험도 있습니다. emulator는 실기의 **gate 비용을 왜곡**합니다. 방금 본 것처럼 multi-controlled $Z$ gate가 emulator에서는 XOR 한 줄로 보이니, 실기라면 엄청나게 비쌀 circuit이 값싸 보입니다. 그래서 **emulator로 "algorithm의 논리가 맞다"는 것은 검증할 수 있어도, "이 circuit이 실기에서 실현 가능하다"는 것은 검증하지 못합니다.** emulator가 재현하는 것은 algorithm의 수학이지 물리적 gate 예산이 아닙니다.

그리고 이 역설에는 **반대 방향**도 있습니다. 실기에서 값싼 trick이 emulator에서는 오히려 손해가 되는 경우입니다. 08번 논문(Byrnes 외, PRL 2018)은 diffusion operator 연산을 여러 solution state로 **일반화**한 $G = I - 2P_S$ 를 제안합니다. 실제 quantum computer에서는 이 일반화가 gate를 아껴 주는 좋은 아이디어입니다. 하지만 emulator에서 이 일반화된 projector $P_S$ 를 계산하려면 모든 state 각각에 대해 $D$ dimension inner product를 해야 해서 $O(\text{number of states}\cdot D)$ 짜리 multiply-accumulate와 $\text{number of states}\cdot D$ data words의 추가 저장이 듭니다 — **순수한 손해**입니다.

그래서 08번 논문의 일반화 diffusion operator는 우리에게 **implementation 대상이 아니라, "왜 우리는 표준 diffusion operator 하나($a\mapsto 2\bar a - a$)를 고수하는가"의 근거**입니다. 표준 diffusion operator는 multiplication 없이 accumulation·shift·subtraction만으로 끝나거든요([13.5절](13_oracle_diffusion_measurement_datapath.md#135-diffusion-operator--2mean--amp가-circuit이-되는-순간)·[13.8절](13_oracle_diffusion_measurement_datapath.md#138-multiplier는-어디에-있고-어디에-없는가)).

**한 문장으로: 실제 quantum computer에서 싼 것이 emulator에서 비싸고, 그 반대도 참입니다.** 이 감각을 갖고 논문을 읽어야, 어떤 아이디어를 우리 설계에 가져오고 어떤 것을 버릴지 판단할 수 있습니다.

---

## 11.11 이 장의 요약

- **emulator**는 state vector를 숫자 array로 펼쳐 classical hardware로 계산하는 기계입니다. quantum 이득을 누리지 못하며, 총비용 $O\big(\text{number of states}\cdot\sqrt{\text{number of states}/\text{number of solutions}}\big)$ 은 classical linear scan보다 **느립니다.** 비교 대상은 Qiskit `AerSimulator`·NumPy state vector simulator와 같은 board의 순수 software baseline이고, 값어치는 속도가 아니라 **결정적·재현 가능한 verification**에 있습니다.
- 우리 IP는 **RVX SoC의 APB slave(CSR) + AHB master(DMA)** 이고, host는 UART 너머에서 명령만 내립니다([17장](17_rvx_soc_integration.md)).
- array는 셋입니다 — `amp_mem`(23b, 쓰기 대상, 실제로는 checkpoint slot 여러 벌) · `data_mem`(16b signed, 읽기 전용) · `found_mask`(1b, enumeration용). oracle은 `amp[i] ← −amp[i] if pred(value[i], thr)` 이고 **solution index를 모릅니다.**
- qubit 하나 = memory 두 배. 14 qubits에서 Accelerator Core가 **84 tile**, board 전체가 **116 / 135 tile**(2026-09-07 implementation report)이고, 이 구조에서 15 qubits는 예산 밖입니다.
- "register라서 resource가 터진다"는 **틀렸습니다.** FF는 1.20×, LUT는 19.8× — 원인은 저장이 아니라 **병렬 연산 unit**입니다. 저장 위치 선택은 용량 문제가 아니라 **병렬성 예산** 문제입니다.
- 우리의 **memory-bound는 bandwidth가 아닙니다.** (a) BRAM 용량 천장, (b) BRAM의 number of ports와 port width = 병렬도의 상한 — 두 얼굴로 나타납니다.
- **row = 32 lanes**, index 하위 5 bits가 lane, 상위 9 bits가 row. row 하나(736 bits)가 RAMB36 11개에 담기고, 4 PEs가 row phase 4 banks에서 한 cycle에 4 rows를 읽습니다. 순차 streaming이라 **충돌 0**이고 범용 simulator가 logic 36%를 쓰는 **Beneš permutation network를 통째로 회피**합니다.
- **비용 model**(500 workloads campaign 직선 맞춤): iteration 1회 ≈ 1,033 cycles(1 PE) → **≈ 268 cycles**(4 PEs), shot 1회의 나머지 ≈ 1,327 → **≈ 354 cycles**(final configuration). 여기에 number of shots가 곱해집니다 — 14 qubits·1 solution이면 mean 22.7 shots, final configuration에서 mean 약 **0.25 ms**(RTL cycle 축, [16장](16_iteration_control_and_checkpoints.md)).
- emulator는 실기의 여러 난제(multi-controlled $Z$, uncompute, ancilla, C2Q initialization)를 **공짜로** 우회하지만, 실기의 gate 비용도 **숨깁니다.** 그리고 반대로, 08의 일반화 diffusion operator처럼 실기에서 좋은 trick이 emulator에서는 손해가 되기도 합니다.

다음 장에서는 array의 각 칸 — amplitude 하나 — 를 **실제로 몇 bit의 어떤 숫자로 담을 것인가**를 파고듭니다. fixed-point와 Q1.22, 즉 이 datapath의 가장 실무적인 첫 결정입니다.

---

> [← 10장 용어정리와 치트시트](10_glossary_and_cheat_sheet.md) · [index](index.md) · [12장 amplitude를 숫자로 →](12_fixed_point_and_precision.md)

<!-- HUMANIZE-SUMMARY -->
<!--
{
  "original_chars": 25858,
  "final_chars": 25842,
  "gate_change_rate": 0.0169,
  "grade": "A",
  "self_check": "6/6",
  "categories": [
    "D-14",
    "D-2",
    "D-5",
    "D-8"
  ],
  "highlights": [
    "가능성 표현과 원문의 교육적 권고를 그대로 보존",
    "추가 logic가 전혀 없다는 강화된 주장을 원문의 적은 비용이라는 의미로 복구"
  ],
  "remaining_findings": [],
  "baseline_gate_warning_count": 0,
  "finalize": "corrected",
  "gate_exit_code": 0,
  "new_gate_warnings": 0
}
-->
