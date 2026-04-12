# SC_HUB v2 DV — Edge Cases

**Parent:** [DV_PLAN.md](DV_PLAN.md)
**Canonical ID Range:** E001-E128
**Current Implementation Aliases:** T400-T449 (implemented subset)
**Total:** 128 cases
**Method:** All directed (D)

These tests exercise near-boundary conditions: non-power-of-2 burst lengths, address boundaries, near-full buffers, odd configurations, and scenarios that are intentionally close to failure but must not fail. The hub must handle all of these without hanging, corrupting data, or leaking resources.

**Design philosophy:** Every edge case here was either (a) identified by TLM_PLAN section 12.6 edge case catalog, (b) derived from a TLM_NOTE issue, or (c) found by reasoning about non-power-of-2 and boundary behavior in the split-buffer architecture. If the hub survives all of these, the RTL is robust for the full feb_system parameter space.

---

## 1. Non-Power-of-2 and Odd Burst Lengths (NPO2) -- 15 cases

The hub supports burst lengths 1-256. Most tests exercise powers of 2. These tests verify correct behavior at odd, prime, and boundary-adjacent lengths.

| ID | Bus | Scenario | Stimulus | Checker | Rationale |
|----|-----|----------|----------|---------|-----------|
| T400 | AVMM | Burst read L=3 | `send_burst_read(0x000, 3)` | 3 words correct, reply header length=3 | Odd count: linked-list chain of 3 lines |
| T401 | AVMM | Burst write L=5 | `send_burst_write(0x000, 5, data[])` | BFM memory correct, pld chain = 5 lines | Prime number burst |
| T402 | AVMM | Burst read L=7 | `send_burst_read(0x100, 7)` | all 7 words correct | Near power-of-2 minus 1 |
| T403 | AVMM | Burst write L=13 | `send_burst_write(0x200, 13, data[])` | correct | Prime |
| T404 | AVMM | Burst read L=127 | `send_burst_read(0x000, 127)` | correct | 2^7 - 1 |
| T405 | AVMM | Burst write L=129 | `send_burst_write(0x000, 129, data[])` | correct | 2^7 + 1 |
| T406 | AVMM | Burst read L=255 | `send_burst_read(0x000, 255)` | correct | Max - 1 |
| T407 | AXI4 | Burst read L=3 on AXI4 | `send_burst_read(0x000, 3)` | ARLEN=2, 3 R beats | AXI4 with odd ARLEN |
| T408 | AXI4 | Burst write L=7 on AXI4 | `send_burst_write(0x000, 7, data[])` | AWLEN=6, WLAST on beat 7 | AXI4 with odd AWLEN |
| T409 | AXI4 | Burst read L=255 on AXI4 | `send_burst_read(0x000, 255)` | ARLEN=254, 255 R beats | AXI4 near-max |
| T410 | AVMM | Sequence of all prime lengths 1-31 | 11 reads: L in {1,2,3,5,7,11,13,17,19,23,29,31} | all correct | Sweep primes |
| T411 | AVMM | Burst write L=1 followed by L=256 | write L=1 then write L=256 | both correct | Min then max |
| T412 | AVMM | Alternating L=1 and L=255 (100 pairs) | 200 writes | all correct, free_count returns to full | Near-max alternation stress |
| T413 | AVMM | Burst read L=250 (not aligned to power of 2) | `send_burst_read(0x000, 250)` | correct | Arbitrary large non-aligned |
| T414 | AVMM | Burst write L=2 (minimum non-single) | `send_burst_write(0x000, 2, data[])` | correct | Minimum burst |

---

## 2. Near-Failure Scenarios (NF) -- 15 cases

The hub is pushed to its resource limits but must NOT fail. These are the "one slot left" tests.

| ID | Bus | Scenario | Stimulus | Checker | TLM Source |
|----|-----|----------|----------|---------|------------|
| T415 | AVMM | ext_down_hdr: fill to OUTSTANDING-1, then one more | Issue OUTSTANDING_LIMIT-1 commands (slow BFM stalls them). Issue 1 more. | Last command admitted. No overflow. | TLM 12.6 #7 |
| T416 | AVMM | ext_down_hdr: fill to OUTSTANDING, then one more | Issue OUTSTANDING_LIMIT commands. Issue 1 more. | Last command must be backpressured (o_linkin_ready=0). No overflow. | TLM 12.6 #7 |
| T417 | AVMM | ext_down_pld: fill to depth-1, then L=1 write | Fill 511 of 512 pld words. Send L=1 write. | Admitted (exactly 1 word left). | TLM 12.6 #1 |
| T418 | AVMM | ext_down_pld: fill to depth, then write | Fill 512 of 512 pld words. Send write. | Backpressure. No overflow. No partial allocation. | TLM 12.6 #1 |
| T419 | AVMM | ext_down_pld: fill 510, then L=4 write (need 4, have 2) | Fill 510 words. Send L=4 write. | Backpressure (need 4, only 2 free). Command not admitted. | TLM 2.4 |
| T420 | AVMM | Credit reservation: 1 word left in ext_up_pld | Reserve 511 of 512 upload pld words. Issue L=1 read. | Read admitted, credit reserved from last word. | TLM 2.5 |
| T421 | AVMM | Credit reservation: 0 words left | Reserve 512 of 512. Issue read. | Read stalls at dispatch (credit exhausted). Resumes when earlier read completes and frees credit. | CRED-03 |
| T422 | AVMM | cmd_order_fifo exactly full | Issue exactly OUTSTANDING_LIMIT commands. Verify cmd_order_fifo at capacity. Issue 1 more. | Backpressure, no corruption. | TLM 12.6 #7 |
| T423 | AVMM | Header FIFO wrap: >256 transactions through 8-deep FIFO | 300 sequential reads through ext_down_hdr (depth=8) | All 300 correct. seq_num wraps cleanly at 256. | TLM 12.6 #8 |
| T424 | AVMM | Malloc succeeds with non-contiguous free list | Allocate/free pattern to fragment free list. Then malloc L=64. | Allocation succeeds (linked-list tolerates non-contiguous). Chain is valid. | TLM 3.3 |
| T425 | AVMM | BP FIFO at almost-full watermark | Fill BP FIFO to threshold - 1 word. Issue one more reply. | o_linkin_ready stays 1 (threshold not yet crossed). | -- |
| T426 | AVMM | BP FIFO crosses threshold then drains | Fill BP FIFO to threshold + 1. | o_linkin_ready deasserts. Drain 2 words. o_linkin_ready reasserts. | T079 extended |
| T427 | AVMM | Outstanding limit = 1 (minimum functional config) | Set OUTSTANDING_LIMIT=1. Send 10 reads. | All 10 complete sequentially. One at a time on bus. | TLM 12.6 #12 |
| T428 | AVMM | All 4 payload pools near-full simultaneously | ext_down, int_down, ext_up, int_up each at >90% used. | Mixed int/ext R/W traffic proceeds. All pools drain to full. | TLM 12.6 #10 |
| T429 | AVMM | Admission revert on header push failure | Payload malloc succeeds, but header FIFO is full. | Payload freed (revert). No leak. free_count consistent. | TLM_NOTE #3 |

---

## 3. Configuration Boundary Cases (CFG) -- 20 cases

Tests at unusual but valid configurations, and interaction edge cases between features.

### 3.1 OoO Toggle and Feature Interaction

| ID | Bus | Scenario | Stimulus | Checker | TLM Source |
|----|-----|----------|----------|---------|------------|
| T430 | AXI4 | OoO runtime toggle with 4 txns in flight | OOO_CTRL.enable=1. Issue 4 reads (varied latency). Write CSR OOO_CTRL.enable=0. | In-flight txns drain in natural order. Next 4 txns use in-order path. | TLM 12.6 #6 |
| T431 | AXI4 | OoO toggle on -> off -> on (rapid toggle) | Toggle OoO 3 times with 2 txns between each toggle | All txns complete correctly. No stuck state. | TLM 12.6 #6 |
| T432 | AVMM | OOO_ENABLE=false compile-time, OOO_CTRL write ignored | OOO_ENABLE=false. Write CSR OOO_CTRL bit0=1. Read back. | CSR reads 0 (or write ignored). Hub stays in-order. | -- |
| T433 | AXI4 | OoO + ordering: ACQUIRE in dom=0, OoO dispatches dom=1 | OoO=on. Dom 0: ACQUIRE (slow). Dom 1: 4 RELAXED reads (fast). | Dom 1 reads dispatched and complete out of order. Dom 0 younger ops held. | TLM 12.6 #15 |

### 3.2 Ordering Edge Cases

| ID | Bus | Scenario | Stimulus | Checker | TLM Source |
|----|-----|----------|----------|---------|------------|
| T434 | AVMM | RELEASE with no data payload (L=0) | `send_ordered_write(RELEASE, dom=1, L=0)` | Handled gracefully -- release as pure barrier, no bus write needed. | -- |
| T435 | AVMM | ACQUIRE read to unmapped address | `send_ordered_read(ACQUIRE, dom=1, addr=unmapped)` | ACQUIRE completes with DECODEERROR. younger_blocked[1] cleared. No hang. | -- |
| T436 | AVMM | ORDER=11 (RESERVED) packet | `send_raw` with ORDER bits = 11 | Hub treats as RELAXED (undefined -> default). No crash. | TLM 2.9.1 |
| T437 | AVMM | 16 domains each with 1 outstanding + ACQUIRE on dom=0 | All 16 domains active. Dom 0 gets ACQUIRE. | 15 other domains unaffected. Dom 0 held. No state array corruption. | TLM 12.6 #16 |
| T438 | AVMM | Epoch wrap (ORD_EPOCH from 255 -> 0) | Sequence with epoch values: 254, 255, 0, 1 in dom=1 | Epoch monotonicity check handles wrap correctly. No false assertion. | ORD-I05 |
| T439 | AVMM | Ordering + admission revert: RELEASE admitted, pld ok, hdr full | RELEASE packet. Payload malloc succeeds. Header FIFO full. | Admission fails. Payload freed. Ordering domain state NOT set to release_pending. | TLM 12.6 #17 |

### 3.3 Atomic Edge Cases

| ID | Bus | Scenario | Stimulus | Checker | TLM Source |
|----|-----|----------|----------|---------|------------|
| T440 | AVMM | Atomic RMW to same address as outstanding read | Issue read to addr X. Then atomic_rmw to addr X. | Atomic waits for read to complete (no data hazard). Both correct. | TLM 12.6 #9 |
| T441 | AVMM | Atomic RMW: bus read timeout -> skip write phase | BFM never responds to atomic read phase. | Read timeout fires. Write phase skipped. Reply with DECODEERROR. ERR_FLAGS set. | ATOM-C04 ext. |
| T442 | AVMM | Two back-to-back atomics to same address | atomic_rmw(addr, mask=0x00FF, mod=0x11), atomic_rmw(addr, mask=0xFF00, mod=0x22) | Final value reflects both. Second atomic sees first's result. | ATOM-C01 |

### 3.4 Misc Configuration Boundaries

| ID | Bus | Scenario | Stimulus | Checker | TLM Source |
|----|-----|----------|----------|---------|------------|
| T443 | AVMM | INT_HDR_DEPTH=1: single CSR slot | Set INT_HDR_DEPTH=1. Issue int CSR read, then immediately int CSR write. | First CSR read completes. Second waits for slot. Both succeed. | SIZE-03 edge |
| T444 | AVMM | OUTSTANDING_INT_RESERVED=0: no reserved int slots | Set OUTSTANDING_INT_RESERVED=0. Saturate ext. Issue CSR read. | CSR read must wait for ext slot to free (no reservation). Verify it still completes. | PRIO boundary |
| T445 | AVMM | OUTSTANDING_INT_RESERVED=OUTSTANDING_LIMIT: all slots reserved | Set reserved = limit (e.g., 8). Issue ext read. | Ext read gets 0 slots -> permanent backpressure on ext. Int CSR works. | PRIO boundary |
| T446 | AVMM | EXT_PLD_DEPTH=64 (minimum) with L=64 write | Payload depth = 64. Send L=64 write. | Exactly fills payload. Second write must backpressure. | SIZE-02 edge |
| T447 | AVMM | EXT_PLD_DEPTH=64 with L=65 write | Payload depth = 64. Send L=65 write. | Must backpressure at admission (can't allocate 65 lines). | SIZE-02 edge |
| T448 | AVMM | Address at CSR boundary: 0xFE7F (just below CSR) | `send_read(0xFE7F, 1)` | Routed to external bus (NOT internal CSR). BFM responds. | T124 extended |
| T449 | AVMM | Address at CSR boundary: 0xFEA0 (just above CSR) | `send_read(0xFEA0, 1)` | Routed to external bus. If unmapped, DECODEERROR. NOT internal CSR. | T124 extended |


---

## 4. Planned Expansion Cases (E051-E128)

The cases below extend `DV_EDGE` to the workflow-required volume. They are **canonical plan entries only** today: they document specific boundary conditions that should exist in the regression, but they do not yet have runnable `Txxx` implementations.

### 4.1 Packet Framing and Bubble Boundaries -- 13 planned cases

| Canonical ID | Bus | Scenario | Planned stimulus | Why it exists |
|---|---|---|---|---|
| E051 | AVMM | Single bubble after preamble | Insert one legal idle word between header words | Bubble legality has historically caused parser wedges. |
| E052 | AVMM | Bubble before trailer on write | Long write with a one-cycle gap before trailer | Boundary between payload completion and trailer recognition is fragile. |
| E053 | AVMM | Bubble every other data word | Legal sparse write stream | Ensures payload counters key on real data, not cycle count. |
| E054 | AVMM | Consecutive bubbles at payload start | `L=16` write with 4-cycle gap after header | Tests whether parser arm/disarm logic is truly data-driven. |
| E055 | AVMM | Consecutive bubbles at payload end | `L=16` write with 4-cycle gap before last data word | Looks for premature trailer expectation. |
| E056 | AVMM | Read packet with gap between addr and len words | Legal read framing with delay | Read path should be as tolerant as write path. |
| E057 | AVMM | Back-to-back packets with one idle separator | Minimal legal inter-packet spacing | Exposes parser reset timing issues. |
| E058 | AVMM | Back-to-back packets with no extra idle beyond trailer transition | Tightest legal packet cadence | Defines minimum recovery requirement. |
| E059 | AVMM | Long run of idles then packet | 10k idles then one command | Checks for watchdog or stale state after extended inactivity. |
| E060 | AVMM | Skip characters embedded in maximum burst | `L=256` write with periodic K28.5 skip words | Historically easy place to lose length accounting. |
| E061 | AVMM | Header words split by backpressure-ready toggling | Vary `i_sc_rdy` around header receipt | Confirms ready gating does not corrupt header assembly. |
| E062 | AVMM | Trailer immediately followed by next preamble | Two packets, zero extra spacing | Tests parser handoff at the exact boundary cycle. |
| E063 | AVMM | Legal read after bubble-heavy write | Bubble-heavy write then ordinary read | Recovery boundary after odd framing matters more than framing alone. |

### 4.2 Address, Decode, and Length Boundaries -- 13 planned cases

| Canonical ID | Bus | Scenario | Planned stimulus | Why it exists |
|---|---|---|---|---|
| E064 | AVMM | Lowest external address with max burst | Read from `0x000000`, `L=256` | Existing tests cover pieces, not the combined boundary. |
| E065 | AVMM | Highest 24-bit address with single read | Read from `0xFFFFFF`, `L=1` | Validates full-address-width handling in the parser and bus handler. |
| E066 | AVMM | Highest 24-bit address with short write | Write `0xFFFFFF`, `L=4` | Write path must not truncate top address bits. |
| E067 | AVMM | Address wrap hazard at `0xFFFFFE`, `L=4` | Sequential access crosses 24-bit top boundary | Defines expected behavior before integration finds it accidentally. |
| E068 | AVMM | CSR boundary minus burst | Start just below CSR window with `L=4` | Ensures decode is based on start address contract, not per-beat drift. |
| E069 | AVMM | CSR boundary plus burst | Start just above CSR window with `L=4` | Symmetric boundary check. |
| E070 | AVMM | Sparse unmapped region read cluster | 16 reads across decode holes | Finds decode-table off-by-one errors hidden by single-address tests. |
| E071 | AXI4 | Highest address with fixed burst | AXI4 read at `0xFFFFFF`, `L=8` | Mirrors AVMM width check on AXI4 path. |
| E072 | AXI4 | Nonincrement write at high address | Fixed-address write burst at top of map | Exercises address-hold logic with high bits set. |
| E073 | AVMM | Length one less than payload depth | Parameterized depth boundary | Different from fixed 64/256 edges already listed. |
| E074 | AVMM | Length equal to payload depth plus address hotspot | Param sweep around exact resource boundary | Combines depth limit with decode hot spot. |
| E075 | AVMM | Zero-length ordered barrier | Release or acquire with `L=0` at high address | Barrier packets without payload are easy to under-test. |
| E076 | AVMM | Maximum length nonincrement read | `L=256`, nonincrement, one address | Required once nonincrement is part of the contract. |

### 4.3 Queue, Credit, and Buffer Threshold Boundaries -- 13 planned cases

| Canonical ID | Bus | Scenario | Planned stimulus | Why it exists |
|---|---|---|---|---|
| E077 | AVMM | Packet queue exactly full then one more read | Fill queue to `PKT_QUEUE_DEPTH` | Defines off-by-one behavior at queue full. |
| E078 | AVMM | Packet queue drains from full to empty with alternating reads/writes | Fill, then release naturally | Checks head/tail wrap at both extremes. |
| E079 | AVMM | Payload free count at one entry remaining | Leave exactly one line free, then send `L=1` | Smallest successful allocation boundary. |
| E080 | AVMM | Payload free count at one entry remaining, send `L=2` | Same setup, `L=2` | Smallest failing allocation boundary. |
| E081 | AVMM | Upload credit exact-fit response | Fill upload credits exactly with one long read reply | Exact-fit boundaries often hide miscount bugs. |
| E082 | AVMM | Upload credit one word short | Long read when one credit short | Needed to prove backpressure rather than silent truncation. |
| E083 | AVMM | Header queue one slot from full with internal CSR request | External load nearly full plus CSR read | Validates reserved-slot arithmetic at boundary. |
| E084 | AXI4 | Reorder queue one slot from full | OoO enabled, fill scoreboard to `N-1`, then one more | Defines safe saturation point. |
| E085 | AXI4 | Reorder queue exact full | Fill to `N`, then observe stall semantics | Pairs with E084 to catch off-by-one bugs. |
| E086 | AXI4 | Reorder queue wrap boundary | Long run forcing ID/slot wrap | Boundary condition distinct from ordinary occupancy. |
| E087 | AVMM | Credit return and immediate reallocate same cycle | Response frees credits while next request admits | Checks combinational/sequential ordering assumptions. |
| E088 | AVMM | Simultaneous internal and external slot demand at `N-1` occupancy | One external and one internal arrive together | Arbitration boundaries are frequent tie-break bugs. |
| E089 | AVMM | Soft reset at near-full payload | Reset while every pool is near threshold | Proves full reclamation from worst legal occupancy. |

### 4.4 Ordering and Atomic Contract Boundaries -- 13 planned cases

| Canonical ID | Bus | Scenario | Planned stimulus | Why it exists |
|---|---|---|---|---|
| E090 | AVMM | Nonincrement acquire read | Fixed-address acquire burst | Contract interaction between nonincrement and ordering must be explicit. |
| E091 | AVMM | Nonincrement release write | Fixed-address release burst | Same for write-side barrier semantics. |
| E092 | AVMM | Atomic with full mask `0xFFFFFFFF` | Atomic writeback touches all bits | Mask extremes deserve direct boundary coverage. |
| E093 | AVMM | Atomic with zero mask | Atomic request that should degenerate to read | Good place for contract ambiguity unless defined. |
| E094 | AVMM | Atomic on CSR boundary address | Address near internal/external split | Confirms atomic decode never crosses into unsupported internal path. |
| E095 | AVMM | Two domains issuing acquire on same address | Domains 0 and 1 contend at one location | Domain logic should isolate ordering, not alias on address. |
| E096 | AVMM | Release on domain 15 with all lower domains busy | Highest domain index boundary | Array indexing bugs tend to hide at the top entry. |
| E097 | AVMM | Atomic immediately after release drain completion | Issue atomic on the first release-free cycle | Catches stale serialization flags. |
| E098 | AVMM | Acquire immediately before atomic reply | Force boundary between hold logic and lock release | Another stale-flag hotspot. |
| E099 | AXI4 | OoO enabled, same-domain acquire/release pair | One domain, multiple outstanding | Needed once AXI4+ordering is a supported mix. |
| E100 | AXI4 | OoO enabled, 16-domain relaxed traffic plus one atomic domain | Domain fanout plus lock | Finds scoreboard pressure under maximal domain spread. |
| E101 | AVMM | Repeated barrier-only packets | Sequence of `L=0` acquire/release packets | Ensures barrier bookkeeping can drain without payload traffic. |
| E102 | AVMM | Nonincrement atomic hotspot soak | Short repeated fixed-address atomics | Closest thing to an MMIO register-file atomic workload. |

### 4.5 Reset, Timeout, and Recovery Boundaries -- 13 planned cases

| Canonical ID | Bus | Scenario | Planned stimulus | Why it exists |
|---|---|---|---|---|
| E103 | AVMM | Soft reset one cycle before read completion | Reset on the last wait cycle | Boundary between successful completion and reset discard. |
| E104 | AVMM | Soft reset one cycle after read completion | Reset immediately after reply enqueue | Checks that completed data is not double-freed. |
| E105 | AVMM | Soft reset one cycle before write acceptance | Reset at write boundary | Write-visibility contract must be explicit at the edge. |
| E106 | AVMM | Read timeout exactly at threshold | Stall for `RD_TIMEOUT_CYCLES` | Off-by-one timeout bugs are common. |
| E107 | AVMM | Read timeout one cycle below threshold | Stall for `RD_TIMEOUT_CYCLES-1` | Companion case to E106. |
| E108 | AVMM | Write timeout exactly at threshold | Waitrequest held for `WR_TIMEOUT_CYCLES` | Same off-by-one on write side. |
| E109 | AVMM | Write timeout one cycle below threshold | Companion to E108 | Ensures no premature timeout. |
| E110 | AXI4 | Reset while reorder queue non-empty but no payload outstanding | AXI4 OoO mid-flight edge | Distinguishes scoreboard reset from payload reset. |
| E111 | AXI4 | Reset while last reordered beat returns | Completion/reset race | Historically a common fencepost bug. |
| E112 | AVMM | Recovery packet on first cycle after timeout clear | Issue new read immediately after timeout handling | Proves hub does not need a dead cycle to recover. |
| E113 | AVMM | Consecutive different timeouts | Read timeout then write timeout | Ensures error bookkeeping resets correctly between modes. |
| E114 | AVMM | Reset during legal bubble-heavy packet | Reset with parser mid-bubble | Mixes two fragile contracts: framing tolerance and reset. |
| E115 | AVMM | Hardware reset during internal CSR response | Reset while internal path, not external, is active | Internal path deserves its own boundary case. |

### 4.6 Configuration Tuple Boundaries -- 13 planned cases

| Canonical ID | Bus | Scenario | Planned stimulus | Why it exists |
|---|---|---|---|---|
| E116 | AVMM | Smallest legal fully featured config | Minimal depths, ordering and atomics on | Defines lower bound for supported configuration tuple. |
| E117 | AVMM | Largest supported queue/depth tuple | Max depths everywhere | Upper bound needs a dedicated plan row. |
| E118 | AVMM | OoO enabled with smallest reorder window | AXI4 OoO, window=1 | Distinguishes “enabled but ineffective” from actually broken. |
| E119 | AVMM | Ordering enabled with zero external traffic | Barrier-only config sanity | Removes external bus effects from ordering checks. |
| E120 | AVMM | Atomic enabled with internal slots minimum | Tight recovery path plus lock feature | Couples two sensitive knobs. |
| E121 | AVMM | Nonincrement plus max burst plus minimal payload headroom | Deliberately harsh legal tuple | Good boundary for future integration regressions. |
| E122 | AXI4 | OoO plus smallest payload depth that still claims support | Stress advertised capability boundary | Prevents overclaiming supported tuples. |
| E123 | AVMM | Max domain count plus minimal CSR reservation | Domain table max with scarce internal slots | Another array-boundary plus starvation mix. |
| E124 | AVMM | Feature tuple with ordering off but atomics on | Legal asymmetric config | Needs explicit plan coverage if capability register permits it. |
| E125 | AVMM | Feature tuple with atomics off but ordering on | Complementary asymmetric config | Same reason as E124. |
| E126 | AVMM | Feature tuple with store-and-forward off in trusted-link mode | Trusted link optimization boundary | Prevents the optimization path from being entirely undocumented. |
| E127 | AVMM | Feature tuple with HUB_CAP disabled | Minimal observability config | Tooling must still behave sanely without optional metadata. |
| E128 | AVMM | Feature tuple matching feb_system integration exactly | Canonical integration config snapshot | Keeps the standalone plan anchored to the real system tuple. |
