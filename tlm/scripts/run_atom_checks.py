#!/usr/bin/env python3
from __future__ import annotations

import argparse
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from scripts.run_experiment import append_rows
from tests.atom.checks import CHECKS, run_checks


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Run atomic correctness checks")
    parser.add_argument("experiment_ids", nargs="*")
    parser.add_argument(
        "--csv-dir",
        default=str(ROOT / "results" / "csv"),
        help="CSV output directory",
    )
    args = parser.parse_args(argv)

    if args.experiment_ids:
        invalid = [experiment_id for experiment_id in args.experiment_ids if experiment_id not in CHECKS]
        if invalid:
            parser.error(f"invalid experiment IDs: {', '.join(invalid)}")

    rows = run_checks(args.experiment_ids or list(CHECKS))
    append_rows(Path(args.csv_dir) / "atom_correctness.csv", rows)
    for row in rows:
        status = "PASS" if int(row["passed"]) else "FAIL"
        print(f"{row['experiment']}: {status}", file=sys.stderr)
    return 0 if all(int(row["passed"]) for row in rows) else 1


if __name__ == "__main__":
    raise SystemExit(main())
