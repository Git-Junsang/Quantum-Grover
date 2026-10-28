#!/usr/bin/env bash
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
SW=$(cd "$HERE/../.." && pwd)                     # software/
BOARD=$(cd "$SW/../hardware_bram/configurations/final/vivado/vivado_bbht_grover_fpga/2026-09-08_k3h3_e4_m2_board_500run" && pwd)

export PYTHONPATH="$SW/reference_model_develop/models/common:$SW/pc_grover_develop/team_models/numpy_model:$SW/pc_grover_develop/team_models/qiskit_model:$SW/reference_model_develop/models/rtl_reference_model"
export OMP_NUM_THREADS=1
export OPENBLAS_NUM_THREADS=1
export MKL_NUM_THREADS=1
export NUMEXPR_NUM_THREADS=1

python "$HERE/run_common500_benchmark.py" \
  --inputs "$SW/testbench_data/2026-09-08_common500" \
  --fpga-dir "$BOARD" \
  --output "$SW/reference_model_data/2026-09-11_common500" \
  --targets 1,4,16,64,256 \
  --threads 1
