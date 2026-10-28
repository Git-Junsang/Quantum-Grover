# 11장. checkpoint와 Policy Engine

> [← 10장 Measurement Unit과 Dual-Row Build · Two-Level Select](10_measurement_unit_and_microarchitecture.md) · [index](index.md) · [12장 Accelerator Core port 계약 →](12_accelerator_core_port_contract.md)

---

checkpoint는 Six-Stage Ablation에서 cycle을 56.63% 줄여 가장 큰 개선 효과를 보였습니다.
감소 폭은 나머지 다섯 단계의 효과를 합친 것보다 큽니다.

---

## 11.1 state 재사용 원리

BBHT는 실패하면 sampling range를 키워 다시 뽑습니다([3장 3.3절](03_grover_and_bbht_algorithm.md)).
그런데 새로 뽑은 number of iterations가 직전 것보다 크면, 이미 돌려 둔 state에서 차이만큼만 더 돌리면
됩니다. 처음부터 다시 `S_INIT` 할 이유가 없습니다.

```
shot 1:  5 iterations   →  uniform superposition에서 5 iterations
shot 2:  12 iterations  →  shot 1의 5-iteration state에서 7 iterations만 더   (12 iterations가 아니라)
```

sampling range가 커지는 방향이라 새 number of iterations가 큰 경우가 잦고, 그래서 이득이 큽니다.

enumeration에서는 enumeration round를 넘어 재사용하면 안 됩니다. 결과 하나를 찾을 때마다 oracle의 solution
집합이 바뀌어 다른 search 문제가 되기 때문입니다([3장 3.5절](03_grover_and_bbht_algorithm.md)).

---

## 11.2 checkpoint 저장 구조

`grover_ckpt_meta`가 checkpoint 최대 3개(a Checkpoint-Capacity of 3)의 valid bit와 각 checkpoint가 몇 번째 iteration의 state인지를 들고,
정렬된 checkpoint 집합을 유지합니다.

checkpoint slot은 Checkpoint-Capacity와 무관하게 4벌입니다([6장 6.7절](06_data_representation_and_memory_map.md#67-memory-구조)).
`grover_ckpt_mem_interleaved_e4`가 4 PEs의 4 rows 동시 읽기에 맞춰 bank를 교차 배치합니다.

---

## 11.3 Checkpoint Planner와 Checkpoint Executor

`grover_ckpt_planner_pipe`(Checkpoint Planner)가 논리적인 계획(출발 checkpoint, 정렬된 새 checkpoint 집합)을
checkpoint slot 계획으로 바꿉니다. 규칙은 넷입니다.

- 출발점은 새 number of iterations 이하인 checkpoint 중 가장 가까운 것. 없으면 uniform superposition에서 시작
- 목적지(endpoint)는 반드시 만듭니다
- 중간 checkpoint는 request pool 안에서만 고르고, a Checkpoint-Capacity of 3에서는 최대 2개
- 기존 checkpoint는 Checkpoint-Capacity가 허락하는 한 최대한 남깁니다

`grover_ckpt_executor`(Checkpoint Executor)가 그 계획을 경계 sequence로 풀어 냅니다. metadata를 지우거나
확정하는 것은 안전한 경계에서만 하고, 한 segment의 경계를 넘을 때는 1 iteration짜리 out-of-place
bridge를 씁니다.

`grover_ckpt_segment_router`(Segment Router)의 segment 규약이 이것입니다.

```
Pass 1:  src → dst      (읽는 checkpoint slot과 쓰는 checkpoint slot이 다름)
Pass 2:  dst → dst      (제자리)
```

이 규약에 따라 전체 state memory를 한 벌 더 둘 필요가 없습니다. oracle 결과를 목적지
checkpoint slot에 바로 쓸 수 있는 이유도 여기에 있습니다
([9장 9.4절](09_iteration_datapath_and_number_of_pes.md)).

---

## 11.4 Policy Engine과 3-shot Lookahead

200T 실험의 Policy Scheduler 구상, 설정 기반 실행과 7-shot · 8-shot Lookahead의 Iteration-Count Predictor 전달 수정은
[실험 27](../reports/27_200t_parameter_automation.md)에 있습니다. 여기서는 기본 3-shot Lookahead policy를 설명합니다.
Seed-First Branch and Bound with Single-Action Exit(policy search mode 6)의 단일 후보 조기 반환과 아직 남은 다중 후보 latency는
[실험 28](../reports/28_policy_single_action_exit.md)에 기록했습니다.
같은 relaxed cost를 segment별로 병렬 계산하는 후속 변경과 verification 범위는
[실험 29](../reports/29_policy_per_segment_parallel_lower_bound.md)에 있습니다.
Build 조기 반환, Scan 결과 재사용과 production scheduler의 실행 시작 단축은
[실험 30](../reports/30_policy_parallel_action_check_and_faster_start.md)에 기록했습니다.
최소 lower bound를 달성한 seed의 최적성 증명, 두 request suffix 직접 계산과 Scan 병렬화는
[실험 31](../reports/31_policy_optimality_early_exit_and_parallel_scan.md)에 기록했습니다.

어느 checkpoint를 남길지는 미래에 어떤 number of iterations가 올지에 달려 있습니다. 지금 당장 좋은
선택이 다음 두 번의 request에서 나쁠 수 있습니다.

`grover_ckpt_policy_rolling`이 현재 request와 결정론적으로 예측되는 미래 request 3개(3-shot Lookahead)를
내다보고, 그 범위 안에서 실제로 돌릴 iteration 비용의 sum이 최소가 되는 선택을 DP로
풉니다.

DP 결과가 같은 경우를 처리하는 순서도 다음과 같이 고정합니다.

```
비교 순서:  (DP의 총 executed iterations, number of segments, 정렬된 checkpoint slot 집합)
```

이 규칙이 고정되어야 software reference model이 BBHT trajectory를 재현할 수 있습니다. 동점에서 아무거나
고르면 reference model과 RTL이 갈라지고, 500/500 대조가 성립하지 않습니다.

### Iteration-Count Predictor를 이용한 미래 number of iterations 예측

`grover_shadow_j`가 실제 Iteration-Count LFSR state를 복사본으로 돌려서 "이번 shot이 실패한다면 다음에
무엇이 뽑힐까" 를 미리 계산합니다. 진짜 BBHT random number state는 건드리지 않습니다.

그 예측으로 미리 푼 계획은 `grover_ckpt_plan_queue`(Plan Queue)에 넣어 두었다가, 실제로 실패가 나면
꺼내 씁니다. hit와 miss는 `plan_queue_hit_count` · `plan_queue_miss_count`로
밖에서 셀 수 있습니다([13장](13_csr_registers_and_execution_modes.md)).

예측이 맞지 않으면 계획을 다시 계산하므로 BBHT trajectory에는 영향을 주지 않습니다. 현재 shot이
성공하면 다음 number of iterations를 뽑지 않으므로 이때의 miss도 정상 동작입니다.

---

<a id="115-memo와-3279-사이클"></a>

## 11.5 memo table initialization: 3,279 → 381 cycles

DP의 부분 결과는 `{epoch 8 bits, cost 10 bits}`인 18-bit entry로 memo table에 담습니다.
Board-Verified Build와 2026-10-25까지의 공용 RTL은 a Checkpoint-Capacity of 4 and 4-shot Lookahead와 같은 1,093-entry stride를 a Checkpoint-Capacity of 3 and 3-shot Lookahead에도
사용했습니다.

```
Board-Verified Build:                                        MEM_ENTRIES = 3 × 1,093 = 3,279
최신 main, a Checkpoint-Capacity of 3 and 3-shot Lookahead:  MEM_ENTRIES = 3 ×   127 =   381
```

a Checkpoint-Capacity of 3 and 3-shot Lookahead에서는 내다보는 범위 안의 universe ID가 0..6이고 state 집합 크기가 최대 3입니다. 동결된
`rank_state()` 식에서 도달 가능한 가장 큰 rank는 126이므로 단계당 127 entries면 충분합니다.
최신 main은 세 단계의 address를 `0`, `127`, `254`에서 시작해 최종 address 380까지만 사용하고,
이를 하나의 512×18 `ram_style="block"` array에 둡니다. address 381 이상을 읽거나 쓰면
simulation assertion이 실패합니다. a Checkpoint-Capacity of 3 and 3-shot Lookahead 이외의 parameter 조합은 기존 1,093-entry stride와
bank 구조를 유지합니다.

실제 RAMB 개수는 synthesis 결과로 확정해야 합니다. 2026-10-26 수정 환경에서는 Vivado
license를 얻지 못해 새 array의 OOC resource를 아직 재지 못했습니다
([실험 21](../reports/21_policy_memo_table_compaction.md)).

### memo table initialization 시점

reset 뒤 첫 시작과 8-bit epoch가 한 바퀴 돌 때 Policy Engine은 `ST_CLEAR`에서 memo table을 한 entry씩
지웁니다. 최신 main a Checkpoint-Capacity of 3 and 3-shot Lookahead의 청소 길이는 381 cycles이며, Board-Verified Build보다 2,898 cycles
짧습니다. 공용 100 MHz와 별도 200 MHz overlay에 같은 address 배치를 적용했습니다.

| 대상 | 청소 길이 | 해석 |
|---|---:|---|
| 2026-09-07 Board-Verified Build와 과거 benchmark 묶음 | 3,279 cycles | benchmark 값을 그대로 인용 |
| 최신 main a Checkpoint-Capacity of 3 and 3-shot Lookahead RTL | 381 cycles | 새 RTL simulation·향후 build에 적용 |
| 그 밖의 Checkpoint-Capacity · Lookahead-Shots 조합 | `LOOKAHEAD_SHOTS` × 1,093 | 기존 배치 유지 |

따라서 과거 board 실행과 RTL campaign의 cycle 값은 여전히 직접 맞대면 안 됩니다. 과거
Six-Stage Ablation은 workload마다 새로 시작해 매번 3,279 cycles을 치렀고, board app과
`bench500`은 500개를 연달아 실행해 첫 workload와 epoch 순환 때만 청소했습니다. 이 때문에
final configuration의 과거 비교에서 473/500이 정확히 3,279 cycles 차이났습니다.

원인은 2026-09-16 SoC console simulation에서 확인했습니다. 같은 workload를 reset 직후와 그다음에
연달아 돌려 `cycle` · `policy_cycles` · `policy_stall`이 셋 다 정확히 +3,279이고
`max_latency`가 3,352로 튀는 것을 보았습니다
([soc_rtl_console](../../hardware_bram/configurations/final/results/2026-09-16_soc_rtl_console/evidence.md)).

이 과거 원인은 한 workload에서 확인했으며 473건 전체를 같은 방식으로 재현하지는
않았습니다. 나머지 21건의 차이는 epoch 순환에 따른 initialization 시점과 관련된 것으로 보이지만
아직 검증하지 않았습니다.

---

## 11.6 Checkpoint-Capacity와 Lookahead-Shots의 선택

a Checkpoint-Capacity of 4 and 4-shot Lookahead에서 a Checkpoint-Capacity of 3 and 3-shot Lookahead로 줄였을 때 cycle이 7.66% 감소했고 resource 사용량도 함께 줄었습니다.

| configuration |    LUT |     FF | BRAM tile | DSP |
| -------- | -----: | -----: | --------: | --: |
| Stage 3 | 30,294 | 25,822 |      83.0 |  64 |
| Stage 4 | 29,959 | 25,655 |      83.0 |  64 |

둘을 따로 떼어 본 실험
([kh_isolated_e1](../../hardware_bram/results/2026-09-09_kh_isolated_e1/evidence.md))
은 Checkpoint-Capacity와 Lookahead-Shots의 영향을 분리해 benchmark했습니다.

| 무엇을 줄였나 |    몫 |
| ------------- | ----: |
| Checkpoint-Capacity만 줄임 | 0.21% |
| Lookahead-Shots를 줄임 | 2.58% |

주된 비용은 checkpoint 저장 공간이 아니라 유지할 checkpoint를 결정하는 과정에서
발생합니다. Lookahead-Shots가
크면 DP가 내다보는 범위가 넓어져 풀이가 오래 걸리고, 그동안 datapath가 stall합니다(`policy_stall`).
BRAM이 줄지 않는 것도 checkpoint slot이 Checkpoint-Capacity와 무관하게 4벌이기 때문입니다
([6장 6.7절](06_data_representation_and_memory_map.md#67-memory-구조)).

---

## 11.7 제외한 설계안

| 무엇                            | 왜                                                                         |
| ------------------------------- | -------------------------------------------------------------------------- |
| 5벌 이상의 checkpoint           | 저장 공간보다 checkpoint 선택에 드는 결정 비용이 큽니다                    |
| 전체 state scratch 한 벌 더      | segment 규약이 목적지 checkpoint slot을 그대로 쓰므로 필요 없습니다                      |
| enumeration round를 넘는 checkpoint 재사용 | solution 집합이 바뀌면 다른 search 문제입니다                                    |
| request 순서 분할형 Two-Track Execution        | 분할 비용 +50%, checkpoint slot 소유권 문제로 탈락                                    |
| Pass 2–Build Fusion              | measurement rescan을 없애는 방식. Board-Verified Build는 rescan 비용을 줄이는 방식을 채택했습니다 |

policy algorithm을 고른 과정은 [실험 05](../reports/05_checkpoint_policy_selection.md), Checkpoint-Capacity · Lookahead-Shots를 정한 실험은
[실험 07](../reports/07_lookahead_shots_reduction.md), 마지막 둘의 benchmark는 [실험 10](../reports/10_two_track_execution_and_pass2_build_fusion.md)에 있습니다.

확장 범위의 parameterized RTL 독립 블록 검증은 [실험 34](../reports/34_parameterized_rtl_development.md),
후속 Main IP의 Scheduler · Planner · Executor 연결과 선택한 설정의 integration 검증은
[실험 35](../reports/35_parameterized_main_ip_scheduler_integration.md)에 있습니다.
해당 개발 경로의 full Common500 · 전체 SoC · implementation · board 검증은 남아 있으며,
이 장의 Board-Verified Build 설계와 성능 인용 범위를 바꾸지 않습니다.
