# SC_HUB v2 DV — Basic Functional Cases

**Parent:** [DV_PLAN.md](DV_PLAN.md)
**ID Range:** T001-T128 (legacy v1), T200-T249 (new v2)
**Total:** 155 cases

This document covers bring-up, protocol correctness, and basic feature validation. Every test here must pass before performance, edge, or error tests are meaningful.

---

## 1. SC Basic Transactions (SC_B) -- 24 cases

Single and burst read/write to representative system addresses. Verifies the hub correctly translates SC packets to bus transactions and assembles reply packets.

| ID | Method | Bus | Scenario | Iter | Stimulus | Checker | System Ref |
|----|--------|-----|----------|------|----------|---------|------------|
| T001 | D | AVMM | Single read, scratch pad addr 0x000000 | 1 | `send_read(0x000000, 1)` | `expect_read_reply(mem[0x000000])` | -> SC-001 |
| T002 | D | AVMM | Single read, control CSR addr 0x00FC04 | 1 | `send_read(0x00FC04, 1)` | `expect_read_reply(mem[0x00FC04])` | -> SC-002 |
| T003 | D | AVMM | Single read, datapath CSR addr 0x008002 (frame_rcv[0]) | 1 | `send_read(0x008002, 1)` | reply data matches BFM memory | -> SC-003 |
| T004 | D | AVMM | Single write + readback, scratch pad | 64 | `send_write(addr_i, 1, data_i); send_read(addr_i, 1)` | readback == data_i | -> SC-004 |
| T005 | D | AVMM | Burst read, scratch pad 64 words | 1 | `send_burst_read(0x000000, 64)` | all 64 words in reply match BFM memory | -> SC-020 |
| T006 | D | AVMM | Burst write, scratch pad 64 words | 1 | `send_burst_write(0x000000, 64, data[])` | readback all 64 correct | -> SC-021 |
| T007 | D | AVMM | Max burst read (256 words) | 1 | `send_burst_read(0x000000, 256)` | all 256 words correct | -> SC-022 |
| T008 | D | AVMM | Max burst write (256 words) | 1 | `send_burst_write(0x000000, 256, data[])` | all 256 written to BFM | -> SC-022 |
| T009 | D | AVMM | Min burst (1-word payload) | 1 | `send_read(0x000000, 1)` | preamble-addr-header-data-trailer correct | -> SC-023 |
| T010 | D | AVMM | Reply CSR response header format (read) | 1 | `send_read(0x001000, 1)` | word 2: bits[15:0]=1, bit[16]=1, bits[29:28]=00, bits[31:30]=00 | -- |
| T011 | D | AVMM | Reply CSR response header format (write) | 1 | `send_write(0x001000, 1, 0xABCD)` | word 2 format identical to read reply | -- |
| T012 | D | AVMM | FPGA ID echo | 1 | `send_read(0x000000, 1)` with FPGA_ID=0xABCD | reply preamble bits[23:8]=0xABCD | -> SC-097 |
| T013 | D | AXI4 | Single read | 1 | `send_read(0x000000, 1)` | AR handshake, ARLEN=0, RLAST=1, data correct | -- |
| T014 | D | AXI4 | Single write | 1 | `send_write(0x000000, 1, 0x1234)` | AW/W handshake, WLAST=1, BRESP=OKAY | -- |
| T015 | D | AXI4 | Burst read 8 words | 1 | `send_burst_read(0x000000, 8)` | ARLEN=7, 8 R beats, RLAST on beat 8 | -- |
| T016 | D | AXI4 | Burst write 8 words | 1 | `send_burst_write(0x000000, 8, data[])` | AWLEN=7, WLAST on beat 8, single BRESP | -- |
| T017 | D | AXI4 | Max burst read 256 | 1 | `send_burst_read(0x000000, 256)` | ARLEN=255, 256 R beats correct | -- |
| T018 | D | AXI4 | Max burst write 256 | 1 | `send_burst_write(0x000000, 256, data[])` | AWLEN=255, WLAST on beat 256 | -- |
| T019 | D | AXI4 | AWSIZE/ARSIZE always 010 | 1 | any read + any write | AWSIZE=010, ARSIZE=010 | -- |
| T020 | D | AXI4 | AWBURST/ARBURST always INCR (01) | 1 | burst read + burst write | AWBURST=01, ARBURST=01 | -- |
| T021 | D | AXI4 | AWID/ARID/BID/RID always 0 (OoO=off) | 1 | any transaction | all IDs = 0 | -- |
| T022 | D | AXI4 | WSTRB always 4'b1111 | 1 | any write | WSTRB = 4'b1111 | -- |
| T023 | D | AXI4 | AW before or simultaneous with first W | 1 | burst write | no W beat before AW handshake | -- |
| T024 | D | AXI4 | Reply format identical to AVMM path | 1 | CSR read via AXI4 | response header matches AVMM test T010 | -- |

---

## 2. Store-and-Forward Validation (SF) -- 18 cases

Verifies that the download path buffers and validates the complete write packet before committing to the bus. Malformed packets must be dropped silently -- no partial write may reach the interconnect.

| ID | Method | Bus | Scenario | Iter | Stimulus | Checker | System Ref |
|----|--------|-----|----------|------|----------|---------|------------|
| T025 | D | AVMM | No bus write until trailer validated | 1 | `send_burst_write(0x000, 16, data[])`, sample `avm_m0_write` every cycle during RX | `avm_m0_write=0` until after trailer | -- |
| T026 | D | AXI4 | No AXI4 W/AW until trailer validated | 1 | same as T025 on AXI4 | `AWVALID=0, WVALID=0` during RX | -- |
| T027 | D | AVMM | Missing trailer -> drop | 16 | send write L=8, omit K28.4 (send non-K data) | PKT_DROP_CNT++, no bus write | -> SC-025 |
| T028 | D | AVMM | Length > 256 -> drop | 1 | send write L=257 | PKT_DROP_CNT++, no bus activity | -- |
| T029 | D | AVMM | Length = 0 -> graceful handling | 1 | send write L=0 | trailer expected immediately; handled without hang | -- |
| T030 | D | AVMM | Data count short (L=8, only 4 words) -> drop | 16 | declare L=8, send 4 data words + trailer | PKT_DROP_CNT++ | -> SC-027 |
| T031 | D | AVMM | Data count long (L=4, send 8 words) -> drop | 16 | declare L=4, send 8 data words + trailer | PKT_DROP_CNT++ | -> SC-027 |
| T032 | D | AVMM | Truncated mid-data (timeout) -> rollback | 16 | send 8 of 16 words, then silence | rollback, PKT_DROP_CNT++ | -> SC-026 |
| T033 | D | AVMM | Truncated after preamble only | 1 | send preamble, then silence | rollback, no bus activity | -> SC-026 |
| T034 | D | AVMM | Wrong data type (not SC) -> ignore | 1 | preamble bits[31:26]="001111" | no pkt_valid, no drop count (not SC) | -> SC-024 |
| T035 | D | AVMM | FIFO overflow during RX -> rollback | 1 | fill S&F FIFO nearly full, inject overflowing packet | second packet dropped | -- |
| T036 | D | AVMM | Valid packet after drop -> recovery | 16 | malformed then valid | second packet succeeds | -> SC-113 |
| T037 | D | AVMM | 3 consecutive drops then valid | 1 | 3x malformed + 1x valid | PKT_DROP_CNT=3, fourth succeeds | -> SC-113 |
| T038 | D | AVMM | Read is NOT store-and-forward | 1 | single read L=1 | bus read issued at DISPATCH, no trailer wait | -- |
| T039 | D | AVMM | Skip words (K28.5) between write data | 1 | write L=4, K28.5 skip words interspersed | skip words filtered, 4 real words to slave | -- |
| T040 | D | AXI4 | Drop -> no AXI4 channel activity | 1 | malformed write on AXI4 | no AW/W/AR activity | -- |
| T041 | D | AVMM | Consecutive preambles (no trailer for first) | 1 | preamble -> preamble (second packet) | first abandoned, second processed | -- |
| T042 | D | AVMM | Drop does not corrupt BFM memory | 16 | pre-fill BFM with known pattern, send malformed write | BFM memory unchanged | -- |

---

## 3. Internal CSR Registers (CSR) -- 18 cases

Verifies the internal CSR register map (0xFE80-0xFE9F). CSR transactions never reach the bus -- they are handled inside the hub.

| ID | Method | Bus | Scenario | Iter | Stimulus | Checker | System Ref |
|----|--------|-----|----------|------|----------|---------|------------|
| T043 | D | AVMM | Read CSR ID (0xFE80+0x000) | 1 | `send_read(0xFE80, 1)` | returns 0x53480000 | -- |
| T044 | D | AVMM | Read CSR VERSION | 1 | `send_read(0xFE81, 1)` | YY=26, fields match RTL constants | -- |
| T045 | D | AVMM | Write/read CTRL (enable bit) | 1 | write CTRL bit0=1, readback | bit0=1 | -- |
| T046 | D | AVMM | Read STATUS (idle state) | 1 | read STATUS when hub idle | busy=0, flushing=0 | -- |
| T047 | D | AVMM | ERR_FLAGS write-1-to-clear | 1 | trigger timeout -> ERR_FLAGS.rd_timeout=1 -> write 1 -> read | bit cleared | -- |
| T048 | D | AVMM | ERR_COUNT saturation | 1 | trigger 260+ errors | ERR_COUNT at max, no wrap | -- |
| T049 | D | AVMM | SCRATCH register R/W | 1 | write 0xDEADBEEF, read, write 0x12345678, read | both match | -- |
| T050 | D | AVMM | GTS snapshot | 1 | read GTS_SNAP_HI -> triggers snapshot -> read GTS_SNAP_LO | LO captured at HI read time | -- |
| T051 | D | AVMM | FIFO_CFG default (S&F bit) | 1 | read FIFO_CFG at startup | bit0 (download S&F) = 1 | -- |
| T052 | D | AVMM | FIFO_STATUS / USEDW during traffic | 1 | inject traffic, read FIFO_STATUS, DOWN_USEDW, UP_USEDW | non-zero, consistent | -- |
| T053 | D | AVMM | EXT_PKT_RD/WR_CNT | 1 | 5 reads + 3 writes -> read counters | 5 and 3 | -- |
| T054 | D | AVMM | EXT_WORD_RD/WR_CNT | 1 | burst read L=10 + burst write L=20 -> read counters | 10 and 20 | -- |
| T055 | D | AVMM | LAST_RD_ADDR/DATA | 1 | read from 0x1234 -> read LAST_RD_ADDR, LAST_RD_DATA | addr=0x1234, data=last read word | -- |
| T056 | D | AVMM | LAST_WR_ADDR/DATA | 1 | write 0xCAFEBABE to 0x5678 -> read LAST_WR_ADDR, LAST_WR_DATA | match | -- |
| T057 | D | AVMM | PKT_DROP_CNT after drops | 1 | 3 malformed packets -> read PKT_DROP_CNT | = 3 | -- |
| T058 | D | AVMM | Invalid CSR offset (0xFE80+0x01B) | 1 | read unmapped CSR slot inside the hub CSR window | returns 0xEEEEEEEE, response=SLAVEERROR | -- |
| T059 | D | AVMM | Burst write to CSR -> reject | 1 | burst write L=2 to CSR address | SLAVEERROR response | -- |
| T060 | D | AXI4 | CSR read on AXI4 config | 1 | read CSR ID via AXI4 | same result as T043 (CSR bypasses bus handler) | -- |

---

## 4. Backpressure and Flow Control (BP) -- 12 cases

Verifies hub behavior when the uplink (reply path) is congested or when the bus slave stalls.

| ID | Method | Bus | Scenario | Iter | Stimulus | Checker | System Ref |
|----|--------|-----|----------|------|----------|---------|------------|
| T077 | D | AVMM | Uplink not ready during entire reply | 1 | deassert `aso_to_uplink_ready` during read reply | reply buffered in BP FIFO, delivered when ready reasserts | -- |
| T078 | D | AVMM | Uplink toggle every 2 cycles | 1 | burst read L=64, toggle ready every 2 cycles | all 64 words delivered, no corruption | -- |
| T079 | D | AVMM | BP FIFO half-full -> linkin_ready deasserts | 1 | fill BP FIFO past 256 words | o_linkin_ready=0; resume drain -> o_linkin_ready=1 | -- |
| T080 | D | AVMM | BP FIFO full -> no overflow | 1 | fill BP FIFO to capacity | no overflow, hub stalls gracefully | -- |
| T081 | D | AVMM | AVMM waitrequest stall 50 cycles | 1 | BFM asserts waitrequest 50 cycles on write | hub waits, no data loss, write completes | -> SC-037 |
| T082 | D | AVMM | AVMM read latency 100 cycles | 1 | BFM read latency = 100 | hub waits, reply correct | -> SC-036 |
| T083 | D | AVMM | BP FIFO packet integrity (3 varied replies) | 1 | 3 reply packets (L=1, L=16, L=64) drained slowly | SOP/EOP framing correct, no inter-packet leakage | -- |
| T084 | D | AXI4 | ARREADY stall 50 cycles | 1 | AXI4 slave deasserts ARREADY 50 cycles | hub holds ARVALID, read completes | -- |
| T085 | D | AXI4 | WREADY toggle every other cycle | 1 | AXI4 slave toggles WREADY on burst write | write beats pause correctly, WLAST on correct beat | -- |
| T086 | D | AXI4 | AWREADY stall 30 cycles | 1 | AXI4 slave deasserts AWREADY 30 cycles | hub holds AWVALID | -- |
| T087 | D | AVMM | Back-to-back commands under sustained BP | 128 | 128 commands, uplink ready=0 for random intervals | all 128 replies eventually delivered in order | -> SC-017 |
| T088 | D | AVMM | Downlink ready deasserted -> no data accepted | 1 | send packet when o_linkin_ready=0 | data not accepted, not lost | -- |

---

## 5. Mute Mask and Reply Suppression (MUTE) -- 6 cases

| ID | Method | Bus | Scenario | Iter | Stimulus | Checker | System Ref |
|----|--------|-----|----------|------|----------|---------|------------|
| T089 | D | AVMM | mask_s=1 (SciFi mute) -> no reply | 1 | read with mask_s=1 | bus read completes, no reply on uplink | -- |
| T090 | D | AVMM | mask_r=1 (mute all) -> no reply | 1 | write with mask_r=1 | bus write completes, no reply | -- |
| T091 | D | AVMM | mask_m=1 (Mupix mute) -> no reply | 1 | read with mask_m=1 | no reply | -- |
| T092 | D | AVMM | mask_t=1 (Tile mute) -> no reply | 1 | read with mask_t=1 | no reply | -- |
| T093 | D | AVMM | All masks=0 -> reply emitted | 1 | read with no mute | reply present | -- |
| T094 | D | AVMM | Muted then unmuted -> exactly one reply | 1 | muted read, then unmuted read | exactly 1 reply (for second command) | -- |

---

## 6. Packet Format Edge Cases (PKT) -- 10 cases

| ID | Method | Bus | Scenario | Iter | Stimulus | Checker | System Ref |
|----|--------|-----|----------|------|----------|---------|------------|
| T095 | D | AVMM | Skip words between header fields | 1 | K28.5 skip words between preamble, address, length | skip filtered, transaction succeeds | -> SC-081 |
| T096 | D | AVMM | Skip words between write data | 1 | K28.5 skips between data words | filtered, correct data written | -- |
| T097 | D | AVMM | sc_type="00" BurstRead | 1 | BurstRead with L=8 | handled as burst read | -- |
| T098 | D | AVMM | sc_type="01" BurstWrite | 1 | BurstWrite with L=8 | handled as burst write | -- |
| T099 | D | AVMM | sc_type="10" Read | 1 | single Read | L=1, single word | -- |
| T100 | D | AVMM | sc_type="11" Write | 1 | single Write | L=1, single word | -- |
| T101 | D | AVMM | Address bits [23:16] non-zero | 1 | start_address=0xFF1234 | only [15:0]=0x1234 used as bus address | -- |
| T102 | D | AVMM | Reply K-code verification | 1 | any transaction | reply word 0: datak[0]=1, data[7:0]=K28.5; trailer: datak[0]=1, data[7:0]=K28.4 | -- |
| T103 | D | AVMM | Reserved preamble bits zero | 1 | verify hub ignores reserved bits in preamble | no side-effect from non-zero reserved | -- |
| T104 | D | AVMM | Reserved address bits zero | 1 | verify hub ignores bits [31:28] of address word | no side-effect | -- |

---

## 7. Reset and Recovery (RST) -- 8 cases

| ID | Method | Bus | Scenario | Iter | Stimulus | Checker | System Ref |
|----|--------|-----|----------|------|----------|---------|------------|
| T105 | D | AVMM | Reset during IDLE | 1 | reset for 10 cycles in IDLE | hub returns to IDLE, CSR counters cleared | -> RST-002 |
| T106 | D | AVMM | Reset during burst read | 1 | reset mid-AVMM-read | hub recovers, next packet succeeds | -> RST-006 |
| T107 | D | AVMM | Reset during burst write | 1 | reset mid-write (data partially drained from S&F FIFO) | clean recovery | -> RST-006 |
| T108 | D | AVMM | Reset during reply TX | 1 | reset while reply packet being transmitted | partial reply discarded, hub recovers | -- |
| T109 | D | AVMM | Reset clears all FIFOs | 1 | after reset: verify download FIFO, read FIFO, BP FIFO all empty | all empty | -- |
| T110 | D | AVMM | CSR CTRL.reset bit (software reset) | 1 | write CTRL bit 2=1 via SC | same effect as hardware reset -- FIFOs cleared, IDLE | -- |
| T111 | D | AVMM | Reset + immediate SC command | 64 | reset deassert -> SC command at cycle N (N=1..64) | first command after reset succeeds | -> RST-009 |
| T112 | D | AVMM | SC command across reset boundary | 64 | SC command -> reset -> SC command | second command works, no stale state | -> SC-045 |

---

## 8. UVM Parametric Sweeps (SWP) -- 6 cases

| ID | Method | Bus | Scenario | Iter | Sequence | System Ref |
|----|--------|-----|----------|------|----------|------------|
| T123 | U | BOTH | Burst length sweep (read + write) | 22 | `sc_pkt_burst_seq`: L in {1,2,3,4,8,16,32,64,128,255,256}, both read and write per length | -> SC-020..SC-022 |
| T124 | U | BOTH | Address sweep (external + CSR boundary) | 20 | `sc_pkt_addr_sweep_seq`: addr in {0x0000, 0x0001, 0x0100, 0x1000, 0x7FFF, 0xFE7F, 0xFE80(CSR), 0xFE9F, 0xFEA0, 0xFFFF} | -> SC-049..SC-064 |
| T125 | U | BOTH | Slave latency sweep | 18 | BFM latency in {1,2,4,8,16,32,64,100,199} cycles | -> SC-036..SC-037 |
| T126 | U | BOTH | Error injection sweep | 14 | {read,write} x {OKAY,SLAVEERROR,DECODEERROR} + read timeout | -> SC-015..SC-016 |
| T127 | U | AVMM | Inter-command gap sweep | 128 | gap in {0..15} cycles x {BurstRead, BurstWrite, Read, Write, CSR_Read, CSR_Write, Muted_Read, Malformed} | -> SC-081..SC-096 |
| T128 | U | BOTH | Mixed traffic soak (100-pkt sequences) | 200 | 100-packet sequence with LCG-selected params. Intersperse 10 malformed packets. | -> SC-035, SC-113..SC-128 |

---

## 9. v2 Split-Buffer Functional (BUF) -- 10 cases

Bring-up for the 8-subFIFO split-buffer architecture, linked-list payload RAM, and malloc/free module. Derived from TLM model architecture (TLM_PLAN section 2).

| ID | Method | Bus | Scenario | Stimulus | Checker | TLM Source |
|----|--------|-----|----------|----------|---------|------------|
| T200 | D | AVMM | Ext write: payload stored in ext_down_pld linked list | `send_write(0x000, 8, data[])` | data traverses ext_down_pld, read-back from bus matches. Verify pld_head_ptr chain is 8 lines long. | TLM 2.2 |
| T201 | D | AVMM | Ext read: reply payload stored in ext_up_pld | `send_read(0x000, 16)` | 16 words arrive via ext_up_pld linked list. Verify pld chain freed after reply TX. | TLM 2.2 |
| T202 | D | AVMM | Int CSR read: uses int_down_hdr + int_up_pld path | `send_read(0xFE80, 1)` | transaction routed through internal path (classifier). BFM sees no bus activity. | TLM 2.1 |
| T203 | D | AVMM | Int CSR write: uses int_down_hdr + int_down_pld | `send_write(0xFE86, 1, 0xDEAD)` | SCRATCH register updated. Routed via internal path. | TLM 2.1 |
| T204 | D | AVMM | Malloc basic: allocate + free + verify free_count | `send_write(0x000, 64, data[]); wait reply` | free_count returns to initial value after reply TX frees payload. Assert A37. | TLM 3.3 |
| T205 | D | AVMM | Malloc sequential: 4 writes fill ext_down_pld | 4x `send_write(0x000, 128, data[])` | 4 x 128 = 512 words fills default depth. 5th write must see backpressure (o_linkin_ready=0). | TLM 2.4 |
| T206 | D | AVMM | cmd_order_fifo: read then write interleave | `send_read; send_write; send_read; send_write` | replies arrive in command order (OoO=off). cmd_order_fifo correctly tracks int/ext routing. | TLM 2.1 |
| T207 | D | AVMM | reply_order_fifo: 8 back-to-back reads | 8x `send_read(addr_i, 1)` | all 8 replies in command issue order. reply_order_fifo depth = OUTSTANDING_LIMIT. | TLM 2.6 |
| T208 | D | AVMM | All 8 subFIFOs non-empty simultaneously | mixed workload: ext write + ext read + int write + int read, slow BFM | at some cycle, all 8 subFIFOs have at least 1 entry. Coverage bin CP_FREELIST hit. | TLM 12.6 #10 |
| T209 | D | AVMM | Payload deallocation chain walk | `send_read(0x000, 64)` with fragmented free list | free walks 64-line chain. After free, free_count increases by 64. | TLM 3.3 |

---

## 10. v2 Out-of-Order Functional (OOO) -- 10 cases

Bring-up for OoO dispatch and reply assembly. Derived from TLM OOO correctness checks (OOO-C01..C07).

| ID | Method | Bus | Scenario | Stimulus | Checker | TLM Source |
|----|--------|-----|----------|----------|---------|------------|
| T210 | D | AXI4 | OoO reply data integrity | OOO_ENABLE=true. 4 reads: addr A (fast=2cy), B (slow=50cy), C (fast=2cy), D (slow=50cy) | All 4 replies contain correct data regardless of completion order. | OOO-C01 |
| T211 | D | AXI4 | OoO no reply duplication | 8 mixed reads, OoO enabled, varied latency | Each command produces exactly 1 reply. Monitor counts replies per seq_num. | OOO-C02 |
| T212 | D | AXI4 | OoO no reply loss | 8 reads + 4 writes, OoO enabled | All 12 commands produce a reply. Monitor asserts count == 12 at quiesce. | OOO-C03 |
| T213 | D | AXI4 | OoO payload isolation | 4 reads: L=32, L=16, L=8, L=4. Fast/slow interleave. OoO enabled. | Each reply payload matches BFM memory exactly. No cross-chain corruption. | OOO-C04 |
| T214 | D | AXI4 | OoO free-list consistency | 12 mixed transactions, OoO enabled | After all complete and replies TX'd, free_count == RAM_DEPTH for all 4 pools. Assert A37. | OOO-C05 |
| T215 | D | AXI4 | OoO runtime disable reverts to in-order | OOO_ENABLE=true, OOO_CTRL.enable=1. Issue 4 reads. Toggle OOO_CTRL.enable=0 via CSR write. Issue 4 more reads. | First 4: may complete out of order. Second 4: replies in strict command order. | OOO-C06 |
| T216 | D | AXI4 | OoO mixed int/ext: internal bypasses external | OoO=on. 4 slow ext reads (50cy) + 4 fast int CSR reads (2cy) | Int CSR replies arrive before ext replies. No starvation (both paths drain). | OOO-C07 |
| T217 | D | AXI4 | OoO with different ARID values | OOO_ENABLE=true. Issue reads to 4 addresses with varied latency. | AXI4 master uses different ARID for concurrent reads. Responses reordered by RID. | TLM 2.6 |
| T218 | D | AVMM | OoO disabled: strict in-order reply | OOO_ENABLE=false. 4 reads with varied BFM latency. | Replies always in command order, even though BFM could complete faster. | TLM 2.6 |
| T219 | D | AXI4 | OoO scoreboard basic | OOO_ENABLE=true. 2 reads: fast then slow. | Fast read reply emitted first. Scoreboard tracks correct seq_num mapping. | TLM 2.6 |

---

## 11. v2 Atomic RMW Functional (ATM) -- 10 cases

Bring-up for hub-internal atomic read-modify-write. Derived from TLM ATOM correctness checks (ATOM-C01..C05).

| ID | Method | Bus | Scenario | Stimulus | Checker | TLM Source |
|----|--------|-----|----------|----------|---------|------------|
| T220 | D | AVMM | Atomic RMW basic: read-modify-write to scratch pad | `send_atomic_rmw(0x000, mask=0xFF, modify=0xAB, RELAXED, dom=0)` | BFM[0x000] = (original & ~0xFF) | (0xAB & 0xFF). Reply contains original read data. | TLM 2.7 |
| T221 | D | AVMM | Atomic RMW atomicity: two concurrent atomics | atomic_rmw to addr X (mask=0x00FF, mod=0x11), then atomic_rmw to addr X (mask=0xFF00, mod=0x22) | Final BFM[X] reflects both modifications. No lost update. | ATOM-C01 |
| T222 | D | AVMM | Atomic lock exclusion | Issue atomic_rmw (slow BFM=50cy). Simultaneously queue normal read. | avm_m0_lock=1 during atomic. Normal read does not issue until lock released. | ATOM-C02 |
| T223 | D | AVMM | Atomic: internal CSR bypass during lock | Issue atomic_rmw (slow BFM). Queue int CSR read to 0xFE80. | CSR read completes during atomic lock (doesn't use bus). | ATOM-C03 |
| T224 | D | AVMM | Atomic: read phase SLAVEERROR -> skip write | BFM returns SLAVEERROR on read phase of atomic | Write phase skipped. BFM memory unchanged. Reply contains error code. | ATOM-C04 |
| T225 | D | AVMM | Atomic reply format | `send_atomic_rmw(0x100, mask=0xFFFF, modify=0x1234, RELAXED, dom=0)` | Reply word 2: response=OK. Reply data: original pre-modify value. | ATOM-C05 |
| T226 | D | AXI4 | Atomic RMW on AXI4 (AxLOCK=01) | `send_atomic_rmw(0x000, ...)` on AXI4 config | ARLOCK=01 on read phase, AWLOCK=01 on write phase. Correct data. | TLM 2.7 |
| T227 | D | AVMM | Atomic with 32-bit full mask | `send_atomic_rmw(0x200, mask=0xFFFFFFFF, modify=0x12345678)` | BFM[0x200] = 0x12345678 (full overwrite). Reply = old value. | TLM 2.7 |
| T228 | D | AVMM | Atomic with zero mask (no-op) | `send_atomic_rmw(0x200, mask=0x00000000, modify=0xFFFFFFFF)` | BFM[0x200] unchanged. Reply = current value. Atomic is effectively a read. | TLM 2.7 |
| T229 | D | AVMM | Atomic + ordered: relaxed atomic (no ordering) | `send_atomic_rmw(0x300, ..., ORDER=RELAXED, dom=0)` | Atomic proceeds without ordering overhead. ORDER=00 in reply echo. | TLM 2.9.6 |

---

## 12. v2 Ordering Functional (ORD) -- 20 cases

Bring-up for release/acquire/relaxed ordering semantics. Derived from TLM ORD correctness checks (ORD-C01..C06) and invariants (ORD-I01..I05).

| ID | Method | Bus | Scenario | Stimulus | Checker | TLM Source |
|----|--------|-----|----------|----------|---------|------------|
| T230 | D | AVMM | RELAXED pass-through (zero overhead) | `send_ordered_write(0x000, 1, data, RELAXED, dom=0, epoch=0)` | Transaction completes with same latency as T004 (no ordering overhead). Assert A32. | ORD-I04 |
| T231 | D | AVMM | RELEASE basic: single domain drain | 4x `send_write(RELAXED, dom=1)` + 1x `send_write(RELEASE, dom=1)` | Release does not retire until all 4 prior writes in dom 1 get bus write response. | ORD-C02 |
| T232 | D | AVMM | RELEASE: no younger bypass | `send_write(RELAXED, dom=1)` x4, `send_write(RELEASE, dom=1)`, `send_write(RELAXED, dom=1)` x4 | No younger-than-release write in dom 1 completes before the release. | ORD-C01 |
| T233 | D | AVMM | ACQUIRE basic: blocks younger in domain | `send_read(ACQUIRE, dom=2)` + 10x `send_read(RELAXED, dom=2)` | None of the 10 RELAXED reads complete before the ACQUIRE. | ORD-C03 |
| T234 | D | AVMM | ACQUIRE visibility: sees prior RELEASE writes | `send_write(RELEASE, dom=1)` to addr X, then `send_read(ACQUIRE, dom=1)` from addr X | ACQUIRE read data reflects the RELEASE write (visibility rule R4). | ORD-C04 |
| T235 | D | AVMM | Cross-domain independence | dom 0: ACQUIRE (slow BFM 100cy). dom 1: 4x RELAXED reads (fast BFM 2cy). | Dom 1 reads complete without waiting for dom 0 acquire. Assert A29. | ORD-C05 |
| T236 | D | AVMM | Ordering + atomic combined | `send_write(RELEASE, dom=1)`, then `send_atomic_rmw(RELAXED, dom=1)` | Atomic waits for release to complete (same-domain). Then atomic proceeds with bus lock. | ORD-C06 |
| T237 | D | AVMM | ORDER/ORD_DOM_ID echo in reply | `send_read(ACQUIRE, dom=3, epoch=42)` | Reply word 1 bits[31:30]=10 (ACQUIRE), word 2 bits[31:28]=3, bits[27:20]=42. | TLM 2.3 |
| T238 | D | AVMM | Domain 0 backward compatibility | `send_read(0x000, 1)` (old packet, no ordering fields) | ORDER=00, ORD_DOM_ID=0, ORD_EPOCH=0 by default. Zero overhead. | TLM 2.7 |
| T239 | D | AVMM | Release with zero outstanding writes (instant drain) | `send_write(RELEASE, dom=1)` when no prior writes in dom 1 | Release retires immediately (drain is instant). No deadlock. | TLM 12.6 #13 |
| T240 | D | AVMM | Back-to-back releases in same domain | `send_write(RELEASE, dom=1)`, then immediately `send_write(RELEASE, dom=1)` | Second release waits for first to complete. Both eventually retire. | TLM 12.6 #14 |
| T241 | D | AVMM | Epoch monotonicity within domain | Sequence: epoch=1(RELAXED), epoch=2(RELAXED), epoch=3(RELEASE), epoch=4(RELAXED) in dom=1 | Bus transactions issued with monotonically non-decreasing epochs. Assert A33. | ORD-I05 |
| T242 | D | AVMM | Acquire blocks both issue AND completion | ACQUIRE in dom=1 (slow 50cy). Meanwhile, a younger RELAXED read in dom=1 is admitted. | Younger read does not issue to bus AND does not have reply assembled, even if it could. Assert A31. | ORD-I03 |
| T243 | D | AXI4 | OoO + ordering: cross-domain reorder | OoO=on. Dom 0: ACQUIRE (slow). Dom 1: RELAXED reads (fast). | Dom 1 reads reorder past dom 0 acquire (cross-domain). Dom 0 younger ops blocked. | ORD-06 |
| T244 | D | AVMM | Release drain with accepted-but-not-dispatched writes | 4 writes (RELAXED, dom=1) admitted but dispatch stalled by outstanding limit. Then RELEASE(dom=1). | Release must not retire until all 4 writes dispatch AND complete. (TLM_NOTE ISSUE 1). | TLM_NOTE #1 |
| T245 | D | AVMM | 16 domains active simultaneously | 16 concurrent transactions, one per domain. Dom 0 has ACQUIRE. | All other 15 domains proceed independently. Dom 0 held. Assert A29 for all 16. | TLM 12.6 #16 |
| T246 | D | AVMM | ORD_SCOPE field propagation | `send_ordered_write(0x000, 1, data, RELEASE, dom=1, scope=2)` | ORD_SCOPE=10 (end-to-end) echoed in reply. Hub internal tracking carries scope. | TLM 2.9.8 |
| T247 | D | AVMM | Ordering + admission revert | RELEASE admitted, payload malloc ok, but header FIFO full | Admission fails cleanly. Payload freed. Ordering state not corrupted. | TLM 12.6 #17 |
| T248 | D | AVMM | OOO_CTRL CSR read/write | Write OOO_CTRL (0xFE80+0x18) bit0=1, readback. Write bit0=0, readback. | CSR reflects written value. Runtime OoO toggle functional. | TLM_NOTE #5 |
| T249 | D | AVMM | Performance counters: release_drain_counter, acquire_hold_counter | 2 RELEASE + 3 ACQUIRE transactions | CSR release_drain_counter=2, acquire_hold_counter=3. | TLM 3.1 |
