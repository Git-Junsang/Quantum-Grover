# a Checkpoint-Capacity of 3, 3-shot Lookahead, 4 PEs, Triple-Row Build · Two-Level Select, Seed-First Branch and Bound with Single-Action Exit — Arty 100T implementation (진행 중)

현황: **진행 중.** 1차 implementation은 timing 실패. 원인을 고친 RTL로 2차 implementation을 돌리는 중이며
결과는 아직 이 묶음에 없습니다.

| 항목 | 값 |
|---|---|
| 부품 | Arty A7-100T (`xc7a100tcsg324-1`), 그때의 RVX platform `bbht_grover_k3h3_e4_m3_s6` |
| clock | `sys_clk_pin` 10 ns (100 MHz) |
| Vivado | 2026.1, RVX 기본 흐름(directive 없음), `general.maxThreads 1` |
| baseline | 같은 Accelerator Core의 Exhaustive DFS revision `capacity3_lookahead3_pes4_triplerow_twolevel`: 기본 흐름 WNS +0.106, `ExtraNetDelay_high` +0.182 ([Triple-Row Build 묶음](../../../../capacity3_lookahead3_pes4_triplerow_twolevel/results/2026-10-27_m3_wns0182/evidence.md)) |

## 1차 implementation (`v1_wns-0302/`, RTL commit `f02dd60`)

| 항목 | 값 |
|---|---:|
| WNS / TNS | −0.302 ns / −10.186 ns |
| 실패 endpoint | 88 |
| WHS | +0.026 ns |
| routing 오류 | 0 |
| Slice | 15,703 / 15,850 (99.07 %) |
| LUT / FF | 52,074 / 47,664 |
| BRAM tile / DSP | 113.5 / 196 |

실패 경로 88개(`failing_paths.txt`)는 세 부류였습니다.

| 경로 | 개수 | 원인 |
|---|---:|---|
| memo table BRAM 출력 → `f_best_cost` · `f_dmask` · `actionq_*` 의 CE | 68 | policy search mode 5 · 6의 search 제어 쓰기를 memo table hit/miss 분기 안에 두어 BRAM → hit 판정 → CE 경로가 생김 |
| `pvalq` → `pmeta` (root tie-break 정렬) | 11 | 기존 최악 경로, slice 99 % 혼잡 |
| 생성기 `a_dmask` → `f_rmask`, Born `lane_index` → `st` | 8 | 혼잡 |

memory: 4 threads로 돌린 두 번의 시도는 container memory(최고 10.8 GB)를 넘어 synthesis 중 OOM으로
죽었습니다. 1 thread로 완료했습니다.

## 2차 implementation (진행 중)

첫 부류를 없애려고 search 제어 block을 memo table hit/miss 분기 **앞으로** 옮겼습니다
(`grover_policy.v`). 같은 cycle의 miss 분기가 나중에 쓰므로 동작은 같고, policy 단독
34회 · `regress-real` · policy search mode 6의 bench500이 cycle 단위로 같음을 확인했습니다
([policy RTL 묶음](../../../../../results/2026-10-27_policy_seed_first/evidence.md)).
2차 implementation 결과는 끝나면 이 묶음에 `v2_*/` 로 더합니다.

`bitstream_sha256.txt` 는 1차 build bitstream의 hash입니다. timing 위반이라 board에 올리지
않습니다.
