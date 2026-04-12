#!/usr/bin/env python3
import argparse
import json
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CASES_DIR = ROOT / "waves" / "cases"


def add_artifact(items, label, atype, href):
    if href:
        items.append({"label": label, "type": atype, "href": href})


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--case-id', required=True)
    ap.add_argument('--title', required=True)
    ap.add_argument('--kind', default='directed')
    ap.add_argument('--group', default='smoke')
    ap.add_argument('--alias', default='')
    ap.add_argument('--status', default='draft')
    ap.add_argument('--vcd')
    ap.add_argument('--gtkw')
    ap.add_argument('--wavedrom')
    ap.add_argument('--summary')
    ap.add_argument('--notes', default='')
    ap.add_argument('--markers', nargs='*', default=[])
    args = ap.parse_args()

    case_dir = CASES_DIR / args.case_id
    case_dir.mkdir(parents=True, exist_ok=True)

    artifacts = []
    add_artifact(artifacts, 'VCD', 'vcd', args.vcd)
    add_artifact(artifacts, 'GTKWave Save', 'gtkw', args.gtkw)
    add_artifact(artifacts, 'WaveDrom', 'wavedrom', args.wavedrom)
    add_artifact(artifacts, 'Summary', 'markdown', args.summary)

    data = {
        'case_id': args.case_id,
        'title': args.title,
        'kind': args.kind,
        'group': args.group,
        'alias': args.alias,
        'status': args.status,
        'published_at': datetime.now(timezone.utc).isoformat(),
        'artifacts': artifacts,
        'markers': args.markers,
        'notes': args.notes,
    }
    (case_dir / 'meta.json').write_text(json.dumps(data, indent=2) + '\n')
    print(case_dir / 'meta.json')


if __name__ == '__main__':
    main()
