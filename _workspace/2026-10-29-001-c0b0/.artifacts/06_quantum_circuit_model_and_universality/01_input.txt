# 6장. quantum circuit model과 universality

> [← 5장 multi-qubit와 entanglement](05_multiple_qubits_and_entanglement.md) · [index](index.md) · [7장 oracle과 phase kickback →](07_oracle_and_phase_kickback.md)
> **이 장을 읽기 위한 준비**: [3장](03_single_qubit_gates.md) gate, [4장](04_measurement.md) measurement, [5장](05_multiple_qubits_and_entanglement.md) multi-qubit·$2^{\text{number of qubits}}$·CNOT.

---

부품이 다 모였습니다: qubit([1장](01_qubits_and_states.md)), single-qubit gate([3장](03_single_qubit_gates.md)), measurement([4장](04_measurement.md)), CNOT([5장](05_multiple_qubits_and_entanglement.md)). 이 장에서는 이들을 조립해 **quantum computation이 무엇인지**를 딱 세 단계로 정의하고, algorithm에 꼭 필요한 기법 — **$H^{\otimes \text{number of qubits}}$ 로 uniform superposition 만들기** — 를 정리합니다. 또 classical computation을 quantum으로 옮기는 데 필요한 Toffoli gate와 universality도 짚습니다. 이 장이 끝나면 [7장](07_oracle_and_phase_kickback.md)부터 실제 algorithm으로 들어갑니다.

---

## 6.1 quantum computation — 딱 세 단계

일반적인 quantum computation은 놀랍도록 단순한 세 단계입니다.

> 🔑 **quantum computation의 3단계**
> 1. **initialization**: 모든 qubit를 computational basis state(보통 $|00\cdots0\rangle$)로 준비한다.
> 2. **gate 적용**: single-qubit gate와 CNOT을 순서대로 적용한다.
> 3. **measurement**: computational basis로 measurement한다. 결과 $00\cdots0$ 이 나올 probability는 해당 amplitude의 absolute value square.

이게 전부입니다. "이게 다야?"라는 말이 나올 만큼 단순하지만, 이 안에 놀라운 깊이가 있습니다. circuit diagram으로 그리면:

```
 |0⟩ ─[H]─────●────[?]──| D |═ m0
              │
 |0⟩ ─[H]────[X]───[?]──| D |═ m1
 |0⟩ ─[H]──────────[?]──| D |═ m2
       ↑        ↑         ↑
 superposition  CNOT 등  measurement
```

우리 project의 FPGA emulator도 이 3단계를 그대로 밟습니다. 다만 2단계를 **gate 하나하나의 matrix multiplication으로 처리하지 않는다**는 점이 중요합니다. ① initialization은 $H^{\otimes \text{number of qubits}}$ 라는 gate를 실제로 돌리는 대신, 그 결과가 어차피 모든 칸이 $\frac{1}{\sqrt{\text{number of states}}}$ 임을 미리 알고 amplitude array 전 칸에 그 constant를 써 넣는 한 번의 쓰기 pass입니다. ② 그다음은 gate가 아니라 **oracle과 diffusion operator라는 두 operator**를 통째로 정해진 횟수만큼 반복 적용합니다. 한 번의 iteration은 32 lanes가 amplitude array를 두 번 훑는 2 passes이고, 이 경로에는 multiplier가 한 개도 없습니다([13장](13_oracle_diffusion_measurement_datapath.md)). ③ measurement는 amplitude의 square를 probability로 삼아 random number로 하나를 뽑는 **Born-rule sampling**입니다 — 가장 큰 amplitude를 고르는 것이 아닙니다([14.4절](14_multiple_solutions_and_minimum_search.md#144-born-rule-sampling--probability를-circuit으로)). 임의의 gate matrix를 받아 곱해 주는 general-purpose engine을 만들지 않는 이유는 간단합니다: Grover가 쓰는 unitary는 oracle과 diffusion operator **둘로 고정**되어 있어서, 그 둘을 circuit으로 굳혀 두는 편이 훨씬 싸기 때문입니다. 설계값의 source of truth는 [15.4절](15_paper_map_and_design_decisions.md#154-우리-project의-좌표--확정-설계-결정표)입니다.

---

## 6.2 uniform superposition 만들기 — $H^{\otimes \text{number of qubits}}$

거의 모든 quantum algorithm의 **첫 단계**는 "모든 가능성을 동시에 담기" 위해 모든 qubit에 Hadamard를 거는 것입니다.

$$H^{\otimes \text{number of qubits}}|0\rangle^{\otimes \text{number of qubits}} = \frac{1}{\sqrt{2^{\text{number of qubits}}}}\sum_{x \in \{0,1\}^{\text{number of qubits}}} |x\rangle$$

즉 $|00\cdots0\rangle$ 에서 시작해 각 qubit에 $H$ 를 걸면, $2^{\text{number of qubits}}$ 개의 모든 computational basis state가 **똑같은 amplitude $\frac{1}{\sqrt{2^{\text{number of qubits}}}}$** 로 담긴 uniform superposition이 됩니다.

🔍 **계산 따라가기 — 2 qubits**

$$H|0\rangle \otimes H|0\rangle = \frac{|0\rangle+|1\rangle}{\sqrt2} \otimes \frac{|0\rangle+|1\rangle}{\sqrt2} = \frac12(|00\rangle + |01\rangle + |10\rangle + |11\rangle)$$

네 state가 각각 amplitude $\frac12 = \frac{1}{\sqrt{4}}$. normalization: $4\times\frac14 = 1$. ✓

> 🔑 **핵심 — "$2^{\text{number of qubits}}$ 개를 한꺼번에"**: qubit마다 $H$ gate 하나씩이라는 아주 적은 resource로 $2^{\text{number of qubits}}$ 개 state를 동시에 담습니다. 이 uniform superposition이 [8장 Deutsch-Jozsa](08_deutsch_jozsa_algorithm.md)와 [9장 Grover](09_grover_algorithm.md)의 출발선입니다. Grover에서는 이 state를 $|\psi\rangle$ 라 부릅니다.

### Hadamard 수학 — sign까지 담은 일반식

한 qubit에서 $u \in \{0,1\}$ 에 대해:

$$H|u\rangle = \frac{1}{\sqrt2}\big(|0\rangle + (-1)^u|1\rangle\big) = \frac{1}{\sqrt2}\sum_{v\in\{0,1\}}(-1)^{uv}|v\rangle$$

$(-1)^u$ 인수는 probability(absolute value)에는 영향이 없지만 **phase(sign)** 에는 영향을 줍니다 — 물리학자들이 **phase change**라 부르는 것. qubit 여러 개로 확장하면:

$$H^{\otimes \text{number of qubits}}|u\rangle = \frac{1}{\sqrt{2^{\text{number of qubits}}}}\sum_{v\in\{0,1\}^{\text{number of qubits}}}(-1)^{u\cdot v}|v\rangle$$

여기서 $u\cdot v$ 는 bit별 inner product입니다. 이 일반식이 [8장](08_deutsch_jozsa_algorithm.md)에서 interference를 계산하는 핵심 도구가 되니, 지금은 "$H$ 는 $(-1)^{u\cdot v}$ sign을 뿌린다"만 기억해 두세요.

✏️ **연습 6-1**: $H^{\otimes 3}|000\rangle$ 에서 computational basis state $|101\rangle$ 의 amplitude는 얼마일까요? *(answer: $\frac{1}{\sqrt8}$. [10장](10_glossary_and_cheat_sheet.md#106-연습문제-답)에 풀이.)*

---

## 6.3 quantum parallelism과 그 한계

uniform superposition $\frac{1}{\sqrt{2^{\text{number of qubits}}}}\sum_x|x\rangle$ 에 function $f$ 를 계산하는 oracle을 한 번 걸면, 원리적으로 $2^{\text{number of qubits}}$ 개 입력에 대한 $f$ 값이 **한 번에** 계산됩니다. 이를 **quantum parallelism**이라 합니다.

하지만 여기 결정적인 함정이 있습니다.

> ⚠️ **함정 — parallelism만으로는 공짜 점심이 없다**: $2^{\text{number of qubits}}$ 개 답을 동시에 "계산"해도, [4장](04_measurement.md)에서 배웠듯 **measurement하면 그중 딱 하나만** 무작위로 나옵니다. 나머지는 collapse로 사라집니다. 그래서 단순히 병렬 계산만으로는 이득이 없습니다.

진짜 비결은 **interference** 입니다: 원하는 답의 amplitude는 보강하고 원치 않는 답의 amplitude는 상쇄시켜, **measurement에서 solution이 높은 probability로 나오게** 만드는 것. [3.4절 $HH=I$](03_single_qubit_gates.md#34-hadamard-gate-h--superposition을-만드는-열쇠)에서 본 상쇄·보강이 바로 이 도구입니다. Deutsch-Jozsa와 Grover는 서로 다른 방식으로 이 interference를 설계합니다.

💡 **비유**: quantum parallelism은 "모든 복권을 동시에 사는 것"입니다. 하지만 긁을 수 있는 건 한 장뿐. interference는 "당첨 복권만 두껍게, 꽝 복권은 얇게" 조작해, 아무거나 한 장 긁어도 당첨될 probability를 높이는 기술입니다.

"measurement하면 collapse한다"는 것은 실기 quantum 장치의 이야기입니다. 우리 emulator의 amplitude는 BRAM에 적힌 숫자일 뿐이고, Measurement Unit은 그 array를 읽어 square를 probability로 삼아 하나를 뽑을 뿐 amplitude에 한 글자도 쓰지 않습니다 — **읽기 전용**입니다([16.5절](16_iteration_control_and_checkpoints.md#165-checkpoint--measurement가-읽기-전용이라는-사실에서)). 그렇다고 위 함정을 피해 가는 것은 아닙니다. measurement 한 번이 답 후보 하나이고, 이 한 번을 **shot**이라 부릅니다. solution이 몇 개인지 모르는 채로 도는 우리 설계는 답 하나를 얻기까지 mean 22.7 shots가 듭니다(14 qubits·1 solution, board benchmark와 같은 100 workloads, [16.3절](16_iteration_control_and_checkpoints.md#163-shot-통계--mean이-20-shots를-넘는-이유)). collapse가 없다는 사실이 벌어 주는 것은 답의 개수가 아니라, 실패한 shot이 남긴 amplitude array를 다음 shot이 이어받을 수 있다는 점입니다.

---

## 6.4 classical computation을 quantum으로 — reversibility 문제

quantum computer가 classical computer보다 최소한 못하지 않으려면, 임의의 classical circuit을 quantum circuit으로 옮길 수 있어야 합니다. NOT은 쉽습니다 — 그냥 $X$ gate. 문제는 **AND** 입니다.

AND gate는 입력 2-bit $x, y$ → 출력 1-bit $x\wedge y$. 그런데 [3.7절](03_single_qubit_gates.md#37-unitary의-또-다른-성질--reversibility)에서 봤듯 quantum gate는 **reversible**해야 하고, unitary gate는 들어간 만큼의 qubit가 그대로 나옵니다. 입력 2 → 출력 1인 AND는 **irreversible**이라 그대로는 quantum gate가 될 수 없습니다.

> ❓ **왜 AND는 irreversible인가?**: 출력이 0이라는 것만 보고는 입력이 $00, 01, 10$ 중 무엇이었는지 복원할 수 없습니다(정보 손실). 반면 quantum gate는 정보를 잃지 않습니다.

---

## 6.5 Toffoli gate — reversible AND

해결책은 **Toffoli gate**(controlled-controlled-NOT, CCNOT)입니다. CNOT과 비슷하지만 **control qubit가 두 개**($x, y$)이고 target qubit가 하나($z$)입니다. 두 control qubit가 **모두** 1일 때만 target qubit를 뒤집습니다:

$$|x, y, z\rangle \to |x, y, z\oplus(x\wedge y)\rangle$$

target qubit를 $z=0$ 으로 시작하면 출력의 셋째 qubit가 $x\wedge y$ — 바로 AND입니다! 여분의 qubit를 하나 쓰는 대가로 reversibility를 얻습니다. Toffoli + $X$ 로 임의의 classical circuit(AND·NOT은 universal set)을 quantum circuit으로 옮길 수 있습니다.

Toffoli 자체는 기본 gate set에 없지만, **CNOT과 single-qubit gate들로 조립**할 수 있습니다. 그 구체적 circuit은 외워둘 필요 없이 "필요하면 찾아 쓰면 되는 것"입니다.

> 🔑 **universal gate set**: single-qubit gate + CNOT 만으로 임의의 unitary 연산을 (원하는 precision으로) 근사할 수 있습니다. 이를 **universal**이라 합니다. classical computing의 "NAND만으로 모든 circuit"에 대응합니다. Toffoli는 여기에 classical logic를 얹는 다리 역할입니다.

이 oracle을 reversible하게 구현하는 아이디어 — "여분 qubit에 $\oplus f(x)$ 로 결과를 쓴다" — 가 [7장 oracle](07_oracle_and_phase_kickback.md) $U_f|x\rangle|y\rangle = |x\rangle|y\oplus f(x)\rangle$ 의 정확한 형태입니다.

---

## 6.6 circuit의 순효과는 하나의 unitary

measurement 전까지, 여러 gate를 순서대로 적용한 circuit 전체의 효과는 **하나의 큰 unitary matrix** $U = U_k \cdots U_2 U_1$ 입니다 (unitary의 product는 unitary). 그래서 quantum circuit = state space 위의 하나의 unitary transformation, 그리고 마지막에 measurement. 이 관점이 [9장 Grover](09_grover_algorithm.md)에서 "oracle과 diffusion operator의 product를 여러 번 적용"을 분석할 때 유용합니다.

이 사실은 hardware에서 뜻밖의 배당금을 냅니다. Grover iteration 한 번을 $G = D\,O$(oracle $O$ 뒤에 diffusion operator $D$)라 쓰면 이를 반복한 circuit 전체가 $G^{\text{number of iterations}}$ 라는 **하나의** unitary이고, matrix multiplication은 associative하므로 다음이 성립합니다:

$$(D O)^{\,\text{target iterations}} = (D O)^{\,\text{target iterations} - \text{completed iterations}} \cdot (D O)^{\,\text{completed iterations}}$$

왼쪽은 "처음부터 target iterations만큼 돌린다"이고, 오른쪽은 "이미 completed iterations만큼 돌아 있는 state에서 차이만큼만 더 돌린다"입니다. 둘은 같은 operation이므로 도달한 state도 같습니다. 이 한 줄이 뒤에서 실패한 shot의 amplitude array를 버리지 않고 이어 쓰는 **checkpoint**의 정당성 근거가 됩니다([16.6절](16_iteration_control_and_checkpoints.md#166-왜-결과가-달라지지-않는가)).

6.4~6.5에서 본 reversibility 제약은 state를 물리적으로 들고 있는 실기 quantum에만 걸립니다. 우리 emulator는 unitary의 **효과**를 숫자로 재현할 뿐이라, oracle 안의 Predicate Unit을 reversible logic로 짤 이유가 없습니다 — `value < thr` 같은 비교는 subtractor 하나와 그 sign bit로 끝나고, Toffoli 분해도 여분의 ancilla qubit도 등장하지 않습니다([13.3절](13_oracle_diffusion_measurement_datapath.md#133-oracle--predicate-4종이-subtractor-하나를-공유한다)). universal gate set도 같은 자리에 놓입니다. 그것은 "이 부품들로 어떤 quantum algorithm이든 만들 수 있다"는 가능성의 정리이지, 우리가 만들 기계가 universal해야 한다는 요구가 아닙니다. Toffoli와 CNOT은 우리에게 synthesis할 circuit이 아니라 논문의 circuit diagram을 읽는 언어로 남습니다.

---

## 6.7 이 장의 요약

- **quantum computation 3단계**: ① $|0\cdots0\rangle$ initialization → ② single-qubit gate + CNOT 적용 → ③ computational basis measurement($\text{probability} = |\text{amplitude}|^2$).
- **$H^{\otimes \text{number of qubits}}|0\rangle^{\otimes \text{number of qubits}} = \frac{1}{\sqrt{2^{\text{number of qubits}}}}\sum_x|x\rangle$**: 모든 algorithm의 첫 단계. qubit마다 gate 하나로 $2^{\text{number of qubits}}$ states의 uniform superposition.
- **Hadamard 일반식**: $H^{\otimes \text{number of qubits}}|u\rangle = \frac{1}{\sqrt{2^{\text{number of qubits}}}}\sum_v (-1)^{u\cdot v}|v\rangle$. sign(phase)를 뿌림 → interference의 도구.
- **quantum parallelism의 한계**: $2^{\text{number of qubits}}$ 개를 계산해도 measurement는 하나만. 진짜 비결은 **interference**(solution 보강·non-solution 상쇄).
- **reversibility**: AND는 irreversible → 그대로는 quantum gate 불가.
- **Toffoli(CCNOT)**: reversible AND. $|x,y,z\rangle\to|x,y,z\oplus(x\wedge y)\rangle$. + $X$ 로 classical circuit을 quantum circuit으로.
- **universality**: single-qubit gate + CNOT = universal. circuit 전체 = 하나의 unitary.

여기까지가 quantum computing의 **model 전체**입니다. 다음 장(7장)부터는 이 model로 실제 algorithm을 만듭니다. 첫 주제는 algorithm이 "solution이 무엇인지"를 아는 통로 — **oracle** — 과 그 마법 같은 트릭 **phase kickback** 입니다.

---

> [← 5장 다중 qubit와 entanglement](05_multiple_qubits_and_entanglement.md) · [index](index.md) · [7장 oracle과 phase kickback →](07_oracle_and_phase_kickback.md)
