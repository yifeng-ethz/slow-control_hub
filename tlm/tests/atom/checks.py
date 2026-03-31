from __future__ import annotations

from include.sc_hub_tlm_config import HubConfig, LatencyModelConfig
from include.sc_hub_tlm_types import LatencyKind, OpType, OrderType, ResponseCode, Route, SCCommand
from src.sc_hub_model import ScHubModel


def _cmd(
    seq: int,
    arrival_ns: float,
    *,
    route: Route,
    op: OpType,
    address: int,
    payload_words: list[int] | None = None,
    atomic_flag: bool = False,
    atomic_mask: int = 0xFFFFFFFF,
    atomic_modify: int = 0,
) -> SCCommand:
    return SCCommand(
        seq=seq,
        arrival_ns=arrival_ns,
        route=route,
        op=op,
        address=address,
        length=1,
        order=OrderType.RELAXED,
        ord_dom_id=0,
        ord_epoch=(seq + 1) & 0xFF,
        payload_words=list(payload_words or []),
        atomic_flag=atomic_flag,
        atomic_mask=atomic_mask,
        atomic_modify=atomic_modify,
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


def atom_05_correctness() -> dict[str, object]:
    hub = HubConfig(ext_issue_limit=8)
    latency = LatencyModelConfig(kind=LatencyKind.FIXED, fixed_read_ns=8.0, fixed_write_ns=4.0)
    address = 0x0200
    commands: list[SCCommand] = []
    valid_values = {0x12345678 ^ ((address * 0x9E3779B1) & 0xFFFFFFFF)}
    seq = 0
    for idx in range(1000):
        value = (0x10000000 + idx) & 0xFFFFFFFF
        valid_values.add(value)
        commands.append(
            _cmd(
                seq,
                float(seq),
                route=Route.EXT,
                op=OpType.READ,
                address=address,
                atomic_flag=True,
                atomic_mask=0xFFFFFFFF,
                atomic_modify=value,
            )
        )
        seq += 1
        if idx % 10 == 0:
            commands.append(_cmd(seq, float(seq), route=Route.EXT, op=OpType.READ, address=address))
            seq += 1
    model = _run(commands, hub=hub, latency=latency, seed=701)
    read_values = [
        tx.response_words[0]
        for tx in model.tx_states.values()
        if not tx.command.atomic_flag and tx.command.route == Route.EXT and tx.response_words
    ]
    final_atomic = max(
        (tx for tx in model.tx_states.values() if tx.command.atomic_flag),
        key=lambda tx: (tx.complete_ns if tx.complete_ns is not None else float("inf"), tx.command.seq),
    )
    passed = all(value in valid_values for value in read_values) and model.bus.memory[address] == final_atomic.command.atomic_modify
    return _row(
        "ATOM-05",
        passed,
        "non-atomic reads never observe a torn atomic update",
        sampled_reads=len(read_values),
        final_value=model.bus.memory[address],
    )


def atom_06_internal_priority() -> dict[str, object]:
    hub = HubConfig(ext_issue_limit=8)
    latency = LatencyModelConfig(kind=LatencyKind.UNIFORM, uniform_read_min_ns=4.0, uniform_read_max_ns=20.0)
    commands: list[SCCommand] = []
    seq = 0
    for idx in range(200):
        commands.append(
            _cmd(
                seq,
                float(seq),
                route=Route.EXT,
                op=OpType.READ,
                address=0x0400 + (idx % 8),
                atomic_flag=(idx % 2 == 0),
                atomic_mask=0xFFFFFFFF,
                atomic_modify=(0xABC00000 + idx) & 0xFFFFFFFF,
            )
        )
        seq += 1
        if idx % 25 == 24:
            commands.append(_cmd(seq, float(seq), route=Route.INT, op=OpType.READ, address=0xFE80))
            seq += 1
    model = _run(commands, hub=hub, latency=latency, seed=702)
    int_lat = model.perf.int_latencies_ns
    ext_done = [tx.reply_done_ns or 0.0 for tx in model.tx_states.values() if tx.command.route == Route.EXT]
    int_done = [tx.reply_done_ns or 0.0 for tx in model.tx_states.values() if tx.command.route == Route.INT]
    passed = bool(int_lat) and max(int_lat) < 100.0 and min(int_done) < max(ext_done)
    return _row(
        "ATOM-06",
        passed,
        "internal CSR traffic stays reachable during heavy atomic locking",
        int_max_latency_ns=max(int_lat) if int_lat else 0.0,
        atomic_lock_avg_ns=model.perf.basic_summary()["atomic_lock_avg_ns"],
    )


def atom_c01_atomicity() -> dict[str, object]:
    hub = HubConfig(ext_issue_limit=8)
    latency = LatencyModelConfig(kind=LatencyKind.FIXED, fixed_read_ns=8.0, fixed_write_ns=4.0)
    address = 0x0300
    commands = [
        _cmd(0, 0.0, route=Route.EXT, op=OpType.READ, address=address, atomic_flag=True, atomic_mask=0x0000FFFF, atomic_modify=0x00001234),
        _cmd(1, 1.0, route=Route.EXT, op=OpType.READ, address=address, atomic_flag=True, atomic_mask=0xFFFF0000, atomic_modify=0xABCD0000),
    ]
    model = _run(commands, hub=hub, latency=latency, seed=703)
    initial = ((address * 0x9E3779B1) ^ 0x12345678) & 0xFFFFFFFF
    expected = (initial & 0x00000000) | 0xABCD1234
    passed = model.bus.memory[address] == expected
    return _row(
        "ATOM-C01",
        passed,
        "two atomic RMW operations to the same address preserve both updates",
        final_value=model.bus.memory[address],
        expected_value=expected,
    )


def atom_c02_lock_exclusion() -> dict[str, object]:
    hub = HubConfig(ext_issue_limit=8)
    latency = LatencyModelConfig(kind=LatencyKind.FIXED, fixed_read_ns=40.0, fixed_write_ns=20.0)
    commands = [
        _cmd(0, 0.0, route=Route.EXT, op=OpType.READ, address=0x0400, atomic_flag=True, atomic_modify=0x11111111),
        _cmd(1, 1.0, route=Route.EXT, op=OpType.READ, address=0x0404),
        _cmd(2, 2.0, route=Route.EXT, op=OpType.WRITE, address=0x0408, payload_words=[0x22222222]),
    ]
    model = _run(commands, hub=hub, latency=latency, seed=704)
    atomic_complete = model.tx_states[0].complete_ns or 0.0
    other_dispatch = min(model.tx_states[idx].dispatch_ns or 0.0 for idx in (1, 2))
    passed = other_dispatch >= atomic_complete
    return _row(
        "ATOM-C02",
        passed,
        "no external transaction dispatches while the atomic lock is held",
        atomic_complete_ns=atomic_complete,
        first_other_dispatch_ns=other_dispatch,
    )


def atom_c03_internal_bypass() -> dict[str, object]:
    hub = HubConfig(ext_issue_limit=8)
    latency = LatencyModelConfig(kind=LatencyKind.FIXED, fixed_read_ns=50.0, fixed_write_ns=25.0)
    commands = [
        _cmd(0, 0.0, route=Route.EXT, op=OpType.READ, address=0x0500, atomic_flag=True, atomic_modify=0x33333333),
        _cmd(1, 1.0, route=Route.INT, op=OpType.READ, address=0xFE80),
        _cmd(2, 2.0, route=Route.INT, op=OpType.READ, address=0xFE81),
    ]
    model = _run(commands, hub=hub, latency=latency, seed=705)
    atomic_complete = model.tx_states[0].complete_ns or 0.0
    int_complete = max(model.tx_states[idx].complete_ns or 0.0 for idx in (1, 2))
    passed = int_complete < atomic_complete and max(model.perf.int_latencies_ns) < 100.0
    return _row(
        "ATOM-C03",
        passed,
        "internal CSR accesses complete during the atomic lock window",
        int_complete_ns=int_complete,
        atomic_complete_ns=atomic_complete,
    )


def atom_c04_error_path() -> dict[str, object]:
    hub = HubConfig(ext_issue_limit=8)
    latency = LatencyModelConfig(kind=LatencyKind.FIXED, fixed_read_ns=8.0, fixed_write_ns=4.0, error_rate=1.0)
    address = 0x0600
    initial = ((address * 0x9E3779B1) ^ 0x12345678) & 0xFFFFFFFF
    commands = [
        _cmd(0, 0.0, route=Route.EXT, op=OpType.READ, address=address, atomic_flag=True, atomic_modify=0x44444444),
    ]
    model = _run(commands, hub=hub, latency=latency, seed=706)
    tx = model.tx_states[0]
    passed = tx.response == ResponseCode.SLVERR and model.bus.memory[address] == initial
    return _row(
        "ATOM-C04",
        passed,
        "atomic write phase is skipped when the read phase errors",
        response=tx.response.value,
        final_value=model.bus.memory[address],
    )


def atom_c05_reply_format() -> dict[str, object]:
    hub = HubConfig(ext_issue_limit=8)
    latency = LatencyModelConfig(kind=LatencyKind.FIXED, fixed_read_ns=8.0, fixed_write_ns=4.0)
    address = 0x0700
    initial = ((address * 0x9E3779B1) ^ 0x12345678) & 0xFFFFFFFF
    commands = [
        _cmd(0, 0.0, route=Route.EXT, op=OpType.READ, address=address, atomic_flag=True, atomic_modify=0x55555555),
    ]
    model = _run(commands, hub=hub, latency=latency, seed=707)
    tx = model.tx_states[0]
    passed = tx.response == ResponseCode.OK and tx.response_words == [initial]
    return _row(
        "ATOM-C05",
        passed,
        "atomic reply returns the original read value with the response code",
        response=tx.response.value,
        old_value=tx.response_words[0] if tx.response_words else None,
        expected_old_value=initial,
    )


CHECKS = {
    "ATOM-05": atom_05_correctness,
    "ATOM-06": atom_06_internal_priority,
    "ATOM-C01": atom_c01_atomicity,
    "ATOM-C02": atom_c02_lock_exclusion,
    "ATOM-C03": atom_c03_internal_bypass,
    "ATOM-C04": atom_c04_error_path,
    "ATOM-C05": atom_c05_reply_format,
}


def run_checks(experiment_ids: list[str] | None = None) -> list[dict[str, object]]:
    selected = experiment_ids or list(CHECKS)
    return [CHECKS[experiment_id]() for experiment_id in selected]
