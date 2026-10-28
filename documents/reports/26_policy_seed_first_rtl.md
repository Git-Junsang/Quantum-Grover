# 실험 26. Seed-First Branch and Bound RTL과 Dual-Row Build · Triple-Row Build의 Checkpoint-Capacity · Lookahead-Shots 비교 (진행 중)

> [← 실험 25](25_triple_row_build_capacity_5_resource_review.md) · [실험 보고서 index](index.md) · [실험 27 →](27_200t_parameter_automation.md)

> **진행 중.** RTL 기능 verification과 RTL cycle benchmark는 끝났지만, Arty 100T implementation timing이 아직
> 통과하지 못했고 policy 최적화 전(Exhaustive DFS) Checkpoint-Capacity · Lookahead-Shots 전 범위 benchmark가 돌고 있습니다. 아래 결론은
> 이 두 가지가 끝나면 다시 확인해야 합니다.

| 확인한 것 | 근거의 축 | 상태 |
|---|---|---|
| 실험 24의 Seed-First Branch and Bound(full-horizon bound + seed-first exact DFS)를 RTL로 구현했고, 선택 결과가 Exhaustive DFS policy와 같다 | policy 단독 RTL, Checkpoint-Capacity 3 · 4 × 1-shot ~ 8-shot Lookahead | 확인 |
| policy 계산이 a Checkpoint-Capacity of 3 and 3-shot Lookahead에서 56 %, a Checkpoint-Capacity of 4 and 8-shot Lookahead에서 93 % 줄었다 (Seed-First Branch and Bound with Single-Action Exit) | policy 단독 RTL | 확인 |
| Triple-Row Build와 a Checkpoint-Capacity of 3 and 3-shot Lookahead의 전체 cycles이 4,680,014 → 4,566,996 (−2.41 %) | 통합 bench500, RTL cycle | 확인 |
| 최적화 후 최적 cell은 Triple-Row Build에서 a Checkpoint-Capacity of 3 and 3-shot Lookahead, Dual-Row Build에서 a Checkpoint-Capacity of 4 and 4-shot Lookahead | 통합 bench500 | 확인 |
| Dual-Row Build는 어떤 Checkpoint-Capacity · Lookahead-Shots로도 Triple-Row Build의 a Checkpoint-Capacity of 3 and 3-shot Lookahead를 이기지 못한다 | 통합 benchmark + model lower bound | 확인 |
| Triple-Row Build + Seed-First Branch and Bound with Single-Action Exit가 Arty 100T에 100 MHz로 들어간다 | Vivado implementation | **미확인** (1차 WNS −0.302) |

## 목적

실험 24는 full-horizon admissible lower bound와 seed-first exact DFS를 software로 계산하고 cycle
model로 효과를 예측했습니다. 이 실험은 그 search를 policy RTL에 넣어 실제 cycle과 결과 동일성을
확인하고, Triple-Row Build Measurement Unit 위에서 Checkpoint-Capacity · Lookahead-Shots를 다시 고르는 것이 목적입니다.

## implementation

`grover_policy.v`에 두 policy search mode를 더했습니다. 기존 policy search mode 0~4는 그대로입니다.

| policy search mode | 내용 |
|---|---|
| Seed-First Branch and Bound | frame마다 Scan(모든 child의 bound) → seed(가장 작은 bound)를 정확히 평가 → canonical order로 돌며 `즉시비용 + bound ≥ 최선`이면 pruning |
| Seed-First Branch and Bound with Single-Action Exit | Seed-First Branch and Bound + 현재 request의 legal action이 하나뿐이면 하위 search 없이 결정. 그때 `root_cost`는 정확한 비용 대신 lower bound(Accelerator Core는 이 값을 읽지 않음) |

bound는 universe 값을 정렬 순위로 바꾼 bitmask 위에서 계산합니다. request 하나가 register 한
단이고, 각 단은 "임계 순위 이하", "최상위 bit", "그 위 segment" 같은 bit 연산뿐이라 값 comparator나
max tree가 없습니다. 순위는 Build의 capture → resolve → commit 단계에서 증분으로 유지해 Build
cycle을 늘리지 않았습니다. 이 mode를 쓰는 configuration은 `capacity3_lookahead3_pes4_triplerow_twolevel_seedfirst_singleexit`
(a Checkpoint-Capacity of 3, 3-shot Lookahead, 4 PEs, Triple-Row Build · Two-Level Select, Seed-First Branch and Bound with Single-Action Exit, `POLICY_SEARCH_MODE=6`)입니다.

## 결과

### policy 단독

| Checkpoint-Capacity | Lookahead-Shots | Exhaustive DFS | Two-Request Bound Pruning | Seed-First Branch and Bound | Seed-First Branch and Bound with Single-Action Exit |
|:-:|:-:|---:|---:|---:|---:|
| 3 | 3 | 1,183,308 | 933,966 | 700,076 | 525,037 |
| 4 | 4 | 2,841,616 | 1,985,090 | 1,136,391 | 816,610 |
| 4 | 8 | 21,593,720 | 18,354,629 | 2,539,529 | 1,521,059 |

실험 24의 cycle model은 RTL보다 낙관적이었습니다(a Checkpoint-Capacity of 3 and 3-shot Lookahead 예측 590,569 대 Seed-First Branch and Bound benchmark 700,076). model에
Scan · seed · canonical 각 pass의 고정 latency가 빠져 있기 때문입니다.

### 통합 (Triple-Row Build, Dual-Row Build)

policy 계산의 대부분은 Grover 실행 뒤에 숨기 때문에 전체 cycle에는 stall만큼만 드러납니다.

| a Checkpoint-Capacity of 3 and 3-shot Lookahead | policy 단독 | stall | 전체 |
|---|---:|---:|---:|
| Triple-Row Build · Exhaustive DFS | 1,183,308 | 152,458 | 4,680,014 |
| Triple-Row Build · Seed-First Branch and Bound with Single-Action Exit | 525,037 | 39,440 | 4,566,996 |
| Dual-Row Build · Exhaustive DFS | 1,183,308 | 98,273 | 5,255,084 |
| Dual-Row Build · Seed-First Branch and Bound with Single-Action Exit | 525,037 | 38,280 | 5,195,091 |

- Triple-Row Build에서는 Lookahead-Shots를 키우면 stall이 iteration 절감보다 빨리 늘어 a Checkpoint-Capacity of 3 and 3-shot Lookahead가 최적입니다(a Checkpoint-Capacity of 4 and 3-shot Lookahead는 +0.02 %,
  a Checkpoint-Capacity of 4 and 4-shot Lookahead는 +0.28 % 느려 사실상 동률). Dual-Row Build는 숨길 시간이 길어 a Checkpoint-Capacity of 4 and 4-shot Lookahead가 최적입니다.
- Triple-Row Build가 줄인 고정 부분(약 63만 cycles)이 Checkpoint-Capacity · Lookahead-Shots로 줄일 수 있는 iteration(최대 약 24만 cycles)보다
  커서, Dual-Row Build는 어떤 Checkpoint-Capacity · Lookahead-Shots로도 Triple-Row Build의 a Checkpoint-Capacity of 3 and 3-shot Lookahead를 이기지 못합니다.

cell별 표, model, 40 cells heatmap, resource 무제한 가정의 Checkpoint-Capacity 1~10 × 1-shot ~ 10-shot Lookahead 추정은
[Checkpoint-Capacity · Lookahead-Shots evidence bundle](../../hardware_bram/results/2026-10-27_kh_sweep_m2_m3/evidence.md)에 있습니다.

### implementation

OOC placement · routing(100 MHz)은 policy 단독 a Checkpoint-Capacity of 3 and 3-shot Lookahead · a Checkpoint-Capacity of 4 and 8-shot Lookahead와 Accelerator Core Triple-Row Build 모두 통과했습니다(Accelerator Core
+0.068 ns, LUT +1,011). Arty 100T 전체 SoC 1차 implementation은 slice 99.07 %, WNS −0.302 ns로
실패했습니다. 실패 88 경로 중 68 개가 memo table BRAM 출력에서 search 제어 register의 enable로 가는
경로였고, search 제어 block를 memo table hit/miss 분기 앞으로 옮겨 없앴습니다(cycle 동일 확인).
2차 implementation이 진행 중입니다. 근거는 [policy RTL evidence bundle](../../hardware_bram/results/2026-10-27_policy_seed_first/evidence.md)
과 [`capacity3_lookahead3_pes4_triplerow_twolevel_seedfirst_singleexit` implementation evidence bundle](../../hardware_bram/configurations/capacity3_lookahead3_pes4_triplerow_twolevel_seedfirst_singleexit/vivado/vivado_bbht_grover_k3h3_e4_m3_s6/2026-10-27_arty100t_build/evidence.md).

## 남은 일

1. Arty 100T 2차 implementation 확인. 실패하면 `ExtraNetDelay_high` placement directive, 그래도 실패하면 Triple-Row Build · Exhaustive DFS 유지
2. Exhaustive DFS의 Checkpoint-Capacity 3 · 4 × 1-shot ~ 8-shot Lookahead 통합 benchmark(Dual-Row Build, Triple-Row Build) 완료 후 네 configuration 비교표 갱신
3. a Checkpoint-Capacity of 4 and 4-shot Lookahead memo table 압축 검토. model로는 a Checkpoint-Capacity of 4 and 4-shot Lookahead stall의 절반 가까이가 memo table initialization이고, 압축하면
   a Checkpoint-Capacity of 3 and 3-shot Lookahead보다 약 1.8 % 빨라질 것으로 추정
4. 기술문서 11장 · 5장 configuration 표 · CLAUDE.md configuration 목록 · 실험 보고서 index 반영
5. 실험 22~24 도구(`kh_sweep.py` 등)와 이 실험의 분석 script를 저장소 경로로 정리
