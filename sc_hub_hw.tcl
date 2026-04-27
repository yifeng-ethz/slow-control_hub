# ============================================================================
# sc_hub "Slow Control Hub" v26.6.9.0414
# Yifeng Wang 2026.04.14
#
# Compatibility-facing Platform Designer wrapper around the canonical sc_hub v2
# Avalon-MM top-level.
# ============================================================================

package require -exact qsys 16.1

set sc_hub_hw_dir [file dirname [file normalize [info script]]]

set SC_HUB_IP_UID_DEFAULT_CONST        [expr {0x53434842}] ;# ASCII "SCHB"
set SC_HUB_VERSION_MAJOR_DEFAULT_CONST 26
set SC_HUB_VERSION_MINOR_DEFAULT_CONST 6
set SC_HUB_VERSION_PATCH_DEFAULT_CONST 9
set SC_HUB_BUILD_DEFAULT_CONST         414
set SC_HUB_VERSION_DATE_DEFAULT_CONST  20260414
set SC_HUB_VERSION_GIT_DEFAULT_CONST   0
set SC_HUB_INSTANCE_ID_DEFAULT_CONST   0

if {![catch {
    set sc_hub_git_short [string trim [exec git -C $sc_hub_hw_dir rev-parse --short HEAD]]
}]} {
    if {[regexp {^[0-9a-fA-F]+$} $sc_hub_git_short]} {
        scan $sc_hub_git_short %x SC_HUB_VERSION_GIT_DEFAULT_CONST
    }
}

set_module_property NAME sc_hub
set_module_property DISPLAY_NAME "Slow Control Hub Mu3E IP"
set_module_property VERSION 26.6.9.0414
set_module_property DESCRIPTION "Slow Control Hub Mu3e IP Core"
set_module_property GROUP "Mu3e Control Plane/Modules"
set_module_property AUTHOR "Yifeng Wang"
set_module_property INTERNAL false
set_module_property OPAQUE_ADDRESS_MAP true
set_module_property INSTANTIATE_IN_SYSTEM_MODULE true
set_module_property EDITABLE true
set_module_property REPORT_TO_TALKBACK false
set_module_property ALLOW_GREYBOX_GENERATION false
set_module_property REPORT_HIERARCHY false
set_module_property ELABORATION_CALLBACK sc_hub_elaborate
set_module_property VALIDATION_CALLBACK sc_hub_validate
set_module_property ICON_PATH ../firmware_builds/misc/logo/mu3e_logo.png

proc add_html_text {group_name item_name html_text} {
    add_display_item $group_name $item_name TEXT ""
    set_display_item_property $item_name DISPLAY_HINT html
    set_display_item_property $item_name TEXT $html_text
}

proc sc_hub_add_interface {interface_name interface_kind interface_dir} {
    uplevel 1 [list add_interface $interface_name $interface_kind $interface_dir]
}

proc sc_hub_add_interface_port {interface_name port_name role direction width} {
    uplevel 1 [list add_interface_port $interface_name $port_name $role $direction $width]
}

proc sc_hub_format_hex {value width} {
    set mask [expr {(1 << ($width * 4)) - 1}]
    return [format "0x%0*X" $width [expr {$value & $mask}]]
}

proc sc_hub_version_string {} {
    return [format "%d.%d.%d.%04d" \
        [get_parameter_value VERSION_MAJOR] \
        [get_parameter_value VERSION_MINOR] \
        [get_parameter_value VERSION_PATCH] \
        [get_parameter_value BUILD]]
}

set CSR_TABLE_HTML {<html><table border="1" cellpadding="3" width="100%">
<tr><th>Word</th><th>Name</th><th>Access</th><th>Description</th></tr>
<tr><td>0x00</td><td>UID</td><td>RO</td><td>Immutable Mu3e IP identifier. Default ASCII "SCHB".</td></tr>
<tr><td>0x01</td><td>META</td><td>RW/RO</td><td>Write page selector[1:0]. Read selected page: VERSION / DATE / GIT / INSTANCE_ID.</td></tr>
<tr><td>0x02</td><td>CTRL</td><td>RW</td><td>Enable, diagnostic clear, and software reset control word.</td></tr>
<tr><td>0x03</td><td>STATUS</td><td>RO</td><td>Busy/error summary and FIFO/bus state.</td></tr>
<tr><td>0x04</td><td>ERR_FLAGS</td><td>RW1C</td><td>Sticky overflow, timeout, packet-drop, and bus error flags.</td></tr>
<tr><td>0x05</td><td>ERR_COUNT</td><td>RO</td><td>Saturating 32-bit error counter.</td></tr>
<tr><td>0x06</td><td>SCRATCH</td><td>RW</td><td>General-purpose software scratch register.</td></tr>
<tr><td>0x07</td><td>GTS_SNAP_LO</td><td>RO</td><td>Global timestamp snapshot low word.</td></tr>
<tr><td>0x08</td><td>GTS_SNAP_HI</td><td>RO</td><td>Global timestamp snapshot high word. Reading triggers a fresh snapshot.</td></tr>
<tr><td>0x09</td><td>FIFO_CFG</td><td>RO</td><td>Backpressure/store-and-forward configuration summary.</td></tr>
<tr><td>0x0A</td><td>FIFO_STATUS</td><td>RO</td><td>Download, reply, and read-data FIFO state summary.</td></tr>
<tr><td>0x0B</td><td>DOWN_PKT_CNT</td><td>RO</td><td>Download packet occupancy summary bit.</td></tr>
<tr><td>0x0C</td><td>UP_PKT_CNT</td><td>RO</td><td>Reply FIFO packet count.</td></tr>
<tr><td>0x0D</td><td>DOWN_USEDW</td><td>RO</td><td>Download FIFO used words.</td></tr>
<tr><td>0x0E</td><td>UP_USEDW</td><td>RO</td><td>Reply FIFO used words.</td></tr>
<tr><td>0x0F</td><td>EXT_PKT_RD</td><td>RO</td><td>External read packet counter.</td></tr>
<tr><td>0x10</td><td>EXT_PKT_WR</td><td>RO</td><td>External write packet counter.</td></tr>
<tr><td>0x11</td><td>EXT_WORD_RD</td><td>RO</td><td>External read word counter.</td></tr>
<tr><td>0x12</td><td>EXT_WORD_WR</td><td>RO</td><td>External write word counter.</td></tr>
<tr><td>0x13</td><td>LAST_RD_ADDR</td><td>RO</td><td>Last external read address.</td></tr>
<tr><td>0x14</td><td>LAST_RD_DATA</td><td>RO</td><td>Last external read data.</td></tr>
<tr><td>0x15</td><td>LAST_WR_ADDR</td><td>RO</td><td>Last external write address.</td></tr>
<tr><td>0x16</td><td>LAST_WR_DATA</td><td>RO</td><td>Last external write data.</td></tr>
<tr><td>0x17</td><td>PKT_DROP_CNT</td><td>RO</td><td>Malformed-packet drop counter.</td></tr>
<tr><td>0x18</td><td>OOO_CTRL</td><td>RW</td><td>Runtime OoO enable request. Only effective when OOO support is synthesized.</td></tr>
<tr><td>0x19</td><td>ORD_DRAIN_CNT</td><td>RO</td><td>Release drain event counter.</td></tr>
<tr><td>0x1A</td><td>ORD_HOLD_CNT</td><td>RO</td><td>Acquire hold event counter.</td></tr>
<tr><td>0x1B</td><td>DBG_DROP_DETAIL</td><td>RO</td><td>Last dropped-packet debug detail word.</td></tr>
<tr><td>0x1C</td><td>FEB_TYPE</td><td>RW</td><td>Local detector-class selector used by M/S/T packet masking: 0=ALL, 1=MUPIX, 2=SCIFI, 3=TILE.</td></tr>
<tr><td>0x1F</td><td>HUB_CAP</td><td>RO</td><td>Compile-time capability bits and identity-header presence.</td></tr>
</table></html>}

set META_FIELDS_HTML {<html><table border="1" cellpadding="3" width="100%">
<tr><th>Bits</th><th>Name</th><th>Access</th><th>Description</th></tr>
<tr><td>1:0</td><td>page_sel</td><td>RW</td><td>Selects the META readback page: 0=VERSION, 1=DATE, 2=GIT, 3=INSTANCE_ID.</td></tr>
<tr><td>31:2</td><td>reserved</td><td>RO</td><td>Reserved, read as zero.</td></tr>
</table></html>}

set CTRL_FIELDS_HTML {<html><table border="1" cellpadding="3" width="100%">
<tr><th>Bit</th><th>Name</th><th>Access</th><th>Description</th></tr>
<tr><td>0</td><td>enable</td><td>RW</td><td>Global enable for packet execution.</td></tr>
<tr><td>1</td><td>diag_clear</td><td>W1C</td><td>Clears software-visible counters and sticky diagnostics.</td></tr>
<tr><td>2</td><td>soft_reset</td><td>W1S</td><td>Requests a local soft reset pulse.</td></tr>
<tr><td>31:3</td><td>reserved</td><td>RO</td><td>Reserved, read as zero.</td></tr>
</table></html>}

set STATUS_FIELDS_HTML {<html><table border="1" cellpadding="3" width="100%">
<tr><th>Bit</th><th>Name</th><th>Access</th><th>Description</th></tr>
<tr><td>0</td><td>busy</td><td>RO</td><td>Core FSM is not idle.</td></tr>
<tr><td>1</td><td>error</td><td>RO</td><td>Error summary derived from ERR_FLAGS.</td></tr>
<tr><td>2</td><td>dl_fifo_full</td><td>RO</td><td>Download FIFO full.</td></tr>
<tr><td>3</td><td>bp_full</td><td>RO</td><td>Reply/backpressure FIFO full.</td></tr>
<tr><td>4</td><td>enable_state</td><td>RO</td><td>Current latched enable state.</td></tr>
<tr><td>5</td><td>bus_busy</td><td>RO</td><td>External bus handler is busy.</td></tr>
<tr><td>31:6</td><td>reserved</td><td>RO</td><td>Reserved, read as zero.</td></tr>
</table></html>}

set ERR_FLAGS_FIELDS_HTML {<html><table border="1" cellpadding="3" width="100%">
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

set FIFO_CFG_FIELDS_HTML {<html><table border="1" cellpadding="3" width="100%">
<tr><th>Bit</th><th>Name</th><th>Access</th><th>Description</th></tr>
<tr><td>0</td><td>backpressure_on</td><td>RO</td><td>Reply FIFO/backpressure path present in this build.</td></tr>
<tr><td>1</td><td>store_forward</td><td>RO</td><td>Write packets are validated before any external side effect.</td></tr>
<tr><td>31:2</td><td>reserved</td><td>RO</td><td>Reserved, read as zero.</td></tr>
</table></html>}

set FIFO_STATUS_FIELDS_HTML {<html><table border="1" cellpadding="3" width="100%">
<tr><th>Bit</th><th>Name</th><th>Access</th><th>Description</th></tr>
<tr><td>0</td><td>dl_full</td><td>RO</td><td>Download FIFO full.</td></tr>
<tr><td>1</td><td>bp_full</td><td>RO</td><td>Reply/backpressure FIFO full.</td></tr>
<tr><td>2</td><td>dl_overflow</td><td>RO</td><td>Download FIFO overflow sticky summary.</td></tr>
<tr><td>3</td><td>bp_overflow</td><td>RO</td><td>Reply/backpressure FIFO overflow sticky summary.</td></tr>
<tr><td>4</td><td>rd_fifo_full</td><td>RO</td><td>Read-data staging FIFO full.</td></tr>
<tr><td>5</td><td>rd_fifo_empty</td><td>RO</td><td>Read-data staging FIFO empty.</td></tr>
<tr><td>31:6</td><td>reserved</td><td>RO</td><td>Reserved, read as zero.</td></tr>
</table></html>}

set OOO_CTRL_FIELDS_HTML {<html><table border="1" cellpadding="3" width="100%">
<tr><th>Bit</th><th>Name</th><th>Access</th><th>Description</th></tr>
<tr><td>0</td><td>ooo_runtime_enable</td><td>RW</td><td>Runtime request to enable out-of-order completion. Only effective when <b>OOO_ENABLE=true</b> at compile time.</td></tr>
<tr><td>31:1</td><td>reserved</td><td>RO</td><td>Reserved, read as zero.</td></tr>
</table></html>}

set HUB_CAP_FIELDS_HTML {<html><table border="1" cellpadding="3" width="100%">
<tr><th>Bit</th><th>Name</th><th>Access</th><th>Description</th></tr>
<tr><td>0</td><td>ooo_capable</td><td>RO</td><td>Compile-time out-of-order support synthesized.</td></tr>
<tr><td>1</td><td>ordering_capable</td><td>RO</td><td>Compile-time acquire/release ordering tracker synthesized.</td></tr>
<tr><td>2</td><td>atomic_capable</td><td>RO</td><td>Compile-time atomic read-modify-write support synthesized.</td></tr>
<tr><td>3</td><td>identity_header</td><td>RO</td><td>Common Mu3e UID + META identity header implemented at words 0x00 and 0x01.</td></tr>
<tr><td>31:4</td><td>reserved</td><td>RO</td><td>Reserved, read as zero.</td></tr>
</table></html>}

proc sc_hub_validate {} {
    set bus_type [string toupper [get_parameter_value BUS_TYPE]]
    set debug_level [get_parameter_value DEBUG]

    if {$bus_type ne "AVALON" && $bus_type ne "AXI4"} {
        send_message error "BUS_TYPE must be AVALON or AXI4. Got $bus_type."
    }

    if {$bus_type eq "AXI4"} {
        send_message error "BUS_TYPE=AXI4 is not supported by the current Platform Designer generation flow for sc_hub. Use AVALON for regenerated systems until a dedicated AXI4 wrapper is packaged."
    }

    if {$debug_level < 0 || $debug_level > 4} {
        send_message error "DEBUG must stay in the range 0..4."
    }
}

proc validate {} {
    sc_hub_validate
}

proc add_avmm_master_interface {} {
    if {[catch {
        add_interface hub_master avalon start
        set_interface_property hub_master addressUnits WORDS
        set_interface_property hub_master associatedClock hub_clock
        set_interface_property hub_master associatedReset hub_reset
        set_interface_property hub_master bitsPerSymbol 8
        set_interface_property hub_master burstOnBurstBoundariesOnly false
        set_interface_property hub_master burstcountUnits WORDS
        set_interface_property hub_master doStreamReads false
        set_interface_property hub_master doStreamWrites false
        set_interface_property hub_master holdTime 0
        set_interface_property hub_master linewrapBursts false
        set_interface_property hub_master maximumPendingReadTransactions 1
        set_interface_property hub_master maximumPendingWriteTransactions 1
        set_interface_property hub_master readLatency 0
        set_interface_property hub_master readWaitTime 1
        set_interface_property hub_master registerIncomingSignals false
        set_interface_property hub_master setupTime 0
        set_interface_property hub_master timingUnits Cycles
        set_interface_property hub_master writeWaitTime 0
        set_interface_property hub_master ENABLED true

        add_interface_port hub_master avm_hub_address address Output 18
        add_interface_port hub_master avm_hub_read read Output 1
        add_interface_port hub_master avm_hub_readdata readdata Input 32
        add_interface_port hub_master avm_hub_writeresponsevalid writeresponsevalid Input 1
        add_interface_port hub_master avm_hub_response response Input 2
        add_interface_port hub_master avm_hub_write write Output 1
        add_interface_port hub_master avm_hub_writedata writedata Output 32
        add_interface_port hub_master avm_hub_waitrequest waitrequest Input 1
        add_interface_port hub_master avm_hub_readdatavalid readdatavalid Input 1
        add_interface_port hub_master avm_hub_burstcount burstcount Output 9
    } err_msg]} {
        send_message error "add_avmm_master_interface failed: $err_msg"
    }
}

proc add_axi4_master_interface {} {
    if {[catch {
        sc_hub_add_interface hub_master axi4 start
        set_interface_property hub_master associatedClock hub_clock
        set_interface_property hub_master associatedReset hub_reset
        set_interface_property hub_master ENABLED true

        sc_hub_add_interface_port hub_master m_axi_awid awid Output 4
        sc_hub_add_interface_port hub_master m_axi_awaddr awaddr Output 18
        sc_hub_add_interface_port hub_master m_axi_awlen awlen Output 8
        sc_hub_add_interface_port hub_master m_axi_awsize awsize Output 3
        sc_hub_add_interface_port hub_master m_axi_awburst awburst Output 2
        sc_hub_add_interface_port hub_master m_axi_awvalid awvalid Output 1
        sc_hub_add_interface_port hub_master m_axi_awready awready Input 1
        sc_hub_add_interface_port hub_master m_axi_wdata wdata Output 32
        sc_hub_add_interface_port hub_master m_axi_wstrb wstrb Output 4
        sc_hub_add_interface_port hub_master m_axi_wlast wlast Output 1
        sc_hub_add_interface_port hub_master m_axi_wvalid wvalid Output 1
        sc_hub_add_interface_port hub_master m_axi_wready wready Input 1
        sc_hub_add_interface_port hub_master m_axi_bid bid Input 4
        sc_hub_add_interface_port hub_master m_axi_bresp bresp Input 2
        sc_hub_add_interface_port hub_master m_axi_bvalid bvalid Input 1
        sc_hub_add_interface_port hub_master m_axi_bready bready Output 1
        sc_hub_add_interface_port hub_master m_axi_arid arid Output 4
        sc_hub_add_interface_port hub_master m_axi_araddr araddr Output 18
        sc_hub_add_interface_port hub_master m_axi_arlen awlen Output 8
        sc_hub_add_interface_port hub_master m_axi_arsize awsize Output 3
        sc_hub_add_interface_port hub_master m_axi_arburst awburst Output 2
        sc_hub_add_interface_port hub_master m_axi_arvalid awvalid Output 1
        sc_hub_add_interface_port hub_master m_axi_arready awready Input 1
        sc_hub_add_interface_port hub_master m_axi_rid rid Input 4
        sc_hub_add_interface_port hub_master m_axi_rdata rdata Input 32
        sc_hub_add_interface_port hub_master m_axi_rresp rresp Input 2
        sc_hub_add_interface_port hub_master m_axi_rlast rlast Input 1
        sc_hub_add_interface_port hub_master m_axi_rvalid rvalid Input 1
        sc_hub_add_interface_port hub_master m_axi_rready rready Output 1
    } err_msg]} {
        send_message error "add_axi4_master_interface failed: $err_msg"
    }
}

proc sc_hub_update_identity_html {} {
    set version_str [sc_hub_version_string]
    set uid_hex     [sc_hub_format_hex [get_parameter_value IP_UID] 8]
    set git_hex     [sc_hub_format_hex [get_parameter_value VERSION_GIT] 8]
    set date_val    [get_parameter_value VERSION_DATE]
    set instance_id [get_parameter_value INSTANCE_ID]

    set profile_html "<html><b>Delivered profile</b><br/>"
    append profile_html "This compatibility-facing wrapper is packaged as <b>$version_str</b>. "
    append profile_html "It keeps the external packet framing and the legacy Platform Designer "
    append profile_html "interface names used by the live systems while adopting the canonical "
    append profile_html "Mu3e identity header at CSR words <b>0x00 UID</b> and <b>0x01 META</b>.</html>"
    catch {set_display_item_property identity_profile_html TEXT $profile_html}

    set version_html "<html><b>Catalog version</b><br/>"
    append version_html "Platform Designer sees <b>NAME=sc_hub</b> and <b>VERSION=$version_str</b>.<br/><br/>"
    append version_html "<table border='1' cellpadding='3' width='100%'>"
    append version_html "<tr><th>Field</th><th>Value</th><th>Runtime visibility</th></tr>"
    append version_html "<tr><td><b>IP_UID</b></td><td>$uid_hex</td><td>CSR word 0x00</td></tr>"
    append version_html "<tr><td><b>VERSION</b></td><td>$version_str</td><td>META page 0</td></tr>"
    append version_html "<tr><td><b>VERSION_DATE</b></td><td>$date_val</td><td>META page 1</td></tr>"
    append version_html "<tr><td><b>VERSION_GIT</b></td><td>$git_hex</td><td>META page 2</td></tr>"
    append version_html "<tr><td><b>INSTANCE_ID</b></td><td>$instance_id</td><td>META page 3</td></tr>"
    append version_html "</table><br/><br/><b>Legacy coexistence</b><br/>"
    append version_html "Existing systems can keep the historical interface names while the runtime "
    append version_html "identity contract now matches the common Mu3e UID + META format.</html>"
    catch {set_display_item_property version_html TEXT $version_html}
}

proc sc_hub_elaborate {} {
    catch {remove_interface hub_master}
    add_avmm_master_interface
    catch {set_parameter_property VERSION_GIT ENABLED [get_parameter_value GIT_STAMP_OVERRIDE]}
    sc_hub_update_identity_html
}

proc elaborate {} {
    sc_hub_elaborate
}

add_fileset QUARTUS_SYNTH QUARTUS_SYNTH "" ""
set_fileset_property QUARTUS_SYNTH TOP_LEVEL sc_hub_top
set_fileset_property QUARTUS_SYNTH ENABLE_RELATIVE_INCLUDE_PATHS false
set_fileset_property QUARTUS_SYNTH ENABLE_FILE_OVERWRITE_MODE false
add_fileset_file rtl/sc_hub_pkg.vhd VHDL PATH rtl/sc_hub_pkg.vhd
add_fileset_file rtl/fifo/sc_hub_fifo_sc.vhd VHDL PATH rtl/fifo/sc_hub_fifo_sc.vhd
add_fileset_file rtl/fifo/sc_hub_fifo_sf.vhd VHDL PATH rtl/fifo/sc_hub_fifo_sf.vhd
add_fileset_file rtl/fifo/sc_hub_fifo_bp.vhd VHDL PATH rtl/fifo/sc_hub_fifo_bp.vhd
add_fileset_file rtl/sc_hub_pkt_rx.vhd VHDL PATH rtl/sc_hub_pkt_rx.vhd
add_fileset_file rtl/sc_hub_pkt_tx.vhd VHDL PATH rtl/sc_hub_pkt_tx.vhd
add_fileset_file rtl/sc_hub_core.vhd VHDL PATH rtl/sc_hub_core.vhd
add_fileset_file rtl/sc_hub_avmm_handler.vhd VHDL PATH rtl/sc_hub_avmm_handler.vhd
add_fileset_file rtl/sc_hub_payload_ram.vhd VHDL PATH rtl/sc_hub_payload_ram.vhd
add_fileset_file rtl/sc_hub_axi4_handler.vhd VHDL PATH rtl/sc_hub_axi4_handler.vhd
add_fileset_file rtl/sc_hub_axi4_core.vhd VHDL PATH rtl/sc_hub_axi4_core.vhd
add_fileset_file rtl/sc_hub_axi4_ooo_handler.vhd VHDL PATH rtl/sc_hub_axi4_ooo_handler.vhd
add_fileset_file rtl/sc_hub_top.vhd VHDL PATH rtl/sc_hub_top.vhd TOP_LEVEL_FILE
add_fileset_file rtl/sc_hub_top_axi4.vhd VHDL PATH rtl/sc_hub_top_axi4.vhd

add_parameter BACKPRESSURE BOOLEAN true
set_parameter_property BACKPRESSURE DISPLAY_NAME "Enable Backpressure FIFO"
set_parameter_property BACKPRESSURE UNITS None
set_parameter_property BACKPRESSURE HDL_PARAMETER true
set_parameter_property BACKPRESSURE DESCRIPTION "Retained compatibility generic for the uplink backpressure path. The v2 RTL always keeps the reply FIFO in place."

add_parameter SCHEDULER_USE_PKT_TRANSFER BOOLEAN true
set_parameter_property SCHEDULER_USE_PKT_TRANSFER DISPLAY_NAME "Scheduler Packet Transfer Compatibility"
set_parameter_property SCHEDULER_USE_PKT_TRANSFER UNITS None
set_parameter_property SCHEDULER_USE_PKT_TRANSFER HDL_PARAMETER true
set_parameter_property SCHEDULER_USE_PKT_TRANSFER DESCRIPTION "Retained compatibility generic for systems that still propagate the legacy packet-transfer scheduler setting."

add_parameter INVERT_RD_SIG BOOLEAN true
set_parameter_property INVERT_RD_SIG DISPLAY_NAME "Invert Uplink Ready"
set_parameter_property INVERT_RD_SIG UNITS None
set_parameter_property INVERT_RD_SIG HDL_PARAMETER true
set_parameter_property INVERT_RD_SIG DESCRIPTION "When enabled, the uplink ready input is inverted before entering the hub. This preserves the existing integration contract with Intel mux IP."

add_parameter DEBUG NATURAL 1
set_parameter_property DEBUG DISPLAY_NAME "Debug Level"
set_parameter_property DEBUG UNITS None
set_parameter_property DEBUG ALLOWED_RANGES 0:4
set_parameter_property DEBUG HDL_PARAMETER true
set_parameter_property DEBUG DESCRIPTION "Synthesizable debug verbosity level exposed to the RTL."

add_parameter BUS_TYPE STRING {AVALON}
set_parameter_property BUS_TYPE DISPLAY_NAME "Master Bus Type"
set_parameter_property BUS_TYPE UNITS None
set_parameter_property BUS_TYPE ALLOWED_RANGES {"AVALON"}
set_parameter_property BUS_TYPE HDL_PARAMETER false
set_parameter_property BUS_TYPE DESCRIPTION "Selects the external master interface wrapper. The current checked-in Platform Designer component is fixed to the Avalon-MM compatibility boundary."

add_parameter IP_UID NATURAL $SC_HUB_IP_UID_DEFAULT_CONST
set_parameter_property IP_UID DISPLAY_NAME "IP UID"
set_parameter_property IP_UID HDL_PARAMETER true
set_parameter_property IP_UID DESCRIPTION "ASCII 4-character Mu3e IP identifier. Default = 'SCHB' (0x53434842)."

add_parameter VERSION_MAJOR NATURAL $SC_HUB_VERSION_MAJOR_DEFAULT_CONST
set_parameter_property VERSION_MAJOR DISPLAY_NAME "Version Major"
set_parameter_property VERSION_MAJOR HDL_PARAMETER true
set_parameter_property VERSION_MAJOR ENABLED false

add_parameter VERSION_MINOR NATURAL $SC_HUB_VERSION_MINOR_DEFAULT_CONST
set_parameter_property VERSION_MINOR DISPLAY_NAME "Version Minor"
set_parameter_property VERSION_MINOR HDL_PARAMETER true
set_parameter_property VERSION_MINOR ENABLED false

add_parameter VERSION_PATCH NATURAL $SC_HUB_VERSION_PATCH_DEFAULT_CONST
set_parameter_property VERSION_PATCH DISPLAY_NAME "Version Patch"
set_parameter_property VERSION_PATCH HDL_PARAMETER true
set_parameter_property VERSION_PATCH ENABLED false

add_parameter BUILD NATURAL $SC_HUB_BUILD_DEFAULT_CONST
set_parameter_property BUILD DISPLAY_NAME "Build (MMDD)"
set_parameter_property BUILD HDL_PARAMETER true
set_parameter_property BUILD ENABLED false

add_parameter VERSION_DATE NATURAL $SC_HUB_VERSION_DATE_DEFAULT_CONST
set_parameter_property VERSION_DATE DISPLAY_NAME "Version Date"
set_parameter_property VERSION_DATE HDL_PARAMETER true
set_parameter_property VERSION_DATE ENABLED false

add_parameter GIT_STAMP_OVERRIDE BOOLEAN false
set_parameter_property GIT_STAMP_OVERRIDE DISPLAY_NAME "Override Git Stamp"
set_parameter_property GIT_STAMP_OVERRIDE HDL_PARAMETER false
set_parameter_property GIT_STAMP_OVERRIDE DESCRIPTION "When enabled, VERSION_GIT becomes editable. When disabled, the packaged git stamp stays fixed to the authored revision."

add_parameter VERSION_GIT NATURAL $SC_HUB_VERSION_GIT_DEFAULT_CONST
set_parameter_property VERSION_GIT DISPLAY_NAME "Version Git Stamp"
set_parameter_property VERSION_GIT HDL_PARAMETER true
set_parameter_property VERSION_GIT ENABLED false
set_parameter_property VERSION_GIT DESCRIPTION "32-bit git stamp exposed through META page 2."

add_parameter INSTANCE_ID NATURAL $SC_HUB_INSTANCE_ID_DEFAULT_CONST
set_parameter_property INSTANCE_ID DISPLAY_NAME "Instance ID"
set_parameter_property INSTANCE_ID HDL_PARAMETER true
set_parameter_property INSTANCE_ID DESCRIPTION "Per-instance integration identifier exposed through META page 3."

set TAB_CONFIG     "Configuration"
set TAB_IDENTITY   "Identity"
set TAB_INTERFACES "Interfaces"
set TAB_REGMAP     "Register Map"

add_display_item "" $TAB_CONFIG GROUP tab
add_display_item $TAB_CONFIG "Overview" GROUP
add_display_item $TAB_CONFIG "Packet / Bus" GROUP
add_display_item $TAB_CONFIG "Compatibility" GROUP
add_display_item $TAB_CONFIG "Debug" GROUP

add_html_text "Overview" overview_html {<html><b>Function</b><br/>The compatibility-facing <b>sc_hub</b> component terminates Mu3e slow-control packets, validates write payloads before external side effects, routes internal CSR accesses locally, and formats reply packets on the uplink side.</html>}
add_html_text "Packet / Bus" packet_bus_html {<html><b>Bus selection</b><br/>This wrapper is fixed to the live <b>Avalon-MM</b> master boundary used by existing systems. The runtime CSR identity contract is the common Mu3e <b>UID + META</b> header.</html>}
add_display_item "Packet / Bus" BUS_TYPE parameter
add_display_item "Compatibility" BACKPRESSURE parameter
add_display_item "Compatibility" SCHEDULER_USE_PKT_TRANSFER parameter
add_display_item "Compatibility" INVERT_RD_SIG parameter
add_html_text "Compatibility" compat_html {<html><b>Compatibility generics</b><br/>These parameters remain visible so existing Platform Designer systems regenerate without changing their generic list. The v2 datapath still uses the internal reply FIFO and validated packet receiver regardless of the legacy generic values.</html>}
add_display_item "Debug" DEBUG parameter
add_html_text "Debug" advanced_html {<html><b>Implementation notes</b><br/>1. The internal CSR aperture is fixed at base word address <b>0xFE80</b>.<br/>2. Download writes are validated through the store-and-forward FIFO before the bus command is launched.<br/>3. The legacy <b>avm_m0_flush</b> path is intentionally absent in this v2 datapath.</html>}

add_display_item "" $TAB_IDENTITY GROUP tab
add_display_item $TAB_IDENTITY "Delivered Profile" GROUP
add_display_item $TAB_IDENTITY "Versioning" GROUP
add_html_text "Delivered Profile" identity_profile_html {<html><i>Delivered profile text will appear after elaboration.</i></html>}
add_display_item "Versioning" IP_UID parameter
add_display_item "Versioning" VERSION_MAJOR parameter
add_display_item "Versioning" VERSION_MINOR parameter
add_display_item "Versioning" VERSION_PATCH parameter
add_display_item "Versioning" BUILD parameter
add_display_item "Versioning" VERSION_DATE parameter
add_display_item "Versioning" GIT_STAMP_OVERRIDE parameter
add_display_item "Versioning" VERSION_GIT parameter
add_display_item "Versioning" INSTANCE_ID parameter
add_html_text "Versioning" version_html {<html><i>Version summary will appear after elaboration.</i></html>}

add_display_item "" $TAB_INTERFACES GROUP tab
add_display_item $TAB_INTERFACES "Clock / Reset" GROUP
add_display_item $TAB_INTERFACES "Packet Links" GROUP
add_display_item $TAB_INTERFACES "Master Bus" GROUP
add_display_item $TAB_INTERFACES "CSR Slave" GROUP

add_html_text "Clock / Reset" clock_html {<html><b>hub_clock</b> and <b>hub_reset</b><br/>Single synchronous domain for packet ingress, dispatch, reply formatting, and the internal CSR window.</html>}
add_html_text "Packet Links" packet_html {<html><b>hub_sc_packet_downlink</b> accepts 32-bit Mu3e slow-control words with a 4-bit K-character sideband. <b>hub_sc_packet_uplink</b> emits the formatted reply packet as a 36-bit Avalon-ST source with SOP/EOP.</html>}
add_html_text "Packet Links" packet_down_fmt_html {<html><b>hub_sc_packet_downlink</b><br/><table border="1" cellpadding="3" width="100%"><tr><th>Signal</th><th>Bits</th><th>Description</th></tr><tr><td><b>i_download_data</b></td><td>31:0</td><td>Mu3e slow-control word stream.</td></tr><tr><td><b>i_download_datak</b></td><td>3:0</td><td>Per-byte K-character markers from the 8B10B decoder.</td></tr><tr><td><b>o_download_ready</b></td><td>0</td><td>Ingress backpressure toward the packet receiver.</td></tr></table></html>}
add_html_text "Packet Links" packet_up_fmt_html {<html><b>hub_sc_packet_uplink</b><br/><table border="1" cellpadding="3" width="100%"><tr><th>Bits / Signal</th><th>Field</th><th>Description</th></tr><tr><td><b>aso_upload_data[35:32]</b></td><td>datak</td><td>K-character qualifiers associated with the reply word on bits [31:0].</td></tr><tr><td><b>aso_upload_data[31:0]</b></td><td>data</td><td>Mu3e slow-control reply header, payload, and trailer stream.</td></tr><tr><td><b>aso_upload_startofpacket</b></td><td>SOP</td><td>Asserted on the first reply word.</td></tr><tr><td><b>aso_upload_endofpacket</b></td><td>EOP</td><td>Asserted on the trailer word.</td></tr><tr><td><b>aso_upload_valid / ready</b></td><td>Handshake</td><td>Backpressure-safe Avalon-ST transfer handshake.</td></tr></table></html>}
add_html_text "Master Bus" master_html {<html><b>hub_master</b><br/>Compatibility-facing Avalon-MM master boundary for the live systems. The deprecated <b>avm_m0_flush</b> signal is intentionally not present in this v2 datapath.</html>}
add_html_text "Master Bus" master_fmt_html {<html><table border="1" cellpadding="3" width="100%"><tr><th>Signal</th><th>Direction</th><th>Description</th></tr><tr><td><b>avm_hub_address[17:0]</b></td><td>Out</td><td>Word address of the external SC target.</td></tr><tr><td><b>avm_hub_read</b>, <b>avm_hub_write</b></td><td>Out</td><td>Read/write command strobes.</td></tr><tr><td><b>avm_hub_writedata[31:0]</b></td><td>Out</td><td>Write payload word.</td></tr><tr><td><b>avm_hub_readdata[31:0]</b></td><td>In</td><td>Read payload word returned by the interconnect.</td></tr><tr><td><b>avm_hub_waitrequest</b>, <b>avm_hub_readdatavalid</b>, <b>avm_hub_writeresponsevalid</b></td><td>In</td><td>Bus completion and backpressure handshake signals.</td></tr><tr><td><b>avm_hub_response[1:0]</b></td><td>In</td><td>Response code propagated into the SC reply packet.</td></tr><tr><td><b>avm_hub_burstcount[8:0]</b></td><td>Out</td><td>Requested burst length in words.</td></tr></table></html>}
add_html_text "CSR Slave" csr_html {<html><b>csr</b> — Avalon-MM slave<br/>The internal CSR window occupies slow-control word addresses <b>0xFE80..0xFE9F</b>. Words 0 and 1 implement the common Mu3e identity header.</html>}

add_display_item "" $TAB_REGMAP GROUP tab
add_display_item $TAB_REGMAP "CSR Window" GROUP
add_html_text "CSR Window" csr_table_html $CSR_TABLE_HTML
add_display_item $TAB_REGMAP "META Fields (0x01)" GROUP
add_html_text "META Fields (0x01)" meta_fields_html $META_FIELDS_HTML
add_display_item $TAB_REGMAP "CTRL Fields (0x02)" GROUP
add_html_text "CTRL Fields (0x02)" ctrl_fields_html $CTRL_FIELDS_HTML
add_display_item $TAB_REGMAP "STATUS Fields (0x03)" GROUP
add_html_text "STATUS Fields (0x03)" status_fields_html $STATUS_FIELDS_HTML
add_display_item $TAB_REGMAP "ERR_FLAGS Fields (0x04)" GROUP
add_html_text "ERR_FLAGS Fields (0x04)" err_flags_fields_html $ERR_FLAGS_FIELDS_HTML
add_display_item $TAB_REGMAP "FIFO_CFG Fields (0x09)" GROUP
add_html_text "FIFO_CFG Fields (0x09)" fifo_cfg_fields_html $FIFO_CFG_FIELDS_HTML
add_display_item $TAB_REGMAP "FIFO_STATUS Fields (0x0A)" GROUP
add_html_text "FIFO_STATUS Fields (0x0A)" fifo_status_fields_html $FIFO_STATUS_FIELDS_HTML
add_display_item $TAB_REGMAP "OOO_CTRL Fields (0x18)" GROUP
add_html_text "OOO_CTRL Fields (0x18)" ooo_ctrl_fields_html $OOO_CTRL_FIELDS_HTML
add_display_item $TAB_REGMAP "HUB_CAP Fields (0x1F)" GROUP
add_html_text "HUB_CAP Fields (0x1F)" hub_cap_fields_html $HUB_CAP_FIELDS_HTML

add_interface hub_clock clock end
set_interface_property hub_clock clockRate 0
set_interface_property hub_clock ENABLED true
add_interface_port hub_clock i_clk clk Input 1

add_interface hub_reset reset end
set_interface_property hub_reset associatedClock hub_clock
set_interface_property hub_reset synchronousEdges DEASSERT
set_interface_property hub_reset ENABLED true
add_interface_port hub_reset i_rst reset Input 1

add_interface hub_sc_packet_downlink conduit end
set_interface_property hub_sc_packet_downlink associatedClock hub_clock
set_interface_property hub_sc_packet_downlink associatedReset hub_reset
set_interface_property hub_sc_packet_downlink ENABLED true
add_interface_port hub_sc_packet_downlink i_download_data data Input 32
add_interface_port hub_sc_packet_downlink i_download_datak datak Input 4
add_interface_port hub_sc_packet_downlink o_download_ready ready Output 1

add_interface hub_sc_packet_uplink avalon_streaming start
set_interface_property hub_sc_packet_uplink associatedClock hub_clock
set_interface_property hub_sc_packet_uplink associatedReset hub_reset
set_interface_property hub_sc_packet_uplink dataBitsPerSymbol 36
set_interface_property hub_sc_packet_uplink firstSymbolInHighOrderBits true
set_interface_property hub_sc_packet_uplink maxChannel 0
set_interface_property hub_sc_packet_uplink readyLatency 0
set_interface_property hub_sc_packet_uplink ENABLED true
add_interface_port hub_sc_packet_uplink aso_upload_data data Output 36
add_interface_port hub_sc_packet_uplink aso_upload_valid valid Output 1
add_interface_port hub_sc_packet_uplink aso_upload_ready ready Input 1
add_interface_port hub_sc_packet_uplink aso_upload_startofpacket startofpacket Output 1
add_interface_port hub_sc_packet_uplink aso_upload_endofpacket endofpacket Output 1

add_interface csr avalon end
set_interface_property csr addressUnits WORDS
set_interface_property csr associatedClock hub_clock
set_interface_property csr associatedReset hub_reset
set_interface_property csr bitsPerSymbol 8
set_interface_property csr burstOnBurstBoundariesOnly false
set_interface_property csr burstcountUnits WORDS
set_interface_property csr explicitAddressSpan 0
set_interface_property csr holdTime 0
set_interface_property csr linewrapBursts false
set_interface_property csr maximumPendingReadTransactions 1
set_interface_property csr maximumPendingWriteTransactions 0
set_interface_property csr readLatency 0
set_interface_property csr readWaitTime 1
set_interface_property csr setupTime 0
set_interface_property csr timingUnits Cycles
set_interface_property csr writeWaitTime 0
set_interface_property csr ENABLED true
add_interface_port csr avs_csr_address address Input 5
add_interface_port csr avs_csr_read read Input 1
add_interface_port csr avs_csr_write write Input 1
add_interface_port csr avs_csr_writedata writedata Input 32
add_interface_port csr avs_csr_readdata readdata Output 32
add_interface_port csr avs_csr_readdatavalid readdatavalid Output 1
add_interface_port csr avs_csr_waitrequest waitrequest Output 1
add_interface_port csr avs_csr_burstcount burstcount Input 1

add_interface hub_master avalon start
set_interface_property hub_master addressUnits WORDS
set_interface_property hub_master associatedClock hub_clock
set_interface_property hub_master associatedReset hub_reset
set_interface_property hub_master bitsPerSymbol 8
set_interface_property hub_master burstOnBurstBoundariesOnly false
set_interface_property hub_master burstcountUnits WORDS
set_interface_property hub_master doStreamReads false
set_interface_property hub_master doStreamWrites false
set_interface_property hub_master holdTime 0
set_interface_property hub_master linewrapBursts false
set_interface_property hub_master maximumPendingReadTransactions 1
set_interface_property hub_master maximumPendingWriteTransactions 1
set_interface_property hub_master readLatency 0
set_interface_property hub_master readWaitTime 1
set_interface_property hub_master registerIncomingSignals false
set_interface_property hub_master setupTime 0
set_interface_property hub_master timingUnits Cycles
set_interface_property hub_master writeWaitTime 0
set_interface_property hub_master ENABLED true
add_interface_port hub_master avm_hub_address address Output 18
add_interface_port hub_master avm_hub_read read Output 1
add_interface_port hub_master avm_hub_readdata readdata Input 32
add_interface_port hub_master avm_hub_writeresponsevalid writeresponsevalid Input 1
add_interface_port hub_master avm_hub_response response Input 2
add_interface_port hub_master avm_hub_write write Output 1
add_interface_port hub_master avm_hub_writedata writedata Output 32
add_interface_port hub_master avm_hub_waitrequest waitrequest Input 1
add_interface_port hub_master avm_hub_readdatavalid readdatavalid Input 1
add_interface_port hub_master avm_hub_burstcount burstcount Output 9
