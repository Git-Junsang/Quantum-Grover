# common500 backend comparison

SW environment: Intel Xeon @ 2.80GHz (cloud dev VM), 2 threads; single-core runs pinned to core 1; REPS=1, Qiskit on 2 seeds (smoke run).
FPGA: Arty A7-100T, 2026-09-08 board 500-run (EQ). Standard ref = Normal-E1 (different bitstream from K3/H3-E4-M2). Board time = command-to-DONE (DMA load, CSR config and readback excluded).
SW: search_ns = whole BBHT search with the dataset loaded and the oracle mask built.
"is faster by" = backend total search time / FPGA total over the same workloads (>1: the FPGA is faster).

## Timing (totals over the same workloads)

| Backend | runs | search total (ms) | compute total (ms) | E2E total (ms) | FPGA K3H3_E4_M2 is faster by | FPGA NORMAL_E1 is faster by |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `FPGA_K3H3_E4_M2` | 500 | 55.8 | - | - | 1.00x | 0.13x |
| `CPP_SW_BEST_ALLJ_F32` | 500 | 65.0 | 47.8 | 69.5 | 1.16x | 0.15x |
| `CPP_SW_BEST_ALLJ_F32_W2` | 500 | 78.0 | 61.1 | 81.9 | 1.40x | 0.18x |
| `CPP_SW_BEST_ALLJ_F64` | 500 | 103.5 | 84.8 | 108.7 | 1.85x | 0.24x |
| `CPP_SW_BEST_K4H4_F32` | 500 | 112.9 | 43.7 | 116.7 | 2.02x | 0.27x |
| `CPP_SW_BEST_ALLJ_F64_W2` | 500 | 114.2 | 94.1 | 121.9 | 2.05x | 0.27x |
| `CPP_RTL_EXACT_K3H3` | 500 | 127.9 | 74.8 | 131.6 | 2.29x | 0.30x |
| `CPP_SW_BEST_K3H3_F32` | 500 | 157.2 | 67.4 | 162.3 | 2.82x | 0.37x |
| `FPGA_K4H4_E1` | 500 | 164.9 | - | - | 2.96x | 0.39x |
| `CPP_SW_BEST_K4H4_F64` | 500 | 196.4 | 68.7 | 200.3 | 3.52x | 0.46x |
| `CPP_SW_BEST_NORMAL_F32_W2` | 500 | 210.2 | 164.5 | 214.7 | 3.77x | 0.49x |
| `CPP_SW_BEST_NORMAL_F32` | 500 | 249.4 | 201.1 | 254.6 | 4.47x | 0.59x |
| `CPP_SW_BEST_NORMAL_F64` | 500 | 257.3 | 204.3 | 261.8 | 4.61x | 0.60x |
| `CPP_RTL_EXACT_NORMAL` | 500 | 261.7 | 230.2 | 266.1 | 4.69x | 0.61x |
| `CPP_SW_BEST_NORMAL_F64_W2` | 500 | 268.7 | 212.9 | 272.8 | 4.82x | 0.63x |
| `CPP_SW_BEST_K3H3_F64` | 500 | 304.7 | 84.5 | 308.3 | 5.46x | 0.72x |
| `CPP_RTL_EXACT_NORMAL_W2` | 500 | 305.8 | 269.7 | 309.5 | 5.48x | 0.72x |
| `FPGA_NORMAL_E1` | 500 | 425.5 | - | - | 7.63x | 1.00x |
| `CPP_SW_BEST_NORMAL_F32_T2` | 500 | 592.4 | 533.7 | 597.3 | 10.62x | 1.39x |
| `CPP_SW_BEST_NORMAL_F64_T2` | 500 | 726.6 | 632.2 | 731.8 | 13.02x | 1.71x |
| `NUMPY_ALLJ_F64` | 500 | 728.9 | 336.7 | 757.0 | 13.06x | 1.71x |
| `NUMPY_NORMAL_F64` | 500 | 960.2 | 640.3 | 975.3 | 17.21x | 2.26x |
| `NUMPY_K3H3_F64` | 500 | 1096.2 | 282.9 | 1124.5 | 19.65x | 2.58x |
| `QISKIT_AER_ALLJ_F64_T2` | 10 | 2901.1 | 761.4 | 4013.2 | 2590.30x | 337.07x |
| `QISKIT_AER_K3H3_F64_T2` | 10 | 2985.1 | 743.0 | 4094.3 | 2665.25x | 346.82x |
| `QISKIT_AER_ALLJ_F64` | 10 | 3125.0 | 1135.8 | 4160.3 | 2790.19x | 363.08x |
| `QISKIT_AER_K3H3_F64` | 10 | 3711.0 | 1261.4 | 4822.0 | 3313.37x | 431.16x |
| `QISKIT_AER_NORMAL_F64_T2` | 10 | 10609.6 | 2747.8 | 12551.4 | 9472.86x | 1232.67x |
| `QISKIT_AER_NORMAL_F64` | 10 | 14037.4 | 5062.2 | 16035.5 | 12533.38x | 1630.93x |

## Throughput (multi-core, workloads in parallel)

| Backend | workers | searches per second | FPGA K3/H3 is faster by |
| --- | ---: | ---: | ---: |
| `FPGA_K3H3_E4_M2` | 1 engine | 8,961 | 1.00x |
| `CPP_RTL_EXACT_NORMAL_W2` (500 workloads) | 2 | 3,197 | 2.80x |
| `CPP_SW_BEST_ALLJ_F32_W2` (500 workloads) | 2 | 11,450 | 0.78x |
| `CPP_SW_BEST_ALLJ_F64_W2` (500 workloads) | 2 | 6,044 | 1.48x |
| `CPP_SW_BEST_NORMAL_F32_W2` (500 workloads) | 2 | 4,643 | 1.93x |
| `CPP_SW_BEST_NORMAL_F64_W2` (500 workloads) | 2 | 3,561 | 2.52x |

## Equivalence

Trajectory = (result_index, trial_count, L_BBHT) per workload; FPGA reference = `FPGA_NORMAL_E1`.

| Backend | = FPGA trajectory | = float trajectory (`NUMPY_NORMAL_F64`) |
| --- | ---: | ---: |
| `FPGA_NORMAL_E1` | 500/500 | 23/500 |
| `FPGA_K4H4_E1` | 500/500 | 23/500 |
| `FPGA_K3H3_E4_M2` | 500/500 | 23/500 |
| `CPP_RTL_EXACT_K3H3` | 500/500 | 23/500 |
| `CPP_RTL_EXACT_NORMAL` | 500/500 | 23/500 |
| `CPP_RTL_EXACT_NORMAL_W2` | 500/500 | 23/500 |
| `CPP_SW_BEST_ALLJ_F32` | 23/500 | 500/500 |
| `CPP_SW_BEST_ALLJ_F32_W2` | 23/500 | 500/500 |
| `CPP_SW_BEST_ALLJ_F64` | 23/500 | 500/500 |
| `CPP_SW_BEST_ALLJ_F64_W2` | 23/500 | 500/500 |
| `CPP_SW_BEST_K3H3_F32` | 23/500 | 500/500 |
| `CPP_SW_BEST_K3H3_F64` | 23/500 | 500/500 |
| `CPP_SW_BEST_K4H4_F32` | 23/500 | 500/500 |
| `CPP_SW_BEST_K4H4_F64` | 23/500 | 500/500 |
| `CPP_SW_BEST_NORMAL_F32` | 23/500 | 500/500 |
| `CPP_SW_BEST_NORMAL_F32_T2` | 23/500 | 500/500 |
| `CPP_SW_BEST_NORMAL_F32_W2` | 23/500 | 500/500 |
| `CPP_SW_BEST_NORMAL_F64` | 23/500 | 500/500 |
| `CPP_SW_BEST_NORMAL_F64_T2` | 23/500 | 500/500 |
| `CPP_SW_BEST_NORMAL_F64_W2` | 23/500 | 500/500 |
| `NUMPY_ALLJ_F64` | 23/500 | 500/500 |
| `NUMPY_K3H3_F64` | 23/500 | 500/500 |
| `NUMPY_NORMAL_F64` | 23/500 | 500/500 |
| `QISKIT_AER_ALLJ_F64` | 0/10 | 10/10 |
| `QISKIT_AER_ALLJ_F64_T2` | 0/10 | 10/10 |
| `QISKIT_AER_K3H3_F64` | 0/10 | 10/10 |
| `QISKIT_AER_K3H3_F64_T2` | 0/10 | 10/10 |
| `QISKIT_AER_NORMAL_F64` | 0/10 | 10/10 |
| `QISKIT_AER_NORMAL_F64_T2` | 0/10 | 10/10 |

## Float vs fixed-point (FPGA) distributions

Float and Q1.22 state vectors sample different trajectories per seed, so distributions are compared
(two-sided; p > 0.05 = no detectable difference). Tests with p < 0.05: 0 of 10
(about 0.5 expected by chance).

| predicate | M | float success | FPGA success | trials median float / FPGA | Mann-Whitney p (trials) | KS p (L_BBHT) |
| --- | ---: | ---: | ---: | --- | ---: | ---: |
| EQ | 1 | 100/100 | 100/100 | 23.0 / 23.0 | 0.870 | 0.702 |
| EQ | 4 | 100/100 | 100/100 | 20.0 / 19.0 | 0.601 | 0.815 |
| EQ | 16 | 100/100 | 100/100 | 16.0 / 16.0 | 0.977 | 0.815 |
| EQ | 64 | 100/100 | 100/100 | 11.0 / 11.0 | 0.586 | 0.908 |
| EQ | 256 | 100/100 | 100/100 | 8.0 / 7.0 | 0.407 | 0.470 |
