# sc_hub TB Implementation Status

## Runnable snapshot

| Harness | Runnable IDs / flows | Current note |
|---|---|---|
| Directed | `smoke_basic`, directed protocol cases through `T130` | Includes internal CSR, masking, malformed-packet, and nonincrementing directed checks |
| UVM promoted | `T123`–`T128`, `T300`–`T357` via `scripts/run_uvm_case.sh` | Includes promoted ordering, atomic, throughput, and mixed long-run cases |
| PERF helper | `scripts/run_perf.sh` | Includes `T356` and `T357` in the promoted batch |
| Static checks | `T548`, `T549` | Enforced by `scripts/check_static_cases.py` |

## Remaining blind spots

- No randomized UVM matrix yet for `M/S/T` masking versus local CSR `FEB_TYPE`.
- The packaged Platform Designer component is still Avalon-MM only; AXI4 exists
  as a standalone RTL top-level, not as a generated PD variant.
- Legacy host software that only checks reply bit `16` can detect a reply again, but
  it still cannot see the extended error code in reserved bits `[19:18]`.
- The `online_sc` `MSTR_bar` API is raw-bit based and must not be reused against
  the v2 overlay without an explicit field-definition wrapper.

## Recommended bring-up path

1. Use directed tests for protocol and malformed-frame corner cases.
2. Use promoted UVM cases for long mixed traffic and ordering/atomic interactions.
3. Use the standalone sign-off Quartus project under `syn/quartus/` for timing.
4. Treat old host-side parsers as diagnostic hints only, not correctness oracles.
