# sc_hub TB Implementation Status + RTL Handoff

## Scope

This document tracks TB runtime coverage against the current DV plan snapshot and
explicitly lists RTL boundaries that block broader `DV_PLAN.md` execution.

## What is runnable in this harness

| Harness | Implemented | Runnable IDs | Status note |
|---|---|---|---|
| Directed | `sc_hub_tb_top.sv` | `smoke_basic`, `T001`–`T012`, `T025`, `T027`–`T070`, `T077`–`T083`, `T087`–`T122` | Direct dispatch via `TEST_NAME`; current checked-in matrix is AVMM-only |
| UVM | `sc_hub_uvm_tb_top.sv` | `sc_hub_base_test`, `sc_hub_sweep_test` | Via `UVM_TESTNAME`; sweep defaults are trimmed to the current implemented surface |
| PERF | `scripts/` + `DV_PERF.md` | None | Not mapped into this snapshot run matrix |
| EDGE | `scripts/` + `DV_EDGE.md` | None | Not mapped into this snapshot run matrix |
| ERROR | `scripts/` + `DV_ERROR.md` | None | Not mapped into this snapshot run matrix |

Confidence: inferred from `tb/Makefile` targets and `sc_hub_tb_top.sv` dispatch table
(confirmed by files read).

## Missing boundaries blocking full DV_PLAN execution

### 1) Split-buffer + free-list visibility

Root cause: linked-list free-list state and allocator/revert checkpoints are only exposed through test-specific assumptions, not through runnable TB scoreboards/counters in this snapshot.  
Effect: `T200`–`T229` and `T214`/`T247` family expectations cannot be validated as pass/fail without RTL-side instrumentation and predictable visibility.  
Practical fix: expose allocator state/masking points for free_count and admission-revert behavior at the RTL boundary or add a dedicated visibility shim for regression.  
Likely RTL files needing work: `../sc_hub_core.vhd`, `../sc_hub_pkt_rx.vhd`, `../sc_hub_pkt_tx.vhd`, `../fifo/sc_hub_fifo_sc.vhd`, `../fifo/sc_hub_fifo_sf.vhd`, `../fifo/sc_hub_fifo_bp.vhd`.

### 2) Out-of-order dispatch + completion boundary

Root cause: `OOO_CTRL`, ARID/RID-reordered completion, and mixed AXI4/AVMM return-path behavior are not all wired into a unified runnable flow (`run_directed.sh` / `run_uvm.sh` and sequence mapping currently stop at `T122`).  
Effect: `T210`–`T219` + related OoO edge cases cannot be executed in this snapshot, and ordering interactions with free-list pressure cannot be observed as required by `DV_BASIC.md`/`DV_PERF.md`.  
Practical fix: complete runnable OoO control in core and handler modules and map to directed/UVM transaction generators.  
Likely RTL files needing work: `../sc_hub_core.vhd`, `../sc_hub_axi4_handler.vhd`, `../sc_hub_avmm_handler.vhd`, `../sc_hub_top_axi4.vhd`, `../sc_hub_top.vhd`, `../sc_hub_pkg.vhd`.

### 3) Ordering and atomic feature boundaries

Root cause: ordering (RELAXED/RELEASE/ACQUIRE) state machine and atomic RMW lock/exclusive handoff are not fully represented in the currently runnable sequence-to-scoreboard path.  
Effect: `T220`–`T229`, `T230`–`T249`, and `T236`/`T247` ordering-atomic interactions cannot be asserted in this snapshot.  
Practical fix: finalize ordering and atomic sequencing contracts in RTL and align RTL-visible hooks (`ordering_scope`, `atomic_lock`, reply metadata) with existing TB tasks and assertions.  
Likely RTL files needing work: `../sc_hub_core.vhd`, `../sc_hub_pkt_rx.vhd`, `../sc_hub_pkt_tx.vhd`, `../sc_hub_avmm_handler.vhd`, `../sc_hub_axi4_handler.vhd`.

### 4) Error/recovery and feature-gate contract

Root cause: timeout, recovery, and feature-disable behavior (`OOO_ENABLE`, `ORD_ENABLE`, `ATOMIC_ENABLE`) are compile/CFG-sensitive and not coupled to harness run-time gates.  
Effect: soft/hard/fatal error cases (`T500`+), reset-domain fault cases (`T548`–`T549`), and feature-mismatch expectations (`T532`–`T539`) remain un-runnable.  
Practical fix: add testable RTL hooks for timeout/error counters and feature-gate reporting, then add run presets + skip logic in harness gating.  
Likely RTL files needing work: `../sc_hub_core.vhd`, `../sc_hub_top.vhd`, `../sc_hub_top_axi4.vhd`, `../sc_hub_pkg.vhd`.

## Current integration notes

- The committed snapshot includes TB runner fixes, assertion fixes, and Platform Designer wrapper truthfulness fixes under `hw_tcl/`.
- The current Platform Designer wrapper is AVMM-only. Root cause: the packaged `QUARTUS_SYNTH` fileset is fixed to the live `sc_hub_top` boundary, and PD does not allow switching the compiled top-level during elaboration.
- Effect: AXI4 remains available as a standalone RTL top-level (`sc_hub_top_axi4`) but is not a generatable PD configuration in this snapshot.
- Practical fix for future AXI4 PD integration: ship a dedicated AXI4 component/wrapper or separate catalog entry with its own fixed fileset and interface contract.
