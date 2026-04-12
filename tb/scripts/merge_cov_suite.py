#!/usr/bin/env python3
import argparse
import csv
import os
import re
import subprocess
import sys
from pathlib import Path

SUMMARY_RE = re.compile(r"^\s*(Branches|Conditions|Covergroups|Expressions|FSM States|FSM Transitions|Statements|Toggles)\s+.*?([0-9]+\.[0-9]+)%\s*$")
TOTAL_RE = re.compile(r"^Total coverage \((?:Code Coverage Only, )?filtered view\):\s+([0-9]+\.[0-9]+)%\s*$")
KEY_MAP = {
    "Branches": "branches_pct",
    "Conditions": "conditions_pct",
    "Covergroups": "covergroups_pct",
    "Expressions": "expressions_pct",
    "FSM States": "fsm_states_pct",
    "FSM Transitions": "fsm_transitions_pct",
    "Statements": "statements_pct",
    "Toggles": "toggles_pct",
}


def find_vcover() -> str:
    env_qh = os.environ.get("QUESTA_HOME", "").strip()
    candidates = []
    if env_qh:
        candidates.extend([
            Path(env_qh) / "bin" / "vcover",
            Path(env_qh) / "linux_x86_64" / "vcover",
        ])
    candidates.extend([
        Path("/data1/intelFPGA_pro/23.1/questa_fe/bin/vcover"),
        Path("/data1/intelFPGA_pro/23.1/questa_fe/linux_x86_64/vcover"),
        Path("/data1/intelFPGA_pro/23.1/questa_fse/bin/vcover"),
        Path("/data1/intelFPGA_pro/23.1/questa_fse/linux_x86_64/vcover"),
    ])
    for cand in candidates:
        if cand.is_file():
            return str(cand)
    found = subprocess.run(["bash", "-lc", "command -v vcover || true"], text=True, capture_output=True)
    if found.stdout.strip():
        return found.stdout.strip()
    raise SystemExit("unable to locate vcover; set QUESTA_HOME or install Questa")


def repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def rtl_srcfile_arg() -> str:
    rtl_files = sorted((repo_root() / "rtl").glob("*.vhd"))
    if not rtl_files:
        raise SystemExit("no RTL files found for structural coverage filtering")
    return "-srcfile=" + "+".join(str(path.resolve()) for path in rtl_files)


def covg_srcfile_arg() -> str:
    return f"-srcfile={(repo_root() / 'tb' / 'uvm' / 'sc_hub_cov_collector.sv').resolve()}"


def report_has_no_matching_data(text: str) -> bool:
    return "No matching coverage data found" in text


def parse_summary(text: str) -> dict:
    metrics = {value: None for value in KEY_MAP.values()}
    metrics["total_pct"] = None
    for line in text.splitlines():
        match = SUMMARY_RE.match(line)
        if match:
            metrics[KEY_MAP[match.group(1)]] = float(match.group(2))
            continue
        match = TOTAL_RE.match(line)
        if match:
            metrics["total_pct"] = float(match.group(1))
    return metrics


def read_final_row(csv_path: Path) -> dict:
    with csv_path.open() as fh:
        rows = list(csv.DictReader(fh))
    if not rows:
        raise SystemExit(f"empty trend csv: {csv_path}")
    rows.sort(key=lambda row: int(row["txn_count"]))
    return rows[-1]


def maybe_plot(rows, out_png: Path):
    try:
        import matplotlib.pyplot as plt
    except Exception as exc:
        print(f"plot skipped: matplotlib unavailable ({exc})")
        return
    x = [float(row["cumulative_wall_s"]) for row in rows]
    fig, ax = plt.subplots(figsize=(10, 5))
    ax.plot(x, [float(row["total_pct"]) for row in rows], marker="o", label="dut total")
    ax.plot(x, [float(row["statements_pct"]) for row in rows], marker="o", label="stmt")
    ax.plot(x, [float(row["branches_pct"]) for row in rows], marker="o", label="branch")
    ax.plot(x, [float(row["toggles_pct"]) for row in rows], marker="o", label="toggle")
    ax.plot(x, [float(row["covergroups_pct"]) for row in rows], marker="o", label="cvg")
    ax.set_xlabel("cumulative wall time [s]")
    ax.set_ylabel("coverage [%]")
    ax.set_title("Merged suite coverage trend")
    ax.grid(True, alpha=0.3)
    ax.legend(loc="best")
    fig.tight_layout()
    fig.savefig(out_png, dpi=160)


def report_structural(vcover: str, ucdb: Path) -> dict:
    rpt = subprocess.run([vcover, "report", "-summary", "-code", "bcesft", rtl_srcfile_arg(), str(ucdb)], text=True, capture_output=True)
    if rpt.returncode != 0:
        print(rpt.stdout)
        print(rpt.stderr, file=sys.stderr)
        raise SystemExit(f"vcover structural report failed for {ucdb}")
    return parse_summary(rpt.stdout)


def report_functional(vcover: str, ucdb: Path) -> dict:
    primary = subprocess.run([vcover, "report", "-summary", "-cvg", covg_srcfile_arg(), str(ucdb)], text=True, capture_output=True)
    primary_metrics = parse_summary(primary.stdout) if primary.returncode == 0 else None
    if primary.returncode == 0 and not report_has_no_matching_data(primary.stdout) and primary_metrics.get("covergroups_pct") is not None:
        return primary_metrics
    fallback = subprocess.run([vcover, "report", "-summary", "-cvg", str(ucdb)], text=True, capture_output=True)
    if fallback.returncode != 0:
        print(primary.stdout)
        print(primary.stderr, file=sys.stderr)
        print(fallback.stdout)
        print(fallback.stderr, file=sys.stderr)
        raise SystemExit(f"vcover functional report failed for {ucdb}")
    return parse_summary(fallback.stdout)


def main() -> int:
    ap = argparse.ArgumentParser(description="Merge final per-case UCDBs into a cumulative suite coverage trend")
    ap.add_argument("trend_csv", nargs="+", help="Per-case trend CSVs in desired accumulation order")
    ap.add_argument("--outdir", required=True)
    args = ap.parse_args()

    vcover = find_vcover()
    outdir = Path(args.outdir)
    outdir.mkdir(parents=True, exist_ok=True)

    cumulative_ucdbs = []
    cumulative_wall = 0.0
    rows = []
    for idx, csv_arg in enumerate(args.trend_csv, start=1):
        final_row = read_final_row(Path(csv_arg))
        cumulative_ucdbs.append(final_row["ucdb"])
        cumulative_wall += float(final_row["wall_s"])
        merged_ucdb = outdir / f"suite_step{idx:02d}_{final_row['case_id']}.ucdb"
        merge = subprocess.run([vcover, "merge", "-out", str(merged_ucdb)] + cumulative_ucdbs, text=True, capture_output=True)
        if merge.returncode != 0:
            print(merge.stdout)
            print(merge.stderr, file=sys.stderr)
            raise SystemExit(f"vcover merge failed at step {idx}")

        struct_metrics = report_structural(vcover, merged_ucdb)
        func_metrics = report_functional(vcover, merged_ucdb)
        prev_total = float(rows[-1]["total_pct"]) if rows else 0.0
        prev_cvg = float(rows[-1]["covergroups_pct"]) if rows and rows[-1]["covergroups_pct"] else 0.0
        delta_total = 0.0 if struct_metrics["total_pct"] is None else struct_metrics["total_pct"] - prev_total
        current_cvg = 0.0 if func_metrics["covergroups_pct"] is None else func_metrics["covergroups_pct"]
        delta_cvg = current_cvg - prev_cvg
        wall_s = float(final_row["wall_s"])
        gain_per_s = 0.0 if wall_s == 0 else delta_total / wall_s
        cvg_gain_per_s = 0.0 if wall_s == 0 else delta_cvg / wall_s
        row = {
            "step": idx,
            "case_id": final_row["case_id"],
            "txn_count": final_row["txn_count"],
            "wall_s": final_row["wall_s"],
            "cumulative_wall_s": f"{cumulative_wall:.3f}",
            "delta_total_pct": f"{delta_total:.2f}",
            "delta_total_pct_per_s": f"{gain_per_s:.3f}",
            "delta_covergroups_pct": f"{delta_cvg:.2f}",
            "delta_covergroups_pct_per_s": f"{cvg_gain_per_s:.3f}",
            "merged_ucdb": str(merged_ucdb),
        }
        for key, value in struct_metrics.items():
            if key == "covergroups_pct":
                continue
            row[key] = "" if value is None else f"{value:.2f}"
        row["covergroups_pct"] = "" if func_metrics["covergroups_pct"] is None else f"{func_metrics['covergroups_pct']:.2f}"
        rows.append(row)
        print(
            f"step={idx} case={row['case_id']} dut_total={row['total_pct']} delta={row['delta_total_pct']} "
            f"delta_cvg={row['delta_covergroups_pct']} cum_wall={row['cumulative_wall_s']}s"
        )

    csv_path = outdir / "suite_trend.csv"
    with csv_path.open("w", newline="") as fh:
        writer = csv.DictWriter(
            fh,
            fieldnames=[
                "step", "case_id", "txn_count", "wall_s", "cumulative_wall_s", "delta_total_pct", "delta_total_pct_per_s",
                "delta_covergroups_pct", "delta_covergroups_pct_per_s", "total_pct", "statements_pct", "branches_pct",
                "conditions_pct", "expressions_pct", "fsm_states_pct", "fsm_transitions_pct", "toggles_pct",
                "covergroups_pct", "merged_ucdb",
            ],
        )
        writer.writeheader()
        writer.writerows(rows)
    png_path = outdir / "suite_trend.png"
    maybe_plot(rows, png_path)
    print(f"csv={csv_path}")
    print(f"png={png_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
