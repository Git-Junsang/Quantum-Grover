# 실험 36. Generalized Main IP Common500과 policy heatmap

> [← 실험 35](35_parameterized_main_ip_scheduler_integration.md) · [실험 보고서 index](index.md) · [실험 37 →](37_expanded_iteration_and_measurement_engines.md)

| 확인한 것 | 근거의 축 | 범위 |
|---|---|---|
| 기존 구성의 일반화 physical kernel full Common500 | 실제 driver · Main IP RTL · exact reference | 완료 |
| generic solver의 단일 후보 · 마지막 두 요청 단축 | parameterized RTL · 독립 exhaustive DP · 동일 입력 old/new RTL replay | 완료 |
| 고정 iteration / square engines의 policy parameter sweep | 실제 Main IP RTL Common500 | 전 조합 검증 완료; 모든 parameter가 policy clock 목표를 만족한 것은 아님 |
| 200T fitting / timing / board | 이번 source로는 미수행 | 후속 단계 |

기록일: 2026-10-29. [실험 35](35_parameterized_main_ip_scheduler_integration.md)의 짧은 integration
검증을 전체 Common500으로 넓히고, generic solver의 불필요한 BUILD / 후보 탐색 / 마지막 tail 처리를
단축했습니다. 정책의 action set과 cost / segment / tuple 동률 규칙은 유지합니다.

## 범위

Checkpoint-Capacity 1~5와 Lookahead-Shots 1~8을 조합합니다. iteration engines 4,
square engines 2와 generic backend를 고정합니다. 사용자 지시대로 현재 campaign에서 iteration /
square engines를 변경하지 않습니다. 두 simulation을 병렬 실행하고 한 model compile은 한 thread를 사용합니다.

모든 configuration은 같은 정식 Common500 전체 입력을 Normal / Checkpoint 순서로 실행합니다.
CSV 결과 · 요청 trajectory · physical iterations를 대조하고, 실제 solver start / done / plan acceptance를
독립 exact reference와 검사합니다. 계산 clock과 노출된 policy stall, 전체 accelerator clock을 따로 기록합니다.

## 의미와 후속 작업

기존 optimized backend와 새 generic backend의 실제 통합 결과, 같은 generic backend의 old/new solver
단독 재생 결과를 구분합니다. 단독 solver의 감소율을 전체 실행의 감소율로 옮겨 적지 않습니다.
원자료 · cycle · source hash · 검증 범위 · 재현 명령은
[evidence bundle](../../hardware_bram/results/2026-10-29_generalized_common500/evidence.md)에 있습니다.
고정 병렬도에서 최소 전체 cycle인 구성과 policy clock 목표를 넘은 구성, 남은 병목은 evidence의
최종 heatmap과 상태별 측정에 정리했습니다. 200T 자원과 timing을 포함한 최적점 선정은 남아 있습니다.

이번 heatmap 다음에는 200T 자원 사용 가능량과 memory 구조를 바탕으로 feasible parameter range를
추정하고 대표 구성의 synthesis / timing으로 보정합니다. 자원과 timing을 만족하는 구성의 실제 전체
cycle과 policy stall로 유망 범위를 정한 뒤 heatmap을 확장합니다.
iteration / square engine 지원 범위를 넓힌 후속 구현과 memory 정리 · resource 선정 순서는
[실험 37](37_expanded_iteration_and_measurement_engines.md)에 있습니다.
