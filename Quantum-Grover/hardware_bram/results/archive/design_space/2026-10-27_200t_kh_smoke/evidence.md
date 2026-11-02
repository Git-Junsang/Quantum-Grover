# 설정만 바꾸는 Checkpoint-Capacity · Lookahead-Shots 통합 확인

날짜: 2026-10-27 (한국). 축: 통합 RTL cycle. board benchmark 없음.

입력은 [manifest.json](manifest.json)에 있습니다. Checkpoint-Capacity 3 · 4 × Lookahead-Shots 3 · 8, 4 PEs,
Quad-Row Build, policy search mode 6을 설정 file의 array로 지정했습니다. Common500의 앞 **2 workloads**를
reset·epoch 이력을 유지한 순서로 실행합니다. 전체 성능 비교가 아니라 각 cell의 자동 생성,
policy 선택·executed iterations, 8-shot Lookahead 설정 전달을 확인하는 목적입니다.

runner는 각 cell의 exhaustive policy replay → policy 단독 RTL 대조 → 통합 RTL → 외부 trace와
논리 결과 대조 → 같은 Checkpoint-Capacity · Lookahead-Shots의 executed iterations 대조 → 표·heatmap을 실행합니다.
네 cell 모두 policy 단독 40/40 결정이 exhaustive 기준과 일치했고, 통합 2/2 workload의
결과·trial·L_BBHT와 해당 Checkpoint-Capacity · Lookahead-Shots의 executed iterations가 일치했습니다. Plan Queue miss는 모두 0입니다.
8-shot Lookahead의 speculative planning root에는 아홉 미래 request를 공급한 RTL입니다.

| Checkpoint-Capacity | Lookahead-Shots | 통합 cycle | policy stall | executed iterations |
|---:|---:|---:|---:|---:|
| 3 | 3 | 30,425 | 531 | 79 |
| 3 | 8 | 42,023 | 12,119 | 79 |
| 4 | 3 | 33,497 | 3,601 | 79 |
| 4 | 8 | 43,370 | 13,464 | 79 |

이 표는 두 workload 앞부분에서만 성립합니다. 이 값으로 Common500 전체의 최적 Checkpoint-Capacity · Lookahead-Shots나
8-shot Lookahead의 가치를 판정하지 않습니다. 원자료는 [summary.csv](summary.csv), configuration별 `bench.csv`와
`policy.json`이며, [heatmap](heatmap_e4_b4_p6.png)의 제목에도 표본 수를 표시했습니다.
routing하지 않은 cell의 WNS는 `unmeasured`입니다. 설계·명령은
[실험 27](../../../../../documents/reports/27_200t_parameter_automation.md)에 있습니다.
