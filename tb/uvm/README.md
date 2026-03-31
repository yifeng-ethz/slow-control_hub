# UVM Scaffold

This directory contains the UVM 1.2 scaffold from `DV_PLAN.md`:

- UVM sequence item, driver, monitor, agent, env, and test shells
- coverage and scoreboard subscribers
- sequence library shells for single, burst, error, mixed, backpressure, and CSR traffic
- `sc_hub_uvm_tb_top.sv` as the UVM top-level

Current status:
- Compile-ready UVM test classes: `sc_hub_base_test`, `sc_hub_sweep_test`
- No UVM class coverage yet for PERf/EDGE/ERROR category IDs in a complete
  plan matrix.
- UVM sweeps currently exist for core transaction families, but `T123`–`T128`
  and `T350`–`T355` are not yet mapped to full DV_PLAN execution gating.
- Use `scripts/run_uvm.sh` as the preferred run entrypoint
