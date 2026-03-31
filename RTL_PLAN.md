# SC_HUB v2 — RTL Redesign Plan

**IP Name:** sc_hub (Slow Control Hub)
**Author:** Yifeng Wang
**Planned Version:** 26.2.xxxx
**Baseline:** v26.0.0332 (feb_system_v2 synthesis submodule, with internal CSR)
**Integration Target:** online_dpv2 / fe_scifi / feb_system_v2

---

## 1. Motivation

The current sc_hub (v26.0.0330 in mu3e-ip-cores, v26.0.0332 in feb_system_v2) has three structural limitations:

1. **No internal CSR header in the IP-core tree.** The CSR register map (ID, version, control, status, error, FIFO config, perf counters) exists only in the feb_system_v2 synthesis copy (v26.0.0332). It must be promoted into the canonical IP source.

2. **Avalon-only master interface.** The hub is hard-wired to Avalon-MM. Systems targeting Xilinx or AXI4-based interconnect have no path. The `_hw.tcl` should allow selecting between Avalon-MM and AXI4 master at generation time.

3. **Cut-through only transaction model.** Both download (host→device write) and upload (device→host read) paths use cut-through FIFO semantics:
   - **Download path:** Write data streams from the SC packet directly into `wr_fifo` and is forwarded to AVMM as it arrives. A malformed or truncated packet (missing trailer, wrong length) can partially complete an AVMM write burst, leaving the slave in a corrupted state.
   - **Upload path:** Read data from AVMM streams into `rd_fifo` and is forwarded to the reply link. Cut-through here is correct — the AVMM read is already committed, and streaming reduces latency.
   - **No flush recovery.** `avm_m0_flush` is deprecated in Avalon spec ≥1.2. The current 200-cycle read timeout + flush cannot safely abort a partial burst. Without store-and-forward on the download side, the only option when a packet is bad is to stall the interconnect.

---

## 2. Design Goals

| # | Goal | Acceptance Criteria |
|---|------|---------------------|
| G1 | Canonical CSR header | CSR register map in IP-core source matches v26.0.0332. Internal CSR read/write FSM states (INT_RD, INT_WR) in the main entity. CSR base at 0xFE80, 32-word window. |
| G2 | Dual bus interface | `_hw.tcl` parameter `BUS_TYPE` ∈ {`AVALON`, `AXI4`}. Entity conditionally generates either AVMM or AXI4 master ports. Shared packet FSM, bus-specific transaction handler. |
| G3 | Store-and-forward download | Download FIFO validates entire command packet (preamble through trailer, length match) before releasing to the bus transaction handler. Malformed packets are dropped and counted in CSR error registers. |
| G4 | Cut-through upload | Upload (read reply) path remains cut-through. AVMM/AXI read data streams directly into reply assembly with no packet-level buffering. |
| G5 | Remove `avm_m0_flush` | No flush signal. Read timeout aborts the reply (sends error response code) but does not attempt to flush the interconnect. |
| G6 | Backward-compatible packet format | SC command and reply packet wire format unchanged. The CSR response header (word 2 of reply, bits [29:28] response code, bit [16] header valid) is carried forward from v26.0.0332. |

---

## 3. Architecture

### 3.1 Top-Level Hierarchy

```
sc_hub_top.vhd                    (top-level, Platform Designer boundary)
├── sc_hub_pkt_rx.vhd             (packet receiver + store-and-forward validator)
│   └── sc_hub_fifo_sf.vhd        (store-and-forward FIFO with commit/rollback)
├── sc_hub_core.vhd               (central FSM + CSR + bus dispatch)
│   ├── sc_hub_avmm_handler.vhd   (Avalon-MM transaction handler, generate-conditional)
│   ├── sc_hub_axi4_handler.vhd   (AXI4 transaction handler, generate-conditional)
│   └── sc_hub_fifo_sc.vhd        (read data FIFO, generic SC-FIFO)
├── sc_hub_pkt_tx.vhd             (reply assembly + backpressure FIFO)
│   └── sc_hub_fifo_bp.vhd        (backpressure FIFO, half-full threshold)
└── sc_hub_pkg.vhd                (shared types, constants, CSR offsets)
```

### 3.2 Block Diagram

```
                        sc_hub_top
 ┌──────────────────────────────────────────────────────────────────────────┐
 │                                                                          │
 │  SC CMD         ┌──────────────┐    pkt_valid    ┌──────────────┐       │
 │  (conduit) ────>│ sc_hub_pkt_rx│───────────────->│              │       │
 │  i_linkin_*     │              │    pkt_info      │              │       │
 │                 │ Store-and-   │    wr_data_fifo  │  sc_hub_core │       │
 │                 │ Forward FIFO │────────────────->│              │       │
 │                 │ + Validator  │                   │  - Main FSM  │       │
 │                 └──────────────┘                   │  - CSR regs  │       │
 │                                                    │  - Bus dispatch      │
 │  SC REPLY       ┌──────────────┐    reply_*       │              │       │
 │  (AST/conduit)<─│ sc_hub_pkt_tx│<────────────────│              │       │
 │  aso_to_uplink  │              │                   │   ┌────────┐│       │
 │                 │ Reply assem- │                   │   │ AVMM   ││ AVMM  │
 │                 │ bly + BP FIFO│                   │   │ handler│├──────>│
 │                 └──────────────┘                   │   └────────┘│master │
 │                                                    │       OR     │       │
 │                                                    │   ┌────────┐│       │
 │                                                    │   │ AXI4   ││ AXI4  │
 │                                                    │   │ handler│├──────>│
 │                                                    │   └────────┘│master │
 │                                                    └──────────────┘       │
 │                                                                          │
 └──────────────────────────────────────────────────────────────────────────┘
```

### 3.3 Module Descriptions

#### 3.3.1 `sc_hub_pkt_rx` — Packet Receiver + Store-and-Forward Validator

**Purpose:** Receive 8b10b-framed SC command packets, validate completeness, and present validated packets to the core.

**Behavior:**
1. Detect preamble (K28.5 in byte 0, data type `000111` in bits [31:26]).
2. Buffer header words (preamble, address, length) and write data into a download FIFO (32-bit × 256 deep).
3. Track word count against declared length. Detect trailer (K28.4).
4. **Validation checks before releasing packet:**
   - Trailer present at expected position (word offset = 3 + L for write, 3 for read).
   - Declared length ≤ 256 (fits in FIFO and burstcount).
   - No FIFO overflow during reception.
5. On validation pass: assert `o_pkt_valid` pulse, expose `o_pkt_info` record (sc_type, fpga_id, masks, start_address, rw_length).
6. On validation fail: discard packet, increment `o_pkt_drop_count`, do NOT present to core.

**Ports:**
```
-- Packet link input (conduit)
i_linkin_data[31:0], i_linkin_datak[3:0], o_linkin_ready

-- Validated packet output
o_pkt_valid         : std_logic
o_pkt_info          : sc_pkt_info_t
o_wr_data_rdreq     : in  std_logic          -- core pulls write data
o_wr_data_q         : out std_logic_vector(31 downto 0)
o_wr_data_empty     : out std_logic

-- Status
o_pkt_drop_count[15:0]
o_fifo_usedw[8:0], o_fifo_full, o_fifo_overflow
```

**Store-and-forward detail:** The download FIFO is written word-by-word as the packet arrives. A shadow write pointer is maintained. Only when the trailer passes validation is the shadow pointer committed (FIFO read pointer is released). On validation failure, the shadow pointer is rolled back (packet data is logically discarded without draining). This requires a dual-pointer FIFO or a simple FIFO with a commit/rollback sideband.

#### 3.3.2 `sc_hub_core` — Packet FSM + CSR + Bus Dispatch

**Purpose:** Central control. Accepts validated packets from `pkt_rx`, dispatches bus transactions, manages CSR registers, coordinates reply generation through `pkt_tx`.

**FSM (simplified from current 3-FSM design):**

```
Main FSM:
  IDLE → DISPATCH → {EXT_RD, EXT_WR, INT_RD, INT_WR} → REPLY → IDLE

  IDLE:       Wait for pkt_valid from pkt_rx.
  DISPATCH:   Latch pkt_info. Check internal_csr_hit. Route to EXT or INT handler.
  EXT_RD:     Drive bus handler read interface. Collect responses into rd_fifo.
  EXT_WR:     Drive bus handler write interface. Drain wr_data from pkt_rx FIFO.
  INT_RD:     Combinational CSR lookup (1 cycle per word, single-cycle for single read).
  INT_WR:     CSR register write (single word only, else error).
  REPLY:      Signal pkt_tx with reply metadata + response code. Wait for pkt_tx done.
```

**CSR Register Map (carried forward from v26.0.0332):**

| Offset | Name | R/W | Description |
|--------|------|-----|-------------|
| 0x000 | ID | RO | 0x53480000 ("SH") |
| 0x001 | VERSION | RO | YY.Major.Pre.Month.Day packed |
| 0x002 | CTRL | RW | bit 0: enable, bit 1: flush, bit 2: reset |
| 0x003 | STATUS | RO | busy, has_errors, fifo_status, flushing |
| 0x004 | ERR_FLAGS | W1C | up_overflow, down_overflow, internal_addr_err, rd_timeout |
| 0x005 | ERR_COUNT | RO | Saturating error counter |
| 0x006 | SCRATCH | RW | General-purpose scratch |
| 0x007 | GTS_SNAP_LO | RO | GTS counter low word (snapshot on read of 0x008) |
| 0x008 | GTS_SNAP_HI | RO | GTS counter high word (triggers snapshot) |
| 0x009 | FIFO_CFG | RW | bit 0: download store-and-forward (always 1 in v2), bit 1: upload store-and-forward |
| 0x00A | FIFO_STATUS | RO | full flags, overflow flags |
| 0x00B | DOWN_PKT_CNT | RO | Download FIFO packet count |
| 0x00C | UP_PKT_CNT | RO | Upload FIFO packet count |
| 0x00D | DOWN_USEDW | RO | Download FIFO words used |
| 0x00E | UP_USEDW | RO | Upload FIFO words used |
| 0x00F | EXT_PKT_RD_CNT | RO | External read packet count |
| 0x010 | EXT_PKT_WR_CNT | RO | External write packet count |
| 0x011 | EXT_WORD_RD_CNT | RO | External read word count |
| 0x012 | EXT_WORD_WR_CNT | RO | External write word count |
| 0x013 | LAST_RD_ADDR | RO | Last external read address |
| 0x014 | LAST_RD_DATA | RO | Last external read data |
| 0x015 | LAST_WR_ADDR | RO | Last external write address |
| 0x016 | LAST_WR_DATA | RO | Last external write data |
| 0x017 | PKT_DROP_CNT | RO | **NEW:** Dropped packet count from store-and-forward validation |

**Bus handler interface (abstract, used by both AVMM and AXI4L handlers):**
```
-- Command
i_cmd_valid, i_cmd_ready
i_cmd_type       : rd / wr
i_cmd_address    : 16-bit word address
i_cmd_burstcount : 9-bit
i_cmd_wrdata     : 32-bit (streamed from pkt_rx FIFO for writes)
i_cmd_wrdata_valid, o_cmd_wrdata_ready

-- Response
o_rsp_valid
o_rsp_rddata     : 32-bit
o_rsp_response   : 2-bit (00=OK, 10=SLAVEERROR, 11=DECODEERROR)
o_rsp_rd_done    : pulse on last read word
o_rsp_wr_done    : pulse on write complete
```

#### 3.3.3 `sc_hub_avmm_handler` — Avalon-MM Transaction Handler

**Purpose:** Translate abstract bus commands into Avalon-MM master signals.

**Key changes from current design:**
- **No `avm_m0_flush`.** Read timeout (configurable, default 200 cycles) aborts the transaction internally, returns DECODEERROR response code, but does not assert flush.
- **Single pending transaction.** `maximumPendingReadTransactions = 1`, `maximumPendingWriteTransactions = 1` (unchanged).
- **Write response handling.** `writeresponsevalid` is checked. On SLAVEERROR, the error is propagated to the reply packet.
- **Burst boundary.** `linewrapBursts = false`, `burstOnBurstBoundariesOnly = false` (unchanged).

#### 3.3.4 `sc_hub_axi4_handler` — AXI4 Transaction Handler

**Purpose:** Translate abstract bus commands into AXI4 master signals with native INCR burst support.

**AXI4 burst mapping:**
- SC burst read → single AXI4 AR transaction with ARLEN = rw_length - 1, ARBURST = INCR (01). Read data arrives on R channel, one beat per cycle when RVALID/RREADY.
- SC burst write → single AXI4 AW transaction with AWLEN = rw_length - 1, AWBURST = INCR (01). Write data streamed on W channel with WLAST on final beat. Single B response collected.
- SC single read/write → burst length 1 (ARLEN/AWLEN = 0).
- BRESP/RRESP mapped to the 2-bit response code: OKAY (00) = 00, SLVERR (10) = 10, DECERR (11) = 11.
- Fixed parameters: ARSIZE/AWSIZE = 010 (4 bytes), ARCACHE/AWCACHE = 0011 (normal non-cacheable bufferable), ARPROT/AWPROT = 000 (unprivileged, secure, data).

**AXI4 master ports:**
```
-- Write address channel
m_axi_awid[3:0], m_axi_awaddr[15:0], m_axi_awlen[7:0], m_axi_awsize[2:0]
m_axi_awburst[1:0], m_axi_awvalid, m_axi_awready
-- Write data channel
m_axi_wdata[31:0], m_axi_wstrb[3:0], m_axi_wlast, m_axi_wvalid, m_axi_wready
-- Write response channel
m_axi_bid[3:0], m_axi_bresp[1:0], m_axi_bvalid, m_axi_bready
-- Read address channel
m_axi_arid[3:0], m_axi_araddr[15:0], m_axi_arlen[7:0], m_axi_arsize[2:0]
m_axi_arburst[1:0], m_axi_arvalid, m_axi_arready
-- Read data channel
m_axi_rid[3:0], m_axi_rdata[31:0], m_axi_rresp[1:0], m_axi_rlast
m_axi_rvalid, m_axi_rready
```

**Key design points:**
- **Single outstanding transaction.** Only one AXI4 read or write in flight at a time (ID width = 4 but only ID 0 used). This matches the SC hub's serial command model.
- **WLAST generation.** The handler tracks the write beat count and asserts WLAST on the final beat. This is derived from the burstcount in the abstract command interface.
- **Read timeout.** Same as AVMM handler — configurable cycle count. On timeout, RREADY is held high to drain any late responses, error response code returned to core.
- **No write interleaving.** AW is issued before or simultaneously with the first W beat (AXI4 spec allows this). W beats are streamed consecutively without gaps.
- **Burst length mapping.** SC rw_length (1-256) maps directly to AXI4 AWLEN/ARLEN (0-255). Max AXI4 burst of 256 beats matches the SC max burst.

#### 3.3.5 `sc_hub_pkt_tx` — Reply Assembly + Backpressure FIFO

**Purpose:** Assemble SC reply packets from core signals and buffer them through the backpressure FIFO.

**Behavior:**
1. Core signals reply start with `i_reply_valid`, `i_reply_info` (sc_type, fpga_id, address, length, response code).
2. TX assembles: preamble → address → CSR response header (word 2) → read data (streamed from rd_fifo) → trailer.
3. Output goes through the existing 40-bit × 512-deep backpressure FIFO.
4. Half-full threshold feeds back to `pkt_rx` to deassert `o_linkin_ready`.

**Mute logic:** If `pkt_info.mask_s = '1'` (or mask_r), the reply is suppressed entirely (no packet emitted). This is unchanged from current behavior.

---

## 4. Transaction Model Summary

| Path | Direction | Model | Rationale |
|------|-----------|-------|-----------|
| Download (write) | Host → Device | **Store-and-forward** | Validate entire SC write packet before committing to bus. Prevents partial/corrupt AVMM/AXI writes from malformed packets. Dropped packets are counted, not stalled. |
| Upload (read) | Device → Host | **Cut-through** | AVMM/AXI read is already committed. Streaming read data directly into reply minimizes latency. No validation needed — the bus response is authoritative. |

### 4.1 Download Store-and-Forward Detail

```
Timeline (write command, L data words):

Cycle   pkt_rx                          core                  bus handler
─────   ──────                          ────                  ───────────
1       Receive preamble
2       Receive address word
3       Receive length word
4..3+L  Receive write data → FIFO
4+L     Receive trailer
5+L     Validate: length match, trailer   
        present, no overflow.
        Assert pkt_valid ──────────────> Latch pkt_info
6+L                                      DISPATCH → EXT_WR
7+L                                      Pull wr_data[0] ──> Issue burst write
...                                      Pull wr_data[L-1]   Last write
                                         wr_done ────────────>
                                         REPLY
                                         Signal pkt_tx
```

**Latency cost:** +1 cycle (validation) relative to cut-through. The FIFO fill time overlaps with packet reception, so the only added latency is the single validation cycle after the trailer.

### 4.2 Malformed Packet Handling

| Condition | Detection Point | Action |
|-----------|----------------|--------|
| Missing trailer after declared length | pkt_rx: word count exceeds L+3 without K28.4 | Drop packet, increment PKT_DROP_CNT, set ERR_FLAGS.down_pkt_drop |
| Length > 256 | pkt_rx: length field check | Drop packet |
| FIFO overflow during reception | pkt_rx: fifo_full during write | Drop packet (rollback write pointer) |
| Truncated packet (link loss mid-packet) | pkt_rx: timeout (no new word for N cycles) | Drop partial packet, rollback |
| Wrong data type in preamble | pkt_rx: bits [31:26] ≠ "000111" | Ignore (not an SC packet) |

---

## 5. `_hw.tcl` Generation

### 5.1 New Parameter

```tcl
add_parameter BUS_TYPE STRING "AVALON"
set_parameter_property BUS_TYPE ALLOWED_RANGES {"AVALON" "AXI4"}
set_parameter_property BUS_TYPE DISPLAY_NAME "Bus Interface Type"
set_parameter_property BUS_TYPE DESCRIPTION "Select Avalon-MM or AXI4 master interface"
set_parameter_property BUS_TYPE HDL_PARAMETER true
```

### 5.2 Conditional Interface Generation

```tcl
proc elaborate {} {
    set bus_type [get_parameter_value BUS_TYPE]

    if {$bus_type == "AVALON"} {
        add_interface hub_master avalon start
        # ... existing AVMM port definitions (address, read, readdata, etc.)
        # Remove avm_m0_flush port
    } elseif {$bus_type == "AXI4"} {
        add_interface hub_master axi4 master
        # ... AXI4 port definitions (awaddr, awlen, awburst, wdata, wlast, etc.)
    }

    # Common interfaces unchanged:
    # hub_clock, hub_reset, hub_sc_packet_downlink, hub_sc_packet_uplink
}
```

### 5.3 Conditional File Inclusion

```tcl
# Common files (no vendor megafunction dependency)
add_fileset_file sc_hub_pkg.vhd           VHDL PATH sc_hub_pkg.vhd
add_fileset_file fifo/sc_hub_fifo_sc.vhd  VHDL PATH fifo/sc_hub_fifo_sc.vhd
add_fileset_file fifo/sc_hub_fifo_sf.vhd  VHDL PATH fifo/sc_hub_fifo_sf.vhd
add_fileset_file fifo/sc_hub_fifo_bp.vhd  VHDL PATH fifo/sc_hub_fifo_bp.vhd
add_fileset_file sc_hub_pkt_rx.vhd        VHDL PATH sc_hub_pkt_rx.vhd
add_fileset_file sc_hub_pkt_tx.vhd        VHDL PATH sc_hub_pkt_tx.vhd
add_fileset_file sc_hub_core.vhd          VHDL PATH sc_hub_core.vhd
add_fileset_file sc_hub_top.vhd           VHDL PATH sc_hub_top.vhd TOP_LEVEL_FILE

# Bus-specific handler
if {$bus_type == "AVALON"} {
    add_fileset_file sc_hub_avmm_handler.vhd  VHDL PATH sc_hub_avmm_handler.vhd
} elseif {$bus_type == "AXI4"} {
    add_fileset_file sc_hub_axi4_handler.vhd  VHDL PATH sc_hub_axi4_handler.vhd
}
```

---

## 6. HDL Generic Parameters

| Generic | Type | Default | Description |
|---------|------|---------|-------------|
| `BUS_TYPE` | string | `"AVALON"` | `"AVALON"` or `"AXI4"` — selects bus handler |
| `ADDR_WIDTH` | natural | 16 | Master address width (word addressing) |
| `MAX_BURST` | natural | 256 | Maximum burst length in words |
| `RD_TIMEOUT_CYCLES` | natural | 200 | Read timeout before aborting (no flush) |
| `BP_FIFO_DEPTH` | natural | 512 | Backpressure FIFO depth (reply path) |
| `DL_FIFO_DEPTH` | natural | 256 | Download FIFO depth (must be ≥ MAX_BURST) |
| `DEBUG` | natural | 1 | Debug level (0=none, 1=counters, 2=ILA-ready) |

---

## 7. File Plan

```
slow-control_hub/
│
├── sc_hub_hw.tcl               NEW (v2) Platform Designer component (NAME: sc_hub_v2, VERSION: 26.2.xxxx)
├── sc_hub_top.vhd              NEW (v2) Top-level: instantiate pkt_rx, core, pkt_tx
├── sc_hub_core.vhd             NEW (v2) Central FSM + CSR + bus dispatch
├── sc_hub_pkt_rx.vhd           NEW (v2) Store-and-forward packet receiver + validator
├── sc_hub_pkt_tx.vhd           NEW (v2) Reply assembly + backpressure FIFO
├── sc_hub_avmm_handler.vhd     NEW (v2) Avalon-MM bus transaction handler
├── sc_hub_axi4_handler.vhd     NEW (v2) AXI4 bus transaction handler (INCR burst)
├── sc_hub_pkg.vhd              NEW (v2) Shared types (sc_pkt_info_t, constants, CSR offsets)
├── fifo/
│   ├── sc_hub_fifo_sc.vhd      NEW (v2) Generic SC-FIFO (show-ahead, parameterised width/depth)
│   ├── sc_hub_fifo_sf.vhd      NEW (v2) Store-and-forward FIFO (commit/rollback write pointer)
│   └── sc_hub_fifo_bp.vhd      NEW (v2) Backpressure FIFO (40-bit, half-full threshold output)
│
├── legacy/
│   ├── sc_hub_hw.tcl            OLD (v1) Platform Designer component (NAME: sc_hub, VERSION: 26.0.330)
│   ├── sc_hub.vhd               OLD (v1) Monolithic core (v26.0.0330)
│   ├── sc_hub_top.vhd           OLD (v1) Top-level with backpressure FIFO
│   ├── sc_hub_wrapper.vhd       OLD (v1) External integration wrapper
│   ├── dp_ram.vhd               OLD (v1) Dual-port RAM utility
│   ├── sc_hub_24p0p0711_hw.tcl  OLD      Historical _hw.tcl versions
│   ├── sc_hub_25p0p0809_hw.tcl  OLD      ...
│   ├── sc_hub_2p7p0_hw.tcl      OLD      ...
│   ├── sc_hub_2p7p11_hw.tcl     OLD      ...
│   └── alt_ip/                  OLD (v1) Intel megafunction FIFOs
│       ├── alt_fifo_w32d256/
│       └── alt_fifo_w40d512/
│
└── RTL_PLAN.md                 THIS FILE
```

### Dual `_hw.tcl` — Both Versions Available in Platform Designer

Both the legacy v1 and the new v2 IP are registered as separate Platform Designer components. This allows existing systems to continue using the old hub while new designs adopt v2.

| Component | `_hw.tcl` Location | NAME | VERSION | GROUP |
|-----------|-------------------|------|---------|-------|
| Legacy v1 | `legacy/sc_hub_hw.tcl` | `sc_hub` | 26.0.330 | "Mu3e Control Plane/Modules" |
| New v2 | `sc_hub_hw.tcl` | `sc_hub_v2` | 26.2.xxxx | "Mu3e Control Plane/Modules" |

Platform Designer discovers both `_hw.tcl` files via the IP search path. Using different NAMEs (`sc_hub` vs `sc_hub_v2`) ensures they appear as distinct components and can coexist in the same Qsys system or IP catalog. Existing `.qsys` files that reference `sc_hub` continue to resolve to the legacy `_hw.tcl` in `legacy/` without modification.

**No legacy file dependency.** The v2 IP is built from scratch. The v2 source tree has zero imports from files in `legacy/`. The legacy files are preserved solely for backward compatibility with existing Platform Designer systems.

**Vendor-neutral FIFOs.** The current v1 design depends on Intel `alt_fifo_w32d256` and `alt_fifo_w40d512` megafunctions. The v2 design replaces these with portable VHDL FIFO implementations (inferred block RAM, compatible with both Intel and Xilinx synthesis). The download FIFO adds commit/rollback semantics for store-and-forward:
```
fifo/
├── sc_hub_fifo_sc.vhd          Generic SC-FIFO (show-ahead, parameterised width/depth)
├── sc_hub_fifo_sf.vhd          Store-and-forward FIFO (commit/rollback write pointer)
└── sc_hub_fifo_bp.vhd          Backpressure FIFO (40-bit, half-full threshold output)
```

---

## 8. Verification Strategy

### 8.1 Testbench Components (Questa FSE compatible — no rand, no covergroup, no DPI)

| Component | Purpose |
|-----------|---------|
| `sc_hub_tb_top.sv` | Top-level testbench, clock/reset generation |
| `sc_pkt_driver.sv` | Drive SC command packets (preamble→data→trailer) with configurable errors |
| `sc_pkt_monitor.sv` | Capture and check SC reply packets |
| `avmm_slave_bfm.sv` | Simple Avalon-MM slave model (memory-backed, configurable latency/errors) |
| `axi4_slave_bfm.sv` | Simple AXI4 slave model (memory-backed, burst-capable) |

### 8.2 Test Cases

| # | Test | Checks |
|---|------|--------|
| T1 | Single read, single write | Basic functionality, CSR response header format |
| T2 | Burst read (256 words) | Max burst, word count, reply data integrity |
| T3 | Burst write (256 words) | Store-and-forward: data not issued until trailer validated |
| T4 | Malformed write (missing trailer) | Packet dropped, PKT_DROP_CNT incremented, no bus activity |
| T5 | Malformed write (length mismatch) | Packet dropped, no partial write on bus |
| T6 | Read timeout | Error response code (DECODEERROR), no flush signal |
| T7 | Slave error on write | SLAVEERROR propagated in reply response code |
| T8 | Internal CSR read/write | All CSR offsets readable, writable registers functional |
| T9 | Back-to-back packets | No inter-packet stall, pipeline throughput |
| T10 | Backpressure (uplink not ready) | BP FIFO absorbs, linkin_ready deasserted at threshold |
| T11 | Mute mask | Reply suppressed when mask bit set |
| T12 | AXI4 single read/write | AXI4 handler basic functionality, ARLEN/AWLEN = 0 |
| T13 | AXI4 burst read/write (256 words) | Native INCR burst, WLAST assertion, RLAST check |
| T14 | AXI4 write with BRESP error | SLVERR propagated through B channel to reply |

---

## 9. Migration Notes

### 9.1 Backward Compatibility

- **Packet format:** Unchanged. Existing host software (midas frontends, `mhttpd` SC pages) requires no changes.
- **CSR register map:** Superset of v26.0.0332. One new register (0x017 PKT_DROP_CNT). Existing CSR read scripts remain compatible.
- **AVMM interface:** Identical except `avm_m0_flush` is removed. Systems that connect flush to a dummy signal will work. Systems that rely on flush for recovery need to handle read timeout via the error response code instead.

### 9.2 Integration in feb_system_v2

The current integration path:
```
feb_system_v2 (Qsys)
  └── sc_hub (instance) ── hub_avmm ──> system interconnect
        ↑ hub_sc_packet_downlink (from 5G link decoder)
        ↓ hub_sc_packet_uplink (to 5G link encoder)
```

Migration:
1. Replace `sc_hub` IP in Qsys with updated `sc_hub` (v26.2.xxxx).
2. Set `BUS_TYPE = "AVALON"` (default, no change for existing systems).
3. Remove any external flush signal connections (flush port no longer exists).
4. Remove external download/upload FIFOs if present — all FIFOs are now internal. The external FIFO sideband ports (`i_download_fifo_*`, `i_upload_fifo_*`) from v26.0.0332 no longer exist; FIFO status is accessible only via internal CSR registers.
5. No dependency on Intel `alt_fifo` megafunctions — the new FIFOs use inferred block RAM, portable across Intel and Xilinx.

---

## 10. Open Questions

1. **Download FIFO: commit/rollback vs. drain-and-discard?**
   Commit/rollback (shadow write pointer) is cleaner but requires a custom FIFO wrapper around the Intel FIFO IP. Drain-and-discard (read and throw away on validation fail) is simpler but wastes cycles proportional to packet size. Recommend: commit/rollback with a thin wrapper over `alt_fifo_w32d256` that adds a `commit`/`rollback` sideband.

2. **GTS counter input.**
   The CSR exposes GTS snapshot registers (0x007, 0x008). The v26.0.0332 design reads from an implicit internal counter. Should the v2 design accept an external GTS timestamp input port for synchronisation with the system time, or keep the internal free-running counter?
