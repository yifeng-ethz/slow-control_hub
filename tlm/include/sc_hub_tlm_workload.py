from __future__ import annotations

from dataclasses import replace

from .sc_hub_tlm_config import AddressRegion, WorkloadConfig


def uniform_rw(name: str = "uniform_rw", total_transactions: int = 4096) -> WorkloadConfig:
    return WorkloadConfig(name=name, total_transactions=total_transactions)


def read_heavy(name: str = "read_heavy", total_transactions: int = 4096) -> WorkloadConfig:
    return WorkloadConfig(
        name=name,
        total_transactions=total_transactions,
        read_ratio=0.8,
        length_mode="uniform",
        length_min=1,
        length_max=64,
    )


def write_heavy(name: str = "write_heavy", total_transactions: int = 4096) -> WorkloadConfig:
    return WorkloadConfig(
        name=name,
        total_transactions=total_transactions,
        read_ratio=0.2,
        length_mode="uniform",
        length_min=1,
        length_max=64,
    )


def single_word(name: str = "single_word", total_transactions: int = 4096) -> WorkloadConfig:
    return WorkloadConfig(
        name=name,
        total_transactions=total_transactions,
        length_mode="fixed",
        length_min=1,
        length_max=1,
        length_short=1,
        length_long=1,
    )


def max_burst(name: str = "max_burst", total_transactions: int = 2048) -> WorkloadConfig:
    return WorkloadConfig(
        name=name,
        total_transactions=total_transactions,
        length_mode="fixed",
        length_min=256,
        length_max=256,
        length_short=256,
        length_long=256,
    )


def bimodal(name: str = "bimodal", total_transactions: int = 4096) -> WorkloadConfig:
    return WorkloadConfig(
        name=name,
        total_transactions=total_transactions,
        length_mode="bimodal",
        length_short=1,
        length_long=256,
        long_probability=0.3,
    )


def csr_heavy(name: str = "csr_heavy", total_transactions: int = 4096) -> WorkloadConfig:
    return WorkloadConfig(
        name=name,
        total_transactions=total_transactions,
        offered_rate=0.7,
        read_ratio=0.6,
        int_ratio=0.6,
        length_mode="uniform",
        length_min=1,
        length_max=8,
    )


def atomic_mix(name: str = "atomic_mix", total_transactions: int = 4096) -> WorkloadConfig:
    return WorkloadConfig(
        name=name,
        total_transactions=total_transactions,
        offered_rate=0.6,
        read_ratio=0.6,
        atomic_ratio=0.1,
        length_mode="uniform",
        length_min=1,
        length_max=32,
    )


def feb_system_realistic(
    name: str = "feb_system_realistic", total_transactions: int = 6000
) -> WorkloadConfig:
    return WorkloadConfig(
        name=name,
        total_transactions=total_transactions,
        offered_rate=0.7,
        reference_service_ns=10.0,
        interarrival_mode="poisson",
        read_ratio=0.7,
        int_ratio=0.15,
        atomic_ratio=0.02,
        length_mode="bimodal",
        length_short=1,
        length_long=16,
        long_probability=0.25,
        external_regions=(
            AddressRegion("frame_rcv", 0x8000, 0x87FF, 0.50),
            AddressRegion("scratch", 0x0000, 0x03FF, 0.20),
            AddressRegion("histogram", 0xC000, 0xC1FF, 0.10),
            AddressRegion("ring_buf_cam", 0xA000, 0xA7FF, 0.05),
            AddressRegion("other", 0x4000, 0x40FF, 0.15),
        ),
    )


def ordered_publish(
    name: str = "ordered_publish",
    total_transactions: int = 4096,
    release_ratio: float = 0.05,
    domain_id: int = 1,
) -> WorkloadConfig:
    return WorkloadConfig(
        name=name,
        total_transactions=total_transactions,
        offered_rate=0.85,
        read_ratio=0.0,
        length_mode="fixed",
        length_min=1,
        length_max=1,
        order_release_ratio=release_ratio,
        order_acquire_ratio=0.0,
        order_domain_weights=(1.0,),
        order_default_domain=domain_id,
    )


def ordered_consume(
    name: str = "ordered_consume",
    total_transactions: int = 4096,
    acquire_ratio: float = 0.05,
    domain_id: int = 1,
) -> WorkloadConfig:
    return WorkloadConfig(
        name=name,
        total_transactions=total_transactions,
        offered_rate=0.85,
        read_ratio=1.0,
        length_mode="fixed",
        length_min=1,
        length_max=1,
        order_release_ratio=0.0,
        order_acquire_ratio=acquire_ratio,
        order_domain_weights=(1.0,),
        order_default_domain=domain_id,
    )


def ordered_pub_con(
    name: str = "ordered_pub_con",
    total_transactions: int = 4096,
    release_ratio: float = 0.02,
    acquire_ratio: float = 0.02,
    domain_id: int = 1,
) -> WorkloadConfig:
    return WorkloadConfig(
        name=name,
        total_transactions=total_transactions,
        offered_rate=0.85,
        read_ratio=0.5,
        length_mode="fixed",
        length_min=1,
        length_max=1,
        order_release_ratio=release_ratio,
        order_acquire_ratio=acquire_ratio,
        order_domain_weights=(1.0,),
        order_default_domain=domain_id,
    )


def multi_domain(
    name: str = "multi_domain",
    total_transactions: int = 4096,
    domain_weights: tuple[float, ...] = (0.5, 0.5),
    domain_release_ratio: tuple[float, ...] = (0.0, 0.0),
    domain_acquire_ratio: tuple[float, ...] = (0.10, 0.0),
) -> WorkloadConfig:
    return WorkloadConfig(
        name=name,
        total_transactions=total_transactions,
        offered_rate=0.85,
        read_ratio=1.0,
        length_mode="fixed",
        length_min=1,
        length_max=1,
        order_domain_weights=domain_weights,
        order_domain_release_ratio=domain_release_ratio,
        order_domain_acquire_ratio=domain_acquire_ratio,
        order_default_domain=0,
    )


WORKLOAD_BUILDERS = {
    "uniform_rw": uniform_rw,
    "read_heavy": read_heavy,
    "write_heavy": write_heavy,
    "single_word": single_word,
    "max_burst": max_burst,
    "bimodal": bimodal,
    "csr_heavy": csr_heavy,
    "atomic_mix": atomic_mix,
    "feb_system_realistic": feb_system_realistic,
    "ordered_publish": ordered_publish,
    "ordered_consume": ordered_consume,
    "ordered_pub_con": ordered_pub_con,
    "multi_domain": multi_domain,
}


def with_offered_rate(cfg: WorkloadConfig, offered_rate: float) -> WorkloadConfig:
    return replace(cfg, offered_rate=offered_rate)
