# sc_hub Verification Harness

This `tb/` tree contains the slow-control_hub regression harness.

- `sim/`: directed/SystemVerilog scaffolding from `DV_PLAN.md`
- `uvm/`: UVM 1.2 scaffold for promoted sweeps
- `scripts/`: run helpers and report helpers
- `implementation-status.md`: explicit coverage and RTL handoff notes

## Implemented today

- Directed harness dispatch and runnable IDs:
  - `smoke_basic`
  - `T001`–`T122`
- UVM harness entry tests:
  - `sc_hub_base_test`
  - `sc_hub_sweep_test`

All remaining categories are still scaffolded in plan docs but not currently runnable in this snapshot.

- `T123`–`T128` (UVM SWP): sequence shells exist but no full matrix wiring.
- `T200`–`T249`: split-buffer, OoO, atomic, and ordering feature blocks are not yet mapped to the runner matrix.
- `T300`–`T349`, `T350`–`T355`: PERF sweeps are not runnable.
- `T400`–`T449`: EDGE cases are not runnable.
- `T500`–`T549`: ERROR cases are not runnable.

## Makefile run entry points

```bash
cd tb
make run_directed TEST_NAME=T001
make run_uvm     UVM_TESTNAME=sc_hub_base_test
make run_basic   BUS_TYPE=AXI4
make run_all
make coverage_report
```

## Script matrix

- `scripts/run_directed.sh [TEST_NAME ...]` dispatches directed tests (`sc_hub_tb_top.sv`).
- `scripts/run_uvm.sh [UVM_TESTNAME ...]` dispatches UVM tests.
- `scripts/run_basic.sh` runs the currently implemented directed default set (`T001`–`T122`).
- `scripts/run_perf.sh` currently reports PERF blockers and exits cleanly.
- `scripts/run_edge.sh` currently reports EDGE blockers and exits cleanly.
- `scripts/run_error.sh` currently reports ERROR blockers and exits cleanly.
- `scripts/run_all.sh` runs `run_basic`, `run_uvm`, `run_perf`, `run_edge`, `run_error` and summarizes step outcomes.
- `scripts/coverage_report.sh` prepares/prints coverage reporting commands.

## Handoff status

See [`implementation-status.md`](implementation-status.md) for the current
harness-to-plan gap, boundary-specific blockers, and RTL file candidates that
need handoff.
