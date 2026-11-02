#!/bin/bash
# usage: run_cell_vl.sh <K> <H> <mode>  -- Verilator build + run of the standalone policy harness
S=/tmp/claude-1000/-workspace/e2bf3af7-5088-4566-a65a-8c884cbf49eb/scratchpad
W=$S/wt/hardware_bram
K=$1; H=$2; P=$3
D=$S/vl/k${K}h${H}_p${P}
L=$S/vl/k${K}h${H}_p${P}.log
verilator --binary --timing -Wno-fatal -Wno-DECLFILENAME -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC -Wno-LATCH \
  -I$W/src -GCKPT_K=$K -GH_FUTURE=$H -GEXACT_PRUNE=$P --top-module tb_policy_kh_sweep \
  $W/testbench/tb_policy_kh_sweep.sv $W/src/grover_policy.v --Mdir $D -o sim -j 2 > $L.build 2>&1 \
  || { echo "k$K h$H p$P BUILD_FAIL"; exit 1; }
$D/sim +TRACE=$S/traces/trace_k${K}h${H}.txt > $L 2>&1
echo "k$K h$H p$P $(grep -m1 -E 'SUMMARY|FAIL' $L) errors=$(grep -c '^ERROR' $L)"
rm -rf $D
