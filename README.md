# Multi-Predicate Grover Search Accelerator

**English** | [한국어](README.ko.md)

FPGA SoC that emulates a 15-qubit Grover search over an on-chip data array, resolving four predicates — `<`, `>`, `=`, `a < x < b` — on a single Spartan-7.

Chung-Ang University undergraduate internship project · 2026

* * *

## 1. Background

Grover's algorithm finds an item satisfying a predicate among `N` unsorted items in `O(√N)` oracle queries. That speedup belongs to **real quantum hardware**. Emulating the state vector on classical logic means touching all `N` amplitudes on every iteration, so the emulator costs `O(N·√(N/M))` — slower than a classical linear scan.

The value of this accelerator is therefore not raw speed. It is a **dedicated engine that reproduces and verifies the behaviour of a quantum algorithm deterministically and repeatably**. The baseline for comparison is a software state-vector simulator (Qiskit AerSimulator, NumPy), never a classical scan.

Most published Grover FPGA emulators hard-code the solution index as a parameter, or assume a single solution. This project drops both assumptions. The oracle compares **data values** rather than indices, and when several items satisfy the predicate the accelerator enumerates all of them without duplicates.

* * *

## 2. System Overview

| Component | Role |
|---|---|
| Host PC | Sends predicate and thresholds over UART, receives result indices |
| RVX SoC (`rvc_orca` RV32) | Predicate/threshold policy, UART parsing, enumeration round termination, data staging. In firmware-driven mode it also writes an absolute `j_target` per shot |
| **Grover IP** (hand-designed) | Amplitude init · oracle · diffusion · Born measurement · classical verify · resume-cache decision. In autonomous mode it also runs the BBHT shot loop |
| APB slave | Control and status registers |
| AHB master | DMA of the search data array |

The shot loop has **two coexisting modes**. In **BBHT autonomous mode** the outer FSM in hardware updates `m`, draws `j_target` from an LFSR and decides cache validity; firmware sees only configure → `start` → poll → read result. In **firmware-driven mode** the application writes an absolute `j_target` each shot. Either way `j_cur` and `cache_valid` are owned by hardware, so the cache state never exists in two places.

| Item | Value |
|---|---|
| Target FPGA | Arty-S7-50 (`xc7s50csga324-1`) |
| Target qubits | n = 15 (N = 32,768) |
| Amplitude format | real-only fixed point, 18-bit Q2.16, round-half-to-even, saturating |
| Data word | 16-bit signed |
| Parallelism | P = 32 lanes (bank select from the low 5 index bits) |
| One iteration | 2 passes = 2N/P = 2,048 cycles |
| Target clock | 100 MHz (RVX generates `SYSTEM_CLK_HZ = 50 MHz` by default — to be confirmed in Phase 0) |
| One search | approx. 3.7 ms (n=15, M=1, cache enabled) |

* * *

## 3. Algorithm & Hardware Architecture

### 3.1 Algorithm — BBHT with a predicate oracle

The number of solutions `M` depends on the predicate, the threshold and the data, so it cannot be known in advance. Counting it with quantum phase estimation would force complex amplitudes and break the real-only datapath, so the design uses **BBHT** instead.

```
m ← 1,  λ ← 6/5
repeat:
    j ~ U[0, m)                      # uniform draw
    run j Grover iterations          # the resume cache acts here
    measure by Born sampling
    classical verify — re-read one word of data_mem and re-test the predicate
    on failure:  m ← min(1.2·m, √N)
```

Because `m` grows slowly from 1, the early shots almost always fail. At n=15, M=1 the mean is **24.5 shots** (Monte Carlo, 20,000 runs).

**Resume cache — the core contribution.** Only three operations write the amplitude array: init, oracle and diffusion. Born measurement only **reads** it and the classical verify touches a single data word. A failed shot therefore leaves the state after `j_prev` iterations intact.

```
if (!cache_valid || force_init || j_target < j_cur)   init, then run j_target iterations
else                                                   run only (j_target − j_cur) more
```

The resumed path executes literally the same operation sequence as a fresh init followed by `j` iterations, so results are bit-identical. It costs **zero additional BRAM** — only the `j_cur` and `cache_valid` registers — and combined with parallel measurement it saves about **35 %** (n=15, M=1, Monte Carlo 20,000 runs; the saving falls to 29 % at M=256).

| Predicate | `mode` | Decision |
|---|:-:|---|
| `value < thr_a` | 0 | MSB of `value − thr_a` |
| `value > thr_a` | 1 | same MSB with operands swapped |
| `value == thr_a` | 2 | XOR-NOR |
| `thr_a < value < thr_b` | 3 | AND of two comparisons |

No comparator IP is instantiated; the sign bit of a single subtractor is the answer. Enumeration mode ANDs in `!found[i]` to exclude solutions already reported.

### 3.2 Hardware Architecture — RTL

One iteration splits into two passes because diffusion needs the mean of the whole array and therefore cannot share a pass with the oracle.

| State | Cycles | Work |
|---|--:|---|
| `S_INIT` | 1,024 | write `INIT_AMP` (362 at n=15) to every cell |
| `S_PASS1` | 1,024 | predicate → sign flip → write back, accumulating in the same cycle |
| `S_MEAN` | 1 | arithmetic right shift of the accumulator by `n−1` → `two_mean` |
| `S_PASS2` | 1,024 | replace each cell with `two_mean − amp` |

**Diffusion contains no multiplier.** What diffusion needs is twice the mean, so the accumulator is shifted right by `n−1` in a single step — never `>>> n` followed by `<<< 1`, which would discard the least significant bit and put rounding in two places. The rest is subtraction. The only DSPs in the design are the 32 squarers in the measurement path.

**Measurement is Born sampling, not argmax.** The oracle and diffusion treat the solution set with perfect symmetry, so the `M` solution amplitudes stay **exactly equal** at every iteration. A largest-amplitude circuit would return the same index forever, making enumeration impossible. A two-stage parallel sampler completes in 2,080 cycles instead of 32,768.

| Resource | Configuration | BRAM36 | DSP |
|---|---|--:|--:|
| `amp_mem` | 32 banks × 1024 × 18b | 16 | 0 |
| `data_mem` | 32 banks × 1024 × 16b | 16 | 0 |
| `mask_mem` | 1024 × 32b | 1 | 0 |
| Lanes × 32 | comparator, sign flip, diffusion | 0 | **0** |
| `born_sampler` | 32 squarers | 0 | 32 |
| **IP total** | | **33 / 75** | **32 / 120** |

* * *

## 4. Directory Structure

```
├── hardware/
│   ├── src/                   # RTL (Verilog) + grover_param.vh
│   ├── testbench/             # testbenches, entry point of the iverilog regression
│   └── sim/                   # verilator harness
├── software/
│   ├── golden/                # float64 reference, bit-accurate fixed-point model, test vectors
│   ├── soc/                   # RVX platform, RISC-V app, driver
│   ├── host/                  # grover_cli.py (UART client)
│   ├── bench/                 # benchmark sweeps
│   └── tools/                 # deploy.sh
└── documents/
    ├── study_references/      # primary textbook — chapters 0-18 + appendix A
    ├── design/                # 개발계획.md (current plan) + 2026-07 records (see banner)
    ├── presentation/          # slide decks, named YYYY-MM-DD_<kind>_<topic>
    ├── papers/                # source papers (read-only)
    ├── papers_ko/             # Korean paper commentaries (auxiliary)
    └── check_docs.py          # documentation consistency checker
```

`hardware/src/` and `hardware/testbench/` now hold the 21 RTL modules and the iverilog regression; `hardware/sim/` and `software/` are still empty — see Development Status below.

* * *

## 5. Getting Started

### 5.1 Golden model (Python)

```bash
cd software/golden
python3 run_all.py            # float64 reference → bit-accurate fixed-point model → RTL test vectors
```

### 5.2 RTL simulation (local)

```bash
make -C hardware/testbench regress     # iverilog + vvp, compared bit-for-bit against the golden vectors
```

Locally available tools are `iverilog`, `vvp`, `verilator` and `gtkwave`.

### 5.3 SoC integration and synthesis (RVX, remote)

```bash
source /home/coder/rvx_lec_hw/rvx_setup.sh
cd $RVX_MINI_HOME/platform/grover_soc
make syn && make sim_rtl                       # remote ModelSim
make imp_fpga TARGET_IMP_CLASS=arty-50         # remote Vivado → bitstream
```

This is the RVX Mini (thin client) edition, so generation, simulation and synthesis all run on a remote server. `vivado`, `vsim` and `riscv-gcc` are **not** installed locally.

### 5.4 Documentation checks

```bash
python3 documents/check_docs.py        # must report 0 errors
```

### 5.5 Run on hardware (host PC UART client)

```bash
python3 software/host/grover_cli.py --mode 2 --thr 42     # index where value == 42
```

* * *

## 6. Development Status

**Current state — Documentation complete. RTL first pass written and passing local iverilog regression; Phase 0 (toolchain bring-up) not started.**

No physical board yet. Through Phase 6 the acceptance criteria are remote ModelSim simulation and Vivado implementation reports; board execution happens in Phase 7 once hardware arrives. Full task detail and acceptance criteria live in [개발계획.md](documents/design/개발계획.md).

**Phase 0 — Toolchain and repository skeleton**
- [ ] Create `software/{golden,soc,host,bench,tools}`
- [ ] Clone the RVX platform from `lec_ahb` (AHB master + APB slave, the pattern this design follows)
- [ ] Decide how the repository maps onto the RVX workspace (symlink, else tar deploy)
- [ ] hello world on the virtual platform, then on remote RTL simulation
- [ ] `make imp_fpga TARGET_IMP_CLASS=arty-50` and capture the utilization report as the resource baseline
- [ ] Confirm the UART **receive** path (`uart_getc`) — the host command channel
- [ ] Compile an empty `grover_top` stub with `iverilog -g2012`

**Phase 1 — Golden model and numeric spec** *(most important)*
- [ ] `grover_float.py` — float64 reference: four predicates, BBHT loop, Born sampling
- [ ] `grover_fixed.py` — bit-accurate fixed-point model matching the RTL one-to-one
- [ ] Bit-width sweep: f = 8..24 × n ∈ {10,12,14,15} × M ∈ {1,4,64} → success-rate curves
- [ ] Q-format sweep: {Q1.17, Q2.16} × {half-up, half-even} → saturation counts
- [ ] Cache sweep: naive vs forward-only resume, serial vs parallel measurement
- [ ] Generate RTL test vectors for n = 8, 10, 12
- [ ] Measure the NumPy / Qiskit AerSimulator baseline
- [ ] Decide the M = 0 termination rule

**Phase 2 — SoC shell: end-to-end path with a dummy IP**
- [ ] Generate the CSR register file with the RVX mmio generator
- [ ] Wire the APB slave in `grover_soc_user_region.vh`
- [ ] RVX wrapper — `grover_top.v` must not include `ervp_*.vh`, so it stays iverilog-simulable
- [ ] Dummy `grover_top`: assert `done` K cycles after `start`
- [ ] Driver `grover_api.{c,h}` and app `grover_search/src/main.c` (ASCII line protocol)
- [ ] Host `grover_cli.py`

**Phase 3 — Datapath core (P = 1, n ≤ 12), bit-exact against the golden model**
- [ ] `grover_param.vh` — NB, DW, QF, W, P, ACCW, INIT_AMP
- [ ] `grover_predicate.v` — four predicates sharing one subtractor
- [ ] `grover_lane.v` — sign flip + diffusion (`two_mean − amp`, saturating)
- [ ] `grover_two_mean_calc.v` — single `n−1` shift with round-half-to-even
- [ ] `grover_adder_tree.v`, `grover_sum_accum.v`, `grover_ctrl_fsm.v`
- [ ] `grover_amp_mem.v`, `grover_data_mem.v`, `grover_data_gen.v` (xorshift), `grover_verify.v`

**Phase 4 — Parallelism P = 32 and measurement**
- [ ] Banking on the low `log₂P` index bits
- [ ] 32-input 5-level adder tree
- [ ] `grover_born_sampler.v` — two-stage parallel sampler, 32 squarers, rejection sampling
- [ ] `grover_lfsr.v`, `grover_iter_rom.v` (30 entries), `cycle_cnt` / `passes_run` counters

**Phase 5 — Resume cache and BBHT shot loop** *(the headline requirement)*
- [ ] 5a: firmware-driven mode — app writes absolute `j_target` per shot
- [ ] 5a: `grover_cache_ctrl.v` and hardware auto-invalidation on predicate/threshold/mask writes
- [ ] 5a: prove bit-identity — resumed path vs fresh init, full array comparison
- [ ] 5b: `grover_shot_fsm.v` — outer FSM with `m` register, LFSR draw, `S_VERIFY`
- [ ] 5b: `ctrl.auto_shot` selects between the two modes

**Phase 6 — AHB master data loading and enumeration**
- [ ] `grover_ahb_master.v` — burst master modelled on `lec_simd.v`
- [ ] `grover_mask_mem.v`, `grover_result_fifo.v`
- [ ] Enumeration round loop with `M_max` and `TOO_MANY`

**Phase 7 — Implementation, evaluation, documentation**
- [ ] Staged implementation: n=12/P=8 → n=12/P=32 → **n=15/P=32** on arty-50
- [ ] Close timing at 100 MHz
- [ ] Benchmarks: cache on/off, serial vs parallel measurement, BBHT vs known-M, NumPy/Qiskit comparison
- [ ] n=16 implementation report on arty-100t
- [ ] Board bring-up once hardware arrives

**Open questions** (nine; sources are [16.9](documents/study_references/16_반복제어와_재개캐시.md#169-아직-정하지-않은-것) and [17.8](documents/study_references/17_RVX_SoC_통합.md#178-아직-정하지-않은-것)): M = 0 termination · uniformity of `j ~ U[0,m)` (LFSR masking is not uniform) · random-number consumption protocol · hardware arithmetic for `m ← min(1.2m, √N)` · CSR map is a draft · enumeration result return path · `M_max` value · actual RVX SoC resource usage · whether 100 MHz is achievable.

* * *

## 7. Extras

### Documents

**[Study references (documents/study_references/)](documents/study_references/README.md)** — chapters 0 to 18, from quantum computing fundamentals to the design decisions behind this accelerator, written for a reader new to quantum algorithms.

| Part | Chapters | Content |
|---|---|---|
| Theory | 0-10 | qubits · gates · measurement · entanglement · oracles · Grover |
| Skeleton | 11-12 | memory map and resource budget · fixed point Q2.16 |
| Datapath | 13-14 | oracle and diffusion · Born measurement and enumeration |
| Design coordinates | 15 | paper map · **confirmed decision table (single source for every number)** |
| Outside the shot | 16-18 | BBHT and the resume cache · RVX SoC integration · golden model verification |

### Design notes

[개발계획.md](documents/design/개발계획.md) (2026-08-15) is the current source of truth for development order and acceptance criteria. `블록도.md` and `반복횟수_결정.md` are 2026-07 records and carry a banner pointing to the current spec. Slide decks are in [documents/presentation/](documents/presentation/README.md).

* * *

## 8. References

- Grover, L. K. (1996). *A fast quantum mechanical algorithm for database search.* STOC.
- Boyer, M., Brassard, G., Høyer, P., Tapp, A. (1998). *Tight bounds on quantum searching.* Fortschritte der Physik 46(4-5). — origin of the BBHT schedule
- Choi, S., Lee, W. (2024). *Developing a Grover's quantum algorithm emulator on standalone FPGAs.* AIMS Mathematics 9(11).
- Choi, S. et al. (2026). *Precision-aware fixed-point emulation of Grover's algorithm.* Quantum Information Processing 25:214.
- Byrnes, T., Forster, G., Tessler, L. (2018). *Generalized Grover's algorithm for multiple phase inversion states.* PRL 120:060501.
- El-Araby, E. et al. (2023). *Towards complete and scalable emulation of quantum algorithms on high-performance reconfigurable computers.* IEEE Trans. Computers 72(8).
- Han, K. et al. *RVX (RISC-V eXpress)* — ETRI SoC Design Research Group.

The full list, and the errata that matter when citing these papers, are in [chapter 15](documents/study_references/15_논문지도와_설계결정표.md).
