# SC_HUB v2 DV — Performance and Stress Cases

**Parent:** [DV_PLAN.md](DV_PLAN.md)
**ID Range:** T300-T349
**Total:** 50 cases
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

## 7. UVM Performance Sweep Extensions (T350-T360)

These are UVM test variants of the above directed scans for automated regression and cross-coverage closure.

| ID | Method | Scenario | Sequence | Iterations |
|----|--------|----------|----------|------------|
| T350 | U | Rate-latency full sweep (all outstanding depths) | `sc_pkt_perf_sweep_seq` with OD in {1,2,4,8,16} x 10 rates | 50 |
| T351 | U | OoO speedup full sweep (all latency models) | `sc_pkt_ooo_seq` with lat in {fixed, uniform, bimodal, address_dep} x OoO {on,off} | 8 |
| T352 | U | Fragmentation soak (burst length sweep x free pattern) | `sc_pkt_burst_seq` with L in {1,4,16,64,128,256} x 10k txns | 6 |
| T353 | U | Credit sweep (payload depth x outstanding) | `sc_pkt_burst_seq` with PLD in {128,256,512} x OD in {4,8,16} | 9 |
| T354 | U | Ordering ratio sweep | `sc_pkt_ordering_seq` with RELEASE% in {0,1,2,5,10,25,50} | 7 |
| T355 | U | Atomic ratio sweep | `sc_pkt_atomic_seq` with atomic% in {0,1,5,10,25,50} | 6 |

---

## 8. Result Comparison Protocol

For each performance test:

1. **Run TLM first:** `python3 scripts/run_experiment.py <TLM-ID>` produces CSV baseline.
2. **Run RTL:** `make run_uvm TEST=<DV-ID>` produces cycle-accurate CSV.
3. **Compare:** `python3 scripts/compare_tlm_rtl.py <TLM-CSV> <RTL-CSV>` reports:
   - Throughput delta (must be < 15% of TLM prediction)
   - Latency delta (must be < 25% for avg, < 50% for P99 — RTL cycle-accurate adds pipeline stages TLM abstracts)
   - Qualitative match: saturation curve shape, knee location, OoO speedup ratio direction

If RTL diverges > thresholds from TLM, investigate: the TLM may have abstracted away a pipeline stage or the RTL may have a bug. Either way, update TLM_NOTE.md with the finding.
