# Synthesis Signoff

## Scope

This note records the current standalone Quartus signoff state for the active
`slow-control_hub` RTL under `syn/quartus/`.

Compiled standalone revisions:

- `sc_hub_minimal_live`
- `sc_hub_tiles_minimal`
- `sc_hub_full_live_axi4`

## Signoff Target

- Device family: Arria V
- Device: `5AGXBA7D4F31C5`
- Quartus: `18.1.0 Build 625`
- Signoff clock in all standalone revisions:
  - `create_clock -period 5.818 [get_ports {i_clk}]`
  - equivalent to `171.875 MHz`
- Nominal Mu3e SC clock:
  - `156.25 MHz`
- Therefore the standalone signoff projects are compiled at `110%` of nominal
  target frequency.

Important: because the project SDC is already tightened to `5.818 ns`, the
relevant gate is `setup WNS >= 0` and `hold WNS >= 0` at that period. Applying
an additional `+10% margin` rule on top of these projects would double-count
the intended margin.

## Overall Result

Overall status: PASS.

All three active standalone revisions now close setup and hold at the tightened
`5.818 ns` signoff period.

Caveat:

- `sc_hub_full_live_axi4` closes with only `+0.006 ns` setup margin, so the
  AXI4 preset is signed off but not comfortable.

## Timing Summary

| Revision | Bus / preset | Setup WNS ns | Setup TNS ns | Hold WNS ns | Hold TNS ns | Status |
|----------|--------------|-------------:|-------------:|------------:|------------:|--------|
| `sc_hub_minimal_live` | full Avalon live | 0.083 | 0.000 | 0.274 | 0.000 | PASS |
| `sc_hub_tiles_minimal` | reduced Avalon tiles | 0.382 | 0.000 | 0.295 | 0.000 | PASS |
| `sc_hub_full_live_axi4` | full AXI4 live | 0.006 | 0.000 | 0.270 | 0.000 | PASS |

All three revisions are also clean for minimum pulse width in the current
reports.

## Top-Level Resource Summary

The table below uses the fitter summary totals.

| Revision | ALMs used | Regs | Memory bits | M10Ks | DSPs | Pins |
|----------|----------:|-----:|------------:|------:|-----:|-----:|
| `sc_hub_minimal_live` | 4229 | 6271 | 35840 | 4 | 0 | 251 |
| `sc_hub_tiles_minimal` | 1846 | 2635 | 10432 | 3 | 0 | 177 |
| `sc_hub_full_live_axi4` | 3377 | 5888 | 76800 | 9 | 0 | 243 |

Note on accounting:

- the top-level table above uses `*.fit.summary`
- the block-level tables below use the entity-level fitter accounting from
  `*.fit.rpt`, which reports `ALMs used in final placement`
- those two views are related but not numerically identical, so they should not
  be mixed without stating which accounting basis is used

## Block-Level Utilization

### `sc_hub_minimal_live`

Entity-level fitter accounting:

- top placed ALMs: `4705.6`
- top registers: `6271`
- top memory bits: `35840`
- top M10Ks: `4`

| Block | ALMs used in final placement | Comb ALUTs | Regs | Mem bits | M10Ks |
|-------|-----------------------------:|-----------:|-----:|---------:|------:|
| `sc_hub_avmm_handler` | 108.3 | 155 | 101 | 0 | 0 |
| `sc_hub_core` | 2141.5 | 3073 | 2421 | 8192 | 1 |
| `sc_hub_pkt_rx` | 2118.7 | 1603 | 3300 | 8192 | 1 |
| `sc_hub_pkt_tx` | 264.0 | 393 | 305 | 19456 | 2 |

Readout:

- logic is split almost evenly between `sc_hub_core` and `sc_hub_pkt_rx`
- reply-side RAM ownership remains dominated by `sc_hub_pkt_tx`
- `sc_hub_avmm_handler` is not a major timing or area driver

### `sc_hub_tiles_minimal`

Entity-level fitter accounting:

- top placed ALMs: `2226.5`
- top registers: `2635`
- top memory bits: `10432`
- top M10Ks: `3`

| Block | ALMs used in final placement | Comb ALUTs | Regs | Mem bits | M10Ks |
|-------|-----------------------------:|-----------:|-----:|---------:|------:|
| `sc_hub_avmm_handler` | 107.9 | 160 | 102 | 0 | 0 |
| `sc_hub_core` | 1135.3 | 1473 | 1086 | 8192 | 1 |
| `sc_hub_pkt_rx` | 690.3 | 810 | 1054 | 1024 | 1 |
| `sc_hub_pkt_tx` | 234.2 | 309 | 281 | 1216 | 1 |

Readout:

- the reduced tiles preset is still core-dominated
- the old failing `read_fill_index -> reply_arm_*` cone is no longer the top
  path after the reply-prep split
- the current top path moved into the small AVMM shell and now has healthy
  margin

### `sc_hub_full_live_axi4`

Entity-level fitter accounting:

- top placed ALMs: `4145.0`
- top registers: `5888`
- top memory bits: `76800`
- top M10Ks: `9`

| Block | ALMs used in final placement | Comb ALUTs | Regs | Mem bits | M10Ks |
|-------|-----------------------------:|-----------:|-----:|---------:|------:|
| `sc_hub_axi4_core` | 1500.7 | 1539 | 1945 | 49152 | 6 |
| `sc_hub_axi4_ooo_handler` | 270.8 | 347 | 260 | 0 | 0 |
| `sc_hub_pkt_rx` | 2013.9 | 1521 | 3236 | 8192 | 1 |
| `sc_hub_pkt_tx` | 297.2 | 415 | 305 | 19456 | 2 |

Readout:

- `sc_hub_pkt_rx` remains the largest logic owner
- `sc_hub_axi4_core` remains the dominant RAM owner
- the AXI4 timing bottleneck is still inside the core TX/slot bookkeeping space,
  but it is now just on the positive side of the signoff line

## Critical Timing Cones

These are the current worst setup paths from fresh post-closure `report_timing`
runs.

### `sc_hub_minimal_live`

- Slack: `+0.083 ns`
- From: `sc_hub_core:core_inst|pkt_info_reg.rw_length[5]`
- To: `sc_hub_core:core_inst|last_ext_read_addr[2]`

Interpretation:

- the full Avalon live preset is closed, but not with large residual margin
- changes touching external-read address generation should continue to rerun this
  preset first

### `sc_hub_tiles_minimal`

- Slack: `+0.382 ns`
- From: `sc_hub_top:dut_inst|sc_hub_avmm_handler:avmm_handler_inst|words_seen[1]`
- To: `sc_hub_top:dut_inst|sc_hub_avmm_handler:avmm_handler_inst|avmm_state.IDLING`

Interpretation:

- the previous core-side reply-arm cone is no longer the limiting path
- the AVALON tiles preset now has useful headroom relative to the prior fail

### `sc_hub_full_live_axi4`

- Slack: `+0.006 ns`
- From: `sc_hub_axi4_core:core_inst|tx_ooo_ext_ready_seq[5]`
- To: `sc_hub_axi4_core:core_inst|tx_ext_words_remaining[12]`

Interpretation:

- the AXI4 timing fix worked, but the remaining margin is razor-thin
- the critical cone has moved to the registered OoO-ready to TX-remaining-word
  bookkeeping path
- any future feature growth in AXI4 TX selection/bookkeeping should be assumed to
  threaten closure until recompiled

## Signoff Decision

### What is closed

- all three active standalone revisions meet setup and hold at the tightened
  `5.818 ns` signoff clock
- the prior failing AVALON and AXI4 cones were both reduced enough to close
- top-level area remains modest on Arria V across all three presets

### Remaining limitations

- `sc_hub_full_live_axi4` has only `+0.006 ns` setup margin and should be
  treated as fragile timing closure
- `doc/RTL_PLAN.md` still lacks a numeric per-block resource budget table, so a
  strict actual-vs-estimate ratio gate is still not formally closed

## Required Guardrails for Future Changes

1. Keep `sc_hub_full_live_axi4` in the standalone compile gate for any AXI4-core edit.
2. Recheck the `tx_ooo_ext_ready_seq -> tx_ext_words_remaining` cone first if AXI4 timing regresses.
3. Recheck `sc_hub_minimal_live` on any external-read datapath edit.
4. If the resource plan is promoted to a formal signoff gate, add explicit
   numeric ALM/register/RAM budgets to `doc/RTL_PLAN.md`.
