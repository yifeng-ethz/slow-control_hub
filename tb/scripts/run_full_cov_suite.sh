#!/usr/bin/env bash
# Run every registered case in run_uvm_case.sh with COV_ENABLE=1, merge
# the resulting per-run UCDBs into one suite UCDB, and report totals.
#
# Usage:
#   scripts/run_full_cov_suite.sh [out_dir]
#
# Environment:
#   SKIP_CASES   space-separated list of case IDs to skip
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TB_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
OUT_ROOT="${1:-${TB_DIR}/sim_runs/cov_full_suite}"
LOG_DIR="${OUT_ROOT}/logs"
COV_DIR="${OUT_ROOT}/ucdb"
SUMMARY_CSV="${OUT_ROOT}/summary.csv"
MERGED_UCDB="${OUT_ROOT}/merged.ucdb"
REPORT_TXT="${OUT_ROOT}/merged_report.txt"

source "${SCRIPT_DIR}/../../../scripts/questa_one_env.sh"

mkdir -p "$LOG_DIR" "$COV_DIR"
cd "$TB_DIR"

skip_set=" ${SKIP_CASES:-} "

mapfile -t CASE_IDS < <(grep -oE "^[[:space:]]+T[0-9]{3}\)" scripts/run_uvm_case.sh \
  | sed 's/)//' | awk '{print $1}' | sort -u)

echo "case,status,elapsed_s" > "$SUMMARY_CSV"
pass=0
fail=0
skip=0

for case_id in "${CASE_IDS[@]}"; do
  if [[ "$skip_set" == *" $case_id "* ]]; then
    echo "[SKIP] $case_id"
    echo "${case_id},skipped,0" >> "$SUMMARY_CSV"
    skip=$((skip+1))
    continue
  fi
  log_file="${LOG_DIR}/${case_id}.log"
  start=$(date +%s)
  echo "=== ${case_id} ==="
  if COV_ENABLE=1 COV_DIR="$COV_DIR" ./scripts/run_uvm_case.sh "$case_id" >"$log_file" 2>&1; then
    status=pass; pass=$((pass+1))
  else
    status=fail; fail=$((fail+1))
    echo "[FAIL] $case_id -- see $log_file"
  fi
  end=$(date +%s)
  echo "${case_id},${status},$((end-start))" >> "$SUMMARY_CSV"
done

echo "=== merge UCDBs ==="
shopt -s nullglob
ucdb_files=("$COV_DIR"/*.ucdb)
if [ "${#ucdb_files[@]}" -eq 0 ]; then
  echo "no UCDBs found in $COV_DIR" >&2
  exit 1
fi
"$QUESTA_HOME/bin/vcover" merge -out "$MERGED_UCDB" "${ucdb_files[@]}" \
  > "${OUT_ROOT}/merge.log" 2>&1

echo "=== report ==="
"$QUESTA_HOME/bin/vcover" report -summary "$MERGED_UCDB" > "$REPORT_TXT" 2>&1
cat "$REPORT_TXT"

echo
echo "suite summary: pass=$pass fail=$fail skip=$skip"
echo "merged UCDB: $MERGED_UCDB"
echo "report:      $REPORT_TXT"
