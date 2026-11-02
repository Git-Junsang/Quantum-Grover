# Results directory organization (두 번째)

기록일: 2026-10-29, Asia/Seoul. directory 정리와 원자료 보존 확인입니다.
RTL simulation, synthesis, implementation 또는 board verification을 새로 수행한 기록이 아닙니다.
[첫 정리](../2026-10-29_organization/evidence.md)와 같은 방식으로 진행했습니다.

첫 정리 뒤 최상위에 남았던 실험 묶음 32개 가운데 20개를 `archive/`의 다섯 topic directory로 옮겼고,
최상위에는 12개가 남았습니다. 옮긴 묶음은 Parameterized RTL(실험 34~37)에 이르기까지 거친 과정입니다.

| topic | 옮긴 묶음 |
|---|---|
| `design_space/` (새로 만듦) | `2026-10-26_kh_sweep`, `2026-10-27_200t_dse`, `2026-10-27_200t_kh_smoke`, `2026-10-27_kh_sweep_m2_m3` |
| `policy_search/` | `2026-10-26_policy_search_full40_seedfull`, `2026-10-26_policy_search_method1`, `2026-10-27_policy_seed_first` |
| `policy_optimization/` | `2026-10-26_policy_memo_compact`, `2026-10-28_policy_single_action`, `2026-10-28_policy_bottleneck`, `2026-10-28_policy_gap_bound_final`, `2026-10-28_policy_parallel_paths_verified`, `2026-10-28_policy_scan_parallel_verified`, `2026-10-28_policy_kh_cycles`, `2026-10-28_k3h3_performance_recheck` |
| `policy_unpipeline/` | `2026-10-28_policy_unpipeline_final`, `2026-10-28_policy_unpipeline_timingfix`, `2026-10-28_policy_pause` |
| `implementation_pipeline/` (새로 만듦) | `2026-10-28_policy_rank_timing`, `2026-10-28_k3h3_e4_m2_policy6_board` |

최상위에 남긴 묶음은 2026-09 benchmark 세 개, 실험 18 Six-Stage Ablation의 2026-10-07 · 10-08 묶음 다섯 개,
실험 34~37의 묶음 네 개입니다. 실험 18 묶음은 200T board에서 잰 독립 benchmark이고 board benchmark 표의
인용처라 옮기지 않았습니다.

## 이동과 보존

- [moves.json](moves.json): 이동 전후 경로와 topic.
- [files_before.json](files_before.json): 이동한 모든 file(git 추적 밖의 file 포함)의 기존 경로, 새 경로, bytes와 SHA-256.
- [preservation.json](preservation.json): 이동 file 961개 중 경로만 고친 12개를 뺀 949개의 SHA-256 일치,
  이동 대상 밖의 git 추적 file 5,974개가 바뀌지 않았음을 대조한 결과.
- [reference_updates.json](reference_updates.json): 경로를 고치거나 내용을 더한 file 36개(catalog 포함)의 수정 전후 SHA-256.
- [validation.json](validation.json): 문서 검사, 재검사 도구와 helper 경로 확인.
- [catalog.json](../../catalog.json): 현재 최상위 묶음과 archive의 전체 경로 목록.

원자료를 삭제하지 않았습니다. 이동은 `git mv`로 directory를 통째로 옮겨 git 추적 밖의 file도 함께 옮겼습니다.
`*.txt` `*.csv` `*.log` `*.rpt` `*.json` `*.patch` 안의 과거 실행 경로는 당시 기록이라 고치지 않았습니다.
경로를 고친 곳은 다음 세 종류입니다.

- authored Markdown(실험 보고서 21~35, 보고서 index, evidence 묶음의 `evidence.md`)의 link와 경로.
- 옮긴 묶음을 기본 입출력으로 쓰는 helper 네 개: `hardware_bram/sim/kh_sweep.py`,
  `policy_full40_analysis.py`, `policy_search_method1.py`, `hardware_bram/synth/full_bound_pipeline_ooc.tcl`.
- 묶음 안의 재검사 도구 `verify_soc.py` 다섯 개. 저장소 root를 묶음 위치에서 두 단계 위로 계산하던 것을
  네 단계 위로 바꾸었습니다. 같은 묶음의 `pipeline_worker.py` · `retry_low_memory_20261029.py`는 이미
  끝난 background 실행의 기록이라 고치지 않았습니다. 다시 실행하면 root를 잘못 계산합니다.

정리 뒤 `2026-10-28_policy_rank_timing/evidence.md`에 4차 implementation 실행의 결과 절을 더했습니다.
이 file은 preservation.json 대조 뒤에 바뀌었으므로 수정 전후 SHA-256은 reference_updates.json에 있습니다.
같은 묶음과 `2026-10-28_k3h3_e4_m2_policy6_board`의 종료된 background 실행 기록(`pipeline.log`,
`pipeline_state.json`, 4차 시도 report 등)은 이번에 git에 더했습니다.
`2026-10-28_policy_unpipeline_timingfix`의 Vivado checkpoint(`*.dcp` 네 개, 약 75 MB)는 다시 만들 수 있는
build 산출물이라 git에 더하지 않고 그대로 두었습니다.
