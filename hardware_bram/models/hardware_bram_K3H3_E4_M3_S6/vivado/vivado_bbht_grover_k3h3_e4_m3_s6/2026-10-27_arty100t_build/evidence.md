# K3H3_E4_M3_S6 Arty 100T 구현 (진행 중)

상태: **진행 중.** 1차 구현은 타이밍 실패. 원인을 고친 RTL 로 2차 구현을 돌리는 중이며
결과는 아직 이 묶음에 없습니다.

| 항목 | 값 |
|---|---|
| 부품 | Arty A7-100T (`xc7a100tcsg324-1`), RVX 플랫폼 `bbht_grover_k3h3_e4_m3_s6` |
| 클럭 | `sys_clk_pin` 10 ns (100 MHz) |
| Vivado | 2026.1, RVX 기본 흐름(지시어 없음), `general.maxThreads 1` |
| 비교 기준 | 같은 Main IP 의 prune0 판 `K3H3_E4_M3`: 기본 흐름 WNS +0.106, `ExtraNetDelay_high` +0.182 ([M3 묶음](../../../../hardware_bram_K3H3_E4_M3/results/2026-10-27_m3_wns0182/evidence.md)) |

## 1차 구현 (`v1_wns-0302/`, RTL 커밋 `f02dd60`)

| 항목 | 값 |
|---|---:|
| WNS / TNS | −0.302 ns / −10.186 ns |
| 실패 끝점 | 88 |
| WHS | +0.026 ns |
| 배선 오류 | 0 |
| Slice | 15,703 / 15,850 (99.07 %) |
| LUT / FF | 52,074 / 47,664 |
| BRAM tile / DSP | 113.5 / 196 |

실패 경로 88개(`failing_paths.txt`)는 세 부류였습니다.

| 경로 | 개수 | 원인 |
|---|---:|---|
| memo BRAM 출력 → `f_best_cost` · `f_dmask` · `actionq_*` 의 CE | 68 | EXACT_PRUNE=5/6 의 탐색 제어 쓰기를 memo hit/miss 분기 안에 두어 BRAM → hit 판정 → CE 경로가 생김 |
| `pvalq` → `pmeta` (루트 tie-break 정렬) | 11 | 기존 최악 경로, slice 99 % 혼잡 |
| 생성기 `a_dmask` → `f_rmask`, Born `lane_index` → `st` | 8 | 혼잡 |

메모리: 4스레드로 돌린 두 번의 시도는 컨테이너 메모리(최고 10.8 GB)를 넘어 합성 중 OOM 으로
죽었습니다. 1스레드로 완료했습니다.

## 2차 구현 (진행 중)

첫 부류를 없애려고 탐색 제어 블록을 memo hit/miss 분기 **앞으로** 옮겼습니다
(`grover_policy.v`). 같은 사이클의 miss 분기가 나중에 쓰므로 동작은 같고, 정책 단독
34회 · `regress-real` · S6 bench500 이 사이클 단위로 같음을 확인했습니다
([정책 RTL 묶음](../../../../../results/2026-10-27_policy_seed_first/evidence.md)).
2차 구현 결과는 끝나면 이 묶음에 `v2_*/` 로 더합니다.

`bitstream_sha256.txt` 는 1차 빌드 비트스트림의 해시입니다. 타이밍 위반이라 보드에 올리지
않습니다.
