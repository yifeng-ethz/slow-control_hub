#!/usr/bin/env python3
import json
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CASES_DIR = ROOT / "waves" / "cases"
OUT = ROOT / "waves" / "manifest.json"


def rel_or_str(path: Path):
    try:
        return str(path.resolve().relative_to(ROOT.resolve()))
    except Exception:
        return str(path)


def normalize_artifact(case_dir: Path, item: dict):
    out = dict(item)
    href = item.get("href")
    if href:
        p = Path(href)
        if not p.is_absolute():
            case_local = case_dir / href
            root_local = ROOT / href
            if case_local.exists():
                p = case_local
            elif root_local.exists():
                p = root_local
            else:
                p = case_local
        out["href"] = rel_or_str(p)
    return out


def main():
    cases = []
    if CASES_DIR.exists():
        for meta_path in sorted(CASES_DIR.glob('*/meta.json')):
            data = json.loads(meta_path.read_text())
            case_dir = meta_path.parent
            data["case_dir"] = rel_or_str(case_dir)
            data["artifacts"] = [normalize_artifact(case_dir, x) for x in data.get("artifacts", [])]
            cases.append(data)
    manifest = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "case_count": len(cases),
        "cases": cases,
    }
    OUT.write_text(json.dumps(manifest, indent=2) + "\n")
    print(f'wrote {OUT} with {len(cases)} cases')


if __name__ == '__main__':
    main()
