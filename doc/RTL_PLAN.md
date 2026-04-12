# SC_HUB v2 — RTL Design Plan

**IP Name:** sc_hub_v2 (Slow Control Hub)
**Author:** Yifeng Wang
**Version:** 26.3.0
**Baseline:** v26.0.0332 (feb_system_v2 synthesis submodule)
**Integration Target:** online_dpv2 / fe_scifi / feb_system_v2
**Companion Documents:** TLM_PLAN.md, DV_PLAN.md, DV_BASIC.md, DV_PROF.md, DV_EDGE.md, DV_ERROR.md, TLM_NOTE.md, ORDERING_GUIDE.md

---

## 1. Motivation

The v1 hub (v26.0.0330) has three structural limitations:

1. **No internal CSR header** in the IP-core tree. The CSR register map exists only in the synthesis copy.
2. **Avalon-only master.** No path for AXI4-based systems.
3. **Cut-through only.** Malformed packets can partially complete bus writes. `avm_m0_flush` is deprecated.

The v2 redesign addresses these and adds four new capabilities driven by TLM analysis (TLM_PLAN.md):

4. **Split-buffer architecture** with multiple outstanding transactions and linked-list payload RAM.
5. **Out-of-order dispatch** for AXI4 with reply reordering (compile-time + runtime controllable).
6. **Release/Acquire ordering semantics** per domain (16 domains, 4 correctness rules).
7. **Atomic read-modify-write** with bus lock sequencing.

---

## 2. Design Goals

| # | Goal | Acceptance Criteria |
|---|------|---------------------|
| G1 | Canonical CSR | CSR map at 0xFE80, 32-word window, in IP source. Extended with OOO_CTRL, ORD counters, HUB_CAP. |
| G2 | Dual bus interface | `BUS_TYPE` ∈ {AVALON, AXI4}. Shared packet FSM, bus-specific handler. |
| G3 | Store-and-forward download | Validate entire packet before bus write. Drop and count malformed packets. |
| G4 | Cut-through upload | Read data streams directly into reply assembly. |
| G5 | Remove flush | Read/write timeout aborts internally, no interconnect flush. |
| G6 | Backward-compatible packet format | Wire format unchanged. New fields (ORDER, atomic_flag) occupy previously reserved bits. |
| G7 | Split-buffer / multi-outstanding | 8 subFIFOs, linked-list payload RAM, configurable outstanding depth (1–32). |
| G8 | OoO dispatch | Compile-time OOO_ENABLE + runtime OOO_CTRL CSR. AXI4 per-ID tracking. |
| G9 | Ordering semantics | RELAXED/RELEASE/ACQUIRE per packet. 16 independent domains. Zero overhead on RELAXED. |
| G10 | Atomic RMW | Hub-internal read-modify-write with bus lock. Internal CSR bypasses lock. |
| G11 | Preset-based configuration | 14 named presets in `_hw.tcl`, JESD204B-style GUI. No reliance on .prst files. |

---

## 3. Architecture

### 3.1 Top-Level Hierarchy

```
sc_hub_top.vhd                         (Platform Designer boundary)
├── sc_hub_pkt_rx.vhd                  (S&F validator, commit/rollback FIFO)
│   └── sc_hub_fifo_sf.vhd
├── sc_hub_core.vhd                    (classifier, dispatch FSM, reply assembler)
│   ├── sc_hub_admit_ctrl.vhd          (space check: header + payload + cmd_order)
│   ├── sc_hub_malloc.vhd              (linked-list payload alloc/free, 4 pools)
│   ├── sc_hub_pld_ram.vhd             (linked-list payload RAM, parameterised)
│   ├── sc_hub_credit_mgr.vhd          (upload payload credit reservation)
│   ├── sc_hub_ooo_scoreboard.vhd      (OoO dispatch tracking, conditional)
│   ├── sc_hub_ord_tracker.vhd         (per-domain release/acquire FSM, conditional)
│   ├── sc_hub_atomic_seq.vhd          (RMW lock sequencer, conditional)
│   ├── sc_hub_avmm_handler.vhd        (Avalon-MM handler, conditional on BUS_TYPE)
│   └── sc_hub_axi4_handler.vhd        (AXI4 handler, conditional on BUS_TYPE)
├── sc_hub_pkt_tx.vhd                  (reply assembly)
│   └── sc_hub_fifo_bp.vhd             (backpressure FIFO)
├── fifo/
│   ├── sc_hub_fifo_sc.vhd             (generic show-ahead FIFO)
│   ├── sc_hub_fifo_sf.vhd             (store-and-forward with commit/rollback)
│   └── sc_hub_fifo_bp.vhd             (backpressure FIFO, half-full threshold)
└── sc_hub_pkg.vhd                     (types, constants, CSR offsets)
```

### 3.2 Split-Buffer Data Path

The core contains **8 subFIFOs** organized as 4 pools (ext_down, int_down, ext_up, int_up), each with a header FIFO and a linked-list payload RAM:

```
SC CMD ──> [S&F Validator] ──> [Classifier]
                                    │
               ext path             │            int path
               ┌────┐               │            ┌────┐
               │ ext_down_hdr (OD)  │            │ int_down_hdr (IHD)
               │ ext_down_pld (PLD) │            │ int_down_pld (IPLD)
               └────┘               │            └────┘
                    │          cmd_order_fifo          │
                    v               │                  v
               [Dispatch FSM] ──────┼──── [CSR Handler]
                    │                                  │
               Bus Handler                             │
                    │                                  │
               │ ext_up_hdr (OD)  │          │ int_up_hdr (IHD)
               │ ext_up_pld (PLD) │          │ int_up_pld (IPLD)
               └────┘               │        └────┘
                    │          reply_order_fifo    │
                    v               │             v
               [Reply Assembler] ───┘
                    │
               [BP FIFO (BP)]
                    │
               SC REPLY out
```

**Payload RAM:** Each pool uses a linked-list allocation scheme (`sc_hub_malloc`). Fragmentation does not cause allocation failure — non-contiguous blocks are linked via next-pointers. TLM FRAG experiments validate this property.

**Admission control:** `sc_hub_admit_ctrl` checks space in header FIFO, payload RAM (via malloc free count), and cmd_order_fifo before accepting a new packet. On failure, the header push is reverted and the packet is retried or backpressured.

**Credit manager:** `sc_hub_credit_mgr` reserves upload payload capacity before issuing a read. Effective read outstanding = min(OUTSTANDING_LIMIT, EXT_UP_PLD_DEPTH / burst_length).

**Internal priority:** `OUTSTANDING_INT_RESERVED` slots are exclusively for internal CSR transactions, guaranteeing CSR reachability (including CTRL.reset) even when external traffic saturates.

### 3.3 Out-of-Order Dispatch

When `OOO_ENABLE=true` (compile-time) and `OOO_CTRL.enable=1` (runtime):

- Dispatch scoreboard tracks in-flight transactions by AXI4 ID.
- Reply assembly uses scoreboard match instead of reply_order_fifo.
- Read responses may complete in any order; the scoreboard maps RID back to the original command slot.
- With `BUS_TYPE=AVALON`: OoO provides limited benefit (Avalon-MM guarantees in-order read completion). Benefit is limited to internal CSR bypass.

TLM OOO-01..06 predict 1.3–3.0x throughput improvement at high-variance slave latency.

When `OOO_ENABLE=false`: scoreboard logic is not synthesized. All transactions complete in issue order.

### 3.4 Ordering Semantics

When `ORD_ENABLE=true`, `sc_hub_ord_tracker` implements per-domain release/acquire FSMs:

- **RELAXED (ORDER=00):** Zero overhead. Domain state checked in O(1), never blocks.
- **RELEASE (ORDER=01):** Drain barrier. All older writes in the domain must reach bus-visible-retired before the release transaction issues. Prevents reordering across a publish point.
- **ACQUIRE (ORDER=10):** Hold barrier. No younger same-domain transaction issues until the acquire completes. Ensures the consumer sees all writes published before the acquire.

Four correctness rules (R1–R4) are defined in ORDERING_GUIDE.md and verified by SVA assertions A29–A33 (DV_PLAN.md).

16 independent ordering domains (4-bit ORD_DOM_ID). Cross-domain traffic is independent.

When `ORD_ENABLE=false`: ordering tracker not synthesized. All traffic treated as RELAXED.

### 3.5 Atomic Read-Modify-Write

When `ATOMIC_ENABLE=true`, `sc_hub_atomic_seq` provides:

1. Read phase: issue bus read with lock (AVMM `avm_hub_lock=1` / AXI4 `AxLOCK=1`).
2. Modify phase: compute `(read_data & ~mask) | (modify_data & mask)`.
3. Write phase: issue bus write with lock held.
4. Lock released after write response.

Internal CSR traffic bypasses the lock. Atomic packets with `ATOMIC_ENABLE=false` receive SLAVEERROR.

### 3.6 Bus Handlers

**AVMM handler:** Avalon-MM master with burstcount, writeresponsevalid. No flush. Configurable read/write timeout. `maximumPendingReadTransactions` = EFFECTIVE_EXT_OUTSTANDING. Optional `avm_hub_lock` for atomic.

**AXI4 handler:** AXI4 full with INCR bursts. ARLEN/AWLEN = rw_length - 1. Fixed ARSIZE/AWSIZE = 010 (4 bytes). Configurable ID width (1–8 bits). Optional AxLOCK for atomic, optional AxUSER for ordering metadata.

### 3.7 Store-and-Forward Download

`sc_hub_pkt_rx` buffers the entire write packet in `sc_hub_fifo_sf`. A shadow write pointer is committed only after trailer validation passes. On failure, the pointer rolls back (zero-cycle discard). Malformed packets increment PKT_DROP_CNT.

Latency cost: +1 cycle over cut-through (validation after trailer).

---

## 4. CSR Register Map

Base: 0xFE80 (32-word window). Extended from v26.0.0332:

| Offset | Name | R/W | New in v2 |
|--------|------|-----|-----------|
| 0x00–0x17 | Legacy CSR (ID, VERSION, CTRL, STATUS, ERR_FLAGS, ERR_COUNT, SCRATCH, GTS, FIFO, counters) | various | No |
| 0x18 | OOO_CTRL | RW | Yes — runtime OoO enable (bit 0). Only present when OOO_ENABLE=true. |
| 0x19 | ORD_DRAIN_CNT | RO | Yes — release drain event counter. Only when ORD_ENABLE=true. |
| 0x1A | ORD_HOLD_CNT | RO | Yes — acquire hold event counter. Only when ORD_ENABLE=true. |
| 0x1F | HUB_CAP | RO | Yes — compile-time capability flags (OoO, ORD, ATM, S&F, INT_RESERVED, PLD_DEPTH, MAX_BURST). Only when HUB_CAP_ENABLE=true. |

Software reads HUB_CAP at init to detect which features are compiled in, avoiding silent failures from using disabled features (see DV_ERROR.md T532–T549 fatal analysis).

---

## 5. HDL Generics

The full parameter set is defined in `hw_tcl/sc_hub_v2_params.tcl` (8 groups, ~30 parameters). Key generics that become VHDL top-level ports/generics:

| Generic | Type | Default | Range | Description |
|---------|------|---------|-------|-------------|
| BUS_TYPE | string | AVALON | {AVALON, AXI4} | Bus handler selection |
| ADDR_WIDTH | natural | 16 | 12–24 | Word address width |
| OUTSTANDING_LIMIT | natural | 8 | 1–32 | Max concurrent transactions |
| OUTSTANDING_INT_RESERVED | natural | 2 | 1–4 | Slots reserved for internal CSR |
| EXT_DOWN_PLD_DEPTH | natural | 512 | 64–2048 | External download payload RAM depth |
| EXT_UP_PLD_DEPTH | natural | 512 | 64–2048 | External upload payload RAM depth |
| MAX_BURST | natural | 256 | 1–256 | Maximum burst length |
| BP_FIFO_DEPTH | natural | 512 | 64–1024 | Backpressure FIFO depth |
| OOO_ENABLE | boolean | false | — | Compile-time OoO scoreboard |
| ORD_ENABLE | boolean | true | — | Compile-time ordering tracker |
| ORD_NUM_DOMAINS | natural | 16 | 1–16 | Independent ordering domains |
| ATOMIC_ENABLE | boolean | true | — | Compile-time atomic RMW sequencer |
| S_AND_F_ENABLE | boolean | true | — | Store-and-forward write validation |
| HUB_CAP_ENABLE | boolean | true | — | Capability register |
| RD_TIMEOUT_CYCLES | natural | 1024 | 128–8192 | Read timeout |
| WR_TIMEOUT_CYCLES | natural | 1024 | 128–8192 | Write timeout |
| AXI4_ID_WIDTH | natural | 4 | 1–8 | AXI4 ID width (visible when AXI4) |
| AXI4_USER_WIDTH | natural | 16 | 0–32 | AXI4 AxUSER width (ordering metadata) |

Derived parameters (computed during elaboration): EXT_HDR_DEPTH, PLD_ADDR_WIDTH, BURSTCOUNT_WIDTH, EFFECTIVE_EXT_OUTSTANDING.

---

## 6. `_hw.tcl` Structure

The `_hw.tcl` is modular, split into 8 sub-files sourced from `hw_tcl/`:

| File | Purpose |
|------|---------|
| `sc_hub_v2_hw.tcl` | Main entry, module properties, elaboration/validation callbacks |
| `hw_tcl/sc_hub_v2_utils.tcl` | HTML helpers, clog2, format utilities |
| `hw_tcl/sc_hub_v2_params.tcl` | All parameter definitions (8 groups) |
| `hw_tcl/sc_hub_v2_presets.tcl` | 14 named presets + application logic |
| `hw_tcl/sc_hub_v2_gui.tcl` | 8-tab GUI layout, dynamic elaboration |
| `hw_tcl/sc_hub_v2_validate.tcl` | Range checks, cross-parameter validation |
| `hw_tcl/sc_hub_v2_connections.tcl` | Interface building, conditional HDL fileset |
| `hw_tcl/sc_hub_v2_tlm_preview.tcl` | TLM CSV lookup, performance preview HTML |
| `hw_tcl/sc_hub_v2_report.tcl` | Resource estimation from synthesis database |

**Presets:** 14 named configurations spanning 3 platforms (SciFi, Mupix, Tiles) × 4 feature tiers (DEFAULT, OOO, ORDERED, FULL) + 5 generic presets (MINIMAL_CSR_ONLY, MAX_THROUGHPUT, MAX_FEATURES, AREA_OPTIMIZED, CUSTOM). Selecting a preset atomically sets all parameters. CUSTOM enables manual tuning.

**GUI:** 8 tabs modeled after Intel JESD204B IP: Configuration, Buffer Architecture, Features, Performance Preview, Resource Estimate, Register Map, Interfaces, Identity. Dynamic sections update based on parameter values.

**Conditional HDL fileset:** Core files always present. Bus handler (AVMM or AXI4), OoO scoreboard, ordering tracker, and atomic sequencer are conditionally included based on feature enables.

---

## 7. File Plan

```
slow-control_hub/
├── sc_hub_v2_hw.tcl                  Main _hw.tcl (v26.3.0)
├── hw_tcl/                           _hw.tcl sub-files (8 files)
├── sc_hub_pkg.vhd                    Shared types, constants
├── sc_hub_top.vhd                    Platform Designer top-level
├── sc_hub_core.vhd                   Central FSM + CSR + dispatch
├── sc_hub_pkt_rx.vhd                 S&F packet receiver
├── sc_hub_pkt_tx.vhd                 Reply assembly
├── sc_hub_avmm_handler.vhd           Avalon-MM handler
├── sc_hub_axi4_handler.vhd           AXI4 handler
├── sc_hub_top_axi4.vhd               AXI4 top-level wrapper
├── sc_hub_malloc.vhd                 Linked-list payload alloc/free
├── sc_hub_pld_ram.vhd                Parameterised payload RAM
├── sc_hub_admit_ctrl.vhd             Admission control
├── sc_hub_credit_mgr.vhd             Upload credit reservation
├── sc_hub_ooo_scoreboard.vhd         OoO dispatch scoreboard (conditional)
├── sc_hub_ord_tracker.vhd            Ordering domain tracker (conditional)
├── sc_hub_atomic_seq.vhd             Atomic RMW sequencer (conditional)
├── fifo/
│   ├── sc_hub_fifo_sc.vhd            Generic show-ahead FIFO
│   ├── sc_hub_fifo_sf.vhd            Store-and-forward FIFO
│   └── sc_hub_fifo_bp.vhd            Backpressure FIFO
├── legacy/                           v1 preserved for backward compat
├── syn/                              Standalone synthesis scripts + resource DB
├── tlm/                              Python TLM model + results
├── dv/                               Testbench, UVM env, tests, scripts
├── RTL_PLAN.md                       THIS FILE
├── DV_PLAN.md                        DV main entrance (305 tests, 14 presets)
├── DV_BASIC.md                       Basic functional tests (T001–T249)
├── DV_PROF.md                        Performance + stress (T300–T357 implementation aliases)
├── DV_EDGE.md                        Edge cases (T400–T449)
├── DV_ERROR.md                       Error handling: soft/hard/fatal (T500–T549)
├── TLM_PLAN.md                       Python TLM model (63 experiments)
├── TLM_NOTE.md                       TLM implementation review (7 issues, all fixed)
└── ORDERING_GUIDE.md                 Software guide for ordering + atomic
```

**Vendor-neutral FIFOs.** All FIFOs use portable VHDL (inferred block RAM). No Intel megafunction dependencies.

---

## 8. Verification

DV is organized in DV_PLAN.md with 305 test cases across 4 categories:

| Category | Document | Tests | Method |
|----------|----------|-------|--------|
| Basic functional | DV_BASIC.md | T001–T249 (155) | Directed + UVM |
| Performance | DV_PROF.md | T300–T357 implementation aliases | UVM sweeps |
| Edge cases | DV_EDGE.md | T400–T449 (50) | Directed |
| Error handling | DV_ERROR.md | T500–T549 (50) | Directed |

**Compile-time dimension:** All 14 presets are compiled as separate RTL variants. Each preset runs the applicable subset of 305 tests. Feature-gated tests (OoO, ordering, atomic) are skipped for presets that lack the feature. Total signoff cells: ~3,500.

**Fatal configuration analysis:** DV_ERROR.md T532–T549 examines each area-saving configuration one-by-one. HUB_CAP register converts silent failures into detectable errors at software init.

**Testbench:** Questa FSE 2022.4 (local) or full Questa via ETH floating license (`8161@lic-mentor.ethz.ch`). With the ETH license, `covergroup` and `rand`/`constraint` are available. 37 SVA assertions (A01–A37) covering bus protocol, packet framing, FSM liveness, ordering invariants, and free-list integrity.

**TLM-to-RTL traceability:** Every new test case traces back to a TLM experiment (see DV_PLAN.md section 1.1).

---

## 9. Migration from v1

- **Packet format:** Unchanged. ORDER and atomic_flag occupy previously reserved bits (backward compatible).
- **CSR register map:** Superset of v26.0.0332. Four new conditional registers (0x18–0x1F).
- **AVMM interface:** `avm_m0_flush` removed. `maximumPendingReadTransactions` now equals EFFECTIVE_EXT_OUTSTANDING (was 1).
- **Integration:** Replace `sc_hub` with `sc_hub_v2` in Qsys. Set `BUS_TYPE=AVALON` for drop-in replacement. Remove external FIFO sideband connections. No Intel megafunction dependencies.

Both v1 (`sc_hub`) and v2 (`sc_hub_v2`) are registered as separate Platform Designer components and can coexist in the IP catalog.

---

## 10. Resolved Design Questions

| Question | Resolution | Reference |
|----------|-----------|-----------|
| Download FIFO: commit/rollback vs. drain? | Commit/rollback via shadow write pointer in `sc_hub_fifo_sf`. | Implemented |
| GTS counter: external vs. internal? | Keep internal free-running counter. External sync deferred. | Unchanged |
| Single vs. multi-outstanding? | Multi-outstanding with configurable depth (1–32). TLM SIZE-01 shows knee at OD=4–8. | TLM_PLAN.md |
| OoO: compile-time vs. runtime? | Both. Compile-time gate (no area when disabled) + runtime CSR toggle. | TLM_PLAN.md OOO-01..06 |
| Ordering model? | Release/Acquire/Relaxed per domain, 4 rules (R1–R4). | ORDERING_GUIDE.md |
| Atomic RMW? | Hub-internal with bus lock. Single-word only. | TLM_PLAN.md ATOM-01..04 |
