# ============================================================================
# sc_hub_v2 — GUI Layout and Dynamic Elaboration
#
# Enforced Mu3e packaging layout:
#   Tab 1: Configuration
#   Tab 2: Identity
#   Tab 3: Interfaces
#   Tab 4: Register Map
# ============================================================================

# ----------------------------------------------------------------------------
# Top-level tabs
# ----------------------------------------------------------------------------

set TAB_CONFIGURATION "Configuration"
set TAB_IDENTITY      "Identity"
set TAB_INTERFACES    "Interfaces"
set TAB_REGMAP        "Register Map"

add_display_item "" $TAB_CONFIGURATION GROUP tab
add_display_item "" $TAB_IDENTITY      GROUP tab
add_display_item "" $TAB_INTERFACES    GROUP tab
add_display_item "" $TAB_REGMAP        GROUP tab

# ============================================================================
# TAB 1: Configuration
# ============================================================================

add_display_item $TAB_CONFIGURATION "Overview" GROUP
add_display_item $TAB_CONFIGURATION "Preset Selection" GROUP
add_display_item $TAB_CONFIGURATION "Sizing" GROUP
add_display_item $TAB_CONFIGURATION "Feature Set" GROUP
add_display_item $TAB_CONFIGURATION "Performance" GROUP
add_display_item $TAB_CONFIGURATION "Resources" GROUP
add_display_item $TAB_CONFIGURATION "Debug" GROUP

sc_hub_v2_add_html "Overview" overview_html \
    {<html><b>Function</b><br/>
    <b>sc_hub_v2</b> terminates Mu3e slow-control packets, validates write payloads
    before any external side effect, routes internal CSR accesses locally, and
    issues the resulting transaction stream to an Avalon-MM or AXI4 master
    boundary. Reply assembly remains decoupled by the uplink backpressure FIFO so
    upstream stalls do not change the external bus contract.</html>}
sc_hub_v2_add_html "Overview" buf_diagram_html \
    {<html><i>Architecture summary will appear after elaboration.</i></html>}

add_display_item "Preset Selection" PRESET parameter
sc_hub_v2_add_html "Preset Selection" preset_help_html \
    {<html><b>How presets work</b><br/>
    Selecting a preset reapplies a validated configuration during elaboration.
    Choose <b>CUSTOM</b> to edit parameters manually. The preset name is stored as
    a GUI parameter because Quartus 18.1 does not reliably propagate `.prst`
    state through catalog rescans.</html>}
sc_hub_v2_add_html "Preset Selection" preset_matrix_html \
    {<html><i>Preset matrix table will appear after elaboration.</i></html>}

add_display_item "Sizing" OUTSTANDING_LIMIT parameter
add_display_item "Sizing" OUTSTANDING_INT_RESERVED parameter
add_display_item "Sizing" EXT_DOWN_PLD_DEPTH parameter
add_display_item "Sizing" INT_DOWN_PLD_DEPTH parameter
add_display_item "Sizing" EXT_UP_PLD_DEPTH parameter
add_display_item "Sizing" INT_UP_PLD_DEPTH parameter
add_display_item "Sizing" INT_HDR_DEPTH parameter
add_display_item "Sizing" MAX_BURST parameter
add_display_item "Sizing" BP_FIFO_DEPTH parameter
sc_hub_v2_add_html "Sizing" config_summary_html \
    {<html><i>Configuration summary will appear after elaboration.</i></html>}

add_display_item "Feature Set" BUS_TYPE parameter
add_display_item "Feature Set" ADDR_WIDTH parameter
add_display_item "Feature Set" AXI4_USER_WIDTH parameter
add_display_item "Feature Set" AXI4_ID_WIDTH parameter
add_display_item "Feature Set" OOO_ENABLE parameter
add_display_item "Feature Set" ORD_ENABLE parameter
add_display_item "Feature Set" ORD_NUM_DOMAINS parameter
add_display_item "Feature Set" ATOMIC_ENABLE parameter
add_display_item "Feature Set" S_AND_F_ENABLE parameter
add_display_item "Feature Set" HUB_CAP_ENABLE parameter
add_display_item "Feature Set" BACKPRESSURE parameter
add_display_item "Feature Set" SCHEDULER_USE_PKT_TRANSFER parameter
add_display_item "Feature Set" INVERT_RD_SIG parameter
sc_hub_v2_add_html "Feature Set" feature_note_html \
    {<html><b>Feature notes</b><br/>
    The checked-in Platform Designer wrapper keeps the live Avalon-MM fileset as
    the generated boundary, but the GUI still documents the AXI4-capable core so
    compile-time intent stays visible to integrators.</html>}

sc_hub_v2_add_html "Performance" tlm_summary_html \
    {<html><i>TLM performance data will appear after elaboration.</i></html>}
sc_hub_v2_add_html "Performance" tlm_rate_html \
    {<html><i>Rate-latency preview will appear here.</i></html>}
sc_hub_v2_add_html "Performance" tlm_frag_html \
    {<html><i>Fragmentation preview will appear here.</i></html>}
sc_hub_v2_add_html "Performance" tlm_ord_html \
    {<html><i>Ordering-overhead preview will appear here.</i></html>}

sc_hub_v2_add_html "Resources" resource_summary_html \
    {<html><i>Resource estimates will appear after elaboration.</i></html>}
sc_hub_v2_add_html "Resources" resource_breakdown_html \
    {<html><i>Module-level breakdown will appear after elaboration.</i></html>}
sc_hub_v2_add_html "Resources" resource_compare_html \
    {<html><i>Preset comparison will appear after elaboration.</i></html>}

add_display_item "Debug" DEBUG parameter
add_display_item "Debug" RD_TIMEOUT_CYCLES parameter
add_display_item "Debug" WR_TIMEOUT_CYCLES parameter
sc_hub_v2_add_html "Debug" advanced_html \
    {<html><b>Debug and implementation notes</b><br/>
    1. The internal CSR aperture is fixed at base word address <b>0xFE80</b>.<br/>
    2. Download writes are validated through the store-and-forward path before
       the external command launches.<br/>
    3. The legacy flush path is removed. Read timeout reports an error response
       instead of trying to flush the interconnect.</html>}

# ============================================================================
# TAB 2: Identity
# ============================================================================

add_display_item $TAB_IDENTITY "Delivered Profile" GROUP
add_display_item $TAB_IDENTITY "Versioning" GROUP

sc_hub_v2_add_html "Delivered Profile" identity_profile_html \
    {<html><i>Delivered profile text will appear after elaboration.</i></html>}
add_display_item "Versioning" IP_UID parameter
add_display_item "Versioning" VERSION_MAJOR parameter
add_display_item "Versioning" VERSION_MINOR parameter
add_display_item "Versioning" VERSION_PATCH parameter
add_display_item "Versioning" BUILD parameter
add_display_item "Versioning" VERSION_DATE parameter
add_display_item "Versioning" GIT_STAMP_OVERRIDE parameter
add_display_item "Versioning" VERSION_GIT parameter
add_display_item "Versioning" INSTANCE_ID parameter
sc_hub_v2_add_html "Versioning" id_version_html \
    {<html><i>Version summary will appear after elaboration.</i></html>}

# ============================================================================
# TAB 3: Interfaces
# ============================================================================

add_display_item $TAB_INTERFACES "Clock / Reset" GROUP
add_display_item $TAB_INTERFACES "Packet Links" GROUP
add_display_item $TAB_INTERFACES "Master Bus" GROUP
add_display_item $TAB_INTERFACES "CSR Slave" GROUP

sc_hub_v2_add_html "Clock / Reset" if_clock_html \
    {<html><b>hub_clock</b> and <b>hub_reset</b><br/>
    Single synchronous domain for packet ingress, dispatch, reply assembly, and
    the internal CSR window. No internal CDC is inserted by the wrapper.</html>}

sc_hub_v2_add_html "Packet Links" if_pkt_html \
    {<html><b>download</b> accepts 32-bit Mu3e slow-control words with a 4-bit
    K-character sideband. <b>upload</b> emits the formatted reply packet as a
    36-bit Avalon-ST source with SOP/EOP.</html>}
sc_hub_v2_add_html "Packet Links" if_download_fmt_html {<html>
<b>download</b> — 32-bit conduit sink plus 4-bit datak<br/>
<table border="1" cellpadding="3" width="100%">
<tr><th>Signal</th><th>Bits</th><th>Description</th></tr>
<tr><td><b>i_download_data</b></td><td>31:0</td><td>Mu3e SC word stream. Header, address, payload, and trailer words are all carried here.</td></tr>
<tr><td><b>i_download_datak</b></td><td>3:0</td><td>Per-byte K-character markers from the 8B10B decoder. The header comma appears as byte-lane K on the packet word that starts a transaction.</td></tr>
<tr><td><b>o_download_ready</b></td><td>0</td><td>Hub backpressure toward the packet receiver. Deasserts when ingress buffering cannot safely accept another word.</td></tr>
</table></html>}
sc_hub_v2_add_html "Packet Links" if_upload_fmt_html {<html>
<b>upload</b> — 36-bit Avalon-ST source<br/>
<table border="1" cellpadding="3" width="100%">
<tr><th>Bits / Signal</th><th>Field</th><th>Description</th></tr>
<tr><td><b>aso_upload_data[35:32]</b></td><td>datak</td><td>K-character qualifiers associated with the reply word on bits [31:0].</td></tr>
<tr><td><b>aso_upload_data[31:0]</b></td><td>data</td><td>Mu3e slow-control reply header, payload, and trailer stream.</td></tr>
<tr><td><b>aso_upload_startofpacket</b></td><td>SOP</td><td>Asserted on the first reply word.</td></tr>
<tr><td><b>aso_upload_endofpacket</b></td><td>EOP</td><td>Asserted on the trailer word.</td></tr>
<tr><td><b>aso_upload_valid / ready</b></td><td>Handshake</td><td>Backpressure-safe Avalon-ST transfer handshake for the reply packet.</td></tr>
</table></html>}

sc_hub_v2_add_html "Master Bus" if_bus_html \
    {<html><b>hub</b><br/>
    The core can target either Avalon-MM or AXI4 as its external master
    interface. The current checked-in Platform Designer fileset keeps the live
    Avalon-MM wrapper as the generated boundary, while the GUI still documents
    the AXI4-capable top-level for standalone use.</html>}
sc_hub_v2_add_html "Master Bus" if_bus_avmm_fmt_html {<html>
<b>Avalon-MM master boundary</b><br/>
<table border="1" cellpadding="3" width="100%">
<tr><th>Signal</th><th>Direction</th><th>Description</th></tr>
<tr><td><b>avm_hub_address[17:0]</b></td><td>Out</td><td>Word address of the external SC target.</td></tr>
<tr><td><b>avm_hub_read</b>, <b>avm_hub_write</b></td><td>Out</td><td>Read/write command strobes.</td></tr>
<tr><td><b>avm_hub_writedata[31:0]</b></td><td>Out</td><td>Write payload word for external transactions.</td></tr>
<tr><td><b>avm_hub_readdata[31:0]</b></td><td>In</td><td>Read payload word returned by the interconnect.</td></tr>
<tr><td><b>avm_hub_waitrequest</b>, <b>avm_hub_readdatavalid</b>, <b>avm_hub_writeresponsevalid</b></td><td>In</td><td>Bus completion and backpressure handshake signals.</td></tr>
<tr><td><b>avm_hub_response[1:0]</b></td><td>In</td><td>Response code propagated into the SC reply packet.</td></tr>
<tr><td><b>avm_hub_burstcount[8:0]</b></td><td>Out</td><td>Requested burst length in words.</td></tr>
</table></html>}
sc_hub_v2_add_html "Master Bus" if_bus_axi4_fmt_html {<html>
<b>AXI4 master boundary</b><br/>
<table border="1" cellpadding="3" width="100%">
<tr><th>Channel</th><th>Signals</th><th>Description</th></tr>
<tr><td><b>AW</b></td><td>m_axi_aw*</td><td>Write address channel for burst descriptors.</td></tr>
<tr><td><b>W</b></td><td>m_axi_w*</td><td>Write payload data and strobes.</td></tr>
<tr><td><b>B</b></td><td>m_axi_b*</td><td>Write response completion channel.</td></tr>
<tr><td><b>AR</b></td><td>m_axi_ar*</td><td>Read address channel for burst descriptors.</td></tr>
<tr><td><b>R</b></td><td>m_axi_r*</td><td>Read payload data and completion channel.</td></tr>
</table></html>}

sc_hub_v2_add_html "CSR Slave" if_csr_html {<html>
<b>csr</b> — Avalon-MM slave<br/>
The internal CSR window occupies word addresses <b>0xFE80..0xFE9F</b> in the
slow-control address space. Words 0 and 1 implement the common Mu3e identity
header (UID + META page mux).</html>}

# ============================================================================
# TAB 4: Register Map
# ============================================================================

add_display_item $TAB_REGMAP "CSR Window" GROUP
add_display_item $TAB_REGMAP "META Fields (0x01)" GROUP
add_display_item $TAB_REGMAP "CTRL Fields (0x02)" GROUP
add_display_item $TAB_REGMAP "STATUS Fields (0x03)" GROUP
add_display_item $TAB_REGMAP "ERR_FLAGS Fields (0x04)" GROUP
add_display_item $TAB_REGMAP "FIFO_CFG Fields (0x09)" GROUP
add_display_item $TAB_REGMAP "FIFO_STATUS Fields (0x0A)" GROUP
add_display_item $TAB_REGMAP "OOO_CTRL Fields (0x18)" GROUP
add_display_item $TAB_REGMAP "HUB_CAP Fields (0x1F)" GROUP

sc_hub_v2_add_html "CSR Window" csr_table_html \
    {<html><i>CSR register table will appear after elaboration.</i></html>}
sc_hub_v2_add_html "META Fields (0x01)" meta_fields_html {<html>
<table border="1" cellpadding="3" width="100%">
<tr><th>Bits</th><th>Name</th><th>Access</th><th>Description</th></tr>
<tr><td>1:0</td><td>page_sel</td><td>RW</td><td>Selects the META readback page: 0=VERSION, 1=DATE, 2=GIT, 3=INSTANCE_ID.</td></tr>
<tr><td>31:2</td><td>reserved</td><td>RO</td><td>Reserved, read as zero.</td></tr>
</table></html>}
sc_hub_v2_add_html "CTRL Fields (0x02)" ctrl_fields_html {<html>
<table border="1" cellpadding="3" width="100%">
<tr><th>Bit</th><th>Name</th><th>Access</th><th>Description</th></tr>
<tr><td>0</td><td>enable</td><td>RW</td><td>Global enable for packet execution.</td></tr>
<tr><td>1</td><td>diag_clear</td><td>W1C</td><td>Clears software-visible counters and sticky diagnostics.</td></tr>
<tr><td>2</td><td>soft_reset</td><td>W1S</td><td>Requests a local soft reset pulse.</td></tr>
<tr><td>31:3</td><td>reserved</td><td>RO</td><td>Reserved, read as zero.</td></tr>
</table></html>}
sc_hub_v2_add_html "STATUS Fields (0x03)" status_fields_html {<html>
<table border="1" cellpadding="3" width="100%">
<tr><th>Bit</th><th>Name</th><th>Access</th><th>Description</th></tr>
<tr><td>0</td><td>busy</td><td>RO</td><td>Core FSM is not in the idle state.</td></tr>
<tr><td>1</td><td>error</td><td>RO</td><td>Error summary bit derived from ERR_FLAGS.</td></tr>
<tr><td>2</td><td>dl_fifo_full</td><td>RO</td><td>Download-side FIFO is full.</td></tr>
<tr><td>3</td><td>bp_full</td><td>RO</td><td>Reply backpressure FIFO is full.</td></tr>
<tr><td>4</td><td>enable_state</td><td>RO</td><td>Current latched enable state.</td></tr>
<tr><td>5</td><td>bus_busy</td><td>RO</td><td>External bus handler is busy.</td></tr>
<tr><td>31:6</td><td>reserved</td><td>RO</td><td>Reserved, read as zero.</td></tr>
</table></html>}
sc_hub_v2_add_html "ERR_FLAGS Fields (0x04)" err_flags_fields_html {<html>
<table border="1" cellpadding="3" width="100%">
<tr><th>Bit</th><th>Name</th><th>Access</th><th>Description</th></tr>
<tr><td>0</td><td>up_overflow</td><td>RW1C</td><td>Upload/backpressure FIFO overflow observed.</td></tr>
<tr><td>1</td><td>down_overflow</td><td>RW1C</td><td>Download ingress FIFO overflow observed.</td></tr>
<tr><td>2</td><td>int_addr_err</td><td>RW1C</td><td>Internal CSR access targeted an unmapped word.</td></tr>
<tr><td>3</td><td>rd_timeout</td><td>RW1C</td><td>External read timed out.</td></tr>
<tr><td>4</td><td>pkt_drop</td><td>RW1C</td><td>Malformed or truncated packet was dropped before execution.</td></tr>
<tr><td>5</td><td>slverr</td><td>RW1C</td><td>Slave error returned by the external bus.</td></tr>
<tr><td>6</td><td>decerr</td><td>RW1C</td><td>Decode error returned by the external bus.</td></tr>
<tr><td>31:7</td><td>reserved</td><td>RO</td><td>Reserved, read as zero.</td></tr>
</table></html>}
sc_hub_v2_add_html "FIFO_CFG Fields (0x09)" fifo_cfg_fields_html {<html>
<table border="1" cellpadding="3" width="100%">
<tr><th>Bit</th><th>Name</th><th>Access</th><th>Description</th></tr>
<tr><td>0</td><td>backpressure_on</td><td>RO</td><td>Reply FIFO/backpressure path present in this build.</td></tr>
<tr><td>1</td><td>store_forward</td><td>RO</td><td>Write packets are validated before any external side effect.</td></tr>
<tr><td>31:2</td><td>reserved</td><td>RO</td><td>Reserved, read as zero.</td></tr>
</table></html>}
sc_hub_v2_add_html "FIFO_STATUS Fields (0x0A)" fifo_status_fields_html {<html>
<table border="1" cellpadding="3" width="100%">
<tr><th>Bit</th><th>Name</th><th>Access</th><th>Description</th></tr>
<tr><td>0</td><td>dl_full</td><td>RO</td><td>Download FIFO full.</td></tr>
<tr><td>1</td><td>bp_full</td><td>RO</td><td>Reply/backpressure FIFO full.</td></tr>
<tr><td>2</td><td>dl_overflow</td><td>RO</td><td>Download FIFO overflow sticky summary.</td></tr>
<tr><td>3</td><td>bp_overflow</td><td>RO</td><td>Reply/backpressure FIFO overflow sticky summary.</td></tr>
<tr><td>4</td><td>rd_fifo_full</td><td>RO</td><td>Read-data staging FIFO full.</td></tr>
<tr><td>5</td><td>rd_fifo_empty</td><td>RO</td><td>Read-data staging FIFO empty.</td></tr>
<tr><td>31:6</td><td>reserved</td><td>RO</td><td>Reserved, read as zero.</td></tr>
</table></html>}
sc_hub_v2_add_html "OOO_CTRL Fields (0x18)" ooo_ctrl_fields_html {<html>
<table border="1" cellpadding="3" width="100%">
<tr><th>Bit</th><th>Name</th><th>Access</th><th>Description</th></tr>
<tr><td>0</td><td>ooo_runtime_enable</td><td>RW</td><td>Runtime request to enable out-of-order completion. Only effective when <b>OOO_ENABLE=true</b> at compile time.</td></tr>
<tr><td>31:1</td><td>reserved</td><td>RO</td><td>Reserved, read as zero.</td></tr>
</table></html>}
sc_hub_v2_add_html "HUB_CAP Fields (0x1F)" hub_cap_fields_html {<html>
<table border="1" cellpadding="3" width="100%">
<tr><th>Bit</th><th>Name</th><th>Access</th><th>Description</th></tr>
<tr><td>0</td><td>ooo_capable</td><td>RO</td><td>Compile-time out-of-order support synthesized.</td></tr>
<tr><td>1</td><td>ordering_capable</td><td>RO</td><td>Compile-time acquire/release ordering tracker synthesized.</td></tr>
<tr><td>2</td><td>atomic_capable</td><td>RO</td><td>Compile-time atomic read-modify-write support synthesized.</td></tr>
<tr><td>3</td><td>identity_header</td><td>RO</td><td>Common Mu3e UID + META identity header implemented at words 0x00 and 0x01.</td></tr>
<tr><td>31:4</td><td>reserved</td><td>RO</td><td>Reserved, read as zero.</td></tr>
</table></html>}

# ----------------------------------------------------------------------------
# Dynamic GUI update
# ----------------------------------------------------------------------------

proc sc_hub_v2_update_gui {} {
    set bus        [string toupper [get_parameter_value BUS_TYPE]]
    set ooo        [get_parameter_value OOO_ENABLE]
    set ord        [get_parameter_value ORD_ENABLE]
    set atm        [get_parameter_value ATOMIC_ENABLE]
    set preset     [get_parameter_value PRESET]
    set is_custom  [expr {$preset eq "CUSTOM"}]
    set axi4_vis   [expr {$bus eq "AXI4"}]
    set git_override [get_parameter_value GIT_STAMP_OVERRIDE]

    sc_hub_v2_show_param AXI4_USER_WIDTH $axi4_vis
    sc_hub_v2_show_param AXI4_ID_WIDTH $axi4_vis
    sc_hub_v2_show_param ORD_NUM_DOMAINS $ord
    sc_hub_v2_show_item if_bus_avmm_fmt_html [expr {!$axi4_vis}]
    sc_hub_v2_show_item if_bus_axi4_fmt_html $axi4_vis

    foreach p {BUS_TYPE ADDR_WIDTH OUTSTANDING_LIMIT OUTSTANDING_INT_RESERVED \
               EXT_DOWN_PLD_DEPTH INT_DOWN_PLD_DEPTH EXT_UP_PLD_DEPTH INT_UP_PLD_DEPTH \
               INT_HDR_DEPTH MAX_BURST BP_FIFO_DEPTH OOO_ENABLE ORD_ENABLE \
               ORD_NUM_DOMAINS ATOMIC_ENABLE S_AND_F_ENABLE HUB_CAP_ENABLE \
               RD_TIMEOUT_CYCLES WR_TIMEOUT_CYCLES AXI4_USER_WIDTH AXI4_ID_WIDTH \
               DEBUG} {
        catch {set_parameter_property $p ENABLED $is_custom}
    }
    catch {set_parameter_property VERSION_GIT ENABLED $git_override}

    if {$ooo && $bus eq "AVALON"} {
        send_message warning "OOO_ENABLE=true with BUS_TYPE=AVALON: Avalon-MM still returns data in order. OoO remains useful mainly for local bypass and documentation alignment."
    }

    set od       [get_parameter_value OUTSTANDING_LIMIT]
    set ir       [get_parameter_value OUTSTANDING_INT_RESERVED]
    set pld      [get_parameter_value EXT_DOWN_PLD_DEPTH]
    set upld     [get_parameter_value EXT_UP_PLD_DEPTH]
    set mb       [get_parameter_value MAX_BURST]
    set eff_ext  [expr {$od - $ir}]
    set ooo_str  [expr {$ooo ? "<span style='color:green'>Enabled</span>" : "Disabled"}]
    set ord_str  [expr {$ord ? "<span style='color:green'>Enabled</span>" : "Disabled"}]
    set atm_str  [expr {$atm ? "<span style='color:green'>Enabled</span>" : "Disabled"}]

    set summary_html "<html><table border='1' cellpadding='4' width='100%'>"
    append summary_html "<tr><td><b>Preset</b></td><td>$preset</td></tr>"
    append summary_html "<tr><td><b>Bus</b></td><td>$bus</td></tr>"
    append summary_html "<tr><td><b>Outstanding slots</b></td><td>$od total ($eff_ext external + $ir internal reserved)</td></tr>"
    append summary_html "<tr><td><b>Payload RAM</b></td><td>ext down $pld words, ext up $upld words</td></tr>"
    append summary_html "<tr><td><b>Max burst</b></td><td>$mb words</td></tr>"
    append summary_html "<tr><td><b>OoO</b></td><td>$ooo_str</td></tr>"
    append summary_html "<tr><td><b>Ordering</b></td><td>$ord_str</td></tr>"
    append summary_html "<tr><td><b>Atomic</b></td><td>$atm_str</td></tr>"
    append summary_html "</table></html>"

    catch {set_display_item_property config_summary_html TEXT $summary_html}
    catch {set_display_item_property preset_matrix_html TEXT [sc_hub_v2_preset_summary_html]}

    sc_hub_v2_update_identity_html
    sc_hub_v2_update_buf_diagram
    sc_hub_v2_update_csr_table
}

proc sc_hub_v2_update_identity_html {} {
    set version_str [sc_hub_v2_version_string_from_params]
    set uid_hex     [sc_hub_v2_format_hex [get_parameter_value IP_UID] 8]
    set git_hex     [sc_hub_v2_format_hex [get_parameter_value VERSION_GIT] 8]
    set date_val    [get_parameter_value VERSION_DATE]
    set instance_id [get_parameter_value INSTANCE_ID]
    set bus         [string toupper [get_parameter_value BUS_TYPE]]

    set profile_html "<html><b>Delivered profile</b><br/>"
    append profile_html "This packaged release is <b>$version_str</b>. Platform Designer exposes the "
    append profile_html "<b>sc_hub_v2</b> catalog component while the runtime CSR window exposes the common "
    append profile_html "Mu3e identity header at words <b>0x00 UID</b> and <b>0x01 META</b>.<br/><br/>"
    append profile_html "<b>Live wrapper intent</b><br/>The checked-in fileset keeps the Avalon-MM top-level "
    append profile_html "for generated systems. BUS_TYPE currently selects the documented external contract "
    append profile_html "for standalone analysis; current GUI value: <b>$bus</b>.</html>"
    catch {set_display_item_property identity_profile_html TEXT $profile_html}

    set version_html "<html><b>Catalog version</b><br/>"
    append version_html "Platform Designer sees <b>NAME=sc_hub_v2</b> and <b>VERSION=$version_str</b>.<br/><br/>"
    append version_html "<table border='1' cellpadding='3' width='100%'>"
    append version_html "<tr><th>Field</th><th>Value</th><th>Runtime visibility</th></tr>"
    append version_html "<tr><td><b>IP_UID</b></td><td>$uid_hex</td><td>CSR word 0x00</td></tr>"
    append version_html "<tr><td><b>VERSION</b></td><td>$version_str</td><td>META page 0</td></tr>"
    append version_html "<tr><td><b>VERSION_DATE</b></td><td>$date_val</td><td>META page 1</td></tr>"
    append version_html "<tr><td><b>VERSION_GIT</b></td><td>$git_hex</td><td>META page 2</td></tr>"
    append version_html "<tr><td><b>INSTANCE_ID</b></td><td>$instance_id</td><td>META page 3</td></tr>"
    append version_html "</table></html>"
    catch {set_display_item_property id_version_html TEXT $version_html}
}

proc sc_hub_v2_update_buf_diagram {} {
    set od    [get_parameter_value OUTSTANDING_LIMIT]
    set pld   [get_parameter_value EXT_DOWN_PLD_DEPTH]
    set upld  [get_parameter_value EXT_UP_PLD_DEPTH]
    set ipld  [get_parameter_value INT_DOWN_PLD_DEPTH]
    set iupld [get_parameter_value INT_UP_PLD_DEPTH]
    set ihd   [get_parameter_value INT_HDR_DEPTH]
    set bp    [get_parameter_value BP_FIFO_DEPTH]

    set html "<html><pre style='font-family:monospace; font-size:11px;'>"
    append html "  SC CMD --> [pkt_rx + validator] --> [classifier]\n"
    append html "                                      |             \n"
    append html "                 ext path            |            int path\n"
    append html "                 +-------------------+-------------------+\n"
    append html "                 | ext_down_hdr ($od) | int_down_hdr ($ihd) |\n"
    append html "                 | ext_down_pld ($pld)| int_down_pld ($ipld)|\n"
    append html "                 +---------+----------+----------+--------+\n"
    append html "                           | cmd_order_fifo      |\n"
    append html "                           v                     v\n"
    append html "                      [dispatch FSM]      [CSR handler]\n"
    append html "                           |                     |\n"
    append html "                    [bus handler]               |\n"
    append html "                           |                     |\n"
    append html "                 | ext_up_pld ($upld) | int_up_pld ($iupld) |\n"
    append html "                 +----------+----------+----------+---------+\n"
    append html "                            \\         reply assembler      \n"
    append html "                             +-----------> [BP FIFO ($bp)] --> SC REPLY\n"
    append html "</pre></html>"

    catch {set_display_item_property buf_diagram_html TEXT $html}
}

proc sc_hub_v2_update_csr_table {} {
    set rows {
        {0x00 UID RO "Immutable Mu3e IP identifier. Default ASCII 'SCHB'."}
        {0x01 META RW/RO "Write page selector[1:0]. Read selected page: VERSION / DATE / GIT / INSTANCE_ID."}
        {0x02 CTRL RW "Enable, diagnostic clear, and software reset control word."}
        {0x03 STATUS RO "Busy/error summary and FIFO/bus state."}
        {0x04 ERR_FLAGS RW1C "Sticky overflow, timeout, packet-drop, and bus error flags."}
        {0x05 ERR_COUNT RO "Saturating 32-bit error counter."}
        {0x06 SCRATCH RW "General-purpose software scratch register."}
        {0x07 GTS_SNAP_LO RO "Global timestamp snapshot low word."}
        {0x08 GTS_SNAP_HI RO "Global timestamp snapshot high word. Reading triggers a fresh snapshot."}
        {0x09 FIFO_CFG RO "Backpressure/store-and-forward configuration summary."}
        {0x0A FIFO_STATUS RO "Download, reply, and read-data FIFO state summary."}
        {0x0B DOWN_PKT_CNT RO "Download packet occupancy summary bit."}
        {0x0C UP_PKT_CNT RO "Reply FIFO packet count."}
        {0x0D DOWN_USEDW RO "Download FIFO used words."}
        {0x0E UP_USEDW RO "Reply FIFO used words."}
        {0x0F EXT_PKT_RD RO "External read packet counter."}
        {0x10 EXT_PKT_WR RO "External write packet counter."}
        {0x11 EXT_WORD_RD RO "External read word counter."}
        {0x12 EXT_WORD_WR RO "External write word counter."}
        {0x13 LAST_RD_ADDR RO "Last external read address."}
        {0x14 LAST_RD_DATA RO "Last external read data."}
        {0x15 LAST_WR_ADDR RO "Last external write address."}
        {0x16 LAST_WR_DATA RO "Last external write data."}
        {0x17 PKT_DROP_CNT RO "Malformed-packet drop counter."}
        {0x18 OOO_CTRL RW "Runtime OoO enable request. Only effective when OOO support is synthesized."}
        {0x19 ORD_DRAIN_CNT RO "Release drain event counter."}
        {0x1A ORD_HOLD_CNT RO "Acquire hold event counter."}
        {0x1B DBG_DROP_DETAIL RO "Last dropped-packet debug detail word."}
        {0x1F HUB_CAP RO "Compile-time capability bits and identity-header presence."}
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
