from __future__ import annotations

from collections import deque

from include.sc_hub_tlm_config import HubConfig
from include.sc_hub_tlm_types import Route, TxState


class ScHubPktTxModel:
    def __init__(self, cfg: HubConfig) -> None:
        self.cfg = cfg

    def reply_latency_ns(self, tx: TxState) -> float:
        if tx.command.is_reply_suppressed:
            return 0.0
        payload_words = len(tx.response_words) if tx.command.op.value == "read" else 0
        payload_hops = tx.up_payload.pointer_hops if tx.up_payload is not None else 0
        return self.cfg.reply_assembly_base_ns + float(payload_words + payload_hops)

    def select_next_reply(
        self,
        ready_replies: set[int],
        reply_order: deque[int],
        tx_states: dict[int, TxState],
        ooo_runtime_enable: bool,
    ) -> TxState | None:
        if not ready_replies:
            return None
        if not ooo_runtime_enable:
            for seq in reply_order:
                if seq in ready_replies and not tx_states[seq].reply_scheduled:
                    return tx_states[seq]
            return None

        candidates = [
            tx_states[seq]
            for seq in ready_replies
            if not tx_states[seq].reply_scheduled
        ]
        if not candidates:
            return None
        candidates.sort(
            key=lambda tx: (
                0 if tx.command.route == Route.INT else 1,
                tx.complete_ns if tx.complete_ns is not None else float("inf"),
                tx.command.seq,
            )
        )
        return candidates[0]
