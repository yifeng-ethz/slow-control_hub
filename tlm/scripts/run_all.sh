#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

rm -rf "${ROOT_DIR}/results/csv" "${ROOT_DIR}/results/plots"
mkdir -p "${ROOT_DIR}/results/csv" "${ROOT_DIR}/results/plots"

for category in frag rate ooo atom cred prio size ord; do
  python3 "${ROOT_DIR}/scripts/run_experiment.py" --category "${category}" --csv-dir "${ROOT_DIR}/results/csv"
done

python3 "${ROOT_DIR}/scripts/run_ord_checks.py" --csv-dir "${ROOT_DIR}/results/csv"
python3 "${ROOT_DIR}/scripts/run_ooo_checks.py" --csv-dir "${ROOT_DIR}/results/csv"
python3 "${ROOT_DIR}/scripts/run_atom_checks.py" --csv-dir "${ROOT_DIR}/results/csv"
python3 "${ROOT_DIR}/scripts/run_ordering_scan.py" --csv-dir "${ROOT_DIR}/results/csv"
python3 "${ROOT_DIR}/scripts/plot_results.py" "${ROOT_DIR}/results/csv" "${ROOT_DIR}/results/plots"
