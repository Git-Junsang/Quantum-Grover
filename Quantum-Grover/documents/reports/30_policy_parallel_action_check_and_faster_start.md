# 실험 30. policy 후보 병렬 검사와 실행 시작 단축

> [← 실험 29](29_policy_per_segment_parallel_lower_bound.md) · [실험 보고서 index](index.md) · [실험 31 →](31_policy_optimality_early_exit_and_parallel_scan.md)

| 확인한 것 | 근거의 축 | 상태 |
|---|---|---|
| 단일 후보의 universe Build를 생략하고 Scan 결과를 4-bank cache에서 재사용 | 독립 exhaustive solver 비교 | 통과 |
| 후보를 병렬로 걸러낸 후 필요한 것만 memo table 조회 | 1/2/4-lane 및 a Checkpoint-Capacity of 4 and 8-shot Lookahead 집중 정확성 검사 | 통과 |
| 정렬된 logical checkpoint set 유지와 plan 수신 시 Checkpoint Planner 시작으로 준비 state 단축 | Common500, 전체 RVX SoC console | 통과 |
| 큰 Checkpoint-Capacity · Lookahead-Shots의 policy cycles 목표 및 200T timing·resource | 전체 Checkpoint-Capacity · Lookahead-Shots 성능·implementation | 미검증 |

## 변경과 판단

직전 profile에서 비용이 큰 Build, 후보 순회, 응답 대기와 scheduler 준비 경로를 개선했습니다.
단일 후보는 입력 snapshot에서 판정하고, 다중 후보는 Scan에서 구한 bound와 tuple을 frame별로
저장합니다. CANON은 최대 네 후보를 한 번에 검사하고 살아남은 첫 후보만 memo table에 보냅니다.
선택 순서, root 동점 규칙, restricted-B 공간과 exact 비용 계산은 유지합니다.

production scheduler는 완료된 plan의 canonical checkpoint 집합을 보존합니다. 이를 실제 physical
metadata와 demand마다 대조하는 simulation assertion을 넣었고, metadata invalidate와 재시작을
구분해 연속 RUN·Enumeration에서도 일치하는지 확인했습니다. 계획 수신 edge에서 Checkpoint Planner를
시작하고 그 결과를 Checkpoint Executor가 직접 받아 중복 packet capture와 별도 launch를 줄입니다.
수동 호환 설정의 기존 경로는 유지합니다.

수치, source hash, 단계별 profile과 verification 범위는
[evidence bundle](../../hardware_bram/results/archive/policy_optimization/2026-10-28_policy_parallel_paths_verified/evidence.md)에 모았습니다.

## 범위

a Checkpoint-Capacity of 3 and 3-shot Lookahead · 4 PEs · Triple-Row Build configuration 하나의 Common500과 전체 SoC console을 검증했습니다. a Checkpoint-Capacity of 4 and 8-shot Lookahead는 220개
root 후보를 사용하는 집중 정확성 검사이며 전체 성능 benchmark는 아닙니다. 병렬 bound 검사와 별개로
정확한 child DFS와 memo table port는 하나입니다. 전체 Checkpoint-Capacity · Lookahead-Shots 성능과 200T routing timing·resource를 확인하기
전에는 큰 Checkpoint-Capacity · Lookahead-Shots의 300,000 cycles 목표를 달성했다고 판단하지 않습니다.
