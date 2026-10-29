# 실험 37. Parameterized iteration engines와 measurement BUILD 확장

> [← 실험 36](36_generalized_common500_and_policy_heatmaps.md) · [실험 보고서 index](index.md) · [실험 38 →](38_iteration_square_engine_sweep_200t.md)

| 구현과 확인 범위 | 근거의 축 | 경계 |
|---|---|---|
| Checkpoint-Capacity · Lookahead-Shots 각각 1~10 | 기존 parameterized policy · Planner · Executor | algorithm과 동률 규칙 유지 |
| iteration engines 1~20 · square engines 1~11 | parameterized Main IP RTL · 실제 C driver | 최대 구성과 기존 구성 full Common500 완료; 선택 boundary 검증 |
| 가변 measurement BUILD와 16×32 Two-Level Select | 기존 single-row sampler와 exact comparison | 66 transaction 통과; precision · PRNG draw 순서 유지 |
| 200T fitting · routing timing · board | 이번 확장 source로는 미수행 | 후속 resource optimization 단계 |

기록일: 2026-10-29. 새 범위는 simulation development의 지원 범위입니다. 범위 내 모든 조합이
200T에 들어간다는 의미가 아니며, 전체 조합을 한 번에 실행하는 자동화를 기본 동작으로 삼지 않습니다.
하나의 JSON으로 한 구성을 선택하고 검증한 뒤 다음 숫자를 바꾸는 흐름을 유지합니다.

## 구현

iteration datapath와 amplitude memory의 지원 상한을 늘렸습니다. iteration engines가
거듭제곱이 아니어도 global reduction의 남는 leaf를 zero로 처리하고 마지막 row group의
유효하지 않은 engine을 mask합니다. memory의 slot별 bank stride는 올림하여 서로 다른
checkpoint slot이 마지막 불완전 group에서 alias하지 않게 합니다.

square engines 1~4는 기존 sampler의 경로를 유지합니다. 그보다 큰 값에는
`grover_born_sampler_parallel`을 연결하여 지정한 개수의 32-lane squarer를 사용합니다.
amplitude read port와 bank 수는 iteration과 measurement 양쪽의 요구를 반영합니다.
row weight는 square engine별 bank에 쓰고 마지막 부분 묶음을 mask합니다. 32-row group의
경계가 어느 square lane에 와도 그 lane까지의 exact prefix를 group CDF로 기록합니다.

선택은 기존과 같은 16 groups × 32 rows, strict first-prefix comparison, 선택 row 재읽기와
32-lane 선택입니다. registered rejection mapper와 HI→LO random draw 순서를 재사용합니다.
weight zero와 one의 처리는 기존 계약을 유지합니다. timing-only policy queue는 추가하지 않습니다.

실제 source hash, 검증 결과, 범위와 재실행 명령은
[evidence bundle](../../hardware_bram/results/2026-10-29_generalized_e20_m11/evidence.md)에 기록합니다.

## 확장용 memory의 후속 정리

현재 개발 단계는 parameter 변경과 기능 검증을 우선합니다. dataset · found mask 복제,
worst-case 후보 cache, BRAM 깊이와 너비의 padding 등은 resource 최적화가 끝난 구조가 아닙니다.
최종 유망 Checkpoint-Capacity · Lookahead-Shots · iteration engines · square engines가 정해지면
불필요한 복제와 여유 공간을 줄이고, 해당 구성에 맞는 bank와 cache 배치로 정리합니다.
최대 지원값 때문에 모든 구성이 최대 개수의 연산기를 갖게 하지는 않으며, 실제 instance와 array
폭은 선택한 parameter로 결정합니다.

이 정리는 필요한 amplitude capacity와 동시 read/write bandwidth를 보존해야 합니다. memory를
줄인 뒤 같은 Common500, checkpoint 복구, PRNG와 bit-exact 결과를 다시 확인하고 synthesis와
전체 SoC routing timing으로 실제 이득을 확인합니다. memory 정리로 feasible parameter range가
달라지면 최종 후보를 다시 비교합니다.

## 다음 resource와 성능 선정 순서

1. checkpoint와 policy를 위한 resource 예산을 남긴 상태에서 iteration / measurement 연산부의
   병목과 실제 cycle을 비교하고, 200T 예산 안의 iteration / square engine 후보를 찾습니다.
   비교 중에는 같은 기준 Checkpoint-Capacity · Lookahead-Shots를 사용해 연산부의 효과를 구분합니다.
   Normal mode 연산 cycle과 200T 대략 판정은 [실험 38](38_iteration_square_engine_sweep_200t.md)입니다.
2. 유망한 engine 후보마다 Checkpoint-Capacity · Lookahead-Shots를 탐색합니다. 이미 얻은
   고정 engine heatmap의 최적점을 새 engine 구성의 최종값으로 고정하지 않습니다.
3. 유망 전체 구성의 확장용 memory를 정리하고 실제 synthesis · timing으로 예산을 보정합니다.
   전체 cycle, 노출된 policy stall과 달성한 clock으로 최종 구성을 고릅니다.
4. 선택한 후보의 전체 SoC, bitstream과 board verification을 수행합니다.

따라서 다음 작업은 resource 한도 내의 연산부 최적화가 먼저이고, 후보별 policy parameter 선정과
memory 정리 뒤 전체 구성을 함께 확정하는 흐름입니다. policy의 탐색 방식 개선은 이 연산부
비교와 분리하여 요청한 범위에서 진행합니다.
