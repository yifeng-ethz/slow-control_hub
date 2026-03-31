# SC_HUB v2 DV — Edge Cases

**Parent:** [DV_PLAN.md](DV_PLAN.md)
**ID Range:** T400-T449
**Total:** 50 cases
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
