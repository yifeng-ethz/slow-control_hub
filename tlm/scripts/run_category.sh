#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CATEGORY="${1:-}"
CSV_DIR="${2:-${ROOT_DIR}/results/csv}"

if [[ -z "${CATEGORY}" ]]; then
  echo "usage: $0 <frag|rate|ooo|atom|cred|prio|size|ord> [csv_dir]" >&2
  exit 1
fi

mkdir -p "${CSV_DIR}" "${ROOT_DIR}/results/plots"
python3 "${ROOT_DIR}/scripts/run_experiment.py" --category "${CATEGORY}" --csv-dir "${CSV_DIR}"
