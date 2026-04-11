# SC Hub Software Mismatch Note

## Scope

This note tracks host-software limitations and unsafe assumptions relative to the
current `sc_hub v2` RTL and the Mu3e Spec Book chapter 4.7 packet contract.

Authoritative RTL/protocol references:

- `rtl/sc_hub_pkt_rx.vhd`
- `rtl/sc_hub_pkt_tx.vhd`
- `rtl/sc_hub_pkg.vhd`
- `doc/PROTOCOL.md`

Primary affected software tree:

- `online_sc/online/switching_pc/slowcontrol/FEBSlowcontrolInterface.*`
- `online_sc/online/switching_pc/midas_fe/switch_fe.cpp`

## Summary

Current `sc_hub` RTL is stricter and wider than the mainline `online_sc` helper
stack in several places:

- packet start address is 24-bit in RTL, while `online_sc` still enforces 16-bit
- packet/request length is 16-bit in RTL and in the SWB MMIO register, while
  `online_sc` hard-caps bursts to 255 words
- `MSTR_bar` is still a raw software overlay into command word 1 and can collide
  with the current v2 reserved-bit reuse
- reply parsing detects request-vs-reply correctly via bit `16`, but software
  still does not expose the v2 extended response code in reserved bits `[19:18]`

These are software compatibility limits or observability gaps. They are not the
current standalone RTL limit.

## 1. Address Width Mismatch

Current RTL command word 1 uses a 24-bit start address.

Relevant RTL:

- `rtl/sc_hub_pkt_rx.vhd:562`

The `online_sc` transport helper still rejects addresses above 16 bits and
stores the parsed reply start address as `uint16_t`.

Relevant software:

- `online_sc/online/switching_pc/slowcontrol/FEBSlowcontrolInterface.cpp:64`
- `online_sc/online/switching_pc/slowcontrol/FEBSlowcontrolInterface.h:92`
- `online_sc/online/switching_pc/midas_fe/switch_fe.cpp:3280`
- `online_sc/online/switching_pc/midas_fe/switch_fe.cpp:3367`

Impact:

- valid `sc_hub` addresses above `0xFFFF` cannot be issued from the current
  helper stack
- valid replies above `0xFFFF` would be truncated in the helper-side parsed
  start-address accessor

Required software fix:

- widen helper validation and parsed reply accessors to 24-bit start address
- remove hard-coded 16-bit assumptions from MIDAS FE checks and SC helper APIs

## 2. Burst Length Limit Mismatch

Current `sc_hub` packet length is 16-bit in command/reply word 2, and the SWB
MMIO `SC_MAIN_LENGTH_REGISTER_W` is also 16-bit wide.

The helper stack still hard-caps transactions to 255 words.

Relevant software:

- `online_sc/online/switching_pc/slowcontrol/FEBSlowcontrolInterface.cpp:17`
- `online_sc/online/switching_pc/slowcontrol/FEBSlowcontrolInterface.cpp:88`
- `online_sc/online/switching_pc/midas_fe/switch_fe.cpp:118`
- `online_sc/online/switching_pc/midas_fe/switch_fe.cpp:627`
- `online_sc/online/switching_pc/midas_fe/switch_fe.cpp:3285`
- `online_sc/online/switching_pc/midas_fe/switch_fe.cpp:3372`
- `online_sc/online/switching_pc/midas_fe/switch_fe.cpp:3603`

Impact:

- host software silently underuses the protocol width
- large valid accesses are either rejected or forcibly split at 255 words
- the current limit is software policy, not protocol truth

Important nuance:

- the existing 255-word cap may still be a practical SWB-path workaround in some
  deployed systems
- that does not make it a protocol limit, and it should be documented as a host
  policy until proven otherwise on the integrated path

Required software fix:

- promote chunking policy to an explicit configurable transport limit
- separate protocol maximum from conservative deployment default
- remove comments that describe the SC length field itself as 8-bit

## 3. `MSTR_bar` Raw Overlay Risk

`online_sc` still ORs a raw caller-provided mask into command word 1.

Relevant software:

- `online_sc/online/switching_pc/slowcontrol/FEBSlowcontrolInterface.cpp:102`

Current `sc_hub v2` command word 1 uses:

- `[31:30]` ordering mode
- `[28]` atomic flag
- `[27:24]` `M/S/T/R`
- `[23:0]` start address

Relevant RTL:

- `rtl/sc_hub_pkt_rx.vhd:557`

Impact:

- any caller that still builds `MSTR_bar` from an older raw bit-position model
  can corrupt ordering, atomic, detector-mask, or address bits
- this can create false protocol failures that appear to be RTL bugs

Current safety status:

- mainline MIDAS FE call sites use `MSTR_bar=0`
- the raw-overlay API remains unsafe for other callers and for future reuse

Required software fix:

- replace raw `MSTR_bar` with a typed command-builder API
- encode `M/S/T/R`, atomic, and ordering fields by named fields rather than raw
  OR masks

## 4. Reply Status Visibility Gap

Current reply marker is spec-aligned again on bit `16`.

Relevant RTL and software:

- `rtl/sc_hub_pkt_tx.vhd:223`
- `online_sc/online/switching_pc/slowcontrol/FEBSlowcontrolInterface.h:90`

But the helper stack still does not expose the extended v2 response code in
reserved bits `[19:18]`:

- `00 = OK`
- `10 = SLVERR`
- `11 = DECERR`

Impact:

- software can distinguish request from reply
- software cannot report the richer hub-side response classification without
  further parsing

Required software fix:

- add an explicit parsed response-code field to the SC reply object
- propagate that field into MIDAS FE status mapping and CLI diagnostics

## 5. Nonincrementing Access Status

Nonincrementing accesses are supported in RTL and already emitted by
`online_sc`.

Relevant RTL:

- `rtl/sc_hub_pkg.vhd:284`
- `rtl/sc_hub_avmm_handler.vhd:127`
- `rtl/sc_hub_axi4_ooo_handler.vhd:160`

This is not a current mismatch.

The real software problem is narrower:

- nonincrementing is available
- the surrounding helper API still carries the width and observability problems
  listed above

## Practical Guidance

- Treat the current `255` burst cap as software policy, not protocol truth.
- Do not use raw `MSTR_bar` composition for new callers.
- Do not assume 16-bit SC address space when targeting `sc_hub v2`.
- If a host-side failure appears protocol-related, first check whether software
  truncated address or length before suspecting RTL.
