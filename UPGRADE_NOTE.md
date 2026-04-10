# Upgrade Note — v26.5.0 Standard CSR Identity Header

**Date:** 2026-04-11
**Scope:** RTL contract change affecting testbench and synthesis wrappers.

---

## Summary of RTL Changes

The CSR words 0 and 1 have been replaced with the standard Mu3e IP identity
header (same contract as `histogram_statistics_v2`).

### Package (`sc_hub_pkg.vhd`)

| Before | After | Notes |
|--------|-------|-------|
| `HUB_ID_CONST = x"53480000"` | `HUB_UID_CONST = x"53434842"` | Renamed + new value (ASCII "SCHB") |
| `HUB_CSR_WO_ID_CONST` | `HUB_CSR_WO_UID_CONST` | Constant renamed |
| `HUB_CSR_WO_VERSION_CONST` | `HUB_CSR_WO_META_CONST` | Constant renamed |
| `HUB_VERSION_YY_CONST` | *(removed)* | Now a generic (`VERSION_MAJOR_G`) |
| `HUB_VERSION_MAJOR_CONST` | *(removed)* | Now a generic (`VERSION_MINOR_G`) |
| `HUB_VERSION_PRE_CONST` | *(removed)* | Now a generic (`VERSION_PATCH_G`) |
| `HUB_VERSION_MONTH_CONST` | *(removed)* | Now a generic (`BUILD_G`) |
| `HUB_VERSION_DAY_CONST` | *(removed)* | Now a generic (`BUILD_G`) |

### Core (`sc_hub_core.vhd`, `sc_hub_axi4_core.vhd`)

- **New generics:** `IP_UID_G`, `VERSION_MAJOR_G`, `VERSION_MINOR_G`,
  `VERSION_PATCH_G`, `BUILD_G`, `VERSION_DATE_G`, `VERSION_GIT_G`,
  `INSTANCE_ID_G`.
- **New signal:** `meta_page_sel : std_logic_vector(1 downto 0)` — page
  selector for the META read-mux (reset to `"00"`).
- **Word 0 read:** returns `IP_UID_G` (was `HUB_ID_CONST`).
- **Word 0 write:** no-op (read-only UID).
- **Word 1 read:** META mux — returns VERSION/DATE/GIT/INSTANCE_ID based on
  `meta_page_sel` (was `pack_version_func(...)` with old encoding).
- **Word 1 write:** stores `writedata(1:0)` into `meta_page_sel` (was no-op).

### Top (`sc_hub_top.vhd`, `sc_hub_top_axi4.vhd`)

- **New generics:** `IP_UID`, `VERSION_MAJOR`, `VERSION_MINOR`,
  `VERSION_PATCH`, `BUILD`, `VERSION_DATE`, `VERSION_GIT`, `INSTANCE_ID`
  (passed through to core).

### Version Encoding Change

| Field | Old encoding | New encoding |
|-------|-------------|-------------|
| Word 1 `[31:24]` | `version_yy` (8-bit) | `VERSION_MAJOR` (8-bit) |
| Word 1 `[23:18]` | `version_major` (6-bit) | `VERSION_MINOR[7:2]` |
| Word 1 `[17:16]` | `version_pre` (2-bit) | `VERSION_MINOR[1:0]` (note: full 8-bit) |
| Word 1 `[23:16]` | *(split above)* | `VERSION_MINOR` (8-bit) |
| Word 1 `[15:8]` | `version_month` (8-bit) | `VERSION_PATCH[3:0]` in `[15:12]` |
| Word 1 `[7:0]` | `version_day` (8-bit) | `BUILD[11:0]` in `[11:0]` |

New layout (META page 0 = VERSION):
```
[31:24] VERSION_MAJOR  (8 bits)
[23:16] VERSION_MINOR  (8 bits)
[15:12] VERSION_PATCH  (4 bits)
[11:0]  BUILD          (12 bits)
```

---

## Files Requiring Update

### Testbench — `tb/sim/sc_hub_ref_model.sv`

The reference model has hardcoded constants that must be updated:

```systemverilog
// OLD:
localparam logic [31:0] HUB_ID_CONST             = 32'h5348_0000;
localparam int unsigned HUB_VERSION_YY_CONST     = 26;
localparam int unsigned HUB_VERSION_MAJOR_CONST  = 2;
localparam int unsigned HUB_VERSION_PRE_CONST    = 0;
localparam int unsigned HUB_VERSION_MONTH_CONST  = 3;
localparam int unsigned HUB_VERSION_DAY_CONST    = 31;

// NEW:
localparam logic [31:0] HUB_UID_CONST            = 32'h5343_4842;  // "SCHB"
localparam int unsigned VERSION_MAJOR             = 26;
localparam int unsigned VERSION_MINOR             = 5;
localparam int unsigned VERSION_PATCH             = 0;
localparam int unsigned BUILD                     = 12'h411;
localparam int unsigned VERSION_DATE              = 32'h2026_0411;
localparam int unsigned VERSION_GIT               = 0;
localparam int unsigned INSTANCE_ID               = 0;
```

The CSR read model function must be updated:

```systemverilog
// OLD:
18'h0000: return HUB_ID_CONST;
18'h0001: return pack_version(HUB_VERSION_YY_CONST, ...);

// NEW:
18'h0000: return HUB_UID_CONST;
18'h0001: return meta_mux(meta_page_sel);  // implement META page logic
```

Add a `meta_page_sel` state variable and update the CSR write model:

```systemverilog
// NEW write case:
18'h0000: ;  // UID read-only, ignore
18'h0001: meta_page_sel = wdata[1:0];
```

### Testbench — `tb/uvm/sc_hub_scoreboard_uvm.sv`

Same changes as the standalone ref model above.  The scoreboard imports
constants from `sc_hub_ref_model_pkg` — update that package.

### Synthesis — `syn/quartus/sc_hub_tiles_minimal_top.vhd`

No mandatory changes.  The synthesis wrapper uses default generics, which
now include the identity generics with correct defaults.  However, the
`avm_hub_address` width (16-bit) does not match the core's 18-bit port.
This is a pre-existing issue unrelated to the identity header change.

### Tests Affected

Any test that checks the CSR read value of words 0 or 1 will fail:

- **Word 0:** expected `0x53480000`, now returns `0x53434842`.
- **Word 1:** expected old `pack_version` encoding, now returns new
  VERSION/MINOR/PATCH/BUILD encoding (and is page-selectable via write).

Tests that write to word 1 will now change the META page selector instead
of being a no-op.  Verify that no test relies on word 1 being write-ignored.

### Checklist

- [ ] Update `tb/sim/sc_hub_ref_model.sv` — constants, read model, write model
- [ ] Update `tb/uvm/sc_hub_scoreboard_uvm.sv` — same as above
- [ ] Add META page-select test: write page 0/1/2/3 to word 1, read back, verify
- [ ] Verify all existing tests pass with updated ref model
- [ ] Run standalone synthesis signoff to confirm no area/timing regression
- [ ] Update any downstream integration tests that read hub CSR words 0-1
