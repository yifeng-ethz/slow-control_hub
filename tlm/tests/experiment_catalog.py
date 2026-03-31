from __future__ import annotations

from include.sc_hub_tlm_config import ExperimentSpec, HubConfig, LatencyModelConfig
from include.sc_hub_tlm_types import LatencyKind
from include.sc_hub_tlm_workload import (
    atomic_mix,
    bimodal,
    feb_system_realistic,
    single_word,
    uniform_rw,
)


def _ord_notes(
    profile: str,
    *,
    release_ratio: float = 0.0,
    acquire_ratio: float = 0.0,
    atomic_ratio: float = 0.0,
    domains: int = 1,
    ooo: bool = False,
) -> str:
    return (
        f"profile={profile};"
        f"release_ratio={release_ratio:.3f};"
        f"acquire_ratio={acquire_ratio:.3f};"
        f"atomic_ratio={atomic_ratio:.3f};"
        f"domains={domains};"
        f"ooo={int(ooo)}"
    )


def _domain_count(workload) -> int:
    weights = tuple(float(value) for value in workload.order_domain_weights)
    if not weights:
        return 1
    return max(1, sum(1 for value in weights if value > 0.0))


RATE_POINTS = tuple(round(0.1 * idx, 2) for idx in range(1, 11))
SIZE_OUTSTANDING = (1, 2, 4, 8, 12, 16, 24, 32)
SIZE_PAYLOAD = (64, 128, 256, 512, 1024)
SIZE_INT_HDR = (1, 2, 4, 8)

BASE_HUB = HubConfig()
FIXED_8 = LatencyModelConfig(kind=LatencyKind.FIXED, fixed_read_ns=8.0, fixed_write_ns=4.0)
UNIFORM_4_20 = LatencyModelConfig(
    kind=LatencyKind.UNIFORM,
    uniform_read_min_ns=4.0,
    uniform_read_max_ns=20.0,
    uniform_write_min_ns=4.0,
    uniform_write_max_ns=8.0,
)
UNIFORM_4_50 = LatencyModelConfig(
    kind=LatencyKind.UNIFORM,
    uniform_read_min_ns=4.0,
    uniform_read_max_ns=50.0,
    uniform_write_min_ns=4.0,
    uniform_write_max_ns=8.0,
)
UNIFORM_4_200 = LatencyModelConfig(
    kind=LatencyKind.UNIFORM,
    uniform_read_min_ns=4.0,
    uniform_read_max_ns=200.0,
    uniform_write_min_ns=4.0,
    uniform_write_max_ns=8.0,
)
BIMODAL_4_40 = LatencyModelConfig(
    kind=LatencyKind.BIMODAL,
    bimodal_fast_ns=4.0,
    bimodal_slow_ns=40.0,
    bimodal_fast_prob=0.5,
)
ADDRESS_DEP = LatencyModelConfig(kind=LatencyKind.ADDRESS)


def _specs() -> dict[str, ExperimentSpec]:
    specs: dict[str, ExperimentSpec] = {}

    specs["FRAG-01"] = ExperimentSpec(
        "FRAG-01",
        "frag",
        "Uniform burst length, in-order",
        "frag",
        BASE_HUB.clone(),
        uniform_rw(total_transactions=10000).clone(offered_rate=0.65),
        UNIFORM_4_20.clone(),
        seed=11,
    )
    specs["FRAG-02"] = ExperimentSpec(
        "FRAG-02",
        "frag",
        "Bimodal burst length, in-order",
        "frag",
        BASE_HUB.clone(),
        bimodal(total_transactions=10000).clone(offered_rate=0.65),
        UNIFORM_4_20.clone(),
        seed=12,
    )
    specs["FRAG-03"] = ExperimentSpec(
        "FRAG-03",
        "frag",
        "Small bursts only",
        "frag",
        BASE_HUB.clone(),
        uniform_rw(total_transactions=10000).clone(length_min=1, length_max=4, offered_rate=0.7),
        UNIFORM_4_20.clone(),
        seed=13,
    )
    specs["FRAG-04"] = ExperimentSpec(
        "FRAG-04",
        "frag",
        "Large bursts only",
        "frag",
        BASE_HUB.clone(),
        uniform_rw(total_transactions=10000).clone(length_min=128, length_max=256, offered_rate=0.55),
        UNIFORM_4_20.clone(),
        seed=14,
    )
    specs["FRAG-05"] = ExperimentSpec(
        "FRAG-05",
        "frag",
        "Uniform burst length, OoO",
        "frag",
        BASE_HUB.clone(ooo_enable=True, ooo_runtime_enable=True),
        uniform_rw(total_transactions=10000).clone(offered_rate=0.65),
        UNIFORM_4_50.clone(),
        seed=15,
    )
    specs["FRAG-06"] = ExperimentSpec(
        "FRAG-06",
        "frag",
        "Bimodal burst length, OoO",
        "frag",
        BASE_HUB.clone(ooo_enable=True, ooo_runtime_enable=True),
        bimodal(total_transactions=10000).clone(offered_rate=0.65),
        UNIFORM_4_50.clone(),
        seed=16,
    )
    specs["FRAG-07"] = ExperimentSpec(
        "FRAG-07",
        "frag",
        "Alternating 1 and 256 word bursts",
        "frag",
        BASE_HUB.clone(),
        uniform_rw(total_transactions=10000).clone(
            length_mode="alternating",
            length_short=1,
            length_long=256,
            offered_rate=0.6,
        ),
        UNIFORM_4_20.clone(),
        seed=17,
    )
    specs["FRAG-08"] = ExperimentSpec(
        "FRAG-08",
        "frag",
        "Long soak",
        "frag",
        BASE_HUB.clone(),
        uniform_rw(total_transactions=1_000_000).clone(offered_rate=0.65),
        UNIFORM_4_20.clone(),
        seed=18,
    )

    specs["RATE-01"] = ExperimentSpec(
        "RATE-01",
        "rate",
        "Baseline anchor fixed latency outstanding=1",
        "rate_sweep",
        BASE_HUB.clone(outstanding_limit=1, outstanding_int_reserved=0, ext_issue_limit=1),
        single_word(total_transactions=3000).clone(read_ratio=1.0),
        FIXED_8.clone(),
        seed=100,
        offered_rates=RATE_POINTS,
    )
    for exp_id, outstanding in [
        ("RATE-02", 1),
        ("RATE-03", 2),
        ("RATE-04", 4),
        ("RATE-05", 8),
        ("RATE-06", 16),
    ]:
        specs[exp_id] = ExperimentSpec(
            exp_id,
            "rate",
            f"Fixed latency outstanding={outstanding}",
            "rate_sweep",
            BASE_HUB.clone(outstanding_limit=outstanding, outstanding_int_reserved=min(1, outstanding - 1), ext_issue_limit=outstanding),
            single_word(total_transactions=3000).clone(read_ratio=1.0),
            FIXED_8.clone(),
            seed=100 + outstanding,
            offered_rates=RATE_POINTS,
        )
    specs["RATE-07"] = ExperimentSpec(
        "RATE-07",
        "rate",
        "Variable latency, in-order",
        "rate_sweep",
        BASE_HUB.clone(),
        single_word(total_transactions=3000).clone(read_ratio=1.0),
        UNIFORM_4_50.clone(),
        seed=107,
        offered_rates=RATE_POINTS,
    )
    specs["RATE-08"] = ExperimentSpec(
        "RATE-08",
        "rate",
        "Variable latency, OoO",
        "rate_sweep",
        BASE_HUB.clone(ooo_enable=True, ooo_runtime_enable=True),
        single_word(total_transactions=3000).clone(read_ratio=1.0),
        UNIFORM_4_50.clone(),
        seed=108,
        offered_rates=RATE_POINTS,
    )
    specs["RATE-09"] = ExperimentSpec(
        "RATE-09",
        "rate",
        "Bimodal latency, in-order",
        "rate_sweep",
        BASE_HUB.clone(),
        single_word(total_transactions=3000).clone(read_ratio=1.0),
        BIMODAL_4_40.clone(),
        seed=109,
        offered_rates=RATE_POINTS,
    )
    specs["RATE-10"] = ExperimentSpec(
        "RATE-10",
        "rate",
        "Bimodal latency, OoO",
        "rate_sweep",
        BASE_HUB.clone(ooo_enable=True, ooo_runtime_enable=True),
        single_word(total_transactions=3000).clone(read_ratio=1.0),
        BIMODAL_4_40.clone(),
        seed=110,
        offered_rates=RATE_POINTS,
    )
    specs["RATE-11"] = ExperimentSpec(
        "RATE-11",
        "rate",
        "Mixed read/write, in-order",
        "rate_sweep",
        BASE_HUB.clone(),
        uniform_rw(total_transactions=3500).clone(read_ratio=0.5, length_min=1, length_max=32),
        FIXED_8.clone(),
        seed=111,
        offered_rates=RATE_POINTS,
    )
    specs["RATE-12"] = ExperimentSpec(
        "RATE-12",
        "rate",
        "Address-dependent feb_system",
        "rate_sweep",
        BASE_HUB.clone(),
        feb_system_realistic(total_transactions=4500),
        ADDRESS_DEP.clone(),
        seed=112,
        offered_rates=RATE_POINTS,
    )

    for exp_id, latency, workload, seed in [
        ("OOO-01", FIXED_8.clone(), single_word(total_transactions=3500).clone(read_ratio=1.0, offered_rate=2.0), 201),
        ("OOO-02", UNIFORM_4_50.clone(), single_word(total_transactions=3500).clone(read_ratio=1.0, offered_rate=2.0), 202),
        ("OOO-03", UNIFORM_4_200.clone(), single_word(total_transactions=3500).clone(read_ratio=1.0, offered_rate=2.0), 203),
        ("OOO-04", UNIFORM_4_50.clone(), uniform_rw(total_transactions=4000).clone(read_ratio=1.0, int_ratio=0.5, length_min=1, length_max=4, offered_rate=2.0), 204),
        ("OOO-05", UNIFORM_4_50.clone(), uniform_rw(total_transactions=4000).clone(read_ratio=0.5, length_min=1, length_max=32, offered_rate=2.0), 205),
        ("OOO-06", UNIFORM_4_50.clone(), atomic_mix(total_transactions=4000).clone(atomic_ratio=0.1, offered_rate=2.0), 206),
    ]:
        specs[exp_id] = ExperimentSpec(
            exp_id,
            "ooo",
            f"OoO comparison for {exp_id}",
            "ooo_compare",
            BASE_HUB.clone(),
            workload,
            latency,
            seed=seed,
            pair_compare=True,
        )

    for exp_id, description, workload, latency, seed in [
        (
            "OOO-F01",
            "OoO frees in random order",
            uniform_rw(total_transactions=10000).clone(offered_rate=0.65),
            UNIFORM_4_50.clone(),
            230,
        ),
        (
            "OOO-F02",
            "Long-lived and short-lived mix under OoO",
            uniform_rw(total_transactions=10000).clone(
                length_mode="alternating",
                length_short=1,
                length_long=256,
                offered_rate=0.65,
            ),
            UNIFORM_4_50.clone(),
            231,
        ),
    ]:
        specs[exp_id] = ExperimentSpec(
            exp_id,
            "ooo",
            description,
            "frag",
            BASE_HUB.clone(ooo_enable=True, ooo_runtime_enable=True),
            workload,
            latency,
            seed=seed,
        )

    specs["OOO-F03"] = ExperimentSpec(
        "OOO-F03",
        "ooo",
        "Fragmentation recovery after OoO stress",
        "ooo_frag_recovery",
        BASE_HUB.clone(ooo_enable=True, ooo_runtime_enable=True),
        uniform_rw(total_transactions=10000).clone(
            length_mode="alternating",
            length_short=1,
            length_long=256,
            offered_rate=0.65,
        ),
        UNIFORM_4_50.clone(),
        seed=232,
    )

    for exp_id, description, seed in [
        ("OOO-C01", "Reply data integrity under OoO", 240),
        ("OOO-C02", "No reply duplication under OoO", 241),
        ("OOO-C03", "No reply loss under OoO", 242),
        ("OOO-C04", "Payload isolation under OoO", 243),
        ("OOO-C05", "Free-list consistency after OoO", 244),
        ("OOO-C06", "Runtime OoO toggle reverts to in-order", 245),
        ("OOO-C07", "Mixed internal and external OoO ordering", 246),
    ]:
        specs[exp_id] = ExperimentSpec(
            exp_id,
            "ooo",
            description,
            "ooo_check",
            BASE_HUB.clone(ooo_enable=True, ooo_runtime_enable=True),
            single_word(total_transactions=64).clone(read_ratio=1.0),
            UNIFORM_4_50.clone(),
            seed=seed,
        )

    for exp_id, workload, latency, release_ratio, acquire_ratio, atomic_ratio, ooo, note in [
        (
            "ORD-01",
            single_word(total_transactions=3000).clone(
                read_ratio=0.0, offered_rate=2.0, order_release_ratio=0.05
            ),
            FIXED_8.clone(),
            0.05,
            0.0,
            0.0,
            False,
            "release_shallow",
        ),
        (
            "ORD-02",
            single_word(total_transactions=3000).clone(
                read_ratio=0.0,
                length_min=64,
                length_max=64,
                offered_rate=0.8,
                order_release_ratio=0.05,
            ),
            FIXED_8.clone(),
            0.05,
            0.0,
            0.0,
            False,
            "release_deep",
        ),
        (
            "ORD-03",
            single_word(total_transactions=3000).clone(
                read_ratio=1.0, offered_rate=2.0, order_acquire_ratio=0.05
            ),
            FIXED_8.clone(),
            0.0,
            0.05,
            0.0,
            False,
            "acquire_hold",
        ),
        (
            "ORD-04",
            uniform_rw(total_transactions=4000).clone(
                read_ratio=0.5,
                offered_rate=1.25,
                order_release_ratio=0.02,
                order_acquire_ratio=0.02,
            ),
            UNIFORM_4_50.clone(),
            0.02,
            0.02,
            0.0,
            False,
            "release_acquire",
        ),
        (
            "ORD-05",
            single_word(total_transactions=2500).clone(
                read_ratio=1.0,
                offered_rate=2.0,
                order_domain_weights=(0.5, 0.5),
                order_domain_acquire_ratio=(0.10, 0.0),
            ),
            FIXED_8.clone(),
            0.0,
            0.10,
            0.0,
            False,
            "multi_domain_mix",
        ),
        (
            "ORD-06",
            uniform_rw(total_transactions=4000).clone(
                read_ratio=0.5,
                offered_rate=1.0,
                order_domain_weights=(0.25, 0.25, 0.25, 0.25),
                order_domain_release_ratio=(0.05, 0.05, 0.05, 0.05),
                order_domain_acquire_ratio=(0.05, 0.05, 0.05, 0.05),
            ),
            UNIFORM_4_50.clone(),
            0.05,
            0.05,
            0.0,
            True,
            "ooo_ordered_mix",
        ),
        (
            "ORD-07",
            single_word(total_transactions=3000).clone(
                read_ratio=0.0, offered_rate=2.0, order_release_ratio=0.50
            ),
            FIXED_8.clone(),
            0.50,
            0.0,
            0.0,
            False,
            "release_pathological",
        ),
        (
            "ORD-08",
            uniform_rw(total_transactions=4000).clone(
                read_ratio=0.55,
                offered_rate=1.25,
                order_release_ratio=0.03,
                order_acquire_ratio=0.02,
            ),
            UNIFORM_4_50.clone(),
            0.03,
            0.02,
            0.02,
            False,
            "ordering_atomics",
        ),
    ]:
        specs[exp_id] = ExperimentSpec(
            exp_id,
            "ord",
            f"Ordering experiment {exp_id}",
            "ordering_impact",
            BASE_HUB.clone(ooo_enable=ooo, ooo_runtime_enable=ooo),
            workload,
            latency.clone(),
            seed=700 + int(exp_id[-2:]),
            notes=_ord_notes(
                note,
                release_ratio=release_ratio,
                acquire_ratio=acquire_ratio,
                atomic_ratio=atomic_ratio,
                domains=_domain_count(workload),
                ooo=ooo,
            ),
        )

    for exp_id, atomic_ratio, seed in [
        ("ATOM-01", 0.0, 301),
        ("ATOM-02", 0.01, 302),
        ("ATOM-03", 0.10, 303),
        ("ATOM-04", 0.50, 304),
    ]:
        specs[exp_id] = ExperimentSpec(
            exp_id,
            "atom",
            f"Atomic ratio {atomic_ratio:.2f}",
            "standard",
            BASE_HUB.clone(),
            atomic_mix(total_transactions=4000).clone(atomic_ratio=atomic_ratio, offered_rate=0.75),
            FIXED_8.clone(),
            seed=seed,
        )

    for exp_id, description, seed in [
        ("ATOM-05", "Atomic correctness with concurrent reads", 320),
        ("ATOM-06", "Atomic saturation with internal priority", 321),
        ("ATOM-C01", "Atomic RMW atomicity", 322),
        ("ATOM-C02", "Atomic lock exclusion", 323),
        ("ATOM-C03", "Internal bypass during atomic lock", 324),
        ("ATOM-C04", "Atomic error handling", 325),
        ("ATOM-C05", "Atomic reply format", 326),
    ]:
        specs[exp_id] = ExperimentSpec(
            exp_id,
            "atom",
            description,
            "atom_check",
            BASE_HUB.clone(),
            atomic_mix(total_transactions=128).clone(atomic_ratio=0.5, offered_rate=1.0),
            FIXED_8.clone(),
            seed=seed,
        )

    for exp_id, length, depth, seed in [
        ("CRED-01", 64, 512, 401),
        ("CRED-02", 64, 128, 402),
        ("CRED-03", 256, 512, 403),
        ("CRED-04", 16, 512, 404),
    ]:
        workload = single_word(total_transactions=2500).clone(
            read_ratio=1.0 if exp_id != "CRED-04" else 0.5,
            length_mode="fixed",
            length_min=length,
            length_max=length,
            offered_rate=0.8,
        )
        specs[exp_id] = ExperimentSpec(
            exp_id,
            "cred",
            f"Credit experiment {exp_id}",
            "standard",
            BASE_HUB.clone(
                ext_down_pld_depth=depth,
                ext_up_pld_depth=depth,
            ),
            workload,
            UNIFORM_4_20.clone(),
            seed=seed,
        )

    specs["PRIO-01"] = ExperimentSpec(
        "PRIO-01",
        "prio",
        "External saturated baseline",
        "standard",
        BASE_HUB.clone(),
        single_word(total_transactions=3500).clone(read_ratio=1.0, offered_rate=1.0),
        UNIFORM_4_20.clone(),
        seed=501,
    )
    specs["PRIO-02"] = ExperimentSpec(
        "PRIO-02",
        "prio",
        "External saturated with periodic internal",
        "standard",
        BASE_HUB.clone(),
        single_word(total_transactions=3500).clone(read_ratio=1.0, int_ratio=0.02, offered_rate=1.0),
        UNIFORM_4_20.clone(),
        seed=502,
    )
    specs["PRIO-03"] = ExperimentSpec(
        "PRIO-03",
        "prio",
        "External saturated with burst internal",
        "standard",
        BASE_HUB.clone(),
        uniform_rw(total_transactions=3500).clone(read_ratio=0.8, int_ratio=0.05, length_min=1, length_max=4, offered_rate=1.0),
        UNIFORM_4_20.clone(),
        seed=503,
    )
    specs["PRIO-04"] = ExperimentSpec(
        "PRIO-04",
        "prio",
        "External atomics with internal traffic",
        "standard",
        BASE_HUB.clone(),
        atomic_mix(total_transactions=3500).clone(int_ratio=0.04, atomic_ratio=0.5, offered_rate=1.0),
        UNIFORM_4_50.clone(),
        seed=504,
    )

    specs["SIZE-01"] = ExperimentSpec(
        "SIZE-01",
        "size",
        "Outstanding depth sweep",
        "size_outstanding_sweep",
        BASE_HUB.clone(),
        single_word(total_transactions=3000).clone(read_ratio=1.0, offered_rate=0.8),
        UNIFORM_4_20.clone(),
        seed=601,
        sweep_values=SIZE_OUTSTANDING,
    )
    specs["SIZE-02"] = ExperimentSpec(
        "SIZE-02",
        "size",
        "Payload depth sweep",
        "size_payload_sweep",
        BASE_HUB.clone(),
        uniform_rw(total_transactions=3000).clone(read_ratio=0.7, length_min=1, length_max=64, offered_rate=0.8),
        UNIFORM_4_20.clone(),
        seed=602,
        sweep_values=SIZE_PAYLOAD,
    )
    specs["SIZE-03"] = ExperimentSpec(
        "SIZE-03",
        "size",
        "Internal header depth sweep",
        "size_internal_sweep",
        BASE_HUB.clone(),
        uniform_rw(total_transactions=3000).clone(read_ratio=0.7, int_ratio=0.2, length_min=1, length_max=8, offered_rate=0.8),
        UNIFORM_4_20.clone(),
        seed=603,
        sweep_values=SIZE_INT_HDR,
    )
    specs["SIZE-04"] = ExperimentSpec(
        "SIZE-04",
        "size",
        "Outstanding x payload joint sweep",
        "size_joint_sweep",
        BASE_HUB.clone(),
        uniform_rw(total_transactions=2500).clone(read_ratio=0.8, length_min=1, length_max=64, offered_rate=0.85),
        UNIFORM_4_20.clone(),
        seed=604,
        sweep_values=(4, 8, 16),
        sweep_secondary=(256, 512, 1024),
    )
    specs["SIZE-05"] = ExperimentSpec(
        "SIZE-05",
        "size",
        "feb_system realistic profile",
        "standard",
        BASE_HUB.clone(),
        feb_system_realistic(total_transactions=4500),
        ADDRESS_DEP.clone(),
        seed=605,
    )
    specs["SIZE-06"] = ExperimentSpec(
        "SIZE-06",
        "size",
        "Worst-case large read workload",
        "standard",
        BASE_HUB.clone(),
        single_word(total_transactions=2500).clone(read_ratio=1.0, length_mode="fixed", length_min=256, length_max=256, offered_rate=0.9),
        UNIFORM_4_20.clone(),
        seed=606,
    )
    return specs


EXPERIMENT_SPECS = _specs()


def categories() -> tuple[str, ...]:
    return ("frag", "rate", "ooo", "atom", "cred", "prio", "size", "ord")


def get_experiment(experiment_id: str) -> ExperimentSpec:
    return EXPERIMENT_SPECS[experiment_id]


def list_experiment_ids(category: str | None = None) -> list[str]:
    ids = sorted(EXPERIMENT_SPECS)
    if category is None:
        return ids
    return [exp_id for exp_id in ids if EXPERIMENT_SPECS[exp_id].category == category]
