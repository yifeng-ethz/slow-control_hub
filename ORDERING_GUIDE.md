# SC Hub v2 — Ordering and Atomic Operations Software Guide

## Audience

Software developers working on the MIDAS frontend slow control path — specifically
`FEBSlowcontrolInterface` and its sub-detector subclasses (`Mutrig_FEB`,
`SciFi_FEB`, `Tiles_FEB`, etc.).

This document describes how to use the new `ORDER`, `ORD_DOM_ID`, and
`atomic_flag` fields in the SC packet format. These fields are carried in
Word 1 and Word 2 of the slow-control command packet and are processed by
the sc_hub_v2 IP on the FEB.

---

## 1. Packet Format Reference

### Current (v1) packet layout

```
Word 0 — Preamble:   [31:26] = 0x07 (SC)
                      [25:24] = sc_type (00=Read, 01=Write, 10=RdNoIncr, 11=WrNoIncr)
                      [23:8]  = FPGA_ID
                      [7:0]   = 0xBC (K28.5)

Word 1 — Address:     [27:24] = mute masks (M/S/T/R)
                      [23:0]  = start address

Word 2 — Length:      [15:0]  = burst length (number of data words)

Words 3..N — Payload: write data (for writes)

Word N+1 — Trailer:  [7:0]   = 0x9C (K28.4)
```

### New (v2) additions to Word 1 and Word 2

```
Word 1 — Address (modified):
  [31:30] = ORDER[1:0]       <-- NEW
              00 = RELAXED    (default — no ordering enforcement)
              01 = RELEASE    (drain older writes before this retires)
              10 = ACQUIRE    (block younger ops until this completes)
              11 = reserved
  [29]    = reserved (0)
  [28]    = atomic_flag       <-- NEW (1 = atomic read-modify-write)
  [27:24] = mute masks        (unchanged)
  [23:0]  = start address      (unchanged)

Word 2 — Length (modified):
  [31:28] = ORD_DOM_ID[3:0]  <-- NEW (ordering domain, 0–15)
  [27:20] = ORD_EPOCH[7:0]   <-- NEW (optional sequence tag, 0 if unused)
  [19:18] = ORD_SCOPE[1:0]   <-- NEW (00=local, 01=device, 10=e2e, 11=rsvd)
  [17:16] = reserved (0)
  [15:0]  = burst length       (unchanged)
```

**Backward compatibility:** Setting the new bits to zero produces the v1
behavior. Existing software that writes `(startaddr & 0x00FFFFFF) | MSTR_bar`
into Word 1 and `data.size()` into Word 2 remains correct — bits [31:28] of
both words default to zero, which means `ORDER=RELAXED`, `ORD_DOM_ID=0`,
`ORD_EPOCH=0`, `ORD_SCOPE=local`.

---

## 2. Proposed C++ API Changes in FEBSlowcontrolInterface

### 2.1 New types

Add to `feb_sc_registers.h` (or a new `feb_sc_ordering.h`):

```cpp
// Ordering semantics for sc_hub_v2
enum SCOrderType : uint8_t {
    SC_ORDER_RELAXED = 0,  // default — no ordering enforcement
    SC_ORDER_RELEASE = 1,  // write-side barrier: drain older writes first
    SC_ORDER_ACQUIRE = 2,  // read-side barrier: block younger until done
};

// Ordering domain (0–15). Ops in different domains are independent.
// Domain 0 is the default (backward-compatible relaxed traffic).
using SCOrderDomain = uint8_t;

// Optional flags struct passed to FEB_read / FEB_write
struct SCOrderFlags {
    SCOrderType order    = SC_ORDER_RELAXED;
    SCOrderDomain domain = 0;      // 0–15
    uint8_t epoch        = 0;      // optional sequence tag (debug/replay)
    uint8_t scope        = 0;      // 0=local, 1=device, 2=e2e
    bool    atomic       = false;  // true -> atomic RMW (reads only, L=1)
    uint32_t atomic_mask = 0;      // bit mask for RMW
    uint32_t atomic_modify = 0;    // modify data for RMW
};
```

### 2.2 Extended FEB_write / FEB_read signatures

```cpp
// New overloads — old ones remain unchanged (SCOrderFlags defaults to RELAXED)
int FEB_write(const mappedFEB & FEB, uint32_t startaddr,
              const vector<uint32_t> & data,
              const SCOrderFlags & flags = {},
              bool nonincrementing = false, bool broadcast = false,
              uint32_t MSTR_bar = 0);

int FEB_read(const mappedFEB & FEB, uint32_t startaddr,
             vector<uint32_t> & data,
             const SCOrderFlags & flags = {},
             bool nonincrementing = false);

// Atomic RMW convenience (always L=1, sc_type=Read with atomic_flag)
int FEB_atomic_rmw(const mappedFEB & FEB, uint32_t addr,
                   uint32_t mask, uint32_t modify,
                   uint32_t & old_value,
                   const SCOrderFlags & flags = {});
```

### 2.3 Packet construction changes

In `FEB_write()` and `FEB_read()`, the packet words are currently built as
(see `FEBSlowcontrolInterface.cpp` lines 81–83):

```cpp
// CURRENT (v1):
mdev.write_memory_rw(0, PACKET_TYPE_SC << 26 | packet_type << 24
                        | (uint16_t)(FPGA_ID & 0xFF) << 8 | 0xBC);
mdev.write_memory_rw(1, (startaddr & 0x00FFFFFF) | MSTR_bar);
mdev.write_memory_rw(2, data.size());
```

Change to:

```cpp
// NEW (v2) — Word 1 encodes ORDER and atomic_flag in bits [31:28]
uint32_t word1 = (startaddr & 0x00FFFFFF) | MSTR_bar;
word1 |= (uint32_t)(flags.order & 0x3) << 30;       // ORDER[1:0] in bits [31:30]
if (flags.atomic)
    word1 |= (1u << 28);                              // atomic_flag in bit [28]

// NEW (v2) — Word 2 encodes ORD_DOM_ID, ORD_EPOCH, ORD_SCOPE in bits [31:16]
uint32_t word2 = (uint32_t)(data.size() & 0xFFFF);
word2 |= (uint32_t)(flags.domain & 0xF) << 28;       // ORD_DOM_ID[3:0]
word2 |= (uint32_t)(flags.epoch  & 0xFF) << 20;      // ORD_EPOCH[7:0]
word2 |= (uint32_t)(flags.scope  & 0x3) << 18;       // ORD_SCOPE[1:0]

mdev.write_memory_rw(0, PACKET_TYPE_SC << 26 | packet_type << 24
                        | (uint16_t)(FPGA_ID & 0xFF) << 8 | 0xBC);
mdev.write_memory_rw(1, word1);
mdev.write_memory_rw(2, word2);
```

For atomic RMW, additionally write the mask and modify words:

```cpp
// Atomic RMW: sc_type = Read, atomic_flag = 1, L = 1
mdev.write_memory_rw(3, flags.atomic_mask);    // Word 3 — atomic mask
mdev.write_memory_rw(4, flags.atomic_modify);  // Word 4 — atomic modify data
mdev.write_memory_rw(5, 0x0000009C);           // Trailer
```

---

## 3. When to Use Each Ordering Semantic

### 3.1 RELAXED (default — use this for everything unless you need ordering)

No ordering enforcement. The hub processes the command as fast as possible.
All existing slow-control traffic should remain RELAXED.

```cpp
// This is exactly what existing code does — no change needed:
feb_sc.FEB_write(FEB, CTRL_REG, value);
feb_sc.FEB_read(FEB, STATUS_REG, data);
```

### 3.2 RELEASE (publish / commit / doorbell)

Use RELEASE when software has written a batch of data and needs to guarantee
that all prior writes in the same domain are visible to hardware before the
commit point.

**Hub behavior:** The hub drains ALL older writes in the same `ORD_DOM_ID` to
the bus and waits for write responses before this packet retires. Younger
same-domain packets are held behind the release boundary.

```cpp
// Example: write a multi-word descriptor, then commit with RELEASE
SCOrderFlags relaxed = { .domain = 1 };
SCOrderFlags release = { .order = SC_ORDER_RELEASE, .domain = 1 };

// Step 1: write descriptor words (RELAXED, fast, may be reordered with each other)
feb_sc.FEB_write(FEB, DESC_BASE + 0, desc_word0, relaxed);
feb_sc.FEB_write(FEB, DESC_BASE + 1, desc_word1, relaxed);
feb_sc.FEB_write(FEB, DESC_BASE + 2, desc_word2, relaxed);

// Step 2: commit (RELEASE) — hub guarantees desc_word0..2 are visible first
feb_sc.FEB_write(FEB, DOORBELL_REG, 1, release);
```

### 3.3 ACQUIRE (consume / synchronize)

Use ACQUIRE when software needs to read a value and guarantee that all
subsequent reads in the same domain see state that is at least as recent as
the acquire point.

**Hub behavior:** The hub issues the acquire read, waits for the response,
then unblocks younger same-domain operations. Younger reads in the domain
cannot bypass the acquire.

```cpp
// Example: read completion status, then read dependent data
SCOrderFlags acquire = { .order = SC_ORDER_ACQUIRE, .domain = 1 };
SCOrderFlags relaxed = { .domain = 1 };

// Step 1: read status with ACQUIRE — blocks younger until done
vector<uint32_t> status(1);
feb_sc.FEB_read(FEB, COMPLETION_STATUS_REG, status, acquire);

// Step 2: read dependent data (RELAXED) — only proceeds after acquire
if (status[0] & DONE_BIT) {
    vector<uint32_t> result(64);
    feb_sc.FEB_read(FEB, RESULT_BASE, result, relaxed);
}
```

---

## 4. Ordering Domains — Decoupling Independent Streams

### 4.1 Why domains matter

Without domains, a RELEASE or ACQUIRE blocks ALL traffic through the hub.
With domains, blocking is scoped to one stream — other domains proceed freely.

There are 16 domains (0–15). Domain 0 is the default.

### 4.2 Practical example: histogram readout vs. counter monitoring

Suppose software periodically:
- **Stream A**: Reads histogram bins (burst read, 64 words from `0xC000`)
- **Stream B**: Reads rate counters (single-word reads from `0x8000+`)
- **Stream C**: Writes configuration registers

These are independent — a slow histogram burst should NOT block a fast counter
read. Assign them to different domains:

```cpp
// Domain assignments (choose once, use consistently)
constexpr SCOrderDomain DOM_HISTOGRAM = 1;
constexpr SCOrderDomain DOM_COUNTERS  = 2;
constexpr SCOrderDomain DOM_CONFIG    = 3;

// --- Stream A: histogram readout (domain 1) ---
SCOrderFlags hist_flags = { .domain = DOM_HISTOGRAM };
vector<uint32_t> hist_data(64);
feb_sc.FEB_read(FEB, 0xC000, hist_data, hist_flags);

// --- Stream B: counter monitoring (domain 2) ---
// This proceeds even if the histogram read above is slow
SCOrderFlags cnt_flags = { .domain = DOM_COUNTERS };
uint32_t ch_rate;
for (int ch = 0; ch < 8; ch++) {
    feb_sc.FEB_read(FEB, MUTRIG_CH_RATE_REGISTER_R + ch, ch_rate, cnt_flags);
}

// --- Stream C: config write (domain 3) ---
SCOrderFlags cfg_relaxed = { .domain = DOM_CONFIG };
SCOrderFlags cfg_release = { .order = SC_ORDER_RELEASE, .domain = DOM_CONFIG };

feb_sc.FEB_write(FEB, THRESHOLD_REG, new_threshold, cfg_relaxed);
feb_sc.FEB_write(FEB, ENABLE_REG, 1, cfg_release);  // commit: prior write visible first
```

**Key property:** An ACQUIRE pending in domain 1 does NOT stall reads in
domain 2. The hub enforces ordering strictly within each domain and allows
cross-domain traffic to flow independently.

### 4.3 Domain assignment guidelines

| Domain | Suggested Use | Rationale |
|--------|--------------|-----------|
| 0 | Legacy / unordered traffic | Default, backward-compatible |
| 1 | Histogram / bulk data reads | Slow bursts, should not block others |
| 2 | Rate counter monitoring | Fast single-word polling |
| 3 | Configuration writes | Occasionally needs RELEASE for commit |
| 4 | Run control state machine | ACQUIRE before reading run state |
| 5–15 | Application-specific | Sub-detector or per-ASIC grouping |

These are suggestions — the mapping is entirely software-defined.

---

## 5. Atomic Read-Modify-Write

### 5.1 What it does

Atomic RMW reads a word, modifies selected bits, writes the result back, and
returns the original value — all while holding the bus lock so no other
external transaction can interleave.

```
new_value = (old_value & ~mask) | (modify & mask)
```

The reply contains the **original** (pre-modify) value.

### 5.2 Software API

```cpp
// Atomically set bit 7 of CTRL_REG, read back the old value
uint32_t old_value;
int status = feb_sc.FEB_atomic_rmw(
    FEB,
    CTRL_REG,
    /*mask=*/    (1u << 7),     // which bits to modify
    /*modify=*/  (1u << 7),     // value to write into those bits
    old_value                    // receives original value
);
// old_value now contains what CTRL_REG held before the modify
```

### 5.3 Atomic + ordering

Atomic and ordering are orthogonal. By default, atomic RMW is RELAXED. If the
atomic is a synchronization point, combine with RELEASE or ACQUIRE:

```cpp
// Atomic RMW as a release (publish pattern):
// All prior writes in domain 3 drain before the atomic executes
SCOrderFlags flags = {
    .order = SC_ORDER_RELEASE,
    .domain = 3,
    .atomic = true,
    .atomic_mask = (1u << 0),
    .atomic_modify = (1u << 0),
};
feb_sc.FEB_atomic_rmw(FEB, DOORBELL_REG, flags.atomic_mask,
                      flags.atomic_modify, old_val, flags);
```

### 5.4 Constraints

- Atomic RMW is single-word only (`burst_length = 1`).
- While the atomic lock is held, **all other external bus transactions are
  blocked**. Internal CSR transactions (to the hub itself) are NOT blocked.
- Use atomics sparingly — they serialize the bus. Under normal conditions,
  atomics should be < 2% of traffic.

---

## 6. Correctness Rules (Hardware Contract)

The hub guarantees these four rules per ordering domain D:

| Rule | Guarantee |
|------|-----------|
| R1 | A younger transaction in D never bypasses a RELEASE in D. |
| R2 | A RELEASE in D does not complete until all older writes in D are bus-visible. |
| R3 | A younger transaction in D does not issue or complete past an ACQUIRE in D until that ACQUIRE completes. |
| R4 | An ACQUIRE completion reflects a state where all causally prior RELEASEs in D are visible. |

**Cross-domain:** Domains are fully independent. A RELEASE in domain 1 says
nothing about writes in domain 2.

**RELAXED:** Rules R1–R4 only apply when ORDER is RELEASE or ACQUIRE. RELAXED
traffic has no ordering guarantees beyond what the bus naturally provides
(Avalon-MM: in-order completion; AXI4: per-ID ordering).

---

## 7. Migration Guide

### 7.1 No changes needed for existing code

All existing `FEB_read()` / `FEB_write()` calls continue to work unchanged.
The `SCOrderFlags` parameter defaults to `{RELAXED, domain=0, epoch=0}`, which
produces the same packet bits as v1 (all new fields are zero).

### 7.2 Adding ordering to an existing polling loop

Before (v1):
```cpp
// Periodic monitoring — reads may interleave with histogram bursts
feb_sc.FEB_read(FEB, COUNTER_REG, counter_val);
feb_sc.FEB_read(FEB, HISTOGRAM_BASE, hist_buf);
```

After (v2) — decouple into separate domains:
```cpp
SCOrderFlags cnt = { .domain = 2 };
SCOrderFlags hist = { .domain = 1 };

feb_sc.FEB_read(FEB, COUNTER_REG, counter_val, cnt);   // domain 2
feb_sc.FEB_read(FEB, HISTOGRAM_BASE, hist_buf, hist);   // domain 1
// Histogram burst does not block counter reads
```

### 7.3 Adding a release/acquire pair to a configuration sequence

Before:
```cpp
feb_sc.FEB_write(FEB, FIFO_BASE + 0, data0);
feb_sc.FEB_write(FEB, FIFO_BASE + 1, data1);
feb_sc.FEB_write(FEB, FIFO_COMMIT_REG, 1);
// BUG: commit may reach hardware before data0/data1 under high load
```

After:
```cpp
SCOrderFlags wr = { .domain = 3 };
SCOrderFlags commit = { .order = SC_ORDER_RELEASE, .domain = 3 };

feb_sc.FEB_write(FEB, FIFO_BASE + 0, data0, wr);
feb_sc.FEB_write(FEB, FIFO_BASE + 1, data1, wr);
feb_sc.FEB_write(FEB, FIFO_COMMIT_REG, 1, commit);
// RELEASE guarantees data0 and data1 are bus-visible before commit
```

### 7.4 Nios RPC with ordering

If `FEBsc_NiosRPC()` writes payload chunks followed by a command trigger, the
trigger should be RELEASE to ensure all payload is visible before the Nios
processes the command:

```cpp
SCOrderFlags payload = { .domain = 5 };
SCOrderFlags trigger = { .order = SC_ORDER_RELEASE, .domain = 5 };

for (auto & chunk : payload_chunks)
    feb_sc.FEB_write(FEB, RPC_DATA_BASE + offset, chunk, payload);
feb_sc.FEB_write(FEB, RPC_CMD_REG, command, trigger);
```

---

## 8. Performance Expectations

| Scenario | Overhead |
|----------|----------|
| 100% RELAXED traffic (default) | Zero — no ordering logic activated |
| 5% RELEASE among writes | ~5% throughput reduction (drain stalls at release points) |
| 5% ACQUIRE among reads | ~5% throughput reduction (younger reads held at acquire) |
| Cross-domain (different ORD_DOM_ID) | No overhead — domains are independent |
| Atomic RMW | Bus locked for `read_latency + 3 cycles + write_latency`; all external traffic blocked during lock |

**Guideline:** Keep release + acquire below 5% of total traffic. Keep atomics
below 2%. Use different domains to avoid unnecessary blocking across
independent operation streams.

---

## 9. Reference: Files Requiring Modification

The following files construct SC command packets and will need the Word 1/Word 2
modifications described in section 2.3:

| File | Function | What to change |
|------|----------|---------------|
| `switching_pc/slowcontrol/FEBSlowcontrolInterface.h` | Class declaration | Add `SCOrderFlags` parameter to `FEB_write()`, `FEB_read()`. Add `FEB_atomic_rmw()`. |
| `switching_pc/slowcontrol/FEBSlowcontrolInterface.cpp` | `FEB_write()` (line 81–83) | Word 1: OR in ORDER, atomic_flag. Word 2: OR in ORD_DOM_ID, epoch, scope. |
| `switching_pc/slowcontrol/FEBSlowcontrolInterface.cpp` | `FEB_read()` (line 250–253) | Same Word 1 / Word 2 changes. Add atomic RMW path (extra words 3–4). |
| `switching_pc/slowcontrol/DummyFEBSlowcontrolInterface.cpp` | `FEB_write()` | Mirror the changes for the dummy/test interface. |
| `switching_pc/slowcontrol/DummyFEBSlowcontrolInterface.h` | Class declaration | Mirror new signatures. |
| `common/include/generated/feb_sc_registers.h` | Constants | Add `SC_ORDER_RELAXED`, `SC_ORDER_RELEASE`, `SC_ORDER_ACQUIRE`, `SC_ATOMIC_FLAG_BIT`. |
| Sub-detector FEBs (`Mutrig_FEB.cpp`, etc.) | Callers | Add `SCOrderFlags` where ordering is desired (optional — default is RELAXED). |

**Reply packet:** `SC_reply_packet::IsRD()` / `IsWR()` in the header check
Word 0 with mask `0x1f0000bc`. Bits [31:28] of Word 0 are NOT used for ordering
(ordering is in Word 1), so no change is needed to reply parsing.

---

## 10. Quick Reference Card

```
  SC Packet Word 1 (Address)
  [31:30]  ORDER     00=relaxed 01=release 10=acquire
  [29]     reserved
  [28]     ATOMIC    1=read-modify-write
  [27:24]  MSTR_bar  mute masks (M/S/T/R)
  [23:0]   ADDR      start address

  SC Packet Word 2 (Length + Domain)
  [31:28]  DOM_ID    ordering domain (0-15)
  [27:20]  EPOCH     sequence tag (optional, 0 default)
  [19:18]  SCOPE     00=local 01=device 10=e2e
  [17:16]  reserved
  [15:0]   LENGTH    burst length (1-256)

  Ordering cheat sheet:
    RELAXED  -> no overhead, default for everything
    RELEASE  -> "all my prior writes are done" (publish / commit)
    ACQUIRE  -> "I need fresh data before continuing" (consume / sync)
    Domains  -> independent streams, no cross-domain blocking
    Atomic   -> bus-locked RMW, combine with RELEASE/ACQUIRE if needed
```
