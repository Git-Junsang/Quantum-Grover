# 실험 31. policy 최적성 조기 종료와 병렬 Scan

> [← 실험 30](30_policy_parallel_action_check_and_faster_start.md) · [실험 보고서 index](index.md) · [실험 32 →](32_capacity_3_lookahead_3_performance_recheck.md)

| 확인한 것 | 근거의 축 | 상태 |
|---|---|---|
| 후보 순회·필터와 응답·종료 segment를 각각 절반 이하로 감소 | 같은 a Checkpoint-Capacity of 3 and 3-shot Lookahead · 4 PEs · Triple-Row Build Common500 RTL profile | 통과 |
| root 동점 규칙을 포함한 최적성 증명과 두 request suffix 직접 계산 | exhaustive solver·순차 bound oracle, 2,232 cases | 통과 |
| Scan 1/2/4개 발행과 cache 선행 읽기 | a Checkpoint-Capacity of 4 and 8-shot Lookahead·220 root 후보·서로 다른 lane/bank 구성 | 통과 |
| 최종 source의 전체 SoC console | Questa Errors 0 / Warnings 0, 같은 source 응답 90항목 일치 | 통과 |
| 큰 Checkpoint-Capacity · Lookahead-Shots 전체 성능 및 새 RTL의 200T timing·resource | 전체 성능·routing implementation | 미검증 |

## 변경과 판단

Scan이 선택한 seed의 실제 비용이 최소 lower bound와 같으면 최적성이 증명됩니다. root에서는 segment와
값으로 정렬한 tuple까지 optimistic key에 포함해 기존 동점 규칙을 보존합니다. 그때 CANON 전체를
생략합니다. 마지막 request 하나가 뒤따르는 내부 state는 달성 가능한 predecessor를 직접 찾아 정확한
minimum을 계산하므로 후보 나열 자체를 생략합니다.

남은 Scan은 후보 생성·lower bound·최소 선택·cache 저장까지 병렬화합니다. cache 읽기를 후보 검사·parent
복귀 평가와 겹치고 마지막 후보 처리와 종료를 통합합니다. lower bound의 유용한 3단 계산 경계와 동기
memo table 응답 정렬은 유지하며 제어 latency 단계는 추가하지 않습니다. 이번 benchmark에서 목표를 달성해
segment 비용 사전 계산표는 도입하지 않았습니다.

Solver의 SCAN_LANES와 Accelerator Core의 POLICY_SCAN_LANES를 추가했습니다. 1/2/4를 지원하며 Scan
폭은 CANON bank 수 이하여야 합니다. root 입력 값 정렬도 기존 Build와 병행하도록 옮겼습니다.

source hash·정확성 논거·benchmark 원자료·전체 SoC 상태·재현 명령은
[evidence bundle](../../hardware_bram/results/2026-10-28_policy_scan_parallel_verified/evidence.md)에 있습니다.

## 해석의 범위

policy 계산 대부분이 실제 연산과 겹치므로 계산량 감소를 전체 실행 시간의 같은 비율 개선으로
해석하지 않습니다. 측정한 3-shot Lookahead에서는 CANON이 모두 생략됐지만 8-shot Lookahead에서는 여전히 필요하며 집중
검사에서 그 경로도 실행했습니다. 8-shot Lookahead 정확성 verification을 8-shot Lookahead Common500 성능으로 인용하지 않습니다.
큰 Checkpoint-Capacity · Lookahead-Shots의 300,000 cycles 목표는 별도 성능 benchmark가 필요합니다.
