# Expanded iteration and measurement engines

기록일: 2026-10-29, Asia/Seoul. 요청한 RTL 확장과 아래 verification을 완료했습니다.

Checkpoint-Capacity · Lookahead-Shots 각각 1~10, iteration engines 1~20, square engines 1~11의
simulation development 지원 범위입니다. 200T fitting · routing timing · board verification은 포함하지 않습니다.

[source_sha256.json](source_sha256.json)은 이번 구현의 source이며, 각 실행의 `source/`와
manifest는 해당 실행의 고정 snapshot입니다. 이전 단계의 diagnostic과 승인한 최종 실행을 구분합니다.
최종 verification 상태는 [validation.json](validation.json), 실제 counter는
[summary.csv](summary.csv)에 있습니다. 전체 parameter 조합을 모두 실행한 것은 아닙니다.

## 실제 Main IP RTL 결과

각 full Common500은 같은 500 workloads를 Normal / Checkpoint로 실행한 1,000 rows입니다.
정책 결정은 independent exact reference로, trajectory와 physical iterations는 같은 요청 열로
대조했습니다. source hash는 실행별 manifest와 현재 source가 일치합니다.

| Checkpoint-Capacity | Lookahead-Shots | iteration engines | square engines | workloads | 전체 cycles | policy cycles | policy stall |
|---:|---:|---:|---:|---:|---:|---:|---:|
| 3 | 3 | 4 | 2 | 500 | 5,148,615 | 67,280 | 14,013 |
| 10 | 10 | 20 | 11 | 500 | 1,534,934 | 121,707 | 31,770 |
| 5 | 7 | 19 | 7 | 10 | 63,567 | 4,301 | 371 |
| 3 | 3 | 1 | 11 | 10 | 530,893 | 2,429 | 349 |

기존 구성의 모든 CSV bytes는 [직전 full Common500](../2026-10-29_generalized_common500/k3h3e4m2_fast/bench.csv)과
같습니다([비교](baseline_comparison.json)). 최대 구성에서는 physical iterations 8,586회와
7,903개 solver jobs, 7,403개 accepted plans를 검사했습니다. 큰 구성의 cycle은 simulation
실측이며, 200T resource나 clock 달성을 증명하지 않습니다.

[기존 구성](baseline_common500/integration.json), [최대 구성](max_common500/integration.json),
[홀수 engine 구성](odd_integration/integration.json),
[measurement 병렬도가 iteration보다 큰 구성](measurement_heavy_integration/integration.json)이 원자료입니다.
네 구성 모두 console · Enumeration · same-Oracle warm restart를 통과했고 Enumeration 결과는
8685, 2852, 507, 4724로 같습니다.

최대 구성에서 [mismatch injection](max_mismatch/integration.json)과
[epoch reuse injection](max_epoch_reuse/integration.json)을 각각 한 번 발생시켰습니다.
오래된 speculative plan을 버리고 올바른 현재-context plan을 수락하며, 결과와 physical work가
independent reference와 일치했습니다. 두 fault 실행은 각각 2 workloads의 복구 검사입니다.

## 독립 block과 measurement protocol

[measurement_final/result.log](measurement_final/result.log)는 square engines 1~11의
66개 transaction을 기존 single-row sampler와 대조합니다. zero weight, weight one의 무작위
추출 생략, 균일 state, 32-row group 경계, 마지막 부분 묶음, 큰 양·음 amplitude와 반복 start를
포함합니다. 총 weight · PRNG draw 수 · threshold · candidate가 같습니다.

`blocks/`의 여섯 구성은 모든 checkpoint slot과 512 rows, 네 predicate의 global sum · mean ·
diffusion과 32-lane squares를 검사합니다. 각 구성은 일반 pattern과 saturation pattern을 각각
통과했습니다. 최대 engine 수, 홀수 engine 수와 measurement / iteration의 독립 병렬도를 포함합니다.

[config_validation.json](config_validation.json)의 24개 입력 검사는 parameter 경계와 잘못된
type을 검사합니다. independent reference와 exhaustive reference의 800개 cross-check도
통과했습니다. [최대 구성 lint](lint_approved/result.json)에 오류 · 새 latch · 새 multiple driver가
없으며 기존 arithmetic `pre_node`의 array-level UNOPTFLAT warning은 남아 있습니다.

기존 full Common500 evidence 1,998개 file, 보호한 paper benchmark 18개 file과 앞서 archive로
이동한 934개 file의 hash를 다시 확인했습니다. background implementation의 상태는 조회하지 않았습니다.
초기 lint와 development diagnostic은 `diagnostics/`에 보존하며 승인한 최종 검증과 구분합니다.

## 재실행

한 설정의 숫자를 바꾸어 실행합니다. 같은 출력 directory의 source가 바뀌면 오류 처리하므로 새
출력 directory를 사용합니다. 최대 설정의 simulation은 memory를 많이 사용할 수 있습니다.

```bash
BBHT_BUILD_JOBS=1 python3 hardware_bram/sim/generalize_main.py \
  --config hardware_bram/results/2026-10-29_generalized_e20_m11/max_config.json \
  --out /tmp/bbht_extended_main_run --workloads 500

iverilog -g2012 -Ihardware_bram/src -s tb_measure_build_rows \
  -o /tmp/bbht_extended_sampler.vvp \
  hardware_bram/testbench/tb_measure_build_rows.sv \
  hardware_bram/src/grover_parallel.sv hardware_bram/src/grover_measurement.v \
  hardware_bram/src/grover_memories.v hardware_bram/src/grover_arithmetic.v
vvp /tmp/bbht_extended_sampler.vvp
```

확장용 memory를 최종 유망 구성에 맞춰 줄이는 계획과 resource 한도 내 연산부 최적화 뒤
policy parameter를 선정하는 순서는 [실험 37](../../../documents/reports/37_expanded_iteration_and_measurement_engines.md)에 있습니다.
