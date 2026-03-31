#!/usr/bin/env python3
from __future__ import annotations

import argparse
import csv
import sys
from dataclasses import replace
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from include.sc_hub_tlm_config import ExperimentSpec, WorkloadConfig
from include.sc_hub_tlm_workload import single_word
from src.bus_target_model import BusTargetModel
from src.sc_hub_model import ScHubModel
from src.sc_hub_tlm_top import ScHubTlmTop
from src.sc_pkt_source import ScPktSource
from tests.experiment_catalog import categories, get_experiment, list_experiment_ids


def append_rows(path: Path, rows: list[dict[str, object]]) -> None:
    if not rows:
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    existing_header: list[str] | None = None
    existing_rows: list[dict[str, str]] = []
    if path.exists():
        with path.open("r", newline="") as handle:
            reader = csv.DictReader(handle)
            existing_header = reader.fieldnames or []
            existing_rows = list(reader)
    row_fields = sorted({key for row in rows for key in row})
    if existing_header:
        fieldnames = existing_header[:] 
        new_fields = [name for name in row_fields if name not in existing_header]
        fieldnames.extend(new_fields)
        if new_fields:
            with path.open("w", newline="") as handle:
                writer = csv.DictWriter(handle, fieldnames=fieldnames)
                writer.writeheader()
                for row in existing_rows:
                    writer.writerow({name: row.get(name, "") for name in fieldnames})
    else:
        fieldnames = row_fields
    with path.open("a", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        if existing_header is None:
            writer.writeheader()
        for row in rows:
            writer.writerow({name: row.get(name, "") for name in fieldnames})


def _safe_float(value: str | None) -> float:
    if value is None or value == "":
        return 0.0
    try:
        return float(value)
    except ValueError:
        return 0.0


def _parse_order_notes(notes: str) -> dict[str, object]:
    parsed: dict[str, object] = {
        "release_ratio": 0.0,
        "acquire_ratio": 0.0,
        "atomic_ratio": 0.0,
        "profile": "unknown",
        "domains": 1,
        "ooo": 0,
    }
    for pair in notes.split(";"):
        if "=" not in pair:
            continue
        key, value = pair.split("=", 1)
        key = key.strip()
        value = value.strip()
        if key in {"release_ratio", "acquire_ratio", "atomic_ratio"}:
            parsed[key] = _safe_float(value)
            continue
        if key in {"domains", "ooo"}:
            try:
                parsed[key] = int(value)
            except ValueError:
                parsed[key] = 0
            continue
        parsed[key] = value
    return parsed


def _strip_ordering(workload_cfg: WorkloadConfig) -> WorkloadConfig:
    return workload_cfg.clone(
        order_release_ratio=0.0,
        order_acquire_ratio=0.0,
        order_domain_release_ratio=tuple(0.0 for _ in workload_cfg.order_domain_weights),
        order_domain_acquire_ratio=tuple(0.0 for _ in workload_cfg.order_domain_weights),
    )


def run_once(spec: ExperimentSpec, *, run_tag: str, seed_offset: int = 0, hub=None, workload=None, latency=None):
    hub_cfg = hub or spec.hub
    workload_cfg = workload or spec.workload
    latency_cfg = latency or spec.latency
    perf = ScHubTlmTop(hub_cfg, latency_cfg, workload_cfg, spec.seed + seed_offset).run()
    summary = perf.basic_summary()
    summary.update(
        {
            "experiment": spec.experiment_id,
            "category": spec.category,
            "description": spec.description,
            "run_tag": run_tag,
            "seed": spec.seed + seed_offset,
            "workload": workload_cfg.name,
            "offered_rate": workload_cfg.offered_rate,
            "outstanding_limit": hub_cfg.outstanding_limit,
            "ext_payload_depth": hub_cfg.ext_up_pld_depth,
            "int_hdr_depth": hub_cfg.int_hdr_depth,
            "ooo_enable": int(hub_cfg.ooo_enable and hub_cfg.ooo_runtime_enable),
            "atomic_ratio": workload_cfg.atomic_ratio,
            "latency_stddev_ns": BusTargetModel(latency_cfg, spec.seed + seed_offset).latency_stddev_hint(),
        }
    )
    return perf, summary


def run_commands(
    spec: ExperimentSpec,
    commands,
    *,
    run_tag: str,
    hub=None,
    latency=None,
    seed_offset: int = 0,
    workload_name: str | None = None,
    offered_rate: float | None = None,
):
    hub_cfg = hub or spec.hub
    latency_cfg = latency or spec.latency
    model = ScHubModel(hub_cfg, latency_cfg, spec.seed + seed_offset)
    perf = model.run(commands)
    summary = perf.basic_summary()
    summary.update(
        {
            "experiment": spec.experiment_id,
            "category": spec.category,
            "description": spec.description,
            "run_tag": run_tag,
            "seed": spec.seed + seed_offset,
            "workload": workload_name or spec.workload.name,
            "offered_rate": offered_rate if offered_rate is not None else spec.workload.offered_rate,
            "outstanding_limit": hub_cfg.outstanding_limit,
            "ext_payload_depth": hub_cfg.ext_up_pld_depth,
            "int_hdr_depth": hub_cfg.int_hdr_depth,
            "ooo_enable": int(hub_cfg.ooo_enable and hub_cfg.ooo_runtime_enable),
            "atomic_ratio": spec.workload.atomic_ratio,
            "latency_stddev_ns": BusTargetModel(latency_cfg, spec.seed + seed_offset).latency_stddev_hint(),
        }
    )
    return model, perf, summary


def emit_common_traces(csv_dir: Path, spec: ExperimentSpec, run_tag: str, perf) -> None:
    append_rows(
        csv_dir / "credit_trace.csv",
        [{"experiment": spec.experiment_id, "run_tag": run_tag, **row} for row in perf.credit_trace],
    )
    append_rows(
        csv_dir / "outstanding_trace.csv",
        [{"experiment": spec.experiment_id, "run_tag": run_tag, **row} for row in perf.outstanding_trace],
    )
    append_rows(
        csv_dir / "ord_domain_trace.csv",
        [{"experiment": spec.experiment_id, "run_tag": run_tag, **row} for row in perf.ord_domain_trace],
    )


def run_frag(spec: ExperimentSpec, csv_dir: Path) -> int:
    perf, summary = run_once(spec, run_tag="base")
    rows = [{"experiment": spec.experiment_id, **row} for row in perf.transaction_rows]
    append_rows(csv_dir / "frag_results.csv", rows)
    append_rows(csv_dir / "frag_summary.csv", [summary])
    emit_common_traces(csv_dir, spec, "base", perf)
    return 1


def run_rate(spec: ExperimentSpec, csv_dir: Path) -> int:
    rows = []
    for idx, offered_rate in enumerate(spec.offered_rates):
        workload = spec.workload.clone(offered_rate=offered_rate)
        perf, summary = run_once(spec, run_tag=f"rate_{offered_rate:.2f}", seed_offset=idx, workload=workload)
        rows.append(summary)
    append_rows(csv_dir / "rate_latency.csv", rows)
    return len(rows)


def run_ooo(spec: ExperimentSpec, csv_dir: Path) -> int:
    perf_ino, summary_ino = run_once(
        spec,
        run_tag="ino",
        hub=spec.hub.clone(ooo_enable=False, ooo_runtime_enable=False),
        seed_offset=0,
        workload=spec.workload,
    )
    perf_ooo, summary_ooo = run_once(
        spec,
        run_tag="ooo",
        seed_offset=0,
        hub=spec.hub.clone(ooo_enable=True, ooo_runtime_enable=True),
        workload=spec.workload,
    )
    speedup = summary_ooo["throughput_tps"] / max(summary_ino["throughput_tps"], 1.0)
    row = {
        "experiment": spec.experiment_id,
        "description": spec.description,
        "latency_stddev_ns": summary_ooo["latency_stddev_ns"],
        "throughput_ino_tps": summary_ino["throughput_tps"],
        "throughput_ooo_tps": summary_ooo["throughput_tps"],
        "speedup": speedup,
        "avg_lat_ino_ns": summary_ino["avg_latency_ns"],
        "avg_lat_ooo_ns": summary_ooo["avg_latency_ns"],
        "lat_reduction_ns": summary_ino["avg_latency_ns"] - summary_ooo["avg_latency_ns"],
        "ooo_reorders": summary_ooo["ooo_reorders"],
        "avg_outstanding_ino": summary_ino["avg_outstanding"],
        "avg_outstanding_ooo": summary_ooo["avg_outstanding"],
    }
    append_rows(csv_dir / "ooo_speedup.csv", [row])
    append_rows(csv_dir / "latency_cdf.csv", perf_ino.latency_cdf_rows(spec.experiment_id, "ino"))
    append_rows(csv_dir / "latency_cdf.csv", perf_ooo.latency_cdf_rows(spec.experiment_id, "ooo"))
    emit_common_traces(csv_dir, spec, "ino", perf_ino)
    emit_common_traces(csv_dir, spec, "ooo", perf_ooo)
    return 2


def run_standard(spec: ExperimentSpec, csv_dir: Path) -> int:
    perf, summary = run_once(spec, run_tag="base")
    emit_common_traces(csv_dir, spec, "base", perf)
    if spec.category == "atom":
        append_rows(csv_dir / "atomic_impact.csv", [summary])
        append_rows(csv_dir / "latency_cdf.csv", perf.latency_cdf_rows(spec.experiment_id, spec.experiment_id.lower()))
    elif spec.category == "cred":
        append_rows(csv_dir / "credit_analysis.csv", [summary])
    elif spec.category == "prio":
        append_rows(csv_dir / "priority_analysis.csv", [summary])
    elif spec.category == "size":
        append_rows(csv_dir / "sizing_sweep.csv", [dict(summary, sweep_name="single", param_value="base")])
    else:
        append_rows(csv_dir / f"{spec.category}_summary.csv", [summary])
    return 1


def run_size_outstanding(spec: ExperimentSpec, csv_dir: Path) -> int:
    rows = []
    for idx, outstanding in enumerate(spec.sweep_values):
        hub = spec.hub.clone(
            outstanding_limit=outstanding,
            outstanding_int_reserved=min(2, max(1, outstanding // 4)),
            ext_issue_limit=outstanding,
        )
        perf, summary = run_once(spec, run_tag=f"os_{outstanding}", seed_offset=idx, hub=hub)
        rows.append(dict(summary, sweep_name="outstanding", param_value=outstanding))
    append_rows(csv_dir / "sizing_sweep.csv", rows)
    return len(rows)


def run_size_payload(spec: ExperimentSpec, csv_dir: Path) -> int:
    rows = []
    for idx, depth in enumerate(spec.sweep_values):
        hub = spec.hub.clone(
            ext_down_pld_depth=depth,
            ext_up_pld_depth=depth,
        )
        perf, summary = run_once(spec, run_tag=f"pld_{depth}", seed_offset=idx, hub=hub)
        rows.append(dict(summary, sweep_name="payload", param_value=depth))
    append_rows(csv_dir / "sizing_sweep.csv", rows)
    return len(rows)


def run_size_internal(spec: ExperimentSpec, csv_dir: Path) -> int:
    rows = []
    for idx, depth in enumerate(spec.sweep_values):
        hub = spec.hub.clone(int_hdr_depth=depth, int_up_hdr_depth=depth)
        perf, summary = run_once(spec, run_tag=f"int_{depth}", seed_offset=idx, hub=hub)
        rows.append(dict(summary, sweep_name="int_hdr", param_value=depth))
    append_rows(csv_dir / "sizing_sweep.csv", rows)
    return len(rows)


def run_size_joint(spec: ExperimentSpec, csv_dir: Path) -> int:
    rows = []
    sweep_idx = 0
    for outstanding in spec.sweep_values:
        for depth in spec.sweep_secondary:
            hub = spec.hub.clone(
                outstanding_limit=outstanding,
                outstanding_int_reserved=min(2, max(1, outstanding // 4)),
                ext_issue_limit=outstanding,
                ext_down_pld_depth=depth,
                ext_up_pld_depth=depth,
            )
            perf, summary = run_once(spec, run_tag=f"joint_{outstanding}_{depth}", seed_offset=sweep_idx, hub=hub)
            rows.append(
                dict(
                    summary,
                    sweep_name="joint",
                    param_value=outstanding,
                    param_value_secondary=depth,
                )
            )
            sweep_idx += 1
    append_rows(csv_dir / "sizing_sweep.csv", rows)
    return len(rows)


def run_ordering_impact(spec: ExperimentSpec, csv_dir: Path) -> int:
    ordered_perf, ordered_summary = run_once(spec, run_tag="ordered", seed_offset=0)
    base_perf, base_summary = run_once(
        spec,
        run_tag="baseline",
        seed_offset=0,
        workload=_strip_ordering(spec.workload),
    )
    details = _parse_order_notes(spec.notes)
    release_ratio = float(details.get("release_ratio", 0.0))
    acquire_ratio = float(details.get("acquire_ratio", 0.0))
    throughput_ordered = ordered_summary["throughput_tps"]
    throughput_base = base_summary["throughput_tps"]
    overhead = (throughput_base - throughput_ordered) / max(throughput_base, 1.0) * 100.0
    row = {
        "experiment": spec.experiment_id,
        "description": spec.description,
        "workload": spec.workload.name,
        "ord_profile": details.get("profile", "unknown"),
        "offered_rate": spec.workload.offered_rate,
        "peak_outstanding": spec.hub.ext_issue_limit,
        "outstanding_limit": spec.hub.outstanding_limit,
        "throughput_ordered": throughput_ordered,
        "throughput_baseline": throughput_base,
        "overhead_pct": overhead,
        "avg_latency_ordered_ns": ordered_summary["avg_latency_ns"],
        "avg_latency_baseline_ns": base_summary["avg_latency_ns"],
        "avg_drain_latency_ns": ordered_summary.get("avg_release_drain_ns", 0.0),
        "avg_hold_latency_ns": ordered_summary.get("avg_acquire_hold_ns", 0.0),
        "ordered_release_drain_ns": ordered_summary.get("avg_release_drain_ns", 0.0),
        "ordered_acquire_hold_ns": ordered_summary.get("avg_acquire_hold_ns", 0.0),
        "base_release_drain_ns": base_summary.get("avg_release_drain_ns", 0.0),
        "base_acquire_hold_ns": base_summary.get("avg_acquire_hold_ns", 0.0),
        "max_drain_latency_ns": ordered_summary.get("max_release_drain_ns", 0.0),
        "max_hold_latency_ns": ordered_summary.get("max_acquire_hold_ns", 0.0),
        "release_ratio": release_ratio,
        "acquire_ratio": acquire_ratio,
        "atomic_ratio": details.get("atomic_ratio", 0.0),
        "domains": details.get("domains", 1),
        "ooo_enabled": int(spec.hub.ooo_enable and spec.hub.ooo_runtime_enable),
        "latency_stddev_ns": ordered_summary["latency_stddev_ns"],
        "release_events": ordered_summary.get("release_count", 0.0),
        "acquire_events": ordered_summary.get("acquire_count", 0.0),
        "run_tag": "ordered_minus_baseline",
    }
    append_rows(csv_dir / "ordering_impact.csv", [row])
    append_rows(
        csv_dir / "ordering_transactions.csv",
        [{"experiment": spec.experiment_id, "run_tag": "ordered", **row} for row in ordered_perf.transaction_rows],
    )
    append_rows(
        csv_dir / "ordering_transactions.csv",
        [{"experiment": spec.experiment_id, "run_tag": "baseline", **row} for row in base_perf.transaction_rows],
    )
    append_rows(csv_dir / "latency_cdf.csv", ordered_perf.latency_cdf_rows(spec.experiment_id, "ordered"))
    append_rows(csv_dir / "latency_cdf.csv", base_perf.latency_cdf_rows(spec.experiment_id, "baseline"))
    emit_common_traces(csv_dir, spec, "ordered", ordered_perf)
    emit_common_traces(csv_dir, spec, "baseline", base_perf)
    return 1


def run_ooo_check(spec: ExperimentSpec, csv_dir: Path) -> int:
    from tests.ooo.checks import run_checks

    rows = run_checks([spec.experiment_id])
    append_rows(csv_dir / "ooo_correctness.csv", rows)
    return 1


def run_atom_check(spec: ExperimentSpec, csv_dir: Path) -> int:
    from tests.atom.checks import run_checks

    rows = run_checks([spec.experiment_id])
    append_rows(csv_dir / "atom_correctness.csv", rows)
    return 1


def run_ooo_frag_recovery(spec: ExperimentSpec, csv_dir: Path) -> int:
    stress_commands = ScPktSource(spec.workload, spec.seed).generate()
    recovery_workload = single_word(name="recovery_single_word", total_transactions=10000).clone(
        read_ratio=0.5,
        offered_rate=spec.workload.offered_rate,
    )
    time_base = (stress_commands[-1].arrival_ns if stress_commands else 0.0) + 20.0
    recovery_commands = [
        replace(cmd, seq=len(stress_commands) + idx, arrival_ns=time_base + cmd.arrival_ns)
        for idx, cmd in enumerate(ScPktSource(recovery_workload, spec.seed + 1).generate())
    ]
    _, perf, summary = run_commands(
        spec,
        stress_commands + recovery_commands,
        run_tag="recovery",
        workload_name=f"{spec.workload.name}+{recovery_workload.name}",
        offered_rate=spec.workload.offered_rate,
    )
    split_seq = len(stress_commands)
    rows = []
    for row in perf.transaction_rows:
        rows.append(
            {
                "experiment": spec.experiment_id,
                "phase": "stress" if int(row["txn_id"]) < split_seq else "recovery",
                **row,
            }
        )
    append_rows(csv_dir / "frag_results.csv", rows)
    append_rows(csv_dir / "frag_summary.csv", [dict(summary, phase_split_txn=split_seq)])
    emit_common_traces(csv_dir, spec, "recovery", perf)
    return 1


def run_spec(spec: ExperimentSpec, csv_dir: Path) -> int:
    if spec.mode == "frag":
        return run_frag(spec, csv_dir)
    if spec.mode == "rate_sweep":
        return run_rate(spec, csv_dir)
    if spec.mode == "ooo_compare":
        return run_ooo(spec, csv_dir)
    if spec.mode == "size_outstanding_sweep":
        return run_size_outstanding(spec, csv_dir)
    if spec.mode == "size_payload_sweep":
        return run_size_payload(spec, csv_dir)
    if spec.mode == "size_internal_sweep":
        return run_size_internal(spec, csv_dir)
    if spec.mode == "size_joint_sweep":
        return run_size_joint(spec, csv_dir)
    if spec.mode == "ordering_impact":
        return run_ordering_impact(spec, csv_dir)
    if spec.mode == "ooo_check":
        return run_ooo_check(spec, csv_dir)
    if spec.mode == "atom_check":
        return run_atom_check(spec, csv_dir)
    if spec.mode == "ooo_frag_recovery":
        return run_ooo_frag_recovery(spec, csv_dir)
    return run_standard(spec, csv_dir)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Run sc_hub TLM experiments")
    parser.add_argument("experiment_ids", nargs="*", help="Experiment IDs to run")
    parser.add_argument("--category", choices=categories(), help="Run every experiment in a category")
    parser.add_argument("--all", action="store_true", help="Run all configured experiments")
    parser.add_argument("--list", nargs="?", const="all", help="List experiments or one category")
    parser.add_argument(
        "--csv-dir",
        default=str(ROOT / "results" / "csv"),
        help="CSV output directory",
    )
    args = parser.parse_args(argv)

    if args.list is not None:
        category = None if args.list == "all" else args.list
        for experiment_id in list_experiment_ids(category):
            print(experiment_id)
        return 0

    if args.all:
        experiment_ids = list_experiment_ids()
    elif args.category:
        experiment_ids = list_experiment_ids(args.category)
    else:
        experiment_ids = args.experiment_ids

    if not experiment_ids:
        parser.error("no experiments selected")

    csv_dir = Path(args.csv_dir)
    total_runs = 0
    for experiment_id in experiment_ids:
        spec = get_experiment(experiment_id)
        total_runs += run_spec(spec, csv_dir)
        print(f"{experiment_id}: done", file=sys.stderr)
    print(f"completed {len(experiment_ids)} experiments / {total_runs} simulation runs", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
