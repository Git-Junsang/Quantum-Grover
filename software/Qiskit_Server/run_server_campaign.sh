#!/usr/bin/env bash
set -euo pipefail

PYTHON=${PYTHON:-python3}
RESULT_ROOT=${RESULT_ROOT:-verification_results}

mkdir -p "$RESULT_ROOT"

echo "[1/2] requested-j NumPy/Qiskit benchmark"
"$PYTHON" qiskit_three_way_benchmark.py \
  --preset SERVER \
  --threads 1 \
  --repeats 10 \
  --warmups 2 \
  --output "$RESULT_ROOT/qiskit_three_way_server_1thread"

echo "[2/2] BBHT NumPy/Qiskit 50-seed benchmark"
"$PYTHON" qiskit_bbht_benchmark.py \
  --targets 1,4,16,64,256 \
  --seed-start 1 \
  --seed-count 50 \
  --threads 1 \
  --output "$RESULT_ROOT/qiskit_bbht_server_50seed"

echo "complete: $RESULT_ROOT"
