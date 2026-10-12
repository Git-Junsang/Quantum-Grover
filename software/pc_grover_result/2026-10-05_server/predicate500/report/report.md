# predicate500 backend comparison

SW environment: Intel(R) Core(TM) i5-14600K, 8 physical cores / 8 logical CPUs; single-core runs pinned to CPU 13 (max 4000.0000 MHz).
FPGA: Arty A7-100T, 2026-10-04 board Predicate500. K3/H3-E4-M2 and NORMAL (E4-M2) come from the same bitstream (burst_enable 1/0); NOCKPT = Normal-E4 build; DRAM = DDR3 all-j table. Board time = command-to-DONE (DMA load, CSR config and readback excluded).
SW: search_ns = whole BBHT search with the dataset loaded and the oracle mask built.
SW suffixes: `_T<n>` = one search split over n cores (latency mode); `_W<n>` = n searches in parallel (throughput).
`CPP_SW_BEST_K3H3_*_T4` / `CPP_RTL_EXACT_K3H3_T4` = SW counterpart of K3/H3-E4-M2 (K3H3 policy, 4 cores per iteration, hierarchical sampler).
"is faster by" = backend total search time / FPGA total over the same workloads (>1: the FPGA is faster).

## Timing (totals over the same workloads)

| Backend | runs | search total (ms) | compute total (ms) | E2E total (ms) | FPGA K3H3_E4_M2 is faster by | FPGA NORMAL_E4_M2 is faster by |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `FPGA_K3H3_E4_M2` | 2000 | 221.0 | - | - | 1.00x | 0.46x |
| `CPP_SW_BEST_ALLJ_F32` | 2000 | 228.1 | 164.5 | 324.4 | 1.03x | 0.48x |
| `CPP_SW_BEST_ALLJ_F64` | 2000 | 270.9 | 219.6 | 374.4 | 1.23x | 0.57x |
| `CPP_SW_BEST_ALLJ_F32_W8` | 2000 | 314.0 | 240.4 | 424.9 | 1.42x | 0.66x |
| `CPP_SW_BEST_K3H3_F32_T4` | 2000 | 316.1 | 79.2 | 440.8 | 1.43x | 0.66x |
| `CPP_RTL_EXACT_ALLJ` | 2000 | 337.3 | 276.7 | 440.8 | 1.53x | 0.70x |
| `CPP_RTL_EXACT_K3H3_T4` | 2000 | 342.7 | 95.3 | 472.4 | 1.55x | 0.72x |
| `CPP_SW_BEST_K4H4_F32` | 2000 | 391.0 | 170.8 | 492.6 | 1.77x | 0.82x |
| `CPP_SW_BEST_K3H3_F32` | 2000 | 404.6 | 180.9 | 541.8 | 1.83x | 0.84x |
| `CPP_SW_BEST_NORMAL_F32_T4` | 2000 | 414.1 | 250.3 | 533.2 | 1.87x | 0.86x |
| `CPP_SW_BEST_K3H3_F64_T4` | 2000 | 455.8 | 144.1 | 576.9 | 2.06x | 0.95x |
| `FPGA_NORMAL_E4_M2` | 2000 | 479.0 | - | - | 2.17x | 1.00x |
| `CPP_RTL_EXACT_NORMAL_T4` | 2000 | 491.5 | 326.5 | 607.5 | 2.22x | 1.03x |
| `CPP_SW_BEST_NORMAL_F32_T8` | 2000 | 491.6 | 318.8 | 595.8 | 2.22x | 1.03x |
| `CPP_SW_BEST_NORMAL_F32_T2` | 2000 | 493.9 | 330.4 | 612.6 | 2.23x | 1.03x |
| `CPP_SW_BEST_K4H4_F64` | 2000 | 506.3 | 231.3 | 617.6 | 2.29x | 1.06x |
| `CPP_SW_BEST_NORMAL_F64_T8` | 2000 | 517.3 | 287.5 | 640.9 | 2.34x | 1.08x |
| `CPP_RTL_EXACT_K3H3` | 2000 | 521.1 | 306.2 | 636.8 | 2.36x | 1.09x |
| `CPP_SW_BEST_K3H3_F64` | 2000 | 542.6 | 240.7 | 645.0 | 2.45x | 1.13x |
| `FPGA_NOCKPT_NORMAL_E4` | 2000 | 621.2 | - | - | 2.81x | 1.30x |
| `CPP_SW_BEST_NORMAL_F64_T4` | 2000 | 671.3 | 465.6 | 791.1 | 3.04x | 1.40x |
| `CPP_SW_BEST_NORMAL_F64_T2` | 2000 | 682.5 | 490.0 | 782.7 | 3.09x | 1.42x |
| `CPP_SW_BEST_ALLJ_F64_W8` | 2000 | 741.6 | 648.3 | 862.2 | 3.36x | 1.55x |
| `CPP_SW_BEST_NORMAL_F32` | 2000 | 764.6 | 602.3 | 874.8 | 3.46x | 1.60x |
| `CPP_SW_BEST_NORMAL_F64` | 2000 | 976.6 | 795.5 | 1091.6 | 4.42x | 2.04x |
| `CPP_SW_BEST_NORMAL_F32_W8` | 2000 | 1099.2 | 870.1 | 1205.8 | 4.97x | 2.29x |
| `CPP_RTL_EXACT_NORMAL` | 2000 | 1169.4 | 1016.1 | 1271.1 | 5.29x | 2.44x |
| `CPP_RTL_EXACT_NORMAL_W8` | 2000 | 1289.7 | 1090.5 | 1411.0 | 5.84x | 2.69x |
| `NUMPY_ALLJ_F64` | 2000 | 1744.9 | 653.7 | 1880.8 | 7.89x | 3.64x |
| `CPP_SW_BEST_NORMAL_F64_W8` | 2000 | 2086.6 | 1696.4 | 2190.9 | 9.44x | 4.36x |
| `NUMPY_K3H3_F64` | 2000 | 2279.7 | 711.9 | 2442.4 | 10.31x | 4.76x |
| `NUMPY_ALLJ_F64_W8` | 2000 | 2748.4 | 1209.2 | 2967.0 | 12.43x | 5.74x |
| `NUMPY_NORMAL_F64` | 2000 | 3006.5 | 2171.6 | 3170.8 | 13.60x | 6.28x |
| `NUMPY_K3H3_F64_W8` | 2000 | 3153.0 | 1074.4 | 3334.5 | 14.26x | 6.58x |
| `FPGA_DRAM_ALLJ_SESSION` | 2000 | 3459.0 | - | - | 15.65x | 7.22x |
| `NUMPY_NORMAL_F64_W8` | 2000 | 4964.7 | 3895.2 | 5148.5 | 22.46x | 10.37x |
| `GOLDEN_PY_K3H3` | 2000 | 9899.1 | 4423.5 | 29919.5 | 44.79x | 20.67x |
| `GOLDEN_PY_ALLJ` | 2000 | 14383.4 | 9525.0 | 34417.4 | 65.07x | 30.03x |
| `GOLDEN_PY_K3H3_W8` | 2000 | 15123.8 | 7333.6 | 39341.9 | 68.42x | 31.58x |
| `GOLDEN_PY_NORMAL` | 2000 | 19133.9 | 14699.7 | 39112.2 | 86.57x | 39.95x |
| `GOLDEN_PY_ALLJ_W8` | 2000 | 20870.9 | 14412.1 | 44229.0 | 94.42x | 43.57x |
| `GOLDEN_PY_NORMAL_W8` | 2000 | 26257.4 | 20443.8 | 49528.7 | 118.79x | 54.82x |
| `QISKIT_AER_ALLJ_F64` | 400 | 62315.2 | 20488.3 | 67517.1 | 1409.59x | 650.27x |
| `QISKIT_AER_ALLJ_F64_T8` | 400 | 64216.4 | 21766.0 | 69498.6 | 1452.60x | 670.11x |
| `QISKIT_AER_K3H3_F64` | 400 | 69614.0 | 22732.2 | 76297.2 | 1574.69x | 726.44x |
| `QISKIT_AER_K3H3_F64_T8` | 400 | 70596.2 | 22690.0 | 77563.2 | 1596.91x | 736.69x |
| `QISKIT_AER_NORMAL_F64_T8` | 400 | 200071.7 | 51128.3 | 212515.1 | 4525.69x | 2087.80x |
| `QISKIT_AER_NORMAL_F64` | 400 | 225573.3 | 77463.0 | 238553.7 | 5102.54x | 2353.91x |

## Throughput (multi-core, workloads in parallel)

| Backend | workers | searches per second | FPGA K3/H3 is faster by |
| --- | ---: | ---: | ---: |
| `FPGA_K3H3_E4_M2` | 1 engine | 9,048 | 1.00x |
| `CPP_RTL_EXACT_NORMAL_W8` (2000 workloads) | 8 | 10,744 | 0.84x |
| `CPP_SW_BEST_ALLJ_F32_W8` (2000 workloads) | 8 | 34,476 | 0.26x |
| `CPP_SW_BEST_ALLJ_F64_W8` (2000 workloads) | 8 | 15,985 | 0.57x |
| `CPP_SW_BEST_NORMAL_F32_W8` (2000 workloads) | 8 | 13,183 | 0.69x |
| `CPP_SW_BEST_NORMAL_F64_W8` (2000 workloads) | 8 | 7,196 | 1.26x |
| `GOLDEN_PY_ALLJ_W8` (2000 workloads) | 8 | 593 | 15.26x |
| `GOLDEN_PY_K3H3_W8` (2000 workloads) | 8 | 720 | 12.57x |
| `GOLDEN_PY_NORMAL_W8` (2000 workloads) | 8 | 496 | 18.23x |
| `NUMPY_ALLJ_F64_W8` (2000 workloads) | 8 | 4,392 | 2.06x |
| `NUMPY_K3H3_F64_W8` (2000 workloads) | 8 | 3,715 | 2.44x |
| `NUMPY_NORMAL_F64_W8` (2000 workloads) | 8 | 2,871 | 3.15x |

## Equivalence

Trajectory = (result_index, trial_count, L_BBHT) per workload; FPGA reference = `FPGA_NORMAL_E4_M2`.

| Backend | = FPGA trajectory | = float trajectory (`NUMPY_NORMAL_F64`) |
| --- | ---: | ---: |
| `FPGA_NORMAL_E4_M2` | 2000/2000 | 96/2000 |
| `FPGA_K3H3_E4_M2` | 2000/2000 | 96/2000 |
| `FPGA_NOCKPT_NORMAL_E4` | 2000/2000 | 96/2000 |
| `FPGA_DRAM_ALLJ_SESSION` | 2000/2000 | 96/2000 |
| `CPP_RTL_EXACT_ALLJ` | 2000/2000 | 96/2000 |
| `CPP_RTL_EXACT_K3H3` | 2000/2000 | 96/2000 |
| `CPP_RTL_EXACT_K3H3_T4` | 2000/2000 | 96/2000 |
| `CPP_RTL_EXACT_NORMAL` | 2000/2000 | 96/2000 |
| `CPP_RTL_EXACT_NORMAL_T4` | 2000/2000 | 96/2000 |
| `CPP_RTL_EXACT_NORMAL_W8` | 2000/2000 | 96/2000 |
| `CPP_SW_BEST_ALLJ_F32` | 96/2000 | 2000/2000 |
| `CPP_SW_BEST_ALLJ_F32_W8` | 96/2000 | 2000/2000 |
| `CPP_SW_BEST_ALLJ_F64` | 96/2000 | 2000/2000 |
| `CPP_SW_BEST_ALLJ_F64_W8` | 96/2000 | 2000/2000 |
| `CPP_SW_BEST_K3H3_F32` | 96/2000 | 2000/2000 |
| `CPP_SW_BEST_K3H3_F32_T4` | 96/2000 | 2000/2000 |
| `CPP_SW_BEST_K3H3_F64` | 96/2000 | 2000/2000 |
| `CPP_SW_BEST_K3H3_F64_T4` | 96/2000 | 2000/2000 |
| `CPP_SW_BEST_K4H4_F32` | 96/2000 | 2000/2000 |
| `CPP_SW_BEST_K4H4_F64` | 96/2000 | 2000/2000 |
| `CPP_SW_BEST_NORMAL_F32` | 96/2000 | 2000/2000 |
| `CPP_SW_BEST_NORMAL_F32_T2` | 96/2000 | 2000/2000 |
| `CPP_SW_BEST_NORMAL_F32_T4` | 96/2000 | 2000/2000 |
| `CPP_SW_BEST_NORMAL_F32_T8` | 96/2000 | 2000/2000 |
| `CPP_SW_BEST_NORMAL_F32_W8` | 96/2000 | 2000/2000 |
| `CPP_SW_BEST_NORMAL_F64` | 96/2000 | 2000/2000 |
| `CPP_SW_BEST_NORMAL_F64_T2` | 96/2000 | 2000/2000 |
| `CPP_SW_BEST_NORMAL_F64_T4` | 96/2000 | 2000/2000 |
| `CPP_SW_BEST_NORMAL_F64_T8` | 96/2000 | 2000/2000 |
| `CPP_SW_BEST_NORMAL_F64_W8` | 96/2000 | 2000/2000 |
| `GOLDEN_PY_ALLJ` | 2000/2000 | 96/2000 |
| `GOLDEN_PY_ALLJ_W8` | 2000/2000 | 96/2000 |
| `GOLDEN_PY_K3H3` | 2000/2000 | 96/2000 |
| `GOLDEN_PY_K3H3_W8` | 2000/2000 | 96/2000 |
| `GOLDEN_PY_NORMAL` | 2000/2000 | 96/2000 |
| `GOLDEN_PY_NORMAL_W8` | 2000/2000 | 96/2000 |
| `NUMPY_ALLJ_F64` | 96/2000 | 2000/2000 |
| `NUMPY_ALLJ_F64_W8` | 96/2000 | 2000/2000 |
| `NUMPY_K3H3_F64` | 96/2000 | 2000/2000 |
| `NUMPY_K3H3_F64_W8` | 96/2000 | 2000/2000 |
| `NUMPY_NORMAL_F64` | 96/2000 | 2000/2000 |
| `NUMPY_NORMAL_F64_W8` | 96/2000 | 2000/2000 |
| `QISKIT_AER_ALLJ_F64` | 19/400 | 400/400 |
| `QISKIT_AER_ALLJ_F64_T8` | 19/400 | 400/400 |
| `QISKIT_AER_K3H3_F64` | 19/400 | 400/400 |
| `QISKIT_AER_K3H3_F64_T8` | 19/400 | 400/400 |
| `QISKIT_AER_NORMAL_F64` | 19/400 | 400/400 |
| `QISKIT_AER_NORMAL_F64_T8` | 19/400 | 400/400 |

## Float vs fixed-point (FPGA) distributions

Float and Q1.22 state vectors sample different trajectories per seed, so distributions are compared
(two-sided; p > 0.05 = no detectable difference). Tests with p < 0.05: 1 of 40
(about 2.0 expected by chance).

| predicate | M | float success | FPGA success | trials median float / FPGA | Mann-Whitney p (trials) | KS p (L_BBHT) |
| --- | ---: | ---: | ---: | --- | ---: | ---: |
| EQ | 1 | 100/100 | 100/100 | 23.0 / 23.0 | 0.870 | 0.702 |
| EQ | 4 | 100/100 | 100/100 | 20.0 / 19.0 | 0.601 | 0.815 |
| EQ | 16 | 100/100 | 100/100 | 16.0 / 16.0 | 0.977 | 0.815 |
| EQ | 64 | 100/100 | 100/100 | 11.0 / 11.0 | 0.586 | 0.908 |
| EQ | 256 | 100/100 | 100/100 | 8.0 / 7.0 | 0.407 | 0.470 |
| GT | 1 | 100/100 | 100/100 | 23.0 / 23.0 | 0.347 | 0.583 |
| GT | 4 | 100/100 | 100/100 | 19.0 / 20.0 | 0.564 | 0.470 |
| GT | 16 | 100/100 | 100/100 | 16.0 / 15.0 | 0.156 | 0.282 |
| GT | 64 | 100/100 | 100/100 | 11.0 / 11.0 | 0.532 | 0.968 |
| GT | 256 | 100/100 | 100/100 | 8.0 / 7.0 | 0.005 | 0.036 |
| LT | 1 | 100/100 | 100/100 | 24.0 / 23.5 | 0.833 | 0.908 |
| LT | 4 | 100/100 | 100/100 | 19.5 / 19.0 | 0.917 | 0.908 |
| LT | 16 | 100/100 | 100/100 | 16.0 / 15.0 | 0.207 | 0.368 |
| LT | 64 | 100/100 | 100/100 | 11.0 / 11.0 | 0.484 | 0.908 |
| LT | 256 | 100/100 | 100/100 | 7.0 / 7.0 | 0.560 | 0.994 |
| RANGE | 1 | 100/100 | 100/100 | 23.0 / 22.5 | 0.401 | 0.470 |
| RANGE | 4 | 100/100 | 100/100 | 19.0 / 19.0 | 0.184 | 0.155 |
| RANGE | 16 | 100/100 | 100/100 | 15.0 / 15.0 | 0.536 | 0.968 |
| RANGE | 64 | 100/100 | 100/100 | 12.0 / 11.0 | 0.333 | 0.583 |
| RANGE | 256 | 100/100 | 100/100 | 8.0 / 7.0 | 0.371 | 0.702 |
