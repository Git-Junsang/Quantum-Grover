# 부록 A. 수학 빠른 복습 — complex number와 linear algebra

> [index](index.md) · [1장 qubit와 state →](01_qubits_and_states.md)
> **성격**: 참조용. 이 해설서가 *실제로 쓰는* 수학만 추렸습니다. 완전한 강의가 아니라, 본문을 읽다 막혔을 때 돌아와 확인하는 최소 사전입니다.

---

이 해설서는 두 가지 배경 지식에 기댑니다. [1장](01_qubits_and_states.md)부터 [9장](09_grover_algorithm.md)까지의 quantum 계산은 **complex number**와 **linear algebra(vector·matrix)** 위에서 돌아가고, [11장](11_state_vector_emulator.md) 이후의 hardware 설계는 **binary fixed-point arithmetic**과 **기초 probability**를 씁니다. 처음 배우거나 오래 잊었다면 앞쪽에서는 $\alpha^*$, $|\alpha|^2$, $e^{i\theta}$, matrix multiplication에서 멈추게 되고, 뒤쪽에서는 Q1.22 같은 Q format이나 arithmetic shift, prefix sum에서 다시 멈추게 됩니다.

그래서 이 부록도 두 부분으로 나뉩니다 — **A.1~A.4가 quantum 계산 쪽, A.5~A.6이 hardware 쪽**입니다. 처음부터 순서대로 읽을 것은 아니고 막힌 기호가 있는 절만 펴 보면 됩니다. 여기 있는 것만 알면 9장까지의 손계산과 [12장](12_fixed_point_and_precision.md)의 수 표현, [16장](16_iteration_control_and_checkpoints.md)의 shot 통계를 손으로 따라갈 수 있습니다.

---

## A.1 complex number

**imaginary unit** $i$ 는 square가 $-1$ 이 되는 수입니다: $i^2 = -1$. real number 범위에서는 square가 negative number인 수가 없으므로, 그런 수를 새로 하나 들여온 것입니다.

**complex number**는 real number 두 개를 붙인 $\alpha = a + bi$ 꼴입니다. $a$ 를 real part, $b$ 를 imaginary part라 부릅니다. complex number는 평면 위의 한 점 $(a, b)$ 로 볼 수 있어서, "complex plane"에 화살표로 그리곤 합니다.

**complex conjugate**는 imaginary part의 sign만 뒤집은 것으로, 별표로 씁니다: $\alpha^* = a - bi$. 예를 들어 $(3 + 4i)^* = 3 - 4i$ 입니다. complex conjugate는 곧 배울 bra([2장](02_dirac_notation_and_linear_algebra.md))와 probability 계산에서 계속 등장합니다.

**absolute value(크기)**는 원점에서 그 점까지의 거리입니다:

$$|\alpha| = \sqrt{a^2 + b^2}, \qquad |\alpha|^2 = a^2 + b^2 = \alpha^*\alpha$$

마지막 등식 $|\alpha|^2 = \alpha^*\alpha$ 가 특히 중요합니다. $\alpha^*\alpha = (a-bi)(a+bi) = a^2 + b^2$ 이므로 항상 **non-negative real number**가 됩니다. 이 해설서 전체에서 **measurement probability = amplitude의 absolute value square**$= |\alpha|^2$ 이라는 규칙([4장 Born rule](04_measurement.md))이 나오는데, 여기서 probability가 언제나 0 이상의 real number가 되는 이유가 바로 이 성질입니다. 예: $|3+4i| = \sqrt{9+16} = 5$, $|3+4i|^2 = 25$.

**Euler's formula와 phase.** 크기가 1인 complex number는 전부 다음 꼴로 쓸 수 있습니다:

$$e^{i\theta} = \cos\theta + i\sin\theta$$

이것은 complex plane의 **unit circle 위**의 점이고($|e^{i\theta}| = 1$), 각도 $\theta$ 를 **phase**라 부릅니다. 몇 개만 외워두면 편합니다: $e^{i0}=1$, $e^{i\pi/2}=i$, $e^{i\pi}=-1$, $e^{i2\pi}=1$. 임의의 complex number는 크기와 phase로 $\alpha = r\,e^{i\theta}$ (polar form)처럼 분해됩니다. sign $-1 = e^{i\pi}$ 도 phase의 특수한 경우라, quantum에서 "solution state의 sign을 뒤집는다"는 말이 곧 "phase를 $\pi$ 만큼 돌린다"는 뜻입니다([3장 $Z$](03_single_qubit_gates.md), [7장 oracle](07_oracle_and_phase_kickback.md)).

정리하면, quantum computing이 real number 대신 complex number를 쓰는 이유는 이렇습니다. amplitude가 complex number라야 크기(→ probability)와 phase(→ interference)라는 **두 가지 정보**를 동시에 담을 수 있고, phase들이 서로 더해지고 상쇄되는 **interference**가 algorithm의 핵심 동력이 되기 때문입니다.

다만 이 해설서가 끝까지 따라가는 표준 Grover만큼은 예외입니다 — amplitude가 처음부터 끝까지 real number로만 유지되어 complex number가 필요 없고([9.8절](09_grover_algorithm.md#98-전체-그림-정리--amplitude는-왜-real-number뿐인가)), 이것이 amplitude 한 칸을 fixed-point real number **하나**로 저장하는([A.5](#a5-fixed-point-arithmetic)) 근거이자 complex phase를 amplitude에 직접 곱하는 quantum phase estimation 계열을 설계에서 제외한 이유입니다.

---

## A.2 vector

이 해설서에서 qubit state는 성분이 complex number인 **column vector** 입니다. qubit 하나는 성분 두 개짜리 vector죠:

$$|\psi\rangle = \begin{bmatrix} \alpha \\ \beta \end{bmatrix}$$

vector의 **norm**은 성분들의 absolute value square를 더해 square root를 씌운 것입니다:

$$\big\||\psi\rangle\big\| = \sqrt{|\alpha|^2 + |\beta|^2}$$

크기가 1인 vector를 **unit vector**라 하고, 어떤 vector를 그 크기로 나눠 unit vector로 만드는 일을 **normalization**이라 합니다. 이 해설서에서 **모든 qubit state는 unit vector**입니다 — 즉 $|\alpha|^2 + |\beta|^2 = 1$ ([1장](01_qubits_and_states.md)). 그 이유(measurement probability의 sum이 1)는 [4장](04_measurement.md)에서 밝혀집니다. qubit가 여러 개로 늘면 vector의 성분 수가 $2^{\text{number of qubits}}$ 개로 늘 뿐, "state = unit vector"라는 원칙은 똑같습니다([5장](05_multiple_qubits_and_entanglement.md)).

$2^{\text{number of qubits}}$ 라는 수는 이 해설서에서 두 가지 일을 합니다. 하나는 방금 말한 **성분의 개수**이고, 다른 하나는 그 성분에 붙는 **번호(index)** 입니다. 성분에 $0$ 부터 $2^{\text{number of qubits}} - 1$ 까지 번호를 매기면 번호 하나가 qubit마다 bit 하나씩인 binary number 하나와 일대일로 대응하고, 그래서 $|x\rangle$ 의 $x$ 를 어떤 곳에서는 bit string으로, 어떤 곳에서는 integer로 부릅니다. 우리 설계는 14 qubits이므로 $2^{14} = 16{,}384$ states이고 index는 **14 bits**입니다.

binary number의 성질 하나만 더 챙기면 뒤쪽 절반이 훨씬 편해집니다. 어떤 수의 **하위 $k$ bit는 그 수를 $2^k$ 로 나눈 나머지**이고, 남는 위쪽 bit는 **몫**입니다. index $i$ 라면 하위 5 bits가 $i \bmod 32$, 상위 9 bits가 $\lfloor i/32 \rfloor$ 인 것이죠. 그래서 14-bit index를 위아래로 자르기만 하면 divider 없이 두 정보가 동시에 나옵니다 — 하위 5 bits는 row 안의 몇 번째 lane인지, 상위 9 bits는 몇 번째 row인지입니다. [11.7절](11_state_vector_emulator.md#117-병렬도와-banking)의 row · lane 배치는 이 한 줄에서 시작합니다.

---

## A.3 matrix와 matrix multiplication

**matrix**는 숫자를 직사각형으로 배열한 것이고, 이 해설서에서 gate는 대부분 $2\times2$ matrix입니다([3장](03_single_qubit_gates.md)).

**matrix × vector.** gate를 qubit에 "적용"하는 것이 바로 이 곱입니다. $2\times2$ matrix에 성분 2개짜리 vector를 곱하는 규칙은 이렇습니다:

$$\begin{bmatrix} a & b \\ c & d \end{bmatrix}\begin{bmatrix} x \\ y \end{bmatrix} = \begin{bmatrix} ax + by \\ cx + dy \end{bmatrix}$$

즉 결과의 $k$ 번째 성분은 "matrix의 $k$ 번째 **row**와 vector를 원소끼리 곱해 더한 값"입니다. 구체적인 예로, $X$ gate([3장](03_single_qubit_gates.md))가 amplitude를 맞바꾸는 것을 확인해 봅시다:

$$\begin{bmatrix} 0 & 1 \\ 1 & 0 \end{bmatrix}\begin{bmatrix} \alpha \\ \beta \end{bmatrix} = \begin{bmatrix} 0\cdot\alpha + 1\cdot\beta \\ 1\cdot\alpha + 0\cdot\beta \end{bmatrix} = \begin{bmatrix} \beta \\ \alpha \end{bmatrix}$$

**matrix × matrix.** gate를 연달아 적용하면 matrix끼리 곱하게 됩니다([3장](03_single_qubit_gates.md), [6장](06_quantum_circuit_model_and_universality.md)). 곱 $AB$ 의 $(i, j)$ 성분은 "$A$ 의 $i$ 번째 row"와 "$B$ 의 $j$ 번째 column"을 원소끼리 곱해 더한 값입니다. 주의할 점은 matrix multiplication은 **순서를 바꾸면 값이 달라진다**는 것($AB \ne BA$ 가 보통)이고, 그래서 [3장](03_single_qubit_gates.md)에서 "circuit의 gate 순서와 matrix multiplication의 순서가 반대"라는 함정이 생깁니다.

**transpose와 conjugate transpose.** matrix의 row와 column을 뒤바꾼 것을 **transpose** $A^T$ 라 하고, transpose한 뒤 모든 성분의 complex conjugate를 취한 것을 **conjugate transpose(dagger)** $A^\dagger = (A^T)^*$ 라 합니다. 이 $\dagger$ 는 bra와 unitary 조건($U^\dagger U = I$)에서 핵심이 되며, [2장](02_dirac_notation_and_linear_algebra.md)에서 본격적으로 다룹니다. 여기서는 "transpose + complex conjugate" 두 동작이라는 것만 기억하면 충분합니다.

---

## A.4 이 책이 실제로 쓰는 것만 (한눈에)

| 기호 | 읽는 법 | 뜻 | 처음 나오는 곳 |
|------|---------|-----|:--:|
| $i$ | imaginary unit | $i^2 = -1$ | [A.1](#a1-complex-number) |
| $\alpha^*$ | alpha conjugate | $a+bi \to a-bi$ | [2장](02_dirac_notation_and_linear_algebra.md) |
| $\|\alpha\|^2$ | absolute value square | $\alpha^*\alpha = a^2+b^2$ = probability | [4장](04_measurement.md) |
| $e^{i\theta}$ | phase factor | unit circle 위의 점, $\|e^{i\theta}\|=1$ | [4장](04_measurement.md) |
| $\begin{bmatrix}\alpha\\\beta\end{bmatrix}$ | column vector | qubit state (unit vector) | [1장](01_qubits_and_states.md) |
| $U|\psi\rangle$ | matrix × vector | gate 적용 | [3장](03_single_qubit_gates.md) |
| $AB$ | matrix × matrix | gate composition (순서 중요) | [3장](03_single_qubit_gates.md) |
| $A^\dagger$ | dagger | transpose + complex conjugate | [2장](02_dirac_notation_and_linear_algebra.md) |

더 깊이 보려면 3Blue1Brown의 *Essence of Linear Algebra* 영상 시리즈와 complex number 기초 자료를 권합니다. 위 표는 1~9장의 손계산에서 실제로 손을 움직이게 만드는 기호를 모은 것입니다. 다만 표가 유도를 대신하지는 않습니다 — 기호를 알아본 뒤에도 막힌다면 그 장의 계산을 한 줄씩 따라 적어 보는 편이 빠릅니다. 11장 이후 hardware 쪽에서 처음 만나는 기호는 다음 두 절에 따로 모았습니다.

---

## A.5 fixed-point arithmetic

11장 이후의 amplitude는 complex number도 real number도 아니고 **정해진 폭의 binary integer**입니다. 그 integer를 어떻게 읽기로 약속했는지가 아래 다섯 가지입니다. 결정의 근거는 [12장](12_fixed_point_and_precision.md)에 있고, 값의 source of truth는 [15.4절 설계 결정표](15_paper_map_and_design_decisions.md#154-우리-project의-좌표--확정-설계-결정표)입니다.

**two's complement.** 정해진 data word width 안에서 negative number까지 표현하는 표준 규약입니다. 최상위 bit만 자리값이 negative인 $-2^{\,\text{data word width}-1}$ 이고 나머지 bit는 평소대로 읽으면 됩니다. 표현 범위는 $[-2^{\,\text{data word width}-1},\ 2^{\,\text{data word width}-1}-1]$ 이고, sign을 뒤집는 연산은 **모든 bit를 반전한 뒤 1을 더하는 것**입니다. 이 규약을 쓰는 이유는 addition·subtraction circuit이 unsigned integer일 때와 **똑같아서**입니다 — sign을 위한 별도 hardware가 필요 없습니다.

**Q format.** 저장된 integer를 $2^{-\text{fraction bits}}$ 단위로 읽기로 한 약속이 fixed-point입니다. integer $v$ 가 실제로 뜻하는 값은 $v/2^{\text{fraction bits}}$ 이고, 소수점은 circuit 어디에도 없이 약속 속에만 있습니다. 표기는 `Q<integer bits>.<fraction bits>` 인데 문헌마다 sign bit를 integer bits에 넣기도 하고 빼기도 하므로, **이 해설서는 sign을 integer bits에 포함**시켜 하나로 못 박습니다([12.2절](12_fixed_point_and_precision.md#122-fixed-point와-q-format-명명-규약)). 그러면 data word width는 언제나 integer bits와 fraction bits를 더한 값입니다. 우리 amplitude는 **Q1.22** — 23 bits이고 sign bit 1 + fraction bits 22, resolution은 $2^{-22}$ 입니다. integer bits에 sign밖에 없어서 real number $1.0$ 에 해당하는 integer $2^{22} = 4{,}194{,}304$ 는 담기지 않고, 담을 수 있는 maximum은 $4{,}194{,}303$ 입니다.

**shift.** binary number를 왼쪽으로 $k$ 칸 밀면 $2^k$ 를 곱한 것이고, 오른쪽으로 밀면 $2^k$ 로 나눈 것입니다. 오른쪽으로 밀 때는 반드시 **arithmetic right shift**(Verilog `>>>`)를 써야 합니다 — 빈 자리를 0이 아니라 sign bit로 채워야 negative number가 negative number로 남기 때문입니다. logical shift(`>>`)로 밀면 $-4$ 가 거대한 positive number로 바뀝니다. multiplier 없이 $2\bar a - \alpha$ 를 만드는 circuit 전체가 이 성질 위에 서 있습니다([13.5절](13_oracle_diffusion_measurement_datapath.md#135-diffusion-operator--2mean--amp가-circuit이-되는-순간)).

**rounding.** right shift는 아래 bit를 **버립니다.** 버리는 방식이 셋인데, 그냥 잘라 내면(truncate) two's complement에서는 언제나 작은 쪽으로 밀리므로 mean $-0.5$ least significant bit만큼의 한쪽 bias가 남습니다. **half-up**은 정확히 절반인 값을 늘 위로 올리고, **round-half-to-even**은 절반일 때 결과의 least significant bit가 0이 되는 쪽으로 붙입니다. integer를 2로 나누는 1-bit shift를 예로 들면, $5/2 = 2.5$ 를 half-up은 $3$ 으로 올리지만 half-to-even은 $2$ 로 내리고, $7/2 = 3.5$ 는 둘 다 $4$ 입니다. 절반인 경우가 위·아래로 반반 갈리므로 half-to-even은 bias가 정확히 0이고, 같은 rounding을 백 번 넘게 되풀이하는 loop에서는 이 차이가 error의 성장 속도를 바꿉니다([12.4절](12_fixed_point_and_precision.md#124-rounding--왜-half-to-even인가)).

**saturation.** 결과가 표현 범위를 넘을 때 two's complement를 그대로 두면 maximum 바로 위가 minimum이 되어 **sign까지 뒤집힙니다**(wraparound). saturation은 그 대신 maximum을 넘으면 maximum에, minimum을 밑돌면 minimum에 붙입니다. 값은 틀리지만 sign과 크기 순서는 살아남고 error가 그 칸에 머무릅니다([12.5절](12_fixed_point_and_precision.md#125-overflow-policy--saturationwraparound-금지renormalization-없음)).

---

## A.6 probability와 random number

measurement를 circuit으로 만들려면([14장](14_multiple_solutions_and_minimum_search.md)) probability를 손으로 다뤄야 합니다. 필요한 것은 셋뿐입니다.

**uniform random number.** 어떤 interval의 값 중 어느 것이나 같은 probability로 나오는 random number를 $r \sim U[0, \text{upper limit})$ 처럼 적습니다. hardware에 진짜 random number는 없으므로 LFSR 같은 PRNG로 만드는데, 같은 seed에서 늘 같은 수열이 나온다는 점이 verification에서는 오히려 이득입니다([18.3절](18_reference_model_verification.md#183-bit-exact가-성립하기-위한-조건)).

**prefix sum과 inverse transform sampling.** index $i$ 마다 0 이상의 row weight가 붙어 있고 그 비율대로 index 하나를 뽑고 싶다고 합시다. prefix sum

$$\text{prefix sum}(i) = \sum_{k \le i} \text{row weight}_k, \qquad \text{total weight} = \text{prefix sum}(\text{last index})$$

을 만들어 두고 $r \sim U[0, \text{total weight})$ 를 뽑은 뒤, $\text{prefix sum}(i) > r$ 이 되는 **첫 번째** $i$ 를 답으로 씁니다. 길이가 제각각인 막대를 한 줄로 이어 붙여 놓고 그 위에 점을 아무 데나 찍는 그림을 떠올리면 됩니다 — 점이 $i$ 번 막대에 떨어질 probability는 그 막대가 차지한 길이의 비율 $\text{row weight}_i/\text{total weight}$ 이고, 그것이 우리가 원한 distribution입니다. probability가 되도록 row weight를 normalization하는 대신 $r$ 의 범위를 total weight로 잡은 것은 비교의 양변에 같은 constant를 곱한 것과 같아서, divider 없이 같은 distribution을 얻습니다. [14.4절](14_multiple_solutions_and_minimum_search.md#144-born-rule-sampling--probability를-circuit으로)이 이 절차에 $\text{row weight}_i = a_i^2$ 를 넣은 것입니다.

**expected number of shots.** success probability가 $p$ 인 shot을 성공할 때까지 독립적으로 되풀이하면, 필요한 number of shots의 mean은

$$E[\text{number of shots}] = \sum_{k \ge 1} k\,(1-p)^{k-1}p = \frac{1}{p}$$

입니다(geometric distribution). $p = 1/4$ 면 mean이 4 shots죠. 전제를 반드시 함께 기억해야 합니다 — 이 공식은 **$p$ 가 shot마다 같을 때**만 성립합니다. [16.3절](16_iteration_control_and_checkpoints.md#163-shot-통계--mean이-20-shots를-넘는-이유)의 shot loop는 초반 shot의 success probability가 거의 0이고 shot마다 값이 달라지므로 mean이 4 shots가 아니라 22.7 shots(14 qubits · 1 solution, 100 workloads)로 나오는데, 그 어긋남의 정체가 바로 이 전제입니다.

방금 괄호 안에 붙인 조건이 그 22.7 shots를 어떻게 얻었는지도 말해 줍니다. probability를 식으로 풀기 어려울 때는 random number로 실제로 여러 번 돌려 보고 결과의 mean을 구하는데, 이것을 **Monte Carlo**라 합니다. 22.7 shots는 shot loop 전체를 서로 다른 100 seeds로 돌려(board benchmark와 같은 workload) mean number of shots를 잰 값입니다.

---

여기까지가 이 해설서를 손으로 따라가는 데 필요한 최소 사전입니다. 이제 [1장](01_qubits_and_states.md)으로 가서, 이 vector가 왜 하필 "qubit의 state"가 되는지 봅시다.

---

> [index](index.md) · [1장 qubit와 state →](01_qubits_and_states.md)
