# Parameterized policy-only OOC synthesis/timing probe.
set PART        xc7a100tcsg324-1
set SRC         $::env(POLICY_SRC_DIR)
set OUTDIR      $::env(POLICY_OUT_DIR)
set CHECKPOINT_CAPACITY      $::env(POLICY_CKPT_K)
set LOOKAHEAD_SHOTS    $::env(LOOKAHEAD_SHOTS)
set EXACT_PRUNE $::env(POLICY_SEARCH_MODE)

file mkdir $OUTDIR
read_verilog -include_dirs $SRC [list \
    $SRC/grover_policy.v \
    $SRC/grover_policy_ooc_top.v]

synth_design -top grover_policy_ooc_top -part $PART -mode out_of_context \
    -flatten_hierarchy rebuilt \
    -generic CHECKPOINT_CAPACITY=$CHECKPOINT_CAPACITY \
    -generic LOOKAHEAD_SHOTS=$LOOKAHEAD_SHOTS \
    -generic EXACT_PRUNE=$EXACT_PRUNE

create_clock -name policy_clk -period 10.000 [get_ports clk]
report_utilization -file $OUTDIR/util.rpt
report_utilization -hierarchical -file $OUTDIR/util_hier.rpt
report_timing_summary -delay_type max -max_paths 20 -file $OUTDIR/timing_synth.rpt
write_checkpoint -force $OUTDIR/policy_synth.dcp
