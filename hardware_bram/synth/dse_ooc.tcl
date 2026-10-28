# Called from sim/dse.py with an immutable source snapshot and one cell's
# parameterized adapter.  OOC reports constrain only the accelerator clock;
# they do not prove full RVX SoC timing, CDC or board I/O timing.
set src $::env(DSE_SRC)
set cell $::env(DSE_CELL)
set out $::env(DSE_OUT)
file mkdir $out
set_param general.maxThreads 1
set files [list]
foreach name {
    bbht_grover_main_ip.v grover_arithmetic.v grover_bbht.v grover_checkpoint.v
    grover_iteration.v grover_loader.v grover_measurement.v grover_memories.v
    grover_policy.v grover_status.v bbht_rvx_wrapper.v bbht_grover_mmio.v bbht_ahb_loader.v
} { lappend files [file join $src $name] }
lappend files [file join $cell adapter.v]
if {$::env(DSE_STAGE) eq "synth"} {
    read_verilog $files
    read_verilog -sv [list $src/grover_parallel.sv $src/grover_policy_parameterized.sv]
    synth_design -top bbht_rvx_wrapper -part $::env(DSE_PART) \
        -mode out_of_context -flatten_hierarchy rebuilt -include_dirs $src
    create_clock -name accel_clk -period $::env(DSE_CLOCK_NS) [get_ports clk]
    report_utilization -file [file join $out util.rpt]
    report_timing_summary -file [file join $out timing.rpt]
    write_checkpoint -force [file join $out synth.dcp]
} else {
    open_checkpoint [file join $cell synth synth.dcp]
    opt_design
    place_design
    phys_opt_design
    route_design
    report_utilization -file [file join $out util.rpt]
    report_timing_summary -delay_type min_max -report_unconstrained \
        -file [file join $out timing.rpt]
    report_route_status -file [file join $out route_status.rpt]
    write_checkpoint -force [file join $out route.dcp]
    # Machine-readable metrics come from Vivado objects, avoiding version-
    # dependent timing-table parsing.  Negative hold/setup slack is preserved.
    set setup_paths [get_timing_paths -delay_type max -max_paths 1]
    set hold_paths [get_timing_paths -delay_type min -max_paths 1]
    if {[llength $setup_paths] == 0 || [llength $hold_paths] == 0} {
        error "No clocked paths found in OOC implementation"
    }
    set f [open [file join $out slack.csv] w]
    puts $f "wns_ns,whs_ns"
    puts $f "[get_property SLACK $setup_paths],[get_property SLACK $hold_paths]"
    close $f
}
