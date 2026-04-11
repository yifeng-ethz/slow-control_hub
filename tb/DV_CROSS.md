# DV Cross Cases

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

These long cross cases still do not randomize detector masking against `FEB_TYPE`.
That remains a separate directed gap until the UVM environment learns how to
safely correlate locally masked packets with expected “no execute / no reply” behavior.
