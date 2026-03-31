# ============================================================================
# sc_hub_v2 — Parameter Validation
#
# Called from the VALIDATION_CALLBACK. Checks parameter ranges, cross-parameter
# consistency, feature dependencies, and emits warnings for risky configs.
# ============================================================================

# ----------------------------------------------------------------------------
# Range validation
# ----------------------------------------------------------------------------
proc sc_hub_v2_validate_ranges {} {
    set od  [get_parameter_value OUTSTANDING_LIMIT]
    set ir  [get_parameter_value OUTSTANDING_INT_RESERVED]
    set pld [get_parameter_value EXT_DOWN_PLD_DEPTH]
    set mb  [get_parameter_value MAX_BURST]
    set bp  [get_parameter_value BP_FIFO_DEPTH]
    set dbg [get_parameter_value DEBUG]
    set bus [string toupper [get_parameter_value BUS_TYPE]]
    set aw  [get_parameter_value ADDR_WIDTH]

    # OUTSTANDING_INT_RESERVED must be >= 1 (fatal DV_ERROR T540)
    if {$ir < 1} {
        send_message error \
            "OUTSTANDING_INT_RESERVED must be >= 1. Setting it to 0 \
             removes the software reset recovery path (see DV_ERROR.md T540)."
    }

    # OUTSTANDING_INT_RESERVED must be < OUTSTANDING_LIMIT
    if {$ir >= $od} {
        send_message error \
            "OUTSTANDING_INT_RESERVED ($ir) must be < OUTSTANDING_LIMIT ($od). \
             Otherwise no external transactions can proceed."
    }

    # EXT_DOWN_PLD_DEPTH should be >= MAX_BURST for full burst support
    if {$pld < $mb} {
        send_message warning \
            "EXT_DOWN_PLD_DEPTH ($pld) < MAX_BURST ($mb). Writes with \
             L > $pld will be permanently backpressured. Software must not \
             send bursts larger than $pld words (see DV_ERROR.md T542-T543)."
    }

    # BP_FIFO_DEPTH should hold at least one max reply packet
    set min_bp [expr {$mb + 4}]
    if {$bp < $min_bp} {
        send_message warning \
            "BP_FIFO_DEPTH ($bp) < MAX_BURST + 4 ($min_bp). A single \
             max-burst reply may not fit in the backpressure FIFO, causing \
             potential stalls."
    }

    # Debug range
    if {$dbg < 0 || $dbg > 4} {
        send_message error "DEBUG must be in range 0..4. Got $dbg."
    }

    # Bus type
    if {$bus ne "AVALON" && $bus ne "AXI4"} {
        send_message error "BUS_TYPE must be AVALON or AXI4. Got $bus."
    }

    # Address width minimum
    if {$aw < 16} {
        send_message warning \
            "ADDR_WIDTH ($aw) < 16. Internal CSR window at 0xFE80 may not \
             be addressable. Ensure the CSR base is within 2^$aw."
    }
}

# ----------------------------------------------------------------------------
# Cross-parameter consistency
# ----------------------------------------------------------------------------
proc sc_hub_v2_validate_cross {} {
    set bus [string toupper [get_parameter_value BUS_TYPE]]
    set ooo [get_parameter_value OOO_ENABLE]
    set ord [get_parameter_value ORD_ENABLE]
    set nd  [get_parameter_value ORD_NUM_DOMAINS]
    set uw  [get_parameter_value AXI4_USER_WIDTH]

    if {$bus eq "AXI4"} {
        send_message error \
            "BUS_TYPE=AXI4 is not generatable through the current Platform Designer wrapper. \
             Root cause: the component fileset is fixed to the live AVMM top-level sc_hub_top, \
             and PD does not allow switching QUARTUS_SYNTH TOP_LEVEL during ELABORATE. \
             Effect: the AXI4 interface would not match the compiled HDL boundary. \
             Practical fix: keep BUS_TYPE=AVALON for PD integration, or ship a dedicated AXI4 wrapper/component."
    }

    # OoO + AVMM: limited benefit
    if {$ooo && $bus eq "AVALON"} {
        send_message warning \
            "OOO_ENABLE=true with BUS_TYPE=AVALON: Avalon-MM guarantees \
             in-order read data completion. OoO benefit is limited to \
             internal CSR bypass. Consider AXI4 for full OoO benefit."
    }

    # Ordering + AXI4 USER width
    if {$ord && $bus eq "AXI4" && $uw < 16} {
        send_message error \
            "ORD_ENABLE=true with AXI4 requires AXI4_USER_WIDTH >= 16 \
             (order_type:2 + ord_dom_id:4 + ord_epoch:8 + ord_scope:2 = 16). \
             Current AXI4_USER_WIDTH = $uw."
    }

    # ORD_NUM_DOMAINS without ORD_ENABLE
    if {!$ord && $nd > 1} {
        send_message info \
            "ORD_NUM_DOMAINS ($nd) > 1 but ORD_ENABLE=false. Domain state \
             array will not be synthesized. Value is ignored."
    }

    # Credit constraint: upload payload must handle max concurrent reads
    set od  [get_parameter_value OUTSTANDING_LIMIT]
    set ir  [get_parameter_value OUTSTANDING_INT_RESERVED]
    set upld [get_parameter_value EXT_UP_PLD_DEPTH]
    set mb  [get_parameter_value MAX_BURST]
    set eff [expr {$od - $ir}]
    set max_needed [expr {$eff * $mb}]

    if {$max_needed > $upld} {
        set eff_reads [expr {$upld / $mb}]
        if {$eff_reads < 1} {set eff_reads 1}
        send_message info \
            "EXT_UP_PLD_DEPTH ($upld) < EFFECTIVE_EXT_OUTSTANDING x MAX_BURST \
             ($eff x $mb = $max_needed). Credit manager will limit effective \
             read outstanding to ~$eff_reads for max-burst reads. This is \
             normal and validated by TLM CRED-03."
    }
}

# ----------------------------------------------------------------------------
# Feature dependency checks
# ----------------------------------------------------------------------------
proc sc_hub_v2_validate_features {} {
    set sf  [get_parameter_value S_AND_F_ENABLE]
    set atm [get_parameter_value ATOMIC_ENABLE]
    set ooo [get_parameter_value OOO_ENABLE]
    set ord [get_parameter_value ORD_ENABLE]
    set cap [get_parameter_value HUB_CAP_ENABLE]

    # S&F disabled: warn about truncated packet vulnerability
    if {!$sf} {
        send_message warning \
            "S_AND_F_ENABLE=false: Write packets stream directly to bus \
             without validation. Truncated or malformed packets may cause \
             partial bus writes (see DV_ERROR.md T546). Only safe with \
             hardware-guaranteed link integrity."
    }

    # HUB_CAP disabled: software cannot detect missing features
    if {!$cap && (!$atm || !$ord || !$ooo)} {
        send_message warning \
            "HUB_CAP_ENABLE=false with some features disabled. Software \
             cannot detect missing features at init. Silent failures may \
             occur if software uses disabled features (see DV_ERROR.md)."
    }
}

# ----------------------------------------------------------------------------
# Risky configuration warnings
# ----------------------------------------------------------------------------
proc sc_hub_v2_validate_warnings {} {
    set od  [get_parameter_value OUTSTANDING_LIMIT]
    set pld [get_parameter_value EXT_DOWN_PLD_DEPTH]
    set ord [get_parameter_value ORD_ENABLE]
    set atm [get_parameter_value ATOMIC_ENABLE]

    # Very deep outstanding with small payload
    if {$od >= 16 && $pld <= 256} {
        send_message warning \
            "OUTSTANDING_LIMIT=$od with EXT_DOWN_PLD_DEPTH=$pld: payload \
             may become a bottleneck for burst writes. Consider increasing \
             payload depth or reducing outstanding limit."
    }

    # Ordering disabled: RELEASE/ACQUIRE packets will be treated as RELAXED
    if {!$ord} {
        send_message info \
            "ORD_ENABLE=false: All RELEASE/ACQUIRE packets will be treated \
             as RELAXED. The ordering tracker is not synthesized. Ensure \
             software does not rely on ordering semantics."
    }

    # Atomic disabled: atomic_flag packets will return SLAVEERROR
    if {!$atm} {
        send_message info \
            "ATOMIC_ENABLE=false: Packets with atomic_flag=1 will receive \
             SLAVEERROR response. Ensure software does not use atomic RMW."
    }
}
