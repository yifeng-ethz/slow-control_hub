from __future__ import annotations

from dataclasses import dataclass
from typing import Optional

from include.sc_hub_tlm_types import OpType, OrderType, TxState


@dataclass(slots=True)
class OrdDomainState:
    release_pending: bool = False
    acquire_pending: bool = False
    younger_blocked: bool = False
    accepted_writes: int = 0
    outstanding_writes: int = 0
    outstanding_txns: int = 0
    last_issued_epoch: int = 0
    last_retired_epoch: int = 0
    release_wait_start_ns: Optional[float] = None
    acquire_wait_start_ns: Optional[float] = None


class ScHubOrdTrackerModel:
    def __init__(self, domain_count: int = 16) -> None:
        self.domain_count = max(1, domain_count)
        self.domains: list[OrdDomainState] = [OrdDomainState() for _ in range(self.domain_count)]

    def can_dispatch(self, tx: TxState, now_ns: float) -> tuple[bool, str | None]:
        state = self._state(tx.command.ord_dom_id)
        cmd = tx.command

        if cmd.order == OrderType.RELEASE:
            if state.release_pending or state.acquire_pending or state.younger_blocked:
                return False, "ord_domain_blocked"
            release_credit = 1 if cmd.op == OpType.WRITE else 0
            if state.accepted_writes > release_credit or state.outstanding_writes > 0:
                if state.release_wait_start_ns is None:
                    state.release_wait_start_ns = now_ns
                return False, "ord_release_wait"

        if cmd.order == OrderType.ACQUIRE and state.younger_blocked:
            return False, "ord_domain_blocked"
        if cmd.order == OrderType.RELAXED and state.younger_blocked:
            return False, "ord_domain_blocked"

        return True, None

    def on_admit(self, tx: TxState) -> None:
        cmd = tx.command
        if cmd.op != OpType.WRITE:
            return
        state = self._state(cmd.ord_dom_id)
        state.accepted_writes += 1

    def on_dispatch(self, tx: TxState, now_ns: float) -> None:
        cmd = tx.command
        state = self._state(cmd.ord_dom_id)

        if cmd.order == OrderType.RELAXED and state.younger_blocked:
            raise AssertionError(
                f"BUG: RELAXED cmd seq={cmd.seq} dispatched in domain "
                f"{cmd.ord_dom_id} while younger_blocked=True. "
                f"can_dispatch() should have prevented this."
            )

        state.outstanding_txns += 1

        if cmd.order == OrderType.RELEASE:
            state.release_pending = True
            state.younger_blocked = True
            if state.release_wait_start_ns is not None:
                tx.release_drain_ns = max(0.0, now_ns - state.release_wait_start_ns)
            else:
                tx.release_drain_ns = 0.0
            state.release_wait_start_ns = None
            if cmd.ord_epoch > state.last_issued_epoch:
                state.last_issued_epoch = cmd.ord_epoch

        elif cmd.order == OrderType.ACQUIRE:
            state.acquire_pending = True
            state.younger_blocked = True
            if state.acquire_wait_start_ns is None:
                state.acquire_wait_start_ns = now_ns
            if cmd.ord_epoch > state.last_issued_epoch:
                state.last_issued_epoch = cmd.ord_epoch

        else:
            if cmd.ord_epoch > state.last_issued_epoch:
                state.last_issued_epoch = cmd.ord_epoch

        if cmd.op == OpType.WRITE:
            if state.accepted_writes <= 0:
                raise AssertionError(
                    f"BUG: write cmd seq={cmd.seq} in domain {cmd.ord_dom_id} "
                    "dispatched without accepted_writes tracking."
                )
            state.accepted_writes -= 1
            state.outstanding_writes += 1

    def on_complete(self, tx: TxState, now_ns: float) -> None:
        cmd = tx.command
        state = self._state(cmd.ord_dom_id)

        if cmd.op == OpType.WRITE:
            state.outstanding_writes = max(0, state.outstanding_writes - 1)

        if state.last_retired_epoch < cmd.ord_epoch:
            state.last_retired_epoch = cmd.ord_epoch

        if cmd.order == OrderType.ACQUIRE:
            tx.acquire_hold_ns = 0.0
            if state.acquire_wait_start_ns is not None:
                tx.acquire_hold_ns = now_ns - state.acquire_wait_start_ns
            state.acquire_wait_start_ns = None
            state.acquire_pending = False

        if cmd.order == OrderType.RELEASE:
            state.release_pending = False

        state.outstanding_txns = max(0, state.outstanding_txns - 1)

        if state.release_pending and state.accepted_writes == 0 and state.outstanding_writes == 0:
            state.release_pending = False

        if not state.release_pending and not state.acquire_pending:
            state.younger_blocked = False

    def _state(self, domain_id: int) -> OrdDomainState:
        return self.domains[domain_id % self.domain_count]

    def snapshot(self) -> list[dict[str, int | bool]]:
        rows: list[dict[str, int | bool]] = []
        for domain_id, state in enumerate(self.domains):
            rows.append(
                {
                    "ord_dom_id": domain_id,
                    "release_pending": state.release_pending,
                    "acquire_pending": state.acquire_pending,
                    "younger_blocked": state.younger_blocked,
                    "accepted_writes": state.accepted_writes,
                    "outstanding_writes": state.outstanding_writes,
                    "outstanding_txns": state.outstanding_txns,
                    "last_issued_epoch": state.last_issued_epoch,
                    "last_retired_epoch": state.last_retired_epoch,
                }
            )
        return rows
