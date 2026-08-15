# 논문 해설·정리본 (한국어)

> **중앙대학교 학부 인턴 프로젝트**
> [`../papers/`](../papers/) 의 영어 원문에 대한 한국어 해설서. 원문 PDF를 옆에 두고 함께 읽는 용도입니다.

---

## 0. 이 폴더는 무엇인가요?

[`study_references/`](../study_references/) 가 **이론을 밑바닥부터 쌓는 교재**라면, 이 폴더는 **실제 논문을 읽기 위한 독해 보조 자료**입니다. 9장까지 배운 개념(오라클·위상 킥백·평균 반사·진폭증폭)이 실제 논문에서 어떤 기호와 어떤 하드웨어로 나타나는지를 잇는 다리입니다.

각 문서는 **문장 단위 번역이 아니라 해설·정리본**입니다. 원문의 절 순서를 그대로 따라가되 설명은 우리말로 새로 썼고, **수식·표·수치 결과는 원문 그대로 재현**했습니다. 각 절 첫머리의 `> 원문 p.12-15` 앵커로 원문 PDF의 해당 쪽을 바로 펼칠 수 있습니다.

| 문서 | 위치 | 성격 |
|------|------|------|
| 학습 해설서 | [`../study_references/`](../study_references/) | 이론 교재 (0~10장), 배경지식부터 |
| **논문 해설본 (본 폴더)** | `papers_ko/` | 논문 독해 보조, 원문과 1:1 대응 |
| 원문 PDF | [`../papers/`](../papers/) | 원본 (읽을 때 반드시 옆에 두세요) |

---

## 1. 먼저 알아야 할 것 — 이 논문들은 흩어진 9편이 아닙니다

폴더의 논문들은 **서로 인용하는 하나의 계보**입니다. 특히 중요한 사실:

**7편 중 3편이 우리 연구실(중앙대 지능형반도체공학과, 이우주 교수님) 논문입니다.**

```
  [04] Grover 에뮬레이터        Choi, W.Lee              AIMS Mathematics  2024
         │                                                (CC BY 4.0)
         ├──── 인용 ────┐
         ▼              │
  [06] QAOA 에뮬레이터   │      Choi, K.Lee, J-J.Lee, W.Lee   arXiv      2025
         │              │
         │              └──── 인용 ────► [07] HPRC (El-Araby, Kansas)  IEEE TC 2023
         ▼                                    = 대조군: "HPC 가속기" 진영
  [05] 정밀도 이론              Choi, K.Lee, Choi, Jung, W.Lee(교신)
                                Quantum Information Processing  2026 ★최신
```

- **[04] → [06] → [05]** 가 우리 연구실의 3부작입니다. [06]의 참고문헌 [10]이 정확히 [04]이고, [06]의 [9]가 정확히 [07]입니다.
- 우리 프로젝트(`project1/hardware/grover_ip.v`)는 **이 계보의 다음 단계**입니다. 그래서 [04]는 참고문헌이 아니라 사실상 **설계도**입니다.
- [05]는 2026년 6월 공개된 최신 논문으로, [04]의 고정소수점 정밀도 문제를 이론적으로 정리한 후속작입니다.

나머지 3편은 주변 맥락입니다 — **[07]** 확장성의 천장(대조군), **[08]** 이론적 일반화, **[09]** 응용 사례.

---

## 2. 문서 목록

| # | 해설본 | 원문 | 원문 정보 |
|:-:|--------|------|-----------|
| 03 | [Quantum Computing for the Very Curious](03_quantum_computing_for_the_very_curious_ko.md) | [원문](<../papers/1. 양자컴퓨터 기초이론/양자컴퓨터 기초이론 3. Quantum computing for the very curious.pdf>) | Nielsen & Matuschak, quantum.country, 64쪽 |
| 04 | [Developing a Grover's Emulator on Standalone FPGAs](04_developing_grover_emulator_standalone_fpga_ko.md) · [PDF](04_developing_grover_emulator_standalone_fpga_ko.pdf) | [원문](<../papers/2. Grover 논문 (LPSoC)/Developing a Grover’s quantum algorithm emulator on standalone FPGAs.pdf>) | **Choi & W. Lee (중앙대)**, AIMS Math. 9(11) 30939–30971, 2024 · `10.3934/math.20241493` |
| 05 | [Precision-aware Fixed-point Emulation of Grover's](05_precision_aware_fixed_point_grover_ko.md) · [PDF](05_precision_aware_fixed_point_grover_ko.pdf) | [원문](<../papers/2. Grover 논문 (LPSoC)/Precision-aware fixed-point emulation of Grover’s algorith.pdf>) | **Choi 외, W. Lee 교신 (중앙대)**, Quantum Inf. Process. 25:214, 2026 · `10.1007/s11128-026-05235-9` |
| 06 | [Standalone FPGA-Based QAOA Emulator for Weighted-MaxCut](06_standalone_fpga_qaoa_emulator_ko.md) · [PDF](06_standalone_fpga_qaoa_emulator_ko.pdf) | [원문](<../papers/3. QCE-FPGA 논문/Standalone FPGA-Based QAOA Emulator for.pdf>) | **Choi 외, W. Lee (중앙대)**, arXiv:2502.11316v2, 2025 |
| 07 | [Towards Complete and Scalable Emulation (HPRC)](07_towards_complete_scalable_emulation_hprc_ko.md) · [PDF](07_towards_complete_scalable_emulation_hprc_ko.pdf) | [원문](<../papers/3. QCE-FPGA 논문/Towards_Complete_and_Scalable_Emulation_of_Quantum_Algorithms_on_High-Performance_Reconfigurable_Computers.pdf>) | El-Araby 외 (U. Kansas), IEEE Trans. Comput. 72(8) 2350–2364, 2023 · `10.1109/TC.2023.3248276` |
| 08 | [Generalized Grover's Algorithm for Multiple Phase Inversion States](08_generalized_grover_multiple_phase_inversion_ko.md) · [PDF](08_generalized_grover_multiple_phase_inversion_ko.pdf) | [원문](<../papers/4. Grover 응용 논문/Generalized Grover's Algorithm for Multiple Phase Inversion States.pdf>) | Byrnes, Forster, Tessler, **PRL 120**, 060501, 2018 · `10.1103/PhysRevLett.120.060501` |
| 09 | [Quantum Minimum Searching for AUD in Wireless IoT](09_quantum_minimum_searching_aud_iot_ko.md) · [PDF](09_quantum_minimum_searching_aud_iot_ko.pdf) | [원문](<../papers/4. Grover 응용 논문/Quantum_Minimum_Searching_Algorithms_for_Active_User_Detection_in_Wireless_IoT_Networks.pdf>) | Habibie, Goursaud, Hamie (INSA Lyon), IEEE IoT J. 11(12) 22603–22615, 2024 · `10.1109/JIOT.2024.3382337` |

### 번역하지 않은 2편

[`papers/1. 양자컴퓨터 기초이론/`](<../papers/1. 양자컴퓨터 기초이론/>) 의 아래 두 편은 **이미 한국어**입니다 (블로그 글을 브라우저에서 PDF로 인쇄한 것). 번역이 필요 없어 그대로 두었습니다.

- `양자컴퓨터 기초이론 1. 그로버 알고리즘과 도이치 알고리즘.pdf` — [hgmin1159.github.io](https://hgmin1159.github.io/quantum/quantum_algorithm/)
- `양자컴퓨터 기초이론 2. 그로버 알고리즘.pdf` — [infossm.github.io](https://infossm.github.io/blog/2020/06/18/quantum-computing-grover/)

---

## 3. 추천 독서 순서

**하드웨어를 짜는 게 목적이라면** — [04] → [05] → [06] → [07]
[04]가 설계도, [05]가 비트 폭 결정 근거, [06]이 같은 골격의 다른 알고리즘, [07]이 확장의 천장입니다.

**이론을 먼저 다지고 싶다면** — [03] → [08]
단, [03]은 [`study_references/`](../study_references/) 1~9장과 내용이 겹칩니다. 해설서를 이미 읽었다면 [03]은 건너뛰고 [08]로 가도 됩니다.

**`grover_min_ip.v` 를 이어서 짤 거라면** — [09] 를 먼저
파일명이 시사하듯 최솟값 탐색(DHA) 변형이고, [09]가 정확히 그 알고리즘입니다.

---

## 4. 해설본에 담긴 원문 정오표

원문을 페이지 이미지와 대조하며 읽는 과정에서 **원문 자체의 오류·오타**를 여러 건 확인했습니다. 각 해설본에 표시해 두었으니, 원문을 그대로 구현하기 전에 반드시 확인하세요. 특히 다음 둘은 **그대로 옮기면 동작하지 않습니다**.

| 원문 | 위치 | 내용 |
|------|------|------|
| [04] | p.25 코드 | `>> NUM_STATE` → **`NUM_QUBIT`** 이어야 함 ($1/N^i = 2^{-ni}$). 그대로 짜면 값이 0이 됨. 같은 코드에 `amp_state` 인덱스 누락, `i - 1 << k` 연산자 우선순위 버그도 있음 |
| [09] | Eq. 12 | 본문의 `r = MSB(a−b)` 서술과 Eq. 12의 부호가 모순. 그대로 옮기면 **최솟값이 아니라 최댓값**을 찾음 |
| [04] | Table 1 | Pauli $Y$ 의 (2,2) 성분이 `1` 로 인쇄됨 → `0` 이 맞음 |
| [04] | p.17 | "$p=3$ 이면 0.4%" → 0.4%는 $p=2$ 의 값 ($1/16^3 = 0.024\%$) |
| [04] | Theorem 6 | `acc/N` 로 서술되나 Eq. (3.1)·RTL은 $2/N$. **Eq. (3.1) 기준**으로 읽을 것 |
| [06] | Eq. 6 | $l$ 과 $(i,j)$ 의 역할이 뒤바뀌어 인쇄됨. §IV-B 코드가 정답지 |
| [07] | Fig. 8 | (b)와 (c) 그림이 캡션과 **뒤바뀌어** 배치됨 |
| [08] | 기호 | 논문의 $D$ = 우리 9장 문서의 $N$. 논문의 $N$ 은 전혀 다른 변수 (해설본 0절에 대조표) |

---

## 5. 우리 코드에 대한 발견

해설본을 쓰는 과정에서 [`project1/hardware/`](../../project1/hardware/) 의 Verilog를 논문과 대조해 확인한 사항입니다. 근거는 각 해설본의 「이 프로젝트에 어떻게 쓰이나」 절에 있습니다.

**고칠 것**

- **확산 시프트에서 1비트가 새고 있습니다** (`grover_ip.v`, `grover_min_ip.v` 공통). `mean = sum>>>NBITS; two_mean = mean<<<1` 은 LSB를 항상 0으로 만들어 **`FRAC`을 1 줄인 것과 등가**입니다($\ell_2$ 평균 1.94배 악화). → `two_mean = sum >>> (NBITS-1)` 한 줄로, 자원 증가 없이 회수됩니다. [05]

**고치지 말 것**

- 현재의 **평균 중심 반사**(`two_mean - amp[i]`)는 [06] 논문의 $H_1DH_1$ 경로보다 **우수합니다** (곱셈 0개 vs 아다마르 $2(N{+}1)$ 클럭). 논문을 따라 바꾸지 마세요. [06]
- `R_ITERS=1` 은 [05] Eq.(9)의 반올림 공식($N{=}4$에서 $k{=}2$ → 성공확률 0.25)보다 **옳습니다**. 우리 값이 성공확률 1.0. [05]

**알아 둘 것**

- `grover_min_ip.v` 의 `T_INIT=16'sh7FFF` 는 첫 라운드에 **전부**를 마킹해 $O = -I$ 가 되므로, `R_GROVER=2` 회가 측정 분포를 바꾸지 못합니다. DHA상 버그는 아니지만(첫 라운드는 원래 무작위 추출) 처방은 BBHT입니다. [08][09]
- 우리 Q1.16 표현은 `INIT_AMP` $= 2^{16-n/2}$ 이고 (현재 상수 32768·23170이 정확히 이 식), $n{=}32$ 에서 1 LSB로 죽습니다. 즉 **정밀도 천장이 메모리 천장보다 먼저** 옵니다. [07]
- [04]의 6큐비트 한계는 Grover의 한계가 아니라 "모든 루프를 1클럭에 펼친" 아키텍처 선택의 결과입니다 (2→6큐비트에서 FF는 27% 증가, LUT는 28배 폭발). 상태벡터를 BRAM에 두고 순차 누산하면 8큐비트도 60µs 수준입니다. [04]
- $n \approx \log_2(\text{메모리})$ 가 이 분야의 철칙입니다 — [07]의 32큐비트 천장은 $2^{32} \times 4\,\text{B} = 16\,\text{GiB}$ 로 정확히 떨어지고, GPU·Qiskit·슈퍼컴퓨터가 전부 이 식을 따릅니다. [07]

---

## 6. 문서 만드는 법

Markdown이 원본이고 PDF는 파생본입니다. `.md` 를 고친 뒤 다시 만들려면:

```bash
python3 ~/.claude/skills/convert-md-pdf/convert.py documents/papers_ko/*.md
```

수식은 pandoc + xelatex로 렌더링됩니다. 표 안에서 케트를 쓸 때는 `$\lvert 0\rangle$` 또는 `$\|0\rangle$` 를 쓰세요 (표 밖에서는 `\|` 가 노름 ‖로 렌더링되므로 `\lvert` 를 쓸 것).
