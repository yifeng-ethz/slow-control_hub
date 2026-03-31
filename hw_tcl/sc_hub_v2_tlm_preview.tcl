# ============================================================================
# sc_hub_v2 — TLM Performance Preview
#
# Loads TLM experiment results from CSV files and generates HTML performance
# summaries for the Platform Designer GUI. The CSV files are produced by the
# Python discrete-event TLM model (see TLM_PLAN.md).
#
# Expected CSV directory: $IP_ROOT/tlm/results/csv/
#
# Called from sc_hub_v2_elaborate via:
#   sc_hub_v2_update_tlm_preview
#   sc_hub_v2_update_perf_plot
# ============================================================================

# ----------------------------------------------------------------------------
# CSV lookup infrastructure
# ----------------------------------------------------------------------------

# Resolve the TLM results directory relative to this script
proc sc_hub_v2_tlm_results_dir {} {
    set script_dir [file dirname [info script]]
    return [file normalize [file join $script_dir .. tlm results csv]]
}

# Load a CSV file into a list of dicts (first row = header)
proc sc_hub_v2_load_csv {filepath} {
    if {![file exists $filepath]} {
        return {}
    }
    set fh [open $filepath r]
    set lines [split [read $fh] "\n"]
    close $fh

    if {[llength $lines] < 2} {return {}}

    set header [split [lindex $lines 0] ","]
    set header [lmap h $header {string trim $h}]
    set result {}
    foreach line [lrange $lines 1 end] {
        set line [string trim $line]
        if {$line eq ""} continue
        set vals [split $line ","]
        set row [dict create]
        for {set i 0} {$i < [llength $header]} {incr i} {
            dict set row [lindex $header $i] \
                [string trim [lindex $vals $i]]
        }
        lappend result $row
    }
    return $result
}

# Filter CSV rows by matching a dict of {column value} pairs
proc sc_hub_v2_filter_csv {rows match_dict} {
    set result {}
    foreach row $rows {
        set ok 1
        dict for {col val} $match_dict {
            if {![dict exists $row $col] || [dict get $row $col] ne $val} {
                set ok 0
                break
            }
        }
        if {$ok} {lappend result $row}
    }
    return $result
}

# ----------------------------------------------------------------------------
# TLM data file catalog
# ----------------------------------------------------------------------------
# Each TLM experiment category produces a CSV with known columns.
# File names follow the pattern: <category>.csv
#
#   rate_latency.csv      — od, pld, bus_lat, offered_rate, throughput, avg_lat, p99_lat
#   ooo_speedup.csv       — od, pld, ooo, lat_dist, speedup, throughput
#   fragmentation.csv     — od, pld, burst_dist, frag_ratio, admit_fail_rate
#   credit_priority.csv   — od, pld, ir, ext_rate, int_lat_avg, int_lat_p99
#   ordering_overhead.csv — od, release_pct, burst_len, throughput_ratio
#   buffer_sizing.csv     — od, pld, bp, throughput, area_alm, area_m10k
# ----------------------------------------------------------------------------

# ----------------------------------------------------------------------------
# TLM summary HTML (Tab 4, group "TLM Performance Summary")
# ----------------------------------------------------------------------------
proc sc_hub_v2_update_tlm_preview {} {
    set results_dir [sc_hub_v2_tlm_results_dir]

    # Current parameter values for lookup
    set od   [get_parameter_value OUTSTANDING_LIMIT]
    set pld  [get_parameter_value EXT_DOWN_PLD_DEPTH]
    set ooo  [get_parameter_value OOO_ENABLE]
    set bus  [get_parameter_value BUS_TYPE]
    set mb   [get_parameter_value MAX_BURST]
    set ir   [get_parameter_value OUTSTANDING_INT_RESERVED]
    set ord  [get_parameter_value ORD_ENABLE]

    set html "<html>"

    # ---- Section 1: Rate-Latency summary ----
    set rl_file [file join $results_dir rate_latency.csv]
    set rl_data [sc_hub_v2_load_csv $rl_file]
    set rl_match [sc_hub_v2_filter_csv $rl_data [dict create od $od pld $pld]]

    if {[llength $rl_match] > 0} {
        append html "<h3>Rate-Latency (OD=$od, PLD=$pld)</h3>"
        append html "<table border='1' cellpadding='3' width='100%'>"
        append html "<tr><th>Bus Lat</th><th>Offered Rate</th>"
        append html "<th>Throughput</th><th>Avg Lat (cy)</th><th>P99 Lat (cy)</th></tr>"
        foreach row $rl_match {
            set bl  [sc_hub_v2_csv_get $row bus_lat "?"]
            set or  [sc_hub_v2_csv_get $row offered_rate "?"]
            set tp  [sc_hub_v2_csv_get $row throughput "?"]
            set al  [sc_hub_v2_csv_get $row avg_lat "?"]
            set p99 [sc_hub_v2_csv_get $row p99_lat "?"]
            append html "<tr><td>$bl</td><td>$or</td>"
            append html "<td><b>$tp</b></td><td>$al</td><td>$p99</td></tr>"
        }
        append html "</table><br/>"
    } else {
        append html "<h3>Rate-Latency</h3>"
        append html "<p><i>No TLM data for OD=$od, PLD=$pld. "
        append html "Run TLM RATE experiments or select a preset with existing data.</i></p>"
    }

    # ---- Section 2: OoO speedup summary ----
    set ooo_str [expr {$ooo ? "true" : "false"}]
    set ooo_file [file join $results_dir ooo_speedup.csv]
    set ooo_data [sc_hub_v2_load_csv $ooo_file]
    set ooo_match [sc_hub_v2_filter_csv $ooo_data [dict create od $od ooo $ooo_str]]

    if {[llength $ooo_match] > 0} {
        append html "<h3>OoO Speedup (OD=$od, OoO=$ooo_str)</h3>"
        append html "<table border='1' cellpadding='3' width='100%'>"
        append html "<tr><th>Latency Dist</th><th>Speedup</th><th>Throughput</th></tr>"
        foreach row $ooo_match {
            set ld [sc_hub_v2_csv_get $row lat_dist "?"]
            set su [sc_hub_v2_csv_get $row speedup "?"]
            set tp [sc_hub_v2_csv_get $row throughput "?"]
            # Color-code speedup
            set color "black"
            if {[string is double -strict $su] && $su > 1.5} {set color "green"}
            if {[string is double -strict $su] && $su < 1.05} {set color "#888"}
            append html "<tr><td>$ld</td><td style='color:$color'><b>${su}x</b></td>"
            append html "<td>$tp</td></tr>"
        }
        append html "</table><br/>"
    } else {
        set ooo_note ""
        if {!$ooo} {
            set ooo_note " OOO_ENABLE=false: in-order dispatch only."
        }
        if {$bus eq "AVALON" && $ooo} {
            set ooo_note " <b>Note:</b> OoO with AVMM provides limited benefit \
                          (Avalon-MM guarantees in-order read completion)."
        }
        append html "<h3>OoO Speedup</h3>"
        append html "<p><i>No TLM OoO data for OD=$od.$ooo_note</i></p>"
    }

    # ---- Section 3: Fragmentation summary ----
    set frag_file [file join $results_dir fragmentation.csv]
    set frag_data [sc_hub_v2_load_csv $frag_file]
    set frag_match [sc_hub_v2_filter_csv $frag_data [dict create od $od pld $pld]]

    if {[llength $frag_match] > 0} {
        append html "<h3>Payload Fragmentation (OD=$od, PLD=$pld)</h3>"
        append html "<table border='1' cellpadding='3' width='100%'>"
        append html "<tr><th>Burst Dist</th><th>Frag Ratio</th><th>Admit Fail Rate</th></tr>"
        foreach row $frag_match {
            set bd  [sc_hub_v2_csv_get $row burst_dist "?"]
            set fr  [sc_hub_v2_csv_get $row frag_ratio "?"]
            set af  [sc_hub_v2_csv_get $row admit_fail_rate "?"]
            set color "black"
            if {[string is double -strict $fr] && $fr > 0.5} {set color "orange"}
            if {[string is double -strict $af] && $af > 0.01} {set color "red"}
            append html "<tr><td>$bd</td><td style='color:$color'>$fr</td>"
            append html "<td style='color:$color'>$af</td></tr>"
        }
        append html "</table><br/>"
    } else {
        append html "<h3>Payload Fragmentation</h3>"
        append html "<p><i>No TLM fragmentation data for OD=$od, PLD=$pld.</i></p>"
    }

    # ---- Section 4: Credit & Priority summary ----
    set cred_file [file join $results_dir credit_priority.csv]
    set cred_data [sc_hub_v2_load_csv $cred_file]
    set cred_match [sc_hub_v2_filter_csv $cred_data [dict create od $od ir $ir]]

    if {[llength $cred_match] > 0} {
        append html "<h3>Internal Priority (OD=$od, INT_RESERVED=$ir)</h3>"
        append html "<table border='1' cellpadding='3' width='100%'>"
        append html "<tr><th>Ext Rate</th><th>Int Avg Lat (cy)</th><th>Int P99 Lat (cy)</th></tr>"
        foreach row $cred_match {
            set er  [sc_hub_v2_csv_get $row ext_rate "?"]
            set ia  [sc_hub_v2_csv_get $row int_lat_avg "?"]
            set ip  [sc_hub_v2_csv_get $row int_lat_p99 "?"]
            append html "<tr><td>$er</td><td>$ia</td><td>$ip</td></tr>"
        }
        append html "</table><br/>"
    } else {
        append html "<h3>Internal Priority</h3>"
        append html "<p><i>No TLM priority data for OD=$od, IR=$ir.</i></p>"
    }

    # ---- Section 5: Ordering overhead summary ----
    if {$ord} {
        set ord_file [file join $results_dir ordering_overhead.csv]
        set ord_data [sc_hub_v2_load_csv $ord_file]
        set ord_match [sc_hub_v2_filter_csv $ord_data [dict create od $od]]

        if {[llength $ord_match] > 0} {
            append html "<h3>Ordering Overhead (OD=$od)</h3>"
            append html "<table border='1' cellpadding='3' width='100%'>"
            append html "<tr><th>RELEASE %</th><th>Burst Len</th><th>Throughput Ratio</th></tr>"
            foreach row $ord_match {
                set rp [sc_hub_v2_csv_get $row release_pct "?"]
                set bl [sc_hub_v2_csv_get $row burst_len "?"]
                set tr [sc_hub_v2_csv_get $row throughput_ratio "?"]
                set color "black"
                if {[string is double -strict $tr] && $tr < 0.8} {set color "orange"}
                if {[string is double -strict $tr] && $tr < 0.5} {set color "red"}
                append html "<tr><td>$rp%</td><td>$bl</td>"
                append html "<td style='color:$color'><b>$tr</b></td></tr>"
            }
            append html "</table><br/>"
        } else {
            append html "<h3>Ordering Overhead</h3>"
            append html "<p><i>No TLM ordering data for OD=$od.</i></p>"
        }
    }

    # ---- TLM data provenance footer ----
    append html "<hr/><p style='font-size:10px; color:#888;'>"
    append html "TLM data from: <code>$results_dir</code><br/>"
    append html "Generated by sc_hub TLM model (TLM_PLAN.md). "
    append html "Re-run TLM experiments to update after parameter changes.</p>"
    append html "</html>"

    catch {set_display_item_property tlm_summary_html TEXT $html}

    # Update sub-group previews
    sc_hub_v2_update_rate_preview $rl_match $od $pld
    sc_hub_v2_update_frag_preview $frag_match $od $pld
    sc_hub_v2_update_ord_preview $ord $od
}

# Safe CSV column accessor
proc sc_hub_v2_csv_get {row col {default "?"}} {
    if {[dict exists $row $col]} {
        return [dict get $row $col]
    }
    return $default
}

# ----------------------------------------------------------------------------
# Rate-Latency detail (Tab 4, group "Rate-Latency Preview")
# ----------------------------------------------------------------------------
proc sc_hub_v2_update_rate_preview {rl_match od pld} {
    if {[llength $rl_match] == 0} {
        set html "<html><p><i>No rate-latency data available for OD=$od, PLD=$pld.<br/>"
        append html "Expected file: tlm/results/csv/rate_latency.csv</i></p></html>"
        catch {set_display_item_property tlm_rate_html TEXT $html}
        return
    }

    # Build an ASCII-art throughput bar chart (Platform Designer has no
    # native plotting, so we use HTML + monospace bars)
    set html "<html><h4>Throughput vs Bus Latency (OD=$od, PLD=$pld)</h4>"
    append html "<pre style='font-family:monospace; font-size:11px;'>"

    # Find max throughput for scaling
    set max_tp 0.0
    foreach row $rl_match {
        set tp [sc_hub_v2_csv_get $row throughput "0"]
        if {[string is double -strict $tp] && $tp > $max_tp} {
            set max_tp $tp
        }
    }
    if {$max_tp <= 0} {set max_tp 1.0}

    # Group by bus_lat, take first offered_rate entry per bus_lat
    set seen_lat [dict create]
    foreach row $rl_match {
        set bl [sc_hub_v2_csv_get $row bus_lat "?"]
        if {[dict exists $seen_lat $bl]} continue
        dict set seen_lat $bl 1

        set tp [sc_hub_v2_csv_get $row throughput "0"]
        set al [sc_hub_v2_csv_get $row avg_lat "?"]
        if {![string is double -strict $tp]} {set tp 0}

        set bar_len [expr {int(40.0 * $tp / $max_tp)}]
        if {$bar_len < 0} {set bar_len 0}
        set bar [string repeat "#" $bar_len]
        set pad [string repeat " " [expr {40 - $bar_len}]]

        append html [format "lat=%3s |%s%s| tp=%-8s avg=%s\n" \
            $bl $bar $pad $tp $al]
    }
    append html "</pre>"

    # TLM guidance callout
    append html "<p style='font-size:11px;'>"
    append html "<b>TLM SIZE-01 guidance:</b> Throughput knee at OD=4-8. "
    append html "Diminishing returns above OD=16 unless bus latency &gt;100cy."
    append html "</p></html>"

    catch {set_display_item_property tlm_rate_html TEXT $html}
}

# ----------------------------------------------------------------------------
# Fragmentation detail (Tab 4, group "Fragmentation Preview")
# ----------------------------------------------------------------------------
proc sc_hub_v2_update_frag_preview {frag_match od pld} {
    if {[llength $frag_match] == 0} {
        set html "<html><p><i>No fragmentation data for OD=$od, PLD=$pld.<br/>"
        append html "Expected file: tlm/results/csv/fragmentation.csv</i></p></html>"
        catch {set_display_item_property tlm_frag_html TEXT $html}
        return
    }

    set html "<html><h4>Fragmentation Analysis (OD=$od, PLD=$pld)</h4>"
    append html "<p>Linked-list payload RAM does <b>not</b> suffer from "
    append html "allocation failure due to fragmentation (non-contiguous "
    append html "allocation is supported). Fragmentation ratio measures "
    append html "the proportion of non-contiguous pointer hops.</p>"

    append html "<table border='1' cellpadding='3' width='100%'>"
    append html "<tr><th>Burst Distribution</th><th>Frag Ratio</th>"
    append html "<th>Admit Fail Rate</th><th>Assessment</th></tr>"

    foreach row $frag_match {
        set bd [sc_hub_v2_csv_get $row burst_dist "?"]
        set fr [sc_hub_v2_csv_get $row frag_ratio "0"]
        set af [sc_hub_v2_csv_get $row admit_fail_rate "0"]

        set assess "OK"
        set color "green"
        if {[string is double -strict $fr] && $fr > 0.3} {
            set assess "Moderate fragmentation"
            set color "orange"
        }
        if {[string is double -strict $af] && $af > 0.0} {
            set assess "Admission failures — increase PLD depth"
            set color "red"
        }

        append html "<tr><td>$bd</td><td>$fr</td><td>$af</td>"
        append html "<td style='color:$color'><b>$assess</b></td></tr>"
    }
    append html "</table>"

    append html "<p style='font-size:11px;'>"
    append html "<b>TLM FRAG guidance:</b> Bimodal bursts (alternating L=1 and L=256) "
    append html "are the worst case. PLD &ge; 2 x MAX_BURST eliminates admit failures "
    append html "under bimodal traffic."
    append html "</p></html>"

    catch {set_display_item_property tlm_frag_html TEXT $html}
}

# ----------------------------------------------------------------------------
# Ordering overhead detail (Tab 4, group "Ordering Overhead Preview")
# ----------------------------------------------------------------------------
proc sc_hub_v2_update_ord_preview {ord_enable od} {
    if {!$ord_enable} {
        set html "<html><p>ORD_ENABLE=false: ordering tracker not synthesized. "
        append html "All transactions treated as RELAXED with zero ordering overhead.</p></html>"
        catch {set_display_item_property tlm_ord_html TEXT $html}
        return
    }

    set results_dir [sc_hub_v2_tlm_results_dir]
    set ord_file [file join $results_dir ordering_overhead.csv]
    set ord_data [sc_hub_v2_load_csv $ord_file]
    set ord_match [sc_hub_v2_filter_csv $ord_data [dict create od $od]]

    if {[llength $ord_match] == 0} {
        set html "<html><p><i>No ordering overhead data for OD=$od.<br/>"
        append html "Expected file: tlm/results/csv/ordering_overhead.csv</i></p></html>"
        catch {set_display_item_property tlm_ord_html TEXT $html}
        return
    }

    set html "<html><h4>Ordering Overhead (OD=$od, ORD_ENABLE=true)</h4>"
    append html "<p>Throughput ratio = throughput_with_ordering / throughput_relaxed_only. "
    append html "Values near 1.0 indicate negligible overhead.</p>"

    # ASCII bar chart
    append html "<pre style='font-family:monospace; font-size:11px;'>"
    foreach row $ord_match {
        set rp [sc_hub_v2_csv_get $row release_pct "?"]
        set bl [sc_hub_v2_csv_get $row burst_len "?"]
        set tr [sc_hub_v2_csv_get $row throughput_ratio "0"]
        if {![string is double -strict $tr]} {set tr 0}

        set bar_len [expr {int(40.0 * $tr)}]
        if {$bar_len < 0} {set bar_len 0}
        if {$bar_len > 40} {set bar_len 40}
        set bar [string repeat "#" $bar_len]
        set pad [string repeat " " [expr {40 - $bar_len}]]

        append html [format "REL=%2s%% L=%3s |%s%s| ratio=%s\n" \
            $rp $bl $bar $pad $tr]
    }
    append html "</pre>"

    append html "<p style='font-size:11px;'>"
    append html "<b>TLM ORD guidance:</b> At 5% RELEASE, L=1: ~5% throughput loss. "
    append html "At 50% RELEASE (pathological): effective OD=1, severe degradation. "
    append html "Cross-domain traffic is independent (domain 0 drain does not block domain 1)."
    append html "</p></html>"

    catch {set_display_item_property tlm_ord_html TEXT $html}
}

# ----------------------------------------------------------------------------
# BDF performance plot reference
# ----------------------------------------------------------------------------
# Platform Designer supports .bdf schematic symbols. We generate a reference
# to a parameterized .bdf that encodes the current config as a visual block
# diagram with key performance numbers annotated.
#
# The .bdf is pre-generated per preset by syn/generate_bdf.tcl.
# Here we just update the GUI to point to the right one.
# ----------------------------------------------------------------------------
proc sc_hub_v2_update_perf_plot {} {
    set preset [get_parameter_value PRESET]
    set script_dir [file dirname [info script]]
    set bdf_dir [file normalize [file join $script_dir .. syn bdf]]

    # Map preset to BDF file
    set bdf_name "sc_hub_v2_perf_[string tolower $preset].bdf"
    set bdf_path [file join $bdf_dir $bdf_name]

    set od  [get_parameter_value OUTSTANDING_LIMIT]
    set pld [get_parameter_value EXT_DOWN_PLD_DEPTH]
    set ooo [get_parameter_value OOO_ENABLE]
    set bus [get_parameter_value BUS_TYPE]
    set mb  [get_parameter_value MAX_BURST]

    set html "<html>"

    if {[file exists $bdf_path]} {
        append html "<h4>Performance Block Diagram</h4>"
        append html "<p>BDF schematic with annotated TLM performance: "
        append html "<code>$bdf_path</code></p>"
        append html "<p>Open in Platform Designer Schematic Editor to view "
        append html "the parameterized block diagram with throughput/latency "
        append html "annotations per submodule.</p>"
    } else {
        append html "<h4>Performance Block Diagram</h4>"
        append html "<p><i>No pre-generated BDF for preset '$preset'.<br/>"
        append html "Run <code>syn/generate_bdf.tcl</code> to create BDF files "
        append html "for all presets.</i></p>"
    }

    # Always show a text-based performance summary
    append html "<h4>Configuration Performance Summary</h4>"
    append html "<table border='1' cellpadding='3' width='100%'>"
    append html "<tr><th>Parameter</th><th>Value</th><th>TLM Impact</th></tr>"

    # Outstanding depth impact
    set od_impact "Throughput knee"
    if {$od <= 2} {set od_impact "Low throughput — consider OD=4+"}
    if {$od >= 16} {set od_impact "Diminishing returns unless bus_lat>100cy"}
    append html "<tr><td>OUTSTANDING_LIMIT</td><td>$od</td><td>$od_impact</td></tr>"

    # Payload depth impact
    set pld_impact "Adequate for MAX_BURST=$mb"
    if {$pld < $mb} {
        set pld_impact "<span style='color:red'>PLD &lt; MAX_BURST: burst stall risk</span>"
    }
    if {$pld >= [expr {4 * $mb}]} {
        set pld_impact "Generous — low fragmentation risk"
    }
    append html "<tr><td>EXT_DOWN_PLD_DEPTH</td><td>$pld</td><td>$pld_impact</td></tr>"

    # OoO impact
    set ooo_impact "In-order dispatch"
    if {$ooo && $bus eq "AXI4"} {
        set ooo_impact "<span style='color:green'>1.3-3.0x speedup (TLM OOO-01..06)</span>"
    }
    if {$ooo && $bus eq "AVALON"} {
        set ooo_impact "<span style='color:orange'>Limited benefit with AVMM</span>"
    }
    append html "<tr><td>OOO_ENABLE</td><td>$ooo</td><td>$ooo_impact</td></tr>"

    # Bus type impact
    set bus_impact "Standard in-order completion"
    if {$bus eq "AXI4"} {
        set bus_impact "Supports OoO completion, per-ID tracking"
    }
    append html "<tr><td>BUS_TYPE</td><td>$bus</td><td>$bus_impact</td></tr>"

    # Max burst impact
    set mb_impact "Full Mu3e SC burst range"
    if {$mb <= 4} {
        set mb_impact "CSR-only operation (no bulk transfer)"
    }
    if {$mb <= 64} {
        set mb_impact "Limited bulk — large histogram reads will be split"
    }
    append html "<tr><td>MAX_BURST</td><td>$mb</td><td>$mb_impact</td></tr>"

    append html "</table></html>"

    # We reuse the TLM summary area since there is no dedicated perf_plot
    # display item. The BDF reference is informational.
    # The actual plot is the pre-generated .bdf file opened externally.
}
