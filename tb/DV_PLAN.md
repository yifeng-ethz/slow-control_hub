# SC_HUB v2 — Design Verification Plan

**IP Name:** sc_hub_v2 (Slow Control Hub)
**Author:** Yifeng Wang
**Companion:** ../doc/RTL_PLAN.md, ../doc/TLM_PLAN.md, ../doc/TLM_NOTE.md
**System DV Plan:** `/home/yifeng/packages/online_dpv2/online/fe_board/fe_scifi/tb/scifi_dp/doc/DV_PLAN.md`
**Simulator Goal:** QuestaOne 2026 with the ETH floating license chain
(`8161@lic-mentor.ethz.ch`)  
**Current Tool Reality:** the supported standalone flow now comes from the
shared `scripts/questa_one.mk` / `scripts/questa_one_env.sh` wrappers and
resolves to `/data1/questaone_sim/questasim` on this host. Older FSE-only
notes below are historical context, not the active runtime contract.  
**UVM:** UVM 1.2

---

## 1. Plan Structure

This plan is the **main entrance point** for all sc_hub_v2 DV. Test cases are organized into four sub-documents by category. Each sub-document is self-contained with its own scenario tables, but shares the testbench architecture, coverage model, and assertion library defined here.

Current implementation snapshot:
- The tables below allocate the full planned ID space.
- The checked-in standalone harness now executes directed protocol coverage through `T130`, the promoted UVM case matrix `T123`–`T128` plus `T300`–`T368`, and static configuration guard checks beyond the canonical alias overlay.
- See `implementation-status.md` for the current runnable truth, residual blind spots, and bring-up guidance.

| Document | Scope | Canonical Plan IDs | Current Implementation Alias Space | Count |
|----------|-------|--------------------|------------------------------------|-------|
| [DV_BASIC.md](DV_BASIC.md) | Functional bring-up, protocol correctness, basic feature validation | B001–B152 | table-order overlay across T001-T060, T077-T112, T123-T128, T200-T249 | 152 |
| [DV_PROF.md](DV_PROF.md) | Performance scans, stress tests, publication-quality characterization | P001–P128 | T300–T355 (implemented subset) | 128 |
| [DV_EDGE.md](DV_EDGE.md) | Near-boundary, non-power-of-2, intentional near-failure without failure | E001–E128 | T400–T449 (implemented subset) | 128 |
| [DV_ERROR.md](DV_ERROR.md) | Soft errors, hard recoverable failures, configuration-fatal failures | X001–X128 | T500–T549 (implemented subset) | 128 |
| [DV_CROSS.md](DV_CROSS.md) | Long mixed-feature cross cases for promoted regressions | CROSS-001–CROSS-002 | T356–T357 | 2 |
| Closure extensions | Additional promoted closure/debug cases beyond the canonical alias overlay | planned-only today | T358–T368 | 11 |
| **Total** | | | | **538** |

Workflow note:

- the canonical plan space is now `B/E/P/X`
- the checked-in runnable harness still uses legacy `Txxx` implementation names for the implemented subset
- canonical IDs that have no `Txxx` alias yet are **planned-only** and intentionally fail in the runners with a `planned but not implemented` message
- migration therefore proceeds through explicit aliasing instead of pretending the legacy implementation labels are the plan IDs

**ID allocation:**
- T001–T128: Legacy v1 cases (migrated into DV_BASIC.md and DV_ERROR.md)
- T200–T249: New v2 basic functional cases (split-buffer, OoO, atomic, ordering)
- T300–T349: Performance and stress (derived from TLM experiments)
- T400–T449: Edge cases (derived from TLM edge case catalog, section 12.6)
- T500–T549: Error handling (soft / hard / fatal)

### 1.1 TLM-to-DV Derivation

Every new v2 test case traces back to a TLM experiment or TLM finding. The mapping is:

| TLM Source | DV Category | Rationale |
|------------|-------------|-----------|
| FRAG-01..08 (fragmentation analysis) | PERF | Stress malloc/free at RTL, verify no admission failure under bimodal burst |
| RATE-01..12 (rate-latency curves) | PERF | Measure RTL throughput vs. offered rate, compare against TLM predictions |
| OOO-01..06 (OoO speedup) | PERF | Verify OoO AXI4 burst reordering, measure RTL speedup |
| OOO-C01..C07 (OoO correctness) | BASIC | Reply integrity, no duplication/loss, payload isolation under OoO |
| OOO-F01..F03 (OoO fragmentation) | PERF | Free-list consistency after OoO free patterns |
| ATOM-01..04 (atomic impact) | PERF | Lock hold time, throughput degradation vs. atomic ratio |
| ATOM-C01..C05 (atomic correctness) | BASIC | RMW atomicity, lock exclusion, internal bypass, error handling |
| ATOM-05..06 (atomic complex) | EDGE | Concurrent atomic + non-atomic to same address, internal priority during lock |
| CRED-01..04 (credit analysis) | PERF | Credit stall under deep/shallow payload, backpressure verification |
| PRIO-01..04 (internal priority) | PERF | Internal CSR latency bounded under external saturation |
| ORD-01..08 (ordering performance) | PERF | Release drain cost, acquire hold cost, multi-domain independence |
| ORD-C01..C06 (ordering correctness) | BASIC | Four correctness rules (R1–R4), cross-domain independence |
| SIZE-01..06 (buffer sizing) | PERF | Outstanding depth sweep, payload depth sweep at RTL |
| TLM_PLAN 12.6 edge cases 1–17 | EDGE | Malloc failure, admission revert, OoO toggle, pointer wrap, etc. |
| TLM_PLAN 8.3 DV recommendations | ERROR | Bus error propagation, free-list leak detection, timeout recovery |
| TLM_NOTE ISSUE 1–7 | EDGE/ERROR | Release drain accepted-writes gap, admission revert-on-failure |

---

## 2. Verification Scope and System Context

This plan verifies the sc_hub_v2 IP as a standalone unit, but every test is written from the perspective of its integration in the `feb_system` control path:

```
feb_system (Qsys)
  +-- control_path_subsystem (debug_sc_system_v2)
  |   +-- sc_hub_v2 ----------------+
  |   +-- jtag_avalon_master        | -- hub_avmm --> AVMM system interconnect
  |   +-- register_file             |
  +-- data_path_subsystem           |
      +-- frame_rcv_ip[0..7]  <-----+ (CSR targets at various addresses)
      +-- mts_processor[0..1]
      +-- ring_buffer_cam[0..7]
      +-- feb_frame_assembly[0..1]
      +-- histogram[0..1]
```

**Standalone boundary:** The testbench wraps `sc_hub_top` only. The AVMM/AXI4 slave BFM replaces the system interconnect and all downstream IPs. The SC packet driver replaces the 5G link decoder (`swb_sc_main`). The SC reply monitor replaces the 5G link encoder (`swb_sc_secondary`).

**System alignment:** Test IDs, address maps, packet formats, and coverage bins are chosen so that this plan's results directly feed into the system plan's SC-001..SC-128 scenarios. When the hub is integrated, the same stimulus sequences (with address adjustments) promote to system-level regression.

### 2.1 Test Method Key

- **Directed (D):** Self-contained SystemVerilog testbench. Hand-crafted stimulus, inline assertion + scoreboard checking. One scenario per test file.
- **UVM (U):** Promoted to UVM sequence for parametric sweeps. A single `sc_hub_sweep_test` iterates over a parameter range. With ETH Questa license, `rand`/`constraint` can drive stimulus randomization. Used when exhaustive coverage across a dimension is needed.

### 2.2 Relationship to System Plan

```
DV_PLAN.md (this plan) -- 305 standalone sc_hub_v2 tests
  |
  |  Promotes to:
  |
  +-- feb_system DV_PLAN.md
        +-- SC-001..SC-128    (SC packet path through real interconnect)
        +-- SCDATA-001..100   (SC concurrent with data -- not covered here)
        +-- SCRC-001..064     (SC concurrent with run control -- not covered here)
        +-- SYS-001..064      (full system integration)
```

Tests in this plan that have a direct system counterpart are annotated with `-> SC-xxx` in the scenario tables.

---

## 3. Testbench Architecture

### 3.1 Directed Testbench

```
sc_hub_tb_top.sv
+-- clk_rst_gen                    Clock (156.25 MHz) + reset generation
+-- sc_pkt_driver                  Drives SC command packets on i_linkin_*
|   +-- task send_read(addr, len)
|   +-- task send_write(addr, len, data[])
|   +-- task send_burst_read(addr, len)
|   +-- task send_burst_write(addr, len, data[])
|   +-- task send_atomic_rmw(addr, mask, modify, order, dom_id)
|   +-- task send_ordered_read(addr, len, order, dom_id, epoch)
|   +-- task send_ordered_write(addr, len, data[], order, dom_id, epoch)
|   +-- task send_malformed(error_type, ...)
|   +-- task send_raw(words[], datak[])
+-- sc_pkt_monitor                 Captures + decodes SC reply packets from aso_to_uplink_*
|   +-- task wait_reply(timeout) -> sc_reply_t
|   +-- task assert_no_reply(timeout)
|   +-- task assert_reply_matches(expected)
|   +-- task assert_reply_order(expected_seq[])
+-- avmm_slave_bfm                 Memory-backed AVMM slave (system interconnect model)
|   +-- parameter MEM_DEPTH = 65536
|   +-- parameter RD_LATENCY = 1..N (configurable per-test)
|   +-- parameter WR_LATENCY = 1..N
|   +-- input     inject_rd_error, inject_wr_error, inject_decode_error
|   +-- input     inject_waitrequest_cycles
|   +-- function  mem_read(addr), mem_write(addr, data)
+-- axi4_slave_bfm                 Memory-backed AXI4 slave (burst-capable, OoO-capable)
|   +-- parameter MEM_DEPTH = 65536
|   +-- parameter RD_LATENCY = 1..N
|   +-- parameter WR_LATENCY = 1..N
|   +-- parameter OOO_CAPABLE = 1     (can reorder R responses by RID)
|   +-- input     inject_rresp_err, inject_bresp_err
|   +-- input     inject_arready_stall, inject_wready_stall
|   +-- INCR burst support (ARLEN/AWLEN up to 255)
+-- sc_hub_scoreboard              Reference model: expected reply from command + slave memory
+-- sc_hub_cov_collector           Coverage collector (covergroup with ETH license, counter fallback)
+-- sc_hub_assertions              SVA bind module (protocol + liveness)
+-- sc_hub_ord_checker             Ordering rule checker (R1-R4 per domain)
+-- sc_hub_freelist_monitor        Monitors free_count consistency at quiesce
```

### 3.2 UVM Testbench

```
sc_hub_uvm_tb_top.sv
+-- sc_hub_uvm_env
|   +-- sc_pkt_agent               (driver + monitor + sequencer)
|   |   +-- sc_pkt_driver_uvm      Drives SC packets from sequence items
|   |   +-- sc_pkt_monitor_uvm     Captures replies, sends to scoreboard via analysis port
|   |   +-- sc_pkt_sequencer       Routes sequence items
|   +-- bus_agent                   (AVMM or AXI4, selected by config)
|   |   +-- bus_slave_driver_uvm   Responds to bus transactions (memory model)
|   |   +-- bus_slave_monitor_uvm  Snoops bus signals for scoreboard
|   +-- sc_hub_scoreboard_uvm      Checks reply against expected
|   +-- sc_hub_cov_collector_uvm   Coverage collector (covergroup or counter-based)
|   +-- sc_hub_ord_checker_uvm     Ordering rule monitor (analysis port from bus monitor)
|   +-- sc_hub_env_cfg             Environment configuration object
+-- sc_hub_base_test               Base test: build env, apply reset
+-- sc_hub_sweep_test              Parameterised sweep test (extends base)
+-- Sequences:
    +-- sc_pkt_single_seq          Single read or write
    +-- sc_pkt_burst_seq           Burst with configurable length
    +-- sc_pkt_error_seq           Malformed packet injection
    +-- sc_pkt_mixed_seq           Interleaved read/write/CSR traffic
    +-- sc_pkt_backpressure_seq    Traffic with uplink throttling
    +-- sc_pkt_csr_seq             CSR register access sequence
    +-- sc_pkt_addr_sweep_seq      Address range sweep (external + CSR boundary)
    +-- sc_pkt_concurrent_seq      Rapid-fire mixed traffic with error injection
    +-- sc_pkt_atomic_seq          Atomic RMW sequences
    +-- sc_pkt_ordering_seq        Release/acquire ordering sequences
    +-- sc_pkt_ooo_seq             Out-of-order dispatch sequences
    +-- sc_pkt_perf_sweep_seq      Rate sweep with latency measurement
```

### 3.3 Shared Components

| File | Description |
|------|-------------|
| `sc_hub_tb_pkg.sv` | Types: `sc_cmd_t`, `sc_reply_t`, `sc_pkt_info_t`, `sc_order_t`. Constants: K28.5, K28.4, SC data type. Address map from `feb_system_v2.sopcinfo`. |
| `sc_hub_ref_model.sv` | Pure-function reference model: given command + slave memory state, compute expected reply. Extended for ordering and atomic. |
| `sc_hub_assertions.sv` | SVA bind module: protocol checks on AVMM/AXI4 master, packet framing, FSM liveness. |
| `sc_hub_addr_map.sv` | Address map constants derived from `feb_system_v2.sopcinfo`: scratch pad, control CSR, frame_rcv[0..7], mts_proc[0..1], ring_buf_cam[0..7], feb_frame_asm[0..1], histogram[0..1], unmapped holes. |
| `sc_hub_ord_checker.sv` | Ordering rule checker: monitors bus transactions per domain, asserts R1–R4 invariants continuously. |
| `sc_hub_freelist_monitor.sv` | At quiesce: asserts `free_count == RAM_DEPTH` for all 4 payload pools. |

### 3.4 Address Map (from `feb_system_v2.sopcinfo`)

| Region | Word Address Range | BFM Behavior |
|--------|--------------------|-------------|
| Scratch pad | 0x000000-0x0003FF | Normal R/W memory |
| Control CSR | 0x00FC00-0x00FC1F | Normal R/W memory |
| frame_rcv_ip[0..7] | 0x008000-0x0087FF | Normal R/W memory (8 x 256 words) |
| mts_processor[0..1] | 0x009000-0x0091FF | Normal R/W memory |
| ring_buffer_cam[0..7] | 0x00A000-0x00A7FF | Normal R/W memory |
| feb_frame_assembly[0..1] | 0x00B000-0x00B1FF | Normal R/W memory |
| histogram[0..1] | 0x00C000-0x00C1FF | Normal R/W memory |
| Internal CSR | 0x00FE80-0x00FE9F | Handled internally by hub (never reaches BFM) |
| Unmapped holes | gaps between above | DECODEERROR response |

---

## 4. Coverage Model (Counter-Based)

### 4.1 Coverage Bins

Aligned with the system plan's SC coverage (section 5.1 of feb_system DV_PLAN.md) so bins merge cleanly at system level.

| Bin | Dimension | Values | System Plan Ref |
|-----|-----------|--------|-----------------|
| CP_SC_TYPE | sc_type | {BurstRead, BurstWrite, Read, Write} | SC operation |
| CP_BURST_LEN | rw_length | {1, 2, 3, 4, 8, 16, 32, 64, 128, 255, 256} | -- |
| CP_ADDR_RANGE | address | {scratch_pad, control_csr, frame_rcv, mts_proc, ring_buf_cam, feb_frame_asm, histogram, internal_csr, unmapped} | SC target IP |
| CP_RESPONSE | response code | {OK, SLAVEERROR, DECODEERROR} | SC response |
| CP_MUTE_MASK | mask bits | {none, mask_s, mask_m, mask_t, mask_r} | -- |
| CP_BUS_TYPE | bus config | {AVMM, AXI4} | -- |
| CP_PKT_DROP | drop reason | {missing_trailer, length_overflow, data_count_mismatch, fifo_overflow, truncated, bad_dtype} | SC packet state |
| CP_BP_STATE | backpressure | {no_bp, bp_during_reply, bp_during_read_data, bp_fifo_half_full} | -- |
| CP_SLAVE_LAT | slave latency | {1, 2, 4, 8, 16, 32, 64, 100, 199} | -- |
| CP_INTER_CMD_GAP | gap cycles | {0, 1, 2..7, 8..15, 16+} | SC inter-cmd gap |
| CP_XACT_SEQ | transaction sequence | {rd_after_rd, wr_after_wr, rd_after_wr, wr_after_rd, csr_after_ext, ext_after_csr} | -- |
| CP_ORDER_TYPE | ordering semantic | {RELAXED, RELEASE, ACQUIRE} | -- |
| CP_ORD_DOM | ordering domain | {0, 1, 2..7, 8..15} | -- |
| CP_ATOMIC | atomic state | {no_atomic, atomic_rmw, atomic_during_lock, internal_during_lock} | -- |
| CP_OOO_STATE | OoO mode | {ooo_off, ooo_on_inorder_complete, ooo_on_reordered_complete} | -- |
| CP_FREELIST | free-list state | {full, >75%, 50-75%, 25-50%, <25%, empty} | -- |

### 4.2 Cross Coverage (Counter Pairs)

| Cross | Bins | Rationale |
|-------|------|-----------|
| SC_TYPE x BURST_LEN | 4 x 11 = 44 | Every operation at every burst length |
| SC_TYPE x RESPONSE | 4 x 3 = 12 | Every operation sees every response |
| SC_TYPE x BUS_TYPE | 4 x 2 = 8 | Both bus types exercised with all ops |
| BURST_LEN x BUS_TYPE | 11 x 2 = 22 | Both buses at every burst length |
| ADDR_RANGE x SC_TYPE | 9 x 4 = 36 | Every address region with every operation |
| PKT_DROP x BUS_TYPE | 6 x 2 = 12 | All drop reasons on both buses |
| INTER_CMD_GAP x SC_TYPE | 5 x 4 = 20 | Timing vs operation type |
| ORDER_TYPE x SC_TYPE | 3 x 4 = 12 | Ordering semantic with every operation |
| ORDER_TYPE x ORD_DOM | 3 x 4 = 12 | Ordering across domain bins |
| ATOMIC x OOO_STATE | 4 x 3 = 12 | Atomic + OoO interaction |
| FREELIST x BURST_LEN | 6 x 11 = 66 | Free-list pressure at every burst size |
| **Total cross bins** | | **256** |

---

## 5. SVA Protocol Assertions (Bind Module)

Checked continuously during all tests. Not counted as test cases.

### 5.1 AVMM Master Assertions (active when BUS_TYPE = "AVALON")

| ID | Assertion | Description |
|----|-----------|-------------|
| A01 | avmm_read_write_mutex | `read` and `write` never asserted simultaneously |
| A02 | avmm_read_stable_until_accepted | read + address hold stable while waitrequest=1 |
| A03 | avmm_write_stable_until_accepted | write + writedata + address hold stable while waitrequest=1 |
| A04 | avmm_burstcount_nonzero | burstcount > 0 when read or write asserted |
| A05 | avmm_burstcount_max | burstcount <= 256 |
| A06 | avmm_no_flush | flush signal never asserts |
| A07 | avmm_lock_exclusion | while avm_m0_lock=1, no new non-atomic bus transaction issues |
| A08 | avmm_lock_release | lock deasserts after atomic write response |

### 5.2 AXI4 Master Assertions (active when BUS_TYPE = "AXI4")

| ID | Assertion | Description |
|----|-----------|-------------|
| A09 | axi4_arvalid_stable | ARVALID holds until ARREADY handshake |
| A10 | axi4_awvalid_stable | AWVALID holds until AWREADY handshake |
| A11 | axi4_wvalid_stable | WVALID holds until WREADY handshake |
| A12 | axi4_wlast_on_final_beat | WLAST on exactly the (AWLEN+1)th beat |
| A13 | axi4_rlast_check | RLAST on exactly the (ARLEN+1)th beat |
| A14 | axi4_bvalid_after_wlast | B channel response only after WLAST |
| A15 | axi4_no_interleave | no new AW/AR while transaction in flight (unless OoO=on) |
| A16 | axi4_burst_type_incr | AWBURST/ARBURST always = 01 |
| A17 | axi4_size_4byte | AWSIZE/ARSIZE always = 010 |
| A18 | axi4_lock_exclusive | AxLOCK=01 only during atomic RMW |

### 5.3 Packet Protocol Assertions

| ID | Assertion | Description |
|----|-----------|-------------|
| A19 | reply_starts_with_k285 | reply word 0: datak[0]=1, data[7:0]=K28.5 |
| A20 | reply_ends_with_k284 | reply last word (EOP): datak[0]=1, data[7:0]=K28.4 |
| A21 | reply_sop_eop_paired | every SOP followed by exactly one EOP before next SOP |
| A22 | reply_resp_header_valid | reply word 2 bit[16]=1 always |
| A23 | no_pkt_valid_when_busy | pkt_valid from pkt_rx only when core FSM in IDLE |

### 5.4 FSM Liveness Assertions

| ID | Assertion | Description |
|----|-----------|-------------|
| A24 | fsm_no_deadlock | core FSM exits any non-IDLE state within (RD_TIMEOUT_CYCLES + MAX_BURST + 100) cycles |
| A25 | pkt_rx_no_deadlock | pkt_rx completes reception within (MAX_BURST + 100 + rx_timeout) cycles |
| A26 | release_drain_bounded | release drain completes within (OUTSTANDING_MAX * MAX_BUS_LAT + 100) cycles |
| A27 | acquire_hold_bounded | acquire hold completes within (MAX_BUS_LAT + 100) cycles |
| A28 | atomic_lock_bounded | atomic lock released within (2 * MAX_BUS_LAT + 10) cycles |

### 5.5 Ordering Invariant Assertions

| ID | Assertion | Description |
|----|-----------|-------------|
| A29 | ord_domain_isolation | younger_blocked[D] only affects transactions with ord_dom_id==D |
| A30 | ord_release_visibility | release retirement only after all older writes in domain reach visible-retired (level 3) |
| A31 | ord_acquire_blocks_issue | no younger same-domain transaction issues while acquire_pending[D] |
| A32 | ord_relaxed_zero_overhead | RELAXED transactions (ORDER=00) incur zero extra cycles from ordering tracker |
| A33 | ord_epoch_monotonic | within a domain, ord_epoch on bus is monotonically non-decreasing |

### 5.6 Free-List Integrity Assertions

| ID | Assertion | Description |
|----|-----------|-------------|
| A34 | freelist_no_double_free | no line freed twice without intervening allocation |
| A35 | freelist_no_use_after_free | no data written to a line that is on the free list |
| A36 | freelist_count_consistent | free_count matches actual number of is_free=1 lines (checked at quiesce) |
| A37 | freelist_quiesce_full | after all transactions complete, free_count == RAM_DEPTH for all 4 pools |

---

## 6. DV File Plan

```
slow-control_hub/
+-- DV_PLAN.md                     THIS FILE (main entrance)
+-- DV_BASIC.md                    Basic functional test cases
+-- DV_PROF.md                     Performance and stress test cases
+-- DV_EDGE.md                     Edge cases
+-- DV_ERROR.md                    Error handling test cases (soft/hard/fatal)
|
+-- dv/
|   +-- tb/
|   |   +-- sc_hub_tb_top.sv           Directed testbench top-level
|   |   +-- sc_hub_tb_pkg.sv           Shared types, constants, address map
|   |   +-- sc_hub_addr_map.sv         Address map from feb_system_v2.sopcinfo
|   |   +-- sc_pkt_driver.sv           SC packet driver (tasks)
|   |   +-- sc_pkt_monitor.sv          SC reply monitor (tasks)
|   |   +-- avmm_slave_bfm.sv          Avalon-MM slave BFM
|   |   +-- axi4_slave_bfm.sv          AXI4 slave BFM (OoO-capable)
|   |   +-- sc_hub_scoreboard.sv       Reference model + checker
|   |   +-- sc_hub_assertions.sv       SVA bind module (A01-A37)
|   |   +-- sc_hub_ref_model.sv        Pure-function reference model
|   |   +-- sc_hub_ord_checker.sv      Ordering rule checker (R1-R4)
|   |   +-- sc_hub_freelist_monitor.sv Free-list consistency monitor
|   |
|   +-- uvm/
|   |   +-- sc_hub_uvm_tb_top.sv       UVM testbench top-level
|   |   +-- sc_hub_uvm_env.sv          UVM environment
|   |   +-- sc_hub_uvm_env_cfg.sv      Environment configuration
|   |   +-- sc_pkt_agent.sv            UVM agent
|   |   +-- sc_pkt_driver_uvm.sv       UVM driver
|   |   +-- sc_pkt_monitor_uvm.sv      UVM monitor
|   |   +-- sc_pkt_seq_item.sv         Sequence item (extended for v2)
|   |   +-- bus_agent.sv               Bus slave agent
|   |   +-- sc_hub_scoreboard_uvm.sv   UVM scoreboard
|   |   +-- sc_hub_cov_collector.sv    Coverage collector
|   |   +-- sc_hub_ord_checker_uvm.sv  Ordering rule monitor
|   |   +-- sc_hub_base_test.sv        Base UVM test
|   |   +-- sc_hub_sweep_test.sv       Parameterised sweep test
|   |   +-- sequences/
|   |       +-- sc_pkt_single_seq.sv
|   |       +-- sc_pkt_burst_seq.sv
|   |       +-- sc_pkt_error_seq.sv
|   |       +-- sc_pkt_mixed_seq.sv
|   |       +-- sc_pkt_bp_seq.sv
|   |       +-- sc_pkt_csr_seq.sv
|   |       +-- sc_pkt_addr_sweep_seq.sv
|   |       +-- sc_pkt_concurrent_seq.sv
|   |       +-- sc_pkt_atomic_seq.sv
|   |       +-- sc_pkt_ordering_seq.sv
|   |       +-- sc_pkt_ooo_seq.sv
|   |       +-- sc_pkt_perf_sweep_seq.sv
|   |
|   +-- tests/
|   |   +-- directed/
|   |   |   +-- t001_avmm_single_read.sv     ... (T001-T122)
|   |   |   +-- t200_split_buf_basic.sv       ... (T200-T249)
|   |   |   +-- t300_rate_lat_scan.sv         ... (T300-T349)
|   |   |   +-- t400_odd_burst_len.sv         ... (T400-T449)
|   |   |   +-- t500_soft_slaveerror.sv       ... (T500-T549)
|   |   +-- uvm/
|   |       +-- t123_uvm_sweep_burst_len.sv   ... (T123-T128)
|   |       +-- t350_uvm_rate_sweep.sv        ... (T350-T355)
|   |
|   +-- scripts/
|   |   +-- Makefile                    Compile + run (Questa FSE)
|   |   +-- run_directed.sh             Run all directed tests
|   |   +-- run_uvm.sh                  Run all UVM tests
|   |   +-- run_all.sh                  Full regression
|   |   +-- run_basic.sh                Basic category only
|   |   +-- run_perf.sh                 Performance category only
|   |   +-- run_edge.sh                 Edge cases only
|   |   +-- run_error.sh                Error cases only
|   |   +-- coverage_report.sh          Coverage summary report
|   |
|   +-- README.md                       DV quick-start guide
|
+-- ...                                 (RTL files as per RTL_PLAN.md)
```

---

## 7. Makefile Pattern (QuestaOne 2026)

```makefile
include ../../scripts/questa_one.mk

UVM_HOME            ?= $(QUESTA_UVM_HOME)
UVM_DPI_SO          ?= $(QUESTA_UVM_DPI_SO)
QUESTA_MODELSIM_INI ?= $(QSIM_INI)
MODELSIM_INI        := $(CURDIR)/modelsim.ini
WORK                ?= work_sc_hub_tb
BUS_TYPE            ?= AVALON
UVM_TESTNAME        ?= sc_hub_base_test

$(WORK):
	$(VLIB) $(WORK)

$(MODELSIM_INI): $(WORK)
	cp "$(QUESTA_MODELSIM_INI)" "$(MODELSIM_INI)"
	chmod u+w "$(MODELSIM_INI)"
	$(VMAP) -modelsimini $(MODELSIM_INI) $(WORK) $(WORK)

compile_uvm: compile_rtl
	$(VLOG) -modelsimini $(MODELSIM_INI) -sv -work $(WORK) \
		+incdir+$(UVM_HOME)/src \
		$(UVM_HOME)/src/uvm_pkg.sv \
		$(SIM_DIR)/sc_hub_pkg.sv \
		$(SIM_DIR)/sc_hub_addr_map.sv \
		$(SIM_DIR)/sc_hub_ref_model.sv \
		$(SIM_DIR)/avmm_slave_bfm.sv \
		$(SIM_DIR)/axi4_slave_bfm.sv \
		$(SIM_DIR)/sc_hub_assertions.sv \
		$(UVM_FILES)

run_uvm_smoke: compile_uvm
	$(VSIM) -modelsimini $(MODELSIM_INI) -c -quiet \
		-sv_lib $(basename $(UVM_DPI_SO)) \
		-work $(WORK) tb_top \
		+UVM_TESTNAME=$(UVM_TESTNAME) \
		-do "run -all; quit -f"

.PHONY: compile_rtl compile_uvm run_uvm_smoke
```

---

## 8. Simulator License and Constraints

**Primary:** shared QuestaOne 2026 environment from
`../../scripts/questa_one_env.sh`, using the ETH floating license chain
(`8161@lic-mentor.ethz.ch`).
**Harness choice:** the implemented DV environment still uses counter-based
coverage collectors and portable deterministic stimulus, even though the active
toolchain now supports native `rand`, `covergroup`, and DPI.

| Feature | Supported on active host | Current harness usage |
|---------|--------------------------|---------------------|
| `rand` / `constraint` | Yes | still optional; most promoted cases stay table-driven |
| `covergroup` | Yes | not yet adopted; closure reports still use counter collectors |
| DPI | Yes | enabled through the shared QuestaOne wrapper |
| UVM version | UVM 1.2 bundled | UVM 1.2 |

Counter-based collection and LCG-style deterministic replay remain acceptable in
this plan, but they are now design choices for portability and stable debug
rather than hard simulator restrictions.

---

## 9. Test Case Summary (All Categories)

| Category | Document | ID Range | Directed | UVM | Count |
|----------|----------|----------|----------|-----|-------|
| SC Basic Transactions (SC_B) | DV_BASIC | T001-T024 | 24 | 0 | 24 |
| Store-and-Forward (SF) | DV_BASIC | T025-T042 | 18 | 0 | 18 |
| Internal CSR (CSR) | DV_BASIC | T043-T060 | 18 | 0 | 18 |
| Backpressure (BP) | DV_BASIC | T077-T088 | 12 | 0 | 12 |
| Mute Mask (MUTE) | DV_BASIC | T089-T094 | 6 | 0 | 6 |
| Packet Format (PKT) | DV_BASIC | T095-T104 | 10 | 0 | 10 |
| UVM Sweep (SWP) | DV_BASIC | T123-T128 | 0 | 6 | 6 |
| v2 Split-Buffer (BUF) | DV_BASIC | T200-T209 | 10 | 0 | 10 |
| v2 OoO Functional (OOO) | DV_BASIC | T210-T219 | 10 | 0 | 10 |
| v2 Atomic Functional (ATM) | DV_BASIC | T220-T229 | 10 | 0 | 10 |
| v2 Ordering Functional (ORD) | DV_BASIC | T230-T249 | 20 | 0 | 20 |
| Reset (RST) | DV_BASIC | T105-T112 | 8 | 0 | 8 |
| Performance Scan (RATE) | DV_PROF | T300-T312 | 0 | 13 | 13 |
| OoO Speedup (OOOS) | DV_PROF | T313-T319 | 0 | 7 | 7 |
| Fragmentation Stress (FRAGS) | DV_PROF | T320-T327 | 0 | 8 | 8 |
| Credit & Priority (CREDP) | DV_PROF | T328-T335 | 0 | 8 | 8 |
| Ordering Overhead (ORDS) | DV_PROF | T336-T343 | 0 | 8 | 8 |
| Buffer Sizing (SIZS) | DV_PROF | T344-T349 | 0 | 6 | 6 |
| Non-Power-of-2 & Boundary (NPO2) | DV_EDGE | T400-T414 | 15 | 0 | 15 |
| Near-Failure (NF) | DV_EDGE | T415-T429 | 15 | 0 | 15 |
| Config Boundary (CFG) | DV_EDGE | T430-T449 | 20 | 0 | 20 |
| Soft Error (SERR) | DV_ERROR | T500-T516 | 17 | 0 | 17 |
| Hard Error (HERR) | DV_ERROR | T517-T531 | 15 | 0 | 15 |
| Fatal / Config-Induced (FERR) | DV_ERROR | T532-T549 | 18 | 0 | 18 |
| **Total (per-config)** | | | **249** | **56** | **305** |

---

## 10. Compile-Time Configuration Testing (Preset Matrix as DV Dimension)

Signoff requires two orthogonal dimensions:

1. **Runtime dimension:** All 305 test cases (T001–T549), run under a fixed compile-time configuration.
2. **Compile-time dimension:** All legal presets from `sc_hub_v2_presets.tcl`, each compiled as a separate RTL variant, then run through an applicable subset of the 305 test cases.

Neither dimension alone is sufficient. A test that passes under `FEB_SCIFI_DEFAULT` may fail under `MINIMAL_CSR_ONLY` because the latter removes OoO, ordering, and atomic logic. A test that passes under `MAX_FEATURES` may expose a timing issue that only appears at `AREA_OPTIMIZED` buffer depths.

### 10.1 Preset Compile Matrix

Each row is a distinct RTL compilation. The `_hw.tcl` preset sets all generics at synthesis/simulation time. The Makefile variable `PRESET=<name>` selects which configuration to build.

| Preset | Bus | OD | PLD | OoO | ORD | ATM | S&F | CAP | Category |
|--------|-----|----|-----|-----|-----|-----|-----|-----|----------|
| FEB_SCIFI_DEFAULT | AVMM | 8 | 512 | N | Y | Y | Y | Y | Production |
| FEB_SCIFI_OOO | AXI4 | 8 | 512 | Y | Y | Y | Y | Y | Production |
| FEB_SCIFI_ORDERED | AVMM | 8 | 512 | N | Y | Y | Y | Y | Production |
| FEB_SCIFI_FULL | AXI4 | 16 | 1024 | Y | Y | Y | Y | Y | Production |
| FEB_MUPIX_DEFAULT | AVMM | 8 | 512 | N | Y | Y | Y | Y | Production |
| FEB_MUPIX_OOO | AXI4 | 8 | 512 | Y | Y | Y | Y | Y | Production |
| FEB_MUPIX_ORDERED | AVMM | 8 | 512 | N | Y | Y | Y | Y | Production |
| FEB_MUPIX_FULL | AXI4 | 16 | 1024 | Y | Y | Y | Y | Y | Production |
| FEB_TILES_DEFAULT | AVMM | 4 | 256 | N | Y | Y | Y | Y | Area-constrained |
| FEB_TILES_MINIMAL | AVMM | 4 | 128 | N | N | N | Y | Y | Minimal |
| MINIMAL_CSR_ONLY | AVMM | 1 | 64 | N | N | N | Y | Y | Minimal |
| MAX_THROUGHPUT | AXI4 | 32 | 2048 | Y | Y | Y | Y | Y | Benchmark |
| MAX_FEATURES | AXI4 | 8 | 512 | Y | Y | Y | Y | Y | DV reference |
| AREA_OPTIMIZED | AVMM | 4 | 128 | N | Y | Y | Y | Y | Area-constrained |

**Total compile variants: 14** (CUSTOM is not a fixed preset; it is tested via edge cases T430–T449 with hand-picked parameter combinations).

### 10.2 Test Applicability per Preset

Not all 305 tests apply to every preset. Tests that exercise a disabled feature are **skipped** (not failed) for presets that lack that feature. The applicability rules:

| Feature Gate | Tests Affected | Skip Condition |
|-------------|----------------|----------------|
| OOO_ENABLE=false | T210–T219 (OoO functional), T313–T319 (OoO speedup), T430–T435 (OoO edge) | Skip OoO-specific tests |
| ORD_ENABLE=false | T230–T249 (ordering functional), T336–T343 (ordering overhead), T436–T441 (ordering edge) | Skip ordering tests |
| ATOMIC_ENABLE=false | T220–T229 (atomic functional), T442–T445 (atomic edge) | Skip atomic tests |
| BUS_TYPE=AVALON | T009–T016 (AXI4-specific from legacy) | Skip AXI4-only tests |
| BUS_TYPE=AXI4 | T001–T008 (AVMM-specific from legacy) | Skip AVMM-only tests |
| OD=1 | T300–T312 (rate scans with OD sweep), T320–T327 (fragmentation stress) | Adapt: run with OD=1 only |
| MAX_BURST≤4 | T400–T414 (non-power-of-2 bursts >4) | Skip burst lengths exceeding MAX_BURST |

**Estimated applicable tests per preset:**

| Preset | Applicable Tests | Skipped | Notes |
|--------|-----------------|---------|-------|
| FEB_SCIFI_DEFAULT | ~265 | ~40 | Skips OoO and AXI4-specific |
| FEB_SCIFI_OOO | ~285 | ~20 | Skips AVMM-specific |
| FEB_SCIFI_FULL | ~285 | ~20 | Skips AVMM-specific |
| FEB_TILES_MINIMAL | ~195 | ~110 | Skips OoO, ordering, atomic, AXI4 |
| MINIMAL_CSR_ONLY | ~160 | ~145 | Skips OoO, ordering, atomic, large bursts |
| MAX_THROUGHPUT | ~285 | ~20 | Skips AVMM-specific |
| MAX_FEATURES | ~285 | ~20 | Skips AVMM-specific; DV reference config |

### 10.3 Fatal Configuration Tests (DV_ERROR.md T532–T549)

Fatal configuration tests are **only run under the specific preset that triggers the fatal condition**. They are not part of the normal regression matrix. Instead, each T532–T549 test specifies the exact parameter override needed:

| Test | Config Override | Preset Base | Purpose |
|------|----------------|-------------|---------|
| T532 | OOO_ENABLE=false, write OOO_CTRL | FEB_TILES_MINIMAL | Verify benign (CSR write ignored) |
| T533 | OOO_ENABLE=false, AXI4 slave reorders | CUSTOM (AXI4, OoO=false) | Verify fatal detection or corruption |
| T534 | OOO_ENABLE=false, high-variance lat | FEB_SCIFI_DEFAULT | Verify degraded-not-fatal |
| T535–T537 | ORD_ENABLE=false, send RELEASE/ACQUIRE/RELAXED | FEB_TILES_MINIMAL | Verify fatal/fatal/benign |
| T538–T539 | ATOMIC_ENABLE=false, send atomic/normal | FEB_TILES_MINIMAL | Verify SLAVEERROR / benign |
| T540–T541 | INT_RESERVED=0 (CUSTOM override) | CUSTOM | Verify unreachable CSR |
| T542–T543 | PLD_DEPTH=64, L=64/L=65 | CUSTOM | Verify permanent stall |
| T544–T545 | BUS_TYPE mismatch | CUSTOM | Verify handler synthesis error |
| T546–T547 | S_AND_F=false, truncated/valid | CUSTOM (S&F=false) | Verify partial write / benign |
| T548–T549 | Clock/reset mismatch | CUSTOM | Verify metastability |

### 10.4 Compile-Time DV Makefile Extension

The existing Makefile (section 7) is extended with preset iteration targets:

```makefile
# ============================================================================
# Compile-time preset iteration
# ============================================================================

PRESETS = FEB_SCIFI_DEFAULT FEB_SCIFI_OOO FEB_SCIFI_ORDERED FEB_SCIFI_FULL \
          FEB_MUPIX_DEFAULT FEB_MUPIX_OOO FEB_MUPIX_ORDERED FEB_MUPIX_FULL \
          FEB_TILES_DEFAULT FEB_TILES_MINIMAL \
          MINIMAL_CSR_ONLY MAX_THROUGHPUT MAX_FEATURES AREA_OPTIMIZED

# Bus type derived from preset (used for BFM selection)
BUS_TYPE_FEB_SCIFI_DEFAULT   = AVALON
BUS_TYPE_FEB_SCIFI_OOO       = AXI4
BUS_TYPE_FEB_SCIFI_ORDERED   = AVALON
BUS_TYPE_FEB_SCIFI_FULL      = AXI4
BUS_TYPE_FEB_MUPIX_DEFAULT   = AVALON
BUS_TYPE_FEB_MUPIX_OOO       = AXI4
BUS_TYPE_FEB_MUPIX_ORDERED   = AVALON
BUS_TYPE_FEB_MUPIX_FULL      = AXI4
BUS_TYPE_FEB_TILES_DEFAULT   = AVALON
BUS_TYPE_FEB_TILES_MINIMAL   = AVALON
BUS_TYPE_MINIMAL_CSR_ONLY    = AVALON
BUS_TYPE_MAX_THROUGHPUT      = AXI4
BUS_TYPE_MAX_FEATURES        = AXI4
BUS_TYPE_AREA_OPTIMIZED      = AVALON

# Feature flags per preset (for test filtering)
OOO_FEB_SCIFI_DEFAULT   = 0
OOO_FEB_SCIFI_OOO       = 1
OOO_FEB_SCIFI_FULL      = 1
OOO_MAX_THROUGHPUT      = 1
OOO_MAX_FEATURES        = 1
# ... (all presets defined similarly)

ORD_FEB_TILES_MINIMAL   = 0
ORD_MINIMAL_CSR_ONLY    = 0
# ... (all presets, default=1 unless explicitly 0)

ATM_FEB_TILES_MINIMAL   = 0
ATM_MINIMAL_CSR_ONLY    = 0
# ... (all presets)

# Compile RTL for a specific preset
compile_preset_%:
	@echo "=== Compiling preset: $* ==="
	$(VCOM) -2008 -work $(WORK)_$* \
		+define+PRESET=\"$*\" \
		+define+BUS_TYPE=\"$(BUS_TYPE_$*)\" \
		$(RTL_FILES)

# Run all applicable tests for a preset
run_preset_%: compile_preset_%
	@echo "=== Running tests for preset: $* ==="
	./scripts/run_preset.sh $* $(BUS_TYPE_$*) $(OOO_$*) $(ORD_$*) $(ATM_$*)

# Run all presets (full compile-time regression)
run_all_presets: $(addprefix run_preset_,$(PRESETS))
	@echo "=== All presets complete ==="

# Generate compile-time coverage report
compile_time_report:
	./scripts/compile_time_coverage.sh $(PRESETS)
```

### 10.5 Preset Test Filter Script (`run_preset.sh`)

```bash
#!/bin/bash
# run_preset.sh <PRESET> <BUS_TYPE> <OOO> <ORD> <ATM>
# Runs all applicable tests for a given preset, skipping feature-gated tests.

PRESET=$1
BUS_TYPE=$2
OOO=$3
ORD=$4
ATM=$5

SKIP_PATTERNS=""

# Skip tests for disabled features
if [ "$OOO" = "0" ]; then
    SKIP_PATTERNS="$SKIP_PATTERNS|t21[0-9]|t31[3-9]|t43[0-5]"
fi
if [ "$ORD" = "0" ]; then
    SKIP_PATTERNS="$SKIP_PATTERNS|t23[0-9]|t24[0-9]|t33[6-9]|t34[0-3]|t43[6-9]|t44[01]"
fi
if [ "$ATM" = "0" ]; then
    SKIP_PATTERNS="$SKIP_PATTERNS|t22[0-9]|t44[2-5]"
fi
if [ "$BUS_TYPE" = "AVALON" ]; then
    SKIP_PATTERNS="$SKIP_PATTERNS|t00[9]|t01[0-6]"  # AXI4-specific legacy
fi
if [ "$BUS_TYPE" = "AXI4" ]; then
    SKIP_PATTERNS="$SKIP_PATTERNS|t00[1-8]"  # AVMM-specific legacy
fi

# Remove leading |
SKIP_PATTERNS="${SKIP_PATTERNS#|}"

echo "Preset: $PRESET  Bus: $BUS_TYPE  OoO: $OOO  ORD: $ORD  ATM: $ATM"
echo "Skip patterns: $SKIP_PATTERNS"

# Run each test, skipping as needed
for test_file in tests/directed/t*.sv tests/uvm/t*.sv; do
    test_name=$(basename "$test_file" .sv)
    if [ -n "$SKIP_PATTERNS" ] && echo "$test_name" | grep -qE "$SKIP_PATTERNS"; then
        echo "SKIP  $test_name (feature not compiled)"
        continue
    fi
    echo "RUN   $test_name"
    make run_directed TEST=$test_name BUS_TYPE=$BUS_TYPE PRESET=$PRESET 2>&1 \
        | tee logs/${PRESET}_${test_name}.log
done
```

### 10.6 Signoff Matrix

Signoff requires **all cells** in the following matrix to be PASS or SKIP (with documented reason):

```
                    T001  T002  ...  T128  T200  ...  T249  T300  ...  T549
FEB_SCIFI_DEFAULT   PASS  PASS  ...  PASS  PASS  ...  PASS  PASS  ...  PASS
FEB_SCIFI_OOO       PASS  PASS  ...  SKIP  PASS  ...  PASS  PASS  ...  PASS
FEB_SCIFI_FULL      PASS  PASS  ...  SKIP  PASS  ...  PASS  PASS  ...  PASS
FEB_MUPIX_DEFAULT   PASS  PASS  ...  PASS  PASS  ...  PASS  PASS  ...  PASS
...
MINIMAL_CSR_ONLY    PASS  PASS  ...  PASS  SKIP  ...  SKIP  SKIP  ...  PASS
MAX_FEATURES        PASS  PASS  ...  SKIP  PASS  ...  PASS  PASS  ...  PASS
AREA_OPTIMIZED      PASS  PASS  ...  PASS  PASS  ...  SKIP  PASS  ...  PASS
```

**Total signoff cells: 14 presets x 305 tests = 4,270 cells** (minus SKIP cells).

Estimated runtime per preset: ~4 hours on Questa FSE (sequential, no parallelism).
Estimated total regression: ~56 hours sequential, ~4 hours with 14-way parallel compilation.

### 10.7 Regression Gate Criteria

| Gate | Criterion | Enforcement |
|------|-----------|-------------|
| G1: Compile | All 14 presets compile without VHDL/SV errors | `compile_preset_%` target |
| G2: Runtime | All applicable tests PASS for all presets | `run_all_presets` target |
| G3: Coverage | All 16 coverage bins hit for each preset | `compile_time_coverage.sh` |
| G4: Assertions | Zero assertion failures across all presets | SVA bind module (A01–A37) |
| G5: Fatal review | All T532–T549 cases run with correct verdict | Manual review per DV_ERROR.md |
| G6: Performance | RTL throughput within TLM tolerance (section 8 of DV_PROF.md) for production presets | `run_perf.sh` comparison |
| G7: Free-list | `free_count == RAM_DEPTH` at quiesce for all presets | A37 assertion |

### 10.8 Test Case Total with Compile-Time Dimension

| Dimension | Count |
|-----------|-------|
| Runtime test cases | 305 |
| Compile-time presets | 14 |
| Total signoff cells | 4,270 |
| Estimated applicable (non-SKIP) cells | ~3,500 |
| Fatal config cases (run separately) | 18 |
| **Grand total test executions for signoff** | **~3,518** |
