# 실험 07. Lookahead-Shots를 줄인 이유: 8 → 6 → 4 → 3 shots

> [← 실험 06 checkpoint memory packing](06_checkpoint_memory_packing.md) · [index](index.md) · [실험 08 1 PE profiling과 4 PEs →](08_one_pe_profiling_and_four_pes.md)

---

| 정한 것 | 근거의 축 |
|---|---|
| Lookahead를 8 → 4 → 3 shots로 줄임, a Checkpoint-Capacity of 3 | board 250쌍 · RTL simulation |

## board에서 본 것: executed iterations가 가장 적다고 cycle이 가장 적지는 않다

같은 250쌍 workload(seed 50)를 board에서 돌린 결과입니다. PE는 한 벌(1 PE)입니다.

| 설계 | executed iterations | cycles | Restart mode 대비 |
|---|---:|---:|---:|
| Restart mode | 14,883 | 20,229,755 | 1.000× |
| a Checkpoint-Capacity of 4 and 8-shot Lookahead | 4,134 | 13,824,806 | 1.463× |
| a Checkpoint-Capacity of 4 and 6-shot Lookahead | 4,154 | 9,154,981 | 2.210× |
| a Checkpoint-Capacity of 4 and 4-shot Lookahead | 4,247 | 7,796,908 | 2.595× |

Lookahead를 6 shots에서 4 shots로 줄이자 executed iterations는 2.24% 늘었지만 cycle은 14.83% 줄었습니다. Lookahead-Shots가 많으면 DP가 풀 범위가 커져
풀이가 오래 걸리고, 그동안 datapath가 기다립니다(`policy_stall`). 8-shot Lookahead는 iteration을 조금 덜 쓰는 대신
policy stall을 크게 물어 총 cycle에서 손해를 봤습니다. 이것으로 a Checkpoint-Capacity of 4 and 4-shot Lookahead를 당시의 실용적 knee point로
정했습니다. search한 모든 Checkpoint-Capacity · Lookahead-Shots 조합을 board에서 잰 global optimum이라고 주장하지는 않습니다.

software design space search(24 points)에서 고른 point들입니다. executed iterations와 policy 일감만 보고 knee point를
설명하는 데 쓰고, benchmark하지 않은 point의 추정 cycle은 쓰지 않습니다.

| point | executed iterations / run | policy operations / shot |
|---|---:|---:|
| a Checkpoint-Capacity of 4 and 3-shot Lookahead | 147.665 | 75.0 |
| a Checkpoint-Capacity of 4 and 4-shot Lookahead | 134.821 | 157.9 |
| a Checkpoint-Capacity of 4 and 5-shot Lookahead | 127.883 | 303.1 |
| a Checkpoint-Capacity of 4 and 6-shot Lookahead | 123.149 | 547.3 |
| a Checkpoint-Capacity of 3 and 3-shot Lookahead | 152.652 | 38.4 |
| a Checkpoint-Capacity of 3 and 4-shot Lookahead | 142.738 | 71.6 |
| a Checkpoint-Capacity of 3 and 5-shot Lookahead | 138.048 | 123.9 |

## 4 PEs 뒤의 재조정: a Checkpoint-Capacity of 3 and 3-shot Lookahead

Grover iteration 한 번이 4 PEs로 빨라지면 executed iteration 하나의 값어치가 떨어지고, 상대적으로 policy 비용이 커집니다.
a Checkpoint-Capacity of 3 and 3-shot Lookahead는 a Checkpoint-Capacity of 4 and 4-shot Lookahead보다 executed iterations는 늘지만 policy 일감이 약 76% 줄어서 실제 RTL로 비교했습니다.

| 항목 (RTL, 6 cases) | Stage 3 | Stage 4 | 변화 |
|---|---:|---:|---:|
| total cycles | 301,404 | 288,164 | −4.4% |
| enumeration executed iterations | 317 | 332 | +4.7% |
| policy actions | 16,266 | 4,898 | −69.9% |
| policy cycles | 76,774 | 34,184 | −55.5% |
| policy stall | 15,160 | 4,114 | −72.9% |

Measurement Unit을 Two-Level Select까지 줄인 뒤에는 policy를 숨길 시간이 더 짧아지므로 a Checkpoint-Capacity of 3 and 4-shot Lookahead와 다시 겨뤘습니다.

| 항목 (RTL, enumeration 전체) | a Checkpoint-Capacity of 3, 3-shot Lookahead and Two-Level Select | a Checkpoint-Capacity of 3, 4-shot Lookahead and Two-Level Select |
|---|---:|---:|
| total cycles | 192,874 | 201,460 (+4.45%) |
| executed iterations | 544 | 540 |
| policy 일감 | 31,481 | 53,178 |
| policy만 드러난 cycles | 5,817 | 15,745 |

4-shot Lookahead가 아낀 4 iterations는 4 PEs에서 약 1,056 cycles인데 드러난 policy 시간은 약 9,928 cycles 늘었습니다.
그래서 a Checkpoint-Capacity of 3 and 3-shot Lookahead로 굳혔습니다. 목표는 policy 일감을 최소로 하는 것이 아니라, datapath와 measurement가 숨겨 줄 수 있는
범위 안에서 iteration을 줄여 총 cycle을 최소로 하는 것입니다.

## Checkpoint-Capacity와 Lookahead-Shots를 따로 떼어 본 실험

같은 공용 source RTL에서 1 PE · Measurement Microarchitecture 최적화 없이(Single-Row Build · Linear Select) Checkpoint-Capacity와 Lookahead-Shots만 바꿔 250 workloads씩 돌린
RTL cycle입니다([kh_isolated_e1](../../hardware_bram/results/2026-09-09_kh_isolated_e1/evidence.md)).
새로 돌린 500 simulations는 모두 통과했고 의미 불일치는 0이었습니다.

| number of solutions | Stage 2 | a Checkpoint-Capacity of 3, 4-shot Lookahead and 1 PE | a Checkpoint-Capacity of 3, 3-shot Lookahead and 1 PE | speedup (Stage 2 → a Checkpoint-Capacity of 3, 3-shot Lookahead) |
|---|---:|---:|---:|---:|
| 1 | 3,671,037 | 3,677,142 | 3,637,074 | 1.0093× |
| 4 | 2,122,688 | 2,105,863 | 2,080,916 | 1.0201× |
| 16 | 1,434,286 | 1,429,509 | 1,381,988 | 1.0378× |
| 64 | 912,322 | 910,075 | 856,569 | 1.0651× |
| 256 | 695,965 | 695,512 | 640,062 | 1.0873× |
| sum | 8,836,298 | 8,818,101 | 8,596,609 | 1.0279× |

Checkpoint-Capacity만 줄이면 cycle이 0.21% 줄고, 이어서 Lookahead-Shots를 줄이면 2.51%가 더 줄었습니다(speedup으로는 1.0258×,
다른 장에서 "Lookahead-Shots 몫 2.58%"로 적는 값). 이 실험은 workload마다 reset해 매 run이 memo table 청소를 치르므로, memo table이 큰 a Checkpoint-Capacity of 4 and 4-shot Lookahead 쪽이 그만큼 불리하게 잡혔을 수 있습니다. board와 같은 조건(연달아 실행)에서는 a Checkpoint-Capacity of 3 and 3-shot Lookahead로 줄인 것이 1 PE에서 오히려 느리고 4 PEs에서 -3.7%입니다([실험 18 「단계별 손익」](18_six_stage_ablation_comparison.md#단계별-손익)). 비싼 쪽은 저장 공간이 아니라 결정 비용입니다. solution이 많을수록 3-shot Lookahead의 이득이 커지는 경향이 보이지만 원인 counter를 따로 재지 않아
mechanism은 단정하지 않습니다. 이 표는 RTL cycle이라 위의 board 250쌍 cycle과 맞대지 않습니다.
