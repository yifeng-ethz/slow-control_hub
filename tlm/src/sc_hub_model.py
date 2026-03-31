from __future__ import annotations

import heapq
import itertools
from collections import deque
from dataclasses import dataclass

from include.sc_hub_tlm_config import HubConfig, LatencyModelConfig
from include.sc_hub_tlm_types import OpType, ResponseCode, Route, SCCommand, TxState

from .bus_target_model import BusTargetModel
from .perf_collector import PerfCollector
from .sc_hub_admit_ctrl import ScHubAdmitCtrlModel
from .sc_hub_buffer import ScHubBufferModel
from .sc_hub_credit_mgr import ScHubCreditManagerModel
from .sc_hub_csr import ScHubCsrModel
from .sc_hub_dispatch import ScHubDispatchModel
from .sc_hub_pkt_rx_model import ScHubPktRxModel
from .sc_hub_pkt_tx_model import ScHubPktTxModel
from .sc_hub_ord_tracker import ScHubOrdTrackerModel


@dataclass(order=True)
class _Event:
    time_ns: float
    order: int
    kind: str
    seq: int = -1


class ScHubModel:
    def __init__(self, hub_cfg: HubConfig, latency_cfg: LatencyModelConfig, seed: int) -> None:
        self.hub_cfg = hub_cfg
        self.buffers = ScHubBufferModel(hub_cfg)
        self.bus = BusTargetModel(latency_cfg, seed + 101)
        self.perf = PerfCollector()
        self.pkt_rx = ScHubPktRxModel(hub_cfg)
        self.admit_ctrl = ScHubAdmitCtrlModel(hub_cfg)
        self.credit_mgr = ScHubCreditManagerModel()
        self.csr = ScHubCsrModel(ooo_ctrl_enable=hub_cfg.ooo_runtime_enable)
        self.dispatch = ScHubDispatchModel(hub_cfg)
        self.pkt_tx = ScHubPktTxModel(hub_cfg)
        self.ord_tracker = ScHubOrdTrackerModel()

        self.now_ns = 0.0
        self.events: list[_Event] = []
        self.event_counter = itertools.count()
        self.tx_states: dict[int, TxState] = {}
        self.ingress_waiting: deque[int] = deque()
        self.ingress_int_waiting: deque[int] = deque()
        self.ext_queue: deque[int] = deque()
        self.int_queue: deque[int] = deque()
        self.dispatch_order: deque[int] = deque()
        self.reply_order: deque[int] = deque()
        self.ready_replies: set[int] = set()

        self.ext_active = 0
        self.int_active = 0
        self.ext_inflight = 0
        self.int_inflight = 0
        self.ext_issue_free_ns = 0.0
        self.int_issue_free_ns = 0.0
        self.reply_engine_free_ns = 0.0
        self.ext_ordered_complete_ns = 0.0
        self.bus_locked = False

    def run(self, commands: list[SCCommand]) -> PerfCollector:
        for cmd in commands:
            self.perf.note_arrival(cmd.arrival_ns)
            tx = TxState(command=cmd, packet_ready_ns=self.pkt_rx.packet_ready_ns(cmd))
            self.tx_states[cmd.seq] = tx
            self._schedule(tx.packet_ready_ns, "arrival", cmd.seq)

        while self.events:
            event = heapq.heappop(self.events)
            self.now_ns = event.time_ns
            if event.kind == "arrival":
                self.ingress_waiting.append(event.seq)
                if self.tx_states[event.seq].command.route == Route.INT:
                    self.ingress_int_waiting.append(event.seq)
            elif event.kind == "complete":
                self._handle_complete(event.seq)
            elif event.kind == "reply_done":
                self._handle_reply_done(event.seq)
            self._progress_until_stable()

        return self.perf

    def _progress_until_stable(self) -> None:
        while True:
            progressed = False
            progressed |= self._try_admit()
            progressed |= self._try_dispatch()
            progressed |= self._try_start_reply()
            if not progressed:
                break

    def _try_admit(self) -> bool:
        progressed = False
        while self.ingress_waiting:
            seq = self.ingress_waiting[0]
            tx = self.tx_states[seq]
            admitted, reason = self.admit_ctrl.try_admit(
                tx,
                self.now_ns,
                self.buffers,
                self.ext_active,
                self.int_active,
                len(self.dispatch_order),
            )
            if not admitted and tx.command.route == Route.EXT:
                bypass_seq = self._find_internal_admit_bypass()
                if bypass_seq is not None:
                    if reason is not None:
                        self.perf.note_admission_reject(reason)
                    seq = bypass_seq
                    tx = self.tx_states[seq]
                    admitted = True
                    reason = None
            if not admitted:
                if reason is not None:
                    self.perf.note_admission_reject(reason)
                break
            self.ord_tracker.on_admit(tx)
            if self.ingress_waiting and self.ingress_waiting[0] == seq:
                self.ingress_waiting.popleft()
            else:
                self.ingress_waiting.remove(seq)
            if tx.command.route == Route.INT:
                try:
                    self.ingress_int_waiting.remove(seq)
                except ValueError:
                    pass
            if tx.command.route == Route.EXT:
                self.ext_active += 1
                self.ext_queue.append(seq)
            else:
                self.int_active += 1
                self.int_queue.append(seq)
            self.dispatch_order.append(seq)
            self.reply_order.append(seq)
            self._sample_state()
            progressed = True
        return progressed

    def _find_internal_admit_bypass(self) -> int | None:
        for seq in self.ingress_int_waiting:
            tx = self.tx_states[seq]
            admitted, _ = self.admit_ctrl.try_admit(
                tx,
                self.now_ns,
                self.buffers,
                self.ext_active,
                self.int_active,
                len(self.dispatch_order),
            )
            if admitted:
                return seq
        return None

    def _try_dispatch(self) -> bool:
        progressed = False
        while True:
            seq = self.dispatch.next_seq(
                self.int_queue,
                self.ext_queue,
                self.dispatch_order,
                self.tx_states,
                self._can_dispatch,
                self._ooo_enabled(),
            )
            if seq is None:
                self._schedule_if_needed()
                return progressed
            tx = self.tx_states[seq]
            if tx.command.route == Route.INT:
                self._consume_seq(self.int_queue, seq, Route.INT)
                self.int_issue_free_ns = self.now_ns + self.hub_cfg.dispatch_latency_ns
                self.int_inflight += 1
            else:
                self._consume_seq(self.ext_queue, seq, Route.EXT)
                self.ext_issue_free_ns = self.now_ns + self.hub_cfg.dispatch_latency_ns
                self.ext_inflight += 1
                if tx.command.atomic_flag:
                    self.bus_locked = True

            self._issue_transaction(tx)
            progressed = True
        return progressed

    def _can_dispatch(self, tx: TxState) -> bool:
        cmd = tx.command
        ok, reason = self.ord_tracker.can_dispatch(tx, self.now_ns)
        if not ok:
            tx.note = reason or tx.note
            return False

        if cmd.route == Route.INT:
            if self.now_ns < self.int_issue_free_ns or self.int_inflight >= self.hub_cfg.int_issue_limit:
                return False
            ok, reason = self.credit_mgr.has_reply_resources(
                self.buffers, cmd.route, cmd.length if cmd.op == OpType.READ else 0
            )
            if not ok:
                if reason == "int_up_credit_empty":
                    self.perf.note_credit_stall()
                tx.note = reason or tx.note
                return False
            tx.note = ""
            return True

        if self.now_ns < self.ext_issue_free_ns or self.ext_inflight >= self.hub_cfg.ext_issue_limit:
            return False
        if self.bus_locked:
            return False
        if cmd.atomic_flag and self.ext_inflight > 0:
            return False
        ok, reason = self.credit_mgr.has_reply_resources(
            self.buffers, cmd.route, cmd.length if cmd.op == OpType.READ else 0
        )
        if not ok:
            if reason == "ext_up_credit_empty":
                self.perf.note_credit_stall()
            tx.note = reason or tx.note
            return False
        tx.note = ""
        return True

    def _issue_transaction(self, tx: TxState) -> None:
        cmd = tx.command
        tx.dispatch_ns = self.now_ns
        tx.dispatch_wait_ns = self.now_ns - (tx.admitted_ns if tx.admitted_ns is not None else self.now_ns)
        self.ord_tracker.on_dispatch(tx, self.now_ns)

        up_alloc = None
        if cmd.op == OpType.READ:
            ok, up_alloc, reason = self.credit_mgr.reserve_reply_resources(
                self.buffers, cmd.route, cmd.length
            )
            if not ok:
                raise RuntimeError(f"credit reservation failed after dispatchable check: {reason}")
        if not self.buffers.up_hdr(cmd.route).push(cmd.seq):
            if up_alloc is not None:
                self.buffers.up_pld(cmd.route).free(up_alloc.head_ptr)
            raise RuntimeError(f"reply header overflow at {cmd.route.value}")
        tx.up_payload = up_alloc
        if up_alloc is not None:
            tx.alloc_latency_ns_total += up_alloc.alloc_latency_ns

        if cmd.route == Route.INT:
            service_latency, response, data_words = self._issue_internal(tx)
            tx.bus_latency_ns = 0.0
            tx.response = response
            tx.response_words = data_words
        else:
            service_latency, response, data_words, bus_latency = self._issue_external(tx)
            tx.bus_latency_ns = bus_latency
            tx.response = response
            tx.response_words = data_words

        tx.service_latency_ns = service_latency
        completion_ns = self.now_ns + service_latency
        if cmd.route == Route.EXT and not self._ooo_enabled():
            completion_ns = max(completion_ns, self.ext_ordered_complete_ns)
            self.ext_ordered_complete_ns = completion_ns
        self._schedule(completion_ns, "complete", cmd.seq)
        self._sample_state()

    def _issue_internal(self, tx: TxState) -> tuple[float, ResponseCode, list[int]]:
        cmd = tx.command
        if cmd.op == OpType.READ:
            offset = cmd.address - 0xFE80
            response, words = self.csr.read(offset, cmd.length)
            if tx.up_payload is not None and response == ResponseCode.OK:
                hops, payload_latency = self.buffers.up_pld(cmd.route).write_chain(tx.up_payload, words)
                tx.payload_access_hops += hops
                latency = self.hub_cfg.internal_read_setup_ns + float(cmd.length) + payload_latency
            else:
                latency = self.hub_cfg.internal_read_setup_ns + float(cmd.length)
            return latency, response, words

        write_words = cmd.payload_words[:1]
        response = self.csr.write(cmd.address - 0xFE80, write_words)
        hops = 0
        payload_latency = 0.0
        if tx.down_payload is not None:
            _, hops, payload_latency = self.buffers.down_pld(cmd.route).read_chain(tx.down_payload)
        tx.payload_access_hops += hops
        return self.hub_cfg.internal_write_latency_ns + payload_latency, response, []

    def _issue_external(self, tx: TxState) -> tuple[float, ResponseCode, list[int], float]:
        cmd = tx.command
        if cmd.atomic_flag:
            bus_latency, response, old_value, _ = self.bus.atomic_rmw(
                cmd.address, cmd.atomic_mask, cmd.atomic_modify
            )
            if tx.up_payload is not None and response == ResponseCode.OK:
                hops, payload_latency = self.buffers.up_pld(cmd.route).write_chain(tx.up_payload, [old_value])
                tx.payload_access_hops += hops
                return bus_latency + payload_latency, response, [old_value], bus_latency
            return bus_latency, response, [old_value], bus_latency

        if cmd.op == OpType.READ:
            bus_latency, response, data_words = self.bus.read(cmd.address, cmd.length)
            if tx.up_payload is not None and response == ResponseCode.OK:
                hops, payload_latency = self.buffers.up_pld(cmd.route).write_chain(tx.up_payload, data_words)
                tx.payload_access_hops += hops
                return bus_latency + payload_latency, response, data_words, bus_latency
            return bus_latency, response, data_words, bus_latency

        payload_hops = 0
        payload_latency = 0.0
        data_words = cmd.payload_words
        if tx.down_payload is not None:
            data_words, payload_hops, payload_latency = self.buffers.down_pld(cmd.route).read_chain(tx.down_payload)
        tx.payload_access_hops += payload_hops
        bus_latency, response = self.bus.write(cmd.address, data_words)
        return payload_latency + bus_latency, response, [], bus_latency

    def _handle_complete(self, seq: int) -> None:
        tx = self.tx_states[seq]
        tx.complete_ns = self.now_ns
        tx.ready_for_reply = True
        self.ready_replies.add(seq)
        self.ord_tracker.on_complete(tx, self.now_ns)

        if tx.command.route == Route.EXT:
            self.ext_inflight = max(0, self.ext_inflight - 1)
            if tx.command.atomic_flag:
                self.bus_locked = False
                self.perf.note_atomic_lock(tx.service_latency_ns)
        else:
            self.int_inflight = max(0, self.int_inflight - 1)

        if tx.command.needs_payload and tx.down_payload is not None:
            self.buffers.down_pld(tx.command.route).free(tx.down_payload)
            tx.down_payload = None

        self._sample_state()

    def _try_start_reply(self) -> bool:
        if self.now_ns < self.reply_engine_free_ns:
            return False
        tx = self.pkt_tx.select_next_reply(
            self.ready_replies,
            self.reply_order,
            self.tx_states,
            self._ooo_enabled(),
        )
        if tx is None:
            return False
        head_seq = self.reply_order[0] if self.reply_order else tx.command.seq
        if self._ooo_enabled() and tx.command.seq != head_seq:
            self.perf.note_ooo_reorder()
        tx.reply_start_ns = self.now_ns
        tx.reply_scheduled = True
        self.ready_replies.discard(tx.command.seq)
        try:
            self.reply_order.remove(tx.command.seq)
        except ValueError:
            pass
        reply_latency = self.pkt_tx.reply_latency_ns(tx)
        finish_ns = self.now_ns + reply_latency
        self.reply_engine_free_ns = finish_ns
        self._schedule(finish_ns, "reply_done", tx.command.seq)
        return True

    def _handle_reply_done(self, seq: int) -> None:
        tx = self.tx_states[seq]
        tx.reply_done_ns = self.now_ns
        self.buffers.up_hdr(tx.command.route).discard(seq)
        if tx.up_payload is not None:
            self.buffers.up_pld(tx.command.route).free(tx.up_payload)
            tx.up_payload = None

        if tx.command.route == Route.EXT:
            self.ext_active = max(0, self.ext_active - 1)
        else:
            self.int_active = max(0, self.int_active - 1)
        self.perf.note_tx_done(tx, self.now_ns, self.buffers)
        self._sample_state()

    def _sample_state(self) -> None:
        self.perf.note_outstanding(self.now_ns, self.ext_active, self.int_active)
        self.perf.note_ord_domains(self.now_ns, self.ord_tracker.snapshot())
        used, total = self.buffers.upload_utilization()
        self.perf.note_credit_utilization(self.now_ns, used, total)

    def _ooo_enabled(self) -> bool:
        return bool(self.hub_cfg.ooo_enable and self.csr.ooo_ctrl_enable)

    def _consume_seq(self, queue: deque[int], seq: int, route: Route) -> None:
        try:
            queue.remove(seq)
        except ValueError:
            return
        try:
            self.dispatch_order.remove(seq)
        except ValueError:
            pass
        if route == Route.INT:
            self.buffers.int_down_hdr.discard(seq)
        else:
            self.buffers.ext_down_hdr.discard(seq)

    def _schedule_if_needed(self) -> None:
        candidates = []
        if self.int_queue and self.int_issue_free_ns > self.now_ns:
            candidates.append(self.int_issue_free_ns)
        if self.ext_queue:
            if self.ext_issue_free_ns > self.now_ns:
                candidates.append(self.ext_issue_free_ns)
        if self.ready_replies and self.reply_engine_free_ns > self.now_ns:
            candidates.append(self.reply_engine_free_ns)
        if candidates:
            self._schedule(min(candidates), "kick")

    def _schedule(self, time_ns: float, kind: str, seq: int = -1) -> None:
        heapq.heappush(self.events, _Event(time_ns, next(self.event_counter), kind, seq))
