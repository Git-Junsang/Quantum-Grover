# 18장. 무엇을 어떻게 증명하나 — 3단 reference model과 bit-exact

> [← 17장 RVX SoC에 붙이기 — APB CSR · AHB DMA · UART](17_rvx_soc_integration.md) · [index](index.md)
> **이 장을 읽기 위한 준비**: [9.4절 4-state 손계산](09_grover_algorithm.md#94-진짜로-한-번-돌려보기--4-states), [12장 amplitude를 숫자로](12_fixed_point_and_precision.md)의 Q1.22·round-half-to-even·saturation, [13장 oracle과 diffusion operator](13_oracle_diffusion_measurement_datapath.md)의 datapath, [14장 multiple solutions](14_multiple_solutions_and_minimum_search.md)의 Measurement Unit(14.5절), [16장 BBHT shot loop와 checkpoint](16_iteration_control_and_checkpoints.md), [17장 RVX SoC에 붙이기](17_rvx_soc_integration.md)의 CSR map.

---

앞의 일곱 장이 설계를 확정했습니다. 이 장은 그 설계가 맞다는 것을 **어떤 절차로 확인했는가**를 정리합니다.

이 장이 필요한 이유가 두 군데에 이미 적혀 있습니다. 12.7절은 05번 논문의 minimum fraction bits 공식이 전제하는 조건 셋을 우리가 전부 벗어난다고 결론 내리면서, 22 fraction bits가 충분한지는 "이론으로 정하지 않고 직접 잰다"고 했습니다. 15.6절의 정오표는 여섯 편의 1차 자료 모두에 인용할 때 주의해야 할 오류가 있음을 보이면서 논문 수치는 직접 재현해 확인하라고 못 박았습니다. 두 결론 모두 **재는 절차**가 필요하다는 뜻입니다. 초판에서 계획이었던 그 절차가 이제 실제로 돌았고, 이 장은 그 절차와 결과를 함께 씁니다.

---

## 18.1 왜 verification이 설계의 일부인가

보통 verification은 설계가 끝난 뒤에 붙는 일로 취급됩니다. 이 project에서는 그렇지 않습니다. 이유가 셋 있습니다.

**첫째, 1차 자료가 틀립니다.** 15.6절의 정오표는 논문의 사소한 오탈자 모음이 아닙니다. 04번의 pseudocode는 그대로 옮기면 **circuit이 동작하지 않고**, 04번이 제시한 magic number 두 개는 최하위 bit가 어긋나 있으며, 09번 식 (9)·(12)의 sign 규약은 본문과 어긋나서 그대로 쓰면 minimum이 아니라 **maximum**을 찾습니다. 이 사례들은 검증할 때 다음과 같은 태도가 필요함을 보여줍니다 — hardware로 옮기기 전에 원문을 의심하고, 수치는 직접 계산해 보고, sign은 simulation으로 확인한다. 이 셋을 하려면 원문과 대조할 수 있는 참조 implementation을 갖추어야 합니다.

**둘째, 이 설계에는 이론이 답을 주지 못하는 자리가 있습니다.** 12.7절이 그 대표입니다. minimum fraction bits 공식은 truncation·넓은 단일 data word·distribution 전체의 $\ell_2$ error를 전제하는데 우리는 round-half-to-even을 쓰고, 저장 data word가 23 bits로 좁고, 우리가 신경 쓰는 것은 distribution 전체가 아니라 "solution check를 통과할 답이 제때 나오는가"입니다. 공식을 대입하면 아슬아슬하다는 답이 나오지만 그 답은 우리 조건의 답이 아닙니다. 그러면 남는 방법은 하나 — 우리 조건을 그대로 담은 model을 만들어 직접 재는 것입니다. 즉 verification infrastructure가 있어야 **설계 결정을 내릴 수 있습니다.** 설계를 확정하기 전부터 검증이 필요한 것이지요.

**셋째, 이 IP의 값어치 자체가 verification 가능성입니다.** 여러 번 못 박았듯 이 accelerator는 classical linear scan보다 빠르지 않습니다. emulation 비용이 $O(\text{number of states}\sqrt{\text{number of states}/\text{number of solutions}})$ 이라 원리적으로 그럴 수 없습니다. 이 IP가 주는 것은 속도가 아니라 **quantum algorithm의 동작을 결정적이고 재현 가능하게 재현·검증하는 전용 hardware**라는 성질입니다. 그렇다면 "재현 가능하다"는 주장을 뒷받침하는 절차가 곧 제품 사양의 일부입니다. verification 계획이 부실하면 기능이 부실한 것과 같습니다.

---

## 18.2 3단 verification ladder

핵심 구조는 단순합니다. 참조 implementation을 **세 칸**으로 나누고, 각 칸이 잡는 버그의 종류를 다르게 둡니다. 마지막에는 board에서 확인합니다.

<img src="diagrams/18_golden_ladder.svg" width="760" alt="verification ladder: 1단 NumPy float64 · Qiskit Aer(algorithm) → 2단 Q1.22 bit-exact reference model(수 표현) → 3단 RTL(circuit) → board(실물), 각 단계의 합격 기준과 benchmark 결과">

**1단 — NumPy float64와 Qiskit Aer. 묻는 것은 "algorithm이 맞나".** amplitude를 double-precision real number로 두고 Grover iteration·Born-rule sampling·BBHT shot loop를 그대로 옮깁니다. 수 표현은 사실상 무한 precision이라고 보고, 오직 논리만 봅니다. 이 칸이 잡는 버그는 predicate 판정의 방향(`<` 를 `>` 로 짠 것), diffusion operator의 sign, number of iterations를 한 칸 잘못 센 overshoot, BBHT의 sampling range 갱신 누락 같은 것들입니다. 전부 "circuit 이전"의 실수이고, 여기서 못 잡으면 뒤 칸에서는 훨씬 비싸게 잡힙니다. 우리 저장소에는 이 칸이 둘입니다 — 직접 짠 NumPy state vector와 범용 quantum simulator Qiskit Aer. 둘은 Iteration-Count LFSR의 같은 random number와 같은 measurement 규칙으로 BBHT를 돌아, 500 workloads 전부에서 결과 index·shot count·requested iterations가 **서로** 같았습니다(500/500).

이 칸의 결과를 2단과 그대로 맞대면 안 된다는 점을 짚어 둡니다. floating-point와 fixed-point는 probability distribution이 아주 조금 다르고, 같은 random number라도 prefix sum이 경계를 넘는 칸이 달라질 수 있습니다. 실제로 1 solution에서 requested iterations의 median이 1단은 149.5, 2단과 board는 163.5였습니다(shot count median은 둘 다 23). 둘 다 옳은 결과입니다 — BBHT trajectory가 같아야 하는 것은 **같은 칸끼리**입니다.

**2단 — Q1.22 bit-exact reference model. 묻는 것은 "수 표현이 맞나".** 1단과 논리는 같지만 real number를 전부 integer로 바꿉니다. amplitude는 23-bit integer, shift는 arithmetic right shift에 round-half-to-even, 넘치면 symmetric saturation, accumulator는 정해진 폭, random number는 RTL과 같은 생성기와 같은 소비 규약. Python으로 쓰되 **floating-point를 한 줄도 섞지 않는 것**이 규율입니다. 이 칸이 잡는 버그는 rounding 편향, 예상 밖의 saturation, accumulator 폭 부족, shift를 rounding 앞에 둘지 뒤에 둘지 같은 것들입니다. 12.7절이 넘겨 둔 질문 — 22 fraction bits가 충분한가 — 의 답도 이 칸에서 나왔습니다. **이 model이 곧 "reference model"입니다.** RTL과 bit 단위로 맞춰 볼 상대가 이 칸이지 1단이 아닙니다. 저장소에서는 arithmetic·random number·measurement를 담은 `fixed_point_statevector.py` 와, 그 위에 BBHT 제어·checkpoint policy·enumeration을 얹은 `checkpoint_bbht_model.py` 가 이 칸입니다([software reference model 안내](../design_references/04_software_reference_model_and_test_vectors.md)).

**3단 — RTL. 묻는 것은 "circuit이 맞나".** 이 칸이 잡는 버그는 앞의 둘과 완전히 종류가 다릅니다. FSM state 전이, address generator의 off-by-one, row·lane indexing(하위 5 bits인데 상위 5 bits를 쓴다든가), pipeline stage 사이의 latency 정렬, 같은 address를 읽으면서 쓰는 hazard, CSR handshake, reset 후 초기값. arithmetic은 이미 2단에서 검증됐으므로, 여기서 값이 어긋나면 원인은 **거의 언제나 timing이나 제어**입니다. 합격 기준은 2단과 **bit-exact** — iteration이 끝난 시점의 amplitude 16,384칸이 전수 일치하고, 같은 seed를 넣었을 때 shot별 후보 index sequence가 완전히 같아야 합니다. 2단이 만든 requested-j test vector 256 cases가 앞의 기준을, 500 workloads RTL campaign이 뒤의 기준을 봅니다.

**그리고 board.** verification ladder의 마지막 확인은 실물입니다. 같은 500 workloads를 board에 올려, 2단 reference model과 board가 결과 index·shot count·requested iterations에서 500/500, checkpoint의 executed iterations까지 500/500 같았습니다. RTL과 board도 BBHT trajectory는 500/500 같았습니다 — 다만 cycle 값 자체는 달라서(final configuration은 대부분의 workload가 정확히 3,279 cycles 차이), board에서는 wall-clock time을, RTL에서는 cycle을 인용합니다.

이 verification ladder에서 가장 중요한 규율은 **한 칸도 건너뛰지 않는 것**입니다. RTL을 곧바로 float64 model과 비교하면, 값이 어긋났을 때 원인이 rounding 규칙인지 FSM인지 구분할 방법이 없습니다. 두 종류의 error가 섞여 있으면 "얼마나 어긋나야 버그인가"라는 판정 기준조차 세울 수 없고, 그러면 허용 error를 임의로 넓게 잡고 넘어가는 유혹에 빠집니다. 중간 칸이 있어야 판정이 **일치 / 불일치**라는 이진값이 되고, 이진값이어야 regression test가 자동화됩니다.

---

## 18.3 bit-exact가 성립하기 위한 조건

2단과 3단이 bit 단위로 같아야 한다는 기준은 강력하지만 저절로 성립하지는 않습니다. 두 implementation이 **같은 결정을 같은 자리에서** 내려야 성립합니다. 아래 가운데 하나라도 어긋나면 reference model과 RTL은 일치하지 않고 더 나쁜 것은 그 불일치가 "미세한 error"처럼 보여서 원인을 찾는 데 며칠이 든다는 점입니다.

| 고정해야 할 것 | 우리 규약 | 어긋나면 어떻게 보이나 |
|---|---|---|
| rounding 규칙 | round-half-to-even, 조건 $\text{guard} \wedge (\text{sticky} \vee \text{LSB})$ (유도는 [12.4절](12_fixed_point_and_precision.md#124-rounding--왜-half-to-even인가), circuit은 [13.5절](13_oracle_diffusion_measurement_datapath.md#135-diffusion-operator--2mean--amp가-circuit이-되는-순간)) | 대부분의 값은 맞고 정확히 절반인 경우에만 1 LSB 차 |
| rounding이 적용되는 **지점** | diffusion operator의 13-bit right shift **한 곳뿐** ([12.4절](12_fixed_point_and_precision.md#124-rounding--왜-half-to-even인가)) | subtraction 뒤에도 rounding을 넣으면 iteration마다 어긋남이 누적 |
| saturation 지점과 범위 | 되쓰기 직전, symmetric $\pm 4{,}194{,}303$ ([12.5절](12_fixed_point_and_precision.md#125-overflow-policy--saturationwraparound-금지renormalization-없음)) | saturation이 안 일어나는 조건에서는 완전히 일치하다가, solution amplitude가 1에 닿는 iteration에서만 갈라짐 |
| shift 위치와 방향 | $2\bar a$ 는 $\text{number of qubits} - 1 = 13$ bits arithmetic right shift ([13.5절](13_oracle_diffusion_measurement_datapath.md#135-diffusion-operator--2mean--amp가-circuit이-되는-순간)) | signed 값의 logical shift는 음수에서만 틀림 |
| accumulator 폭 | partial sum 28 bits · 전체 sum 39 bits, 자르지 않음 ([13.7절](13_oracle_diffusion_measurement_datapath.md#137-32-lane-datapath와-accumulation-순서)) | 중간에서 자르면 addition 순서가 결과를 바꿈 |
| measurement arithmetic과 순서 | square 46 · row weight 51 · total weight 60 bits, 자르지 않음, 엄격한 `>`, group → row → lane ([14.5절](14_multiple_solutions_and_minimum_search.md#145-2단-병렬-measurement)) | 같은 random number에서 이웃 칸이 뽑힘 |
| Iteration-Count LFSR | 32-bit LFSR, 후보마다 7 steps 전진, rejection sampling(버린 후보도 sampling 한 번), seed 0이면 대체 constant ([16.2절](16_iteration_control_and_checkpoints.md#162-bbht--무작위로-뽑는-number-of-iterations와-12-growth-factor)) | 첫 shot부터 number of iterations가 달라 아무것도 비교할 수 없음 |
| Measurement PRNG | xorshift64, 32-bit seed를 64 bits로 확장, rejection된 후보마다 64-bit block 하나, 하위 bit를 (total weight − 1)의 bit 길이만큼 ([14.4절](14_multiple_solutions_and_minimum_search.md#144-born-rule-sampling--probability를-circuit으로)) | 몇 shot은 우연히 맞다가 어긋나기 시작 — 가장 찾기 어려운 형태 |
| checkpoint policy의 동률 규칙 | 비용 → 전진하는 segment 개수 → 정해진 정렬 순서 ([16.5절](16_iteration_control_and_checkpoints.md#165-checkpoint--measurement가-읽기-전용이라는-사실에서)) | BBHT trajectory는 같은데 executed iterations만 다름 |

초판은 이 표의 random number 두 줄을 **미정**으로 남겨 두면서, "이 둘은 미룰 수 있는 미정이 아니다 — 정해지기 전까지 verification ladder의 위 두 칸을 아예 맞춰 볼 수 없다"고 적었습니다. 그 말 그대로였습니다. 두 규약이 못 박힌 뒤에야 reference model이 board와 BBHT trajectory를 500/500 맞추게 되었고, 마지막 줄의 동률 규칙까지 옮기고 나서 executed iterations까지 500/500이 되었습니다.

실무적으로는 규약을 **문서 한 장에 못 박고 두 implementation이 그 문서만 참조**하게 만듭니다. 더 나은 방법은 constant를 한 곳에서만 만드는 것입니다. 우리 저장소에서 algorithm constant(`INIT_AMP`, sampling range 경계 ROM 28 entries, requested iterations budget, 대체 seed)는 RTL의 `grover_param.vh` 에 있고, reference model은 같은 규칙에서 같은 값을 스스로 계산합니다 — 둘이 어긋나면 첫 workload에서 BBHT trajectory가 갈라지므로 금방 드러납니다. CSR offset은 사정이 다릅니다. 예전에는 source of truth file 하나에서 C·Verilog·Python header를 생성했지만, 지금은 [CSR 규격 문서](../design_references/13_csr_registers_and_execution_modes.md)와 reference model의 계약 module 두 곳을 손으로 맞춥니다. 같은 constant를 사람이 두 번 적으면 언젠가 반드시 어긋나므로, 한쪽을 고칠 때는 다른 쪽과 기계적으로 대조하십시오.

한 가지 언어별 함정을 덧붙입니다. Python의 `>>` 는 음수에 대해 $-\infty$ 방향으로 내림하는 arithmetic shift라서 Verilog의 `>>>` 와 같은 동작을 하지만, C의 right shift는 음수에서 implementation-defined이고 NumPy는 폭이 고정된 integer type에서 조용히 wraparound합니다. reference model을 Python 기본 integer로 쓰되 폭 제한은 **명시적인 mask와 saturation function으로 직접 implementation**하는 편이 안전합니다.

---

## 18.4 첫 test vector는 9.4절의 손계산

verification을 어디서부터 시작할지는 이미 정해져 있습니다. **9.4절에서 손으로 푼 4-state 예제**입니다.

uniform superposition $(\frac12, \frac12, \frac12, \frac12)$ 에서 출발해 oracle이 세 번째 칸의 sign을 뒤집으면 $(\frac12, \frac12, -\frac12, \frac12)$ 이 되고, mean $\bar a = \frac14$ 를 중심으로 반사하면 $(0, 0, 1, 0)$ 이 됩니다. iteration 한 번으로 probability 100%입니다. 이 예제를 Q1.22 규칙으로 따라가 보면 흥미로운 일이 생깁니다. $\texttt{INIT\_AMP} = 2^{22}/2 = 2{,}097{,}152$ 는 $0.5$ 의 정확한 표현이고, oracle 뒤 sum은 $2^{22}$, $2\bar a$ 는 $\text{number of qubits} - 1 = 1$ bit right shift라 $2^{21}$, 그리고 solution 칸은 $2^{21} - (-2^{21}) = 2^{22}$ — **정확히 1.0입니다.** 그런데 12.2절에서 봤듯 Q1.22는 $+1.0$ 을 담지 못합니다. 이 값은 symmetric saturation으로 $4{,}194{,}303$ 에 붙고, `amp_overflow` 가 섭니다. 가장 작은 손계산이 곧바로 **saturation 경로를 밟는 test**가 되는 셈입니다. 한 번 더 돌리면 sum이 $-4{,}194{,}303$ 이라 $2\bar a$ 가 $-2{,}097{,}151.5$ 로 **정확히 절반**에 걸립니다. 12.4절의 round-half-to-even 규칙이 여기서 처음 적용됩니다.

하나를 더 붙입니다. 8 states · solution $\{1,3,5\}$ · 3 solutions 예제입니다($\theta = 37.761°$, 최적 iteration 1번). Q1.22에서 $\texttt{INIT\_AMP} = \mathrm{round}(2^{22}/\sqrt8) = 1{,}482{,}910$ 이고, iteration 한 번이면 세 solution 칸이 **정확히 2,224,365**, 다섯 non-solution 칸이 **정확히 $-741{,}455$** 가 됩니다. real number로 환산하면 $0.530330$ 과 $-0.176777$ 이니 이론값 $0.53033$ / $-0.17678$ 과 맞습니다. 이 예제에서는 **두 번째 iteration**도 살펴볼 필요가 있습니다. 그 시점의 sum이 $-10{,}380{,}370$ 이라 $2\bar a = -10{,}380{,}370 / 4 = -2{,}595{,}092.5$ 로 **정확히 절반**에 걸립니다. round-half-to-even은 짝수 쪽인 $-2{,}595{,}092$ 를 고르고, arithmetic right shift를 그대로 쓰는 truncation은 $-2{,}595{,}093$ 을 고릅니다. 흔히 쓰는 단순한 implementation(truncation)과 우리 규칙이 갈리는 자리가 두 번째 iteration에서 자연히 나오는 것입니다. 18.3절 표의 첫 row를 검사하는 최소 test vector가 이렇게 손에 들어옵니다.

다만 이 두 예제는 **RTL에 그대로 걸 수 없습니다.** RTL은 14 qubits로 합성되어 state space가 늘 16,384 states이고, reference model의 hardware profile도 14 qubits(와 폐기된 16 qubits 확장)만 받습니다. 그래서 4-state · 8-state 예제는 몇 줄짜리 별도 script로 규칙을 확인하는 데 쓰고, RTL의 첫 vector는 **실제 크기에서 손으로 확인되는 경우**를 고릅니다.

그런 경우가 있습니다. 14 qubits · 1 solution · 1 iteration입니다. 초기 amplitude가 모두 $32{,}768$ 이고 solution 한 칸만 뒤집히므로 sum은 $16{,}382 \times 32{,}768 = 536{,}805{,}376$, 이것을 13 bits 밀면 $2\bar a = 65{,}528$ 로 **나누어떨어집니다.** 그러면 solution 칸은 $65{,}528 + 32{,}768 = 98{,}296$, 나머지는 $65{,}528 - 32{,}768 = 32{,}760$ 입니다. 이론값과 대조하면 $\sin 3\theta = 3/128 - 4/128^3$ 이라 $2^{22}$ 을 곱하면 $98{,}304 - 8 = 98{,}296$ — **rounding 없이 정확히 같습니다.** requested-j test vector의 방향성 case `dir_000001_eq_m1_j1` 이 바로 이것이고, 기대 amplitude file에 32,760이 16,383칸, 98,296이 한 칸 들어 있으며 iteration 추적에도 sum 536,805,376과 $2\bar a$ 65,528이 적혀 있습니다. waveform viewer에서 cycle을 짚어 가며 대조하기에 적합한 출발점입니다. 같은 묶음이 0 · 4 · 8 · 16 · 64 iterations와 최적점 100 iterations, 범위 끝 127 iterations로 한 걸음씩 넓혀 갑니다.

state가 적은 경우를 보고 싶을 때 RTL에서 할 수 있는 것은 **`DATA_COUNT` 를 작게** 두는 것입니다. state space는 16,384 states 그대로지만 그 뒤 칸은 전부 non-solution이 되므로, 한 칸짜리 data(`dir_000021_eq_data_count1_m1_j1`)나 row 경계를 걸치는 개수(31·32·33)로 padding 문과 lane 경계를 찔러 볼 수 있습니다. 이 기본 예제를 확인한 뒤에는 predicate 판정을 아예 빼고 solution index를 constant로 못 박은 최소 oracle을 잠깐 써도 좋습니다([13.3절](13_oracle_diffusion_measurement_datapath.md#133-oracle--predicate-4종이-subtractor-하나를-공유한다)) — 다만 그것은 verification용 예제이지 실제 설계가 아닙니다.

---

## 18.5 predicate 4종과 경계값

기본 예제를 확인한 뒤에는 실제 predicate circuit을 봅니다. 13.3절에서 네 predicate를 모두 **strict inequality**로 고정했으므로, 경계값 test는 그 약속이 circuit에 그대로 반영됐는지를 확인하는 일입니다.

가장 먼저 볼 것은 **threshold와 정확히 같은 값**입니다. `value == thr_a` 인 칸은 `LT` 에서도 `GT` 에서도 solution이 아니어야 하고, `EQ` 에서만 solution이어야 하며, range predicate `thr_a < value < thr_b` 에서는 양 끝 모두 제외돼야 합니다. 이 네 가지가 한 data array에서 동시에 확인되도록 threshold와 같은 값을 data에 **일부러 심어 둡니다.** inequality sign을 한 칸 잘못 짠 circuit은 다른 test를 전부 통과하고 이 test에서만 걸립니다.

다음은 data word의 **범위 양 끝**입니다. data word width가 16 bits(signed)이므로 값은 $[-32768,\ 32767]$ 입니다. `thr_a = -32768` 로 두면 `LT` 의 solution이 하나도 없고(0 solutions), `thr_a = 32767` 로 두면 `GT` 의 solution이 하나도 없습니다. 이때 확인할 것은 결과만이 아니라 **subtractor의 폭**입니다. 13.3절이 sign extension한 17-bit subtraction을 쓰는 이유가 정확히 이 극단에서 드러납니다 — 16 bits로 빼면 $32767 - (-32768)$ 이 넘쳐 MSB가 뒤집히고, predicate가 정반대 답을 냅니다. range predicate에서는 폭이 좁은 경우와 넓은 경우를 넣습니다. requested-j 묶음의 방향성 case(`gt_max_m0`, `lt_min_m0`, `range_narrow`, `range_wide`)가 이 자리입니다.

그다음은 number of solutions의 극단입니다. 네 가지를 각각 시나리오로 둡니다.

- **0 solutions — solution이 하나도 없다.** BBHT는 영원히 실패하므로 16.9절의 종료 규칙에 따라 멈춰야 합니다. 확인할 것은 shot cap이나 requested iterations budget에서 FSM이 **멈춰 있지 않고 종료하는가**, 그리고 해당 status bit가 서는가입니다.
- **1 solution.** 최적 iteration이 100회인 표준 경우입니다. number of iterations별 success probability 표(100 iterations에서 100%)를 1단 model이 재현하는지, 그리고 100 iterations · 127 iterations 방향성 case가 2단·3단에서 bit 단위로 같은지 봅니다.
- **$\text{number of solutions} > \text{number of states}/2$ — 역주행.** 14.8절의 함정 2입니다. solution을 절반 넘게, 혹은 전부 심으면(`eq_mhalf`, `eq_mall`) oracle이 사실상 $-I$ 에 가까워져 iteration이 measurement distribution을 거의 바꾸지 못합니다. 확인할 것은 "그래도 답이 나오는가"입니다 — 초반 shot은 iteration이 0 근처라 사실상 균등 무작위 추출이고, solution이 많으면 그것만으로 곧바로 맞아야 합니다.
- **enumeration에서 solution이 256개를 넘을 때 — FIFO가 찬다.** solution이 FIFO 깊이보다 많은 data를 넣고 firmware가 일부러 늦게 뽑아, hardware가 멈췄다가(`FIFO_STALL` 증가) 뽑는 대로 다시 진행하는지, 결과가 하나도 빠지거나 겹치지 않는지 확인합니다.

data distribution은 **세 종류**를 씁니다. 첫째, uniform random number — 기본 regression입니다. 둘째, 정렬된 data — solution이 index의 연속 interval에 몰립니다. 우리 indexing은 하위 5 bits가 lane이므로 연속 interval은 이웃한 row들의 lane에 골고루 퍼지고, 그 성질이 실제로 성립하는지 확인하는 것이 이 distribution의 목적입니다. 셋째, **solution이 한 row나 한 group 경계에 몰리는 인위적 data** — row weight의 prefix sum이 group 경계(32 rows마다)나 row 경계(lane 31/32)에서 넘어가는 자리입니다. Two-Level Select의 group·row 선택이 가장 까다로운 입력을 받는 경우이고, prefix sum의 off-by-one이 여기서 드러납니다(`eq_min_lane31`, `eq_max_lane32`, `d31`·`d32`·`d33` case). 중복 값이 많은 data를 넷째로 두면 `EQ` predicate에서 solution이 갑자기 많아지는 상황도 함께 볼 수 있습니다.

---

## 18.6 Born sampler를 어떻게 검증하나

measurement는 확률적입니다. 그런데 앞에서 합격 기준을 bit-exact로 잡았습니다. 모순처럼 보이지만 아닙니다 — **서로 다른 두 가지를 검사하는 것**이고, 둘을 섞으면 verification이 무너집니다.

**첫째, equivalence check.** seed를 고정하면 sampler는 완전히 결정적인 circuit입니다. 같은 amplitude array와 같은 seed를 reference model과 RTL에 넣으면 두 implementation은 **같은 후보 index sequence**를 내야 하고, 여기에는 허용 error가 없습니다. 이것은 distribution에 관한 시험이 아니라 두 implementation이 같은 function인지 보는 시험입니다. 18.3절의 random number 규약이 확정돼야 성립하는 것이 바로 이 검사이고, 지금은 500 workloads 전부에서 성립합니다.

**둘째, distribution test.** equivalence check는 두 implementation이 **똑같이 틀렸을** 가능성을 배제하지 못합니다. 그래서 distribution이 정말 $a_i^2 / \text{total weight}$ 인지는 따로 봐야 합니다. 방법은 statistical test입니다 — seed를 바꿔 가며 sample을 많이 뽑고, empirical distribution과 theoretical distribution의 chi-square goodness-of-fit test를 합니다.

이때 조심할 것이 둘 있습니다. 하나는 **cell 개수**입니다. 14 qubits면 index가 16,384개라 웬만한 sample 수로는 대부분의 cell의 expected frequency가 1 미만이 되어 chi-square 근사가 성립하지 않습니다. cell을 묶어야 합니다 — 16 groups 단위로 묶으면 degrees of freedom 15가 되고, solution/non-solution 두 group으로 묶으면 success rate test가 됩니다. 다른 하나는 **판정 방식**입니다. significance level 0.05로 test하면 정상인 circuit도 스무 번에 한 번은 기각됩니다. 한 번의 $p < 0.05$ 로 실패를 선언하면 regression test가 무작위로 실패를 보고하게 됩니다. test를 여러 번 되풀이해 $p$ 값들이 $[0,1]$ 에 균등하게 흩어지는지 보는 편이 훨씬 안정적입니다.

또 하나 — **test 대상을 좁혀야 합니다.** 여기서 보려는 것은 "sampler가 주어진 amplitude array에서 Born distribution을 내는가"이지 "Grover가 맞는가"가 아닙니다. 그래서 amplitude array를 Grover로 만들지 말고 **알려진 값으로 직접 채워 넣고** sampler만 떼어 시험하는 것이 깔끔합니다. 극단적인 array(한 칸만 0이 아닌 경우, 전부 같은 값인 경우, 두 칸만 크고 나머지가 아주 작은 경우)을 넣어 보면 경계 처리의 실수가 빨리 드러납니다.

**Two-Level Select가 distribution을 바꾸지 않는다는 것은 증명보다 강하게 확인할 수 있습니다.** 14.5절에 대수적 증명이 있지만, 증명이 보장하는 것은 **의도한 절차**이지 **implementation**이 아닙니다. 다행히 우리 sampler는 전부 integer로 자르지 않고 계산하므로, 같은 random number에 대해 "group → row → lane으로 좁혀 가며 찾은 index"와 "0번부터 차례로 prefix sum을 쌓아 처음 그 random number를 넘는 index"가 **정확히 같아야** 합니다. statistical test가 아니라 random number 하나하나에 대한 일치 검사가 가능하다는 뜻입니다. group prefix sum의 경계, row 안 잔여값 계산, 엄격한 `>` — 이 셋 중 하나만 어긋나도 경계 근처의 random number에서 이웃 칸이 나오고, 이 검사가 그것을 바로 잡습니다.

마지막으로 **드문 경로도 직접 시험해야 합니다.** rejection sampling은 후보가 total weight 이상일 때만 다시 뽑는데, 받아들여질 probability가 늘 절반을 넘으므로 여러 번 연달아 rejection되는 경로는 정상 simulation에서 거의 나오지 않습니다. total weight 0(`zero_weight_error`)은 정상 동작에서 아예 나오지 않습니다. 이런 경로는 random number나 amplitude를 강제로 주입해 **직접 밟아 봐야** 합니다. 실행된 적 없는 code가 정확할 probability는 낮습니다. 같은 방식으로 $\text{number of iterations} \sim U[0, \text{sampling range})$ 의 균등성도 histogram으로 확인합니다 — sampling range가 2의 거듭제곱이 아닐 때 rejection sampling이 제대로 동작하지 않으면 distribution이 기울고, 그 기울기가 BBHT의 "success probability $\ge 1/4$" 보장을 약화시킵니다.

---

## 18.7 checkpoint를 어떻게 검증하나

checkpoint는 이 project의 headline 기여이면서 동시에 **오류가 가장 드러나기 어려운** 부분입니다. 다행히 합격 기준이 아주 선명합니다.

**기본 검사는 전수 비교입니다.** 16.6절이 $(DO)^{x+y} = (DO)^{x}(DO)^{y}$ 라는 associativity로 두 경로가 같은 연산열임을 보였고, 우리 arithmetic이 결정적이므로 결과는 근사적으로 같은 정도가 아니라 **bit 단위로 동일**해야 합니다. 그래서 같은 request에 대해 (a) 새로 Init하고 요청된 횟수만큼 전진한 array와 (b) checkpoint slot에 저장된 state에서 이어 차이만큼 전진한 array를 만들어, **16,384칸 전부를** 비교합니다. requested-j vector가 (a)의 expected result를 이미 갖고 있으므로, checkpoint 경로의 최종 amplitude를 그 hash와 대조하면 됩니다. 몇 칸만 sample로 뽑거나 error를 허용하는 비교는 하면 안 됩니다. 같아야 하는 근거가 수학적 항등식이므로, 한 bit라도 다르면 그것은 error가 아니라 버그입니다.

**무효화 조건은 각각 하나씩 regression test를 세웁니다.** 16.7절이 무효화를 hardware에 맡긴 이유가 "software에 맡기면 반드시 새는 곳이 생긴다"였는데, hardware에 맡겨도 조건 하나를 빠뜨리면 같은 일이 벌어집니다. data load, predicate 종류, threshold A·B, data 개수, enumeration의 Found Mask — **하나하나에 대해** 바꾼 직후의 search가 Init부터 시작하는지 확인합니다. 반대 방향도 세웁니다. seed·shot cap·mode bit를 바꿨을 때는 checkpoint slot이 **유효하게 남아 있어야** 합니다. 비워도 결과는 맞지만 성능 이득이 사라져 결과만으로는 문제를 알아차리기 어렵습니다.

여기서 **가장 위험한 버그의 모양**을 알아 두는 것이 중요합니다. 무효화가 빠지면 circuit은 겉으로 완벽히 정상 동작합니다. 첫 search도 맞고, 두 번째 search도 맞고, threshold를 바꾸지 않는 한 계속 맞습니다. 그러다 threshold를 바꾼 순간부터 **이전 predicate로 증폭된 amplitude array 위에서** 새 predicate의 oracle이 돌기 시작하고, 겉으로 드러나지 않게 답이 틀립니다 — solution check가 non-solution은 걸러 주지만, shot count와 requested iterations가 Restart mode와 달라지는 형태로 드러납니다. 이런 고장은 무작위 regression으로는 잡히지 않습니다. "설정을 바꾼다 → checkpoint slot이 유효한 채로 남는다 → BBHT trajectory가 달라진다"는 시나리오를 **의도적으로 만들어** test에 넣어야 합니다.

**checkpoint on/off equivalence**는 checkpoint가 관측량을 바꾸지 않는다는 16.6절 주장의 실험적 확인입니다. 같은 seed·같은 data·같은 predicate에서 Restart mode와 Checkpoint mode가 **동일한 결과 index**, **동일한 shot count와 requested iterations**를 내야 하고, 오직 **executed iterations와 cycle만** 달라야 합니다. 이 비교는 이미 여러 층에서 돌았습니다 — 최상단 testbench가 Restart mode/Checkpoint mode 짝을 대조하고, 500 workloads RTL campaign과 board benchmark가 모두 BBHT trajectory 500/500 일치였습니다. 여기에 policy까지 옮긴 reference model이 board와 **executed iterations까지** 500/500 맞았습니다.

끝으로 policy의 드문 경로를 잊지 마십시오. request가 checkpoint slot의 iteration과 정확히 같아 비용이 0인 경우, request가 모든 checkpoint slot보다 작아 Init부터 가는 경우, 중간 state를 다른 checkpoint slot에 저장하는 경우입니다. BBHT에서 sampling range는 커지기만 하므로 뒤의 두 경우는 드물게 나옵니다. seed를 골라 강제로 만들거나 request 수열을 직접 주입해 경로를 밟아 보십시오. 그리고 policy가 미리 풀어 둔 계획과 실제 request가 어긋난 횟수(`PLAN_FIFO_MISMATCH_COUNT`)는 언제나 0이어야 합니다. 0이 아니면 앞으로 올 request를 예측하는 circuit이 실제 Iteration-Count LFSR 출력과 어긋났다는 직접 증거입니다.

---

## 18.8 잰 수치와 그 조건

초판의 이 절은 "다시 재야 하는 수치"의 목록이었습니다. 이제 그 수치들을 쟀고, 무엇을 어떤 조건에서 쟀는지 표로 정리합니다. 값의 source of truth는 [15.4절](15_paper_map_and_design_decisions.md#154-우리-project의-좌표--확정-설계-결정표)입니다.

| 수치 | 값 | benchmark 조건 | 상세 |
|---|---|---|:-:|
| fraction bits 충분성 | 모든 실행에서 amplitude·probability·success probability·norm error $< 10^{-3}$. 14 qubits는 22 fraction bits에서 probability $\ell_2 \le 10^{-5}$ | 같은 arithmetic(14 qubits · Q1.22)의 reference model 671,600회 campaign과 precision 분석 | [12.7](12_fixed_point_and_precision.md#127-몇-bit면-되나--minimum-fraction-bits-공식과-그-전제) |
| saturation | BBHT 1,000회당 2.67번, 기능 결과 불일치 0 | 같은 campaign | [12.3](12_fixed_point_and_precision.md#123-integer-bits는-몇-bit인가--재는-대상이-셋이다) |
| mean shot count | 22.7 (median 23) | 1 solution, 500 workloads RTL campaign 중 100개 | [16.3](16_iteration_control_and_checkpoints.md#163-shot-통계--mean이-20-shots를-넘는-이유) |
| executed iterations | 31,424 → 9,582 (−69.5%) | 500 workloads, Restart mode → a Checkpoint-Capacity of 3 and 3-shot Lookahead | [16.5](16_iteration_control_and_checkpoints.md#165-checkpoint--measurement가-읽기-전용이라는-사실에서) |
| RTL cycle | 42,308,335 → 6,890,470 (6.1401×) | 같은 500 workloads, Six-Stage Ablation | [15.5](15_paper_map_and_design_decisions.md#155-확정-platform과-resource-예산) |
| board wall-clock time | 425,502 µs → 55,798 µs (7.626×) | 같은 500 workloads, search 호출 interval만 | [15.5](15_paper_map_and_design_decisions.md#155-확정-platform과-resource-예산) |
| 같은 board 순수 software 대비 | 116,426× (wall-clock time) | 같은 chip·같은 workload·같은 seed, RISC-V core 하나. 32 lanes 병렬과 clock 두 배 때문이지 algorithm 우위가 아님 | [15.5](15_paper_map_and_design_decisions.md#155-확정-platform과-resource-예산) |
| resource · timing | LUT 45,284 · BRAM 116 · DSP 132, 100 MHz WNS +0.126 ns | 2026-09-07 implementation report (board 전체) | [15.5](15_paper_map_and_design_decisions.md#155-확정-platform과-resource-예산) |
| reference model ↔ board | BBHT trajectory 500/500, executed iterations 500/500 | Common500 비교 | [18.2](#182-3단-verification-ladder) |

아직 재지 않은 것도 적어 둡니다. software reference model은 cycle을 흉내 내지 않습니다 — policy가 결정을 내리는 latency, Plan Queue stall, 4 PEs와 Measurement Microarchitecture의 timing은 hardware의 몫이라, cycle은 언제나 RTL이나 board에서 인용합니다. iteration마다의 amplitude를 DRAM에 저장하는 두 번째 variant(DRAM Variant)는 동작 model 위의 RTL regression까지만 있고 board 수치가 없습니다.

**비교 실험의 공정성 기준**도 여기서 정합니다. 비교 대상은 **Qiskit AerSimulator와 NumPy state vector simulator**, 그리고 같은 board의 순수 software baseline입니다. classical linear scan과는 비교하지 않습니다 — emulation 비용이 $O(\text{number of states}\sqrt{\text{number of states}/\text{number of solutions}})$ 이라 $O(\text{number of states})$ scan보다 느린 것이 당연하고, algorithm의 $\sqrt{\text{number of states}}$ 이득은 실제 quantum computer의 이야기입니다. 이 비교로 보이려는 것은 속도 우위가 아니라, **같은 algorithm을 같은 순서로 돌렸을 때 전용 hardware가 어느 지점에서 이득을 내는가**입니다.

같게 두어야 할 것은 다음과 같습니다. number of qubits, data array(같은 seed로 생성한 같은 `value[]`), predicate와 threshold, random number seed, 그리고 **BBHT schedule 전체** — 같은 growth factor, 같은 sampling range 수열, 같은 Iteration-Count LFSR random number. shot마다 뽑히는 iteration이 다르면 전체 iteration이 달라지고, 그러면 무엇을 비교한 것인지 알 수 없게 됩니다. 성공 판정도 같은 기준(solution check 한 칸)으로 통일합니다. Common500 비교 실험이 정확히 이 조건으로, board와 같은 다섯 dataset과 seed 100쌍에 NumPy·Qiskit·fixed-point model을 걸었습니다.

재는 것은 둘로 나눕니다. **wall-clock time**은 무엇을 포함했는지를 반드시 밝힙니다. NumPy는 state vector 계산 core만, Qiskit은 Aer 실행만, board는 명령 발행부터 결과까지를 쟀습니다. 예를 들어 1 solution의 median이 NumPy 약 9 ms, Qiskit Aer 약 1.8 s, board의 final configuration 약 0.21 ms였는데, 경계가 서로 달라 이 비율은 참고값입니다. 성능 주장에 쓰는 것은 같은 경계 안의 비교 — board configuration끼리의 speedup — 입니다. 그리고 마지막으로 밝혀 둘 것 — Aer는 double-precision complex number로 amplitude 하나에 16 bytes를 쓰고 우리는 23-bit real number를 씁니다. **같은 수 표현으로 같은 문제를 푸는 것이 아닙니다.** 그러므로 정확도를 나란히 놓고 우열을 논하지 말고, "같은 algorithm·같은 shot sequence를 도는 데 걸리는 시간"만 비교하십시오.

---

## 18.9 toolchain과 directory

마지막으로 이 verification이 실제로 어디서 도는지를 정리합니다.

이 project 환경에는 필요한 도구가 **전부 local에** 있습니다 — RTL simulator `verilator`(cycle-accurate C++ model)와 `iverilog`, commercial simulator Questa, synthesis·implementation·bitstream을 내는 Vivado, RISC-V firmware를 빌드하는 GCC, 그리고 SoC 전체를 생성하는 RVX. 화면이 없는 환경이라 waveform viewer와 Vivado GUI는 띄울 수 없고, Vivado는 batch mode로만 씁니다. waveform 대신 testbench가 값을 file로 저장하고 script가 대조합니다.

작업 순서는 verification ladder를 따릅니다. 1단과 2단은 Python이라 어디서든 돌고, 3단 regression은 verilator로 몇 초에서 몇십 분이며, 그다음이 synthesis·timing closure·resource benchmark, 마지막이 board입니다. 순서를 뒤집으면 synthesis 한 번에 수십 분을 쓰면서 simulation으로 5분이면 잡을 버그를 찾게 됩니다. 두 simulator는 역할이 다릅니다. `verilator` 는 빨라서 250·500 workloads testbench 같은 긴 regression을 맡고, Six-Stage Ablation의 2,500회 campaign은 `iverilog` 로 돌았습니다. reference model이 Python이므로 simulator harness가 결과를 file로 저장해 대조하는 형태가 자연스럽습니다.

directory는 이렇게 나뉩니다.

| 경로 | 담는 것 |
|---|---|
| `hardware_bram/src/` | RTL — Bus Interface(CSR · DMA Engine)와 Accelerator Core |
| `hardware_bram/testbench/` | Verilog testbench와 C++ harness |
| `hardware_bram/sim/` | regression 진입점 `Makefile` 과 runner·보고 script |
| `hardware_bram/results/` · `hardware_bram/configurations/*/results/` | simulation campaign 결과 묶음 (configuration 사이 비교 · configuration별) |
| `software/reference_model_develop/models/` | 2단 reference model (Q1.22 bit-exact · checkpoint policy) |
| `software/pc_grover_develop/` | 1단 기준 (NumPy · Qiskit) 과 C++ implementation |
| `software/reference_model_data/` | 2단이 만든 test vector · expected result · 비교 결과 |
| `software/testbench_data/` | testbench · 실험이 읽는 입력 dataset |
| `software/reference_model_develop/` · `software/reference_model_data/` | Common500 비교 실험과 그 결과 |

reference model이 `hardware_bram/` 이 아니라 `software/` 에 있는 것이 의도적입니다. 같은 reference model을 BRAM Variant와 DRAM Variant가 **함께** 쓰기 때문입니다 — DRAM Variant는 같은 stimulus를 BRAM Variant에도 걸어 search의 BBHT trajectory가 같은지 대조하고, 그 기준이 되는 의미 규약은 두 variant 어디에도 속하지 않습니다. regression을 실제로 돌리는 명령과, 저장소 상황에 따라 먼저 되살려야 할 file은 [toolchain 사용법](../design_references/02_development_environment_and_toolchain.md)에 있습니다.

---

## 18.10 이 장의 요약

- **verification이 설계의 일부인 이유 셋**: 1차 자료가 틀리고([15.6절](15_paper_map_and_design_decisions.md#156-인용-시-주의--논문의-오류와-모호점)), 이론이 답을 못 주는 자리가 있으며(fraction bits 충분성, 12.7절), 이 IP의 값어치 자체가 재현 가능성이라 verification 절차가 곧 제품 사양입니다.
- **3단 verification ladder + board**: float64·Qiskit(**algorithm**이 맞나) → Q1.22 bit-exact reference model(**수 표현**이 맞나) → RTL(**circuit**가 맞나) → board. 각 칸이 잡는 버그의 종류가 다르고, 한 칸을 건너뛰면 rounding 버그와 FSM 버그가 섞여 판정 기준을 세울 수 없습니다. **reference model은 2단**이고, BBHT trajectory가 같아야 하는 것은 같은 칸끼리입니다(1단의 float BBHT trajectory는 2단과 다를 수 있습니다).
- **bit-exact 성립 조건**: rounding 규칙 · rounding 지점 · saturation 지점과 범위 · shift · accumulator 폭 · measurement arithmetic과 순서 · **Iteration-Count LFSR 규약** · **Measurement PRNG 규약** · policy의 동률 규칙. 초판이 미정으로 남긴 random number 두 줄이 정해진 뒤 reference model과 board가 BBHT trajectory 500/500, 동률 규칙까지 옮긴 뒤 executed iterations 500/500이 되었습니다. algorithm constant는 RTL header 한 곳에, CSR offset은 손으로 맞추는 두 곳에 있습니다.
- **첫 test vector는 9.4절 손계산**: 4-state 예제는 Q1.22에서 solution amplitude가 정확히 1.0이 되어 **saturation 경로**를 밟고, 두 번째 iteration에서 절반에 걸립니다. 8 states·3 solutions 예제는 두 번째 iteration의 $2\bar a = -2{,}595{,}092.5$ 에서 round-half-to-even과 truncation이 갈립니다. RTL의 첫 vector는 실제 크기에서 손으로 확인되는 **14 qubits·1 solution·1 iteration** — solution 98,296, 나머지 32,760이 이론값과 rounding 없이 같습니다.
- **predicate 경계값**: threshold와 같은 값(strict inequality 확인) · 16-bit signed data word 범위 양 끝(17-bit subtractor의 존재 이유) · 좁고 넓은 범위 · 0 solutions · 1 solution · solution이 state의 절반을 넘는 역주행 · FIFO가 차는 enumeration. data distribution은 uniform random number · 정렬 · **solution을 row·group 경계에 몰아넣은 인위적 array**.
- **Born sampler는 두 시험이 다릅니다**: seed를 고정하면 결정적이라 **bit-exact equivalence check**가 되고, distribution 자체는 **chi-square test**로 따로 봅니다(cell은 group 단위로 묶고, 한 번의 $p<0.05$ 로 실패를 선언하지 않습니다). Two-Level Select는 integer 정확 계산이라 순차 prefix sum 선택과 **random number 하나하나에서 같아야** 하고, 연속된 rejection과 total weight 0 같은 드문 경로는 강제 주입으로 직접 시험합니다.
- **checkpoint verification의 합격 기준은 전수 비교**: 이어 간 경로와 새 Init 경로의 amplitude 16,384칸이 **bit 단위로 전부 일치**해야 합니다. 무효화 조건 각각과 무효화하지 않아야 할 조건 각각에 regression을 두고, on/off가 같은 seed에서 **같은 결과·같은 shot count·같은 requested iterations**를 내고 **executed iterations와 cycle만** 다른지 확인합니다 — board와 RTL에서 500/500이었고, Plan Queue miss counter는 늘 0이어야 합니다.
- **잰 수치**: fraction bits 충분성(error $< 10^{-3}$) · saturation(1,000회당 2.67) · mean 22.7 shots · executed iterations −69.5% · RTL 6.1401× · board 7.626× · resource와 timing. 비교 대상은 Qiskit Aer / NumPy / 같은 board의 순수 software며 **classical scan과는 비교하지 않습니다.** 같게 둘 것은 number of qubits·data·predicate·seed·BBHT schedule 전체, wall-clock time은 benchmark 경계를 반드시 밝힙니다.
- **toolchain**: simulator·synthesis·firmware·SoC 생성이 전부 local이고, 작업 순서는 verification ladder를 따릅니다. reference model은 두 variant가 함께 쓰므로 `software/` 에 있습니다.

이것으로 해설서를 마칩니다. index 에서 "왜 quantum computer인가"로 시작해 9장에서 Grover를 손으로 돌려 보았고, 11장부터 그 algorithm을 memory와 arithmetic과 제어와 bus로 구현했으며 이 장에서 그 구현이 맞는지 어떤 절차로 확인했는지 살펴보았습니다. board 위에서 도는 이 circuit은, 여러분이 1장에서 처음 본 amplitude라는 숫자가 끝까지 정해진 규칙에 따라 계산된 결과입니다.

---

> [← 17장 RVX SoC에 붙이기](17_rvx_soc_integration.md) · [index](index.md)

<!-- HUMANIZE-SUMMARY -->
<!--
{
  "원본_글자수": 29241,
  "최종_글자수": 29285,
  "경로": "heavy",
  "게이트_변경률": 0.0085,
  "등급": "B",
  "자체검증": "6/6 (보존 지시 대상의 교재 형식 제외)",
  "상태": "corrected",
  "국소_보정_수": 1,
  "카테고리": [
    "A-15",
    "A-7",
    "D-14",
    "D-2",
    "D-8"
  ],
  "하이라이트": [
    {
      "rule": "A-15",
      "before": "그 설계가 맞다는 것을 **어떻게 보였는가**를 정리합니다.",
      "after": "그 설계가 맞다는 것을 **어떤 절차로 확인했는가**를 정리합니다."
    },
    {
      "rule": "A-7",
      "before": "여섯 편의 1차 자료가 하나도 빠짐없이 인용 사고를 낼 오류를 갖고 있음을 보이면서,",
      "after": "여섯 편의 1차 자료 모두에 인용할 때 주의해야 할 오류가 있음을 보이면서"
    }
  ],
  "잔존_finding": []
}
-->
