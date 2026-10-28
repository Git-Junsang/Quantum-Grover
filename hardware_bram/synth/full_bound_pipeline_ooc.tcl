set k 5
set h 8
if {[info exists ::env(BOUND_K)]} { set k $::env(BOUND_K) }
if {[info exists ::env(BOUND_H)]} { set h $::env(BOUND_H) }
set root [file normalize [file join [file dirname [info script]] ../..]]
set out [file join $root hardware_bram/results/2026-10-26_policy_search_full40_seedfull]
file mkdir $out
read_verilog [file join $root hardware_bram/sim/full_bound_pipeline_estimate.v]
synth_design -top full_bound_pipeline_estimate -part xc7a100tcsg324-1 \
    -generic K=$k -generic H=$h
report_utilization -file [file join $out bound_pipe_k${k}h${h}_util.rpt]
report_timing_summary -file [file join $out bound_pipe_k${k}h${h}_timing.rpt]
exit
