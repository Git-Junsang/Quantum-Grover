# Parameterized Main IP: Scheduler · Planner · Executor integration

작업 완료 기록: 2026-10-29. 결과 directory는 시작일 이름을 유지합니다.
사용자가 승인한 세부 단계 1~6의 구현과 선택한 조합의 integration 검증입니다.
전체 Common500 campaign은 7번 단계로 남아 있습니다. 전체 조합 sweep은 실행하지 않았습니다.

## 구현 범위

| 단계 | 반영한 내용 |
|---|---|
| 1. 기준 고정 | 기존 `k3h3_e4_b2_p6` source와 결과를 [baseline.json](baseline.json), [before](before/)에 보존 |
| 2. 내부 interface | Checkpoint-Capacity에 맞춰 tuple · valid mask · count · slot · boundary packet · plan FIFO 폭 확장 |
| 3. Metadata / Planner | 동적 슬롯 정렬 · retain / clear / allocation, immutable input snapshot, 다섯 번째 이후 boundary 처리 |
| 4. Executor | parameter 폭 packet 해석, source 보존, bridge 1 iteration 후 목적지 in-place 실행, 완료 후 metadata commit |
| 5. 실제 연산 경로 | iteration engines 1~16의 row issue / read latency / tail mask / drain, square engines 1~4와 16×32 Two-Level Select 연결 |
| 6. Scheduler | demand / speculation · FIFO matching · flush · epoch · warm restart, 취소된 in-flight 결과의 재수락 차단 |

설정은 [`generalize_config.json`](../../sim/generalize_config.json)의 `schema: 2` 한 개를 읽습니다.
`k` / `h`는 Checkpoint-Capacity / Lookahead-Shots 각각 1~10,
`e`는 iteration engines 1~16, `m`은 square engines 1~4입니다.
square engine 하나는 **한 row의 32 lanes를 제곱하는 블록**입니다.
새 설정의 `m`은 과거 Measurement Microarchitecture 이름의 번호와 구분합니다.

내부 slot 수는 `max(4, CHECKPOINT_CAPACITY)`, 확장 count / slot 폭은 각각
`clog2(CHECKPOINT_CAPACITY+1)` / `clog2(CHECKPOINT_CAPACITY)`입니다.
현재 요청을 포함한 policy window는 `max(9, LOOKAHEAD_SHOTS+1)`개를 전달합니다.
Iteration-Count Predictor는 speculative 다음 요청에도 필요한 future 값을 생성합니다.
외부 수동 policy ABI는 기존 4-slot 계약을 유지하고 automatic policy의 내부 폭을 확장했습니다.

`GENERALIZED_RTL=1`은 기존 지원 조합도 새 physical kernel로 실행합니다.
확장 조합은 parameter 조건에 의해 자동 선택됩니다. 기존 지원 조합의 기본 solver는 최신 optimized
rolling backend이며 확장 조합은 parameterized exact backend입니다. `force_generic: true`로
기존 지원 조합도 같은 generic backend를 강제할 수 있습니다. **backend가 다른 cycle을 같은
최적화 구현의 scaling 결과로 해석하지 않습니다.**

기존 Scheduler의 `AP_*` / `SP_*` FSM과 solver 모듈 분리는 유지했습니다. 새 별도 scheduler 모듈로
재작성한 작업은 아닙니다. 발행 시 demand가 우선하며 이미 실행 중인 speculation은 완료까지 진행할 수
있습니다. flush 때 `policy_active_stale`을 유지하여 8-bit epoch가 재사용되어도 취소한 결과를 FIFO나
Executor에 다시 넣지 않습니다. 유용한 metadata snapshot 경계는 유지하며 timing-only action queue를
재도입하지 않았습니다.

새 physical kernel은 실제 amplitude memory / iteration / measurement를 구동합니다. 단순 cycle 모델을
기존 datapath 대신 연결한 것이 아닙니다. 데이터와 Found Mask의 engine별 복제는 simulation 우선 구조이며,
이 확장 경로의 200T resource / timing 적합성은 검증하지 않았습니다.

## 검증 방법과 source

현재 구현 source와 시험 도구는 [verified_source](verified_source/) 및
[verified_source_sha256.json](verified_source_sha256.json)에 있습니다.
Main integration 각 directory의 `manifest.json`은 별도의 immutable source hash를 기록합니다.
최종 시험들의 RTL hash와 현재 작업 source를 대조했습니다.
[summary.json](summary.json)은 완료 범위와 최종 결과 경로를 모읍니다.
[final_checks.json](final_checks.json)에 198개 source hash 대조, 이전 prefix 4행 동일성,
보호 firmware 17개 · background 입력 28개 보존, CSR / port 계약과 문서 오류 0건을 기록했습니다.

실제 C driver → APB/AHB wrapper → Main IP를 Verilator로 실행했습니다.
수동 cycle 추정 대신 RTL의 실제 solver start / done / plan acceptance를 관측합니다.
각 solver 입력의 checkpoint 집합과 요청 window에 대해 독립 Python exhaustive DP의 source와 선택 tuple을
대조하고, 실제 transaction clock 차이가 RTL `policy_cycles_last`와 같은지 확인합니다.
Executor가 수락한 plan은 flush generation · epoch · 현재 요청 · 입력 집합까지 일치하는 완료 job으로
추적합니다. 취소된 job은 epoch 값이 같아져도 다른 generation으로 남습니다.

정식 Common500 입력의 **앞 2 workloads**만 각 설정에 사용했습니다. Normal / Checkpoint의 결과,
shots, requested work와 해당 Checkpoint-Capacity / Lookahead-Shots의 physical iterations를 검사합니다.
추가 console sequence는 같은 Oracle의 segment restart와 Enumeration을 실행합니다.
Enumeration 결과 순서는 모든 최종 console에서 `8685, 2852, 507, 4724`로 일치했습니다.

## Main integration 결과

아래는 2-workload prefix의 **Checkpoint mode 합계**입니다. 단위는 RTL cycles이며 full Common500
성능 수치나 board wall-clock time이 아닙니다. 각 설정은 Normal mode도 함께 검증했습니다.

| 설정 기록 (`k/h/e/m`) | solver | 전체 cycles | physical iterations | policy cycles | policy stall | 원자료 |
|---|---|---:|---:|---:|---:|---|
| `3/3/4/2` | optimized | 35,341 | 79 | 820 | 447 | [integration](k3h3e4m2_final/integration.json) |
| `5/3/3/4` | generic | 36,746 | 79 | 837 | 88 | [integration](final_boundaries/k5h3e3m4/integration.json) |
| `3/9/1/1` | generic | 107,412 | 79 | 3,801 | 828 | [integration](final_boundaries/k3h9e1m1/integration.json) |
| `10/2/16/3` | generic | 16,238 | 79 | 850 | 96 | [integration](final_boundaries/k10h2e16m3/integration.json) |
| `1/10/1/4` | generic | 193,564 | 172 | 630 | 103 | [integration](final_boundaries/k1h10e1m4/integration.json) |
| `3/3/4/2`, `force_generic=true` | generic | 34,978 | 79 | 846 | 84 | [integration](forced_generic_final/integration.json) |

각 행에서 42 jobs / 42 completed, 40 accepted plans 중 FIFO 38 plans이며 모든 검사 errors=0입니다.

`3/3/4/2`의 새 physical kernel 결과는 [기존 kernel 재실행](legacy_baseline_final/integration.json)의
Normal / Checkpoint 4개 CSV 행과 전 필드가 같았습니다. 고정한 이전 full Common500 결과의 동일 prefix와도
같습니다. 과거 고정 source의 전체 500 workloads 수치는 policy 80,719, policy stall 16,363,
Checkpoint 전체 5,150,965 cycles입니다([baseline.json](baseline.json)).
**일반화 후 전체 500 workloads를 재실행한 수치로 인용하지 않습니다.**

## 경계와 복구 검증

| 검사 | 자극과 판정 | 원자료 |
|---|---|---|
| Metadata → Planner → Executor | Checkpoint-Capacity 1 / 3 / 5 / 10에서 각 85개 policy vector, 총 340개. delayed physical segment fixture로 slot 내용 · retain · bridge · commit 시점 검증 | [checkpoint_units_final](checkpoint_units_final/) |
| 최대 boundary 수 | 각 capacity에서 모든 slot에 boundary를 쓰는 4개 추가 vector. 최대 구성에서 10 commits / 9 bridges, slot 9까지 사용. 합계 344개 valid vectors | [checkpoint_max_boundaries](checkpoint_max_boundaries/) |
| 잘못된 packet / invalidate | 위 네 capacity마다 invalid packet 거절, 실행 중 invalidate 시 진행 중 작업을 drain하고 metadata commit 폐기 | [testbench](../../testbench/tb_checkpoint_parameterized.sv) |
| wide FIFO | 10 slots / 4-bit count / 185-bit packet, full · overflow · 동시 push/pop · flush 우선 · epoch byte 값 순환 · tuple 상위 bits 보존 | [simulation log](queue_units/simulation.log) |
| 미래 요청 | 7 / 8 / 9 / 10 / 11개 출력에 각각 80개 문맥, 총 400개. restart와 wrap 자극 | [shadow_results.json](shadow_results.json) |
| demand only | speculation 비활성: 40 cold jobs, FIFO accept 0, policy stall 1,301. 같은 physical work / 결과 유지 | [integration](demand_only_final/integration.json) |
| FIFO mismatch | 예상 요청 값을 한 번 손상: mismatch counter 정확히 1, flush / 재계산 후 정확한 결과 | [result](mismatch_final/result.json) |
| epoch 재사용 | speculative job이 busy인 동안 flush 뒤 과거 epoch를 강제 재사용. 취소한 결과가 수락되지 않고 재계산 | [result](epoch_reuse_final/result.json) |
| warm restart | 10개 checkpoint가 유효한 상태의 같은 Oracle segment 재시작 3회. valid mask `3ff`와 70-bit metadata가 재시작 edge에서 유지 | [console](warm_restart_final/console.json) |
| 최대 parameter 조합 | `10/10/16/4`, synthetic all-target dataset, 첫 요청 0. 실제 Main loader / measurement / 두 solver window / plan 연결. 77-bit window, 70-bit tuple, 측정 index 14282를 독립 reference와 대조 | [result](maximum_width_final/result.json) |

최대 조합 검사는 uniform-state / zero-iteration 연결 시험입니다. 큰 탐색 공간 전체의 policy latency나
16개 engines의 nonzero iteration stress를 이 한 시험으로 검증한 것은 아닙니다. Nonzero physical work는
위 다른 조합들이 수행했습니다. 같은 Oracle의 segment retry에서는 checkpoint를 보존하며,
Found Mask / Oracle가 바뀌는 Enumeration 경계에서는 이전 plan과 metadata를 무효화합니다.

초기 `*_generic`, `*_v2`, `*_guarded`, `fifo_mismatch_recovery` directory는 observer 보정 중 기록입니다.
최종 판정은 `summary.json`에 나열한 final 결과를 사용합니다. 이전 기록을 삭제하거나 덮어쓰지 않았습니다.

## 한 설정 재현

repository root에서 실행합니다. 기본값은 2 workloads와 console 검사입니다.
출력 directory의 입력 hash가 달라지면 덮어쓰지 않고 새 경로를 요구합니다.

```bash
python3 hardware_bram/sim/generalize_main.py \
  --config hardware_bram/sim/generalize_config.json \
  --out /tmp/bbht_generalized_main_one --workloads 2

python3 hardware_bram/sim/generalize.py \
  --config hardware_bram/sim/generalize_config.json \
  --out /tmp/bbht_generalized_main_dispatch --stages main
```

`--demand-only`, `--legacy-kernel`, `--inject-mismatch`, `--inject-epoch-reuse`, `--no-console`은
첫 runner의 선택 옵션입니다. fault 두 종류는 서로 다른 실행으로 검사합니다.
같은 입력으로 solver backend를 비교하려면 JSON의 `force_generic`을 명시합니다.
runner의 `--workloads 500` 경로는 제공하지만 이 작업에서는 실행하지 않았습니다.

## background 구현과 분리

고정 platform 입력 28개와 보호 firmware의 hash는 일반화 작업 전후 일치했습니다.
이 일반화 RTL을 background platform에 설치하지 않았습니다.
사용자 요청으로 처음 조회했을 때 고정 source의 SoC는 90 checks, errors / warnings 0이었고
worker는 1차 implementation 단계였습니다([observation](background_observation.json)).

이후 사용자가 2026-10-29 다시 조회를 요청하여, 세 실행 모두 Vivado가 synthesis 중 `Killed`로 종료한
사실을 확인했습니다. 배치배선 결과 · WNS / WHS · bitstream은 생성되지 않았으며 board는 시작되지
않았습니다. 일반 스레드 제한과 별개인 `synth.maxThreads`가 기본값 7임을 local Vivado에서 확인하고,
일반 / 합성 스레드를 각각 1로 제한하는 4차 실행을 제출했습니다. RTL과 clock constraints는 유지합니다.
이는 제출 기록이며 재제출 후 완료 상태를 조회하지 않았습니다. 자세한 기록은
[timing evidence](../2026-10-28_policy_rank_timing/evidence.md)에 있습니다.

남은 작업은 전체 Common500 성능 campaign, 폭 확장 경로의 전체 SoC 검증과 200T synthesis / implementation,
board 검증입니다. 사용자 요청에 따라 현재 RTL · 검증 결과 · 남은 범위를 진행 상태 checkpoint로 commit합니다.
완료 범위는 [checkpoint_state.json](checkpoint_state.json)에 고정하며 background의 완료 상태를
추가 조회하지 않습니다.
