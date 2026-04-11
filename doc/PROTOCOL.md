# SC Hub Protocol Note

## Scope

This note separates the Mu3e base slow-control packet format from the current
`sc_hub v2` overlay that is implemented in RTL.

Base-spec source of truth:

- Mu3e Spec Book, chapter 4.7
- [Command figure](pictures/sc_packet_cmd.png)
- [Reply figure](pictures/sc_packet_ack.png)

Current RTL source of truth:

- `rtl/sc_hub_pkt_rx.vhd`
- `rtl/sc_hub_pkt_tx.vhd`
- `rtl/sc_hub_pkg.vhd`
- `rtl/sc_hub_core.vhd`
- `rtl/sc_hub_axi4_core.vhd`

## 1. Base Mu3e framing

The base framing from the spec is unchanged:

- Word 0 is the preamble and contains `SC`, `FPGA ID`, and `K28.5`
- The final word is always the trailer `K28.4`
- `SC=00/01/10/11` selects incrementing read, incrementing write,
  nonincrementing read, or nonincrementing write

The base-spec behavior of `M/S/T/R` is:

- `R=1`: execute but suppress reply
- `M=1`: MuPix FEB ignores packet
- `S=1`: SciFi FEB ignores packet
- `T=1`: Tile FEB ignores packet

## 2. Current command encoding in RTL

`sc_hub v2` keeps the base packet length and word boundaries, but overlays
reserved bits in the command header.

### Word 1

Current RTL command word 1 layout:

| Bits | Meaning |
|------|---------|
| `[31:30]` | `order_mode` |
| `[29]` | reserved, driven `0` |
| `[28]` | `atomic_flag` |
| `[27]` | `mask_m` |
| `[26]` | `mask_s` |
| `[25]` | `mask_t` |
| `[24]` | `mask_r` |
| `[23:0]` | `start_address` |

This is different from the base figure, where the full word is still treated as
`M/S/T/R + start address` with no ordering or atomic bits.

### Word 2

Current RTL command word 2 layout:

| Bits | Meaning |
|------|---------|
| `[31:28]` | `order_domain` |
| `[27:20]` | `order_epoch` |
| `[19:18]` | `order_scope` |
| `[17:16]` | reserved in commands |
| `[15:0]` | `rw_length` |

`rw_length` is the requested transfer length. Nonincrementing accesses still use
that length; they simply keep the target address constant.

## 3. Current reply encoding in RTL

Current RTL reply word 2 layout:

| Bits | Meaning |
|------|---------|
| `[31:28]` | echoed `order_domain` |
| `[27:20]` | echoed `order_epoch` |
| `[19:18]` | `response` (`00=OK`, `10=SLVERR`, `11=DECERR`) |
| `[17]` | reserved, driven `0` |
| `[16]` | spec-book acknowledge marker, always `1` on replies |
| `[15:0]` | echoed request length |

Important consequences:

- The base reply figure is the authoritative contract.
- Current RTL keeps the spec-book acknowledge marker on bit `16`.
- Successful non-atomic write replies echo the request length but carry no payload.
- Atomic write replies may carry one data word containing the pre-modify read value.
- Error detail lives in reserved bits `[19:18]`.

Software may trust bit `16` as the reply marker again. Software that decodes the
extended response code from `[17:16]` is stale for the current RTL.

## 4. Detector-class masking and `FEB_TYPE`

The execution masks are evaluated against CSR word `0x1C FEB_TYPE`.

| `FEB_TYPE[1:0]` | Meaning |
|-----------------|---------|
| `00` | `ALL` / unknown local class |
| `01` | MuPix |
| `10` | SciFi |
| `11` | Tile |

Current RTL behavior from `pkt_locally_masked_func()` is:

- local `MuPix`: only `M=1` suppresses execution
- local `SciFi`: only `S=1` suppresses execution
- local `Tile`: only `T=1` suppresses execution
- local `ALL`: any of `M/S/T=1` suppresses execution

So `ALL` is conservative, not a broadcast target class. To address all FEB
classes, the sender must leave `M/S/T` clear.

## 5. Nonincrementing access support

Nonincrementing support is implemented end-to-end.

### Avalon-MM

`rtl/sc_hub_avmm_handler.vhd` keeps the address register fixed when
`i_cmd_nonincrement='1'`.

### AXI4

`rtl/sc_hub_axi4_ooo_handler.vhd` drives fixed bursts when the command is
nonincrementing:

- `AWBURST = 2'b00`
- `ARBURST = 2'b00`

The verification harness contains directed and UVM cases that exercise these
paths on both bus families.

## 6. Software compatibility notes

### `online_sc` command emission

`online_sc` already emits all four base SC packet types:

- `PACKET_TYPE_SC_READ`
- `PACKET_TYPE_SC_WRITE`
- `PACKET_TYPE_SC_READ_NONINCREMENTING`
- `PACKET_TYPE_SC_WRITE_NONINCREMENTING`

So nonincrementing access is not blocked by host software.

### `online_sc` reply parsing

`online_sc` `FEBSlowcontrolInterface::SC_reply_packet::IsResponse()` uses
`bit16==1` response detection. That matches the current spec-aligned reply
marker again.

### `MSTR_bar` caveat

`FEBSlowcontrolInterface::FEB_write(..., MSTR_bar, ...)` ORs raw bits into
command word 1.

- Mainline MIDAS FE call sites pass `MSTR_bar=0`, so they do not currently trip
  this mismatch.
- Any caller that still builds `MSTR_bar` according to the base-spec mask bit
  positions must be updated for the v2 overlay, because bit 28 is now
  `atomic_flag` and `M/S/T/R` live in bits `27:24`.

### `online_sc` address and length limits

The `online_sc` transport helpers are still narrower than the packet format:

- `FEBSlowcontrolInterface` rejects `startaddr >= 2^16` and stores parsed reply
  start addresses as `uint16_t`, while the packet field is 24-bit in the spec
  and RTL.
- `FEBSlowcontrolInterface` hard-caps host chunking at `255` words even though
  the SWB `SC_MAIN_LENGTH_REGISTER_W` and the packet `rw_length` field are both
  16-bit wide.

These are software-side compatibility limits, not current RTL limits.

### `online_sc` reply status visibility

`online_sc` trusts bit `16` for reply detection, which is correct for the
current spec-aligned RTL. It does not currently expose the extended response
code carried in reserved bits `[19:18]`, so software can distinguish
request/reply but not `OK` vs `SLVERR` vs `DECERR` without further parsing work.

## 7. Practical guidance

- Use the spec-book figures for base packet boundaries and semantics.
- Use the RTL tables above for actual `sc_hub v2` bit positions.
- Trust bit `16` for reply detection; use reserved bits `[19:18]` for the v2 response code.
- For detector-class broadcast behavior, set local `FEB_TYPE` first and keep
  `M/S/T` clear unless the sender intends to suppress a detector class.
