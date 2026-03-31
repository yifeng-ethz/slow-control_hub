# SC_HUB v2 — Transaction-Level Model Plan

**IP Name:** sc_hub_v2 (Slow Control Hub)
**Author:** Yifeng Wang
**Companion:** RTL_PLAN.md, DV_PLAN.md
**Language:** Python 3 discrete-event behavioral model (originally planned as SystemC TLM 2.0; Python chosen because workspace lacks a local SystemC build — behavioral fidelity is equivalent)
**Purpose:** Behavioral modeling of the split-buffer architecture, malloc/linked-list payload management, OoO dispatch, atomic RMW, release/acquire ordering semantics, and performance characterization. Results from this model inform RTL parameterisation, software packet format co-design, and DV test case selection.

---

## 1. Motivation

The sc_hub_v2 introduces a PCIe-like split-buffer architecture with 8 subFIFOs, linked-list payload RAM, compile-time OoO support, hub-internal atomic read-modify-write, and per-domain release/acquire ordering semantics (co-designed with the MIDAS FE software packet format). These features have complex interactions that are expensive to explore at RTL level:

- **Fragmentation:** Linked-list payload allocation under mixed burst lengths creates fragmentation. How severe? At what workload does it cause admission failure?
- **OoO speedup:** When bus latency varies (e.g., different slaves at different distances in the interconnect), OoO can improve throughput. How much? At what outstanding depth does the benefit saturate?
- **Atomic RMW cost:** Holding the bus lock blocks all other transactions. What is the throughput impact under various atomic-to-normal ratios?
- **Credit exhaustion:** Upload payload reservation can fail if read completions are slow. How often does this stall the pipeline?
- **Ordering overhead:** Release drain and acquire hold block same-domain traffic. What is the throughput cost at realistic ordering ratios (~1–5%)? Is cross-domain independence preserved under load?
- **Outstanding sizing:** The default is 8 headers / 512 words. Is this sufficient for the feb_system workload? Where is the knee of the rate-latency curve?

A TLM model answers these questions in seconds (vs. hours at RTL), and its results directly drive RTL parameter defaults and DV coverage targets.

---

## 2. Architecture Overview

### 2.1 The 8 SubFIFOs

```
                    sc_hub_v2 Split Buffer Architecture

  ┌─────────────────────────── Download (cmd in) ───────────────────────────┐
  │                                                                         │
  │   SC CMD ──> [S&F Validator] ──> [Classifier] ──┬──> ext_down_hdr (1)  │
  │              (existing)          (int/ext?)      │    ext_down_pld (2)  │
  │                                                  │                      │
  │                                                  └──> int_down_hdr (3)  │
  │                                                       int_down_pld (4)  │
  │                                                                         │
  ├─────────────────────── cmd_order_fifo ──────────────────────────────────┤
  │                                                                         │
  │   [Dispatch] <── cmd_order_fifo ──> selects ext_down or int_down       │
  │       │                                                                 │
  │       ├──> Bus Handler (AVMM/AXI4) ──> ext_up_hdr (5), ext_up_pld (6) │
  │       └──> CSR Handler ──────────────> int_up_hdr (7), int_up_pld (8)  │
  │                                                                         │
  ├─────────────────────── reply_order_fifo ────────────────────────────────┤
  │                                                                         │
  │   [Reply Assembler] <── reply_order_fifo ──> selects ext_up or int_up  │
  │       │                                                                 │
  │       └──> SC REPLY out                                                 │
  │                                                                         │
  └─────────────────────────── Upload (reply out) ──────────────────────────┘
```

| # | SubFIFO | Direction | Routing | Content | Structure | Default Depth |
|---|---------|-----------|---------|---------|-----------|---------------|
| 1 | `ext_down_hdr` | Download | External | Header | Ring FIFO | 8 entries |
| 2 | `ext_down_pld` | Download | External | Payload | Linked-list RAM | 512 words |
| 3 | `int_down_hdr` | Download | Internal | Header | Ring FIFO | 4 entries |
| 4 | `int_down_pld` | Download | Internal | Payload | Linked-list RAM | 64 words |
| 5 | `ext_up_hdr` | Upload | External | Header | Ring FIFO | 8 entries |
| 6 | `ext_up_pld` | Upload | External | Payload | Linked-list RAM | 512 words |
| 7 | `int_up_hdr` | Upload | Internal | Header | Ring FIFO | 4 entries |
| 8 | `int_up_pld` | Upload | Internal | Payload | Linked-list RAM | 64 words |

**Infrastructure FIFOs (not counted as subFIFOs):**

| FIFO | Purpose | Width | Depth |
|------|---------|-------|-------|
| `cmd_order_fifo` | Records routing tag (ext/int) per admitted command | 1 bit | OUTSTANDING_EXT + OUTSTANDING_INT |
| `reply_order_fifo` | Mirrors command order for reply assembly (OoO=off) | 1 bit | same |

### 2.2 Linked-List Payload RAM

Each payload subFIFO (2, 4, 6, 8) is implemented as a RAM with an integrated malloc/free module. The RAM is word-addressable with each line structured as:

```
  ┌──────────────────────────────────────────────────────┐
  │  RAM Line (width = 32 + ADDR_BITS + 2)               │
  ├──────────┬──────────────┬──────────┬─────────────────┤
  │ data[31:0] │ next_ptr[A-1:0] │ is_last[0] │ is_free[0] │
  └──────────┴──────────────┴──────────┴─────────────────┘

  A = ceil(log2(RAM_DEPTH))
```

| Field | Bits | Description |
|-------|------|-------------|
| `data` | 31:0 | Payload data word (valid when `is_free=0`) |
| `next_ptr` | A-1:0 | Pointer to next line in the chain (linked list) |
| `is_last` | 0 | 1 = this is the last line of the allocation (next_ptr invalid) |
| `is_free` | 0 | 1 = this line is on the free list (available for malloc) |

**Malloc module (`sc_hub_malloc`):**

```
Allocation:
  Input:  request_size (number of words)
  Output: head_ptr (address of first line), success/fail

  Algorithm:
    Walk the free list, collecting `request_size` lines.
    Link them into a new chain (set next_ptr, clear is_free, set is_last on final).
    If free list has fewer than `request_size` lines: fail (no partial allocation).
    Return head_ptr of the new chain.

Deallocation:
  Input:  head_ptr (address of first line in chain to free)

  Algorithm:
    Walk the chain from head_ptr following next_ptr until is_last=1.
    Set is_free=1 on each visited line.
    Append the chain to the free list (set the last freed line's next_ptr to current free_head).
    Update free_head to head_ptr.

Free list initialization:
  All lines linked sequentially: line 0 → line 1 → ... → line N-1 (is_last=1).
  free_head = 0, free_count = N.
```

**Key properties:**
- Allocation is O(N) where N = request_size (must walk free list to collect lines)
- Deallocation is O(N) where N = chain length (must walk chain to mark free)
- Fragmentation: lines may be non-contiguous. Each pointer hop adds 1 cycle latency in RTL (pipeline the linked-list walk). For TLM, this is modeled as additional latency proportional to the number of non-contiguous segments.
- The `free_count` register tracks available lines for O(1) admission checks.

### 2.3 Header Entry Formats

```
ext_down_hdr entry (command descriptor):
  sc_type[1:0]            — BurstRead/BurstWrite/Read/Write
  fpga_id[15:0]           — FPGA identifier (echoed in reply)
  masks[3:0]              — Mute masks (R/M/S/T)
  start_address[15:0]     — Bus word address
  rw_length[15:0]         — Burst length (1–256)
  pld_head_ptr[A-1:0]     — Head pointer into ext_down_pld linked list (0 for reads)
  pld_word_count[8:0]     — Number of payload words (0 for reads)
  atomic_flag[0]          — 1 = atomic RMW command
  atomic_mask[31:0]       — Bit mask for RMW (valid when atomic_flag=1)
  atomic_modify[31:0]     — Modify data for RMW (valid when atomic_flag=1)
  order_type[1:0]         — RELAXED(00)/RELEASE(01)/ACQUIRE(10)/RSVD(11)
  ord_dom_id[3:0]         — Ordering domain identifier (16 domains)
  ord_epoch[7:0]          — Epoch/sequence tag (debug, replay, formal)
  ord_scope[1:0]          — Visibility scope (local/device/e2e/rsvd)
  seq_num[7:0]            — Global sequence number (for reply matching)

int_down_hdr entry (CSR command descriptor):
  sc_type[1:0]
  fpga_id[15:0]
  masks[3:0]
  csr_offset[4:0]         — CSR word offset within 0xFE80–0xFE9F window
  rw_length[15:0]         — Burst length (1–32 for CSR window)
  pld_head_ptr[A-1:0]     — Head pointer into int_down_pld (0 for reads)
  pld_word_count[8:0]
  order_type[1:0]         — RELAXED(00)/RELEASE(01)/ACQUIRE(10)/RSVD(11)
  ord_dom_id[3:0]         — Ordering domain identifier
  ord_epoch[7:0]          — Epoch/sequence tag
  ord_scope[1:0]          — Visibility scope
  seq_num[7:0]

ext_up_hdr entry (reply descriptor):
  sc_type[1:0]
  fpga_id[15:0]
  masks[3:0]
  start_address[15:0]
  rw_length[15:0]
  response[1:0]           — OK/SLAVEERROR/DECODEERROR
  pld_head_ptr[A-1:0]     — Head pointer into ext_up_pld (0 for write replies)
  pld_word_count[8:0]
  order_type[1:0]         — Echoed from command (software uses to match ordering)
  ord_dom_id[3:0]         — Echoed from command
  ord_epoch[7:0]          — Echoed from command
  ord_scope[1:0]          — Echoed from command
  seq_num[7:0]

int_up_hdr entry (CSR reply descriptor):
  sc_type[1:0]
  fpga_id[15:0]
  masks[3:0]
  csr_offset[4:0]
  rw_length[15:0]
  response[1:0]
  pld_head_ptr[A-1:0]     — Head pointer into int_up_pld (0 for write replies)
  pld_word_count[8:0]
  order_type[1:0]         — Echoed from command
  ord_dom_id[3:0]         — Echoed from command
  ord_epoch[7:0]          — Echoed from command
  ord_scope[1:0]          — Echoed from command
  seq_num[7:0]
```

### 2.4 Admission Control Flow

```
                         Packet arrives from S&F validator
                                      │
                                      v
                          ┌───────────────────────┐
                          │ Classify: int or ext?  │
                          └──────┬────────┬────────┘
                                 │        │
                      ext        │        │       int
                      ┌──────────┘        └──────────┐
                      v                               v
            ┌──────────────────┐            ┌──────────────────┐
            │ ext_down_hdr     │            │ int_down_hdr     │
            │ has space?       │            │ has space?       │
            └────┬────┬────────┘            └────┬────┬────────┘
                 │    │ no→backpressure          │    │ no→backpressure
              yes│    │                       yes│    │
                 v    │                          v    │
         ┌────────────────┐              ┌────────────────┐
         │ Needs payload? │              │ Needs payload? │
         │ (write cmd)    │              │ (write cmd)    │
         └──┬─────────┬───┘              └──┬─────────┬───┘
         no │      yes│                  no │      yes│
            │         v                     │         v
            │  ┌──────────────┐             │  ┌──────────────┐
            │  │ ext_down_pld │             │  │ int_down_pld │
            │  │ free_count   │             │  │ free_count   │
            │  │ >= rw_length?│             │  │ >= rw_length?│
            │  └──┬────┬──────┘             │  └──┬────┬──────┘
            │     │    │ no→backpressure    │     │    │ no→backpressure
            │  yes│    │                    │  yes│    │
            v     v    │                    v     v    │
      ┌─────────────┐  │              ┌─────────────┐  │
      │ cmd_order   │  │              │ cmd_order   │  │
      │ fifo has    │  │              │ fifo has    │  │
      │ space?      │  │              │ space?      │  │
      └──┬────┬─────┘  │              └──┬────┬─────┘  │
         │    │ no→bp   │                 │    │ no→bp  │
      yes│    │         │              yes│    │        │
         v    │         │                 v    │        │
    ┌──────────────┐    │           ┌──────────────┐   │
    │ ADMIT:       │    │           │ ADMIT:       │   │
    │ 1. malloc    │    │           │ 1. malloc    │   │
    │    pld space │    │           │    pld space │   │
    │ 2. write hdr │    │           │ 2. write hdr │   │
    │ 3. copy pld  │    │           │ 3. copy pld  │   │
    │ 4. push order│    │           │ 4. push order│   │
    │    fifo      │    │           │    fifo      │   │
    └──────────────┘    │           └──────────────┘   │
                        │                              │
           (all revert on any failure in steps 1-4)    │
```

### 2.5 Credit-Based Upload Payload Reservation

Before the dispatch FSM issues an external bus read, it must **reserve** space in `ext_up_pld` for the expected read data:

```
Dispatch FSM (external read):
  1. Dequeue hdr from ext_down_hdr
  2. Check: ext_up_pld.free_count >= hdr.rw_length
     AND:  ext_up_hdr has space for 1 entry
  3. If yes:
       - Reserve rw_length lines in ext_up_pld (malloc, but don't write data yet)
       - Record reserved head_ptr in a pending_read_table[seq_num]
       - Issue bus read (AVMM/AXI4)
  4. If no:
       - Re-queue hdr (push back to ext_down_hdr front, or don't dequeue)
       - Wait for credit to become available
  5. When bus read data arrives (readdatavalid / RVALID):
       - Write data to reserved lines, following the chain from head_ptr
  6. When bus read completes (all words received):
       - Write reply header to ext_up_hdr with pld_head_ptr = reserved head_ptr
       - Push routing tag to reply_order_fifo
```

Same logic applies for `int_up_pld` when dispatching internal CSR reads.

### 2.6 OoO Dispatch (Compile-Time Feature)

**When OoO is disabled (default, compile-time `OOO_ENABLE = false`):**
- Dispatch reads `cmd_order_fifo` to determine next command routing (ext or int)
- Replies assembled in command order using `reply_order_fifo`
- Only one external bus transaction at a time (outstanding=1 effective, though buffer can hold more waiting)

Wait — the user said outstanding=8. With OoO=off, we can still have multiple outstanding if the bus supports pipelining (Avalon: maximumPendingReadTransactions > 1). The ordering is guaranteed by the bus itself (Avalon returns read data in order). So:

**OoO=off, outstanding > 1:**
- Multiple reads can be pipelined on the bus (in-order issue, in-order completion)
- `cmd_order_fifo` ensures dispatch order matches arrival order
- `reply_order_fifo` ensures reply assembly order matches dispatch order
- Bus guarantees in-order completion, so `ext_up_hdr` naturally fills in order

**When OoO is enabled (compile-time `OOO_ENABLE = true`):**
- Dispatch can issue commands out of order (e.g., skip a stalled external read to process a fast internal CSR command)
- AXI4: different ARID/AWID values for different transactions; bus allows OoO completion
- `reply_order_fifo` is bypassed; reply assembler dequeues from whichever upload header FIFO has a completed entry
- CSR `OOO_CTRL` register: bit 0 = OoO runtime enable (1=OoO active, 0=force in-order even though hardware supports it)
- Payload RAM: random-access consumption via linked-list pointers (no FIFO-order constraint)

### 2.7 Atomic Read-Modify-Write

**SC command packet extension for ordering and atomic RMW:**

The packet header carries both **ordering semantics** (release/acquire) and **atomic RMW** fields. These are orthogonal: a packet can be a relaxed atomic, a release write, an acquire read, etc.

```
Word 0 - Preamble (unchanged):
  [31:26] = 000111 (SlowControl)
  [25:24] = sc_type = "10" (Read) — atomic RMW uses Read type with atomic flag
  [23:8]  = FPGA ID
  [7:0]   = K28.5

Word 1 - Start Address (modified):
  [31:30] = ORDER[1:0]   (NEW: ordering semantic)
              00 = RELAXED  — no additional ordering action (default fast path)
              01 = RELEASE  — write-side ordering point: drain older writes before retire
              10 = ACQUIRE  — read-side ordering point: block younger until complete
              11 = RESERVED — (future: ACQ_REL / SEQCST extension)
  [29]    = reserved
  [28]    = atomic_flag   (1 = atomic RMW, orthogonal to ORDER)
  [27:24] = mute ack masks
  [23:0]  = start address (read and write to same address for atomic)

Word 2 - Burst Length + Ordering Domain (modified):
  [31:28] = ORD_DOM_ID[3:0]  (NEW: ordering domain / stream ID, 16 domains)
  [27:20] = ORD_EPOCH[7:0]   (NEW: optional epoch/sequence tag for debug & replay)
  [19:18] = ORD_SCOPE[1:0]   (NEW: visibility scope)
              00 = local endpoint
              01 = device / hub domain
              10 = end-to-end destination visibility
              11 = reserved
  [17:16] = reserved
  [15:0]  = burst length (unchanged, 1–256; =1 for atomic RMW)

Word 3 - Atomic Mask (present only when atomic_flag=1):
  [31:0]  = bit mask for RMW operation

Word 4 - Atomic Modify Data (present only when atomic_flag=1):
  [31:0]  = data to OR/AND/XOR with masked read value

Word N - Trailer:
  [7:0]   = K28.4
```

**Backward compatibility:** Old packets (without ordering) have ORDER=00 (RELAXED), ORD_DOM_ID=0, ORD_EPOCH=0, ORD_SCOPE=00. The hub treats these as ordinary relaxed transactions with no ordering enforcement — identical to current behavior.

**Hub-internal RMW sequence:**
1. Acquire bus lock (`avm_m0_lock=1` / `AxLOCK=01`)
2. Issue bus read to `start_address`
3. Wait for read data
4. Compute: `write_data = (read_data & ~atomic_mask) | (atomic_modify & atomic_mask)`
5. Issue bus write to `start_address` with `write_data`
6. Wait for write response
7. Release bus lock (`avm_m0_lock=0` / `AxLOCK=00`)
8. Generate reply with: response code, original read data (pre-modify)

**Atomic operations block all other external transactions** while the lock is held (steps 1–7). Internal CSR transactions are NOT blocked — they don't use the bus.

### 2.8 Internal Transaction Priority

Internal transactions (CSR access) are the last measure for upstream to perform functional reset or error recovery on this IP. They must **always be reachable**, even when external transactions saturate the outstanding limit.

**Implementation:**
- The global outstanding limit (default 8) is split: `OUTSTANDING_EXT_MAX` and `OUTSTANDING_INT_RESERVED`
- `OUTSTANDING_INT_RESERVED` (default 2) slots are exclusively reserved for internal transactions
- External transactions can use at most `OUTSTANDING_LIMIT - OUTSTANDING_INT_RESERVED` slots
- Internal transactions can use any available slot (reserved + shared)
- Dispatch priority: when both ext_down_hdr and int_down_hdr have pending commands, **internal is dispatched first**

```
Outstanding allocation:
  Total slots: OUTSTANDING_LIMIT (8)
  External max: OUTSTANDING_LIMIT - OUTSTANDING_INT_RESERVED (6)
  Internal reserved: OUTSTANDING_INT_RESERVED (2)

  ext_outstanding_count <= 6  (hard limit)
  int_outstanding_count <= 8  (can use all slots if external is idle)
  ext_outstanding_count + int_outstanding_count <= 8  (global limit)
```

### 2.9 Ordering Semantics (Release / Acquire / Relaxed)

**Design intent:** Software tags packets with ordering intent; the hub translates that intent into local control actions and NoC transaction attributes. The hub does NOT implement the C/C++ memory model directly — it provides per-domain ordering and visibility guarantees that software can compose into higher-level synchronization patterns.

#### 2.9.1 Ordering Semantic Definitions

| ORDER | Name | Hub Behavior |
|-------|------|-------------|
| `00` | RELAXED | No additional ordering action. Normal enqueue, normal dispatch. Default fast path — almost all data traffic. |
| `01` | RELEASE | **Write-side ordering point.** All prior writes in the same `ORD_DOM_ID` must reach the visibility point before this release retires. Younger transactions in the domain must not bypass the release. |
| `10` | ACQUIRE | **Read-side ordering point.** The acquire transaction itself proceeds normally, but no younger operation in the same `ORD_DOM_ID` may issue or complete until the acquire completes and its visibility condition is satisfied. |
| `11` | RESERVED | Future extension for ACQ_REL (atomic RMW synchronization) or SEQCST. Not implemented in first version. |

#### 2.9.2 Ordering Domain (`ORD_DOM_ID`)

A packet must indicate **which sequence of operations is ordered together**. Without a domain, every release/acquire would become global (too expensive).

- 4-bit field → 16 ordering domains
- Maps to a software concept: queue pair, flow ID, thread context, or software ordering group
- The hub maintains **independent ordering state per domain** — operations in domain 3 do not block operations in domain 7
- Domain 0 is the default (backward-compatible relaxed traffic)
- Software is responsible for assigning domain IDs consistently

#### 2.9.3 Per-Domain Ordering State

For each active ordering domain, the hub maintains:

```
struct ord_domain_state {
    bool     release_pending;      // a release is waiting for older writes to drain
    bool     acquire_pending;      // an acquire is outstanding, blocking younger ops
    bool     younger_blocked;      // younger same-domain ops are held
    uint     outstanding_writes;   // writes issued but not yet visibility-retired
    uint     outstanding_txns;     // total txns outstanding in this domain
    uint     last_issued_epoch;    // epoch of most recently issued txn
    uint     last_retired_epoch;   // epoch of most recently retired txn
};
```

**State array:** `ord_domain_state domains[16];` (one per ORD_DOM_ID value).

#### 2.9.4 Release Drain Mechanism

When a RELEASE packet arrives for domain `D`:

```
1. Parse ORDER=01, extract ORD_DOM_ID=D
2. Set domains[D].release_pending = true
3. Set domains[D].younger_blocked = true
   → dispatch FSM will NOT issue any younger same-domain transaction past
     the release boundary
4. Wait: until domains[D].outstanding_writes == 0
   → all older writes in domain D have reached the visibility point
   (see 2.9.7 for write retirement levels)
5. Emit the release transaction to the bus:
   - AVMM: normal write with release metadata in internal tracking
   - AXI4:  AWUSER carries order_type=RELEASE, ord_dom_id=D
   (or: emit as explicit barrier transaction if NoC supports it)
6. Wait: until release transaction itself is acknowledged
7. Clear domains[D].release_pending = false
8. Clear domains[D].younger_blocked = false
   → younger same-domain transactions may now proceed
```

**Key invariant (Rule 2):** A release in domain D cannot complete until ALL older writes in domain D reach the required visibility point.

#### 2.9.5 Acquire Hold Mechanism

When an ACQUIRE packet arrives for domain `D`:

```
1. Parse ORDER=10, extract ORD_DOM_ID=D
2. Set domains[D].acquire_pending = true
3. Issue the acquire transaction (typically a read or status fetch):
   - AVMM: normal read with acquire metadata in internal tracking
   - AXI4:  ARUSER carries order_type=ACQUIRE, ord_dom_id=D
4. Set domains[D].younger_blocked = true
   → no younger same-domain operation may issue or complete
5. Wait: until acquire response arrives AND visibility condition is met
   (the response must represent a state where all causally prior
    released writes that should be visible are visible)
6. Clear domains[D].acquire_pending = false
7. Clear domains[D].younger_blocked = false
   → younger same-domain transactions may now proceed
```

**Key invariant (Rule 3):** No younger transaction in domain D may issue or complete past an acquire until that acquire completes.

#### 2.9.6 Interaction with OoO Dispatch

- **OoO=off:** Ordering enforcement is simpler — transactions within a domain already issue in order. Release/acquire still enforce the drain/hold, but cross-domain reordering is not possible.
- **OoO=on:** The dispatch FSM must respect the `younger_blocked` flag per domain. It MAY skip a blocked domain and issue transactions from a different domain (cross-domain traffic is independent). This is the primary benefit of domain-based ordering with OoO.
- **Interaction with atomic:** An atomic RMW with ORDER=11 (ACQ_REL, future) would combine both release drain and acquire hold around the RMW sequence. For first implementation, atomic RMW with ORDER=RELAXED is sufficient — the bus lock already provides atomicity, and software can issue explicit release/acquire packets around the atomic if ordering is needed.

#### 2.9.7 Write Retirement Levels

The hub must distinguish three levels of write progress. **Release cannot be satisfied at level 1 — it must wait for level 3.**

| Level | Name | Meaning | How Tracked |
|-------|------|---------|-------------|
| 1 | **Accepted** | Write data is in the hub's download payload FIFO | `ext_down_pld` occupancy |
| 2 | **Issued** | Write has been dispatched to the bus (AVMM write asserted / AXI4 WVALID+WLAST) | `outstanding_writes` counter |
| 3 | **Visible-retired** | Bus write response received (AVMM: waitrequest deasserted after write / AXI4: BVALID+BRESP=OK) | Decrement `outstanding_writes`, increment `last_retired_epoch` |

For the TLM model: write visibility is modeled as the bus target acknowledging the write. In RTL, this maps to the bus write response.

#### 2.9.8 NoC Transaction Metadata

The hub generates bus transactions with the following ordering metadata (carried in AXI4 AxUSER sideband or tracked internally for AVMM):

```
txn.order_type    // RELAXED, RELEASE, ACQUIRE
txn.ord_dom_id    // ordering domain (4 bits)
txn.ord_epoch     // optional epoch tag (8 bits)
txn.ord_scope     // visibility scope (2 bits)
txn.src_id        // hub source ID
txn.dst_id        // target address
txn.is_barrier    // true if this is an explicit fence/barrier (future)
```

**AVMM note:** Avalon-MM has no user sideband. Ordering metadata is tracked purely hub-internally. The bus itself provides in-order completion, so the hub only needs to track domain state and enforce drain/hold.

**AXI4 note:** `AxUSER` width must accommodate order_type(2) + ord_dom_id(4) + ord_epoch(8) + ord_scope(2) = 16 bits. The `_hw.tcl` must set `ASSOCIATED_BUSUSER_WIDTH` accordingly.

#### 2.9.9 Software Programming Model

The software contract is simple:

**Release usage (publish):** Software sends a RELEASE-marked packet when it wants to guarantee that all prior writes in a domain are visible before a synchronization point.

```
Typical pattern:
  1. Write descriptors / payload / metadata  (ORDER=RELAXED, ORD_DOM_ID=D)
  2. Write doorbell / commit word             (ORDER=RELEASE, ORD_DOM_ID=D)
```

**Acquire usage (consume):** Software sends an ACQUIRE-marked packet when it wants to consume state only after synchronization.

```
Typical pattern:
  1. Read completion/status register          (ORDER=ACQUIRE, ORD_DOM_ID=D)
  2. Read dependent data structures           (ORDER=RELAXED, ORD_DOM_ID=D)
```

**Relaxed usage (default):** All ordinary traffic remains RELAXED for performance. This keeps the system scalable.

#### 2.9.10 Ordering Correctness Rules

For each ordering domain `D`, the hub must satisfy these four rules:

| Rule | Statement |
|------|-----------|
| **R1** | Younger transactions in D must never bypass a release in D. |
| **R2** | A release in D cannot complete until all older writes in D reach the required visibility point. |
| **R3** | Younger transactions in D must not issue or complete past an acquire in D until that acquire completes. |
| **R4** | An acquire completion in D must reflect a visibility state consistent with prior releases intended to synchronize with it. |

These four rules are sufficient for a correct first implementation.

#### 2.9.11 Practical Scope for First Implementation

For the first sc_hub_v2 implementation, support only:

- **RELAXED** — default fast path (no overhead)
- **RELEASE** — used on publish/doorbell/commit packets
- **ACQUIRE** — used on completion/status/consume packets

Do NOT implement full SEQCST unless a concrete use case requires it. The `ORDER=11` encoding is reserved for future extension.

**Expected traffic mix:** >95% relaxed, <3% release, <2% acquire. The ordering mechanisms should have **zero overhead on relaxed traffic** — the domain state check (`younger_blocked == false`) is a single-cycle gate.

---

## 3. TLM Model Architecture

### 3.1 SystemC Module Hierarchy

```
sc_hub_tlm_top (sc_module)
├── sc_pkt_source                  SC command packet generator
│   ├── Configurable: rate, burst length distribution, read/write ratio,
│   │   address distribution, atomic ratio, internal/external ratio
│   └── Output: tlm_generic_payload transactions via initiator socket
│
├── sc_hub_model (sc_module)       The hub TLM model
│   ├── sc_hub_pkt_rx_model        S&F validation + classification
│   ├── sc_hub_admit_ctrl_model    Admission control (space checks, malloc)
│   ├── sc_hub_buffer_model        8 subFIFOs + malloc + order tracking
│   │   ├── hdr_fifo<T> (x4)      Templated header FIFO model
│   │   ├── pld_ram<D> (x4)       Linked-list payload RAM model
│   │   ├── malloc_model           Malloc/free with free-list tracking
│   │   ├── cmd_order_fifo         Command ordering
│   │   └── reply_order_fifo       Reply ordering (OoO=off)
│   ├── sc_hub_dispatch_model      Command scheduling (in-order or OoO)
│   ├── sc_hub_credit_mgr_model    Upload payload reservation
│   ├── sc_hub_csr_model           Internal CSR register bank
│   ├── sc_hub_atomic_model        Atomic RMW sequencer
│   ├── sc_hub_ord_tracker_model   Per-domain ordering state (16 domains)
│   │   ├── ord_domain_state[16]   Release/acquire pending, younger_blocked
│   │   ├── release_drain_fsm      Drain older writes to visibility before retire
│   │   └── acquire_hold_fsm       Block younger ops until acquire completes
│   └── sc_hub_pkt_tx_model        Reply assembly
│
├── bus_target_model (sc_module)   System bus slave model
│   ├── Configurable: latency distribution (fixed, uniform, bimodal),
│   │   error injection rate, address-dependent latency
│   └── Memory model (64K words)
│
├── perf_collector (sc_module)     Performance metrics collection
│   ├── latency_histogram          Per-transaction latency tracking
│   ├── throughput_counter          Transactions/sec, words/sec
│   ├── fragmentation_tracker      Free-count over time, frag ratio
│   ├── outstanding_tracker         Outstanding count over time
│   ├── admission_reject_counter   Rejection events by reason
│   ├── credit_stall_counter       Upload credit exhaustion events
│   ├── ooo_reorder_counter        Out-of-order completions observed
│   ├── release_drain_counter      Release drain events + drain latency
│   ├── acquire_hold_counter       Acquire hold events + hold latency
│   └── ord_domain_utilization     Per-domain active time, blocked time
│
└── report_generator               Generates CSV/JSON output for plotting
```

### 3.2 Timing Model

The TLM model uses `sc_time` for approximate timing. Not cycle-accurate, but captures the key latency contributors.

| Operation | Modeled Latency | Notes |
|-----------|----------------|-------|
| S&F validation | `sc_time(L + 5, SC_NS)` | L = packet words. ~1 cycle/word + validation overhead |
| Admission (malloc) | `sc_time(N * 2, SC_NS)` | N = words to allocate. ~2 cycles per free-list walk step |
| Header FIFO enqueue | `sc_time(1, SC_NS)` | 1 cycle |
| Command dispatch | `sc_time(2, SC_NS)` | Routing + dequeue |
| AVMM bus read (no wait) | configurable: `sc_time(latency, SC_NS)` | Default: uniform(4, 20) ns |
| AVMM bus read (waitrequest) | `+ sc_time(waitreq_cycles, SC_NS)` | Configurable stall |
| AVMM bus write | configurable | Default: fixed(4) ns |
| AXI4 bus read | configurable | Default: uniform(4, 50) ns (higher variance) |
| AXI4 bus write | configurable | Default: fixed(4) ns |
| Internal CSR read | `sc_time(N + 1, SC_NS)` | N = burst length, 1 cycle/word + 1 setup |
| Internal CSR write | `sc_time(2, SC_NS)` | Single-cycle write + 1 setup |
| Atomic RMW | `read_latency + sc_time(3, SC_NS) + write_latency` | 3 cycle modify + lock overhead |
| Release drain | `sc_time(1, SC_NS) + wait(outstanding_writes==0)` | 1 cycle domain check + variable drain wait |
| Acquire hold | `sc_time(1, SC_NS) + read_latency + visibility_ack` | 1 cycle domain check + read + ack |
| Ordering domain check | `sc_time(1, SC_NS)` | Single-cycle gate on `younger_blocked[D]` |
| Reply assembly | `sc_time(L + 4, SC_NS)` | L = payload words. Preamble + addr + header + data + trailer |
| Payload deallocation (free) | `sc_time(N, SC_NS)` | N = chain length. 1 cycle per free-list link |
| Linked-list payload read | `sc_time(N + hops, SC_NS)` | N = words, hops = pointer-hop count (fragmentation cost) |

**Address-dependent bus latency model:**

To simulate the feb_system interconnect where different slave IPs have different access latencies:

| Address Range | Modeled Latency | Simulates |
|---------------|----------------|-----------|
| 0x0000–0x03FF (scratch) | fixed(2) ns | Fast local memory |
| 0x8000–0x87FF (frame_rcv) | uniform(4, 12) ns | Near datapath IP |
| 0xA000–0xA7FF (ring_buf_cam) | uniform(8, 20) ns | Farther datapath IP |
| 0xC000–0xC1FF (histogram) | uniform(6, 16) ns | Medium-distance IP |
| Unmapped | fixed(50) ns + DECODEERROR | Timeout simulation |

### 3.3 Malloc Model Detail

The malloc model is the core of the TLM and must be validated carefully.

```cpp
class sc_hub_malloc_model {
public:
    // State
    int ram_depth;
    int free_count;
    int free_head;          // head of free list (-1 if empty)
    struct ram_line_t {
        uint32_t data;
        int      next_ptr;  // -1 = no next
        bool     is_last;
        bool     is_free;
    };
    std::vector<ram_line_t> ram;

    // Statistics (for fragmentation analysis)
    int total_allocs;
    int total_frees;
    int total_alloc_words;
    int total_free_words;
    int peak_used;
    int alloc_failures;
    std::vector<int> free_count_trace;  // sampled periodically

    // Operations
    int  malloc(int size);    // returns head_ptr or -1 on failure
    void free(int head_ptr);  // frees entire chain
    int  get_free_count();
    double get_fragmentation_ratio();  // 1.0 = no frag, <1.0 = fragmented

    // Fragmentation metric:
    //   Walk free list, count number of contiguous segments.
    //   frag_ratio = 1.0 / num_segments  (1 segment = no frag)
    //   Also: largest_contiguous_free / free_count (1.0 = all free space is contiguous)
};
```

**Fragmentation ratio definition:**

```
frag_ratio = largest_contiguous_free_block / free_count

  frag_ratio = 1.0  → all free space is one contiguous block (no fragmentation)
  frag_ratio = 0.5  → largest free block is half of total free space
  frag_ratio → 0    → free space is scattered in single-line fragments
```

**Fragmentation consequences in RTL:**
- When `frag_ratio` is low, malloc may fail even though `free_count >= request_size` (no contiguous run of `request_size` lines exists... wait, with linked-list, contiguity doesn't matter! Each allocation is a linked list, so any N free lines can be collected regardless of their physical position.)
- **Correction:** With linked-list allocation, fragmentation does NOT cause allocation failure. As long as `free_count >= request_size`, malloc always succeeds. The cost of fragmentation is **performance**: more pointer hops during payload read/write, increasing latency.

So the fragmentation metric for this architecture is:

```
frag_cost = (total_pointer_hops / total_words_accessed) during payload consumption

  frag_cost = 0    → all allocated chains are perfectly contiguous (0 extra hops)
  frag_cost = 0.1  → 10% of accesses are pointer hops (navigation overhead)
  frag_cost = 1.0  → every other access is a pointer hop (severe fragmentation)
```

This directly translates to RTL throughput: each pointer hop adds 1 cycle of latency to the payload read/write path.

---

## 4. Experiments

### 4.1 Experiment Categories

| Cat | Name | Purpose | Key Metric |
|-----|------|---------|------------|
| FRAG | Fragmentation Analysis | Characterize malloc/free fragmentation under various workloads | `frag_cost`, free_count over time |
| RATE | Rate-Latency Curves | Throughput vs. offered load at various outstanding depths | transactions/sec vs. offered rate |
| OOO | OoO Speedup | Compare in-order vs. OoO throughput under latency variance | speedup ratio, reorder buffer occupancy |
| ATOM | Atomic RMW Impact | Measure throughput degradation from atomic operations | throughput with/without atomics |
| CRED | Credit Analysis | Upload payload reservation failure rate | stall rate, credit utilization |
| PRIO | Internal Priority | Verify internal CSR reachability under external saturation | internal latency when external is saturated |
| ORD | Ordering Semantics | Characterize release drain / acquire hold cost and correctness | drain latency, hold latency, cross-domain independence |
| SIZE | Buffer Sizing | Find optimal outstanding depth and payload RAM size | knee of rate-latency curve |

### 4.2 FRAG — Fragmentation Analysis (8 experiments)

| ID | Experiment | Workload | Measurement | Duration |
|----|------------|----------|-------------|----------|
| FRAG-01 | Uniform burst length, no OoO | Burst length uniform(1,256), 50% read, 50% write | `frag_cost` over time, free_count trace | 10k transactions |
| FRAG-02 | Bimodal burst length, no OoO | 70% L=1 (single), 30% L=256 (max burst) | `frag_cost`, allocation pattern | 10k transactions |
| FRAG-03 | Small bursts only | L uniform(1,4) | `frag_cost` (should be minimal) | 10k transactions |
| FRAG-04 | Large bursts only | L uniform(128,256) | `frag_cost`, free_count trace | 10k transactions |
| FRAG-05 | Uniform with OoO=on | Same as FRAG-01 but OoO enabled, random completion order | `frag_cost` (worse due to non-sequential free) | 10k transactions |
| FRAG-06 | Bimodal with OoO=on | Same as FRAG-02, OoO enabled | `frag_cost` | 10k transactions |
| FRAG-07 | Pathological: alternating 1 and 256 | Strict alternation of L=1 and L=256 | `frag_cost`, worst-case analysis | 10k transactions |
| FRAG-08 | Long soak | FRAG-01 workload for 1M transactions | `frag_cost` drift over time (does it stabilize or degrade?) | 1M transactions |

**Output:** CSV of `{transaction_id, frag_cost, free_count, peak_used, alloc_time_ns}` for each experiment. Plot `frag_cost` vs. transaction count.

### 4.3 RATE — Rate-Latency Curves (12 experiments)

For each experiment: sweep offered rate from 10% to 100% of theoretical maximum (1 transaction/bus_latency). Measure delivered throughput and average/P99 latency.

| ID | Experiment | Bus Latency Model | Outstanding | OoO | Payload Depth |
|----|------------|-------------------|-------------|-----|---------------|
| RATE-01 | Baseline: fixed latency, in-order | fixed(8 ns) | 1 | off | 512 |
| RATE-02 | Outstanding sweep: depth=1 | fixed(8 ns) | 1 | off | 512 |
| RATE-03 | Outstanding sweep: depth=2 | fixed(8 ns) | 2 | off | 512 |
| RATE-04 | Outstanding sweep: depth=4 | fixed(8 ns) | 4 | off | 512 |
| RATE-05 | Outstanding sweep: depth=8 | fixed(8 ns) | 8 | off | 512 |
| RATE-06 | Outstanding sweep: depth=16 | fixed(8 ns) | 16 | off | 512 |
| RATE-07 | Variable latency, in-order | uniform(4, 50 ns) | 8 | off | 512 |
| RATE-08 | Variable latency, OoO | uniform(4, 50 ns) | 8 | on | 512 |
| RATE-09 | Bimodal latency (fast/slow slaves) | bimodal(4 ns, 40 ns, 50/50) | 8 | off | 512 |
| RATE-10 | Bimodal latency, OoO | bimodal(4 ns, 40 ns, 50/50) | 8 | on | 512 |
| RATE-11 | Mixed read/write, in-order | fixed(8 ns) read, fixed(4 ns) write, 50/50 mix | 8 | off | 512 |
| RATE-12 | Address-dependent latency (feb_system model) | See section 3.2 | 8 | off | 512 |

**Output:** For each experiment, a CSV of `{offered_rate, delivered_throughput, avg_latency, p50_latency, p99_latency, max_latency}`. Plot:
1. Throughput vs. offered rate (saturation curve)
2. Latency vs. offered rate (hockey-stick curve)
3. Overlay RATE-02..RATE-06 to show outstanding-depth impact

### 4.4 OOO — Out-of-Order Speedup (6 experiments)

Each experiment runs the same workload twice: once with OoO=off, once with OoO=on. The speedup ratio quantifies the benefit of OoO.

| ID | Experiment | Bus Latency Model | Outstanding | Workload |
|----|------------|-------------------|-------------|----------|
| OOO-01 | Fixed latency (no variance) | fixed(8 ns) | 8 | 100% reads, L=1 |
| OOO-02 | Uniform variance | uniform(4, 50 ns) | 8 | 100% reads, L=1 |
| OOO-03 | High variance | uniform(4, 200 ns) | 8 | 100% reads, L=1 |
| OOO-04 | Bimodal: fast CSR + slow data IP | int=fixed(2 ns), ext=uniform(10, 50 ns) | 8 | 50% internal, 50% external |
| OOO-05 | Mixed read/write with variance | uniform(4, 50 ns) | 8 | 50% read, 50% write, mixed L |
| OOO-06 | OoO with atomics blocking | uniform(4, 50 ns) + 10% atomics | 8 | 90% normal, 10% atomic |

**Output:** For each experiment, a table:
```
{experiment, throughput_ino, throughput_ooo, speedup, avg_lat_ino, avg_lat_ooo, lat_reduction}
```

**Expected results:**
- OOO-01: speedup ~1.0 (fixed latency → no reordering benefit)
- OOO-02: speedup ~1.3–1.8 (moderate variance → moderate benefit)
- OOO-03: speedup ~2.0–3.0 (high variance → significant benefit)
- OOO-04: speedup >2.0 (fast internal can bypass slow external)

### 4.5 ATOM — Atomic RMW Impact (4 experiments)

| ID | Experiment | Atomic Ratio | Bus Latency | Outstanding |
|----|------------|-------------|-------------|-------------|
| ATOM-01 | No atomics (baseline) | 0% | fixed(8 ns) | 8 |
| ATOM-02 | 1% atomic | 1% | fixed(8 ns) | 8 |
| ATOM-03 | 10% atomic | 10% | fixed(8 ns) | 8 |
| ATOM-04 | 50% atomic | 50% | fixed(8 ns) | 8 |

**Output:** Throughput degradation curve: `{atomic_ratio, throughput, avg_latency}`. Atomics hold the bus lock for read_latency + 3 cycles + write_latency, blocking all other external transactions.

**Additional atomic tests:**
| ID | Experiment | Description |
|----|------------|-------------|
| ATOM-05 | Atomic correctness | 1000 atomic RMW to same address, concurrent non-atomic reads. Verify: no torn read/write (read always sees pre-modify or post-modify, never partial). |
| ATOM-06 | Atomic + internal priority | Saturate bus with atomics (50%), verify internal CSR still serviced within latency budget. |

### 4.6 CRED — Credit Analysis (4 experiments)

| ID | Experiment | Workload | Outstanding | Payload Depth | Measurement |
|----|------------|----------|-------------|---------------|-------------|
| CRED-01 | Reads only, deep payload | 100% burst read L=64 | 8 | 512 | Credit stall rate (should be ~0) |
| CRED-02 | Reads only, shallow payload | 100% burst read L=64 | 8 | 128 | Credit stall rate (expect stalls) |
| CRED-03 | Reads only, max burst | 100% burst read L=256 | 8 | 512 | Credit stall (8 × 256 = 2048 > 512, must stall) |
| CRED-04 | Mixed, realistic | 50% read L=16, 50% write L=16 | 8 | 512 | Credit utilization over time |

**Output:** `{experiment, stall_count, stall_rate, avg_credit_utilization, peak_credit_utilization}`

**Key insight from CRED-03:** With 8 outstanding × 256 max burst = 2048 words needed, but payload RAM is only 512. The credit manager will limit effective outstanding for large bursts. The TLM should report the **effective outstanding** (actual concurrency achieved given payload constraints).

### 4.7 PRIO — Internal Priority Verification (4 experiments)

| ID | Experiment | External Load | Internal Load | Measurement |
|----|------------|---------------|---------------|-------------|
| PRIO-01 | External saturated, internal idle | 100% external, outstanding=8 | 0 | Baseline: external throughput |
| PRIO-02 | External saturated, periodic internal | 100% external, outstanding=8 | 1 CSR read every 100 transactions | Internal latency (must be bounded) |
| PRIO-03 | External saturated, burst internal | 100% external, outstanding=8 | 4 CSR reads back-to-back every 500 txns | All 4 internal complete despite external saturation |
| PRIO-04 | External saturated + atomics, internal | 50% ext + 50% atomic, outstanding=8 | 1 CSR read every 50 txns | Internal still reachable during atomic lock |

**Output:** `{experiment, int_avg_latency, int_max_latency, int_stall_count, ext_throughput_impact}`

**Pass criteria:** Internal CSR latency must remain bounded (< 100 ns) regardless of external load. The reserved slots (OUTSTANDING_INT_RESERVED=2) must guarantee this.

### 4.8 ORD — Ordering Semantics (8 performance + 6 correctness = 14 experiments)

#### 4.8.1 Performance Experiments

| ID | Experiment | Workload | Ordering Mix | Outstanding | Measurement |
|----|------------|----------|-------------|-------------|-------------|
| ORD-01 | Release drain cost (shallow) | 100% writes, L=1 | 5% RELEASE, 95% RELAXED, 1 domain | 8 | Throughput degradation vs. 0% release baseline |
| ORD-02 | Release drain cost (deep) | 100% writes, L=64 | 5% RELEASE, 95% RELAXED, 1 domain | 8 | Drain latency (must wait for outstanding_writes==0) |
| ORD-03 | Acquire hold cost | 100% reads, L=1 | 5% ACQUIRE, 95% RELAXED, 1 domain | 8 | Throughput degradation vs. 0% acquire baseline |
| ORD-04 | Release + acquire pair (publish/consume) | 50% write, 50% read | 2% RELEASE, 2% ACQUIRE, 96% RELAXED, 1 domain | 8 | End-to-end synchronization latency |
| ORD-05 | Multi-domain independence | 100% reads, L=1 | Domain 0: 50% traffic (10% ACQUIRE), Domain 1: 50% traffic (RELAXED only) | 8 | Domain 1 throughput unaffected by Domain 0 acquire holds |
| ORD-06 | Ordering + OoO interaction | uniform(4,50 ns), mixed | 5% RELEASE, 5% ACQUIRE across 4 domains, OoO=on | 8 | OoO can still reorder across domains while honoring intra-domain order |
| ORD-07 | High release ratio stress | 100% writes, L=1 | 50% RELEASE (pathological), 1 domain | 8 | Worst-case: every other write is a release → effective outstanding=1 |
| ORD-08 | Ordering + atomics | mixed | 2% atomic RMW, 3% RELEASE, 2% ACQUIRE, 1 domain | 8 | Combined ordering + atomic overhead |

**Output:** For each experiment: `{experiment, throughput_ordered, throughput_baseline, overhead_pct, avg_drain_latency, avg_hold_latency, max_drain_latency, max_hold_latency}`.

**Expected results:**
- ORD-01: ~5% throughput overhead (release drain is fast when writes are single-word)
- ORD-02: Higher overhead — drain must wait for outstanding large writes to complete on bus
- ORD-05: Domain 1 throughput within 2% of all-relaxed baseline (cross-domain independent)
- ORD-07: Severe degradation — demonstrates why release should be rare

#### 4.8.2 Correctness Checks

| ID | Check | Description |
|----|-------|-------------|
| ORD-C01 | Rule 1: no bypass on release | Issue 100 RELAXED writes in domain D, then 1 RELEASE in domain D, then 100 more RELAXED in domain D. Verify: no younger-than-release write completes before the release. |
| ORD-C02 | Rule 2: release waits for visibility | Issue 4 outstanding writes in domain D (slow bus: 100 ns), then RELEASE. Verify: release does not retire until all 4 write responses arrive. |
| ORD-C03 | Rule 3: acquire blocks younger | Issue ACQUIRE read in domain D, then 10 RELAXED reads in domain D. Verify: none of the 10 reads complete before the acquire. |
| ORD-C04 | Rule 4: acquire visibility | Issue RELEASE write in domain D on node A, then ACQUIRE read in domain D on node B. Verify: acquire response reflects a state where the released write is visible. |
| ORD-C05 | Cross-domain independence | Domain 0 has ACQUIRE pending (slow bus). Domain 1 issues RELAXED reads. Verify: domain 1 reads complete without waiting for domain 0 acquire. |
| ORD-C06 | Ordering + atomic combined | Issue RELEASE in domain D, then atomic RMW (RELAXED) in domain D. Verify: atomic waits for release to complete (same-domain ordering), then proceeds with bus lock. |

### 4.9 SIZE — Buffer Sizing (6 experiments)

Sweep buffer parameters to find the optimal configuration for the feb_system workload.

| ID | Experiment | Swept Parameter | Range | Fixed Parameters |
|----|------------|----------------|-------|------------------|
| SIZE-01 | Outstanding depth sweep | OUTSTANDING_LIMIT | {1,2,4,8,12,16,24,32} | pld_depth=512, bus_lat=uniform(4,20) |
| SIZE-02 | Payload depth sweep | EXT_PLD_DEPTH | {64,128,256,512,1024} | outstanding=8, bus_lat=uniform(4,20) |
| SIZE-03 | Internal depth sweep | INT_HDR_DEPTH | {1,2,4,8} | outstanding=8, pld_depth=512 |
| SIZE-04 | Joint: outstanding × payload | OUTSTANDING × PLD_DEPTH | {4,8,16} × {256,512,1024} | bus_lat=uniform(4,20) |
| SIZE-05 | feb_system workload profile | — | — | Address-dependent latency model, realistic SC command mix |
| SIZE-06 | Worst-case sizing | — | — | All reads, max burst, high load |

**Output:** For each sweep point: `{param_value, throughput, avg_latency, p99_latency, frag_cost, credit_stall_rate}`. Plot parameter vs. throughput to identify the knee.

---

## 5. Workload Models

### 5.1 SC Command Distributions

| Workload | Description | Parameters |
|----------|-------------|------------|
| `uniform_rw` | 50% read, 50% write, uniform burst length | `rd_ratio=0.5, L=uniform(1,256)` |
| `read_heavy` | 80% read, 20% write | `rd_ratio=0.8, L=uniform(1,64)` |
| `write_heavy` | 20% read, 80% write | `rd_ratio=0.2, L=uniform(1,64)` |
| `single_word` | All single-word (L=1) read/write | `rd_ratio=0.5, L=1` |
| `max_burst` | All max burst (L=256) | `rd_ratio=0.5, L=256` |
| `bimodal` | 70% L=1, 30% L=256 | `rd_ratio=0.5, L=bimodal(1,256,0.7)` |
| `feb_system_realistic` | Based on typical SC traffic in feb_system | See 5.2 |
| `csr_heavy` | 60% internal CSR, 40% external | `int_ratio=0.6, L=uniform(1,8)` |
| `atomic_mix` | 90% normal, 10% atomic RMW | `atomic_ratio=0.1, L=1 for atomic` |
| `ordered_publish` | Release-marked doorbell pattern | `95% RELAXED write, 5% RELEASE write, ORD_DOM_ID=1` |
| `ordered_consume` | Acquire-marked status read pattern | `95% RELAXED read, 5% ACQUIRE read, ORD_DOM_ID=1` |
| `ordered_pub_con` | Publish + consume pairing | `48% RELAXED wr, 2% RELEASE wr, 48% RELAXED rd, 2% ACQUIRE rd, ORD_DOM_ID=1` |
| `multi_domain` | Independent domains with ordering | `domain 0: 50% traffic (10% ACQUIRE), domain 1: 50% (RELAXED only)` |

### 5.2 feb_system Realistic Workload

Derived from typical MIDAS frontend slow-control polling patterns:

```
Command mix:
  - 40% single-word CSR reads (L=1) to frame_rcv[0..7] status registers
  - 20% single-word CSR writes (L=1) to configuration registers
  - 15% burst reads (L=8..32) to histogram bins
  - 10% internal CSR reads (L=1) to hub status
  - 5%  internal CSR writes (L=1) to hub control
  - 5%  burst writes (L=4..16) to scratch pad
  - 3%  burst reads (L=64) to scratch pad dump
  - 2%  atomic RMW (L=1) to shared control registers
  - 1%  RELEASE-tagged writes (doorbell/commit after descriptor setup, ORD_DOM_ID=1)
  - 1%  ACQUIRE-tagged reads (completion status before consuming data, ORD_DOM_ID=1)

Inter-command gap: exponential(mean=20 ns) — bursty

Address distribution:
  - 50% frame_rcv (0x8000–0x87FF) — latency: uniform(4,12) ns
  - 20% scratch pad (0x0000–0x03FF) — latency: fixed(2) ns
  - 10% histogram (0xC000–0xC1FF) — latency: uniform(6,16) ns
  - 10% internal CSR (0xFE80–0xFE9F) — latency: fixed(2) ns
  - 5%  ring_buf_cam (0xA000–0xA7FF) — latency: uniform(8,20) ns
  - 5%  other
```

---

## 6. OoO-Specific TLM Validation

Since OoO is a compile-time feature that fundamentally changes the IP, the TLM must validate it thoroughly before RTL implementation.

### 6.1 OoO Correctness Checks

| ID | Check | Description |
|----|-------|-------------|
| OOO-C01 | Reply data integrity | Every reply contains the correct data for its command, regardless of completion order |
| OOO-C02 | No reply duplication | Each command produces exactly one reply |
| OOO-C03 | No reply loss | Every admitted command eventually produces a reply |
| OOO-C04 | Payload isolation | OoO consumption does not corrupt adjacent payload chains in RAM |
| OOO-C05 | Free-list consistency | After all transactions complete, free_count == RAM_DEPTH (no leaked lines) |
| OOO-C06 | Sequence number correctness | When OoO is runtime-disabled (CSR toggle), replies revert to in-order |
| OOO-C07 | Mixed int/ext ordering | Internal replies bypass external ordering; verify no starvation |

### 6.2 OoO Performance Characterization

Generate the following plots from experiments OOO-01 through OOO-06:

1. **Speedup vs. latency variance:** X = stddev(bus_latency), Y = throughput_ooo / throughput_ino
2. **Effective outstanding vs. nominal outstanding:** with OoO=off, effective outstanding may be less than nominal if head-of-line blocking occurs. With OoO=on, effective approaches nominal.
3. **Reorder buffer occupancy:** histogram of how many entries are in ext_up_hdr at any time (OoO=on). Helps size the buffer.

### 6.3 OoO + Fragmentation Interaction

| ID | Experiment | Description |
|----|------------|-------------|
| OOO-F01 | OoO frees in random order | With OoO, payloads are freed in completion order (not allocation order). Measure fragmentation increase vs. in-order free. |
| OOO-F02 | Long-lived vs short-lived transactions | Mix of L=256 (slow bus) and L=1 (fast bus). With OoO, L=1 completes first, freeing scattered single lines between L=256 blocks. Measure frag_cost degradation. |
| OOO-F03 | Fragmentation recovery | Run OOO-F02 workload for 10k txns, then switch to all L=1 for 10k txns. Measure: does frag_cost recover as small transactions compact the free list? |

---

## 7. Atomic RMW TLM Validation

### 7.1 Correctness Checks

| ID | Check | Description |
|----|-------|-------------|
| ATOM-C01 | RMW atomicity | Two concurrent atomic RMW to the same address: final value must reflect both modifications (no lost update) |
| ATOM-C02 | Lock exclusion | While atomic holds lock, no other external transaction proceeds on the bus |
| ATOM-C03 | Internal bypass during lock | Internal CSR transactions complete normally during atomic lock (they don't use the bus) |
| ATOM-C04 | Atomic + error handling | Atomic read phase returns SLAVEERROR: write phase is skipped, reply contains error |
| ATOM-C05 | Atomic reply format | Reply contains original read data (pre-modify) and response code |

### 7.2 Performance Characterization

Generate from ATOM-01 through ATOM-04:

1. **Throughput vs. atomic ratio:** X = % atomic transactions, Y = throughput. Expect linear degradation proportional to atomic_latency / normal_latency.
2. **Latency distribution shift:** CDF of transaction latency with 0%, 1%, 10%, 50% atomic ratio. Atomics should increase tail latency for non-atomic transactions.
3. **Lock hold time histogram:** distribution of how long the bus lock is held per atomic. Depends on bus read/write latency.

---

## 7B. Ordering Semantics TLM Validation

### 7B.1 Correctness Checks

The ORD-C01 through ORD-C06 checks (section 4.8.2) verify the four correctness rules from section 2.9.10. In addition, the following structural invariants must hold at all times:

| ID | Invariant | Description |
|----|-----------|-------------|
| ORD-I01 | Domain isolation | `younger_blocked[D]` only affects transactions with `ord_dom_id == D`. All other domains proceed freely. |
| ORD-I02 | Release visibility level | Release retirement occurs only after ALL older writes reach level 3 (visible-retired), not level 1 (accepted) or level 2 (issued). |
| ORD-I03 | Acquire blocks both issue and completion | A younger-than-acquire transaction in the same domain must not be issued to the bus AND must not have its reply assembled, even if its bus response arrives. |
| ORD-I04 | Zero overhead on RELAXED | RELAXED transactions (ORDER=00) must incur zero additional latency from the ordering tracker — the domain state check is a single-cycle pass-through. |
| ORD-I05 | Epoch monotonicity | Within a domain, `ord_epoch` values issued to the bus must be monotonically non-decreasing (when ordering is enforced). |

### 7B.2 Performance Characterization

Generate from ORD-01 through ORD-08:

1. **Throughput vs. release ratio:** X = % RELEASE in traffic, Y = throughput. Expect near-linear degradation because each release forces a drain point.
2. **Drain latency histogram:** Distribution of how long the release drain takes (depends on outstanding_writes count and bus write latency). CDF plot.
3. **Hold latency histogram:** Distribution of how long the acquire hold blocks younger operations. CDF plot.
4. **Cross-domain independence verification:** Overlay domain 0 (with acquire holds) and domain 1 (all relaxed) throughput timeseries from ORD-05. Domain 1 should track the all-relaxed baseline.
5. **OoO + ordering interaction:** From ORD-06, plot effective outstanding per domain. OoO should allow cross-domain reordering while honoring intra-domain order.

---

## 8. Output Artifacts

The TLM produces the following artifacts for consumption by RTL design and DV:

### 8.1 CSV Data Files

| File | Content | Used By |
|------|---------|---------|
| `frag_results.csv` | Per-experiment fragmentation traces | RTL: malloc block size, free-list optimization |
| `rate_latency.csv` | Throughput/latency per offered rate per config | RTL: default outstanding depth, payload depth |
| `ooo_speedup.csv` | In-order vs. OoO throughput comparison | RTL: OoO enable decision for AXI4 targets |
| `atomic_impact.csv` | Throughput degradation vs. atomic ratio | RTL: atomic lock implementation choice |
| `credit_analysis.csv` | Stall rate per payload depth per outstanding | RTL: payload RAM sizing |
| `priority_analysis.csv` | Internal latency under external saturation | RTL: reserved slot count |
| `ordering_impact.csv` | Release drain / acquire hold latency and throughput overhead | RTL: ordering tracker sizing, AxUSER width |
| `sizing_sweep.csv` | Parameter sweep results | RTL: default parameter table |

### 8.2 Plots (Generated via Python Post-Processing)

| Plot | Type | Source |
|------|------|--------|
| Rate-latency curves (overlay by outstanding depth) | Line plot, X=offered rate, Y=latency | `rate_latency.csv` |
| Throughput saturation curves | Line plot, X=offered rate, Y=throughput | `rate_latency.csv` |
| Fragmentation cost over time | Time series, X=transaction, Y=frag_cost | `frag_results.csv` |
| OoO speedup vs. latency variance | Scatter, X=stddev, Y=speedup | `ooo_speedup.csv` |
| Atomic throughput degradation | Bar chart, X=atomic%, Y=throughput | `atomic_impact.csv` |
| Buffer sizing knee chart | Line plot, X=parameter, Y=throughput | `sizing_sweep.csv` |
| Internal priority latency under load | Box plot, X=external_load, Y=int_latency | `priority_analysis.csv` |
| Credit utilization CDF | CDF, X=credit_used/credit_total | `credit_analysis.csv` |
| Release drain latency CDF | CDF, X=drain_latency_ns | `ordering_impact.csv` |
| Acquire hold latency CDF | CDF, X=hold_latency_ns | `ordering_impact.csv` |
| Throughput vs. release ratio | Line plot, X=release%, Y=throughput | `ordering_impact.csv` |
| Cross-domain independence | Timeseries overlay, domain 0 vs. domain 1 throughput | `ordering_impact.csv` |

### 8.3 DV Test Case Recommendations

After TLM experiments complete, the following DV cases should be selected based on TLM findings:

| TLM Finding | DV Action |
|-------------|-----------|
| Fragmentation is severe at bimodal burst lengths | Add DV test: bimodal L={1,256} workload, verify no admission failure in RTL |
| OoO speedup > 1.5 at uniform(4,50) latency | Add DV test: OoO enabled, verify AXI4 burst reordering correct |
| Credit stalls at 8×256 outstanding reads | Add DV test: 8 concurrent L=256 reads, verify backpressure (not overflow) |
| Internal latency bounded at < 100 ns under saturation | Add DV assertion: int CSR read latency < 100 cycles under full ext load |
| Atomic lock holds for read_lat + 3 + write_lat | Add DV test: atomic RMW, verify lock signal timing, verify no other bus activity during lock |
| Free-list leaks under OoO free patterns | Add DV test: 10k transactions, verify free_count returns to RAM_DEPTH at quiesce |
| Release drain takes > N cycles for outstanding writes | Add DV assertion: release completion latency matches expected drain time |
| Acquire hold blocks younger same-domain ops | Add DV test: acquire + younger reads, verify no younger-than-acquire read data returned before acquire completes |
| Cross-domain traffic unaffected by ordering | Add DV test: domain 0 acquire pending, domain 1 relaxed traffic proceeds normally |
| Ordering has zero overhead on relaxed traffic | Add DV assertion: relaxed transaction latency unchanged when ordering tracker is present |

**These DV cases will be added to DV_PLAN.md after TLM experiments complete (per user instruction).**

---

## 9. File Plan

```
slow-control_hub/
├── tlm/
│   ├── CMakeLists.txt                  Thin wrapper (Python dispatch, no C++ build)
│   ├── README.md                       Quick-start: run, plot
│   │
│   ├── src/
│   │   ├── __init__.py
│   │   ├── sc_hub_tlm_top.py           Top-level testbench module
│   │   ├── sc_pkt_source.py            SC command packet generator
│   │   ├── sc_hub_model.py             Hub TLM model (top-level, event-driven)
│   │   ├── sc_hub_pkt_rx_model.py      S&F validation + classification
│   │   ├── sc_hub_admit_ctrl.py        Admission control
│   │   ├── sc_hub_buffer.py            8 subFIFOs container
│   │   ├── sc_hub_hdr_fifo.py          Header FIFO (seq-number ring)
│   │   ├── sc_hub_pld_ram.py           Linked-list payload RAM
│   │   ├── sc_hub_malloc.py            Malloc/free module
│   │   ├── sc_hub_dispatch.py          Dispatch FSM (in-order / OoO)
│   │   ├── sc_hub_credit_mgr.py        Upload payload credit manager
│   │   ├── sc_hub_csr.py               Internal CSR register bank
│   │   ├── sc_hub_atomic.py            Atomic RMW computation
│   │   ├── sc_hub_ord_tracker.py       Per-domain ordering state + drain/hold
│   │   ├── sc_hub_pkt_tx_model.py      Reply assembly
│   │   ├── bus_target_model.py         System bus slave (latency model)
│   │   └── perf_collector.py           Performance metric collection
│   │
│   ├── include/
│   │   ├── __init__.py
│   │   ├── sc_hub_tlm_types.py         Shared types (SCCommand, TxState, enums)
│   │   ├── sc_hub_tlm_config.py        Configuration structs (HubConfig, LatencyModelConfig, WorkloadConfig)
│   │   └── sc_hub_tlm_workload.py      Workload distribution definitions (13 profiles)
│   │
│   ├── tests/
│   │   ├── __init__.py
│   │   ├── experiment_catalog.py       Central catalog: all experiment configs by ID
│   │   ├── frag/
│   │   │   └── frag_01_uniform.py      Entry point for FRAG-01 through FRAG-08
│   │   ├── rate/
│   │   │   └── rate_01_baseline.py     Entry point for RATE-02 through RATE-12
│   │   ├── ooo/
│   │   │   └── ooo_01_fixed_lat.py     Entry point for OOO-01 through OOO-06
│   │   ├── atom/
│   │   │   └── atom_01_no_atomic.py    Entry point for ATOM-01 through ATOM-04
│   │   ├── cred/
│   │   │   └── cred_01_deep_pld.py     Entry point for CRED-01 through CRED-04
│   │   ├── prio/
│   │   │   └── prio_01_saturated.py    Entry point for PRIO-01 through PRIO-04
│   │   ├── ord/
│   │   │   ├── __init__.py
│   │   │   ├── checks.py              ORD-C01 through ORD-C06 correctness checks
│   │   │   ├── ord_01_release_shallow.py  Entry point for ORD-01 through ORD-08
│   │   │   ├── ord_c01_no_bypass.py       Entry point for correctness checks
│   │   │   └── ord_08_with_atomics.py     Entry point for ORD-08
│   │   └── size/
│   │       └── size_01_outstanding.py  Entry point for SIZE-01 through SIZE-06
│   │
│   ├── scripts/
│   │   ├── run_all.sh                  Run all experiments + checks + plots
│   │   ├── run_category.sh             Run one category
│   │   ├── run_experiment.py           Experiment dispatcher (by ID or category)
│   │   ├── run_ord_checks.py           Run ORD-C01 through ORD-C06
│   │   ├── run_ordering_scan.py        Release-ratio sweep analysis
│   │   ├── generate_ord_notebook.py    Jupyter notebook generation
│   │   └── plot_results.py             Reads CSV, generates all plots
│   │
│   └── results/                        (generated, git-ignored)
│       ├── csv/                        Raw data files
│       └── plots/                      Generated PNG/PDF plots
│
└── TLM_PLAN.md                        THIS FILE
```

---

## 10. Build and Run

### 10.1 Dependencies

| Dependency | Version | Notes |
|------------|---------|-------|
| Python 3 | 3.8+ | Simulation engine + plotting |
| matplotlib | 3.5+ | Plot generation |
| pandas | 1.4+ | CSV analysis in plot scripts |

No SystemC, no C++ compiler, no simulator license required.

### 10.2 Build

No build step required — pure Python.

```bash
cd slow-control_hub/tlm
# Optional: install Python deps
pip install matplotlib pandas
```

### 10.3 Run

```bash
# Run all experiments + correctness checks + plots
./scripts/run_all.sh

# Run one category
./scripts/run_category.sh frag

# Run one experiment by ID
python3 scripts/run_experiment.py FRAG-01

# Run ordering correctness checks only
python3 scripts/run_ord_checks.py

# Generate plots from existing CSV
python3 scripts/plot_results.py results/csv/ results/plots/
```

### 10.4 Expected Runtime

Python discrete-event simulation is significantly faster than the original SystemC estimate.

| Category | Base Experiments | Sim Runs (with sweeps) | Est. Runtime |
|----------|-----------------|------------------------|-------------|
| FRAG | 8 | 8 | ~10 sec |
| RATE | 11 (each sweeps 10 rate points) | 110 | ~60 sec |
| OOO | 6 (each runs in-order + OoO pair) | 12 | ~10 sec |
| ATOM | 4 | 4 | ~5 sec |
| CRED | 4 | 4 | ~5 sec |
| PRIO | 4 | 4 | ~5 sec |
| ORD | 8 performance (each runs ordered + baseline) | 16 | ~15 sec |
| ORD-C | 6 correctness checks | 6 | ~10 sec |
| SIZE | 6 (each sweeps multiple points) | 26 | ~30 sec |
| **Total** | **57 (51 perf + 6 correctness)** | **~190** | **~3 min** |

**Note:** 18 experiments from the original plan (RATE-01, ATOM-05/06, OOO-C01–C07, OOO-F01–F03) are not yet implemented in the catalog. See implementation status notes below.

---

## 11. TLM-to-RTL Traceability

Each TLM component maps to an RTL module:

| TLM Component | RTL Module | Fidelity |
|---------------|------------|----------|
| `sc_hub_malloc` | `sc_hub_malloc.vhd` | Exact algorithm (linked-list, free-list) |
| `sc_hub_pld_ram` | `sc_hub_pld_ram.vhd` | Same RAM structure (data + next_ptr + flags) |
| `sc_hub_hdr_fifo` | `sc_hub_hdr_fifo.vhd` | Same entry format, same depth |
| `sc_hub_admit_ctrl` | `sc_hub_admit_ctrl.vhd` | Same check sequence, same revert logic |
| `sc_hub_credit_mgr` | `sc_hub_credit_mgr.vhd` | Same reserve/release protocol |
| `sc_hub_dispatch` | Part of `sc_hub_core.vhd` | Same FSM states, same priority logic |
| `sc_hub_atomic` | Part of `sc_hub_avmm_handler.vhd` / `sc_hub_axi4_handler.vhd` | Same lock sequence |
| `sc_hub_ord_tracker` | `sc_hub_ord_tracker.vhd` | Same per-domain state, same drain/hold FSM, same 4 correctness rules |
| `bus_target_model` | N/A (replaced by real bus) | Latency model only |
| `perf_collector` | CSR counters in `sc_hub_core.vhd` | Subset (RTL has counters, not histograms) |

**RTL parameter defaults** will be set based on TLM SIZE experiment results:
- `OUTSTANDING_EXT_MAX`: from SIZE-01 knee
- `EXT_PLD_DEPTH`: from SIZE-02 knee
- `INT_HDR_DEPTH`: from SIZE-03 (expected: 4 is sufficient)
- `OUTSTANDING_INT_RESERVED`: from PRIO experiments (expected: 2)
- `OOO_ENABLE`: compile-time, default false. TLM OOO experiments inform whether to enable for AXI4 targets.

---

## 12. Implementation Notes for Codex

This section provides guidance for the Codex agent that will implement the TLM code.

### 12.1 Coding Conventions

**Implementation language: Python 3** (not SystemC — see section header note).

- Pure Python discrete-event behavioral model using `heapq`-based event scheduling
- All modules are Python classes (not sc_module)
- Timing modeled as explicit `float` nanosecond timestamps (no sc_time)
- All configuration via `HubConfig`, `LatencyModelConfig`, `WorkloadConfig` dataclasses (no hardcoded values)
- Experiment dispatch via `experiment_catalog.py` + `run_experiment.py`
- Output CSV via `perf_collector.basic_summary()` and `append_rows()`

### 12.2 Malloc Implementation Priority

The malloc module is the highest-priority component. Implement and unit-test it first:
1. Initialize free list (all lines linked)
2. `malloc(size)` → walk free list, collect `size` lines, link into chain, return head_ptr
3. `free(head_ptr)` → walk chain, mark all lines free, prepend to free list
4. `get_free_count()` → return free_count
5. `get_frag_cost()` → walk all allocated chains, count pointer hops vs. data words

Unit test: 1000 random malloc/free sequences with varying sizes. Verify:
- `free_count` always consistent with actual free lines
- No double-free, no use-after-free
- After freeing everything, `free_count == RAM_DEPTH`

### 12.3 OoO Dispatch Implementation

When `OOO_ENABLE = true` in config:
- `sc_hub_dispatch` maintains a scoreboard of outstanding transactions indexed by `seq_num`
- On bus completion: mark scoreboard entry as complete, push to appropriate upload header FIFO
- Reply assembler: scan scoreboard for any completed entry (round-robin priority between ext and int, with int priority)
- When `OOO_ENABLE = true` but CSR `OOO_CTRL.enable = false` at runtime: fall back to in-order (use `reply_order_fifo`)

When `OOO_ENABLE = false` in config:
- No scoreboard. Dispatch strictly follows `cmd_order_fifo`. Reply assembler follows `reply_order_fifo`.
- Simpler data path, less logic.

### 12.4 Experiment Runner Pattern

Each experiment is defined in `experiment_catalog.py` with its configuration and invoked via `run_experiment.py`:

1. `experiment_catalog.py` maps experiment ID → `(HubConfig, LatencyModelConfig, WorkloadConfig)` tuple
2. `run_experiment.py` dispatches to a mode-specific runner (frag, rate_sweep, ooo_compare, size sweep, ordering_impact, or standard)
3. Runner instantiates `ScHubTlmTop`, calls `top.run()`, queries `perf.basic_summary()`
4. Results written as CSV rows to `results/csv/`

Entry-point scripts (e.g., `frag_01_uniform.py`) simply call `main(["FRAG-01"])`.

The `run_category.sh` script runs all experiments in a category via `run_experiment.py --category <cat>`.

### 12.5 Ordering Tracker Implementation

The ordering tracker (`sc_hub_ord_tracker`) manages 16 independent ordering domains. Implement as follows:

1. **Data structure:** `std::array<ord_domain_state, 16> domains;` — initialized to all-zero (no pending, no blocked)
2. **On packet admission:** extract `order_type`, `ord_dom_id` from header. If RELAXED, check `domains[D].younger_blocked` — if false, pass through with zero overhead. If true, wait on `sc_event` until unblocked.
3. **Release path:** Set `release_pending[D]=true`, `younger_blocked[D]=true`. Start a `SC_THREAD` that waits until `outstanding_writes[D]==0` (use `sc_event` triggered by write completion callbacks). Then emit the release transaction, wait for bus ack, clear pending/blocked.
4. **Acquire path:** Set `acquire_pending[D]=true`. Issue the acquire read. Set `younger_blocked[D]=true`. Wait for read response. Clear pending/blocked.
5. **Write completion callback:** Called by bus handler when write response arrives. Decrement `domains[D].outstanding_writes`. If `outstanding_writes[D]==0 && release_pending[D]`, notify the release drain event.
6. **Integration with dispatch:** The dispatch FSM must check `domains[D].younger_blocked` before issuing. If blocked for domain D, skip to next command (possibly from a different domain if OoO=on).

**Key correctness property:** The domain state check on the RELAXED fast path must be O(1) — a single array lookup. Do NOT walk a linked list or search a map.

### 12.6 Key Edge Cases to Model

These must be tested by the TLM (some are correctness, some are performance):

| # | Edge Case | How to Test |
|---|-----------|-------------|
| 1 | Malloc fails (free_count < request_size) | CRED-03: 8 × L=256 reads exhaust 512-word payload |
| 2 | Admission revert (header written, payload malloc fails) | Set payload RAM to near-full, attempt large write |
| 3 | Free-list corruption after OoO free | OOO-F01: randomize free order, verify free_count consistency |
| 4 | Credit reservation + deallocation race | Issue read, reserve credit, read data arrives, free credit, next read reserves — no double-count |
| 5 | Internal priority under atomic lock | PRIO-04: atomic holds bus, internal CSR must still complete |
| 6 | OoO runtime toggle during transactions in flight | Toggle OOO_CTRL.enable while 4 transactions outstanding — must drain in-order then switch |
| 7 | Order FIFO full (outstanding limit reached) | Push exactly OUTSTANDING_LIMIT commands, verify backpressure |
| 8 | Payload pointer wrap in ring buffer (for header FIFOs) | Run > 256 transactions through 8-deep header FIFO, verify seq_num wrap |
| 9 | Atomic RMW to same address as outstanding read | Issue read to addr X, then atomic RMW to addr X — atomic must wait for read to complete (no data hazard) |
| 10 | All 8 subFIFOs simultaneously non-empty | Mixed workload with concurrent int/ext read/write — verify all 8 subFIFOs have data at some point |
| 11 | Fragmentation recovery after long OoO run | OOO-F03: measure frag_cost recovery time |
| 12 | Zero-outstanding mode (outstanding=0) | Edge case: should this mean "blocking, 1 at a time" or "disabled"? TLM should handle gracefully |
| 13 | Release with zero outstanding writes | RELEASE arrives when `outstanding_writes[D]==0` — should drain instantly (no wait), just emit and clear |
| 14 | Back-to-back releases in same domain | Two RELEASE packets arrive consecutively in domain D — second must wait for first to complete |
| 15 | Acquire + OoO cross-domain bypass | Domain 0 acquire pending, domain 1 RELAXED — verify domain 1 bypasses freely (OoO=on) |
| 16 | All 16 domains active simultaneously | Stress: each domain has 1 outstanding, verify no state corruption between domains |
| 17 | Ordering + admission revert | RELEASE packet admitted, payload malloc succeeds, but header FIFO full — revert must also clear ordering state |

---

## 13. Success Criteria

The TLM phase is complete when:

1. All 57 implemented experiments pass (correctness checks) or produce valid CSV output (performance). 18 planned experiments are not yet implemented — see section 10.4 note.
2. All 12 plots are generated and reviewed
3. The following design questions are answered with quantitative data:
   - What is the default `OUTSTANDING_EXT_MAX`? (from SIZE-01 knee)
   - What is the default `EXT_PLD_DEPTH`? (from SIZE-02 knee)
   - Is OoO beneficial for the feb_system AXI4 target? (from OOO experiments)
   - What is the fragmentation cost under realistic workload? (from FRAG experiments)
   - What is the atomic RMW throughput impact? (from ATOM experiments)
   - Are 2 reserved internal slots sufficient? (from PRIO experiments)
   - What is the release drain overhead under realistic ordering ratios? (from ORD experiments)
   - What is the acquire hold overhead? (from ORD experiments)
   - Are 16 ordering domains sufficient? (from ORD-05, ORD-06)
   - Is cross-domain independence maintained under load? (from ORD-C05)
   - Does ordering have zero overhead on relaxed traffic? (from ORD-I04)
4. DV test case recommendations (section 8.3) are concrete and traceable to TLM findings
5. RTL parameter defaults are set based on TLM results (section 11)
6. Software packet format with ORDER/ORD_DOM_ID fields is validated against the four correctness rules (ORD-C01 through ORD-C06)
