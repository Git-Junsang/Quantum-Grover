# 실험 12. Board-Verified Build 500 workloads

> [← 실험 11 채택하지 않은 확장과 variant](11_rejected_extensions.md) · [index](index.md) · [실험 13 Accelerator Core 최종 발표 (v1.3) →](13_accelerator_core_final_presentation.md)

---

| 확인한 것 | 근거의 축 |
|---|---|
| 성능 세 축(board wall-clock time · RTL cycle · ORCA 대비)의 Board-Verified Build 묶음 | board wall-clock time (Arty A7-100T) |

2026-09-08에 2026-09-07 build bitstream을 Arty A7-100T에 굽고, 500 workloads를 Restart mode · a Checkpoint-Capacity of 4 and 4-shot Lookahead ·
final configuration 세 구성으로 돌린 benchmark입니다. 같은 chip · 같은 workload · 같은 seed로 ORCA 1 core 순수 software
baseline도 같이 쟀습니다. 이 묶음이 성능 세 축의 source of truth입니다.

## 조건

| 항목 | 값 |
|---|---|
| bitstream | 2026-09-07 build (Vivado 2024.2) |
| app | `bbht_paper_bench.elf` |
| workload | 1 · 4 · 16 · 64 · 256 solutions × 100 seeds = 500 |
| 조건 | `EQ`(12345), 16,384 data entries, shot cap 100 |

## 결과

결과 수치와 인용 규칙은 성능 세 축의 source of truth라
[1장 1.5절](../design_references/01_project_overview.md#15-성능-지표와-인용-기준) 한 곳에만 적습니다. ORCA speedup에
붙여야 하는 단서(32 lanes 병렬과 clock 2× 때문이지 algorithm 우위가 아님)도 거기 있습니다.

같은 app · 같은 workload를 2026-10-08에 200T board에서 다시 잰 값과의 workload별 대조는
[실험 18 「100T Board-Verified Build와의 대조」](18_six_stage_ablation_comparison.md#100t-board-verified-build와의-대조)에 있습니다.

## 근거

- board wall-clock time 세 구성: [board_500run](../../hardware_bram/configurations/final/vivado/vivado_bbht_grover_fpga/2026-09-08_k3h3_e4_m2_board_500run/evidence.md)
- ORCA 1 core baseline: [orca_1core_baseline](../../hardware_bram/configurations/final/vivado/vivado_bbht_grover_fpga/2026-09-08_orca_1core_baseline/evidence.md)
- 실물(bitstream · 두 ELF · hash): [bitstream/2026-09-08_k3h3_e4_m2](../../hardware_bram/configurations/final/bitstream/2026-09-08_k3h3_e4_m2/evidence.md)
