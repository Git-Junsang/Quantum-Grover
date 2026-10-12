#!/usr/bin/env bash
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
SW=$(cd "$HERE/../.." && pwd)                     # software/
BOARD=$(cd "$SW/../hardware_bram/models/hardware_bram_K3H3_E4_M2/vivado/vivado_bbht_grover_fpga/2026-09-08_k3h3_e4_m2_board_500run" && pwd)

export PYTHONPATH="$SW/golden_develop/models/common:$SW/pc_grover_develop/team_models/numpy_model:$SW/pc_grover_develop/team_models/qiskit_model:$SW/golden_develop/models/rtl_reference_model"
export OMP_NUM_THREADS=1
export OPENBLAS_NUM_THREADS=1
export MKL_NUM_THREADS=1
export NUMEXPR_NUM_THREADS=1

python "$HERE/run_common500_benchmark.py" \
  --inputs "$SW/testbench_data/2026-09-08_common500" \
  --fpga-dir "$BOARD" \
  --output "$SW/golden_data/2026-09-11_common500" \
  --targets 1,4,16,64,256 \
  --threads 1
