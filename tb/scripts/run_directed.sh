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
  local run_workspace
  local modelsim_ini
  local work_lib
  local vlog_opts_with_mode
  local -a make_args=(
    "TEST_NAME=$test_name"
    "BUS_TYPE=${BUS_TYPE:-AVALON}"
  )

  if [ -n "${VLOG_OPTS-}" ]; then
    vlog_opts_with_mode="${VLOG_OPTS}"
  else
    vlog_opts_with_mode=""
  fi

  if [[ "$test_name" == "T532" || "$test_name" == "T533" || "$test_name" == "T534" ]]; then
    if [[ -n "${vlog_opts_with_mode}" ]]; then
      vlog_opts_with_mode+=" "
    fi
    vlog_opts_with_mode+="+define+SC_HUB_TB_AXI4_OOO_DISABLED"
  fi

  if [[ "$test_name" == "T535" || "$test_name" == "T536" || "$test_name" == "T537" ]]; then
    if [[ -n "${vlog_opts_with_mode}" ]]; then
      vlog_opts_with_mode+=" "
    fi
    if [[ "${BUS_TYPE:-AVALON}" == "AXI4" ]]; then
      vlog_opts_with_mode+="+define+SC_HUB_TB_AXI4_ORD_DISABLED"
    else
      vlog_opts_with_mode+="+define+SC_HUB_TB_AVALON_ORD_DISABLED"
    fi
  fi

  if [[ "$test_name" == "T538" || "$test_name" == "T539" ]]; then
    if [[ -n "${vlog_opts_with_mode}" ]]; then
      vlog_opts_with_mode+=" "
    fi
    if [[ "${BUS_TYPE:-AVALON}" == "AXI4" ]]; then
      vlog_opts_with_mode+="+define+SC_HUB_TB_AXI4_ATOMIC_DISABLED"
    else
      vlog_opts_with_mode+="+define+SC_HUB_TB_AVALON_ATOMIC_DISABLED"
    fi
  fi

  if [[ "$test_name" == "T427" ]]; then
    if [[ -n "${vlog_opts_with_mode}" ]]; then
      vlog_opts_with_mode+=" "
    fi
    vlog_opts_with_mode+="+define+SC_HUB_TB_AVALON_OUTSTANDING_LIMIT=1 +define+SC_HUB_TB_AVALON_OUTSTANDING_INT_RESERVED=0"
  fi

  if [[ "$test_name" == "T248" || "$test_name" == "T523" ]]; then
    if [[ -n "${vlog_opts_with_mode}" ]]; then
      vlog_opts_with_mode+=" "
    fi
    vlog_opts_with_mode+="+define+SC_HUB_TB_AVALON_OOO_ENABLED"
  fi

  if [[ "$test_name" == "T444" ]]; then
    if [[ -n "${vlog_opts_with_mode}" ]]; then
      vlog_opts_with_mode+=" "
    fi
    vlog_opts_with_mode+="+define+SC_HUB_TB_AVALON_OUTSTANDING_INT_RESERVED=0"
  fi

  if [[ "$test_name" == "T445" ]]; then
    if [[ -n "${vlog_opts_with_mode}" ]]; then
      vlog_opts_with_mode+=" "
    fi
    vlog_opts_with_mode+="+define+SC_HUB_TB_AVALON_OUTSTANDING_LIMIT=8 +define+SC_HUB_TB_AVALON_OUTSTANDING_INT_RESERVED=8"
  fi

  if [[ "$test_name" == "T446" || "$test_name" == "T447" ]]; then
    if [[ -n "${vlog_opts_with_mode}" ]]; then
      vlog_opts_with_mode+=" "
    fi
    vlog_opts_with_mode+="+define+SC_HUB_TB_AVALON_EXT_PLD_DEPTH=64"
  fi

  if [[ "$test_name" == "T205" ]]; then
    if [[ -n "${vlog_opts_with_mode}" ]]; then
      vlog_opts_with_mode+=" "
    fi
    vlog_opts_with_mode+="+define+SC_HUB_TB_AVALON_WR_TIMEOUT_CYCLES=5000"
  fi

  if [[ "$test_name" == "T540" || "$test_name" == "T541" ]]; then
    if [[ -n "${vlog_opts_with_mode}" ]]; then
      vlog_opts_with_mode+=" "
    fi
    vlog_opts_with_mode+="+define+SC_HUB_TB_AVALON_OUTSTANDING_INT_RESERVED=0"
  fi

  if [[ "$test_name" == "T542" ]]; then
    if [[ -n "${vlog_opts_with_mode}" ]]; then
      vlog_opts_with_mode+=" "
    fi
    vlog_opts_with_mode+="+define+SC_HUB_TB_AVALON_EXT_PLD_DEPTH=1"
  fi

  if [[ "$test_name" == "T543" ]]; then
    if [[ -n "${vlog_opts_with_mode}" ]]; then
      vlog_opts_with_mode+=" "
    fi
    vlog_opts_with_mode+="+define+SC_HUB_TB_AVALON_EXT_PLD_DEPTH=32"
  fi

  if [ -n "${vlog_opts_with_mode}" ]; then
    make_args+=("VLOG_OPTS=${vlog_opts_with_mode}")
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

  case "$test_name" in
    T123|T124|T125|T126|T127|T128|T3[0-4][0-9]|T350|T351|T352|T353|T354|T355)
      if "$SCRIPT_DIR/run_uvm_case.sh" "$test_name"; then
        pass_count=$((pass_count + 1))
        echo "[PASS] ${test_name}"
      else
        fail_count=$((fail_count + 1))
        echo "[FAIL] ${test_name}"
      fi
      return
      ;;
  esac

  if [[ "$test_name" == "T548" || "$test_name" == "T549" ]]; then
    if python3 "$SCRIPT_DIR/check_static_cases.py" "$test_name"; then
      pass_count=$((pass_count + 1))
      echo "[PASS] ${test_name}"
    else
      fail_count=$((fail_count + 1))
      echo "[FAIL] ${test_name}"
    fi
    return
  fi

  run_workspace="$(mktemp -d "${TMPDIR:-/tmp}/sc_hub_directed.${test_name}.XXXXXX")"
  modelsim_ini="${run_workspace}/modelsim.ini"
  work_lib="${run_workspace}/work_sc_hub_tb"
  log_file="${run_workspace}/run.log"
  make_args+=(
    "MODELSIM_INI=$modelsim_ini"
    "WORK=$work_lib"
  )

  if (cd "$TB_DIR" && make run_sim_smoke "${make_args[@]}" 2>&1 | tee "$log_file"); then
    if rg -q '(^# \*\* (Error|Fatal):|unknown TEST_NAME=)' "$log_file"; then
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
  rm -rf "$run_workspace"
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
