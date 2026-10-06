# Multi-Predicate Grover Search Accelerator

An FPGA emulator accelerator that uses Grover's algorithm to find indices in an
on-chip data array satisfying one of four predicates: `<`, `>`, `=`, and range
(`a < x < b`). A host PC sends the predicate and thresholds over UART; a custom IP
inside an RVX SoC computes and returns the result index.

- Board: Arty A7-100T (`xc7a100tcsg324-1`)
- Reference spec: **K3/H3-E4-M2** (built 2026-09-07, measured 2026-09-08). What was verified on the board wins.

Korean documentation is the primary source — see [README.ko.md](README.ko.md).

---

## 1. Status

| Item | State |
|---|---|
| Main IP algorithm (Q14 / P32 / DATA16) | K3/H3-E4-M2, board sign-off complete |
| Communication layer (CSR, DMA, FIFO, driver, UART console) | Our layer is confirmed on the board: command round trip on 2026-09-17, and on 2026-10-04 all four predicates x 500 workloads x two modes (4,000 runs, with wall-clock time) match the reference model 4,000/4,000 |
| 100 MHz implementation | Timing closed (WNS +0.126 ns); reports under `hardware_bram/models/hardware_bram_K3H3_E4_M2/vivado/` |
| **Main IP RTL source** | `hardware_bram/src/`, one current tree. The sha256-identical board source is tag `board-k3h3-e4-m2` (where the folder was still named `hardware_bram/`) |
| Performance evidence | Board wall-clock **7.626x**, RTL cycles **6.1401x**, **116,426x** over a single ORCA core |
| Software reference models | NumPy, Qiskit Aer, Q1.22 bit-exact, and the K3/H3 policy model. On the same 500 workloads as the board, search trajectories and physical iteration counts match 500/500 |

Wiring correctness is enforced by a
[port contract check](software/contract/check_ports.py) that diffs the handoff
document's port tables (19 wrapper + 61 core signals) against the RTL across three
branches (`stub`, `real`, `dram`). All three match.

---

## 2. Frozen numbers

The single source of truth for the CSR map is
[`software/contract/bbht_grover_csr.json`](software/contract/bbht_grover_csr.json).
`gen_csr.py` generates the Verilog, C, and Python headers plus
[chapter 13 of the technical docs](documents/design_references/13_CSR_레지스터와_실행_모드.md) from it. Two
other places hold the same numbers but are not generated (the software reference model,
which also carries policy names, and the board bench app, whose ELF hash is frozen);
`gen_csr.py --check` reads and cross-checks both.

| Item | Value |
|---|---|
| Qubits | Q = 14 (N = 16,384) |
| Data word | 16-bit signed |
| Amplitude | 23-bit, Q1.22 family |
| Parallelism | P = 32 lanes |
| Predicates | `LT`, `GT`, `EQ`, `RANGE` |
| Run modes | `MANUAL_SINGLE`, `NORMAL_SINGLE`, `CKPT_SINGLE`, `NORMAL_ENUM`, `CKPT_ENUM` (K/H are build constants, not CSR fields) |
| CSR | APB slave, base `0xE2020000`, 4-byte stride, 32-bit, 38 registers |
| Data load | AHB master, SINGLE, single outstanding. SRAM `0xE0000000`–`0xE001FFFF` |
| Result FIFO | Depth 256 |
| Clocks | Accelerator 100 MHz / system 50 MHz |
| Final configuration | **K3/H3-E4-M2** — 3 checkpoints, policy horizon 3, 4 intra-iteration engines, 2-stage measurement optimization |

### Performance — do not mix the axes

| Axis | Value | Evidence |
|---|---|---|
| Board wall-clock | Normal 425,502 us → **55,798 us** (7.626x) | `hardware_bram/models/hardware_bram_K3H3_E4_M2/vivado/vivado_bbht_grover_fpga/2026-09-08_k3h3_e4_m2_board_500run/` |
| RTL cycles (6 stages) | Normal 42,308,335 → **6,890,470** (6.1401x) | `hardware_bram/results/2026-09-08_publication_6stage/` |
| Versus software | **116,426x** over one ORCA core | `hardware_bram/models/hardware_bram_K3H3_E4_M2/vivado/vivado_bbht_grover_fpga/2026-09-08_orca_1core_baseline/` |

All three use the same 500 workloads (M = 1/4/16/64/256 x 100 seeds). Board and RTL agree
on the search trajectory 500/500, but the cycle counts themselves differ, so never build a
ratio that mixes the two axes.

---

## 3. Two competing implementations and the BRAM models

The design forks on how amplitudes are reused after a failed shot.
**Neither is final; one will be chosen later.** There are two hardware trees,
`hardware_bram/` and `hardware_dram/`. On 2026-10-06 the former
`hardware_bram_checkpoint/` and `hardware_bram_nocheckpoint/` were merged into
`hardware_bram/`, with one model folder per checkpoint/engine configuration. Inside tags
(`board-k3h3-e4-m2` and others) the folder still has its name of that time, `hardware_bram/`.

### `hardware_bram/` — shared BRAM sources plus ten models

BRAM only. Amplitudes from a failed shot are not discarded; computation resumes from a
checkpoint and advances only by the difference (K, H). Inside one physical Grover
iteration, several P=32 engines split the 512 rows (E). The silicon-proven design belongs
to this branch.

The checkpoint count K, policy horizon H, engine count E, and measurement optimizations
M1/M2 are all compile-time parameters of the Main IP, so **every model compiles the same
RTL with different parameters**. The comms layer, Main IP, testbenches, firmware,
simulation, and synthesis live once directly under `hardware_bram/`. Only what differs per
model -- one adapter that sets the parameter defaults, the RVX platform definition, and that
model's implementation reports, board measurements, and bitstreams -- lives in
`hardware_bram/models/hardware_bram_<model>/`. The ten models are the combinations tried so far.

| Model | K/H | E | M | Origin | Hardware |
|---|---|---|---|---|---|
| `K3H3_E4_M2` | 3/3 | 4 | M2 | **Final configuration** (last 6-stage ablation step) | Reference board run (2026-09-08) |
| `K3H3_E4_M1` | 3/3 | 4 | M1 | 6-stage ablation, step 5 | RTL simulation only |
| `K3H3_E4` | 3/3 | 4 | - | 6-stage ablation, step 4 | RTL simulation only |
| `K4H4_E4` | 4/4 | 4 | - | 6-stage ablation, step 3 | RTL simulation only |
| `K4H4_E1` | 4/4 | 1 | - | 6-stage ablation step 2, control of the K/H isolation study | Board run on older RTL (2026-09-04) |
| `K3H4_E1` | 3/4 | 1 | - | K/H isolation study | RTL simulation only |
| `K3H3_E1` | 3/3 | 1 | - | K/H isolation study | RTL simulation only |
| `K4H8_E1` | 4/8 | 1 | - | First checkpoint board run | Board run on older RTL (2026-09-01) |
| `nocheckpoint` | none | 4 | - | Normal-E4 baseline (below) | Board run (2026-10-04) |
| `Normal_E1` | none | 1 | - | Same configuration as 6-stage ablation step 1 | None |

The 6-stage ablation and K/H isolation numbers were measured with standalone tops inside
the tag; each model adapter carries over the parameters those tops passed. The campaign
measured Normal-E1 by running the `K4H4_E1` build in runtime NORMAL mode, so `Normal_E1` is
the first build with the checkpoint hardware removed at E1. The `K4H8_E1` and `K4H4_E1`
board bitstreams came from the older single-engine RTL and are not byte-identical to the
current Main IP with these adapters. All ten models pass the port contract, lint, and the
T1-T9 comms contract on the real core (`make -C hardware_bram/sim ports-models lint-models`,
`make -C hardware_bram/sim real MODEL=<model>`).

### `hardware_dram/` — full DRAM storage plus a BRAM queue

Amplitudes for every `j` are stored in DRAM. Whenever the random number generator draws
a `j`, that amplitude set is also pushed onto a BRAM queue. After guessing a candidate
and verifying it, a wrong answer causes the queue entry for that `j` to be dropped and
the next `j` amplitude set to be fetched from DRAM onto the queue. Since any `j` is one
burst away, this branch needs neither a checkpoint count K nor a lookahead policy H.

The top level `src/bbht_dram_top.v` ties in the host path (APB CSR and AHB dataset
load). Since 2026-09-25 **a bridge (`src/grover_dram_axi_bridge.v`) turns its DRAM burst
port into a 32-bit AXI4 master** that reaches the DDR3 (`slow_dram`) of the RVX platform
`bbht_grover_dram`. All four predicates x 500 workloads match the software reference
model 2,000/2,000 on an AXI memory model, and a 16-run console script matches 16/16 in a
full-SoC RTL simulation with the real NoC and DDR model. On 2026-10-04 it also matched
2,000/2,000 on the board (first run on real DDR3); on the same board it is about 15.6x slower
in wall-clock time than the checkpoint build
([technical docs ch. 22, Korean](documents/design_references/22_DRAM_갈래.md)).
Regression runs against a behavioral DRAM model
(`make -C hardware_dram/sim`; the `top` target covers the top level). `make -C hardware_dram/sim equiv` replays the same stimulus
on the `hardware_bram` Main IP (K3/H3-E4-M2) and checks that the search trajectories match. Single Search only for
now; Enumeration is rejected as a `config_error`.

### `hardware_bram/models/hardware_bram_nocheckpoint/` — baseline without checkpoints

Keeps only the four intra-iteration engines (E4) and turns off checkpoints, the policy
engine, and the measurement optimizations M1/M2 (Normal-E4). It exists to compare speed
with and without the optimizations on the same board and SoC. Like every model it uses
the shared Main IP, comms layer, and firmware of `hardware_bram/` unchanged; its only RTL is
an adapter with different parameter defaults and burst handling.
Normal runs match the software reference 2,000/2,000 and match the `K3H3_E4` model (the
checkpoint build with M1/M2 off, run in Normal mode) **cycle for cycle** on all 2,000 workloads.
In RTL cycles, K3/H3-E4-M2 is 2.897x faster than this baseline. The 100 MHz bitstream closes
timing (WNS +0.193 ns). On 2026-10-04 its 2,000 Normal runs matched the reference model on the
board, and on the same board the checkpoint build is **2.810x** faster in wall-clock time
([technical docs ch. 21, Korean](documents/design_references/21_체크포인트_없는_BRAM_판.md)).

`hardware_bram/` and `hardware_dram/` share the same shape -- `src`, `testbench`, `sim`,
`rvx`, `firmware` -- except that on the bram side the per-model `vivado`, `bitstream`, and
model-specific `results` sit under `models/`. Both trees share the software reference
models, verification vectors, and comparison experiments under `software/`.

---

## 4. Directory structure

```
documents/
  design_references/    Technical docs: 24 numbered chapters, entry point 00_문서_지도.md (Korean)
    diagrams/           Figures those chapters reference (the only subfolder)
  study_references/     Tutorial chapters 0-18 plus appendix A (Korean)
  papers/               Source paper PDFs (papers_ko/ holds Korean commentaries)
  check_docs.py         Documentation consistency checker
  *.pptx                Final Main IP slides (read-only)

hardware_bram/          Branch 1 - BRAM only. Everything below is shared by all models
  src/                  One RTL tree (comms layer, top level, Main IP). Adapters live per model.
                        The exact board source is tag board-k3h3-e4-m2
  testbench/            Testbenches, including the verilator C++ harnesses
  sim/                  Makefile, runners, report scripts. MODEL=<model> picks the adapter
  synth/                Vivado batch scripts for Main IP resource synthesis
  results/              Cross-model evidence (6-stage ablation, 5-config resources, K/H isolation)
  rvx/                  Shared RVX installer install_model.sh, user region template
  firmware/             Driver, console app, benchmark app, ORCA baseline
  models/               Ten models, folders named hardware_bram_<model>
    hardware_bram_K3H3_E4_M2/   Final configuration (board reference)
      src/              One adapter (K/H/E/M defaults)
      rvx/              RVX platform bbht_grover_upgrade definition and install script
      results/          Simulation evidence for this configuration (YYYY-MM-DD_<topic>/)
      vivado/           Vivado project vivado_bbht_grover_fpga (reports, board measurements)
      bitstream/        Bitstream bundles flashed to the board
    hardware_bram_nocheckpoint/ Normal-E4 baseline: src rvx sim results vivado bitstream
    hardware_bram_K4H8_E1/      src rvx, plus vivado/ with the older-RTL board run (2026-09-01)
    hardware_bram_K4H4_E1/      src rvx, plus vivado/ with the older-RTL board run (2026-09-04)
    hardware_bram_{Normal_E1,K3H4_E1,K3H3_E1,K4H4_E4,K3H3_E4,K3H3_E4_M1}/
                        src rvx only (never built into a bitstream)

hardware_dram/          Branch 2 - full DRAM storage plus BRAM queue
                        (RTL + top level + AXI4 bridge + RVX install; measured on the board 2026-10-04)
                        A single tree without model folders: the hardware_bram layout plus
                        vivado and bitstream, without synth

software/               Shared by both trees
  models/               NumPy, Qiskit, Q1.22 bit-exact, and checkpoint-policy reference models
  experiments/          Common500 comparison (the same 500 workloads as the board)
  rtl_vectors/          RTL answer vectors (256 requested-j cases, two enumeration methods)
                          tools/dump_bench_workload.py -- bench250/500 stimulus
  results/              Common500 final results, tables, plots, validation report
  contract/             Hardware/software contracts and their checkers
                          CSR source of truth (JSON), gen_csr.py, generated/
                          port_contract.tsv, check_ports.py
  host/bbht_cli.py      Host-side CLI (real UART, mock, sim-transcript replay)
  host/bbht_predicate500.py  Automated board test, four predicates x 500 workloads -> Excel
  requirements.txt      Python packages for rerunning Common500

trash_bin/              Superseded docs and bulky artifacts. Not tracked by git
```

---

## 5. Quick start

```bash
# Comms regression / comms + adapter + Main IP / 250-pair trajectory bench
make -C hardware_bram/sim ports lint regress driver
make -C hardware_bram/sim real
make -C hardware_bram/sim bench250

# Four predicates x 500 workloads: RTL bench for all three trees, then the board test
make -C hardware_bram/sim predicate500
make -C hardware_bram/models/hardware_bram_nocheckpoint/sim predicate500 predicate500-ref equiv
make -C hardware_dram/sim predicate500
python3 software/host/bbht_predicate500.py --port /dev/ttyUSB1

# Software reference models, Common500 comparison (after installing software/requirements.txt in a venv)
bash software/experiments/common500_benchmark/run_full_benchmark.sh

# Install into the RVX platform (needs the files above)
source /opt/rvx/rvx_setup.sh
hardware_bram/models/hardware_bram_K3H3_E4_M2/rvx/install_to_platform.sh

# After editing documentation
python3 documents/check_docs.py
```

On the board, load the console app (`hardware_bram/firmware/bbht_console/`) and type
commands in a serial terminal; see
[technical docs ch. 17](documents/design_references/17_보드_운용.md).

---

## 6. Further reading

| Question | Where |
|---|---|
| The whole system, chapter by chapter (24 chapters, Korean) | [00_문서_지도.md](documents/design_references/00_문서_지도.md) |
| How do I drive it from the host? | [ch. 17 board operation](documents/design_references/17_보드_운용.md) |
| What does each CSR register do? | [ch. 13 CSR registers](documents/design_references/13_CSR_레지스터와_실행_모드.md) |
| Main IP ports | [ch. 12 Main IP port contract](documents/design_references/12_Main_IP_포트_계약.md) |
| Fixed-point format and memory layout | [ch. 6 data and memory map](documents/design_references/06_데이터_표현과_메모리_맵.md) |
| UART commands | [ch. 14 UART protocol](documents/design_references/14_호스트_인터페이스와_UART_프로토콜.md) |
| Software reference models and the comparison experiment | [ch. 4 reference models](documents/design_references/04_소프트웨어_기준모델과_정답_벡터.md) |
| Why each design decision was made | [ch. 23 design-rationale experiments](documents/design_references/23_설계_근거_실험.md) |
| Grover's algorithm itself | [study_references/](documents/study_references/README.md) chapters 0-18 |
