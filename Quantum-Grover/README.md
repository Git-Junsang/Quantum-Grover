# Multi-Predicate Grover Search Accelerator

An FPGA emulator accelerator that uses Grover's algorithm to find indices in an
on-chip data array satisfying one of four predicates: `<`, `>`, `=`, and range
(`a < x < b`). The host sends the predicate and thresholds over UART; the accelerator inside an RVX SoC computes and returns the result index.

- Board: Arty A7-100T (`xc7a100tcsg324-1`)
- Board-Verified Build: the **final configuration** (built 2026-09-07, benchmarked 2026-09-08). What was verified on the board wins.

Korean documentation is the primary source — see [README.ko.md](README.ko.md).

---

## 1. Status

| Item | State |
|---|---|
| Accelerator Core algorithm (14 qubits / 32 lanes / 16-bit data) | Final configuration, board sign-off complete |
| Bus Interface (CSR, DMA, FIFO, driver, UART console) | Our Bus Interface is confirmed on the board: command round trip on 2026-09-17, and on 2026-10-04 all four predicates × 500 workloads × two modes (4,000 runs, with wall-clock time) match the reference model 4,000/4,000 |
| 100 MHz implementation | Timing closed (WNS +0.126 ns); reports under `hardware_bram/configurations/final/vivado/` |
| **Accelerator Core RTL source** | `hardware_bram/src/`, one current directory tree. The sha256-identical board source is tag `board-verified-build-2026-09-07` (where the folder was still named `hardware_bram/`) |
| Performance evidence | Board wall-clock time **7.626×**, RTL cycles **6.1401×**, **116,426×** over a single ORCA core |
| Software reference models | NumPy, Qiskit Aer, Q1.22 bit-exact, and the policy model for a Checkpoint-Capacity of 3 and 3-shot Lookahead. On the same 500 workloads as the board, BBHT trajectories and executed iterations match 500/500 |

Wiring correctness is enforced by a
[port contract check](spec/check_ports.py) that diffs the handoff
document's port tables (19 wrapper + 61 core signals) against the RTL across three
variants (`stub`, `real`, `dram`). All three match.

---

## 2. Frozen numbers

The single source of truth for the CSR map is
[`spec/bbht_grover_csr.json`](spec/bbht_grover_csr.json).
`gen_csr.py` generates the Verilog, C, and Python headers plus
[chapter 13 of the technical docs](documents/design_references/13_csr_registers_and_execution_modes.md) from it. Two
other places hold the same numbers but are not generated (the software reference model,
which also carries policy names, and the board bench app, whose ELF hash is frozen);
`gen_csr.py --check` reads and cross-checks both.

| Item | Value |
|---|---|
| number of qubits | 14 qubits (16,384 states) |
| Data word | 16-bit signed |
| Amplitude | 23-bit, Q1.22 family |
| number of lanes | 32 lanes |
| Predicates | `LT`, `GT`, `EQ`, `RANGE` |
| Run modes | `MANUAL_SINGLE`, `RESTART_SINGLE`, `CHECKPOINT_SINGLE`, `RESTART_ENUMERATION`, `CHECKPOINT_ENUMERATION` (Checkpoint-Capacity and Lookahead-Shots are build constants, not CSR fields) |
| CSR | APB slave, base `0xE2020000`, 4-byte stride, 32-bit, 38 registers |
| Data load | AHB master, SINGLE, single outstanding. SRAM `0xE0000000`–`0xE001FFFF` |
| Result FIFO | Depth 256 |
| Clocks | Accelerator 100 MHz / system 50 MHz |
| Final configuration | a Checkpoint-Capacity of 3, 3-shot Lookahead, 4 PEs, Dual-Row Build · Two-Level Select |

### Performance — do not mix the axes

| Axis | Value | Evidence |
|---|---|---|
| Board wall-clock time | Restart mode 425,502 µs → **55,798 µs** (7.626×) | `hardware_bram/configurations/final/vivado/vivado_bbht_grover_fpga/2026-09-08_k3h3_e4_m2_board_500run/` |
| RTL cycles (Six-Stage Ablation) | Stage 1 42,308,335 → **6,890,470** (6.1401×) | `hardware_bram/results/2026-09-08_publication_6stage/` |
| Versus software | **116,426×** over one ORCA core | `hardware_bram/configurations/final/vivado/vivado_bbht_grover_fpga/2026-09-08_orca_1core_baseline/` |

All three use the same 500 workloads (1, 4, 16, 64 or 256 solutions × 100 seeds). Board and RTL agree
on the BBHT trajectory 500/500, but the cycle counts themselves differ, so never build a
ratio that mixes the two axes.

On 2026-10-11 a new software baseline (`software/orca_grover_develop/`) was benchmarked on the ORCA core of the 200T
board and on one x86 core of a server, over the four-predicate 2,000 workloads, and compared mode for mode
with the FPGA on the same board. ORCA is 15,889–19,861× slower than the FPGA in wall-clock time, but one
server core finishes in 1.15–1.34× the FPGA time. Board, workloads, and baseline differ from the table above,
so do not mix them ([experiment 19](documents/reports/19_orca_server_software_baseline.md), Korean).

---

## 3. Two competing variants and the BRAM configurations

The design forks on how amplitudes are reused after a failed shot.
**Neither is final; one will be chosen later.** There are two hardware directory trees,
`hardware_bram/` and `hardware_dram/`. On 2026-10-06 the former
`hardware_bram_checkpoint/` and `no_checkpoint_baseline/` were merged into
`hardware_bram/`, with one folder per configuration. Inside tags
(`board-verified-build-2026-09-07` and others) the folder still has its name of that time, `hardware_bram/`.

### `hardware_bram/` — BRAM Variant: shared sources plus ten configurations

BRAM only. Amplitudes from a failed shot are not discarded; computation resumes from a
checkpoint and advances only by the difference (Checkpoint-Capacity, Lookahead-Shots). Inside one
Grover iteration, several 32-lane PEs split the 512 rows (number of PEs). The silicon-proven design belongs
to this variant.

Checkpoint-Capacity, Lookahead-Shots, number of PEs, and the Measurement Microarchitecture
(Dual-Row Build, Two-Level Select) are all compile-time parameters of the Accelerator Core, so **every configuration compiles the same
RTL with different parameters**. The Bus Interface, Accelerator Core, testbenches, firmware,
simulation, and synthesis live once directly under `hardware_bram/`. Only what differs per
configuration -- one adapter that sets the parameter defaults, the RVX platform definition, and that
configuration's implementation reports, board benchmarks, and bitstreams -- lives in
`hardware_bram/configurations/<model>/`. The ten configurations are the combinations tried so far.

| Folder | Checkpoint-Capacity / Lookahead-Shots | number of PEs | Measurement Microarchitecture | Origin | Hardware |
|---|---|---|---|---|---|
| `final` | 3/3 | 4 | Dual-Row Build · Two-Level Select | **Final configuration** (last step of the Six-Stage Ablation) | Reference board run (2026-09-08), 200T bitstream (2026-10-07), 200T board 500-run (2026-10-08) |
| `capacity3_lookahead3_pes4_dualrow_linear` | 3/3 | 4 | Dual-Row Build · Linear Select | Six-Stage Ablation, Stage 5 | RTL simulation, 100T implementation, 200T bitstream (2026-10-07), 200T board 500-run (2026-10-08) |
| `capacity3_lookahead3_pes4_singlerow_linear` | 3/3 | 4 | Single-Row Build · Linear Select | Six-Stage Ablation, Stage 4 | RTL simulation, 100T implementation, 200T bitstream (2026-10-07), 200T board 500-run (2026-10-08) |
| `capacity4_lookahead4_pes4_singlerow_linear` | 4/4 | 4 | Single-Row Build · Linear Select | Six-Stage Ablation, Stage 3 | RTL simulation, 100T implementation, 200T bitstream (2026-10-07), 200T board 500-run (2026-10-08) |
| `capacity4_lookahead4_pes1_singlerow_linear` | 4/4 | 1 | Single-Row Build · Linear Select | Six-Stage Ablation, Stage 2; control of the Checkpoint-Capacity / Lookahead-Shots isolation study | Board run on older RTL (2026-09-04); current RTL: RTL simulation, 100T implementation, 200T bitstream (2026-10-07), 200T board 500-run (2026-10-08) |
| `capacity3_lookahead4_pes1_singlerow_linear` | 3/4 | 1 | Single-Row Build · Linear Select | Checkpoint-Capacity / Lookahead-Shots isolation study | RTL simulation only |
| `capacity3_lookahead3_pes1_singlerow_linear` | 3/3 | 1 | Single-Row Build · Linear Select | Checkpoint-Capacity / Lookahead-Shots isolation study | RTL simulation, 100T implementation, 200T bitstream (2026-10-07), 200T board 500-run (2026-10-08) |
| `capacity4_lookahead8_pes1_singlerow_linear` | 4/8 | 1 | Single-Row Build · Linear Select | First checkpoint board run | Board run on older RTL (2026-09-01) |
| `no_checkpoint_baseline` | none | 4 | Single-Row Build · Linear Select | No-Checkpoint Baseline (below) | Board run (2026-10-04) |
| `capacity0_pes1_singlerow_linear` | none | 1 | Single-Row Build · Linear Select | Same configuration as Stage 1 of the Six-Stage Ablation | 100T implementation (2026-10-08) |
| `final_200mhz` | 3/3 | 4 | Dual-Row Build · Two-Level Select | Final configuration with the accelerator clock at 200 MHz (own RTL, below) | RTL simulation, 200T bitstream, 200T board four-predicate run (2026-10-12), 500-run (2026-10-13) |

The Six-Stage Ablation and isolation-study numbers were benchmarked with standalone tops inside
the tag; each configuration's adapter carries over the parameters those tops passed. The campaign
benchmarked Stage 1 by running the `capacity4_lookahead4_pes1_singlerow_linear` build in Restart mode, so `capacity0_pes1_singlerow_linear` is
the first build with the checkpoint hardware removed at 1 PE. The `capacity4_lookahead8_pes1_singlerow_linear` and `capacity4_lookahead4_pes1_singlerow_linear`
board bitstreams came from the older single-PE RTL and are not byte-identical to the
current Accelerator Core with these adapters. All ten configurations pass the port contract, lint, and the
T1–T9 Bus Interface contract on the real core (`make -C hardware_bram/sim ports-configurations lint-configurations`,
`make -C hardware_bram/sim real CONFIGURATION=<model>`).

`final_200mhz` is the one exception: it keeps its own copy of the Accelerator Core RTL with
extra pipeline registers for 200 MHz. Its BBHT trajectories match `final`; RTL cycles grow by
5.0 % (Restart mode) and 10.1 % (Checkpoint mode). On the remote 200T board all 4,000 four-predicate runs
match the reference model, and wall-clock time is 1.869× (Restart mode) and 1.751× (Checkpoint mode) faster
than the 100 MHz build on the same board ([experiment 20](documents/reports/20_200mhz_implementation.md)).

### `hardware_dram/` — DRAM Variant: full DRAM storage plus a BRAM queue

Amplitudes for every number of iterations are stored in DRAM. Whenever the Iteration-Count LFSR draws
a number of iterations, that amplitude set is also pushed onto a BRAM queue. After measuring a candidate
and checking it, a non-solution causes the queue entry for that number of iterations to be dropped and
the next amplitude set to be fetched from DRAM onto the queue. Since any number of iterations is one
burst away, this variant needs neither a Checkpoint-Capacity nor Lookahead-Shots.

The top level `src/bbht_dram_top.v` ties in the host path (APB CSR and AHB dataset
load). Since 2026-09-25 **a bridge (`src/grover_dram_axi_bridge.v`) turns its DRAM burst
port into a 32-bit AXI4 master** that reaches the DDR3 (`slow_dram`) of the RVX platform
`bbht_grover_dram`. All four predicates × 500 workloads match the software reference
model 2,000/2,000 on an AXI memory model, and a 16-run console script matches 16/16 in a
full-SoC RTL simulation with the real NoC and DDR model. On 2026-10-04 it also matched
2,000/2,000 on the board (first run on real DDR3); on the same board it is about 15.6× slower
in wall-clock time than the checkpoint build
([technical docs ch. 21, Korean](documents/design_references/21_dram_variant.md)).
Regression runs against a behavioral DRAM model
(`make -C hardware_dram/sim`; the `top` target covers the top level). `make -C hardware_dram/sim equiv` replays the same stimulus
on the `hardware_bram` Accelerator Core (final configuration) and checks that the BBHT trajectories match. Single search only for
now; Enumeration is rejected as a `config_error`.

### `hardware_bram/configurations/no_checkpoint_baseline/` — No-Checkpoint Baseline

Keeps only the 4 PEs and turns off checkpoints, the Policy
Engine, Dual-Row Build and Two-Level Select. It exists to compare speed
with and without the optimizations on the same board and SoC. Like every configuration it uses
the shared Accelerator Core, Bus Interface, and firmware of `hardware_bram/` unchanged; its only RTL is
an adapter with different parameter defaults and burst handling.
Restart mode runs match the software reference model 2,000/2,000 and match the `capacity3_lookahead3_pes4_singlerow_linear` configuration (Stage 4,
run in Restart mode) **cycle for cycle** on all 2,000 workloads.
In RTL cycles, the final configuration is 2.897× faster than this baseline. The 100 MHz bitstream closes
timing (WNS +0.193 ns). On 2026-10-04 its 2,000 Restart mode runs matched the reference model on the
board, and on the same board the checkpoint build is **2.810×** faster in wall-clock time
([technical docs ch. 20, Korean](documents/design_references/20_no_checkpoint_baseline.md)).

`hardware_bram/` and `hardware_dram/` share the same shape -- `src`, `testbench`, `sim`,
`rvx`, `firmware` -- except that on the BRAM side the per-configuration `vivado`, `bitstream`, and
configuration-specific `results` sit under `models/`. Both directory trees share the software reference
models, test vectors, and comparison experiments under `software/`.

---

## 4. Directory structure

```
documents/
  study_references/     Study material: entry point index.md, chapters 1-18 plus appendix A (Korean)
    papers/             Source paper PDFs (papers_ko/ holds Korean commentaries), our paper outline paper_outline.md
  design_references/    The settled design: 22 numbered chapters, entry point index.md (Korean)
    diagrams/           Figures the docs and reports reference (the only subfolder)
  reports/              Experiments run to settle or confirm the design, <number>_<name>.md,
                          entry point index.md (Korean)
  check_docs.py         Documentation consistency checker

hardware_bram/          BRAM Variant. Everything below is shared by all configurations
  src/                  One RTL directory tree (Bus Interface, top level, Accelerator Core). Adapters live per configuration.
                        The exact board source is tag board-verified-build-2026-09-07
  testbench/            Testbenches, including the verilator C++ harnesses
  sim/                  Makefile, runners, report scripts. CONFIGURATION=<model> picks the adapter
  synth/                Vivado batch scripts for Accelerator Core resource synthesis
  results/              Cross-configuration evidence (Six-Stage Ablation, resources, isolation study)
  rvx/                  Shared RVX installer install_model.sh, user region template
  firmware/             Driver, console app, benchmark app, ORCA baseline
  models/               Ten configurations plus the 200 MHz one, folders named hardware_bram_<model>
    final/   Final configuration (board reference)
      src/              One adapter (defaults of the four configuration axes)
      rvx/              RVX platform bbht_grover_final definition and install script
      results/          Simulation evidence for this configuration (YYYY-MM-DD_<topic>/)
      vivado/           Vivado project vivado_bbht_grover_fpga (reports, board benchmarks)
      bitstream/        Bitstream bundles flashed to the board
    no_checkpoint_baseline/ No-Checkpoint Baseline: src rvx sim results vivado bitstream
    final_200mhz/ Final configuration at 200 MHz: src holds the adapter and
                        10 Accelerator Core RTL files; rvx sim results vivado bitstream
    capacity4_lookahead8_pes1_singlerow_linear/      src rvx, plus vivado/ with the older-RTL board run (2026-09-01)
    capacity4_lookahead4_pes1_singlerow_linear/      src rvx, plus vivado/ with the older-RTL board run (2026-09-04)
    hardware_bram_{capacity0_pes1_singlerow_linear,capacity3_lookahead4_pes1_singlerow_linear,capacity3_lookahead3_pes1_singlerow_linear,capacity4_lookahead4_pes4_singlerow_linear,capacity3_lookahead3_pes4_singlerow_linear,capacity3_lookahead3_pes4_dualrow_linear}/
                        src rvx only (never built into a bitstream)

hardware_dram/          DRAM Variant - full DRAM storage plus BRAM queue
                        (RTL + top level + AXI4 bridge + RVX install; benchmarked on the board 2026-10-04)
                        A single directory tree without configuration folders: the hardware_bram layout plus
                        vivado and bitstream, without synth

spec/                   Register and port specification shared by RTL, firmware, and host tools
                          CSR source JSON, gen_csr.py, generated/, port_contract.tsv, check_ports.py

software/               category / subfolder / contents; data and result folders are date_topic with a same-name .md
  reference_model_develop/       reference models (models/), RTL testbench stimulus generators (tb_stimulus/),
                          Common500 comparison, Predicate500 expected-result generator
  reference_model_data/          what the reference model produced: requested-iterations vectors, enumeration vectors,
                          Common500 results, Predicate500 expected results
  testbench_data/       inputs read by testbenches and experiments: Common500 datasets and seed roster,
                          Predicate500 datasets
  pc_grover_develop/    Grover on a PC (C++, NumPy, Qiskit). Experiment report 17
  pc_grover_result/       its benchmarks
  orca_grover_develop/  accelerator-free C, three models, built for ORCA and for x86. Experiment report 19
  orca_grover_result/     its benchmarks
  host_fpga_develop/    PC-side tools that drive the board
                          bbht_cli.py (real UART, mock, replay), bbht_predicate500.py (four-predicate test)

trash_bin/              Superseded docs and bulky artifacts. Not tracked by git
```

---

## 5. Quick start

```bash
# Bus Interface regression / Bus Interface + adapter + Accelerator Core / 250-pair BBHT trajectory testbench
make -C hardware_bram/sim ports lint regress driver
make -C hardware_bram/sim real
make -C hardware_bram/sim bench250

# Four predicates × 500 workloads: RTL testbench for all three directory trees, then the board test
make -C hardware_bram/sim predicate500
make -C hardware_bram/configurations/no_checkpoint_baseline/sim predicate500 predicate500-ref equiv
make -C hardware_dram/sim predicate500
python3 software/host_fpga_develop/bbht_predicate500.py --port /dev/ttyUSB1

# Software reference models, Common500 comparison (after installing software/reference_model_develop/common500/requirements.txt in a venv)
bash software/reference_model_develop/common500/run_full_benchmark.sh

# Install into the RVX platform (needs the files above)
source /opt/rvx/rvx_setup.sh
hardware_bram/configurations/final/rvx/install_to_platform.sh

# After editing documentation
python3 documents/check_docs.py
```

On the board, load the console app (`hardware_bram/firmware/bbht_console/`) and type
commands in a serial terminal; see
[technical docs ch. 17](documents/design_references/17_board_operation.md).

---

## 6. Further reading

| Question | Where |
|---|---|
| The whole system, chapter by chapter (22 chapters, Korean) | [index.md](documents/design_references/index.md) |
| How do I drive it from the host? | [ch. 17 board operation](documents/design_references/17_board_operation.md) |
| What does each CSR register do? | [ch. 13 CSR registers](documents/design_references/13_csr_registers_and_execution_modes.md) |
| Accelerator Core ports | [ch. 12 Accelerator Core port contract](documents/design_references/12_accelerator_core_port_contract.md) |
| Fixed-point format and memory layout | [ch. 6 data and memory map](documents/design_references/06_data_representation_and_memory_map.md) |
| UART commands | [ch. 14 UART protocol](documents/design_references/14_host_interface_and_uart_protocol.md) |
| Software reference models and the comparison experiment | [ch. 4 reference models](documents/design_references/04_software_reference_model_and_test_vectors.md) |
| Why each design decision was made, board runs, baseline comparisons | [experiment index](documents/reports/index.md) (Korean) |
| Grover's algorithm itself | [study_references/](documents/study_references/index.md) index and chapters 1-18 |
