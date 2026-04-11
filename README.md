# Slow Control Hub Mu3E IP

8B10B slow-control bridge for Mu3e front-end boards. The hub accepts SC packets
from the SWB downlink, executes Avalon-MM or AXI4 transactions on the FEB, and
emits packetized replies on the uplink.

**Version:** 26.6.1.0411
**RTL tops:** `rtl/sc_hub_top.vhd` (Avalon-MM), `rtl/sc_hub_top_axi4.vhd` (AXI4)
**Platform Designer group:** Mu3e Control Plane/Modules

## Entry Points

- [Protocol note](doc/PROTOCOL.md)
- [Software mismatch note](doc/SOFTWARE_MISMATCH.md)
- [Host API standard](doc/SC_HOST_API_STANDARD.md)
- [Verification signoff](doc/VERIFICATION_SIGNOFF.md)
- [Synthesis signoff](doc/SYNTHESIS_SIGNOFF.md)
- [Changelog](doc/CHANGELOG.md)
- [RTL plan](doc/RTL_PLAN.md)
- [Verification README](tb/README.md)
- [Verification plan](tb/DV_PLAN.md)

## Architecture

```text
SWB SC downlink
  -> rtl/sc_hub_pkt_rx.vhd
  -> rtl/sc_hub_core.vhd or rtl/sc_hub_axi4_core.vhd
  -> rtl/sc_hub_avmm_handler.vhd / rtl/sc_hub_axi4_handler.vhd / rtl/sc_hub_axi4_ooo_handler.vhd
  -> rtl/sc_hub_pkt_tx.vhd
  -> SWB SC uplink
```

The internal CSR window lives at `0xFE80..0xFE9F` and never leaves the hub.
External accesses are translated to Avalon-MM or AXI4 bus transactions.

## Packet Contract

The Mu3e Spec Book chapter 4.7 figures remain the authoritative base framing:

- Command figure: [doc/pictures/sc_packet_cmd.png](doc/pictures/sc_packet_cmd.png)
- Reply figure: [doc/pictures/sc_packet_ack.png](doc/pictures/sc_packet_ack.png)

`sc_hub v2` keeps the base framing words but reuses only reserved bits for
ordering, atomic, and error metadata.

### Supported command types

- `SC=00`: incrementing read
- `SC=01`: incrementing write
- `SC=10`: nonincrementing read
- `SC=11`: nonincrementing write

### Detector-class and reply masks

The base-spec `M/S/T/R` semantics are implemented in RTL.

- `R=1`: execute locally but suppress the reply packet
- `M=1`: MuPix FEBs ignore the packet
- `S=1`: SciFi FEBs ignore the packet
- `T=1`: Tile FEBs ignore the packet

The local detector class is selected by CSR word `0x1C FEB_TYPE`:

- `00`: ALL / unknown local class
- `01`: MuPix
- `10`: SciFi
- `11`: Tile

Important: `FEB_TYPE=ALL` is conservative. If any of `M/S/T` is set while the
local type is still `ALL`, the hub ignores the packet. To target all FEB types,
leave `M/S/T` clear.

### v2 overlay relative to the base figure

Command word 1 in current RTL is:

- `[31:30]` `order_mode`
- `[29]` reserved `0`
- `[28]` `atomic_flag`
- `[27:24]` `M/S/T/R`
- `[23:0]` `start_address`

Command word 2 in current RTL is:

- `[31:28]` `order_domain`
- `[27:20]` `order_epoch`
- `[19:18]` `order_scope`
- `[17:16]` reserved in commands
- `[15:0]` `rw_length`

Reply word 2 in current RTL is:

- `[31:28]` `order_domain`
- `[27:20]` `order_epoch`
- `[19:18]` `response` (`00=OK`, `10=SLVERR`, `11=DECERR`)
- `[17]` reserved `0`
- `[16]` spec-book acknowledge marker, always `1` on replies
- `[15:0]` echoed request length

Compatibility note: successful non-atomic write replies still echo the original
request length in the header but carry no payload, exactly as shown by the spec
figure. The distinguishers are packet type plus the reply acknowledge marker on
bit `16`, not “payload words equals echoed length”.

### Nonincrementing support

Nonincrementing commands are implemented and verified on both bus variants.

- `rtl/sc_hub_avmm_handler.vhd` keeps the word address fixed across the burst
- `rtl/sc_hub_axi4_ooo_handler.vhd` drives `AWBURST/ARBURST = FIXED`
- The directed/UVM regressions include nonincrementing traffic in both AVMM and AXI4 flows

## Internal CSR Window

The hub-owned CSR words are:

| Word | Name | Access | Meaning |
|------|------|--------|---------|
| `0x00` | `UID` | RO | Immutable Mu3e IP identifier, default `0x53434842` (`"SCHB"`) |
| `0x01` | `META` | RW/RO | Page selector on write, selected page on read (`VERSION`, `DATE`, `GIT`, `INSTANCE_ID`) |
| `0x02` | `CTRL` | RW | Enable, diag clear, soft reset |
| `0x03` | `STATUS` | RO | Busy/error summary and FIFO/bus state |
| `0x04` | `ERR_FLAGS` | RW1C | Sticky overflow, timeout, packet-drop, and bus-error flags |
| `0x05` | `ERR_COUNT` | RO | Saturating error counter |
| `0x06` | `SCRATCH` | RW | Software scratch register |
| `0x07` | `GTS_SNAP_LO` | RO | Timestamp snapshot low |
| `0x08` | `GTS_SNAP_HI` | RO | Timestamp snapshot high; reading captures a fresh snapshot |
| `0x09` | `FIFO_CFG` | RO | FIFO configuration summary |
| `0x0A` | `FIFO_STATUS` | RO | FIFO state summary |
| `0x0B` | `DOWN_PKT_CNT` | RO | Download packet occupancy summary bit |
| `0x0C` | `UP_PKT_CNT` | RO | Reply FIFO packet count |
| `0x0D` | `DOWN_USEDW` | RO | Download FIFO used words |
| `0x0E` | `UP_USEDW` | RO | Reply FIFO used words |
| `0x0F` | `EXT_PKT_RD` | RO | External read packet counter |
| `0x10` | `EXT_PKT_WR` | RO | External write packet counter |
| `0x11` | `EXT_WORD_RD` | RO | External read word counter |
| `0x12` | `EXT_WORD_WR` | RO | External write word counter |
| `0x13` | `LAST_RD_ADDR` | RO | Last external read address |
| `0x14` | `LAST_RD_DATA` | RO | Last external read data |
| `0x15` | `LAST_WR_ADDR` | RO | Last external write address |
| `0x16` | `LAST_WR_DATA` | RO | Last external write data |
| `0x17` | `PKT_DROP_CNT` | RO | Packet drop counter |
| `0x18` | `OOO_CTRL` | RW | AXI4 OoO enable shadow |
| `0x19` | `ORD_DRAIN_CNT` | RO | Ordering drain counter |
| `0x1A` | `ORD_HOLD_CNT` | RO | Ordering hold counter |
| `0x1B` | `DBG_DROP_DETAIL` | RO | Last packet-drop reason detail |
| `0x1C` | `FEB_TYPE` | RW | Local FEB class used by `M/S/T` masking |
| `0x1F` | `HUB_CAP` | RO | Capability summary word |

## Software Notes

Mainline `online_sc` command emission already supports the base nonincrementing
SC types, and its reply detector can trust bit `16` again. The remaining
software mismatches are:

- `FEBSlowcontrolInterface::FEB_write(..., MSTR_bar, ...)` ORs raw bits into
  command word 1. Mainline MIDAS FE paths pass `MSTR_bar=0`, but any caller that
  uses legacy base-spec mask bit positions must be updated for the v2 overlay.
- `FEBSlowcontrolInterface` still rejects `startaddr >= 2^16` and parses reply
  start address as `uint16_t`, while the protocol and RTL use a 24-bit start
  address field.
- `FEBSlowcontrolInterface` still caps host chunking at `255` words even though
  the SC protocol length field and SWB `SC_MAIN_LENGTH_REGISTER_W` are both
  16-bit wide.
- `online_sc` host code treats the reply marker as a yes/no bit only. It does
  not surface the v2 extended response code carried in reserved bits `[19:18]`.

## Repository Layout

```text
slow-control_hub/
  doc/        protocol, plans, changelog, figures
  rtl/        active VHDL sources
  tb/         directed + UVM verification harness
  syn/        standalone Quartus sign-off projects
  hw_tcl/     Platform Designer packaging helpers
  tlm/        transaction-level modeling support
  legacy/     archived historical sources
```

## Quick Start

### Directed simulation

```bash
cd tb
make compile_sim WORK=work_dir BUS_TYPE=AXI4
make run_sim_smoke WORK=work_dir BUS_TYPE=AXI4 TEST_NAME=T129
make run_sim_smoke WORK=work_dir BUS_TYPE=AXI4 TEST_NAME=T130
```

### UVM regression

```bash
cd tb
make compile_uvm WORK=work_uvm BUS_TYPE=AXI4
./scripts/run_uvm_case.sh T341 T356 T357
```

### Standalone timing sign-off

```bash
cd syn/quartus
quartus_sh --flow compile sc_hub_minimal_live -c sc_hub_minimal_live
```
