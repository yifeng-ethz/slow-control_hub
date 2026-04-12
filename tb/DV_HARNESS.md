# SC_HUB v2 -- DV Harness Architecture

**Parent:** [DV_PLAN.md](DV_PLAN.md)
**Skill Reference:** `~/.claude/skills/dv-workflow/SKILL.md`
**RTL Under Test:** `rtl/sc_hub_top.vhd` (AVMM), `rtl/sc_hub_top_axi4.vhd` (AXI4)
**Sub-blocks:** `sc_hub_core`, `sc_hub_pkt_rx`, `sc_hub_pkt_tx`, `sc_hub_avmm_handler`, `sc_hub_axi4_handler`, `sc_hub_axi4_ooo_handler`, `sc_hub_payload_ram`, `sc_hub_axi4_core`
**Prefix:** `sc_hub_` (env/scoreboard/coverage), `sc_pkt_` (packet agent)
**Version:** 26.6.1

Canonical plan note: `DV_BASIC/DV_EDGE/DV_PROF/DV_ERROR` now carry the full workflow-sized canonical plan. Only the rows with legacy `Txxx` aliases are runnable in the checked-in harness today; planned-only canonical rows are intentionally unresolved until implementation lands.

---

## 1. DUT Boundary

The testbench wraps `sc_hub_top` (AVMM) or `sc_hub_top_axi4` (AXI4). Bus selection is compile-time via `+define+SC_HUB_BUS_AXI4`. The harness replaces every external actor:

| System actor | Testbench model |
|---|---|
| 5G link decoder (`swb_sc_main`) | `sc_pkt_driver_uvm` via `sc_pkt_if` |
| 5G link encoder (`swb_sc_secondary`) | `sc_pkt_monitor_uvm` via `sc_reply_if` |
| Qsys AVMM interconnect + downstream IPs | `avmm_slave_bfm` via `sc_hub_avmm_if` |
| Qsys AXI4 interconnect + downstream IPs | `axi4_slave_bfm` via `sc_hub_axi4_if` |
| Host CSR access (jtag_avalon_master) | Direct drive of `avs_csr_*` ports in `tb_top` |

No external clock-domain crossing exists at the DUT boundary -- `sc_hub_top` is single-clock (`i_clk`, synchronous active-high `i_rst`). The registered soft-reset path (`core_soft_reset_pulse OR rx_soft_reset_pulse -> soft_reset_pulse`) adds one cycle of latency; tests that inject a soft-reset must account for this pipeline stage.

### 1.1 DUT Generics Under Test

| Generic | Default | Sweep range | Notes |
|---|---|---|---|
| `BACKPRESSURE` | `true` | `{true, false}` | Controls download-ready gating |
| `OOO_ENABLE` | `false` | `{true, false}` | AXI4-only, enables out-of-order completion |
| `ORD_ENABLE` | `true` | `{true, false}` | Release/acquire ordering semantics |
| `ATOMIC_ENABLE` | `true` | `{true, false}` | Read-modify-write atomic support |
| `HUB_CAP_ENABLE` | `true` | `{true, false}` | CSR HUB_CAP register visibility |
| `EXT_PLD_DEPTH` | 256 | `{64, 128, 256, 512}` | Download payload FIFO depth |
| `PKT_QUEUE_DEPTH` | 16 | `{4, 8, 16}` | Packet queue staging depth |
| `BP_FIFO_DEPTH` | 512 | `{128, 256, 512}` | Backpressure (upload) FIFO depth |
| `RD_TIMEOUT_CYCLES` | 200 | `{50, 200, 1000}` | Bus read timeout threshold |
| `WR_TIMEOUT_CYCLES` | 200 | `{50, 200, 1000}` | Bus write timeout threshold |
| `OUTSTANDING_LIMIT` | 8 | `{1, 4, 8}` | Pending-queue depth (AXI4 OoO slots) |
| `OUTSTANDING_INT_RESERVED` | 2 | `{0, 2, 4}` | Reserved internal-priority slots |

---

## 2. Environment Architecture

```
tb_top.sv
  sc_hub_uvm_tb_top (module)
  +-- clk_gen                              156.25 MHz (6.4 ns period)
  +-- rst_gen                              synchronous, 16 cycles
  +-- sc_pkt_if     sc_pkt_vif             download link interface
  +-- sc_reply_if   sc_reply_vif           upload link interface
  +-- sc_hub_avmm_if / sc_hub_axi4_if     bus interface (compile-time)
  +-- sc_hub_top / sc_hub_top_axi4         DUT
  +-- avmm_slave_bfm / axi4_slave_bfm     bus BFM (reactive slave)
  +-- [bind] sc_hub_uvm_assertions_bind    SVA assertions
  +-- UVM test (set via +UVM_TESTNAME)
       +-- sc_hub_uvm_env
            +-- sc_hub_uvm_env_cfg         run-time configuration object
            +-- sc_pkt_agent               SC packet agent (active)
            |    +-- sc_pkt_sequencer
            |    +-- sc_pkt_driver_uvm     drives sc_pkt_if
            |    +-- sc_pkt_monitor_uvm    monitors sc_reply_if
            +-- bus_agent                  bus monitor agent (passive)
            |    +-- bus_slave_monitor_uvm monitors sc_hub_avmm_if or sc_hub_axi4_if
            +-- sc_hub_scoreboard_uvm      reference-model checker
            +-- sc_hub_cov_collector       functional covergroups
            +-- sc_hub_ord_checker_uvm     ordering/atomic protocol checker
```

### 2.1 Configuration Object (`sc_hub_uvm_env_cfg`)

The env config is set from plusargs in the base test and propagated to all sub-components via `uvm_config_db`. Key fields:

| Field | Type | Drives |
|---|---|---|
| `bus_type` | `sc_hub_bus_e` | AVMM vs AXI4 BFM selection |
| `rd_latency`, `wr_latency` | `int unsigned` | BFM response latency |
| `enable_ooo` | `bit` | Scoreboard OoO-aware matching |
| `enable_ordering` | `bit` | Ordering-checker epoch-monotonic checks |
| `enable_atomic` | `bit` | Atomic sequence generation |
| `enable_perf` | `bit` | Performance sweep sequences |
| `enable_bp` | `bit` | Backpressure injection sequences |
| `enable_error` | `bit` | Error injection (bus error, decode error) |
| `check_order_epoch_monotonic` | `bit` | Strict epoch-monotonic checking |
| `sweep_addr_start/end/step` | `int unsigned` | Address sweep range |
| `perf_burst_min/max/step` | `int unsigned` | Burst length sweep parameters |

---

## 3. Interface Definitions

### 3.1 `sc_pkt_if` -- SC Downlink (to DUT)

```systemverilog
interface sc_pkt_if(input logic clk);
  logic        rst;
  logic [31:0] data;       // i_download_data
  logic [3:0]  datak;      // i_download_datak
  logic        ready;      // o_download_ready (active high)
endinterface
```

Maps to DUT ports `i_download_data`, `i_download_datak`, `o_download_ready`.

### 3.2 `sc_reply_if` -- SC Uplink (from DUT)

```systemverilog
interface sc_reply_if(input logic clk);
  logic        rst;
  logic [35:0] data;       // aso_upload_data
  logic        valid;      // aso_upload_valid
  logic        ready;      // aso_upload_ready
  logic        sop;        // aso_upload_startofpacket
  logic        eop;        // aso_upload_endofpacket
endinterface
```

Maps to DUT ports `aso_upload_*`. Note: `INVERT_RD_SIG` inverts `ready` polarity inside the DUT; the testbench drives `ready` with normal active-high semantics.

### 3.3 `sc_hub_avmm_if` -- Avalon-MM Master Bus

```systemverilog
interface sc_hub_avmm_if(input logic clk);
  logic        rst;
  logic [17:0] address;         // avm_hub_address
  logic        read;            // avm_hub_read
  logic [31:0] readdata;        // avm_hub_readdata
  logic        writeresponsevalid; // avm_hub_writeresponsevalid
  logic [1:0]  response;        // avm_hub_response
  logic        write;           // avm_hub_write
  logic [31:0] writedata;       // avm_hub_writedata
  logic        waitrequest;     // avm_hub_waitrequest
  logic        readdatavalid;   // avm_hub_readdatavalid
  logic [8:0]  burstcount;      // avm_hub_burstcount
  // Error injection control (testbench-only)
  logic        inject_rd_error;
  logic        inject_wr_error;
  logic        inject_decode_error;
endinterface
```

### 3.4 `sc_hub_axi4_if` -- AXI4 Master Bus

Full AXI4 with 5 channels (AW/W/B/AR/R), 4-bit ID, 18-bit address, 32-bit data, plus error-injection control signals (`inject_rd_error`, `inject_wr_error`, `inject_decode_error`, `inject_rresp_err`, `inject_bresp_err`).

### 3.5 CSR Slave Port

The `avs_csr_*` port group is directly driven by the tb_top module (not through a UVM agent). The CSR window is 32 words at base `0xFE80`. This interface is used for:
- identity readback verification (UID at word 0, version at word 1)
- scratch register R/W
- FIFO configuration register access
- error flag readback and clear

---

## 4. Agent Topology

### 4.1 SC Packet Agent (`sc_pkt_agent`) -- Active

**Sequencer** (`sc_pkt_sequencer`): standard `uvm_sequencer#(sc_pkt_seq_item)`.

**Driver** (`sc_pkt_driver_uvm`):
- Converts `sc_pkt_seq_item` into byte-level SC packet protocol on `sc_pkt_if`
- Emits K28.5 SOP, header words, optional payload words, K28.4 EOP
- Respects `ready` backpressure from DUT
- Publishes sent command via `sent_ap` analysis port for scoreboard/coverage/ordering checker

**Monitor** (`sc_pkt_monitor_uvm`):
- Decodes SC reply packets from `sc_reply_if`
- Reconstructs `sc_reply_item` with header fields (sc_type, fpga_id, start_address, response, echoed_length, ordering metadata, atomic flag) and payload queue
- Publishes decoded replies via `reply_ap` analysis port

**Analysis port connections:**

```
pkt_agent.driver.sent_ap   --> scoreboard.cmd_imp
pkt_agent.driver.sent_ap   --> coverage.cmd_imp
pkt_agent.driver.sent_ap   --> ord_checker.cmd_imp
pkt_agent.driver.sent_ap   --> bus_agent.monitor.cmd_ap
pkt_agent.monitor.reply_ap --> scoreboard.rsp_imp
pkt_agent.monitor.reply_ap --> coverage.rsp_imp
bus_agent.monitor.bus_ap   --> ord_checker.bus_imp
```

### 4.2 Bus Agent (`bus_agent`) -- Passive

The bus agent is monitor-only. The BFM (reactive slave) is instantiated at module level in `tb_top`, not inside the UVM agent.

**Bus Monitor** (`bus_slave_monitor_uvm`):
- Samples accepted bus transactions at the AVMM or AXI4 interface
- Correlates each bus transaction to the originating `sc_pkt_seq_item` via a pending-command queue (FIFO-ordered, with OoO match support)
- Produces `sc_hub_bus_txn` items annotating: `is_read`, `is_write`, `address`, `burst_length`, `has_cmd_meta`, ordering metadata, atomic metadata, `is_ooo`
- For AVMM nonincrementing commands with `rw_length > 1`, the monitor correctly expands to N single-beat pending entries (matching `sc_hub_avmm_handler` RTL behavior)
- For atomic commands, an additional synthetic write-phase pending entry is enqueued (matching the read-modify-write bus pattern)

### 4.3 Scoreboard (`sc_hub_scoreboard_uvm`)

**Reference model:** flat memory array `mem_model[0:262143]` (18-bit word address space). Initialized with base+offset pattern (`0x1000_0000 + idx` for AVMM, `0x2000_0000 + idx` for AXI4). Internal CSR addresses (`0xFE80..0xFE9F`) initialized to zero except UID (word 0) and version (word 1).

**Checking flow:**
1. `write_cmd(sc_pkt_seq_item)`: if `reply_expected()` is true (no mask bits set, `expect_reply` is set), clone and push to `expected_q`
2. `write_rsp(sc_reply_item)`: match against `expected_q`:
   - **Exact match**: search entire queue for reply whose predicted fields (type, fpga_id, address, order metadata, atomic, echoed_length, response, payload) all match. Pop matched entry.
   - **Same-address fallback**: if exact match fails, find first entry with same `start_address`. Log error but continue.
   - **FIFO fallback (AVMM only)**: if no address match, pop front (in-order assumption).
   - **OoO mode**: no FIFO fallback; unmatched reply is a hard error.
3. `compare_reply()`: field-by-field comparison with per-field error reporting
4. `apply_completed_cmd()`: update `mem_model` for completed writes and atomics

**Atomic reference model:** for RMW atomics, `mem[addr] = (old & ~mask) | (data & mask)`.

**Nonincrementing reference model:** all beats address the same `start_address[17:0]`, both for read prediction and write application.

**Error prediction:** forced bus errors (`SLVERR`, `DECERR`) are predicted based on `forced_response` field in `sc_pkt_seq_item`. Error replies may carry a diagnostic payload word (`0xBBAD_BEEF` for SLVERR, `0xDEAD_BEEF` for DECERR).

### 4.4 Ordering Checker (`sc_hub_ord_checker_uvm`)

Separate from the scoreboard because ordering violations can exist even when payload content is correct.

**Command-side checks:**
- Ordering domain in range `[0, 15]`
- Order mode is `RELEASE` or `ACQUIRE` when `ordered` flag is set
- Epoch monotonicity per domain (when `check_order_epoch_monotonic` is enabled)
- Atomic flag consistency with `atomic_mode`

**Bus-side checks:**
- Zero-length burst detection
- Bus-observed ordering epoch monotonicity per domain
- OoO detection: `force_ooo` vs actual out-of-order delivery
- Atomic mode consistency at bus level

**Counters reported at `report_phase`:** `ordered_seen`, `relaxed_seen`, `atomic_seen`, `release_seen`, `acquire_seen`, `bus_seen`, `ooo_seen`, `order_violation`, `atomic_violation`, `bus_violation`.

### 4.5 Coverage Collector (`sc_hub_cov_collector`)

Two covergroups, both `per_instance`:

**`cmd_cg`** (sampled on every command):

| Coverpoint | Bins |
|---|---|
| `cp_type` | `SC_READ`, `SC_WRITE`, `SC_READ_NONINCREMENTING`, `SC_WRITE_NONINCREMENTING` |
| `cp_internal` | external, internal (CSR) |
| `cp_ordered` | no, yes |
| `cp_atomic` | no, yes |
| `cp_masked` | no, yes (any of mask_m/s/t/r) |
| `cp_malformed` | no, yes |
| `cp_length` | 1, 2-4, 5-16, 17-64, 65-256 |
| **`cmd_cross`** | `cp_type x cp_internal x cp_atomic x cp_ordered` |

**`rsp_cg`** (sampled on every reply):

| Coverpoint | Bins |
|---|---|
| `cp_header_valid` | bad, good |
| `cp_response` | ok (00), badarg (01), busy (10), failed (11) |
| `cp_payload_words` | zero, one, short (2-4), burst (5-32), long_burst (33-256) |
| `cp_atomic` | no, yes |
| `cp_ordered` | no, yes |
| `cp_write_reply` | no, yes |
| **`rsp_cross`** | `cp_response x cp_payload_words x cp_atomic x cp_write_reply` |

---

## 5. Transaction Model

### 5.1 Command Transaction (`sc_pkt_seq_item`)

| Field | Type | Drives |
|---|---|---|
| `sc_type` | `sc_type_e` (2-bit) | Read/write, incrementing/nonincrementing |
| `start_address` | `logic [23:0]` | Effective 18-bit word address |
| `rw_length` | `int unsigned` | Burst word count (1..256) |
| `mask_m`, `mask_s`, `mask_t`, `mask_r` | `bit` | Detector-type execution masks, reply suppression |
| `expect_reply` | `bit` | Whether scoreboard should expect a reply |
| `malformed` | `bit` | Inject malformed packet (error testing) |
| `forced_response` | `logic [1:0]` | Force BFM to return SLVERR/DECERR |
| `order_mode` | `sc_order_mode_e` | RELAXED / RELEASE / ACQUIRE |
| `order_domain` | `int unsigned` | Domain index (0..15) |
| `order_epoch` | `int unsigned` | Monotonic epoch counter |
| `ordered` | `bit` | Enable ordering semantics |
| `atomic` | `bit` | Enable atomic RMW |
| `atomic_mode` | `sc_atomic_mode_e` | DISABLED / RMW / LOCK / MIXED |
| `atomic_mask` | `logic [31:0]` | RMW bit mask |
| `atomic_data` | `logic [31:0]` | RMW data value |
| `force_ooo` | `bit` | Force AXI4 out-of-order completion |
| `data_words_q` | `logic [31:0] [$]` | Write payload |

**Helper methods:**
- `to_cmd()` -> `sc_cmd_t` struct for reference model
- `is_write()` -> `sc_type[0]`
- `reply_expected()` -> `expect_reply && !(mask_m || mask_s || mask_t || mask_r)`
- `has_ordering_meta()`, `has_atomic_meta()` -> feature detection

### 5.2 Reply Transaction (`sc_reply_item`)

| Field | Type | Source |
|---|---|---|
| `sc_type` | `sc_type_e` | Echoed from command |
| `fpga_id` | `logic [15:0]` | Echoed FPGA ID |
| `start_address` | `logic [23:0]` | Echoed start address |
| `order_mode/domain/epoch/scope` | `logic` | Echoed ordering metadata |
| `atomic` | `bit` | Echoed atomic flag |
| `echoed_length` | `logic [15:0]` | Echoed rw_length |
| `response` | `logic [1:0]` | 00=OK, 10=SLVERR, 11=DECERR |
| `header_valid` | `bit` | Reply header decode success |
| `payload_q` | `logic [31:0] [$]` | Read data or error diagnostic |

### 5.3 Bus Transaction (`sc_hub_bus_txn`)

| Field | Type | Source |
|---|---|---|
| `is_read`, `is_write` | `bit` | Observed bus direction |
| `address` | `logic [17:0]` | Observed bus address |
| `burst_length` | `int unsigned` | AVMM burstcount or AXI4 `awlen+1`/`arlen+1` |
| `has_cmd_meta` | `bit` | Pending-queue correlation succeeded |
| `ordered`, `order_mode/domain/epoch` | | From correlated command |
| `atomic_mode`, `atomic_id` | | From correlated command |
| `is_ooo` | `bit` | Matched out-of-order in pending queue |

### 5.4 Transaction Lifecycle

Tests do not reset the DUT between transactions. The hub runs continuously.

```
sequence drives sc_pkt_seq_item
  --> sc_pkt_driver_uvm encodes SC packet on sc_pkt_if
  --> DUT decodes, dispatches to bus handler
  --> bus_slave_monitor_uvm captures AVMM/AXI4 activity
  --> BFM responds (with optional injected latency/error)
  --> DUT forms reply packet on sc_reply_if
  --> sc_pkt_monitor_uvm decodes reply into sc_reply_item
  --> scoreboard matches reply against prediction
  --> coverage collector samples both command and reply
  --> ordering checker validates ordering/atomic invariants
```

---

## 6. Scoreboard Reference Model

### 6.1 Memory Model

Flat array `logic [31:0] mem_model[0:262143]` covering the full 18-bit word address space.

**Initialization:**
- External addresses: `base_word + idx` where `base_word = 0x1000_0000` (AVMM) or `0x2000_0000` (AXI4)
- Internal CSR range `[0xFE80, 0xFE9F]`: initialized to `0x0000_0000`

**CSR prediction (read-only for two identity words):**
- Word 0 (`HUB_CSR_WO_UID`): returns `0x5343_4842` ("SCHB")
- Word 1 (`HUB_CSR_WO_META`): returns packed version `{major[7:0], minor[7:0], patch[3:0], build[11:0]}`

### 6.2 Prediction Rules

| Command type | Prediction |
|---|---|
| Read (incrementing) | Payload = `mem[addr+0], mem[addr+1], ..., mem[addr+len-1]` |
| Read (nonincrementing) | Payload = `mem[addr], mem[addr], ..., mem[addr]` (len times) |
| Write (incrementing) | No payload; update `mem[addr+i] = data_words_q[i]` |
| Write (nonincrementing) | No payload; update `mem[addr] = data_words_q[i]` for each beat |
| Internal CSR read | Payload from `predict_csr_read_word()` |
| Atomic RMW | Read old value, reply with old value, then `mem[addr] = (old & ~mask) | (data & mask)` |
| Bus error (forced) | Response echoed; payload = `{0xBBAD_BEEF}` (SLVERR) or `{0xDEAD_BEEF}` (DECERR) |
| Masked command | No reply expected (reply_expected = false) |

### 6.3 OoO Matching Strategy

- **AVMM (in-order):** strict FIFO with same-address fallback, then front-of-queue pop
- **AXI4 with OoO:** full-queue search for exact match; no FIFO fallback; unmatched reply = hard error

---

## 7. Coverage Plan -- Mapping to DV_CROSS

### 7.1 Cross Coverage Objectives

| DV_CROSS ID | Implementation | Bus | Profile | Key coverage targets |
|---|---|---|---|---|
| CROSS-001 / T356 | `sc_pkt_mixed_seq` | Avalon-MM | 768 txns, mixed incr/nonincr | `cmd_cross{type x internal}`, `rsp_cross{response x payload_words}`, counter monotonicity |
| CROSS-002 / T357 | `sc_pkt_ooo_seq` | AXI4 OoO | 768 txns, mixed nonincr/ordering/atomic | `cmd_cross{type x atomic x ordered}`, `rsp_cross{response x atomic x write_reply}`, OoO reply ordering |

### 7.2 Coverage Gaps Identified in DV_CROSS

- Detector masking (`mask_m/s/t` vs `FEB_TYPE`) is not yet randomized in cross cases. Requires the UVM environment to correlate locally masked packets with expected no-execute / no-reply behavior.
- `cp_malformed` is only exercised in DV_ERROR cases, not in cross cases.

### 7.3 Coverage Targets

| Metric | Target | Measured by |
|---|---|---|
| `cmd_cg` coverage | > 95% | `cmd_cross` cross bins |
| `rsp_cg` coverage | > 95% | `rsp_cross` cross bins |
| Statement coverage | > 95% | Questa `vcover report` |
| Branch coverage | > 90% | Questa `vcover report`, all 18 FSM states covered |
| Toggle coverage | > 80% | All DUT port signals toggled |

---

## 8. SVA Categories and Bind Strategy

### 8.1 Assertion Module

Single unified module `sc_hub_assertions` in `tb/sim/sc_hub_assertions.sv`. Compile-time `ifdef SC_HUB_BUS_AXI4` selects between AVMM and AXI4 protocol assertions.

### 8.2 Bind Wrapper

`sc_hub_uvm_assertions_bind` in `tb/uvm/sva/sc_hub_uvm_assertions_bind.sv` is a thin port-mapping wrapper. The `bind` statement in `tb/uvm/tb_top.sv` attaches it to `sc_hub_uvm_tb_top`:

```systemverilog
bind sc_hub_uvm_tb_top sc_hub_uvm_assertions_bind assertions_bind_inst (
  .clk(clk), .rst(rst),
  .link_ready(sc_pkt_vif.ready),
  .link_data(sc_pkt_vif.data),
  // ... full port map per bus variant
);
```

All assertions fire `$error` (not `$fatal`) so the scoreboard can also report the mismatch.

### 8.3 Assertion Categories

#### Packet Framing (A01-A05, always active)

| ID | Property | What it catches |
|---|---|---|
| A01 | `command_data_known_outside_reset` | X/Z on download link during active operation |
| A02 | `no_valid_while_in_reset` | Uplink valid leaking during reset |
| A03 | `ready_known_after_reset` | X on download_ready after reset deasserts |
| A04 | `reply_starts_with_k285` | Reply missing K28.5 SOP marker |
| A05 | `reply_ends_with_k284` | Reply missing K28.4 EOP marker |

#### Reply Protocol (A09-A13)

| ID | Property | What it catches |
|---|---|---|
| A09 | `k_char_is_control` | Control char outside SOP/EOP beat |
| A10 | `nonk_char_is_payload` | Non-zero datak on payload beat |
| A11 | `reply_resp_header_fields_known` | Invalid response code (reserved `01`), missing response-present bit |
| A12 | `no_eop_without_open_reply` | EOP without preceding SOP |
| A13 | `reply_sop_eop_paired` | Nested SOP (prior reply never closed) |

#### FIFO Invariants (A14-A17)

| ID | Property | What it catches |
|---|---|---|
| A14 | `dl_fifo_usedw_in_range` | Download FIFO usedw exceeds configured `EXT_PLD_DEPTH` |
| A15 | `dl_fifo_full_consistent` | Full flag asserted before usedw reaches depth |
| A16 | `bp_fifo_usedw_in_range` | Backpressure FIFO usedw exceeds configured `BP_FIFO_DEPTH` |
| A17 | `dl_fifo_no_read_when_empty` | Read request while write-data FIFO is empty |

#### Backpressure Chain (A19-A21)

| ID | Property | What it catches |
|---|---|---|
| A19 | `payload_space_stall_reaches_rx_ready` | Internal stall not propagated to external ready |
| A20 | `rx_backpressure_reaches_link_ready` | Internal RX backpressure not reflected on link |
| A21 | `reply_start_gated_by_ready` | Core starts reply while pkt_tx is not ready |

#### AVMM Protocol (active when `!SC_HUB_BUS_AXI4`)

| ID | Property | What it catches |
|---|---|---|
| AM01 | `avmm_read_write_mutex` | Simultaneous read + write |
| AM02 | `avmm_read_stable_until_accepted` | Address/burstcount change during waitrequest stall |
| AM03 | `avmm_write_stable_until_accepted` | Address/writedata/burstcount change during stall |
| AM04 | `avmm_burstcount_nonzero` | Zero burstcount on active command |
| AM05 | `avmm_burstcount_max` | Burstcount exceeds 257 (MAX_BURST_BYTES) |

#### AXI4 Protocol (active when `SC_HUB_BUS_AXI4`)

| ID | Property | What it catches |
|---|---|---|
| AX01 | `axi4_arvalid_stable` | AR channel change while ARREADY low |
| AX02 | `axi4_awvalid_stable` | AW channel change while AWREADY low |
| AX03 | `axi4_wvalid_stable` | W channel change while WREADY low |
| AX04 | `axi4_burst_type_supported` | Burst type not FIXED (00) or INCR (01) |
| AX05 | `axi4_size_4byte` | Beat size not 4-byte (010) |
| AX06 | `axi4_bvalid_after_wlast` | BVALID before final WLAST beat |
| AX07 | `axi4_no_interleave` | AW issued while prior txn is in-flight |
| AX08 | `axi4_no_reuse_arid` | ARID reused while prior same-ID txn in-flight |
| AX09 | `axi4_no_parallel_aw_ar` | AW and AR issued in same cycle |

#### Runtime Protocol Counters (always-ff block)

The assertions module maintains runtime counters for reply framing anomalies:
- `reply_protocol_violations` -- total framing errors
- `reply_word_index_overflow` -- reply exceeded MAX_REPLY_BEATS
- `reply_missing_eop_count` -- SOP without prior EOP
- `reply_control_outside_packet` -- control beat outside open packet
- `axi_protocol_violations` (AXI4 only) -- protocol-level anomalies

#### Not Covered at Harness Boundary

| Range | Reason |
|---|---|
| A06-A08 (lock/flush/atomic metadata) | Requires core-internal signal visibility |
| A18 (atomic lock ownership) | Not observable from top-level ports |
| A23-A33 (ordering/liveness, free-list) | Require core-internal FSM/pointer visibility |

---

## 9. Compile and Run Targets

### 9.1 Compile

```bash
cd slow-control_hub/tb

# AVMM UVM compile
make compile_uvm WORK=work_sc_hub_tb BUS_TYPE=AVALON COV=1

# AXI4 UVM compile
make compile_uvm WORK=work_sc_hub_tb BUS_TYPE=AXI4 COV=1
```

Compile chain: `vcom` (VHDL RTL) -> `vlog` (SV sim pkg, BFMs, assertions, UVM env). The `-mfcu` flag compiles UVM files as a single compilation unit (`sc_hub_uvm_dvworkflow_cu`).

### 9.2 Run

```bash
# Smoke test (base test, ~50k cycle timeout)
make run_uvm_smoke WORK=work_sc_hub_tb BUS_TYPE=AVALON UVM_TESTNAME=sc_hub_base_test

# Single case (e.g., T341)
./scripts/run_uvm_case.sh T341

# Cross cases
./scripts/run_uvm_case.sh T356 T357

# Suite runners
make run_basic    # B001-B155 subset
make run_perf     # P001-P058 subset
make run_edge     # E001-E052 subset
make run_error    # X001-X051 subset
make run_all      # Full regression
```

### 9.3 Coverage Collection and Merge

```bash
# Run with coverage
make run_uvm_smoke COV=1 ...

# Merge across tests
$(QUESTA_HOME)/bin/vcover merge merged.ucdb test1.ucdb test2.ucdb ...

# HTML report
$(QUESTA_HOME)/bin/vcover report -html -output cov_html merged.ucdb

# Holes below 100%
$(QUESTA_HOME)/bin/vcover report -details -below 100 merged.ucdb
```

### 9.4 VCD Generation

```bash
make run_uvm_smoke SIM_DO="vcd file \$(TEST).vcd; vcd add -r /*; run -all; vcd flush; quit -f" ...
```

### 9.5 License

The Makefile chains `8161@lic-mentor.ethz.ch` (ETH Mentor floating) as primary, with local Questa FSE as fallback. Full Mentor license is required for `rand`/`constraint`, `covergroup`, and DPI.

---

## 10. Directory Layout (As-Built)

```
tb/
  Makefile                        # Top-level compile/run targets
  DV_PLAN.md                      # Entry point
  DV_HARNESS.md                   # This document
  DV_BASIC.md / DV_EDGE.md / DV_PROF.md / DV_ERROR.md / DV_CROSS.md
  implementation-status.md
  scripts/
    run_uvm_case.sh               # Per-case runner
    run_basic.sh / run_perf.sh / run_edge.sh / run_error.sh / run_all.sh
    coverage_report.sh / merge_cov_suite.py / run_uvm_cov_trend.py
  sim/
    sc_hub_pkg.sv                 # Shared enums, structs, helpers
    sc_hub_addr_map.sv            # Address-map constants
    sc_hub_ref_model.sv           # Standalone reference model package
    sc_pkt_driver.sv              # Directed-mode packet driver
    sc_pkt_monitor.sv             # Directed-mode reply monitor
    avmm_slave_bfm.sv            # Reactive AVMM slave BFM
    axi4_slave_bfm.sv            # Reactive AXI4 slave BFM
    sc_hub_scoreboard.sv          # Directed-mode scoreboard
    sc_hub_assertions.sv          # Unified SVA module
    sc_hub_ord_checker.sv         # Directed-mode ordering checker
    sc_hub_freelist_monitor.sv    # Free-list boundary monitor
    sc_hub_tb_top.sv              # Directed testbench top
  uvm/
    Makefile                      # Delegates to parent Makefile
    tb_top.sv                     # Module wrapper + bind statements
    sc_hub_uvm_tb_top.sv         # DUT instantiation, clock/reset, interfaces
    sc_hub_uvm_pkg.sv            # Package: interfaces, enums, all UVM includes
    sc_hub_uvm_env.sv            # UVM env: agents, scoreboard, coverage
    sc_hub_uvm_env_cfg.sv        # Configuration object
    sc_pkt_seq_item.sv           # Command transaction class
    sc_pkt_driver_uvm.sv         # UVM packet driver
    sc_pkt_monitor_uvm.sv        # UVM reply monitor
    sc_pkt_agent.sv              # UVM packet agent (sequencer + driver + monitor)
    bus_agent.sv                 # Bus agent + bus_slave_monitor_uvm + sc_hub_bus_txn
    sc_hub_scoreboard_uvm.sv     # Reference-model scoreboard
    sc_hub_cov_collector.sv      # Functional covergroups (cmd_cg, rsp_cg)
    sc_hub_ord_checker_uvm.sv    # Ordering/atomic checker
    sc_hub_base_test.sv          # Base test class
    sc_hub_case_test.sv          # Per-case test class
    sc_hub_sweep_test.sv         # Parametric sweep test
    tests/
      sc_hub_base_test.sv        # (duplicated entry point)
      sc_hub_case_test.sv
      sc_hub_sweep_test.sv
    sequences/
      sc_pkt_single_seq.sv       # Single read/write
      sc_pkt_script_seq.sv       # Scripted multi-step
      sc_pkt_burst_seq.sv        # Burst sweep
      sc_pkt_error_seq.sv        # Malformed/error injection
      sc_pkt_mixed_seq.sv        # Mixed traffic (CROSS-001)
      sc_pkt_bp_seq.sv           # Backpressure stress
      sc_pkt_csr_seq.sv          # Internal CSR access
      sc_pkt_addr_sweep_seq.sv   # Address range sweep
      sc_pkt_concurrent_seq.sv   # Concurrent multi-stream
      sc_pkt_atomic_seq.sv       # Atomic RMW
      sc_pkt_ordering_seq.sv     # Release/acquire ordering
      sc_pkt_ooo_seq.sv          # Out-of-order (CROSS-002)
      sc_pkt_perf_sweep_seq.sv   # Performance burst sweep
    sva/
      sc_hub_uvm_assertions_bind.sv  # Bind wrapper for sc_hub_assertions
```

---

## 11. Phased Implementation Notes

### Phase 0 -- Plan (complete)

All plan files (`DV_PLAN.md`, `DV_BASIC.md`, `DV_EDGE.md`, `DV_PROF.md`, `DV_ERROR.md`, `DV_CROSS.md`) are checked in. 318 total cases allocated. Legacy `Txxx` implementation aliases mapped to canonical `B/E/P/X/CROSS` IDs.

### Phase 1 -- Harness (complete, structural gaps remain)

The UVM environment compiles and runs. All five components (packet agent, bus agent, scoreboard, coverage, ordering checker) are connected and functional. Assertions are bound via `tb_top.sv`.

**Remaining structural gaps:**
- Agent files are flat in `uvm/` rather than in `sc_hub_sc_agent/` and `sc_hub_bus_agent/` subdirectories
- `tests/` directory contains duplicate copies of test classes (also included at `uvm/` root)
- `tb/uvm/Makefile` delegates to parent; no standalone compile capability yet

### Phase 2+3 -- Case Implementation (in progress)

Directed cases through `T130` and UVM cases `T123-T128`, `T300-T368` are checked in and runnable. Cases are implemented via codex delegation, reviewed by Claude.

**Coverage status:** `cmd_cg` and `rsp_cg` covergroups are sampling. `cmd_cross` (type x internal x atomic x ordered) and `rsp_cross` (response x payload_words x atomic x write_reply) are the primary functional closure bins.

### Phase 4 -- Waveforms (not started)

VCD generation targets are defined in the Makefile. WaveDrom viewer integration and per-case waveform index page are planned but not yet built.

### Phase 5 -- System Integration (future)

After DV closure, RTL fixes propagate to `feb_system_v2/synthesis/submodules/` (per Qsys IP source file rule). SC test sequences promote to system-level `SC-001..SC-128` scenarios with address adjustments.
