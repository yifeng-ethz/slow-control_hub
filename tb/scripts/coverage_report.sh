#!/usr/bin/env bash
# ============================================================================
# coverage_report.sh — Coverage helper for sc_hub TB
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TB_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

TRANSCRIPT_DIR="${TB_DIR}/transcript"
OUTPUT_DIR="${TB_DIR}/transcript/coverage"

mkdir -p "$OUTPUT_DIR"

collect_db() {
  local test_name="${1:-smoke_basic}"
  local db_name="${2:-${test_name}}"
  local ucd_path="${OUTPUT_DIR}/${db_name}.ucd"

  echo "=== collect ==="
  echo "No automatic compile/run collection step is performed by default."
  echo "To collect coverage data:"
  echo "  make compile_sim VLOG_OPTS='-coverage' VCOM_OPTS='-coverage' VSIM_OPTS='-coverage' \\" 
  echo "    SIM_DO='coverage save -onexit ${ucd_path}; run -all; quit -f' TEST_NAME=${test_name} run_sim_smoke"
  echo "The generated ${ucd_path} can then be used with this script's --report mode."
}

report_db() {
  local db_file="$1"
  local base_file="$(basename "$db_file")"
  local report_txt="${OUTPUT_DIR}/${base_file%.ucd}.txt"

  if command -v vcover >/dev/null 2>&1; then
    echo "=== report ==="
    echo "Running vcover report on: ${db_file}"
    vcover report "$db_file" > "$report_txt"
    echo "Report written to: $report_txt"
  else
    echo "vcover not available in this environment."
    echo "Please install ModelSim's vcover utility to generate text/html reports."
  fi
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

ucd_files=( "$TRANSCRIPT_DIR"/*.ucd )
if [ "${#ucd_files[@]}" -eq 1 ] && [ ! -e "${ucd_files[0]}" ]; then
  echo "No .ucd coverage database found in: $TRANSCRIPT_DIR"
  echo "Use --collect to create one, then rerun coverage_report.sh <path_to_ucd>."
  exit 1
fi

for db in "${ucd_files[@]}"; do
  report_db "$db"
done
