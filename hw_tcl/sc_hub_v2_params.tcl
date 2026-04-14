# ============================================================================
# sc_hub_v2 — Parameter Definitions
#
# All compile-time parameters for the sc_hub_v2 IP. Parameters are organized
# by functional group and have explicit ranges, defaults, and descriptions.
#
# HDL_PARAMETER=true means the parameter becomes a VHDL generic.
# HDL_PARAMETER=false means it controls _hw.tcl elaboration only (GUI/fileset).
# ============================================================================

# ============================================================================
# PACKAGING VERSION CONSTANTS
# ============================================================================

set sc_hub_v2_params_dir [file dirname [file normalize [info script]]]
set sc_hub_v2_ip_dir [file normalize [file join $sc_hub_v2_params_dir ..]]

set SC_HUB_V2_IP_UID_DEFAULT_CONST        [expr {0x53434842}] ;# ASCII "SCHB"
set SC_HUB_V2_VERSION_MAJOR_DEFAULT_CONST 26
set SC_HUB_V2_VERSION_MINOR_DEFAULT_CONST 6
set SC_HUB_V2_VERSION_PATCH_DEFAULT_CONST 9
set SC_HUB_V2_BUILD_DEFAULT_CONST         414
set SC_HUB_V2_VERSION_DATE_DEFAULT_CONST  20260414
set SC_HUB_V2_VERSION_GIT_DEFAULT_CONST   0
set SC_HUB_V2_INSTANCE_ID_DEFAULT_CONST   0

if {![catch {
    set sc_hub_v2_git_short [string trim [exec git -C $sc_hub_v2_ip_dir rev-parse --short HEAD]]
}]} {
    if {[regexp {^[0-9a-fA-F]+$} $sc_hub_v2_git_short]} {
        scan $sc_hub_v2_git_short %x SC_HUB_V2_VERSION_GIT_DEFAULT_CONST
    }
}

# ============================================================================
# GROUP 1: Preset selector (GUI-only, not an HDL generic)
# ============================================================================

add_parameter PRESET STRING "CUSTOM"
set_parameter_property PRESET DISPLAY_NAME "Configuration Preset"
set_parameter_property PRESET DESCRIPTION \
    "Select a preset to auto-configure all parameters for a known use case. \
     The current Platform Designer wrapper only exposes AVMM-compatible \
     presets. Selecting 'CUSTOM' enables manual parameter tuning. Presets \
     override individual parameter values on elaboration."
set_parameter_property PRESET HDL_PARAMETER false
set_parameter_property PRESET ALLOWED_RANGES {
    "FEB_SCIFI_DEFAULT"
    "FEB_SCIFI_ORDERED"
    "FEB_MUPIX_DEFAULT"
    "FEB_MUPIX_ORDERED"
    "FEB_TILES_DEFAULT"
    "FEB_TILES_MINIMAL"
    "MINIMAL_CSR_ONLY"
    "AREA_OPTIMIZED"
    "CUSTOM"
}

# ============================================================================
# GROUP 2: Common Identity Header
# ============================================================================

add_parameter IP_UID NATURAL $SC_HUB_V2_IP_UID_DEFAULT_CONST
set_parameter_property IP_UID DISPLAY_NAME "IP UID"
set_parameter_property IP_UID DESCRIPTION \
    "ASCII 4-character Mu3e IP identifier. Default = 'SCHB' (0x53434842). \
     Integration-time editable so a derivative wrapper can override the UID."
set_parameter_property IP_UID HDL_PARAMETER true

add_parameter VERSION_MAJOR NATURAL $SC_HUB_V2_VERSION_MAJOR_DEFAULT_CONST
set_parameter_property VERSION_MAJOR DISPLAY_NAME "Version Major"
set_parameter_property VERSION_MAJOR DESCRIPTION \
    "Packed VERSION bits 31:24. Fixed by the packaged release year and not GUI editable."
set_parameter_property VERSION_MAJOR HDL_PARAMETER true
set_parameter_property VERSION_MAJOR ENABLED false

add_parameter VERSION_MINOR NATURAL $SC_HUB_V2_VERSION_MINOR_DEFAULT_CONST
set_parameter_property VERSION_MINOR DISPLAY_NAME "Version Minor"
set_parameter_property VERSION_MINOR DESCRIPTION \
    "Packed VERSION bits 23:16. Fixed by the packaged release and not GUI editable."
set_parameter_property VERSION_MINOR HDL_PARAMETER true
set_parameter_property VERSION_MINOR ENABLED false

add_parameter VERSION_PATCH NATURAL $SC_HUB_V2_VERSION_PATCH_DEFAULT_CONST
set_parameter_property VERSION_PATCH DISPLAY_NAME "Version Patch"
set_parameter_property VERSION_PATCH DESCRIPTION \
    "Packed VERSION bits 15:12. Fixed by the packaged release and not GUI editable."
set_parameter_property VERSION_PATCH HDL_PARAMETER true
set_parameter_property VERSION_PATCH ENABLED false

add_parameter BUILD NATURAL $SC_HUB_V2_BUILD_DEFAULT_CONST
set_parameter_property BUILD DISPLAY_NAME "Build (MMDD)"
set_parameter_property BUILD DESCRIPTION \
    "Packed VERSION bits 11:0 build stamp encoded as MMDD. Fixed by the packaged release."
set_parameter_property BUILD HDL_PARAMETER true
set_parameter_property BUILD ENABLED false

add_parameter VERSION_DATE NATURAL $SC_HUB_V2_VERSION_DATE_DEFAULT_CONST
set_parameter_property VERSION_DATE DISPLAY_NAME "Version Date"
set_parameter_property VERSION_DATE DESCRIPTION \
    "Full packaging date in YYYYMMDD form. Fixed by the packaged release."
set_parameter_property VERSION_DATE HDL_PARAMETER true
set_parameter_property VERSION_DATE ENABLED false

add_parameter GIT_STAMP_OVERRIDE BOOLEAN false
set_parameter_property GIT_STAMP_OVERRIDE DISPLAY_NAME "Override Git Stamp"
set_parameter_property GIT_STAMP_OVERRIDE DESCRIPTION \
    "When enabled, VERSION_GIT becomes editable. When disabled, the packaged git \
     stamp remains fixed to the revision used when the _hw.tcl was authored."
set_parameter_property GIT_STAMP_OVERRIDE HDL_PARAMETER false

add_parameter VERSION_GIT NATURAL $SC_HUB_V2_VERSION_GIT_DEFAULT_CONST
set_parameter_property VERSION_GIT DISPLAY_NAME "Version Git Stamp"
set_parameter_property VERSION_GIT DESCRIPTION \
    "32-bit git stamp exposed through META page 2. Disabled unless Override Git Stamp is enabled."
set_parameter_property VERSION_GIT HDL_PARAMETER true
set_parameter_property VERSION_GIT ENABLED false

add_parameter INSTANCE_ID NATURAL $SC_HUB_V2_INSTANCE_ID_DEFAULT_CONST
set_parameter_property INSTANCE_ID DISPLAY_NAME "Instance ID"
set_parameter_property INSTANCE_ID DESCRIPTION \
    "Per-instance integration identifier exposed through META page 3."
set_parameter_property INSTANCE_ID HDL_PARAMETER true

# ============================================================================
# GROUP 3: Bus Interface
# ============================================================================

add_parameter BUS_TYPE STRING "AVALON"
set_parameter_property BUS_TYPE DISPLAY_NAME "Master Bus Type"
set_parameter_property BUS_TYPE DESCRIPTION \
    "Selects the external master interface. The current Platform Designer \
     wrapper is fixed to the live Avalon-MM boundary and does not generate \
     the AXI4 top-level."
set_parameter_property BUS_TYPE HDL_PARAMETER false
set_parameter_property BUS_TYPE ALLOWED_RANGES {"AVALON"}

add_parameter ADDR_WIDTH NATURAL 18
set_parameter_property ADDR_WIDTH DISPLAY_NAME "Address Width (bits)"
set_parameter_property ADDR_WIDTH DESCRIPTION \
    "Word address width. 18 bits covers 256K words, sufficient for the \
     current Qsys slave map (highest address: 0x3F010)."
set_parameter_property ADDR_WIDTH HDL_PARAMETER false
set_parameter_property ADDR_WIDTH ALLOWED_RANGES {16 17 18 19 20 21 22 23 24}

add_parameter DATA_WIDTH NATURAL 32
set_parameter_property DATA_WIDTH DISPLAY_NAME "Data Width (bits)"
set_parameter_property DATA_WIDTH DESCRIPTION "Fixed at 32 bits for Mu3e SC protocol."
set_parameter_property DATA_WIDTH HDL_PARAMETER false
set_parameter_property DATA_WIDTH ALLOWED_RANGES {32}

# ============================================================================
# GROUP 4: Split-Buffer Architecture
# ============================================================================

add_parameter OUTSTANDING_LIMIT NATURAL 8
set_parameter_property OUTSTANDING_LIMIT DISPLAY_NAME "Outstanding Transaction Limit"
set_parameter_property OUTSTANDING_LIMIT DESCRIPTION \
    "Maximum number of transactions that can be in flight simultaneously. \
     This is the depth of ext_down_hdr (and cmd_order_fifo). \
     TLM SIZE-01 identifies the throughput knee."
set_parameter_property OUTSTANDING_LIMIT HDL_PARAMETER true
set_parameter_property OUTSTANDING_LIMIT ALLOWED_RANGES {1 2 4 8 12 16 24 32}

add_parameter OUTSTANDING_INT_RESERVED NATURAL 2
set_parameter_property OUTSTANDING_INT_RESERVED DISPLAY_NAME "Reserved Internal Slots"
set_parameter_property OUTSTANDING_INT_RESERVED DESCRIPTION \
    "Slots exclusively reserved for internal CSR transactions. Guarantees \
     CSR reachability even when external traffic saturates. MUST be >= 1 \
     for software reset recovery. TLM PRIO experiments validate this."
set_parameter_property OUTSTANDING_INT_RESERVED HDL_PARAMETER true
set_parameter_property OUTSTANDING_INT_RESERVED ALLOWED_RANGES {1 2 3 4}

add_parameter EXT_DOWN_PLD_DEPTH NATURAL 512
set_parameter_property EXT_DOWN_PLD_DEPTH DISPLAY_NAME "External Download Payload Depth (words)"
set_parameter_property EXT_DOWN_PLD_DEPTH DESCRIPTION \
    "Linked-list payload RAM depth for external download (write data). \
     Must be >= MAX_BURST for full burst support. \
     TLM SIZE-02 identifies the throughput knee."
set_parameter_property EXT_DOWN_PLD_DEPTH HDL_PARAMETER false
set_parameter_property EXT_DOWN_PLD_DEPTH ALLOWED_RANGES {64 128 256 512 1024 2048}

add_parameter INT_DOWN_PLD_DEPTH NATURAL 64
set_parameter_property INT_DOWN_PLD_DEPTH DISPLAY_NAME "Internal Download Payload Depth (words)"
set_parameter_property INT_DOWN_PLD_DEPTH DESCRIPTION \
    "Linked-list payload RAM for internal CSR writes. CSR window is 32 words \
     max, so 64 is usually sufficient."
set_parameter_property INT_DOWN_PLD_DEPTH HDL_PARAMETER false
set_parameter_property INT_DOWN_PLD_DEPTH ALLOWED_RANGES {32 64 128}

add_parameter EXT_UP_PLD_DEPTH NATURAL 512
set_parameter_property EXT_UP_PLD_DEPTH DISPLAY_NAME "External Upload Payload Depth (words)"
set_parameter_property EXT_UP_PLD_DEPTH DESCRIPTION \
    "Linked-list payload RAM for external upload (read data). Credit-based \
     reservation: effective outstanding for reads is min(OUTSTANDING_LIMIT, \
     EXT_UP_PLD_DEPTH / avg_burst_length). TLM CRED experiments characterize."
set_parameter_property EXT_UP_PLD_DEPTH HDL_PARAMETER false
set_parameter_property EXT_UP_PLD_DEPTH ALLOWED_RANGES {64 128 256 512 1024 2048}

add_parameter INT_UP_PLD_DEPTH NATURAL 64
set_parameter_property INT_UP_PLD_DEPTH DISPLAY_NAME "Internal Upload Payload Depth (words)"
set_parameter_property INT_UP_PLD_DEPTH HDL_PARAMETER false
set_parameter_property INT_UP_PLD_DEPTH ALLOWED_RANGES {32 64 128}

add_parameter INT_HDR_DEPTH NATURAL 4
set_parameter_property INT_HDR_DEPTH DISPLAY_NAME "Internal Header FIFO Depth"
set_parameter_property INT_HDR_DEPTH DESCRIPTION \
    "Depth of int_down_hdr and int_up_hdr. TLM SIZE-03 shows 4 is \
     sufficient for typical workloads."
set_parameter_property INT_HDR_DEPTH HDL_PARAMETER false
set_parameter_property INT_HDR_DEPTH ALLOWED_RANGES {1 2 4 8}

add_parameter MAX_BURST NATURAL 256
set_parameter_property MAX_BURST DISPLAY_NAME "Maximum Burst Length (words)"
set_parameter_property MAX_BURST DESCRIPTION \
    "Maximum supported burst length. Mu3e SC protocol supports up to 256. \
     Reducing this saves area in burstcount and payload address logic."
set_parameter_property MAX_BURST HDL_PARAMETER false
set_parameter_property MAX_BURST ALLOWED_RANGES {1 4 8 16 32 64 128 256}

add_parameter BP_FIFO_DEPTH NATURAL 512
set_parameter_property BP_FIFO_DEPTH DISPLAY_NAME "Backpressure FIFO Depth (words)"
set_parameter_property BP_FIFO_DEPTH DESCRIPTION \
    "Reply backpressure FIFO depth. Must hold at least one max-burst reply \
     packet (MAX_BURST + 4 header words)."
set_parameter_property BP_FIFO_DEPTH HDL_PARAMETER true
set_parameter_property BP_FIFO_DEPTH ALLOWED_RANGES {64 128 256 512 1024}

# ============================================================================
# GROUP 5: Feature Enables (compile-time)
# ============================================================================

add_parameter OOO_ENABLE BOOLEAN false
set_parameter_property OOO_ENABLE DISPLAY_NAME "Enable Out-of-Order Dispatch"
set_parameter_property OOO_ENABLE DESCRIPTION \
    "Compile-time OoO support. When true, the dispatch scoreboard and \
     reply reorder logic are synthesized. OoO can still be disabled at \
     runtime via OOO_CTRL CSR. Requires BUS_TYPE=AXI4 for full benefit. \
     TLM OOO experiments quantify the speedup."
set_parameter_property OOO_ENABLE HDL_PARAMETER true

add_parameter ORD_ENABLE BOOLEAN true
set_parameter_property ORD_ENABLE DISPLAY_NAME "Enable Ordering Semantics"
set_parameter_property ORD_ENABLE DESCRIPTION \
    "Compile-time ordering tracker. When true, the per-domain release \
     drain and acquire hold FSMs are synthesized. Software can use \
     RELEASE/ACQUIRE packet tags. When false, ORDER field is ignored \
     and all traffic treated as RELAXED."
set_parameter_property ORD_ENABLE HDL_PARAMETER true

add_parameter ORD_NUM_DOMAINS NATURAL 16
set_parameter_property ORD_NUM_DOMAINS DISPLAY_NAME "Number of Ordering Domains"
set_parameter_property ORD_NUM_DOMAINS DESCRIPTION \
    "Number of independent ordering domains. 16 = full 4-bit ORD_DOM_ID. \
     Reducing saves state array area (each domain is ~48 bits of state). \
     Only meaningful when ORD_ENABLE=true."
set_parameter_property ORD_NUM_DOMAINS HDL_PARAMETER false
set_parameter_property ORD_NUM_DOMAINS ALLOWED_RANGES {1 2 4 8 16}

add_parameter ATOMIC_ENABLE BOOLEAN true
set_parameter_property ATOMIC_ENABLE DISPLAY_NAME "Enable Atomic RMW"
set_parameter_property ATOMIC_ENABLE DESCRIPTION \
    "Compile-time atomic RMW sequencer. When true, the bus lock logic \
     and read-modify-write FSM are synthesized. When false, atomic_flag \
     in the packet is ignored (returns SLAVEERROR for safety)."
set_parameter_property ATOMIC_ENABLE HDL_PARAMETER true

add_parameter S_AND_F_ENABLE BOOLEAN true
set_parameter_property S_AND_F_ENABLE DISPLAY_NAME "Enable Store-and-Forward (writes)"
set_parameter_property S_AND_F_ENABLE DESCRIPTION \
    "When true, write packets are fully received and validated before \
     bus write is issued. When false, writes stream directly to bus \
     (lower latency but vulnerable to truncated packets)."
set_parameter_property S_AND_F_ENABLE HDL_PARAMETER false

add_parameter HUB_CAP_ENABLE BOOLEAN true
set_parameter_property HUB_CAP_ENABLE DISPLAY_NAME "Enable HUB_CAP Capability Register"
set_parameter_property HUB_CAP_ENABLE DESCRIPTION \
    "When true, a read-only CSR reports compile-time feature flags so \
     software can detect missing features at init instead of failing silently."
set_parameter_property HUB_CAP_ENABLE HDL_PARAMETER true

# ============================================================================
# GROUP 6: Timing and Timeout
# ============================================================================

add_parameter RD_TIMEOUT_CYCLES NATURAL 1024
set_parameter_property RD_TIMEOUT_CYCLES DISPLAY_NAME "Read Timeout (cycles)"
set_parameter_property RD_TIMEOUT_CYCLES DESCRIPTION \
    "If no readdatavalid arrives within this many cycles, the hub \
     generates a DECODEERROR reply and sets ERR_FLAGS.rd_timeout."
set_parameter_property RD_TIMEOUT_CYCLES HDL_PARAMETER true
set_parameter_property RD_TIMEOUT_CYCLES ALLOWED_RANGES {128 256 512 1024 2048 4096 8192}

add_parameter WR_TIMEOUT_CYCLES NATURAL 1024
set_parameter_property WR_TIMEOUT_CYCLES DISPLAY_NAME "Write Timeout (cycles)"
set_parameter_property WR_TIMEOUT_CYCLES DESCRIPTION \
    "If waitrequest stays asserted for this many cycles during a write, \
     the hub aborts the write and sets ERR_FLAGS.wr_timeout."
set_parameter_property WR_TIMEOUT_CYCLES HDL_PARAMETER true
set_parameter_property WR_TIMEOUT_CYCLES ALLOWED_RANGES {128 256 512 1024 2048 4096 8192}

# ============================================================================
# GROUP 7: Compatibility (legacy generics)
# ============================================================================

add_parameter BACKPRESSURE BOOLEAN true
set_parameter_property BACKPRESSURE DISPLAY_NAME "Enable Backpressure FIFO (legacy)"
set_parameter_property BACKPRESSURE DESCRIPTION \
    "Retained compatibility generic. v2 always uses the BP FIFO."
set_parameter_property BACKPRESSURE HDL_PARAMETER true

add_parameter SCHEDULER_USE_PKT_TRANSFER BOOLEAN true
set_parameter_property SCHEDULER_USE_PKT_TRANSFER DISPLAY_NAME "Scheduler Packet Transfer (legacy)"
set_parameter_property SCHEDULER_USE_PKT_TRANSFER HDL_PARAMETER true

add_parameter INVERT_RD_SIG BOOLEAN true
set_parameter_property INVERT_RD_SIG DISPLAY_NAME "Invert Uplink Ready (legacy)"
set_parameter_property INVERT_RD_SIG DESCRIPTION \
    "Inverts the uplink ready input. Preserves existing integration with \
     Intel mux IP."
set_parameter_property INVERT_RD_SIG HDL_PARAMETER true

add_parameter DEBUG NATURAL 1
set_parameter_property DEBUG DISPLAY_NAME "Debug Level"
set_parameter_property DEBUG HDL_PARAMETER true
set_parameter_property DEBUG ALLOWED_RANGES 0:4

# ============================================================================
# GROUP 7: AXI4-specific (visible only when BUS_TYPE=AXI4)
# ============================================================================

add_parameter AXI4_USER_WIDTH NATURAL 16
set_parameter_property AXI4_USER_WIDTH DISPLAY_NAME "AXI4 AxUSER Width (bits)"
set_parameter_property AXI4_USER_WIDTH DESCRIPTION \
    "Width of ARUSER/AWUSER sideband for ordering metadata. \
     Requires: order_type(2) + ord_dom_id(4) + ord_epoch(8) + \
     ord_scope(2) = 16 bits when ORD_ENABLE=true."
set_parameter_property AXI4_USER_WIDTH HDL_PARAMETER false
set_parameter_property AXI4_USER_WIDTH ALLOWED_RANGES {0 1 2 4 8 16 32}

add_parameter AXI4_ID_WIDTH NATURAL 4
set_parameter_property AXI4_ID_WIDTH DISPLAY_NAME "AXI4 ID Width (bits)"
set_parameter_property AXI4_ID_WIDTH DESCRIPTION \
    "Width of ARID/AWID/RID/BID. When OOO_ENABLE=false, all IDs are 0 \
     (single-ID in-order). When OOO_ENABLE=true, IDs differentiate \
     concurrent transactions for OoO completion."
set_parameter_property AXI4_ID_WIDTH HDL_PARAMETER false
set_parameter_property AXI4_ID_WIDTH ALLOWED_RANGES {1 2 4 8}

# ============================================================================
# GROUP 8: Derived parameters (read-only, computed during elaboration)
# ============================================================================

add_parameter EXT_HDR_DEPTH NATURAL 8
set_parameter_property EXT_HDR_DEPTH DISPLAY_NAME "External Header FIFO Depth (derived)"
set_parameter_property EXT_HDR_DEPTH DESCRIPTION \
    "Equal to OUTSTANDING_LIMIT. Derived, not user-settable."
set_parameter_property EXT_HDR_DEPTH HDL_PARAMETER true
set_parameter_property EXT_HDR_DEPTH DERIVED true

add_parameter PLD_ADDR_WIDTH NATURAL 9
set_parameter_property PLD_ADDR_WIDTH DISPLAY_NAME "Payload Address Width (derived)"
set_parameter_property PLD_ADDR_WIDTH DESCRIPTION \
    "ceil(log2(EXT_DOWN_PLD_DEPTH)). Derived."
set_parameter_property PLD_ADDR_WIDTH HDL_PARAMETER true
set_parameter_property PLD_ADDR_WIDTH DERIVED true

add_parameter BURSTCOUNT_WIDTH NATURAL 9
set_parameter_property BURSTCOUNT_WIDTH DISPLAY_NAME "Burstcount Width (derived)"
set_parameter_property BURSTCOUNT_WIDTH DESCRIPTION \
    "ceil(log2(MAX_BURST)) + 1. Derived."
set_parameter_property BURSTCOUNT_WIDTH HDL_PARAMETER true
set_parameter_property BURSTCOUNT_WIDTH DERIVED true

add_parameter EFFECTIVE_EXT_OUTSTANDING NATURAL 6
set_parameter_property EFFECTIVE_EXT_OUTSTANDING DISPLAY_NAME "Effective External Outstanding (derived)"
set_parameter_property EFFECTIVE_EXT_OUTSTANDING DESCRIPTION \
    "OUTSTANDING_LIMIT - OUTSTANDING_INT_RESERVED. Derived."
set_parameter_property EFFECTIVE_EXT_OUTSTANDING HDL_PARAMETER true
set_parameter_property EFFECTIVE_EXT_OUTSTANDING DERIVED true

# The checked-in RTL only exposes the legacy compatibility generics today.
# Keep the richer v2 parameter set in the GUI/reporting layer, but do not pass
# those planned knobs down as VHDL generics until the corresponding RTL exists.
foreach planned_generic {
    BUS_TYPE
    ADDR_WIDTH
    DATA_WIDTH
    OUTSTANDING_LIMIT
    OUTSTANDING_INT_RESERVED
    EXT_DOWN_PLD_DEPTH
    INT_DOWN_PLD_DEPTH
    EXT_UP_PLD_DEPTH
    INT_UP_PLD_DEPTH
    INT_HDR_DEPTH
    MAX_BURST
    BP_FIFO_DEPTH
    OOO_ENABLE
    ORD_ENABLE
    ORD_NUM_DOMAINS
    ATOMIC_ENABLE
    S_AND_F_ENABLE
    HUB_CAP_ENABLE
    RD_TIMEOUT_CYCLES
    WR_TIMEOUT_CYCLES
    AXI4_USER_WIDTH
    AXI4_ID_WIDTH
    EXT_HDR_DEPTH
    PLD_ADDR_WIDTH
    BURSTCOUNT_WIDTH
    EFFECTIVE_EXT_OUTSTANDING
} {
    set_parameter_property $planned_generic HDL_PARAMETER false
}
