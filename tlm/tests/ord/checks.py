from __future__ import annotations

from include.sc_hub_tlm_config import AddressLatencyRegion, HubConfig, LatencyModelConfig
from include.sc_hub_tlm_types import LatencyKind, OpType, OrderType, Route, SCCommand, TxState
from include.sc_hub_tlm_workload import uniform_rw
from src.sc_hub_model import ScHubModel
from src.sc_hub_ord_tracker import ScHubOrdTrackerModel
from src.sc_pkt_source import ScPktSource


def _cmd(
    seq: int,
    arrival_ns: float,
    *,
    route: Route,
    op: OpType,
    address: int,
    order: OrderType = OrderType.RELAXED,
    ord_dom_id: int = 0,
    payload_word: int | None = None,
    atomic_flag: bool = False,
    atomic_mask: int = 0xFFFF00FF,
    atomic_modify: int = 0,
) -> SCCommand:
    payload = []
    if op == OpType.WRITE:
        payload = [payload_word if payload_word is not None else ((seq << 8) ^ address) & 0xFFFFFFFF]
    return SCCommand(
        seq=seq,
        arrival_ns=arrival_ns,
        route=route,
        op=op,
        address=address,
        length=1,
        order=order,
        ord_dom_id=ord_dom_id,
        ord_epoch=(seq + 1) & 0xFF,
        ord_scope=0,
        atomic_flag=atomic_flag,
        atomic_mask=atomic_mask,
        atomic_modify=atomic_modify,
        payload_words=payload,
    )


def _run(
    commands: list[SCCommand],
    *,
    hub: HubConfig,
    latency: LatencyModelConfig,
    seed: int = 1,
) -> ScHubModel:
    model = ScHubModel(hub, latency, seed)
    model.run(commands)
    return model


def _tx(cmd: SCCommand) -> TxState:
    return TxState(command=cmd, packet_ready_ns=cmd.arrival_ns)


def _row(check_id: str, passed: bool, effect: str, **metrics: object) -> dict[str, object]:
    return {
        "experiment": check_id,
        "passed": int(passed),
        "effect": effect,
        **metrics,
    }


def ord_c01_no_bypass() -> dict[str, object]:
    hub = HubConfig(ooo_enable=True, ooo_runtime_enable=True, ext_issue_limit=8)
    latency = LatencyModelConfig(kind=LatencyKind.FIXED, fixed_read_ns=24.0, fixed_write_ns=40.0)
    commands: list[SCCommand] = []
    seq = 0
    dom = 2
    for idx in range(4):
        commands.append(
            _cmd(
                seq,
                float(seq),
                route=Route.EXT,
                op=OpType.WRITE,
                address=0x0100 + idx,
                ord_dom_id=dom,
            )
        )
        seq += 1
    release_seq = seq
    commands.append(
        _cmd(
            seq,
            float(seq),
            route=Route.EXT,
            op=OpType.WRITE,
            address=0x0120,
            order=OrderType.RELEASE,
            ord_dom_id=dom,
            payload_word=0xAA550001,
        )
    )
    seq += 1
    younger = []
    for idx in range(4):
        younger.append(seq)
        commands.append(
            _cmd(
                seq,
                float(seq),
                route=Route.EXT,
                op=OpType.WRITE,
                address=0x0200 + idx,
                ord_dom_id=dom,
            )
        )
        seq += 1
    for idx in range(2):
        younger.append(seq)
        commands.append(
            _cmd(
                seq,
                float(seq),
                route=Route.INT,
                op=OpType.WRITE,
                address=0xFE80 + idx,
                ord_dom_id=dom,
                payload_word=0x100 + idx,
            )
        )
        seq += 1
    model = _run(commands, hub=hub, latency=latency, seed=501)
    release_tx = model.tx_states[release_seq]
    release_complete = release_tx.complete_ns or 0.0
    min_younger_dispatch = min(model.tx_states[seq_id].dispatch_ns or 0.0 for seq_id in younger)
    min_younger_complete = min(model.tx_states[seq_id].complete_ns or 0.0 for seq_id in younger)
    passed = min_younger_dispatch >= release_complete and min_younger_complete >= release_complete
    return _row(
        "ORD-C01",
        passed,
        "younger same-domain traffic stays behind the release across ext/int paths",
        release_complete_ns=release_complete,
        min_younger_dispatch_ns=min_younger_dispatch,
        min_younger_complete_ns=min_younger_complete,
    )


def ord_c02_release_waits_for_visibility() -> dict[str, object]:
    hub = HubConfig(ext_issue_limit=4, outstanding_limit=4)
    latency = LatencyModelConfig(kind=LatencyKind.FIXED, fixed_read_ns=20.0, fixed_write_ns=100.0)
    commands: list[SCCommand] = []
    dom = 3
    older = []
    for seq in range(4):
        older.append(seq)
        commands.append(
            _cmd(
                seq,
                float(seq),
                route=Route.EXT,
                op=OpType.WRITE,
                address=0x0300 + seq,
                ord_dom_id=dom,
            )
        )
    release_seq = 4
    commands.append(
        _cmd(
            release_seq,
            float(release_seq),
            route=Route.EXT,
            op=OpType.WRITE,
            address=0x0310,
            order=OrderType.RELEASE,
            ord_dom_id=dom,
            payload_word=0xCAFEBABE,
        )
    )
    model = _run(commands, hub=hub, latency=latency, seed=502)
    older_complete = max(model.tx_states[seq_id].complete_ns or 0.0 for seq_id in older)
    release_tx = model.tx_states[release_seq]
    release_dispatch = release_tx.dispatch_ns or 0.0
    release_complete = release_tx.complete_ns or 0.0
    passed = release_dispatch >= older_complete and release_complete >= older_complete
    return _row(
        "ORD-C02",
        passed,
        "release drains all older writes to visible retirement before it issues",
        older_complete_ns=older_complete,
        release_dispatch_ns=release_dispatch,
        release_complete_ns=release_complete,
    )


def ord_c03_acquire_blocks_younger() -> dict[str, object]:
    hub = HubConfig(ooo_enable=True, ooo_runtime_enable=True, ext_issue_limit=8)
    latency = LatencyModelConfig(kind=LatencyKind.FIXED, fixed_read_ns=60.0, fixed_write_ns=20.0)
    commands: list[SCCommand] = []
    dom = 5
    acquire_seq = 0
    commands.append(
        _cmd(
            acquire_seq,
            0.0,
            route=Route.EXT,
            op=OpType.READ,
            address=0x0400,
            order=OrderType.ACQUIRE,
            ord_dom_id=dom,
        )
    )
    younger = []
    seq = 1
    for idx in range(6):
        younger.append(seq)
        commands.append(
            _cmd(
                seq,
                float(seq),
                route=Route.EXT,
                op=OpType.READ,
                address=0x0410 + idx,
                ord_dom_id=dom,
            )
        )
        seq += 1
    for idx in range(3):
        younger.append(seq)
        commands.append(
            _cmd(
                seq,
                float(seq),
                route=Route.INT,
                op=OpType.READ,
                address=0xFE80 + idx,
                ord_dom_id=dom,
            )
        )
        seq += 1
    model = _run(commands, hub=hub, latency=latency, seed=503)
    acquire_complete = model.tx_states[acquire_seq].complete_ns or 0.0
    min_younger_dispatch = min(model.tx_states[seq_id].dispatch_ns or 0.0 for seq_id in younger)
    min_younger_complete = min(model.tx_states[seq_id].complete_ns or 0.0 for seq_id in younger)
    passed = min_younger_dispatch >= acquire_complete and min_younger_complete >= acquire_complete
    return _row(
        "ORD-C03",
        passed,
        "acquire blocks both issue and completion of younger same-domain traffic",
        acquire_complete_ns=acquire_complete,
        min_younger_dispatch_ns=min_younger_dispatch,
        min_younger_complete_ns=min_younger_complete,
    )


def ord_c04_acquire_visibility() -> dict[str, object]:
    hub = HubConfig(ext_issue_limit=4, outstanding_limit=4)
    latency = LatencyModelConfig(kind=LatencyKind.FIXED, fixed_read_ns=30.0, fixed_write_ns=30.0)
    dom = 1
    value = 0xA5A55A5A
    commands = [
        _cmd(
            0,
            0.0,
            route=Route.EXT,
            op=OpType.WRITE,
            address=0x0500,
            order=OrderType.RELEASE,
            ord_dom_id=dom,
            payload_word=value,
        ),
        _cmd(
            1,
            1.0,
            route=Route.EXT,
            op=OpType.READ,
            address=0x0500,
            order=OrderType.ACQUIRE,
            ord_dom_id=dom,
        ),
    ]
    model = _run(commands, hub=hub, latency=latency, seed=504)
    release_complete = model.tx_states[0].complete_ns or 0.0
    acquire_tx = model.tx_states[1]
    acquire_dispatch = acquire_tx.dispatch_ns or 0.0
    observed = acquire_tx.response_words[0] if acquire_tx.response_words else None
    passed = acquire_dispatch >= release_complete and observed == value
    return _row(
        "ORD-C04",
        passed,
        "acquire observes state updated by the prior release in the same domain",
        release_complete_ns=release_complete,
        acquire_dispatch_ns=acquire_dispatch,
        observed_value=observed,
        expected_value=value,
    )


def ord_c05_cross_domain_independence() -> dict[str, object]:
    hub = HubConfig(ooo_enable=True, ooo_runtime_enable=True, ext_issue_limit=8)
    latency = LatencyModelConfig(
        kind=LatencyKind.ADDRESS,
        address_regions=(
            AddressLatencyRegion("fast", 0x0000, 0x00FF, "fixed", 4.0, 4.0),
            AddressLatencyRegion("slow", 0x2000, 0x20FF, "fixed", 80.0, 80.0),
            AddressLatencyRegion("rest", 0x0000, 0xFFFF, "fixed", 50.0, 50.0, True),
        ),
    )
    commands = [
        _cmd(
            0,
            0.0,
            route=Route.EXT,
            op=OpType.READ,
            address=0x2000,
            order=OrderType.ACQUIRE,
            ord_dom_id=0,
        )
    ]
    domain1 = []
    for seq in range(1, 7):
        domain1.append(seq)
        commands.append(
            _cmd(
                seq,
                float(seq),
                route=Route.EXT,
                op=OpType.READ,
                address=0x0010 + seq,
                ord_dom_id=1,
            )
        )
    model = _run(commands, hub=hub, latency=latency, seed=505)
    acquire_complete = model.tx_states[0].complete_ns or 0.0
    min_domain1_complete = min(model.tx_states[seq_id].complete_ns or 0.0 for seq_id in domain1)
    passed = min_domain1_complete < acquire_complete
    return _row(
        "ORD-C05",
        passed,
        "other domains continue while one domain is held behind an acquire",
        acquire_complete_ns=acquire_complete,
        min_domain1_complete_ns=min_domain1_complete,
    )


def ord_c06_release_then_atomic() -> dict[str, object]:
    hub = HubConfig(ooo_enable=True, ooo_runtime_enable=True, ext_issue_limit=8)
    latency = LatencyModelConfig(kind=LatencyKind.FIXED, fixed_read_ns=30.0, fixed_write_ns=30.0)
    dom = 4
    commands = [
        _cmd(
            0,
            0.0,
            route=Route.EXT,
            op=OpType.WRITE,
            address=0x0600,
            order=OrderType.RELEASE,
            ord_dom_id=dom,
            payload_word=0x10203040,
        ),
        _cmd(
            1,
            1.0,
            route=Route.EXT,
            op=OpType.READ,
            address=0x0600,
            order=OrderType.RELAXED,
            ord_dom_id=dom,
            atomic_flag=True,
            atomic_modify=0x00000011,
        ),
    ]
    model = _run(commands, hub=hub, latency=latency, seed=506)
    release_complete = model.tx_states[0].complete_ns or 0.0
    atomic_dispatch = model.tx_states[1].dispatch_ns or 0.0
    atomic_complete = model.tx_states[1].complete_ns or 0.0
    passed = atomic_dispatch >= release_complete and atomic_complete >= atomic_dispatch
    return _row(
        "ORD-C06",
        passed,
        "same-domain atomic waits behind the release boundary before taking the bus lock",
        release_complete_ns=release_complete,
        atomic_dispatch_ns=atomic_dispatch,
        atomic_complete_ns=atomic_complete,
    )


def ord_i02_accepted_writes_gate() -> dict[str, object]:
    tracker = ScHubOrdTrackerModel()
    dom = 6
    older = [_cmd(seq, float(seq), route=Route.EXT, op=OpType.WRITE, address=0x0700 + seq, ord_dom_id=dom) for seq in range(3)]
    release = _cmd(
        3,
        3.0,
        route=Route.EXT,
        op=OpType.WRITE,
        address=0x0710,
        order=OrderType.RELEASE,
        ord_dom_id=dom,
        payload_word=0x77777777,
    )
    txs = [_tx(cmd) for cmd in older]
    release_tx = _tx(release)
    for tx in txs:
        tracker.on_admit(tx)
    tracker.on_admit(release_tx)
    can_issue_release, reason = tracker.can_dispatch(release_tx, 10.0)
    for idx, tx in enumerate(txs):
        tracker.on_dispatch(tx, 20.0 + idx)
        tracker.on_complete(tx, 30.0 + idx)
    ready, ready_reason = tracker.can_dispatch(release_tx, 40.0)
    passed = (not can_issue_release) and reason == "ord_release_wait" and ready and ready_reason is None
    return _row(
        "ORD-I02A",
        passed,
        "release waits for accepted-but-not-yet-dispatched writes in the same domain",
        initial_reason=reason,
        ready_after_older_complete=int(ready),
    )


def ord_i04_zero_overhead_relaxed() -> dict[str, object]:
    hub = HubConfig(ooo_enable=True, ooo_runtime_enable=True, ext_issue_limit=8)
    latency = LatencyModelConfig(kind=LatencyKind.UNIFORM, uniform_read_min_ns=4.0, uniform_read_max_ns=50.0)
    commands = [
        _cmd(seq, float(seq), route=Route.EXT, op=OpType.READ, address=0x0800 + seq, ord_dom_id=seq % 4)
        for seq in range(12)
    ]
    baseline = [
        _cmd(seq, float(seq), route=Route.EXT, op=OpType.READ, address=0x0800 + seq, ord_dom_id=0)
        for seq in range(12)
    ]
    model_relaxed = _run(commands, hub=hub, latency=latency, seed=610)
    model_base = _run(baseline, hub=hub, latency=latency, seed=610)
    relaxed_dispatch = [model_relaxed.tx_states[seq].dispatch_ns or 0.0 for seq in range(12)]
    relaxed_reply = [model_relaxed.tx_states[seq].reply_done_ns or 0.0 for seq in range(12)]
    base_dispatch = [model_base.tx_states[seq].dispatch_ns or 0.0 for seq in range(12)]
    base_reply = [model_base.tx_states[seq].reply_done_ns or 0.0 for seq in range(12)]
    summary_relaxed = model_relaxed.perf.basic_summary()
    summary_base = model_base.perf.basic_summary()
    passed = (
        relaxed_dispatch == base_dispatch
        and relaxed_reply == base_reply
        and summary_relaxed["throughput_tps"] == summary_base["throughput_tps"]
    )
    return _row(
        "ORD-I04",
        passed,
        "relaxed traffic sees zero modeled overhead from the ordering tracker",
        throughput_relaxed=summary_relaxed["throughput_tps"],
        throughput_baseline=summary_base["throughput_tps"],
    )


def ord_i05_epoch_monotonicity() -> dict[str, object]:
    hub = HubConfig(ooo_enable=True, ooo_runtime_enable=True, ext_issue_limit=8)
    latency = LatencyModelConfig(kind=LatencyKind.UNIFORM, uniform_read_min_ns=4.0, uniform_read_max_ns=50.0)
    commands = ScPktSource(
        uniform_rw(total_transactions=128).clone(
            offered_rate=1.0,
            read_ratio=0.5,
            order_domain_weights=(0.55, 0.45),
            order_domain_release_ratio=(0.12, 0.00),
            order_domain_acquire_ratio=(0.12, 0.00),
        ),
        611,
    ).generate()
    model = _run(commands, hub=hub, latency=latency, seed=611)
    per_domain: dict[int, list[int]] = {}
    dispatched = sorted(
        (
            tx
            for tx in model.tx_states.values()
            if tx.dispatch_ns is not None and tx.command.order != OrderType.RELAXED
        ),
        key=lambda tx: (tx.dispatch_ns if tx.dispatch_ns is not None else float("inf"), tx.command.seq),
    )
    for tx in dispatched:
        per_domain.setdefault(tx.command.ord_dom_id, []).append(tx.command.ord_epoch)
    checked_domains = {dom: epochs for dom, epochs in per_domain.items() if len(epochs) > 1}
    passed = bool(checked_domains) and all(epochs == sorted(epochs) for epochs in checked_domains.values())
    return _row(
        "ORD-I05",
        passed,
        "issued ord_epoch values remain monotonic within each domain",
        domains_checked=len(checked_domains),
    )


CHECKS = {
    "ORD-C01": ord_c01_no_bypass,
    "ORD-C02": ord_c02_release_waits_for_visibility,
    "ORD-C03": ord_c03_acquire_blocks_younger,
    "ORD-C04": ord_c04_acquire_visibility,
    "ORD-C05": ord_c05_cross_domain_independence,
    "ORD-C06": ord_c06_release_then_atomic,
    "ORD-I02A": ord_i02_accepted_writes_gate,
    "ORD-I04": ord_i04_zero_overhead_relaxed,
    "ORD-I05": ord_i05_epoch_monotonicity,
}


def run_checks(experiment_ids: list[str] | None = None) -> list[dict[str, object]]:
    selected = experiment_ids or list(CHECKS)
    return [CHECKS[experiment_id]() for experiment_id in selected]
