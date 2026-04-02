# `sc_hub` TLM Harness

This directory implements the `TLM_PLAN.md` harness as a fast Python discrete-event model.
The plan asked for SystemC/TLM 2.0, but the current workspace does not ship a local SystemC
build. This harness keeps the same architectural split, experiment categories, CSV outputs,
and plot flow so the RTL agents can iterate on sizing and latency behavior now.

## What Is Modeled

- Split-buffer hub with separate external/internal header and payload resources
- Linked-list payload RAM with free-list allocation and fragmentation-induced pointer-hop cost
- Internal reserved outstanding slots
- In-order vs OoO reply behavior
- Atomic external RMW that blocks the external bus but does not block internal CSR traffic
- Fixed, uniform, bimodal, and address-dependent latency models
- 64K-word bus memory model for read/write/atomic correctness

## Layout

- `include/`: shared types, configuration objects, workload definitions
- `src/`: allocator, payload RAM, bus model, hub model, performance collector
- `tests/`: experiment catalog plus category entrypoints
- `scripts/`: batch runners and plotting
- `results/`: generated CSV and plot artifacts (git-ignored)

## Quick Start

```bash
cd /home/yifeng/packages/mu3e_ip_dev/mu3e-ip-cores/slow-control_hub/tlm

# Run a representative subset from every category.
./scripts/run_all.sh

# Run one category.
./scripts/run_category.sh rate
./scripts/run_category.sh ord /home/yifeng/packages/mu3e_ip_dev/mu3e-ip-cores/slow-control_hub/tlm/results/ord_review/csv

# Run ORD correctness checks and parameter scans.
python3 scripts/run_ord_checks.py
python3 scripts/run_ordering_scan.py

# Run the concrete field-workload bundle and generate the review notebook.
python3 scripts/run_field_workload.py --csv-dir results/field_review_v4/csv
python3 scripts/generate_field_notebook.py --csv-dir results/field_review_v4/csv --out results/field_review_v4/field_workload_review.ipynb

# The field bundle writes its own namespaced CSV set under results/field_review_v4/csv.
# Use the executed notebook there for plots, or point custom scripts at that CSV directory.

# Run one named experiment.
python3 scripts/run_experiment.py RATE-08

# Generate plots from existing category CSV.
python3 scripts/plot_results.py results/csv results/plots
```

## Output Files

- `results/csv/frag_results.csv`
- `results/csv/rate_latency.csv`
- `results/csv/ooo_speedup.csv`
- `results/csv/atomic_impact.csv`
- `results/csv/ordering_impact.csv`
- `results/csv/ordering_transactions.csv`
- `results/csv/ordering_scan.csv`
- `results/csv/ordering_correctness.csv`
- `results/csv/ord_domain_trace.csv`
- `results/csv/credit_analysis.csv`
- `results/csv/priority_analysis.csv`
- `results/csv/sizing_sweep.csv`
- `results/csv/latency_cdf.csv`
- `results/csv/credit_trace.csv`
- `results/csv/outstanding_trace.csv`
- `results/field_review_v4/csv/field_summary.csv`
- `results/field_review_v4/csv/field_transactions.csv`
- `results/field_review_v4/csv/field_overlap_scan.csv`
- `results/field_review_v4/csv/field_flow_summary.csv`
- `results/field_review_v4/csv/field_config_summary.csv`
- `results/field_review_v4/csv/field_scenarios.csv`
- `results/field_review_v4/csv/field_credit_trace.csv`
- `results/field_review_v4/csv/field_outstanding_trace.csv`
- `results/field_review_v4/csv/field_ord_domain_trace.csv`

Representative ORD entry points:

- `tests/ord/ord_01_release_shallow.py`
- `tests/ord/ord_c01_no_bypass.py`
- `tests/ord/ord_08_with_atomics.py`

## Modeling Scope

This is a loosely-timed guidance model, not a cycle-accurate RTL surrogate.

- Root cause avoided: the current RTL has no split payload RAM or variable-latency bus memory yet.
- Effect: RTL-only simulation cannot answer the sizing, fragmentation, OoO, or credit questions in `TLM_PLAN.md`.
- Practical fix: use this harness to establish qualitative curves and parameter knees first, then match the RTL behavior to the same trends once the memory-backed architecture exists.

Ordering-specific guidance:

- Root cause: without explicit per-domain drain/hold state, a same-domain RELEASE or ACQUIRE can be bypassed by younger traffic when OoO scan logic looks ahead in the queues.
- Effect: the harness underestimates ordering overhead and misses the no-bypass correctness rules from `TLM_PLAN.md`.
- Practical fix: keep an explicit per-domain tracker, export event-level drain/hold traces, and compare RTL against the same release-ratio, acquire-ratio, and cross-domain plots produced here.
