#!/usr/bin/env python3
from __future__ import annotations

import argparse
import math
import statistics
import sys
from dataclasses import dataclass, replace
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from include.sc_hub_tlm_config import (
    AddressLatencyRegion,
    ExperimentSpec,
    HubConfig,
    LatencyModelConfig,
    WorkloadConfig,
)
from include.sc_hub_tlm_types import LatencyKind, OpType, OrderType, Route, SCCommand
from scripts.run_experiment import append_rows, run_commands


FIELD_HUB = HubConfig()
FIELD_LATENCY = LatencyModelConfig(
    kind=LatencyKind.ADDRESS,
    address_regions=(
        AddressLatencyRegion("scratch", 0x0000, 0x03FF, "fixed", 2.0, 2.0),
        AddressLatencyRegion("frame_rcv", 0x8000, 0x87FF, "uniform", 4.0, 12.0),
        AddressLatencyRegion("mts_proc", 0x9000, 0x91FF, "uniform", 4.0, 10.0),
        AddressLatencyRegion("ring_buf_cam", 0xA000, 0xA7FF, "uniform", 8.0, 20.0),
        AddressLatencyRegion("feb_frame_asm", 0xB000, 0xB1FF, "uniform", 5.0, 14.0),
        AddressLatencyRegion("histogram", 0xC000, 0xC1FF, "uniform", 6.0, 16.0),
        AddressLatencyRegion("control_csr", 0xFC00, 0xFC1F, "fixed", 3.0, 3.0),
        AddressLatencyRegion("internal_csr", 0xFE80, 0xFE9F, "fixed", 2.0, 2.0),
        AddressLatencyRegion("unmapped", 0x0000, 0xFFFF, "fixed", 50.0, 50.0, True),
    ),
)
FIELD_WORKLOAD = WorkloadConfig(
    name="field_realistic",
    total_transactions=1,
    offered_rate=0.0,
    read_ratio=1.0,
    int_ratio=0.0,
)

HISTOGRAM_BASE = 0x00C000
CONTROL_CSR_BASE = 0x00FC00
SCRATCH_PAD_BASE = 0x000000

WINDOW_CHUNK_WORDS = 64
HISTOGRAM_WORDS = 256
CONFIG_BITS = 2662
CONFIG_WORDS = math.ceil(CONFIG_BITS / 32)
ASIC_COUNT = 8

FLOW0_DOMAIN = 1
FLOW1_DOMAIN = 2
FLOW2_DOMAIN = 3

FLOW_GAP_NS = 8.0
FLOW0_OFFSET_NS = 0.0
FLOW1_OFFSET_NS = 24.0
FLOW2_OFFSET_NS = 48.0
POLL_GAP_NS = 120.0
SERIAL_PACKET_OVERHEAD_NS = 5.0

DATAPATH_WINDOWS = (
    ("frame_rcv", 0x008000, 8, 256),
    ("mts_proc", 0x009000, 2, 256),
    ("ring_buf_cam", 0x00A000, 8, 256),
    ("feb_frame_asm", 0x00B000, 2, 256),
)


@dataclass(frozen=True, slots=True)
class ScenarioConfig:
    scenario_id: str
    description: str
    period_ns: float
    window_count: int
    config_windows: tuple[int, ...]
    profile: str = "field"


SCENARIOS = (
    ScenarioConfig(
        scenario_id="literal_sparse",
        description="Literal field cadence: histogram and datapath sweeps every second, one 8-ASIC config burst after 180 seconds",
        period_ns=1_000_000_000.0,
        window_count=181,
        config_windows=(180,),
    ),
    ScenarioConfig(
        scenario_id="compressed_overlap",
        description="Compressed maintenance window: same burst shapes packed into 20 us windows so overlap is visible",
        period_ns=20_000.0,
        window_count=32,
        config_windows=tuple(range(32)),
    ),
    ScenarioConfig(
        scenario_id="positive_control",
        description="Positive-control mix: background config writes plus short frame_rcv reads that can benefit from OoO",
        period_ns=20_000.0,
        window_count=32,
        config_windows=tuple(range(32)),
        profile="positive_control",
    ),
)
OVERLAP_SCAN_PERIODS_NS = (4_000.0, 5_000.0, 6_000.0, 8_000.0, 12_000.0, 20_000.0, 40_000.0)
FIELD_OUTPUT_FILES = (
    "field_config_summary.csv",
    "field_credit_trace.csv",
    "field_flow_summary.csv",
    "field_ord_domain_trace.csv",
    "field_outstanding_trace.csv",
    "field_overlap_scan.csv",
    "field_scenarios.csv",
    "field_summary.csv",
    "field_transactions.csv",
)


def build_spec(scenario: ScenarioConfig) -> ExperimentSpec:
    return ExperimentSpec(
        experiment_id=f"FIELD-{scenario.scenario_id}",
        category="field",
        description=scenario.description,
        mode="field",
        hub=FIELD_HUB.clone(),
        workload=FIELD_WORKLOAD.clone(name=scenario.scenario_id),
        latency=FIELD_LATENCY.clone(),
        seed=2400,
    )


def payload_words(seed: int, length: int) -> list[int]:
    words: list[int] = []
    for idx in range(length):
        words.append(((seed * 0x1F123BB5) ^ (idx * 0x9E3779B9) ^ 0xA5A55A5A) & 0xFFFFFFFF)
    return words


def chunk_window(
    seq: int,
    *,
    arrival_ns: float,
    route: Route,
    op: OpType,
    base_addr: int,
    total_words: int,
    gap_ns: float,
    order: OrderType,
    ord_dom_id: int,
    metadata: dict[str, object],
    payload_seed: int = 0,
    atomic_flag: bool = False,
    atomic_mask: int = 0xFFFFFFFF,
    atomic_modify: int = 0,
) -> tuple[int, list[SCCommand]]:
    commands: list[SCCommand] = []
    words_done = 0
    chunk_index = 0
    arrival_cursor = arrival_ns
    while words_done < total_words:
        chunk_words = min(WINDOW_CHUNK_WORDS, total_words - words_done)
        cmd_metadata = dict(metadata)
        cmd_metadata.update(
            {
                "chunk_index": chunk_index,
                "chunk_words": chunk_words,
                "burst_words_total": total_words,
            }
        )
        cmd = SCCommand(
            seq=seq,
            arrival_ns=arrival_cursor,
            route=route,
            op=op,
            address=base_addr + words_done,
            length=chunk_words,
            order=order,
            ord_dom_id=ord_dom_id,
            ord_epoch=chunk_index,
            atomic_flag=atomic_flag,
            atomic_mask=atomic_mask,
            atomic_modify=atomic_modify,
            payload_words=payload_words(payload_seed + seq, chunk_words) if op == OpType.WRITE else [],
            metadata=cmd_metadata,
        )
        commands.append(cmd)
        words_done += chunk_words
        seq += 1
        chunk_index += 1
        arrival_cursor += max(gap_ns, float(chunk_words) + SERIAL_PACKET_OVERHEAD_NS)
    return seq, commands


def build_histogram_flow(seq: int, window_idx: int, window_start_ns: float) -> tuple[int, list[SCCommand]]:
    metadata = {
        "scenario_flow": "flow0",
        "flow_name": "histogram",
        "phase": "histogram_read",
        "window_idx": window_idx,
        "slave": "histogram",
    }
    return chunk_window(
        seq,
        arrival_ns=window_start_ns + FLOW0_OFFSET_NS,
        route=Route.EXT,
        op=OpType.READ,
        base_addr=HISTOGRAM_BASE,
        total_words=HISTOGRAM_WORDS,
        gap_ns=FLOW_GAP_NS,
        order=OrderType.RELAXED,
        ord_dom_id=FLOW0_DOMAIN,
        metadata=metadata,
    )


def build_datapath_flow(seq: int, window_idx: int, window_start_ns: float) -> tuple[int, list[SCCommand]]:
    commands: list[SCCommand] = []
    cursor_ns = window_start_ns + FLOW1_OFFSET_NS
    for slave_name, base_addr, count, words_per_instance in DATAPATH_WINDOWS:
        for instance in range(count):
            seq, chunks = chunk_window(
                seq,
                arrival_ns=cursor_ns,
                route=Route.EXT,
                op=OpType.READ,
                base_addr=base_addr + instance * words_per_instance,
                total_words=words_per_instance,
                gap_ns=FLOW_GAP_NS,
                order=OrderType.RELAXED,
                ord_dom_id=FLOW1_DOMAIN,
                metadata={
                    "scenario_flow": "flow1",
                    "flow_name": "datapath_snapshot",
                    "phase": "datapath_read",
                    "window_idx": window_idx,
                    "slave": slave_name,
                    "slave_instance": instance,
                },
            )
            commands.extend(chunks)
            cursor_ns = chunks[-1].arrival_ns + float(chunks[-1].length) + SERIAL_PACKET_OVERHEAD_NS
    return seq, commands


def build_config_flow(seq: int, window_idx: int, window_start_ns: float) -> tuple[int, list[SCCommand]]:
    commands: list[SCCommand] = []
    cursor_ns = window_start_ns + FLOW2_OFFSET_NS
    scratch_stride = 96
    ctrl_progress_base = CONTROL_CSR_BASE + 0x10
    ctrl_start_base = CONTROL_CSR_BASE + 0x00
    for asic_idx in range(ASIC_COUNT):
        scratch_base = SCRATCH_PAD_BASE + asic_idx * scratch_stride
        seq, scratch_cmds = chunk_window(
            seq,
            arrival_ns=cursor_ns,
            route=Route.EXT,
            op=OpType.WRITE,
            base_addr=scratch_base,
            total_words=CONFIG_WORDS,
            gap_ns=FLOW_GAP_NS,
            order=OrderType.RELAXED,
            ord_dom_id=FLOW2_DOMAIN,
            metadata={
                "scenario_flow": "flow2",
                "flow_name": "config_burst",
                "phase": "scratch_write",
                "window_idx": window_idx,
                "asic_idx": asic_idx,
                "slave": "scratch",
            },
            payload_seed=asic_idx + window_idx * 31,
        )
        commands.extend(scratch_cmds)
        cursor_ns = scratch_cmds[-1].arrival_ns + float(scratch_cmds[-1].length) + SERIAL_PACKET_OVERHEAD_NS

        start_cmd = SCCommand(
            seq=seq,
            arrival_ns=cursor_ns,
            route=Route.EXT,
            op=OpType.WRITE,
            address=ctrl_start_base + asic_idx,
            length=1,
            order=OrderType.RELEASE,
            ord_dom_id=FLOW2_DOMAIN,
            ord_epoch=0x40 + asic_idx,
            payload_words=[1],
            metadata={
                "scenario_flow": "flow2",
                "flow_name": "config_burst",
                "phase": "cfg_start",
                "window_idx": window_idx,
                "asic_idx": asic_idx,
                "slave": "control_csr",
            },
        )
        commands.append(start_cmd)
        seq += 1
        cursor_ns += 1.0 + SERIAL_PACKET_OVERHEAD_NS

        for poll_idx in range(4):
            poll_order = OrderType.ACQUIRE if poll_idx == 3 else OrderType.RELAXED
            poll_cmd = SCCommand(
                seq=seq,
                arrival_ns=cursor_ns + poll_idx * POLL_GAP_NS,
                route=Route.EXT,
                op=OpType.READ,
                address=ctrl_progress_base + asic_idx,
                length=1,
                order=poll_order,
                ord_dom_id=FLOW2_DOMAIN,
                ord_epoch=0x60 + poll_idx,
                atomic_flag=True,
                atomic_mask=0,
                atomic_modify=0,
                metadata={
                    "scenario_flow": "flow2",
                    "flow_name": "config_burst",
                    "phase": "cfg_poll",
                    "window_idx": window_idx,
                    "asic_idx": asic_idx,
                    "poll_idx": poll_idx,
                    "slave": "control_csr",
                },
            )
            commands.append(poll_cmd)
            seq += 1
        cursor_ns = commands[-1].arrival_ns + 1.0 + SERIAL_PACKET_OVERHEAD_NS
    return seq, commands


def build_scenario_commands(scenario: ScenarioConfig) -> list[SCCommand]:
    if scenario.profile == "positive_control":
        return build_positive_control_commands(scenario)
    seq = 0
    commands: list[SCCommand] = []
    config_windows = set(scenario.config_windows)
    for window_idx in range(scenario.window_count):
        window_start_ns = float(window_idx) * scenario.period_ns
        seq, hist_cmds = build_histogram_flow(seq, window_idx, window_start_ns)
        seq, datapath_cmds = build_datapath_flow(seq, window_idx, window_start_ns)
        commands.extend(hist_cmds)
        commands.extend(datapath_cmds)
        if window_idx in config_windows:
            seq, cfg_cmds = build_config_flow(seq, window_idx, window_start_ns)
            commands.extend(cfg_cmds)
    return commands


def build_positive_control_commands(scenario: ScenarioConfig) -> list[SCCommand]:
    seq = 0
    commands: list[SCCommand] = []
    for window_idx in range(scenario.window_count):
        window_start_ns = float(window_idx) * scenario.period_ns
        cursor_ns = window_start_ns + FLOW2_OFFSET_NS
        scratch_stride = 96
        for asic_idx in range(ASIC_COUNT):
            scratch_base = SCRATCH_PAD_BASE + asic_idx * scratch_stride
            seq, scratch_cmds = chunk_window(
                seq,
                arrival_ns=cursor_ns,
                route=Route.EXT,
                op=OpType.WRITE,
                base_addr=scratch_base,
                total_words=CONFIG_WORDS,
                gap_ns=FLOW_GAP_NS,
                order=OrderType.RELAXED,
                ord_dom_id=FLOW2_DOMAIN,
                metadata={
                    "scenario_flow": "flowA",
                    "flow_name": "cfg_background",
                    "phase": "scratch_write",
                    "window_idx": window_idx,
                    "asic_idx": asic_idx,
                    "slave": "scratch",
                },
                payload_seed=asic_idx + window_idx * 53,
            )
            commands.extend(scratch_cmds)
            cursor_ns = scratch_cmds[-1].arrival_ns + float(scratch_cmds[-1].length) + SERIAL_PACKET_OVERHEAD_NS

        quick_read_count = 40
        quick_gap_ns = 200.0
        for read_idx in range(quick_read_count):
            cmd = SCCommand(
                seq=seq,
                arrival_ns=window_start_ns + 120.0 + read_idx * quick_gap_ns,
                route=Route.EXT,
                op=OpType.READ,
                address=0x008000 + (read_idx % 16),
                length=1,
                order=OrderType.RELAXED,
                ord_dom_id=FLOW1_DOMAIN,
                metadata={
                    "scenario_flow": "flowB",
                    "flow_name": "frame_status",
                    "phase": "quick_read",
                    "window_idx": window_idx,
                    "slave": "frame_rcv",
                },
            )
            commands.append(cmd)
            seq += 1
    return commands


def integrate_active_time(trace_rows: list[dict[str, object]]) -> float:
    if len(trace_rows) < 2:
        return 0.0
    rows = sorted(trace_rows, key=lambda row: float(row["time_ns"]))
    active_ns = 0.0
    for current, nxt in zip(rows, rows[1:]):
        if float(current.get("total_active", 0)) > 0.0:
            active_ns += max(float(nxt["time_ns"]) - float(current["time_ns"]), 0.0)
    return active_ns


def percentile(values: list[float], frac: float) -> float:
    if not values:
        return 0.0
    ordered = sorted(values)
    idx = min(len(ordered) - 1, max(0, int(round(frac * (len(ordered) - 1)))))
    return ordered[idx]


def summarize_by_flow(
    scenario: ScenarioConfig,
    run_tag: str,
    rows: list[dict[str, object]],
) -> list[dict[str, object]]:
    grouped: dict[tuple[str, str], list[dict[str, object]]] = {}
    for row in rows:
        key = (str(row["flow_name"]), str(row["phase"]))
        grouped.setdefault(key, []).append(row)
    summary_rows: list[dict[str, object]] = []
    for (flow_name, phase), group in sorted(grouped.items()):
        latencies = [float(row["latency_ns"]) for row in group]
        summary_rows.append(
            {
                "scenario_id": scenario.scenario_id,
                "run_tag": run_tag,
                "flow_name": flow_name,
                "phase": phase,
                "transactions": len(group),
                "avg_latency_ns": statistics.fmean(latencies),
                "p50_latency_ns": percentile(latencies, 0.50),
                "p95_latency_ns": percentile(latencies, 0.95),
                "p99_latency_ns": percentile(latencies, 0.99),
                "max_latency_ns": max(latencies),
            }
        )
    return summary_rows


def summarize_config_windows(
    scenario: ScenarioConfig,
    run_tag: str,
    rows: list[dict[str, object]],
) -> list[dict[str, object]]:
    grouped: dict[tuple[int, int], list[dict[str, object]]] = {}
    for row in rows:
        if row.get("flow_name") != "config_burst":
            continue
        key = (int(row["window_idx"]), int(row["asic_idx"]))
        grouped.setdefault(key, []).append(row)
    summary_rows: list[dict[str, object]] = []
    for (window_idx, asic_idx), group in sorted(grouped.items()):
        arrivals = [float(row["arrival_ns"]) for row in group]
        replies = [float(row["reply_done_ns"]) for row in group if row.get("reply_done_ns") not in ("", None)]
        if not replies:
            continue
        summary_rows.append(
            {
                "scenario_id": scenario.scenario_id,
                "run_tag": run_tag,
                "window_idx": window_idx,
                "asic_idx": asic_idx,
                "config_makespan_ns": max(replies) - min(arrivals),
                "cfg_poll_p99_ns": percentile(
                    [float(row["latency_ns"]) for row in group if row.get("phase") == "cfg_poll"],
                    0.99,
                ),
            }
        )
    return summary_rows


def decorate_transaction_rows(
    scenario: ScenarioConfig,
    run_tag: str,
    commands: list[SCCommand],
    tx_rows: list[dict[str, object]],
) -> list[dict[str, object]]:
    by_seq = {cmd.seq: cmd for cmd in commands}
    rows: list[dict[str, object]] = []
    for tx_row in tx_rows:
        seq = int(tx_row["txn_id"])
        cmd = by_seq[seq]
        row = dict(tx_row)
        row.update(cmd.metadata)
        row.update(
            {
                "scenario_id": scenario.scenario_id,
                "scenario_description": scenario.description,
                "run_tag": run_tag,
                "command_order": seq,
                "address_hex": f"0x{cmd.address:06X}",
                "arrival_s": cmd.arrival_ns / 1e9,
                "window_start_ns": float(row["window_idx"]) * scenario.period_ns,
                "busy_period_ns": scenario.period_ns,
            }
        )
        rows.append(row)
    return rows


def run_scenario(scenario: ScenarioConfig, csv_dir: Path) -> None:
    spec = build_spec(scenario)
    commands = build_scenario_commands(scenario)
    append_rows(
        csv_dir / "field_scenarios.csv",
        [
            {
                "scenario_id": scenario.scenario_id,
                "description": scenario.description,
                "period_ns": scenario.period_ns,
                "window_count": scenario.window_count,
                "config_windows": ",".join(str(idx) for idx in scenario.config_windows),
                "transaction_count": len(commands),
            }
        ],
    )

    for run_tag, hub_cfg in (
        ("ino", spec.hub.clone(ooo_enable=False, ooo_runtime_enable=False)),
        ("ooo", spec.hub.clone(ooo_enable=True, ooo_runtime_enable=True)),
    ):
        _, perf, summary = run_commands(
            spec,
            commands,
            run_tag=run_tag,
            hub=hub_cfg,
            latency=spec.latency,
            workload_name=scenario.scenario_id,
        )
        tx_rows = decorate_transaction_rows(scenario, run_tag, commands, perf.transaction_rows)
        flow_summary = summarize_by_flow(scenario, run_tag, tx_rows)
        config_summary = summarize_config_windows(scenario, run_tag, tx_rows)
        busy_time_ns = integrate_active_time(perf.outstanding_trace)
        schedule_span_ns = (
            max(float(row["reply_done_ns"]) for row in tx_rows) - min(float(row["arrival_ns"]) for row in tx_rows)
            if tx_rows
            else 0.0
        )
        summary.update(
            {
                "scenario_id": scenario.scenario_id,
                "scenario_description": scenario.description,
                "run_tag": run_tag,
                "window_count": scenario.window_count,
                "period_ns": scenario.period_ns,
                "config_window_count": len(scenario.config_windows),
                "busy_time_ns": busy_time_ns,
                "schedule_span_ns": schedule_span_ns,
                "duty_cycle": (busy_time_ns / schedule_span_ns) if schedule_span_ns else 0.0,
                "model_limitations": "poll_status_value_is_static; atomic_only_models_bus_lock_and_readback",
            }
        )

        append_rows(csv_dir / "field_transactions.csv", tx_rows)
        append_rows(csv_dir / "field_summary.csv", [summary])
        append_rows(csv_dir / "field_flow_summary.csv", flow_summary)
        append_rows(csv_dir / "field_config_summary.csv", config_summary)
        append_rows(
            csv_dir / "field_credit_trace.csv",
            [{"scenario_id": scenario.scenario_id, "run_tag": run_tag, **row} for row in perf.credit_trace],
        )
        append_rows(
            csv_dir / "field_outstanding_trace.csv",
            [{"scenario_id": scenario.scenario_id, "run_tag": run_tag, **row} for row in perf.outstanding_trace],
        )
        append_rows(
            csv_dir / "field_ord_domain_trace.csv",
            [{"scenario_id": scenario.scenario_id, "run_tag": run_tag, **row} for row in perf.ord_domain_trace],
        )
def run_overlap_scan(csv_dir: Path) -> None:
    base = next(scenario for scenario in SCENARIOS if scenario.scenario_id == "compressed_overlap")
    rows: list[dict[str, object]] = []
    for period_ns in OVERLAP_SCAN_PERIODS_NS:
        scenario = replace(
            base,
            scenario_id=f"scan_{int(period_ns)}ns",
            description=f"Compressed overlap scan at {period_ns:.0f} ns period",
            period_ns=period_ns,
            window_count=8,
            config_windows=tuple(range(8)),
        )
        spec = build_spec(scenario)
        commands = build_scenario_commands(scenario)
        phase_rows: dict[str, dict[str, float]] = {}
        for run_tag, hub_cfg in (
            ("ino", spec.hub.clone(ooo_enable=False, ooo_runtime_enable=False)),
            ("ooo", spec.hub.clone(ooo_enable=True, ooo_runtime_enable=True)),
        ):
            _, perf, summary = run_commands(
                spec,
                commands,
                run_tag=run_tag,
                hub=hub_cfg,
                latency=spec.latency,
                workload_name=scenario.scenario_id,
            )
            tx_rows = decorate_transaction_rows(scenario, run_tag, commands, perf.transaction_rows)
            phase_rows[run_tag] = {
                "cfg_poll_p99_ns": percentile(
                    [float(row["latency_ns"]) for row in tx_rows if row.get("phase") == "cfg_poll"],
                    0.99,
                ),
                "frame_rcv_p99_ns": percentile(
                    [
                        float(row["latency_ns"])
                        for row in tx_rows
                        if row.get("phase") == "datapath_read" and row.get("slave") == "frame_rcv"
                    ],
                    0.99,
                ),
            }
            rows.append(
                {
                    "period_ns": period_ns,
                    "run_tag": run_tag,
                    "avg_latency_ns": summary["avg_latency_ns"],
                    "p99_latency_ns": summary["p99_latency_ns"],
                    "throughput_tps": summary["throughput_tps"],
                    "ooo_reorders": summary["ooo_reorders"],
                    **phase_rows[run_tag],
                }
            )
    append_rows(csv_dir / "field_overlap_scan.csv", rows)


def reset_output_dir(csv_dir: Path) -> None:
    for name in FIELD_OUTPUT_FILES:
        path = csv_dir / name
        if path.exists():
            path.unlink()


def main() -> int:
    parser = argparse.ArgumentParser(description="Run explicit field-workload TLM scenarios")
    parser.add_argument(
        "--csv-dir",
        default="results/field_review_v4/csv",
        help="Output CSV directory",
    )
    parser.add_argument(
        "--append",
        action="store_true",
        help="Append into an existing CSV directory instead of replacing the field-review files",
    )
    args = parser.parse_args()

    csv_dir = Path(args.csv_dir)
    csv_dir.mkdir(parents=True, exist_ok=True)
    if not args.append:
        reset_output_dir(csv_dir)
    for scenario in SCENARIOS:
        run_scenario(scenario, csv_dir)
    run_overlap_scan(csv_dir)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
