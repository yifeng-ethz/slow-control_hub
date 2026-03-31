#!/usr/bin/env python3
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from scripts.run_ooo_checks import main


if __name__ == "__main__":
    raise SystemExit(main(["OOO-C01", "OOO-C02", "OOO-C03", "OOO-C04", "OOO-C05", "OOO-C06", "OOO-C07"]))
