# Fresh implementation-strategy trial from a synthesized Vivado checkpoint.
#
# Environment:
#   INPUT_DCP        synthesized checkpoint
#   OUTDIR           isolated output directory
#   PLACE_DIRECTIVE  place_design directive
#   ROUTE_DIRECTIVE  route_design directive
#   TARGET_WNS       desired setup slack in ns
#
# This script changes physical implementation only. It intentionally leaves the
# RTL, policy decisions, and cycle behavior unchanged.

set input_dcp       $::env(INPUT_DCP)
set outdir          $::env(OUTDIR)
set place_directive $::env(PLACE_DIRECTIVE)
set route_directive $::env(ROUTE_DIRECTIVE)
set target_wns      $::env(TARGET_WNS)

file mkdir $outdir
open_checkpoint $input_dcp

# Match the platform implementation flow: clocks are asynchronous to each
# other, so only same-clock paths participate in timing closure.
set clock_list [all_clocks]
foreach clock_a $clock_list {
    foreach clock_b $clock_list {
        if {$clock_a ne $clock_b} {
            set_false_path -from [get_clocks $clock_a] -to [get_clocks $clock_b]
        }
    }
}

puts "PLACE_DIRECTIVE=$place_directive"
puts "ROUTE_DIRECTIVE=$route_directive"

opt_design
place_design -directive $place_directive
phys_opt_design -directive AggressiveExplore
route_design -directive $route_directive

# Give post-route physical optimization one recovery pass. route_design repairs
# only the connections changed by phys_opt_design.
phys_opt_design -directive AggressiveExplore
route_design -directive $route_directive

report_timing_summary -delay_type min_max -max_paths 100 \
    -report_unconstrained -check_timing_verbose \
    -file $outdir/route_timing_summary.rpt
report_utilization -file $outdir/route_util.rpt
report_route_status -file $outdir/route_status.rpt
write_checkpoint -force $outdir/routed.dcp

set worst_path [get_timing_paths -delay_type max -max_paths 1]
set final_wns [get_property SLACK $worst_path]
puts "FINAL_WNS=$final_wns"
puts "TARGET_WNS=$target_wns"

set result_file [open $outdir/result.txt w]
puts $result_file "PLACE_DIRECTIVE=$place_directive"
puts $result_file "ROUTE_DIRECTIVE=$route_directive"
puts $result_file "FINAL_WNS=$final_wns"
puts $result_file "TARGET_WNS=$target_wns"

if {$final_wns >= $target_wns} {
    write_bitstream -force \
        $outdir/bbht_grover_k3h3_e4_m3_fpga.arty-100t.bit
    puts "TARGET_MET=1"
    puts $result_file "TARGET_MET=1"
} else {
    puts "TARGET_MET=0"
    puts $result_file "TARGET_MET=0"
}

close $result_file
close_project
