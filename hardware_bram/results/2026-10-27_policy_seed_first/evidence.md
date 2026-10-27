# seed-first 정책 탐색 RTL (EXACT_PRUNE=5/6) 검증 근거

상태: **진행 중.** RTL 기능 검증은 끝났고, Arty 100T 타이밍은 아직 통과하지 못했습니다.

| 항목 | 내용 |
|---|---|
| RTL | `hardware_bram/src/grover_policy.v` (커밋 `f02dd60` + 탐색 제어 블록 이동) |
| 모드 | `EXACT_PRUNE=5`: full-horizon admissible lower bound + seed-first exact DFS. `EXACT_PRUNE=6`: 5 + legal action 이 하나뿐인 결정은 하위 탐색 생략 |
| 모델 | `hardware_bram_K3H3_E4_M3_S6` (M3 + `POLICY_EXACT_PRUNE=6`) |
| 축 | RTL 사이클 (Verilator, iverilog 교차 확인). 보드 측정 없음 |

## 1. 정책 단독 RTL (`standalone_rtl.csv`)

`tb_policy_kh_sweep.sv` 에 Common500 의 7,403 결정을 넣고, 결정마다 source 와 체크포인트
tuple 을 exhaustive SW 정책(`kh_sweep.select_policy_action`)의 정답과 대조했습니다.

- K3/K4 × H1..8, 모드 5·6: 32 셀 전부 7,403/7,403 일치 (`mismatches` 열 0)
- 모드 0(K3/K4 × H1..8)·모드 4(K4H4)는 실험 22·23 의 기록과 사이클·action 수까지 같음
  → 기존 모드의 동작은 바뀌지 않음
- K3H3 모드 5·6 은 iverilog 와 Verilator 의 사이클이 같음 (700,076 / 525,037)

| 셀 | 모드 0 | 모드 4 | 모드 5 | 모드 6 |
|---|---:|---:|---:|---:|
| K3H3 | 1,183,308 | 933,966 | 700,076 | 525,037 |
| K4H4 | 2,841,616 | 1,985,090 | 1,136,391 | 816,610 |
| K4H8 | 21,593,720 | 18,354,629 | 2,539,529 | 1,521,059 |

(정책 사이클 = 7,403 결정의 `start`→`done` 합, memo 초기화 포함. 모드 4 열은 실험 23 기록)

## 2. Main IP 통합

| 검사 | 결과 |
|---|---|
| `make regress-real` T1~T10 (모드 5, 모드 6 모델) | 오류 0 |
| `run_driver_test.sh` D1~D11 (모드 5) | 오류 0 |
| `make ports-real lint-real MODEL=K3H3_E4_M3_S6` | 통과 |
| M3 bench500 K3H3 | prune0 4,680,014 / 모드 5 4,581,269 / 모드 6 4,566,996, 궤적 500/500, `plan_fifo_mismatch` 0 |

prune0 값은 M3 근거 묶음(`1e32e08`)의 4,680,014 · stall 152,458 을 그대로 재현합니다.
K/H 전 범위의 통합 측정은 [K/H 묶음](../2026-10-27_kh_sweep_m2_m3/evidence.md).

## 3. 타이밍 (`ooc_timing.csv`)

OOC 배치·배선 (xc7a100t, 100 MHz, 1차 RTL `f02dd60`):

| 대상 | WNS | 합성 LUT |
|---|---:|---:|
| 정책 단독 K3H3 모드 0 | +0.361 | 2,950 |
| 정책 단독 K3H3 모드 6 | +0.081 | 3,929 |
| 정책 단독 K4H8 모드 6 | +0.262 | 5,331 |
| Main IP K3H3 M3 모드 6 | +0.068 | 40,940 (M3 prune0 39,929 대비 +1,011) |

전체 SoC 는 1차에서 WNS −0.302 로 실패했고 2차 구현이 진행 중입니다
([S6 구현 묶음](../../models/hardware_bram_K3H3_E4_M3_S6/vivado/vivado_bbht_grover_k3h3_e4_m3_s6/2026-10-27_arty100t_build/evidence.md)).

## 4. 탐색 제어 블록 이동 후 재검증

1차 구현 실패 원인(memo BRAM → 탐색 제어 CE)을 없애려고 제어 블록을 hit/miss 분기 앞으로
옮긴 뒤 다시 확인했습니다.

- 정책 단독 34 회(위 32 셀 + K3H3 모드 0 + K4H4 모드 4): 사이클 · action · 최대 지연이
  옮기기 전과 모두 같음
- `regress-real` (S6) 오류 0, S6 bench500 4,566,996 · 궤적 500/500

## 남은 일

- Arty 100T 2차 구현의 WNS / slice 확인. 실패하면 배치 지시어(`ExtraNetDelay_high`) 적용,
  그래도 실패하면 M3 prune0 유지
- 기술문서(11장 정책 엔진, 5장 모델 표, CLAUDE.md 모델 목록)와 실험 보고서 index 반영
