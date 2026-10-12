# common500 backend comparison

SW environment: Intel(R) Core(TM) i5-14600K, 8 physical cores / 8 logical CPUs; single-core runs pinned to CPU 13 (max 4000.0000 MHz).
FPGA: Arty A7-100T, 2026-09-08 board 500-run (EQ). Standard ref = Normal-E1 (different bitstream from K3/H3-E4-M2). Board time = command-to-DONE (DMA load, CSR config and readback excluded).
SW: search_ns = whole BBHT search with the dataset loaded and the oracle mask built.
SW suffixes: `_T<n>` = one search split over n cores (latency mode); `_W<n>` = n searches in parallel (throughput).
`CPP_SW_BEST_K3H3_*_T4` / `CPP_RTL_EXACT_K3H3_T4` = SW counterpart of K3/H3-E4-M2 (K3H3 policy, 4 cores per iteration, hierarchical sampler).
"is faster by" = backend total search time / FPGA total over the same workloads (>1: the FPGA is faster).

## Timing (totals over the same workloads)

| Backend | runs | search total (ms) | compute total (ms) | E2E total (ms) | FPGA K3H3_E4_M2 is faster by | FPGA NORMAL_E1 is faster by |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `CPP_SW_BEST_ALLJ_F32` | 500 | 55.5 | 39.6 | 86.4 | 1.00x | 0.13x |
| `FPGA_K3H3_E4_M2` | 500 | 55.8 | - | - | 1.00x | 0.13x |
| `CPP_SW_BEST_ALLJ_F64` | 500 | 67.3 | 54.3 | 101.3 | 1.21x | 0.16x |
| `CPP_SW_BEST_ALLJ_F32_W8` | 500 | 76.0 | 58.5 | 106.6 | 1.36x | 0.18x |
| `CPP_SW_BEST_K3H3_F32_T4` | 500 | 76.7 | 18.4 | 109.2 | 1.37x | 0.18x |
| `CPP_SW_BEST_NORMAL_F32_T8` | 500 | 83.6 | 41.6 | 117.0 | 1.50x | 0.20x |
| `CPP_RTL_EXACT_K3H3_T4` | 500 | 84.0 | 24.0 | 117.2 | 1.51x | 0.20x |
| `CPP_RTL_EXACT_ALLJ` | 500 | 85.5 | 70.2 | 117.5 | 1.53x | 0.20x |
| `CPP_SW_BEST_K4H4_F32` | 500 | 97.6 | 41.9 | 129.8 | 1.75x | 0.23x |
| `CPP_SW_BEST_K3H3_F32` | 500 | 99.8 | 43.9 | 133.6 | 1.79x | 0.23x |
| `CPP_SW_BEST_NORMAL_F32_T4` | 500 | 102.4 | 61.8 | 131.2 | 1.84x | 0.24x |
| `CPP_RTL_EXACT_NORMAL_T4` | 500 | 117.7 | 76.6 | 132.8 | 2.11x | 0.28x |
| `CPP_SW_BEST_NORMAL_F32_T2` | 500 | 121.4 | 81.0 | 151.5 | 2.18x | 0.29x |
| `CPP_SW_BEST_K4H4_F64` | 500 | 123.9 | 56.0 | 156.8 | 2.22x | 0.29x |
| `CPP_SW_BEST_K3H3_F64_T4` | 500 | 127.2 | 33.4 | 159.3 | 2.28x | 0.30x |
| `CPP_SW_BEST_NORMAL_F64_T8` | 500 | 127.9 | 71.3 | 156.8 | 2.29x | 0.30x |
| `CPP_RTL_EXACT_K3H3` | 500 | 132.0 | 77.4 | 148.1 | 2.37x | 0.31x |
| `CPP_SW_BEST_K3H3_F64` | 500 | 156.7 | 58.3 | 185.3 | 2.81x | 0.37x |
| `CPP_SW_BEST_NORMAL_F64_T2` | 500 | 163.5 | 116.3 | 187.6 | 2.93x | 0.38x |
| `FPGA_K4H4_E1` | 500 | 164.9 | - | - | 2.96x | 0.39x |
| `CPP_SW_BEST_NORMAL_F64_T4` | 500 | 165.0 | 113.9 | 201.2 | 2.96x | 0.39x |
| `CPP_SW_BEST_ALLJ_F64_W8` | 500 | 172.7 | 150.2 | 202.4 | 3.09x | 0.41x |
| `CPP_SW_BEST_NORMAL_F32` | 500 | 186.7 | 145.9 | 219.3 | 3.35x | 0.44x |
| `CPP_SW_BEST_NORMAL_F64` | 500 | 241.9 | 196.1 | 266.9 | 4.34x | 0.57x |
| `CPP_SW_BEST_NORMAL_F32_W8` | 500 | 260.7 | 207.2 | 295.6 | 4.67x | 0.61x |
| `CPP_RTL_EXACT_NORMAL` | 500 | 292.6 | 253.6 | 324.2 | 5.24x | 0.69x |
| `CPP_RTL_EXACT_NORMAL_W8` | 500 | 307.2 | 260.1 | 341.7 | 5.50x | 0.72x |
| `NUMPY_ALLJ_F64` | 500 | 417.4 | 158.7 | 458.6 | 7.48x | 0.98x |
| `FPGA_NORMAL_E1` | 500 | 425.5 | - | - | 7.63x | 1.00x |
| `CPP_SW_BEST_NORMAL_F64_W8` | 500 | 505.3 | 410.7 | 536.0 | 9.06x | 1.19x |
| `NUMPY_K3H3_F64` | 500 | 564.2 | 173.5 | 607.9 | 10.11x | 1.33x |
| `NUMPY_ALLJ_F64_W8` | 500 | 579.7 | 284.7 | 618.4 | 10.39x | 1.36x |
| `NUMPY_K3H3_F64_W8` | 500 | 719.2 | 253.0 | 759.7 | 12.89x | 1.69x |
| `NUMPY_NORMAL_F64` | 500 | 734.8 | 527.4 | 772.6 | 13.17x | 1.73x |
| `NUMPY_NORMAL_F64_W8` | 500 | 1192.4 | 944.0 | 1230.5 | 21.37x | 2.80x |
| `GOLDEN_PY_K3H3` | 500 | 2497.8 | 1126.5 | 5848.3 | 44.77x | 5.87x |
| `GOLDEN_PY_K3H3_W8` | 500 | 3621.9 | 1819.2 | 7266.9 | 64.91x | 8.51x |
| `GOLDEN_PY_ALLJ` | 500 | 3635.4 | 2408.3 | 6971.2 | 65.15x | 8.54x |
| `GOLDEN_PY_NORMAL` | 500 | 4427.4 | 3358.8 | 7780.8 | 79.35x | 10.41x |
| `GOLDEN_PY_ALLJ_W8` | 500 | 4490.6 | 3008.0 | 8114.3 | 80.48x | 10.55x |
| `GOLDEN_PY_NORMAL_W8` | 500 | 5896.4 | 4589.7 | 9533.5 | 105.67x | 13.86x |
| `QISKIT_AER_ALLJ_F64_T8` | 100 | 15054.4 | 3818.5 | 16505.4 | 1342.23x | 175.01x |
| `QISKIT_AER_ALLJ_F64` | 100 | 16699.3 | 5541.8 | 18136.0 | 1488.89x | 194.13x |
| `QISKIT_AER_K3H3_F64_T8` | 100 | 16777.0 | 3860.4 | 18632.6 | 1495.81x | 195.03x |
| `QISKIT_AER_K3H3_F64` | 100 | 19066.4 | 6234.5 | 20947.5 | 1699.92x | 221.65x |
| `QISKIT_AER_NORMAL_F64_T8` | 100 | 51482.3 | 12525.5 | 54874.9 | 4590.08x | 598.49x |
| `QISKIT_AER_NORMAL_F64` | 100 | 59562.0 | 20392.3 | 62897.7 | 5310.45x | 692.41x |

## Throughput (multi-core, workloads in parallel)

| Backend | workers | searches per second | FPGA K3/H3 is faster by |
| --- | ---: | ---: | ---: |
| `FPGA_K3H3_E4_M2` | 1 engine | 8,961 | 1.00x |
| `CPP_RTL_EXACT_NORMAL_W8` (500 workloads) | 8 | 11,568 | 0.77x |
| `CPP_SW_BEST_ALLJ_F32_W8` (500 workloads) | 8 | 43,129 | 0.21x |
| `CPP_SW_BEST_ALLJ_F64_W8` (500 workloads) | 8 | 18,495 | 0.48x |
| `CPP_SW_BEST_NORMAL_F32_W8` (500 workloads) | 8 | 14,366 | 0.62x |
| `CPP_SW_BEST_NORMAL_F64_W8` (500 workloads) | 8 | 7,551 | 1.19x |
| `GOLDEN_PY_ALLJ_W8` (500 workloads) | 8 | 746 | 12.02x |
| `GOLDEN_PY_K3H3_W8` (500 workloads) | 8 | 844 | 10.61x |
| `GOLDEN_PY_NORMAL_W8` (500 workloads) | 8 | 583 | 15.38x |
| `NUMPY_ALLJ_F64_W8` (500 workloads) | 8 | 5,940 | 1.51x |
| `NUMPY_K3H3_F64_W8` (500 workloads) | 8 | 4,326 | 2.07x |
| `NUMPY_NORMAL_F64_W8` (500 workloads) | 8 | 3,137 | 2.86x |

## Equivalence

Trajectory = (result_index, trial_count, L_BBHT) per workload; FPGA reference = `FPGA_NORMAL_E1`.

| Backend | = FPGA trajectory | = float trajectory (`NUMPY_NORMAL_F64`) |
| --- | ---: | ---: |
| `FPGA_NORMAL_E1` | 500/500 | 23/500 |
| `FPGA_K4H4_E1` | 500/500 | 23/500 |
| `FPGA_K3H3_E4_M2` | 500/500 | 23/500 |
| `CPP_RTL_EXACT_ALLJ` | 500/500 | 23/500 |
| `CPP_RTL_EXACT_K3H3` | 500/500 | 23/500 |
| `CPP_RTL_EXACT_K3H3_T4` | 500/500 | 23/500 |
| `CPP_RTL_EXACT_NORMAL` | 500/500 | 23/500 |
| `CPP_RTL_EXACT_NORMAL_T4` | 500/500 | 23/500 |
| `CPP_RTL_EXACT_NORMAL_W8` | 500/500 | 23/500 |
| `CPP_SW_BEST_ALLJ_F32` | 23/500 | 500/500 |
| `CPP_SW_BEST_ALLJ_F32_W8` | 23/500 | 500/500 |
| `CPP_SW_BEST_ALLJ_F64` | 23/500 | 500/500 |
| `CPP_SW_BEST_ALLJ_F64_W8` | 23/500 | 500/500 |
| `CPP_SW_BEST_K3H3_F32` | 23/500 | 500/500 |
| `CPP_SW_BEST_K3H3_F32_T4` | 23/500 | 500/500 |
| `CPP_SW_BEST_K3H3_F64` | 23/500 | 500/500 |
| `CPP_SW_BEST_K3H3_F64_T4` | 23/500 | 500/500 |
| `CPP_SW_BEST_K4H4_F32` | 23/500 | 500/500 |
| `CPP_SW_BEST_K4H4_F64` | 23/500 | 500/500 |
| `CPP_SW_BEST_NORMAL_F32` | 23/500 | 500/500 |
| `CPP_SW_BEST_NORMAL_F32_T2` | 23/500 | 500/500 |
| `CPP_SW_BEST_NORMAL_F32_T4` | 23/500 | 500/500 |
| `CPP_SW_BEST_NORMAL_F32_T8` | 23/500 | 500/500 |
| `CPP_SW_BEST_NORMAL_F32_W8` | 23/500 | 500/500 |
| `CPP_SW_BEST_NORMAL_F64` | 23/500 | 500/500 |
| `CPP_SW_BEST_NORMAL_F64_T2` | 23/500 | 500/500 |
| `CPP_SW_BEST_NORMAL_F64_T4` | 23/500 | 500/500 |
| `CPP_SW_BEST_NORMAL_F64_T8` | 23/500 | 500/500 |
| `CPP_SW_BEST_NORMAL_F64_W8` | 23/500 | 500/500 |
| `GOLDEN_PY_ALLJ` | 500/500 | 23/500 |
| `GOLDEN_PY_ALLJ_W8` | 500/500 | 23/500 |
| `GOLDEN_PY_K3H3` | 500/500 | 23/500 |
| `GOLDEN_PY_K3H3_W8` | 500/500 | 23/500 |
| `GOLDEN_PY_NORMAL` | 500/500 | 23/500 |
| `GOLDEN_PY_NORMAL_W8` | 500/500 | 23/500 |
| `NUMPY_ALLJ_F64` | 23/500 | 500/500 |
| `NUMPY_ALLJ_F64_W8` | 23/500 | 500/500 |
| `NUMPY_K3H3_F64` | 23/500 | 500/500 |
| `NUMPY_K3H3_F64_W8` | 23/500 | 500/500 |
| `NUMPY_NORMAL_F64` | 23/500 | 500/500 |
| `NUMPY_NORMAL_F64_W8` | 23/500 | 500/500 |
| `QISKIT_AER_ALLJ_F64` | 5/100 | 100/100 |
| `QISKIT_AER_ALLJ_F64_T8` | 5/100 | 100/100 |
| `QISKIT_AER_K3H3_F64` | 5/100 | 100/100 |
| `QISKIT_AER_K3H3_F64_T8` | 5/100 | 100/100 |
| `QISKIT_AER_NORMAL_F64` | 5/100 | 100/100 |
| `QISKIT_AER_NORMAL_F64_T8` | 5/100 | 100/100 |

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
