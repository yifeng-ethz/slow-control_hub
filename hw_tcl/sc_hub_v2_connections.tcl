# ============================================================================
# sc_hub_v2 — Interface and HDL File Composition
#
# Dynamically creates bus interfaces and selects HDL files based on
# feature enables and bus type. Called from the elaboration callback.
# ============================================================================

# ----------------------------------------------------------------------------
# Build interfaces (called from sc_hub_v2_elaborate)
# ----------------------------------------------------------------------------
proc sc_hub_v2_build_interfaces {} {
    set bus [string toupper [get_parameter_value BUS_TYPE]]

    # Always present: clock, reset, download conduit, upload streaming
    sc_hub_v2_build_clock_reset
    sc_hub_v2_build_download_conduit
    sc_hub_v2_build_upload_streaming
    sc_hub_v2_build_csr_slave

    # Bus master: AVMM or AXI4
    catch {remove_interface hub}
    if {$bus eq "AXI4"} {
        sc_hub_v2_build_axi4_master
    } else {
        sc_hub_v2_build_avmm_master
    }
}

proc sc_hub_v2_build_clock_reset {} {
    catch {remove_interface hub_clock}
    catch {remove_interface hub_reset}

    add_interface hub_clock clock end
    set_interface_property hub_clock clockRate 0
    set_interface_property hub_clock ENABLED true
    add_interface_port hub_clock i_clk clk Input 1

    add_interface hub_reset reset end
    set_interface_property hub_reset associatedClock hub_clock
    set_interface_property hub_reset synchronousEdges DEASSERT
    set_interface_property hub_reset ENABLED true
    add_interface_port hub_reset i_rst reset Input 1
}

proc sc_hub_v2_build_download_conduit {} {
    catch {remove_interface download}

    add_interface download conduit end
    set_interface_property download associatedClock hub_clock
    set_interface_property download associatedReset hub_reset
    set_interface_property download ENABLED true
    add_interface_port download i_download_data data Input 32
    add_interface_port download i_download_datak datak Input 4
    add_interface_port download o_download_ready ready Output 1
}

proc sc_hub_v2_build_upload_streaming {} {
    catch {remove_interface upload}

    add_interface upload avalon_streaming start
    set_interface_property upload associatedClock hub_clock
    set_interface_property upload associatedReset hub_reset
    set_interface_property upload dataBitsPerSymbol 36
    set_interface_property upload firstSymbolInHighOrderBits true
    set_interface_property upload maxChannel 0
    set_interface_property upload readyLatency 0
    set_interface_property upload ENABLED true
    add_interface_port upload aso_upload_data data Output 36
    add_interface_port upload aso_upload_valid valid Output 1
    add_interface_port upload aso_upload_ready ready Input 1
    add_interface_port upload aso_upload_startofpacket startofpacket Output 1
    add_interface_port upload aso_upload_endofpacket endofpacket Output 1
}

proc sc_hub_v2_build_csr_slave {} {
    catch {remove_interface csr}

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
}

proc sc_hub_v2_build_avmm_master {} {
    # Widened to 18 bits to reach slaves at addresses above 0xFFFF (e.g. 0x3F010).
    # SC protocol carries 24-bit addresses; 18 bits covers the current Qsys map.
    set aw 18
    set bcw 9

    add_interface hub avalon start
    set_interface_property hub addressUnits WORDS
    set_interface_property hub associatedClock hub_clock
    set_interface_property hub associatedReset hub_reset
    set_interface_property hub bitsPerSymbol 8
    set_interface_property hub burstOnBurstBoundariesOnly false
    set_interface_property hub burstcountUnits WORDS
    set_interface_property hub doStreamReads false
    set_interface_property hub doStreamWrites false
    set_interface_property hub holdTime 0
    set_interface_property hub linewrapBursts false
    set_interface_property hub maximumPendingReadTransactions 1
    set_interface_property hub maximumPendingWriteTransactions 1
    set_interface_property hub readLatency 0
    set_interface_property hub readWaitTime 1
    set_interface_property hub registerIncomingSignals false
    set_interface_property hub setupTime 0
    set_interface_property hub timingUnits Cycles
    set_interface_property hub writeWaitTime 0
    set_interface_property hub ENABLED true

    add_interface_port hub avm_hub_address address Output $aw
    add_interface_port hub avm_hub_read read Output 1
    add_interface_port hub avm_hub_readdata readdata Input 32
    add_interface_port hub avm_hub_writeresponsevalid writeresponsevalid Input 1
    add_interface_port hub avm_hub_response response Input 2
    add_interface_port hub avm_hub_write write Output 1
    add_interface_port hub avm_hub_writedata writedata Output 32
    add_interface_port hub avm_hub_waitrequest waitrequest Input 1
    add_interface_port hub avm_hub_readdatavalid readdatavalid Input 1
    add_interface_port hub avm_hub_burstcount burstcount Output $bcw
}

proc sc_hub_v2_build_axi4_master {} {
    # Widened to 18 bits to match Avalon master port width.
    set aw 18
    set idw 4

    add_interface hub axi4 start
    set_interface_property hub associatedClock hub_clock
    set_interface_property hub associatedReset hub_reset
    set_interface_property hub ENABLED true

    # Write address channel
    add_interface_port hub m_axi_awid awid Output $idw
    add_interface_port hub m_axi_awaddr awaddr Output $aw
    add_interface_port hub m_axi_awlen awlen Output 8
    add_interface_port hub m_axi_awsize awsize Output 3
    add_interface_port hub m_axi_awburst awburst Output 2
    add_interface_port hub m_axi_awvalid awvalid Output 1
    add_interface_port hub m_axi_awready awready Input 1

    # Write data channel
    add_interface_port hub m_axi_wdata wdata Output 32
    add_interface_port hub m_axi_wstrb wstrb Output 4
    add_interface_port hub m_axi_wlast wlast Output 1
    add_interface_port hub m_axi_wvalid wvalid Output 1
    add_interface_port hub m_axi_wready wready Input 1

    # Write response channel
    add_interface_port hub m_axi_bid bid Input $idw
    add_interface_port hub m_axi_bresp bresp Input 2
    add_interface_port hub m_axi_bvalid bvalid Input 1
    add_interface_port hub m_axi_bready bready Output 1

    # Read address channel
    add_interface_port hub m_axi_arid arid Output $idw
    add_interface_port hub m_axi_araddr araddr Output $aw
    add_interface_port hub m_axi_arlen arlen Output 8
    add_interface_port hub m_axi_arsize arsize Output 3
    add_interface_port hub m_axi_arburst arburst Output 2
    add_interface_port hub m_axi_arvalid arvalid Output 1
    add_interface_port hub m_axi_arready arready Input 1

    # Read data channel
    add_interface_port hub m_axi_rid rid Input $idw
    add_interface_port hub m_axi_rdata rdata Input 32
    add_interface_port hub m_axi_rresp rresp Input 2
    add_interface_port hub m_axi_rlast rlast Input 1
    add_interface_port hub m_axi_rvalid rvalid Input 1
    add_interface_port hub m_axi_rready rready Output 1
}

# ----------------------------------------------------------------------------
# Define fileset once at component load time
# ----------------------------------------------------------------------------
proc sc_hub_v2_init_fileset {} {
    add_fileset QUARTUS_SYNTH QUARTUS_SYNTH "" ""
    set_fileset_property QUARTUS_SYNTH TOP_LEVEL sc_hub_top
    set_fileset_property QUARTUS_SYNTH ENABLE_RELATIVE_INCLUDE_PATHS false
    set_fileset_property QUARTUS_SYNTH ENABLE_FILE_OVERWRITE_MODE false

    # Keep the PD wrapper aligned to the live checked-in AVMM top-level.
    # Relative component paths avoid broken "submodules/home/..." QIP entries.
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
}

# ----------------------------------------------------------------------------
# Select top level during elaboration
# ----------------------------------------------------------------------------
proc sc_hub_v2_build_fileset {} {
    # Platform Designer does not allow changing the QUARTUS_SYNTH top-level
    # entity during ELABORATE. Keep the component fileset fixed to the live
    # AVMM wrapper (sc_hub_top) for the current integration path. AXI4 remains
    # available as a standalone RTL top-level, but not through this PD wrapper.
    return
}
