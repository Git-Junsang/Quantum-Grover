# 2장. Dirac notation과 linear algebra

> [← 1장 qubit와 state](01_qubits_and_states.md) · [index](index.md) · [3장 single-qubit gate →](03_single_qubit_gates.md)
> **이 장을 읽기 위한 준비**: [1장](01_qubits_and_states.md)의 ket·superposition·normalization. complex conjugate와 vector transpose(→ 필요하면 [부록 A](A_math_review.md)).

---

[1장](01_qubits_and_states.md)에서 qubit state를 ket $|\psi\rangle$ 으로 썼습니다. 이 장에서는 그 짝인 **bra** $\langle\psi|$ 를 도입하고, 둘을 합친 **inner product**를 배웁니다. inner product는 "두 state가 얼마나 닮았는가"를 재는 도구이며, measurement probability·normalization·unitary condition을 모두 이 도구로 표현할 수 있습니다. 이 notation(Dirac notation)에 익숙해지면 이후 모든 계산이 쉬워집니다.

---

## 2.1 ket과 bra

[1장](01_qubits_and_states.md)에서 본 ket은 **column vector** 입니다.

$$
|\psi\rangle = \begin{bmatrix} \alpha \\ \beta \end{bmatrix}
$$

여기에 짝을 이루는 대상을 정의합니다. 같은 $\psi$ 를 쓰되 꺾쇠 방향이 반대인 **bra**:

$$
\langle\psi| := \begin{bmatrix} \alpha^* & \beta^* \end{bmatrix}
$$

즉 bra $\langle\psi|$ 는 ket의 component를 **complex conjugate**하고 **가로로 눕힌(transpose한)** row vector입니다. ket이 "ket", bra가 "bra"인데, 둘을 합치면 "bra-ket = bracket(괄호)"이 됩니다. 물리학자 Paul Dirac(1939)의 말장난입니다.

💡 **비유**: ket $|\psi\rangle$ 이 세로로 선 화살표라면, bra $\langle\psi|$ 는 그 화살표를 inner product 계산에 쓰는 가로 slot으로 바꾼 것입니다.

---

## 2.2 conjugate transpose(dagger, †) operation

ket을 bra로 바꾸는 operation에는 이름이 있습니다. **conjugate transpose(adjoint)** 또는 **dagger operation**, 기호로 $\dagger$ 입니다.

$$
|\psi\rangle^\dagger = \langle\psi|, \qquad \langle\psi|^\dagger = |\psi\rangle
$$

matrix에 대해서도 정의됩니다. **transpose한 뒤 모든 entry를 complex conjugate**하면 됩니다:

$$
U^\dagger := (U^T)^* \qquad\Longrightarrow\qquad \begin{bmatrix} a & b \\ c & d \end{bmatrix}^\dagger = \begin{bmatrix} a^* & c^* \\ b^* & d^* \end{bmatrix}
$$

이 $\dagger$ 는 "Hermitian conjugate"라고도 부릅니다. [3장](03_single_qubit_gates.md)에서 unitary condition $U^\dagger U = I$ 를 정의할 때 핵심 도구가 됩니다.

> 🔑 **유용한 규칙**: product의 dagger는 순서를 뒤집습니다. $(A|\psi\rangle)^\dagger = \langle\psi| A^\dagger$. 신발을 신고 양말을 신었다면, 되돌릴 때는 양말을 먼저 벗고 신발을 벗는 것과 같습니다.

---

## 2.3 inner product — 두 state가 얼마나 닮았나

이제 bra와 ket을 곱합니다. bra $\langle\phi|$ (row vector, $1\times 2$) 와 ket $|\psi\rangle$ (column vector, $2\times 1$) 를 곱하면 **scalar(숫자)** 하나가 나옵니다. 이것이 **inner product** 입니다.

$$
\langle\phi|\psi\rangle = \begin{bmatrix} \gamma^* & \delta^* \end{bmatrix}\begin{bmatrix} \alpha \\ \beta \end{bmatrix} = \gamma^*\alpha + \delta^*\beta
$$

(여기서 $|\phi\rangle = \gamma|0\rangle + \delta|1\rangle$.) 표기할 때 가운데 세로줄 두 개 $\langle\phi||\psi\rangle$ 를 하나로 줄여 $\langle\phi|\psi\rangle$ 로 씁니다.

inner product의 의미:

- $\langle\phi|\psi\rangle = 0$ 이면 두 state는 **orthogonal**, 즉 완전히 구별 가능.
- $\langle\phi|\psi\rangle$ 의 magnitude가 1에 가까우면 두 state가 거의 같음.

🔍 **계산 따라가기 — $|0\rangle$ 과 $|1\rangle$ 은 orthogonal한가?**

$$
\langle 0|1\rangle = \begin{bmatrix} 1 & 0\end{bmatrix}\begin{bmatrix} 0 \\ 1\end{bmatrix} = 1\cdot 0 + 0\cdot 1 = 0 \quad ✓
$$

orthogonal합니다. 그래서 measurement로 $|0\rangle$ 과 $|1\rangle$ 을 완벽히 구별할 수 있습니다. 또한 각각의 자기 자신과의 inner product:

$$
\langle 0|0\rangle = 1, \qquad \langle 1|1\rangle = 1
$$

즉 $\{|0\rangle, |1\rangle\}$ 은 **orthonormal basis**입니다.

✏️ **연습 2-1**: $|+\rangle$ 과 $|-\rangle$ 은 orthogonal할까요? $\langle +|-\rangle$ 을 계산해 보세요. *(answer: $0$. orthogonal합니다 — [10장](10_glossary_and_cheat_sheet.md#106-연습문제-답)에 풀이.)*

---

## 2.4 inner product로 표현한 길이(normalization)

[1장](01_qubits_and_states.md)의 normalization condition은 inner product로 간단히 표현됩니다. state $|\psi\rangle$ 의 **길이의 square**는 자기 자신과의 inner product입니다.

$$
\||\psi\rangle\|^2 = \langle\psi|\psi\rangle = \alpha^*\alpha + \beta^*\beta = |\alpha|^2 + |\beta|^2
$$

따라서 normalization condition은 한 줄로:

$$
\langle\psi|\psi\rangle = 1
$$

> 🔑 **핵심**: "state는 normalize되어 있다"는 곧 **$\langle\psi|\psi\rangle = 1$**. 이 조건이 [3장](03_single_qubit_gates.md) gate가 unitary여야 하는 이유, [4장](04_measurement.md) measurement probability의 sum이 1인 이유와 직접 연결됩니다.

---

## 2.5 unit vector $|e_i\rangle$ 와 matrix entry 뽑기

계산에 유용한 도구 하나. $|e_i\rangle$ 를 "$i$ 번째 component만 1이고 나머지는 0인 vector"라고 하면, qubit에서는 $|e_0\rangle = |0\rangle$, $|e_1\rangle = |1\rangle$ 입니다.

linear algebra의 기본 사실 두 가지:

- $A|e_k\rangle$ 는 matrix $A$ 의 **$k$ 번째 column**.
- $\langle e_i|A|e_k\rangle$ 는 matrix $A$ 의 **$(i,k)$ entry**.

이 "샌드위치" $\langle\cdot|A|\cdot\rangle$ 형태는 앞으로 자주 나옵니다. 예를 들어 [3장](03_single_qubit_gates.md)에서 gate의 특정 entry를 확인하거나, [9장](09_grover_algorithm.md)에서 diffusion operator를 분석할 때 씁니다.

---

## 2.6 outer product — ket 곱하기 bra

inner product가 "bra × ket = scalar"였다면, 순서를 뒤집은 **outer product** "ket × bra"는 **matrix**를 만듭니다.

$$
|\psi\rangle\langle\phi| = \begin{bmatrix} \alpha \\ \beta\end{bmatrix}\begin{bmatrix} \gamma^* & \delta^*\end{bmatrix} = \begin{bmatrix} \alpha\gamma^* & \alpha\delta^* \\ \beta\gamma^* & \beta\delta^* \end{bmatrix}
$$

특히 $|\psi\rangle\langle\psi|$ 는 $|\psi\rangle$ 방향으로 projection하는 operator입니다. 이 형태는 [9장](09_grover_algorithm.md) Grover diffusion operator $U_\psi = 2|\psi\rangle\langle\psi| - I$ 에 쓰이므로 지금 눈에 익혀 두세요.

🔍 **계산 따라가기 — $|0\rangle\langle 0|$ 은?**

$$
|0\rangle\langle 0| = \begin{bmatrix} 1 \\ 0\end{bmatrix}\begin{bmatrix} 1 & 0\end{bmatrix} = \begin{bmatrix} 1 & 0 \\ 0 & 0\end{bmatrix}
$$

이 matrix를 임의 state에 곱하면 $|0\rangle$ component만 남습니다 (projection). 확인: $|0\rangle\langle 0|(\alpha|0\rangle + \beta|1\rangle) = \alpha|0\rangle$.

다만 hardware는 이 matrix를 **만들지 않습니다.** 14 qubits면 $|\psi\rangle\langle\psi|$ 는 $16{,}384 \times 16{,}384$, 곧 2억 칸이 넘는 matrix라 FPGA에 올릴 방법이 없습니다. 그런데 $|\psi\rangle$ 가 uniform superposition일 때 $2|\psi\rangle\langle\psi| - I$ 를 amplitude array에 적용한 결과를 component별로 적어 보면, 각 칸이 `2 × mean − 자기 자신` 으로 바뀔 뿐입니다. matrix를 저장하고 곱하는 대신, array를 훑으며 sum을 구하고 빼면 됩니다([13.5절](13_oracle_diffusion_measurement_datapath.md#135-diffusion-operator--2mean--amp가-circuit이-되는-순간)).

---

## 2.7 notation 정리 — 헷갈리지 않기

| 표현                            | 이름         | 모양               | 결과               |
| ------------------------------- | ------------ | ------------------ | ------------------ |
| $\|\psi\rangle$               | ket     | column vector $2\times1$ | state               |
| $\langle\psi\|$               | bra   | row vector $1\times2$ | ket의 conjugate transpose      |
| $\langle\phi\|\psi\rangle$    | inner product | scalar             | 닮은 정도 (0=orthogonal) |
| $\|\psi\rangle\langle\phi\|$  | outer product | matrix $2\times2$   | operator (projection 등)   |
| $\langle\phi\|A\|\psi\rangle$ | expectation value 형태     | scalar             | matrix entry·mean    |

⚠️ **함정 — 순서가 전부다**: $\langle\phi|\psi\rangle$ (scalar)와 $|\psi\rangle\langle\phi|$ (matrix)는 완전히 다른 대상입니다. bra가 앞이면 숫자, ket이 앞이면 matrix. 항상 "row vector × column vector = 숫자, column vector × row vector = matrix"로 크기를 따져보세요.

---

## 2.8 이 장의 요약

- **ket·bra**: $|\psi\rangle$ 은 column vector, $\langle\psi| = |\psi\rangle^\dagger$ 는 conjugate transpose한 row vector. 합쳐서 bra-ket(Dirac notation).
- **dagger $\dagger$**: transpose + complex conjugate. matrix는 $U^\dagger = (U^T)^*$. 곱은 순서 뒤집힘 $(A|\psi\rangle)^\dagger = \langle\psi|A^\dagger$.
- **inner product $\langle\phi\|\psi\rangle$**: scalar. 0이면 orthogonal(구별 가능). $\{|0\rangle,|1\rangle\}$ 은 orthonormal basis.
- **normalization**: $\langle\psi\|\psi\rangle = 1$ = 길이 1. 이후 unitary condition·measurement probability를 설명하는 조건.
- **outer product $\|\psi\rangle\langle\phi\|$**: matrix(operator). $|0\rangle\langle 0|$ 은 projection. Grover diffusion operator $2\|\psi\rangle\langle\psi\|-I$ 에 쓰이는 형태.

다음 장에서는 이 state들을 **바꾸는** 방법 — quantum gate — 를 배웁니다. gate는 unitary matrix이고, dagger와 inner product가 그 정당성을 뒷받침합니다.

---

> [← 1장 qubit와 state](01_qubits_and_states.md) · [index](index.md) · [3장 단일 qubit gate →](03_single_qubit_gates.md)

<!-- HUMANIZE-SUMMARY -->
<!--
{
  "original_chars": 7651,
  "final_chars": 7651,
  "gate_change_rate": 0.0106,
  "grade": "A",
  "self_check": "6/6",
  "categories": [
    "A-18",
    "A-19",
    "D-14",
    "D-2"
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
