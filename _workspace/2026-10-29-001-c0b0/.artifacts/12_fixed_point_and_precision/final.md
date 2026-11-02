# 12장. amplitude를 숫자로 — fixed-point와 Q1.22

> [← 11장 state vector emulator — memory map과 resource 예산](11_state_vector_emulator.md) · [index](index.md) · [13장 oracle과 diffusion operator — multiplier 없는 산술 →](13_oracle_diffusion_measurement_datapath.md)
> **이 장을 읽기 위한 준비**: [1장 amplitude·normalization](01_qubits_and_states.md), [4장 Born rule](04_measurement.md), [11장 state vector emulator](11_state_vector_emulator.md).

---

11장에서 state vector를 array `amp[0..16383]` 로 펼쳤습니다. 그런데 array의 한 칸에 amplitude $\alpha_i$ 를 담으려면 **결국 몇 bit짜리 어떤 숫자 형식으로 담을지**를 정해야 합니다. 이것은 FPGA emulator를 설계할 때 처음 정해야 할 사항입니다. bit를 너무 적게 잡으면 error가 쌓여 solution을 찾기 어려워지고, 너무 많이 잡으면 memory와 logic를 낭비합니다(11장에서 봤듯 amplitude bit 폭은 곧 memory 폭이니까요).

결론부터 적어 둡니다. 우리 amplitude 한 칸은 **23-bit fixed-point, Q1.22**입니다. rounding은 round-half-to-even, 넘치면 symmetric saturation, norm renormalization은 하지 않습니다. 계산 도중의 중간값만 더 넓은 register에서 다루고, memory에 되쓸 때 23 bits의 범위로 제한합니다. 이 장은 그 결정 하나하나가 **무엇을 재서** 나왔는지를 따라갑니다(값의 source of truth는 [15.4절 설계 결정표](15_paper_map_and_design_decisions.md#154-우리-project의-좌표--확정-설계-결정표)).

길잡이가 되는 것은 두 편의 중앙대 연구실 논문입니다. 04번(Choi & Lee, 2024)은 "fixed-point로 하자, Q1.30으로"라는 **선택**을 내렸고, 05번(Choi 외, QIP 2026)은 "그럼 fraction bits는 정확히 몇 bit여야 하는가"라는 **이론**을 세웠습니다. 우리는 둘 중 어느 쪽 숫자도 그대로 쓰지 않는데, 왜 그런지가 이 장의 절반입니다.

---

## 12.1 왜 floating-point를 안 쓰는가

프로그래밍에서 fractional number를 다룰 때 우리는 보통 `float`·`double` 같은 **floating-point**를 씁니다. radix point 위치가 "떠다니며" 아주 큰 수와 아주 작은 수를 모두 표현하죠. 편리하지만, hardware로 만들면 **비쌉니다.** floating-point는 숫자를 $\text{mantissa}\times 2^{\text{exponent}}$ 로 쪼개 저장하기 때문에, addition 한 번에도 exponent를 맞추고(alignment) 결과를 다시 normalization하고 rounding하는 부수 작업이 딸려 옵니다.

04번 논문은 이 비용을 정확히 셉니다. floating-point **addition 한 번**은 내부적으로 real addition 4회 + 비교 4회 + shift 3회를 요구하고, **multiplication 한 번**은 real addition 4 + real multiplication 1 + 비교 4 + shift 2 + XOR 1이 필요합니다. 반면 **fixed-point**는 같은 addition이 그냥 integer addition 1회, power of two를 곱하는 것은 shift 1회로 끝납니다. emulator는 diffusion operator 한 번에 모든 amplitude를 더하고 빼므로(13.5절), 이 constant 배의 차이가 number of states에 곱해져 resource·전력·latency로 고스란히 나타납니다.

우리에게는 이유가 하나 더 있습니다. 13.8절에서 보겠지만 이 IP의 diffusion operator·oracle·initialization 경로에는 **multiplier가 하나도 없습니다** — 전부 addition·subtraction·shift뿐입니다. floating-point를 택하는 순간 그 결론은 성립하지 않습니다. alignment와 normalization이 곧 가변 shift와 priority encoder를 뜻하고, 그것이 128 lanes마다 하나씩 붙기 때문입니다.

---

## 12.2 fixed-point와 Q format 명명 규약

**fixed-point**는 이름 그대로 radix point 위치를 **한 자리에 고정해** 두는 방식입니다. radix point가 떠다니지 않으므로 alignment·normalization이 필요 없고, 숫자를 그냥 **integer처럼** 다루되 "이 integer의 아래 몇 bit는 fraction bits"라고 약속만 해 두면 됩니다.

일상의 비유를 들면, 돈을 다룰 때 우리는 12,345원을 굳이 $1.2345\times 10^4$ 로 쓰지 않습니다. 그냥 "원" 단위 integer로 적고 radix point는 생각하지 않죠. fixed-point도 똑같습니다. 예를 들어 아래 22 bits를 fraction bits로 약속하면, memory에 저장된 integer $2{,}097{,}152$ 는 실제로는 $2^{21}/2^{22} = 0.5$ 를 뜻합니다. radix point는 "약속" 속에만 있고 hardware는 integer 연산만 합니다.

이 약속을 **Q format**으로 표기합니다. `Q<integer bits>.<fraction bits>` 꼴입니다. 그런데 여기에 문헌마다 갈리는 함정이 있습니다 — **sign bit를 integer bits에 넣어 세는 곳과 따로 빼는 곳이 있어서**, 똑같은 32-bit data word가 어디서는 Q1.30으로, 어디서는 Q2.30으로 적힙니다.

이 해설서에서는 다음 규약으로 통일합니다. **sign bit는 integer bits에 포함합니다.** 따라서 Q format의 data word width는 언제나 integer bits + fraction bits이고, 표현 범위는 $[-2^{\,\text{integer bits}-1},\ 2^{\,\text{integer bits}-1} - 2^{-\text{fraction bits}}]$, resolution은 $2^{-\text{fraction bits}}$ 입니다.

이 규약으로 우리 설계를 적으면 이렇게 됩니다. amplitude data word width는 23 bits, fraction bits는 22 bits, 그래서 **Q1.22** — sign 1 + fraction 22이고, integer bits에 sign 말고는 아무것도 없습니다. 23-bit two's complement의 표현 범위는 $[-1,\ 1 - 2^{-22}]$ 이고 resolution은 $2^{-22} \approx 2.38\times 10^{-7}$ 입니다. 여기서 한 가지를 눈여겨보십시오 — **$+1.0$ 은 담기지 않습니다.** integer로 $2^{22} = 4{,}194{,}304$ 가 필요한데 23-bit two's complement의 maximum은 $4{,}194{,}303$ 입니다. 우리는 여기에 한 칸을 더 버려, 음수 쪽 끝 $-4{,}194{,}304$ 도 쓰지 않고 **$[-4{,}194{,}303,\ +4{,}194{,}303]$ 의 대칭 범위**만 합법 값으로 둡니다. 왜 그런지는 12.5절과 13.4절에서 드러납니다.

<img src="diagrams/12_qformat.svg" width="700" alt="23-bit Q1.22 저장 data word(sign 1 + fraction 22)와 25-bit 중간값 register, diffusion operator 중간값 상한 1 + 2/√(number of states)이 저장 data word 천장을 넘으면 symmetric saturation으로 붙이는 그림">

04번 논문의 표기도 이 규약으로 옮겨 읽어야 합니다. 논문은 32-bit data word를 "Q1.30"이라 부르는데, 이는 sign을 밖으로 뺀 표기입니다. 우리 규약으로는 **Q2.30**(sign 1 + integer 1 + fraction 30 = 32 bits)입니다. 앞으로 Q format 표기를 만나면 **"integer bits + fraction bits = data word width"가 성립하는지** 확인하십시오. 성립하지 않으면 sign을 따로 센 표기입니다. 이 사소해 보이는 구분이 memory 예산 계산에서 bit를 한 칸씩 어긋나게 만듭니다.

마지막으로 이 규약이 곧바로 쓰이는 constant 하나. uniform amplitude는 $1/\sqrt{\text{number of states}}$ 인데, 14 qubits면 $1/\sqrt{16384} = 1/128 = 2^{-7}$ 로 **power of two**입니다. Q1.22 integer로는 $2^{22}/2^{7} = \mathbf{32{,}768}$ 이고, rounding이 전혀 없는 **정확한** 값입니다. initialization이란 array 16,384칸을 전부 32,768로 채우는 일입니다(13.2절).

---

## 12.3 integer bits는 몇 bit인가 — 재는 대상이 셋이다

integer bits를 몇 bit로 잡을지는 **표현할 수 있어야 하는 maximum**이 정합니다. 여기서 혼동하기 쉬운 점이 있습니다. datapath가 만들어 내는 값이 **한 종류가 아니라 셋**이고, 셋의 maximum이 서로 다르다는 것입니다.

**(a) array에 저장되는 amplitude.** 4장 Born rule에서 measurement probability는 $|\alpha_i|^2$ 이고 전체 probability의 sum이 1이므로, 어떤 amplitude도 $|\alpha_i|\le 1$ 입니다. 여기까지만 보면 integer bits는 $\pm 1$ 근방만 담으면 되니 **sign bit 하나로 충분**해 보입니다. 04번이 integer bits를 1-bit로 잡고 남는 30 bits를 전부 fraction bits로 몰아준 것이 이 논리입니다.

**(b) diffusion operator 도중에 만들어지는 중간값 $2\bar a - \alpha_i$.** 그런데 amplitude는 memory에 저장된 뒤에도 매 iteration inversion about the mean을 거치며 바뀝니다. 그 결과값의 상한을 재 보면 이렇습니다. Cauchy–Schwarz inequality로 mean의 크기는

$$|\bar a| = \frac{1}{\text{number of states}}\left|\sum_i \alpha_i\right| \le \frac{1}{\text{number of states}}\sqrt{\text{number of states}}\sqrt{\sum_i \alpha_i^2} = \frac{1}{\sqrt{\text{number of states}}}$$

이고 $|\alpha_i| \le 1$ 이므로

$$\left|2\bar a - \alpha_i\right| \le 1 + \frac{2}{\sqrt{\text{number of states}}}$$

**이 값은 1을 넘을 수 있습니다.** 넘는 폭이 크지는 않습니다 — 14 qubits면 $2/\sqrt{16384} = 2/128 = 0.0156$ 이니 상한이 1.0156입니다. 하지만 Q1.22의 천장은 $1 - 2^{-22}$ 이라, 이 값을 23-bit data word에 그대로 담을 수는 없습니다.

**(c) 전체 sum을 담는 accumulator $\sum_i \alpha_i$.** mean을 구하려면 먼저 모든 amplitude를 더해야 합니다. 최악의 경우 자릿수가 $\log_2(\text{number of states}) = \text{number of qubits}$ bits만큼 늘어납니다.

integer bits 폭을 하나만 정해서 셋에 다 쓰겠다는 발상이 틀린 것입니다. **재는 대상이 다르면 필요한 폭도 다릅니다.** 그래서 우리 datapath는 셋을 따로 잡습니다.

| 값 | 폭 | 이유 |
|---|--:|---|
| 저장 amplitude (a) | **23 bits** (Q1.22) | 수학적으로 $\lvert\alpha\rvert \le 1$. memory에 들어가는 유일한 값 |
| $2\bar a$ 와 diffusion operator 중간값 (b) | **25 bits** | 상한 1.0156 을 넉넉히 담는 register. 되쓸 때 23 bits로 symmetric saturation |
| sum accumulator (c) | **39 bits** | data word width + number of qubits + 2 = 23 + 14 + 2 |

(b)를 어떻게 처리하느냐가 이 절의 핵심 결정입니다. 길은 둘입니다. 저장 data word 자체에 integer bit를 하나 더 두는 길(Q2.22, 24 bits)과, 저장 data word는 Q1.22 로 두고 **중간값만 넓은 register에서 계산한 뒤 되쓸 때 saturation하는** 길입니다. 우리 RTL은 뒤를 택했습니다. 근거는 셋입니다.

첫째, **되쓰는 값은 수학적으로 1을 넘지 않습니다.** $2\bar a - \alpha_i$ 의 상한 $1 + 2/\sqrt{\text{number of states}}$ 은 Cauchy–Schwarz inequality가 주는 느슨한 한계일 뿐이고, diffusion operator를 마친 값은 정확한 산술에서 여전히 unit vector의 성분입니다 — Grover iteration은 unitary이기 때문입니다(9장). 1을 넘는 양은 rounding이 만든 몇 LSB 뿐이고, 그것도 solution amplitude가 1에 거의 닿는 iteration에서만 생깁니다. 둘째, 중간값은 **register 하나**라 두 bit 넓히는 비용이 미미하지만, 저장 data word를 넓히면 그 비용이 amplitude array 전체와 checkpoint slot 전부에 곱해집니다. 셋째, 그리고 결정적으로 **benchmark가 뒷받침합니다.** 같은 산술(14 qubits · Q1.22 · 같은 rounding과 saturation 규칙)로 돌린 2026-08 reference model campaign 671,600 runs에서 saturation이 걸린 경우는 이렇습니다([실험 02 amplitude precision](../reports/02_amplitude_precision.md)).

| search | run | saturation event | 1,000 runs당 |
|---|--:|--:|--:|
| number of iterations 수동 지정 (최적 근처를 일부러 포함) | 41,280 | 2,520 | 61.05 |
| BBHT Restart mode | 137,600 | 368 | 2.67 |
| BBHT Checkpoint mode | 137,600 | 368 | 2.67 |

saturation이 일어나도 **기능 결과가 달라진 경우는 0**이었고, Restart mode와 Checkpoint mode에서 saturation event가 똑같이 368번 나왔다는 것은 두 경로가 같은 state를 지난다는 추가 증거입니다. saturation은 조용히 넘어가지 않고 `amp_overflow` 라는 sticky bit로 남습니다(12.5절). 진단용이지 결과 무효 표시가 아닙니다.

다만 이 선택으로 BRAM을 아낀 것은 아닙니다. 24-bit lane 셋은 72 bits로 RAMB36 한 port 폭에 정확히 들어가서, Q2.22로 잡았어도 state 한 벌이 RAMB36 11개로 같았을 것입니다(12.8절). 그러니 23 bits의 근거는 memory가 아니라 위의 셋 — 수학적 상한, register와 memory의 비용 차이, 그리고 benchmark입니다. (이 해설서의 옛 revision은 integer bits 2 bits를 결론으로 적었지만, 최종 RTL은 이 절의 방식을 택했습니다.)

(c)의 accumulator는 amplitude와 같은 data word에 담을 수 없으니 따로 잡습니다. Cauchy–Schwarz 상한만 보면 7 bits(number of qubits / 2)면 되지만 최악값인 14 bits(number of qubits)로 잡았는데, accumulator는 memory가 아니라 register라서 몇 bit 더 잡는 비용이 미미하기 때문입니다. 나머지 2 bits는 sign extension과 뒷단 연산을 위한 여유입니다. Measurement Unit에는 또 다른 accumulator(amplitude square의 sum)가 있는데, 그 폭은 measurement circuit의 구조와 함께 14장에서 정합니다.

---

## 12.4 rounding — 왜 half-to-even인가

integer bits가 넘침을 막는 역할이라면, **fraction bits는 precision**을 정합니다. fraction bits가 유한하므로 어딘가에서는 아래 bit를 버려야 합니다. 어디서 버려질까요? 05번 논문이 이를 정확히 셋으로 짚습니다.

1. **initialization** — uniform amplitude $1/\sqrt{\text{number of states}}$ 를 유한 bit로 표현할 때. loop 시작 전 **한 번**. 다만 우리 14 qubits에서는 $1/\sqrt{\text{number of states}} = 2^{-7}$ 이라 **버리는 bit가 없습니다**(12.2절).
2. **diffusion operator의 right shift** — diffusion operator가 실제로 필요로 하는 값은 mean이 아니라 **2×mean**이라, accumulator를 number of qubits − 1 bits, 곧 13 bits만큼 arithmetic right shift해(`sum >>> 13`) 한 번에 구합니다(13.5절). 이 shift에서 아래 13 bits가 떨어져 나갑니다. **매 iteration**.
3. **measurement의 square** — probability를 만들 때 amplitude를 제곱합니다. 05번은 여기서도 product의 아래 bit를 버리지만 우리는 자르지 않습니다. 23-bit끼리의 product는 46 bits이고 그 폭 그대로 누적하므로, 이 자리에서 precision을 좌우하는 것은 truncation이 아니라 **accumulator 폭**입니다. 폭 결정은 [14.5절](14_multiple_solutions_and_minimum_search.md#145-2단-병렬-measurement)에 있습니다. loop가 끝난 뒤 **한 번**.

addition과 subtraction은 fraction bits를 깎지 않고(자릿수만 늘 뿐 아래 bit를 버리지 않습니다), 2×는 shift 칸수를 14 대신 13으로 잡는 것으로 흡수되어 별도의 연산 자체가 없습니다. 그래서 diffusion operator 전체(accumulation → shift → subtraction)에서 error를 만드는 곳은 **가운데 shift 한 곳**뿐입니다. 되쓸 때의 saturation은 그보다 훨씬 드문 두 번째 자리입니다(12.3·12.5절).

그런데 그 한 곳이 결정적입니다. mean은 그 iteration의 **모든 amplitude에 2×로 실려** 들어갑니다 — mean의 rounding error $\epsilon$ 은 곧바로 모든 칸에 $2\epsilon$ 으로 퍼집니다. 그리고 이 일이 매 iteration 되풀이됩니다. 14 qubits · 1 solution이면 최적은 100 iterations입니다.

따라서 rounding 방식도 설계 결정의 하나입니다. 후보는 셋입니다.

- **truncation** — arithmetic right shift 결과를 그대로 쓰는 것. two's complement에서 truncation은 언제나 $-\infty$ 방향이므로 평균적으로 $-0.5$ LSB의 **한 방향 편향**이 남습니다.
- **half-up** — 정확히 절반인 지점을 늘 위로 올림. 대부분의 값에서는 편향이 사라지지만, 절반인 경우에만 $+$ 방향으로 치우친 것이 남습니다.
- **round-half-to-even** — 절반일 때는 결과의 최하위 bit가 0이 되는 쪽으로 붙임. 절반이 위·아래로 반반 갈리므로 편향이 정확히 0입니다.

편향이 있느냐 없느냐가 error의 **성장 속도**를 바꿉니다. 방향이 같은 error는 서로 상쇄되지 않고 number of iterations에 **비례**해 쌓입니다. 반면 방향이 무작위인 error는 서로 상쇄되며 $\sqrt{\text{number of iterations}}$ 규모로만 자랍니다. 100 iterations를 도는 loop에서 이 차이는 열 배입니다. 그래서 **truncation은 쓰지 않습니다.**

남은 둘 중 half-to-even을 고른 이유는 error 크기가 아닙니다. diffusion operator의 shift는 13 bits라 버려지는 bit가 정확히 절반이 되는 경우 자체가 $2^{-13}$ probability로만 나오고, half-up과 갈리는 자리도 딱 거기뿐이기 때문입니다. 고른 이유는 규칙이 대칭이라 편향의 상한이 원리적으로 0이라는 것, 그리고 수식으로 적었을 때 모호함이 없어 software reference model과 RTL이 tie에서 갈릴 여지가 없다는 것입니다(18.3절).

hardware 비용은 사실상 0입니다. 버릴 하위 bit 중 최상위 하나를 $g$(guard), 그 아래 전부의 OR를 $r$(sticky), 남는 값의 최하위 bit를 $\ell$ 이라 하면 올림 조건은

$$g \wedge (r \vee \ell)$$

입니다. gate 몇 개짜리 combinational logic이고, diffusion operator 한 번에 한 번만 씁니다.

두 가지를 미리 밝혀 둡니다. 첫째, 다음 두 절에서 인용할 05번 논문의 error 이론은 **truncation을 전제로** 세워졌습니다. 규칙을 바꾸는 순간 그 이론의 exponent와 constant를 그대로 가져다 쓸 수 없게 되는데, 이것이 12.7절의 주제입니다. 둘째, 규칙을 못 박는 것 자체가 verification의 전제조건입니다. reference model과 RTL이 서로 다른 rounding을 쓰면 두 결과는 영원히 bit 단위로 일치하지 않습니다(18.3절).

---

## 12.5 overflow policy — saturation·wraparound 금지·renormalization 없음

12.3절에서 중간값만 넓게 잡고 되쓸 때 23 bits로 붙이기로 했습니다. 그러면 "붙인다"가 정확히 무엇인지 정해야 합니다.

**wraparound는 금지입니다.** two's complement 산술에서 넘침을 방치하면 maximum 바로 위가 minimum이 됩니다 — $+0.99\ldots$ 에 조금 더하면 $-1$ 이 나옵니다. amplitude가 **sign까지 뒤집혀 정반대 값**이 되는 것입니다. Grover에서 sign은 장식이 아닙니다. oracle이 하는 일 전부가 sign 반전이고, diffusion operator는 sign이 뒤집힌 칸을 mean 위로 끌어올립니다(9장). 한 칸의 sign이 잘못 뒤집히면 그 칸은 다음 iteration부터 solution처럼 처리되고 오염된 값이 mean에 섞여 **모든 칸으로 번집니다.** 조용히 틀린 답을 내는 circuit이 되는 것이고, 이런 고장은 simulation에서도 찾아내기 어렵습니다.

**그래서 symmetric saturation을 씁니다.** 25-bit 중간값이 $+4{,}194{,}303$ 을 넘으면 $+4{,}194{,}303$ 에, $-4{,}194{,}303$ 을 밑돌면 $-4{,}194{,}303$ 에 붙입니다. error는 남지만 sign과 크기 순서는 보존되고, 무엇보다 error가 그 칸에 **국소적으로** 머뭅니다. 비용은 comparator 하나와 mux 하나입니다. 아래쪽 끝을 $-4{,}194{,}304$ 가 아니라 $-4{,}194{,}303$ 으로 잡는 이유는 13.4절에서 보듯 **모든 합법 값의 sign 반전이 다시 합법 값**이 되게 하려는 것입니다.

saturation이 한 번이라도 일어나면 `amp_overflow` bit가 서고, 다음 search가 시작될 때까지 내려가지 않습니다. saturation은 값을 상한에 붙일 뿐 아무 signal도 내지 않으므로, 이 bit가 없으면 saturation이 실제로 발동했는지 관측할 방법이 없습니다. 이 bit는 **진단용이고 결과 무효 표시가 아닙니다** — 12.3절의 benchmark대로 saturation이 기능 결과를 바꾼 경우는 없었고, 뽑힌 후보는 어차피 solution check를 통과해야 채택됩니다(16.4절).

**norm renormalization은 하지 않습니다.** 매 iteration 끝에 $\sum_i \alpha_i^2$ 를 다시 1로 맞추는 것은 수치해석에서 흔한 처방이지만, 우리는 세 가지 이유로 하지 않습니다. 첫째, Grover iteration은 이론상 unitary라 norm이 보존되고 실제로 어긋나는 양은 rounding error 규모뿐입니다. 둘째, norm을 1로 되돌리려면 $1/\|a\|$ 를 곱해야 하는데 inverse square root와 multiplication이 들어옵니다 — 12.1절에서 확보한 "diffusion operator·oracle 경로에 0 multipliers"가 그 자리에서 무너집니다. 셋째, 애초에 필요가 없습니다. measurement가 Born-rule sampling이고, sampler는 amplitude square를 **전체 sum으로 나눈 상대 비율**만 쓰므로(14.4절) norm이 정확히 1이 아니어도 probability distribution은 제대로 정의됩니다.

---

## 12.6 error는 어떻게 자라나

05번 논문에서 제시한 분석 결과입니다. truncation error가 Grover iteration을 거치며 최종 measurement probability distribution을 얼마나 왜곡하는지를, 두 state의 amplitude만 추적하는 방법으로 닫힌 형태로 유도합니다.

그 방법의 출발점은 **two-amplitude theorem**입니다 — Grover의 어느 iteration 시점에서도 state vector에는 딱 **두 종류의 값**만 존재한다는 것입니다: solution amplitude $\alpha_{\text{solution}}$ 하나와, 나머지 non-solution amplitude $\alpha_{\text{non-solution}}$ 하나. 9장에서 4 states를 손으로 돌릴 때 non-solution 세 칸이 항상 같은 값이었던 것을 기억하시나요? 그게 우연이 아니라 **number of states와 무관하게 성립하는 성질**입니다. 덕분에 $2^{\text{number of qubits}}$ dimension 문제가 2 scalars 문제로 줄어 분석이 가능해집니다.

이 theorem은 이 해설서에서 두 번 쓰입니다. 여기서는 error 분석을 가능하게 하고, 14.3절에서는 **solution이 여럿일 때 그 amplitude들이 매 iteration 정확히 같다**는 사실을 뒷받침해 measurement 방식 자체를 결정하는 근거가 됩니다. 9.4절 손계산에서 숫자로 확인할 수 있습니다.

분석의 결론을 한 줄로 쓰면:

$$\ell_2 \text{ error} = O\!\left(2^{\,\text{number of qubits}-\text{fraction bits}}\right)$$

measurement probability distribution의 $\ell_2$ 거리(참값과 얼마나 벌어졌는가)가 $2^{\text{number of qubits}-\text{fraction bits}}$ 규모로 자란다는 뜻입니다. 이 exponent는 다음 관계를 뜻합니다:

- **fraction bits를 1 bit 늘리면** → exponent가 1 줄어 **error가 절반**.
- **qubit를 1개 늘리면** → exponent가 1 늘어 **error가 두 배**.

<img src="diagrams/12_error_scaling.svg" width="600" alt="ℓ2 error = 2^(number of qubits − fraction bits) 등고선과 16 qubits · 16 fraction bits 붕괴 지점">

왜 하필 solution amplitude에 이렇게 빠르게 error가 쌓일까요? solution amplitude는 작게 시작해 iteration마다 커지는데, 그 커지는 과정이 **inversion about the mean**($a\mapsto 2\bar a - a$)라서 매 iteration non-solution들의 truncation error까지 함께 끌어와 증폭하기 때문입니다. number of iterations가 $\frac{\pi}{4}\sqrt{\text{number of states}} \approx O(2^{\text{number of qubits}/2})$ 이고 error가 대략 그 square로 누적되므로 $O(2^{\text{number of qubits}})$, 여기에 한 번의 truncation 크기 $2^{-\text{fraction bits}}$ 가 곱해져 $O(2^{\text{number of qubits}-\text{fraction bits}})$ 가 됩니다.

이 공식이 실무에 주는 경고가 하나 있습니다. 05번 논문의 실험에서 16 qubits, 16 fraction bits를 넣으면 $\ell_2$ error가 무려 **0.494** 로 치솟습니다. measurement probability의 총합이 1인데 error가 0.494라면, 결과는 사실상 **무의미**합니다. "amplitude를 그냥 16 bits에 담으면 충분하겠지"라는 순진한 가정이 정확히 어디서 무너지는지 보여주는 반례입니다 — qubit가 늘면 fraction bits도 그만큼 따라 키워야 한다는 것이죠.

그리고 여기서 반드시 붙여 두어야 할 단서가 있습니다. 위 유도에서 error가 number of iterations의 square로 누적되는 것은 **매 iteration 같은 방향으로 밀리는 error**의 그림입니다. 12.4절에서 본 그대로, 그것은 **truncation**의 성질입니다. 05번의 이론 전체가 truncation을 전제로 합니다.

---

## 12.7 몇 bit면 되나 — minimum fraction bits 공식과 그 전제

이제 필요한 폭을 정하는 문제를 봅시다. "목표 정확도를 맞추려면 fraction bits를 최소 몇 bit로 잡아야 하는가?" 05번 논문은 위 error 공식을 뒤집어 닫힌 형태의 답을 냅니다. 허용 가능한 최대 error를 $\ell_{2,\max}$ 라 하면:

$$\boxed{\,\text{minimum fraction bits} = \left\lceil\, \text{number of qubits} - \log_2 \ell_{2,\max} - 1.03 \,\right\rceil\,}$$

qubit가 많을수록 bit가 더 필요하고, 더 엄격한 정확도를 원할수록 bit가 더 필요합니다. constant $1.03$ 은 error 계수를 실험으로 보정한 값입니다. 예를 들어 6 qubits에서 error를 $10^{-5}$ 이하로 잡고 싶다면 $\log_2 10^{-5}\approx -16.6$ 이므로 minimum fraction bits는 $\lceil 6 + 16.6 - 1.03 \rceil = 22$, 곧 22 bits입니다. 04번의 30 fraction bits는 같은 조건에서 **8 bits가 과잉**인 셈입니다.

이 공식을 우리 설계에 대입해 봅시다. 14 qubits, 22 fraction bits이므로

$$\ell_2 \approx 2^{\,\text{number of qubits}-\text{fraction bits}-1.03} = 2^{\,14-22-1.03} = 2^{-9.03} \approx 1.9\times 10^{-3}$$

입니다. 흔히 쓰는 기준 $10^{-3}$ 을 조금 넘는 값이라, 공식만 믿으면 아슬아슬해 보입니다. 그러나 이 공식에는 **세 가지 전제**가 있고, 우리 설계는 셋 다 다릅니다.

1. **rounding이 truncation입니다.** error가 매 iteration 같은 방향으로 쌓이는 것이 square 누적의 근거인데, 우리는 round-half-to-even으로 그 편향을 없앴습니다(12.4절).
2. **data word 구성이 다릅니다.** 05번은 integer bits를 number of qubits만큼 넉넉히 잡은 **하나의 넓은 data word**를 전제합니다. 우리는 저장 data word를 23 bits로 좁히고 중간값과 accumulator만 따로 넓혔습니다(12.3절).
3. **판정 지표가 다릅니다.** 05번의 $\ell_2$ 는 measurement probability distribution **전체**가 참값에서 얼마나 벌어졌는가입니다. 우리 합격 기준은 그것이 아닙니다 — shot 하나가 후보 index를 하나 내면, 그 index는 **solution check**를 거쳐 predicate를 실제로 만족할 때만 채택됩니다(16.4절). distribution이 조금 흐려지면 shot이 몇 번 더 필요할 뿐, 틀린 답이 출력되지는 않습니다. precision error가 **정확도가 아니라 속도로** 나타나는 구조입니다.

세 전제가 모두 다르니 공식의 수를 우리 설계의 예측으로 읽어서는 안 됩니다. 그래서 우리는 fraction bits를 공식으로 정하지 않고 **직접 쟀습니다.** 두 가지 benchmark가 있습니다.

첫째, float64 기준과 같은 mask·같은 iterations로 fraction bits 폭만 바꿔 돌린 precision 분석입니다(1 · 4 · 64 solutions와 state 절반이 solution인 경우). probability distribution $\ell_2$ 가 $10^{-3}$ 이하가 되는 것은 fraction bits 20 bits부터, $10^{-5}$ 이하가 되는 것은 **22 bits**부터였습니다. 같은 분석에서 15 qubits · 16 qubits는 fraction bits 24 bits까지 늘려도 $10^{-5}$ 에 닿지 못했습니다 — 14 qubits로 굳힌 근거 중 하나가 이것입니다([실험 02 amplitude precision](../reports/02_amplitude_precision.md)). 둘째, 12.3절의 671,600-run campaign입니다. Q1.22로 돈 모든 run에서 amplitude $\ell_2$ · probability $\ell_2$ · success probability error · norm error의 maximum이 전부 $10^{-3}$ 아래였습니다([같은 실험 02](../reports/02_amplitude_precision.md)).

즉 22 fraction bits는 공식이 준 답이 아니라 **잰 답**입니다. 공식으로 경향을 파악하되 전제가 다르면 benchmark로 확인합니다. 18장 verification ladder도 이 원칙을 따릅니다.

---

## 12.8 data word와 BRAM 환산

amplitude 말고 폭을 정해야 할 것이 하나 더 있습니다. search 대상이 되는 data array `value[i]` 입니다. 확정값은 **16-bit signed** 입니다.

여기에는 precision 이론이 필요 없습니다. `value` 는 계산되는 값이 아니라 host가 실어 주는 **입력 data**이고, oracle이 하는 일은 `value - thr` 의 최상위 bit 하나를 보는 것뿐이라(13.3절) truncation error가 누적될 자리가 아예 없습니다. 16 bits는 $-32{,}768 \sim 32{,}767$ 을 담아 sensor 값·pixel·index 같은 흔한 data를 그대로 받기에 자연스럽고, 32-bit bus data word 하나에 두 칸이 딱 들어가 load도 간단합니다(17.5절).

**왜 폭이 개수를 정하는가.** 7 시리즈 FPGA의 BRAM은 RAMB18(18Kb)·RAMB36(36Kb) 단위로 잡히고, RAMB36은 한 port를 최대 **72-bit 폭 × 512 깊이**로 쓸 수 있습니다. 23-bit amplitude 셋이 69 bits라 그 폭에 들어가고, 우리 row 하나(32 lanes × 23-bit = 736 bits)는 3 lanes짜리 10개 + 2 lanes짜리 1개, 곧 **RAMB36 11개**에 담깁니다. 깊이 512도 우리 512 rows와 딱 맞습니다. 그래서 state 한 벌이 11개입니다.

14 qubits(16,384 states)에서 array들의 예산입니다.

| array | data word width | 용량 | 실제 BRAM (implementation report) |
|---|--:|--:|--:|
| amplitude state 한 벌 | 23b × 32 lanes = 736b × 512 rows | 368 Kb | RAMB36 11 |
| amplitude · checkpoint memory (checkpoint slot 4벌) | | 1,472 Kb | RAMB36 44 |
| `data_mem` (data) | 16b | 256 Kb | RAMB18 64 |
| `found_mask` (enumeration mask) | 1b | 16 Kb | RAMB36 2 |
| **Accelerator Core 계** (measurement·policy memory 포함) | | | **84 tile** |

board는 Arty A7-100T(`xc7a100tcsg324-1`)이고 BRAM tile이 **135개** 있습니다. RVX SoC가 32 tile을 써서 board 전체가 116 / 135입니다. `data_mem` 이 용량(256 Kb)에 비해 BRAM을 많이 먹는 것은, oracle이 한 cycle에 4 rows 128칸을 읽어야 해서 폭이 개수를 정하기 때문입니다.

만약 04번을 따라 amplitude를 **32 bits**로 잡았다면 어땠을까요. 32-bit lane은 72-bit 폭에 둘밖에 안 들어가서 state 한 벌이 RAMB36 16개, checkpoint slot 4벌이 64개가 됩니다. 지금보다 20개가 더 들어 board 전체가 136 / 135 — **넘칩니다.** 12.7절에서 본 대로 30 fraction bits는 이론적으로도 과잉이었으니, 우리가 04번의 data word width를 그대로 베끼지 않은 데에는 이론과 예산 양쪽의 이유가 있는 셈입니다.

표를 읽을 때 한 가지 주의할 점이 있습니다. 용량 열은 bits만 센 것이고, 실제 BRAM 개수는 data word를 몇 개로 쪼개 동시에 읽느냐가 함께 정합니다. 그래서 qubit를 줄여도 개수가 그대로일 수 있습니다. 그 계산은 11.7절에 있습니다.

---

## 12.9 반론 — "fixed-point는 부정확하다"

다른 선택을 한 연구도 살펴보겠습니다. 07번 논문(El-Araby 외)은 fixed-point를 **명시적으로 "low accuracy(낮은 정확도)"라고 비판**하며, 기존 FPGA quantum emulator들이 쓴 16 bits·24-bit fixed-point를 정확도 부족의 사례로 지목합니다. 그리고 자신은 **32-bit floating-point complex number**를 씁니다. 04·05번과 정면으로 부딪히는 입장이죠. 이 차이를 검토하면 우리가 fixed-point를 택한 근거를 더 분명히 설명할 수 있습니다. 해소 논리는 셋입니다.

**첫째, Grover amplitude는 dynamic range가 좁습니다.** floating-point의 진짜 강점은 아주 큰 수와 아주 작은 수를 동시에 다루는 **넓은 exponent 범위**입니다. 그런데 우리 datapath에 등장하는 값은 저장 amplitude가 $[-1, 1]$, 중간값이 $[-1.016, 1.016]$ 안입니다(12.3절). float32의 exponent 8 bits는 $10^{\pm 38}$ 을 담는데, 우리가 실제로 쓰는 범위는 한 자릿수도 되지 않습니다. 필요 없는 범위에 exponent 처리 circuit을 얹는 것은 낭비입니다.

**둘째, 요구 precision은 오히려 올라갔지만 그것이 floating-point의 근거가 되지는 않습니다.** measurement가 **Born-rule sampling**이기 때문에(14.4절) sampler는 amplitude square의 **상대적인 probability mass**을 그대로 출력 distribution으로 삼습니다. 순위뿐 아니라 크기의 **비율**까지 맞아야 하고, solution보다 훨씬 작은 non-solution amplitude도 수천 개가 모이면 probability mass의 상당 부분을 차지하므로 작은 값도 제대로 담겨야 합니다. 요구가 올라간 것은 분명합니다. 다만 올라간 것은 **resolution**(fraction bits)이지 **exponent 범위**가 아닙니다. fixed-point는 fraction bits를 늘려 resolution을 높이면 되지만 float32는 24-bit mantissa를 얻으려고 8 bits를 exponent에 떼어 줍니다 — 같은 data word width에서 우리에게는 버려지는 8 bits입니다. 07번이 절대 정확도에 민감했던 이유도 짚어 둘 만합니다. 그들의 대상은 **quantum Haar transform(QHT)을 통한 image 재구성**이었고, 재구성된 pixel 값 자체가 결과물이라 절대 정확도가 필수였습니다. 우리 출력은 index 하나이고, 그 index는 solution check를 통과해야 채택됩니다(16.4절).

**셋째, 근거의 무게가 반대입니다.** 07번은 fixed-point를 "부정확하다"고 비판하면서도, 정작 **bit 폭에 따른 error 곡선을 하나도 측정하지 않았습니다.** 반면 05번은 minimum fraction bits 공식과 그것을 뒷받침하는 verification table을 냅니다. 한쪽은 정성적 비판, 다른 쪽은 정량적 이론입니다. 07번의 비판은 "**아무렇게나** fixed-point를 쓰면 부정확하다"로 읽는 것이 옳고, 05번은 그 "아무렇게나"를 숫자로 바꾸는 처방입니다. 우리는 여기서 한 걸음 더 갔습니다 — 우리 조건이 05번의 전제마저 벗어나므로(12.7절), 공식조차 그대로 믿지 않고 직접 쟀고, 그 결과가 모든 run에서 $10^{-3}$ 아래였습니다.

---

## 12.10 우리 project의 결정

지금까지의 논증을 설계 언어로 정리하면 이렇습니다. 값의 source of truth는 [15.4절 설계 결정표](15_paper_map_and_design_decisions.md#154-우리-project의-좌표--확정-설계-결정표)입니다.

| 항목 | 값 | 근거 |
|---|---|---|
| 수 체계 | real number 전용 fixed-point | 12.1 · 9.8 |
| amplitude data word | 23 bits, **Q1.22** (sign 1 + fraction 22) | 12.2 · 12.3 |
| 범위 / resolution | 대칭 $[-(1-2^{-22}),\ 1-2^{-22}]$ / $2^{-22} \approx 2.38\times10^{-7}$ | 12.2 · 12.5 |
| `INIT_AMP` (14 qubits) | **32768** $= 2^{22}/128$, error 0 | 12.2 |
| 2×mean · diffusion operator 중간값 | 25-bit register | 12.3 |
| sum accumulator | 39 bits (data word width + number of qubits + 2) | 12.3 |
| rounding | **round-half-to-even**, 13-bit right shift 한 곳 | 12.4 |
| overflow | **symmetric saturation** + `amp_overflow` 진단 bit. wraparound 금지. norm renormalization 없음 | 12.5 |
| fraction bits 충분성 | 공식이 아니라 benchmark — 모든 run에서 error $< 10^{-3}$ | 12.7 |
| data word | 16-bit signed | 12.8 |
| amplitude memory | state 한 벌 RAMB36 11개, checkpoint slot 4벌 44개 (Accelerator Core 84 / board 116 tile) | 12.8 |

이 장에 미결로 남긴 항목은 없습니다. 초기 revision에서 "아직 하지 않은 benchmark"로 남겨 두었던 fraction bits 충분성은 이제 precision 분석과 671,600-run campaign으로 확인했습니다.

---

## 12.11 이 장의 요약

- **floating-point는 비쌉니다.** addition 하나에 alignment·normalization·rounding이 딸려 옵니다(04번: addition 4 + 비교 4 + shift 3). fixed-point는 integer addition 1회이고, 이것이 "0 multipliers diffusion operator"의 전제입니다.
- **명명 규약: sign은 integer bits에 포함.** Q format의 data word width = integer bits + fraction bits. 우리는 **Q1.22**(23 bits), 04번의 "Q1.30"은 우리 규약으로 **Q2.30**(32 bits). Q1.22는 $+1.0$ 을 담지 못하고, 우리는 $-1.0$ 도 버려 **대칭 범위**만 씁니다.
- 14 qubits에서 $1/\sqrt{\text{number of states}} = 2^{-7}$ 이라 **초기 amplitude 32,768이 정확**합니다. initialization에서는 error가 생기지 않습니다.
- **폭은 재는 대상이 셋**입니다: 저장 amplitude(23 bits) · diffusion operator 중간값(상한 $1 + 2/\sqrt{\text{number of states}} = 1.0156$, 25-bit register) · sum accumulator(39 bits). 저장 data word를 넓히는 대신 중간값만 넓히고 되쓸 때 **symmetric saturation**합니다. 되쓰는 값은 수학적으로 1을 넘지 않고, 671,600-run campaign에서 saturation은 드물었고(BBHT 1,000 runs당 2.67) 기능 결과를 바꾸지 않았습니다.
- **rounding은 round-half-to-even.** loop 안에서 매 iteration 새로 생기는 truncation은 diffusion operator의 13-bit right shift 하나뿐인데, 그 error가 mean을 통해 전 칸에 퍼지고 1 solution이면 100 iterations 동안 되풀이됩니다. 한 방향 편향은 number of iterations에 비례해 쌓이고, 무편향은 $\sqrt{\text{number of iterations}}$ 로만 쌓이므로 truncation은 쓰지 않습니다.
- **overflow는 symmetric saturation**과 `amp_overflow` 진단 bit. wraparound는 sign을 뒤집어 non-solution을 solution으로 만들고 mean을 통해 전체로 번집니다. **renormalization은 하지 않습니다** — Born sampler가 상대 비율만 쓰므로 필요가 없고, 하려면 multiplier가 들어옵니다.
- **error 성장**: 05번의 $\ell_2 = O(2^{\text{number of qubits}-\text{fraction bits}})$, fraction bits 1 bit = error 절반, qubit 1개 = error 두 배. 단 이 이론은 **truncation 전제**입니다.
- **minimum fraction bits 공식의 전제 셋**(truncation · 넓은 단일 data word · distribution 전체의 $\ell_2$)이 모두 우리와 다릅니다. 그래서 fraction bits를 공식으로 정하지 않고 **직접 쟀습니다** — 14 qubits에서 22 fraction bits면 probability $\ell_2 \le 10^{-5}$, campaign의 모든 run에서 error $< 10^{-3}$.
- **data word 16-bit signed**, amplitude 23 bits. 23-bit 셋이 RAMB36 한 port(72 bits)에 들어가 state 한 벌이 11개, checkpoint slot 4벌이 44개. amplitude를 32 bits로 잡았다면 64개로 board를 넘겼을 것입니다.
- **07번의 float32 비판**에 대한 답 셋: (1) dynamic range가 좁아 exponent field가 낭비, (2) Born-rule sampling으로 precision 요구가 **올라갔지만** 필요한 것은 resolution이지 exponent 범위가 아님, (3) 07번은 error 실험이 없고 우리는 쟀음.

다음 장에서는 이 숫자 형식 위에서 oracle·diffusion operator가 **실제 circuit**이 되는 과정을 봅니다. 12장에서 "error의 주범"이라 부른 그 right shift가 13.5절에서 gate로 구현되는 모습을 보고 12.3절의 25-bit 중간값과 symmetric saturation이 왜 그 자리에 필요했는지도 그때 눈으로 확인하게 됩니다.

---

> [← 11장 state vector emulator](11_state_vector_emulator.md) · [index](index.md) · [13장 multiplier 없는 산술 →](13_oracle_diffusion_measurement_datapath.md)

<!-- HUMANIZE-SUMMARY -->
<!--
{
  "원본_글자수": 25593,
  "최종_글자수": 25533,
  "경로": "heavy",
  "게이트_변경률": 0.0091,
  "등급": "B",
  "자체검증": "6/6 (보존 지시 대상의 교재 형식 제외)",
  "상태": "corrected",
  "국소_보정_수": 1,
  "카테고리": [
    "D-14",
    "D-2",
    "D-8"
  ],
  "하이라이트": [
    {
      "rule": "D-2",
      "before": "이것이 FPGA emulator 설계자가 마주하는 가장 실무적인 첫 결정입니다.",
      "after": "이것은 FPGA emulator를 설계할 때 처음 정해야 할 사항입니다."
    },
    {
      "rule": "D-14",
      "before": "error가 쌓여 solution이 흐려지고,",
      "after": "error가 쌓여 solution을 찾기 어려워지고,"
    }
  ],
  "잔존_finding": []
}
-->
