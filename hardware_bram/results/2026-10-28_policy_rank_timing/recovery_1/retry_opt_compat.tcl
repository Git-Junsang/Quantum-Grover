# Compatibility for the already-submitted retry controller only.
# No clock, pin, timing exception, or design object is changed here.
if {[llength [info commands bbht_original_opt_design]] == 0} {
    rename opt_design bbht_original_opt_design
    proc opt_design {args} {
        set at [lsearch -exact $args -directive]
        if {$at >= 0 && [lindex $args [expr {$at+1}]] eq "AggressiveExplore"} {
            lset args [expr {$at+1}] ExploreWithRemap
        }
        return [uplevel 1 [list bbht_original_opt_design {*}$args]]
    }
}
