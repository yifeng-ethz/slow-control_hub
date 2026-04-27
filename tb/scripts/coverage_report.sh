#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TB_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$TB_DIR/.." && pwd)"
TRANSCRIPT_DIR="${TB_DIR}/sim_runs"
OUTPUT_DIR="${TB_DIR}/sim_runs/coverage"

mkdir -p "$OUTPUT_DIR"
source "${SCRIPT_DIR}/../../../scripts/questa_one_env.sh"

find_vcover() {
  local qh="${QUESTA_HOME-}"
  local cand
  for cand in "${VCOVER}" "${qh}/bin/vcover" "${qh}/linux_x86_64/vcover"
  do
    if [ -n "$cand" ] && [ -x "$cand" ]; then
      printf '%s
' "$cand"
      return 0
    fi
  done
  if command -v vcover >/dev/null 2>&1; then
    command -v vcover
    return 0
  fi
  return 1
}

rtl_srcfile_arg() {
  local files=()
  local joined=""
  local path
  for path in "$REPO_ROOT"/rtl/*.vhd; do
    [ -f "$path" ] || continue
    files+=("$(readlink -f "$path")")
  done
  if [ "${#files[@]}" -eq 0 ]; then
    echo "rtl_srcfile_arg: no RTL files found" >&2
    return 1
  fi
  joined=$(IFS=+; echo "${files[*]}")
  printf '%s
' "-srcfile=${joined}"
}

covg_srcfile_arg() {
  printf '%s
' "-srcfile=$(readlink -f "$TB_DIR/uvm/sc_hub_cov_collector.sv")"
}

collect_db() {
  local test_name="${1:-smoke_basic}"
  local db_name="${2:-${test_name}}"
  local ucdb_path="${OUTPUT_DIR}/${db_name}.ucdb"

  echo "=== collect ==="
  echo "No automatic compile/run collection step is performed by default."
  echo "To collect coverage data:"
  echo "  COV_ENABLE=1 UCDB_OUT=${ucdb_path} TEST_NAME=${test_name} make run_sim_smoke"
  echo "The generated ${ucdb_path} can then be used with this script report mode."
}

report_db() {
  local db_file="$1"
  local base_file="$(basename "$db_file")"
  local report_txt="${OUTPUT_DIR}/${base_file%.*}.txt"
  local vcover_bin
  local rtl_arg
  local cvg_arg

  if ! vcover_bin="$(find_vcover)"; then
    echo "vcover not available in this environment."
    echo "Set QUESTA_HOME or install Questa to generate coverage reports."
    return 1
  fi
  rtl_arg="$(rtl_srcfile_arg)"
  cvg_arg="$(covg_srcfile_arg)"

  {
    echo "=== DUT structural coverage (RTL only) ==="
    echo "Database: ${db_file}"
    "$vcover_bin" report -summary -code bcesft "$rtl_arg" "$db_file"
    echo
    echo "=== Functional coverage (collector) ==="
    tmp_cvg="$(mktemp)"
    if "$vcover_bin" report -summary -cvg "$cvg_arg" "$db_file" >"$tmp_cvg" 2>&1; then
      cat "$tmp_cvg"
      if grep -q "No matching coverage data found" "$tmp_cvg"; then
        "$vcover_bin" report -summary -cvg "$db_file"
      fi
    else
      cat "$tmp_cvg"
      "$vcover_bin" report -summary -cvg "$db_file"
    fi
    rm -f "$tmp_cvg"
  } > "$report_txt"
  echo "Report written to: $report_txt"
}

if [ "${1-}" = "--collect" ]; then
  shift
  TEST_NAME="${1:-smoke_basic}"
  DB_NAME="${2:-$TEST_NAME}"
  collect_db "$TEST_NAME" "$DB_NAME"
  exit 0
fi

if [ "$#" -gt 0 ] && [ -f "$1" ]; then
  report_db "$1"
  exit 0
fi

shopt -s nullglob
ucdb_files=( "$TRANSCRIPT_DIR"/*.ucdb "$OUTPUT_DIR"/*.ucdb )
if [ "${#ucdb_files[@]}" -eq 0 ]; then
  echo "No .ucdb coverage database found in: $TRANSCRIPT_DIR or $OUTPUT_DIR"
  echo "Use --collect to create one, then rerun coverage_report.sh <path_to_ucdb>."
  exit 1
fi

for db in "${ucdb_files[@]}"; do
  report_db "$db"
done
