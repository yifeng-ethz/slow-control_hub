# ============================================================================
# sc_hub_v2 — GUI Layout and Dynamic Elaboration
#
# Tabs modeled after Intel JESD204B IP GUI:
#   Tab 1: Configuration (preset selector + feature overview)
#   Tab 2: Buffer Architecture (split-buffer sizing, malloc)
#   Tab 3: Features (OoO, ordering, atomic toggles)
#   Tab 4: Performance Preview (TLM-derived, dynamic)
#   Tab 5: Resource Estimate (synthesis-derived, dynamic)
#   Tab 6: Register Map (CSR table, dynamic based on features)
#   Tab 7: Interfaces (clock, reset, packet, bus)
#   Tab 8: Identity (version, compatibility)
# ============================================================================

# ----------------------------------------------------------------------------
# Tab definitions
# ----------------------------------------------------------------------------

set TAB_CONFIG      "Configuration"
set TAB_BUFFER      "Buffer Architecture"
set TAB_FEATURES    "Features"
set TAB_PERF        "Performance Preview"
set TAB_RESOURCES   "Resource Estimate"
set TAB_REGMAP      "Register Map"
set TAB_INTERFACES  "Interfaces"
set TAB_IDENTITY    "Identity"

add_display_item "" $TAB_CONFIG     GROUP tab
add_display_item "" $TAB_BUFFER     GROUP tab
add_display_item "" $TAB_FEATURES   GROUP tab
add_display_item "" $TAB_PERF       GROUP tab
add_display_item "" $TAB_RESOURCES  GROUP tab
add_display_item "" $TAB_REGMAP     GROUP tab
add_display_item "" $TAB_INTERFACES GROUP tab
add_display_item "" $TAB_IDENTITY   GROUP tab

# ============================================================================
# TAB 1: Configuration
# ============================================================================

add_display_item $TAB_CONFIG "Preset Selection" GROUP
add_display_item $TAB_CONFIG "Current Configuration" GROUP
add_display_item $TAB_CONFIG "Preset Matrix" GROUP

add_display_item "Preset Selection" PRESET parameter
sc_hub_v2_add_html "Preset Selection" preset_help_html \
    {<html><b>How presets work</b><br/>
    Selecting a preset auto-configures all parameters for a known platform
    and feature set. Select <b>CUSTOM</b> to manually tune individual
    parameters.<br/><br/>
    <b>Note:</b> Presets are applied during GUI elaboration, not from
    Platform Designer .prst files (those do not propagate reliably
    in Qsys 18.1). The preset name is stored as a parameter and
    re-applied on each regeneration.</html>}

# Dynamic: filled by sc_hub_v2_update_gui
sc_hub_v2_add_html "Current Configuration" config_summary_html \
    {<html><i>Configuration summary will appear after elaboration.</i></html>}

# Static: preset matrix overview
sc_hub_v2_add_html "Preset Matrix" preset_matrix_html \
    {<html><i>Preset matrix table will appear after elaboration.</i></html>}

# ============================================================================
# TAB 2: Buffer Architecture
# ============================================================================

add_display_item $TAB_BUFFER "Outstanding & Header" GROUP
add_display_item $TAB_BUFFER "Payload RAM (Linked-List)" GROUP
add_display_item $TAB_BUFFER "Backpressure FIFO" GROUP
add_display_item $TAB_BUFFER "Buffer Architecture Diagram" GROUP

add_display_item "Outstanding & Header" OUTSTANDING_LIMIT parameter
add_display_item "Outstanding & Header" OUTSTANDING_INT_RESERVED parameter
add_display_item "Outstanding & Header" INT_HDR_DEPTH parameter
add_display_item "Outstanding & Header" MAX_BURST parameter

sc_hub_v2_add_html "Outstanding & Header" outstanding_help_html \
    {<html><b>Outstanding transactions</b><br/>
    The hub supports up to <b>OUTSTANDING_LIMIT</b> concurrent transactions.
    <b>OUTSTANDING_INT_RESERVED</b> slots are exclusively for internal CSR
    traffic, ensuring software can always issue CTRL.reset even under
    external saturation.<br/><br/>
    <b>TLM guidance (SIZE-01):</b> Throughput knee is at OD=4-8 for
    typical SC workloads. OD>16 has diminishing returns unless bus
    latency is very high (>100 cycles).</html>}

add_display_item "Payload RAM (Linked-List)" EXT_DOWN_PLD_DEPTH parameter
add_display_item "Payload RAM (Linked-List)" INT_DOWN_PLD_DEPTH parameter
add_display_item "Payload RAM (Linked-List)" EXT_UP_PLD_DEPTH parameter
add_display_item "Payload RAM (Linked-List)" INT_UP_PLD_DEPTH parameter

sc_hub_v2_add_html "Payload RAM (Linked-List)" pld_help_html \
    {<html><b>Payload RAM</b><br/>
    Each of the 4 payload subFIFOs is implemented as a linked-list RAM
    with malloc/free. Fragmentation does NOT cause allocation failure
    (linked-list tolerates non-contiguous allocation), but increases
    payload read latency due to pointer hops.<br/><br/>
    <b>Sizing rule:</b> EXT_DOWN_PLD_DEPTH &ge; MAX_BURST for full
    burst support. EXT_UP_PLD_DEPTH limits effective read outstanding
    to EXT_UP_PLD_DEPTH / avg_burst_length (credit-based reservation).<br/><br/>
    <b>TLM guidance (SIZE-02):</b> 512 words is sufficient for OD=8,
    MAX_BURST=256. 1024 words needed for OD=16+.</html>}

add_display_item "Backpressure FIFO" BP_FIFO_DEPTH parameter
sc_hub_v2_add_html "Backpressure FIFO" bp_help_html \
    {<html><b>Backpressure FIFO</b><br/>
    Decouples the reply assembly path from the uplink. Must hold at
    least one maximum-size reply packet: MAX_BURST + 4 header words.</html>}

# Dynamic: architecture diagram (text-based, updated per config)
sc_hub_v2_add_html "Buffer Architecture Diagram" buf_diagram_html \
    {<html><i>Architecture diagram will appear after elaboration.</i></html>}

# ============================================================================
# TAB 3: Features
# ============================================================================

add_display_item $TAB_FEATURES "Bus Interface" GROUP
add_display_item $TAB_FEATURES "Out-of-Order Dispatch" GROUP
add_display_item $TAB_FEATURES "Ordering Semantics" GROUP
add_display_item $TAB_FEATURES "Atomic RMW" GROUP
add_display_item $TAB_FEATURES "Store-and-Forward" GROUP
add_display_item $TAB_FEATURES "Diagnostics" GROUP

add_display_item "Bus Interface" BUS_TYPE parameter
add_display_item "Bus Interface" ADDR_WIDTH parameter
add_display_item "Bus Interface" AXI4_USER_WIDTH parameter
add_display_item "Bus Interface" AXI4_ID_WIDTH parameter

add_display_item "Out-of-Order Dispatch" OOO_ENABLE parameter
sc_hub_v2_add_html "Out-of-Order Dispatch" ooo_help_html \
    {<html><b>Out-of-Order Dispatch</b><br/>
    When enabled, the dispatch scoreboard allows transactions to complete
    in any order. Reply assembly uses the scoreboard instead of
    reply_order_fifo. Requires <b>AXI4</b> bus for full benefit (AVMM
    guarantees in-order completion by protocol).<br/><br/>
    <b>Runtime control:</b> OOO_CTRL CSR bit 0 can disable OoO at
    runtime even when compiled in. Toggle drains in-flight transactions
    before switching mode.<br/><br/>
    <b>TLM guidance (OOO-01..06):</b><br/>
    - Fixed latency: speedup ~1.0 (no benefit)<br/>
    - Uniform(4,50ns): speedup 1.3-1.8x<br/>
    - Uniform(4,200ns): speedup 2.0-3.0x<br/>
    - Fast CSR + slow ext: speedup >2.0x</html>}

add_display_item "Ordering Semantics" ORD_ENABLE parameter
add_display_item "Ordering Semantics" ORD_NUM_DOMAINS parameter
sc_hub_v2_add_html "Ordering Semantics" ord_help_html \
    {<html><b>Ordering Semantics (Release / Acquire / Relaxed)</b><br/>
    Per-domain ordering with 4 correctness rules (R1-R4). Software tags
    packets with ORDER[1:0] and ORD_DOM_ID[3:0].<br/><br/>
    <b>Expected traffic mix:</b> >95% RELAXED, &lt;3% RELEASE, &lt;2% ACQUIRE.<br/>
    <b>Zero overhead on RELAXED:</b> domain state check is O(1).<br/><br/>
    <b>TLM guidance (ORD-01..08):</b><br/>
    - 5% RELEASE, L=1: ~5% throughput overhead<br/>
    - 5% RELEASE, L=64: higher (drain waits for large writes)<br/>
    - Cross-domain: independent (domain 1 unaffected by domain 0 acquire)<br/>
    - 50% RELEASE (pathological): severe degradation (effective OD=1)<br/><br/>
    See <b>ORDERING_GUIDE.md</b> for the software programming model.</html>}

add_display_item "Atomic RMW" ATOMIC_ENABLE parameter
sc_hub_v2_add_html "Atomic RMW" atom_help_html \
    {<html><b>Atomic Read-Modify-Write</b><br/>
    Hub-internal RMW: read, compute (data &amp; ~mask) | (modify &amp; mask),
    write. Bus lock held during sequence. Internal CSR traffic bypasses
    the lock.<br/><br/>
    <b>TLM guidance (ATOM-01..04):</b> Throughput degrades linearly with
    atomic ratio. At 10% atomic: ~10% throughput loss.</html>}

add_display_item "Store-and-Forward" S_AND_F_ENABLE parameter
sc_hub_v2_add_html "Store-and-Forward" sf_help_html \
    {<html><b>Store-and-Forward</b><br/>
    When enabled, write packets are fully received and validated before
    any bus write is issued. Prevents partial writes from corrupted or
    truncated packets.<br/><br/>
    <b>Warning:</b> Disabling S&amp;F is only safe when the upstream link
    guarantees packet integrity (hardware CRC with no truncation).</html>}

add_display_item "Diagnostics" HUB_CAP_ENABLE parameter
add_display_item "Diagnostics" DEBUG parameter
add_display_item "Diagnostics" RD_TIMEOUT_CYCLES parameter
add_display_item "Diagnostics" WR_TIMEOUT_CYCLES parameter

# ============================================================================
# TAB 4: Performance Preview (dynamic, filled by tlm_preview.tcl)
# ============================================================================

add_display_item $TAB_PERF "TLM Performance Summary" GROUP
add_display_item $TAB_PERF "Rate-Latency Preview" GROUP
add_display_item $TAB_PERF "Fragmentation Preview" GROUP
add_display_item $TAB_PERF "Ordering Overhead Preview" GROUP

sc_hub_v2_add_html "TLM Performance Summary" tlm_summary_html \
    {<html><i>TLM performance data will appear after elaboration.<br/>
    Data is loaded from tlm/results/csv/ based on current parameter values.</i></html>}

sc_hub_v2_add_html "Rate-Latency Preview" tlm_rate_html \
    {<html><i>Rate-latency curve will appear here.</i></html>}

sc_hub_v2_add_html "Fragmentation Preview" tlm_frag_html \
    {<html><i>Fragmentation preview will appear here.</i></html>}

sc_hub_v2_add_html "Ordering Overhead Preview" tlm_ord_html \
    {<html><i>Ordering overhead preview will appear here.</i></html>}

# ============================================================================
# TAB 5: Resource Estimate (dynamic, filled by report.tcl)
# ============================================================================

add_display_item $TAB_RESOURCES "Resource Summary" GROUP
add_display_item $TAB_RESOURCES "Breakdown by Module" GROUP
add_display_item $TAB_RESOURCES "Comparison with Other Presets" GROUP

sc_hub_v2_add_html "Resource Summary" resource_summary_html \
    {<html><i>Resource estimates will appear after elaboration.</i></html>}

sc_hub_v2_add_html "Breakdown by Module" resource_breakdown_html \
    {<html><i>Module-level breakdown will appear here.</i></html>}

sc_hub_v2_add_html "Comparison with Other Presets" resource_compare_html \
    {<html><i>Preset comparison will appear here.</i></html>}

# ============================================================================
# TAB 6: Register Map (dynamic based on features)
# ============================================================================

add_display_item $TAB_REGMAP "CSR Window (0xFE80-0xFE9F)" GROUP

sc_hub_v2_add_html "CSR Window (0xFE80-0xFE9F)" csr_table_html \
    {<html><i>CSR register table will appear after elaboration.</i></html>}

# ============================================================================
# TAB 7: Interfaces
# ============================================================================

add_display_item $TAB_INTERFACES "Clock / Reset" GROUP
add_display_item $TAB_INTERFACES "Packet Links" GROUP
add_display_item $TAB_INTERFACES "Master Bus" GROUP

sc_hub_v2_add_html "Clock / Reset" if_clock_html \
    {<html><b>hub_clock</b> and <b>hub_reset</b><br/>
    Single synchronous domain. Hub clock and bus clock must be the same
    (no internal CDC). Reset must be synchronized externally.</html>}

sc_hub_v2_add_html "Packet Links" if_pkt_html \
    {<html><b>download (conduit sink)</b><br/>
    32-bit + 4-bit datak Mu3e slow-control packet input.<br/><br/>
    <b>upload (Avalon-ST source)</b><br/>
    36-bit reply packet output with SOP/EOP and backpressure-capable ready.</html>}

sc_hub_v2_add_html "Master Bus" if_bus_html \
    {<html><b>hub (Avalon-MM or AXI4 master)</b><br/>
    Created by elaboration callback based on BUS_TYPE parameter.
    Interface properties (burst capability, outstanding depth) are set
    dynamically to match the configured OUTSTANDING_LIMIT and MAX_BURST.</html>}

# ============================================================================
# TAB 8: Identity
# ============================================================================

add_display_item $TAB_IDENTITY "Version Info" GROUP
add_display_item $TAB_IDENTITY "Compatibility" GROUP

sc_hub_v2_add_html "Version Info" id_version_html \
    {<html><b>sc_hub_v2</b> version <b>26.3.0</b><br/>
    Split-buffer architecture, linked-list payload, OoO dispatch,
    atomic RMW, release/acquire ordering.<br/><br/>
    <b>Companion documents:</b><br/>
    - TLM_PLAN.md (behavioral model and experiments)<br/>
    - TLM_NOTE.md (implementation review)<br/>
    - DV_PLAN.md (design verification)<br/>
    - ORDERING_GUIDE.md (software contract)<br/>
    - RTL_PLAN.md (RTL design plan)</html>}

add_display_item "Compatibility" BACKPRESSURE parameter
add_display_item "Compatibility" SCHEDULER_USE_PKT_TRANSFER parameter
add_display_item "Compatibility" INVERT_RD_SIG parameter
sc_hub_v2_add_html "Compatibility" compat_html \
    {<html><b>Legacy compatibility generics</b><br/>
    These are kept so existing Platform Designer systems regenerate
    without changing their generic list. The v2 RTL always uses the
    internal reply FIFO and validated packet receiver.</html>}

# ============================================================================
# Dynamic GUI update (called from elaboration)
# ============================================================================

proc sc_hub_v2_update_gui {} {
    set bus     [string toupper [get_parameter_value BUS_TYPE]]
    set ooo     [get_parameter_value OOO_ENABLE]
    set ord     [get_parameter_value ORD_ENABLE]
    set atm     [get_parameter_value ATOMIC_ENABLE]
    set preset  [get_parameter_value PRESET]
    set is_custom [expr {$preset eq "CUSTOM"}]

    # Show/hide AXI4-specific params
    set axi4_vis [expr {$bus eq "AXI4"}]
    sc_hub_v2_show_param AXI4_USER_WIDTH $axi4_vis
    sc_hub_v2_show_param AXI4_ID_WIDTH $axi4_vis

    # Show/hide ordering params
    sc_hub_v2_show_param ORD_NUM_DOMAINS $ord

    # Show/hide OoO note when OoO=true but bus=AVMM
    if {$ooo && $bus eq "AVALON"} {
        send_message warning "OOO_ENABLE=true with BUS_TYPE=AVALON: Avalon-MM guarantees \
in-order completion. OoO provides limited benefit (only internal CSR bypass). \
Consider AXI4 for full OoO benefit."
    }

    # Make params read-only when preset is not CUSTOM
    foreach p {BUS_TYPE ADDR_WIDTH OUTSTANDING_LIMIT OUTSTANDING_INT_RESERVED
               EXT_DOWN_PLD_DEPTH INT_DOWN_PLD_DEPTH EXT_UP_PLD_DEPTH INT_UP_PLD_DEPTH
               INT_HDR_DEPTH MAX_BURST BP_FIFO_DEPTH OOO_ENABLE ORD_ENABLE
               ORD_NUM_DOMAINS ATOMIC_ENABLE S_AND_F_ENABLE HUB_CAP_ENABLE
               RD_TIMEOUT_CYCLES WR_TIMEOUT_CYCLES AXI4_USER_WIDTH AXI4_ID_WIDTH
               DEBUG} {
        catch {set_parameter_property $p ENABLED $is_custom}
    }

    # Update configuration summary HTML
    set od      [get_parameter_value OUTSTANDING_LIMIT]
    set ir      [get_parameter_value OUTSTANDING_INT_RESERVED]
    set pld     [get_parameter_value EXT_DOWN_PLD_DEPTH]
    set mb      [get_parameter_value MAX_BURST]
    set eff_ext [expr {$od - $ir}]

    set ooo_str [expr {$ooo ? "<span style='color:green'>Enabled</span>" : "Disabled"}]
    set ord_str [expr {$ord ? "<span style='color:green'>Enabled</span>" : "Disabled"}]
    set atm_str [expr {$atm ? "<span style='color:green'>Enabled</span>" : "Disabled"}]

    set summary_html "<html><table border='1' cellpadding='4' width='100%'>
<tr><td><b>Preset</b></td><td>$preset</td></tr>
<tr><td><b>Bus</b></td><td>$bus</td></tr>
<tr><td><b>Outstanding</b></td><td>$od total ($eff_ext ext + $ir int reserved)</td></tr>
<tr><td><b>Payload RAM</b></td><td>$pld words (ext down/up)</td></tr>
<tr><td><b>Max Burst</b></td><td>$mb words</td></tr>
<tr><td><b>OoO</b></td><td>$ooo_str</td></tr>
<tr><td><b>Ordering</b></td><td>$ord_str</td></tr>
<tr><td><b>Atomic</b></td><td>$atm_str</td></tr>
</table></html>"

    catch {set_display_item_property config_summary_html TEXT $summary_html}

    # Update preset matrix table
    set matrix_html [sc_hub_v2_preset_summary_html]
    catch {set_display_item_property preset_matrix_html TEXT $matrix_html}

    # Update buffer architecture diagram
    sc_hub_v2_update_buf_diagram

    # Update CSR table (dynamic based on features)
    sc_hub_v2_update_csr_table
}

# Generate text-art architecture diagram as HTML
proc sc_hub_v2_update_buf_diagram {} {
    set od  [get_parameter_value OUTSTANDING_LIMIT]
    set pld [get_parameter_value EXT_DOWN_PLD_DEPTH]
    set ipld [get_parameter_value INT_DOWN_PLD_DEPTH]
    set ihd [get_parameter_value INT_HDR_DEPTH]
    set bp  [get_parameter_value BP_FIFO_DEPTH]

    set html "<html><pre style='font-family:monospace; font-size:11px;'>
  SC CMD --&gt; \[S&amp;F Validator\] --&gt; \[Classifier\]
                                     |
                 ext path            |            int path
                 +----+              |            +----+
                 | ext_down_hdr ($od)|            | int_down_hdr ($ihd)
                 | ext_down_pld ($pld)|           | int_down_pld ($ipld)
                 +----+              |            +----+
                      |         cmd_order_fifo         |
                      v              |                 v
                 \[Dispatch FSM\] ----+---- \[CSR Handler\]
                      |                          |
                 Bus Handler                     |
                      |                          |
                 | ext_up_hdr ($od) |         | int_up_hdr ($ihd)
                 | ext_up_pld ($pld)|         | int_up_pld ($ipld)
                 +----+              |        +----+
                      |         reply_order_fifo  |
                      v              |            v
                 \[Reply Assembler\] -+
                      |
                 \[BP FIFO ($bp)\]
                      |
                 SC REPLY out
</pre></html>"

    catch {set_display_item_property buf_diagram_html TEXT $html}
}

# Generate CSR register table (dynamic based on features)
proc sc_hub_v2_update_csr_table {} {
    set ooo [get_parameter_value OOO_ENABLE]
    set ord [get_parameter_value ORD_ENABLE]
    set cap [get_parameter_value HUB_CAP_ENABLE]

    set rows {
        {0x00 ID RO "Fixed ID 0x53480000"}
        {0x01 VERSION RO "Packed version date-style register"}
        {0x02 CTRL RW "Bit 0: enable. Bit 1: clear counters. Bit 2: software reset"}
        {0x03 STATUS RO "Busy, error summary, FIFO state"}
        {0x04 ERR_FLAGS W1C "Overflow, timeout, packet-drop flags"}
        {0x05 ERR_COUNT RO "Saturating 32-bit error counter"}
        {0x06 SCRATCH RW "General-purpose scratch register"}
        {0x07 GTS_SNAP_LO RO "Timestamp snapshot low word"}
        {0x08 GTS_SNAP_HI RO "Timestamp snapshot high + trigger"}
        {0x09 FIFO_CFG RW "Bit 0: S&F enable. Bit 1: upload mode"}
        {0x0A FIFO_STATUS RO "Download/upload FIFO fullness"}
        {0x0B DOWN_PKT_CNT RO "Download packet occupancy"}
        {0x0C UP_PKT_CNT RO "Upload packet occupancy"}
        {0x0D DOWN_USEDW RO "Download FIFO used words"}
        {0x0E UP_USEDW RO "Upload FIFO used words"}
        {0x0F EXT_PKT_RD_CNT RO "External read packet counter"}
        {0x10 EXT_PKT_WR_CNT RO "External write packet counter"}
        {0x11 EXT_WORD_RD_CNT RO "External read word counter"}
        {0x12 EXT_WORD_WR_CNT RO "External write word counter"}
        {0x13 LAST_RD_ADDR RO "Last external read address"}
        {0x14 LAST_RD_DATA RO "Last external read data"}
        {0x15 LAST_WR_ADDR RO "Last external write address"}
        {0x16 LAST_WR_DATA RO "Last external write data"}
        {0x17 PKT_DROP_CNT RO "Malformed packet drop counter"}
    }

    # Conditional registers
    if {$ooo} {
        lappend rows {0x18 OOO_CTRL RW "Bit 0: runtime OoO enable"}
    }
    if {$ord} {
        lappend rows {0x19 ORD_DRAIN_CNT RO "Release drain event counter"}
        lappend rows {0x1A ORD_HOLD_CNT RO "Acquire hold event counter"}
    }
    if {$cap} {
        lappend rows {0x1F HUB_CAP RO "Compile-time capability flags (OoO, ORD, ATM, S&F)"}
    }

    set html "<html><table border='1' cellpadding='3' width='100%'>\n"
    append html "<tr><th>Offset</th><th>Name</th><th>Access</th><th>Description</th></tr>\n"
    foreach row $rows {
        lassign $row offset name access desc
        append html "<tr><td>$offset</td><td><b>$name</b></td><td>$access</td><td>$desc</td></tr>\n"
    }
    append html "</table></html>"

    catch {set_display_item_property csr_table_html TEXT $html}
}
