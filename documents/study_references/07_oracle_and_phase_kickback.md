# 7장. oracle과 phase kickback

> [← 6장 quantum circuit model과 universality](06_quantum_circuit_model_and_universality.md) · [index](index.md) · [8장 Deutsch–Jozsa algorithm →](08_deutsch_jozsa_algorithm.md)
> **이 장을 읽기 위한 준비**: [1.5절](01_qubits_and_states.md#15-자주-등장하는-state들) $\|-\rangle$, [3장](03_single_qubit_gates.md) $X\|Z\|H$, [4장](04_measurement.md) phase, [5장](05_multiple_qubits_and_entanglement.md) CNOT·$\oplus$, [6장](06_quantum_circuit_model_and_universality.md) Toffoli.

---

이제 algorithm의 세계로 들어갑니다. quantum search·판별 algorithm은 모두 "우리가 찾는 solution이 무엇인지"를 알려주는 통로가 필요합니다. 그 통로가 **oracle** 입니다. 그리고 oracle을 유용하게 만드는 결정적 trick이 **phase kickback** — 함숫값을 amplitude의 **sign**으로 바꿔치기하는 마법입니다. 이 장의 두 개념은 [8장 Deutsch–Jozsa](08_deutsch_jozsa_algorithm.md)와 [9장 Grover](09_grover_algorithm.md)를 떠받치는 기둥입니다. 특히 phase kickback을 이해하면 "Grover oracle이 solution state의 sign을 뒤집는다"는 말이 완전히 명확해집니다.

---

## 7.1 oracle이란 무엇인가

**oracle**은 고대 그리스의 신탁에서 따온 이름입니다. 입력을 넣으면 **1 또는 0** (참/거짓)만 돌려주는 function입니다.

$$f : \{0,1\}^{\text{number of qubits}} \to \{0,1\}$$

핵심은 우리가 function **내부 동작은 모른다**는 것입니다. 입력에 대해 0/1을 돌려주는 것만 알 뿐, 어떻게 그 값을 계산하는지는 관심 밖입니다. 그래서 oracle을 **black box**라고도 부릅니다.

💡 **비유**: oracle은 "solution 판별기"입니다. 어떤 상자를 열어 "이게 내가 찾던 민트 초콜릿이냐?"고 물으면 예(1)/아니오(0)만 답하는 기계. 어떻게 판별하는지는 몰라도, 물어볼 수는 있습니다.

우리 project에서 oracle은 "찾고자 하는 항목이면 1, 아니면 0"을 판별합니다. Grover는 이 oracle을 이용해 solution 항목을 찾아냅니다.

---

## 7.2 oracle을 quantum으로 — 두 가지 형태

quantum computer의 모든 연산은 unitary여야 합니다([3장](03_single_qubit_gates.md)). oracle function도 unitary matrix로 표현해야 하는데, 두 가지 표준 형태가 있습니다.

### 형태 A — bit flip oracle (여분 qubit 사용)

[6장 Toffoli](06_quantum_circuit_model_and_universality.md#65-toffoli-gate--reversible-and)에서 본 가역적 implementation 방식입니다. 입력 register $|x\rangle$ 와 별도의 **출력 qubit** $|y\rangle$ 를 두고, 함숫값을 $y$ 에 XOR로 씁니다:

$$U_f\,|x\rangle|y\rangle = |x\rangle\,|y \oplus f(x)\rangle$$

$f(x)=1$ 이면 $y$ 가 뒤집히고, $f(x)=0$ 이면 그대로. 이는 가역적이라 정당한 unitary입니다. ($\oplus$ 는 [5장](05_multiple_qubits_and_entanglement.md)의 XOR.)

### 형태 B — phase oracle (sign 뒤집기)

Grover가 실제로 쓰는 형태입니다. 여분 qubit 없이, solution state의 **amplitude sign만** 뒤집습니다:

$$U_f\,|x\rangle = \begin{cases} -|x\rangle & \text{if } f(x) = 1 \\ +|x\rangle & \text{if } f(x) = 0\end{cases}$$

한 줄로 쓰면:

$$U_f\,|x\rangle = (-1)^{f(x)}|x\rangle$$

solution($f(x)=1$)인 state에만 $-1$ 이 붙습니다. **probability(absolute value)는 그대로**이고 phase(sign)만 뒤집힌다는 게 핵심입니다.

🔍 **예제 (원문) — 3 qubits에서 $|010\rangle$ 만 solution이라면**

uniform superposition에 phase oracle을 걸면, $|010\rangle$ 앞에만 minus sign이 붙습니다:

$$U_f|\psi\rangle = \tfrac{1}{\sqrt8}\big(|000\rangle + |001\rangle - |010\rangle + |011\rangle + |100\rangle + |101\rangle + |110\rangle + |111\rangle\big)$$

이제 문제는 이 sign이 **measurement만으로는 드러나지 않는다**는 것입니다. 이 minus sign은 전체에 곱해진 global phase가 아니라 항들 **사이의** relative phase라 물리적으로 분명히 의미가 있습니다([4.9절](04_measurement.md#49-global-phase는-무의미하다)). 하지만 지금은 여덟 amplitude의 **크기가 모두 같아서** measurement probability($|\text{amplitude}|^2$)가 여전히 균등합니다 — 표식은 붙었으되 그냥 measurement만 해서는 아직 보이지 않는 것이죠. 그래서 [9장 Grover](09_grover_algorithm.md)의 diffusion operator가 이 "숨은 sign 표시"를 큰 amplitude로 바꿔줘야 합니다.

> 🔑 **핵심 — oracle은 "solution에 표시"를 한다**: phase oracle은 solution state에 minus sign이라는 **보이지 않는 표식**을 답니다. 이 표식만으로는 아직 measurement에서 이득이 없습니다. 표식을 amplitude로 증폭하는 것이 algorithm의 나머지 절반입니다.

---

## 7.3 phase kickback — 형태 A가 형태 B로 변신하는 마법

가장 중요한 부분입니다. oracle을 **형태 A($U_f|x\rangle|y\rangle = |x\rangle|y\oplus f(x)\rangle$)로 만들었는데**, 출력 qubit $|y\rangle$ 를 특별한 state $|-\rangle$ 로 두면, 마법처럼 **형태 B(phase oracle)** 가 튀어나옵니다. 이것이 **phase kickback** 입니다.

출력 qubit를 $|y\rangle = |-\rangle = \frac{|0\rangle - |1\rangle}{\sqrt2}$ 로 두고 계산해 봅시다.

🔍 **계산 따라가기**

$$U_f\,|x\rangle|-\rangle = U_f\,|x\rangle\frac{|0\rangle - |1\rangle}{\sqrt2} = \frac{1}{\sqrt2}\big(|x\rangle|0\oplus f(x)\rangle - |x\rangle|1\oplus f(x)\rangle\big)$$

이제 $f(x)$ 값으로 경우를 나눕니다.

**경우 1 — $f(x) = 0$:** $0\oplus0 = 0$, $1\oplus0 = 1$ 이므로

$$\frac{1}{\sqrt2}(|x\rangle|0\rangle - |x\rangle|1\rangle) = |x\rangle\frac{|0\rangle-|1\rangle}{\sqrt2} = |x\rangle|-\rangle$$

그대로입니다.

**경우 2 — $f(x) = 1$:** $0\oplus1 = 1$, $1\oplus1 = 0$ 이므로

$$\frac{1}{\sqrt2}(|x\rangle|1\rangle - |x\rangle|0\rangle) = |x\rangle\frac{|1\rangle-|0\rangle}{\sqrt2} = -|x\rangle\frac{|0\rangle-|1\rangle}{\sqrt2} = -|x\rangle|-\rangle$$

$|0\rangle, |1\rangle$ 이 뒤바뀌어 **전체에 $-1$** 이 붙었습니다!

두 경우를 합치면:

$$U_f\,|x\rangle|-\rangle = (-1)^{f(x)}\,|x\rangle|-\rangle$$

> 🔑 **phase kickback의 정체**: 분명히 $U_f$ 는 출력 qubit $|y\rangle$ 를 건드리는 연산인데, $|y\rangle = |-\rangle$ 로 두면 **$y$ 는 그대로이고 대신 입력 $|x\rangle$ 앞에 sign $(-1)^{f(x)}$ 가 "튀어(kick back)"** 나옵니다. 출력 qubit에서 일어나야 할 변화가 입력 qubit의 phase로 되차인 것입니다.

출력 qubit $|-\rangle$ 은 계산 내내 변하지 않고 곁다리(constant)로 남으므로, 실질적으로는 입력 register에 phase oracle(형태 B)을 건 것과 같습니다:

$$\underbrace{U_f|x\rangle|-\rangle}_{\text{형태 A + }|-\rangle} = \underbrace{(-1)^{f(x)}|x\rangle}_{\text{형태 B}}\,|-\rangle$$

💡 **비유**: $|-\rangle$ 은 "sign을 되받아치는 거울"입니다. oracle이 출력 qubit를 뒤집으려 하면, $|-\rangle$ 거울은 자기가 뒤집히는 대신 그 뒤집힘을 입력 qubit의 sign으로 반사해 보냅니다.

### 왜 하필 $|-\rangle$ 인가

$|-\rangle$ 은 $X$ gate의 eigenstate입니다: $X|-\rangle = -|-\rangle$. 즉 "뒤집혀도 sign만 바뀌고 형태는 그대로"인 state라, 뒤집힘이 sign으로 전환됩니다. 그리고 $|-\rangle = HX|0\rangle$ 이므로 $|0\rangle$ 에 $X$ 다음 $H$ 를 걸어 쉽게 만들 수 있습니다.

✏️ **연습 7-1**: solution이 아닌 입력($f(x)=0$)에 대해 $U_f|x\rangle|-\rangle$ 은 무엇이 될까요? *(답: $|x\rangle|-\rangle$ — 그대로. $(-1)^0 = 1$ 이라 sign이 안 붙습니다. [10장](10_glossary_and_cheat_sheet.md#106-연습문제-답)에 풀이.)*

---

## 7.4 conditional sign flip — operator로 쓰기

phase oracle을 operator 형태로 정리해 둡시다. 조건을 만족하는 입력들의 집합을 $A = \{x : f(x) = 1\}$, 그 크기를 $\text{number of solutions} = |A|$ 라 하면, phase oracle은 다음 unitary로 쓸 수 있습니다:

$$U_f = I - 2\sum_{\omega \in A}|\omega\rangle\langle\omega|$$

🔍 **확인**: [2.6절 outer product](02_dirac_notation_and_linear_algebra.md#26-outer-product--ket-곱하기-bra)에서 $|\omega\rangle\langle\omega|$ 는 $|\omega\rangle$ 방향 projection이었습니다. 서로 다른 computational basis state끼리는 orthogonal이므로 sum에서 항 하나만 살아남고, 검산은 항이 하나였을 때와 똑같은 두 줄로 끝납니다.
- $|\omega'\rangle \in A$ 에 작용: $\omega = \omega'$ 항만 남아 $|\omega'\rangle - 2|\omega'\rangle = -|\omega'\rangle$. ✓ (sign 뒤집힘)
- $A$ 의 모든 원소와 orthogonal인 $|x\rangle$ 에 작용: 항마다 $\langle\omega|x\rangle = 0$ 이므로 $|x\rangle - 0 = |x\rangle$. ✓ (그대로)

solution이 하나뿐인 경우는 sum이 한 항으로 줄어든 **special case** $U_f = I - 2|\omega\rangle\langle\omega|$ 입니다. 교과서가 Grover를 소개할 때 이 형태를 쓰기 때문에 solution은 늘 하나라는 인상을 받기 쉬운데, $f$ 가 조건을 판정하는 function인 이상 number of solutions는 우리가 고르는 값이 아니라 data가 정하는 값입니다. solution이 하나도 없을 수도 있고 모든 state가 solution일 수도 있습니다.

여기서 관찰 하나를 미리 챙겨 두면 나중에 크게 씁니다. 위 식에서 $A$ 의 원소들은 서로 **완전히 대칭**입니다 — 어느 항도 특별대우를 받지 않고 전부 같은 계수의 projection일 뿐이고, 뒤에 올 diffusion operator 역시 index를 구별하지 않습니다. 그래서 증폭이 끝난 뒤 모든 solution의 amplitude는 **정확히 같아집니다**([9.7절](09_grover_algorithm.md#97-이제-수식으로--두-개의-reflection) · [14.3절](14_multiple_solutions_and_minimum_search.md#143-amplitude-동률--argmax가-무너지는-지점)). "가장 큰 amplitude를 고르면 solution이 나온다"는 measurement 방식이 solution이 여럿일 때 무너지는 뿌리가 바로 이 대칭성입니다.

이렇게 "특정 computational basis의 amplitude sign만 뒤집는" 연산을 **conditional sign flip**이라 부릅니다. 이 $I - 2\sum_{\omega\in A}|\omega\rangle\langle\omega|$ 형태가 [9장 Grover](09_grover_algorithm.md)의 oracle 단계이고, 이와 쌍둥이인 $2|\psi\rangle\langle\psi| - I$ 가 diffusion operator입니다. 두 개의 "reflection"이 Grover의 전부입니다.

---

## 7.5 oracle을 실제로 만들기 — $Z$ gate trick

"모든 qubit가 $|1\rangle$ 일 때만 sign을 뒤집는" oracle은 실제로 간단히 구현됩니다. 마지막 qubit 하나만 빼고 나머지를 모두 control qubit로, 마지막을 target qubit로 하는 **multi-controlled $Z$ gate**를 쓰면 됩니다. $Z = \begin{bmatrix}1&0\\0&-1\end{bmatrix}$ 는 target qubit가 $|1\rangle$ 일 때만 sign을 뒤집으므로([3.5절](03_single_qubit_gates.md#35-yz-gate--나머지-pauli-matrix)), 모든 control qubit가 $|1\rangle$ 일 때만 $|11\cdots1\rangle$ 의 sign이 반전됩니다.

특정 bit string $\omega$ 에 대한 oracle도, $\omega$ 의 0인 자리에 $X$ gate를 앞뒤로 감싸 그 bit string을 $|11\cdots1\rangle$ 자리로 옮긴 뒤 이 trick을 쓰면 됩니다. 다만 이 조립법이 무엇을 해 주는 것인지는 정확히 새겨 두어야 합니다. 이것은 **판정 function $f$ 를 이미 circuit으로 갖고 있을 때 그것을 phase oracle(형태 B)로 바꿔 놓는 방법**이지, 어느 입력이 조건을 만족하는지 알아내는 방법이 아닙니다. $X$ 를 어느 자리에 감을지 정하려면 $\omega$ 를 이미 알고 있어야 하므로, 위 배치를 그대로 쓴 circuit은 search를 하는 것이 아니라 답을 아는 채로 algorithm 골격이 도는지 확인하는 실습용 circuit입니다. 실제 search에서 $f$ 는 조건을 계산하는 classical circuit이고, 그것을 [6.4절](06_quantum_circuit_model_and_universality.md#64-classical-computation을-quantum으로--reversibility-문제)의 방식으로 가역화해 형태 A로 만든 다음 출력 qubit를 $|-\rangle$ 로 두면 [7.3절](07_oracle_and_phase_kickback.md#73-phase-kickback--형태-a가-형태-b로-변신하는-마법)의 kickback이 형태 B를 만들어 냅니다. 그동안 circuit은 어느 입력이 조건에 걸리는지 모르고, 알 필요도 없습니다. diffusion operator와 짝을 맞춘 전체 implementation은 [9장](09_grover_algorithm.md)에서 정리합니다.

> ❓ **emulator에서는?**: FPGA emulator는 이 sign flip을 physical gate가 아니라 **state vector의 해당 성분에 $-1$ 을 곱하는 연산**으로 구현합니다. 대상은 미리 못 박아 둔 solution index가 아니라 **predicate를 만족하는 모든 칸**이고, 판정하는 것도 index가 아니라 그 칸에 담긴 값 `value[i]` 입니다([13.3절](13_oracle_diffusion_measurement_datapath.md#133-oracle--predicate-4종이-subtractor-하나를-공유한다)). 이것이 oracle의 수치 implementation 전부입니다. 그래서 oracle을 정확히 이해하는 것이 hardware 설계의 출발점입니다.

우리 accelerator의 oracle도 이 장의 정의를 글자 그대로 지킵니다. 다른 점은 판정 대상이 index가 아니라 data라는 것뿐입니다 — `data_mem` 의 $i$ 번 값을 host가 넘긴 threshold와 견주어 `<`·`>`·`=`·범위 네 predicate 중 하나를 계산하고, 참인 칸에만 sign을 뒤집습니다([13.3절](13_oracle_diffusion_measurement_datapath.md#133-oracle--predicate-4종이-subtractor-하나를-공유한다)). sign flip 자체는 two's complement integer의 bit를 뒤집고 1을 더하는 것이라 multiplier가 필요 없습니다([13.4절](13_oracle_diffusion_measurement_datapath.md#134-sign-반전--twos-complement-negate-한-번)). 대신 대가도 이 장의 정의에서 그대로 따라옵니다 — circuit은 실행 전에 어느 칸이 뒤집힐지 모르므로 predicate를 만족하는 칸이 몇 개인지(number of solutions)도 미리 알 수 없고, Grover iteration을 몇 번 돌려야 하는지 모르는 채로 시작해야 합니다([16장](16_iteration_control_and_checkpoints.md)).

---

## 7.6 이 장의 요약

- **oracle $f:\{0,1\}^{\text{number of qubits}}\to\{0,1\}$**: solution이면 1, 아니면 0을 주는 black box. 내부는 모름.
- **형태 A (bit flip)**: $U_f|x\rangle|y\rangle = |x\rangle|y\oplus f(x)\rangle$. 여분 qubit에 XOR. 가역.
- **형태 B (phase oracle)**: $U_f|x\rangle = (-1)^{f(x)}|x\rangle$. 조건을 만족하는($f(x)=1$) 항의 amplitude **sign만** 뒤집음. Grover가 사용.
- **phase kickback**: 형태 A의 출력 qubit를 $|-\rangle$ 로 두면 $U_f|x\rangle|-\rangle = (-1)^{f(x)}|x\rangle|-\rangle$. 출력의 뒤집힘이 입력의 phase로 되차임 ⇒ 형태 A + $|-\rangle$ = 형태 B.
- **왜 $|-\rangle$**: $X|-\rangle = -|-\rangle$ (eigenstate)라 뒤집힘이 sign으로 전환. $|-\rangle = HX|0\rangle$.
- **conditional sign flip**: $U_f = I - 2\sum_{\omega\in A}|\omega\rangle\langle\omega|$ ($A$ = 조건을 만족하는 입력 집합, $\text{number of solutions}=|A|$). solution이 하나뿐인 경우는 special case. $A$ 의 원소들이 완전 대칭이라 증폭 뒤 amplitude가 정확히 같아집니다. 쌍둥이 diffusion operator와 함께 두 개의 reflection.
- 실제 implementation: multi-controlled $Z$ + $X$ 감싸기는 $f$ 를 circuit으로 갖고 있을 때 **phase oracle로 바꾸는** 방법이지 solution을 알아내는 방법이 아닙니다. emulator는 **predicate를 만족하는 모든 칸**의 성분에 $-1$ 을 곱합니다.

다음 장에서는 이 oracle과 interference를 결합한 **첫 실제 algorithm — Deutsch–Jozsa** 를 봅니다. phase kickback과 $H^{\otimes \text{number of qubits}}$ 가 어떻게 협력해 classical computer를 압도하는지, 완전한 계산으로 확인합니다.

---

> [← 6장 quantum circuit model과 범용성](06_quantum_circuit_model_and_universality.md) · [index](index.md) · [8장 Deutsch–Jozsa algorithm →](08_deutsch_jozsa_algorithm.md)
