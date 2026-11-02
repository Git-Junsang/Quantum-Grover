# 실험 29. Seed 재발행 생략과 segment별 병렬 lower bound

> [← 실험 28](28_policy_single_action_exit.md) · [실험 보고서 index](index.md) · [실험 30 →](30_policy_parallel_action_check_and_faster_start.md)

| 확인한 것 | 근거의 축 | 상태 |
|---|---|---|
| 정확히 평가한 seed를 canonical search에서 다시 발행하지 않음 | 독립 exhaustive solver와 tuple·비용 비교 | 통과 |
| 같은 relaxed cost를 checkpoint segment별로 병렬 계산해 Lookahead-Shots에 비례하던 응답 latency 제거 | request별 기존 lower bound oracle, a Checkpoint-Capacity of 3 and 3-shot Lookahead와 a Checkpoint-Capacity of 4 and 8-shot Lookahead 집중 RTL 검사 | 통과 |
| Common500의 policy 계산 비용 감소 | 단독·통합 RTL | [evidence bundle](../../hardware_bram/results/archive/policy_optimization/2026-10-28_policy_gap_bound_final/evidence.md) |
| 전체 RVX SoC console의 RUN·STAT·ENUM이 같은 source 기준과 일치 | Questa, Verilator의 같은 순서 replay | 통과 |
| 새 lower bound circuit의 200T resource·routing timing | 전체 RVX SoC implementation | 미검증 |

## 목표와 변경

같은 Common500에서 Checkpoint-Capacity · Lookahead-Shots가 커져도 통합 policy cycles을 약 300,000 이내로 유지하는 것이
목표입니다. 실행과 계산을 겹쳐 stall만 숨기는 것으로는 부족하므로 solver의 실제 작업을 줄입니다.

먼저 seed 재발행을 생략했습니다. 정확히 계산한 후보를 다시 보내는 작업은 줄었지만 cycle 감소가
작아, Lookahead-Shots만큼의 request를 따라 순차적으로 계산하던 lower bound도 개선했습니다. 새 circuit은 초기 checkpoint 사이
segment별 비용을 동시에 구합니다. unlimited-capacity relaxed policy에서는 한 segment의 request 처리 비용이
그 segment의 최대 request까지 확장하는 비용으로 모이므로 기존 lower bound와 같은 값을 얻습니다.

이는 restricted-B의 선택 공간이나 정확성을 완화한 변경이 아닙니다. root 동점 처리와 memo table의
의미도 유지하며, epoch 및 단일 후보 조기 반환의 계약은 [실험 28](28_policy_single_action_exit.md)과
같습니다. 계산 원리, source hash, 집중 verification과 Common500 원자료는 위 evidence bundle에 모았습니다.

## 다음 판단

lower bound 응답이 고정 깊이가 되어도 DFS가 방문하는 state 수는 Checkpoint-Capacity · Lookahead-Shots에 따라 늘어납니다. Build와
memo table initialization 비용도 남습니다. 큰 Checkpoint-Capacity · Lookahead-Shots의 전체 policy cycles이 목표 이내인지 확인한 뒤,
clear 비용과 중복 search를 줄이고 필요하면 hierarchical state 병합으로 전환해야 합니다.

이번에는 한 configuration의 Common500, 큰 universe를 사용하는 집중 정확성 검사와 전체 SoC console
verification을 수행했습니다. 전체 Checkpoint-Capacity · Lookahead-Shots sweep, 새 Vivado 실행, board verification과 commit은 포함하지 않았습니다.
