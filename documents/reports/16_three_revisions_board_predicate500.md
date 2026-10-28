# 실험 16. 세 revision의 board Predicate500

> [← 실험 15 Bus Interface revision board console](15_revised_bus_interface_board_console.md) · [index](index.md) · [실험 17 C++ · NumPy · Qiskit baseline 비교 →](17_cpp_numpy_qiskit_baselines.md)

---

| 확인한 것 | 근거의 축 |
|---|---|
| 세 revision(final configuration · No-Checkpoint Baseline · DRAM Variant)이 실물에서 reference model과 같은가, 같은 board 위 revision 사이 speedup | board wall-clock time · board cycle (Arty A7-100T, 8,000 runs) |

[18장](../design_references/18_predicate500_automated_test.md)의 host 프로그램으로 LT · GT · EQ · RANGE 각 500 workloads를 세 revision에서 돌렸습니다. revision마다 묶음의 bitstream과 2026-09-25 revision의 console app을 굽고
올렸고, hash는 저장소의 것과 같습니다. revision마다 smoke(네 predicate × 다섯 가지 number of solutions × 두 seeds)를 먼저 돌린
뒤 reset 없이 본 실행을 이어 갔습니다.

| revision | runs | reference model과 네 축 | RTL testbench와 cycle | wall-clock time sum |
|---|--:|--:|---|--:|
| final configuration, Restart mode | 2,000 | 2,000/2,000 | 2,000/2,000 | 478,975 µs |
| final configuration, Checkpoint mode | 2,000 | 2,000/2,000 | 1,769/2,000 (memo table 청소 위치 차이) | 221,032 µs |
| No-Checkpoint Baseline | 2,000 | 2,000/2,000 | 2,000/2,000 | 621,210 µs |
| DRAM Variant | 2,000 | 2,000/2,000 | AXI model의 1.439× (SoC simulation과 0.16% 안) | 3,459,012 µs |

네 축은 `result_index` · `trial_count` · `L_BBHT` · `actual_iter`이고 predicate 판정도 전부 맞습니다.
LT · GT · RANGE와 다른 두 revision은 이번에 처음 실물에서 benchmark 규모로 돌았습니다. DRAM Variant는
DDR3가 accelerator의 amplitude table로 쓰인 첫 실물 실행이기도 합니다.

같은 board에서 맞댄 wall-clock time speedup은 다음과 같습니다(네 predicate sum).

| 비교 | wall-clock time | board cycle |
|---|--:|--:|
| final configuration 대 No-Checkpoint Baseline | 2.810× | 2.897× |
| 그중 Measurement Microarchitecture(Dual-Row Build · Two-Level Select) 몫 (final configuration의 Restart mode 대 No-Checkpoint Baseline) | 1.297× | 1.303× |
| 그중 checkpoint 몫 (final configuration의 Checkpoint mode 대 Restart mode) | 2.167× | 2.223× |
| DRAM Variant 대 final configuration의 Checkpoint mode (느린 쪽) | 15.65× | 16.36× |

cycle speedup은 [20장 20.5절](../design_references/20_no_checkpoint_baseline.md)의 RTL 값과 같습니다. wall-clock time speedup이
조금 작은 것은 run마다 붙는 고정 4~7 µs 때문이고, run이 짧은 Checkpoint mode 쪽에서 비중이 더
큽니다.

**Bus Interface revision의 wall-clock time도 여기서 확인됐습니다.** EQ 500은 Board-Verified Build 500 runs와 dataset · seed가
같습니다. final configuration의 Checkpoint mode가 Board-Verified Build와 BBHT trajectory 500/500, cycle 442/500이 같고,
wall-clock time sum은 55,963 µs 대 55,798 µs(+0.30%)입니다. cycle이 같은 run은 wall-clock time도 ±3 µs
안입니다.

DRAM Variant는 BRAM Variant의 두 revision과 달리 같은 workload를 다시 돌려도 cycle이 수십 cycle씩 달라집니다
(smoke와 본 실행이 40건 중 7건만 같고, 차이는 최대 0.033%). 실제 DDR3의 latency가 run마다 다른
것으로 보이고 BBHT trajectory에는 영향이 없습니다.

board에서 새로 찾은 것은 하나입니다. console이 보내는 한글 주석 줄 `# amp_overflow (진단용, 결과는
유효)`를 host가 ascii로 풀어 log에서 깨졌습니다. 결과 값과는 무관하고, `bbht_cli.py`의
`SerialTransport`를 UTF-8 incremental decoder로 고쳤습니다.

근거는 revision마다 하나씩입니다.
[final configuration](../../hardware_bram/configurations/final/vivado/vivado_bbht_grover_fpga/2026-10-04_board_predicate500/evidence.md) ·
[No-Checkpoint Baseline](../../hardware_bram/configurations/no_checkpoint_baseline/vivado/vivado_bbht_grover_nocheckpoint/2026-10-04_board_predicate500/evidence.md) ·
[DRAM Variant](../../hardware_dram/vivado/vivado_bbht_grover_dram/2026-10-04_board_predicate500/evidence.md).
