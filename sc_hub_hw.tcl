# ============================================================================
# sc_hub "Slow Control Hub" v26.2.0
# Yifeng Wang 2026.03.31
#
# Major revision: modular sc_hub v2 with internal CSR header in the canonical
# IP tree, validated store-and-forward download path, and an Avalon-MM
# compatibility-facing master interface for existing systems.
#
# GUI modeled after the Intel-style Mu3e IP wrappers such as ring_buffer_cam
# and histogram_statistics_v2.
# ============================================================================

package require -exact qsys 16.1

set_module_property NAME sc_hub
set_module_property DISPLAY_NAME "Slow Control Hub"
set_module_property VERSION 26.2.0
set_module_property DESCRIPTION "Modular slow-control hub with internal CSR window, validated store-and-forward write path, and the live Avalon-MM compatibility boundary used by existing systems."
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
set_module_property ICON_PATH ../figures/mu3e_logo.png

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

set CSR_TABLE_HTML {<html><table border="1" width="100%">
<tr><th>Word</th><th>Name</th><th>Access</th><th>Description</th></tr>
<tr><td>0x00</td><td>ID</td><td>RO</td><td>Fixed ID 0x53480000.</td></tr>
<tr><td>0x01</td><td>VERSION</td><td>RO</td><td>Packed version date-style register carried forward from the legacy hub.</td></tr>
<tr><td>0x02</td><td>CTRL</td><td>RW</td><td>Bit 0 enable. Bits 1 and 2 clear software-visible counters and flags.</td></tr>
<tr><td>0x03</td><td>STATUS</td><td>RO</td><td>Busy, error summary, FIFO state, and bus-active summary bits.</td></tr>
<tr><td>0x04</td><td>ERR_FLAGS</td><td>W1C</td><td>Upload overflow, download overflow, internal CSR address error, read timeout, and packet-drop flags.</td></tr>
<tr><td>0x05</td><td>ERR_COUNT</td><td>RO</td><td>Saturating 32-bit error counter.</td></tr>
<tr><td>0x06</td><td>SCRATCH</td><td>RW</td><td>General-purpose software scratch register.</td></tr>
<tr><td>0x07</td><td>GTS_SNAP_LO</td><td>RO</td><td>Snapshot low word.</td></tr>
<tr><td>0x08</td><td>GTS_SNAP_HI</td><td>RO</td><td>Snapshot high word and snapshot trigger.</td></tr>
<tr><td>0x09</td><td>FIFO_CFG</td><td>RW</td><td>Bit 0 download store-and-forward fixed high. Bit 1 upload mode control.</td></tr>
<tr><td>0x0A</td><td>FIFO_STATUS</td><td>RO</td><td>Download, upload, and reply FIFO fullness and overflow summary.</td></tr>
<tr><td>0x0B</td><td>DOWN_PKT_CNT</td><td>RO</td><td>Download packet occupancy summary.</td></tr>
<tr><td>0x0C</td><td>UP_PKT_CNT</td><td>RO</td><td>Upload packet occupancy summary.</td></tr>
<tr><td>0x0D</td><td>DOWN_USEDW</td><td>RO</td><td>Download FIFO used words.</td></tr>
<tr><td>0x0E</td><td>UP_USEDW</td><td>RO</td><td>Upload FIFO used words.</td></tr>
<tr><td>0x0F</td><td>EXT_PKT_RD_CNT</td><td>RO</td><td>External read packet counter.</td></tr>
<tr><td>0x10</td><td>EXT_PKT_WR_CNT</td><td>RO</td><td>External write packet counter.</td></tr>
<tr><td>0x11</td><td>EXT_WORD_RD_CNT</td><td>RO</td><td>External read word counter.</td></tr>
<tr><td>0x12</td><td>EXT_WORD_WR_CNT</td><td>RO</td><td>External write word counter.</td></tr>
<tr><td>0x13</td><td>LAST_RD_ADDR</td><td>RO</td><td>Last external read address.</td></tr>
<tr><td>0x14</td><td>LAST_RD_DATA</td><td>RO</td><td>Last external read data.</td></tr>
<tr><td>0x15</td><td>LAST_WR_ADDR</td><td>RO</td><td>Last external write address.</td></tr>
<tr><td>0x16</td><td>LAST_WR_DATA</td><td>RO</td><td>Last external write data.</td></tr>
<tr><td>0x17</td><td>PKT_DROP_CNT</td><td>RO</td><td>Validated download packet drops due to malformed or truncated writes.</td></tr>
</table></html>}

proc sc_hub_validate {} {
    set bus_type [string toupper [get_parameter_value BUS_TYPE]]
    set debug_level [get_parameter_value DEBUG]

    if {$bus_type ne "AVALON" && $bus_type ne "AXI4"} {
        send_message error "BUS_TYPE must be AVALON or AXI4. Got $bus_type."
    }

    if {$bus_type eq "AXI4"} {
        send_message error "BUS_TYPE=AXI4 is not supported by the current Platform Designer generation flow for sc_hub. Use AVALON for regenerated systems until the AXI4 wrapper is packaged as a static component."
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
        # 18.1 merlin master_translator mis-handles registered read inputs with
        # readdatavalid: it keeps downstream read asserted until data returns.
        set_interface_property hub_master registerIncomingSignals false
        set_interface_property hub_master setupTime 0
        set_interface_property hub_master timingUnits Cycles
        set_interface_property hub_master writeWaitTime 0
        set_interface_property hub_master ENABLED true

        add_interface_port hub_master avm_hub_address address Output 16
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
        sc_hub_add_interface_port hub_master m_axi_awaddr awaddr Output 16
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
        sc_hub_add_interface_port hub_master m_axi_araddr araddr Output 16
        sc_hub_add_interface_port hub_master m_axi_arlen arlen Output 8
        sc_hub_add_interface_port hub_master m_axi_arsize arsize Output 3
        sc_hub_add_interface_port hub_master m_axi_arburst arburst Output 2
        sc_hub_add_interface_port hub_master m_axi_arvalid arvalid Output 1
        sc_hub_add_interface_port hub_master m_axi_arready arready Input 1
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

proc sc_hub_elaborate {} {
    catch {remove_interface hub_master}
    add_avmm_master_interface
    catch {
        set_display_item_property identity_profile_html TEXT {<html><b>Delivered profile</b><br/>This sc_hub v2 instance is currently configured for the <b>Avalon-MM</b> master wrapper. The packet framing and CSR-visible behavior remain backward compatible with the legacy hub while removing the deprecated flush path.</html>}
    }
}

proc elaborate {} {
    sc_hub_elaborate
}

add_fileset QUARTUS_SYNTH QUARTUS_SYNTH "" ""
set_fileset_property QUARTUS_SYNTH TOP_LEVEL sc_hub_top
set_fileset_property QUARTUS_SYNTH ENABLE_RELATIVE_INCLUDE_PATHS false
set_fileset_property QUARTUS_SYNTH ENABLE_FILE_OVERWRITE_MODE false
add_fileset_file sc_hub_pkg.vhd VHDL PATH sc_hub_pkg.vhd
add_fileset_file fifo/sc_hub_fifo_sc.vhd VHDL PATH fifo/sc_hub_fifo_sc.vhd
add_fileset_file fifo/sc_hub_fifo_sf.vhd VHDL PATH fifo/sc_hub_fifo_sf.vhd
add_fileset_file fifo/sc_hub_fifo_bp.vhd VHDL PATH fifo/sc_hub_fifo_bp.vhd
add_fileset_file sc_hub_pkt_rx.vhd VHDL PATH sc_hub_pkt_rx.vhd
add_fileset_file sc_hub_pkt_tx.vhd VHDL PATH sc_hub_pkt_tx.vhd
add_fileset_file sc_hub_core.vhd VHDL PATH sc_hub_core.vhd
add_fileset_file sc_hub_avmm_handler.vhd VHDL PATH sc_hub_avmm_handler.vhd
add_fileset_file sc_hub_axi4_handler.vhd VHDL PATH sc_hub_axi4_handler.vhd
add_fileset_file sc_hub_axi4_core.vhd VHDL PATH sc_hub_axi4_core.vhd
add_fileset_file sc_hub_axi4_ooo_handler.vhd VHDL PATH sc_hub_axi4_ooo_handler.vhd
add_fileset_file sc_hub_top.vhd VHDL PATH sc_hub_top.vhd TOP_LEVEL_FILE
add_fileset_file sc_hub_top_axi4.vhd VHDL PATH sc_hub_top_axi4.vhd

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

set TAB_CONFIG     "Configuration"
set TAB_IDENTITY   "Identity"
set TAB_INTERFACES "Interfaces"
set TAB_REGMAP     "Register Map"

add_display_item "" $TAB_CONFIG GROUP tab
add_display_item $TAB_CONFIG "Overview" GROUP
add_display_item $TAB_CONFIG "Packet / Bus" GROUP
add_display_item $TAB_CONFIG "Compatibility" GROUP
add_display_item $TAB_CONFIG "Advanced" GROUP

add_html_text "Overview" overview_html {<html><b>Function</b><br/>The slow-control hub terminates Mu3e slow-control packets, validates the full download command before any external write is issued, routes internal CSR accesses locally, and formats the reply packet on the uplink side. The download write boundary is now store-and-forward, so malformed write packets are dropped before they reach the external bus.</html>}
add_display_item "Packet / Bus" BUS_TYPE parameter
add_html_text "Packet / Bus" packet_bus_html {<html><b>Bus selection</b><br/>This compatibility-facing <b>sc_hub</b> component is currently packaged with the Avalon-MM master boundary used by the live systems. The packet format, CSR map, and reply word-2 header format stay the same.</html>}
add_display_item "Compatibility" BACKPRESSURE parameter
add_display_item "Compatibility" SCHEDULER_USE_PKT_TRANSFER parameter
add_display_item "Compatibility" INVERT_RD_SIG parameter
add_html_text "Compatibility" compat_html {<html><b>Compatibility generics</b><br/>These parameters are kept so existing Platform Designer systems regenerate without changing their generic list. The v2 datapath always uses the internal reply FIFO and the validated packet receiver regardless of the legacy generic values.</html>}
add_display_item "Advanced" DEBUG parameter
add_html_text "Advanced" advanced_html {<html><b>Implementation notes</b><br/>1. The internal CSR aperture is fixed at base word address <b>0xFE80</b>.<br/>2. Download writes are validated through the store-and-forward FIFO before the bus command is launched.<br/>3. The legacy <b>avm_m0_flush</b> path is removed in v2. Read timeout reports an error response instead of trying to flush the interconnect.</html>}

add_display_item "" $TAB_IDENTITY GROUP tab
add_display_item $TAB_IDENTITY "Delivered Profile" GROUP
add_display_item $TAB_IDENTITY "Versioning" GROUP

add_html_text "Delivered Profile" identity_profile_html {<html><b>Delivered profile</b><br/>This sc_hub v2-compatible release is packaged as <b>26.2.0</b>. It keeps the external packet framing and the legacy Platform Designer interface names from the live hub while moving the internal CSR implementation into the canonical IP tree and removing the deprecated flush path.</html>}
add_html_text "Versioning" version_html {<html><b>Catalog version</b><br/>Platform Designer sees this component as <b>NAME=sc_hub</b>, <b>VERSION=26.2.0</b>.<br/><br/><b>Legacy coexistence</b><br/>A second `_hw.tcl` under <b>legacy/</b> keeps <b>NAME=sc_hub</b> with the older version stamp and source set so existing systems can keep their prior implementation while the new compatibility wrapper is available from the same search path.</html>}

add_display_item "" $TAB_INTERFACES GROUP tab
add_display_item $TAB_INTERFACES "Clock / Reset" GROUP
add_display_item $TAB_INTERFACES "Packet Links" GROUP
add_display_item $TAB_INTERFACES "Master Bus" GROUP

add_html_text "Clock / Reset" clock_html {<html><b>hub_clock</b> and <b>hub_reset</b><br/>Single synchronous domain for packet ingress, bus dispatch, reply formatting, and the internal CSR window.</html>}
add_html_text "Packet Links" packet_html {<html><b>hub_sc_packet_downlink</b><br/>32-bit Mu3e slow-control packet sink with K-character sideband.<br/><br/><b>hub_sc_packet_uplink</b><br/>36-bit Avalon-ST source carrying the formatted reply packet. The reply FIFO provides backpressure decoupling from the bus and CSR execution path.</html>}
add_html_text "Master Bus" master_html {<html><b>hub_master</b><br/>Compatibility-facing Avalon-MM master boundary for the live systems. The deprecated <b>avm_m0_flush</b> signal is intentionally not present in this v2 datapath.</html>}

add_display_item "" $TAB_REGMAP GROUP tab
add_display_item $TAB_REGMAP "CSR Window" GROUP
add_html_text "CSR Window" csr_table_html $CSR_TABLE_HTML

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
# 18.1 merlin master_translator mis-handles registered read inputs with
# readdatavalid: it keeps downstream read asserted until data returns.
set_interface_property hub_master registerIncomingSignals false
set_interface_property hub_master setupTime 0
set_interface_property hub_master timingUnits Cycles
set_interface_property hub_master writeWaitTime 0
set_interface_property hub_master ENABLED true
add_interface_port hub_master avm_hub_address address Output 16
add_interface_port hub_master avm_hub_read read Output 1
add_interface_port hub_master avm_hub_readdata readdata Input 32
add_interface_port hub_master avm_hub_writeresponsevalid writeresponsevalid Input 1
add_interface_port hub_master avm_hub_response response Input 2
add_interface_port hub_master avm_hub_write write Output 1
add_interface_port hub_master avm_hub_writedata writedata Output 32
add_interface_port hub_master avm_hub_waitrequest waitrequest Input 1
add_interface_port hub_master avm_hub_readdatavalid readdatavalid Input 1
add_interface_port hub_master avm_hub_burstcount burstcount Output 9
