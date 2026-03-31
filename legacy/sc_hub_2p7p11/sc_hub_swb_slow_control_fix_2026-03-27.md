# SWB Slow-Control Packet Reachability Fix Summary

Date checked: 2026-03-27

## Conclusion

The fix for the "slow-control packet from SWB does not reach the FEB" issue is not a same-day RTL change inside the `sc_hub` IP sources under `fe_board/ip_mu3e/sc_hub`.

The active fix is in the FE SciFi integration around `sc_hub`, mainly in:

- [debug_sc_system.qsys](/home/yifeng/packages/online_dpv2/online/fe_board/fe_scifi/debug_sc_system.qsys#L1448)
- [top.vhd](/home/yifeng/packages/online_dpv2/online/fe_board/fe_scifi/top.vhd#L204)

No committed Git change was found on 2026-03-27 for the relevant paths. This summary is therefore based on the current uncommitted worktree.

## What Changed

The downlink path is now wired directly to the `sc_hub` packet-downlink conduit:

- [debug_sc_system.qsys](/home/yifeng/packages/online_dpv2/online/fe_board/fe_scifi/debug_sc_system.qsys#L1448): `download_sc`
- [debug_sc_system.qsys](/home/yifeng/packages/online_dpv2/online/fe_board/fe_scifi/debug_sc_system.qsys#L1450): `internal="sc_hub.hub_sc_packet_downlink"`

The uplink return path is now taken from the merger output instead of the old upload FIFO:

- [debug_sc_system.qsys](/home/yifeng/packages/online_dpv2/online/fe_board/fe_scifi/debug_sc_system.qsys#L1500): `upload_sc`
- [debug_sc_system.qsys](/home/yifeng/packages/online_dpv2/online/fe_board/fe_scifi/debug_sc_system.qsys#L1502): `internal="data_sc_merger.out"`

The merger is now enabled and reduced to two inputs, so the `sc_hub` uplink can be merged back into the FEB upload stream:

- [debug_sc_system.qsys](/home/yifeng/packages/online_dpv2/online/fe_board/fe_scifi/debug_sc_system.qsys#L1511): `data_sc_merger` enabled
- [debug_sc_system.qsys](/home/yifeng/packages/online_dpv2/online/fe_board/fe_scifi/debug_sc_system.qsys#L1514): `numInputInterfaces = 2`
- [debug_sc_system.qsys](/home/yifeng/packages/online_dpv2/online/fe_board/fe_scifi/debug_sc_system.qsys#L2130): `start="sc_hub.hub_sc_packet_uplink"`
- [debug_sc_system.qsys](/home/yifeng/packages/online_dpv2/online/fe_board/fe_scifi/debug_sc_system.qsys#L2131): `end="data_sc_merger.in1"`

The `sc_hub` instance itself is the newer generated IP with packet-transfer scheduling enabled:

- [debug_sc_system.qsys](/home/yifeng/packages/online_dpv2/online/fe_board/fe_scifi/debug_sc_system.qsys#L1927): `version="25.0.808"`
- [debug_sc_system.qsys](/home/yifeng/packages/online_dpv2/online/fe_board/fe_scifi/debug_sc_system.qsys#L1930): `INVERT_RD_SIG = true`
- [debug_sc_system.qsys](/home/yifeng/packages/online_dpv2/online/fe_board/fe_scifi/debug_sc_system.qsys#L1931): `SCHEDULER_USE_PKT_TRANSFER = true`

Compared to the previous committed `debug_sc_system.qsys`, the old `download_fifo` and `upload_fifo` staging around `sc_hub` were removed and replaced by the direct `sc_hub` downlink plus `data_sc_merger` uplink path.

## Top-Level Wiring That Matches The Fix

The FE top-level `feb_system` component interface was updated to use explicit `download_sc_*` ports:

- [top.vhd](/home/yifeng/packages/online_dpv2/online/fe_board/fe_scifi/top.vhd#L206): `cclk156_clk`
- [top.vhd](/home/yifeng/packages/online_dpv2/online/fe_board/fe_scifi/top.vhd#L207): `download_sc_data`
- [top.vhd](/home/yifeng/packages/online_dpv2/online/fe_board/fe_scifi/top.vhd#L208): `download_sc_datak`
- [top.vhd](/home/yifeng/packages/online_dpv2/online/fe_board/fe_scifi/top.vhd#L209): `download_sc_ready`

Those ports are now fed from the firefly receive side:

- [top.vhd](/home/yifeng/packages/online_dpv2/online/fe_board/fe_scifi/top.vhd#L660): `download_sc_data => ffly_rx_data(31 downto 0)`
- [top.vhd](/home/yifeng/packages/online_dpv2/online/fe_board/fe_scifi/top.vhd#L661): `download_sc_datak => ffly_rx_datak(3 downto 0)`
- [top.vhd](/home/yifeng/packages/online_dpv2/online/fe_board/fe_scifi/top.vhd#L662): `download_sc_ready => open`

This is the concrete top-level connection that makes the SWB slow-control packets physically arrive at the `sc_hub` downlink interface inside the control-path subsystem.

## What Did Not Change

The `sc_hub` IP source directory itself is clean in the current worktree:

- `fe_board/ip_mu3e/sc_hub/sc_hub.vhd`
- `fe_board/ip_mu3e/sc_hub/sc_hub_top.vhd`
- `fe_board/ip_mu3e/sc_hub/sc_hub_hw.tcl`

So the current fix is not "a new edit in `sc_hub.vhd` today". It is an integration fix around the already updated `sc_hub` IP.

## TB Folder Check

I also checked the new `tb/scifi_dp` area because it was suspected that the fix might exist there only.

The only FEB-system file there is a DV plan:

- [DV_PLAN.md](/home/yifeng/packages/online_dpv2/online/fe_board/fe_scifi/tb/scifi_dp/feb_system/DV_PLAN.md#L1)

That file documents scope and architecture, including the control-path subsystem and slow control:

- [DV_PLAN.md](/home/yifeng/packages/online_dpv2/online/fe_board/fe_scifi/tb/scifi_dp/feb_system/DV_PLAN.md#L3)
- [DV_PLAN.md](/home/yifeng/packages/online_dpv2/online/fe_board/fe_scifi/tb/scifi_dp/feb_system/DV_PLAN.md#L26)

I did not find a TB-only implementation change that fixes the SWB-to-`sc_hub` path. The actual functional fix is in the integration files listed above.

## Practical Reading

The likely failure before this change was:

1. SWB data entered the FE through the firefly receive path.
2. The control-path subsystem still used FIFO-based staging around `sc_hub`.
3. The direct `sc_hub` packet-downlink and packet-uplink interfaces were not the active exported path.

The likely fix now is:

1. Firefly RX is wired into `download_sc_*` at top level.
2. `download_sc_*` enters `sc_hub.hub_sc_packet_downlink` directly.
3. `sc_hub.hub_sc_packet_uplink` is merged into `data_sc_merger`.
4. `data_sc_merger.out` becomes the exported `upload_sc` stream back toward the uplink path.
