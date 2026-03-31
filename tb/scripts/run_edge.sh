#!/usr/bin/env bash
# ============================================================================
# run_edge.sh — EDGE category harness runner
# ============================================================================
set -euo pipefail

cat <<'EOF'
run_edge.sh
===========

No implemented EDGE IDs are runnable in this snapshot.

Planned EDGE IDs from DV_PLAN: T400-T449.

Blocked by missing RTL-visible boundaries:
- Free-list pressure and credit-admission revert visibility (T419, T429, T439).
- Ordering + OoO interaction under runtime toggles (T430-T433).
- Ordering/atomic collision behavior and CSR bypass semantics (T439, T440, T441).
- Internal slot reservation and release behavior (T444).

See tb/implementation-status.md for exact RTL handoff list.
EOF

echo ""
echo "No EDGE runs were executed (blocked by RTL-handoff items below)."
