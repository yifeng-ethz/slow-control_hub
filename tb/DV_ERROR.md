# SC_HUB v2 DV — Error Handling Cases

**Parent:** [DV_PLAN.md](DV_PLAN.md)
**Canonical ID Range:** X001-X128
**Current Implementation Aliases:** T500-T549 (implemented subset)
**Total:** 128 cases
**Method:** All directed (D)

Error handling is the most critical part of the verification: the hub runs on a particle physics detector frontend where errors happen in production and recovery must be autonomous. This document organizes errors into three severity tiers:

| Tier | Name | Definition | Hub Response | Recovery |
|------|------|-----------|-------------|----------|
| **Soft** | Counter-collected, run-through | Error is detected, counted in CSR, and the hub continues operating. No data loss beyond the affected transaction. | Reply with error response code. Increment ERR_COUNT / ERR_FLAGS. Continue processing next command. | None required. Software reads counters periodically. |
| **Hard** | Stuck, needs functional reset, recoverable | Something is stuck (bus hung, FSM deadlocked, resource leaked). The hub cannot self-recover, but a functional reset (CSR CTRL.reset or hardware reset) restores full operation. | Depends on failure mode. May stop responding until reset. | Software detects via timeout/CSR poll, issues CTRL.reset via internal CSR path (always reachable). Hub returns to IDLE with full resources. |
| **Fatal** | Configuration-induced, unrecoverable without re-synthesis | Due to area-saving compile-time configuration, a feature is removed. If the missing feature is needed at runtime, the hub enters an unrecoverable state. These must be examined one-by-one and documented clearly. | Undefined -- ranges from silent data corruption to permanent hang. | Re-synthesize with correct configuration. Cannot recover at runtime. |

---

## 1. Soft Errors (SERR) -- 17 cases

The hub sees the error, reports it in the reply and/or CSR counters, and keeps running. These are the bread-and-butter error paths.

### 1.1 Bus Error Propagation

| ID | Bus | Scenario | Stimulus | Checker | System Ref |
|----|-----|----------|----------|---------|------------|
| T500 | AVMM | Read -> SLAVEERROR from slave | BFM returns SLAVEERROR on read | Reply response=10, data=0xBBADBEEF. ERR_FLAGS.slave_err set. ERR_COUNT incremented. Next command succeeds. | -> SC-015 |
| T501 | AVMM | Read -> DECODEERROR from slave | BFM returns DECODEERROR | Reply response=11, data=0xDEADBEEF. ERR_FLAGS.decode_err set. | -> SC-015 |
| T502 | AVMM | Write -> SLAVEERROR | BFM writeresponsevalid with SLAVEERROR | Reply response=10. ERR_FLAGS set. | -- |
| T503 | AVMM | Write -> DECODEERROR | BFM returns DECODEERROR on write | Reply response=11. | -- |
| T504 | AXI4 | RRESP=SLVERR on read | AXI4 slave returns RRESP=10 | Reply response=10. | -- |
| T505 | AXI4 | RRESP=DECERR on read | AXI4 slave returns RRESP=11 | Reply response=11, data=0xDEADBEEF. | -- |
| T506 | AXI4 | BRESP=SLVERR on write | AXI4 slave returns BRESP=10 | Reply response=10. | -- |
| T507 | AXI4 | BRESP=DECERR on write | AXI4 slave returns BRESP=11 | Reply response=11. | -- |
| T508 | AXI4 | Burst read partial RRESP error (4 OK + 4 SLVERR) | AXI4 slave returns mixed RRESP | Worst-case response propagated in reply. First 4 words valid, last 4 error-fill. | -- |

### 1.2 Malformed Packet Errors (Running Through)

| ID | Bus | Scenario | Stimulus | Checker | System Ref |
|----|-----|----------|----------|---------|------------|
| T509 | AVMM | Missing trailer -> PKT_DROP_CNT | Send write L=8, omit K28.4 | PKT_DROP_CNT++. No bus write. Hub ready for next packet. | -> SC-025 |
| T510 | AVMM | Length overflow -> PKT_DROP_CNT | Send write L=257 | PKT_DROP_CNT++. Hub ready. | -- |
| T511 | AVMM | Data count mismatch -> PKT_DROP_CNT | Declare L=8, send 4 words + trailer | PKT_DROP_CNT++. | -> SC-027 |
| T512 | AVMM | 10 consecutive drops then valid | 10x malformed + 1x valid read | PKT_DROP_CNT=10. 11th packet succeeds with correct reply. Hub fully operational. | -> SC-113 |

### 1.3 Soft Error Counter Behavior

| ID | Bus | Scenario | Stimulus | Checker | System Ref |
|----|-----|----------|----------|---------|------------|
| T513 | AVMM | ERR_COUNT saturation (no wrap) | Trigger 260+ bus errors | ERR_COUNT saturates at max (255 or 65535 depending on width). Does NOT wrap to 0. | -- |
| T514 | AVMM | ERR_FLAGS write-1-to-clear then new error | Trigger error -> read ERR_FLAGS (bit set) -> write 1 to clear -> trigger same error | Bit cleared after W1C. Bit set again on new error. Counter keeps incrementing. | -- |
| T515 | AVMM | Multiple error types simultaneously | SLAVEERROR on read + malformed packet in same test | Both ERR_FLAGS.slave_err and PKT_DROP_CNT updated independently. | -- |
| T516 | AVMM | Error on unmapped address (64 addresses) | Read/write to 64 unmapped addresses | 64 DECODEERROR replies. ERR_COUNT = 64. Hub still alive. | -> SC-015 |

---

## 2. Hard Errors (HERR) -- 15 cases

Something is stuck. The hub cannot self-recover, but a functional reset restores it. The internal CSR path is always reachable (OUTSTANDING_INT_RESERVED=2 guarantees it), so software can always issue a CTRL.reset even when the external path is stuck.

### 2.1 Bus Timeout and Deadlock

| ID | Bus | Scenario | Stimulus | Checker | Recovery Verification |
|----|-----|----------|----------|---------|----------------------|
| T517 | AVMM | Read timeout: BFM never asserts readdatavalid | Issue read. BFM silent. | After RD_TIMEOUT_CYCLES: reply with DECODEERROR. ERR_FLAGS.rd_timeout set. Hub transitions back to IDLE. Next command works. | Self-recovery via timeout FSM |
| T518 | AVMM | Write timeout: BFM asserts waitrequest indefinitely | Issue write. BFM holds waitrequest forever. | After WR_TIMEOUT_CYCLES (if implemented): error. If NOT implemented: **hub hangs**. Verify via CTRL.reset. | CTRL.reset via CSR clears stuck write. Hub returns to IDLE. |
| T519 | AVMM | Burst read partial timeout | BFM returns 4 of 8 words, then stalls | After timeout: reply with error. 4 valid + 4 error-fill words. Hub recovers. | Self-recovery via timeout |
| T520 | AVMM | Burst write partial stall | BFM accepts 4 of 8 words (waitrequest after 4), then permanent stall | If timeout implemented: error. If not: hub hangs -> CTRL.reset recovers. | CTRL.reset |
| T521 | AVMM | Recovery after timeout: next command succeeds | T517 scenario, then normal read | Second read succeeds. No stale state from timed-out transaction. | -> SC-045 |

### 2.2 Resource Leak and Free-List Corruption

| ID | Bus | Scenario | Stimulus | Checker | Recovery Verification |
|----|-----|----------|----------|---------|----------------------|
| T522 | AVMM | Payload leak detection: reset after partial transaction | Issue L=64 write. Reset mid-bus-write (payload allocated but not freed). | After reset: free_count == RAM_DEPTH. Reset reclaims all resources. Assert A37. | Hardware reset |
| T523 | AVMM | Free-list leak after OoO: 10k txns then quiesce | 10k mixed OoO transactions, varied free order | At quiesce: free_count == RAM_DEPTH. If not: free-list leak -> needs reset. Assert A37. | If leak: CTRL.reset restores full free_count |
| T524 | AVMM | Admission revert failure leak | Payload malloc succeeds, header FIFO full, but revert code is buggy (simulated) | If revert fails: free_count decreases permanently. Detect via CSR read. Recovery: CTRL.reset. | CTRL.reset |

### 2.3 FSM Stuck States

| ID | Bus | Scenario | Stimulus | Checker | Recovery Verification |
|----|-----|----------|----------|---------|----------------------|
| T525 | AVMM | Reset during burst read (FSM in READ state) | Reset mid-AVMM-read (avm_m0_read=1, waiting readdatavalid) | Hub returns to IDLE. FIFOs cleared. Next command succeeds. | Hardware reset |
| T526 | AVMM | Reset during burst write (FSM in WRITE state) | Reset mid-write (data partially sent to BFM) | Hub IDLE. Partial write visible in BFM (non-atomic by design). | Hardware reset |
| T527 | AVMM | Reset during reply TX | Reset while reply packet transmitted (mid-SOP-to-EOP) | Partial reply on uplink (monitor sees truncated packet). Hub recovers. Software ignores truncated reply. | Hardware reset |
| T528 | AVMM | Reset during atomic RMW (lock held) | Reset while avm_m0_lock=1 (between read and write phases) | Lock released by reset. Hub IDLE. Atomic operation abandoned (correct: non-committed). | Hardware reset |
| T529 | AVMM | Reset during release drain (younger_blocked=true) | Reset while release drain is waiting for outstanding writes | Domain state cleared. younger_blocked = false. Hub IDLE. | Hardware reset |
| T530 | AVMM | CTRL.reset via CSR during stuck state | T518 scenario (permanent waitrequest). Write CTRL.reset bit via internal CSR. | Hub returns to IDLE. Bus interface deasserts all signals. Next command succeeds. | CSR software reset |
| T531 | AVMM | CTRL.reset + immediate command | CTRL.reset -> command at cycle N (N=1..10 after reset deassert) | Command succeeds. No reset glitch window. | CSR software reset |

---

## 3. Fatal Errors — Configuration-Induced Unrecoverable (FERR) -- 18 cases

These are the scariest class: due to area-saving compile-time configuration, an IP feature is removed. If the missing feature is exercised at runtime, the hub may silently corrupt data, permanently hang, or produce undefined behavior that no reset can fix (because the logic to handle that case was synthesized away).

**Each case below must be examined individually.** The verdict column states whether the failure is truly fatal or can be detected/mitigated.

### 3.1 OoO Feature Removed (OOO_ENABLE=false)

When `OOO_ENABLE=false`, the OoO scoreboard, ARID/AWID generation, and reply reorder logic are not synthesized.

| ID | Scenario | What Happens | Verdict | Mitigation |
|----|----------|-------------|---------|------------|
| T532 | OOO_ENABLE=false, OOO_CTRL CSR written with enable=1 | CSR write accepted (register exists for compatibility). But no scoreboard logic to act on it. Hub remains in-order. | **Benign.** Hub continues in-order. CSR readback shows 1 but behavior is in-order. | Document: OOO_CTRL.enable has no effect when OOO_ENABLE=false at compile time. Software should check HUB_VERSION or a capability register before toggling. |
| T533 | OOO_ENABLE=false, AXI4 slave responds out of order (different RID) | Hub assumes in-order completion. If slave reorders (shouldn't with all-same ARID), data goes to wrong transaction. | **Fatal.** Silent data corruption. Hub issued ARID=0 for all transactions, so slave MUST return in order. If slave violates this, hub cannot detect it. | RTL must assert ARID=0 when OOO_ENABLE=false. Slave fabric must guarantee in-order for same ID. SVA check A21 enforces ARID=0. |
| T534 | OOO_ENABLE=false, high-variance slave latency (50-200 cy) | In-order dispatch -> head-of-line blocking. Throughput degrades to ~1/(max_latency). | **Degraded, not fatal.** Hub is correct but slow. | This is the performance cost of OoO=false. Documented in TLM OOO experiments. If throughput is insufficient, re-synthesize with OOO_ENABLE=true. |

### 3.2 Ordering Tracker Removed (ORD_ENABLE=false, hypothetical)

If a future area-saving config removes the ordering tracker entirely.

| ID | Scenario | What Happens | Verdict | Mitigation |
|----|----------|-------------|---------|------------|
| T535 | ORD_ENABLE=false, RELEASE packet arrives | Hub does not check younger_blocked. Release treated as normal write. No drain. Younger writes bypass. | **Fatal.** Violates R1 and R2. Software ordering contract broken. Silent correctness failure. | **Must not ship ORD_ENABLE=false if software uses ordering.** Capability register must indicate ORD support. Software checks before using RELEASE/ACQUIRE. |
| T536 | ORD_ENABLE=false, ACQUIRE packet arrives | Acquire treated as normal read. No younger-blocking. | **Fatal.** Violates R3. Same as T535. | Same mitigation as T535. |
| T537 | ORD_ENABLE=false, ORDER=00 (RELAXED only) traffic | No ordering tracker overhead. All traffic proceeds normally. | **Benign.** This is the intended use of ORD_ENABLE=false: legacy traffic with no ordering. | Correct configuration for systems that don't need ordering. |

### 3.3 Atomic RMW Removed (ATOMIC_ENABLE=false, hypothetical)

If the atomic RMW sequencer and bus lock logic are not synthesized.

| ID | Scenario | What Happens | Verdict | Mitigation |
|----|----------|-------------|---------|------------|
| T538 | ATOMIC_ENABLE=false, atomic_flag=1 packet arrives | No atomic sequencer. Hub may try to dispatch as normal read (atomic_flag ignored). No lock, no modify, no write phase. | **Fatal.** Reply contains stale data (no RMW). Software expects atomic behavior but gets plain read. Silent correctness failure. | Capability register must indicate ATOMIC support. Software checks before using atomic_flag. Alternatively: hub detects atomic_flag=1 and returns SLAVEERROR (safe fail). |
| T539 | ATOMIC_ENABLE=false, no atomic packets | Normal operation. No bus lock overhead. | **Benign.** Intended use. | Correct configuration. |

### 3.4 Internal CSR Reserved Slots Removed (OUTSTANDING_INT_RESERVED=0)

If the reserved internal transaction slots are set to 0 at compile time.

| ID | Scenario | What Happens | Verdict | Mitigation |
|----|----------|-------------|---------|------------|
| T540 | OUTSTANDING_INT_RESERVED=0, ext saturates all slots, CSR read | All OUTSTANDING_LIMIT slots used by external. Internal CSR read cannot get a slot. | **Fatal.** Internal CSR path blocked. Software cannot issue CTRL.reset. Hub is stuck AND unrecoverable via CSR. Only hardware reset works. | **OUTSTANDING_INT_RESERVED must be >= 1.** This is the last-resort recovery path. Setting it to 0 removes the ability to software-reset a stuck hub. |
| T541 | OUTSTANDING_INT_RESERVED=0, ext not saturated, CSR read | Ext uses < OUTSTANDING_LIMIT. Int CSR read gets a shared slot. | **Benign under light load.** But any transient ext saturation blocks CSR. | Risky. Not recommended. At minimum, document the risk. |

### 3.5 Payload RAM Depth Undersized

| ID | Scenario | What Happens | Verdict | Mitigation |
|----|----------|-------------|---------|------------|
| T542 | EXT_PLD_DEPTH=1, write L=2 arrives | Malloc cannot allocate 2 lines. Admission fails. Backpressure. | **Permanent stall for writes > L=1.** Not a data corruption, but a functional loss. | **EXT_PLD_DEPTH must be >= MAX_BURST (256) for full functionality.** Smaller values are valid for reduced-burst configurations (e.g., CSR-only hubs where L <= 32). |
| T543 | EXT_PLD_DEPTH=32, write L=33 arrives | Malloc fails. Admission rejects. Backpressure on that command forever if software keeps retrying. | **Permanent stall for that command.** Hub still processes shorter writes. | Software must not send L > EXT_PLD_DEPTH. Document the constraint. |

### 3.6 Bus Handler Removed (Single-Bus Configuration)

If the hub is synthesized with only AVMM (no AXI4) or only AXI4 (no AVMM).

| ID | Scenario | What Happens | Verdict | Mitigation |
|----|----------|-------------|---------|------------|
| T544 | AVMM-only config, dispatch targets AXI4 path | Dispatch logic tries to drive AXI4 signals that don't exist. | **Fatal.** Synthesis should eliminate the dead path. But if dispatch routing has a bug, signals are undriven -> undefined bus behavior. | RTL must tie off unused bus interface. SVA checks on unused interface: all outputs = 0. |
| T545 | AXI4-only config, CSR triggers AVMM-specific logic | Internal CSR path should be bus-independent. If CSR handler references AVMM-specific signals, it may fail. | **Bug if it happens.** CSR path must be fully independent of bus type. | Verify: T060 (CSR on AXI4) must pass with AVMM logic removed. |

### 3.7 S&F Validator Disabled (STORE_AND_FORWARD=false)

If store-and-forward is disabled for latency, writes go directly to bus without validation.

| ID | Scenario | What Happens | Verdict | Mitigation |
|----|----------|-------------|---------|------------|
| T546 | S&F=false, truncated write (8 of 16 words sent, then silence) | Without S&F, partial write data already sent to bus. Bus sees 8 words instead of 16. | **Fatal.** Partial write to slave. Data corruption. Bus protocol violation (AVMM: burstcount=16 but only 8 writedata beats). | **S&F should remain enabled by default.** Only disable if the upstream link guarantees packet integrity (e.g., hardware CRC-checked link with no truncation possible). |
| T547 | S&F=false, valid packet | Write dispatched immediately at first data word. Lower latency. | **Benign if packet is valid.** This is the intended optimization. | Valid use case for CRC-protected links. |

### 3.8 Clock Domain Configuration Error

| ID | Scenario | What Happens | Verdict | Mitigation |
|----|----------|-------------|---------|------------|
| T548 | Hub clock != bus clock (CDC point with no synchronizer) | Hub FSM and bus handshake are in different clock domains. Metastability on control signals. | **Fatal.** Silent data corruption, protocol violations, random hangs. No CDC handling in current RTL design. | **Hub clock and bus clock must be the same.** This is a system integration constraint, not an IP configuration. If clocks differ, an explicit CDC bridge must be inserted OUTSIDE the hub. Do not create a CDC point inside the hub. |
| T549 | Hub reset not synchronized to hub clock | Reset release causes metastability in FSM registers. | **Fatal.** FSM may start in undefined state. | Reset synchronizer required at integration level. Hub assumes synchronous reset. |

---

## 4. Fatal Error Summary and Configuration Guard

The following table summarizes which configurations are truly fatal and must be guarded:

| Configuration | Fatal If | Guard |
|---------------|----------|-------|
| OOO_ENABLE=false | AXI4 slave reorders responses | SVA A21: ARID always 0 when OoO=off |
| ORD_ENABLE=false | Software sends RELEASE/ACQUIRE packets | Capability register bit. Software must check. |
| ATOMIC_ENABLE=false | Software sends atomic_flag=1 packets | Capability register bit. Hub should return SLAVEERROR on atomic_flag=1 if not supported. |
| OUTSTANDING_INT_RESERVED=0 | External saturates all slots | **Minimum = 1 enforced in RTL parameter check.** Synthesis error if set to 0. |
| EXT_PLD_DEPTH < MAX_BURST | Software sends L > depth | Document: L_max = min(256, EXT_PLD_DEPTH). |
| S&F=false | Truncated/malformed packet on unreliable link | Default S&F=true. Only disable with hardware-guaranteed link integrity. |
| Hub clock != bus clock | Always | System integration constraint: same clock domain. |
| Async reset | Always | System integration: synchronized reset. |

**Recommendation:** Add a `HUB_CAP` (capability) read-only CSR register that reports compile-time feature flags:

```
HUB_CAP (offset TBD, read-only):
  bit 0: OOO_ENABLE
  bit 1: ORD_ENABLE
  bit 2: ATOMIC_ENABLE
  bit 3: S_AND_F_ENABLE
  bits [7:4]: OUTSTANDING_INT_RESERVED (4-bit, 0-15)
  bits [15:8]: EXT_PLD_DEPTH / 64 (encoded, 1-16 -> 64-1024)
  bits [23:16]: MAX_BURST (0=256)
```

Software reads HUB_CAP at init and asserts that required features are present before using ordering, atomic, or large burst operations. This converts fatal silent failures into loud software errors at startup.


---

## 5. Planned Expansion Cases (X051-X128)

The cases below are part of the canonical `DV_ERROR` plan but remain **planned-only** today. They target failure signatures that are easy to miss when the regression only validates the obvious malformed-packet and timeout paths.

### 5.1 Parser, Framing, and Contract Hardening -- 13 planned cases

| Canonical ID | Bus | Scenario | Planned stimulus | Why it exists |
|---|---|---|---|---|
| X051 | AVMM | Read packet with illegal type bits but legal trailer | Malformed command that still looks well framed | Distinguishes parser reject from generic framing reject. |
| X052 | AVMM | Write packet with mismatched MSTR/FEB type | Command should not target this FEB | Needed once detector-type masking is part of the contract. |
| X053 | AVMM | Packet with reserved order encoding plus atomic bit | Illegal mixed contract fields | Looks for undefined-field priority bugs. |
| X054 | AVMM | Nonincrement packet to unsupported config | Fixed-address command when feature disabled | Should fail loudly, not act incrementing silently. |
| X055 | AVMM | Length header says 256, trailer arrives after 255 | Off-by-one short payload | Common parser fencepost failure. |
| X056 | AVMM | Length header says 255, 256 payload words arrive | Off-by-one long payload | Companion to X055. |
| X057 | AVMM | Duplicate trailer after valid packet | Extra K28.4 word | Parser must resync cleanly instead of misclassifying next packet. |
| X058 | AVMM | Preamble appears inside payload without datak qualification | Payload resembles control word | Ensures control detection honors K-character contract. |
| X059 | AVMM | Reserved response code from downstream injection | Force unsupported reply meta bits | Host-visible error encoding path must stay defined. |
| X060 | AVMM | Unsupported atomic opcode variant | Reserved atomic modifier bits | Better to reject deterministically than partially execute. |
| X061 | AVMM | Reserved capability bit queried by software | Read future-use bits | Observability contract should remain stable under unknown fields. |
| X062 | AVMM | Mixed legal/illegal packets in same bursty stream | One malformed out of N legal packets | Detects parser state contamination across packets. |
| X063 | AVMM | Malformed packet immediately after soft reset | First packet after reset is bad | Recovery logic often assumes first packet is clean. |

### 5.2 Bus Fault Matrix Expansion -- 13 planned cases

| Canonical ID | Bus | Scenario | Planned stimulus | Why it exists |
|---|---|---|---|---|
| X064 | AVMM | Decode error on first beat of max read | Unmapped `L=256` read | Large-burst decode error path should not assume `L=1`. |
| X065 | AVMM | Decode error on write after payload fully buffered | Unmapped long write | Makes sure store-and-forward rollback/reporting is correct. |
| X066 | AVMM | Alternating decode and slave errors | Inject patterned bus errors | Error flags/counters must classify, not just count. |
| X067 | AVMM | Read timeout followed by decode error | Different failure classes back-to-back | Finds stale error state leakage. |
| X068 | AVMM | Write timeout followed by successful read | Recovery after different fault classes | Same motivation on write side. |
| X069 | AXI4 | BRESP `SLVERR` on final beat | Long write with terminal bus fault | AXI write error timing differs from AVMM. |
| X070 | AXI4 | RRESP error on middle beat | Long read with partial-burst error | Defines whether partial payload is preserved or poisoned. |
| X071 | AXI4 | Split error classes across reordered responses | One RID okay, one RID error | Reorder logic must preserve fault attribution. |
| X072 | AXI4 | Stalled `BVALID` after all W beats accepted | Write response channel fault | Another path to scoreboard wedges. |
| X073 | AXI4 | Stalled `RVALID` mid-burst then timeout | Partial read timeout on AXI4 | Mirrors T519 for AXI4 semantics. |
| X074 | AVMM | Bus returns X data with valid handshake | Corrupt-but-accepted read data | Scoreboard and assertions should catch X-propagation. |
| X075 | AVMM | Spurious readdatavalid without prior read | BFM protocol violation | Hardening against illegal slave behavior. |
| X076 | AXI4 | Spurious response ID not in flight | Rogue RID/BID | Important once OoO path is considered robust. |

### 5.3 Resource Accounting and Leak Sentinels -- 13 planned cases

| Canonical ID | Bus | Scenario | Planned stimulus | Why it exists |
|---|---|---|---|---|
| X077 | AVMM | Payload leak after malformed write under near-full state | Combine parser drop with high occupancy | This is the practical leak corner, not the easy empty case. |
| X078 | AVMM | Header leak after decode error storm | Many failing short reads | Ensures error-heavy traffic still frees metadata. |
| X079 | AVMM | Credit leak after timeout then reset | Timeout, then soft reset, then read counters | Counter/resource reconciliation after reset matters. |
| X080 | AXI4 | Reorder slot leak after mixed RID errors | OoO plus errors | Specific to scoreboard/free path. |
| X081 | AXI4 | Reorder slot leak after reset mid-completion | Reset with responses in flight | Another frequent leak source. |
| X082 | AVMM | Counter saturation under continuous drops | Drive drop counters near max | Saturation behavior should be explicit, not accidental wrap. |
| X083 | AVMM | Counter saturation under continuous bus faults | Same for bus error counters | Companion to X082. |
| X084 | AVMM | Sticky flag clear race with new error | Clear W1C bit on same cycle as new fault | Classic CSR corner. |
| X085 | AVMM | Free-count mismatch detector under injected model bug | Intentionally perturb BFM model to stress assertions | Good proving ground for invariant monitors. |
| X086 | AVMM | Upload-credit mismatch after partial reply abort | Abort reply mid-stream then recover | Upload path accounting is often less exercised. |
| X087 | AVMM | Download occupancy mismatch after parser resync | Malformed packet then immediate good packet | Looks for stale occupancy on recovery. |
| X088 | AXI4 | RID scoreboard occupancy mismatch under timeout | Timeout plus OoO | Error-specific version of ordinary fairness tests. |
| X089 | AVMM | Long-run leak monitor with periodic snapshots | Coverage-oriented error soak | Needed to convert “seems fine” into measured no-leak evidence. |

### 5.4 Reset and Recovery Under Fault Pressure -- 13 planned cases

| Canonical ID | Bus | Scenario | Planned stimulus | Why it exists |
|---|---|---|---|---|
| X090 | AVMM | Soft reset while drop counter increments | Reset on malformed-packet boundary | Reset/error simultaneity is a real hardware event. |
| X091 | AVMM | Soft reset while timeout flag asserts | Reset on the exact timeout cycle | Off-by-one recovery bug hotspot. |
| X092 | AVMM | Double soft reset pulses with no traffic | Two resets separated by 1 cycle | Proves reset path is idempotent. |
| X093 | AVMM | Double soft reset pulses with active traffic | Same as X092 under load | More realistic than idle reset-only checks. |
| X094 | AVMM | Hardware reset after soft-reset recovery | Layered recovery paths back-to-back | Verifies no hidden latch-up in reset trees. |
| X095 | AXI4 | Reset while B channel carries error response | AXI-specific recovery edge | Mirrors read-side cases on write response path. |
| X096 | AXI4 | Reset while R channel carries error response | Error plus reset and OoO | Needed once AXI path is signed off. |
| X097 | AVMM | Recovery packet immediately after malformed burst storm | 100 drops then one good command | Stronger version of existing short recovery cases. |
| X098 | AVMM | Recovery packet immediately after decode-error storm | 100 decode faults then good command | Fault recovery should not be class-specific. |
| X099 | AVMM | Recovery packet immediately after counter clear sequence | W1C cleanup then valid command | Tooling scripts often do this in practice. |
| X100 | AVMM | Reset while internal CSR access is the only traffic | Pure internal-path recovery | Keeps internal path from being assumed trivial. |
| X101 | AVMM | Reset while nonincrement command is active | Feature-specific reset edge | Necessary now that nonincrement is part of the protocol. |
| X102 | AVMM | Reset while masked-detector packet is ignored | Ignore path plus reset | Finds stale parser state when packet is intentionally dropped by mask. |

### 5.5 Capability and Software-Contract Mismatch Defenses -- 13 planned cases

| Canonical ID | Bus | Scenario | Planned stimulus | Why it exists |
|---|---|---|---|---|
| X103 | AVMM | Software uses 16-bit address assumption on 24-bit command | Host truncates top address bits | This mismatch already exists in software notes; regression should reflect it. |
| X104 | AVMM | Software requests burst length 255 cap when hardware allows 256 | Host policy mismatch | Ensures host limitations do not masquerade as hub limits. |
| X105 | AVMM | Software interprets write ack as payload-bearing | Legacy parser contract | Prevents reintroduction of already-seen host bug. |
| X106 | AVMM | Software assumes bit16-only response semantics | Legacy response-code parse | Another known host mismatch. |
| X107 | AVMM | Software sends raw MSTR mask overlay incompatible with v2 fields | Host-side field aliasing bug | Should be detectable, not silently misroute. |
| X108 | AVMM | Software sends unsupported FEB type mask | No matching detector type | Hardware should ignore or error deterministically. |
| X109 | AVMM | Software sends nonincrement to hub that advertises no support | Capability mismatch | Host contract must check capability before use. |
| X110 | AVMM | Software ignores capability bits and sends atomic anyway | Capability mismatch | Same for atomics. |
| X111 | AVMM | Software ignores capability bits and sends ordering anyway | Capability mismatch | Same for ordering. |
| X112 | AVMM | Software assumes every write produces upload payload | Legacy host assumption | Explicitly encode no-payload write-ack contract. |
| X113 | AVMM | Software retries forever on backpressure without observing counters | Host retry storm | Helps evaluate observability needed for debugging. |
| X114 | AVMM | Software clears counters mid-transaction | Host debug misuse | Useful to define whether counters are monotonic/diagnostic only. |
| X115 | AVMM | Software polls wrong CSR alias after version bump | Version skew | Needed once packaging/versioning is part of the signoff story. |

### 5.6 Diagnostic Integrity and Observability Failures -- 13 planned cases

| Canonical ID | Bus | Scenario | Planned stimulus | Why it exists |
|---|---|---|---|---|
| X116 | AVMM | LAST_WR_* CSR stale after failed write | Faulting write should not overwrite last-good diagnostics | Observability can mislead debug if this is wrong. |
| X117 | AVMM | LAST_RD_* CSR stale after failed read | Same for read path | Companion case. |
| X118 | AVMM | Counter snapshot while traffic still active | Read diagnostic CSRs mid-stream | Defines whether software may trust live snapshots. |
| X119 | AVMM | Counter snapshot immediately after soft reset | Read diagnostics right after reset | Reset-value observability matters for tooling. |
| X120 | AVMM | HUB_CAP read during heavy load | Capability CSR under pressure | Internal-path observability should stay reliable. |
| X121 | AVMM | VERSION/META read after error storm | Identity CSRs after faults | Debug scripts typically do this first. |
| X122 | AXI4 | OoO debug counters after mixed error run | AXI-specific observability | Without this, AXI debug remains anecdotal. |
| X123 | AVMM | Diagnostic counters under masked-packet traffic | Ignored traffic should not pollute real counters | Important once detector masks are supported. |
| X124 | AVMM | Diagnostic counters under nonincrement traffic | Fixed-address commands | Ensures new feature traffic is visible in the right buckets. |
| X125 | AVMM | Diagnostic counters under barrier-only traffic | `L=0` acquire/release | Another easy place for counters to look dead or misleading. |
| X126 | AVMM | Diagnostic counters near saturation | Read while approaching max | Detects read-side truncation or formatting bugs. |
| X127 | AVMM | Diagnostic CSRs during partial-reply abort | Read status after truncated upload | Needed for real hardware postmortem workflows. |
| X128 | AVMM | Full observability audit after mixed-fault campaign | One case that compares raw events vs all counters/last-* CSRs | Final planned diagnostic signoff case. |
