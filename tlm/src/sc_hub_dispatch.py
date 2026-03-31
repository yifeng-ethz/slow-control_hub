from __future__ import annotations

from collections import deque

from include.sc_hub_tlm_config import HubConfig
from include.sc_hub_tlm_types import OrderType, Route, TxState


class ScHubDispatchModel:
    def __init__(self, cfg: HubConfig) -> None:
        self.cfg = cfg

    def next_seq(
        self,
        int_queue: deque[int],
        ext_queue: deque[int],
        dispatch_order: deque[int],
        tx_states: dict[int, TxState],
        can_dispatch,
        ooo_reply_enabled: bool,
    ) -> int | None:
        if int_queue:
            if ooo_reply_enabled:
                candidate = self._scan_for_ready(
                    int_queue,
                    dispatch_order,
                    tx_states,
                    can_dispatch,
                )
                if candidate is not None:
                    return candidate
            elif (
                not self._blocked_by_earlier_barrier(
                    int_queue[0],
                    dispatch_order,
                    tx_states,
                )
                and can_dispatch(tx_states[int_queue[0]])
            ):
                return int_queue[0]
        if ext_queue:
            if ooo_reply_enabled:
                candidate = self._scan_for_ready(
                    ext_queue,
                    dispatch_order,
                    tx_states,
                    can_dispatch,
                )
                if candidate is not None:
                    return candidate
            elif (
                not self._blocked_by_earlier_barrier(
                    ext_queue[0],
                    dispatch_order,
                    tx_states,
                )
                and can_dispatch(tx_states[ext_queue[0]])
            ):
                return ext_queue[0]
        return None

    def _scan_for_ready(
        self,
        queue: deque[int],
        dispatch_order: deque[int],
        tx_states: dict[int, TxState],
        can_dispatch,
    ) -> int | None:
        for seq in queue:
            if self._blocked_by_earlier_barrier(seq, dispatch_order, tx_states):
                continue
            if can_dispatch(tx_states[seq]):
                return seq
        return None

    @staticmethod
    def _blocked_by_earlier_barrier(
        seq: int,
        dispatch_order: deque[int],
        tx_states: dict[int, TxState],
    ) -> bool:
        domain = tx_states[seq].command.ord_dom_id
        for older_seq in dispatch_order:
            if older_seq == seq:
                return False
            older_cmd = tx_states[older_seq].command
            if older_cmd.ord_dom_id != domain:
                continue
            if older_cmd.order in {OrderType.RELEASE, OrderType.ACQUIRE}:
                return True
        return False
