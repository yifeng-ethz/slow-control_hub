from __future__ import annotations

from dataclasses import replace

from include.sc_hub_tlm_config import (
    AddressLatencyRegion,
    HubConfig,
    LatencyModelConfig,
)
from include.sc_hub_tlm_types import LatencyKind, OpType, OrderType, ResponseCode, Route, SCCommand
from src.bus_target_model import BusTargetModel
from src.sc_hub_csr import ScHubCsrModel
from src.sc_hub_model import ScHubModel


def _cmd(
    seq: int,
    arrival_ns: float,
    *,
    route: Route,
    op: OpType,
    address: int,
    length: int = 1,
    payload_words: list[int] | None = None,
) -> SCCommand:
    return SCCommand(
        seq=seq,
        arrival_ns=arrival_ns,
        route=route,
        op=op,
        address=address,
        length=length,
        order=OrderType.RELAXED,
        ord_dom_id=0,
        ord_epoch=(seq + 1) & 0xFF,
        payload_words=list(payload_words or []),
    )


def _run(
    commands: list[SCCommand],
    *,
    hub: HubConfig,
    latency: LatencyModelConfig,
    seed: int,
) -> ScHubModel:
    model = ScHubModel(hub, latency, seed)
    model.run(commands)
    return model


def _row(check_id: str, passed: bool, effect: str, **metrics: object) -> dict[str, object]:
    return {
        "experiment": check_id,
        "passed": int(passed),
        "effect": effect,
        **metrics,
    }


def _mixed_ext_commands() -> list[SCCommand]:
    commands: list[SCCommand] = []
    seq = 0
    for idx, length in enumerate((4, 1, 8, 2, 4, 1)):
        base = 0x0100 + idx * 0x20
        payload = [((idx + 1) << 12) | word for word in range(length)]
        commands.append(
            _cmd(
                seq,
                float(seq),
                route=Route.EXT,
                op=OpType.WRITE,
                address=base,
                length=length,
                payload_words=payload,
            )
        )
        seq += 1
        commands.append(
            _cmd(
                seq,
                float(seq),
                route=Route.EXT,
                op=OpType.READ,
                address=base,
                length=length,
            )
        )
        seq += 1
    return commands


def _reference_ext_results(
    model: ScHubModel,
    commands: list[SCCommand],
    latency: LatencyModelConfig,
    seed: int,
) -> dict[int, tuple[ResponseCode, list[int]]]:
    bus = BusTargetModel(latency, seed + 101)
    expected: dict[int, tuple[ResponseCode, list[int]]] = {}
    ext_txs = [
        model.tx_states[cmd.seq]
        for cmd in commands
        if cmd.route == Route.EXT and model.tx_states[cmd.seq].dispatch_ns is not None
    ]
    ext_txs.sort(key=lambda tx: (tx.dispatch_ns if tx.dispatch_ns is not None else float("inf"), tx.command.seq))
    for tx in ext_txs:
        cmd = tx.command
        if cmd.op == OpType.WRITE:
            response = bus.write(cmd.address, cmd.payload_words)[1]
            expected[cmd.seq] = (response, [])
        else:
            latency_ns, response, data_words = bus.read(cmd.address, cmd.length)
            _ = latency_ns
            expected[cmd.seq] = (response, data_words)
    return expected


def ooo_c01_integrity() -> dict[str, object]:
    hub = HubConfig(ooo_enable=True, ooo_runtime_enable=True, ext_issue_limit=8)
    latency = LatencyModelConfig(
        kind=LatencyKind.UNIFORM,
        uniform_read_min_ns=4.0,
        uniform_read_max_ns=50.0,
        uniform_write_min_ns=4.0,
        uniform_write_max_ns=8.0,
    )
    seed = 601
    commands = _mixed_ext_commands()
    model = _run(commands, hub=hub, latency=latency, seed=seed)
    expected = _reference_ext_results(model, commands, latency, seed)
    mismatches = []
    for cmd in commands:
        tx = model.tx_states[cmd.seq]
        exp_response, exp_words = expected[cmd.seq]
        if tx.response != exp_response or tx.response_words != exp_words:
            mismatches.append(cmd.seq)
    passed = not mismatches and model.perf.ooo_reorders > 0
    return _row(
        "OOO-C01",
        passed,
        "every reply carries the correct data despite out-of-order completion",
        mismatches=len(mismatches),
        ooo_reorders=model.perf.ooo_reorders,
    )


def ooo_c02_no_duplication() -> dict[str, object]:
    hub = HubConfig(ooo_enable=True, ooo_runtime_enable=True, ext_issue_limit=8)
    latency = LatencyModelConfig(kind=LatencyKind.UNIFORM, uniform_read_min_ns=4.0, uniform_read_max_ns=50.0)
    commands = _mixed_ext_commands()
    model = _run(commands, hub=hub, latency=latency, seed=602)
    txn_ids = [int(row["txn_id"]) for row in model.perf.transaction_rows]
    passed = len(txn_ids) == len(set(txn_ids)) == len(commands)
    return _row(
        "OOO-C02",
        passed,
        "each command produces exactly one reply row",
        replies=len(txn_ids),
        unique_replies=len(set(txn_ids)),
        commands=len(commands),
    )


def ooo_c03_no_loss() -> dict[str, object]:
    hub = HubConfig(ooo_enable=True, ooo_runtime_enable=True, ext_issue_limit=8)
    latency = LatencyModelConfig(kind=LatencyKind.UNIFORM, uniform_read_min_ns=4.0, uniform_read_max_ns=50.0)
    commands = _mixed_ext_commands()
    model = _run(commands, hub=hub, latency=latency, seed=603)
    replied = {int(row["txn_id"]) for row in model.perf.transaction_rows}
    expected = {cmd.seq for cmd in commands}
    passed = replied == expected
    missing = sorted(expected - replied)
    return _row(
        "OOO-C03",
        passed,
        "every admitted command eventually produces a reply",
        missing=len(missing),
    )


def ooo_c04_payload_isolation() -> dict[str, object]:
    hub = HubConfig(ooo_enable=True, ooo_runtime_enable=True, ext_issue_limit=8)
    latency = LatencyModelConfig(kind=LatencyKind.UNIFORM, uniform_read_min_ns=4.0, uniform_read_max_ns=50.0)
    commands: list[SCCommand] = []
    seq = 0
    for idx, length in enumerate((32, 16, 8, 4, 32, 16)):
        base = 0x0800 + idx * 0x40
        payload = [((idx + 1) << 16) | word for word in range(length)]
        commands.append(_cmd(seq, float(seq), route=Route.EXT, op=OpType.WRITE, address=base, length=length, payload_words=payload))
        seq += 1
        commands.append(_cmd(seq, float(seq), route=Route.EXT, op=OpType.READ, address=base, length=length))
        seq += 1
    seed = 604
    model = _run(commands, hub=hub, latency=latency, seed=seed)
    expected = _reference_ext_results(model, commands, latency, seed)
    bad_reads = 0
    for cmd in commands:
        tx = model.tx_states[cmd.seq]
        exp_response, exp_words = expected[cmd.seq]
        if tx.response != exp_response or tx.response_words != exp_words:
            bad_reads += 1
    passed = bad_reads == 0 and model.buffers.integrity_check()
    return _row(
        "OOO-C04",
        passed,
        "OoO payload use does not corrupt adjacent payload chains",
        mismatched_reads=bad_reads,
        buffers_intact=int(model.buffers.integrity_check()),
    )


def ooo_c05_free_list_consistency() -> dict[str, object]:
    hub = HubConfig(ooo_enable=True, ooo_runtime_enable=True, ext_issue_limit=8)
    latency = LatencyModelConfig(kind=LatencyKind.UNIFORM, uniform_read_min_ns=4.0, uniform_read_max_ns=50.0)
    commands = _mixed_ext_commands()
    model = _run(commands, hub=hub, latency=latency, seed=605)
    pools = (
        model.buffers.ext_down_pld,
        model.buffers.int_down_pld,
        model.buffers.ext_up_pld,
        model.buffers.int_up_pld,
    )
    passed = all(pool.get_free_count() == pool.depth for pool in pools) and model.buffers.integrity_check()
    return _row(
        "OOO-C05",
        passed,
        "all payload RAM lines return to the free list after quiesce",
        free_counts=",".join(str(pool.get_free_count()) for pool in pools),
    )


def ooo_c06_runtime_toggle() -> dict[str, object]:
    hub = HubConfig(ooo_enable=True, ooo_runtime_enable=True, ext_issue_limit=8)
    latency = LatencyModelConfig(
        kind=LatencyKind.ADDRESS,
        address_regions=(
            AddressLatencyRegion("fast", 0x0000, 0x00FF, "fixed", 4.0, 4.0),
            AddressLatencyRegion("slow", 0x1000, 0x10FF, "fixed", 80.0, 80.0),
            AddressLatencyRegion("rest", 0x0000, 0xFFFF, "fixed", 50.0, 50.0, True),
        ),
    )
    ooo_ctrl_addr = 0xFE80 + ScHubCsrModel.OOO_CTRL_OFFSET
    commands = [
        _cmd(0, 0.0, route=Route.EXT, op=OpType.READ, address=0x1000),
        _cmd(1, 1.0, route=Route.EXT, op=OpType.READ, address=0x0001),
        _cmd(2, 2.0, route=Route.EXT, op=OpType.READ, address=0x1002),
        _cmd(3, 3.0, route=Route.EXT, op=OpType.READ, address=0x0003),
        _cmd(4, 4.0, route=Route.INT, op=OpType.WRITE, address=ooo_ctrl_addr, payload_words=[0]),
        _cmd(5, 5.0, route=Route.EXT, op=OpType.READ, address=0x1004),
        _cmd(6, 6.0, route=Route.EXT, op=OpType.READ, address=0x0005),
        _cmd(7, 7.0, route=Route.EXT, op=OpType.READ, address=0x1006),
        _cmd(8, 8.0, route=Route.EXT, op=OpType.READ, address=0x0007),
    ]
    model = _run(commands, hub=hub, latency=latency, seed=606)
    post_toggle = [
        tx.command.seq
        for tx in sorted(
            (model.tx_states[idx] for idx in range(5, 9)),
            key=lambda tx: (tx.reply_done_ns if tx.reply_done_ns is not None else float("inf"), tx.command.seq),
        )
    ]
    passed = post_toggle == sorted(post_toggle) and not model.csr.ooo_ctrl_enable
    return _row(
        "OOO-C06",
        passed,
        "reply ordering reverts to in-order after runtime OoO disable",
        post_toggle_order=",".join(str(seq) for seq in post_toggle),
        final_ooo_ctrl=int(model.csr.ooo_ctrl_enable),
    )


def ooo_c07_mixed_int_ext() -> dict[str, object]:
    hub = HubConfig(ooo_enable=True, ooo_runtime_enable=True, ext_issue_limit=8)
    latency = LatencyModelConfig(
        kind=LatencyKind.ADDRESS,
        address_regions=(
            AddressLatencyRegion("fast", 0x0000, 0x00FF, "fixed", 6.0, 6.0),
            AddressLatencyRegion("slow", 0x2000, 0x20FF, "fixed", 90.0, 90.0),
            AddressLatencyRegion("rest", 0x0000, 0xFFFF, "fixed", 50.0, 50.0, True),
        ),
    )
    commands: list[SCCommand] = []
    seq = 0
    for idx in range(8):
        commands.append(_cmd(seq, float(seq), route=Route.EXT, op=OpType.READ, address=0x2000 + idx))
        seq += 1
        if idx % 2 == 1:
            commands.append(_cmd(seq, float(seq), route=Route.INT, op=OpType.READ, address=0xFE80 + (idx % 4)))
            seq += 1
    model = _run(commands, hub=hub, latency=latency, seed=607)
    int_done = [tx.reply_done_ns or 0.0 for tx in model.tx_states.values() if tx.command.route == Route.INT]
    ext_done = [tx.reply_done_ns or 0.0 for tx in model.tx_states.values() if tx.command.route == Route.EXT]
    passed = bool(int_done) and bool(ext_done) and min(int_done) < max(ext_done) and max(model.perf.int_latencies_ns) < 100.0
    return _row(
        "OOO-C07",
        passed,
        "internal traffic bypasses slow external replies without starvation",
        int_max_latency_ns=max(model.perf.int_latencies_ns) if model.perf.int_latencies_ns else 0.0,
        int_first_reply_ns=min(int_done) if int_done else 0.0,
        ext_last_reply_ns=max(ext_done) if ext_done else 0.0,
    )


CHECKS = {
    "OOO-C01": ooo_c01_integrity,
    "OOO-C02": ooo_c02_no_duplication,
    "OOO-C03": ooo_c03_no_loss,
    "OOO-C04": ooo_c04_payload_isolation,
    "OOO-C05": ooo_c05_free_list_consistency,
    "OOO-C06": ooo_c06_runtime_toggle,
    "OOO-C07": ooo_c07_mixed_int_ext,
}


def run_checks(experiment_ids: list[str] | None = None) -> list[dict[str, object]]:
    selected = experiment_ids or list(CHECKS)
    return [CHECKS[experiment_id]() for experiment_id in selected]
