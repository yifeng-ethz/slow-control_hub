#!/usr/bin/env python3
import argparse
import csv
import re
import subprocess
import sys
from pathlib import Path

SUMMARY_RE = re.compile(r"^\s*(Branches|Conditions|Covergroups|Expressions|FSM States|FSM Transitions|Statements|Toggles)\s+.*?([0-9]+\.[0-9]+)%\s*$")
TOTAL_RE = re.compile(r"^Total coverage \(filtered view\):\s+([0-9]+\.[0-9]+)%\s*$")
KEY_MAP = {
    'Branches': 'branches_pct',
    'Conditions': 'conditions_pct',
    'Covergroups': 'covergroups_pct',
    'Expressions': 'expressions_pct',
    'FSM States': 'fsm_states_pct',
    'FSM Transitions': 'fsm_transitions_pct',
    'Statements': 'statements_pct',
    'Toggles': 'toggles_pct',
}


def parse_summary(text: str) -> dict:
    metrics = {v: None for v in KEY_MAP.values()}
    metrics['total_pct'] = None
    for line in text.splitlines():
        m = SUMMARY_RE.match(line)
        if m:
            metrics[KEY_MAP[m.group(1)]] = float(m.group(2))
            continue
        m = TOTAL_RE.match(line)
        if m:
            metrics['total_pct'] = float(m.group(1))
    return metrics


def read_final_row(csv_path: Path) -> dict:
    with csv_path.open() as fh:
        rows = list(csv.DictReader(fh))
    if not rows:
        raise SystemExit(f'empty trend csv: {csv_path}')
    rows.sort(key=lambda r: int(r['txn_count']))
    return rows[-1]


def maybe_plot(rows, out_png: Path):
    try:
        import matplotlib.pyplot as plt
    except Exception as exc:
        print(f'plot skipped: matplotlib unavailable ({exc})')
        return
    x = [float(r['cumulative_wall_s']) for r in rows]
    fig, ax = plt.subplots(figsize=(10, 5))
    ax.plot(x, [float(r['total_pct']) for r in rows], marker='o', label='total')
    ax.plot(x, [float(r['statements_pct']) for r in rows], marker='o', label='stmt')
    ax.plot(x, [float(r['branches_pct']) for r in rows], marker='o', label='branch')
    ax.plot(x, [float(r['toggles_pct']) for r in rows], marker='o', label='toggle')
    ax.plot(x, [float(r['covergroups_pct']) for r in rows], marker='o', label='cvg')
    ax.set_xlabel('cumulative wall time [s]')
    ax.set_ylabel('coverage [%]')
    ax.set_title('Merged suite coverage trend')
    ax.grid(True, alpha=0.3)
    ax.legend(loc='best')
    fig.tight_layout()
    fig.savefig(out_png, dpi=160)


def main() -> int:
    ap = argparse.ArgumentParser(description='Merge final per-case UCDBs into a cumulative suite coverage trend')
    ap.add_argument('trend_csv', nargs='+', help='Per-case trend CSVs in desired accumulation order')
    ap.add_argument('--outdir', required=True)
    args = ap.parse_args()

    vcover = '/data1/intelFPGA_pro/23.1/questa_fse/bin/vcover'
    outdir = Path(args.outdir)
    outdir.mkdir(parents=True, exist_ok=True)

    cumulative_ucdbs = []
    cumulative_wall = 0.0
    rows = []
    for idx, csv_arg in enumerate(args.trend_csv, start=1):
        final_row = read_final_row(Path(csv_arg))
        cumulative_ucdbs.append(final_row['ucdb'])
        cumulative_wall += float(final_row['wall_s'])
        merged_ucdb = outdir / f'suite_step{idx:02d}_{final_row["case_id"]}.ucdb'
        cmd = [vcover, 'merge', '-out', str(merged_ucdb)] + cumulative_ucdbs
        merge = subprocess.run(cmd, text=True, capture_output=True)
        if merge.returncode != 0:
            print(merge.stdout)
            print(merge.stderr, file=sys.stderr)
            raise SystemExit(f'vcover merge failed at step {idx}')
        rpt = subprocess.run([vcover, 'report', '-summary', '-code', 'bcesft', '-cvg', str(merged_ucdb)], text=True, capture_output=True)
        if rpt.returncode != 0:
            print(rpt.stdout)
            print(rpt.stderr, file=sys.stderr)
            raise SystemExit(f'vcover report failed at step {idx}')
        metrics = parse_summary(rpt.stdout)
        prev_total = float(rows[-1]['total_pct']) if rows else 0.0
        delta_total = 0.0 if metrics['total_pct'] is None else metrics['total_pct'] - prev_total
        wall_s = float(final_row['wall_s'])
        gain_per_s = 0.0 if wall_s == 0 else delta_total / wall_s
        row = {
            'step': idx,
            'case_id': final_row['case_id'],
            'txn_count': final_row['txn_count'],
            'wall_s': final_row['wall_s'],
            'cumulative_wall_s': f'{cumulative_wall:.3f}',
            'delta_total_pct': f'{delta_total:.2f}',
            'delta_total_pct_per_s': f'{gain_per_s:.3f}',
            'merged_ucdb': str(merged_ucdb),
        }
        for key, value in metrics.items():
            row[key] = '' if value is None else f'{value:.2f}'
        rows.append(row)
        print(f"step={idx} case={row['case_id']} total={row['total_pct']} delta={row['delta_total_pct']} cum_wall={row['cumulative_wall_s']}s")

    csv_path = outdir / 'suite_trend.csv'
    with csv_path.open('w', newline='') as fh:
        writer = csv.DictWriter(fh, fieldnames=['step','case_id','txn_count','wall_s','cumulative_wall_s','delta_total_pct','delta_total_pct_per_s','total_pct','statements_pct','branches_pct','conditions_pct','expressions_pct','fsm_states_pct','fsm_transitions_pct','toggles_pct','covergroups_pct','merged_ucdb'])
        writer.writeheader()
        writer.writerows(rows)
    png_path = outdir / 'suite_trend.png'
    maybe_plot(rows, png_path)
    print(f'csv={csv_path}')
    print(f'png={png_path}')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
