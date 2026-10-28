# solver · scheduler 병목 진단 — 2026-10-28

현재 RTL을 바꾸지 않고 a Checkpoint-Capacity of 3 · 3-shot Lookahead · 4 PEs · Triple-Row Build · policy search mode 6 한 configuration의 Common500을 관측했습니다. 결과 · executed iterations · 총 cycle · policy counter를 포함한 `bench.csv`는 직전 검증 revision의 같은 CSV와 byte 단위로 동일합니다. 진행 중인 200T placement and routing의 상태나 결과는 조회하지 않았습니다.

## 범위와 재현

- 현재 `grover_policy.v` SHA-256: `77e2f67d25e3cb32ec2767f7920c78c4451209bd5b99af4ce873e212cfec3627`.
- 현재 `bbht_grover_main_ip.v` SHA-256: `0553299ca6164b0114f1728d979a141bdf7b34df2779500abcb037b1192d2ca1`.
- 두 file은 기존 Verilator model `/tmp/bbht_dse_232024438d8af95c/src`의 file과 동일합니다. model의 전체 입력 hash는 `source_manifest.json`에 보존했습니다. 해당 manifest의 workload_limit=20은 model을 처음 만들 때의 실행 설정입니다. 이번 관측 실행은 같은 model에 BENCH_LIMIT=500을 사용했습니다.
- core · Bus Interface RTL 13개와 `grover_param.vh`도 현재 source와 byte-compare로 일치했습니다. 생성 adapter는 `MEAS_BUILD_ROWS=3`을 명시해 전달합니다. 기존 model의 adapter는 legacy 설정으로 같은 Triple-Row Build를 선택하므로 기능 구성은 같지만, adapter file 자체는 주석과 명시 parameter 추가 때문에 byte 동일하지 않습니다.
- `tb_profile.cpp`는 기존 `tb_bench500.cpp`에 관측 header와 rising edge 직전 `profile_sample(top)` 호출만 추가한 testbench입니다. `profile.h`는 settled RTL state를 읽기만 하며 어떤 signal도 수정하지 않습니다.
- 관측 harness만 다시 compile하고 기존 model archive, runtime objects, 실제 driver object와 link했습니다. model 재합성 · Verilator RTL 재생성은 하지 않았습니다.
- 실행: `WL_DIR=/workspace/hardware_bram/results/2026-10-28_policy_unpipeline_final/workload BENCH_LIMIT=500 /tmp/policy_bottleneck.Kc1Pv7/profile_bench`.
- 원시 profiling 기록은 `profile.log`, workload별 verification 결과는 `bench.csv`입니다. `dse.validate_bench(..., 500)`의 reference model BBHT trajectory verification을 통과했습니다. 이전 CSV의 policy replay/executed iterations verification도 그대로 유지되며, 이번 CSV가 이전 CSV와 완전히 동일함을 확인했습니다.
- 기존 비교 CSV: `../2026-10-28_policy_unpipeline_final/k3h3_e4_b3_p6/bench.csv`.

## profiling 결과

500 workloads, demand 7,403건, executed iterations 9,582회, 전체 4,554,476 cycles, 보고된 policy 309,000 cycles, 실제 demand stall 26,920 cycles입니다. 별도로 관측한 solver의 전체 busy는 309,802 cycles입니다. 차이 802 cycles는 epoch가 오래되어 집계에서 제외된 완료 두 건의 비용과 정확히 같습니다.

### solver busy 분해 — 상호 배타적

| phase | cycles | 전체 solver busy 비중 |
|---|---:|---:|
| memo table clear | 11,811 | 3.81% |
| Build | 63,224 | 20.41% |
| ROOT_INIT | 7,903 | 2.55% |
| frame PREP | 16,227 | 5.24% |
| Scan 후보 발행 | 33,889 | 10.94% |
| Scan 배출 대기 | 68,851 | 22.22% |
| SEED 대기 | 12,267 | 3.96% |
| canonical 후보 발행 | 17,210 | 5.56% |
| canonical 배출 대기 | 37,642 | 12.15% |
| DFS RETURN + RETURN_EVAL | 16,648 | 5.37% |
| FINISH | 16,227 | 5.24% |
| ROOT_DRAIN | 7,903 | 2.55% |
| 합계 | 309,802 | 100% |

배출 대기 두 phase의 sum은 106,493 cycles(34.37%)입니다. 이 분류는 generator가 소진된 state의 해당 phase 시간을 뜻하며, 전부 제거 가능한 빈 cycle이라는 뜻은 아닙니다. 실제 bound/BRAM 응답 처리·종료 제어도 이 phase에 포함됩니다.

solver 완료 7,903건 중 root 단일 후보는 5,723건(72.42%)입니다. 이 경우도 Scan/bound 뒤에 단축됩니다. canonical bound output 16,554건 중 이미 seed로 평가한 후보와 동일한 tuple의 재등장은 4,515건입니다. memo table miss 8,324건에서 flush된 younger bound packet은 656개입니다. 따라서 이 configuration에서 flush 재작업을 최상위 병목이라고 단정할 근거는 약합니다.

### scheduler stall 분해 — 상호 배타적

| stall state | cycles | 의미 |
|---|---:|---|
| AP_DEMAND_CHECK | 7,403 | Plan Queue hit도 포함하는 request당 한 번의 검사 |
| AP_COLD_WAIT_SHADOW | 4,610 | 첫 실제 solve 전 준비 대기 |
| AP_COLD_POLICY_REQ | 500 | 실제 solve request 제어 |
| AP_COLD_POLICY_WAIT | 12,024 | 실제 solve 완료와 결과 수신 대기 |
| AP_WAIT_LATE_SPEC | 2,383 | 예측이 맞지만 아직 완료되지 않은 request 대기 |
| 합계 | 26,920 | 기존 policy_stall과 일치 |

- stall 중 solver busy: 13,893 cycles. solver가 busy가 아닌 stall: 13,027 cycles. 후자는 검사/request/완료 수신의 제어 주기와 Iteration-Count Predictor 대기를 포함하므로 전부 solver 가속으로 없어지지는 않습니다.
- cold 대기 4,610 cycles 중 Iteration-Count Predictor 미완료는 4,110, 준비 완료 후 다음 state로 가는 주기는 500입니다. cold가 기존 solver busy 때문에 막힌 주기는 이번 workload에서 0입니다.
- demand 도착 즉시 Plan Queue hit 6,889건, 일치하는 in-flight 결과를 기다린 request 14건, cold 500건입니다. 14건도 결국 Plan Queue에서 받으므로 pop은 6,903건입니다.
- 관측한 Plan Queue 점유는 0 또는 1뿐입니다. 깊이가 4여도 demand당 한 번의 speculation 제한으로 연속 refill하지 않습니다.
- AP_EXEC_WAIT 동안 첫 speculation을 끝내고 solver가 쉬면서 Plan Queue 여유가 있는 시간이 2,468,089 cycles입니다. 연속 speculative planning의 기회 시간이며 그만큼의 stall을 줄일 수 있다는 뜻은 아닙니다.
- stale solver 때문에 실제 demand가 기다린 시간은 이번 Common500에서 0입니다. 취소 불가 구조는 code에 있지만 현재 benchmark의 주요 stall 원인으로 분류하지 않았습니다. ENUM·문맥 변경 및 더 큰 Checkpoint-Capacity · Lookahead-Shots에서는 별도 확인이 필요합니다.

## code에서 확인한 개선 후보

1. `grover_policy.v`의 PH_SCAN → PH_SEED → PH_CANON 구조는 후보/lower bound를 두 번 생성합니다. seed 자체도 canonical에서 재등장합니다. frame별 bound 저장 또는 seed 재등장 생략은 검토 대상입니다.
2. root 단일 후보에서도 전체 bound 응답을 기다립니다. 출력 계획만 필요하고 root_cost가 lower bound여도 되는 policy search mode 6 계약을 이용하면 조기 반환 경로를 검토할 수 있습니다.
3. Build는 solve마다 4 checkpoint slots와 request (Lookahead-Shots + 1)개를 직렬 처리합니다. a Checkpoint-Capacity of 3 · 3-shot Lookahead에서는 고정 8 cycles이고, 7,903회 누적되어 63,224 cycles입니다. 준비 작업의 병렬화/overlap은 후보지만 현재 root initialization·정렬 timing과 함께 검토해야 합니다.
4. 현재 단일 DFS frame을 실행하고 동기 memo table을 읽는 구조는 여러 state를 같은 층에서 병렬 처리하는 구조가 아닙니다. hierarchical DP로 바꿀 때는 state merge와 BRAM read-modify-write 충돌 처리가 필요합니다.
5. a Checkpoint-Capacity of 3 · 3-shot Lookahead 이외 configuration은 `MEM_ENTRIES = LOOKAHEAD_SHOTS * STATE_RANKS`(`STATE_RANKS` = 1093)를 직렬 clear합니다. 8-shot Lookahead의 clear는 8,744 cycles입니다. 이는 이번 3-shot Lookahead profiling 수치가 아니라 code로 확정되는 8-shot Lookahead 비용입니다.
6. Accelerator Core의 `spec_launched_for_demand`는 한 request 앞까지만 계산하도록 제한합니다. 연속 refill의 개선 여지는 있으나 현재 3-shot Lookahead에서 늦은 speculation은 14건뿐이므로 큰 효과를 미리 보장하지 않습니다.
7. Lookahead-Shots ≤ 6에서는 `SHADOW_FUTURES=7`로 고정되어 있습니다. 3-shot Lookahead의 한 request 앞 계획에 필요한 미래 number of iterations는 4개지만 7개가 끝날 때까지 ready를 내지 않습니다. 기존 cycle identity 보존용 제한이며 시작 latency 개선 대상입니다.
8. 일치하는 늦은 결과도 done에서 직접 전달하지 않고 Plan Queue push 후 다음 주기에 수신합니다. 직접 전달은 제어 latency 단축 후보이며 flush/tag 우선순위를 유지해야 합니다.
9. 진행 중인 speculation을 취소할 수 없고 stale 결과를 끝에서 버립니다. code상 잠재 대기 원인이지만 이번 Common500에서 exposed stale wait는 0입니다.

## 성능 해석과 확장 시 주의

- `memo_pipe_hit`는 실제 epoch hit뿐 아니라 `mresp_direct`도 hit로 분류합니다. 관측 hit 8,307건 중 직접 계산은 5,723, 실제 memo table hit는 2,584입니다. 기존 hit 수를 순수 BRAM hit rate로 해석하면 안 됩니다.
- `policy_actions_last = act_ctr + prune_ctr`에는 최초 Scan의 모든 발행 작업이 포함되지 않습니다. actions만 보고 전체 계산량을 추정하면 Scan 비용이 빠집니다.
- `policy_cycles_run`은 current epoch의 done만 집계하므로 stale 계산의 실제 busy 비용을 누락합니다. raw busy, useful 완료, stale 완료를 분리하면 최적화를 평가하기 쉽습니다.
- Plan Queue가 full인 주기에 pop과 push를 함께 요청하면 현재 Plan Queue는 push를 받지 않습니다. 현재 one-ahead 경로에서는 full이 관측되지 않아 오류로 이어지지 않았습니다. refill 확대 시 자리 예약·결과 backpressure·full+pop 지원 중 하나를 설계해야 합니다.
- Iteration-Count Predictor의 재시작 cap은 runtime `run_shot_cap`이 아니라 `GP_SHOT_CAP_DEFAULT`입니다. 이번 cap=100 workload에서는 일치합니다. 다른 cap과 문맥 재시작을 지원할 때는 예측 계약을 별도로 검증해야 하며, 현재 functional failure를 재현한 것은 아닙니다.
- 일부 주석은 제거된 3단 timing evaluation pipeline(`E0`/`E1`/`E2`)과 옛 a Checkpoint-Capacity of 4 · 7-shot Lookahead 설명을 남겨 실제 구조와 다릅니다. source 주석만으로 latency를 판단하면 안 됩니다.
- 이번 verification에서 기능 오류는 관측하지 못했습니다. 이는 위 구조적 비효율이나 현재 workload 밖의 잠재 문제를 부정하는 결과는 아닙니다.

## 우선순위

현재 3-shot Lookahead benchmark에서는 root 단일 후보 조기 반환, bound 배출 latency, 고정 Build 준비 비용이 solver의 우선 후보입니다. scheduler에서는 Iteration-Count Predictor ready latency와 request 검사/결과 공급의 제어 시간을 먼저 봅니다. 더 깊은 speculative planning은 Checkpoint-Capacity · Lookahead-Shots가 커졌을 때의 latency 변동을 흡수할 후보이며 3-shot Lookahead의 현재 최대 병목이라고 단정하지 않습니다. 모든 효과는 수정 후 동일 configuration의 RTL cycle로 확인해야 합니다.

진단용 testbench와 결과만 추가했습니다. 제품 RTL·firmware·parameter는 수정하지 않았고 commit도 하지 않았습니다.
