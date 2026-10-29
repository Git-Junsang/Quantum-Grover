# 실험 32. a Checkpoint-Capacity of 3 and 3-shot Lookahead 전체 실행 성능 재확인

> [← 실험 31](31_policy_optimality_early_exit_and_parallel_scan.md) · [실험 보고서 index](index.md) · [실험 33 →](33_latest_policy_two_level_select_200t_board_pipeline.md)

| 확인한 것 | 근거의 축 | 상태 |
|---|---|---|
| a Checkpoint-Capacity of 3 and 3-shot Lookahead · 4 PEs · Triple-Row Build Common500의 policy·stall·전체 cycle 재확인 | 같은 최종 RTL native model 재실행, reference model verification | 통과 |
| policy 계산 감소와 실제 전체 실행 이득을 구분 | 동일한 두 baseline revision과 1,000 runs 비교 | 확인 |
| Checkpoint-Capacity 1~10 × 1-shot ~ 10-shot Lookahead 확장과 100 cells 실행 | 이번 결과 평가 뒤 결정 | 미착수 |

## 판단

최종 source와 입력 hash가 같음을 확인하고 Common500을 다시 실행했습니다. 결과와 executed iterations는
유지됐고, 직전 revision 대비 policy 계산량의 감소 대부분은 이미 실제 계산과 겹쳐 있던 segment입니다.
따라서 현재 a Checkpoint-Capacity of 3 and 3-shot Lookahead의 직접적인 전체 실행 이득은 작고, policy throughput 증가와 향후 확장 여유를
구분해서 평가해야 합니다.

수치, baseline, verification 절차와 재현 정보는
[evidence bundle](../../hardware_bram/results/archive/policy_optimization/2026-10-28_k3h3_performance_recheck/evidence.md)에 있습니다.
전체 RVX SoC console verification은 실험 31의 같은 source 결과를 참조하며 이번에는 재실행하지 않았습니다.
