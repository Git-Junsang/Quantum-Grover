# Seed-First Branch and Bound policy search RTL (policy search mode 5 · 6) verification 근거

상태: **진행 중.** RTL 기능 verification은 끝났고, Arty 100T timing은 아직 통과하지 못했습니다.

| 항목 | 내용 |
|---|---|
| RTL | `hardware_bram/src/grover_policy.v` (commit `f02dd60` + search 제어 block 이동) |
| policy search mode | `POLICY_SEARCH_MODE=5`: Seed-First Branch and Bound (full-horizon admissible lower bound + seed-first exact DFS). `POLICY_SEARCH_MODE=6`: 5 + legal action이 하나뿐인 결정은 하위 search 생략 (Seed-First Branch and Bound with Single-Action Exit) |
| configuration | `capacity3_lookahead3_pes4_triplerow_twolevel_seedfirst_singleexit` (Triple-Row Build · Two-Level Select + `POLICY_SEARCH_MODE=6`) |
| 축 | RTL cycle (Verilator, iverilog 교차 확인). board benchmark 없음 |

## 1. policy 단독 RTL (`standalone_rtl.csv`)

`tb_policy_kh_sweep.sv`에 Common500의 7,403 결정을 넣고, 결정마다 source와 checkpoint
tuple을 exhaustive software policy(`kh_sweep.select_policy_action`)의 expected result와 대조했습니다.

- Checkpoint-Capacity 3 · 4 × Lookahead-Shots 1~8, mode 5 · 6: 32 cells 전부 7,403/7,403 일치 (`mismatches` 열 0)
- mode 0(Checkpoint-Capacity 3 · 4 × Lookahead-Shots 1~8) · mode 4(a Checkpoint-Capacity of 4, 4-shot Lookahead)는 실험 22·23의 기록과 cycle·action 수까지 같음
  → 기존 mode의 동작은 바뀌지 않음
- a Checkpoint-Capacity of 3 and 3-shot Lookahead mode 5·6은 iverilog와 Verilator의 cycle이 같음 (700,076 / 525,037)

| cell | mode 0 | mode 4 | mode 5 | mode 6 |
|---|---:|---:|---:|---:|
| a Checkpoint-Capacity of 3 and 3-shot Lookahead | 1,183,308 | 933,966 | 700,076 | 525,037 |
| a Checkpoint-Capacity of 4 and 4-shot Lookahead | 2,841,616 | 1,985,090 | 1,136,391 | 816,610 |
| a Checkpoint-Capacity of 4 and 8-shot Lookahead | 21,593,720 | 18,354,629 | 2,539,529 | 1,521,059 |

(policy cycle = 7,403 결정의 `start`→`done` sum, memo table initialization 포함. mode 4 열은 실험 23 기록)

## 2. Accelerator Core 통합

| 검사 | 결과 |
|---|---|
| `make regress-real` T1~T10 (mode 5, mode 6 configuration) | 오류 0 |
| `run_driver_test.sh` D1~D11 (mode 5) | 오류 0 |
| `make ports-real lint-real CONFIGURATION=capacity3_lookahead3_pes4_triplerow_twolevel_seedfirst_singleexit` | 통과 |
| Triple-Row Build bench500 a Checkpoint-Capacity of 3 and 3-shot Lookahead | mode 0 4,680,014 / mode 5 4,581,269 / mode 6 4,566,996, BBHT trajectory 500/500, `plan_fifo_mismatch` 0 |

mode 0 값은 Triple-Row Build evidence bundle(`1e32e08`)의 4,680,014 · stall 152,458을 그대로 재현합니다.
Checkpoint-Capacity · Lookahead-Shots 전 범위의 통합 benchmark는 [Checkpoint-Capacity · Lookahead-Shots 묶음](../2026-10-27_kh_sweep_m2_m3/evidence.md).

## 3. timing (`ooc_timing.csv`)

OOC placement · routing (xc7a100t, 100 MHz, 1차 RTL `f02dd60`):

| 대상 | WNS | synthesis LUT |
|---|---:|---:|
| policy 단독 a Checkpoint-Capacity of 3 and 3-shot Lookahead mode 0 | +0.361 | 2,950 |
| policy 단독 a Checkpoint-Capacity of 3 and 3-shot Lookahead mode 6 | +0.081 | 3,929 |
| policy 단독 a Checkpoint-Capacity of 4 and 8-shot Lookahead mode 6 | +0.262 | 5,331 |
| Accelerator Core a Checkpoint-Capacity of 3, 3-shot Lookahead and Triple-Row Build mode 6 | +0.068 | 40,940 (Triple-Row Build mode 0 39,929 대비 +1,011) |

전체 SoC는 1차에서 WNS −0.302로 실패했고 2차 implementation이 진행 중입니다
([policy search mode 6 implementation 묶음](../../configurations/capacity3_lookahead3_pes4_triplerow_twolevel_seedfirst_singleexit/vivado/vivado_bbht_grover_k3h3_e4_m3_s6/2026-10-27_arty100t_build/evidence.md)).

## 4. search 제어 block 이동 후 재검증

1차 implementation 실패 원인(memo table BRAM → search 제어 CE)을 없애려고 제어 block을 hit/miss 분기 앞으로
옮긴 뒤 다시 확인했습니다.

- policy 단독 34 회(위 32 cells + a Checkpoint-Capacity of 3 and 3-shot Lookahead mode 0 + a Checkpoint-Capacity of 4 and 4-shot Lookahead mode 4): cycle · action · 최대 latency가
  옮기기 전과 모두 같음
- `regress-real` (policy search mode 6) 오류 0, policy search mode 6 bench500 4,566,996 · BBHT trajectory 500/500

## 남은 일

- Arty 100T 2차 implementation의 WNS / slice 확인. 실패하면 placement 지시어(`ExtraNetDelay_high`) 적용,
  그래도 실패하면 Triple-Row Build mode 0 유지
- 기술문서(11장 Policy Engine, 5장 configuration 표, CLAUDE.md configuration 목록)와 실험 보고서 index 반영
