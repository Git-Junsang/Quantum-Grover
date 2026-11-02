# 16장. 몇 번 돌릴지 모를 때 — BBHT shot loop와 checkpoint

> [← 15장 논문 지도와 설계 결정표](15_paper_map_and_design_decisions.md) · [index](index.md) · [17장 RVX SoC에 붙이기 — APB CSR · AHB DMA · UART →](17_rvx_soc_integration.md)
> **이 장을 읽기 위한 준비**: [4장 measurement](04_measurement.md), [6.6절 circuit의 순효과는 하나의 unitary](06_quantum_circuit_model_and_universality.md#66-circuit의-순효과는-하나의-unitary), [9.6절 지나치면 안 된다](09_grover_algorithm.md#96-지나치면-안-된다), [13장 oracle과 diffusion operator](13_oracle_diffusion_measurement_datapath.md)의 안쪽 FSM(13.1절), [14장 multiple solutions](14_multiple_solutions_and_minimum_search.md).

---

13장은 한 번의 initialization에서 시작해 iteration을 몇 바퀴 돌고 measurement로 끝나는 **한 shot** 안을 들여다봤고, 14장은 그 shot의 마지막 단계인 measurement를 확률적으로 만들었습니다. 그런데 13장은 내내 "number of iterations는 정해져 있다"고 가정했습니다. 이 장은 그 가정을 풉니다.

optimal number of iterations를 계산하려면 number of solutions가 필요한데, 우리 accelerator는 solution이 몇 개인지 모릅니다. 모르면 shot 하나로 끝나지 않고 **여러 번 실행해야** 하고 그러면 곧바로 다음 질문이 따라옵니다 — 실패한 shot이 남긴 amplitude array를 그냥 버릴 것인가? 이 장의 후반부는 그 array를 버리지 않고 몇 벌 남겨 두었다가 이어 돌리는 **checkpoint**를 다룹니다. 이 점이 이 project와 기존 Grover emulator들의 차이이며 board에서 잰 가속의 가장 큰 몫이 여기서 나옵니다.

---

## 16.1 왜 solution이 몇 개인지 모르는가

우리 accelerator가 푸는 문제는 "`data_mem` 에 담긴 16,384개 값 중 predicate를 만족하는 index를 찾아라"입니다. predicate는 `value < thr_a` 같은 부등식이고, threshold는 host가 CSR로 넘겨줍니다. 그러면 number of solutions는 무엇에 달려 있을까요 — **predicate의 종류, threshold, 그리고 그 순간 memory에 실려 있는 data**입니다. 셋 다 실행 시점에 정해지므로, synthesis 시점에는 물론이고 시작 명령을 쓰는 순간에도 solution이 몇 개인지 알 수 없습니다.

number of solutions를 모르면 optimal number of iterations를 계산할 수 없습니다:

$$\text{optimal number of iterations} = \frac{\pi}{4}\sqrt{\frac{\text{number of states}}{\text{number of solutions}}} - \frac12$$

number of solutions가 분모 안에 있으니까요(14 qubits · 1 solution이면 optimal number of iterations는 $100.03 \to 100$; 값의 source of truth는 [15.4절](15_paper_map_and_design_decisions.md#154-우리-project의-좌표--확정-설계-결정표)). 그렇다고 "모르니까 넉넉히 많이 돌리자"가 통하지도 않습니다. 9.6절에서 확인했듯 Grover는 최적점을 지나치면 success probability가 **다시 떨어지고 진동**하기 때문입니다. 많이 돌리는 것이 안전한 쪽이 아니라는 점이 이 문제를 어렵게 만듭니다.

quantum algorithm에는 이 문제를 다루는 표준 방법이 있습니다. **quantum counting** — Grover iteration의 eigenvalue에 담긴 각 $\theta$ 를 phase estimation(QPE)으로 읽어 내 solution이 몇 개인지 추정하는 방법입니다. 우리는 이것을 설계에서 제외했습니다. 이유는 성능이 아니라 **수 표현**입니다. QPE는 inverse quantum Fourier transform을 쓰고, QFT는 $e^{2\pi i k/2^{t}}$ 형태의 complex phase를 곱합니다. 9.8절이 정리한 "표준 Grover는 amplitude가 실수를 벗어나지 않는다"는 성질이 여기서 깨지고, 그러면 imaginary part array가 하나 더 생겨 amplitude memory가 두 배가 되며, 12장에서 세운 실수 전용 23-bit Q1.22 datapath와 13장의 multiplier 없는 산술을 그대로 쓸 수 없게 됩니다. counting을 위해 accelerator 전체를 complex number로 바꾸는 것은 비용에 비해 이득이 작습니다.

여기서 구분해 둘 점이 있습니다. **emulator에서는 solution을 그냥 세면 됩니다.** `data_mem` 을 한 번 훑으면 128 cycles이고, 이는 shot 하나에 드는 시간보다도 짧습니다. 순수 속도만 놓고 보면 세어 놓고 optimal number of iterations를 딱 계산해 도는 쪽이 BBHT보다 빠릅니다. 그럼에도 BBHT를 택하는 이유는 속도가 아니라 **실기 충실도**입니다. 진짜 quantum computer는 amplitude array를 들여다볼 수 없고, oracle을 호출해 보는 것 말고는 solution이 몇 개인지 알 방법이 없습니다. solution을 미리 세어 놓고 시작하는 것은 amplitude array를 직접 읽는 것과 마찬가지로 실제 장치에서 얻을 수 없는 정보를 쓰는 일입니다. 그렇게 만든 기계는 Grover의 외형만 따를 뿐 Grover의 동작을 충실히 재현하지 못합니다. 이 accelerator의 값어치는 고전 code보다 빠른 데 있지 않고 **quantum algorithm의 동작을 결정적이고 재현 가능하게 재현·검증하는 전용 hardware**라는 데 있으므로, 속도보다 충실도를 우선합니다.

다만 number of iterations를 바깥에서 정해 주는 **Manual mode**는 남겨 둡니다(`MANUAL_SINGLE`). firmware가 number of iterations를 직접 적어 한 shot만 돌리는 mode라, solution이 몇 개인지 아는 조건에서 optimal number of iterations로 딱 맞게 도는 비교 실험과 software reference model과의 한 shot 단위 대조에 씁니다.

---

## 16.2 BBHT — 무작위로 뽑는 number of iterations와 1.2× growth factor

solution이 몇 개인지 모를 때 쓰는 표준 절차가 BBHT(Boyer–Brassard–Høyer–Tapp)입니다. 네 줄이면 끝납니다.

1. sampling range를 1로 두고 시작한다.
2. shot마다 number of iterations를 $[0,\ \text{sampling range})$ 에서 **무작위로** 뽑는다.
3. 뽑은 횟수만큼 iteration을 돌고 측정한 뒤, 나온 후보로 solution check를 한다.
4. 실패하면 $\text{sampling range} \leftarrow \min(\text{growth factor}\cdot\text{sampling range},\ \sqrt{\text{number of states}})$ 로 sampling range를 넓히고 2로 돌아간다. growth factor는 6/5다.

학부생이 가장 먼저 걸리는 지점은 2번입니다 — **왜 number of iterations를 무작위로 뽑는가?** 그냥 sampling range − 1 처럼 가장 큰 값을 쓰거나, 매번 1씩 늘리면 안 되나요?

success probability의 모양을 보면 이유를 알 수 있습니다. iteration을 돈 뒤 solution이 나올 probability는

$$\text{success probability} = \sin^2\!\big((2\cdot\text{number of iterations}+1)\,\theta\big), \qquad \sin\theta = \sqrt{\text{number of solutions}/\text{number of states}}$$

로, number of iterations에 대해 **진동**합니다. 14 qubits · 1 solution이면 $\theta = 0.4476°$ 이고 optimal number of iterations는 100인데, number of iterations를 바꿔 가며 재 보면 이렇습니다:

| number of iterations | 0 | 1 | 10 | 25 | 50 | 75 | 100 | 125 | 127 | 150 | 175 | 200 |
|:--|--:|--:|--:|--:|--:|--:|--:|--:|--:|--:|--:|--:|
| success probability | 0.0% | 0.1% | 2.7% | 15.1% | 50.4% | 85.5% | 100.0% | 85.5% | 83.3% | 50.5% | 15.1% | 0.0% |

100 iterations 근처는 100%지만 200 iterations는 **0%** 입니다. 최적점을 두 배쯤 지나치면 probability가 거의 0인 골짜기로 떨어진다는 뜻이죠. 만약 number of iterations를 고정한다면, 하필 그 값이 골짜기에 놓였을 때 그 shot은 몇 번을 반복해도 실패합니다. sampling range 안에서 무작위로 뽑으면 한 shot의 success probability가 골짜기 하나에 걸리지 않고 그 interval의 **mean**이 되고, BBHT의 핵심 lemma는 sampling range가 충분히 커진 뒤 이 mean이 $1/4$ 아래로 내려가지 않음을 보장합니다. number of iterations를 무작위로 뽑는 것은 편의가 아니라 algorithm의 정당성을 보장하는 요소입니다.

4번의 growth factor 6/5도 임의의 숫자가 아닙니다. growth factor가 1보다 크고 $4/3$ 보다 작으면 총 비용의 상한이 보장된다는 것이 BBHT의 결과이고, $6/5$ 는 그 interval 안의 관습적 선택입니다. sampling range를 너무 천천히 넓히면 shot을 더 많이 실행해야 하고 너무 빨리 넓히면 최적점을 건너뛴 큰 number of iterations만 뽑히기 때문에 양쪽 다 손해입니다. 상한 $\sqrt{\text{number of states}}$ 는 solution이 하나일 때 optimal number of iterations가 대략 $\frac{\pi}{4}\sqrt{\text{number of states}}$ 라는 데서 옵니다 — 그보다 넓은 sampling range는 골짜기만 더 많이 담을 뿐입니다. 우리 14 qubits에서는 $\sqrt{\text{number of states}} = 128$ 이 **정확히** integer라, number of iterations는 7-bit $[0, 128)$ 안에서만 뽑힙니다. 위 표의 200 iterations 골짜기는 hardware가 아예 요청하지 못하는 자리이고, sampling range의 끝인 127 iterations에서도 success probability가 83%를 넘습니다. 이렇게 상한이 overshoot를 막습니다.

hardware에서 1.2×를 매번 곱하지는 않습니다. sampling range의 수열을 미리 계산해 **28항 ROM**에 저장해 둡니다 — $\lceil 1.2^k \rceil$ 을 128에서 자른 값으로, $1, 2, 2, 2, 3, 3, 3, 4, 5, 6, 7, 8, 9, 11, 13, 16, 19, 23, 27, 32, 39, 47, 56, 67, 80, 96, 115, 128$ 이고 그 뒤로는 계속 128입니다. number of iterations는 이 경계 안에서 **정확히 균등하게** 뽑습니다. 32-bit Iteration-Count LFSR의 하위 bit를 경계 이상의 가장 작은 2의 거듭제곱 폭으로 잘라 후보로 쓰고, 후보가 경계 이상이면 버리고 다시 뽑는 rejection sampling입니다. 후보를 하나 뽑을 때마다 LFSR을 7 steps씩 전진시켜, 이어 뽑는 후보들이 같은 bit 창을 겹쳐 쓰지 않게 합니다.

---

## 16.3 shot 통계 — mean이 20 shots를 넘는 이유

"한 shot success probability가 $1/4$ 이상이니 mean 네 번쯤 던지면 되겠네"는 이 장에서 가장 흔한 오해입니다. 실제 수치는 이렇습니다. board benchmark와 같은 500 workloads(1 · 4 · 16 · 64 · 256 solutions마다 100 seeds)를 RTL simulation으로 돌린 Six-Stage Ablation campaign의 mean입니다(값의 source of truth는 [15.4절](15_paper_map_and_design_decisions.md#154-우리-project의-좌표--확정-설계-결정표)).

| number of solutions | mean shots | requested iterations | executed iterations (Restart mode) | executed iterations (a Checkpoint-Capacity of 3 and 3-shot Lookahead) | 줄어든 몫 | mean cycles (Stage 1 → final configuration) |
|:-:|--:|--:|--:|--:|--:|--:|
| 1 | **22.7** | 173.5 | 173.5 | 51.9 | 70% | 209,277 → 25,345 |
| 4 | 18.5 | 78.9 | 78.9 | 23.9 | 70% | 106,128 → 16,368 |
| 16 | 15.1 | 40.0 | 40.0 | 12.1 | 70% | 61,458 → 11,993 |
| 64 | 10.6 | 15.9 | 15.9 | 5.5 | 65% | 30,498 → 8,590 |
| 256 | 7.2 | 6.0 | 6.0 | 2.5 | 59% | 15,723 → 6,610 |

여기서 executed iterations는 datapath가 실제로 돈 Grover iteration의 개수입니다. 매 shot 처음부터 도는 Restart mode에서는 requested iterations와 같고, checkpoint를 쓰면 줄어듭니다(16.5절). number of shots와 requested iterations는 두 mode에서 같습니다 — 같은 seed면 같은 number of iterations 수열을 요청하기 때문입니다(16.6절).

mean이 22.7 shots까지 올라가는 이유는 sampling range의 성장 곡선에 있습니다. sampling range는 1에서 출발해 1.2×씩 커지므로 처음 열 shot쯤은 아주 좁습니다 — 16.2절의 ROM 수열 그대로 $1, 2, 2, 2, 3, 3, 3, 4, 5, 6, \dots$ 입니다. 그 동안 number of iterations는 0에서 5 사이에서만 뽑히는데, 위 표에서 10 iterations일 때조차 success probability가 2.7%였습니다. 즉 **초반 shot은 거의 전부 실패하도록 설계되어 있습니다.** 실제로 답을 얻기 쉬워지는 것은 number of iterations가 75~100 근처(success probability 85~100%)에 닿을 만큼 sampling range가 커진 뒤이고, ROM 수열에서 그 자리가 스물다섯 번째 항 안팎입니다. 관측된 mean 22.7 shots(median 23)이 정확히 그 지점입니다.

BBHT의 "$1/4$ 이상" 보장은 **sampling range가 충분히 커진 뒤의 lower bound**이지 첫 shot부터 성립하는 값이 아니라는 것 — 이 구분이 4~5 shots와 22.7 shots를 가릅니다.

이 사실이 곧바로 **measurement를 싸게 만들어야 하는 동기**가 됩니다. shot이 22.7번이면 measurement도 22.7번이니까요. 1 solution에서 final configuration의 mean 25,345 cycles을 11.8절의 직선으로 쪼개 보면, executed iterations가 $51.9 \times 268 \approx 13{,}900$ cycles, shot마다의 measurement·verification이 $22.7 \times 354 \approx 8{,}000$ cycles, 나머지 고정비가 3,400 cycles 남짓입니다. checkpoint가 iteration을 70% 줄이고 나니 measurement가 전체의 3분의 1을 차지하게 된 것이고, 그래서 Measurement Unit을 줄인 Dual-Row Build와 Two-Level Select가 총 cycle을 각각 18% 넘게 더 줄였습니다(14.5절). **checkpoint와 measurement 최적화는 따로 고를 수 있는 option이 아니라 한 쌍입니다** — 한쪽을 줄이면 다른 쪽이 병목으로 드러납니다.

shot이 끝없이 이어지지 않도록 보호 한도가 둘 있습니다. number of shots가 shot cap(`SHOT_CAP`, 기본 100)에 닿거나, 실패한 shot 뒤에 $1 + \text{requested iterations}$ 가 **BBHT budget 576**에 닿으면 search를 끝내고 각각 `shot_limit` · `budget_limit` status bit를 세웁니다. solution이 하나도 없는 search는 이 둘 중 하나로 끝납니다.

---

## 16.4 바깥 FSM — shot loop와 solution check

지금까지의 이야기를 circuit으로 옮기면 13장의 FSM 위에 **바깥 loop**가 한 겹 얹힌 2 layer 구조가 됩니다. 아래 그림은 sampling range 갱신과 number of iterations sampling까지 FSM 안에 들어간 **BBHT autonomous mode 기준**입니다.

<img src="diagrams/16_shot_loop.svg" width="760" alt="BBHT autonomous mode의 2-layer FSM: 바깥 shot loop에서 sampling range ROM과 LFSR rejection sampling으로 number of iterations를 추첨하고, checkpoint policy가 출발 checkpoint slot과 남길 checkpoint slot을 정한 뒤 안쪽 Grover iteration을 차이만큼 돌고, measurement·solution check 후 실패하면 다음 ROM 항으로, 성공하면 끝내거나 enumeration round로">

그림에 보이듯 BBHT autonomous mode의 바깥 shot loop가 하는 일은 넷입니다. **ROM에서 sampling range 경계를 꺼내고**, **LFSR rejection sampling으로 number of iterations를 추첨하고**, **checkpoint policy에 물어 어느 checkpoint slot에서 출발해 어디까지 갈지 정하고**, 안쪽 iteration이 끝나면 **measurement 후보를 받아 solution check**를 합니다. 안쪽 loop는 13장에서 만든 것 그대로 — `S_PASS1`(predicate 판정·sign 반전·accumulation) → `S_MEAN` → `S_PASS2`(diffusion operator) 를 필요한 만큼 — 이고, 여기에는 손댈 것이 없습니다. oracle이 독립된 state로 보이지 않는 것은 [13.1절](13_oracle_diffusion_measurement_datapath.md#131-한-iteration-안의-fsm)이 oracle을 Pass 1에 흡수했기 때문입니다.

새로 등장하는 단계는 **solution check**입니다. measurement가 내놓은 후보 index `cand` 하나로 `data_mem[cand]` 를 읽어 predicate를 다시 판정하는(padding과 enumeration mask까지 포함해) 짧은 고전 확인입니다. 왜 필요한가 — Born-rule sampling은 확률적이고 success probability가 100%가 아니므로 **non-solution을 내놓을 수 있기** 때문입니다. 이 한 칸 확인이 있으면 accelerator의 출력이 "틀릴 수도 있는 확률적 답"에서 "맞다고 확인된 답, 또는 아직 못 찾음"으로 바뀝니다. 이것이 BBHT 4번의 "실패하면"을 circuit이 판정하는 방식이기도 합니다.

가장 바깥에는 **enumeration round loop**가 있습니다. solution check를 통과한 후보가 나왔을 때 enumeration mode라면 답 하나를 Result FIFO에 넣고 끝내는 대신, 그 index의 `found` bit를 세우고 BBHT를 ROM 첫 항부터 다시 시작합니다([14.7절](14_multiple_solutions_and_minimum_search.md#147-enumeration-mode--mask로-중복-없이)). mask가 바뀌면 문제가 바뀐 것이므로 checkpoint도 무효가 됩니다(16.7절). 이때 Iteration-Count LFSR의 random number stream은 다시 seed를 읽지 않고 **이어서** 흐릅니다 — 같은 number of iterations 수열을 되풀이하지 않게 하려는 것입니다. seed는 host가 시작 명령을 쓸 때만 다시 읽힙니다.

hardware 비용은 크지 않습니다. 바깥 Shot Controller와 Iteration-Count LFSR을 합쳐도 implementation report에서 LUT 359개입니다. 비싼 것은 shot loop가 아니라 16.5절의 policy circuit입니다.

shot loop를 hardware가 돈다고 해서 firmware가 shot을 직접 모는 길이 없어진 것은 아닙니다. 16.1절의 Manual mode에서는 firmware가 number of iterations를 CSR에 적고 시작 명령을 쓸 때마다 **한 shot**만 돕니다. 이 mode에서는 checkpoint가 걸리지 않습니다(checkpoint는 autonomous mode와 checkpoint bit가 둘 다 켜졌을 때만 동작합니다). autonomous mode에서 firmware가 보는 것은 설정 · 시작 · polling · 결과 읽기 네 줄뿐이고, shot 사이의 state는 전부 hardware가 관리합니다.

---

## 16.5 checkpoint — measurement가 읽기 전용이라는 사실에서

22.7번의 shot 가운데 스물몇 번은 실패인데, 실패한 shot은 무엇을 남길까요?

관찰 하나에서 출발합니다. **amplitude memory에 쓰는 주체는 셋뿐입니다** — Init, oracle, diffusion operator. 14장에서 만든 Born-rule sampling은 amplitude를 읽어 square의 prefix sum을 만들고 그 prefix sum이 random number를 넘는 지점을 찾을 뿐, amplitude에 **아무 값도 쓰지 않습니다.** 뒤이은 solution check도 `data_mem` 의 한 칸을 읽을 뿐입니다. 그러므로 shot이 실패해 바깥 loop로 돌아온 시점에도 amplitude memory에는 **그 shot이 요청한 만큼 iteration을 돈 state가 고스란히 남아 있습니다.**

그리고 BBHT의 number of iterations는 sampling range 안에서 뽑히는데 sampling range는 단조 증가합니다. 다음 shot이 요청하는 number of iterations가 이미 계산해 둔 state의 number of iterations보다 큰 경우가 흔하다는 뜻이고, 그럴 때는 처음부터 다시 돌 이유가 없습니다. 이 project의 초판 설계는 이 관찰을 **state 한 벌**로 옮겼습니다 — 직전 shot의 state를 지우지 않고, 다음 request가 그보다 크면 차이만큼만 더 돌리는 1칸짜리 **checkpoint**였습니다. 최종 설계는 이것을 **여러 벌**로 넓혔습니다.

**checkpoint slot 세 벌.** amplitude state를 최대 세 벌(a Checkpoint-Capacity of 3) 저장하고 각 checkpoint slot에는 "이 state는 iteration을 몇 번 돈 것인가"라는 number of iterations가 붙어 있습니다. 새 request가 오면, checkpoint slot 가운데 number of iterations가 request 이하이면서 가장 큰 것(가장 가까운 앞선 state)에서 출발합니다. 이번 request의 물리 비용은

$$\text{cost} = \text{number of iterations}_{\text{request}} - \text{number of iterations}_{\text{checkpoint slot}}$$

이고(출발할 checkpoint slot이 없으면 Init 뒤 request의 number of iterations 전부), request와 같은 number of iterations의 checkpoint slot이 이미 있으면 비용은 0 — 계산 없이 그 state를 다시 측정합니다. 전진하는 도중의 중간 state를 다른 checkpoint slot에 저장하는 데도 추가 비용이 거의 들지 않습니다. 그 state는 어차피 datapath를 지나가므로, 한 iteration만 다른 checkpoint slot으로 건너 쓰면(bridge) 됩니다. 계산은 checkpoint slot 안에서 제자리로 이어 가므로, chip 안에는 checkpoint slot과 따로 떨어진 작업용 amplitude memory가 없습니다.

<img src="diagrams/16_cache_timeline.svg" width="760" alt="같은 shot 수열에서 매번 Init부터 도는 Restart mode와 a Checkpoint-Capacity of 3을 쓰는 경우의 시간 비교: checkpoint는 남겨 둔 state 중 가장 가까운 것에서 차이만큼만 전진">

**무엇을 남길 것인가 — policy.** checkpoint slot이 셋뿐이니, 이번 전진이 끝났을 때 어느 state들을 남겨 둘지 골라야 합니다. 여기서 emulator만의 사정이 하나 드러납니다. number of iterations를 뽑는 random number는 seed에서 시작하는 **결정적인** Iteration-Count LFSR이 내고, sampling range 경계도 ROM에 적혀 있습니다. 그러니 "이번 shot이 실패한다면" 다음에 올 request들은 **미리 계산할 수 있습니다.** hardware는 실제 LFSR state를 바꾸지 않고 사본을 전진시켜 앞으로 올 request를 미리 뽑아 보는 circuit(Iteration-Count Predictor)을 둡니다. shot이 성공하면 search가 끝나거나(단일) 문제가 바뀌므로(enumeration) 그 예측은 버리면 되고, 실패하면 예측이 정확히 맞습니다.

policy는 **지금 request 하나와 앞으로 올 3 requests**(3-shot Lookahead)를 한꺼번에 놓고, 어느 number of iterations의 state를 checkpoint slot에 남기면 이 request들 전체의 물리 비용 sum이 가장 작아지는지를 푸는 작은 DP입니다. 남길 후보는 이 request들의 값으로 제한하고, 지금 request의 state는 측정해야 하니 반드시 남깁니다. 비용이 같으면 전진하는 segment가 적은 쪽, 그다음 정해진 정렬 순서로 동률을 처리해 **언제나 같은 답**을 냅니다. 풀이 중간값은 BRAM 4개짜리 memo table에 적어 되풀이 계산을 줄입니다. 그리고 지금 shot이 도는 동안 다음 shot의 계획을 미리 풀어 작은 Plan Queue에 넣어 두어, shot 사이에 policy를 기다리는 시간을 숨깁니다. 미리 푼 계획이 실제 request와 어긋난 횟수(Plan Queue miss)는 `PLAN_FIFO_MISMATCH_COUNT` 로 남고, **0이어야 정상**입니다.

policy가 search 결과를 바꾸는 일은 없습니다. policy가 정하는 것은 "어느 state에서 출발해 무엇을 남기느냐" — 즉 요청된 state를 **어떻게 만드느냐**뿐이고, 어떤 number of iterations를 요청하느냐는 BBHT의 random number가 정합니다.

**얼마나 줄었나.** 500 workloads 전체에서 executed iterations가 31,424에서 9,582로 **69.5%** 줄었습니다(16.3절 표). 이 절감이 Six-Stage Ablation의 첫 단계(Stage 1 → Stage 2, 총 cycle −56.63%)이고, board wall-clock time 7.626× 가속의 가장 큰 몫입니다.

**왜 a Checkpoint-Capacity of 3, 왜 3-shot Lookahead인가.** 직관과 반대로, Checkpoint-Capacity와 Lookahead-Shots를 늘리는 것이 늘 이득은 아니었습니다. a Checkpoint-Capacity of 4 and 4-shot Lookahead에서 a Checkpoint-Capacity of 3 and 3-shot Lookahead로 줄였더니 executed iterations는 9,058에서 9,582로 5.8% **늘었는데** 총 cycle은 7.66% **줄었습니다**. 4 PEs로 iteration 한 번이 약 268 cycles까지 짧아진 뒤에는, policy가 결정을 내리는 데 드는 cycle이 아끼는 iteration보다 비싸졌기 때문입니다. 발표 자료의 직접 비교에서 policy가 평가한 action이 70%, policy cycle이 56%, policy 때문에 search가 멈춘 cycle이 73% 줄었습니다. 1 PE 조건의 Checkpoint-Capacity · Lookahead-Shots 단독 실험도 같은 방향입니다 — Checkpoint-Capacity만 4에서 3으로 줄이면 거의 차이가 없고(0.21%), 이득은 대부분 Lookahead-Shots를 줄일 때 나옵니다(2.58%). **비싼 쪽은 저장 공간이 아니라 결정 비용**입니다. 참고로 4 PEs configuration의 amplitude memory는 checkpoint slot 네 벌 분량(RAMB36 44개)으로 짜여 있어, Checkpoint-Capacity를 3으로 줄여도 BRAM은 줄지 않습니다(11.4절).

---

## 16.6 왜 결과가 달라지지 않는가

실패한 shot의 state를 물려받아 이어 돌리는 것이 정말 **같은 algorithm**인지, 두 층위로 나눠 답해야 합니다.

**첫째, state 재현성.** Grover 한 바퀴를 $G = D \cdot O$(oracle 뒤 diffusion operator)라 쓰면, checkpoint slot에서 이어 가는 경로가 만들어 내는 연산열은

$$(D O)^{\text{number of iterations}_{\text{request}}} = (D O)^{\,\text{number of iterations}_{\text{request}} - \text{number of iterations}_{\text{checkpoint slot}}} \cdot (D O)^{\,\text{number of iterations}_{\text{checkpoint slot}}}$$

입니다. 6.6절이 "circuit의 순효과는 하나의 unitary"라고 했던 그 associative law가 근거입니다 — unitary의 곱은 결합적이므로 어디서 끊어 읽든 순효과가 같습니다. 즉 이어 가는 경로는 새로 Init해서 같은 횟수만큼 돌린 것과 **문자 그대로 같은 연산열**이고, 우리 산술이 결정적(rounding은 round-half-to-even, saturation 지점과 accumulator width는 고정)이므로 결과는 근사적으로 같은 정도가 아니라 **bit 단위로 동일**합니다. checkpoint slot이 몇 벌이든, policy가 어떤 중간 state를 남기든 이 등식은 그대로입니다. 이 등식이 [18.7절](18_reference_model_verification.md#187-checkpoint를-어떻게-검증하나)에서 verification의 합격 기준이 됩니다.

**둘째, 통계적 정당성.** 여기서 반드시 나오는 질문이 있습니다 — *"앞 shot의 계산을 물려받으면 그건 shot을 여러 번 던진 게 아니라 한 번 길게 돌린 거 아닌가? 반칙 아닌가?"*

아닙니다. 이유는 두 가지입니다. 하나, **같은 횟수만큼 iteration을 돈 state는 도달 경로와 무관하게 유일합니다.** 위 등식이 말하는 것이 정확히 그것이죠. 앞선 shot을 거쳐 왔든 방금 Init했든, 같은 횟수만큼 iteration을 돈 amplitude array는 같은 하나입니다. 둘, **measurement random number는 shot마다 Measurement PRNG에서 새로 뽑습니다.** 그래서 각 shot은 여전히 $\sin^2\big((2\cdot\text{number of iterations}+1)\,\theta\big)$ probability로 solution을 내는 **서로 독립인 shot**입니다. 결과적으로 후보 index의 분포도, shot당 success probability도, 총 number of shots의 분포도 checkpoint를 끄나 켜나 똑같습니다. **관측 가능한 출력은 하나도 바뀌지 않고 wall-clock time만 줄어듭니다.** 실제로 같은 500 workloads에서 board의 Restart mode와 final configuration이 결과 index·number of shots·requested iterations를 500/500 같게 냈습니다.

다만 제약도 있습니다. **실기 quantum computer는 이렇게 할 수 없습니다.** [4.4절](04_measurement.md#44-measurement는-state를-collapse시킨다)의 collapse 때문입니다 — 실제 장치에서는 측정하는 순간 superposition이 무너져 amplitude가 사라지므로, 다음 shot은 무조건 $|0\cdots0\rangle$ 부터 다시 만들어야 합니다. 우리가 이어 돌릴 수 있는 것은 amplitude를 memory에 펼쳐 놓았고 Born-rule sampling을 **읽기 전용**으로 구현했기 때문이지, quantum mechanics에서 가능한 동작이어서가 아닙니다. 앞으로 올 request를 미리 계산하는 policy도 마찬가지로 emulator만 할 수 있는 일이지만, 그것이 들여다보는 것은 BBHT가 스스로 만든 number of iterations 수열뿐이고 amplitude나 solution은 아닙니다. 11장에서 말한 "emulator가 실기보다 쉬운 것들"의 대표적인 사례입니다.

그러므로 보고할 때 두 지표를 반드시 갈라 적습니다. **algorithm 지표(requested iterations)는 그대로이고, 줄어드는 것은 executed iterations(`EXECUTED_ITERATIONS`)와 wall-clock time뿐입니다.** 16.3절 표에서 두 열이 따로 적힌 것이 이 구분입니다. 이걸 섞어 "우리 방식이 Grover iteration을 70% 줄였다"고 쓰면 부정확합니다 — 줄어든 것은 emulation 시간이지 algorithm이 oracle에 던진 질의 횟수가 아닙니다.

---

## 16.7 무효화는 hardware가 한다

checkpoint slot에 붙은 number of iterations는 사실 "이 state는 **어떤 predicate·어떤 threshold·어떤 data·어떤 mask**로 몇 번 돌린 결과인가"라는 tuple 전체를 요약한 값입니다. 그 tuple 중 하나라도 바뀌면 남아 있는 amplitude는 지금 풀려는 문제의 중간 결과가 아니게 되므로, 즉시 무효가 되어야 합니다.

Accelerator Core는 다음 경우에 **스스로** checkpoint slot을 전부 비웁니다 — data load 시작, predicate 종류 변경, threshold A·B 변경, 유효 data 개수 변경, 그리고 enumeration에서 새 답이 나와 `found_mask` 가 바뀔 때. 반대로 두 random number seed, shot cap, autonomous mode와 Manual mode 사이의 전환, Manual mode의 number of iterations, checkpoint bit를 바꾸는 것은 amplitude의 의미를 바꾸지 않으므로 checkpoint slot을 비우지 않습니다. 미리 풀어 둔 policy 계획도 문제가 바뀌면 함께 버립니다.

"firmware가 threshold를 바꿀 때 무효화 bit도 같이 쓰면 되지 않나"는 유혹적이지만, software에 맡기면 **무효화 처리를 빠뜨리는 경우가 반드시 생깁니다.** 나중에 predicate를 하나 더 추가한 사람이 무효화를 빼먹는 순간, 이전 amplitude에 새 oracle이 적용되어 **조용히 틀린 답**이 나옵니다. crash도 아니고 timeout도 아니라 그럴듯한 index가 하나 나오는 종류의 bug라, simulation에서 잡기 가장 어렵습니다. 무효화 조건은 Accelerator Core가 이미 들고 있는 설정값에서 추가 비용 없이 판정할 수 있는데 그 신뢰를 software에 넘길 이유가 없습니다. 그래서 CSR에도 무효화 명령 register가 없습니다.

enumeration mode에서의 결말은 두 갈래입니다. 새 답이 나오면 mask가 바뀌므로 checkpoint slot이 비고 다음 enumeration round는 Init부터 시작합니다. 그러나 한 번의 BBHT search가 답을 못 내고 끝났을 때는 mask가 그대로이므로 **checkpoint slot이 살아 있고**, 다음 BBHT search가 그 state들을 이어 씁니다. 그래서 enumeration에서도 checkpoint가 일을 합니다(14.7절의 예에서 requested iterations 2,422 대 executed iterations 635).

---

## 16.8 기각한 대안

checkpoint에 도달하기까지 검토한 안들입니다. 왜 버렸는지가 왜 택했는지만큼 중요합니다.

**1칸 checkpoint (초판).** 직전 shot의 state 한 벌만 남기는 안입니다. 추가 memory가 0이라는 이점이 있었지만 request가 직전보다 작아지면 Init부터 다시 해야 하고 중간 state를 남길 자리도 없습니다. 여러 벌의 checkpoint slot과 policy를 둔 a Checkpoint-Capacity of 4 and 4-shot Lookahead가 board 250쌍에서 executed iterations를 71% 넘게 줄여 이 안을 대체했고, 최종 a Checkpoint-Capacity of 3 and 3-shot Lookahead가 그 뒤를 이었습니다.

**되감기(양방향 이동).** $O$ 와 $D$ 는 각각 자기 자신이 inverse이므로 $G^{-1} = (DO)^{-1} = O D$ 입니다. 즉 이론상으로는 request가 지금 state보다 작을 때 initialization 없이 **뒤로 감을** 수도 있습니다. 그런데 fixed-point에서 $OD$ 는 $DO$ 의 **정확한** 역이 아닙니다(round-half-to-even과 saturation은 비가역이니까요). 되감은 state는 bit 단위로 원래 state와 달라져 16.6절의 등식이 깨집니다. 게다가 checkpoint slot이 여러 벌이면 앞선 state를 이미 들고 있으므로 되감을 이유 자체가 줄어듭니다.

**더 많은 Lookahead-Shots(8-shot Lookahead).** 앞을 더 멀리 보면 iteration을 조금 더 아낄 수 있습니다. benchmark에서 8-shot Lookahead는 4-shot Lookahead보다 iteration을 2.7% 덜 썼지만, policy 때문에 search가 멈춘 cycle이 23×로 늘어 총 cycle에서 손해였습니다(2026-09-04 board benchmark). 이 관찰이 a Checkpoint-Capacity of 3 and 3-shot Lookahead로 가는 근거가 됐습니다(16.5절).

**더 큰 Checkpoint-Capacity.** Checkpoint-Capacity를 늘리면 policy가 고를 여지가 늘지만, 16.5절의 단독 실험처럼 4에서 3으로 줄여도 cycle 차이가 0.21%에 그쳤고, 반대로 늘리는 쪽은 state 한 벌이 RAMB36 11개라 BRAM 예산(11.4절)에 막힙니다.

**`hit[]` bit vector caching.** predicate 판정 결과를 bit vector로 저장해 두면 oracle을 다시 계산하지 않아도 되지 않을까 — 라는 발상입니다. cycle 절감이 **정확히 0**입니다. Predicate Unit은 subtractor 하나짜리 combinational logic이고(13.3절), `data_mem` 읽기가 amplitude 읽기와 **같은 cycle**에 나오기 때문에 아낄 시간이 애초에 없습니다. 무효화해야 할 대상만 하나 더 늘 뿐입니다.

한 가지는 기각이 아니라 **보류**입니다. 각 number of iterations의 amplitude를 DRAM에 전량 저장해 두고 필요한 state를 burst 한 번에 가져오는 DRAM Variant(`hardware_dram`)는 Checkpoint-Capacity도 policy도 필요 없게 만드는 다른 답입니다. RTL 초안과 regression까지 있고 물리 DRAM 연결과 board verification은 아직이라, BRAM Variant와 DRAM Variant 중 어느 쪽을 최종으로 할지는 정해지지 않았습니다.

---

## 16.9 초판의 미정 넷은 이렇게 정해졌다

이 장의 초판은 네 가지를 미정으로 남겨 두었습니다. 지금은 RTL과 software reference model이 같은 규칙으로 확정했습니다.

**1. solution이 없을 때의 종료 조건.** predicate를 만족하는 원소가 하나도 없으면 BBHT는 영원히 실패합니다. hardware는 array를 고전적으로 훑어 "없음"을 확정하지 않고, 16.3절의 두 보호 한도 — shot cap 100, BBHT budget 576 — 중 먼저 닿는 쪽으로 끝냅니다. array에서 정보를 미리 읽지 않는다는 16.1절의 원칙이 그대로 지켜집니다. enumeration mode에서는 이 "실패로 끝난 BBHT"가 연속 `fail_repeat_limit` 번(기본 3번)이면 enumeration을 끝냅니다(14.7절).

**2. $\text{number of iterations} \sim U[0,\ \text{sampling range})$ 의 균등성.** LFSR 출력을 masking만 하면 sampling range가 2의 거듭제곱이 아닐 때 분포가 균등하지 않습니다. 16.2절의 rejection sampling으로 해결했습니다 — 경계 이상의 후보는 버리고 다시 뽑습니다.

**3. random number 소비 규약.** number of iterations stream과 measurement stream은 **서로 독립인 두 generator**입니다. number of iterations 쪽은 32-bit Iteration-Count LFSR이고 후보 하나마다(버린 후보까지 포함해) 한 번 추첨하며 LFSR을 7 steps 전진시킵니다. sampling range 경계가 1이어도 sampling 한 번은 소비하고 0 iterations를 냅니다. measurement 쪽은 Measurement PRNG(64-bit xorshift)이고, rejection sampling의 후보마다 64-bit block 하나를 씁니다(14.4절). group → row → lane 선택은 받아들인 random number 하나의 잔여를 이어 쓰며 새 random number를 뽑지 않습니다. 두 seed는 host가 시작 명령을 쓸 때 다시 읽히고, seed가 0이면 정해진 대체 constant를 씁니다. 이 규약이 다르면 reference model과 RTL이 **bit-exact가 성립하지 않는데**([18.3절](18_reference_model_verification.md#183-bit-exact가-성립하기-위한-조건)), 지금은 둘이 500 workloads 전부에서 같은 BBHT trajectory를 냅니다.

**4. $\text{sampling range} \leftarrow \min(1.2\cdot\text{sampling range},\ \sqrt{\text{number of states}})$ 의 hardware 산술.** 1.2×는 shift로 떨어지지 않지만, $\sqrt{\text{number of states}} = 128$ 이 정확한 integer라 clamp는 쉬워졌습니다. 16.2절의 28항 ROM으로 정했습니다.

---

## 16.10 이 장의 요약

- **solution이 몇 개인지 모른다**: number of solutions는 predicate·threshold·data에 달려 실행 시점에야 정해지므로 optimal number of iterations $\frac{\pi}{4}\sqrt{\text{number of states}/\text{number of solutions}} - \frac12$ 를 미리 계산할 수 없고, 9.6절 때문에 "넉넉히 많이"도 안 통합니다.
- **quantum counting(QPE)은 제외**: complex number를 강제해 실수 전용 23-bit Q1.22 datapath를 그대로 쓸 수 없기 때문. 성능 문제가 아니라 수 표현 문제입니다.
- **그래도 BBHT를 쓰는 이유는 속도가 아니라 충실도**: emulator에서 solution을 세는 비용은 shot 하나보다 싸지만, 그것은 amplitude array를 직접 읽는 것처럼 실제 장치에서 얻을 수 없는 정보를 쓰는 일입니다. 비교 실험용으로는 firmware가 number of iterations를 정하는 Manual mode가 따로 있습니다.
- **BBHT**: sampling range는 1에서 시작하고, shot마다 number of iterations를 $[0,\ \text{sampling range})$ 에서 **무작위**로 뽑고, 실패하면 sampling range를 growth factor 6/5만큼 넓힙니다(상한 $\sqrt{\text{number of states}}$). number of iterations를 무작위로 뽑는 이유는 success probability $\sin^2\big((2\cdot\text{number of iterations}+1)\,\theta\big)$ 가 진동하기 때문 — 14 qubits · 1 solution에서 100 iterations는 100%인데 200 iterations는 0%입니다. $\sqrt{\text{number of states}} = 128$ 이 integer라 number of iterations는 $[0,128)$ 에서만 뽑히고, sampling range 수열은 28항 ROM, number of iterations는 LFSR rejection sampling으로 정확히 균등합니다.
- **mean 22.7 shots**(14 qubits · 1 solution · 500 workloads campaign): sampling range가 1부터 1.2×씩 커져 초반 shot은 거의 전부 실패하도록 되어 있습니다. "4~5회"가 아닙니다. 보호 한도는 shot cap 100과 BBHT budget 576입니다.
- **바깥 FSM 2 layer**: shot loop(ROM에서 sampling range · LFSR로 number of iterations · policy에 출발 checkpoint slot 문의) + 안쪽 iteration(13장) + solution check(한 칸 고전 확인) + enumeration round loop. shot loop 자체는 LUT 359개로 작습니다.
- **checkpoint**: amplitude에 쓰는 것은 Init·oracle·diffusion operator 셋뿐이고 Born-rule sampling은 읽기 전용이므로, 실패한 shot의 state가 그대로 남습니다. state를 **세 벌(a Checkpoint-Capacity of 3)** 저장해 두었다가 가장 가까운 앞선 state에서 **차이만큼만** 전진합니다. 무엇을 남길지는 지금 request와 **앞으로 올 3 requests(3-shot Lookahead)** 를 보는 DP policy가 정하고, 앞으로 올 request는 결정적인 Iteration-Count LFSR의 사본을 전진시켜 미리 압니다. 500 workloads executed iterations **−69.5%**.
- **a Checkpoint-Capacity of 3 and 3-shot Lookahead가 a Checkpoint-Capacity of 4 and 4-shot Lookahead를 이긴 이유**: iteration은 5.8% 더 쓰지만 결정 비용이 크게 줄어 총 cycle −7.66%. 비싼 쪽은 저장 공간이 아니라 결정 비용입니다.
- **결과는 안 바뀝니다**: Grover iteration의 곱은 결합적이라 checkpoint slot에서 이어 간 state가 bit 단위로 같은 state이고(6.6절), measurement random number는 shot마다 새로 뽑으므로 각 shot은 여전히 서로 독립입니다. board에서 Restart mode와 final configuration의 BBHT trajectory가 500/500 같았습니다. 단 **실기 quantum에서는 할 수 없는 동작**이고 algorithm 지표 requested iterations와 executed iterations·wall-clock time을 갈라 적습니다.
- **무효화는 hardware가**: data load·predicate·threshold·data 개수·enumeration mask가 바뀌면 Accelerator Core가 스스로 checkpoint slot을 비웁니다. software에 맡기면 조용히 틀리는 bug가 납니다. enumeration에서 실패한 BBHT 사이에는 checkpoint slot이 유효한 상태로 남습니다.
- **기각·보류한 대안**: 1칸 checkpoint(대체됨) · 되감기(fixed-point에서 정확한 역이 아님) · 8-shot Lookahead(stall 23×) · Checkpoint-Capacity 증설(이득 미미, BRAM 예산) · `hit[]` caching(cycle 절감 0). DRAM Variant는 보류.
- **초판의 미정 넷**은 전부 정해졌습니다: solution이 없으면 두 보호 한도로 종료 · number of iterations는 rejection sampling으로 균등 · 두 random number stream의 소비 규약 고정 · sampling range는 28항 ROM.

이것으로 한 shot 안(13·14장)과 shot 바깥(16장)의 제어가 모두 정리됐습니다. 다음 17장은 이 accelerator를 혼자 두지 않고 RVX SoC에 붙입니다 — host가 UART로 명령을 보내고, RISC-V core가 APB로 CSR을 쓰고, accelerator가 AHB master로 data를 끌어오는 경로입니다.

---

> [← 15장 논문 지도와 설계 결정표](15_paper_map_and_design_decisions.md) · [index](index.md) · [17장 RVX SoC에 붙이기 →](17_rvx_soc_integration.md)
