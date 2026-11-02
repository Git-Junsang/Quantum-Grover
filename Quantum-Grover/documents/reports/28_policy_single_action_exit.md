# 실험 28. policy 단일 후보의 lower bound 대기 제거

> [← 실험 27](27_200t_parameter_automation.md) · [실험 보고서 index](index.md) · [실험 29 →](29_policy_per_segment_parallel_lower_bound.md)

| 확인한 것 | 근거의 축 | 상태 |
|---|---|---|
| Seed-First Branch and Bound with Single-Action Exit의 단일 후보에서 Scan·lower bound·memo table 대기 없이 같은 계획 반환 | 독립 exhaustive solver 비교, Common500 단독·통합 RTL | 통과 |
| mean policy 비용과 실제 노출 stall 감소 | 동일 a Checkpoint-Capacity of 3 and 3-shot Lookahead · 4 PEs · Triple-Row Build의 수정 전후 RTL cycle | [evidence bundle](../../hardware_bram/results/archive/policy_optimization/2026-10-28_policy_single_action/evidence.md) |
| 이번 RTL의 전체 RVX SoC·200T timing·board 동작 | 전체 SoC 및 실물 | 미검증 |

## 결정

현재 request의 합법적인 checkpoint 선택이 하나라면 하위 search의 비용은 그 선택을 바꿀 수 없습니다.
따라서 Seed-First Branch and Bound with Single-Action Exit에서 유일한 계획을 먼저 반환합니다. 다중 후보에서는 기존 exact search를 유지하며,
DFS 교체나 scheduler 분리는 이번 수정의 전제 조건으로 두지 않습니다.

단일 후보의 `root_cost`는 현재 request의 즉시비용 lower bound입니다. Accelerator Core가 계획 선택이나 실행에
사용하지 않는 field며, Seed-First Branch and Bound with Single-Action Exit의 단일 후보는 원래도 exact Lookahead window cost를 보고하지 않았습니다.
출력 checkpoint 집합·source·segment와 epoch 동작은 독립 exhaustive solver로 비교했습니다.

## 다음 대상과 범위

이번 변경은 단일 후보의 불필요한 계산을 없앤 첫 단계입니다. 다중 후보의 최대 latency는 여전히
남아 있으므로 큰 Checkpoint-Capacity · Lookahead-Shots와 더 짧은 Iteration Datapath · Build 실행에서 stall을 억제하는 목표가 완료된 것은 아닙니다.
다음 후보는 bound latency 및 Scan/seed 재처리, Build 고정 비용, scheduler 준비·공급 latency입니다.
hierarchical DP를 비교할 때도 같은 state 병합과 memory 충돌 비용을 포함해야 합니다.

benchmark value, test 범위, source hash와 재현 명령은 위 evidence bundle에 모았습니다. 기존 background implementation은
수정 전 source이므로 이번 변경의 timing 근거로 사용할 수 없습니다. 이번에는 한 configuration만 검증했고,
전체 조합 sweep과 새 Vivado 실행 및 commit은 하지 않았습니다.
