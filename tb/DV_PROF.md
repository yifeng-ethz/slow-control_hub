# SC_HUB v2 DV — Performance and Stress Cases

**Parent:** [DV_PLAN.md](DV_PLAN.md)
**Canonical ID Range:** P001-P128
**Current Implementation Aliases:** T300-T355 (implemented subset)
**Total:** 128 cases
**Method:** All UVM sweep (parametric), run via `sc_hub_sweep_test`

These tests produce publication-quality characterization data: rate-latency curves, OoO speedup scans, fragmentation cost under stress, credit utilization, internal priority bounds, and ordering overhead. Each test maps directly to a TLM experiment and validates RTL against TLM predictions.

**General methodology:** Each UVM sweep test runs a parameterised sequence with LCG-seeded stimulus. Cycle-accurate latency and throughput are measured by the `sc_hub_cov_collector` and compared against TLM CSV baselines (tolerance: +/- 15% for throughput, +/- 25% for tail latency due to cycle-accurate vs. approximate timing).

---

## 1. Rate-Latency Scan (RATE) -- 13 cases

Sweep offered rate from 10% to 100% of theoretical max. Measure delivered throughput and avg/P99 latency at RTL. Compare against TLM `rate_latency.csv`.

**Output per test:** CSV of `{offered_rate, delivered_throughput, avg_latency, p50_latency, p99_latency, max_latency}`.

**Plots:**
1. Throughput vs. offered rate (saturation curve)
2. Latency vs. offered rate (hockey-stick curve)
3. Overlay T301-T305 to show outstanding-depth impact

| ID | Bus | Scenario | BFM Latency | Outstanding | OoO | Workload | TLM Source |
|----|-----|----------|-------------|-------------|-----|----------|------------|
| T300 | AVMM | Baseline anchor: fixed lat, OD=1, single reads | fixed(8 cy) | 1 | off | 100% read, L=1. 10 rate points. | RATE-01 |
| T301 | AVMM | Outstanding sweep: depth=1 | fixed(8 cy) | 1 | off | 50% R/W, L=uniform(1,64). 10 rate points. | RATE-02 |
| T302 | AVMM | Outstanding sweep: depth=2 | fixed(8 cy) | 2 | off | same | RATE-03 |
| T303 | AVMM | Outstanding sweep: depth=4 | fixed(8 cy) | 4 | off | same | RATE-04 |
| T304 | AVMM | Outstanding sweep: depth=8 | fixed(8 cy) | 8 | off | same | RATE-05 |
| T305 | AVMM | Outstanding sweep: depth=16 | fixed(8 cy) | 16 | off | same | RATE-06 |
| T306 | AVMM | Variable latency, in-order | uniform(4,50 cy) | 8 | off | 100% read, L=1. 10 rate points. | RATE-07 |
| T307 | AXI4 | Variable latency, OoO | uniform(4,50 cy) | 8 | on | same | RATE-08 |
| T308 | AVMM | Bimodal latency (fast/slow slaves) | bimodal(4 cy, 40 cy, 50/50) | 8 | off | 100% read, L=1. 10 rate points. | RATE-09 |
| T309 | AXI4 | Bimodal latency, OoO | bimodal(4 cy, 40 cy, 50/50) | 8 | on | same | RATE-10 |
| T310 | AVMM | Mixed read/write, in-order | fixed(8 cy) read, fixed(4 cy) write | 8 | off | 50% R/W, L=uniform(1,32). 10 rate points. | RATE-11 |
| T311 | AVMM | Address-dependent latency (feb_system) | scratch=2cy, frame_rcv=uniform(4,12), histogram=uniform(6,16), ring_buf_cam=uniform(8,20) | 8 | off | feb_system_realistic mix. 10 rate points. | RATE-12 |
| T312 | AVMM | Back-to-back single reads (saturation) | fixed(1 cy) | 8 | off | 100% read, L=1. Max rate for 1000 transactions. Measure inter-reply gap. | PERF T113-T114 |

**Key comparisons for publication:**
- T301..T305 overlay: identifies the outstanding-depth knee (expected: 4-8 for AVMM at 8-cycle latency)
- T306 vs T307: OoO speedup under uniform variance
- T308 vs T309: OoO speedup under bimodal variance (expected: >1.5x)

---

## 2. OoO Speedup Scan (OOOS) -- 7 cases

Each test runs the same workload twice: OoO=off and OoO=on. Measures the speedup ratio at RTL.

**Output per test:** `{throughput_ino, throughput_ooo, speedup, avg_lat_ino, avg_lat_ooo, lat_reduction}`.

**Plots:**
1. Speedup vs. latency variance (scatter)
2. Effective outstanding vs. nominal outstanding
3. Reorder buffer occupancy histogram (ext_up_hdr entries in flight)

| ID | Bus | Scenario | BFM Latency | Outstanding | Workload | TLM Source |
|----|-----|----------|-------------|-------------|----------|------------|
| T313 | AXI4 | Fixed latency (control: expect speedup ~1.0) | fixed(8 cy) | 8 | 100% read, L=1, 3000 txns | OOO-01 |
| T314 | AXI4 | Uniform variance (moderate benefit) | uniform(4,50 cy) | 8 | 100% read, L=1, 3000 txns | OOO-02 |
| T315 | AXI4 | High variance (significant benefit) | uniform(4,200 cy) | 8 | 100% read, L=1, 3000 txns | OOO-03 |
| T316 | AXI4 | Fast CSR + slow ext (internal bypass) | int=fixed(2 cy), ext=uniform(10,50 cy) | 8 | 50% int, 50% ext, L=1, 3000 txns | OOO-04 |
| T317 | AXI4 | Mixed R/W with variance | uniform(4,50 cy) | 8 | 50% R/W, L=uniform(1,32), 3000 txns | OOO-05 |
| T318 | AXI4 | OoO with 10% atomics blocking | uniform(4,50 cy) + 10% atomic | 8 | 90% normal, 10% atomic, 3000 txns | OOO-06 |
| T319 | AXI4 | OoO CSR toggle mid-stream | uniform(4,50 cy) | 8 | 4000 txns: first 2000 OoO=on, toggle CSR, last 2000 OoO=off | OOO-C06 |

**Expected RTL results (from TLM):**
- T313: speedup ~1.0 (fixed latency -> no reordering benefit)
- T314: speedup ~1.3-1.8 (moderate variance)
- T315: speedup ~2.0-3.0 (high variance)
- T316: speedup >2.0 (fast internal bypasses slow external)

---

## 3. Fragmentation Stress (FRAGS) -- 8 cases

Stress the linked-list malloc/free under workloads that TLM predicts cause fragmentation. Verify no admission failure occurs in RTL and measure `frag_cost` (pointer hops during payload read).

**Output per test:** `{total_txns, frag_cost, peak_used, alloc_failures, free_count_min}`.

**Pass criteria:** `alloc_failures == 0` for all tests except T327 (where it is expected). `free_count` returns to `RAM_DEPTH` after all transactions complete (Assert A37).

| ID | Bus | Scenario | Workload | Duration | OoO | TLM Source |
|----|-----|----------|----------|----------|-----|------------|
| T320 | AVMM | Uniform burst, no OoO | L=uniform(1,256), 50% R/W, offered_rate=0.65 | 10k txns | off | FRAG-01 |
| T321 | AVMM | Bimodal burst (70% L=1, 30% L=256) | bimodal burst, 50% R/W | 10k txns | off | FRAG-02 |
| T322 | AVMM | Small bursts only (L=1..4) | L=uniform(1,4), 50% R/W | 10k txns | off | FRAG-03 |
| T323 | AVMM | Large bursts only (L=128..256) | L=uniform(128,256), 50% R/W | 10k txns | off | FRAG-04 |
| T324 | AXI4 | Uniform burst, OoO=on | same as T320, OoO enabled | 10k txns | on | FRAG-05 |
| T325 | AXI4 | Bimodal burst, OoO=on | same as T321, OoO enabled | 10k txns | on | FRAG-06 |
| T326 | AVMM | Pathological: alternating L=1 and L=256 | strict alternation | 10k txns | off | FRAG-07 |
| T327 | AVMM | Long soak (endurance) | same as T320 | 100k txns | off | FRAG-08 (scaled down from 1M for RTL runtime) |

**Key findings expected from TLM:**
- T324/T325 (OoO): higher frag_cost than in-order due to non-sequential free
- T326 (pathological): worst-case fragmentation but no admission failure (linked-list tolerates fragmentation)
- T327 (soak): frag_cost stabilizes, does not degrade over time

---

## 4. Credit and Priority (CREDP) -- 8 cases

Credit-based upload payload reservation + internal priority verification. Derived from TLM CRED-01..04 and PRIO-01..04.

### 4.1 Credit Analysis

**Output:** `{stall_count, stall_rate, avg_credit_utilization, peak_credit_utilization}`.

| ID | Bus | Scenario | Workload | Outstanding | Payload Depth | TLM Source |
|----|-----|----------|----------|-------------|---------------|------------|
| T328 | AVMM | Deep payload, reads only | 100% read L=64, offered_rate=0.8 | 8 | 512 | CRED-01 |
| T329 | AVMM | Shallow payload, reads only | 100% read L=64, offered_rate=0.8 | 8 | 128 | CRED-02 |
| T330 | AVMM | Max burst reads (8 x 256 = 2048 > 512) | 100% read L=256 | 8 | 512 | CRED-03 |
| T331 | AVMM | Mixed R/W, realistic | 50% R/W, L=16 | 8 | 512 | CRED-04 |

**Key insight from T330:** 8 outstanding x 256 max burst = 2048 words needed, but payload RAM is 512. Credit manager must limit effective outstanding to 2 (512/256). Verify backpressure, not overflow.

### 4.2 Internal Priority

**Output:** `{int_avg_latency, int_max_latency, int_stall_count, ext_throughput_impact}`.

**Pass criteria:** Internal CSR latency < 100 cycles regardless of external load (OUTSTANDING_INT_RESERVED=2 guarantees this).

| ID | Bus | Scenario | External Load | Internal Load | TLM Source |
|----|-----|----------|---------------|---------------|------------|
| T332 | AVMM | Ext saturated, int idle (baseline) | 100% ext, outstanding=8, offered_rate=1.0 | 0 | PRIO-01 |
| T333 | AVMM | Ext saturated, periodic int CSR | 100% ext, outstanding=8 | 1 CSR read every 100 txns | PRIO-02 |
| T334 | AVMM | Ext saturated, burst int CSR | 100% ext, outstanding=8 | 4 CSR reads back-to-back every 500 txns | PRIO-03 |
| T335 | AVMM | Ext saturated + 50% atomics, int CSR | 50% ext + 50% atomic | 1 CSR read every 50 txns | PRIO-04 |

---

## 5. Ordering Overhead Scan (ORDS) -- 8 cases

Measure RTL throughput overhead from release drain and acquire hold. Compare against TLM `ordering_impact.csv`.

**Output per test:** `{throughput_ordered, throughput_baseline, overhead_pct, avg_drain_latency, avg_hold_latency, max_drain_latency, max_hold_latency}`.

**Plots:**
1. Throughput vs. release ratio (line)
2. Drain latency CDF
3. Hold latency CDF
4. Cross-domain independence (domain 0 vs domain 1 throughput overlay from T340)

| ID | Bus | Scenario | Workload | Ordering Mix | Domains | OoO | TLM Source |
|----|-----|----------|----------|-------------|---------|-----|------------|
| T336 | AVMM | Release drain cost (shallow writes) | 100% write, L=1, 3k txns | 5% RELEASE, 95% RELAXED | 1 | off | ORD-01 |
| T337 | AVMM | Release drain cost (deep writes) | 100% write, L=64, 3k txns | 5% RELEASE, 95% RELAXED | 1 | off | ORD-02 |
| T338 | AVMM | Acquire hold cost | 100% read, L=1, 3k txns | 5% ACQUIRE, 95% RELAXED | 1 | off | ORD-03 |
| T339 | AVMM | Release + acquire pair (pub/con) | 50% R/W, 4k txns | 2% RELEASE, 2% ACQUIRE, 96% RELAXED | 1 | off | ORD-04 |
| T340 | AVMM | Multi-domain independence | 100% read, L=1, 2.5k txns | Dom 0: 50% traffic (10% ACQUIRE). Dom 1: 50% traffic (RELAXED only). | 2 | off | ORD-05 |
| T341 | AXI4 | Ordering + OoO interaction | uniform(4,50 cy), mixed, 4k txns | 5% RELEASE, 5% ACQUIRE across 4 domains | 4 | on | ORD-06 |
| T342 | AVMM | High release ratio stress (pathological) | 100% write, L=1, 3k txns | 50% RELEASE (every other write) | 1 | off | ORD-07 |
| T343 | AVMM | Ordering + atomics combined | mixed, 4k txns | 2% atomic, 3% RELEASE, 2% ACQUIRE | 1 | off | ORD-08 |

**Expected RTL results (from TLM):**
- T336: ~5% throughput overhead (release drain fast for single-word writes)
- T337: Higher overhead -- drain must wait for outstanding L=64 writes
- T340: Domain 1 throughput within 2% of all-relaxed baseline (cross-domain independent)
- T342: Severe degradation -- effective outstanding=1 (every other write is a barrier)

---

## 6. Buffer Sizing Sweep (SIZS) -- 6 cases

Sweep buffer parameters at RTL to find the optimal configuration. Results set RTL parameter defaults.

**Output per sweep point:** `{param_value, throughput, avg_latency, p99_latency, frag_cost, credit_stall_rate}`.

**Plots:** Parameter vs. throughput to identify the knee.

| ID | Bus | Swept Parameter | Sweep Values | Fixed Parameters | Workload | TLM Source |
|----|-----|----------------|-------------|------------------|----------|------------|
| T344 | AVMM | OUTSTANDING_LIMIT | {1, 2, 4, 8, 12, 16, 24, 32} | pld_depth=512, BFM lat=uniform(4,20 cy) | 50% R/W, L=uniform(1,64), 3k txns | SIZE-01 |
| T345 | AVMM | EXT_PLD_DEPTH | {64, 128, 256, 512, 1024} | outstanding=8, BFM lat=uniform(4,20 cy) | same | SIZE-02 |
| T346 | AVMM | INT_HDR_DEPTH | {1, 2, 4, 8} | outstanding=8, pld_depth=512 | 20% int, 80% ext, L=uniform(1,8), 3k txns | SIZE-03 |
| T347 | AVMM | Joint: OUTSTANDING x PLD_DEPTH | {4,8,16} x {256,512,1024} = 9 points | BFM lat=uniform(4,20 cy) | 50% R/W, L=uniform(1,64), 3k txns | SIZE-04 |
| T348 | AVMM | feb_system realistic profile | default params | address-dependent latency model | feb_system_realistic, 5k txns | SIZE-05 |
| T349 | AVMM | Worst-case large read | outstanding=8, pld=512 | BFM lat=uniform(4,20 cy) | 100% read, L=256, 1k txns | SIZE-06 |

**RTL parameter defaults will be set from:**
- T344 knee -> `OUTSTANDING_EXT_MAX`
- T345 knee -> `EXT_PLD_DEPTH`
- T346 -> `INT_HDR_DEPTH` (expected: 4 is sufficient)
- T347 -> Joint optimization
- T348 -> Validation against realistic workload
- T349 -> Worst-case sizing confirmation

---

## 7. UVM Performance Sweep Extensions (T350-T355)

These are UVM test variants of the above directed scans for automated regression and cross-coverage closure.

| ID | Method | Scenario | Sequence | Iterations |
|----|--------|----------|----------|------------|
| T350 | U | Rate-latency full sweep (all outstanding depths) | `sc_pkt_perf_sweep_seq` with OD in {1,2,4,8,16} x 10 rates | 50 |
| T351 | U | OoO speedup full sweep (all latency models) | `sc_pkt_ooo_seq` with lat in {fixed, uniform, bimodal, address_dep} x OoO {on,off} | 8 |
| T352 | U | Fragmentation soak (burst length sweep x free pattern) | `sc_pkt_burst_seq` with L in {1,4,16,64,128,256} x 10k txns | 6 |
| T353 | U | Credit sweep (payload depth x outstanding) | `sc_pkt_burst_seq` with PLD in {128,256,512} x OD in {4,8,16} | 9 |
| T354 | U | Ordering ratio sweep | `sc_pkt_ordering_seq` with RELEASE% in {0,1,2,5,10,25,50} | 7 |
| T355 | U | Atomic ratio sweep | `sc_pkt_atomic_seq` with atomic% in {0,1,5,10,25,50} | 6 |

## 8. Closure Extensions (implemented, non-canonical T-space)

These runs are checked-in closure helpers for current-tree DV and coverage work. They are intentionally outside the frozen canonical `Pxxx` overlay for now.

| ID | Bus | Scenario | Workload | Intent |
|----|-----|----------|----------|--------|
| T367 | AVMM + AXI4 | Mixed error-recovery stream | mixed traffic with periodic injected SLVERR/DECERR responses, nonincrementing, light internal CSR pressure | Close response/error propagation and recovery interactions without leaving the scalable perf-stream harness. |
| T368 | AVMM + AXI4 | Capability/identity CSR reads under load | mixed traffic with heavy internal `UID/META/HUB_CAP/FEB_TYPE` reads, masks, and nonincrementing packets | Close static observability paths and verify compile-time capability reporting under concurrent traffic. |

---

## 9. Result Comparison Protocol

For each performance test:

1. **Run TLM first:** `python3 scripts/run_experiment.py <TLM-ID>` produces CSV baseline.
2. **Run RTL:** `make run_uvm TEST=<DV-ID>` produces cycle-accurate CSV.
3. **Compare:** `python3 scripts/compare_tlm_rtl.py <TLM-CSV> <RTL-CSV>` reports:
   - Throughput delta (must be < 15% of TLM prediction)
   - Latency delta (must be < 25% for avg, < 50% for P99 — RTL cycle-accurate adds pipeline stages TLM abstracts)
   - Qualitative match: saturation curve shape, knee location, OoO speedup ratio direction

If RTL diverges > thresholds from TLM, investigate: the TLM may have abstracted away a pipeline stage or the RTL may have a bug. Either way, update TLM_NOTE.md with the finding.


---

## 10. Planned Expansion Cases (P057-P128)

The cases below are part of the canonical `DV_PROF` plan and count toward workflow completeness, but they are **not implemented in the runnable harness yet**. They exist to prevent ad-hoc performance testing later: each one names a concrete measurement, the feature interaction it isolates, and the failure mode it is expected to expose if the current model is incomplete.

### 9.1 Rate-Latency and Saturation Variants -- 12 planned cases

| Canonical ID | Bus | Scenario | Planned stimulus and metric | Why it exists |
|---|---|---|---|---|
| P057 | AVMM | Read-only knee under low outstanding | Sweep rate at `OUTSTANDING_LIMIT=2`, fixed 8-cycle read latency, collect knee shift vs `T301` | Separates scheduler saturation from credit saturation. |
| P058 | AVMM | Write-only knee under low outstanding | Sweep rate, 100% writes, `L=1`, `OUTSTANDING_LIMIT=2` | Write path has different occupancy and release behavior than read-only baseline. |
| P059 | AVMM | Deep-write knee | Sweep rate, 100% writes, `L=64`, fixed latency | Measures payload-pressure onset rather than bus-latency onset. |
| P060 | AVMM | Mixed short/long burst saturation | 50% `L=1`, 50% `L=128`, 10 rate points | Catches nonlinear knee migration hidden by uniform-burst sweeps. |
| P061 | AXI4 | Short-read knee with OoO disabled | AXI4, fixed latency, `OOO=off`, read-only | Establishes AXI4 in-order baseline before claiming OoO speedup. |
| P062 | AXI4 | Short-read knee with OoO enabled | Same as P061 with `OOO=on` | Clean apples-to-apples speedup at the same latency model. |
| P063 | AXI4 | Mixed R/W knee with OoO enabled | AXI4, 50% R/W, `L=uniform(1,32)` | Measures interaction between reorder capability and write responses. |
| P064 | AVMM | Address-hotspot saturation | Sweep rate on a 4-address working set | Detects scheduler unfairness and hidden same-address serialization. |
| P065 | AVMM | Wide-address saturation | Sweep rate across sparse 24-bit address map | Confirms throughput is not accidentally biased by low-address decode assumptions. |
| P066 | AVMM | Internal/external arbitration knee | Saturating external load plus periodic CSR reads, 10 rate points | Quantifies when reserved internal slots stop protecting control traffic. |
| P067 | AXI4 | Latency-jitter knee | Sweep rate with burst-to-burst latency jitter | Captures performance cliffs caused by reorder buffer burstiness rather than mean latency. |
| P068 | AVMM | Trailer-gap sensitivity under stress | Sweep rate with protocol-valid download bubbles on long writes | Measures performance loss from legal packet gaps rather than malformed traffic. |

### 9.2 OoO Scalability and Fairness -- 12 planned cases

| Canonical ID | Bus | Scenario | Planned stimulus and metric | Why it exists |
|---|---|---|---|---|
| P069 | AXI4 | OoO speedup vs outstanding depth 1/2/4/8 | Compare throughput ratio for four outstanding limits | Current plan varies latency, not reorder-window size. |
| P070 | AXI4 | OoO speedup under 90/10 read/write mix | Fixed latency variance, mostly reads | Checks whether writes poison reorder benefit even when rare. |
| P071 | AXI4 | OoO fairness across 4 domains | Mixed traffic tagged across 4 ordering domains | Ensures one hot domain cannot starve unrelated domains. |
| P072 | AXI4 | OoO fairness across 16 domains | Same as P071 but all domains active | Stresses RID bookkeeping and fairness metadata scale. |
| P073 | AXI4 | OoO head-of-line relief for bimodal bursts | Small bursts complete around one slow long burst | Quantifies benefit when latency variance and burst-length variance combine. |
| P074 | AXI4 | OoO with periodic atomics | 5% atomics, 95% normal reads | Measures how much lock episodes collapse reorder benefit. |
| P075 | AXI4 | OoO with release/acquire traffic | 5% barriers across 4 domains | Tests whether ordering fences erase expected OoO gain. |
| P076 | AXI4 | OoO under decode-error injection | Sparse decode faults during mixed traffic | Confirms errors do not corrupt reorder bookkeeping or bias throughput math. |
| P077 | AXI4 | OoO under back-to-back completions | Slave returns clustered completions after stalls | Catches reorder scoreboard burst-retire bugs. |
| P078 | AXI4 | OoO under response-id locality | Alternating fast/slow transactions to same ID bucket | Looks for hidden bias from simplified RID assignment. |
| P079 | AXI4 | OoO off/on transition between bursts | Runtime capability toggle across windows | Measures drain cost and residual stale state. |
| P080 | AXI4 | OoO soak fairness | 100k transactions, collect per-domain service histogram | Needed to claim long-run fairness, not just short benchmark speedup. |

### 9.3 Fragmentation and Resource Longevity -- 12 planned cases

| Canonical ID | Bus | Scenario | Planned stimulus and metric | Why it exists |
|---|---|---|---|---|
| P081 | AVMM | 24-hour equivalent short simulation soak surrogate | Repeated 1k-transaction epochs with leak snapshot per epoch | Makes leak trend visible earlier than a monolithic soak. |
| P082 | AVMM | Alternating deep writes and deep reads | `L=256` write, `L=256` read, repeat | Worst-case payload allocation/release churn. |
| P083 | AVMM | Read-heavy fragmentation with tiny gaps | `L=uniform(1,8)`, offered rate near saturation | Exposes pointer-hop growth under dense small payload use. |
| P084 | AVMM | Write-heavy fragmentation with sparse gaps | `L=uniform(1,64)`, 90% writes | Exercises upload-free vs download-alloc imbalance. |
| P085 | AXI4 | OoO fragmentation under domain striping | Domains round-robin, mixed burst lengths | Couples fragmentation to reorder completion order. |
| P086 | AXI4 | OoO fragmentation under hotspot addressing | Same address clusters with varying length | Looks for payload reuse/pathological freelist locality. |
| P087 | AVMM | Payload free-count watermark tracking | Sweep rates and log minimum free count | Converts anecdotal near-full behavior into a measured envelope. |
| P088 | AVMM | Header queue watermark tracking | Saturation run with tiny payloads | Distinguishes header pressure from payload pressure. |
| P089 | AVMM | Admission-failure margin search | Binary-search offered rate until first alloc reject | Finds true headroom rather than assuming it from sizing. |
| P090 | AXI4 | Reorder-buffer occupancy histogram | OoO-on mixed traffic, record occupancy CDF | Needed for quantitative justification of outstanding depth. |
| P091 | AVMM | Reset-after-soak reclamation audit | Soak then soft-reset then read free counters | Proves long runs do not leave latent leaked state across reset. |
| P092 | AVMM | Free-list wrap-around endurance | Force allocator head/tail wrap many times | Specifically targets pointer wrap logic, not just general soak. |

### 9.4 Credit, Payload, and Backpressure Pressure Tests -- 12 planned cases

| Canonical ID | Bus | Scenario | Planned stimulus and metric | Why it exists |
|---|---|---|---|---|
| P093 | AVMM | Credit stall threshold vs burst length | Sweep `L` from 1 to 256 under fixed payload depth | Finds the actual stall threshold curve. |
| P094 | AVMM | Credit stall threshold vs payload depth | Sweep depth 64/128/256/512 at fixed workload | Quantifies which depth points still buy throughput. |
| P095 | AVMM | Credit stall threshold vs internal reservation | Sweep reserved internal slots | Measures control-path protection cost in throughput terms. |
| P096 | AXI4 | Payload credit vs OoO window coupling | Sweep outstanding with `OOO=on` | Detects when reorder capacity outruns payload capacity. |
| P097 | AVMM | Upload FIFO pressure from read-heavy responses | 100% reads, `L=64`, near saturation | Needed because upload-side pressure is hidden in write-centric tests. |
| P098 | AVMM | Download FIFO pressure from long writes | 100% writes, `L=256`, legal gaps | Distinguishes parser-side pressure from bus-side pressure. |
| P099 | AVMM | Internal CSR latency under payload starvation | Saturate external payload, issue periodic CSR reads | Verifies reserved slots still help when payload is near empty/full edges. |
| P100 | AVMM | External backpressure release latency | Measure cycles from credit return to next admission | Catches sluggish restart after stalls. |
| P101 | AVMM | Multi-threshold hysteresis check | Oscillate around credit threshold | Looks for chatter or off-by-one admission bugs. |
| P102 | AXI4 | Credit stress with decode errors | Inject decode errors during near-full payload use | Ensures aborted transactions return credits promptly. |
| P103 | AVMM | Credit stress with ordered barriers | Release/acquire traffic while payload nearly full | Barriers often hide resource-return bugs. |
| P104 | AVMM | Deep-response drain after long stall | Force long stall then free all at once | Verifies burst drain does not miscount returned capacity. |

### 9.5 Ordering, Atomic, and Priority Mixed Stress -- 12 planned cases

| Canonical ID | Bus | Scenario | Planned stimulus and metric | Why it exists |
|---|---|---|---|---|
| P105 | AVMM | Barrier-heavy publication workload | 20% release, 20% acquire, mixed R/W | Measures real throughput collapse under strong ordering. |
| P106 | AVMM | Multi-domain barrier fairness | Four domains, one barrier-heavy, three relaxed | Ensures barrier-heavy domain does not globally poison progress. |
| P107 | AVMM | Atomic-heavy throughput | 25% atomics, 75% normal traffic | Quantifies throughput under realistic lock contention. |
| P108 | AVMM | Atomic hotspot vs relaxed background | Same-address atomics plus wide-address reads | Tests isolation between locked hotspot and unrelated traffic. |
| P109 | AVMM | Atomic plus release sequence cost | Release before and after atomic writeback | Captures compounded serialization penalty. |
| P110 | AXI4 | OoO with ordered domains and atomics | Mixed domains, barriers, and atomics | This is the realistic worst mixed-control workload. |
| P111 | AVMM | Internal CSR service under atomic lock | Periodic internal accesses during long atomics | Confirms control path still makes bounded progress. |
| P112 | AXI4 | OoO latency tail under barriers | Measure p99 under modest ordering rate | Throughput alone misses control-latency pain. |
| P113 | AVMM | Domain-count sweep for ordering overhead | 1/2/4/8/16 domains active | Needed to justify domain table sizing. |
| P114 | AVMM | Release-drain cost vs burst length | Release on `L=1/4/16/64/256` writes | Isolates drain latency from offered-rate confounds. |
| P115 | AVMM | Acquire-hold cost vs outstanding queue fill | Vary queue occupancy before acquire | Finds the actual hold penalty envelope. |
| P116 | AXI4 | Ordered-traffic starvation audit | Measure age histogram of relaxed traffic behind ordered bursts | Detects starvation that a mean metric would hide. |

### 9.6 Long-Run Coverage Harvest and Signoff Campaigns -- 12 planned cases

| Canonical ID | Bus | Scenario | Planned stimulus and metric | Why it exists |
|---|---|---|---|---|
| P117 | AVMM | Toggle-harvest random mix | Long constrained-random mix tuned for dead toggle bins | Purpose-built for structural coverage closure, not benchmarking. |
| P118 | AVMM | Branch-harvest malformed/legal alternation | Legal traffic with rare recoverable faults | Exercises error and recovery branches in one long run. |
| P119 | AXI4 | FSM-harvest OoO mixed run | Long run targeting reorder and timeout states | Needed for FSM coverage, not just functionality. |
| P120 | AVMM | Rare-latency tail harvest | Very wide latency distribution | Reaches watchdog and long-wait branches that short runs miss. |
| P121 | AVMM | Low-probability reset timing harvest | Inject soft reset at randomized legal phases | Builds recovery coverage over many windows. |
| P122 | AVMM | Address-map harvest across 24-bit space | Pseudorandom sparse address selection | Helps toggle decode and address compare logic. |
| P123 | AVMM | Capability-bit harvest | Randomize feature-flag dependent traffic within legal config | Ensures capability-gated code is touched when synthesized in. |
| P124 | AXI4 | RID/response pattern harvest | Stress reorder match logic with varied completion cadence | Coverage-focused equivalent of a directed fairness run. |
| P125 | AVMM | Free-list wrap coverage harvest | Random burst sizes biased to allocator corners | Pushes pointer arithmetic branches deliberately. |
| P126 | AVMM | Counter rollover harvest | Long enough run to approach sticky-counter saturation | Needed for otherwise cold wide-counter branches. |
| P127 | AVMM | Combined signoff stress | Mixed legal workload designed from uncovered bins | Final promoted stress candidate once closure converges. |
| P128 | AVMM | Plateau-detection campaign | Same as P127 but with incremental coverage snapshots | Lets signoff judge when additional runtime stops adding information. |
