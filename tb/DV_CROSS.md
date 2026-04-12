# DV Cross Cases

**Parent:** [DV_PLAN.md](DV_PLAN.md)
**Canonical ID Space:** CROSS-001 to CROSS-004
**Current Implementation Aliases:** T356-T357, T370-T371


This note tracks the promoted long mixed-feature regressions that sit between
basic directed tests and full performance sweeps.

## T356

- Bus: Avalon-MM
- Profile: long mixed incrementing and nonincrementing traffic
- Intent: keep the hub under sustained mixed read/write load while repeatedly
  crossing between incrementing and fixed-address semantics
- Knobs:
  - `SC_HUB_TXN_COUNT=768`
  - `SC_HUB_BURST_MIN=1`
  - `SC_HUB_BURST_MAX=16`
  - `SC_HUB_READ_PCT=50`
  - `SC_HUB_NONINCREMENT_PCT=35`
  - `SC_HUB_INTERNAL_PCT=10`
- Primary checks:
  - reply packets remain well formed
  - internal CSR accesses do not corrupt the external stream
  - counter paths stay monotonic during the run
- Model note:
  - the Avalon UVM bus monitor expands nonincrementing commands into repeated single-beat bus metadata, matching `rtl/sc_hub_avmm_handler.vhd` bus behavior

## T357

- Bus: AXI4 with OoO enabled
- Profile: long mixed incrementing, nonincrementing, ordering, and atomic traffic
- Intent: stress the combined interaction of fixed bursts, ordering metadata,
  atomic transactions, and out-of-order completion
- Knobs:
  - `SC_HUB_TXN_COUNT=768`
  - `SC_HUB_BURST_MIN=1`
  - `SC_HUB_BURST_MAX=16`
  - `SC_HUB_READ_PCT=50`
  - `SC_HUB_NONINCREMENT_PCT=35`
  - `SC_HUB_ORDERING_PCT=10`
  - `SC_HUB_ATOMIC_PCT=5`
  - `SC_HUB_FORCE_OOO=1`
  - `SC_HUB_CFG_ENABLE_OOO=1`
  - `SC_HUB_ORDER_DOMAINS=4`
- Primary checks:
  - no out-of-order reply violation beyond the permitted AXI4 model
  - atomic replies do not get overtaken by later normal traffic
  - nonincrementing fixed bursts behave identically in the scoreboard and bus monitor

## Current gaps

The dedicated `T370` case now exercises detector masking against a real local
`FEB_TYPE`, and `T371` now sweeps stable internal CSR words instead of touching
only the legacy UID/META subset. The remaining gap is broader than simple
masking or register-map reachability: muted/masked ordering semantics and
capability-contract cases are still not covered by a promoted long run and still
need dedicated additions.


## T370

- Bus: Avalon-MM + AXI4 aggregate
- Profile: local-SciFi masked mixed traffic with ordering, nonincrementing, and OoO pressure
- Intent: close the long-standing gap where detector masks were exercised only as `FEB_TYPE_ALL` semantics instead of a real local detector type
- Knobs:
  - `SC_HUB_LOCAL_FEB_TYPE=scifi`
  - `SC_HUB_MASK_PCT=60`
  - `SC_HUB_MASK_MODE=rotate`
  - `SC_HUB_NONINCREMENT_PCT=20`
  - `SC_HUB_ORDERING_PCT=20..25`
  - `SC_HUB_ORDER_DOMAINS=4`
  - `SC_HUB_INTERNAL_PCT=10`
  - AXI4 leg additionally enables `SC_HUB_ATOMIC_PCT=5`, `SC_HUB_FORCE_OOO=1`, and `SC_HUB_CFG_ENABLE_OOO=1`
- Primary checks:
  - packets masked for the local SciFi type are ignored for execution
  - unrelated detector masks still execute and, unless `mask_r` is set, still reply
  - masked traffic does not corrupt ordering or OoO bookkeeping for adjacent unmasked traffic
  - internal `FEB_TYPE` programming and software-visible reply suppression stay aligned with the scoreboard/bus model


## T371

- Bus: Avalon-MM + AXI4 aggregate
- Profile: internal CSR sweep with stable readback and light external traffic
- Intent: cover the internal CSR map branches in `sc_hub_core` and keep the UVM/ref-model contract aligned for writable control words
- Knobs:
  - `SC_HUB_INTERNAL_PCT=85`
  - `SC_HUB_INTERNAL_MODE=csr_sweep`
  - `SC_HUB_FIXED_LEN=1`
  - `SC_HUB_READ_PCT=70`
  - AXI4 leg additionally enables `SC_HUB_FORCE_OOO=1` and `SC_HUB_CFG_ENABLE_OOO=1`
- Primary checks:
  - META page selection, CTRL enable, SCRATCH, FIFO_CFG, OOO_CTRL, FEB_TYPE, and HUB_CAP read back coherently
  - internal writes update the scoreboard/ref-model state rather than being treated as opaque memory side effects
  - the wider CSR sweep increases structural coverage in `sc_hub_core`, `sc_hub_pkg`, and the internal read path without relying on malformed traffic
