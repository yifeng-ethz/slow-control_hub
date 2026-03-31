from __future__ import annotations

from collections import Counter
from statistics import mean

import numpy as np

from include.sc_hub_tlm_types import Route, TxState

from .sc_hub_buffer import ScHubBufferModel


class PerfCollector:
    def __init__(self) -> None:
        self.latencies_ns: list[float] = []
        self.ext_latencies_ns: list[float] = []
        self.int_latencies_ns: list[float] = []
        self.transaction_rows: list[dict[str, object]] = []
        self.credit_trace: list[dict[str, object]] = []
        self.outstanding_trace: list[dict[str, object]] = []
        self.ord_domain_trace: list[dict[str, object]] = []
        self.latency_cdf_points: list[dict[str, object]] = []
        self.credit_stalls = 0
        self.admission_rejects: Counter[str] = Counter()
        self.atomic_lock_hist_ns: list[float] = []
        self.ooo_reorders = 0
        self.release_drain_ns: list[float] = []
        self.acquire_hold_ns: list[float] = []
        self.completed = 0
        self.completed_words = 0
        self.first_arrival_ns: float | None = None
        self.last_done_ns: float | None = None

    def note_arrival(self, arrival_ns: float) -> None:
        if self.first_arrival_ns is None or arrival_ns < self.first_arrival_ns:
            self.first_arrival_ns = arrival_ns

    def note_admission_reject(self, reason: str) -> None:
        self.admission_rejects[reason] += 1

    def note_credit_stall(self) -> None:
        self.credit_stalls += 1

    def note_credit_utilization(self, time_ns: float, used: int, total: int) -> None:
        util = (used / total) if total else 0.0
        self.credit_trace.append({"time_ns": time_ns, "used": used, "total": total, "utilization": util})

    def note_outstanding(self, time_ns: float, ext_active: int, int_active: int) -> None:
        self.outstanding_trace.append(
            {
                "time_ns": time_ns,
                "ext_active": ext_active,
                "int_active": int_active,
                "total_active": ext_active + int_active,
            }
        )

    def note_ord_domains(self, time_ns: float, rows: list[dict[str, object]]) -> None:
        for row in rows:
            active = (
                int(row["outstanding_txns"]) > 0
                or int(row.get("accepted_writes", 0)) > 0
                or int(row["outstanding_writes"]) > 0
                or bool(row["release_pending"])
                or bool(row["acquire_pending"])
                or bool(row["younger_blocked"])
            )
            if not active:
                continue
            self.ord_domain_trace.append({"time_ns": time_ns, **row})

    def note_atomic_lock(self, duration_ns: float) -> None:
        self.atomic_lock_hist_ns.append(duration_ns)

    def note_ooo_reorder(self) -> None:
        self.ooo_reorders += 1

    def note_tx_done(self, tx: TxState, done_ns: float, buffers: ScHubBufferModel) -> None:
        latency_ns = done_ns - tx.command.arrival_ns
        self.completed += 1
        self.completed_words += tx.command.length
        self.last_done_ns = done_ns if self.last_done_ns is None else max(self.last_done_ns, done_ns)
        self.latencies_ns.append(latency_ns)
        if tx.command.route == Route.EXT:
            self.ext_latencies_ns.append(latency_ns)
        else:
            self.int_latencies_ns.append(latency_ns)
        self.transaction_rows.append(
            {
                "txn_id": tx.command.seq,
                "arrival_ns": tx.command.arrival_ns,
                "route": tx.command.route.value,
                "op": tx.command.op.value,
                "length": tx.command.length,
                "atomic": int(tx.command.atomic_flag),
                "dispatch_ns": tx.dispatch_ns,
                "complete_ns": tx.complete_ns,
                "reply_start_ns": tx.reply_start_ns,
                "reply_done_ns": tx.reply_done_ns,
                "latency_ns": latency_ns,
                "bus_latency_ns": tx.bus_latency_ns,
                "service_latency_ns": tx.service_latency_ns,
                "payload_hops": tx.payload_access_hops,
                "frag_cost": buffers.aggregate_frag_cost(),
                "free_count": buffers.aggregate_free_count(),
                "peak_used": buffers.aggregate_peak_used(),
                "alloc_time_ns": tx.alloc_latency_ns_total,
                "order": tx.command.order.value,
                "ord_dom_id": tx.command.ord_dom_id,
                "ord_epoch": tx.command.ord_epoch,
                "ord_scope": tx.command.ord_scope,
                "release_drain_ns": tx.release_drain_ns,
                "acquire_hold_ns": tx.acquire_hold_ns,
                "response": tx.response.value,
            }
        )
        if tx.command.order.value == "release":
            self.release_drain_ns.append(tx.release_drain_ns)
        if tx.command.order.value == "acquire":
            self.acquire_hold_ns.append(tx.acquire_hold_ns)

    def basic_summary(self) -> dict[str, float]:
        duration_ns = 0.0
        if self.first_arrival_ns is not None and self.last_done_ns is not None:
            duration_ns = max(self.last_done_ns - self.first_arrival_ns, 1.0)
        throughput_tps = self.completed / (duration_ns * 1e-9) if duration_ns else 0.0
        words_per_s = self.completed_words / (duration_ns * 1e-9) if duration_ns else 0.0
        return {
            "completed": float(self.completed),
            "throughput_tps": throughput_tps,
            "words_per_s": words_per_s,
            "avg_latency_ns": self._avg(self.latencies_ns),
            "p50_latency_ns": self._percentile(self.latencies_ns, 50),
            "p99_latency_ns": self._percentile(self.latencies_ns, 99),
            "max_latency_ns": max(self.latencies_ns) if self.latencies_ns else 0.0,
            "int_avg_latency_ns": self._avg(self.int_latencies_ns),
            "int_max_latency_ns": max(self.int_latencies_ns) if self.int_latencies_ns else 0.0,
            "credit_stall_rate": self.credit_stalls / max(self.completed, 1),
            "avg_credit_utilization": self._avg([row["utilization"] for row in self.credit_trace]),
            "peak_credit_utilization": max((row["utilization"] for row in self.credit_trace), default=0.0),
            "avg_outstanding": self._avg([row["total_active"] for row in self.outstanding_trace]),
            "peak_outstanding": max((row["total_active"] for row in self.outstanding_trace), default=0.0),
            "ooo_reorders": float(self.ooo_reorders),
            "atomic_lock_avg_ns": self._avg(self.atomic_lock_hist_ns),
            "avg_release_drain_ns": self._avg(self.release_drain_ns),
            "avg_acquire_hold_ns": self._avg(self.acquire_hold_ns),
            "max_release_drain_ns": max(self.release_drain_ns) if self.release_drain_ns else 0.0,
            "max_acquire_hold_ns": max(self.acquire_hold_ns) if self.acquire_hold_ns else 0.0,
            "release_count": float(len(self.release_drain_ns)),
            "acquire_count": float(len(self.acquire_hold_ns)),
        }

    def latency_cdf_rows(self, experiment_id: str, tag: str) -> list[dict[str, object]]:
        if not self.latencies_ns:
            return []
        values = sorted(self.latencies_ns)
        rows: list[dict[str, object]] = []
        for idx, value in enumerate(values, start=1):
            rows.append(
                {
                    "experiment": experiment_id,
                    "tag": tag,
                    "latency_ns": value,
                    "cdf": idx / len(values),
                }
            )
        return rows

    @staticmethod
    def _avg(values: list[float]) -> float:
        return float(mean(values)) if values else 0.0

    @staticmethod
    def _percentile(values: list[float], pct: float) -> float:
        if not values:
            return 0.0
        return float(np.percentile(values, pct))
