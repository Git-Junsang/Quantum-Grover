# Seed 재발행 생략과 segment 병렬 lower bound — 2026-10-28

목표는 같은 Common500에서 Checkpoint-Capacity · Lookahead-Shots를 키워도 통합 policy cycles를 약 300,000 이내로 유지하는 것입니다. 이번 변경은 이미 정확히 평가한 seed의 재발행을 생략하고, Lookahead-Shots에 비례하던 lower bound 계산 latency를 고정 깊이의 segment별 병렬 계산으로 바꿉니다. 전체 solver의 state 수나 search 복잡도가 일정해진다는 의미는 아닙니다.

## source와 범위

- 제품 RTL 변경은 `hardware_bram/src/grover_policy.v`입니다. SHA-256: `1c85c4c7fc82c460dc439b97bee65dc5bc9dcd27c882abf4dc126bf11dc14118`.
- 입력 source · configuration은 `manifest.json`과 `source/`, 단일 configuration은 `config.json`에 보존했습니다. a Checkpoint-Capacity of 3, 3-shot Lookahead, 4 PEs, Triple-Row Build, policy search mode 6, Common500 한 configuration입니다. number of PEs · Build나 scheduler 제어는 바꾸지 않았습니다.
- baseline은 [단일 후보 조기 반환 revision](../2026-10-28_policy_single_action/evidence.md)입니다. mode 6의 단일 후보 `root_cost`가 즉시비용 lower bound라는 계약도 유지합니다.
- 앞서 제거한 WNS용 `actionq/mreq/areq`는 복구하지 않았습니다. seed의 생성 위치를 보존하는 register는 중복 후보를 식별하는 algorithm state며 latency 단계를 추가하지 않습니다.

## 1. 정확히 평가한 seed를 다시 발행하지 않음

Scan은 lower bound가 가장 작은 후보를 seed로 고르고, SEED는 그 후보의 실제 비용을 memo table hit 또는 child의 exact search로 얻습니다. 이후 CANON에서 같은 후보를 재발행해도 값은 바뀌지 않습니다.

Scan의 running minimum과 함께 deposit/retention 생성 위치를 보존하고, 선택된 위치는 DFS frame별로 저장합니다. CANON에서 해당 위치를 만나면 generator만 전진하고 bound·memo table은 발행하지 않습니다. root의 segment/tuple 동점 규칙은 seed를 처음 정확히 평가할 때 이미 적용됩니다. child search에서 복귀하면 부모의 seed 위치도 복구하며, 다른 오래된 후보의 miss 때문에 flush되는 경우에도 같은 위치를 안전하게 다시 생략합니다.

이 변경만 적용한 중간 revision은 `../archive/policy_optimization/2026-10-28_policy_seed_skip/`입니다. 단독 Common500은 236,054 → 235,241 cycles로 0.3444% 줄고, policy actions는 26,104 → 22,093으로 15.3655% 줄었습니다. 후보 수 감소가 그대로 cycle 감소로 이어지지는 않으므로 이 수정만으로 충분하다고 판단하지 않았습니다.

## 2. Lookahead request들의 순차 lower bound를 checkpoint segment별로 병렬 계산

### 기존 lower bound와 같은 값인 이유

기존 relaxed solver는 Checkpoint-Capacity 제한을 없애고 모든 checkpoint를 유지합니다. request를 처리할 때 source부터 endpoint 사이의 모든 request-pool 값도 저장합니다. 실제 remaining request는 전부 이 pool에 포함됩니다.

초기 checkpoint 값으로 수직선을 여러 segment로 나누면 서로 다른 segment의 계산은 독립적입니다. 한 segment에서 지금까지 가장 큰 request를 처리하면 그 이하의 남은 request들은 이미 저장됩니다. 더 작은 request는 비용이 없고, 더 큰 request는 이전 endpoint부터 늘어난 부분만 계산합니다. 따라서 그 segment의 전체 비용은 request 순서나 중복 횟수와 무관하게 가장 큰 request와 segment 아래 endpoint 사이의 거리입니다. request가 없는 segment와 이미 checkpoint인 request의 비용은 0입니다. 첫 segment는 암묵적으로 사용 가능한 state 0을 아래 endpoint로 사용합니다.

새 `grover_ckpt_gap_bound`는 이 segment별 maximum과 source를 동시에 구하고 비용을 balanced adder tree로 합칩니다. bound를 약하게 바꾸거나 추정값으로 교체한 것이 아니라 같은 unlimited-capacity relaxed cost를 다른 구조로 계산합니다. 기존 pruning 비교와 root 동점 규칙도 유지합니다.

### RTL 단계

1. child checkpoint rank mask와 remaining-request rank mask를 capture합니다.
2. 각 segment의 source와 가장 큰 request를 병렬로 선택해 one-hot으로 저장합니다.
3. segment별 비용 sum과 canonical metadata를 기존 `bo_*`에 함께 저장합니다.

후보 발행부터 FSM이 lower bound를 소비할 때까지 **3 cycles**, throughput은 **cycle당 후보 1개**입니다. 기존 latency는 (남은 Lookahead-Shots + 2) cycles였으므로 root에서는 1-shot Lookahead: 3 → 3, 3-shot Lookahead: 5 → 3, 8-shot Lookahead: 10 → 3입니다. universe 폭에 따라 circuit 크기가 늘어나며, 이 구조의 200T routing timing과 resource는 아직 검증하지 않았습니다.

`values_flat`은 function의 명시적인 입력으로 전달합니다. 같은 rank 선택을 유지한 채 다음 solve에서 rank 값만 바뀌어도 event-driven simulation이 값을 다시 계산하도록 했고, 이를 검증하는 연속 packet 사례도 추가했습니다.

## verification

### lower bound 계산기 단독

`tb_policy_gap_bound.sv`의 oracle은 segment 공식을 사용하지 않고 기존 request별 keep-all/deposit-all algorithm을 직접 실행합니다. UB7에서는 모든 child/future 집합 쌍을, UB13에서는 무작위 집합을 검사합니다. 0 유무, 127, 오름차순/내림차순 request, 빈 집합, 연속 발행, 다음 solve의 값 변경을 포함합니다.

- UB7: 32,780 cases, errors=0.
- UB13: 12,012 cases, errors=0.
- 원시 결과: `gap_bound.log`.

### Solver exact 비교와 frame 복구

`tb_policy_seed_replay.sv`는 mode 5의 선택·source·segment·exact cost를 독립 mode 0과 비교합니다. 발행한 모든 lower bound packet도 기존 순차 lower bound 계산으로 따로 대조합니다. 관측기는 DUT의 seed 생성 위치 대신 seed tuple을 저장하므로 잘못된 후보 생략과 seed의 재발행을 모두 검출합니다.

- a Checkpoint-Capacity of 3 and 3-shot Lookahead: 323 cases, errors=0, lower bound 4,023건 대조. seed 생략 399건, 비-root 생략 203건, seed hit 22건, seed miss 702건, canonical miss 78건, root equal-bound 78건.
- a Checkpoint-Capacity of 4 and 8-shot Lookahead: 12개 집중 verification 사례, errors=0, lower bound 2,724건 대조. 13개 universe 값을 모두 사용하는 사례와 오래된 miss가 발생하는 주기의 seed 생략을 포함합니다. 전체 Checkpoint-Capacity · Lookahead-Shots 성능 sweep은 아닙니다.
- 기존 단일 후보 test: 268 cases, errors=0, initial/wrap/reset clear 3건 유지.
- 원시 결과: `seed_replay.log`, `seed_replay_h8.log`, `single_action.log`.

### Common500

단독 mode 6은 기존 exhaustive trace의 결정 7,403개를 모두 통과했습니다. 결과는 `k3h3_e4_b3_p6/rtl_p6_k3h3.log`입니다. 최종 source로 새 Verilator model을 만든 통합 실행도 `# DONE errors=0 workloads=500`으로 완료했습니다.

| RTL 지표 | 직전 단일 후보 조기 반환 revision | 이번 최종 revision | 감소 |
|---|---:|---:|---:|
| 단독 policy cycles | 236,054 | 220,262 | 6.6900% |
| 통합 policy cycles | 257,511 | 239,873 | 6.8494% |
| 실제 policy stall | 22,339 | 22,298 | 0.1835% |
| 전체 checkpoint 실행 cycles | 4,549,895 | 4,549,854 | 0.0009% |
| 단독 policy actions | 26,104 | 22,093 | 15.3655% |
| 통합 policy actions | 28,819 | 24,304 | 15.6667% |
| 단독 최대 latency | 481 | 472 | 9 cycles |
| executed iterations | 9,582 | 9,582 | 동일 |

`dse.validate_bench(..., 500, reference_iterations)`로 workload별 reference model BBHT trajectory와 executed iterations를 확인했습니다. 수정 전후 1,000 rows의 workload · mode · 결과 · shot · requested iterations · executed iterations · mismatch가 모두 같으며 Restart mode row는 전 field가 같습니다. policy 계산 대부분이 실행에 겹쳐 있으므로 이번 solver 작업 감소가 실제 stall에 드러난 것은 41 cycles입니다. 현재 configuration의 exposed stall을 크게 줄였다고 해석하지 않습니다.

최종 `sim_build.log`의 Verilator 경고는 직전 revision 96개에서 94개이며 새 경고 메시지는 없습니다. 새 gap circuit은 단독 Verilator lint도 경고 없이 통과했습니다. 기존 action/planner 및 산술 circuit의 경고를 이번에 해결한 것은 아닙니다.

### 문서 검사

`doc_check_before.log`와 `doc_check.log`의 진단 목록을 비교했습니다. 기존 이동된 papers 경로와 memo table 절 anchor 등의 오류 62건·경고 6건이 그대로이며 새 진단은 없습니다. 전체 문서 검사가 통과한 것은 아닙니다. 다른 작업의 문서 이동·삭제는 수정하지 않았습니다.

### 전체 SoC

새 platform `/opt/rvx/platform/bbht_grover_policy_gap_bound_final`에 같은 snapshot과 생성 adapter를 설치했습니다. `soc_source_sha256.json`은 설치된 user RTL·include·driver·console source hash며, RTL과 adapter가 통합 Common500 snapshot과 byte 동일함을 확인했습니다. RVX `make syn`은 platform 생성만 수행했고 Vivado implementation은 시작하지 않았습니다.

전체 RVX SoC의 Questa console simulation은 **5분 04초, Errors 0 / Warnings 0**으로 완료했습니다. 같은 Verilator model archive에 console harness를 연결해 같은 실행 순서를 재현했고, RUN 3건의 HIT 5개·STAT 15 fields, 명령 종결자와 ENUM 순서·cycles 등 **90개 항목이 일치**했습니다. enumeration 결과는 8,685 / 2,852 / 507 / 4,724입니다. `verify_soc.py`로 재검사하며 결과는 `soc_equivalence.json`입니다.

원시 Questa log는 `soc_qtsim.log`, console harness와 build·기준 출력은 `source/tb_console_seq.cpp`, `console_build.log`, `console_reference.csv`입니다. app compile에서 `BBHT_CONSOLE_SCRIPT`가 적용된 것도 확인했습니다.

기존 `soc_console_check.py`는 같은 source의 Verilator 비교를 모두 통과하지만 예전 final configuration의 board · campaign cycles 및 cycle/stall 차이까지 대조하여 exit 5를 반환합니다. 해당 차이 5건은 `soc_crosscheck.txt`에 그대로 보존했습니다. 현재 configuration과 예전 final configuration의 cycle 비교를 통과했다고 주장하지 않습니다. 새 `verify_soc.py`는 실제 이번 reference CSV로 같은 순서의 field를 직접 검사하며, 과거 checker의 결과나 기준값을 변경하지 않습니다.

### 수정 후 병목 재관측

같은 새 Verilator model에 읽기 전용 observer를 연결했습니다. `bench_profile.csv`는 최종 통합 `bench.csv`와 byte 동일합니다. 전체 solver busy는 240,657 cycles이며, 집계 policy 239,873과의 차이 784는 stale 완료 두 건의 cycles와 같습니다.

- Build: 63,224 cycles, busy의 26.27%.
- memo table clear: 11,811 cycles, 4.91%.
- PREP: 16,227 cycles, 6.74%.
- canonical seed 생략: 4,515건, 관측한 canonical seed 재등장: 0건.
- 전체 demand stall 22,298 중 solver busy 9,271 / solver가 busy가 아닌 제어·Iteration-Count Predictor 대기 13,027 cycles.

원자료는 `profile.log`, 구조화한 값은 `profile.json`, observer는 `profile.h`와 `tb_profile.cpp`입니다. 관측 때문에 제품 RTL을 다시 생성하거나 바꾸지 않았습니다. 이 3-shot Lookahead profile만으로 8-shot Lookahead의 병목 비중을 대신하지 않습니다.

### 구간별 비중과 후속 개선 후보

아래 두 표는 같은 profile에서 서로 다른 분모를 사용합니다. Solver busy와 scheduler state 점유는 겹치므로 합산하지 않습니다. 설정 clock은 100 MHz이며 두 block은 같은 accelerator clock을 사용합니다. 최신 RTL의 200T routing timing은 미검증이므로 이 주파수나 CSV의 환산 시간을 board benchmark로 취급하지 않습니다.

Solver 표의 분모는 stale 계산을 포함한 실제 busy 240,657 cycles입니다. 후보 순회에는 이미 평가한 seed를 발행하지 않고 건너뛰는 주기도 포함됩니다. 배출 대기에는 유효한 bound/memo 응답 처리도 포함되며, 전체를 제거 가능한 빈 주기로 해석하지 않습니다.

| Solver 구간 | cycles | busy 비중 |
|---|---:|---:|
| Build | 63,224 | 26.27% |
| Scan/CANON 후보 순회 | 45,376 | 18.86% |
| Scan/CANON 배출 대기·응답 처리 | 54,517 | 22.65% |
| frame PREP | 16,227 | 6.74% |
| DFS RETURN/RETURN_EVAL | 16,648 | 6.92% |
| memo table clear | 11,811 | 4.91% |
| SEED 대기 | 6,544 | 2.72% |
| root initialization·완료·단일 후보 직행·ROOT_DRAIN | 26,310 | 10.93% |
| 합계 | 240,657 | 100% |

Scheduler는 전체 실행 4,549,854 cycles 동안 유지되는 FSM입니다. 그중 AP_EXEC_WAIT 2,631,567 cycles와 AP_IDLE 1,866,377 cycles를 policy 제어 비용으로 더하지 않습니다. 나머지 제어·대기 state 점유는 51,910 cycles이며 전체 실행의 1.14%입니다. 아래 비중의 분모는 이 51,910 cycles입니다.

| Scheduler 구간 | cycles | 제어·대기 점유 비중 |
|---|---:|---:|
| 입력 정렬 · Checkpoint Planner request · plan packet 수신 · Checkpoint Executor 시작 | 29,612 | 57.04% |
| demand/Plan Queue 검사 | 7,403 | 14.26% |
| Iteration-Count Predictor 준비 대기 | 4,610 | 8.88% |
| cold solver request | 500 | 0.96% |
| cold solver 완료 대기 | 7,524 | 14.49% |
| 늦은 speculative planning 완료 대기 | 2,261 | 4.36% |
| 합계 | 51,910 | 100% |

기존 policy_stall 22,298은 마지막 다섯 row의 sum이며 첫 row의 네 state는 포함하지 않습니다. 첫 row는 네 state가 각각 demand당 한 번, 총 7,403 cycles씩 점유한 값입니다. Accelerator Core의 `u_ckpt_planner_pipe`와 `auto_plan_pipe_*`에는 Checkpoint Planner · Checkpoint Executor 사이의 timing용 pipeline register가 남아 있습니다. 앞서 제거한 solver 내부 `actionq/mreq/areq`와는 구분하여 검토해야 합니다.

후속 후보는 아직 implementation·성능 verification 전입니다.

1. **Build:** 7,903 solve 중 단일 root 후보가 5,723건입니다. 현재 이 경로도 8-cycle Build 이후에야 단축됩니다. 입력에서 유일 후보를 먼저 판정해 universe/rank 준비를 생략하거나, 빈 checkpoint slot을 건너뛰고 여러 입력을 병렬 등록하는 방법을 비교합니다.
2. **Scan/CANON:** 첫 Scan의 lower bound를 저장해 CANON에서 재사용합니다. 현재 seed만 생략하며 나머지 후보의 lower bound는 재계산합니다. 저장 공간·읽기 bandwidth·재귀 frame 보존 비용도 포함해야 합니다.
3. **응답 대기:** memo table 조회와 lower bound 계산을 겹치거나, 독립적인 frame 작업을 이어 발행하는 방법을 검토합니다. 앞선 request가 miss일 때 younger packet을 취소하는 순서와 root 동점 규칙을 유지해야 합니다.
4. **큰 Lookahead-Shots의 initialization:** epoch 확장, 실제 도달 state만 저장하는 memo table 압축, background clear를 비교합니다. epoch 확장은 wrap 청소 빈도를 낮추지만 첫 initialization이 없어지는 것은 아니며 저장 폭·BRAM 비용이 늘 수 있습니다.
5. **Scheduler:** 입력 정렬과 Plan Queue match 겹치기, Checkpoint Planner · Checkpoint Executor 단계 통합, Lookahead-Shots에 맞춘 Iteration-Count Predictor 생성, 일치하는 완료 결과의 Plan Queue 우회 전달을 검토합니다. 단계 통합은 200T timing verification이 필요합니다. 한 request 이상 선행 계산은 stall을 숨길 수 있지만 solver 총 계산량이 줄어드는 것은 아닙니다.

원자료에서 파생한 표는 [solver_breakdown.csv](solver_breakdown.csv), [scheduler_breakdown.csv](scheduler_breakdown.csv)입니다.

## 재현 명령

저장소 루트에서 실행합니다. test source는 `source/`에도 보존했습니다.

```bash
iverilog -g2012 -s tb_policy_gap_bound -I hardware_bram/src \
  -o /tmp/policy_gap_bound_test hardware_bram/testbench/tb_policy_gap_bound.sv hardware_bram/src/grover_policy.v
vvp /tmp/policy_gap_bound_test
iverilog -g2012 -s tb_policy_seed_replay -I hardware_bram/src \
  -o /tmp/policy_seed_replay_test hardware_bram/testbench/tb_policy_seed_replay.sv hardware_bram/src/grover_policy.v
vvp /tmp/policy_seed_replay_test
iverilog -g2012 -s tb_policy_seed_replay -I hardware_bram/src \
  -P tb_policy_seed_replay.CHECKPOINT_CAPACITY=4 -P tb_policy_seed_replay.LOOKAHEAD_SHOTS=8 \
  -P tb_policy_seed_replay.RANDOM_CASES=8 -P tb_policy_seed_replay.REQUIRE_COVERAGE=0 \
  -o /tmp/policy_seed_h8_test hardware_bram/testbench/tb_policy_seed_replay.sv hardware_bram/src/grover_policy.v
vvp /tmp/policy_seed_h8_test
```

Common500은 같은 source snapshot에 기존 exhaustive `policy_trace.txt`와 workload별 `reference_iterations.json`을 입력해 새 RTL로 실행했습니다. trace의 선택 결과나 benchmark value는 수정하지 않았습니다. `dse.py --config config.json --out <새 결과 directory> --stages policy,sim,report`로도 재현할 수 있습니다.

## 남은 범위

DFS의 방문 state 수, Scan 전체 후보 재생성, Build, memo table clear는 남아 있습니다. 특히 a Checkpoint-Capacity of 3 and 3-shot Lookahead 이외 memo table은 255 solve마다 Lookahead-Shots × 1,093 data words를 clear하며, 8-shot Lookahead는 1회 8,744 cycles입니다. 8-shot Lookahead에서도 총 policy를 300,000 이내로 유지하려면 이 비용을 함께 개선해야 합니다. 이번 변경만으로 큰 Checkpoint-Capacity · Lookahead-Shots의 전체 cycles가 300,000 이내가 되었다고 주장하지 않습니다.

이번 RTL의 전체 RVX SoC Questa verification은 완료했으며 200T implementation·board benchmark와 commit은 미실시입니다. 기존 background placement · routing의 상태나 결과를 조회하지 않았고 새 Vivado도 시작하지 않았습니다. `../archive/policy_optimization/2026-10-28_policy_gap_bound/`는 최종 revision과 같은 논리의 중간 실행입니다. 최종 revision은 Verilator가 array 전체를 한 단위로 보면서 내는 false-feedback 경고를 피하도록 `split_var` 주석을 추가한 뒤 새 snapshot으로 재검증했습니다.
