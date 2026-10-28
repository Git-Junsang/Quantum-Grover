"""repo_paths.py : one place for every path the pc_grover tools use.

pc_grover (software/pc_grover_develop) reads the golden models, the Common500 inputs, the
Predicate500 expectations and the RTL vectors where they already are under
software/golden; nothing outside software/pc_grover_develop is copied or modified.
"""
import sys
from pathlib import Path

BENCH_ROOT = Path(__file__).resolve().parents[1]           # software/pc_grover_develop
SOFTWARE = BENCH_ROOT.parent                                # software/
REPO = SOFTWARE.parent                                      # repository root

# ---- shared data (read in place)
COMMON500 = SOFTWARE / "testbench_data" / "2026-09-08_common500"            # seed roster + datasets/
COMMON500_FPGA = REPO / "hardware_bram/configurations/final/vivado/vivado_bbht_grover_fpga/2026-09-08_k3h3_e4_m2_board_500run"
COMMON500_FPGA_FILES = {"normal": "per_run_normal.csv", "k4h4": "per_run_k4h4.csv", "k3h3": "per_run_m2.csv"}   # 09/08 board 500-run
P500_EXPECTED = SOFTWARE / "reference_model_data" / "2026-09-25_predicate500"
VECTORS_ZIP = SOFTWARE / "reference_model_data" / "2026-09-02_requested_j_vectors" / "requested_j_bit_exact_256_cases.zip"

# ---- Predicate500 inputs
P500_DATASETS = SOFTWARE / "testbench_data" / "2026-10-05_predicate500"     # tools/make_predicate500_datasets.py
RESULTS = SOFTWARE / "pc_grover_result"
BOARD_P500_FILES = [  # 10/04 board runs, read where the hardware folders keep them
    REPO / "hardware_bram/configurations/final/vivado/vivado_bbht_grover_fpga/2026-10-04_board_predicate500/result.csv",
    REPO / "hardware_bram/configurations/no_checkpoint_baseline/vivado/vivado_bbht_grover_nocheckpoint/2026-10-04_board_predicate500/result.csv",
    REPO / "hardware_dram/vivado/vivado_bbht_grover_dram/2026-10-04_board_predicate500/result.csv",
]

# ---- builds and code
BUILD = BENCH_ROOT / "cpp" / "build"
GROVER_BENCH = BUILD / "grover_bench"
GROVER_SINGLE = BUILD / "grover_single_run"
BASELINES_DIR = BENCH_ROOT / "python"
TEAM_MODEL_DIRS = ([SOFTWARE / "reference_model_develop" / "models" / d for d in ("common", "rtl_reference_model")]
                   + [BENCH_ROOT / "team_models" / d for d in ("numpy_model", "qiskit_model")])

# Predicate500 thresholds (reference_model_develop/models/common/benchmark_dataset.py PREDICATE500_SPECS)
PREDICATE500 = {"LT": (-16384, 0), "GT": (16383, 0), "EQ": (12345, 0), "RANGE": (-4096, 4096)}


def use_golden() -> None:
    """Make the team models importable (checkpoint_bbht_model, benchmark_dataset, ...).

    Bytecode caching is switched off so importing never writes __pycache__ into
    the team folders.
    """
    sys.dont_write_bytecode = True
    for d in reversed(TEAM_MODEL_DIRS):
        if str(d) not in sys.path:
            sys.path.insert(0, str(d))
