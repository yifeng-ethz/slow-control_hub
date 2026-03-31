#!/usr/bin/env python3
from __future__ import annotations

import sys
from pathlib import Path

import matplotlib.pyplot as plt
import pandas as pd
from matplotlib.ticker import PercentFormatter


plt.style.use("seaborn-v0_8-whitegrid")


def read_csv(path: Path) -> pd.DataFrame:
    if not path.exists():
        return pd.DataFrame()
    return pd.read_csv(path)


def save(fig, out_dir: Path, name: str) -> None:
    out_dir.mkdir(parents=True, exist_ok=True)
    fig.tight_layout()
    fig.savefig(out_dir / f"{name}.png", dpi=180)
    plt.close(fig)


def ecdf(values: pd.Series) -> pd.DataFrame:
    ordered = pd.Series(sorted(float(value) for value in values if pd.notna(value)))
    if ordered.empty:
        return pd.DataFrame(columns=["x", "cdf"])
    return pd.DataFrame({"x": ordered, "cdf": (ordered.index + 1) / len(ordered)})


def plot_rate_curves(csv_dir: Path, out_dir: Path) -> None:
    df = read_csv(csv_dir / "rate_latency.csv")
    if df.empty:
        return

    subset = df[df["experiment"].isin(["RATE-02", "RATE-03", "RATE-04", "RATE-05", "RATE-06"])]
    fig, ax = plt.subplots(figsize=(8, 5))
    for experiment, group in subset.groupby("experiment"):
        ax.plot(group["offered_rate"], group["throughput_tps"] / 1e6, marker="o", label=experiment)
    ax.set_xlabel("Offered Rate (fraction of nominal)")
    ax.set_ylabel("Throughput (Mtxn/s)")
    ax.set_title("Throughput Saturation vs Outstanding Depth")
    ax.legend()
    save(fig, out_dir, "throughput_saturation")

    fig, ax = plt.subplots(figsize=(8, 5))
    for experiment, group in subset.groupby("experiment"):
        ax.plot(group["offered_rate"], group["p99_latency_ns"], marker="o", label=experiment)
    ax.set_xlabel("Offered Rate (fraction of nominal)")
    ax.set_ylabel("P99 Latency (ns)")
    ax.set_title("Latency Hockey Stick vs Outstanding Depth")
    ax.legend()
    save(fig, out_dir, "rate_latency_hockeystick")


def plot_fragmentation(csv_dir: Path, out_dir: Path) -> None:
    df = read_csv(csv_dir / "frag_results.csv")
    if df.empty:
        return
    fig, ax = plt.subplots(figsize=(8, 5))
    for experiment in ["FRAG-01", "FRAG-02", "FRAG-05", "FRAG-07"]:
        group = df[df["experiment"] == experiment].copy()
        if group.empty:
            continue
        group = group.sort_values("txn_id")
        group["frag_smooth"] = group["frag_cost"].rolling(window=128, min_periods=1).mean()
        ax.plot(group["txn_id"], group["frag_smooth"], label=experiment)
    ax.set_xlabel("Transaction")
    ax.set_ylabel("Rolling Fragmentation Cost")
    ax.set_title("Fragmentation Cost Over Time")
    ax.legend()
    save(fig, out_dir, "fragmentation_over_time")


def plot_ooo(csv_dir: Path, out_dir: Path) -> None:
    df = read_csv(csv_dir / "ooo_speedup.csv")
    if df.empty:
        return
    fig, ax = plt.subplots(figsize=(7, 5))
    ax.scatter(df["latency_stddev_ns"], df["speedup"], s=70, alpha=0.8)
    for _, row in df.iterrows():
        ax.annotate(row["experiment"], (row["latency_stddev_ns"], row["speedup"]), xytext=(4, 4), textcoords="offset points", fontsize=8)
    ax.set_xlabel("Latency Stddev (ns)")
    ax.set_ylabel("OoO Speedup")
    ax.set_title("OoO Speedup vs Latency Variance")
    save(fig, out_dir, "ooo_speedup_vs_variance")


def plot_atomic(csv_dir: Path, out_dir: Path) -> None:
    df = read_csv(csv_dir / "atomic_impact.csv")
    if df.empty:
        return
    fig, ax = plt.subplots(figsize=(7, 5))
    ax.bar((df["atomic_ratio"] * 100).astype(int).astype(str), df["throughput_tps"] / 1e6, color="#cc5a3c")
    ax.set_xlabel("Atomic Ratio (%)")
    ax.set_ylabel("Throughput (Mtxn/s)")
    ax.set_title("Atomic Throughput Degradation")
    save(fig, out_dir, "atomic_throughput")

    cdf = read_csv(csv_dir / "latency_cdf.csv")
    if cdf.empty:
        return
    cdf = cdf[cdf["experiment"].isin(["ATOM-01", "ATOM-02", "ATOM-03", "ATOM-04"])]
    fig, ax = plt.subplots(figsize=(7, 5))
    for experiment, group in cdf.groupby("experiment"):
        ax.plot(group["latency_ns"], group["cdf"], label=experiment)
    ax.set_xlabel("Latency (ns)")
    ax.set_ylabel("CDF")
    ax.set_title("Latency Distribution Shift with Atomics")
    ax.legend()
    save(fig, out_dir, "atomic_latency_cdf")


def plot_sizing(csv_dir: Path, out_dir: Path) -> None:
    df = read_csv(csv_dir / "sizing_sweep.csv")
    if df.empty:
        return

    fig, ax = plt.subplots(figsize=(7, 5))
    outstanding = df[df["sweep_name"] == "outstanding"]
    if not outstanding.empty:
        ax.plot(outstanding["param_value"], outstanding["throughput_tps"] / 1e6, marker="o", label="Outstanding")
    payload = df[df["sweep_name"] == "payload"]
    if not payload.empty:
        ax.plot(payload["param_value"], payload["throughput_tps"] / 1e6, marker="s", label="Payload Depth")
    ax.set_xlabel("Parameter Value")
    ax.set_ylabel("Throughput (Mtxn/s)")
    ax.set_title("Sizing Knee Curves")
    ax.legend()
    save(fig, out_dir, "sizing_knee")

    joint = df[df["sweep_name"] == "joint"]
    if joint.empty:
        return
    pivot = joint.pivot_table(index="param_value_secondary", columns="param_value", values="throughput_tps")
    fig, ax = plt.subplots(figsize=(7, 5))
    im = ax.imshow(pivot.values / 1e6, origin="lower", aspect="auto")
    ax.set_xticks(range(len(pivot.columns)))
    ax.set_xticklabels(pivot.columns)
    ax.set_yticks(range(len(pivot.index)))
    ax.set_yticklabels(pivot.index)
    ax.set_xlabel("Outstanding Limit")
    ax.set_ylabel("Payload Depth")
    ax.set_title("Throughput Heatmap")
    fig.colorbar(im, ax=ax, label="Mtxn/s")
    save(fig, out_dir, "sizing_heatmap")


def plot_priority(csv_dir: Path, out_dir: Path) -> None:
    df = read_csv(csv_dir / "priority_analysis.csv")
    if df.empty:
        return
    fig, ax = plt.subplots(figsize=(7, 5))
    ax.bar(df["experiment"], df["int_avg_latency_ns"], color="#4c78a8", label="avg")
    ax.plot(df["experiment"], df["int_max_latency_ns"], color="#e45756", marker="o", label="max")
    ax.set_xlabel("Experiment")
    ax.set_ylabel("Internal Latency (ns)")
    ax.set_title("Internal Priority Under Load")
    ax.legend()
    save(fig, out_dir, "priority_internal_latency")


def plot_credit(csv_dir: Path, out_dir: Path) -> None:
    df = read_csv(csv_dir / "credit_trace.csv")
    if df.empty:
        return
    fig, ax = plt.subplots(figsize=(7, 5))
    for experiment in ["CRED-02", "CRED-03", "CRED-04"]:
        group = df[df["experiment"] == experiment].sort_values("utilization")
        if group.empty:
            continue
        cdf = pd.Series(range(1, len(group) + 1), dtype=float) / len(group)
        ax.plot(group["utilization"], cdf, label=experiment)
    ax.set_xlabel("Upload Credit Utilization")
    ax.set_ylabel("CDF")
    ax.set_title("Credit Utilization CDF")
    if ax.lines:
        ax.legend()
    save(fig, out_dir, "credit_utilization_cdf")


def plot_ordering(csv_dir: Path, out_dir: Path) -> None:
    impact = read_csv(csv_dir / "ordering_impact.csv")
    tx = read_csv(csv_dir / "ordering_transactions.csv")
    scan = read_csv(csv_dir / "ordering_scan.csv")

    if not impact.empty:
        for col in [
            "release_ratio",
            "acquire_ratio",
            "throughput_ordered",
            "throughput_baseline",
            "avg_drain_latency_ns",
            "avg_hold_latency_ns",
            "domains",
        ]:
            if col in impact.columns:
                impact[col] = pd.to_numeric(impact[col], errors="coerce")

    if not scan.empty:
        for col in [
            "param_value",
            "normalized_throughput",
            "throughput_tps",
            "baseline_throughput_tps",
            "avg_release_drain_ns",
            "avg_acquire_hold_ns",
            "avg_outstanding",
        ]:
            if col in scan.columns:
                scan[col] = pd.to_numeric(scan[col], errors="coerce")

    if not scan.empty:
        release_scan = scan[scan["family"].isin(["release_shallow_scan", "release_deep_scan"])].copy()
        if not release_scan.empty:
            fig, ax = plt.subplots(figsize=(7.5, 5))
            labels = {
                "release_shallow_scan": "L=1 writes",
                "release_deep_scan": "L=64 writes",
            }
            for family, group in release_scan.groupby("family"):
                group = group.sort_values("param_value")
                ax.plot(
                    group["param_value"] * 100.0,
                    group["normalized_throughput"] * 100.0,
                    marker="o",
                    linewidth=2.0,
                    label=labels.get(family, family),
                )
            ax.set_xlabel("Release Ratio (%)")
            ax.set_ylabel("Throughput (% of relaxed baseline)")
            ax.yaxis.set_major_formatter(PercentFormatter())
            ax.set_title("Release Ratio Sweep")
            ax.legend()
            save(fig, out_dir, "ordering_release_ratio_scan")

        acquire_scan = scan[scan["family"] == "acquire_scan"].copy()
        if not acquire_scan.empty:
            acquire_scan = acquire_scan.sort_values("param_value")
            fig, ax = plt.subplots(figsize=(7.5, 5))
            ax.plot(
                acquire_scan["param_value"] * 100.0,
                acquire_scan["normalized_throughput"] * 100.0,
                marker="o",
                linewidth=2.0,
                color="#4c78a8",
            )
            ax.set_xlabel("Acquire Ratio (%)")
            ax.set_ylabel("Throughput (% of relaxed baseline)")
            ax.yaxis.set_major_formatter(PercentFormatter())
            ax.set_title("Acquire Ratio Sweep")
            save(fig, out_dir, "ordering_acquire_ratio_scan")

        domain_scan = scan[scan["family"] == "domain_scaling_ooo"].copy()
        if not domain_scan.empty:
            domain_scan = domain_scan.sort_values("param_value")
            fig, ax = plt.subplots(figsize=(7.5, 5))
            ax.plot(
                domain_scan["param_value"],
                domain_scan["normalized_throughput"] * 100.0,
                marker="o",
                linewidth=2.0,
                color="#f58518",
            )
            ax.set_xlabel("Active Ordering Domains")
            ax.set_ylabel("Throughput (% of relaxed baseline)")
            ax.yaxis.set_major_formatter(PercentFormatter())
            ax.set_title("OoO + Ordering Domain Scaling")
            save(fig, out_dir, "ordering_domain_scaling_ooo")

    if not tx.empty:
        for col in [
            "release_drain_ns",
            "acquire_hold_ns",
            "reply_done_ns",
            "ord_dom_id",
        ]:
            if col in tx.columns:
                tx[col] = pd.to_numeric(tx[col], errors="coerce")

        release_rows = tx[
            (tx["run_tag"] == "ordered")
            & (tx["order"] == "release")
            & (tx["release_drain_ns"] > 0)
        ]
        if not release_rows.empty:
            fig, ax = plt.subplots(figsize=(7.5, 5))
            focus = {"ORD-01", "ORD-02", "ORD-07"}
            for experiment, group in release_rows.groupby("experiment"):
                if experiment not in focus:
                    continue
                curve = ecdf(group["release_drain_ns"])
                ax.plot(curve["x"], curve["cdf"], linewidth=2.0, label=experiment)
            ax.set_xlabel("Release Drain Latency (ns)")
            ax.set_ylabel("CDF")
            ax.set_title("Release Drain Latency CDF")
            if ax.lines:
                ax.legend()
            save(fig, out_dir, "ordering_release_drain_cdf")

        acquire_rows = tx[
            (tx["run_tag"] == "ordered")
            & (tx["order"] == "acquire")
            & (tx["acquire_hold_ns"] > 0)
        ]
        if not acquire_rows.empty:
            fig, ax = plt.subplots(figsize=(7.5, 5))
            focus = {"ORD-03", "ORD-05", "ORD-06"}
            for experiment, group in acquire_rows.groupby("experiment"):
                if experiment not in focus:
                    continue
                curve = ecdf(group["acquire_hold_ns"])
                ax.plot(curve["x"], curve["cdf"], linewidth=2.0, label=experiment)
            ax.set_xlabel("Acquire Hold Latency (ns)")
            ax.set_ylabel("CDF")
            ax.set_title("Acquire Hold Latency CDF")
            if ax.lines:
                ax.legend()
            save(fig, out_dir, "ordering_acquire_hold_cdf")

        ord05 = tx[tx["experiment"] == "ORD-05"].copy()
        if not ord05.empty and ord05["reply_done_ns"].notna().any():
            positive_done = ord05["reply_done_ns"].dropna()
            if not positive_done.empty:
                bins = max(12, min(48, len(positive_done) // 20))
                ord05["time_bin"] = pd.cut(ord05["reply_done_ns"], bins=bins, labels=False, include_lowest=True)
                grouped = (
                    ord05.groupby(["run_tag", "ord_dom_id", "time_bin"])
                    .size()
                    .reset_index(name="txn_count")
                )
                bin_edges = pd.cut(positive_done, bins=bins, retbins=True, include_lowest=True)[1]
                bin_width_ns = max(float(bin_edges[1] - bin_edges[0]), 1.0)
                grouped["throughput_mtxns"] = grouped["txn_count"] / bin_width_ns * 1e3
                grouped["time_mid_ns"] = grouped["time_bin"].astype(float).map(
                    lambda idx: 0.5 * (bin_edges[int(idx)] + bin_edges[int(idx) + 1])
                )
                fig, ax = plt.subplots(figsize=(8, 5))
                for run_tag, dom_id, label in [
                    ("ordered", 0, "ordered D0"),
                    ("ordered", 1, "ordered D1"),
                    ("baseline", 1, "baseline D1"),
                ]:
                    view = grouped[(grouped["run_tag"] == run_tag) & (grouped["ord_dom_id"] == dom_id)]
                    if view.empty:
                        continue
                    view = view.sort_values("time_mid_ns")
                    ax.plot(view["time_mid_ns"], view["throughput_mtxns"], linewidth=2.0, label=label)
                ax.set_xlabel("Reply Completion Time (ns)")
                ax.set_ylabel("Binned Throughput (Mtxn/s)")
                ax.set_title("Cross-Domain Independence (ORD-05)")
                if ax.lines:
                    ax.legend()
                save(fig, out_dir, "ordering_cross_domain_independence")

    if not impact.empty:
        fig, ax = plt.subplots(figsize=(8, 5))
        impact = impact.sort_values("experiment")
        ax.bar(impact["experiment"], impact["throughput_baseline"] / 1e6, width=0.38, label="baseline")
        ax.bar(impact["experiment"], impact["throughput_ordered"] / 1e6, width=0.22, label="ordered")
        ax.set_ylabel("Throughput (Mtxn/s)")
        ax.set_title("ORD Ordered vs Relaxed Throughput")
        ax.legend()
        save(fig, out_dir, "ordering_throughput_cmp")


def main(argv: list[str] | None = None) -> int:
    args = argv or sys.argv[1:]
    if len(args) != 2:
        print("usage: plot_results.py <csv_dir> <plot_dir>", file=sys.stderr)
        return 1
    csv_dir = Path(args[0])
    out_dir = Path(args[1])
    plot_rate_curves(csv_dir, out_dir)
    plot_fragmentation(csv_dir, out_dir)
    plot_ooo(csv_dir, out_dir)
    plot_atomic(csv_dir, out_dir)
    plot_sizing(csv_dir, out_dir)
    plot_priority(csv_dir, out_dir)
    plot_credit(csv_dir, out_dir)
    plot_ordering(csv_dir, out_dir)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
