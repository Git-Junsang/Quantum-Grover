# 실험 34. Parameterized RTL 블록과 policy 인터페이스 개발

> [← 실험 33](33_latest_policy_two_level_select_200t_board_pipeline.md) · [실험 보고서 index](index.md) · [실험 35 →](35_parameterized_main_ip_scheduler_integration.md)

## 범위와 상태

Checkpoint-Capacity · Lookahead-Shots 1~10, iteration engines 1~16, square engines 1~4를
단일 JSON으로 지정하는 simulation 개발 경로를 추가했습니다. 기존 Main IP 통합은 아직 남았습니다.
전체 accelerator cycle·policy stall이나 전체 SoC·board 검증 완료를 선언하지 않습니다.
전체 조합을 자동 실행하지 않고 단일 설정을 검증합니다.

production 지원 조합은 기존 solver를 유지하고 확장 조합은 parameter 폭의 exact solver로 검사합니다.
두 backend는 스케줄과 일부 단축 경로가 달라 cycle 비교 시 구분해야 합니다.
독립 memory/iteration/square RTL은 슬롯·bank·lane 폭을 parameter로 결정합니다.

검증한 조합·원자료·backend 차이·실행 명령과 남은 Main IP 연결은
[evidence bundle](../../hardware_bram/results/2026-10-28_parameterized_rtl/evidence.md)에 있습니다.

후속 Main IP의 Scheduler · Planner · Executor 연결과 선택한 조합의 integration 검증은
[실험 35](35_parameterized_main_ip_scheduler_integration.md)에서 완료했습니다.
이 보고서의 독립 블록 결과와 후속 integration 결과는 별도 source 기록으로 보존합니다.

## 분리된 timing 작업

기존 200T 구현은 setup timing을 통과하지 못했습니다. SCAN value-rank key 전달을 수정하고
별도 platform에서 단독·통합·SoC·implementation·board 검증을 이어가는 worker를 제출했습니다.
일반화 RTL은 해당 입력을 덮어쓰지 않습니다. 사용자 요청으로 조회했을 때 최초 worker는
console observer의 이전 driver 필드명 때문에 implementation 전에 중단된 상태였습니다.
observer 사본의 compile·실행을 확인하고 완료한 RTL 검증의 source hash를 대조한 뒤 재제출했습니다.
재제출 뒤 implementation 결과는 반복 조회하지 않았습니다.
수정·회귀·재시도 방식은 [timing evidence](../../hardware_bram/results/2026-10-28_policy_rank_timing/evidence.md)에 있습니다.
