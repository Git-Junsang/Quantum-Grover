#!/usr/bin/env bash
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)

export PYTHONPATH="$ROOT/models/common:$ROOT/models/numpy_model:$ROOT/models/qiskit_model:$ROOT/models/rtl_reference_model"
export OMP_NUM_THREADS=1
export OPENBLAS_NUM_THREADS=1
export MKL_NUM_THREADS=1
export NUMEXPR_NUM_THREADS=1

python "$HERE/run_common500_benchmark.py" \
  --inputs "$HERE/inputs" \
  --output "$ROOT/results/common500_final" \
  --targets 1,4,16,64,256 \
  --threads 1
