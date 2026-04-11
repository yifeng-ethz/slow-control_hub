# TLM Implementation Review — Fix Notes for Codex

**Date:** 2026-03-31
**Reviewer:** Yifeng Wang (via Claude Code review agents)
**Scope:** All files under `tlm/` reviewed against `TLM_PLAN.md`
**Verdict:** Behaviorally faithful overall. 7 issues found, 2 HIGH severity.

---

## How to use this file

Each issue has a severity, root cause, affected file(s), and a fix specification.
Work through issues in severity order (HIGH first). Mark each issue DONE in this
file after fixing by changing `Status: OPEN` to `Status: DONE`.

---

## ISSUE 1 — Release drain ignores accepted-but-not-dispatched writes (HIGH)

**Status: DONE**

**File:** `tlm/src/sc_hub_ord_tracker.py`

**Root cause:** The ordering tracker increments `outstanding_writes` only when a
write is dispatched to the bus (`on_dispatch()`). Writes that have been admitted
into `ext_down_pld` / `int_down_pld` but are still waiting in the dispatch queue
are invisible to the release drain.

**Effect:** When a RELEASE packet arrives for domain D while older writes in
domain D are queued but not yet dispatched, the tracker sees
`outstanding_writes[D] == 0` and retires the release immediately. Those queued
writes then dispatch AFTER the release, violating correctness Rule R2:

> A release in D cannot complete until ALL older writes in D reach the required
> visibility point.

**Fix specification:**

Track writes at two levels per domain:

```python
class OrdDomainState:
    accepted_writes: int    # writes admitted into down_pld, not yet dispatched
    outstanding_writes: int # writes dispatched to bus, not yet visible-retired
```

- **On admission** (called from `sc_hub_admit_ctrl.py` or `sc_hub_model.py`
  after a write command is admitted): increment `accepted_writes[D]`.
- **On dispatch** (existing `on_dispatch()`): decrement `accepted_writes[D]`,
  increment `outstanding_writes[D]`.
- **On bus write completion** (existing `on_complete()`): decrement
  `outstanding_writes[D]`.
- **Release drain condition** changes from:

  ```python
  # WRONG — misses accepted writes
  state.outstanding_writes == 0
  ```

  to:

  ```python
  # CORRECT — waits for all writes at every level
  state.accepted_writes == 0 and state.outstanding_writes == 0
  ```

Integration point: the caller that admits a write command must call
`ord_tracker.on_admit(cmd)` so the tracker can increment `accepted_writes`.
Add this call in `sc_hub_model.py` inside `_try_admit()` (or equivalent),
right after the admission succeeds, BEFORE the command enters the dispatch
queue.

**Validation:** After fixing, ORD-C02 must still pass: issue 4 outstanding
writes with slow bus (100 ns), then RELEASE. Release must not retire until all
4 write responses arrive. Additionally, construct a new scenario: admit 4 writes
that are NOT yet dispatched (dispatch stalled by outstanding limit), then admit
a RELEASE. The release must not retire until all 4 writes dispatch AND complete.

---

## ISSUE 2 — 18 missing experiments from catalog (HIGH)

**Status: DONE**

**File:** `tlm/tests/experiment_catalog.py`

**Root cause:** The experiment catalog was populated with 51 base experiments
(performance only). Correctness and interaction tests from TLM_PLAN.md sections
6, 7, and parts of 4.5 were not added.

**Missing experiments:**

| ID | Section | Description |
|----|---------|-------------|
| `RATE-01` | 4.3 | Baseline: fixed(8 ns), outstanding=1, OoO=off, pld=512. Single-word reads. This is the anchor for all RATE comparisons. |
| `ATOM-05` | 4.5 | Atomic correctness: 1000 atomic RMW to same address, concurrent non-atomic reads. Verify no torn read/write. |
| `ATOM-06` | 4.5 | Atomic + internal priority: 50% bus saturated with atomics, verify internal CSR serviced within latency budget. |
| `OOO-C01` | 6.1 | Reply data integrity: every reply contains correct data regardless of completion order. |
| `OOO-C02` | 6.1 | No reply duplication: each command produces exactly one reply. |
| `OOO-C03` | 6.1 | No reply loss: every admitted command eventually produces a reply. |
| `OOO-C04` | 6.1 | Payload isolation: OoO consumption does not corrupt adjacent payload chains. |
| `OOO-C05` | 6.1 | Free-list consistency: after all transactions complete, `free_count == RAM_DEPTH`. |
| `OOO-C06` | 6.1 | Sequence number correctness: when OoO runtime-disabled, replies revert to in-order. |
| `OOO-C07` | 6.1 | Mixed int/ext ordering: internal replies bypass external ordering; no starvation. |
| `OOO-F01` | 6.3 | OoO frees in random order: measure fragmentation increase vs in-order free. |
| `OOO-F02` | 6.3 | Long-lived vs short-lived: mix L=256 (slow) and L=1 (fast) with OoO. Measure frag_cost. |
| `OOO-F03` | 6.3 | Fragmentation recovery: run OOO-F02 for 10k txns, then all L=1 for 10k. Does frag_cost recover? |
| `ATOM-C01` | 7.1 | RMW atomicity: two concurrent atomic RMW to same address, final value reflects both. |
| `ATOM-C02` | 7.1 | Lock exclusion: while atomic holds lock, no other external transaction proceeds. |
| `ATOM-C03` | 7.1 | Internal bypass during lock: internal CSR completes during atomic lock. |
| `ATOM-C04` | 7.1 | Atomic + error: read phase SLAVEERROR, write phase skipped, reply contains error. |
| `ATOM-C05` | 7.1 | Atomic reply format: reply contains original read data (pre-modify) and response code. |

**Fix specification:**

1. Add all 18 experiments to `experiment_catalog.py` with parameters matching
   the tables in TLM_PLAN.md sections 4.3, 4.5, 6.1, 6.3, and 7.1.

2. For correctness checks (OOO-C, ATOM-C), follow the same pattern as the
   existing `tests/ord/checks.py`: write a `checks.py` under `tests/ooo/` and
   `tests/atom/` respectively. Each check function should:
   - Construct a specific command sequence.
   - Run the model.
   - Assert the correctness property (exact data match, no duplication, etc.).
   - Return pass/fail with a diagnostic message on failure.

3. Add entry-point scripts:
   - `tests/ooo/ooo_c01_integrity.py` → dispatches OOO-C01 through OOO-C07
   - `tests/ooo/ooo_f01_random_free.py` → dispatches OOO-F01 through OOO-F03
   - `tests/atom/atom_c01_atomicity.py` → dispatches ATOM-C01 through ATOM-C05
   - `tests/atom/atom_05_correctness.py` → dispatches ATOM-05
   - `tests/atom/atom_06_int_priority.py` → dispatches ATOM-06
   - `tests/rate/rate_01_anchor.py` → dispatches RATE-01

4. Register the new entry points in `scripts/run_all.sh`.

5. **RATE-01 parameters:**
   - Latency: fixed(8 ns)
   - Outstanding: 1
   - OoO: off
   - Payload depth: 512
   - Workload: `single_word` with `read_ratio=1.0`
   - Sweep: 10 offered-rate points from 10% to 100%

6. **OOO-C06 note:** This test requires the runtime OoO toggle (see ISSUE 5).
   If OOO_CTRL is not yet a runtime CSR, skip this test with a clear
   `# SKIP: requires runtime OoO toggle (ISSUE 5)` comment.

---

## ISSUE 3 — Admission control: no revert-on-failure (MEDIUM)

**Status: DONE**

**File:** `tlm/src/sc_hub_admit_ctrl.py`

**Root cause:** The admission flow allocates payload via `pld.allocate()` and
pushes the header, but has no rollback path. If the header push fails after
payload allocation, the allocated payload lines leak (never freed).

Additionally, `cmd_order_fifo` space is not checked before admission begins.

**Effect:** Under stress near buffer-full, leaked payload lines permanently
reduce effective payload capacity. Fragmentation and credit experiments near
saturation may report pessimistic results because leaked lines reduce
`free_count` below the true available count.

**Fix specification:**

Wrap the admission sequence in a try/rollback pattern:

```python
def try_admit(self, cmd, buffers, ...):
    # 1. Check header FIFO space
    if not down_hdr.has_space():
        return False, "hdr_full"

    # 2. Check payload space (if write)
    pld_alloc = None
    if cmd.is_write and cmd.length > 0:
        if down_pld.get_free_count() < cmd.length:
            return False, "pld_full"

    # 3. Check cmd_order_fifo space
    if not cmd_order_fifo_has_space():
        return False, "order_full"

    # 4. Allocate payload (if write)
    if cmd.is_write and cmd.length > 0:
        pld_alloc = down_pld.allocate(cmd.length)
        if pld_alloc is None:
            return False, "pld_alloc_fail"

    # 5. Push header — if this fails, rollback payload
    if not down_hdr.push(cmd.seq):
        if pld_alloc is not None:
            down_pld.free(pld_alloc.head_ptr)
        return False, "hdr_push_fail"

    # 6. All succeeded — commit
    return True, pld_alloc
```

The key addition is the `down_pld.free()` call on line "rollback payload" if
the header push fails after payload allocation.

Also add the `cmd_order_fifo` space check at step 3. In the current
architecture this maps to checking that `len(dispatch_order) < outstanding_limit`
in `sc_hub_model.py`.

---

## ISSUE 4 — Ordering tracker: silent early-return in `on_dispatch()` (MEDIUM)

**Status: DONE**

**File:** `tlm/src/sc_hub_ord_tracker.py`, lines 54–55

**Root cause:**

```python
if cmd.order == OrderType.RELAXED and state.younger_blocked:
    return  # Early exit, no state update
```

This path should never execute: `can_dispatch()` already returns `False` when
`younger_blocked` is set, so a RELAXED transaction should never reach
`on_dispatch()` in a blocked domain. The silent return masks a caller bug.

**Effect:** If this path executes due to a caller error, `outstanding_txns` is
not incremented. A subsequent release drain may see `outstanding_writes == 0`
prematurely and retire the release early — a silent R2 violation.

**Fix specification:**

Replace the silent return with an assertion:

```python
if cmd.order == OrderType.RELAXED and state.younger_blocked:
    raise AssertionError(
        f"BUG: RELAXED cmd seq={cmd.seq} dispatched in domain "
        f"{cmd.ord_dom_id} while younger_blocked=True. "
        f"can_dispatch() should have prevented this."
    )
```

This makes the failure loud and immediate instead of a silent state corruption.

---

## ISSUE 5 — `OOO_CTRL` not exposed as runtime CSR (MEDIUM)

**Status: DONE**

**File:** `tlm/src/sc_hub_csr.py`

**Root cause:** OoO mode is controlled via `HubConfig.ooo_enable` (compile-time)
and `HubConfig.ooo_runtime_enable` (init-time). There is no CSR register
writable during simulation to toggle OoO at runtime.

**Effect:** Edge case 6 from TLM_PLAN.md section 12.6 is untestable:
"Toggle OOO_CTRL.enable while 4 transactions outstanding — must drain in-order
then switch." Also, OOO-C06 (sequence number correctness on runtime toggle)
cannot be validated.

**Fix specification:**

Add `OOO_CTRL` to the CSR register bank at offset matching the RTL_PLAN CSR
map (check RTL_PLAN.md for the OOO_CTRL register offset within 0xFE80–0xFE9F).

```python
class ScHubCsrModel:
    def __init__(self):
        self.registers = { ... }
        self.ooo_ctrl_enable = False  # Bit 0 of OOO_CTRL register

    def write(self, offset, value):
        if offset == OOO_CTRL_OFFSET:
            self.ooo_ctrl_enable = bool(value & 1)
        ...

    def read(self, offset):
        if offset == OOO_CTRL_OFFSET:
            return int(self.ooo_ctrl_enable)
        ...
```

Then modify `sc_hub_model.py` to check `self.csr.ooo_ctrl_enable` at runtime
(instead of only `hub_cfg.ooo_runtime_enable` at init). The dispatch and reply
assembly paths should query `self._ooo_reply_enabled()` which now reads the
live CSR value.

When OoO is toggled off at runtime while transactions are in flight:
1. Stop issuing new out-of-order transactions.
2. Drain all in-flight transactions in their natural completion order.
3. Resume in-order dispatch using `reply_order_fifo`.

---

## ISSUE 6 — 2 missing workload profiles (LOW)

**Status: DONE**

**File:** `tlm/include/sc_hub_tlm_workload.py`

**Root cause:** `read_heavy` and `write_heavy` workload profiles were not
implemented.

**Fix specification:**

Add two functions:

```python
def read_heavy(n: int = 5000, offered_rate: float = 1.0, seed: int = 42) -> WorkloadConfig:
    """80% read, 20% write, L=uniform(1,64)."""
    return WorkloadConfig(
        name="read_heavy",
        num_transactions=n,
        offered_rate=offered_rate,
        read_ratio=0.8,
        length_mode="uniform",
        length_min=1,
        length_max=64,
        seed=seed,
    )

def write_heavy(n: int = 5000, offered_rate: float = 1.0, seed: int = 42) -> WorkloadConfig:
    """20% read, 80% write, L=uniform(1,64)."""
    return WorkloadConfig(
        name="write_heavy",
        num_transactions=n,
        offered_rate=offered_rate,
        read_ratio=0.2,
        length_mode="uniform",
        length_min=1,
        length_max=64,
        seed=seed,
    )
```

---

## ISSUE 7 — FRAG-01 uses 5000 transactions instead of planned 10k (LOW)

**Status: DONE**

**File:** `tlm/tests/experiment_catalog.py`, FRAG-01 entry

**Root cause:** The `num_transactions` parameter for FRAG-01 is set to 5000.
TLM_PLAN.md section 4.2 specifies 10,000 transactions.

**Fix specification:**

Change the FRAG-01 workload config from `num_transactions=5000` to
`num_transactions=10000`. Also verify FRAG-02 through FRAG-07 (all specified as
10k in the plan) and FRAG-08 (specified as 1M). Adjust any that differ.

Expected values from TLM_PLAN.md section 4.2:

| ID | num_transactions |
|----|-----------------|
| FRAG-01 through FRAG-07 | 10,000 |
| FRAG-08 | 1,000,000 |

---

## Fix order recommendation

1. **ISSUE 1** (release drain accepted writes) — fix first, this is a
   correctness bug that invalidates ordering experiment results.
2. **ISSUE 4** (silent early-return) — fix second, one-line change, prevents
   masking ISSUE 1 regressions.
3. **ISSUE 3** (admission revert) — fix third, prevents resource leaks that
   contaminate stress experiments.
4. **ISSUE 2** (18 missing experiments) — add after the above fixes are in
   place, so the new experiments run against correct logic.
5. **ISSUE 5** (OOO_CTRL CSR) — fix before adding OOO-C06.
6. **ISSUE 6** (workload profiles) — trivial, do anytime.
7. **ISSUE 7** (FRAG count) — trivial, do anytime.

---

## Invariant tests still missing after all fixes

After ISSUE 2 is resolved, the following two ordering invariants from
TLM_PLAN.md section 7B.1 are still not explicitly tested:

- **ORD-I04**: Zero overhead on RELAXED — RELAXED transactions must incur zero
  additional latency from the ordering tracker.
- **ORD-I05**: Epoch monotonicity — within a domain, `ord_epoch` values issued
  to the bus must be monotonically non-decreasing.

Consider adding these as additional checks in `tests/ord/checks.py`.
