# 14-qubit BBHT emulator — 비교·참고 논문

이 문서는 우리 구조(14 qubits · multi-solution BBHT · a Checkpoint-Capacity of 3과 3-shot Lookahead · 4 PEs · Dual-Row Build와 Two-Level Select,
BRAM Variant와 DRAM Variant)를 발표나 보고서에서 **어느 논문과 맞대고, 어느 논문을 근거로 삼을지**
정리한 목록입니다. 2026-10-05 작성.

같은 directory의 [references.md](references.md) 는 citation graph로 모은 137편을 **제목만으로**
분류한 넓은 목록이고, 이 문서는 그중 일부와 새로 찾은 논문을 **우리 설계 요소별로 골라 붙인**
좁은 목록입니다. 둘은 겹치는 논문이 있으며, 겹치는 것은 표에 "references.md" 로 표시했습니다.

**확인 수준.** 아래 서지(저자 · 학회/저널 · 연도 · DOI/arXiv)는 출판사 페이지 · arXiv 초록 ·
학술 DB 로 대조했습니다. 논문 내용 요약 가운데 **본문까지 읽고 확인한 것은 우리 연구실
4편([04]~[07], 한국어 해설본이 있는 것)뿐**이고, 나머지는 초록과 공개 요약 기준입니다.
수치를 발표에 옮기기 전에 원문 해당 쪽을 직접 확인하십시오.

---

## 1. 우리 구조를 한 줄씩 — 무엇과 비교할 수 있나

| 우리 설계 요소 | 무엇을 하나 | 비교·근거 논문 (2절 이하 번호) |
|---|---|---|
| BBHT 외곽 loop | number of solutions를 모른 채 number of iterations를 무작위로 뽑고, 실패하면 sampling range를 키움 | A1 · A2 · A3 (원리), A5 · A6 · A7 (대안) |
| multi-solution · 네 predicate | `<` `>` `=` range로 solution 집합을 정의 | A4 (minimum search), B6 · B7 (multi-pattern Grover emulation) |
| 14 qubits · BRAM state vector | 16,384 states의 amplitude를 chip 안 BRAM 에 둠 | B8 (16 qubits BRAM, 가장 가까운 규모), B9 · B10 (우리 연구실 선행), B5 (DDR4 로 32 qubits) |
| Q1.22 fixed-point | amplitude 23-bit | D1 (fraction bits 공식), B8 (20-bit fixed-point) |
| oracle + diffusion operator를 gate 없이 직접 계산 | "emulator" 방식 | C1 (emulation 개념), B9 (Grover 전용 O(number of states) diffusion operator) |
| a Checkpoint-Capacity of 3 | 실패 시 처음부터가 아니라 가까운 저장 state에서 차이만큼만 더 돌림 | E1 · E2 · E4 (저장-재계산 맞교환) |
| Policy Engine 3-shot Lookahead | 앞으로 올 request 3개를 미리 보고 남길 checkpoint를 DP 로 고름 | E2 (online checkpoint), E5 (미래를 아는 최적 교체) |
| DRAM Variant | iteration마다의 amplitude를 전부 DRAM 에 두고 필요할 때 burst로 가져옴 | E3 (memory 두 층 checkpoint), B5 (DDR streaming) |
| Two-Level Select | 512 rows의 prefix sum을 16 groups의 끝점 → group 안 32 rows 두 단으로 search | F1 (tree 기반 weighted sampling) |
| Measurement PRNG | xorshift64 | F2 |
| software 비교군 | Qiskit Aer · NumPy state vector · ORCA 1 core | C2 · C3 |

우리 구조의 정확한 수치는 이 문서에 다시 적지 않습니다. 성능은
[1장](../../design_references/01_project_overview.md), checkpoint는
[11장](../../design_references/11_checkpoint_and_policy_engine.md), measurement는
[10장](../../design_references/10_measurement_unit_and_microarchitecture.md), DRAM Variant는
[21장](../../design_references/21_dram_variant.md), precision 선택 근거는
[실험 02](../../reports/02_amplitude_precision.md)를 보십시오.

---

## 2. A — BBHT 와 그 주변 algorithm (근거)

우리 외곽 loop의 이론 근거입니다. 발표에서 "왜 number of iterations를 무작위로 뽑는가" 를 설명할 때
A1 하나로 충분하고, 나머지는 질문 대비용입니다.

| # | 논문 | 서지 | 우리와의 관계 |
|:-:|---|---|---|
| A1 | **Tight bounds on quantum searching** — Boyer, Brassard, Høyer, Tapp | Fortschritte der Physik 46(4-5), 493–505, 1998 · [arXiv:quant-ph/9605034](https://arxiv.org/abs/quant-ph/9605034) | **BBHT 원논문.** number of solutions를 모를 때 number of iterations의 상한인 sampling range를 growth factor 1.2(우리 implementation constant는 3장)씩 키우며 그 안에서 무작위로 뽑는 방법과, 기대 iteration 횟수가 여전히 √(number of states / number of solutions) 규모임을 보입니다. 우리 `REQUESTED_ITERATIONS` · `trial_count` 가 이 논문의 절차입니다 |
| A2 | **Quantum counting** — Brassard, Høyer, Tapp | ICALP 1998, LNCS 1443, 820–831 · [arXiv:quant-ph/9805082](https://arxiv.org/abs/quant-ph/9805082) | number of solutions를 먼저 **추정**한 뒤 정확한 number of iterations로 한 번에 찾는 대안. 우리는 추정 단계 없이 BBHT 를 택했으니 "왜 counting 을 안 썼나" 질문의 상대 |
| A3 | **Quantum amplitude amplification and estimation** — Brassard, Høyer, Mosca, Tapp | Contemporary Mathematics 305, 53–74, 2002 · [arXiv:quant-ph/0005055](https://arxiv.org/abs/quant-ph/0005055) | A1 · A2 를 amplitude amplification이라는 틀로 일반화한 정리판. 용어("amplitude amplification")를 인용할 때 쓰는 표준 출처 |
| A4 | **A quantum algorithm for finding the minimum** — Dürr, Høyer | 1996 · [arXiv:quant-ph/9607014](https://arxiv.org/abs/quant-ph/9607014) | BBHT 를 subroutine으로 되풀이해 호출하며 minimum을 찾는 algorithm. 우리 `LT` predicate(threshold보다 작은 것 찾기)를 되풀이하면 이것이 됩니다. 해설서 [14장](../14_multiple_solutions_and_minimum_search.md) 과 해설본 [09](papers_ko/09_quantum_minimum_searching_aud_iot_ko.md) 이 이 계열의 응용 |
| A5 | **Fixed-point quantum search with an optimal number of queries** — Yoder, Low, Chuang | Phys. Rev. Lett. 113, 210501, 2014 · [arXiv:1409.3305](https://arxiv.org/abs/1409.3305) | number of solutions를 몰라도 iteration을 지나치게 해서 probability가 떨어지는 문제(soufflé problem)가 없는 fixed-point search. phase를 iteration마다 바꿔야 해서 우리 diffusion operator circuit과 구조가 다릅니다. "BBHT 말고 다른 해법" 질문의 상대 |
| A6 | **Critically damped quantum search** — Mizel | Phys. Rev. Lett. 102, 150501, 2009 · [DOI](https://doi.org/10.1103/PhysRevLett.102.150501) | number of solutions를 모를 때의 또 다른 해법. 초록 기준으로 질의 수가 1.5× 늘어나는 대가로 number of solutions를 몰라도 된다고 합니다 |
| A7 | **A quantum while loop for amplitude amplification** — Andrés-Martínez, Heunen | 2020 · [arXiv:2009.08832](https://arxiv.org/abs/2009.08832) | weak measurement로 state를 엿보며 성공할 때까지 반복하는 방식. BBHT 처럼 "멈출 때를 모르는" 문제를 다른 각도에서 풉니다 |
| A8 | **A bi-directional multi-solution scalable Grover search algorithm** — Konar, Hafeez, Aggarwal | Quantum Information Processing 게재 확정(arXiv 기재) · [arXiv:2404.15616](https://arxiv.org/abs/2404.15616) | solution이 여럿인 search를 state space를 쪼개 양방향으로 푸는 최근 연구. Qiskit 으로 2~20 qubits를 benchmark합니다. 우리 enumeration mode(`*_ENUM`)와 목적이 겹칩니다 |

> 참고: Grover 원논문(STOC 1996, PRL 79, 325, 1997)과 해설서 [9장](../09_grover_algorithm.md) 이 출발점입니다.

---

## 3. B — FPGA quantum emulator (규모·구조 비교)

발표의 "관련 연구" 표에 들어갈 자리입니다. 비교 축은 **number of qubits · state vector를 어디 두나 ·
수 형식 · chip** 넷이 공정합니다. 실행 시간은 algorithm · clock · benchmark interval이 논문마다 달라서
speedup으로 맞대지 마십시오(4절).

| # | 논문 | 서지 | 규모 · 구조 (확인 수준) |
|:-:|---|---|---|
| B1 | **FPGA-based high-speed emulator of quantum computing** — Fujishima | IEEE FPT 2003, 21–26 · [DOI](https://doi.org/10.1109/FPT.2003.1275727) | FPGA emulator의 초기 연구 (초록) |
| B2 | **FPGA emulation of quantum circuits** — Khalid, Zilic, Radecka | IEEE ICCD 2004, 310–315 | circuit model emulation과 **필요 precision** 문제를 처음 정면으로 다룬 고전. precision 논의의 역사적 출발점 (초록) |
| B3 | **An FPGA-based quantum computing emulation framework based on serial-parallel architecture** — Lee 외 | Int. J. Reconfigurable Computing 2016, 5718124 · [DOI](https://doi.org/10.1155/2016/5718124) | serial-parallel 혼합 구조로 resource와 속도를 맞바꿈. 우리 32 lanes × 512 rows 직렬 구조와 같은 발상 (초록). references.md |
| B4 | **Scaling reconfigurable emulation of quantum algorithms at high precision and high throughput** — Mahmud, El-Araby | Quantum Engineering 1(2), 2019 · [DOI](https://doi.org/10.1002/que2.19) | circuit에서 **kernel 연산을 뽑아 모든 state에 되풀이해 적용**하는 model. 우리가 Grover iteration 한 번을 512 rows stream으로 흘리는 것과 같은 계열 (초록) |
| B5 | **Towards complete and scalable emulation of quantum algorithms on high-performance reconfigurable computers** — El-Araby 외 | IEEE Trans. Computers 72(8), 2350–2364, 2023 · [DOI](https://doi.org/10.1109/TC.2023.3248276) | **32 qubits, state vector를 board DDR4 에 두고 streaming.** 천장이 logic가 아니라 memory라는 것을 수치로 보임. 우리 DRAM Variant의 대조군 (본문 확인, 해설본 [07](papers_ko/07_towards_complete_scalable_emulation_hprc_ko.md)) |
| B6 | **Emulating multi-pattern quantum Grover's search on a high-performance reconfigurable computer** — Mahmud, Haase-Divine, Srimoungchanh, Blankenau, Kuhnke, El-Araby | SC'19 연구 poster, 2019 | **solution이 여럿인 Grover 를 FPGA 로 emulation**한 가장 직접적인 선행. 32-bit floating-point, 다중 FPGA (poster 초록) |
| B7 | **Modifying quantum Grover's algorithm for dynamic multi-pattern search on reconfigurable hardware** — Mahmud 외 | J. Computational Electronics 2020 · [DOI](https://doi.org/10.1007/s10825-020-01489-3) | B6 의 저널판 계열. search pattern을 실행 중에 바꾸는 점이 우리 "predicate·threshold를 CSR 로 runtime에 바꾼다" 와 비교됩니다 (서지만). references.md |
| B8 | **AMARETTO: Enabling efficient quantum algorithm emulation on low-tier FPGAs** — Conti, Volpe, Graziano, Zamboni, Turvani | IEEE ICECS 2024 · [DOI](https://doi.org/10.1109/ICECS61496.2024.10848965) · [arXiv:2411.09320](https://arxiv.org/abs/2411.09320) | **규모가 우리와 가장 가깝습니다.** AMD Kria KV260 에서 16 qubits, amplitude를 BRAM 에 두고 2× clock으로 pumping해 clock당 amplitude 둘을 읽고 씀, 20-bit fixed-point(integer bits 2 · fraction bits 18), RAM 이 100% 로 병목. universal gate(OpenQASM) emulator라 Grover 전용 최적화는 없음 (arXiv 본문 HTML 확인). references.md, PDF 보유 |
| B9 | **Developing a Grover's quantum algorithm emulator on standalone FPGAs** — Choi, W. Lee (중앙대) | AIMS Mathematics 9(11), 30939–30971, 2024 · [DOI](https://doi.org/10.3934/math.20241493) | 우리 연구실 선행. Grover diffusion operator를 O(number of states) 로 줄이고 RISC-V(ORCA) SoC 에 붙인 standalone emulator. Arty A7 4 qubits, Kintex UltraScale+ 6 qubits. **우리 14-qubit revision은 이 계보의 다음 단계**이므로 "얼마나 확장했나" 를 보일 baseline (본문 확인, 해설본 [04](papers_ko/04_developing_grover_emulator_standalone_fpga_ko.md)) |
| B10 | **Standalone FPGA-based QAOA emulator for weighted-MaxCut on embedded devices** — Choi, K. Lee, J.-J. Lee, W. Lee (중앙대) | 2025 · [arXiv:2502.11316](https://arxiv.org/abs/2502.11316) | 같은 연구실의 QAOA emulator. state vector를 FF 에 올려 9 qubits에서 막힘. "BRAM 으로 옮겨야 qubit가 늘어난다" 는 우리 선택의 반례 근거 (본문 확인, 해설본 [06](papers_ko/06_standalone_fpga_qaoa_emulator_ko.md)) |
| B11 | **Optimising iteration scheduling for full-state vector simulation of quantum circuits on FPGAs** — Moawad, Brown, Steijl, Vanderbauwhede | 2024 · [arXiv:2411.18354](https://arxiv.org/abs/2411.18354) | control qubit 조건으로 필요한 amplitude 쌍만 iteration하도록 schedule을 줄임. "필요 없는 iteration을 안 한다" 는 점에서 checkpoint와 목적이 같고 수단이 다름 (초록) |

이 밖에 references.md B 절에 FPGA emulator가 60편 넘게 있습니다. 제목만 보고 분류한 것이라
위 표에 올리지 않았습니다.

---

## 4. C — software simulator (비교군)

| # | 논문 | 서지 | 우리와의 관계 |
|:-:|---|---|---|
| C1 | **High performance emulation of quantum circuits** — Häner, Steiger, Smelyanskiy, Troyer | SC 2016 · [DOI](https://doi.org/10.1109/SC.2016.73) · [arXiv:1604.06460](https://arxiv.org/abs/1604.06460) | **"simulator" 와 "emulator" 를 구분한 출처.** gate를 하나씩 흉내 내지 않고 algorithm을 높은 수준에서 직접 계산하면 훨씬 빠르다는 주장. 우리가 oracle · diffusion operator를 gate 없이 직접 계산하는 것을 "emulator" 라고 부르는 근거로 인용하기 좋습니다. references.md, PDF 보유 |
| C2 | **QuEST and high performance simulation of quantum computers** — Jones, Brown, Bush, Benjamin | Scientific Reports 9, 10736, 2019 · [DOI](https://doi.org/10.1038/s41598-019-47174-9) | 대표적인 CPU/GPU state vector simulator. B5 가 비교군으로 씁니다 |
| C3 | **Quantum computing with Qiskit** — Javadi-Abhari 외 | 2024 · [arXiv:2405.08810](https://arxiv.org/abs/2405.08810) | 우리 비교군 Qiskit Aer 의 공식 인용처 |

---

## 5. D — fixed-point precision

| # | 논문 | 서지 | 우리와의 관계 |
|:-:|---|---|---|
| D1 | **Precision-aware fixed-point emulation of Grover's algorithm** — Choi, K. Lee, J. Choi, Jung, W. Lee (중앙대) | Quantum Information Processing 25:214, 2026 · [DOI](https://doi.org/10.1007/s11128-026-05235-9) | Grover amplitude를 두 값(solution/non-solution)으로 보는 model로 truncation error를 유도하고, 원하는 error에 필요한 **최소 fraction bits**를 닫힌 식으로 줍니다. qubit 하나당 1 bit씩 더 필요하다는 결론이 우리 14 qubits · 22 fraction bits 선택과 직접 맞닿습니다 (본문 확인, 해설본 [05](papers_ko/05_precision_aware_fixed_point_grover_ko.md)) |
| D1' | **Asymptotic error bounds and fractional-bit design for fixed-point Grover's quantum algorithm emulation** — Choi, K. Lee, J. Choi, W. Lee | 2025 · [arXiv:2504.01430](https://arxiv.org/abs/2504.01430) | 같은 저자들의 arXiv 판으로, 제목과 저자 구성이 D1 과 조금 다릅니다. 같은 연구의 이전 판으로 보이나 판 사이 차이는 대조하지 않았습니다. 인용은 저널판 D1 으로 하십시오 |

---

## 6. E — checkpoint와 Policy Engine (가장 비교 대상이 귀한 부분)

**미리 말씀드릴 점.** BBHT 의 실패한 shot 사이에서 **state vector를 저장해 두었다가 이어 돌리는**
emulator는 이번 조사에서 찾지 못했습니다. 실제 quantum computer에서는 measurement를 하면 state가 무너지고
복제도 할 수 없으니 이런 재사용이 원리적으로 불가능하고, 그래서 quantum 쪽 문헌에는 이 문제
자체가 없습니다. classical emulator만 할 수 있는 최적화라는 점이 오히려 우리 기여를 설명하는
문장이 됩니다.

가장 가까운 이론은 **수치해석의 checkpoint 문제**입니다. 긴 시간 step 계산에서 memory에
state 몇 개만 남겨 두고, 나중에 필요한 시점의 state를 가장 가까운 저장점에서 다시 계산해
얻는 문제로, 우리 "Checkpoint-Capacity만큼의 checkpoint slot에 어느 iteration의 state를 남기고 어디서 이어 돌릴까" 와 같은 모양입니다.
다만 그쪽은 **역순**(마지막 step부터 처음으로)으로 state가 필요한 문제이고, 우리는 BBHT random number가
정하는 **순서 없는** request 열이라는 점이 다릅니다. 비교할 때 이 차이를 꼭 짚으십시오.

| # | 논문 | 서지 | 우리와의 관계 |
|:-:|---|---|---|
| E1 | **Algorithm 799: revolve — an implementation of checkpointing for the reverse or adjoint mode of computational differentiation** — Griewank, Walther | ACM TOMS 26(1), 19–45, 2000 · [DOI](https://doi.org/10.1145/347837.347846) | 저장점 개수와 재계산 횟수의 관계를 이항계수로 밝힌 고전(binomial checkpointing). **Checkpoint-Capacity를 얼마로 둘 때 재계산이 얼마나 줄어드는가** 를 이론으로 다루는 표준 출처 |
| E2 | **New algorithms for optimal online checkpointing** — Stumm, Walther | SIAM J. Sci. Comput. 32(2), 836–854, 2010 · [DOI](https://doi.org/10.1137/080742439) | 전체 step 수를 **미리 모르는** online checkpoint. BBHT 도 몇 번 실패할지 모르므로 E1 보다 우리 상황에 가깝습니다 |
| E3 | **Optimal multistage algorithm for adjoint computation** — Aupy, Herrmann, Hovland, Robert | SIAM J. Sci. Comput. 38(3), C232–C255, 2016 · [DOI](https://doi.org/10.1137/15M1019222) | 저장소가 **memory와 disk 두 층**이고 읽기·쓰기 비용이 있을 때의 최적 checkpoint. 우리 BRAM Variant와 DRAM Variant(iteration마다의 state를 전부 느리고 큰 memory에)의 맞교환을 이론 틀로 설명할 때 씁니다 |
| E4 | **Training deep nets with sublinear memory cost** — Chen, Xu, Zhang, Guestrin | 2016 · [arXiv:1604.06174](https://arxiv.org/abs/1604.06174) | deep learning의 gradient checkpointing. 같은 저장-재계산 맞교환이 다른 분야에서도 표준 기법이라는 것을 보여 주는 친숙한 예 |
| E5 | **A study of replacement algorithms for a virtual-storage computer** — Belady | IBM Systems Journal 5(2), 78–101, 1966 · [DOI](https://doi.org/10.1147/sj.52.0078) | 미래 request를 알 때 무엇을 버릴지의 최적해(Belady 의 MIN). 우리 3-shot Lookahead는 Iteration-Count Predictor로 **앞으로 올 request 3개를 미리 알고** 남길 checkpoint를 고르므로, "유한한 Lookahead의 Belady" 로 설명할 수 있습니다 |

이 표의 서지(권·호·쪽)는 학술 DB 로 확인했고 DOI 는 출판사 표기를 따랐습니다. 초록 이상은
읽지 않았으니, 우리 문제와의 대응을 발표에서 주장하려면 E1 · E3 의 문제 정의 절을 먼저
읽어 보십시오.

---

## 7. F — Measurement Unit

| # | 논문 | 서지 | 우리와의 관계 |
|:-:|---|---|---|
| F1 | **An efficient method for weighted sampling without replacement** — Wong, Easton | SIAM J. Computing 9(1), 111–113, 1980 · [DOI](https://doi.org/10.1137/0209009) | weight를 tree에 쌓아 두고 항목 수의 log에 비례하는 비교로 sample을 뽑는 방법. Two-Level Select는 이것을 **두 층**(16 groups → 32 rows)으로 고정한 hardware 구현이라고 설명할 수 있습니다. amplitude square로 prefix sum을 만들고 random number를 넘는 첫 칸을 찾는 것 자체는 inverse transform sampling이라는 표준 기법입니다 |
| F2 | **Xorshift RNGs** — Marsaglia | J. Statistical Software 8(14), 2003 · [DOI](https://doi.org/10.18637/jss.v008.i14) | 우리 Measurement PRNG인 xorshift64 의 원 출처 |

---

## 8. 비교할 때 지킬 것

1. **성능 speedup은 축을 밝혀서만.** RTL cycle · board wall-clock time · software 대비, 세 축의
   source of truth는 [기술문서 1장 1.5절](../../design_references/01_project_overview.md#15-성능-지표와-인용-기준) 에 있습니다. 다른 논문의 실행 시간과 우리 값을
   나란히 놓을 때는 algorithm(범용 gate vs Grover 전용) · number of qubits · measurement 포함 여부를 표에
   같이 적고, speedup은 만들지 않는 편이 안전합니다.
2. **ORCA 1 core 대비 speedup**에는 "32 lanes 병렬과 clock 2× 때문이지 algorithm 우위가 아니다" 는
   단서를 항상 붙입니다. classical linear scan과는 속도를 비교하지 않습니다(emulation이 더 느립니다).
3. **예상 질문 — "Grover 는 amplitude가 두 값뿐인데 왜 state vector 전체를 계산하나?"** D1 이 바로
   그 두 값 model을 씁니다. 해석적으로 풀면 1만 6천 개를 저장할 필요가 없다는 지적이 나올 수
   있으니, 우리 목적(fixed-point hardware에서 실제 amplitude 연산 · measurement · error를 그대로 재현하고
   verification)과 한계를 미리 답으로 준비해 두십시오.
4. **checkpoint는 emulator 전용 최적화**입니다(6절 첫 문단). 실제 quantum hardware로 옮겨지는
   기법처럼 말하지 마십시오.
5. 해설서 [15장](../15_paper_map_and_design_decisions.md) 에 우리 연구실 논문과 설계
   결정의 대응표가 이미 있습니다. 새 논문을 근거로 설계 결정을 설명할 때는 그 표와 어긋나지
   않는지 보십시오.

---

## 9. 조원별로 먼저 읽을 것

| 맡은 부분 | 먼저 | 다음 |
|---|---|---|
| 발표 "관련 연구" 표 | B9 → B8 → B5 | B6 · B7 · B10 |
| algorithm 설명 | A1 | A2 · A5 (질문 대비) |
| checkpoint · policy | E1 → E2 | E3 (DRAM Variant 비교) · E5 |
| precision | D1 | B2 · B8 |
| measurement | F1 | F2 |

PDF 를 받으면 같은 directory의 기존 분류(`1.`~`5.` 하위 directory)에 맞춰 넣고, 이 문서 표의 해당
줄에 "PDF 보유" 를 적어 주십시오.
