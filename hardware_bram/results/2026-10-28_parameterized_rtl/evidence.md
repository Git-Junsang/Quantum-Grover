# Parameterized RTL 개발 — 블록 검증 단계

## 현재 범위

단일 JSON으로 capacity/lookahead 1..10, iteration engines 1..16, square engines 1..4를 지정합니다.
한 configuration의 policy와 독립 memory/iteration/square 블록을 simulation합니다.
기존 Main IP의 Scheduler·Planner·Executor·measurement controller에는 아직 연결하지 않았습니다.
전체 accelerator cycle, policy stall, 전체 SoC, 합성 및 board 검증 완료를 의미하지 않습니다.
전체 100개 조합 sweep도 실행하지 않았습니다.

## RTL 구조

- `grover_ckpt_policy_parameterized`: parameter 폭의 슬롯·요청 창·출력 tuple 인터페이스.
  기존 production 지원 조합은 기존 최적화 solver를 사용합니다. `force_generic`으로 검증 backend를 고정할 수 있습니다.
- `grover_ckpt_policy_generic`: 정렬된 값 집합을 universe mask로 표현합니다. stack과 요청 창은 lookahead 크기,
  tuple·count는 capacity 크기에서 결정합니다. restricted-B action set과 cost/segment/tuple 동률 규칙을 유지합니다.
  병렬 SCAN, 기존 gap bound의 3단계 응답, bound cache, seed certificate, memoized DFS를 구현합니다.
  hash memo는 전체 state/depth/epoch tag를 대조하고 충돌 시 교체합니다. 충돌은 재탐색을 일으킬 수 있지만 오답을 반환하지 않습니다.
  production의 모든 단축 경로와 스케줄을 복제한 것은 아니므로 backend 간 cycle은 별도 기록합니다.
- `grover_ckpt_mem_parallel`: 실제 capacity만큼 슬롯을 할당합니다. bank 수는 read/write 병렬도 중 큰 값,
  슬롯별 bank stride는 올림 처리합니다. 3개 등 비거듭제곱 병렬도의 마지막 불완전 그룹을 mask합니다.
- `grover_iter_datapath_parallel`: parameter 개수의 32-lane 연산기와 공통 global reduction/mean.
  predicate, padding, found mask, round-even mean, diffusion saturation을 유지합니다.
- `grover_born_square_parallel`: 기존 32-lane row squarer를 지정 개수만큼 생성합니다.
  여기서 square engines는 scalar multiplier 수가 아니라 row squarer 수입니다.
  16 groups × 32 rows Two-Level Select는 앞으로 연결할 기존 measurement controller에 유지합니다.

## 검증

`../archive/parameterized_blocks/2026-10-28_parameterized_policy_final/`의 9개 구성, 477건이 독립 exhaustive memoized DP와 일치했습니다.
capacity 1/2/3/4/5/10, lookahead 3/4/8/9/10, mode 5/6, lane 1/2/4의 선택된 경계를 포함합니다.
start 후 입력 변경, 빈 집합, 물리 슬롯 순열·빈 슬롯, zero/127 request, 반복 request,
작은 hash memo의 충돌, epoch wrap과 reset을 검사합니다. 반환 cycle counter는 실제 start-to-done
clock edge 수와도 비교했습니다. 이는 Common500 성능 측정이 아닙니다.

같은 묶음의 `k10h10_dense`는 universe 21개와 root 후보 167,960개를 사용하는 별도 사례입니다.
분석적으로 증명한 최적 action/cost와 일치했고 **한 번의 결정**이 42,113 clocks였습니다.
`analytic_reference.json`에 하한 증명과 exact tuple, `simulation.log`에 원자료가 있습니다.
이 한 건을 Common500 합계나 일반적인 큰 configuration 성능으로 외삽하면 안 됩니다.

`../archive/parameterized_blocks/2026-10-28_parameterized_parallel/`의 5개 구성은 모든 슬롯·512 rows,
제곱의 모든 lane, 네 predicate의 Oracle/global sum/mean/diffusion을 비교했습니다.
iteration engines가 3개인 불완전 그룹과 iteration 1 / square 4의 독립 병렬도를 포함합니다.
`../archive/parameterized_blocks/2026-10-28_generalized_configuration/`은 JSON 하나로 policy와 블록 검증을 함께 통과했습니다.
이 구성과 `../archive/parameterized_blocks/2026-10-28_parameterized_parallel_final/`의 iteration 16 / square 4에서는
최대 진폭의 양·음 값을 섞어 saturation 경로도 추가 검사했습니다.
`../archive/parameterized_blocks/2026-10-28_generalized_configuration_production/`은 기본 설정으로 production backend 선택을 확인했습니다.

Verilator는 parameterized solver와 iteration 16개 블록을 elaboration했습니다.
새 조합 loop·latch·multiple driver·범위 초과·오류는 없습니다. generic solver에는 명시적 정수/폭 변환에
관한 width warning이 남아 있고 iteration 블록에는 기존 arithmetic pre_node의 UNOPTFLAT 경고가 상속됩니다.
`policy_lint.log`, `parallel_lint.log`가 근거입니다. Icarus simulation과 독립 정답 대조도 병행했습니다.

## 재실행

```bash
python3 hardware_bram/sim/generalize.py \
  --config hardware_bram/sim/generalize_config.json \
  --out /tmp/bbht-parameterized-one
```

`--stages policy` 또는 `--stages parallel`로 단계를 선택합니다. 기본은 둘 다입니다.
기본 JSON은 기존 구성과 production backend를 선택합니다. `k/h/e/m`을 단일 숫자로 바꾸며,
지원하지 않는 값이나 기존 결과와 달라진 입력은 오류 처리합니다. 결과에는 실제 사용 backend와
검증 범위를 명시합니다. policy clock에는 Python 정답 계산 시간을 포함하지 않습니다.

## 남은 통합

1. production solver와 generic solver의 공통 스케줄·단축 경로를 정리합니다.
2. parameter 폭의 Planner·Executor·metadata·plan FIFO와 Main IP 연결을 구현합니다.
3. iteration engine의 그룹 controller와 memory arbitration을 연결합니다.
4. measurement controller를 square 병렬도와 연결하고 기존 Two-Level Select를 유지합니다.
5. 같은 configuration의 Common500으로 결과·물리 연산 횟수·stall·전체 cycle을 검증합니다.
6. 그 뒤 원하는 단일 configuration을 변경해 측정하고, 요청 시에만 범위를 넓혀 sweep합니다.

현재 production의 일반화 지원 범위가 넓어진 것은 아닙니다. 실험 블록들은 200T background
platform과 분리되어 있고, 보드 firmware source를 변경하지 않았습니다.
