# ============================================================================
# sc_hub_v2 — Resource Estimation and Reporting
#
# Looks up ALM/M10K/M20K resource estimates from a synthesis result database
# and generates HTML summaries for the Platform Designer GUI.
#
# Synthesis database: $IP_ROOT/syn/resource_db.tcl
#   Populated by standalone synthesis runs (one per preset).
#   Format: Tcl dict mapping preset_name -> {alm M10K M20K fmax modules{...}}
#
# Called from sc_hub_v2_elaborate via:
#   sc_hub_v2_update_resource_estimate
# ============================================================================

# ----------------------------------------------------------------------------
# Resource database infrastructure
# ----------------------------------------------------------------------------

# Load the synthesis resource database
proc sc_hub_v2_load_resource_db {} {
    variable SC_HUB_V2_RESOURCE_DB

    set script_dir [file dirname [info script]]
    set db_file [file normalize [file join $script_dir .. syn resource_db.tcl]]

    if {[file exists $db_file]} {
        # resource_db.tcl defines: set SC_HUB_V2_RESOURCE_DB { ... }
        if {[catch {source $db_file} err]} {
            set SC_HUB_V2_RESOURCE_DB [dict create]
        }
    } else {
        set SC_HUB_V2_RESOURCE_DB [dict create]
    }
}

# Get resource data for a preset (returns dict or empty)
proc sc_hub_v2_get_resources {preset_name} {
    variable SC_HUB_V2_RESOURCE_DB

    if {![info exists SC_HUB_V2_RESOURCE_DB]} {
        sc_hub_v2_load_resource_db
    }

    if {[dict exists $SC_HUB_V2_RESOURCE_DB $preset_name]} {
        return [dict get $SC_HUB_V2_RESOURCE_DB $preset_name]
    }
    return {}
}

# ----------------------------------------------------------------------------
# Analytical resource estimation (fallback when no synthesis data)
# ----------------------------------------------------------------------------
# These are rough estimates based on known FPGA resource consumption patterns
# for FIFO-based designs on Intel MAX10 / Cyclone V.

proc sc_hub_v2_estimate_resources {} {
    set od   [get_parameter_value OUTSTANDING_LIMIT]
    set pld  [get_parameter_value EXT_DOWN_PLD_DEPTH]
    set ipld [get_parameter_value INT_DOWN_PLD_DEPTH]
    set upld [get_parameter_value EXT_UP_PLD_DEPTH]
    set iupld [get_parameter_value INT_UP_PLD_DEPTH]
    set bp   [get_parameter_value BP_FIFO_DEPTH]
    set ihd  [get_parameter_value INT_HDR_DEPTH]
    set ooo  [get_parameter_value OOO_ENABLE]
    set ord  [get_parameter_value ORD_ENABLE]
    set nd   [get_parameter_value ORD_NUM_DOMAINS]
    set atm  [get_parameter_value ATOMIC_ENABLE]
    set sf   [get_parameter_value S_AND_F_ENABLE]
    set cap  [get_parameter_value HUB_CAP_ENABLE]
    set bus  [get_parameter_value BUS_TYPE]
    set dbg  [get_parameter_value DEBUG]

    # ---- M10K blocks (each M10K = 10240 bits = 256x40 or 512x20 or 1024x10) ----
    # Payload RAMs: 32-bit wide -> 256 words per M10K
    set m10k_ext_down [expr {int(ceil(double($pld) / 256.0))}]
    set m10k_int_down [expr {int(ceil(double($ipld) / 256.0))}]
    set m10k_ext_up   [expr {int(ceil(double($upld) / 256.0))}]
    set m10k_int_up   [expr {int(ceil(double($iupld) / 256.0))}]

    # Header FIFOs: ~80 bits wide -> 128 entries per M10K
    set m10k_ext_hdr  [expr {int(ceil(double($od) / 128.0)) * 2}]
    set m10k_int_hdr  [expr {int(ceil(double($ihd) / 128.0)) * 2}]

    # BP FIFO: 36-bit wide -> 256 entries per M10K
    set m10k_bp [expr {int(ceil(double($bp) / 256.0))}]

    # Cmd/reply order FIFO, free lists
    set m10k_ctrl [expr {int(ceil(double($od) / 256.0)) * 2 + 2}]

    # OoO scoreboard: $od entries x ~32 bits
    set m10k_ooo 0
    if {$ooo} {
        set m10k_ooo [expr {int(ceil(double($od) / 256.0)) + 1}]
    }

    # Ordering domain state: $nd x 48 bits (fits in registers, but may use M10K if nd=16)
    set m10k_ord 0
    if {$ord && $nd > 8} {
        set m10k_ord 1
    }

    set m10k_total [expr {$m10k_ext_down + $m10k_int_down + $m10k_ext_up + $m10k_int_up \
        + $m10k_ext_hdr + $m10k_int_hdr + $m10k_bp + $m10k_ctrl + $m10k_ooo + $m10k_ord}]

    # ---- ALMs (rough estimates based on control logic complexity) ----
    # Base core: pkt_rx + pkt_tx + classifier + dispatch FSM + reply assembler
    set alm_base 450

    # Bus handler
    set alm_bus 120
    if {$bus eq "AXI4"} {set alm_bus 200}

    # Malloc/free (4 pools, linked-list management)
    set alm_malloc [expr {80 + 10 * [sc_hub_v2_clog2 $pld]}]

    # Admission control
    set alm_admit 60

    # Credit manager
    set alm_credit 50

    # S&F validator
    set alm_sf 0
    if {$sf} {set alm_sf 40}

    # OoO scoreboard + reorder
    set alm_ooo 0
    if {$ooo} {set alm_ooo [expr {80 + 4 * $od}]}

    # Ordering tracker
    set alm_ord 0
    if {$ord} {set alm_ord [expr {60 + 6 * $nd}]}

    # Atomic RMW sequencer
    set alm_atm 0
    if {$atm} {set alm_atm 45}

    # HUB_CAP register
    set alm_cap 0
    if {$cap} {set alm_cap 10}

    # CSR register file
    set alm_csr [expr {80 + 10 * $dbg}]

    # Debug counters
    set alm_debug [expr {20 * $dbg}]

    set alm_total [expr {$alm_base + $alm_bus + $alm_malloc + $alm_admit \
        + $alm_credit + $alm_sf + $alm_ooo + $alm_ord + $alm_atm \
        + $alm_cap + $alm_csr + $alm_debug}]

    # Build result dict
    set modules [dict create \
        core        [dict create alm $alm_base m10k 0] \
        bus_handler [dict create alm $alm_bus m10k 0] \
        malloc      [dict create alm $alm_malloc m10k [expr {$m10k_ctrl}]] \
        pld_ram     [dict create alm 0 m10k [expr {$m10k_ext_down + $m10k_int_down + $m10k_ext_up + $m10k_int_up}]] \
        hdr_fifo    [dict create alm 20 m10k [expr {$m10k_ext_hdr + $m10k_int_hdr}]] \
        bp_fifo     [dict create alm 15 m10k $m10k_bp] \
        admit_ctrl  [dict create alm $alm_admit m10k 0] \
        credit_mgr  [dict create alm $alm_credit m10k 0] \
        sf_valid    [dict create alm $alm_sf m10k 0] \
        ooo_score   [dict create alm $alm_ooo m10k $m10k_ooo] \
        ord_tracker [dict create alm $alm_ord m10k $m10k_ord] \
        atomic_seq  [dict create alm $alm_atm m10k 0] \
        csr_regs    [dict create alm $alm_csr m10k 0] \
        hub_cap     [dict create alm $alm_cap m10k 0] \
        debug       [dict create alm $alm_debug m10k 0] \
    ]

    return [dict create alm $alm_total m10k $m10k_total m20k 0 \
        fmax "N/A (estimate)" modules $modules source "analytical"]
}

# ----------------------------------------------------------------------------
# Resource summary HTML (Tab 5, group "Resource Summary")
# ----------------------------------------------------------------------------
proc sc_hub_v2_update_resource_estimate {} {
    set preset [get_parameter_value PRESET]

    # Try synthesis database first, fall back to analytical estimate
    set res [sc_hub_v2_get_resources $preset]
    if {[llength $res] == 0 || $res eq ""} {
        set res [sc_hub_v2_estimate_resources]
    }

    set alm    [dict get $res alm]
    set m10k   [dict get $res m10k]
    set m20k   [dict get $res m20k]
    set fmax   [dict get $res fmax]
    set source [dict get $res source]

    # Main summary
    set src_note ""
    if {$source eq "analytical"} {
        set src_note " <span style='color:orange'>(analytical estimate — run synthesis for accurate numbers)</span>"
    } else {
        set src_note " <span style='color:green'>(from synthesis database)</span>"
    }

    set html "<html><h3>Resource Estimate: $preset</h3>"
    append html "<p>Data source: <b>$source</b>$src_note</p>"
    append html "<table border='1' cellpadding='4' width='60%'>"
    append html "<tr><th>Resource</th><th>Used</th><th>Notes</th></tr>"
    append html "<tr><td><b>ALMs</b></td><td><b>[sc_hub_v2_format_int $alm]</b></td>"
    append html "<td>Logic elements (combinational + register)</td></tr>"
    append html "<tr><td><b>M10K Blocks</b></td><td><b>$m10k</b></td>"
    append html "<td>10 Kbit embedded memory blocks</td></tr>"
    append html "<tr><td><b>M20K Blocks</b></td><td><b>$m20k</b></td>"
    append html "<td>20 Kbit blocks (Cyclone V / Arria 10)</td></tr>"
    append html "<tr><td><b>Fmax</b></td><td><b>$fmax</b></td>"
    append html "<td>Target: 156.25 MHz (Mu3e SC clock)</td></tr>"
    append html "</table>"

    # Area budget context
    append html "<p style='font-size:11px;'>"
    append html "<b>MAX10 10M50 budget:</b> 50,000 LEs (~25,000 ALMs), "
    append html "182 M9K blocks. sc_hub_v2 target: &lt;5% of total."
    append html "</p></html>"

    catch {set_display_item_property resource_summary_html TEXT $html}

    # Module breakdown
    sc_hub_v2_update_resource_breakdown $res

    # Preset comparison
    sc_hub_v2_update_resource_comparison $preset
}

# ----------------------------------------------------------------------------
# Module-level breakdown (Tab 5, group "Breakdown by Module")
# ----------------------------------------------------------------------------
proc sc_hub_v2_update_resource_breakdown {res} {
    if {![dict exists $res modules]} {
        set html "<html><p><i>No module breakdown available.</i></p></html>"
        catch {set_display_item_property resource_breakdown_html TEXT $html}
        return
    }

    set modules [dict get $res modules]
    set total_alm [dict get $res alm]
    set total_m10k [dict get $res m10k]
    if {$total_alm <= 0} {set total_alm 1}
    if {$total_m10k <= 0} {set total_m10k 1}

    set html "<html><h4>Resource Breakdown by Module</h4>"
    append html "<table border='1' cellpadding='3' width='100%'>"
    append html "<tr><th>Module</th><th>ALMs</th><th>%</th>"
    append html "<th>M10K</th><th>%</th><th>Bar</th></tr>"

    dict for {name data} $modules {
        set a [dict get $data alm]
        set m [dict get $data m10k]
        set a_pct [format "%.1f" [expr {100.0 * $a / $total_alm}]]
        set m_pct [format "%.1f" [expr {100.0 * $m / $total_m10k}]]

        # ASCII bar for ALM proportion
        set bar_len [expr {int(20.0 * $a / $total_alm)}]
        if {$bar_len < 0} {set bar_len 0}
        set bar [string repeat "#" $bar_len]

        append html "<tr><td><b>$name</b></td>"
        append html "<td align='right'>$a</td><td align='right'>$a_pct%</td>"
        append html "<td align='right'>$m</td><td align='right'>$m_pct%</td>"
        append html "<td><code>$bar</code></td></tr>"
    }

    append html "<tr style='font-weight:bold; background:#eee;'>"
    append html "<td>TOTAL</td>"
    append html "<td align='right'>$total_alm</td><td align='right'>100%</td>"
    append html "<td align='right'>$total_m10k</td><td align='right'>100%</td>"
    append html "<td></td></tr>"
    append html "</table></html>"

    catch {set_display_item_property resource_breakdown_html TEXT $html}
}

# ----------------------------------------------------------------------------
# Preset comparison (Tab 5, group "Comparison with Other Presets")
# ----------------------------------------------------------------------------
proc sc_hub_v2_update_resource_comparison {current_preset} {
    variable SC_HUB_V2_PRESETS

    set html "<html><h4>Resource Comparison Across Presets</h4>"
    append html "<table border='1' cellpadding='3' width='100%'>"
    append html "<tr><th>Preset</th><th>ALMs</th><th>M10K</th>"
    append html "<th>OoO</th><th>ORD</th><th>ATM</th><th>Bar (ALM)</th></tr>"

    # Collect all resource data
    set max_alm 1
    set preset_data {}
    foreach name [sc_hub_v2_get_preset_names] {
        set res [sc_hub_v2_get_resources $name]
        if {[llength $res] == 0 || $res eq ""} {
            # Use analytical estimate for this preset's params
            # We can only estimate for the currently loaded preset
            if {$name eq $current_preset} {
                set res [sc_hub_v2_estimate_resources]
            } else {
                set res [dict create alm "?" m10k "?" m20k "?" fmax "?" source "no data"]
            }
        }
        lappend preset_data [list $name $res]
        if {[dict exists $res alm] && [string is integer -strict [dict get $res alm]]} {
            set a [dict get $res alm]
            if {$a > $max_alm} {set max_alm $a}
        }
    }

    foreach entry $preset_data {
        lassign $entry name res
        set a [dict get $res alm]
        set m [dict get $res m10k]

        # Get feature flags from preset
        set ooo_str "-"
        set ord_str "-"
        set atm_str "-"
        if {[info exists SC_HUB_V2_PRESETS] && [dict exists $SC_HUB_V2_PRESETS $name]} {
            set p [dict get $SC_HUB_V2_PRESETS $name]
            if {[dict get $p OOO_ENABLE]} {set ooo_str "Y"}
            if {[dict get $p ORD_ENABLE]} {set ord_str "Y"}
            if {[dict get $p ATOMIC_ENABLE]} {set atm_str "Y"}
        }

        # Highlight current preset
        set style ""
        if {$name eq $current_preset} {
            set style " style='background:#ffe0b0; font-weight:bold;'"
        }

        # Bar
        set bar ""
        if {[string is integer -strict $a]} {
            set bar_len [expr {int(20.0 * $a / $max_alm)}]
            if {$bar_len < 1 && $a > 0} {set bar_len 1}
            set bar [string repeat "#" $bar_len]
        }

        append html "<tr$style><td>$name</td><td align='right'>$a</td>"
        append html "<td align='right'>$m</td>"
        append html "<td align='center'>$ooo_str</td>"
        append html "<td align='center'>$ord_str</td>"
        append html "<td align='center'>$atm_str</td>"
        append html "<td><code>$bar</code></td></tr>"
    }

    append html "</table>"
    append html "<p style='font-size:11px;'>"
    append html "Highlighted row = currently selected preset. "
    append html "Run <code>syn/run_all_presets.sh</code> to populate synthesis data for all presets."
    append html "</p></html>"

    catch {set_display_item_property resource_compare_html TEXT $html}
}
