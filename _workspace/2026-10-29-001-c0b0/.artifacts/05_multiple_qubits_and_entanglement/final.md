# 5장. multi-qubit와 entanglement

> [← 4장 measurement](04_measurement.md) · [index](index.md) · [6장 quantum circuit model과 universality →](06_quantum_circuit_model_and_universality.md)
> **이 장을 읽기 위한 준비**: [1장](01_qubits_and_states.md) state·superposition, [3장](03_single_qubit_gates.md) gate, [4장](04_measurement.md) measurement.

---

지금까지는 qubit 하나만 다뤘습니다. 하지만 유용한 계산을 하려면 여러 qubit가 필요하고, qubit들이 **서로 상호작용**해야 합니다. 이 장에서는 여러 qubit의 state가 어떻게 표현되는지(qubit가 하나 늘 때마다 dimension이 두 배가 됩니다), qubit를 상호작용시키는 **CNOT gate**, 그리고 순수 quantum 현상인 **entanglement**를 배웁니다. 이렇게 지수적으로 커지는 dimension이 바로 [0장](index.md)에서 말한 quantum computer의 힘의 원천이며, [9장 Grover](09_grover_algorithm.md)가 qubit 몇 개로 $2^{\text{number of qubits}}$ 개 항목을 한꺼번에 다루는 근거입니다.

---

## 5.1 두 qubit의 state — 네 개의 computational basis

qubit 하나의 computational basis는 $|0\rangle, |1\rangle$ 둘이었습니다. qubit **둘**이면 classical bit 2개처럼 네 가지 조합이 가능합니다:

$$
|00\rangle, \quad |01\rangle, \quad |10\rangle, \quad |11\rangle
$$

그리고 이들의 임의의 superposition도 가능합니다:

$$
|\psi\rangle = \alpha|00\rangle + \beta|01\rangle + \gamma|10\rangle + \delta|11\rangle
$$

amplitude $\alpha, \beta, \gamma, \delta$ 는 complex number이고, normalization condition은 마찬가지로:

$$
|\alpha|^2 + |\beta|^2 + |\gamma|^2 + |\delta|^2 = 1
$$

measurement하면 네 결과 00, 01, 10, 11 중 하나가 각각 $|\alpha|^2, |\beta|^2, |\gamma|^2, |\delta|^2$ 의 probability로 나옵니다([4장 Born rule](04_measurement.md)의 자연스러운 확장).

---

## 5.2 $2^{\text{number of qubits}}$ — 지수적으로 커지는 state space

일반적으로 qubit가 여러 개면 computational basis state는 **$\text{number of states} = 2^{\text{number of qubits}}$** 개입니다.

| number of qubits | number of states | 예                                  |
| :------------: | :-----------------: | :---------------------------------- |
|       1       |          2          | $\|0\rangle, \|1\rangle$          |
|       2       |          4          | $\|00\rangle, ..., \|11\rangle$   |
|       3       |          8          | $\|000\rangle, ..., \|111\rangle$ |
|       10       |        1,024        |                                     |
|      300      |     $2^{300}$     | 우주의 원자 수보다 많음             |

qubit 여러 개의 state를 완전히 기술하려면 $2^{\text{number of qubits}}$ 개의 complex amplitude가 필요합니다. 이것이 [0장](index.md)에서 말한 핵심입니다: **300 qubits면 classical computer가 도저히 저장할 수 없는 수의 amplitude를 자연스럽게 담습니다.**

> 🔑 **핵심 — 이것이 quantum parallelism의 근원**: 모든 qubit에 각각 $H$ gate를 걸면([6장](06_quantum_circuit_model_and_universality.md)) $2^{\text{number of qubits}}$ 개 computational basis state가 **전부 동시에** 담긴 uniform superposition이 만들어집니다. oracle 한 번으로 이 state 전부를 한꺼번에 처리하는 것이 [9장 Grover](09_grover_algorithm.md)의 출발점입니다. 3 qubits = 8 states, ..., search space $\text{number of states} = 2^{\text{number of qubits}}$.

### 3-qubit 예제 (원문 notation)

원문에서 3 qubits uniform superposition을 이렇게 씁니다:

$$
|\psi\rangle = \sum_{x=0}^{7} \frac{1}{\sqrt8}|x\rangle = \frac{1}{\sqrt8}\big(|000\rangle + |001\rangle + \cdots + |111\rangle\big)
$$

여덟 state가 모두 amplitude $\frac{1}{\sqrt8}$ 로 동등하게 담깁니다. ($\frac{1}{\sqrt8} = \frac{1}{\sqrt{2^3}}$, normalization: $8 \times \frac18 = 1$.) [9장](09_grover_algorithm.md)에서 이 state가 Grover의 시작점이 됩니다.

amplitude가 complex number라는 것은 **일반적인** state의 이야기입니다. 우리가 만들 emulator는 표준 Grover 하나만 돌리는데, 그 algorithm의 연산 과정 — uniform superposition에서 출발해 sign을 뒤집고 inversion about the mean을 하는 것 — 에서는 amplitude가 항상 real number로 유지됩니다. 그래서 amplitude 하나당 real part·imaginary part 두 칸을 잡을 필요 없이 **real-valued fixed-point 한 벌**만 저장합니다. 여기서는 결론만 알아 두고, 이 성질이 성립하는 세 조건은 [9.8절](09_grover_algorithm.md#98-전체-그림-정리--amplitude는-왜-real-number뿐인가)에서 설명합니다. 다만 이 저장 방식에는 제약이 있어서, amplitude에 complex phase를 직접 곱하는 기법을 얹는 순간 datapath를 complex number에 맞게 다시 설계해야 합니다 — solution이 몇 개인지 세는 표준 기법인 quantum counting(phase estimation)을 설계에서 제외한 이유가 그것입니다([16.1절](16_iteration_control_and_checkpoints.md#161-왜-solution이-몇-개인지-모르는가)).

---

## 5.3 tensor product — 두 qubit를 합치기

qubit 두 개를 각각 $|a\rangle = \alpha|0\rangle + \beta|1\rangle$, $|b\rangle = \gamma|0\rangle + \delta|1\rangle$ 로 준비한 뒤 나란히 놓으면, 합쳐진 state는 **tensor product**로 계산됩니다. 그냥 distributive law처럼 전개하면 됩니다:

$$
|a\rangle \otimes |b\rangle = (\alpha|0\rangle + \beta|1\rangle)(\gamma|0\rangle + \delta|1\rangle) = \alpha\gamma|00\rangle + \alpha\delta|01\rangle + \beta\gamma|10\rangle + \beta\delta|11\rangle
$$

notation: $|0\rangle|0\rangle$, $|0\rangle\otimes|0\rangle$, $|00\rangle$ 은 모두 같은 뜻입니다. 여러 gate를 여러 qubit에 동시에 적용할 때도 tensor product를 씁니다. 예를 들어 $H^{\otimes \text{number of qubits}}$ 는 "모든 qubit 각각에 $H$" 를 뜻하며([6장](06_quantum_circuit_model_and_universality.md)), Grover와 Deutsch-Jozsa의 첫 단계입니다.

💡 **비유**: tensor product는 "각 qubit가 독립적으로 가질 수 있는 state를 Cartesian product처럼 전부 나열"하는 것입니다. qubit가 늘수록 조합이 곱으로 불어나 $2^{\text{number of qubits}}$ 이 됩니다.

---

## 5.4 CNOT gate — qubit를 상호작용시키기

single-qubit gate만으로는 qubit들이 서로 영향을 못 줍니다. 계산하려면 **two-qubit gate**가 필요합니다. 대표가 **CNOT(controlled-NOT)** 입니다.

두 개의 wire(qubit)가 있고, 하나는 **control qubit**, 다른 하나는 **target qubit**입니다. 규칙은 간단합니다:

> **control qubit가 1이면 target qubit를 뒤집는다(NOT). 아니면 아무것도 안 한다.**

네 computational basis state에 대한 작용:

$$
|00\rangle \to |00\rangle, \quad |01\rangle \to |01\rangle, \quad |10\rangle \to |11\rangle, \quad |11\rangle \to |10\rangle
$$

앞 qubit(control qubit)가 1인 마지막 두 경우에만 뒤 qubit가 뒤집혔습니다. 한 줄 공식으로:

$$
|x, y\rangle \to |x,\, y \oplus x\rangle
$$

여기서 $\oplus$ 는 **modulo-2 addition(XOR)**입니다 ($1\oplus1 = 0$). classical programming의 `if (control) target = NOT target;` 와 같습니다.

> ❓ **왜 XOR인가?**: quantum computing의 CNOT이 classical computing의 XOR에 대응하기 때문입니다. 이 $\oplus$ notation은 [7장 oracle](07_oracle_and_phase_kickback.md) $U_f|x\rangle|y\rangle = |x\rangle|y\oplus f(x)\rangle$ 에서 다시 핵심으로 등장합니다.

computational basis $\{|00\rangle, |01\rangle, |10\rangle, |11\rangle\}$ 순서로 matrix로 쓰면 이렇습니다 — 앞 두 computational basis state($|00\rangle, |01\rangle$)는 그대로 두고, 뒤 두 computational basis state($|10\rangle, |11\rangle$)의 자리만 맞바꾸는 형태입니다:

$$
\text{CNOT} = \begin{bmatrix} 1&0&0&0 \\ 0&1&0&0 \\ 0&0&0&1 \\ 0&0&1&0 \end{bmatrix}
$$

CNOT도 물론 unitary이고($\text{CNOT}^\dagger\,\text{CNOT} = I$), superposition에는 linear하게 작용합니다.

---

## 5.5 entanglement — 나눌 수 없는 state

다음 계산을 살펴봅시다. $|00\rangle$ 에서 시작해 **첫 qubit에 $H$, 그다음 CNOT** 을 적용해 봅시다.

🔍 **계산 따라가기**

1단계 — 첫 qubit에 $H$: $|0\rangle \to \frac{|0\rangle+|1\rangle}{\sqrt2}$ 이므로 두 qubit state는

$$
|00\rangle \xrightarrow{H\otimes I} \frac{|00\rangle + |10\rangle}{\sqrt2}
$$

2단계 — CNOT (첫=control qubit, 둘째=target qubit): $|00\rangle$ 은 control qubit가 0이라 그대로, $|10\rangle$ 은 control qubit가 1이라 target qubit를 뒤집어 $|11\rangle$:

$$
\frac{|00\rangle + |10\rangle}{\sqrt2} \xrightarrow{\text{CNOT}} \frac{|00\rangle + |11\rangle}{\sqrt2}
$$

이 출력 state $\frac{|00\rangle + |11\rangle}{\sqrt2}$ 를 **Bell state**라 하고, **entangled state**의 대표 예입니다.

### 왜 entanglement가 특별한가

이 state는 **두 개의 독립된 single-qubit state의 tensor product로 쓸 수 없습니다.** 즉 $|a\rangle \otimes |b\rangle$ 형태로 분해가 안 됩니다 (product state가 아님).

measurement 결과는 다음과 같습니다:

- 첫 qubit의 measurement에서 0이 나오면, 둘째 qubit는 **반드시** 0.
- 첫 qubit가 1이면, 둘째는 **반드시** 1.

두 qubit의 measurement 결과가 완벽히 **correlated**되어 있습니다. 아무리 멀리 떨어뜨려도 그렇습니다. 이것이 Einstein이 "spooky action at a distance"라 부른 entanglement입니다.

> 🔑 **product state vs entangled state**
>
> - **product state**: $|a\rangle\otimes|b\rangle$ 로 분해됨. 각 qubit를 독립적으로 기술 가능. 예: $|00\rangle$, $|+\rangle|-\rangle$.
> - **entangled state**: 분해 불가능. 예: $\frac{|00\rangle+|11\rangle}{\sqrt2}$. 부분들이 전체보다 정보가 적음.

entanglement는 quantum teleportation, quantum error correction, 그리고 빠른 quantum algorithm의 핵심 resource입니다.

⚠️ **함정 — CNOT은 target qubit만 바꾸는 게 아니다**: "control qubit는 그대로, target qubit만 바뀐다"는 computational basis에서만 맞습니다. 예컨대 $|+\rangle|-\rangle$ 을 CNOT에 넣으면 $|-\rangle|-\rangle$ 이 나와 **control qubit가 바뀝니다**. computational basis 직관을 다른 basis에 그대로 옮기면 틀립니다.

✏️ **연습 5-1**: $\frac{|00\rangle + |01\rangle}{\sqrt2}$ 는 product state일까요, entangled state일까요? *(answer: product state. 첫 qubit로 묶어내 보세요 — [10장](10_glossary_and_cheat_sheet.md#106-연습문제-답)에 풀이.)*

이처럼 분해할 수 없다는 성질이 hardware budget을 결정합니다. state가 늘 product state로 유지된다면 qubit 하나를 amplitude 두 개로 적어 $2 \times \text{number of qubits}$ 개의 수만 들고 있으면 됩니다. entangled state는 그렇게 쪼갤 수 없으니 $2^{\text{number of qubits}}$ 개의 amplitude를 **전부** 들고 있어야 하고, qubit당 몇 개의 수로 압축할 방법이 없습니다. Grover의 시작점인 uniform superposition은 아직 product state($|+\rangle^{\otimes \text{number of qubits}}$)이지만, oracle이 한 칸의 sign을 뒤집는 순간 product state로 분해되지 않는 state가 됩니다 — 2 qubits에서 $\frac12(|00\rangle+|01\rangle+|10\rangle-|11\rangle)$ 을 연습 5-1과 같은 방법으로 묶어내 보면 실패합니다. 즉 **entanglement = 압축 불가 = 지수 memory**이고, algorithm이 도는 내내 amplitude array를 통째로 들고 있어야 한다는 뜻입니다. state vector emulator의 속도가 산술 능력보다 memory의 제약에 더 크게 좌우되는([11.6절](11_state_vector_emulator.md#116-memory-bound의-두-얼굴--용량과-port)) 근본 이유가 여기 있습니다.

---

## 5.6 qubit가 많을 때의 CNOT

CNOT은 qubit가 더 많은 계산에도 등장합니다. 예를 들어 3 qubits에서 "둘째=control qubit, 셋째=target qubit"인 CNOT은:

$$
|x, y, z\rangle \to |x, y, z\oplus y\rangle
$$

첫 qubit $x$ 는 관여 안 하니 그대로, control qubit $y$ 도 그대로, target qubit $z$ 만 $y$ 가 1일 때 뒤집힙니다. 이런 식으로 여러 qubit 사이에 conditional logic를 쌓아 복잡한 계산을 만듭니다.

이 장의 부품 가운데 CNOT은 우리 RTL에 module로 등장하지 않습니다. emulator가 gate를 하나씩 state vector에 적용하는 기계가 아니라, oracle과 diffusion operator라는 **operator 단위**로 amplitude array 전체를 한 번에 훑는 기계이기 때문입니다(그 차이는 바로 다음 [6.1절](06_quantum_circuit_model_and_universality.md#61-quantum-computation--딱-세-단계)에서 정확히 짚습니다). 그렇다고 CNOT을 흘려보내도 되는 것은 아닙니다 — 논문의 circuit diagram과 Qiskit code는 여전히 gate로 적혀 있어서, 그 그림을 읽고 우리 operator에 대응시키려면 CNOT과 $\oplus$ 표기가 필요합니다. 이 장에서 CNOT은 직접 만들 circuit이 아니라 **논문을 읽기 위한 표기**로 이해해 두면 됩니다.

---

## 5.7 이 장의 요약

- **$\text{number of states} = 2^{\text{number of qubits}}$**: computational basis state마다 complex amplitude 하나. 지수적 state space가 quantum parallelism의 근원.
- **tensor product**: qubit를 합칠 때 distributive law처럼 전개. $|a\rangle\otimes|b\rangle$. $H^{\otimes \text{number of qubits}}$ = 모든 qubit에 $H$.
- **CNOT**: control qubit가 1이면 target qubit 뒤집기. $|x,y\rangle\to|x,y\oplus x\rangle$ ($\oplus$ = XOR). qubit 상호작용의 기본.
- **entanglement**: $\frac{|00\rangle+|11\rangle}{\sqrt2}$ (Bell state)처럼 product state로 분해 안 되는 state. measurement 결과가 완벽히 correlated.
- **product state vs entangled state**: 분해 가능 vs 불가능. entanglement는 빠른 algorithm·teleportation의 resource.
- CNOT 직관("target qubit만 변함")은 computational basis에서만 유효.

다음 장에서는 이 부품들 — single-qubit gate + CNOT + measurement — 을 합쳐 **완전한 quantum computation model**을 정의하고, $H^{\otimes \text{number of qubits}}$ 로 uniform superposition을 만드는 법과 universality를 봅니다. algorithm 직전의 마지막 준비입니다.

---

> [← 4장 measurement](04_measurement.md) · [index](index.md) · [6장 quantum circuit model과 범용성 →](06_quantum_circuit_model_and_universality.md)

<!-- HUMANIZE-SUMMARY -->
<!--
{
  "original_chars": 10669,
  "final_chars": 10683,
  "gate_change_rate": 0.0096,
  "grade": "A",
  "self_check": "6/6",
  "categories": [
    "A-18",
    "D-14",
    "D-2",
    "D-8"
  ],
  "highlights": [
    "조사와 서술 연결을 자연스럽게 정리",
    "비교 표현이 실제 설계에 CNOT을 쓴다는 여지를 만들지 않도록 원래 구별 복원"
  ],
  "remaining_findings": [],
  "baseline_gate_warning_count": 0,
  "finalize": "corrected",
  "gate_exit_code": 0,
  "new_gate_warnings": 0
}
-->
