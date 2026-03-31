from __future__ import annotations

from dataclasses import dataclass, field, replace

from .sc_hub_tlm_types import LatencyKind


@dataclass(slots=True)
class AddressRegion:
    name: str
    start: int
    end: int
    weight: float


@dataclass(slots=True)
class AddressLatencyRegion:
    name: str
    start: int
    end: int
    kind: str
    min_ns: float
    max_ns: float
    error: bool = False


@dataclass(slots=True)
class HubConfig:
    outstanding_limit: int = 8
    outstanding_int_reserved: int = 2
    ext_hdr_depth: int = 8
    int_hdr_depth: int = 4
    ext_up_hdr_depth: int = 8
    int_up_hdr_depth: int = 4
    ext_down_pld_depth: int = 512
    int_down_pld_depth: int = 64
    ext_up_pld_depth: int = 512
    int_up_pld_depth: int = 64
    ext_issue_limit: int = 8
    int_issue_limit: int = 1
    ooo_enable: bool = False
    ooo_runtime_enable: bool = False
    reply_assembly_base_ns: float = 4.0
    dispatch_latency_ns: float = 2.0
    internal_read_setup_ns: float = 1.0
    internal_write_latency_ns: float = 2.0
    s_and_f_overhead_ns: float = 5.0
    max_burst_words: int = 256

    @property
    def ext_outstanding_max(self) -> int:
        return max(1, self.outstanding_limit - self.outstanding_int_reserved)

    def clone(self, **kwargs: object) -> "HubConfig":
        return replace(self, **kwargs)


@dataclass(slots=True)
class LatencyModelConfig:
    kind: LatencyKind = LatencyKind.FIXED
    fixed_read_ns: float = 8.0
    fixed_write_ns: float = 4.0
    uniform_read_min_ns: float = 4.0
    uniform_read_max_ns: float = 20.0
    uniform_write_min_ns: float = 4.0
    uniform_write_max_ns: float = 8.0
    bimodal_fast_ns: float = 4.0
    bimodal_slow_ns: float = 40.0
    bimodal_fast_prob: float = 0.5
    error_rate: float = 0.0
    atomic_overhead_ns: float = 3.0
    address_regions: tuple[AddressLatencyRegion, ...] = field(
        default_factory=lambda: (
            AddressLatencyRegion("scratch", 0x0000, 0x03FF, "fixed", 2.0, 2.0),
            AddressLatencyRegion("frame_rcv", 0x8000, 0x87FF, "uniform", 4.0, 12.0),
            AddressLatencyRegion("ring_buf_cam", 0xA000, 0xA7FF, "uniform", 8.0, 20.0),
            AddressLatencyRegion("histogram", 0xC000, 0xC1FF, "uniform", 6.0, 16.0),
            AddressLatencyRegion("unmapped", 0x0000, 0xFFFF, "fixed", 50.0, 50.0, True),
        )
    )

    def clone(self, **kwargs: object) -> "LatencyModelConfig":
        return replace(self, **kwargs)


@dataclass(slots=True)
class WorkloadConfig:
    name: str
    total_transactions: int = 4096
    offered_rate: float = 0.5
    reference_service_ns: float = 8.0
    interarrival_mode: str = "deterministic"
    read_ratio: float = 0.5
    int_ratio: float = 0.0
    atomic_ratio: float = 0.0
    length_mode: str = "uniform"
    length_min: int = 1
    length_max: int = 256
    length_short: int = 1
    length_long: int = 256
    long_probability: float = 0.3
    external_regions: tuple[AddressRegion, ...] = field(
        default_factory=lambda: (
            AddressRegion("scratch", 0x0000, 0x03FF, 0.25),
            AddressRegion("frame_rcv", 0x8000, 0x87FF, 0.40),
            AddressRegion("ring_buf_cam", 0xA000, 0xA7FF, 0.15),
            AddressRegion("histogram", 0xC000, 0xC1FF, 0.15),
            AddressRegion("other", 0x4000, 0x40FF, 0.05),
        )
    )
    order_domain_weights: tuple[float, ...] = (1.0,)
    order_domain_release_ratio: tuple[float, ...] = ()
    order_domain_acquire_ratio: tuple[float, ...] = ()
    order_release_ratio: float = 0.0
    order_acquire_ratio: float = 0.0
    order_scope: int = 0
    order_default_domain: int = 0
    internal_csr_base: int = 0xFE80
    internal_csr_words: int = 32
    payload_seed_stride: int = 17

    def clone(self, **kwargs: object) -> "WorkloadConfig":
        return replace(self, **kwargs)


@dataclass(slots=True)
class ExperimentSpec:
    experiment_id: str
    category: str
    description: str
    mode: str
    hub: HubConfig
    workload: WorkloadConfig
    latency: LatencyModelConfig
    seed: int = 1
    offered_rates: tuple[float, ...] = ()
    sweep_values: tuple[int, ...] = ()
    sweep_secondary: tuple[int, ...] = ()
    pair_compare: bool = False
    notes: str = ""
