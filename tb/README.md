# sc_hub Verification Harness

The `tb/` tree is the standalone regression harness for `slow-control_hub`.

- `sim/`: directed SystemVerilog infrastructure and scoreboard
- `uvm/`: promoted UVM environment and sequence-driven regressions
- `scripts/`: run helpers for directed, UVM, PERF, EDGE, and ERROR suites
- `implementation-status.md`: current runnable truth and known blind spots

## Runnable matrix

Current promoted coverage in this tree is:

- directed smoke and directed protocol cases through `T130`
- UVM/promoted sweep cases `T123`–`T128`
- promoted PERF/UVM cases `T300`–`T357`
- long mixed-feature cross cases documented in [DV_CROSS.md](DV_CROSS.md)

The harness is no longer limited to the early `T001`–`T122` snapshot.

## Useful commands

```bash
cd tb
make compile_sim WORK=work_dir BUS_TYPE=AXI4
make run_sim_smoke WORK=work_dir BUS_TYPE=AXI4 TEST_NAME=T129
make compile_uvm WORK=work_uvm BUS_TYPE=AXI4
./scripts/run_uvm_case.sh T341 T356 T357
```

## Script entry points

- `scripts/run_directed.sh [TEST_NAME ...]`: directed and promoted-case dispatcher
- `scripts/run_uvm.sh [UVM_TESTNAME ...]`: raw UVM test launcher
- `scripts/run_uvm_case.sh [Txxx ...]`: promoted DV-plan case dispatcher
- `scripts/run_basic.sh`: basic directed batch
- `scripts/run_perf.sh`: promoted PERF batch, now including `T356` and `T357`
- `scripts/run_edge.sh`: EDGE batch
- `scripts/run_error.sh`: ERROR batch
- `scripts/run_all.sh`: top-level batch wrapper
- `scripts/coverage_report.sh`: coverage reporting helper

## Notes

- The default Questa path in `Makefile` is the local 23.1 tree and prefers the
  ETH Mentor floating license chain when available.
- AXI4 remains supported in standalone RTL simulation even though the packaged
  Platform Designer component is Avalon-MM only.
- Old host software that still assumes the legacy bit-16 write-ack format should
  not be treated as a verification oracle for this hub.
