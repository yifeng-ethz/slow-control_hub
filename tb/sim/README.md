# Directed TB Scaffold

This directory contains the directed/SystemVerilog bench harness from `DV_PLAN.md`:

- `sc_hub_tb_top.sv` dispatches direct test cases by `+TEST_NAME`
- Shared types and helper tasks in `sc_hub_pkg.sv`
- `sc_pkt_driver.sv` + `sc_pkt_monitor.sv` for packet protocol stimulus/observe
- AVMM/AXI4 BFMs for bus-path validation
- scoreboard and assertion shells for functional coverage hooks

Current status:
- Implemented and dispatchable tests: `smoke_basic`, `T001`–`T122`.
- Remaining IDs in `DV_*` docs are scaffolded but not runnable through
  `TEST_NAME` in this snapshot.
- Missing categories:
  - `T200`–`T249` (split-buffer, OoO, atomic, ordering feature blocks).
  - `T300`+ (PERF), `T400`+ (EDGE), `T500`+ (ERROR).

Preferred run path is through the repository scripts:
- `scripts/run_directed.sh`
- `scripts/run_basic.sh`
- `make run_directed TEST_NAME=<id>` (makes compile/run one-shot)
