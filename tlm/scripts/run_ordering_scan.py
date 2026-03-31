#!/usr/bin/env python3
from __future__ import annotations

import argparse
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from include.sc_hub_tlm_config import HubConfig, LatencyModelConfig
from include.sc_hub_tlm_types import LatencyKind
from include.sc_hub_tlm_workload import single_word, uniform_rw
from scripts.run_experiment import append_rows
from src.sc_hub_tlm_top import ScHubTlmTop


def _run_point(hub: HubConfig, latency: LatencyModelConfig, workload, seed: int) -> dict[str, float]:
    perf = ScHubTlmTop(hub, latency, workload, seed).run()
    return perf.basic_summary()


def _strip_ordering(workload):
    return workload.clone(
        order_release_ratio=0.0,
        order_acquire_ratio=0.0,
        order_domain_release_ratio=tuple(0.0 for _ in workload.order_domain_weights),
        order_domain_acquire_ratio=tuple(0.0 for _ in workload.order_domain_weights),
    )


def _row(
    family: str,
    param_name: str,
    param_value: float,
    workload,
    hub: HubConfig,
    latency: LatencyModelConfig,
    seed: int,
) -> dict[str, object]:
    ordered = _run_point(hub, latency, workload, seed)
    baseline = _run_point(hub, latency, _strip_ordering(workload), seed)
    return {
        "family": family,
        "param_name": param_name,
        "param_value": param_value,
        "throughput_tps": ordered["throughput_tps"],
        "baseline_throughput_tps": baseline["throughput_tps"],
        "normalized_throughput": ordered["throughput_tps"] / max(baseline["throughput_tps"], 1.0),
        "avg_latency_ns": ordered["avg_latency_ns"],
        "p99_latency_ns": ordered["p99_latency_ns"],
        "avg_release_drain_ns": ordered.get("avg_release_drain_ns", 0.0),
        "avg_acquire_hold_ns": ordered.get("avg_acquire_hold_ns", 0.0),
        "avg_outstanding": ordered.get("avg_outstanding", 0.0),
        "workload": workload.name,
        "ooo_enabled": int(hub.ooo_enable and hub.ooo_runtime_enable),
    }


def generate_rows() -> list[dict[str, object]]:
    rows: list[dict[str, object]] = []
    fixed = LatencyModelConfig(kind=LatencyKind.FIXED, fixed_read_ns=8.0, fixed_write_ns=4.0)
    uniform = LatencyModelConfig(
        kind=LatencyKind.UNIFORM,
        uniform_read_min_ns=4.0,
        uniform_read_max_ns=50.0,
        uniform_write_min_ns=4.0,
        uniform_write_max_ns=8.0,
    )
    release_points = (0.0, 0.02, 0.05, 0.10, 0.20, 0.50)
    acquire_points = (0.0, 0.02, 0.05, 0.10, 0.20)
    for idx, ratio in enumerate(release_points):
        rows.append(
            _row(
                "release_shallow_scan",
                "release_ratio",
                ratio,
                single_word(total_transactions=1200).clone(
                    read_ratio=0.0,
                    offered_rate=2.0,
                    order_release_ratio=ratio,
                ),
                HubConfig(),
                fixed,
                900 + idx,
            )
        )
        rows.append(
            _row(
                "release_deep_scan",
                "release_ratio",
                ratio,
                single_word(total_transactions=800).clone(
                    read_ratio=0.0,
                    length_mode="fixed",
                    length_min=64,
                    length_max=64,
                    offered_rate=0.80,
                    order_release_ratio=ratio,
                ),
                HubConfig(),
                fixed,
                930 + idx,
            )
        )
    for idx, ratio in enumerate(acquire_points):
        rows.append(
            _row(
                "acquire_scan",
                "acquire_ratio",
                ratio,
                single_word(total_transactions=1200).clone(
                    read_ratio=1.0,
                    offered_rate=2.0,
                    order_acquire_ratio=ratio,
                ),
                HubConfig(),
                fixed,
                960 + idx,
            )
        )
    for idx, domain_count in enumerate((1, 2, 4, 8)):
        weight = tuple(1.0 / domain_count for _ in range(domain_count))
        ratio = tuple(0.05 for _ in range(domain_count))
        rows.append(
            _row(
                "domain_scaling_ooo",
                "domains",
                float(domain_count),
                uniform_rw(total_transactions=1400).clone(
                    offered_rate=1.0,
                    read_ratio=0.5,
                    order_domain_weights=weight,
                    order_domain_release_ratio=ratio,
                    order_domain_acquire_ratio=ratio,
                ),
                HubConfig(ooo_enable=True, ooo_runtime_enable=True),
                uniform,
                990 + idx,
            )
        )
    return rows


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Generate ordering parameter scans")
    parser.add_argument(
        "--csv-dir",
        default=str(ROOT / "results" / "csv"),
        help="CSV output directory",
    )
    args = parser.parse_args(argv)
    rows = generate_rows()
    append_rows(Path(args.csv_dir) / "ordering_scan.csv", rows)
    print(f"generated {len(rows)} ordering scan points", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
