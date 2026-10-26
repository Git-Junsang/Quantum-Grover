# Post-route timing recovery for an already implemented Vivado checkpoint.
#
# Environment:
#   INPUT_DCP  routed checkpoint to reopen
#   OUTDIR     isolated result directory
#   TARGET_WNS minimum setup slack required before bitstream generation (ns)

# This flow changes placement/routing only.  RTL, cycle behavior and the
# policy/measurement algorithms remain untouched.

set input_dcp $::env(INPUT_DCP)
set outdir    $::env(OUTDIR)
set target    $::env(TARGET_WNS)

file mkdir $outdir
open_checkpoint $input_dcp

# The first routed M3 result is already timing-clean but has little margin.
# AggressiveExplore focuses physical optimization on the routed critical paths;
# route_design then reconnects only the nets changed by phys_opt_design.
phys_opt_design -directive AggressiveExplore
route_design -directive AggressiveExplore

report_timing_summary -delay_type min_max -max_paths 100 \
    -report_unconstrained -check_timing_verbose \
    -file $outdir/route_timing_summary.rpt
report_utilization -file $outdir/route_util.rpt
report_route_status -file $outdir/route_status.rpt
write_checkpoint -force $outdir/routed_physopt.dcp

set worst_path [get_timing_paths -delay_type max -max_paths 1]
set final_wns [get_property SLACK $worst_path]
puts "FINAL_WNS=$final_wns"
puts "TARGET_WNS=$target"

if {$final_wns >= $target} {
    write_bitstream -force $outdir/bbht_grover_k3h3_e4_m3_fpga.arty-100t.bit
    puts "TARGET_MET=1"
} else {
    puts "TARGET_MET=0"
}

close_project
