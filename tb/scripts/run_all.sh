#!/usr/bin/env bash
# ============================================================================
# run_all.sh — Convenience entry for full tb harness sweep
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0

run_step() {
  local label="$1"
  local script="$2"

  echo "------------------------------------------------------------"
  echo "Starting ${label}..."
  if "$script"; then
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    FAIL_COUNT=$((FAIL_COUNT + 1))
    echo "[FAIL] ${label}"
  fi
}

run_blocked_step() {
  local label="$1"
  local script="$2"

  echo "------------------------------------------------------------"
  echo "Starting ${label}..."
  if "$script"; then
    SKIP_COUNT=$((SKIP_COUNT + 1))
    echo "[SKIP] ${label}"
  else
    FAIL_COUNT=$((FAIL_COUNT + 1))
    echo "[FAIL] ${label}"
  fi
}

run_step "run_basic" "$SCRIPT_DIR/run_basic.sh"
run_step "run_uvm" "$SCRIPT_DIR/run_uvm.sh"
run_blocked_step "run_perf (blocked by RTL handoff)" "$SCRIPT_DIR/run_perf.sh"
run_blocked_step "run_edge (blocked by RTL handoff)" "$SCRIPT_DIR/run_edge.sh"
run_blocked_step "run_error (blocked by RTL handoff)" "$SCRIPT_DIR/run_error.sh"

echo "============================================================"
echo "run_all.sh summary: pass=${PASS_COUNT} skip=${SKIP_COUNT} fail=${FAIL_COUNT}"
if [ "$FAIL_COUNT" -ne 0 ]; then
  echo "run_all.sh completed with failures."
  exit 1
fi

echo "run_all.sh completed."
