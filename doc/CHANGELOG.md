# Changelog

## 26.6.4.0412

- **RTL**: `sc_hub_pkt_rx` version bumped to `26.2.31`. The `WAITING_WRITE_SPACE` state now treats a held-stable repeat of the already-latched payload word as a no-op instead of a drop (added `elsif (i_download_data = waiting_word_data and i_download_datak = waiting_word_datak) then null;` branch). The code for the behaviour described under `26.6.2.0412` was drafted but never committed; this release commits the actual `sc_hub_pkt_rx.vhd` diff so the 17 retry cases (`T123 T301 T302 T303 T304 T317 T320 T321 T323 T326 T327 T337 T344 T345 T347 T350 T352`) are reproducible from `git checkout 26.6.4.0412`.
- **RTL**: `sc_hub_axi4_core` now defines a local `to_hstring(std_logic_vector) -> string` helper inside the architecture. Quartus Prime Standard `18.1` does **not** ship `to_hstring` in its VHDL-2008 `ieee.std_logic_1164` package, so the existing `report " addr=0x" & to_hstring(...)` debug statements failed Analysis & Synthesis with `Error (10482): object "to_hstring" is used but not declared`. The local helper makes the file self-contained across Questa FE (which provides the builtin) and Quartus 18.1 Standard (which does not). Report bodies are simulation-only, so the function is stripped at synthesis — no electrical impact.
- **Signoff**: `sc_hub_signoff` Quartus project (Arria V `5AGXBA7D4F31C5`, Quartus Prime Standard `18.1`) now contains three revisions, all closing in their final fit:
    - `sc_hub_minimal_live` (AVMM top, `sc_hub_top`) — period `5.818 ns` (~172 MHz). Slow 1100 mV 85 °C setup `+0.083 ns` / hold `+0.274 ns` / MPW `+1.899 ns`. Logic 4 229 ALMs / 6 271 regs.
    - `sc_hub_tiles_minimal` (`sc_hub_tiles_minimal_top`) — period `5.818 ns`. Slow 1100 mV 85 °C setup `+0.382 ns` / hold `+0.295 ns` / MPW `+1.899 ns`. Logic 1 846 ALMs / 2 635 regs.
    - `sc_hub_full_live_axi4` **(new)** (AXI4 top, `sc_hub_top_axi4`, `sc_hub_axi4_core` + `sc_hub_axi4_ooo_handler` only) — period `8.000 ns` (`125 MHz`, the actual slow-control deployment clock; the carried-over `5.818 ns` from the AVMM revision was copy-paste legacy and is too aggressive for the AXI4 path). Slow 1100 mV 85 °C setup `+0.334 ns` / hold `+0.277 ns` / MPW `+2.991 ns`; Slow 0 °C setup `+0.269 ns` / hold `+0.219 ns`; Fast 85 °C setup `+3.759 ns`; Fast 0 °C setup `+3.997 ns`. Logic 3 560 ALMs / 6 026 regs / 9 RAM blocks / 76 800 memory bits. All four corners pass.
- added UVM coverage-closure cases `T376`/`T377`: `csr_diversity` drives the remaining hittable `cmd_cg`/`rsp_cg`/`bus_cg` bins (control-CSR external accesses, multi-mask, domains `8..15`, control-CSR nonincrementing accesses, OoO in-order vs reordered, and atomic lock/mixed bus metadata), while `burn_in` runs a 1200-transaction AVALON stream to exercise long-lived hub/core/FIFO counters without touching RTL
- added `tb/uvm/cov_exclude.do` to persist the verified-unreachable coverage waivers (unsupported `badarg` reply encoding, malformed-reply/header bins not injectable from the harness, bus-side internal/control-CSR bins, fixed-capability `hub_cap_cg` bins, collector-artifact `gap1`, and impossible reply-cross combinations) plus the auxiliary-interface toggle exclusions for `aux_avmm_vif` / `aux_axi4_vif`
- coverage on the merged suite moved from `merged_v4` to the exclusion-applied `merged_v5` as follows: covergroups `80.07% -> 100.00%` on the full summary view; overall toggles `45.44% -> 47.65%` after bench-stub exclusion and burn-in; and RTL-only code coverage (the repo `coverage_report.sh` view) moved from `stmt/branch/toggle = 89.00/83.37/47.23%` to `87.74/81.89/48.71%`
- final non-coverage regression `T371..T377` (7/7) passes with `checks_failed=0 pending_expected=0` on both AVALON and AXI4 legs; scoreboard, ordering checker, bus slave monitor, and packet monitor report zero mismatches
- known gap, not closed in this release: overall toggle coverage still `47.65%` against a `≥85%` aspirational target. The residual deficit is concentrated in `sc_hub_core` (toggle `37.35%` over 17611 bins — dominated by wide `err_count`/`rx_count`/`tx_count` high bits, pipeline-shadow registers, and disabled-feature control nets) and `sc_hub_pkt_rx` (toggle `57.38%`). Closing this to ≥85% is outside the single-burn-in scope and needs a dedicated RTL-toggle campaign with broader error-injection and parameter sweeps; tracked as #14-followup, not gating for covergroup signoff.
- lint waivers manifest added at `lint/waivers.vlog` (33× `vcom-1320` aggregate resolution — WAIVE project-wide, flag `-suppress 1320`) and `lint/waivers.tcl` (14× Quartus `21751` vhdl_input_version directive, 3× `276020` inferred-RAM pass-through on `pkt_rx/pkt_tx/core` FIFOs, 1× `14284/14285/14320` dead-bit elimination on the `pkt_tx` back-pressure RAM `q_b[39:38]`, 1× `15714` VIRTUAL_PIN incomplete I/O — all WAIVE with justification); Layer 3c CDC/RDC/RES/CLK checks unchanged at `74/74 enabled rules passed, 13 disabled` (dormant multi-clock rules)

## 26.6.3.0412

- added UVM coverage-closure cases `T372`–`T375` for full CSR read sweep (including bad offsets and META page rotation), bad-offset CSR writes, OoO-disabled strict dispatch, and controlled soft-reset recovery; added the testbench-only `skip_payload_check` knob in `sc_pkt_seq_item`/scoreboard so unmodeled CSR payloads can still keep header/length/response/address checks strict; refactored `run_uvm_case.sh` to launch arbitrary profiles with latency presets; and raised merged `sc_hub_core` instance coverage from `74.55%/74.44%/47.45%/7.69%` (stmt/branch/cond/expr, `merged_v3`) to `91.22%/85.43%/52.54%/7.69%` (`merged_v4`).

## 26.6.2.0412

- fixed `sc_hub_pkt_rx` dropping long-burst write packets whose preceding
  write had not yet fully drained from the download FIFO. In `WAITING_WRITE_SPACE`
  the recovery rule added in `26.2.30` treated the second appearance of the
  already-latched payload word as an "upstream ignores backpressure"
  violation and invoked `debug_ws_trailer_drop_count++ / drop_packet`. An
  Avalon-style upstream (and the UVM sc_pkt driver) legitimately holds the
  same `data/datak` stable across backpressured cycles, so the rule fired on
  every burst that hit the waiting state — the `burst_len_sweep` 255/256-beat
  writes in `T123` and every retry case that targets post-drain back-to-back
  long bursts were losing the tail packet. The fix compares the incoming word
  against the latched `waiting_word_data/datak` and ignores identical repeats;
  genuinely different non-idle words still drop (buggy-upstream guard
  preserved). This unblocks the 17-case retry batch
  (T123 T301 T302 T303 T304 T317 T320 T321 T323 T326 T327 T337 T344 T345
  T347 T350 T352) without relaxing the pkt-timeout or FIFO-full safeguards.

## 26.6.1.0411

- restored chapter 4.7 reply acknowledge semantics by driving bit `16` high on
  all SC replies while moving the v2 response code into reserved bits `[19:18]`
- updated directed/UVM reply monitors and scoreboards to follow the spec-book
  reply marker instead of the earlier non-spec overlay
- documented that host software may rely on bit `16` for reply detection again,
  but must decode extended error detail from `[19:18]`

## 26.6.0.0411

- formalized the protocol documentation around the Mu3e chapter 4.7 base format
  versus the current `sc_hub v2` overlay
- documented and verified detector-class masking through CSR `0x1C FEB_TYPE`
- documented and verified nonincrementing read/write support on both Avalon-MM
  and AXI4
- promoted long mixed-feature UVM cross cases `T356` and `T357`
- fixed the Avalon UVM bus monitor so nonincrementing commands are modeled as repeated single-beat bus transactions, removing false metadata misses in long `T356` runs
- normalized repository layout so active HDL lives under `rtl/` and top-level
  documentation lives under `doc/`

## 26.5.0.0411

- moved the hub identity contract to the standard Mu3e `UID + META` header
- exposed identity/version/build/date/git/instance metadata through packaging
- aligned verification reference-model identity words with the standardized CSR map

## 26.4.1.0410

- widened the hub external address path from 16 bits to 18 bits
- updated standalone and integrated verification to cover the wider address window

## 26.3.5.0411

- fixed same-cycle RX handoff and final-beat reply padding corner cases
- tightened ordering and atomic dispatch sequencing in the core FSM

## 26.3.1.0331

- added the registered AXI4 RX staging update in the top-level path

## 26.2.0.0331

- split the monolithic hub into separate RX, core, TX, handler, and top-level files
- introduced the standalone verification harness and initial Quartus sign-off flow
