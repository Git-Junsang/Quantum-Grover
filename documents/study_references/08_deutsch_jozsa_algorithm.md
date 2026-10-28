# 8장. Deutsch–Jozsa algorithm

> [← 7장 oracle과 phase kickback](07_oracle_and_phase_kickback.md) · [index](index.md) · [9장 Grover algorithm →](09_grover_algorithm.md)
> **이 장을 읽기 위한 준비**: [6장](06_quantum_circuit_model_and_universality.md) $H^{\otimes \text{number of qubits}}$·Hadamard 일반식, [7장](07_oracle_and_phase_kickback.md) oracle·phase kickback.

---

드디어 완전한 quantum algorithm 하나를 처음부터 끝까지 봅니다. **Deutsch–Jozsa algorithm**은 실용성은 떨어지지만, quantum computer가 classical computer를 **천문학적으로** 앞설 수 있음을 보여준 최초의 사례입니다. 무엇보다 [7장 phase kickback](07_oracle_and_phase_kickback.md)과 [6장 Hadamard interference](06_quantum_circuit_model_and_universality.md)가 어떻게 협력하는지를 명확한 계산으로 보여주기 때문에, [9장 Grover](09_grover_algorithm.md)를 이해하기 위한 완벽한 준비운동입니다.

---

## 8.1 풀려는 문제 — balanced인가 constant인가

function $f:\{0,1\}^{\text{number of qubits}} \to \{0,1\}$ 이 주어졌는데, 이 function이 다음 둘 중 하나임이 **보장**되어 있습니다.

- **constant function**: 모든 입력에 대해 항상 같은 값 (전부 0 또는 전부 1).
- **balanced function**: 입력의 정확히 절반은 0, 나머지 절반은 1로 매핑.

**질문**: $f$ 가 constant인가 balanced인가?

---

## 8.2 classical computer로는 얼마나 걸리나

classical computer로 확실히 판별하려면 최악의 경우 얼마나 많이 물어봐야 할까요? 입력은 총 $2^{\text{number of qubits}}$ 개입니다.

- **운이 좋으면**: 두 번 물어 서로 다른 값이 나오면 즉시 "balanced"로 확정.
- **최악의 경우**: 입력을 계속 물었는데 절반+1번($2^{\text{number of qubits}-1}+1$)까지 전부 같은 값이 나와야 비로소 "constant"라고 확정할 수 있음. (절반까지 모두 0이어도 나머지 절반이 1일 수 있으니, 절반을 넘겨봐야 안다.)

즉 classical computer는 최악의 경우 **$2^{\text{number of qubits}-1}+1$ 번**의 oracle 호출이 필요합니다. qubit가 늘어나면 지수적으로 늘어납니다.

이 비교에서 세는 단위는 처음부터 끝까지 **oracle을 몇 번 호출하는가**이고, 그 이득은 진짜 quantum hardware에서 성립하는 이야기입니다. $2^{\text{number of qubits}}$ 개의 amplitude를 memory에 펼쳐 놓고 계산하는 emulator는 oracle 한 번을 처리하는 데도 array 전체를 훑어야 하므로 호출 횟수의 이득을 그대로 물려받지 못합니다. emulator가 대신 보여 주는 것은 속도가 아니라, interference가 실제로 어떻게 답을 만들어 내는지를 한 칸씩 재현하고 검증할 수 있다는 점입니다.

> 🔑 **Deutsch–Jozsa의 충격**: quantum computer는 oracle을 **단 한 번** 호출해 100% 확실하게 답합니다. query complexity $O(1)$. classical computer의 $O(2^{\text{number of qubits}})$ 와 비교하면 exponential speedup입니다.

---

## 8.3 algorithm circuit

circuit 구조는 이렇습니다 (입력 qubit 여러 개 + 출력 qubit 1개):

```
 |0⟩ ─[H]─┬──────┬─[H]─| D |═ m0
 |0⟩ ─[H]─┤      ├─[H]─| D |═ m1
   ⋮       │  Uf  │       ⋮
 |0⟩ ─[H]─┤      ├─[H]─| D |═ m(number of qubits - 1)
 |1⟩ ─[H]─┴──────┴──────────  (출력 qubit, |−⟩로 준비)
```

단계:

1. 입력 qubit는 모두 $|0\rangle$, 출력 qubit는 $|1\rangle$ 로 시작.
2. **모든** qubit에 $H$ (출력 qubit는 $H|1\rangle = |-\rangle$ 가 됨 → [7장 phase kickback](07_oracle_and_phase_kickback.md) 준비).
3. oracle $U_f$ 한 번 적용.
4. 입력 qubit에 다시 $H^{\otimes \text{number of qubits}}$.
5. 입력 qubit measurement.

---

## 8.4 단계별 계산 — interference가 답을 만든다

### 1~2단계: uniform superposition + kickback 준비

입력 qubit에 $H^{\otimes \text{number of qubits}}$ 를 걸면([6.2절](06_quantum_circuit_model_and_universality.md#62-uniform-superposition-만들기--hotimes-textnumber-of-qubits)):

$$
|x\rangle^{\otimes \text{number of qubits}} = H^{\otimes \text{number of qubits}}|0\rangle^{\otimes \text{number of qubits}} = \frac{1}{\sqrt{2^{\text{number of qubits}}}}\sum_{x\in\{0,1\}^{\text{number of qubits}}}|x\rangle
$$

출력 qubit는 $H|1\rangle = |-\rangle = \frac{|0\rangle-|1\rangle}{\sqrt2}$.

### 3단계: oracle + phase kickback

출력 qubit가 $|-\rangle$ 이므로 [7.3절 phase kickback](07_oracle_and_phase_kickback.md#73-phase-kickback--형태-a가-형태-b로-변신하는-마법)이 발동합니다. oracle이 입력 각 항에 $(-1)^{f(x)}$ 를 붙입니다:

$$
U_f\left(\frac{1}{\sqrt{2^{\text{number of qubits}}}}\sum_x|x\rangle\right)|-\rangle = \left(\frac{1}{\sqrt{2^{\text{number of qubits}}}}\sum_x (-1)^{f(x)}|x\rangle\right)|-\rangle
$$

출력 qubit $|-\rangle$ 은 이제부터 곁다리 constant이므로 떼어놓고, 입력 register만 봅니다:

$$
|\phi\rangle = \frac{1}{\sqrt{2^{\text{number of qubits}}}}\sum_x (-1)^{f(x)}|x\rangle
$$

함숫값 $f(x)$ 가 amplitude의 **sign**에 새겨졌습니다.

### 4단계: 다시 $H^{\otimes \text{number of qubits}}$ — interference

여기에 [6.2절 Hadamard 일반식](06_quantum_circuit_model_and_universality.md#62-uniform-superposition-만들기--hotimes-textnumber-of-qubits) $H^{\otimes \text{number of qubits}}|x\rangle = \frac{1}{\sqrt{2^{\text{number of qubits}}}}\sum_v (-1)^{x\cdot v}|v\rangle$ 을 적용:

$$
H^{\otimes \text{number of qubits}}|\phi\rangle = \frac{1}{2^{\text{number of qubits}}}\sum_x (-1)^{f(x)}\sum_v (-1)^{x\cdot v}|v\rangle = \frac{1}{2^{\text{number of qubits}}}\sum_v\left[\sum_x (-1)^{f(x)+x\cdot v}\right]|v\rangle
$$

우리는 특히 **$|v\rangle = |0\cdots0\rangle$ state의 amplitude**에 주목합니다. $v = 0$ 이면 $x\cdot v = 0$ 이므로 그 amplitude는:

$$
\text{($|0\cdots0\rangle$ 의 amplitude)} = \frac{1}{2^{\text{number of qubits}}}\sum_x (-1)^{f(x)}
$$

### 5단계: 두 경우 분석

**$f$ 가 constant면** — 모든 $f(x)$ 가 같은 값 $c$:

$$
\frac{1}{2^{\text{number of qubits}}}\sum_x (-1)^{c} = \frac{1}{2^{\text{number of qubits}}}\cdot(-1)^c\cdot 2^{\text{number of qubits}} = (-1)^c = \pm1
$$

$|0\cdots0\rangle$ 의 amplitude가 $\pm1$! normalization 때문에 다른 모든 amplitude는 0이어야 합니다. 따라서 measurement를 하면 **100% probability로 $|0\cdots0\rangle$**.

**$f$ 가 balanced면** — 절반은 $(-1)^0=+1$, 절반은 $(-1)^1=-1$:

$$
\frac{1}{2^{\text{number of qubits}}}\sum_x (-1)^{f(x)} = \frac{1}{2^{\text{number of qubits}}}(\underbrace{+1\cdots+1}_{2^{\text{number of qubits}-1}\text{개}} \underbrace{-1\cdots-1}_{2^{\text{number of qubits}-1}\text{개}}) = \frac{1}{2^{\text{number of qubits}}}\cdot 0 = 0
$$

$+1$ 들과 $-1$ 들이 **완벽히 상쇄**됩니다. $|0\cdots0\rangle$ 의 amplitude가 0이므로, measurement를 하면 **절대로 $|0\cdots0\rangle$ 이 안 나옵니다**.

---

## 8.5 결론 — measurement 한 번으로 판별

> 🔑 **판별 규칙**
>
> - measurement 결과가 $|0\cdots0\rangle$ (전부 0) → **$f$ 는 constant**. (probability 100%)
> - measurement 결과에 1이 하나라도 있음 → **$f$ 는 balanced**. (probability 100%)

oracle 단 한 번으로 확실하게 판별했습니다. 이 마법의 정체는 **interference**입니다:

- constant일 때: 모든 항의 phase가 같아 $|0\cdots0\rangle$ 로 **constructive interference**.
- balanced일 때: phase가 반반이라 $|0\cdots0\rangle$ 에서 **destructive interference**.

💡 **비유**: $2^{\text{number of qubits}}$ 개의 파도(amplitude)를 만들어 한 지점($|0\cdots0\rangle$)에 모읍니다. constant function은 모든 파도가 같은 phase(마루끼리)라 크게 겹쳐 솟고, balanced function은 마루와 골이 반반이라 그 지점에서 잔잔해집니다. 파도의 높이를 재면(measurement) 어느 쪽인지 압니다.

✏️ **연습 8-1**: 3 qubits에서 $f$ 가 balanced function일 때, 마지막 measurement에서 $|000\rangle$ 이 나올 probability는? *(답: $0$. balanced면 $|0\cdots0\rangle$ amplitude가 상쇄돼 0. [10장](10_glossary_and_cheat_sheet.md#106-연습문제-답)에 풀이.)*

---

## 8.6 Deutsch–Jozsa에서 배울 것 — Grover로 가는 다리

이 algorithm의 실용성은 낮습니다(constant/balanced 판별은 현실 문제가 아님). 하지만 **quantum algorithm의 3박자 구조**를 완벽히 보여줍니다:

| 단계        | Deutsch–Jozsa                        | 다음 장 Grover                        |
| ----------- | ------------------------------------ | ------------------------------------- |
| ① 펼치기   | $H^{\otimes \text{number of qubits}}$ 로 uniform superposition        | $H^{\otimes \text{number of qubits}}$ 로 uniform superposition         |
| ② 표시하기 | oracle + phase kickback →$(-1)^{f(x)}$ | oracle → 조건을 만족하는 항의 sign flip |
| ③ interference     | $H^{\otimes \text{number of qubits}}$ 한 번 → destructive/constructive interference | **iteration마다** diffusion operator → 점진 증폭 |

가장 큰 차이는 ③입니다. Deutsch–Jozsa는 interference **한 번**으로 답이 딱 떨어지지만(구조가 특수해서), Grover는 solution이 여럿 섞인 일반 search라 **Grover iteration을 여러 번** 돌려 amplitude를 조금씩 키워야 합니다. 그 number of iterations는 조건을 만족하는 항이 하나뿐일 때 대략 $\frac{\pi}{4}\sqrt{\text{number of states}}$ 번이고, 그런 항이 여러 개면 $\frac{\pi}{4}\sqrt{\text{number of states}/\text{number of solutions}} - \frac12$ 로 줄어듭니다([9.5절](09_grover_algorithm.md#95-왜-여러-번--왜-sqrttextnumber-of-states-번--왜-pi)). 이것이 $O(\sqrt{\text{number of states}})$ 의 근원인데, 여기서도 세는 단위는 oracle 호출 횟수입니다.

> ❓ **원문의 Deutsch algorithm과 Deutsch–Jozsa?**: 원래 Deutsch algorithm은 입력 qubit가 하나뿐인 초기 version이고, Deutsch–Jozsa는 이를 여러 qubit로 확장한 것입니다. 원리는 위 계산과 동일합니다.

우리가 만드는 accelerator는 Deutsch–Jozsa를 돌리지 않습니다. accelerator가 아는 연산은 predicate 판정과 inversion about the mean뿐이고 이 장의 circuit은 그 목록에 없습니다. 그런데도 이 장이 해설서에 남아 있는 이유는 하나입니다 — **interference가 어떻게 답을 만들어 내는지를 처음부터 끝까지 수식으로 계산해 보이는 유일한 대목**이기 때문입니다. 8.4절에서 $\frac{1}{2^{\text{number of qubits}}}\sum_x(-1)^{f(x)}$ 가 phase가 같으면 보강해 $\pm1$ 이 되고 반반이면 상쇄해 $0$ 이 되는 것을 손으로 확인했는데, 다음 장에서 solution amplitude는 키우고 non-solution amplitude는 눌러 놓는 diffusion operator가 하는 일이 바로 그 constructive interference와 destructive interference입니다([9.3절](09_grover_algorithm.md#93-핵심-장면--막대-두-번-흔들기)). circuit에서는 그 interference가 inversion about the mean이라는 subtraction 한 줄로 나타납니다([13.5절](13_oracle_diffusion_measurement_datapath.md#135-diffusion-operator--2mean--amp가-circuit이-되는-순간)).

---

## 8.7 이 장의 요약

- **문제**: $f$ 가 constant(전부 같은 값)인가 balanced(절반씩 0/1)인가?
- **classical computer**: 최악 $2^{\text{number of qubits}-1}+1$ 회 oracle 호출 ($O(2^{\text{number of qubits}})$).
- **quantum**: oracle **1회** — query complexity $O(1)$. exponential speedup(세는 단위는 oracle 호출 횟수이고, amplitude를 펼쳐 계산하는 emulator는 이 이득을 물려받지 못합니다).
- **circuit**: $H^{\otimes \text{number of qubits}}$ → $U_f$(phase kickback, 출력 qubit $|-\rangle$) → $H^{\otimes \text{number of qubits}}$ → measurement.
- **핵심 계산**: $|0\cdots0\rangle$ amplitude $= \frac{1}{2^{\text{number of qubits}}}\sum_x(-1)^{f(x)}$. constant면 $\pm1$(constructive interference), balanced면 $0$(destructive interference).
- **판별**: measurement가 전부 0 → constant, 1이 있으면 → balanced. probability 100%.
- **Grover로의 다리**: 펼치기-표시-interference의 3박자. Grover는 interference를 **Grover iteration마다** 되풀이해 점진 증폭 → $O(\sqrt{\text{number of states}})$ (조건을 만족하는 항이 여러 개면 $\frac{\pi}{4}\sqrt{\text{number of states}/\text{number of solutions}}-\frac12$ 회).

다음 장은 이 해설서의 정점, **Grover algorithm**입니다. amplitude amplification·inversion about the mean·diffusion operator·geometric rotation을 모두 동원해, 정렬 안 된 항목들 가운데서 solution을 $O(\sqrt{\text{number of states}})$ 에 찾아내는 과정을 완전히 해부합니다.

---

> [← 7장 oracle과 phase kickback](07_oracle_and_phase_kickback.md) · [index](index.md) · [9장 Grover algorithm →](09_grover_algorithm.md)
