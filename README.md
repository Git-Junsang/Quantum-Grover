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
| Communication layer (CSR, DMA, FIFO, driver, UART console) | Simulation regression passed before the 2026-09-13 `software/` reorganization; it cannot run now because files it needs were removed (section 5). main carries our layer; the board build used PJK's original layer (ours is not on the board yet) |
| 100 MHz implementation | Timing closed (WNS +0.126 ns); reports under `hardware_bram/vivado/` |
| **Main IP RTL source** | `hardware_bram/src/`, one current tree. The sha256-identical board source is tag `board-k3h3-e4-m2` |
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
[CSR_레지스터_규격.md](documents/design_references/CSR_레지스터_규격.md) from it. Two
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
| Board wall-clock | Normal 425,502 us → **55,798 us** (7.626x) | `hardware_bram/vivado/vivado_bbht_grover_fpga/2026-09-08_k3h3_e4_m2_board_500run/` |
| RTL cycles (6 stages) | Normal 42,308,335 → **6,890,470** (6.1401x) | `hardware_bram/results/2026-09-08_publication_6stage/` |
| Versus software | **116,426x** over one ORCA core | `hardware_bram/vivado/vivado_bbht_grover_fpga/2026-09-08_orca_1core_baseline/` |

All three use the same 500 workloads (M = 1/4/16/64/256 x 100 seeds). Board and RTL agree
on the search trajectory 500/500, but the cycle counts themselves differ, so never build a
ratio that mixes the two axes.

---

## 3. Two competing implementations

The design forks on how amplitudes are reused after a failed shot.
**Neither is final; one will be chosen later.**

### `hardware_bram/` — checkpoints plus four intra-iteration engines

The established approach, BRAM only. Amplitudes from a failed shot are not discarded;
computation resumes from a checkpoint and advances only by the difference (K3/H3 policy).
Inside one physical Grover iteration, four P=32 engines split the 512 rows (E4). The
silicon-proven design belongs to this branch, and all code currently in the repository
lives here.

### `hardware_dram/` — full DRAM storage plus a BRAM queue

Amplitudes for every `j` are stored in DRAM. Whenever the random number generator draws
a `j`, that amplitude set is also pushed onto a BRAM queue. After guessing a candidate
and verifying it, a wrong answer causes the queue entry for that `j` to be dropped and
the next `j` amplitude set to be fetched from DRAM onto the queue. Since any `j` is one
burst away, this branch needs neither a checkpoint count K nor a lookahead policy H.

**Draft RTL, its regression, and a top level `src/bbht_dram_top.v` that ties in the
host path (APB CSR and AHB dataset load) exist; the physical DRAM binding (MIG/AXI) and
the RVX install do not yet.** The top level exposes the DRAM burst port so a bridge can
attach there. Verification runs against a behavioral DRAM model
(`make -C hardware_dram/sim`; the `top` target covers the top level). `make -C hardware_dram/sim equiv` replays the same stimulus
on the frozen `hardware_bram` core and checks that the search trajectories match. Single Search only for
now; Enumeration is rejected as a `config_error`.

Both trees share the same shape — `src`, `testbench`, `sim`, `rvx`, `vivado`, `firmware` —
and share the software reference models, verification vectors, and comparison experiments
under `software/`.

---

## 4. Directory structure

```
documents/
  design_references/    Design docs: CSR spec, port spec, host operation, analysis reports
    diagrams/           Figures those docs reference (the only subfolder)
  study_references/     Tutorial chapters 0-18 plus appendix A (Korean)
  papers/               Source paper PDFs (papers_ko/ holds Korean commentaries)
  check_docs.py         Documentation consistency checker
  *.pptx, *.docx        Final Main IP slides and the project master document (read-only originals)

hardware_bram/          Branch 1 - checkpoints plus four intra-iteration engines, BRAM only
  src/                  One current RTL tree (comms layer, adapter, top level, Main IP).
                        The exact board source is tag board-k3h3-e4-m2
  testbench/            Testbenches, including the verilator C++ harnesses
  sim/                  Makefile, runners, report scripts
  synth/                Vivado batch scripts for resource synthesis
  results/              Simulation campaign evidence (YYYY-MM-DD_<topic>/)
  bitstream/            Bitstream bundles flashed to the board
  rvx/                  RVX platform definition and install script
  vivado/               Vivado project folders, named lowercase vivado_<project>
  firmware/             Driver, console app, benchmark app, ORCA baseline

hardware_dram/          Branch 2 - full DRAM storage plus BRAM queue
                        (draft RTL + top level + regression; no physical DRAM binding or RVX install yet)
                        Same layout as hardware_bram, without the bram-only folders
                        (synth, bitstream)

software/               Shared by both branches
  models/               NumPy, Qiskit, Q1.22 bit-exact, and checkpoint-policy reference models
  experiments/          Common500 comparison (the same 500 workloads as the board)
  rtl_vectors/          RTL answer vectors (256 requested-j cases, two enumeration methods)
                          tools/dump_bench_workload.py -- bench250/500 stimulus
  results/              Common500 final results, tables, plots, validation report
  contract/             Hardware/software contracts and their checkers
                          CSR source of truth (JSON), gen_csr.py, generated/
                          port_contract.tsv, check_ports.py
  host/bbht_cli.py      Host-side CLI (real UART, mock, sim-transcript replay)
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

# Software reference models, Common500 comparison (after installing software/requirements.txt in a venv)
bash software/experiments/common500_benchmark/run_full_benchmark.sh

# Install into the RVX platform (needs the files above)
source /opt/rvx/rvx_setup.sh
hardware_bram/rvx/install_to_platform.sh

# After editing documentation
python3 documents/check_docs.py
```

On the board, load the console app (`hardware_bram/firmware/bbht_console/`) and type
commands in a serial terminal; see
[호스트_조작_방법.md](documents/design_references/호스트_조작_방법.md).

---

## 6. Further reading

| Question | Where |
|---|---|
| How do I drive it from the host? | [design_references/호스트_조작_방법.md](documents/design_references/호스트_조작_방법.md) |
| What does each CSR register do? | [design_references/CSR_레지스터_규격.md](documents/design_references/CSR_레지스터_규격.md) |
| Main IP ports | [design_references/Main_IP_포트_규격.md](documents/design_references/Main_IP_포트_규격.md) |
| Fixed-point format and memory layout | [design_references/데이터_고정소수점_메모리_규격.md](documents/design_references/데이터_고정소수점_메모리_규격.md) |
| UART commands | [design_references/UART_명령_프로토콜.md](documents/design_references/UART_명령_프로토콜.md) |
| Software reference models and the comparison experiment | [design_references/소프트웨어_기준모델과_Common500.md](documents/design_references/소프트웨어_기준모델과_Common500.md) |
| Grover's algorithm itself | [study_references/](documents/study_references/README.md) chapters 0-18 |
