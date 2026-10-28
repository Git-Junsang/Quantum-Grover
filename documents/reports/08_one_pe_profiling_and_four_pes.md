# 실험 08. 1 PE profiling과 4 PEs

> [← 실험 07 Lookahead-Shots를 줄인 이유: 8 → 6 → 4 → 3 shots](07_lookahead_shots_reduction.md) · [index](index.md) · [실험 09 measurement 병목과 Dual-Row Build · Two-Level Select →](09_measurement_bottleneck_and_microarchitecture.md)

---

| 정한 것 | 근거의 축 |
|---|---|
| Grover iteration 안에서 4 rows를 병렬로 처리(4 PEs) | RTL cycle 분해 |

Checkpoint mode의 executed iteration 한 번을 RTL simulation에서 cycle 단위로 나눴습니다(1 PE).

| 단계 | cycles / executed iteration | 무엇 |
|---|---:|---|
| Pass 1 | 516 | oracle + global sum streaming |
| P1DRN | 1 | Pass 1 pipeline drain |
| Mean | 1 | global mean 확정 |
| Pass 2 | 515 | diffusion operator + 되쓰기 |
| sum | 1,033 | |
| Init (별도) | 514 | uniform superposition initialization |

1,033 cycles 중 1,031 cycles이 512 rows streaming에 몰려 있습니다. 같은 iteration의 서로 다른 row를 여러
PE가 동시에 처리하면 크게 줄일 수 있다는 뜻이고, 이것이 4 PEs의 근거입니다. 4 PEs는 독립된 search
네 개가 아니라, 한 번의 executed iteration을 32-lane PE 네 벌이 4 rows씩 나눠 처리하는 구조입니다. BBHT의
request 열, enumeration 순서, 결과 의미, policy의 논리는 그대로입니다([9장 9.4절](../design_references/09_iteration_datapath_and_number_of_pes.md#94-4-pes의-4-rows-병렬-처리)).

4 PEs가 policy stall을 새로 만든다는 가설도 확인했습니다. 같은 workload에서 1 PE와 4 PEs의 policy cycles은
112,855로 같았고 policy stall도 38,540 대 38,569로 거의 같았습니다. 4 PEs가 Grover 본체를 줄이자 고정된
policy · checkpoint 비용의 상대 비중이 커진 것이지, 4 PEs가 stall을 만든 것이 아닙니다. 이것이 [실험 07](07_lookahead_shots_reduction.md)의
a Checkpoint-Capacity of 3 and 3-shot Lookahead 재조정으로 이어졌습니다.
