#!/usr/bin/env python3
import argparse
import csv
import os
import re
import subprocess
import sys
import time
from pathlib import Path

VCD_KEYS = {
    "Branches": "branches_pct",
    "Conditions": "conditions_pct",
    "Covergroups": "covergroups_pct",
    "Expressions": "expressions_pct",
    "FSM States": "fsm_states_pct",
    "FSM Transitions": "fsm_transitions_pct",
    "Statements": "statements_pct",
    "Toggles": "toggles_pct",
    "Total coverage (filtered view)": "total_pct",
}

SUMMARY_RE = re.compile(r"^\s*(Branches|Conditions|Covergroups|Expressions|FSM States|FSM Transitions|Statements|Toggles)\s+.*?([0-9]+\.[0-9]+)%\s*$")
TOTAL_RE = re.compile(r"^Total coverage \(filtered view\):\s+([0-9]+\.[0-9]+)%\s*$")
FUNC_RE = re.compile(r"cmd_cov=([0-9]+\.[0-9]+)\s+rsp_cov=([0-9]+\.[0-9]+)")
SIM_TIME_RE = re.compile(r"Time:\s+([0-9]+)\s+ns")


def parse_args() -> argparse.Namespace:
    ap = argparse.ArgumentParser(description="Run sc_hub UVM case prefixes with coverage and emit a trend CSV/plot")
    ap.add_argument("case_id", help="Promoted UVM case id, for example T356")
    ap.add_argument("--points", default="64,128,256,512,768", help="Comma-separated SC_HUB_TXN_COUNT override points")
    ap.add_argument("--seed", type=int, default=1, help="Deterministic SC_HUB_SEED override")
    ap.add_argument("--outdir", default=None, help="Output directory (default: tb/transcript/coverage_trend/<case>)")
    ap.add_argument("--extra-plusargs", default="", help="Additional raw plusargs appended to every run")
    ap.add_argument("--case-script", default="./scripts/run_uvm_case.sh")
    ap.add_argument("--tb-dir", default=str(Path(__file__).resolve().parents[1]))
    return ap.parse_args()


def run(cmd, cwd=None, env=None, capture=True):
    return subprocess.run(cmd, cwd=cwd, env=env, text=True, capture_output=capture, check=False)


def parse_summary(text: str) -> dict:
    metrics = {v: None for v in VCD_KEYS.values()}
    for line in text.splitlines():
        m = SUMMARY_RE.match(line)
        if m:
            metrics[VCD_KEYS[m.group(1)]] = float(m.group(2))
            continue
        m = TOTAL_RE.match(line)
        if m:
            metrics["total_pct"] = float(m.group(1))
    return metrics


def parse_functional(log_text: str) -> tuple:
    func_cmd = None
    func_rsp = None
    sim_ns = None
    for line in log_text.splitlines():
        m = FUNC_RE.search(line)
        if m:
            func_cmd = float(m.group(1))
            func_rsp = float(m.group(2))
        m = SIM_TIME_RE.search(line)
        if m:
            sim_ns = int(m.group(1))
    return func_cmd, func_rsp, sim_ns


def maybe_plot(rows, out_png: Path):
    try:
        import matplotlib.pyplot as plt
    except Exception as exc:
        print(f"plot skipped: matplotlib unavailable ({exc})")
        return

    by_subrun = {}
    for row in rows:
        by_subrun.setdefault(row["subrun"], []).append(row)

    fig, axes = plt.subplots(len(by_subrun), 1, figsize=(10, 4 * max(1, len(by_subrun))), squeeze=False)
    for ax, (subrun, subrows) in zip(axes.flatten(), sorted(by_subrun.items())):
        subrows = sorted(subrows, key=lambda r: float(r["wall_s"]))
        x = [float(r["wall_s"]) for r in subrows]
        ax.plot(x, [float(r["total_pct"]) for r in subrows], marker='o', label='total')
        ax.plot(x, [float(r["statements_pct"]) for r in subrows], marker='o', label='stmt')
        ax.plot(x, [float(r["branches_pct"]) for r in subrows], marker='o', label='branch')
        ax.plot(x, [float(r["toggles_pct"]) for r in subrows], marker='o', label='toggle')
        ax.plot(x, [float(r["covergroups_pct"]) for r in subrows], marker='o', label='cvg')
        ax.set_title(subrun)
        ax.set_xlabel('wall time [s]')
        ax.set_ylabel('coverage [%]')
        ax.grid(True, alpha=0.3)
        ax.legend(loc='best')
    fig.tight_layout()
    fig.savefig(out_png, dpi=160)


def main() -> int:
    args = parse_args()
    tb_dir = Path(args.tb_dir).resolve()
    case_script = Path(args.case_script)
    if not case_script.is_absolute():
        case_script = (tb_dir / case_script).resolve()
    outdir = Path(args.outdir) if args.outdir else tb_dir / 'transcript' / 'coverage_trend' / args.case_id
    ucdb_dir = outdir / 'ucdb'
    log_dir = outdir / 'logs'
    outdir.mkdir(parents=True, exist_ok=True)
    ucdb_dir.mkdir(parents=True, exist_ok=True)
    log_dir.mkdir(parents=True, exist_ok=True)

    points = [int(p.strip()) for p in args.points.split(',') if p.strip()]
    if not points:
        raise SystemExit('no points specified')

    questa_home = Path('/data1/intelFPGA_pro/23.1/questa_fse/bin/vcover')
    csv_path = outdir / f'{args.case_id}_trend.csv'
    png_path = outdir / f'{args.case_id}_trend.png'
    rows = []

    for point in points:
        run_tag = f'n{point}'
        env = os.environ.copy()
        env['COV_ENABLE'] = '1'
        env['COV_DIR'] = str(ucdb_dir)
        env['RUN_TAG'] = run_tag
        env['SC_HUB_TXN_COUNT_OVERRIDE'] = str(point)
        plusargs = [f'+SC_HUB_SEED={args.seed}']
        if args.extra_plusargs:
            plusargs.append(args.extra_plusargs.strip())
        env['SC_HUB_OVERRIDE_PLUSARGS'] = ' '.join(plusargs)

        start = time.monotonic()
        proc = run([str(case_script), args.case_id], cwd=str(tb_dir), env=env, capture=True)
        elapsed = time.monotonic() - start
        log_path = log_dir / f'{args.case_id}_{run_tag}.log'
        log_text = proc.stdout + proc.stderr
        log_path.write_text(log_text)
        if proc.returncode != 0:
            print(log_text)
            raise SystemExit(f'coverage trend run failed for {args.case_id} point={point}')

        ucdb_files = sorted(ucdb_dir.glob(f'{args.case_id}_*_{run_tag}.ucdb'))
        if not ucdb_files:
            raise SystemExit(f'no UCDB produced for {args.case_id} point={point}')

        report_ucdb = ucdb_files[0]
        report_name = report_ucdb.stem.replace(f'_{run_tag}', '')
        if len(ucdb_files) > 1:
            report_ucdb = ucdb_dir / f'{args.case_id}_aggregate_{run_tag}.ucdb'
            merge_cmd = [str(questa_home), 'merge', '-out', str(report_ucdb)] + [str(p) for p in ucdb_files]
            merge = run(merge_cmd, cwd=str(tb_dir), env=env, capture=True)
            if merge.returncode != 0:
                print(merge.stdout)
                print(merge.stderr, file=sys.stderr)
                raise SystemExit(f'vcover merge failed for {args.case_id} point={point}')
            report_name = f'{args.case_id}_aggregate'

        func_cmd, func_rsp, sim_ns = parse_functional(log_text)
        rpt = run([str(questa_home), 'report', '-summary', '-code', 'bcesft', '-cvg', str(report_ucdb)], cwd=str(tb_dir), env=env, capture=True)
        if rpt.returncode != 0:
            print(rpt.stdout)
            print(rpt.stderr, file=sys.stderr)
            raise SystemExit(f'vcover report failed for {report_ucdb}')
        metrics = parse_summary(rpt.stdout)
        row = {
            'case_id': args.case_id,
            'subrun': report_name,
            'txn_count': point,
            'wall_s': f'{elapsed:.3f}',
            'sim_ns': '' if sim_ns is None else str(sim_ns),
            'func_cmd_cov_pct': '' if func_cmd is None else f'{func_cmd:.2f}',
            'func_rsp_cov_pct': '' if func_rsp is None else f'{func_rsp:.2f}',
            'ucdb': str(report_ucdb),
            'log': str(log_path),
        }
        for key in ['total_pct','branches_pct','conditions_pct','covergroups_pct','expressions_pct','fsm_states_pct','fsm_transitions_pct','statements_pct','toggles_pct']:
            value = metrics.get(key)
            row[key] = '' if value is None else f'{value:.2f}'
        rows.append(row)
        print(f"{report_name}: txn={point} wall={elapsed:.3f}s total={row['total_pct']} stmt={row['statements_pct']} branch={row['branches_pct']} toggle={row['toggles_pct']} cvg={row['covergroups_pct']}")

    fieldnames = ['case_id','subrun','txn_count','wall_s','sim_ns','total_pct','statements_pct','branches_pct','conditions_pct','expressions_pct','fsm_states_pct','fsm_transitions_pct','toggles_pct','covergroups_pct','func_cmd_cov_pct','func_rsp_cov_pct','ucdb','log']
    with csv_path.open('w', newline='') as fh:
        writer = csv.DictWriter(fh, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)
    maybe_plot(rows, png_path)
    print(f'csv={csv_path}')
    print(f'png={png_path}')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
