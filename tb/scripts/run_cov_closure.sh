#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TB_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
OUT_ROOT="${COV_CLOSURE_DIR:-${TB_DIR}/sim_runs/coverage_closure}"
TREND_DIR="${OUT_ROOT}/trends"
SUITE_DIR="${OUT_ROOT}/suite"
POINTS_CORE="${POINTS_CORE:-64,128,256}"
POINTS_LONG="${POINTS_LONG:-64,128,256,512}"
CASE_SCRIPT="${CASE_SCRIPT:-./scripts/run_uvm_cov_trend.py}"
MERGE_SCRIPT="${MERGE_SCRIPT:-./scripts/merge_cov_suite.py}"
EXTRA_PLUSARGS="${EXTRA_PLUSARGS:-}"

read -r -a CORE_CASES <<< "${CORE_CASES:-T341 T356 T357}"
read -r -a EXT_CASES <<< "${EXT_CASES:-T358 T359 T360 T361 T362 T363 T364 T365 T366 T367 T368}"

mkdir -p "$TREND_DIR" "$SUITE_DIR"
cd "$TB_DIR"

trend_csvs=()
run_case() {
  local case_id="$1"
  local points="$2"
  local outdir="${TREND_DIR}/${case_id}"
  local cmd=(python3 "$CASE_SCRIPT" "$case_id" --points "$points" --outdir "$outdir")
  if [ -n "$EXTRA_PLUSARGS" ]; then
    cmd+=(--extra-plusargs "$EXTRA_PLUSARGS")
  fi
  echo "=== coverage trend ${case_id} points=${points} ==="
  "${cmd[@]}"
  trend_csvs+=("${outdir}/${case_id}_trend.csv")
}

for case_id in "${CORE_CASES[@]}"; do
  run_case "$case_id" "$POINTS_CORE"
done
for case_id in "${EXT_CASES[@]}"; do
  run_case "$case_id" "$POINTS_LONG"
done

echo "=== merge coverage suite ==="
python3 "$MERGE_SCRIPT" --outdir "$SUITE_DIR" "${trend_csvs[@]}"

echo "trend_dir=$TREND_DIR"
echo "suite_dir=$SUITE_DIR"
