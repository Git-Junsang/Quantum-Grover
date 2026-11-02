# predicate500 backend comparison

SW environment: Intel Xeon @ 2.80GHz (cloud dev VM), 2 threads; single-core runs pinned to core 1; REPS=1, Qiskit on 2 seeds (smoke run).
FPGA: Arty A7-100T, 2026-10-04 board Predicate500. K3/H3-E4-M2 and NORMAL (E4-M2) come from the same bitstream (burst_enable 1/0); NOCKPT = Normal-E4 build; DRAM = DDR3 all-j table. Board time = command-to-DONE (DMA load, CSR config and readback excluded).
SW: search_ns = whole BBHT search with the dataset loaded and the oracle mask built.
"is faster by" = backend total search time / FPGA total over the same workloads (>1: the FPGA is faster).

## Timing (totals over the same workloads)

| Backend | runs | search total (ms) | compute total (ms) | E2E total (ms) | FPGA K3H3_E4_M2 is faster by | FPGA NORMAL_E4_M2 is faster by |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `FPGA_K3H3_E4_M2` | 2000 | 221.0 | - | - | 1.00x | 0.46x |
| `CPP_SW_BEST_ALLJ_F32` | 2000 | 326.8 | 247.1 | 347.3 | 1.48x | 0.68x |
| `CPP_SW_BEST_ALLJ_F32_W2` | 2000 | 346.3 | 261.5 | 368.1 | 1.57x | 0.72x |
| `FPGA_NORMAL_E4_M2` | 2000 | 479.0 | - | - | 2.17x | 1.00x |
| `CPP_SW_BEST_K3H3_F32` | 2000 | 497.1 | 206.3 | 513.5 | 2.25x | 1.04x |
| `CPP_SW_BEST_K4H4_F32` | 2000 | 516.4 | 198.2 | 532.3 | 2.34x | 1.08x |
| `CPP_SW_BEST_ALLJ_F64` | 2000 | 538.7 | 445.6 | 561.6 | 2.44x | 1.12x |
| `CPP_RTL_EXACT_K3H3` | 2000 | 615.3 | 358.7 | 635.7 | 2.78x | 1.28x |
| `FPGA_NOCKPT_NORMAL_E4` | 2000 | 621.2 | - | - | 2.81x | 1.30x |
| `CPP_SW_BEST_ALLJ_F64_W2` | 2000 | 683.9 | 555.6 | 716.5 | 3.09x | 1.43x |
| `CPP_SW_BEST_K4H4_F64` | 2000 | 741.4 | 260.8 | 758.2 | 3.35x | 1.55x |
| `CPP_SW_BEST_K3H3_F64` | 2000 | 895.0 | 305.9 | 916.6 | 4.05x | 1.87x |
| `CPP_SW_BEST_NORMAL_F32` | 2000 | 908.3 | 718.3 | 932.0 | 4.11x | 1.90x |
| `CPP_SW_BEST_NORMAL_F32_W2` | 2000 | 1159.7 | 933.0 | 1182.9 | 5.25x | 2.42x |
| `CPP_RTL_EXACT_NORMAL_W2` | 2000 | 1223.7 | 1075.4 | 1242.5 | 5.54x | 2.55x |
| `CPP_SW_BEST_NORMAL_F64` | 2000 | 1337.0 | 1061.5 | 1359.2 | 6.05x | 2.79x |
| `CPP_SW_BEST_NORMAL_F64_W2` | 2000 | 1346.4 | 1034.6 | 1371.7 | 6.09x | 2.81x |
| `CPP_RTL_EXACT_NORMAL` | 2000 | 1417.0 | 1258.1 | 1438.2 | 6.41x | 2.96x |
| `CPP_SW_BEST_NORMAL_F32_T2` | 2000 | 2483.5 | 2203.1 | 2509.1 | 11.24x | 5.19x |
| `CPP_SW_BEST_NORMAL_F64_T2` | 2000 | 3288.5 | 2862.6 | 3313.7 | 14.88x | 6.87x |
| `NUMPY_ALLJ_F64` | 2000 | 3360.9 | 1514.1 | 3466.1 | 15.21x | 7.02x |
| `FPGA_DRAM_ALLJ_SESSION` | 2000 | 3459.0 | - | - | 15.65x | 7.22x |
| `NUMPY_NORMAL_F64` | 2000 | 4205.7 | 2799.9 | 4278.9 | 19.03x | 8.78x |
| `NUMPY_K3H3_F64` | 2000 | 4514.2 | 1136.6 | 4619.8 | 20.42x | 9.42x |
| `QISKIT_AER_ALLJ_F64_T2` | 40 | 11921.4 | 3063.8 | 16318.3 | 2673.56x | 1201.27x |
| `QISKIT_AER_K3H3_F64_T2` | 40 | 12425.0 | 3261.6 | 17263.3 | 2786.50x | 1252.01x |
| `QISKIT_AER_ALLJ_F64` | 40 | 13571.8 | 4669.4 | 18612.8 | 3043.69x | 1367.58x |
| `QISKIT_AER_K3H3_F64` | 40 | 14535.1 | 4928.2 | 19329.2 | 3259.73x | 1464.64x |
| `QISKIT_AER_NORMAL_F64_T2` | 40 | 39119.9 | 10895.0 | 46617.3 | 8773.25x | 3941.95x |
| `QISKIT_AER_NORMAL_F64` | 40 | 44897.9 | 16345.6 | 52741.8 | 10069.05x | 4524.18x |

## Throughput (multi-core, workloads in parallel)

| Backend | workers | searches per second | FPGA K3/H3 is faster by |
| --- | ---: | ---: | ---: |
| `FPGA_K3H3_E4_M2` | 1 engine | 9,048 | 1.00x |
| `CPP_RTL_EXACT_NORMAL_W2` (2000 workloads) | 2 | 3,197 | 2.83x |
| `CPP_SW_BEST_ALLJ_F32_W2` (2000 workloads) | 2 | 9,133 | 0.99x |
| `CPP_SW_BEST_ALLJ_F64_W2` (2000 workloads) | 2 | 4,189 | 2.16x |
| `CPP_SW_BEST_NORMAL_F32_W2` (2000 workloads) | 2 | 3,279 | 2.76x |
| `CPP_SW_BEST_NORMAL_F64_W2` (2000 workloads) | 2 | 2,961 | 3.06x |

## Equivalence

Trajectory = (result_index, trial_count, L_BBHT) per workload; FPGA reference = `FPGA_NORMAL_E4_M2`.

| Backend | = FPGA trajectory | = float trajectory (`NUMPY_NORMAL_F64`) |
| --- | ---: | ---: |
| `FPGA_NORMAL_E4_M2` | 2000/2000 | 96/2000 |
| `FPGA_K3H3_E4_M2` | 2000/2000 | 96/2000 |
| `FPGA_NOCKPT_NORMAL_E4` | 2000/2000 | 96/2000 |
| `FPGA_DRAM_ALLJ_SESSION` | 2000/2000 | 96/2000 |
| `CPP_RTL_EXACT_K3H3` | 2000/2000 | 96/2000 |
| `CPP_RTL_EXACT_NORMAL` | 2000/2000 | 96/2000 |
| `CPP_RTL_EXACT_NORMAL_W2` | 2000/2000 | 96/2000 |
| `CPP_SW_BEST_ALLJ_F32` | 96/2000 | 2000/2000 |
| `CPP_SW_BEST_ALLJ_F32_W2` | 96/2000 | 2000/2000 |
| `CPP_SW_BEST_ALLJ_F64` | 96/2000 | 2000/2000 |
| `CPP_SW_BEST_ALLJ_F64_W2` | 96/2000 | 2000/2000 |
| `CPP_SW_BEST_K3H3_F32` | 96/2000 | 2000/2000 |
| `CPP_SW_BEST_K3H3_F64` | 96/2000 | 2000/2000 |
| `CPP_SW_BEST_K4H4_F32` | 96/2000 | 2000/2000 |
| `CPP_SW_BEST_K4H4_F64` | 96/2000 | 2000/2000 |
| `CPP_SW_BEST_NORMAL_F32` | 96/2000 | 2000/2000 |
| `CPP_SW_BEST_NORMAL_F32_T2` | 96/2000 | 2000/2000 |
| `CPP_SW_BEST_NORMAL_F32_W2` | 96/2000 | 2000/2000 |
| `CPP_SW_BEST_NORMAL_F64` | 96/2000 | 2000/2000 |
| `CPP_SW_BEST_NORMAL_F64_T2` | 96/2000 | 2000/2000 |
| `CPP_SW_BEST_NORMAL_F64_W2` | 96/2000 | 2000/2000 |
| `NUMPY_ALLJ_F64` | 96/2000 | 2000/2000 |
| `NUMPY_K3H3_F64` | 96/2000 | 2000/2000 |
| `NUMPY_NORMAL_F64` | 96/2000 | 2000/2000 |
| `QISKIT_AER_ALLJ_F64` | 3/40 | 40/40 |
| `QISKIT_AER_ALLJ_F64_T2` | 3/40 | 40/40 |
| `QISKIT_AER_K3H3_F64` | 3/40 | 40/40 |
| `QISKIT_AER_K3H3_F64_T2` | 3/40 | 40/40 |
| `QISKIT_AER_NORMAL_F64` | 3/40 | 40/40 |
| `QISKIT_AER_NORMAL_F64_T2` | 3/40 | 40/40 |

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
