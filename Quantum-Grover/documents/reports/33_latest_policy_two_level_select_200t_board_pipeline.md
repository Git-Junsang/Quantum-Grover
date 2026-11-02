# 실험 33. 최신 policy를 넣은 Dual-Row Build · Two-Level Select configuration의 200T·board pipeline

> [← 실험 32](32_capacity_3_lookahead_3_performance_recheck.md) · [실험 보고서 index](index.md)

| 확인한 것 | 근거의 축 | 상태 |
|---|---|---|
| 기존 final configuration(a Checkpoint-Capacity of 3 and 3-shot Lookahead · 4 PEs · Dual-Row Build · Two-Level Select)에 최신 Seed-First Branch and Bound with Single-Action Exit policy 적용 | frozen source · 명시적 Dual-Row Build · 16 groups × 32 rows Two-Level Select | 준비 |
| Common500·전체 SoC·200T·board verification 자동 연결 | 분리된 단일 configuration worker | 제출 |
| 새 configuration의 성능·timing·board 일치 | 각 단계의 실행 결과 | simulation 통과, setup timing 미통과로 board 미실행 |

## configuration과 진행

기존 final configuration의 Dual-Row Build · Two-Level Select를 유지하고 최신 policy를 적용하는 configuration 하나를 별도
platform에 설치했습니다. 실험 31·32의 Triple-Row Build benchmark와 구분합니다. 공용 RTL과 Board-Verified Build firmware
source를 변경하지 않고 입력을 동결했습니다.

Common500과 전체 SoC verification 후 Vivado 하나로 200T implementation을 실행합니다. 부품·timing 판정을
통과하면 board의 Restart mode · Checkpoint mode 1,000 runs를 같은 RTL과 엄격히 비교하고 flash 설계를
다시 load합니다. 실패하면 해당 단계에서 멈춰 기록합니다. Checkpoint-Capacity · Lookahead-Shots 일반화는 포함하지 않습니다.

설정·source hash·worker·제출 및 판정 범위는
[evidence bundle](../../hardware_bram/results/archive/implementation_pipeline/2026-10-28_k3h3_e4_m2_policy6_board/evidence.md)에 있습니다.

조회 뒤 timing 수정 재시도와 일반화 블록 개발은 [실험 34](34_parameterized_rtl_development.md)로 이어집니다.
