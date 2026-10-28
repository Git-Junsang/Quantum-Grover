# 3장. single-qubit gate

> [← 2장 Dirac notation과 linear algebra](02_dirac_notation_and_linear_algebra.md) · [index](index.md) · [4장 measurement →](04_measurement.md)
> **이 장을 읽기 위한 준비**: [1장](01_qubits_and_states.md) qubit·superposition, [2장](02_dirac_notation_and_linear_algebra.md) inner product·dagger. matrix × vector multiplication.

---

qubit state를 알았으니, 이제 그 state를 **바꾸는** 방법을 배웁니다. classical computer가 AND·OR·NOT gate로 bit를 조작하듯, quantum computer는 **quantum gate**로 qubit를 조작합니다. quantum gate는 모두 **unitary matrix**이며, state vector에 matrix를 곱하는 것이 곧 gate를 적용하는 것입니다. 이 장에서 배울 $X$·$H$·$Z$ gate는 [7장](07_oracle_and_phase_kickback.md)·[8장](08_deutsch_jozsa_algorithm.md)·[9장](09_grover_algorithm.md) algorithm의 부품이 됩니다. 특히 **Hadamard($H$)** 는 superposition을 만드는 열쇠입니다.

---

## 3.1 gate = matrix, 적용 = matrix multiplication

single-qubit gate는 **$2\times2$ matrix** $U$ 로 표현됩니다. 입력 state가 $|\psi\rangle$ 이면 출력은 그냥 matrix multiplication:

$$|\psi_{\text{out}}\rangle = U|\psi\rangle$$

quantum gate는 state vector에 **linear**하게 작용합니다. 즉 superposition의 각 항에 따로 작용한 뒤 더하면 됩니다:

$$U(\alpha|0\rangle + \beta|1\rangle) = \alpha\, U|0\rangle + \beta\, U|1\rangle$$

이 linearity 덕분에, gate가 $|0\rangle$ 과 $|1\rangle$ 에 무엇을 하는지만 알면 모든 state에 대한 작용을 알 수 있습니다.

---

## 3.2 X gate (NOT) — 0과 1 뒤집기

가장 간단한 gate. classical NOT처럼 $|0\rangle \leftrightarrow |1\rangle$ 을 뒤집습니다.

$$X|0\rangle = |1\rangle, \qquad X|1\rangle = |0\rangle, \qquad X = \begin{bmatrix} 0 & 1 \\ 1 & 0\end{bmatrix}$$

superposition에는 linear하게 작용해 amplitude를 맞바꿉니다:

$$X(\alpha|0\rangle + \beta|1\rangle) = \alpha|1\rangle + \beta|0\rangle = \begin{bmatrix} 0&1\\1&0\end{bmatrix}\begin{bmatrix}\alpha\\\beta\end{bmatrix} = \begin{bmatrix}\beta\\\alpha\end{bmatrix}$$

> ❓ **왜 이름이 $X$ 인가?**: 물리학자 Pauli가 1927년 $x$ 축 회전을 기술하려 도입한 matrix $\sigma_x$ 에서 왔습니다. quantum computing에서는 회전 맥락은 사라지고 이름만 남아 $X$ 가 되었습니다. NOT gate와 $X$ gate는 같은 말입니다.

### circuit notation과 시간의 흐름

quantum circuit에서 gate는 상자로, qubit는 왼쪽에서 오른쪽으로 흐르는 **quantum wire**로 그립니다. **왼쪽→오른쪽이 시간의 흐름**입니다.

```
 |ψ⟩ ──[ X ]── X|ψ⟩
```

⚠️ **함정 — 아무것도 안 하는 circuit이 물리적으로 가장 어렵다**: gate 없는 wire(identity operation)는 수학적으로 사소하지만, 실제 hardware에서는 qubit state를 **깨지지 않게 유지**하는 것이 가장 어려운 축에 듭니다. state는 극도로 부서지기 쉽기 때문입니다.

---

## 3.3 X를 두 번 = identity

$X$ 를 연달아 두 번 적용하면 원래로 돌아옵니다. matrix로 확인:

$$XX = \begin{bmatrix} 0&1\\1&0\end{bmatrix}\begin{bmatrix} 0&1\\1&0\end{bmatrix} = \begin{bmatrix} 1&0\\0&1\end{bmatrix} = I$$

$XX = I$ 이므로 두 개의 $X$ gate는 identity(quantum wire)와 같습니다. 이렇게 **matrix multiplication으로 circuit을 분석**하는 것이 표준 기법입니다.

> ⚠️ **함정 — circuit 순서 vs matrix 순서는 반대**: circuit에서 먼저 $H$, 다음 $X$ 를 적용하면 출력은 $XH|\psi\rangle$ 입니다 ($HX$ 가 아님!). circuit은 왼→오로 읽지만 matrix multiplication은 오른쪽부터 작용하기 때문입니다. **"나중 gate를 왼쪽에"** 쓴다고 기억하세요.

---

## 3.4 Hadamard gate (H) — superposition을 만드는 열쇠

이 해설서에서 가장 중요한 gate입니다. $H$ 는 computational basis를 **uniform superposition**으로 보냅니다.

$$H|0\rangle = \frac{|0\rangle + |1\rangle}{\sqrt2} = |+\rangle, \qquad H|1\rangle = \frac{|0\rangle - |1\rangle}{\sqrt2} = |-\rangle$$

$$H = \frac{1}{\sqrt2}\begin{bmatrix} 1 & 1 \\ 1 & -1\end{bmatrix}$$

🔍 **계산 따라가기 — $H|0\rangle$**

$$H|0\rangle = \frac{1}{\sqrt2}\begin{bmatrix} 1&1\\1&-1\end{bmatrix}\begin{bmatrix} 1\\0\end{bmatrix} = \frac{1}{\sqrt2}\begin{bmatrix} 1\\1\end{bmatrix} = \frac{|0\rangle+|1\rangle}{\sqrt2} \quad ✓$$

$H$ 는 "$|0\rangle$ 이라는 확실한 state"를 "$|0\rangle$ 과 $|1\rangle$ 이 반반인 superposition"으로 펼칩니다.

💡 **비유 (원문의 배 이야기)**: 고대에 북아프리카에서 이베리아 반도로 가려면 아프리카·유럽을 빙 둘러 육로로 가야 했습니다. 그런데 **배**를 발명하면 바다를 가로질러 지름길로 갑니다. Hadamard 같은 gate는 classical computer가 갈 수 없는 state들("바다")로 계산을 데려가, 지름길을 낼 수 있게 해 줍니다.

### H를 두 번 = identity (interference의 첫 맛)

$H$ 를 $|0\rangle$ 에 두 번 적용하면 어떻게 될까요? 직관적으로는 "더 골고루 섞이겠지" 싶지만, 실제로는 **원래 $|0\rangle$ 로 돌아옵니다.**

🔍 **계산 따라가기**: $H|0\rangle = \frac{|0\rangle+|1\rangle}{\sqrt2}$. 여기에 다시 $H$:

$$H\!\left(\frac{|0\rangle+|1\rangle}{\sqrt2}\right) = \frac{1}{\sqrt2}\left(\frac{|0\rangle+|1\rangle}{\sqrt2} + \frac{|0\rangle-|1\rangle}{\sqrt2}\right) = \frac{1}{2}(2|0\rangle) = |0\rangle$$

$|1\rangle$ 항은 **서로 상쇄(cancel)** 되고 $|0\rangle$ 항은 **보강(reinforce)** 됩니다. 이것이 바로 **interference** 이며, $HH = I$ 입니다.

> 🔑 **핵심 — interference가 quantum algorithm의 심장**: 많은 quantum algorithm은 (1) Hadamard로 state를 넓게 펼치고, (2) oracle로 solution에 표시한 뒤, (3) 영리한 상쇄·보강 패턴으로 solution state만 남기고 나머지를 지웁니다. [8장 Deutsch-Jozsa](08_deutsch_jozsa_algorithm.md)와 [9장 Grover](09_grover_algorithm.md)가 정확히 이 구조입니다.

qubit마다 $H$ 를 하나씩 걸면($H^{\otimes \text{number of qubits}}$, [6.2절](06_quantum_circuit_model_and_universality.md#62-uniform-superposition-만들기--hotimes-textnumber-of-qubits)) $\text{number of states} = 2^{\text{number of qubits}}$ 개의 computational basis state가 모두 amplitude $1/\sqrt{\text{number of states}}$ 를 나눠 갖는 uniform superposition이 됩니다. 우리 project의 14 qubits라면 16,384 states이고 $1/\sqrt{16{,}384} = 1/128 = 0.0078125$ 인데, 이 값을 23-bit fixed-point(Q1.22 — 표기의 뜻은 [12.2절](12_fixed_point_and_precision.md#122-fixed-point와-q-format-명명-규약))에 담으면 **integer 32,768 하나**이고 rounding 없이 정확합니다. 그래서 emulator의 initialization은 $2^{14}\times2^{14}$ 짜리 matrix를 곱하는 일이 아니라 **constant 32,768을 16,384칸에 채워 넣는 일**이 됩니다([13.2절](13_oracle_diffusion_measurement_datapath.md#132-init--uniform-amplitude를-square-root-unit-없이)). 수식과 circuit이 이렇게 달라 보이는 이유는 간단합니다 — 우리는 matrix를 만드는 대신, 그 matrix가 만들어 낼 **결과**를 곧장 적어 넣습니다.

---

## 3.5 Y·Z gate — 나머지 Pauli matrix

$X$ 와 함께 Pauli가 도입한 두 matrix $Y$, $Z$ 도 유용한 gate입니다.

$$Y = \begin{bmatrix} 0 & -i \\ i & 0\end{bmatrix}, \qquad Z = \begin{bmatrix} 1 & 0 \\ 0 & -1\end{bmatrix}$$

$Z$ gate가 특히 중요합니다. $|0\rangle$ 은 그대로 두고 $|1\rangle$ 의 **sign만 뒤집습니다**:

$$Z|0\rangle = |0\rangle, \qquad Z|1\rangle = -|1\rangle$$

이 "sign 뒤집기 = phase 반전"이 [7장 phase kickback](07_oracle_and_phase_kickback.md)과 [9장 Grover oracle](09_grover_algorithm.md)의 핵심 동작입니다. $\{X, Y, Z\}$ 를 합쳐 **Pauli matrix**라 부릅니다.

✏️ **연습 3-1**: $Z|+\rangle$ 은? *(answer: $Z\frac{|0\rangle+|1\rangle}{\sqrt2} = \frac{|0\rangle-|1\rangle}{\sqrt2} = |-\rangle$. $Z$ 가 $|+\rangle \leftrightarrow |-\rangle$ 을 맞바꿈.)*

---

## 3.6 unitary matrix — 왜 이것만 gate가 되나

임의의 single-qubit gate는 **unitary matrix** $U$ 입니다. unitary의 정의(대수적):

$$U^\dagger U = I$$

즉 $U$ 의 conjugate transpose([2장](02_dirac_notation_and_linear_algebra.md))를 곱하면 identity matrix가 됩니다. 이게 왜 중요할까요?

> 🔑 **unitary = 길이 보존**: unitary matrix는 vector의 **길이를 바꾸지 않습니다**. $\|U|\psi\rangle\| = \||\psi\rangle\|$. real vector space의 회전·반사가 길이를 안 바꾸는 것의 complex number version입니다.

이것이 gate에 필수인 이유: 입력 state는 normalize(길이 1)되어 있고, 출력도 정당한 state이려면 길이 1이어야 합니다([1장](01_qubits_and_states.md), [4장](04_measurement.md)). unitary만이 이를 보장합니다. 사실 **길이를 보존하는 matrix는 unitary뿐**이라는 정리도 성립합니다.

다만 이 보장은 amplitude를 정확한 real number로 다룰 때의 이야기입니다. amplitude를 유한한 bit 수로 적는 순간 operation마다 rounding이 끼어들어, 실제 hardware에서 norm은 정확히 1로 유지되지 않습니다. 우리 설계는 그 어긋남을 rounding error 규모로 보고 **감수하며, 매 iteration 끝에 길이를 1로 되돌리는 renormalization을 하지 않습니다**([12.5절](12_fixed_point_and_precision.md#125-overflow-policy--saturationwraparound-금지renormalization-없음)).

🔍 **계산 따라가기 — $H$ 는 unitary인가?**: $H$ 는 real symmetric matrix라 $H^\dagger = H$. 따라서 $H^\dagger H = HH = I$ ([3.4절](#34-hadamard-gate-h--superposition을-만드는-열쇠)에서 확인). ✓ unitary.

⚠️ **함정 — 아무 matrix나 gate가 아니다**: 예컨대 $J = \frac{1}{\sqrt2}\begin{bmatrix}1&1\\1&1\end{bmatrix}$ 은 $J|0\rangle, J|1\rangle$ 은 normalize된 state를 주지만 unitary가 아닙니다($J^\dagger J \ne I$). $J|-\rangle$ 을 계산하면 길이가 0이 되어 정당한 state가 아닙니다. 그래서 gate로 쓸 수 없습니다.

---

## 3.7 unitary의 또 다른 성질 — reversibility

$U^\dagger U = I$ 는 $U^\dagger = U^{-1}$ 을 뜻합니다. 즉 **모든 quantum gate는 inverse가 존재**하며, 그 역은 $U^\dagger$ 입니다. quantum computation은 (measurement 전까지) 항상 **되돌릴 수 있습니다(reversible)**.

이는 classical gate와 큰 차이입니다. classical AND gate는 출력 0을 보고 입력을 복원할 수 없지만(정보 손실), quantum gate는 정보를 잃지 않습니다. [6장](06_quantum_circuit_model_and_universality.md)에서 이 reversibility 때문에 classical circuit을 quantum circuit으로 옮길 때 Toffoli gate가 필요한 이유를 봅니다.

---

## 3.8 주요 single-qubit gate 요약표

| gate | matrix | 작용 | 쓰임 |
|--------|------|------|------|
| $I$ (identity) | $\begin{bmatrix}1&0\\0&1\end{bmatrix}$ | 아무것도 안 함 | quantum wire |
| $X$ (NOT) | $\begin{bmatrix}0&1\\1&0\end{bmatrix}$ | $\|0\rangle\leftrightarrow\|1\rangle$ | bit 반전 |
| $Z$ | $\begin{bmatrix}1&0\\0&-1\end{bmatrix}$ | $\|1\rangle$ sign 반전 | **phase 반전** — oracle의 sign 반전(circuit에서는 two's complement negate) |
| $Y$ | $\begin{bmatrix}0&-i\\i&0\end{bmatrix}$ | bit+phase 반전 | error correction 등 |
| $H$ (Hadamard) | $\frac{1}{\sqrt2}\begin{bmatrix}1&1\\1&-1\end{bmatrix}$ | computational basis ↔ superposition | **superposition 생성** (모든 algorithm) |

이 표는 [10장 cheat sheet](10_glossary_and_cheat_sheet.md)에 다시 정리되어 있습니다. $X$, $H$, $Z$ 셋은 반드시 손으로 계산할 수 있어야 합니다.

이 장의 matrix들이 우리 FPGA emulator에서 어떤 circuit이 되는지 한 문단에 모아 둡니다. amplitude를 memory에 펼쳐 두는 구조에서 gate 적용은 원리적으로 $2^{\text{number of qubits}}\times2^{\text{number of qubits}}$ matrix multiplication이지만, 3.4절에서 본 것처럼 Grover가 쓰는 gate는 matrix를 세우지 않고 **뜻만** 옮기면 됩니다. $Z$ 류의 phase 반전이 특히 그렇습니다 — 표에 "$-1$ 을 곱한다"고 적힌 연산이 circuit에서는 multiplier가 아니라 **two's complement negate**(bit 반전 후 $+1$) 한 번이고, predicate에 걸린 칸에 대해 oracle이 amplitude에 하는 일은 그것이 전부입니다([13.4절](13_oracle_diffusion_measurement_datapath.md#134-sign-반전--twos-complement-negate-한-번)). 덧붙이면 이 표의 다섯 gate 가운데 우리 datapath가 실제로 circuit으로 만드는 것은 $H$ 의 **결과**와 $Z$ 의 **sign 반전** 둘뿐입니다. $X$·$Y$ 는 이론을 세우는 데 꼭 필요하지만, diffusion operator를 gate sequence로 분해하지 않고 inversion about the mean 산술로 곧장 계산하기 때문에 circuit에는 등장하지 않습니다([13.5절](13_oracle_diffusion_measurement_datapath.md#135-diffusion-operator--2mean--amp가-circuit이-되는-순간)).

---

## 3.9 이 장의 요약

- **gate = unitary $2\times2$ matrix**, 적용 = matrix multiplication $U|\psi\rangle$. linear라서 superposition 각 항에 따로 작용.
- **$X$ (NOT)**: $|0\rangle\leftrightarrow|1\rangle$. $XX = I$.
- **$H$ (Hadamard)**: $|0\rangle\to|+\rangle$, $|1\rangle\to|-\rangle$. superposition을 만드는 핵심. $HH = I$ — $|1\rangle$ 상쇄·$|0\rangle$ 보강의 **interference**.
- **$Z$**: $|1\rangle$ sign 반전 = phase 반전. oracle의 부품.
- **unitary $U^\dagger U = I$**: 길이 보존 ⇒ normalization 유지 ⇒ 정당한 gate. 길이 보존 matrix는 unitary뿐.
- **reversibility**: 모든 gate는 inverse $U^\dagger = U^{-1}$ 가 존재. quantum computation은 measurement 전까지 되돌릴 수 있음.
- **circuit vs matrix 순서 반대**: circuit "먼저 $H$ 다음 $X$" = matrix $XH$.

다음 장에서는 계산의 마지막 단계 — **measurement** — 를 배웁니다. 숨어 있던 amplitude가 어떻게 probability로 바뀌고, state가 어떻게 collapse하는지를 봅니다.

---

> [← 2장 Dirac 표기법과 linear algebra](02_dirac_notation_and_linear_algebra.md) · [index](index.md) · [4장 measurement →](04_measurement.md)
