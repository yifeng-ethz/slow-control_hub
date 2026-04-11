#!/usr/bin/env bash
# ============================================================================
# run_uvm.sh — Run UVM harness TB test(s)
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TB_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

usage() {
  cat <<'EOF'
Usage:
  run_uvm.sh [UVM_TESTNAME ...]

Examples:
  run_uvm.sh sc_hub_base_test
  run_uvm.sh sc_hub_sweep_test sc_hub_base_test

Environment:
  BUS_TYPE         AVALON (default) | AXI4
  VLOG_OPTS        Extra options passed to vlog
  VCOM_OPTS        Extra options passed to vcom
  VSIM_OPTS        Extra options passed to vsim
  WORK             Optional explicit Questa work library
  COV_ENABLE       When set to 1, compile/run with code coverage enabled
  UCDB_OUT         Optional UCDB file saved on exit when COV_ENABLE=1
  SIM_DO           Command passed to vsim -do (default: run -all; quit -f)
EOF
}

if [ "${1-}" = "-h" ] || [ "${1-}" = "--help" ]; then
  usage
  exit 0
fi

if [ "$#" -eq 0 ]; then
  TESTS=("sc_hub_base_test" "sc_hub_sweep_test")
else
  TESTS=("$@")
fi

pass_count=0
fail_count=0
run_count=0

run_one() {
  local test_name="$1"
  local log_file
  local work_name="${WORK-}"
  local sim_do="${SIM_DO-}"
  local -a make_args=(
    "UVM_TESTNAME=$test_name"
    "BUS_TYPE=${BUS_TYPE:-AVALON}"
  )

  if [ -z "$work_name" ] && [ "${COV_ENABLE:-0}" = "1" ]; then
    work_name="work_sc_hub_cov_${BUS_TYPE:-AVALON}"
  fi
  if [ -n "$work_name" ]; then
    make_args+=("WORK=${work_name}")
  fi
  if [ "${COV_ENABLE:-0}" = "1" ]; then
    make_args+=("COV=1")
    if [ -z "$sim_do" ] && [ -n "${UCDB_OUT-}" ]; then
      sim_do="coverage save -onexit ${UCDB_OUT}; run -all; quit -f"
    fi
  fi
  if [ -n "${VLOG_OPTS-}" ]; then
    make_args+=("VLOG_OPTS=${VLOG_OPTS}")
  fi
  if [ -n "${VCOM_OPTS-}" ]; then
    make_args+=("VCOM_OPTS=${VCOM_OPTS}")
  fi
  if [ -n "${VSIM_OPTS-}" ]; then
    make_args+=("VSIM_OPTS=${VSIM_OPTS}")
  fi
  if [ -n "$sim_do" ]; then
    make_args+=("SIM_DO=${sim_do}")
  fi

  run_count=$((run_count + 1))
  printf '%s\n' "----------------------------------------------------------------"
  printf '[%d] run_uvm_smoke UVM_TESTNAME=%s BUS_TYPE=%s\n' \
         "$run_count" "$test_name" "${BUS_TYPE:-AVALON}"

  log_file="$(mktemp "${TMPDIR:-/tmp}/sc_hub_uvm.${test_name}.XXXXXX.log")"
  if (cd "$TB_DIR" && make run_uvm_smoke "${make_args[@]}" 2>&1 | tee "$log_file"); then
    if rg -q -e '# UVM_ERROR :[[:space:]]*[1-9][0-9]*'              -e '# UVM_FATAL :[[:space:]]*[1-9][0-9]*'              -e '\*\* Error:'              -e '\*\* Fatal:' "$log_file"; then
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
echo "UVM run summary: pass=$pass_count fail=$fail_count total=$run_count"
if [ "$fail_count" -ne 0 ]; then
  echo "UVM smoke regressions had failures."
  exit 1
fi
