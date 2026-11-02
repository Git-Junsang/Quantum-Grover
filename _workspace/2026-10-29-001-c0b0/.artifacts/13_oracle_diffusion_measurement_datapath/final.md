# 13장. oracle과 diffusion operator — multiplier 없는 산술

> [← 12장 amplitude를 숫자로 — fixed-point와 Q1.22](12_fixed_point_and_precision.md) · [index](index.md) · [14장 multiple solutions — Born-rule sampling과 enumeration →](14_multiple_solutions_and_minimum_search.md)
> **이 장을 읽기 위한 준비**: [9.4절 4 states 손계산](09_grover_algorithm.md#94-진짜로-한-번-돌려보기--4-states), [9.7절 두 개의 반사](09_grover_algorithm.md#97-이제-수식으로--두-개의-reflection), [11.7절 병렬도와 banking](11_state_vector_emulator.md#117-병렬도와-banking), [11.8절 cycle 비용 model](11_state_vector_emulator.md#118-cycle-비용-model), [12장 fixed-point와 Q1.22](12_fixed_point_and_precision.md).

---

11장에서 state vector를 세 개의 array로 펼쳤고, 12장에서 그 array의 한 칸을 Q1.22 fixed-point로 정했습니다. 이 장은 그 array 위에서 **Grover iteration 한 바퀴**가 실제로 어떤 circuit이 되는지를 봅니다.

범위를 먼저 좁혀 두겠습니다. 이 장이 다루는 것은 **한 iteration 안쪽**뿐입니다. 몇 번 돌릴지 정하는 shot loop, 뽑힌 후보를 확인하는 solution check, amplitude array를 재활용할지 정하는 checkpoint는 전부 [16장](16_iteration_control_and_checkpoints.md)의 소관입니다. amplitude array에서 답 하나를 뽑는 measurement는 [14장](14_multiple_solutions_and_minimum_search.md)이고요. 여기서는 "목표 number of iterations를 받아 그만큼 돌고 빠져나오는" 안쪽 FSM만 봅니다.

이 장에서 확인할 성질은 다음과 같습니다 — **initialization·oracle·diffusion operator 경로에는 multiplier가 한 개도 없습니다.** 9장에서 배운 inversion about the mean이 어떤 연산으로 구현되는지 살펴보겠습니다. 동시에 multiplier가 정말로 필요한 곳이 어디인지도 13.8절에서 정확히 짚습니다. "0 multipliers"라고만 쓰면 어느 경로를 가리키는지 알 수 없어 부정확하기 때문입니다.

---

## 13.1 한 iteration 안의 FSM

안쪽 FSM은 네 종류의 state뿐입니다. initialization 한 번, 그다음 **Pass 1과 Pass 2를 iteration마다 한 번씩 왕복**하고 끝입니다.

| state | cycle (4 PEs) | 하는 일 |
|---|---:|---|
| `S_INIT` | 128 | amplitude array의 모든 칸을 `INIT_AMP` 로 (13.2) |
| `S_PASS1` | 128 + pipeline | predicate 판정 → sign 반전 → 되쓰기. **같은 흐름에서** 전체 accumulation (13.3·13.4) |
| `S_MEAN` | 1 | accumulator를 13칸 right shift하고 rounding해 $2\bar a$ 확정 (13.5) |
| `S_PASS2` | 128 + pipeline | 각 칸을 $2\bar a - a_i$ 로 갱신하고 saturation (13.5) |

final configuration은 4 PEs(PE 하나가 32 lanes)가 한 cycle에 4 rows(128칸)를 처리하므로 array 한 바퀴가 $\text{number of states}/128 = 128$ cycles입니다([11.7절](11_state_vector_emulator.md#117-병렬도와-banking)). 여기에 pipeline을 채우고 비우는 몇 cycle이 더해져 500 workloads campaign에서 잰 **Grover iteration 1회는 약 268 cycles**, 100 MHz에서 약 2.7 µs입니다([11.8절](11_state_vector_emulator.md#118-cycle-비용-model)). Pass 1에는 100 MHz timing을 맞추려고 adder tree 중간에 pipeline register를 넣은 탓에, 마지막 row를 되쓴 뒤 partial sum이 accumulator에 도착하기를 기다리는 **drain cycle**이 하나 있습니다. 결과 산술은 바뀌지 않고 latency만 늘어납니다.

oracle이 독립된 pass를 갖지 않는다는 점이 중요합니다 — sign 반전은 amplitude를 읽어 되쓰는 김에 끼워 넣을 수 있으므로, oracle은 **cycle을 한 개도 쓰지 않습니다.**

<img src="diagrams/13_datapath.svg" width="760" alt="안쪽 iteration FSM: Init(checkpoint가 출발점을 주면 생략) → (Pass 1 oracle + accumulation → 13칸 shift로 2×mean 확정 → Pass 2 diffusion operator와 symmetric saturation) × iterations → measurement로">

그림 맨 위의 "Init을 할지 말지"만 이 장 바깥의 결정입니다. checkpoint slot 중 하나에 이어 쓸 수 있는 amplitude array가 있으면 `S_INIT` 을 건너뛰고 곧바로 Pass 1로 들어가는데, 그 판정 규칙과 정당화는 [16.5절](16_iteration_control_and_checkpoints.md#165-checkpoint--measurement가-읽기-전용이라는-사실에서)에 있습니다. iteration이 끝난 뒤 amplitude array를 **지우지 않고 그대로 두는 것**도 같은 이유입니다.

---

## 13.2 Init — uniform amplitude를 square-root unit 없이

initialization은 $H^{\otimes \text{number of qubits}}|0\rangle$ 을 만드는 일, 즉 array의 모든 칸을 $1/\sqrt{\text{number of states}}$ 로 채우는 일입니다. 문제는 $\sqrt{\ }$ 가 hardware로 비싸다는 것입니다. 그런데 $\text{number of states} = 2^{\text{number of qubits}}$ 라는 사실을 쓰면 square-root unit이 통째로 사라집니다:

$$\frac{1}{\sqrt{\text{number of states}}} = \frac{1}{\sqrt{2^{\text{number of qubits}}}} = \begin{cases} 1 \times \dfrac{1}{2^{\text{number of qubits}/2}}, & \text{number of qubits}\text{ even} \\[2ex] \dfrac{1}{\sqrt 2}\times\dfrac{1}{2^{(\text{number of qubits}-1)/2}}, & \text{number of qubits}\text{ odd}\end{cases}$$

number of qubits가 짝수면 $1/\sqrt{\text{number of states}}$ 가 딱 power of two라 constant $1.0$ 을 그만큼 right shift하면 되고, 홀수면 $1/\sqrt 2$ 라는 **constant 하나**만 있으면 나머지는 역시 shift입니다. 04번 논문(Choi & Lee, 2024)이 Q1.30에서 쓰는 code가 이 꼴입니다:

```c
init_coefficient = (NUM_QUBIT % 2 == 0)
                 ? (0x4000_0000 >> (NUM_QUBIT / 2))         // 0x4000_0000 = 1.0
                 : (0x2D41_3CCE >> ((NUM_QUBIT - 1) / 2));  // 0x2D41_3CCE = 1/√2
```

우리는 14 qubits, 즉 **짝수 분기**입니다. Q1.22에서 $1.0$ 에 해당하는 integer는 $2^{22}$ 이고, 이것을 7칸(14 / 2) right shift하면 $2^{15} = 32{,}768$ 이 나옵니다. 그래서 **`INIT_AMP` = 32768** 이고, $32768/2^{22} = 1/128 = 1/\sqrt{16384}$ 가 **정확히** 성립합니다. rounding이 한 번도 일어나지 않으므로 초기 state의 norm도 정확히 1입니다. measurement 쪽 숫자로 확인하면, amplitude square의 총합이 $16384 \times 32768^2 = 2^{44}$ 이고 이것이 Q1.22 square의 $1.0$ 에 해당하는 값 그대로입니다(14.5절). constant가 필요 없으니 RTL은 이 값을 `grover_param.vh` 의 integer 하나로 정의합니다.

number of qubits가 홀수였다면 사정이 다릅니다. $1/\sqrt 2$ 를 22 fraction bits로 rounding하는 순간 error가 생기고, 그 error가 모든 칸에 똑같이 실려 초기 norm이 1을 살짝 벗어납니다. 짝수일 때는 이 오차가 생기지 않습니다.

다만 원문의 값을 그대로 옮겨 쓰면 안 됩니다. 논문에 인쇄된 constant `0x2D41_3CCE` 는 실제 $\frac{1}{\sqrt2}\times2^{30}$ = `0x2D41_3CCD` 와 **1 LSB 어긋나** 있습니다. 같은 수법으로 만든 number of iterations constant `0x1_1C58_31AC`($\frac{\pi\sqrt2}{4}\times2^{32}$) 도 실제 값 `0x1_1C58_31AE` 와 **2 LSB 어긋나** 있고요(`0x4000_0000` 과 `0xC90F_DAA2` = $\frac{\pi}{4}\times2^{32}$ 는 정확합니다). error가 $\sim10^{-9}$ 라 실용적으로는 무해하지만, 교훈은 constant 자체가 아니라 **1차 자료도 틀린다**는 것입니다. magic number는 인용하지 말고 직접 계산해 넣으십시오. 위의 32768도 직접 계산해 유도한 값입니다. (논문 constant·수식의 오류 목록 전체는 [15.6절](15_paper_map_and_design_decisions.md#156-인용-시-주의--논문의-오류와-모호점)에 모여 있습니다. number of iterations constant를 우리가 어떻게 다루는지는 [16.2절](16_iteration_control_and_checkpoints.md#162-bbht--무작위로-뽑는-number-of-iterations와-12-growth-factor)입니다 — 우리는 최적 number of iterations를 고정 constant로 정의하지 않기 때문에 이 constant를 쓸 일 자체가 별로 없습니다.)

---

## 13.3 oracle — predicate 4종이 subtractor 하나를 공유한다

이 project의 oracle은 **solution이 어디 있는지 아는 circuit이 아니라, 한 칸을 보고 predicate를 만족하는지 판정하는 circuit**입니다([14.2절](14_multiple_solutions_and_minimum_search.md#142-oracle은-solution을-아는-circuit이-아니다)). 우리 IP가 판정하는 predicate는 네 가지입니다:

$$\texttt{LT}:\ v_i < t_a \qquad \texttt{GT}:\ v_i > t_a \qquad \texttt{EQ}:\ v_i = t_a \qquad \texttt{RANGE}:\ t_a < v_i < t_b$$

여기서 $v_i$ 는 `data_mem` 의 $i$ 번 칸이고 $t_a, t_b$ 는 CSR로 받은 threshold입니다. data word는 16-bit signed입니다([12.8절](12_fixed_point_and_precision.md#128-data-word와-bram-환산)).

조건마다 comparator IP를 하나씩 두는 방법을 먼저 생각할 수 있지만, 네 개가 모두 필요하지는 않습니다. **비교는 subtraction의 sign bit 하나**이기 때문입니다. 16-bit operand를 sign extension해 17 bits로 빼면

$$d = \underbrace{\{v_{15}, v\}}_{17\text{b}} - \underbrace{\{t_{15}, t\}}_{17\text{b}}$$

이고, $d$ 의 최상위 bit `d[16]` 이 곧 $v < t$ 의 답입니다. sign extension을 빠뜨리면 $v = -32768$, $t = 1$ 같은 입력에서 subtraction이 overflow해 sign bit가 뒤집히므로, 17 bits로 넓히지 않으면 circuit이 잘못된 결과를 냅니다. 나머지 predicate는 이 subtractor를 재활용합니다.

| predicate | subtractor 입력 $A - B$ | `hit_i` combinational logic | 추가 hardware |
|---|---|---|---|
| `LT` $v_i < t_a$ | $A = v_i$, $B = t_a$ | `d1[16]` | 없음 |
| `GT` $v_i > t_a$ | $A = t_a$, $B = v_i$ (**operand 교환**) | `d1[16]` | 입력 mux |
| `EQ` $v_i = t_a$ | (subtractor를 쓰지 않음) | `~\|(v_i ^ t_a)` (XOR-NOR) | XOR 16개 + NOR 1단 |
| `RANGE` $t_a < v_i < t_b$ | $A = t_a, B = v_i$ / $A = v_i, B = t_b$ | `d1[16] & d2[16]` | subtractor 하나 더 |

`GT` 는 추가 비교 연산이 필요 없다는 점을 눈여겨보십시오. $v > t$ 는 $t < v$ 와 같은 말이므로, subtractor에 들어가는 두 입력을 **바꿔 넣기만** 하면 됩니다. comparator를 새로 만들 이유가 없습니다. `EQ` 는 subtractor조차 필요 없습니다 — 두 값이 같다는 것은 XOR 결과가 전부 0이라는 뜻이니 XOR 한 층과 NOR 한 층이면 끝이고, 이게 subtraction 결과가 0인지 보는 것보다 latency가 짧습니다. `RANGE` 만 비교가 둘이라 subtractor를 하나 더 둡니다. 17-bit subtractor는 LUT 수십 개 수준이라 128 lanes에 깔아도 부담이 크지 않습니다 — implementation report에서 lane 하나의 predicate circuit이 LUT 한 자릿수로 잡힙니다. 경계가 열린 interval($<$)인지 닫힌 interval($\le$)인지는 circuit이 아니라 **약속**의 문제이고, 우리는 위 표대로 네 predicate 모두 strict inequality로 고정합니다. 경계값 test는 [18.5절](18_reference_model_verification.md#185-predicate-4종과-경계값)에서 따로 다룹니다.

판정 앞에는 조건이 하나 더 있습니다. host가 array를 다 채우지 않고 `DATA_COUNT` 개만 올렸다면, index가 `DATA_COUNT` 이상인 칸은 memory에 무엇이 남아 있든 **항상 non-solution**입니다(padding gate). 이 조건이 없으면 지난 실험에서 남은 값이 solution으로 판정될 수 있습니다.

마지막으로 **enumeration mode**가 이 판정에 한 겹을 더합니다. 이미 찾아낸 index를 다시 뽑지 않으려면 `found_mask` 의 bit를 AND로 걸면 됩니다:

$$\texttt{hit}_i = \texttt{predicate}(v_i) \ \wedge\ \overline{\texttt{found}[i]}$$

AND gate 하나가 전부이고, 이것이 왜 정당한 oracle인지는 [14.7절](14_multiple_solutions_and_minimum_search.md#147-enumeration-mode--mask로-중복-없이)에서 설명합니다.

solution index를 parameter로 고정하고 그 칸만 뒤집는 circuit — predicate 판정이 아예 없는 형태 — 도 값어치가 있긴 합니다. 9장의 수식을 **최소 circuit으로 확인하는 한 단계**이기 때문입니다. 판정 logic가 없으니 diffusion operator와 iteration만 남고, 그러면 [9.4절](09_grover_algorithm.md#94-진짜로-한-번-돌려보기--4-states)의 4 states 손계산과 waveform을 한 칸씩 대조할 수 있습니다([18.4절](18_reference_model_verification.md#184-첫-test-vector는-94절의-손계산)). 다만 그것은 verification을 위한 중간 단계이며 실제 설계는 아닙니다. 우리 oracle은 처음부터 위 표의 predicate circuit입니다.

---

## 13.4 sign 반전 — two's complement negate 한 번

판정 뒤의 연산은 간단합니다. oracle $U_f$ 가 하는 일은 predicate를 만족하는 칸의 **sign을 뒤집는 것**뿐이고, fixed-point는 two's complement이므로 sign 반전은 bit 반전 + 1입니다.

$$a_i \leftarrow (-1)^{\texttt{hit}_i}\, a_i$$

조건부 반전이라는 점을 이용하면 gate가 더 줄어듭니다. `hit` 를 XOR의 한 입력과 adder의 carry-in에 동시에 넣으면 됩니다:

```verilog
// hit=0 이면 amp 그대로, hit=1 이면 ~amp + 1 = -amp
wire signed [DW-1:0] amp_o = (amp ^ {DW{hit}}) + hit;
```

multiplication도, ancilla qubit도, 별도의 state도 없습니다. 실기에서 multi-controlled $Z$ gate로 만들어야 하는 phase 반전이 emulator에서는 XOR 한 줄이 되는 것 — [11.9절](11_state_vector_emulator.md#119-emulator가-실기보다-쉬운-것들)에서 설명한 차이를 잘 보여 주는 사례입니다.

two's complement에는 원래 **sign 반전이 불가능한 값**이 하나 있습니다. 23-bit container의 minimum $-4{,}194{,}304$($= -1.0$)를 반전하면 $+4{,}194{,}304$ 인데 이 값은 23 bits에 담기지 않습니다. wraparound로 두면 $-1.0$ 이 $-1.0$ 으로 되돌아와 **sign 반전이 항등이 되어 그 칸에서는 oracle이 작동하지 않습니다.** 우리 설계에서는 이 실패 mode가 구조적으로 사라집니다. [12.5절](12_fixed_point_and_precision.md#125-overflow-policy--saturationwraparound-금지renormalization-없음)의 symmetric saturation이 amplitude를 $[-4{,}194{,}303,\ +4{,}194{,}303]$ 안에만 두기 때문에, array에 들어 있는 어떤 값을 뒤집어도 다시 합법 범위 안입니다. 아래쪽 끝을 한 칸 버린 이유가 여기 있습니다.

---

## 13.5 diffusion operator — 2·mean − amp가 circuit이 되는 순간

9장에서 diffusion operator를 "inversion about the mean" $a\mapsto 2\bar a - a$ 로 배웠습니다(9.4·9.7절). 이 한 줄이 circuit에서 어떻게 펼쳐지는지 봅니다. 9.7절에서 쓴 diffusion operator $U_\psi$ 를 matrix로 펼치면 이렇게 생겼습니다($|\psi\rangle$ 은 uniform superposition):

$$U_\psi = H^{\otimes \text{number of qubits}}\big(2|0\cdots0\rangle\langle0\cdots0| - I\big)H^{\otimes \text{number of qubits}} = 2|\psi\rangle\langle\psi| - I = \begin{bmatrix} 2^{-\text{number of qubits}+1} & \cdots & 2^{-\text{number of qubits}+1} \\ \vdots & \ddots & \vdots \\ 2^{-\text{number of qubits}+1} & \cdots & 2^{-\text{number of qubits}+1}\end{bmatrix} - I$$

"모든 원소가 $2^{-\text{number of qubits}+1}$ 인 matrix에서 identity matrix를 뺀" 꼴입니다. 언뜻 $\text{number of states}\times\text{number of states}$ matrix-vector product($O(\text{number of states}^2)$)가 필요해 보이지만, 이 특수 구조 덕분에 **세 단계**로 분해됩니다. 지금 array에 저장된 state를 $|\phi\rangle = \sum_i \beta_i|i\rangle$ 라고 두면:

$$U_\psi|\phi\rangle = 2^{-\text{number of qubits}+1}\begin{bmatrix}\sum_i\beta_i \\ \vdots \\ \sum_i\beta_i\end{bmatrix} - \begin{bmatrix}\beta_0 \\ \vdots \\ \beta_{\text{number of states}-1}\end{bmatrix}$$

즉 ① 모든 amplitude를 **더하고**(accumulation $\sum\beta_i$), ② $2^{-\text{number of qubits}+1}$ 을 **곱하고**(= $\text{number of qubits}-1$ bits right shift), ③ 각 원소를 그 값에서 **빼면**($\text{sum}\times2^{-\text{number of qubits}+1} - \beta_i$) 끝입니다. 이것이 정확히 inversion about the mean입니다 — 왜냐하면 $2^{-\text{number of qubits}+1}\sum\beta_i = \frac{2}{\text{number of states}}\sum\beta_i = 2\bar\beta$ 이고, 따라서 세 번째 단계가 $2\bar\beta - \beta_i$ 이니까요.

**"왜 $\text{number of qubits}-1$ 칸 shift인가"** 가 여기서 풀립니다. mean은 sum을 $2^{\text{number of qubits}}$ 으로 나누는 것(= $\text{number of qubits}$ 칸 right shift)이지만, 우리가 실제로 필요한 것은 mean이 아니라 **2×mean**($2\bar a$)입니다. $\frac{2}{2^{\text{number of qubits}}} = \frac{1}{2^{\text{number of qubits}-1}}$ 이므로, $\text{number of qubits}$ 칸 shift 후 다시 2를 곱하는 대신 처음부터 **$\text{number of qubits}-1$ 칸만** shift하면 한 번에 $2\bar a$ 가 나옵니다. 14 qubits면 13칸입니다.

두 번에 나눠 하지 않는 것이 중요합니다. `mean = sum >>> n` 으로 밀었다가 `two_mean = mean <<< 1` 로 되미는 implementation은 결과값은 같아 보여도 **최하위 bit 하나를 버립니다**(오른쪽으로 밀 때 떨어져 나간 bit는 왼쪽으로 되밀어도 0으로 채워집니다). 한 번에 13칸을 미는 쪽이 precision이 낫고, 무엇보다 **rounding이 일어나는 지점이 정확히 한 곳으로 고정**됩니다.

그 지점을 확인해 두겠습니다. 한 번의 Grover iteration에서 fraction bits가 줄어드는 곳은 **accumulator를 13칸 right shift하는 이 한 순간뿐**입니다. oracle의 sign 반전은 정확하고, 반사의 subtraction도 두 operand가 모두 22 fraction bits라 정확합니다. 그러므로 [12.4절](12_fixed_point_and_precision.md#124-rounding--왜-half-to-even인가)의 round-half-to-even은 여기, 오직 여기에만 적용됩니다:

```verilog
localparam K = NBITS - 1;                    // n=14 → 13
wire [ACCW-1:0] trunc = $signed(sum) >>> K;  // 버림
wire            half  = sum[K-1];            // 버려지는 bit 중 최상위
wire            rest  = |sum[K-2:0];         // 그 아래에 1이 하나라도 있나
wire [ACCW-1:0] two_mean = trunc + (half & (rest | trunc[0]));
```

마지막 줄이 half-to-even 그 자체입니다. 버려지는 부분이 정확히 절반이면(`half=1, rest=0`) 결과의 최하위 bit가 1일 때만 올림해서 짝수로 맞춥니다. RTL은 이 결과를 25-bit `two_mean` register에 담습니다([12.3절](12_fixed_point_and_precision.md#123-integer-bits는-몇-bit인가--재는-대상이-셋이다)). 매 iteration 한 번씩, 1 solution이면 100 iterations 안팎 동안 적용되는 이 규칙이 reference model과 RTL이 bit 단위로 일치하기 위한 첫 번째 조건입니다([18.3절](18_reference_model_verification.md#183-bit-exact가-성립하기-위한-조건)).

subtraction 결과 $2\bar a - a_i$ 는 25-bit 폭에서 계산되고, 되쓰기 직전에 23-bit 대칭 범위로 saturation됩니다. saturation이 걸리면 그 lane이 signal을 내고, 한 번이라도 걸린 search는 `amp_overflow` 가 섭니다(12.5절).

그리고 이 세 단계 어디에도 **multiplier가 없습니다.** accumulation은 addition, $2^{-\text{number of qubits}+1}$ 을 곱하는 것은 shift, 반사는 subtraction — 전부 addition 계열입니다.

---

## 13.6 왜 2 passes인가

diffusion operator가 왜 굳이 두 번의 array 순회로 쪼개지는지는 한 문장으로 답할 수 있습니다. **$2\bar a - a_i$ 를 계산하려면 $\bar a$ 가 이미 확정돼 있어야 하는데, $\bar a$ 는 모든 $a_i$ 를 다 더해야 나오기 때문입니다.**

<img src="diagrams/13_diffusion_2pass.svg" width="600" alt="diffusion operator 2 passes timing: accumulation이 확정된 뒤에야 subtraction이 가능">

accumulation과 subtraction을 한 pass에서 섞으면 아직 다 더해지지도 않은 partial sum으로 subtraction이 시작됩니다. array 앞쪽 칸은 거의 0에 가까운 partial sum으로 반사되고 뒤쪽 칸은 거의 전체 sum으로 반사되어, 결과는 diffusion operator의 계산과 달라집니다. simulation에서 잡기 어려운 종류의 버그는 아니지만(amplitude의 오차가 뚜렷합니다), 이 순서 제약이 **algorithm에서 오는 것이지 implementation 편의가 아니라는** 점이 중요합니다. diffusion operator는 전역 연산이고, 전역 연산은 global reduction을 먼저 끝내야 합니다.

그래서 Pass 1은 oracle을 건 amplitude를 memory에 되쓰면서 sum을 모으고, Pass 2는 그 되쓴 값을 다시 읽어 $2\bar a$ 에서 뺍니다. checkpoint가 출발점을 준 경우에는 Pass 1이 출발 checkpoint slot에서 읽어 목적 checkpoint slot에 쓰고, Pass 2가 목적 checkpoint slot을 읽고 덮어쓰는 식으로 두 pass가 checkpoint slot을 나눠 쓰기도 합니다(16.5절). 어느 쪽이든 순서 제약은 같습니다.

이 제약이 남기는 흔적은 cycle만이 아닙니다. 12장에서 폭을 따로 잡았던 것이 전부 여기서 나옵니다. 첫째, Pass 1이 만드는 sum은 모든 amplitude의 총합이라 amplitude 하나보다 훨씬 큽니다. 그래서 accumulator는 amplitude container보다 넓어야 하고, 그 폭이 data word width + number of qubits + 2 = 23 + 14 + 2 = 39 bits입니다. 둘째 — 그리고 이쪽이 놓치기 쉬운데 — **넓혀야 하는 것이 accumulator만이 아닙니다.** Pass 2가 만드는 값 $2\bar a - a_i$ 자체가 이론상 $1 + 2/\sqrt{\text{number of states}} = 1.0156$ 까지 커져 Q1.22의 표현 범위를 넘을 수 있습니다. 그래서 이 값은 25-bit register에서 계산하고, memory에 되쓸 때만 23-bit 대칭 범위로 붙입니다([12.3절](12_fixed_point_and_precision.md#123-integer-bits는-몇-bit인가--재는-대상이-셋이다)). 되쓰는 값은 수학적으로 1을 넘지 않으므로 saturation이 걸리는 것은 rounding이 한두 LSB 넘긴 드문 경우뿐입니다.

---

## 13.7 32-lane datapath와 accumulation 순서

지금까지의 circuit은 amplitude 한 칸을 다루는 이야기였습니다. 실제로는 PE 하나가 한 cycle에 row 하나(32칸)를 처리하고, final configuration에는 **4 PEs**가 있어 128칸이 한꺼번에 흐릅니다([11.7절](11_state_vector_emulator.md#117-병렬도와-banking)).

address 생성부터 봅니다. index의 **하위 5 bits가 lane, 상위 9 bits가 row**이고, row 번호의 하위 2 bits가 네 row phase bank 중 하나를 고릅니다(14 qubits):

$$i = \underbrace{\texttt{row}[8{:}2]}_{\text{address in bank}}\ \Vert\ \underbrace{\texttt{row}[1{:}0]}_{\text{row phase bank}}\ \Vert\ \underbrace{\texttt{lane}[4{:}0]}_{\text{lane}}$$

이렇게 잘라 두면 address generator가 7-bit counter 하나로 끝납니다. cycle $c$ 에는 네 bank가 **모두 같은 address $c$** 를 읽어 row $4c \ldots 4c+3$ 이 한꺼번에 나오므로 충돌이 원리적으로 0이고, crossbar나 permutation network가 필요 없습니다. amplitude를 임의로 재배치해야 하는 범용 gate simulator가 permutation network 하나에 logic의 3분의 1을 쓰는 것과 대조됩니다 — Grover의 두 연산(전역 균일 반사, index별 predicate 판정)이 둘 다 **순차 streaming**으로 충분하기 때문에 우리는 그 비용을 통째로 피합니다.

lane 하나는 지금까지 만든 것을 그대로 복제한 것입니다. `data_mem` 에서 $v_i$, amplitude memory에서 $a_i$ 를 같은 cycle에 읽고, subtractor가 predicate를 판정하고, XOR-carry-in 한 줄이 sign을 뒤집어 되씁니다. 여기에 Pass 1에서만 쓰이는 것이 하나 더 붙습니다 — **lane 간 adder tree**입니다. PE 하나마다 32 amplitudes를 5단 adder tree로 더하면 단마다 폭이 1-bit씩 늘어 $23 + 5 = 28$-bit partial sum이 되고, PE마다 accumulator가 하나씩 이 partial sum을 128 cycles 동안 모읍니다. mean을 확정할 때는 **네 accumulator를 더한 전체 sum**에서 13.5절의 shift를 한 번 합니다. 39 bits는 이 모든 경우를 최악값으로 담는 폭입니다.

여기에 함정이 하나 있습니다. **addition 순서를 고정하지 않으면 bit-exact가 흔들릴 수 있습니다.** integer addition은 폭이 충분하면 순서에 무관하게 같은 값을 주므로 언뜻 신경 쓸 일이 없어 보입니다 — 실제로 우리 RTL은 partial sum을 자르지 않고 최악 폭으로 담기 때문에, tree 모양이 달라도 integer 결과는 같습니다. 하지만 두 가지 경우에 순서가 결과를 바꿉니다. 첫째, 폭을 아끼려고 중간 partial sum을 좁은 register에 담아 자르거나 saturation하는 순간, 어느 쌍을 먼저 더했는지가 잘리는 bit를 바꿉니다. 둘째, float64 model과 대조할 때는 **floating-point addition은 associativity를 만족하지 않으므로** 순서가 곧 결과입니다. `sum += a[i]` 로 차례로 더한 float model과 tree로 더한 RTL은 마지막 bit가 다를 수 있습니다. 그래서 bit-exact 대조의 상대는 float64 model이 아니라 **integer로만 계산하는 fixed-point reference model**이고, 이 항목이 [18.3절](18_reference_model_verification.md#183-bit-exact가-성립하기-위한-조건)의 고정 대상 목록에 들어 있는 이유입니다.

Pass 2에는 adder tree가 없고, 대신 확정된 $2\bar a$ 가 128 lanes에 broadcast되어 각 lane이 subtraction과 saturation 하나씩을 합니다. broadcast signal이 128곳으로 퍼지므로 fanout이 커지는데, pipeline register를 한 단 두어 나눠 주면 100 MHz에서 문제가 되지 않습니다. 실제로 이 IP는 100 MHz에서 timing을 닫았습니다(WNS +0.126 ns, 17장).

---

## 13.8 multiplier는 어디에 있고 어디에 없는가

이제 이 장에서 설명한 연산 경로를 정리합니다.

**initialization·oracle·diffusion operator 경로에는 multiplier가 0개입니다.** initialization은 constant 하나, oracle은 subtractor와 XOR, diffusion operator는 adder tree·arithmetic right shift·subtraction·saturation뿐입니다. 임의 실수를 곱하는 자리가 한 군데도 없으니 DSP가 잡힐 이유가 없습니다. 이것은 우연이 아니라 Grover라는 algorithm의 성질입니다 — oracle이 거는 phase가 $0$ 아니면 $\pi$(sign $+$ 아니면 $-$)뿐이고, diffusion operator가 곱하는 계수가 $2^{-\text{number of qubits}+1}$ 이라는 power of two뿐이기 때문입니다. 같은 연구실의 QAOA emulator(06번)와 대조하면 선명해집니다. QAOA는 임의 각도 $e^{i\theta}$ 회전이 필요해서 CORDIC과 complex number multiplier를 넣어야 했고 DSP를 31~32개 고정으로 씁니다. Grover는 그 회전 hardware가 통째로 필요 없습니다.

**그러나 Measurement Unit에는 multiplier가 있습니다.** Born-rule sampling은 amplitude square $a_i^2$ 의 prefix sum을 만들어야 하고, square는 shift로 바뀌지 않습니다([14.5절](14_multiple_solutions_and_minimum_search.md#145-2단-병렬-measurement)). $23\times23$ multiplication은 Artix-7의 DSP48(25×18 multiplier) 하나에 들어가지 않아 squarer 하나가 DSP **2개**를 씁니다. 32 lanes면 64개이고, final configuration은 measurement 준비 단계에서 한 cycle에 2 rows를 제곱하도록(Dual-Row Build) 32-lane squarer를 두 벌 두므로 **DSP 128개**입니다. board가 주는 240개 중 절반을 조금 넘고, SoC가 쓰는 4개를 더해 board 전체가 132 / 240입니다.

그래서 예전 revision에 있던 "합성했는데 DSP가 잡히면 잘못 짠 것"이라는 점검 기준은 **틀렸습니다.** 우리 IP를 합성하면 DSP가 128개 잡히고, 그것이 정상입니다. 올바른 점검 기준은 경로를 붙인 쪽입니다:

| 경로 | 기대 DSP | 잡히면 의심할 것 |
|---|---:|---|
| Init | 0 | constant를 shift가 아니라 multiplication으로 썼는가 |
| oracle (predicate·sign 반전) | 0 | comparator IP나 multiplication 기반 비교를 불렀는가 |
| diffusion operator (accumulation·shift·subtraction·saturation) | 0 | `two_mean` 을 `sum >>> (n−1)` 대신 multiplication·division으로 썼는가 |
| measurement (sum of squares) | **128** | 128보다 많으면 squarer가 중복 instantiate됐는가 |
| Measurement PRNG | 0 | multiplication이 필요한 PRNG를 골랐는가 (xorshift는 shift와 XOR뿐) |

`two_mean` 을 `2 * (sum / N)` 처럼 풀어 써 두면 synthesis tool이 대개는 shift로 알아서 바꿔 주지만, 폭이 애매하거나 sign이 섞이면 multiplier·divider가 생성될 수 있습니다. shift로 쓸 수 있는 것은 **shift로 쓰는 편**이 synthesis 결과를 예측 가능하게 만듭니다 — 13.5절의 `sum >>> (n−1)` 한 줄이 그 자리입니다. 그리고 synthesis report를 볼 때는 총 DSP 사용량이 아니라 **어느 module에서 잡혔는지**를 보십시오. 우리 implementation report에서 128개는 전부 measurement sampler의 squarer 두 벌 아래에 잡혀 있습니다. 이 표는 그 확인용입니다.

---

## 13.9 이 장의 요약

- 안쪽 FSM은 `Init → (Pass 1: oracle + accumulation → Mean → Pass 2: diffusion operator) × iterations` 뿐입니다. shot loop·solution check·checkpoint는 [16장](16_iteration_control_and_checkpoints.md), measurement는 [14장](14_multiple_solutions_and_minimum_search.md)입니다.
- **pass 1회 = 128 cycles**(4 PEs가 한 cycle에 4 rows), **iteration 1회 ≈ 268 cycles**(2 passes + pipeline, campaign 직선 맞춤), 100 MHz에서 약 2.7 µs. **oracle은 cycle을 쓰지 않습니다** — amplitude를 읽어 되쓰는 김에 sign을 뒤집습니다.
- **Init**: 14 qubits는 짝수라 $1/\sqrt{\text{number of states}} = 2^{-7}$. Q1.22에서 $2^{22} \gg 7 =$ **32768**, error 0, 초기 norm 정확히 1.
- **oracle**: comparator IP 없이 **sign extension한 subtraction의 MSB 하나**가 `<` 의 답. `>` 는 operand 교환(공짜), `=` 는 XOR-NOR, 범위는 두 비교의 AND, `DATA_COUNT` 밖은 항상 non-solution, enumeration mode는 `!found[i]` 를 AND. 뒷단은 two's complement negate 한 줄이고, symmetric saturation 덕에 negate가 늘 합법입니다.
- **diffusion operator**: $a\mapsto 2\bar a - a$ = accumulation → **13칸(number of qubits − 1) shift**(∵ 필요한 건 mean이 아니라 2×mean) → subtraction → symmetric saturation. round-half-to-even이 적용되는 지점은 **이 shift 한 곳뿐**입니다.
- **2 passes는 필연**입니다. mean이 전체 sum을 요구하기 때문입니다. 그 대가로 accumulator가 39 bits, 반사 중간값이 25 bits로 넓어지고, 되쓸 때 23 bits로 붙입니다.
- **128 lanes**: index 하위 5 bits가 lane, row 번호 하위 2 bits가 row phase bank → 충돌 0, crossbar 불필요. PE마다 5단 adder tree와 accumulator가 하나씩이고, 네 accumulator의 sum에서 mean을 확정합니다. partial sum을 자르지 않아 integer 결과는 순서에 무관하지만, bit-exact 대조의 상대는 float64가 아니라 integer reference model입니다([18.3절](18_reference_model_verification.md#183-bit-exact가-성립하기-위한-조건)).
- **multiplier**: Init·oracle·diffusion operator 경로 **0개**, measurement 경로 **128개**(23×23 squarer가 DSP 2개씩, 32 lanes × squarer 두 벌). "DSP가 잡히면 잘못 짠 것"이 아니라, **어느 경로에서** 잡혔는지를 보십시오.

다음 장은 이 datapath가 만들어 낸 amplitude array에서 답을 뽑습니다. predicate를 만족하는 칸이 여럿일 때 그 amplitude들이 매 iteration 정확히 같아진다는 사실, 그래서 maximum을 고르는 방식이 원리적으로 실패한다는 사실, 그리고 Born-rule sampling을 circuit으로 만드는 방법을 봅니다.

---

> [← 12장 amplitude를 숫자로](12_fixed_point_and_precision.md) · [index](index.md) · [14장 multiple solutions →](14_multiple_solutions_and_minimum_search.md)

<!-- HUMANIZE-SUMMARY -->
<!-- {"original_chars": 21908, "final_chars": 21871, "change_rate": 0.0131, "grade": "B", "self_check": "6/6 통과 (학습서 장르와 사용자 보존 조건에 따라 기존 서식·제목·콜아웃 제외)", "categories": ["D-14", "D-8"], "highlights": [{"rule": "D-14", "before": "Q1.22 fixed-point로 못 박았습니다.", "after": "Q1.22 fixed-point로 정했습니다."}, {"rule": "D-8", "before": "이 장이 심으려는 감각은 하나입니다 —", "after": "이 장에서 확인할 성질은 다음과 같습니다 —"}], "residual_findings": [], "warnings": ["각주 검사 경고 3건은 수정 전 원문을 원문 자신과 비교해도 동일하게 발생함. 수식·수치·code·제목·link 직접 보존 검사는 통과함."], "finalizer_corrections": 0} -->
