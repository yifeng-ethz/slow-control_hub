#!/usr/bin/env bash
# ============================================================================
# run_error.sh — ERROR category harness runner
# ============================================================================
set -euo pipefail

cat <<'EOF'
run_error.sh
============

No implemented ERROR IDs are runnable in this snapshot.

Planned ERROR IDs from DV_PLAN: T500-T549.

Blocked by incomplete failure-injection and recovery wiring:
- Soft and hard bus-error propagation requires deterministic timeout/replay paths.
- Atomic, OoO, and ordering fault-injection cases rely on explicit feature-gate
  semantics in RTL headers and CSR handling.
- reset-domain/clock-boundary fault cases (T548/T549) are compile-dimension
  conditions and not covered in this snapshot harness.

See tb/implementation-status.md for exact RTL handoff list.
EOF

echo ""
echo "No ERROR runs were executed (blocked by RTL-handoff items below)."
