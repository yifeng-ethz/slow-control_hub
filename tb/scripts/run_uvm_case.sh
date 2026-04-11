#!/usr/bin/env bash
# ============================================================================
# run_uvm_case.sh — Run DV-plan UVM case IDs through the scaffold
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TB_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

usage() {
  cat <<'EOF'
Usage:
  run_uvm_case.sh T123 [T124 ...]

Runs the UVM-mapped DV plan IDs through `sc_hub_case_test`.
EOF
}

if [ "${1-}" = "-h" ] || [ "${1-}" = "--help" ]; then
  usage
  exit 0
fi

if [ "$#" -eq 0 ]; then
  echo "run_uvm_case.sh: at least one Txxx case id is required" >&2
  exit 2
fi

pass_count=0
fail_count=0
run_count=0
current_case_rc=0
cov_subrun_index=0

rewrite_plusarg() {
  local opts="$1"
  local key="$2"
  local value="$3"

  if [ -z "$value" ]; then
    printf '%s' "$opts"
    return 0
  fi

  if printf '%s' "$opts" | rg -q "(^| )\+${key}="; then
    printf '%s' "$(printf '%s' "$opts" | perl -0pe "s@(?<!\S)\+${key}=[^\s]+@+${key}=${value}@g")"
  else
    printf '%s' "$opts +${key}=${value}"
  fi
}

apply_runtime_overrides() {
  local opts="$1"
  local key
  local env_name
  local value

  for key in \
    SC_HUB_TXN_COUNT \
    SC_HUB_RATE_POINTS \
    SC_HUB_MAX_GAP \
    SC_HUB_FIXED_LEN \
    SC_HUB_BURST_MIN \
    SC_HUB_BURST_MAX \
    SC_HUB_READ_PCT \
    SC_HUB_INTERNAL_PCT \
    SC_HUB_ORDERING_PCT \
    SC_HUB_ATOMIC_PCT \
    SC_HUB_NONINCREMENT_PCT \
    SC_HUB_ORDER_DOMAINS \
    SC_HUB_CFG_ENABLE_OOO \
    SC_HUB_FORCE_OOO \
    SC_HUB_CHECK_ORDER_EPOCH_MONO \
    SC_HUB_RD_LATENCY \
    SC_HUB_WR_LATENCY \
    TIMEOUT_CYCLES; do
    env_name="${key}_OVERRIDE"
    value="${!env_name-}"
    if [ -n "$value" ]; then
      opts="$(rewrite_plusarg "$opts" "$key" "$value")"
    fi
  done

  if [ -n "${SC_HUB_OVERRIDE_PLUSARGS-}" ]; then
    opts+=" ${SC_HUB_OVERRIDE_PLUSARGS}"
  fi
  printf '%s' "$opts"
}

coverage_ucdb_path() {
  local case_id="$1"
  local bus="$2"
  local profile="$3"
  local desc="$4"
  local subrun_idx="$5"
  local cov_dir="${COV_DIR:-${TB_DIR}/transcript/coverage}"
  local run_tag="${RUN_TAG-}"
  local stem
  local desc_tag

  mkdir -p "$cov_dir"
  desc_tag="$(printf '%s' "$desc" | tr ':/ +' '____' | tr -cd '[:alnum:]_.-')"
  stem="${case_id}_${bus}_${profile}_${desc_tag}_s${subrun_idx}"
  stem="$(printf '%s' "$stem" | tr ':/ +' '____' | tr -cd '[:alnum:]_.-')"
  if [ -n "$run_tag" ]; then
    stem+="_$(printf '%s' "$run_tag" | tr ':/ +' '____' | tr -cd '[:alnum:]_.-')"
  fi
  printf '%s/%s.ucdb' "$cov_dir" "$stem"
}

run_uvm_subrun() {
  local bus="$1"
  local desc="$2"
  local vlog_opts="$3"
  local vsim_opts="$4"
  local ucdb_out=""

  printf '    subrun: %s (%s)\n' "$desc" "$bus"
  cov_subrun_index=$((cov_subrun_index + 1))
  if [ "${COV_ENABLE:-0}" = "1" ]; then
    ucdb_out="$(coverage_ucdb_path "${CURRENT_CASE_ID:-case}" "$bus" "${CURRENT_PROFILE:-${desc}}" "$desc" "$cov_subrun_index")"
  fi
  if (
    cd "$TB_DIR"
    BUS_TYPE="$bus" \
    VLOG_OPTS="$vlog_opts" \
    VSIM_OPTS="$vsim_opts" \
    COV_ENABLE="${COV_ENABLE:-0}" \
    UCDB_OUT="$ucdb_out" \
    "$SCRIPT_DIR/run_uvm.sh" sc_hub_case_test
  ); then
    return 0
  fi

  current_case_rc=1
  return 0
}

run_case_once() {
  local case_id="$1"
  local bus="$2"
  local profile="$3"
  local vlog_opts="${4-}"
  local extra_vsim="${5-}"
  local timeout_cycles="${6-120000}"
  local vsim_opts="+SC_HUB_CASE_ID=${case_id} +SC_HUB_PROFILE=${profile} +TIMEOUT_CYCLES=${timeout_cycles}"

  if [ -n "$extra_vsim" ]; then
    vsim_opts+=" ${extra_vsim}"
  fi
  vsim_opts="$(apply_runtime_overrides "$vsim_opts")"
  CURRENT_CASE_ID="$case_id"
  CURRENT_PROFILE="$profile"
  run_uvm_subrun "$bus" "${case_id}:${profile}" "$vlog_opts" "$vsim_opts"
}

run_case_both() {
  local case_id="$1"
  local profile="$2"
  local vlog_opts="${3-}"
  local extra_vsim="${4-}"
  local timeout_cycles="${5-120000}"

  run_case_once "$case_id" "AVALON" "$profile" "$vlog_opts" "$extra_vsim" "$timeout_cycles"
  run_case_once "$case_id" "AXI4"   "$profile" "$vlog_opts" "$extra_vsim" "$timeout_cycles"
}

run_perf_stream_case() {
  local case_id="$1"
  local bus="$2"
  local lat_profile="$3"
  local extra_vlog="${4-}"
  local extra_vsim="${5-}"
  local timeout_cycles="${6-180000}"
  local vsim_opts="+SC_HUB_CASE_ID=${case_id} +SC_HUB_PROFILE=perf_stream +SC_HUB_LAT_PROFILE=${lat_profile} +TIMEOUT_CYCLES=${timeout_cycles}"

  if [ -n "$extra_vsim" ]; then
    vsim_opts+=" ${extra_vsim}"
  fi
  vsim_opts="$(apply_runtime_overrides "$vsim_opts")"
  CURRENT_CASE_ID="$case_id"
  CURRENT_PROFILE=perf_stream
  run_uvm_subrun "$bus" "${case_id}:perf_stream" "$extra_vlog" "$vsim_opts"
}

run_speedup_pair() {
  local case_id="$1"
  local lat_profile="$2"
  local common_vsim="$3"
  local timeout_cycles="${4-180000}"

  run_perf_stream_case "$case_id" "AXI4" "$lat_profile" "+define+SC_HUB_TB_AXI4_OOO_DISABLED" \
    "${common_vsim} +SC_HUB_CFG_ENABLE_OOO=0" "$timeout_cycles"
  run_perf_stream_case "$case_id" "AXI4" "$lat_profile" "" \
    "${common_vsim} +SC_HUB_FORCE_OOO=1 +SC_HUB_CFG_ENABLE_OOO=1" "$timeout_cycles"
}

run_one() {
  local case_id="$1"

  run_count=$((run_count + 1))
  current_case_rc=0
  printf '%s\n' "----------------------------------------------------------------"
  printf '[%d] run_uvm_case %s\n' "$run_count" "$case_id"

  case "$case_id" in
    T123)
      run_case_both "$case_id" "burst_len_sweep" "" "" 180000
      ;;
    T124)
      run_case_both "$case_id" "addr_boundary_sweep" "" "" 120000
      ;;
    T125)
      local bus lat
      for bus in AVALON AXI4; do
        for lat in 1 2 4 8 16 32 64 100 199; do
          run_case_once "$case_id" "$bus" "latency_pair" "" \
            "+SC_HUB_RD_LATENCY=${lat} +SC_HUB_WR_LATENCY=${lat}" 180000
        done
      done
      ;;
    T126)
      local bus
      for bus in AVALON AXI4; do
        run_case_once "$case_id" "$bus" "error_case" "" "+SC_HUB_ERR_KIND=OKAY +SC_HUB_ERR_OP=read" 120000
        run_case_once "$case_id" "$bus" "error_case" "" "+SC_HUB_ERR_KIND=SLVERR +SC_HUB_ERR_OP=read +SC_HUB_INJECT_RD_ERROR" 120000
        run_case_once "$case_id" "$bus" "error_case" "" "+SC_HUB_ERR_KIND=DECERR +SC_HUB_ERR_OP=read +SC_HUB_INJECT_DECODE_ERROR" 120000
        run_case_once "$case_id" "$bus" "error_case" "" "+SC_HUB_ERR_KIND=OKAY +SC_HUB_ERR_OP=write" 120000
        run_case_once "$case_id" "$bus" "error_case" "" "+SC_HUB_ERR_KIND=SLVERR +SC_HUB_ERR_OP=write +SC_HUB_INJECT_WR_ERROR" 120000
        run_case_once "$case_id" "$bus" "error_case" "" "+SC_HUB_ERR_KIND=DECERR +SC_HUB_ERR_OP=write +SC_HUB_INJECT_DECODE_ERROR" 120000
        run_case_once "$case_id" "$bus" "error_case" "" "+SC_HUB_ERR_KIND=TIMEOUT +SC_HUB_ERR_OP=read +SC_HUB_RD_LATENCY=512" 220000
      done
      ;;
    T127)
      run_case_once "$case_id" "AVALON" "gap_sweep" "" "" 240000
      ;;
    T128)
      run_case_both "$case_id" "perf_stream" "" \
        "+SC_HUB_TXN_COUNT=100 +SC_HUB_RATE_POINTS=1 +SC_HUB_BURST_MIN=1 +SC_HUB_BURST_MAX=16 +SC_HUB_READ_PCT=50 +SC_HUB_INTERNAL_PCT=0 +SC_HUB_MALFORMED_EVERY=10" 180000
      ;;

    T300)
      run_perf_stream_case "$case_id" "AVALON" "FIXED8" \
        "+define+SC_HUB_TB_AVALON_OUTSTANDING_LIMIT=1 +define+SC_HUB_TB_AVALON_OUTSTANDING_INT_RESERVED=0" \
        "+SC_HUB_TXN_COUNT=20 +SC_HUB_RATE_POINTS=10 +SC_HUB_FIXED_LEN=1 +SC_HUB_READ_PCT=100 +SC_HUB_MAX_GAP=9" 200000
      ;;
    T301|T302|T303|T304|T305)
      local od
      case "$case_id" in
        T301) od=1 ;;
        T302) od=2 ;;
        T303) od=4 ;;
        T304) od=8 ;;
        *)    od=16 ;;
      esac
      run_perf_stream_case "$case_id" "AVALON" "FIXED8" \
        "+define+SC_HUB_TB_AVALON_OUTSTANDING_LIMIT=${od} +define+SC_HUB_TB_AVALON_OUTSTANDING_INT_RESERVED=0" \
        "+SC_HUB_TXN_COUNT=24 +SC_HUB_RATE_POINTS=10 +SC_HUB_BURST_MIN=1 +SC_HUB_BURST_MAX=64 +SC_HUB_READ_PCT=50 +SC_HUB_MAX_GAP=9" 220000
      ;;
    T306)
      run_perf_stream_case "$case_id" "AVALON" "UNIFORM4_50" \
        "" "+SC_HUB_TXN_COUNT=20 +SC_HUB_RATE_POINTS=10 +SC_HUB_FIXED_LEN=1 +SC_HUB_READ_PCT=100 +SC_HUB_MAX_GAP=9" 220000
      ;;
    T307)
      run_perf_stream_case "$case_id" "AXI4" "UNIFORM4_50" \
        "" "+SC_HUB_TXN_COUNT=20 +SC_HUB_RATE_POINTS=10 +SC_HUB_FIXED_LEN=1 +SC_HUB_READ_PCT=100 +SC_HUB_MAX_GAP=9 +SC_HUB_FORCE_OOO=1 +SC_HUB_CFG_ENABLE_OOO=1" 220000
      ;;
    T308)
      run_perf_stream_case "$case_id" "AVALON" "BIMODAL4_40" \
        "" "+SC_HUB_TXN_COUNT=20 +SC_HUB_RATE_POINTS=10 +SC_HUB_FIXED_LEN=1 +SC_HUB_READ_PCT=100 +SC_HUB_MAX_GAP=9" 220000
      ;;
    T309)
      run_perf_stream_case "$case_id" "AXI4" "BIMODAL4_40" \
        "" "+SC_HUB_TXN_COUNT=20 +SC_HUB_RATE_POINTS=10 +SC_HUB_FIXED_LEN=1 +SC_HUB_READ_PCT=100 +SC_HUB_MAX_GAP=9 +SC_HUB_FORCE_OOO=1 +SC_HUB_CFG_ENABLE_OOO=1" 220000
      ;;
    T310)
      run_perf_stream_case "$case_id" "AVALON" "READ8_WRITE4" \
        "" "+SC_HUB_TXN_COUNT=24 +SC_HUB_RATE_POINTS=10 +SC_HUB_BURST_MIN=1 +SC_HUB_BURST_MAX=32 +SC_HUB_READ_PCT=50 +SC_HUB_MAX_GAP=9" 220000
      ;;
    T311)
      run_perf_stream_case "$case_id" "AVALON" "ADDRESSDEP" \
        "" "+SC_HUB_TXN_COUNT=24 +SC_HUB_RATE_POINTS=10 +SC_HUB_BURST_MIN=1 +SC_HUB_BURST_MAX=16 +SC_HUB_READ_PCT=50 +SC_HUB_MAX_GAP=9 +SC_HUB_ADDR_MODE=feb" 220000
      ;;
    T312)
      run_perf_stream_case "$case_id" "AVALON" "FIXED1" \
        "" "+SC_HUB_TXN_COUNT=1000 +SC_HUB_RATE_POINTS=1 +SC_HUB_FIXED_LEN=1 +SC_HUB_READ_PCT=100 +SC_HUB_MAX_GAP=0" 260000
      ;;

    T313)
      run_speedup_pair "$case_id" "FIXED8" "+SC_HUB_TXN_COUNT=300 +SC_HUB_RATE_POINTS=1 +SC_HUB_FIXED_LEN=1 +SC_HUB_READ_PCT=100 +SC_HUB_MAX_GAP=0"
      ;;
    T314)
      run_speedup_pair "$case_id" "UNIFORM4_50" "+SC_HUB_TXN_COUNT=300 +SC_HUB_RATE_POINTS=1 +SC_HUB_FIXED_LEN=1 +SC_HUB_READ_PCT=100 +SC_HUB_MAX_GAP=0"
      ;;
    T315)
      run_speedup_pair "$case_id" "UNIFORM4_200" "+SC_HUB_TXN_COUNT=300 +SC_HUB_RATE_POINTS=1 +SC_HUB_FIXED_LEN=1 +SC_HUB_READ_PCT=100 +SC_HUB_MAX_GAP=0" 260000
      ;;
    T316)
      run_speedup_pair "$case_id" "UNIFORM4_50" "+SC_HUB_TXN_COUNT=300 +SC_HUB_RATE_POINTS=1 +SC_HUB_FIXED_LEN=1 +SC_HUB_READ_PCT=50 +SC_HUB_INTERNAL_PCT=50 +SC_HUB_MAX_GAP=0"
      ;;
    T317)
      run_speedup_pair "$case_id" "UNIFORM4_50" "+SC_HUB_TXN_COUNT=300 +SC_HUB_RATE_POINTS=1 +SC_HUB_BURST_MIN=1 +SC_HUB_BURST_MAX=32 +SC_HUB_READ_PCT=50 +SC_HUB_MAX_GAP=0"
      ;;
    T318)
      run_speedup_pair "$case_id" "UNIFORM4_50" "+SC_HUB_TXN_COUNT=300 +SC_HUB_RATE_POINTS=1 +SC_HUB_BURST_MIN=1 +SC_HUB_BURST_MAX=32 +SC_HUB_READ_PCT=90 +SC_HUB_ATOMIC_PCT=10 +SC_HUB_MAX_GAP=0"
      ;;
    T319)
      run_speedup_pair "$case_id" "UNIFORM4_50" "+SC_HUB_TXN_COUNT=400 +SC_HUB_RATE_POINTS=1 +SC_HUB_FIXED_LEN=1 +SC_HUB_READ_PCT=100 +SC_HUB_MAX_GAP=0"
      ;;

    T320)
      run_perf_stream_case "$case_id" "AVALON" "UNIFORM4_20" "" \
        "+SC_HUB_TXN_COUNT=512 +SC_HUB_BURST_MIN=1 +SC_HUB_BURST_MAX=256 +SC_HUB_READ_PCT=50" 260000
      ;;
    T321)
      run_perf_stream_case "$case_id" "AVALON" "UNIFORM4_20" "" \
        "+SC_HUB_TXN_COUNT=512 +SC_HUB_BURST_MIN=1 +SC_HUB_BURST_MAX=256 +SC_HUB_FIXED_LEN=0 +SC_HUB_READ_PCT=50" 260000
      ;;
    T322)
      run_perf_stream_case "$case_id" "AVALON" "UNIFORM4_20" "" \
        "+SC_HUB_TXN_COUNT=512 +SC_HUB_BURST_MIN=1 +SC_HUB_BURST_MAX=4 +SC_HUB_READ_PCT=50" 220000
      ;;
    T323)
      run_perf_stream_case "$case_id" "AVALON" "UNIFORM4_20" "" \
        "+SC_HUB_TXN_COUNT=256 +SC_HUB_BURST_MIN=128 +SC_HUB_BURST_MAX=256 +SC_HUB_READ_PCT=50" 260000
      ;;
    T324|T325)
      local burst_min burst_max
      if [ "$case_id" = "T324" ]; then
        burst_min=1; burst_max=256
      else
        burst_min=1; burst_max=256
      fi
      run_perf_stream_case "$case_id" "AXI4" "UNIFORM4_20" "" \
        "+SC_HUB_TXN_COUNT=512 +SC_HUB_BURST_MIN=${burst_min} +SC_HUB_BURST_MAX=${burst_max} +SC_HUB_READ_PCT=50 +SC_HUB_FORCE_OOO=1 +SC_HUB_CFG_ENABLE_OOO=1" 260000
      ;;
    T326)
      run_perf_stream_case "$case_id" "AVALON" "UNIFORM4_20" "" \
        "+SC_HUB_TXN_COUNT=512 +SC_HUB_BURST_MIN=1 +SC_HUB_BURST_MAX=256 +SC_HUB_READ_PCT=50" 260000
      ;;
    T327)
      run_perf_stream_case "$case_id" "AVALON" "UNIFORM4_20" "" \
        "+SC_HUB_TXN_COUNT=4000 +SC_HUB_BURST_MIN=1 +SC_HUB_BURST_MAX=256 +SC_HUB_READ_PCT=50" 1200000
      ;;

    T328)
      run_perf_stream_case "$case_id" "AVALON" "FIXED8" "" \
        "+SC_HUB_TXN_COUNT=128 +SC_HUB_FIXED_LEN=64 +SC_HUB_READ_PCT=100" 220000
      ;;
    T329)
      run_perf_stream_case "$case_id" "AVALON" "FIXED8" \
        "+define+SC_HUB_TB_AVALON_EXT_PLD_DEPTH=128" \
        "+SC_HUB_TXN_COUNT=128 +SC_HUB_FIXED_LEN=64 +SC_HUB_READ_PCT=100" 220000
      ;;
    T330)
      run_perf_stream_case "$case_id" "AVALON" "FIXED8" "" \
        "+SC_HUB_TXN_COUNT=64 +SC_HUB_FIXED_LEN=256 +SC_HUB_READ_PCT=100" 220000
      ;;
    T331)
      run_perf_stream_case "$case_id" "AVALON" "FIXED8" "" \
        "+SC_HUB_TXN_COUNT=128 +SC_HUB_FIXED_LEN=16 +SC_HUB_READ_PCT=50" 220000
      ;;
    T332)
      run_perf_stream_case "$case_id" "AVALON" "FIXED8" "" \
        "+SC_HUB_TXN_COUNT=128 +SC_HUB_FIXED_LEN=16 +SC_HUB_READ_PCT=100" 220000
      ;;
    T333)
      run_perf_stream_case "$case_id" "AVALON" "FIXED8" "" \
        "+SC_HUB_TXN_COUNT=128 +SC_HUB_FIXED_LEN=16 +SC_HUB_READ_PCT=90 +SC_HUB_INTERNAL_PCT=10" 220000
      ;;
    T334)
      run_perf_stream_case "$case_id" "AVALON" "FIXED8" "" \
        "+SC_HUB_TXN_COUNT=128 +SC_HUB_FIXED_LEN=16 +SC_HUB_READ_PCT=85 +SC_HUB_INTERNAL_PCT=15" 220000
      ;;
    T335)
      run_perf_stream_case "$case_id" "AVALON" "FIXED8" "" \
        "+SC_HUB_TXN_COUNT=128 +SC_HUB_FIXED_LEN=16 +SC_HUB_READ_PCT=50 +SC_HUB_INTERNAL_PCT=10 +SC_HUB_ATOMIC_PCT=50" 220000
      ;;

    T336)
      run_perf_stream_case "$case_id" "AVALON" "FIXED8" "" \
        "+SC_HUB_TXN_COUNT=256 +SC_HUB_FIXED_LEN=1 +SC_HUB_READ_PCT=0 +SC_HUB_ORDERING_PCT=5 +SC_HUB_ORDER_DOMAINS=1 +SC_HUB_CHECK_ORDER_EPOCH_MONO=0" 220000
      ;;
    T337)
      run_perf_stream_case "$case_id" "AVALON" "FIXED8" "" \
        "+SC_HUB_TXN_COUNT=128 +SC_HUB_FIXED_LEN=64 +SC_HUB_READ_PCT=0 +SC_HUB_ORDERING_PCT=5 +SC_HUB_ORDER_DOMAINS=1 +SC_HUB_CHECK_ORDER_EPOCH_MONO=0" 220000
      ;;
    T338)
      run_perf_stream_case "$case_id" "AVALON" "FIXED8" "" \
        "+SC_HUB_TXN_COUNT=256 +SC_HUB_FIXED_LEN=1 +SC_HUB_READ_PCT=100 +SC_HUB_ORDERING_PCT=5 +SC_HUB_ORDER_DOMAINS=1 +SC_HUB_CHECK_ORDER_EPOCH_MONO=0" 220000
      ;;
    T339)
      run_perf_stream_case "$case_id" "AVALON" "FIXED8" "" \
        "+SC_HUB_TXN_COUNT=256 +SC_HUB_BURST_MIN=1 +SC_HUB_BURST_MAX=4 +SC_HUB_READ_PCT=50 +SC_HUB_ORDERING_PCT=4 +SC_HUB_ORDER_DOMAINS=1 +SC_HUB_CHECK_ORDER_EPOCH_MONO=0" 220000
      ;;
    T340)
      run_perf_stream_case "$case_id" "AVALON" "FIXED8" "" \
        "+SC_HUB_TXN_COUNT=256 +SC_HUB_FIXED_LEN=1 +SC_HUB_READ_PCT=100 +SC_HUB_ORDERING_PCT=10 +SC_HUB_ORDER_DOMAINS=2 +SC_HUB_CHECK_ORDER_EPOCH_MONO=0" 220000
      ;;
    T341)
      run_perf_stream_case "$case_id" "AXI4" "UNIFORM4_50" "" \
        "+SC_HUB_TXN_COUNT=256 +SC_HUB_BURST_MIN=1 +SC_HUB_BURST_MAX=16 +SC_HUB_READ_PCT=50 +SC_HUB_ORDERING_PCT=10 +SC_HUB_ORDER_DOMAINS=4 +SC_HUB_FORCE_OOO=1 +SC_HUB_CFG_ENABLE_OOO=1 +SC_HUB_CHECK_ORDER_EPOCH_MONO=0" 240000
      ;;
    T342)
      run_perf_stream_case "$case_id" "AVALON" "FIXED8" "" \
        "+SC_HUB_TXN_COUNT=256 +SC_HUB_FIXED_LEN=1 +SC_HUB_READ_PCT=0 +SC_HUB_ORDERING_PCT=50 +SC_HUB_ORDER_DOMAINS=1 +SC_HUB_CHECK_ORDER_EPOCH_MONO=0" 220000
      ;;
    T343)
      run_perf_stream_case "$case_id" "AVALON" "FIXED8" "" \
        "+SC_HUB_TXN_COUNT=256 +SC_HUB_BURST_MIN=1 +SC_HUB_BURST_MAX=16 +SC_HUB_READ_PCT=50 +SC_HUB_ORDERING_PCT=5 +SC_HUB_ATOMIC_PCT=2 +SC_HUB_ORDER_DOMAINS=1 +SC_HUB_CHECK_ORDER_EPOCH_MONO=0" 240000
      ;;

    T344)
      local od
      for od in 1 2 4 8 12 16 24 32; do
        run_perf_stream_case "$case_id" "AVALON" "UNIFORM4_20" \
          "+define+SC_HUB_TB_AVALON_OUTSTANDING_LIMIT=${od} +define+SC_HUB_TB_AVALON_OUTSTANDING_INT_RESERVED=0" \
          "+SC_HUB_TXN_COUNT=192 +SC_HUB_BURST_MIN=1 +SC_HUB_BURST_MAX=64 +SC_HUB_READ_PCT=50" 220000
      done
      ;;
    T345)
      local depth
      for depth in 64 128 256 512 1024; do
        run_perf_stream_case "$case_id" "AVALON" "UNIFORM4_20" \
          "+define+SC_HUB_TB_AVALON_EXT_PLD_DEPTH=${depth}" \
          "+SC_HUB_TXN_COUNT=192 +SC_HUB_BURST_MIN=1 +SC_HUB_BURST_MAX=64 +SC_HUB_READ_PCT=50" 220000
      done
      ;;
    T346)
      for _ in 1 2 3 4; do
        run_perf_stream_case "$case_id" "AVALON" "UNIFORM4_20" "" \
          "+SC_HUB_TXN_COUNT=128 +SC_HUB_BURST_MIN=1 +SC_HUB_BURST_MAX=8 +SC_HUB_READ_PCT=80 +SC_HUB_INTERNAL_PCT=20" 220000
      done
      ;;
    T347)
      local od depth
      for od in 4 8 16; do
        for depth in 256 512 1024; do
          run_perf_stream_case "$case_id" "AVALON" "UNIFORM4_20" \
            "+define+SC_HUB_TB_AVALON_OUTSTANDING_LIMIT=${od} +define+SC_HUB_TB_AVALON_OUTSTANDING_INT_RESERVED=0 +define+SC_HUB_TB_AVALON_EXT_PLD_DEPTH=${depth}" \
            "+SC_HUB_TXN_COUNT=192 +SC_HUB_BURST_MIN=1 +SC_HUB_BURST_MAX=64 +SC_HUB_READ_PCT=50" 220000
        done
      done
      ;;
    T348)
      run_perf_stream_case "$case_id" "AVALON" "ADDRESSDEP" "" \
        "+SC_HUB_TXN_COUNT=256 +SC_HUB_BURST_MIN=1 +SC_HUB_BURST_MAX=16 +SC_HUB_READ_PCT=50 +SC_HUB_ADDR_MODE=feb" 240000
      ;;
    T349)
      run_perf_stream_case "$case_id" "AVALON" "UNIFORM4_20" "" \
        "+SC_HUB_TXN_COUNT=64 +SC_HUB_FIXED_LEN=256 +SC_HUB_READ_PCT=100" 240000
      ;;

    T350)
      local od
      for od in 1 2 4 8 16; do
        run_perf_stream_case "$case_id" "AVALON" "FIXED8" \
          "+define+SC_HUB_TB_AVALON_OUTSTANDING_LIMIT=${od} +define+SC_HUB_TB_AVALON_OUTSTANDING_INT_RESERVED=0" \
          "+SC_HUB_TXN_COUNT=24 +SC_HUB_RATE_POINTS=10 +SC_HUB_BURST_MIN=1 +SC_HUB_BURST_MAX=64 +SC_HUB_READ_PCT=50 +SC_HUB_MAX_GAP=9" 220000
      done
      ;;
    T351)
      local profile onoff_vlog onoff_vsim
      for profile in FIXED8 UNIFORM4_50 BIMODAL4_40 ADDRESSDEP; do
        run_perf_stream_case "$case_id" "AXI4" "$profile" "+define+SC_HUB_TB_AXI4_OOO_DISABLED" \
          "+SC_HUB_TXN_COUNT=128 +SC_HUB_FIXED_LEN=1 +SC_HUB_READ_PCT=100 +SC_HUB_CFG_ENABLE_OOO=0" 220000
        run_perf_stream_case "$case_id" "AXI4" "$profile" "" \
          "+SC_HUB_TXN_COUNT=128 +SC_HUB_FIXED_LEN=1 +SC_HUB_READ_PCT=100 +SC_HUB_FORCE_OOO=1 +SC_HUB_CFG_ENABLE_OOO=1" 220000
      done
      ;;
    T352)
      local blen
      for blen in 1 4 16 64 128 256; do
        run_perf_stream_case "$case_id" "AVALON" "UNIFORM4_20" "" \
          "+SC_HUB_TXN_COUNT=512 +SC_HUB_FIXED_LEN=${blen} +SC_HUB_READ_PCT=50" 260000
      done
      ;;
    T353)
      local depth od
      for depth in 128 256 512; do
        for od in 4 8 16; do
          run_perf_stream_case "$case_id" "AVALON" "FIXED8" \
            "+define+SC_HUB_TB_AVALON_EXT_PLD_DEPTH=${depth} +define+SC_HUB_TB_AVALON_OUTSTANDING_LIMIT=${od} +define+SC_HUB_TB_AVALON_OUTSTANDING_INT_RESERVED=0" \
            "+SC_HUB_TXN_COUNT=128 +SC_HUB_FIXED_LEN=64 +SC_HUB_READ_PCT=100" 220000
        done
      done
      ;;
    T354)
      local ratio
      for ratio in 0 1 2 5 10 25 50; do
        run_perf_stream_case "$case_id" "AVALON" "FIXED8" "" \
          "+SC_HUB_TXN_COUNT=192 +SC_HUB_FIXED_LEN=4 +SC_HUB_READ_PCT=50 +SC_HUB_ORDERING_PCT=${ratio} +SC_HUB_ORDER_DOMAINS=1 +SC_HUB_CHECK_ORDER_EPOCH_MONO=0" 220000
      done
      ;;
    T355)
      local ratio
      for ratio in 0 1 5 10 25 50; do
        run_perf_stream_case "$case_id" "AVALON" "UNIFORM4_20" "" \
          "+SC_HUB_TXN_COUNT=192 +SC_HUB_BURST_MIN=1 +SC_HUB_BURST_MAX=16 +SC_HUB_READ_PCT=100 +SC_HUB_ATOMIC_PCT=${ratio}" 220000
      done
      ;;

    T356)
      run_perf_stream_case "$case_id" "AVALON" "UNIFORM4_20" ""         "+SC_HUB_TXN_COUNT=768 +SC_HUB_BURST_MIN=1 +SC_HUB_BURST_MAX=16 +SC_HUB_READ_PCT=50 +SC_HUB_NONINCREMENT_PCT=35 +SC_HUB_INTERNAL_PCT=10" 320000
      ;;
    T357)
      run_perf_stream_case "$case_id" "AXI4" "UNIFORM4_50" ""         "+SC_HUB_TXN_COUNT=768 +SC_HUB_BURST_MIN=1 +SC_HUB_BURST_MAX=16 +SC_HUB_READ_PCT=50 +SC_HUB_NONINCREMENT_PCT=35 +SC_HUB_ORDERING_PCT=10 +SC_HUB_ATOMIC_PCT=5 +SC_HUB_ORDER_DOMAINS=4 +SC_HUB_FORCE_OOO=1 +SC_HUB_CFG_ENABLE_OOO=1 +SC_HUB_CHECK_ORDER_EPOCH_MONO=0" 360000
      ;;
    *)
      echo "run_uvm_case.sh: unsupported case id ${case_id}" >&2
      current_case_rc=2
      ;;
  esac
  if [ "$current_case_rc" -eq 0 ]; then
    pass_count=$((pass_count + 1))
    echo "[PASS] ${case_id}"
  else
    fail_count=$((fail_count + 1))
    echo "[FAIL] ${case_id}"
  fi
}

for case_id in "$@"; do
  run_one "$case_id"
done

printf '%s\n' "----------------------------------------------------------------"
echo "UVM case run summary: pass=$pass_count fail=$fail_count total=$run_count"
if [ "$fail_count" -ne 0 ]; then
  exit 1
fi
