# Build·후보 cache·실행 시작 경로 개선 — 2026-10-28

a Checkpoint-Capacity of 3 and 3-shot Lookahead · 4 PEs · Triple-Row Build · Two-Level Select · policy search mode 6의 Common500에서 통합 policy cycles를 239,873에서 161,272로 줄였습니다. 단독·통합 RTL과 전체 RVX SoC console verification을 통과했습니다. 큰 Checkpoint-Capacity · Lookahead-Shots의 총 300,000 cycles 목표 및 새 RTL의 200T routing timing·resource는 아직 검증하지 않았습니다.

## 입력과 source

설정은 `config.json`, 전체 source hash는 `manifest.json`, 실제 benchmark한 RTL과 test는 `source/`에 보존했습니다. 설정 부품은 `xc7a200tfbg484-2`, accelerator clock 목표는 100 MHz입니다. 이는 implementation timing 통과나 board benchmark 결과가 아닙니다.

| file | SHA-256 |
|---|---|
| `grover_policy.v` | `59c0efc23278e20a0a791ef0506e863f95f3b8acf0e65e50543c5f90729b07c5` |
| `bbht_grover_main_ip.v` | `bb8523435e99cf97664557915ba31615deed087b9d80c46514f1afb3c5977633` |

baseline은 [직전 segment 병렬 lower bound revision](../2026-10-28_policy_gap_bound_final/evidence.md)입니다. E/B, restricted-B의 선택 공간, Lookahead-Shots, root 동점 규칙, RNG와 executed iterations 규칙은 바꾸지 않았습니다. 기존 WNS용 `actionq/mreq/areq`도 복구하지 않았습니다.

## 네 부분의 변경

### 1. Build 이전의 단일 후보 판정

입력 snapshot에서 closest predecessor, endpoint 존재 여부, 보존할 checkpoint 수와 eligible deposit 유무를 구합니다. endpoint와 기존 checkpoint가 모두 Checkpoint-Capacity 안에 들어가고 다른 deposit이 없으면 계획은 하나입니다. 중복 physical checkpoint가 있으면 이 단축 경로를 사용하지 않아 기존 오류 검사가 동작합니다.

유일한 계획은 첫 Build edge에서 바로 반환합니다. universe·rank 생성, ROOT_INIT, PREP를 수행하지 않으며 initialization을 제외한 latency는 **11 → 1 cycle**입니다. 기존 initial/epoch-wrap memo table clear와 epoch 증가 규칙은 그대로입니다. mode 6 단일 후보의 `root_cost`는 계속 즉시비용 lower bound며 Accelerator Core가 계획 선택·실행에 사용하지 않습니다.

### 2. Scan 결과를 frame별로 보존

`grover_policy_action_cache`에 Scan이 계산한 canonical 후보를 저장합니다. 한 word는 count 3 bits, ID tuple 16 bits, deposit 수 2 bits, lower bound 11 bits인 32 bits입니다. CACHE의 frame address를 분리해 child DFS가 부모 결과를 덮어쓰지 않으며, frame별 count 아래의 항목만 읽으므로 별도 전체 clear가 필요하지 않습니다.

크기는 universe와 Checkpoint-Capacity로부터 endpoint를 포함하는 가능한 child 집합 수를 상한으로 계산합니다. a Checkpoint-Capacity of 4 and 8-shot Lookahead의 상한은 299개이고, 실제 root 후보 220개를 생성하는 집중 사례로 여러 bank와 group, 재귀 후 부모 복구를 검사했습니다. a Checkpoint-Capacity of 5용 구조를 구현한 것은 아닙니다.

### 3. CANON 병렬 필터와 직접 memo table 조회

기본 4개 bank에서 후보 묶음을 읽고 최대 4 lower bounds를 동시에 검사합니다. 이미 정확히 평가한 seed는 건너뛰고, bound로 탈락하지 않는 가장 앞 후보 하나만 단일 memo table port로 보냅니다. 나머지는 다음 cycle에 이어 처리합니다. root의 equal-cost 후보는 segment/tuple 동점 검사를 위해 유지합니다.

CANON에서는 generator를 다시 순회하거나 lower bound pipeline을 다시 채우지 않습니다. 저장된 후보로 곧바로 동기 memo table 조회를 시작하고, miss 후에는 저장한 cache 위치 다음부터 재개합니다. 부모 cache count·seed 위치·재개 위치를 DFS stack에 보존합니다. 단일 후보 frame은 seed 평가 뒤 replay도 생략합니다. 마지막 응답이 모두 반영된 cache 경로는 빈 ROOT_DRAIN도 생략합니다.

공개 parameter는 solver의 `CANON_LANES`, Accelerator Core의 `POLICY_CANON_LANES`이며 1/2/4를 지원하고 기본값은 4입니다. 이는 동시에 4개의 DFS를 실행한다는 뜻이 아닙니다. 후보 lower bound 검사만 병렬이며, exact child search와 memo table port는 하나입니다. BRAM bank 추가에 따른 실제 resource와 timing은 implementation으로 확인해야 합니다.

### 4. Scheduler의 정렬·Checkpoint Planner·Checkpoint Executor 시작

완료된 plan의 canonical checkpoint 집합을 별도 state로 유지합니다. 실제 metadata invalidate와 함께 초기화하고, checkpoint를 보존하는 연속 RUN이나 Enumeration segment 재시작에서는 유지합니다. 매 demand마다 이 집합을 실제 physical metadata와 비교하는 simulation assertion을 추가했습니다. 생산 mode에서 이 집합을 사용해 입력 정렬 state를 건너뜁니다. 수동 호환 경로에는 기존 정렬 fallback을 유지합니다.

Plan Queue 또는 cold solver의 계획을 받는 edge에서 Checkpoint Planner pipeline stage 1도 함께 capture합니다. 다음 cycle의 pipeline stage 2 결과를 Checkpoint Executor가 직접 받아 Accelerator Core의 중복 plan packet capture와 별도 launch state를 생략합니다. Checkpoint Planner 내부의 실제 계산 경계는 유지합니다. 이 단축은 생산 설정 `CHECKPOINT_MANUAL_ENABLE=0`에 적용하며 수동 호환 경로의 기존 동작은 유지합니다.

## benchmark 결과

| Common500 RTL 지표 | 수정 전 | 수정 후 | 감소 |
|---|---:|---:|---:|
| 통합 policy cycles | 239,873 | 161,272 | 32.7678% |
| 단독 policy cycles, 7,403 decisions | 220,262 | 146,666 | 33.4129% |
| 실제 policy stall | 22,298 | 17,715 | 20.5534% |
| 전체 checkpoint 실행 cycles | 4,549,854 | 4,523,062 | 0.5889% |
| 단독 최대 latency | 472 | 466 | 6 cycles |
| executed iterations | 9,582 | 9,582 | 동일 |
| 통합 policy actions | 24,304 | 24,304 | 동일 |

같은 C driver·RTL configuration의 500 workloads를 실행했습니다. Restart mode · Checkpoint mode 1,000 rows에서 결과, shot 수, requested iterations · executed iterations, mismatch가 모두 같고 Restart mode rows는 모든 field가 같습니다. `dse.validate_bench`로 reference model BBHT trajectory와 workload별 executed iterations도 확인했습니다. 결과는 `summary.csv`와 `k3h3_e4_b3_p6/bench.csv`입니다.

같은 새 Verilator model을 읽기만 하는 observer의 `bench_profile.csv`도 최종 `bench.csv`와 byte 동일합니다. raw solver busy는 162,036이며, 집계 policy와의 차이 764는 stale 완료 두 건입니다. 원자료는 `profile.log`, 구조화한 값은 `profile.json`, observer는 `profile.h`·`tb_profile.cpp`입니다.

### 선택한 네 부분

| 부분 | 수정 전 cycles | 수정 후 cycles | 감소 |
|---|---:|---:|---:|
| Build state, 조기 판정 포함 | 63,224 | 23,163 | 63.3636% |
| Scan/CANON 후보 순회·필터 | 45,376 | 34,304 | 24.4006% |
| 응답·종료 처리, 후보 순회 제외 | 54,517 | 46,378 | 14.9293% |
| 입력 정렬·Checkpoint Planner·Checkpoint Executor 시작 | 29,612 | 7,403 | 75.0000% |

Build state 중 5,723 cycles는 실제 universe 준비를 하지 않은 조기 판정입니다. 실제 Build 작업은 17,440 cycles입니다. 후보 순회는 이전의 Scan/CANON generator 활동과 새 Scan generator/CANON filter 활동을 분류합니다. 응답·종료 부분은 각 phase에서 후보 순회·필터를 하지 않는 시간이며 유효한 응답 처리도 포함합니다. 구조 변경 전후에 같은 종류의 동작으로 묶은 비교이며, 전부 제거 가능한 빈 cycle을 뜻하지 않습니다. 파생 표는 `target_comparison.csv`입니다.

Scan 후보 발행 28,166과 Scan drain 31,512는 아직 남습니다. CANON lower bound 재발행은 없어졌고, cache filter는 6,138 cycles에 bound 9,855건을 탈락시켰습니다. 한 cycle에 4개를 탈락시킨 경우는 432건입니다. younger bound packet flush는 656 → 0입니다.

Scheduler의 네 준비 state 중 AP_EXEC_PLAN_WAIT만 demand당 한 번 남아 7,403 cycles입니다. policy_stall까지 포함한 제어·stall 점유는 51,910 → 25,118 cycles입니다. 전체 cycle 감소 26,792 중 22,209는 준비 state 제거, 나머지 4,583은 stall 감소입니다. 두 값과 solver busy를 다시 합산하면 겹치는 시간을 중복 집계하게 됩니다.

## verification

- policy search mode 5 대 독립 Exhaustive DFS(mode 0): 323 cases, errors=0. 모든 발행 lower bound와 읽어온 cache lower bound도 기존 순차 relaxed algorithm으로 대조했습니다.
- policy search mode 6 대 mode 0: 323 cases, errors=0. 단일 후보의 cost lower bound 계약도 검사했습니다.
- a Checkpoint-Capacity of 4 and 8-shot Lookahead 집중 검사: 13 cases, errors=0. universe 13개와 root 후보 220개, bank 경계, 재귀 후 부모 cache 복구를 포함합니다.
- a Checkpoint-Capacity of 4 and 8-shot Lookahead의 policy search mode 6도 37 cases, errors=0으로 검사했습니다. 단일 후보의 입력 단계 판정과 큰 cache를 함께 사용하며 `seed_replay6_h8.log`에 보존했습니다.
- `CANON_LANES=1/2`: 각각 323 cases, errors=0. 4-lane 검사에서 한 cycle에 4개 pruning도 관측했습니다.
- 1-shot Lookahead 경계: 35 cases, errors=0. 단일 후보·epoch wrap·soft reset 검사도 268 cases, errors=0입니다.
- Common500 단독 결정 7,403건, 통합 500 workloads 모두 통과했습니다.
- 최종 Verilator 경고는 94 → 92개이고 새 경고 메시지는 없습니다. 기존 경고 전체를 해결한 것은 아닙니다.

test 결과는 `seed_replay.log`, `seed_replay6.log`, `seed_replay_h8.log`, `lane1.log`, `lane2.log`, `horizon1.log`, `single_action.log`에 보존했습니다. 8-shot Lookahead 결과는 집중 정확성 검사이며 8-shot Lookahead Common500의 총 cycles benchmark가 아닙니다.

### 전체 RVX SoC

platform `/opt/rvx/platform/bbht_grover_policy_parallel_paths_final`에 benchmark snapshot과 같은 RTL·생성 adapter를 설치했습니다. `soc_source_sha256.json`으로 byte-compare와 입력 hash를 보존했습니다. Questa console은 **5분 04초, Errors 0 / Warnings 0**으로 완료했습니다. 같은 source의 Verilator console 순서 replay와 RUN·STAT·ENUM 및 명령 응답 90개 항목이 일치합니다. `soc_qtsim.log`, `console_reference.csv`, `soc_equivalence.json`, `verify_soc.py`가 근거입니다.

기존 checker는 이번 같은 source 비교를 통과하지만 과거 final configuration의 cycles까지 비교하므로 차이 5건으로 exit 5를 반환합니다. 이 결과는 `soc_crosscheck.txt`에 보존하고, 이번 source CSV를 직접 검증하는 `verify_soc.py`로 현재 configuration의 동등성을 따로 확인했습니다. 과거 benchmark value나 checker 기준은 바꾸지 않았습니다.

### 문서 검사

`doc_check_before.log`와 `doc_check.log`의 진단 목록은 같습니다. 기존 papers 이동 경로와 memo table 절 anchor 등 오류 62건·경고 6건이 남아 있으며 새 진단은 없습니다. 전체 문서 검사가 통과한 것은 아니며 다른 작업의 문서 이동·삭제는 변경하지 않았습니다.

## 재현과 남은 작업

단일 configuration은 `dse.py --config config.json --out <새 결과 디렉터리> --stages policy,sim,report`로 재현합니다. 후보 병렬도 검사는 `tb_policy_seed_replay.CANON_LANES`를 1/2/4로 바꿉니다. 큰 Checkpoint-Capacity · Lookahead-Shots의 전체 성능 sweep은 수행하지 않았습니다.

이번 source의 200T implementation·WNS/WHS·실제 resource와 board benchmark는 미검증이며 commit하지 않았습니다. 기존 background placement · routing의 진행 상황과 결과를 조회하지 않았고 새 Vivado도 시작하지 않았습니다. memo table clear는 바꾸지 않아 8-shot Lookahead의 1회 8,744 cycles가 남습니다. DFS 방문 state 수와 Scan의 한 후보/clock 발행도 남으므로 큰 Checkpoint-Capacity · Lookahead-Shots에서도 policy 총 300,000 cycles 이내라는 목표는 아직 완료되지 않았습니다.
