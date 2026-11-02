# policy search mode 6 단일 후보 조기 반환 — 2026-10-28

a Checkpoint-Capacity of 3, 3-shot Lookahead, 4 PEs, Triple-Row Build, policy search mode 6 한 configuration에서, 현재 request의 legal action이 하나뿐일 때 Scan·lower bound 계산·memo table 응답을 기다리지 않고 계획을 반환하도록 수정했습니다. 단독 RTL과 Accelerator Core 통합 Common500을 통과했습니다. 이번 수정의 전체 RVX SoC simulation·200T implementation·board verification은 아직 하지 않았으며, commit하지 않았습니다.

## 변경과 계약

- 수정 file은 `hardware_bram/src/grover_policy.v`입니다. SHA-256은 `f50ba93c8a60b58a7f225c2fef2027d2f53cc681660b7f6cfacfc6e4886a38b5`이고, `source/grover_policy.v`와 같습니다. 다른 입력 source와 configuration은 `manifest.json`에 보존했습니다.
- mode 6에서 root의 optional deposit이 없고, endpoint를 제외한 기존 checkpoint가 모두 남을 수 있으면 action은 하나입니다. 기존 정렬값에 endpoint를 삽입해 같은 checkpoint 집합을 반환합니다. 다중 후보는 기존 exact search를 사용합니다.
- `ST_RUN`에서 조기 완료하고 해당 후보의 `bound_capture`를 막습니다. 추가 timing register를 넣지 않았으며, 제거했던 `actionq/mreq/areq`도 복구하지 않았습니다. 동기 memo table 응답 및 다중 후보의 algorithm상 bound pipeline은 남아 있습니다.
- `source_j`, `next_count`, `next_j_flat`, segment 선택은 유지합니다. 단일 후보의 `root_cost`는 종전의 full-horizon relaxed bound 대신 **현재 request의 즉시비용만 포함한 lower bound**입니다. mode 6은 이 경우 원래도 exact horizon cost를 보장하지 않았습니다. Accelerator Core는 이 field를 저장·전달할 뿐 계획 선택이나 실행에 사용하지 않습니다. 다중 후보의 exact cost 계약은 유지합니다.
- memo table clear 및 epoch wrap 동작은 유지합니다. initialization 비용을 제외한 단일 후보 latency는 기존 20 cycles에서 11 cycles로 줄었습니다. Build/root/PREP 자체의 비용은 이번에 줄이지 않았습니다.

## verification

### 독립 exhaustive solver와 비교

`hardware_bram/testbench/tb_policy_single_action.sv`에서 mode 6을 mode 0과 비교했습니다. 빈 checkpoint 집합, 기존 endpoint, 새 endpoint 삽입, Checkpoint-Capacity가 찬 retention 선택, 중간 deposit, 0/127 경계값, 비연속·비정렬 checkpoint slot, epoch wrap, soft reset을 포함합니다.

단일 후보는 같은 계획, 즉시비용 lower bound, clear를 제외한 11 cycles, bound 발행 0건, memo table read 0건을 검사합니다. 다중 후보는 일반 search를 거치고 exact cost도 일치하는지 검사합니다. 결과는 **268 cases, errors=0, clear events=3**입니다. 실행 결과는 `single_action.log`, test source 사본은 `source/tb_policy_single_action.sv`입니다.

```bash
iverilog -g2012 -s tb_policy_single_action -I hardware_bram/src \
  -o /tmp/policy_single_action_test \
  hardware_bram/testbench/tb_policy_single_action.sv hardware_bram/src/grover_policy.v
vvp /tmp/policy_single_action_test
```

### Common500

- 단독 policy replay는 7,403개 결정을 기존 exhaustive 기준 tuple과 비교했습니다. `k3h3_e4_b3_p6/rtl_p6_k3h3.log`의 결과는 `SUMMARY,3,3,7403,236054,26104,481,0`입니다. trace는 기존 기준 결과와 같으며 새 RTL로 직접 실행한 benchmark입니다.
- Accelerator Core·실제 C driver를 연결한 통합 실행은 `bench.csv`의 `# DONE errors=0 workloads=500`으로 완료했습니다. reference model BBHT trajectory와 workload별 기준 executed iterations를 `dse.validate_bench`로 확인했습니다.
- 이전 결과와 새 결과의 1,000 rows 모두에서 workload, mode, 결과 index, shot, requested iterations, executed iterations, mismatch가 같습니다. Restart mode 실행 row는 전체 field가 같습니다.
- baseline은 [수정 전 관측 묶음](../2026-10-28_policy_bottleneck/evidence.md)과 [기존 Common500 결과](../../policy_unpipeline/2026-10-28_policy_unpipeline_final/summary.csv)입니다. 수정 전 관측 CSV와 기존 Triple-Row Build CSV는 byte 동일했습니다.

| RTL 지표 | 수정 전 | 수정 후 | 감소 |
|---|---:|---:|---:|
| 단독 policy cycles, 7,403 decisions | 285,140 | 236,054 | 17.2147% |
| 통합에서 집계한 policy cycles | 309,000 | 257,511 | 16.6631% |
| 실제 policy stall | 26,920 | 22,339 | 17.0171% |
| 전체 checkpoint 실행 cycles | 4,554,476 | 4,549,895 | 0.1006% |
| executed iterations | 9,582 | 9,582 | 동일 |
| 통합 policy actions | 28,819 | 28,819 | 동일 |
| 단독 최대 latency | 481 | 481 | 동일 |

이는 RTL cycle 비교입니다. policy 계산 대부분이 실행과 겹치므로 policy 가속률과 전체 가속률이 다릅니다. 단독 replay는 실제 demand만, 통합 policy counter는 cold 및 speculative planning 완료를 집계하므로 두 policy cycles 합계도 다릅니다. mean 비용은 줄었지만 다중 후보의 최대 latency는 그대로이며, 큰 Checkpoint-Capacity · Lookahead-Shots에서 stall이 없어진다는 결과가 아닙니다.

### 문서 검사

`python3 documents/check_docs.py`는 기존의 이동된 papers 경로와 memo table 절 anchor 등에서 오류 62건·경고 6건을 보고했습니다. 이번에 추가한 문서와 link를 memory에서 제외한 수정 전 상태도 같은 검사를 실행해 진단 목록이 정확히 같음을 확인했습니다. 새 진단은 없지만 전체 문서 검사가 통과한 것은 아닙니다. 결과는 `doc_check.log`에 보존했으며, 다른 작업의 문서 이동·삭제는 변경하지 않았습니다.

## 다음 변경의 기준

1. 다중 후보의 bound latency와 Scan → SEED → CANON의 중복 후보 처리를 줄입니다. pruning 안전성과 root tie-break를 그대로 검증해야 합니다.
2. 고정 Build 준비 비용과 scheduler의 Iteration-Count Predictor 준비·request 검사·결과 공급 주기를 줄입니다. solver busy와 실제 exposed stall을 나눠 비교합니다.
3. DFS를 유지해야 한다는 제약은 없습니다. 같은 깊이의 state를 병합하는 hierarchical DP를 비교하려면 frontier memory 크기, 같은 state 갱신 충돌, 결정 tie-break를 먼저 정해야 합니다. 이번 변경에는 search algorithm 교체를 섞지 않았습니다.

사용자 지시에 따라 기존 background placement · routing의 상태 · log · 결과는 조회하지 않았고 새 Vivado도 시작하지 않았습니다. 그 작업은 이번 수정 이전 source이므로, 나중에 결과가 나와도 이번 RTL의 timing verification으로 취급할 수 없습니다. 한 configuration의 기능·전체 SoC·timing verification과 commit을 마친 뒤 parameter를 바꾸는 순서를 유지합니다.
