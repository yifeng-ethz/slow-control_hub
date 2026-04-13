package require Tcl 8.5

set script_dir [file dirname [info script]]
set helper_file [file normalize [file join $script_dir .. dashboard_infra cmsis_svd lib mu3e_cmsis_svd.tcl]]
source $helper_file

namespace eval ::mu3e::cmsis::spec {}

proc ::mu3e::cmsis::spec::build_device {} {
    set registers [list \
        [::mu3e::cmsis::svd::register UID 0x00 \
            -description {Immutable Mu3e IP identifier. Default ASCII "SCHB".} \
            -access read-only \
            -resetValue 0x53434842 \
            -fields [list \
                [::mu3e::cmsis::svd::field value 0 32 \
                    -description {Compile-time or integration-time UID word. Default ASCII "SCHB".} \
                    -access read-only]]] \
        [::mu3e::cmsis::svd::register META 0x04 \
            -description {Read-multiplexed metadata word. Write page_sel[1:0] before reading back: 0=VERSION, 1=DATE, 2=GIT, 3=INSTANCE_ID.} \
            -access read-write \
            -fields [list \
                [::mu3e::cmsis::svd::field page_sel 0 2 \
                    -description "Selects the META readback page." \
                    -access read-write] \
                [::mu3e::cmsis::svd::field reserved 2 30 \
                    -description "Reserved, read as zero." \
                    -access read-only]]] \
        [::mu3e::cmsis::svd::register CTRL 0x08 \
            -description "Enable, diagnostic clear, and software-reset control word." \
            -access read-write \
            -fields [list \
                [::mu3e::cmsis::svd::field enable 0 1 \
                    -description "Global enable for packet execution." \
                    -access read-write] \
                [::mu3e::cmsis::svd::field diag_clear 1 1 \
                    -description "Clears software-visible counters and sticky diagnostics." \
                    -access w1c] \
                [::mu3e::cmsis::svd::field soft_reset 2 1 \
                    -description "Requests a local soft-reset pulse." \
                    -access w1s] \
                [::mu3e::cmsis::svd::field reserved 3 29 \
                    -description "Reserved, read as zero." \
                    -access read-only]]] \
        [::mu3e::cmsis::svd::register STATUS 0x0C \
            -description "Busy/error summary and FIFO/bus state." \
            -access read-only \
            -fields [list \
                [::mu3e::cmsis::svd::field busy 0 1 -description "Core FSM is not idle." -access read-only] \
                [::mu3e::cmsis::svd::field error 1 1 -description "Error summary derived from ERR_FLAGS." -access read-only] \
                [::mu3e::cmsis::svd::field dl_fifo_full 2 1 -description "Download FIFO full." -access read-only] \
                [::mu3e::cmsis::svd::field bp_full 3 1 -description "Reply/backpressure FIFO full." -access read-only] \
                [::mu3e::cmsis::svd::field enable_state 4 1 -description "Current latched enable state." -access read-only] \
                [::mu3e::cmsis::svd::field bus_busy 5 1 -description "External bus handler is busy." -access read-only] \
                [::mu3e::cmsis::svd::field reserved 6 26 -description "Reserved, read as zero." -access read-only]]] \
        [::mu3e::cmsis::svd::register ERR_FLAGS 0x10 \
            -description "Sticky overflow, timeout, packet-drop, and bus error flags." \
            -access read-write \
            -fields [list \
                [::mu3e::cmsis::svd::field up_overflow 0 1 -description "Upload/backpressure FIFO overflow observed." -access rw1c] \
                [::mu3e::cmsis::svd::field down_overflow 1 1 -description "Download ingress FIFO overflow observed." -access rw1c] \
                [::mu3e::cmsis::svd::field int_addr_err 2 1 -description "Internal CSR access targeted an unmapped word." -access rw1c] \
                [::mu3e::cmsis::svd::field rd_timeout 3 1 -description "External read timed out." -access rw1c] \
                [::mu3e::cmsis::svd::field pkt_drop 4 1 -description "Malformed or truncated packet was dropped before execution." -access rw1c] \
                [::mu3e::cmsis::svd::field slverr 5 1 -description "Slave error returned by the external bus." -access rw1c] \
                [::mu3e::cmsis::svd::field decerr 6 1 -description "Decode error returned by the external bus." -access rw1c] \
                [::mu3e::cmsis::svd::field reserved 7 25 -description "Reserved, read as zero." -access read-only]]] \
        [::mu3e::cmsis::svd::register ERR_COUNT 0x14 \
            -description "Saturating 32-bit error counter." \
            -access read-only \
            -fields [list [::mu3e::cmsis::svd::field value 0 32 -description "Accumulated error count." -access read-only]]] \
        [::mu3e::cmsis::svd::register SCRATCH 0x18 \
            -description "General-purpose software scratch register." \
            -access read-write \
            -fields [list [::mu3e::cmsis::svd::field value 0 32 -description "Scratch value." -access read-write]]] \
        [::mu3e::cmsis::svd::register GTS_SNAP_LO 0x1C \
            -description "Global-timestamp snapshot low word." \
            -access read-only \
            -fields [list [::mu3e::cmsis::svd::field value 0 32 -description "Low 32 bits of the captured timestamp." -access read-only]]] \
        [::mu3e::cmsis::svd::register GTS_SNAP_HI 0x20 \
            -description "Global-timestamp snapshot high word. Reading this register captures a fresh snapshot." \
            -access read-only \
            -fields [list [::mu3e::cmsis::svd::field value 0 32 -description "High 32 bits of the captured timestamp." -access read-only]]] \
        [::mu3e::cmsis::svd::register FIFO_CFG 0x24 \
            -description "Backpressure and store-and-forward configuration summary." \
            -access read-only \
            -fields [list \
                [::mu3e::cmsis::svd::field backpressure_on 0 1 -description "Reply FIFO/backpressure path present in this build." -access read-only] \
                [::mu3e::cmsis::svd::field store_forward 1 1 -description "Write packets are validated before any external side effect." -access read-only] \
                [::mu3e::cmsis::svd::field reserved 2 30 -description "Reserved, read as zero." -access read-only]]] \
        [::mu3e::cmsis::svd::register FIFO_STATUS 0x28 \
            -description "Download, reply, and read-data FIFO state summary." \
            -access read-only \
            -fields [list \
                [::mu3e::cmsis::svd::field dl_full 0 1 -description "Download FIFO full." -access read-only] \
                [::mu3e::cmsis::svd::field bp_full 1 1 -description "Reply/backpressure FIFO full." -access read-only] \
                [::mu3e::cmsis::svd::field dl_overflow 2 1 -description "Download FIFO overflow sticky summary." -access read-only] \
                [::mu3e::cmsis::svd::field bp_overflow 3 1 -description "Reply/backpressure FIFO overflow sticky summary." -access read-only] \
                [::mu3e::cmsis::svd::field rd_fifo_full 4 1 -description "Read-data staging FIFO full." -access read-only] \
                [::mu3e::cmsis::svd::field rd_fifo_empty 5 1 -description "Read-data staging FIFO empty." -access read-only] \
                [::mu3e::cmsis::svd::field reserved 6 26 -description "Reserved, read as zero." -access read-only]]] \
        [::mu3e::cmsis::svd::register DOWN_PKT_CNT 0x2C \
            -description "Download packet occupancy summary bit." \
            -access read-only \
            -fields [list [::mu3e::cmsis::svd::field value 0 32 -description "Raw download packet occupancy summary word." -access read-only]]] \
        [::mu3e::cmsis::svd::register UP_PKT_CNT 0x30 \
            -description "Reply FIFO packet count." \
            -access read-only \
            -fields [list [::mu3e::cmsis::svd::field value 0 32 -description "Reply FIFO packet count." -access read-only]]] \
        [::mu3e::cmsis::svd::register DOWN_USEDW 0x34 \
            -description "Download FIFO used words." \
            -access read-only \
            -fields [list [::mu3e::cmsis::svd::field value 0 32 -description "Download FIFO occupancy in words." -access read-only]]] \
        [::mu3e::cmsis::svd::register UP_USEDW 0x38 \
            -description "Reply FIFO used words." \
            -access read-only \
            -fields [list [::mu3e::cmsis::svd::field value 0 32 -description "Reply FIFO occupancy in words." -access read-only]]] \
        [::mu3e::cmsis::svd::register EXT_PKT_RD 0x3C \
            -description "External read packet counter." \
            -access read-only \
            -fields [list [::mu3e::cmsis::svd::field value 0 32 -description "Count of external read packets." -access read-only]]] \
        [::mu3e::cmsis::svd::register EXT_PKT_WR 0x40 \
            -description "External write packet counter." \
            -access read-only \
            -fields [list [::mu3e::cmsis::svd::field value 0 32 -description "Count of external write packets." -access read-only]]] \
        [::mu3e::cmsis::svd::register EXT_WORD_RD 0x44 \
            -description "External read word counter." \
            -access read-only \
            -fields [list [::mu3e::cmsis::svd::field value 0 32 -description "Count of external read data words." -access read-only]]] \
        [::mu3e::cmsis::svd::register EXT_WORD_WR 0x48 \
            -description "External write word counter." \
            -access read-only \
            -fields [list [::mu3e::cmsis::svd::field value 0 32 -description "Count of external write data words." -access read-only]]] \
        [::mu3e::cmsis::svd::register LAST_RD_ADDR 0x4C \
            -description "Last external read address." \
            -access read-only \
            -fields [list [::mu3e::cmsis::svd::field value 0 32 -description "Most recent external read address word." -access read-only]]] \
        [::mu3e::cmsis::svd::register LAST_RD_DATA 0x50 \
            -description "Last external read data." \
            -access read-only \
            -fields [list [::mu3e::cmsis::svd::field value 0 32 -description "Most recent external read data word." -access read-only]]] \
        [::mu3e::cmsis::svd::register LAST_WR_ADDR 0x54 \
            -description "Last external write address." \
            -access read-only \
            -fields [list [::mu3e::cmsis::svd::field value 0 32 -description "Most recent external write address word." -access read-only]]] \
        [::mu3e::cmsis::svd::register LAST_WR_DATA 0x58 \
            -description "Last external write data." \
            -access read-only \
            -fields [list [::mu3e::cmsis::svd::field value 0 32 -description "Most recent external write data word." -access read-only]]] \
        [::mu3e::cmsis::svd::register PKT_DROP_CNT 0x5C \
            -description "Malformed-packet drop counter." \
            -access read-only \
            -fields [list [::mu3e::cmsis::svd::field value 0 32 -description "Count of dropped malformed packets." -access read-only]]] \
        [::mu3e::cmsis::svd::register OOO_CTRL 0x60 \
            -description "Runtime out-of-order enable request. Only effective when OOO support is synthesized." \
            -access read-write \
            -fields [list \
                [::mu3e::cmsis::svd::field ooo_runtime_enable 0 1 \
                    -description "Runtime request to enable out-of-order completion." \
                    -access read-write] \
                [::mu3e::cmsis::svd::field reserved 1 31 -description "Reserved, read as zero." -access read-only]]] \
        [::mu3e::cmsis::svd::register ORD_DRAIN_CNT 0x64 \
            -description "Release-drain event counter." \
            -access read-only \
            -fields [list [::mu3e::cmsis::svd::field value 0 32 -description "Count of release-drain events." -access read-only]]] \
        [::mu3e::cmsis::svd::register ORD_HOLD_CNT 0x68 \
            -description "Acquire-hold event counter." \
            -access read-only \
            -fields [list [::mu3e::cmsis::svd::field value 0 32 -description "Count of acquire-hold events." -access read-only]]] \
        [::mu3e::cmsis::svd::register DBG_DROP_DETAIL 0x6C \
            -description "Last dropped-packet debug detail word." \
            -access read-only \
            -fields [list [::mu3e::cmsis::svd::field value 0 32 -description "Raw debug detail for the last packet drop." -access read-only]]] \
        [::mu3e::cmsis::svd::register FEB_TYPE 0x70 \
            -description "Local detector-class selector used by M/S/T packet masking: 0=ALL, 1=MUPIX, 2=SCIFI, 3=TILE." \
            -access read-write \
            -fields [list \
                [::mu3e::cmsis::svd::field feb_type 0 2 -description "Local detector class selector." -access read-write] \
                [::mu3e::cmsis::svd::field reserved 2 30 -description "Reserved, read as zero." -access read-only]]] \
        [::mu3e::cmsis::svd::register HUB_CAP 0x7C \
            -description "Compile-time capability bits and identity-header presence." \
            -access read-only \
            -fields [list \
                [::mu3e::cmsis::svd::field ooo_capable 0 1 -description "Compile-time out-of-order support synthesized." -access read-only] \
                [::mu3e::cmsis::svd::field ordering_capable 1 1 -description "Compile-time acquire/release ordering tracker synthesized." -access read-only] \
                [::mu3e::cmsis::svd::field atomic_capable 2 1 -description "Compile-time atomic read-modify-write support synthesized." -access read-only] \
                [::mu3e::cmsis::svd::field identity_header 3 1 -description "Common Mu3e UID + META identity header implemented at words 0x00 and 0x01." -access read-only] \
                [::mu3e::cmsis::svd::field reserved 4 28 -description "Reserved, read as zero." -access read-only]]]]

    return [::mu3e::cmsis::svd::device MU3E_SC_HUB \
        -version 26.6.1.0411 \
        -description "CMSIS-SVD description of the slow-control hub internal CSR window. BaseAddress is 0 because this file describes the relative hub-owned register window; system integration supplies the live slave base address." \
        -peripherals [list \
            [::mu3e::cmsis::svd::peripheral SC_HUB_INTERNAL_CSR 0x0 \
                -description "Relative internal CSR aperture for the slow-control hub. The window spans 32 words; registers not listed in this file are reserved holes." \
                -groupName MU3E_SC_HUB \
                -addressBlockSize 0x80 \
                -registers $registers]]]
}

if {[info exists ::argv0] &&
    [file normalize $::argv0] eq [file normalize [info script]]} {
    set out_path [file join $script_dir sc_hub.svd]
    if {[llength $::argv] >= 1} {
        set out_path [lindex $::argv 0]
    }
    ::mu3e::cmsis::svd::write_device_file \
        [::mu3e::cmsis::spec::build_device] $out_path
}
