#!/usr/bin/env bash
# ============================================================================
# run_perf.sh — PERF category harness runner
# ============================================================================
set -euo pipefail

cat <<'EOF'
run_perf.sh
============

No implemented PERF IDs are runnable in this snapshot.

Planned PERF IDs from DV_PLAN: T300-T349 plus T350-T355.

Blocked by missing RTL runtime instrumentation:
- Throughput and rate-latency scans (T300+), OoO speedup counters (T313+),
  fragmentation stress (T320+), credit/priority scan (T328+), and ordering overhead
  sweeps (T336+).
- Long-horizon characterization requires ordered statistics collection and stable
  runtime counters in core/handler paths (not present in this TB mapping snapshot).

See tb/implementation-status.md for exact RTL handoff list.
EOF

echo ""
echo "No PERF runs were executed (blocked by RTL-handoff items below)."
