# Read-only post-synthesis audit. Source this after synth_design while the
# synthesized design is still open. No constraints or netlist cells change.
namespace eval ::policy_cache_audit {
    proc csv_quote {value} {
        set escaped [string map [list "\"" "\"\"" "\n" " " "\r" " "] $value]
        return "\"${escaped}\""
    }

    proc collect {directory} {
        file mkdir $directory
        set destination [file join $directory policy_cache_memory.csv]
        set stream [open "${destination}.tmp" w]
        puts $stream "region,instance,reference,primitive_kind"
        set count 0
        # Generate-bank names identify the candidate arrays in the banked RTL.
        # Memo arrays are recorded separately. A hierarchy utilization total
        # cannot distinguish these arrays from the rest of the solver.
        set cells [get_cells -quiet -hierarchical -filter {NAME =~ *g_cache_bank* || NAME =~ *memo_*}]
        foreach cell $cells {
            set name [get_property NAME $cell]
            set reference [get_property REF_NAME $cell]
            if {[string match *g_cache_bank* $name]} {
                set region candidate_cache
            } elseif {[regexp {memo_(epoch|mask|depth|cost)} $name]} {
                set region memo
            } else {
                continue
            }
            switch -glob -- $reference {
                RAMB36* { set kind ramb36 }
                RAMB18* { set kind ramb18 }
                RAM* { set kind distributed_ram_primitive }
                FD* { set kind named_flip_flop }
                LUT* { set kind named_logic_lut }
                SRL* { set kind named_shift_register }
                default { continue }
            }
            set fields [list]
            foreach field [list $region $name $reference $kind] {
                lappend fields [csv_quote $field]
            }
            puts $stream [join $fields ,]
            incr count
        }
        close $stream
        file rename -force "${destination}.tmp" $destination

        # Native per-memory reporting is an independent attribution aid. Its
        # absence or a report failure must not fail the caller's synthesis.
        set native_status unavailable
        if {[llength [info commands report_ram_utilization]] != 0} {
            if {[catch {report_ram_utilization -file [file join $directory ram_utilization.rpt]} detail]} {
                set native_status "failed: $detail"
            } else {
                set native_status written
            }
        }
        set stream [open [file join $directory policy_cache_audit_status.txt] w]
        puts $stream "named_primitive_rows=$count"
        puts $stream "native_ram_report=$native_status"
        puts $stream "RAMB counts are physical primitives attributed by array names."
        puts $stream "Named LUT/FF cells are not a complete cache-control area attribution."
        puts $stream "Distributed RAM primitive counts are not LUT counts."
        close $stream
        puts "POLICY_CACHE_AUDIT: $count named primitive rows written to $destination"
    }
}
