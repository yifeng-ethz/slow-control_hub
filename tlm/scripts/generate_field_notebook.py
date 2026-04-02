#!/usr/bin/env python3
from __future__ import annotations

import argparse
import itertools
import json
import textwrap
from pathlib import Path


_CELL_IDS = itertools.count()


def _md(source: str) -> dict[str, object]:
    source = textwrap.dedent(source).strip()
    return {
        "cell_type": "markdown",
        "id": f"cell-{next(_CELL_IDS)}",
        "metadata": {},
        "source": [line + "\n" for line in source.strip().splitlines()],
    }


def _code(source: str) -> dict[str, object]:
    source = textwrap.dedent(source).strip()
    return {
        "cell_type": "code",
        "execution_count": None,
        "id": f"cell-{next(_CELL_IDS)}",
        "metadata": {},
        "outputs": [],
        "source": [line + "\n" for line in source.strip().splitlines()],
    }


def build_notebook(csv_dir: Path, plot_dir: Path) -> dict[str, object]:
    cells = [
        _md(
            """
            # Field Workload Review Notebook
            This notebook maps the `sc_hub` TLM to a concrete frontend workload:

            - flow 0: histogram read every second, 256 words as four consecutive 64-word reads
            - flow 1: datapath register-map snapshot every second, chunked to 64 words without crossing slave boundaries
            - flow 2: 8-ASIC configuration burst, 2662 bits per ASIC into scratch, then start plus atomic status polling

            Two schedules are compared:

            - `literal_sparse`: preserves the real cadence, so most of the run is idle and OoO gain should be tiny
            - `compressed_overlap`: preserves the same burst shapes, but packs them into 20 us windows so the blocking mechanism is visible

            Modeling limits for this review:

            - the current TLM does not model target-driven status progression, so config polls capture bus pressure and atomic lock cost, not true progress semantics
            - the control/status window is modeled as external low-latency memory for timing purposes
            """
        ),
        _md(
            r"""
            ## Review Equations
            $$
            \rho_{\mathrm{busy}}=\frac{t_{\mathrm{busy}}}{t_{\mathrm{span}}}
            $$
            This is the schedule duty factor. If $\rho_{\mathrm{busy}}\ll 1$, global OoO gain should be negligible because the hub is idle most of the time.

            $$
            \hat F_X(x)=\frac{1}{N}\sum_{i=1}^{N}\mathbf{1}\left(X_i\le x\right)
            $$
            This empirical CDF exposes whether one flow or phase shifts left under OoO.

            $$
            G_{99}=\frac{p99_{\mathrm{ino}}}{p99_{\mathrm{ooo}}}
            $$
            $G_{99}>1$ means OoO improves the 99th percentile latency for that class of requests.
            """
        ),
        _code(
            """
            from pathlib import Path
            import matplotlib.pyplot as plt
            import numpy as np
            import pandas as pd
            from IPython.display import display
            from matplotlib.ticker import PercentFormatter

            plt.style.use("seaborn-v0_8-whitegrid")

            csv_dir = Path(r'__CSV_DIR__')
            plot_dir = Path(r'__PLOT_DIR__')
            plot_dir.mkdir(parents=True, exist_ok=True)

            tx = pd.read_csv(csv_dir / "field_transactions.csv")
            summary = pd.read_csv(csv_dir / "field_summary.csv")
            config = pd.read_csv(csv_dir / "field_config_summary.csv")
            scenarios = pd.read_csv(csv_dir / "field_scenarios.csv")
            outstanding = pd.read_csv(csv_dir / "field_outstanding_trace.csv")
            overlap_scan = pd.read_csv(csv_dir / "field_overlap_scan.csv")

            numeric_candidates = [
                "arrival_ns",
                "arrival_s",
                "reply_done_ns",
                "latency_ns",
                "period_ns",
                "busy_time_ns",
                "schedule_span_ns",
                "duty_cycle",
                "ooo_reorders",
                "window_idx",
                "asic_idx",
                "chunk_words",
                "burst_words_total",
                "slave_instance",
                "command_order",
                "config_makespan_ns",
                "cfg_poll_p99_ns",
                "time_ns",
                "total_active",
            ]
            for frame in [tx, summary, config, scenarios, outstanding, overlap_scan]:
                for col in numeric_candidates:
                    if col in frame.columns:
                        frame[col] = pd.to_numeric(frame[col], errors="coerce")

            def ecdf(values):
                ordered = pd.Series(sorted(float(v) for v in values if pd.notna(v)))
                if ordered.empty:
                    return pd.DataFrame(columns=["x", "cdf"])
                return pd.DataFrame({"x": ordered, "cdf": (ordered.index + 1) / len(ordered)})

            def phase_label(row):
                if row["phase"] == "datapath_read":
                    return f'{row["flow_name"]}:{row["slave"]}'
                return f'{row["flow_name"]}:{row["phase"]}'

            tx["phase_label"] = tx.apply(phase_label, axis=1)
            display(scenarios)
            display(summary[["scenario_id", "run_tag", "completed", "avg_latency_ns", "duty_cycle", "ooo_reorders"]])
            """
        ),
        _md(
            """
            ## Duty Factor
            The literal schedule should look almost idle on a whole-run basis. The compressed schedule is not a frequency claim; it is a local-overlap sensitivity study.
            """
        ),
        _code(
            """
            fig, axes = plt.subplots(1, 2, figsize=(11.5, 4.5))
            duty_view = summary.sort_values(["scenario_id", "run_tag"])
            for axis, metric, title in [
                (axes[0], "duty_cycle", "Busy Duty Factor"),
                (axes[1], "ooo_reorders", "OoO Reply Reorders"),
            ]:
                pivot = duty_view.pivot(index="scenario_id", columns="run_tag", values=metric)
                pivot.plot(kind="bar", ax=axis, rot=15, width=0.75)
                axis.set_title(title)
                axis.set_xlabel("")
                if metric == "duty_cycle":
                    axis.yaxis.set_major_formatter(PercentFormatter(1.0))
                else:
                    axis.set_ylabel("count")
            plt.tight_layout()
            out = plot_dir / "field_duty_and_reorder.png"
            plt.savefig(out, dpi=180)
            plt.show()

            display(summary[["scenario_id", "run_tag", "busy_time_ns", "schedule_span_ns", "duty_cycle", "ooo_reorders"]])
            """
        ),
        _md(
            """
            ## Literal Schedule Overview
            This is the real cadence view. The first panel shows the whole schedule in seconds. The second zooms around the single config event to show that the overlap window is tiny even though commands do contend locally.
            """
        ),
        _code(
            """
            literal = tx[tx["scenario_id"] == "literal_sparse"].copy()
            literal["flow_short"] = literal["scenario_flow"].map({"flow0": "hist", "flow1": "regs", "flow2": "cfg"})
            fig, axes = plt.subplots(1, 2, figsize=(13, 4.8))
            for run_tag, marker in [("ino", "o"), ("ooo", "x")]:
                view = literal[literal["run_tag"] == run_tag]
                axes[0].scatter(view["arrival_s"], view["flow_short"], s=6, alpha=0.45, marker=marker, label=run_tag)
            axes[0].set_xlabel("Arrival Time (s)")
            axes[0].set_ylabel("Flow")
            axes[0].set_title("Whole Literal Schedule")
            axes[0].legend()

            config_anchor_ns = literal[literal["flow_name"] == "config_burst"]["arrival_ns"].min()
            zoom = literal[(literal["arrival_ns"] >= config_anchor_ns - 2.5e5) & (literal["arrival_ns"] <= config_anchor_ns + 2.5e5)].copy()
            zoom["relative_us"] = (zoom["arrival_ns"] - config_anchor_ns) / 1e3
            colors = {"flow0": "#4c78a8", "flow1": "#72b7b2", "flow2": "#e45756"}
            for flow, group in zoom.groupby("scenario_flow"):
                axes[1].scatter(group["relative_us"], group["phase"], s=14, alpha=0.65, color=colors.get(flow, "#999999"), label=flow)
            axes[1].set_xlabel("Time Relative to Config Start (us)")
            axes[1].set_title("Literal Schedule Zoom Near Config Event")
            axes[1].legend()

            plt.tight_layout()
            out = plot_dir / "field_literal_schedule_overview.png"
            plt.savefig(out, dpi=180)
            plt.show()
            """
        ),
        _md(
            """
            ## Literal Cadence: Per-Phase Tail Latency
            Expected result: very small differences, because most 1-second snapshots do not overlap the rare config burst in time.
            """
        ),
        _code(
            """
            literal_focus = literal[literal["phase_label"].isin([
                "histogram:histogram_read",
                "config_burst:cfg_poll",
                "datapath_snapshot:frame_rcv",
                "datapath_snapshot:ring_buf_cam",
            ])].copy()
            phase_order = [
                "histogram:histogram_read",
                "datapath_snapshot:frame_rcv",
                "datapath_snapshot:ring_buf_cam",
                "config_burst:cfg_poll",
            ]
            metric_rows = []
            for (run_tag, phase_label), group in literal_focus.groupby(["run_tag", "phase_label"]):
                metric_rows.append(
                    {
                        "run_tag": run_tag,
                        "phase_label": phase_label,
                        "p50_ns": group["latency_ns"].median(),
                        "p99_ns": group["latency_ns"].quantile(0.99),
                    }
                )
            literal_metrics = pd.DataFrame(metric_rows)

            fig, axes = plt.subplots(1, 2, figsize=(12, 4.5), sharey=False)
            for axis, metric, title in [(axes[0], "p50_ns", "Literal p50"), (axes[1], "p99_ns", "Literal p99")]:
                pivot = literal_metrics.pivot(index="phase_label", columns="run_tag", values=metric).reindex(phase_order)
                pivot.plot(kind="bar", ax=axis, rot=20, width=0.75)
                axis.set_title(title)
                axis.set_xlabel("")
                axis.set_ylabel("Latency (ns)")
            plt.tight_layout()
            out = plot_dir / "field_literal_phase_latency.png"
            plt.savefig(out, dpi=180)
            plt.show()

            literal_gain = literal_metrics.pivot(index="phase_label", columns="run_tag", values="p99_ns").reindex(phase_order)
            literal_gain["p99_gain_ino_over_ooo"] = literal_gain["ino"] / literal_gain["ooo"]
            display(literal_gain)
            """
        ),
        _md(
            """
            ## Compressed Overlap: Per-Class Latency CDF
            This is the real blocking picture. The config and snapshot bursts are aligned in time, so short control polls and lower-latency datapath chunks can benefit from OoO.
            """
        ),
        _code(
            """
            compressed = tx[tx["scenario_id"] == "compressed_overlap"].copy()
            selections = [
                ("histogram:histogram_read", "Histogram 64w", "#4c78a8"),
                ("datapath_snapshot:frame_rcv", "frame_rcv 64w", "#72b7b2"),
                ("datapath_snapshot:ring_buf_cam", "ring_buf_cam 64w", "#f58518"),
                ("config_burst:cfg_poll", "Config poll atomic 1w", "#e45756"),
            ]
            fig, axes = plt.subplots(2, 2, figsize=(12, 8), sharey=True)
            for axis, (phase_label, title, color) in zip(axes.ravel(), selections):
                for run_tag, line_style in [("ino", "-"), ("ooo", "--")]:
                    group = compressed[compressed["phase_label"] == phase_label]
                    curve = ecdf(group[group["run_tag"] == run_tag]["latency_ns"])
                    if curve.empty:
                        continue
                    axis.plot(curve["x"], curve["cdf"], linestyle=line_style, linewidth=2.0, color=color, label=run_tag)
                axis.set_title(title)
                axis.set_xlabel("Latency (ns)")
                axis.legend()
            axes[0, 0].set_ylabel("CDF")
            axes[1, 0].set_ylabel("CDF")
            plt.tight_layout()
            out = plot_dir / "field_compressed_latency_cdf.png"
            plt.savefig(out, dpi=180)
            plt.show()
            """
        ),
        _md(
            """
            ## Compressed Overlap: p50 and p99 by Class
            This makes the real gain easier to read than four separate CDFs.
            """
        ),
        _code(
            """
            compressed_focus = compressed[compressed["phase_label"].isin([item[0] for item in selections])].copy()
            metric_rows = []
            for (run_tag, phase_label), group in compressed_focus.groupby(["run_tag", "phase_label"]):
                metric_rows.append(
                    {
                        "run_tag": run_tag,
                        "phase_label": phase_label,
                        "p50_ns": group["latency_ns"].median(),
                        "p99_ns": group["latency_ns"].quantile(0.99),
                        "avg_ns": group["latency_ns"].mean(),
                    }
                )
            compressed_metrics = pd.DataFrame(metric_rows)
            order = [item[0] for item in selections]

            fig, axes = plt.subplots(1, 2, figsize=(12, 4.6))
            for axis, metric, title in [(axes[0], "p50_ns", "Compressed p50"), (axes[1], "p99_ns", "Compressed p99")]:
                pivot = compressed_metrics.pivot(index="phase_label", columns="run_tag", values=metric).reindex(order)
                pivot.plot(kind="bar", ax=axis, rot=20, width=0.75)
                axis.set_title(title)
                axis.set_xlabel("")
                axis.set_ylabel("Latency (ns)")
            plt.tight_layout()
            out = plot_dir / "field_compressed_phase_latency.png"
            plt.savefig(out, dpi=180)
            plt.show()

            gain = compressed_metrics.pivot(index="phase_label", columns="run_tag", values="p99_ns").reindex(order)
            gain["p99_gain_ino_over_ooo"] = gain["ino"] / gain["ooo"]
            display(gain)
            """
        ),
        _md(
            """
            ## Why This Field Mix Does Not Benefit
            In this TLM, OoO is not a generic small-first scheduler. It mainly changes external completion order and reply selection.

            The compressed field mix is dominated by large external reads:
            - histogram reads
            - datapath snapshot reads
            - atomic config polls that still need replies

            That means the reply engine remains a bottleneck even when completions reorder. The result is visible in the ratio curves below: the current mix is neutral to negative for OoO in this model.
            """
        ),
        _md(
            """
            ## Overlap-Interval Sweep
            This is the SIGCOMM-style parameter scan for the same field burst. The period is swept while the burst shape stays fixed. If OoO helped this workload, the normalized ratio would rise above 1.0 for at least some interval. If it stays below 1.0, the workload is simply not a good OoO target in the current harness.
            """
        ),
        _code(
            """
            overlap_scan["period_us"] = overlap_scan["period_ns"] / 1e3
            pivot_avg = overlap_scan.pivot(index="period_us", columns="run_tag", values="avg_latency_ns").sort_index()
            pivot_cfg = overlap_scan.pivot(index="period_us", columns="run_tag", values="cfg_poll_p99_ns").sort_index()

            fig, axes = plt.subplots(1, 2, figsize=(12, 4.8))
            axes[0].plot(pivot_avg.index, pivot_avg["ino"] / pivot_avg["ooo"], marker="o", linewidth=2.0, color="#4c78a8")
            axes[0].axhline(1.0, color="#444444", linewidth=1.0, linestyle="--")
            axes[0].set_xlabel("Window Period (us)")
            axes[0].set_ylabel("Avg-Latency Ratio (ino / ooo)")
            axes[0].set_title("Aggregate Latency Ratio")

            axes[1].plot(pivot_cfg.index, pivot_cfg["ino"] / pivot_cfg["ooo"], marker="o", linewidth=2.0, color="#e45756")
            axes[1].axhline(1.0, color="#444444", linewidth=1.0, linestyle="--")
            axes[1].set_xlabel("Window Period (us)")
            axes[1].set_ylabel("Cfg-Poll p99 Ratio (ino / ooo)")
            axes[1].set_title("Control Poll Tail Ratio")

            plt.tight_layout()
            out = plot_dir / "field_overlap_period_scan.png"
            plt.savefig(out, dpi=180)
            plt.show()

            display(overlap_scan.sort_values(["period_ns", "run_tag"]))
            """
        ),
        _md(
            """
            ## Positive-Control Flow Set
            This second flow set is intentionally chosen to match where the current TLM can help:

            - background flow: long scratch/config writes for 8 ASICs
            - foreground flow: short 1-word `frame_rcv` status reads

            The background writes have small reply cost, so OoO can expose the benefit of letting short reads complete without waiting for forced in-order completion behind earlier long external work.
            """
        ),
        _code(
            """
            positive = tx[tx["scenario_id"] == "positive_control"].copy()
            positive_quick = positive[positive["phase_label"] == "frame_status:quick_read"].copy()
            positive_bg = positive[positive["phase_label"] == "cfg_background:scratch_write"].copy()

            fig, axes = plt.subplots(1, 2, figsize=(12, 4.8))
            for run_tag, style in [("ino", "-"), ("ooo", "--")]:
                quick_curve = ecdf(positive_quick[positive_quick["run_tag"] == run_tag]["latency_ns"])
                bg_curve = ecdf(positive_bg[positive_bg["run_tag"] == run_tag]["latency_ns"])
                axes[0].plot(quick_curve["x"], quick_curve["cdf"], linestyle=style, linewidth=2.0, color="#4c78a8", label=run_tag)
                axes[1].plot(bg_curve["x"], bg_curve["cdf"], linestyle=style, linewidth=2.0, color="#b279a2", label=run_tag)
            axes[0].set_title("Positive Control: Quick frame_rcv Reads")
            axes[1].set_title("Positive Control: Background Scratch Writes")
            for axis in axes:
                axis.set_xlabel("Latency (ns)")
                axis.set_ylabel("CDF")
                axis.legend()
            plt.tight_layout()
            out = plot_dir / "field_positive_control_cdf.png"
            plt.savefig(out, dpi=180)
            plt.show()
            """
        ),
        _code(
            """
            positive_rows = []
            for (run_tag, phase_label), group in positive.groupby(["run_tag", "phase_label"]):
                positive_rows.append(
                    {
                        "run_tag": run_tag,
                        "phase_label": phase_label,
                        "avg_ns": group["latency_ns"].mean(),
                        "p99_ns": group["latency_ns"].quantile(0.99),
                    }
                )
            positive_metrics = pd.DataFrame(positive_rows)
            positive_order = ["frame_status:quick_read", "cfg_background:scratch_write"]

            fig, axes = plt.subplots(1, 2, figsize=(12, 4.5))
            for axis, metric, title in [(axes[0], "avg_ns", "Positive Control Avg"), (axes[1], "p99_ns", "Positive Control p99")]:
                pivot = positive_metrics.pivot(index="phase_label", columns="run_tag", values=metric).reindex(positive_order)
                pivot.plot(kind="bar", ax=axis, rot=15, width=0.75)
                axis.set_title(title)
                axis.set_xlabel("")
                axis.set_ylabel("Latency (ns)")
            plt.tight_layout()
            out = plot_dir / "field_positive_control_latency.png"
            plt.savefig(out, dpi=180)
            plt.show()

            quick_gain = positive_metrics.pivot(index="phase_label", columns="run_tag", values="p99_ns").loc["frame_status:quick_read", "ino"] / positive_metrics.pivot(index="phase_label", columns="run_tag", values="p99_ns").loc["frame_status:quick_read", "ooo"]
            print({"positive_control_quick_read_p99_gain_ino_over_ooo": float(quick_gain)})
            """
        ),
        _md(
            """
            ## Config Burst Makespan
            Expected result: OoO should not radically accelerate the config flow itself, because the writes, release, and polls live in one domain and the atomic polls still serialize on the external bus. The main value is protecting other flows.
            """
        ),
        _code(
            """
            compressed_cfg = config[config["scenario_id"] == "compressed_overlap"].copy()
            plt.figure(figsize=(7.5, 4.8))
            data = [
                compressed_cfg[compressed_cfg["run_tag"] == "ino"]["config_makespan_ns"],
                compressed_cfg[compressed_cfg["run_tag"] == "ooo"]["config_makespan_ns"],
            ]
            plt.boxplot(data, labels=["ino", "ooo"], showfliers=False)
            plt.ylabel("Per-ASIC Config Makespan (ns)")
            plt.title("Compressed Overlap Config Makespan")
            out = plot_dir / "field_config_makespan_boxplot.png"
            plt.tight_layout()
            plt.savefig(out, dpi=180)
            plt.show()

            display(
                compressed_cfg.groupby("run_tag")["config_makespan_ns"].agg(["mean", "median", lambda s: s.quantile(0.95), "max"]).rename(
                    columns={"<lambda_0>": "p95"}
                )
            )
            """
        ),
        _md(
            """
            ## Representative Timeline
            This is the qualitative sanity plot. One compressed window is shown as command segments from arrival to reply completion. If OoO is working, the short atomic polls and lower-latency datapath chunks should not wait behind every older long burst.
            """
        ),
        _code(
            """
            timeline = compressed[(compressed["window_idx"] == 0) & (compressed["phase_label"].isin([item[0] for item in selections] + ["config_burst:scratch_write", "config_burst:cfg_start"]))].copy()
            timeline["relative_ns"] = timeline["arrival_ns"] - timeline["window_start_ns"]
            label_order = [
                "histogram:histogram_read",
                "datapath_snapshot:frame_rcv",
                "datapath_snapshot:ring_buf_cam",
                "config_burst:scratch_write",
                "config_burst:cfg_start",
                "config_burst:cfg_poll",
            ]
            y_map = {label: idx for idx, label in enumerate(label_order)}

            fig, axes = plt.subplots(1, 2, figsize=(14, 5), sharey=True)
            for axis, run_tag in zip(axes, ["ino", "ooo"]):
                view = timeline[timeline["run_tag"] == run_tag].sort_values("arrival_ns")
                for _, row in view.iterrows():
                    label = row["phase_label"]
                    if label not in y_map:
                        continue
                    axis.hlines(
                        y=y_map[label],
                        xmin=row["relative_ns"],
                        xmax=row["reply_done_ns"] - row["window_start_ns"],
                        linewidth=1.8,
                        color={
                            "histogram:histogram_read": "#4c78a8",
                            "datapath_snapshot:frame_rcv": "#72b7b2",
                            "datapath_snapshot:ring_buf_cam": "#f58518",
                            "config_burst:scratch_write": "#b279a2",
                            "config_burst:cfg_start": "#9d755d",
                            "config_burst:cfg_poll": "#e45756",
                        }[label],
                        alpha=0.75,
                    )
                axis.set_title(run_tag)
                axis.set_xlabel("Time Within Window (ns)")
            axes[0].set_yticks(list(y_map.values()), list(y_map.keys()))
            out = plot_dir / "field_representative_timeline.png"
            plt.tight_layout()
            plt.savefig(out, dpi=180)
            plt.show()
            """
        ),
        _md(
            """
            ## Interpretation
            The expected qualitative outcome is:

            - the literal schedule shows near-zero global gain because the hub is idle for almost all of the 1-second periods
            - the compressed overlap view exposes the local blocking mechanism and shows where OoO buys latency, mainly for fast control polls and lower-latency datapath reads
            - the config flow itself should change much less than the other flows because its own ordering and atomic semantics still serialize it
            """
        ),
        _code(
            """
            literal_cfg = summary[summary["scenario_id"] == "literal_sparse"].set_index("run_tag")
            compressed_cfg_summary = summary[summary["scenario_id"] == "compressed_overlap"].set_index("run_tag")
            conclusions = {
                "literal_duty_cycle": float(literal_cfg.loc["ooo", "duty_cycle"]),
                "literal_avg_latency_delta_ns": float(literal_cfg.loc["ino", "avg_latency_ns"] - literal_cfg.loc["ooo", "avg_latency_ns"]),
                "compressed_avg_latency_delta_ns": float(compressed_cfg_summary.loc["ino", "avg_latency_ns"] - compressed_cfg_summary.loc["ooo", "avg_latency_ns"]),
                "compressed_cfg_poll_p99_gain": float(gain.loc["config_burst:cfg_poll", "p99_gain_ino_over_ooo"]),
                "compressed_frame_rcv_p99_gain": float(gain.loc["datapath_snapshot:frame_rcv", "p99_gain_ino_over_ooo"]),
                "scan_best_avg_ratio": float((pivot_avg["ino"] / pivot_avg["ooo"]).max()),
                "positive_control_quick_read_p99_gain": float(quick_gain),
            }
            print(conclusions)
            """
        ),
        _md(
            """
            ## Reference Figures (external)
            These are style references for how the plots are presented, not quantitative targets for this hub.

            - Tail-latency reasoning: https://research.google/pubs/the-tail-at-scale/
            - SIGCOMM latency-CDF style: https://people.csail.mit.edu/alizadeh/papers/homa-sigcomm18.pdf
            - SIGCOMM load and duty-factor style: https://people.csail.mit.edu/alizadeh/papers/dctcp-sigcomm10.pdf
            - gem5 networking-style comparison: https://networks.ece.cornell.edu/papers/dpdkgem5-ispass24.pdf
            - HTSim simulator context: https://github.com/Broadcom/csg-htsim
            """
        ),
    ]

    return {
        "cells": cells,
        "metadata": {
            "kernelspec": {
                "display_name": "Python 3",
                "language": "python",
                "name": "python3",
            },
            "language_info": {
                "name": "python",
                "version": "3.10",
            },
        },
        "nbformat": 4,
        "nbformat_minor": 5,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate the field workload review notebook")
    parser.add_argument(
        "--out",
        default="results/field_review_v4/field_workload_review.ipynb",
        help="Notebook output path",
    )
    parser.add_argument(
        "--csv-dir",
        default="results/field_review_v4/csv",
        help="CSV input directory to embed in the generated notebook",
    )
    args = parser.parse_args()
    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    csv_dir = Path(args.csv_dir).resolve()
    plot_dir = out.parent.resolve() / "plots"
    notebook = build_notebook(csv_dir, plot_dir)
    payload = json.dumps(notebook, indent=2)
    payload = payload.replace("__CSV_DIR__", str(csv_dir))
    payload = payload.replace("__PLOT_DIR__", str(plot_dir))
    out.write_text(payload)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
