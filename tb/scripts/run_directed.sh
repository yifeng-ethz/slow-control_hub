#!/usr/bin/env bash
# ============================================================================
# run_directed.sh — Run directed (SystemVerilog) TB test(s)
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TB_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

usage() {
  cat <<'EOF'
Usage:
  run_directed.sh [TEST_NAME ...]

Examples:
  run_directed.sh smoke_basic
  run_directed.sh T001 T002 T003

Environment:
  BUS_TYPE         AVMM (default) | AXI4
  VLOG_OPTS        Extra options passed to vlog
  VCOM_OPTS        Extra options passed to vcom
  VSIM_OPTS        Extra options passed to vsim
  SIM_DO           Command passed to vsim -do (default: run -all; quit -f)
EOF
}

if [ "${1-}" = "-h" ] || [ "${1-}" = "--help" ]; then
  usage
  exit 0
fi

if [ "$#" -eq 0 ]; then
  TESTS=("smoke_basic")
else
  TESTS=("$@")
fi

pass_count=0
fail_count=0
run_count=0

run_one() {
  local test_name="$1"
  local log_file
  local -a make_args=(
    "TEST_NAME=$test_name"
    "BUS_TYPE=${BUS_TYPE:-AVALON}"
  )

  if [ -n "${VLOG_OPTS-}" ]; then
    make_args+=("VLOG_OPTS=${VLOG_OPTS}")
  fi
  if [ -n "${VCOM_OPTS-}" ]; then
    make_args+=("VCOM_OPTS=${VCOM_OPTS}")
  fi
  if [ -n "${VSIM_OPTS-}" ]; then
    make_args+=("VSIM_OPTS=${VSIM_OPTS}")
  fi
  if [ -n "${SIM_DO-}" ]; then
    make_args+=("SIM_DO=${SIM_DO}")
  fi

  run_count=$((run_count + 1))
  printf '%s\n' "----------------------------------------------------------------"
  printf '[%d] run_sim_smoke TEST_NAME=%s BUS_TYPE=%s\n' \
         "$run_count" "$test_name" "${BUS_TYPE:-AVALON}"

  log_file="$(mktemp "${TMPDIR:-/tmp}/sc_hub_directed.${test_name}.XXXXXX.log")"
  if (cd "$TB_DIR" && make run_sim_smoke "${make_args[@]}" 2>&1 | tee "$log_file"); then
    if rg -q '^# \*\* Error:' "$log_file"; then
      fail_count=$((fail_count + 1))
      echo "[FAIL] ${test_name}"
    else
      pass_count=$((pass_count + 1))
      echo "[PASS] ${test_name}"
    fi
  else
    fail_count=$((fail_count + 1))
    echo "[FAIL] ${test_name}"
  fi
  rm -f "$log_file"
}

for test_name in "${TESTS[@]}"; do
  run_one "$test_name"
done

printf '%s\n' "----------------------------------------------------------------"
echo "Directed run summary: pass=$pass_count fail=$fail_count total=$run_count"
if [ "$fail_count" -ne 0 ]; then
  echo "Directly driven regressions had failures."
  exit 1
fi
