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
- promoted PERF/UVM cases `T300`–`T368`
- long mixed-feature cross cases documented in [DV_CROSS.md](DV_CROSS.md)

The harness is no longer limited to the early `T001`–`T122` snapshot.

## Useful commands

```bash
cd tb
make compile_sim WORK=work_dir BUS_TYPE=AXI4
make run_sim_smoke WORK=work_dir BUS_TYPE=AXI4 TEST_NAME=T129
make compile_uvm WORK=work_uvm BUS_TYPE=AXI4
./scripts/run_uvm_case.sh T341 T356 T357
./scripts/run_cov_closure.sh
```

## Script entry points

- `scripts/run_directed.sh [TEST_NAME ...]`: directed and promoted-case dispatcher
- `scripts/run_uvm.sh [UVM_TESTNAME ...]`: raw UVM test launcher
- `scripts/run_uvm_case.sh [Txxx|Pxxx|CROSS-xxx ...]`: promoted UVM/performance case dispatcher
- Canonical IDs outside the implemented subset resolve as `planned but not implemented`; this is intentional until each plan row gets a runnable alias
- `scripts/run_basic.sh`: basic directed batch
- `scripts/run_perf.sh`: promoted PERF batch, now including `T356`, `T357`, `T367`, and `T368`
- `scripts/run_edge.sh`: EDGE batch
- `scripts/run_error.sh`: ERROR batch
- `scripts/run_all.sh`: top-level batch wrapper
- `scripts/coverage_report.sh`: coverage reporting helper
- `scripts/run_cov_closure.sh`: promoted closure runset that emits per-case trends and a merged suite trend
- `make run_vcd TEST_NAME=<directed_case>`: dump VCD for a directed case
- `make run_uvm_vcd UVM_TESTNAME=<uvm_test>`: dump VCD for a UVM case
- `scripts/publish_wave_case.py`: register a published waveform case package under `tb/waves/cases/`
- `scripts/build_wave_manifest.py`: rebuild `tb/waves/manifest.json` for `tb/waves/index.html`
- `make wave_index`: rebuild the waveform manifest from the checked-in case packages

## Notes

- The supported simulator flow is the shared QuestaOne 2026 setup from
  `../../scripts/questa_one.mk` and `../../scripts/questa_one_env.sh`. On this
  host that resolves to `/data1/questaone_sim/questasim` with the ETH floating
  license variables exported by the shared wrapper.
- AXI4 remains supported in standalone RTL simulation even though the packaged
  Platform Designer component is Avalon-MM only.
- Old host software that still assumes the legacy bit-16 write-ack format should
  not be treated as a verification oracle for this hub.
