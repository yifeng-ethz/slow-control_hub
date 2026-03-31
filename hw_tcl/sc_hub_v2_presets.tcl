# ============================================================================
# sc_hub_v2 — Preset Matrix
#
# Each preset is a named configuration that sets all parameters to known-good
# values for a specific use case. The preset matrix spans:
#
#   Axis 1: Platform   — FEB_SCIFI, FEB_MUPIX, FEB_TILES, GENERIC
#   Axis 2: Features   — DEFAULT (basic), OOO, ORDERED, FULL (all features)
#   Axis 3: Area tier  — MINIMAL, BALANCED, MAX_THROUGHPUT
#   Axis 4: (implicit) — Speed grade derived from platform
#
# Presets are NOT saved to .prst files (those don't work reliably in Platform
# Designer 18.1). Instead, selecting a preset in the GUI triggers the
# elaboration callback to set all parameters atomically.
#
# Synthesis resource estimates (ALM, M10K, M20K) are looked up from
# syn/resource_db.tcl, which is populated by standalone synthesis runs.
# ============================================================================

# ----------------------------------------------------------------------------
# Preset database: dict mapping preset name -> parameter dict
# ----------------------------------------------------------------------------

# Helper: define a preset as a flat dict
proc sc_hub_v2_define_preset {name desc params} {
    variable SC_HUB_V2_PRESETS
    variable SC_HUB_V2_PRESET_DESC
    dict set SC_HUB_V2_PRESETS $name $params
    dict set SC_HUB_V2_PRESET_DESC $name $desc
}

variable SC_HUB_V2_PRESETS [dict create]
variable SC_HUB_V2_PRESET_DESC [dict create]

# ============================================================================
# FEB_SCIFI presets — SciFi frontend board (MAX10 10M50, moderate resources)
# ============================================================================

sc_hub_v2_define_preset "FEB_SCIFI_DEFAULT" \
    "SciFi FEB: AVMM, in-order, ordering enabled, atomic enabled. \
     Balanced area/throughput for typical SC polling (40% CSR reads, \
     15% histogram bursts). This is the production default." \
    {
        BUS_TYPE            AVALON
        ADDR_WIDTH          16
        OUTSTANDING_LIMIT   8
        OUTSTANDING_INT_RESERVED 2
        EXT_DOWN_PLD_DEPTH  512
        INT_DOWN_PLD_DEPTH  64
        EXT_UP_PLD_DEPTH    512
        INT_UP_PLD_DEPTH    64
        INT_HDR_DEPTH       4
        MAX_BURST           256
        BP_FIFO_DEPTH       512
        OOO_ENABLE          false
        ORD_ENABLE          true
        ORD_NUM_DOMAINS     16
        ATOMIC_ENABLE       true
        S_AND_F_ENABLE      true
        HUB_CAP_ENABLE      true
        RD_TIMEOUT_CYCLES   1024
        WR_TIMEOUT_CYCLES   1024
        AXI4_USER_WIDTH     16
        AXI4_ID_WIDTH       4
        DEBUG               1
    }

sc_hub_v2_define_preset "FEB_SCIFI_OOO" \
    "SciFi FEB: AXI4, OoO enabled, ordering, atomic. For systems with \
     high-variance slave latency (frame_rcv: 4-12cy, ring_buf_cam: 8-20cy). \
     TLM predicts 1.3-1.8x throughput improvement over in-order." \
    {
        BUS_TYPE            AXI4
        ADDR_WIDTH          16
        OUTSTANDING_LIMIT   8
        OUTSTANDING_INT_RESERVED 2
        EXT_DOWN_PLD_DEPTH  512
        INT_DOWN_PLD_DEPTH  64
        EXT_UP_PLD_DEPTH    512
        INT_UP_PLD_DEPTH    64
        INT_HDR_DEPTH       4
        MAX_BURST           256
        BP_FIFO_DEPTH       512
        OOO_ENABLE          true
        ORD_ENABLE          true
        ORD_NUM_DOMAINS     16
        ATOMIC_ENABLE       true
        S_AND_F_ENABLE      true
        HUB_CAP_ENABLE      true
        RD_TIMEOUT_CYCLES   1024
        WR_TIMEOUT_CYCLES   1024
        AXI4_USER_WIDTH     16
        AXI4_ID_WIDTH       4
        DEBUG               1
    }

sc_hub_v2_define_preset "FEB_SCIFI_ORDERED" \
    "SciFi FEB: AVMM, in-order, full ordering (16 domains), atomic. \
     Same as DEFAULT. Explicit name for software teams that need ordering \
     contract guarantees documented in ORDERING_GUIDE.md." \
    {
        BUS_TYPE            AVALON
        ADDR_WIDTH          16
        OUTSTANDING_LIMIT   8
        OUTSTANDING_INT_RESERVED 2
        EXT_DOWN_PLD_DEPTH  512
        INT_DOWN_PLD_DEPTH  64
        EXT_UP_PLD_DEPTH    512
        INT_UP_PLD_DEPTH    64
        INT_HDR_DEPTH       4
        MAX_BURST           256
        BP_FIFO_DEPTH       512
        OOO_ENABLE          false
        ORD_ENABLE          true
        ORD_NUM_DOMAINS     16
        ATOMIC_ENABLE       true
        S_AND_F_ENABLE      true
        HUB_CAP_ENABLE      true
        RD_TIMEOUT_CYCLES   1024
        WR_TIMEOUT_CYCLES   1024
        AXI4_USER_WIDTH     16
        AXI4_ID_WIDTH       4
        DEBUG               1
    }

sc_hub_v2_define_preset "FEB_SCIFI_FULL" \
    "SciFi FEB: AXI4, all features enabled. OoO + ordering + atomic + \
     S&F + capability register. Maximum functionality at higher area cost. \
     Use when latency variance is high AND ordering is needed." \
    {
        BUS_TYPE            AXI4
        ADDR_WIDTH          16
        OUTSTANDING_LIMIT   16
        OUTSTANDING_INT_RESERVED 2
        EXT_DOWN_PLD_DEPTH  1024
        INT_DOWN_PLD_DEPTH  64
        EXT_UP_PLD_DEPTH    1024
        INT_UP_PLD_DEPTH    64
        INT_HDR_DEPTH       4
        MAX_BURST           256
        BP_FIFO_DEPTH       1024
        OOO_ENABLE          true
        ORD_ENABLE          true
        ORD_NUM_DOMAINS     16
        ATOMIC_ENABLE       true
        S_AND_F_ENABLE      true
        HUB_CAP_ENABLE      true
        RD_TIMEOUT_CYCLES   2048
        WR_TIMEOUT_CYCLES   2048
        AXI4_USER_WIDTH     16
        AXI4_ID_WIDTH       4
        DEBUG               1
    }

# ============================================================================
# FEB_MUPIX presets — Mupix frontend board (similar to SciFi)
# ============================================================================

sc_hub_v2_define_preset "FEB_MUPIX_DEFAULT" \
    "Mupix FEB: AVMM, in-order, ordering + atomic. Production default." \
    {
        BUS_TYPE            AVALON
        ADDR_WIDTH          16
        OUTSTANDING_LIMIT   8
        OUTSTANDING_INT_RESERVED 2
        EXT_DOWN_PLD_DEPTH  512
        INT_DOWN_PLD_DEPTH  64
        EXT_UP_PLD_DEPTH    512
        INT_UP_PLD_DEPTH    64
        INT_HDR_DEPTH       4
        MAX_BURST           256
        BP_FIFO_DEPTH       512
        OOO_ENABLE          false
        ORD_ENABLE          true
        ORD_NUM_DOMAINS     16
        ATOMIC_ENABLE       true
        S_AND_F_ENABLE      true
        HUB_CAP_ENABLE      true
        RD_TIMEOUT_CYCLES   1024
        WR_TIMEOUT_CYCLES   1024
        AXI4_USER_WIDTH     16
        AXI4_ID_WIDTH       4
        DEBUG               1
    }

sc_hub_v2_define_preset "FEB_MUPIX_OOO" \
    "Mupix FEB: AXI4, OoO + ordering + atomic." \
    {
        BUS_TYPE            AXI4
        ADDR_WIDTH          16
        OUTSTANDING_LIMIT   8
        OUTSTANDING_INT_RESERVED 2
        EXT_DOWN_PLD_DEPTH  512
        INT_DOWN_PLD_DEPTH  64
        EXT_UP_PLD_DEPTH    512
        INT_UP_PLD_DEPTH    64
        INT_HDR_DEPTH       4
        MAX_BURST           256
        BP_FIFO_DEPTH       512
        OOO_ENABLE          true
        ORD_ENABLE          true
        ORD_NUM_DOMAINS     16
        ATOMIC_ENABLE       true
        S_AND_F_ENABLE      true
        HUB_CAP_ENABLE      true
        RD_TIMEOUT_CYCLES   1024
        WR_TIMEOUT_CYCLES   1024
        AXI4_USER_WIDTH     16
        AXI4_ID_WIDTH       4
        DEBUG               1
    }

sc_hub_v2_define_preset "FEB_MUPIX_ORDERED" \
    "Mupix FEB: AVMM, ordering only (same as DEFAULT)." \
    {
        BUS_TYPE            AVALON
        ADDR_WIDTH          16
        OUTSTANDING_LIMIT   8
        OUTSTANDING_INT_RESERVED 2
        EXT_DOWN_PLD_DEPTH  512
        INT_DOWN_PLD_DEPTH  64
        EXT_UP_PLD_DEPTH    512
        INT_UP_PLD_DEPTH    64
        INT_HDR_DEPTH       4
        MAX_BURST           256
        BP_FIFO_DEPTH       512
        OOO_ENABLE          false
        ORD_ENABLE          true
        ORD_NUM_DOMAINS     16
        ATOMIC_ENABLE       true
        S_AND_F_ENABLE      true
        HUB_CAP_ENABLE      true
        RD_TIMEOUT_CYCLES   1024
        WR_TIMEOUT_CYCLES   1024
        AXI4_USER_WIDTH     16
        AXI4_ID_WIDTH       4
        DEBUG               1
    }

sc_hub_v2_define_preset "FEB_MUPIX_FULL" \
    "Mupix FEB: All features, deep buffers." \
    {
        BUS_TYPE            AXI4
        ADDR_WIDTH          16
        OUTSTANDING_LIMIT   16
        OUTSTANDING_INT_RESERVED 2
        EXT_DOWN_PLD_DEPTH  1024
        INT_DOWN_PLD_DEPTH  64
        EXT_UP_PLD_DEPTH    1024
        INT_UP_PLD_DEPTH    64
        INT_HDR_DEPTH       4
        MAX_BURST           256
        BP_FIFO_DEPTH       1024
        OOO_ENABLE          true
        ORD_ENABLE          true
        ORD_NUM_DOMAINS     16
        ATOMIC_ENABLE       true
        S_AND_F_ENABLE      true
        HUB_CAP_ENABLE      true
        RD_TIMEOUT_CYCLES   2048
        WR_TIMEOUT_CYCLES   2048
        AXI4_USER_WIDTH     16
        AXI4_ID_WIDTH       4
        DEBUG               1
    }

# ============================================================================
# FEB_TILES presets — Tile frontend board (tighter area budget)
# ============================================================================

sc_hub_v2_define_preset "FEB_TILES_DEFAULT" \
    "Tiles FEB: AVMM, in-order, ordering + atomic. Moderate buffers." \
    {
        BUS_TYPE            AVALON
        ADDR_WIDTH          16
        OUTSTANDING_LIMIT   4
        OUTSTANDING_INT_RESERVED 2
        EXT_DOWN_PLD_DEPTH  256
        INT_DOWN_PLD_DEPTH  32
        EXT_UP_PLD_DEPTH    256
        INT_UP_PLD_DEPTH    32
        INT_HDR_DEPTH       2
        MAX_BURST           64
        BP_FIFO_DEPTH       256
        OOO_ENABLE          false
        ORD_ENABLE          true
        ORD_NUM_DOMAINS     4
        ATOMIC_ENABLE       true
        S_AND_F_ENABLE      true
        HUB_CAP_ENABLE      true
        RD_TIMEOUT_CYCLES   512
        WR_TIMEOUT_CYCLES   512
        AXI4_USER_WIDTH     16
        AXI4_ID_WIDTH       4
        DEBUG               0
    }

sc_hub_v2_define_preset "FEB_TILES_MINIMAL" \
    "Tiles FEB: AVMM, no OoO, no ordering, no atomic. Minimum area. \
     Only for systems that use legacy relaxed-only SC protocol." \
    {
        BUS_TYPE            AVALON
        ADDR_WIDTH          16
        OUTSTANDING_LIMIT   4
        OUTSTANDING_INT_RESERVED 1
        EXT_DOWN_PLD_DEPTH  128
        INT_DOWN_PLD_DEPTH  32
        EXT_UP_PLD_DEPTH    128
        INT_UP_PLD_DEPTH    32
        INT_HDR_DEPTH       2
        MAX_BURST           32
        BP_FIFO_DEPTH       128
        OOO_ENABLE          false
        ORD_ENABLE          false
        ORD_NUM_DOMAINS     1
        ATOMIC_ENABLE       false
        S_AND_F_ENABLE      true
        HUB_CAP_ENABLE      true
        RD_TIMEOUT_CYCLES   256
        WR_TIMEOUT_CYCLES   256
        AXI4_USER_WIDTH     0
        AXI4_ID_WIDTH       1
        DEBUG               0
    }

# ============================================================================
# Generic presets — not platform-specific
# ============================================================================

sc_hub_v2_define_preset "MINIMAL_CSR_ONLY" \
    "Smallest possible hub: AVMM, OD=1, no OoO, no ordering, no atomic. \
     For test/debug systems that only need CSR access. MAX_BURST=4." \
    {
        BUS_TYPE            AVALON
        ADDR_WIDTH          16
        OUTSTANDING_LIMIT   1
        OUTSTANDING_INT_RESERVED 1
        EXT_DOWN_PLD_DEPTH  64
        INT_DOWN_PLD_DEPTH  32
        EXT_UP_PLD_DEPTH    64
        INT_UP_PLD_DEPTH    32
        INT_HDR_DEPTH       1
        MAX_BURST           4
        BP_FIFO_DEPTH       64
        OOO_ENABLE          false
        ORD_ENABLE          false
        ORD_NUM_DOMAINS     1
        ATOMIC_ENABLE       false
        S_AND_F_ENABLE      true
        HUB_CAP_ENABLE      true
        RD_TIMEOUT_CYCLES   256
        WR_TIMEOUT_CYCLES   256
        AXI4_USER_WIDTH     0
        AXI4_ID_WIDTH       1
        DEBUG               0
    }

sc_hub_v2_define_preset "MAX_THROUGHPUT" \
    "Maximum throughput: AXI4, OoO, OD=32, deep buffers. For benchmarking. \
     TLM predicts 2-3x throughput vs DEFAULT at high-variance latency." \
    {
        BUS_TYPE            AXI4
        ADDR_WIDTH          16
        OUTSTANDING_LIMIT   32
        OUTSTANDING_INT_RESERVED 4
        EXT_DOWN_PLD_DEPTH  2048
        INT_DOWN_PLD_DEPTH  128
        EXT_UP_PLD_DEPTH    2048
        INT_UP_PLD_DEPTH    128
        INT_HDR_DEPTH       8
        MAX_BURST           256
        BP_FIFO_DEPTH       1024
        OOO_ENABLE          true
        ORD_ENABLE          true
        ORD_NUM_DOMAINS     16
        ATOMIC_ENABLE       true
        S_AND_F_ENABLE      true
        HUB_CAP_ENABLE      true
        RD_TIMEOUT_CYCLES   2048
        WR_TIMEOUT_CYCLES   2048
        AXI4_USER_WIDTH     16
        AXI4_ID_WIDTH       8
        DEBUG               1
    }

sc_hub_v2_define_preset "MAX_FEATURES" \
    "All features enabled, balanced buffers. For DV comprehensive testing." \
    {
        BUS_TYPE            AXI4
        ADDR_WIDTH          16
        OUTSTANDING_LIMIT   8
        OUTSTANDING_INT_RESERVED 2
        EXT_DOWN_PLD_DEPTH  512
        INT_DOWN_PLD_DEPTH  64
        EXT_UP_PLD_DEPTH    512
        INT_UP_PLD_DEPTH    64
        INT_HDR_DEPTH       4
        MAX_BURST           256
        BP_FIFO_DEPTH       512
        OOO_ENABLE          true
        ORD_ENABLE          true
        ORD_NUM_DOMAINS     16
        ATOMIC_ENABLE       true
        S_AND_F_ENABLE      true
        HUB_CAP_ENABLE      true
        RD_TIMEOUT_CYCLES   1024
        WR_TIMEOUT_CYCLES   1024
        AXI4_USER_WIDTH     16
        AXI4_ID_WIDTH       4
        DEBUG               2
    }

sc_hub_v2_define_preset "AREA_OPTIMIZED" \
    "Area-optimized: AVMM, no OoO, 4 ordering domains, small buffers." \
    {
        BUS_TYPE            AVALON
        ADDR_WIDTH          16
        OUTSTANDING_LIMIT   4
        OUTSTANDING_INT_RESERVED 1
        EXT_DOWN_PLD_DEPTH  128
        INT_DOWN_PLD_DEPTH  32
        EXT_UP_PLD_DEPTH    128
        INT_UP_PLD_DEPTH    32
        INT_HDR_DEPTH       2
        MAX_BURST           64
        BP_FIFO_DEPTH       128
        OOO_ENABLE          false
        ORD_ENABLE          true
        ORD_NUM_DOMAINS     4
        ATOMIC_ENABLE       true
        S_AND_F_ENABLE      true
        HUB_CAP_ENABLE      true
        RD_TIMEOUT_CYCLES   512
        WR_TIMEOUT_CYCLES   512
        AXI4_USER_WIDTH     16
        AXI4_ID_WIDTH       4
        DEBUG               0
    }

# ============================================================================
# Preset application logic
# ============================================================================

# Apply a named preset — sets all parameters from the preset dict
proc sc_hub_v2_apply_preset {preset_name} {
    variable SC_HUB_V2_PRESETS

    if {$preset_name eq "CUSTOM"} {
        # CUSTOM = user controls all params individually
        return
    }

    if {![dict exists $SC_HUB_V2_PRESETS $preset_name]} {
        send_message error "Unknown preset: $preset_name"
        return
    }

    set params [dict get $SC_HUB_V2_PRESETS $preset_name]
    dict for {pname pval} $params {
        if {[catch {set_parameter_value $pname $pval} err]} {
            send_message warning "Preset $preset_name: failed to set $pname=$pval: $err"
        }
    }
}

# Called from elaboration: apply preset if it changed
proc sc_hub_v2_apply_preset_if_changed {} {
    set preset [get_parameter_value PRESET]
    if {$preset ne "CUSTOM"} {
        sc_hub_v2_apply_preset $preset
    }

    # Update derived parameters regardless
    sc_hub_v2_compute_derived
}

# Compute derived parameters from current values
proc sc_hub_v2_compute_derived {} {
    set od [get_parameter_value OUTSTANDING_LIMIT]
    set ir [get_parameter_value OUTSTANDING_INT_RESERVED]
    set pld [get_parameter_value EXT_DOWN_PLD_DEPTH]
    set mb [get_parameter_value MAX_BURST]

    set_parameter_value EXT_HDR_DEPTH $od
    set_parameter_value PLD_ADDR_WIDTH [sc_hub_v2_clog2 $pld]
    set_parameter_value BURSTCOUNT_WIDTH [expr {[sc_hub_v2_clog2 $mb] + 1}]
    set_parameter_value EFFECTIVE_EXT_OUTSTANDING [expr {$od - $ir}]
}

# Get all preset names as a list
proc sc_hub_v2_get_preset_names {} {
    variable SC_HUB_V2_PRESETS
    return [dict keys $SC_HUB_V2_PRESETS]
}

# Get preset description
proc sc_hub_v2_get_preset_desc {name} {
    variable SC_HUB_V2_PRESET_DESC
    if {[dict exists $SC_HUB_V2_PRESET_DESC $name]} {
        return [dict get $SC_HUB_V2_PRESET_DESC $name]
    }
    return ""
}

# Generate HTML summary table of all presets for the GUI
proc sc_hub_v2_preset_summary_html {} {
    variable SC_HUB_V2_PRESETS
    variable SC_HUB_V2_PRESET_DESC

    set html "<html><h3>Preset Configuration Matrix</h3>"
    append html "<table border=\"1\" cellpadding=\"3\" width=\"100%\">\n"
    append html "<tr><th>Preset</th><th>Bus</th><th>OD</th><th>PLD</th>"
    append html "<th>OoO</th><th>ORD</th><th>ATM</th><th>Burst</th><th>Description</th></tr>\n"

    dict for {name params} $SC_HUB_V2_PRESETS {
        set bus  [dict get $params BUS_TYPE]
        set od   [dict get $params OUTSTANDING_LIMIT]
        set pld  [dict get $params EXT_DOWN_PLD_DEPTH]
        set ooo  [expr {[dict get $params OOO_ENABLE] ? "Y" : "-"}]
        set ord  [expr {[dict get $params ORD_ENABLE] ? "Y" : "-"}]
        set atm  [expr {[dict get $params ATOMIC_ENABLE] ? "Y" : "-"}]
        set mb   [dict get $params MAX_BURST]
        set desc [dict get $SC_HUB_V2_PRESET_DESC $name]
        # Truncate description for table
        if {[string length $desc] > 80} {
            set desc "[string range $desc 0 79]..."
        }
        append html "<tr><td><b>$name</b></td><td>$bus</td><td>$od</td><td>$pld</td>"
        append html "<td>$ooo</td><td>$ord</td><td>$atm</td><td>$mb</td>"
        append html "<td><small>$desc</small></td></tr>\n"
    }
    append html "</table></html>"
    return $html
}
