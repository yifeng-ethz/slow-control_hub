# Changelog

## 26.6.1.0411

- restored chapter 4.7 reply acknowledge semantics by driving bit `16` high on
  all SC replies while moving the v2 response code into reserved bits `[19:18]`
- updated directed/UVM reply monitors and scoreboards to follow the spec-book
  reply marker instead of the earlier non-spec overlay
- documented that host software may rely on bit `16` for reply detection again,
  but must decode extended error detail from `[19:18]`

## 26.6.0.0411

- formalized the protocol documentation around the Mu3e chapter 4.7 base format
  versus the current `sc_hub v2` overlay
- documented and verified detector-class masking through CSR `0x1C FEB_TYPE`
- documented and verified nonincrementing read/write support on both Avalon-MM
  and AXI4
- promoted long mixed-feature UVM cross cases `T356` and `T357`
- fixed the Avalon UVM bus monitor so nonincrementing commands are modeled as repeated single-beat bus transactions, removing false metadata misses in long `T356` runs
- normalized repository layout so active HDL lives under `rtl/` and top-level
  documentation lives under `doc/`

## 26.5.0.0411

- moved the hub identity contract to the standard Mu3e `UID + META` header
- exposed identity/version/build/date/git/instance metadata through packaging
- aligned verification reference-model identity words with the standardized CSR map

## 26.4.1.0410

- widened the hub external address path from 16 bits to 18 bits
- updated standalone and integrated verification to cover the wider address window

## 26.3.5.0411

- fixed same-cycle RX handoff and final-beat reply padding corner cases
- tightened ordering and atomic dispatch sequencing in the core FSM

## 26.3.1.0331

- added the registered AXI4 RX staging update in the top-level path

## 26.2.0.0331

- split the monolithic hub into separate RX, core, TX, handler, and top-level files
- introduced the standalone verification harness and initial Quartus sign-off flow
