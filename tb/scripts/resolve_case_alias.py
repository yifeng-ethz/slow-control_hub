#!/usr/bin/env python3
import argparse
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

DOC_TABLES = {
    "B": ROOT / "DV_BASIC.md",
    "E": ROOT / "DV_EDGE.md",
    "P": ROOT / "DV_PROF.md",
    "X": ROOT / "DV_ERROR.md",
}
CROSS_DOC = ROOT / "DV_CROSS.md"


def parse_declared_max(path: Path, prefix: str):
    text = path.read_text()
    m = re.search(r"\*\*Canonical ID Range:\*\*\s+%s001-%s(\d{3})" % (prefix, prefix), text)
    if not m:
        return None
    return int(m.group(1))


def parse_table_ids(path: Path):
    ids = []
    for line in path.read_text().splitlines():
        m = re.match(r"\|\s*(T\d{3})\s*\|", line)
        if m:
            ids.append(m.group(1))
    return ids


def parse_cross_ids(path: Path):
    ids = []
    for line in path.read_text().splitlines():
        m = re.match(r"##\s+(T\d{3})\s*$", line.strip())
        if m:
            ids.append(m.group(1))
    return ids


def build_map():
    mapping = {}
    for prefix, path in DOC_TABLES.items():
        ids = parse_table_ids(path)
        for idx, target in enumerate(ids, start=1):
            mapping[f"{prefix}{idx:03d}"] = target
    for idx, target in enumerate(parse_cross_ids(CROSS_DOC), start=1):
        mapping[f"CROSS-{idx:03d}"] = target
    return mapping


def classify(case_id: str):
    if re.fullmatch(r"T\d{3}", case_id):
        return "T"
    if re.fullmatch(r"[BEPX]\d{3}", case_id):
        return case_id[0]
    if re.fullmatch(r"CROSS-\d{3}", case_id):
        return "CROSS"
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("case_id")
    ap.add_argument("--allow", default="T,B,E,P,X,CROSS")
    args = ap.parse_args()

    allowed = {item.strip() for item in args.allow.split(",") if item.strip()}
    case_id = args.case_id.strip()
    kind = classify(case_id)
    if kind is None:
        print(f"unsupported case id format: {case_id}", file=sys.stderr)
        return 2
    if kind not in allowed:
        print(f"case id {case_id} is not allowed in this runner", file=sys.stderr)
        return 2
    if kind == "T":
        print(case_id)
        return 0

    mapping = build_map()
    target = mapping.get(case_id)
    if target is None:
        if kind in DOC_TABLES:
            declared_max = parse_declared_max(DOC_TABLES[kind], kind)
            if declared_max is not None and int(case_id[1:]) <= declared_max:
                print(f"case id {case_id} is planned in {DOC_TABLES[kind].name} but not implemented in the runnable harness", file=sys.stderr)
                return 3
        print(f"no implementation alias found for {case_id}", file=sys.stderr)
        return 2
    print(target)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
