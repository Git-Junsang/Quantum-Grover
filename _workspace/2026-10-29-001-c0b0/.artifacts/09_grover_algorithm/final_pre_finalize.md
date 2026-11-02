# 9장. Grover algorithm ★

> [← 8장 Deutsch–Jozsa algorithm](08_deutsch_jozsa_algorithm.md) · [index](index.md) · [10장 용어 정리와 cheat sheet →](10_glossary_and_cheat_sheet.md)
> **이 장을 읽기 위한 준비**: [1장](01_qubits_and_states.md) amplitude·superposition, [4장](04_measurement.md) measurement, [6.2절 $H^{\otimes \text{number of qubits}}$](06_quantum_circuit_model_and_universality.md#62-uniform-superposition-만들기--hotimes-textnumber-of-qubits), [7장 oracle](07_oracle_and_phase_kickback.md). 뒷부분 수식은 [2.6절 outer product](02_dirac_notation_and_linear_algebra.md#26-outer-product--ket-곱하기-bra)도 씁니다.

---

이 project의 목적지입니다. **Grover algorithm**은 정렬되지 않은 항목들 가운데서 조건에 맞는 항목을 **약 $\sqrt{\text{number of states}}$ 번** 만에 찾습니다.

이 장은 **그림 한 장**(amplitude bar chart)에서 출발합니다. 먼저 Grover가 하는 일을 말로 이해하고, 실제로 손으로 한 번 돌려서 solution을 얻는 과정을 확인한 뒤, "왜 $\sqrt{\text{number of states}}$ 번인지 · 왜 $\pi$ 가 나오는지"를 rotation 그림으로 풀고, 마지막에 수식으로 정리합니다. 수식이 어렵게 느껴지면 **9.7절**은 건너뛰고 직관만 챙겨도 됩니다 — 다만 9.7절의 결론 하나, **solution이 여럿이면 그 amplitude가 항상 정확히 같다**는 사실만은 반드시 챙기셔야 합니다. 그 결론은 손계산으로도 볼 수 있게 **9.4절**에 함께 넣어 두었으니, 9.7절을 건너뛰더라도 9.4절의 뒷부분은 건너뛰지 마세요. 이 사실에 따라 나중에 measurement circuit 전체의 설계가 달라집니다.

---

## 9.1 무슨 문제를 푸는가

100개의 상자 중 하나에 민트 초콜릿이 들어 있습니다. 상자를 하나씩 열어봅니다.

- **운이 좋으면**: 첫 상자에 있음 → 1번.
- **운이 나쁘면**: 99개를 열어도 없어 100번째에서 발견 → 100번.

mean으로 봐도 최악으로 봐도 상자 수에 비례합니다. search는 **$O(\text{number of states})$**. 상자를 열어 "이게 내가 찾는 거냐"를 확인하는 게 곧 oracle 호출이에요([7장](07_oracle_and_phase_kickback.md)).

data가 **정렬**돼 있으면 binary search로 $O(\log \text{number of states})$ 에 찾지만, 정렬은 강한 전제이고 정렬이 불가능한 경우도 많습니다. Grover는 **정렬 안 된** data에서 **$O(\sqrt{\text{number of states}})$** 를 달성합니다 — binary search만큼 극적이진 않아도(quadratic speedup), 정렬 없이 얻는 확실한 이득이고, 이 $O(\sqrt{\text{number of states}})$ 가 **최적**임이 증명돼 있습니다.

> 🔑 숫자로 느껴봅시다: 항목이 100만 개면 classical search는 최악 100만 번, Grover는 약 $\sqrt{10^6} = 1{,}000$ 번. 항목이 많을수록 격차가 벌어집니다.

여기서 비교의 전제를 짚고 넘어가겠습니다. 방금의 $O(\text{number of states})$ 대 $O(\sqrt{\text{number of states}})$ 비교는 **진짜 quantum hardware**에서 성립하는 이야기입니다. 이 project가 만드는 것은 quantum computer가 아니라 Grover를 classical circuit으로 흉내 내는 **emulator**이고, emulator는 iteration 한 번마다 모든 state의 amplitude를 전부 훑어야 하므로 총비용이 $O\!\left(\text{number of states}\cdot\sqrt{\text{number of states}/\text{number of solutions}}\right)$ 입니다. 즉 우리 circuit은 **classical linear scan보다 오히려 느립니다.** 그래서 이 해설서는 우리 accelerator를 classical search와 비교하지 않습니다. 비교 대상은 같은 일을 하는 software state vector simulator — Qiskit AerSimulator나 NumPy로 짠 것 — 이고, 이 accelerator의 값어치는 속도 우위가 아니라 **quantum algorithm의 동작을 결정적이고 재현 가능하게 재현·검증하는 전용 hardware**라는 데 있습니다. algorithm의 $\sqrt{\text{number of states}}$ 는 우리가 흉내 내는 **대상의 성질**이지 우리 circuit의 성능 지표가 아닙니다.

---

## 9.2 문제를 기호로

- qubit의 개수를 number of qubits, search space의 크기를 $\text{number of states} = 2^{\text{number of qubits}}$ 라 씁니다.
- oracle: 조건을 만족하면 $f(x)=1$, 아니면 $0$ ([7장](07_oracle_and_phase_kickback.md)).
- 조건을 만족하는 index 전체를 **solution 집합** $A = \{\,x : f(x)=1\,\}$ 이라 하고, 그 크기를 $\text{number of solutions} = |A|$ 라 씁니다.

이 장은 처음부터 solution이 하나 이상인 경우(**$\text{number of solutions} \ge 1$**)를 정식 설정으로 둡니다. solution이 하나뿐인 경우는 그중 **가장 단순한 special case**이고, 그때만 유일한 solution을 $\omega$ 라 부르겠습니다. 교과서가 흔히 solution 하나짜리부터 시작하는 것은 기호가 짧아지기 때문이지 그게 표준 문제라서가 아닙니다. 실제 search에서 oracle은 "이 index가 solution이냐"가 아니라 **predicate를 만족하느냐**만 판정하고, 그 predicate를 몇 칸이 만족하는지는 data에 따라 정해집니다([14.2절](14_multiple_solutions_and_minimum_search.md#142-oracle은-solution을-아는-circuit이-아니다)). solution을 하나로 못 박는 것은 "solution이 하나뿐임을 이미 안다"는 꽤 강한 가정이에요.

Grover는 oracle을 약 $\frac{\pi}{4}\sqrt{\text{number of states}/\text{number of solutions}}$ 번 호출한 뒤 높은 probability로 solution 하나를 내놓습니다. 이 횟수가 어디서 오는지는 **9.5절**에서 풀립니다. (0 solutions, 즉 조건을 만족하는 칸이 하나도 없는 경우는 rotation angle 자체가 정의되지 않아 algorithm 바깥에서 따로 판정해야 합니다 — hardware에서 이를 어떻게 끝낼지는 아직 확정하지 않았습니다([16.9절](16_iteration_control_and_checkpoints.md#169-초판의-미정-넷은-이렇게-정해졌다)).)

---

## 9.3 핵심 장면 — 막대 두 번 흔들기

Grover가 실제로 무엇을 하는지, **amplitude bar chart** 한 장이면 다 담깁니다. 막대 하나가 state 하나의 amplitude(measurement probability의 뿌리)라고 보세요.

<img src="diagrams/09_amplitude_amplification.svg" width="720" alt="amplitude amplification 3단계">

**시작.** 모든 qubit에 $H$ 를 걸어 **uniform superposition**을 만듭니다([6.2절](06_quantum_circuit_model_and_universality.md#62-uniform-superposition-만들기--hotimes-textnumber-of-qubits)). 막대가 전부 똑같은 높이 $\frac{1}{\sqrt{\text{number of states}}}$ 예요. 지금 measurement를 하면 solution이 나올 probability는 $\frac{\text{number of solutions}}{\text{number of states}}$ — 그냥 찍는 거랑 같습니다.

이제 Grover **한 번**은 딱 두 동작입니다.

**동작 1 — oracle: 조건에 걸리는 막대를 아래로 뒤집기.** oracle $U_f$ 는 **조건을 만족하는 모든 칸**의 amplitude sign을 뒤집어 **negative**로 만듭니다([7.2절](07_oracle_and_phase_kickback.md#72-oracle을-quantum으로--두-가지-형태)). 걸린 칸은 $-\frac{1}{\sqrt{\text{number of states}}}$, 나머지는 그대로 $+\frac{1}{\sqrt{\text{number of states}}}$. circuit은 어느 칸이 걸릴지 미리 알지 못하고, 알 필요도 없습니다 — 판정만 할 뿐입니다.

그런데 이 state에서 measurement를 하면 소용없어요. $\left|-\frac{1}{\sqrt{\text{number of states}}}\right|^2 = \left|\frac{1}{\sqrt{\text{number of states}}}\right|^2$ 라 probability는 여전히 다 똑같거든요. sign은 **아직 안 보이는 표식**일 뿐입니다. 그래서 두 번째 동작이 필요합니다.

**동작 2 — diffusion operator: mean을 기준으로 모두 뒤집기.** 이게 Grover의 심장인 **"inversion about the mean"** 예요. 말은 거창하지만 규칙은 한 줄입니다:

> 모든 막대를 **mean line을 기준으로** 위아래로 뒤집는다. (mean보다 위에 있던 건 그만큼 아래로, 아래 있던 건 그만큼 위로.)

두 동작을 거치면 다음과 같이 달라집니다. 동작 1에서 solution 막대는 mean line **한참 아래**(negative)로 내려가 있었죠. 그러니 mean 기준으로 뒤집으면 solution은 mean **한참 위**로 솟구칩니다. 반면 나머지 막대들은 원래 mean 근처였으니 살짝만 내려가요. 결과적으로 **solution 막대만 껑충 커지고 나머지는 낮아집니다.**

💡 **시소 비유**: oracle은 solution을 시소 바닥까지 꾹 눌러 놓습니다. diffusion operator(inversion about the mean)는 시소를 통째로 뒤집어, 바닥에 있던 solution을 꼭대기로 올려요. 나머지는 원래 가운데쯤이라 크게 안 움직입니다.

이 두 동작(눌렀다 → 뒤집기)을 반복할 때마다 solution 막대가 조금씩 더 커집니다. 충분히 커지면 measurement를 했을 때 solution이 높은 probability로 나오죠. Grover 전체 흐름을 그림으로 보면:

<img src="diagrams/09_grover_flow.svg" width="440" alt="Grover 전체 흐름">

---

## 9.4 진짜로 한 번 돌려보기 — 4 states

작은 예제인 4 states(2 qubits)를 손으로 끝까지 계산해 봅시다. 먼저 solution이 하나인 경우이고, 그 solution을 $\omega$ 라 하겠습니다. 네 state의 amplitude를 순서대로 추적할게요.

**시작 — uniform superposition.** 네 state 모두 amplitude $\frac12$:

$$
\text{amplitude} = \left(\tfrac12,\ \tfrac12,\ \tfrac12,\ \tfrac12\right)
$$

solution을 뽑을 probability는 $\left|\frac12\right|^2 = \frac14$. (넷 중 하나 찍기와 같음.)

**동작 1 — oracle.** solution(세 번째라 하죠)의 amplitude만 negative로:

$$
\left(\tfrac12,\ \tfrac12,\ -\tfrac12,\ \tfrac12\right)
$$

**동작 2 — diffusion operator(inversion about the mean).** 먼저 mean을 구합니다:

$$
\bar a = \frac{1}{4}\left(\tfrac12 + \tfrac12 - \tfrac12 + \tfrac12\right) = \frac14
$$

각 막대를 mean 기준으로 뒤집는 것은 $a \mapsto 2\bar a - a = \frac12 - a$ 로 계산됩니다(왜 이 식인지는 **9.7절**에서):

- non-solution 세 개 ($a = \tfrac12$): $\ \tfrac12 - \tfrac12 = 0$
- solution ($a = -\tfrac12$): $\ \tfrac12 - (-\tfrac12) = 1$

결과 amplitude는 $(0,\ 0,\ 1,\ 0)$ — state가 **정확히 solution $\omega$** 이 되었습니다! measurement를 하면 solution이 나올 probability가 $|1|^2 = 1$, 즉 **단 한 번의 iteration으로 100% 확실하게** 찾았습니다. 두 동작만으로 solution을 얻은 거예요.

(4 states는 한 번에 딱 맞아떨어지는 특별히 운 좋은 크기입니다. state가 많으면 한 번으론 부족하고 여러 번 흔들어야 하는데, 그 얘기가 바로 다음 절입니다.)

### solution이 둘이면 — 같은 계산, 두 막대

이제 방금 계산에서 **solution만 하나 더 늘려** 봅시다. circuit은 그대로 씁니다. 셋째와 넷째 칸이 둘 다 조건을 만족한다고 하죠(2 solutions). oracle은 조건에 걸리는 칸을 **전부** 뒤집으므로:

$$
\left(\tfrac12,\ \tfrac12,\ -\tfrac12,\ -\tfrac12\right)
$$

mean은 $\bar a = \frac14\left(\tfrac12+\tfrac12-\tfrac12-\tfrac12\right) = 0$ 이고, diffusion operator $a \mapsto 2\bar a - a = -a$ 를 적용하면:

$$
\left(-\tfrac12,\ -\tfrac12,\ \tfrac12,\ \tfrac12\right)
$$

두 solution 막대의 값이 **정확히 같습니다.** 우연이 아니에요. 시작이 같았고(uniform superposition이니 모든 칸이 같은 값), oracle이 둘을 똑같이 뒤집었고, diffusion operator $a \mapsto 2\bar a - a$ 는 애초에 index를 구별하지 않는 global operation이라 **같은 값에 같은 function을 적용한 것**뿐입니다. 이 세 줄이 그대로 induction이고, iteration을 몇 번 하든 결론은 바뀌지 않습니다 — **solution들의 amplitude는 매 iteration 후 정확히 같습니다.**

(다만 4 states에 solution이 둘이면 처음부터 절반이 solution이라 더 짜낼 것이 없습니다. 실제로 solution 쪽 probability는 $\frac12$ 에서 $\frac12$ 로 제자리예요. 이건 **9.6절** "지나치면 안 된다"의 최소 사례이기도 합니다 — 한 번의 rotation이 목표를 그대로 지나쳐 버린 것이죠.)

**막대가 나란히 자라는 것까지 보려면 8 states.** 여덟 칸 중 두 칸이 조건을 만족한다고 하고 같은 계산을 반복합니다. 시작 amplitude는 여덟 칸 모두 $\frac{1}{\sqrt 8} \approx 0.35355$.

- oracle 뒤: solution 둘이 $-0.35355$, non-solution 여섯이 $+0.35355$.
- mean: $\bar a = \dfrac{6(0.35355) - 2(0.35355)}{8} = 0.17678$.
- diffusion operator: solution $2(0.17678) - (-0.35355) = 0.70711 = \tfrac{1}{\sqrt2}$, non-solution $2(0.17678) - 0.35355 = 0$.

두 solution 막대가 **나란히 $\frac{1}{\sqrt2}$ 까지 자랐고**, non-solution 여섯은 정확히 0으로 눌렸습니다. 각 solution의 probability는 $\frac12$ 이고 합치면 1 — 여기서도 한 번에 100%입니다. 두 막대의 높이는 정확히 같습니다.

이 "solution들의 amplitude가 항상 같다"는 사실은 이론에서는 사소해 보이지만 hardware에서는 결정적입니다. amplitude가 가장 큰 칸을 고르는 comparator circuit은 동률이 나오면 구조가 정한 **하나**만 내놓기 때문에, solution이 둘 이상이면 나머지는 영원히 출력되지 않습니다([14.3절](14_multiple_solutions_and_minimum_search.md#143-amplitude-동률--argmax가-무너지는-지점)). 일반적인 경우의 증명은 **9.7절** 끝에 있습니다.

---

## 9.5 왜 여러 번? · 왜 $\sqrt{\text{number of states}}$ 번? · 왜 $\pi$?

state가 많으면 solution이 그 많은 state 가운데 딱 하나 묻혀 있어, 처음 막대가 $\frac{1}{\sqrt{\text{number of states}}}$ 로 아주 작습니다. 한 번 흔들어선 충분히 안 커져요. 그래서 Grover iteration을 여러 번 돌리는데, **몇 번**이 적당한지를 알려면 Grover를 **rotation**으로 보는 게 제일 깔끔합니다.

<img src="diagrams/09_geometric_rotation.svg" width="560" alt="Grover geometric rotation">

**state를 화살표로.** 전체 space는 state마다 축이 하나씩 있는 고차원이지만, Grover의 계산이 이루어지는 공간은 딱 **2차원 평면**이에요. 두 방향만 잡으면 됩니다:

- **solution 방향** $|\omega\rangle$ — 우리가 가고 싶은 곳.
- **non-solution 방향** $|s'\rangle$ — solution을 뺀 나머지 전부.

초기 uniform superposition은 이 평면 안의 화살표인데, 거의 **non-solution 방향**을 가리키고 solution 방향에서 살짝 기울어 있어요(solution 성분이 $\frac{1}{\sqrt{\text{number of states}}}$ 로 작으니까). 그 기울어진 각을 $\theta$ 라 하면 $\sin\theta = \frac{1}{\sqrt{\text{number of states}}}$, state가 많으면 $\theta$ 는 아주 작습니다.

**한 번 흔들 때마다 $2\theta$ rotation.** "oracle + diffusion operator" 한 번은 이 화살표를 solution 방향으로 **정확히 $2\theta$ 만큼 돌립니다**(왜 딱 rotation인지는 **9.7절**에서). 그러니 반복할수록 화살표가 non-solution 방향에서 solution 방향으로 조금씩 돌아가요. solution 방향에 화살표가 정렬되면, measurement 시 solution이 나올 probability가 (거의) 1이 됩니다.

**그래서 몇 번? — 여기서 $\pi$ 가 나옵니다.** solution 방향은 non-solution 방향과 **직각(90°)** 입니다. 화살표를 거기까지 돌리는 건 원의 **4분의 1 바퀴**, 각도로는 **$\frac{\pi}{2}$** 예요 (π 는 "반 바퀴 = π, 4분의 1 바퀴 = π/2"인 그 원의 숫자입니다). 한 번에 $2\theta$ 씩 도니까, 필요한 횟수는:

$$
\text{number of iterations} \approx \frac{\text{돌아야 할 각}}{\text{한 번에 도는 각}} = \frac{\pi/2}{2\theta} = \frac{\pi}{4\theta}
$$

solution이 하나면 $\theta \approx \frac{1}{\sqrt{\text{number of states}}}$ 이므로:

$$
\boxed{\text{number of iterations} \approx \frac{\pi}{4}\sqrt{\text{number of states}}}
$$

$\frac{\pi}{4}$ 의 4는 "직각이라 $\pi$ 의 **절반**(=π/2)" × "한 번에 $2\theta$ 라 **2×**" 가 겹쳐 나온 것뿐이에요. solution이 여러 개면 $\sin\theta = \sqrt{\text{number of solutions}/\text{number of states}}$ 가 되어 $\text{number of iterations} \approx \frac{\pi}{4}\sqrt{\text{number of states}/\text{number of solutions}}$. 이것이 **$O(\sqrt{\text{number of states}})$** 의 정확한 근원입니다. (solution이 여러 개일 때 이 $\sqrt{\text{number of states}/\text{number of solutions}}$ 가 hardware에서 무엇을 뜻하는지는 [14.1절](14_multiple_solutions_and_minimum_search.md#141-solution이-여럿이면--oracle에서는-공짜)에서 다룹니다 — multiple solutions는 oracle과 diffusion operator에서는 공짜이고, 값을 치르는 곳은 iteration 제어와 measurement입니다.)

**운전대 비유**: 목표가 옆으로 90° 방향에 있고, 운전대를 한 번 꺾으면 일정 각도씩 돈다고 해봐요. 몇 번 꺾어야 하냐? "90°(=π/2) ÷ 한 번에 도는 각도"죠. $\pi$ 는 그저 "90°를 각도(radian)로 쓰면 π/2"라서 등장한 겁니다 — 신비로운 constant가 아니라 **rotation의 기하학**이에요.

✏️ **연습 9-1**: 64 states 가운데 solution이 4개일 때, iteration을 대략 몇 번 돌리는 것이 최적일까요? *(답: $\text{number of iterations} \approx \frac{\pi}{4}\sqrt{64/4} = \frac{\pi}{4}\sqrt{16} = \pi \approx 3$ 회. [10장](10_glossary_and_cheat_sheet.md#106-연습문제-답)에 풀이.)*

---

## 9.6 지나치면 안 된다

rotation 관점이 주는 중요한 경고입니다. iteration은 화살표를 $2\theta$ 씩 **계속** 돌립니다. 최적 횟수를 넘겨 돌리면 solution 방향을 **지나쳐** 버리고, 그러면 solution probability가 다시 **떨어집니다**(그리고 진동합니다).

> ⚠️ **함정 — Grover는 "많이 돌릴수록 좋은" 게 아니다**: classical algorithm은 오래 돌릴수록 확실해지지만, Grover는 $\frac{\pi}{4}\sqrt{\text{number of states}}$ 근처에서 probability가 최대이고 그 뒤엔 오히려 감소합니다. **정확한 횟수**를 지키는 게 중요합니다. number of solutions를 모르면 횟수를 정하기 어려운데, 이를 다루는 기법들이 따로 연구돼 있습니다.

solution이 하나일 때 최적 횟수 근처의 오류(solution이 안 나올) probability는 약 $\frac{1}{\text{number of states}}$ 정도로 아주 작습니다. 그리고 [8장 Deutsch–Jozsa](08_deutsch_jozsa_algorithm.md)는 interference **한 번**으로 답이 떨어졌지만, Grover iteration을 **여러 번** 돌리는 이유는 이제 분명하죠 — solution 하나가 많은 state 가운데 묻혀 초기 amplitude가 $\frac{1}{\sqrt{\text{number of states}}}$ 로 작으니, rotation을 여러 번 쌓아야 solution 방향에 닿기 때문입니다.

방금 ⚠️ 상자가 "기법들이 따로 연구돼 있다"고만 하고 넘어간 그 기법에 이름을 붙여 둡시다. 표준 해법은 **BBHT**(Boyer–Brassard–Høyer–Tapp, 1998)입니다. number of solutions를 모르니 number of iterations를 한 번에 정하지 않고, 대신 여러 번의 **shot**으로 나눠 매 shot마다 number of iterations를 무작위로 뽑습니다. 뽑는 범위인 sampling range를 $1$ 에서 시작해 $\text{number of iterations} \sim U[0,\,\text{sampling range})$ 로 뽑고, 그 shot이 실패하면 $\text{sampling range} \leftarrow \min(1.2 \cdot \text{sampling range},\ \sqrt{\text{number of states}})$ 로 넓혀 다시 뽑습니다($\text{growth factor} = 6/5 = 1.2$). rotation angle을 모르니 **여러 각도를 무작위로 시도하는** 전략이고 성공 여부는 measurement로 나온 후보 하나가 정말 predicate를 만족하는지 다시 확인하는 **solution check**로 판정합니다 — 값 한 칸을 읽는 것이라 사실상 공짜입니다.

초반 shot이 거의 다 실패하는 것은 고장이 아니라 이 절차의 정상 동작입니다. sampling range가 1에서 시작해 growth factor 1.2로만 커지므로 처음 몇 shot은 number of iterations가 0~2 근처에서만 뽑히는데, state가 많으면 그 정도 iteration은 rotation을 겨우 두어 번 한 state라 solution probability가 사실상 0이거든요. 우리 규모인 14 qubits(16,384 states)에서 solution이 하나라면 최적은 $\frac{\pi}{4}\sqrt{16{,}384} - \frac12 = 100.03 \to 100$ iterations인데, sampling range가 거기까지 커지기 전의 shot들은 성공에 이르지 못합니다. 그래서 shot이 꽤 쌓입니다 — 성공까지 **mean 22.7 shots**입니다(14 qubits·1 solution, board benchmark와 같은 100 workloads). "네댓 번이면 끝난다"가 아니에요. 이 shot loop를 FSM으로 어떻게 돌리는지, 실패한 shot이 남긴 amplitude array를 버리지 않고 재사용하는 방법은 [16장](16_iteration_control_and_checkpoints.md)에서 다룹니다. 원논문은 [10.8절](10_glossary_and_cheat_sheet.md#108-원문-자료-대조표) 대조표 끝에 적어 둔 Boyer et al. (1998) *Tight bounds on quantum searching* 입니다.

hardware에서는 "지나치면 안 된다"는 성질에 더 주의해야 합니다 — number of iterations를 integer로 반올림해야 하고, state가 적으면 그 rounding error가 성공률에 크게 반영됩니다([14.8절](14_multiple_solutions_and_minimum_search.md#148-두-개의-함정)).

---

## 9.7 이제 수식으로 — 두 개의 reflection

여기부터는 앞의 두 그림(막대·rotation)을 **operator(matrix) 언어**로 정확히 옮깁니다. 직관이 이미 잡혔다면 이 절은 "왜 그게 맞는지"의 증명이라고 보면 됩니다.

**oracle = solution 방향의 reflection.** [7.4절](07_oracle_and_phase_kickback.md#74-conditional-sign-flip--operator로-쓰기)에서 phase oracle을 이렇게 썼습니다(solution이 하나인 경우):

$$
U_f = I - 2|\omega\rangle\langle\omega|
$$

이건 "solution $\omega$ 성분만 sign을 뒤집는" 연산이에요. 확인: $\omega$ 에 작용하면 $-|\omega\rangle$(뒤집힘), $\omega$ 와 orthogonal인 state엔 그대로. 기하로는 **non-solution 축 $|s'\rangle$ 에 대한 reflection**입니다.

**diffusion operator = inversion about the mean.** diffusion operator는 이렇게 씁니다. $|\psi\rangle$ 은 uniform superposition입니다:

$$
U_\psi = 2|\psi\rangle\langle\psi| - I
$$

이게 왜 "inversion about the mean"($a \mapsto 2\bar a - a$)인지 봅시다. 임의 state $\sum_x a_x|x\rangle$ 에 작용하면, $\langle\psi|\big(\sum a_x|x\rangle\big) = \frac{1}{\sqrt{\text{number of states}}}\sum a_x = \sqrt{\text{number of states}}\,\bar a$ (mean의 $\sqrt{\text{number of states}}$ 배)이므로:

$$
U_\psi\sum_x a_x|x\rangle = 2|\psi\rangle(\sqrt{\text{number of states}}\,\bar a) - \sum_x a_x|x\rangle = \sum_x (2\bar a - a_x)|x\rangle
$$

정확히 $a_x \mapsto 2\bar a - a_x$ — **9.4절**에서 손으로 쓴 그 규칙입니다. ✓

기하로 보면, $U_\psi$ 는 $|\psi\rangle$ 방향은 그대로 두고($U_\psi|\psi\rangle = |\psi\rangle$) 거기에 수직인 성분만 sign을 뒤집습니다. 즉 **$|\psi\rangle$ 방향을 거울로 삼는 reflection**이에요. oracle이 $|s'\rangle$ 축을 거울로 삼았던 것과 짝을 이룹니다 — 이제 Grover 한 번은 "거울 두 개에 연달아 비추기"가 됩니다.

**gate로 만들기.** $|\psi\rangle = H^{\otimes \text{number of qubits}}|0\rangle^{\otimes \text{number of qubits}}$ 이므로 diffusion operator를 실제 gate로 풀 수 있어요:

$$
U_\psi = H^{\otimes \text{number of qubits}}\big(2|0\cdots0\rangle\langle0\cdots0| - I\big)H^{\otimes \text{number of qubits}}
$$

가운데 $2|0\cdots0\rangle\langle0\cdots0| - I$ 는 "$|0\cdots0\rangle$ 만 빼고 sign flip"인데, 실제로는 [7.5절 $Z$ trick](07_oracle_and_phase_kickback.md#75-oracle을-실제로-만들기--z-gate-trick)처럼 모든 qubit에 $X$ 를 걸어 $|0\cdots0\rangle$ 을 $|1\cdots1\rangle$ 로 옮긴 뒤 multi-controlled $Z$ 로 sign을 뒤집고 다시 $X$ 로 되돌리면 됩니다. 즉 diffusion operator는 **Hadamard → ($|0\cdots0\rangle$만 sign flip) → Hadamard**. 이 **Hadamard–diagonal–Hadamard sandwich** 구조가 [13.5절](13_oracle_diffusion_measurement_datapath.md#135-diffusion-operator--2mean--amp가-circuit이-되는-순간)에서 "accumulation → shift → subtraction"이라는 multiplication 없는 datapath로 구현됩니다.

**두 reflection을 이으면 rotation — 왜 하필 $2\theta$인가.** 한 번의 Grover iteration은

$$
G = U_\psi\,U_f = (2|\psi\rangle\langle\psi| - I)(I - 2|\omega\rangle\langle\omega|)
$$

즉 "oracle reflection → diffusion operator reflection", **거울 두 개에 연달아 비추는 것**입니다. 두 거울은:

- oracle $U_f$: **non-solution 축 $|s'\rangle$** 을 거울로 삼는 reflection.
- diffusion operator $U_\psi$: **초기 state $|\psi\rangle$ 방향**을 거울로 삼는 reflection.

그리고 이 두 거울은 정확히 **$\theta$ 만큼 벌어져** 있어요 — $|\psi\rangle$ 이 $|s'\rangle$ 축에서 $\theta$ 기울어 있으니까(**9.5절**, $\sin\theta = \frac{1}{\sqrt{\text{number of states}}}$). 여기서 기하학의 깔끔한 사실 하나를 씁니다:

> **거울 두 개에 연달아 비추면, 그 결과는 "두 거울 사이 각의 2×"만큼 돌린 것과 같다.**

왜 하필 2배인지, 각도를 직접 따라가 보면 바로 보입니다. 각도를 non-solution 축 $|s'\rangle$(=0°) 기준으로 재고, 화살표가 지금 각도 $\phi$ 에 있다고 하죠. **거울 하나(각도 $a$)에 비추면** 그 거울에 대해 대칭 이동하니 새 각도는 $2a - \phi$ 가 됩니다. 이걸 두 번 적용합니다:

- 시작: 화살표는 $|\psi\rangle$ 위치, 즉 $\phi = \theta$.
- **① oracle** (거울 = $|s'\rangle$ 축, $a=0$): $\ \theta \;\to\; 2\cdot 0 - \theta = -\theta$. → solution 성분 sign이 뒤집혀 축 **아래로** 접힘.
- **② diffusion operator** (거울 = $|\psi\rangle$, $a=\theta$): $\ -\theta \;\to\; 2\theta - (-\theta) = 3\theta$.

시작 $\theta$ 에서 끝 $3\theta$ — solution 축 쪽으로 **정확히 $2\theta$** 돌았습니다. 게다가 시작 각 $\phi$ 가 무엇이든 두 번 접으면 $\phi \to 2\theta - (2\cdot0 - \phi) = \phi + 2\theta$ 라, **언제나 $+2\theta$** 만큼 돕니다. 이게 "두 거울 사이 각($\theta$)의 2×만큼 rotation"의 정체예요.

**9.5절**의 rotation 그림이 바로 이 세 걸음입니다: 파란 화살표 $|\psi\rangle$ 이 $\theta$, 회색 점선이 oracle로 축 아래 $-\theta$ 로 접힌 것, 주황 $G|\psi\rangle$ 이 $3\theta$. 그러니 반복할 때마다 화살표는 $\theta \to 3\theta \to 5\theta \to \cdots \to (2\cdot \text{number of iterations}+1)\theta$ 로 solution 축(90°=$\frac{\pi}{2}$)을 향해 $2\theta$ 씩 다가갑니다. solution 축에 닿을 조건 $(2\cdot \text{number of iterations}+1)\theta \approx \frac{\pi}{2}$ 에서 $\text{number of iterations} \approx \frac{\pi}{4\theta} - \frac12 \approx \frac{\pi}{4}\sqrt{\text{number of states}}$ 가 나오고요.

**solution이 여럿이어도 평면은 2차원.** 지금까지 $|\omega\rangle$ 하나를 solution 축으로 삼았는데, solution 집합 $A$ 에 원소가 여럿이면 oracle은 항이 그만큼 늘어난 꼴이 됩니다:

$$
U_f = I - 2\sum_{x \in A}|x\rangle\langle x|
$$

항이 늘었으니 rotation 평면도 그만큼 많은 차원으로 퍼질 것 같지만 그렇지 않습니다. solution 성분을 하나로 묶은 **solution subspace의 unit vector**

$$
|\omega_A\rangle = \frac{1}{\sqrt{\text{number of solutions}}}\sum_{x \in A}|x\rangle
$$

를 새 solution 축으로 잡아 보세요. $U_f|\omega_A\rangle = -|\omega_A\rangle$ 이고 $|\omega_A\rangle$ 에 orthogonal인 성분은 그대로이니, $U_f$ 는 여전히 **한 축에 대한 reflection**입니다. uniform superposition은 $|\psi\rangle = \sin\theta\,|\omega_A\rangle + \cos\theta\,|s'\rangle$ 로 분해되고 이번엔 $\sin\theta = \sqrt{\text{number of solutions}/\text{number of states}}$ 이고요. diffusion operator는 원래부터 $|\psi\rangle$ 하나만 보는 연산이라 손댈 것이 없습니다. 두 거울이 여전히 같은 평면 안에 있으니 **rotation 평면은 solution이 몇 개든 2차원**이고, 앞의 유도가 $\sqrt{\text{number of states}} \to \sqrt{\text{number of states}/\text{number of solutions}}$ 만 바꿔 그대로 성립합니다.

여기서 다음 성질도 알 수 있습니다. 평면이 2차원이라는 것은 state가 언제나 $\alpha|\omega_A\rangle + \beta|s'\rangle$ 꼴이라는 뜻인데, $|\omega_A\rangle$ 는 $A$ 의 모든 칸에 **똑같은 계수** $\frac{1}{\sqrt{\text{number of solutions}}}$ 를 주는 vector입니다. 따라서 모든 solution의 amplitude는 어느 시점에서나 $\frac{\alpha}{\sqrt{\text{number of solutions}}}$ 로 **전부 같습니다.** 9.4절에서 2 solutions로 손계산해 본 그 동률이, 일반적인 경우에 대해 여기서 증명된 셈입니다. 이 정리가 [14.3절](14_multiple_solutions_and_minimum_search.md#143-amplitude-동률--argmax가-무너지는-지점)에서 measurement circuit의 설계를 통째로 바꿉니다.

> 🔑 Grover의 전부는 결국 **두 reflection** $U_f$ 와 $U_\psi$ 를 번갈아 거는 것입니다. $U_f$ 는 solution에 표식을 달고, $U_\psi$ 는 그 표식을 큰 amplitude로 키웁니다.

---

## 9.8 전체 그림 정리 — amplitude는 왜 real number뿐인가

<img src="diagrams/09_grover_circuit.svg" width="640" alt="Grover algorithm circuit">

| 요소      | 수식                                                                                        | 역할                          |
| --------- | ------------------------------------------------------------------------------------------- | ----------------------------- |
| 초기 state | $\|\psi\rangle = H^{\otimes \text{number of qubits}}\|0\rangle^{\otimes \text{number of qubits}} = \frac{1}{\sqrt{\text{number of states}}}\sum_x\|x\rangle$ | uniform superposition (모든 후보 동시에)   |
| oracle    | $U_f = I - 2\sum_{x\in A}\|x\rangle\langle x\|$                                           | 조건에 걸리는 막대를 전부 아래로 |
| diffusion operator      | $U_\psi = 2\|\psi\rangle\langle\psi\| - I$                                                | inversion about the mean (증폭)         |
| 한 iteration   | $G = U_\psi U_f$                                                                          | solution 방향으로 $2\theta$ rotation |
| number of iterations | $\text{number of iterations} \approx \frac{\pi}{4}\sqrt{\text{number of states}/\text{number of solutions}}$                                                       | solution 방향에 정렬될 때까지     |
| complexity | $O(\sqrt{\text{number of states}})$                                                                              | oracle 호출 횟수 기준(real quantum hardware) |

표를 세로로 훑으면 성질 하나가 눈에 들어옵니다. **여기 어디에도 imaginary number가 없습니다.** 세 가지가 겹쳐서 그렇습니다. 첫째, 시작 state $|\psi\rangle = H^{\otimes \text{number of qubits}}|0\rangle^{\otimes \text{number of qubits}}$ 의 amplitude는 전부 $\frac{1}{\sqrt{\text{number of states}}}$ 로 real number입니다. 둘째, oracle은 각 amplitude에 $+1$ 또는 $-1$ 을 곱할 뿐이라 real number를 real number로 보냅니다. 셋째, diffusion operator $a_x \mapsto 2\bar a - a_x$ 는 real number 계수만 쓰는 linear operation이라 역시 real number를 벗어나지 않습니다. real number 집합이 이 세 연산에 대해 닫혀 있으므로, 귀납적으로 **amplitude는 algorithm 처음부터 끝까지 real number**입니다. 일반적인 state의 amplitude는 complex number이고 그 relative phase가 곧 정보인데([1장](01_qubits_and_states.md)), 표준 Grover는 그 자유도를 한 번도 쓰지 않습니다 — 등장하는 phase가 $0$ 과 $\pi$ 둘뿐이고, 그건 sign bit 하나로 적히니까요.

이 성질 덕분에 hardware에서는 비용을 절반으로 줄일 수 있습니다. amplitude 하나당 real part·imaginary part 두 칸을 잡을 이유가 없으니 **imaginary part memory가 아예 없고**, complex number multiplication(real number multiplication 4번 + addition 2번)도 datapath에 등장하지 않습니다. 대신 조건이 하나 붙습니다 — 이 논증은 "초기 state가 real number + phase가 $\pm1$ + diffusion operator가 real linear"라는 **세 전제를 모두 필요로 하므로**, 그중 하나라도 깨는 기능을 얹는 순간 datapath를 complex number에 맞게 다시 설계해야 합니다. 실제로 number of solutions를 세는 표준 기법인 **quantum counting**은 phase estimation을 쓰고, phase estimation은 $e^{2\pi i k / 2^t}$ 꼴의 complex phase를 amplitude에 직접 곱합니다. 그래서 우리 설계는 counting 계열을 아예 채택하지 않고, number of solutions를 모르는 채로 도는 9.6절의 BBHT를 택했습니다. real number 전용 datapath를 지키는 것이 그 선택의 근거 가운데 하나입니다.

---

## 9.9 여기서부터 hardware로 — 어느 개념이 어느 장으로 가는가

이 장에서 배운 개념은 모두 circuit의 각 부분에 대응합니다. 숫자와 circuit diagram은 해당 장에 맡기고, 여기서는 **어느 개념이 어디서 circuit이 되는지**의 지도만 그립니다.

| 9장의 개념 | hardware에서 무엇이 되나 | 어디서 |
| --- | --- | --- |
| uniform superposition $\frac{1}{\sqrt{\text{number of states}}}\sum_x\|x\rangle$ | amplitude array를 constant 하나로 채우는 Init | [11장](11_state_vector_emulator.md) memory 지도 · [13.2절](13_oracle_diffusion_measurement_datapath.md#132-init--uniform-amplitude를-square-root-unit-없이) |
| oracle $U_f$ — predicate 판정 | predicate circuit과 sign flip | [13.3절](13_oracle_diffusion_measurement_datapath.md#133-oracle--predicate-4종이-subtractor-하나를-공유한다) |
| diffusion operator $U_\psi$ — $a \mapsto 2\bar a - a$ | accumulation → arithmetic shift → subtraction | [13.5절](13_oracle_diffusion_measurement_datapath.md#135-diffusion-operator--2mean--amp가-circuit이-되는-순간) |
| solution이 여러 개라는 것 · measurement | amplitude 동률과 Born-rule sampling | [14장](14_multiple_solutions_and_minimum_search.md) |
| number of iterations | number of solutions를 모를 때의 BBHT shot loop | [16장](16_iteration_control_and_checkpoints.md) |
| amplitude를 숫자로 적는 일 | fixed-point 형식과 round-half-to-even·saturation 규칙 | [12장](12_fixed_point_and_precision.md) |

이 지도에서 가장 자주 오해받는 칸은 **measurement**입니다. 9.3절의 bar chart를 보면 "제일 높은 막대를 고르면 되지 않나" 하는 생각이 자연스럽게 들고, 실제로 이 project도 한동안 maximum comparator를 Measurement Unit으로 상정했습니다. 그런데 9.4절의 손계산과 9.7절의 증명이 말하는 대로 모든 solution의 amplitude는 **정확히 같습니다.** maximum comparator는 동률에서 구조가 정한 index 하나만 결정적으로 내놓으므로, solution이 둘 이상이면 나머지는 probability가 낮아서가 아니라 **원리적으로** 출력될 수 없습니다. 그래서 Measurement Unit은 amplitude의 square를 probability로 삼아 random number로 뽑는 **Born-rule sampling**으로 설계합니다([14.4절](14_multiple_solutions_and_minimum_search.md#144-born-rule-sampling--probability를-circuit으로)). 이 절의 요약만 읽고 comparator를 만들면 나중에 전면 재작업이 필요하므로 이 차이를 기억해 두세요.

> 🔑 FPGA 설계자는 결국 "amplitude array에 **sign flip(oracle)**과 **inversion about the mean(diffusion operator)**을 $\sqrt{\text{number of states}}$ 번 적용"하는 circuit을 만듭니다. 이 한 문장의 모든 단어 — amplitude·sign flip·inversion about the mean·$\sqrt{\text{number of states}}$ — 가 1~9장에서 쌓아 온 개념이에요. algorithm을 정확히 이해해야 precision(fixed-point bit width)·resource·오류를 올바르게 설계할 수 있습니다.

그 "precision·resource·오류를 올바르게 설계"하는 이야기가 **Part 5 이후(11~18장)** 입니다. 위 표의 여섯 줄을 다 지나면 여섯 논문의 지도와 설계 결정표([15장](15_paper_map_and_design_decisions.md)), SoC 통합([17장](17_rvx_soc_integration.md)), verification([18장](18_reference_model_verification.md))이 남습니다. 설계값의 source of truth는 [15.4절](15_paper_map_and_design_decisions.md#154-우리-project의-좌표--확정-설계-결정표)의 결정표입니다.

---

## 9.10 이 장의 요약

- **문제**: 정렬 안 된 $\text{number of states} = 2^{\text{number of qubits}}$ 개 항목에서 조건을 만족하는 항목 찾기. solution 집합 $A$ 가 비어 있지 않은 경우($\text{number of solutions} \ge 1$)가 정식 설정이고, solution이 하나뿐인 경우는 가장 단순한 special case.
- **핵심 장면**: 균등 막대에서 시작 → ① oracle로 조건에 걸리는 막대를 전부 negative로 → ② diffusion operator(inversion about the mean $a\mapsto2\bar a-a$)로 그 막대들을 껑충. 이 둘을 매 iteration마다 되풀이.
- **4 states 예제**: amplitude $(\tfrac12,\tfrac12,\tfrac12,\tfrac12)$ → oracle → diffusion operator → $(0,0,1,0)$. 한 번에 probability 1. solution을 둘로 늘리면 두 amplitude가 **정확히 같은 값**으로 움직이고, 8 states·2 solutions에서는 나란히 $\frac{1}{\sqrt2}$ 까지 자란다.
- **왜 $\sqrt{\text{number of states}}$·왜 $\pi$**: Grover는 solution 방향(직각)으로 매번 $2\theta$ 씩 도는 **rotation**. 직각까지 = $\frac{\pi}{2}$, 나눗셈하면 $\text{number of iterations} \approx \frac{\pi}{4\theta} \approx \frac{\pi}{4}\sqrt{\text{number of states}/\text{number of solutions}}$. $\pi$ 는 rotation angle이라서 나온 것.
- **함정**: 최적 횟수를 넘기면 solution을 지나쳐 probability가 다시 떨어짐. number of solutions를 모르면 number of iterations를 계산할 수 없어 **BBHT** shot loop가 shot마다 그 값을 무작위로 뽑는다.
- **수식**: 두 reflection $U_f = I - 2\sum_{x\in A}|x\rangle\langle x|$, $U_\psi = 2|\psi\rangle\langle\psi| - I$. 두 reflection의 composition = rotation. solution이 여러 개여도 rotation 평면은 2차원이고, 그래서 solution들의 amplitude가 **항상 동일**하다.
- **real number 전용**: 초기 uniform superposition이 real number + oracle이 $\pm1$ 곱하기 + diffusion operator가 real linear → amplitude는 real number를 벗어나지 않는다. imaginary part memory가 없고, complex number를 강제하는 quantum counting(phase estimation) 계열은 설계에서 제외.
- **emulator와의 관계**: $\sqrt{\text{number of states}}$ 는 real quantum hardware의 oracle 호출 횟수 이야기다. classical circuit으로 흉내 내면 $O(\text{number of states}\cdot\sqrt{\text{number of states}/\text{number of solutions}})$ 이라 classical linear scan보다 느리므로, 비교 대상은 Qiskit Aer·NumPy state vector simulator이고 값어치는 속도가 아니라 **재현성과 verification**에 있다.

quantum computing 기초부터 Grover까지 살펴보았습니다. 다음 장은 배운 내용을 한눈에 보는 **cheat sheet와 glossary**입니다.

---

> [← 8장 Deutsch–Jozsa algorithm](08_deutsch_jozsa_algorithm.md) · [index](index.md) · [10장 용어정리와 치트시트 →](10_glossary_and_cheat_sheet.md)
