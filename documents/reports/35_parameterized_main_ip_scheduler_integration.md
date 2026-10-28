# 실험 35. Parameterized Main IP의 Scheduler · Planner · Executor 연결

> [← 실험 34](34_parameterized_rtl_development.md) · [실험 보고서 index](index.md)

| 확인한 것 | 근거의 축 | 범위 |
|---|---|---|
| parameter 폭 Main IP와 실제 iteration / measurement 연결 | RTL simulation · 독립 exhaustive policy reference | 승인한 세부 단계 1~6 |
| 기존 지원 구성의 동작 유지와 확장 경계 복구 | 실제 C driver · APB/AHB wrapper · console · fault injection | 선택한 설정과 짧은 Common500 prefix |
| 전체 성능 campaign · 200T 구현 · board | 이번 일반화 source로는 미수행 | 다음 단계 |

완료 기록: 2026-10-29. Checkpoint-Capacity · Lookahead-Shots 각각 1~10,
iteration engines 1~16, square engines 1~4를 한 JSON으로 지정하는 개발 경로를
Main IP의 Scheduler · Metadata · Planner · Executor와 실제 physical kernel에 연결했습니다.
사용자 요청대로 한 설정을 실행하는 방식이며 전체 조합 sweep은 수행하지 않았습니다.

## 구현과 확인한 동작

내부 tuple · slot · count · boundary · FIFO packet 폭을 parameter로 결정합니다.
Executor는 source checkpoint를 보호하고 bridge 이후 목적지에서 실행하며, 실제 작업 완료 뒤 metadata를
commit합니다. iteration engines의 row tail과 read / write drain을 처리하고, square engines 수와
독립적으로 16×32 Two-Level Select를 유지합니다. 새로운 square engines 수는 과거 Measurement
Microarchitecture 번호와 구분합니다.

기존 Scheduler FSM을 확장했으며 별도 scheduler 모듈로 재작성하지 않았습니다.
flush 때 in-flight policy의 무효 상태를 완료까지 기억하여 epoch 값이 재사용되어도 오래된 결과를
Executor가 수락하지 않게 했습니다. 같은 Oracle의 segment retry는 checkpoint를 보존합니다.
timing-only action queue는 다시 추가하지 않았습니다.

기존 지원 조합은 optimized solver를 유지하며 확장 조합은 parameterized exact solver를 사용합니다.
기존 지원 조합에서도 generic backend를 강제해 검사하는 설정을 제공합니다. 두 backend의 cycle은
같은 최적화 구현의 scaling 결과로 섞지 않습니다.

## 검증 범위와 다음 단계

기존 구성과 확장 경계의 실제 driver integration, 최대 parameter 조합의 연결, 넓어진 FIFO,
다섯 번째 이후 checkpoint boundary, same-Oracle warm restart, mismatch와 epoch 재사용 복구를
검증했습니다. 기존 구성의 동일 입력 prefix는 기존 kernel과 전 CSV 필드가 같았습니다.

각 설정의 cycle · policy stall · physical iterations, 원자료, source hash, 독립 reference 검사법,
재현 명령은 [evidence bundle](../../hardware_bram/results/2026-10-28_generalized_main_integration/evidence.md)에
있습니다. 일반화 전 고정 source의 full Common500 수치를 일반화 후 full regression 결과로 인용하지 않습니다.

다음은 전체 Common500 campaign입니다. 큰 parameter의 solver latency와 실제 전체 cycle을 측정한 뒤,
일반화 physical kernel의 memory 배치를 200T synthesis / implementation에 맞춰 확인해야 합니다.
이번 경로의 전체 SoC · board 검증은 남아 있습니다.
현재 구현과 검증 기록은 사용자 요청에 따라 진행 상태 checkpoint로 commit합니다.

기존 고정 source의 background 200T 작업은 분리했습니다. 사용자 요청 재조회에서 synthesis 중 process 종료를
확인하고 serial synthesis로 재제출했습니다. 완료 여부는 재제출 뒤 조회하지 않았으며 기록은
[timing evidence](../../hardware_bram/results/2026-10-28_policy_rank_timing/evidence.md)에 있습니다.
