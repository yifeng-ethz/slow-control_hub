from __future__ import annotations

import random

from include.sc_hub_tlm_config import AddressRegion, WorkloadConfig
from include.sc_hub_tlm_types import OpType, OrderType, Route, SCCommand


class ScPktSource:
    def __init__(self, cfg: WorkloadConfig, seed: int) -> None:
        self.cfg = cfg
        self.rng = random.Random(seed)
        self._alternate_long = False
        self._ord_epoch = [0] * 16

    def generate(self) -> list[SCCommand]:
        commands: list[SCCommand] = []
        time_ns = 0.0
        for seq in range(self.cfg.total_transactions):
            gap = self._sample_gap()
            time_ns += gap
            route = Route.INT if self.rng.random() < self.cfg.int_ratio else Route.EXT
            atomic = route == Route.EXT and self.rng.random() < self.cfg.atomic_ratio
            op = OpType.READ if self.rng.random() < self.cfg.read_ratio else OpType.WRITE
            length = self._sample_length()
            if route == Route.INT and op == OpType.WRITE:
                length = 1
            if atomic:
                op = OpType.READ
                length = 1
            ord_dom_id = self._sample_order_domain()
            order = self._sample_order(ord_dom_id, op, atomic)
            ord_epoch = self._next_ord_epoch(ord_dom_id)
            address, region_name = self._sample_address(route)
            payload = []
            if op == OpType.WRITE:
                payload = [
                    ((seq * self.cfg.payload_seed_stride) + address + idx * 7) & 0xFFFFFFFF
                    for idx in range(length)
                ]
            commands.append(
                SCCommand(
                    seq=seq,
                    arrival_ns=time_ns,
                    route=route,
                    op=op,
                    address=address,
                    length=length,
                    order=order,
                    ord_dom_id=ord_dom_id,
                    ord_epoch=ord_epoch,
                    ord_scope=self.cfg.order_scope,
                    atomic_flag=atomic,
                    atomic_mask=0xFFFF00FF,
                    atomic_modify=(seq * 0x01010101) & 0xFFFFFFFF,
                    payload_words=payload,
                    metadata={"region": region_name},
                )
            )
        return commands

    def _sample_gap(self) -> float:
        mean_gap_ns = self.cfg.reference_service_ns / max(self.cfg.offered_rate, 1e-3)
        if self.cfg.interarrival_mode == "poisson":
            return self.rng.expovariate(1.0 / mean_gap_ns)
        return mean_gap_ns

    def _sample_length(self) -> int:
        if self.cfg.length_mode == "fixed":
            return self.cfg.length_min
        if self.cfg.length_mode == "alternating":
            self._alternate_long = not self._alternate_long
            return self.cfg.length_long if self._alternate_long else self.cfg.length_short
        if self.cfg.length_mode == "bimodal":
            if self.rng.random() < self.cfg.long_probability:
                return self.cfg.length_long
            return self.cfg.length_short
        return self.rng.randint(self.cfg.length_min, self.cfg.length_max)

    def _sample_address(self, route: Route) -> tuple[int, str]:
        if route == Route.INT:
            offset = self.rng.randint(0, self.cfg.internal_csr_words - 1)
            return self.cfg.internal_csr_base + offset, "csr"
        region = self._weighted_region(self.cfg.external_regions)
        return self.rng.randint(region.start, region.end), region.name

    def _weighted_region(self, regions: tuple[AddressRegion, ...]) -> AddressRegion:
        total = sum(region.weight for region in regions)
        pick = self.rng.random() * total
        running = 0.0
        for region in regions:
            running += region.weight
            if pick <= running:
                return region
        return regions[-1]

    def _sample_order_domain(self) -> int:
        weights = self.cfg.order_domain_weights
        if not weights:
            return 0
        if len(weights) == 1:
            return min(max(int(self.cfg.order_default_domain), 0), 15)
        total = sum(max(0.0, float(value)) for value in weights)
        if total <= 0.0:
            return int(self.cfg.order_default_domain)
        pick = self.rng.random() * total
        running = 0.0
        for domain, weight in enumerate(weights):
            running += max(0.0, float(weight))
            if pick <= running:
                return min(domain, 15)
        return min(len(weights) - 1, 15)

    def _domain_order_rates(self, domain: int) -> tuple[float, float]:
        if self.cfg.order_domain_release_ratio:
            rel_dom = min(max(int(domain), 0), max(len(self.cfg.order_domain_release_ratio) - 1, 0))
            release = float(self.cfg.order_domain_release_ratio[rel_dom])
        else:
            release = float(self.cfg.order_release_ratio)

        if self.cfg.order_domain_acquire_ratio:
            acq_dom = min(max(int(domain), 0), max(len(self.cfg.order_domain_acquire_ratio) - 1, 0))
            acquire = float(self.cfg.order_domain_acquire_ratio[acq_dom])
        else:
            acquire = float(self.cfg.order_acquire_ratio)

        return release, acquire

    def _sample_order(self, domain: int, op: OpType, atomic: bool) -> OrderType:
        if atomic:
            return OrderType.RELAXED
        release_ratio, acquire_ratio = self._domain_order_rates(domain)
        if op == OpType.WRITE:
            acquire_ratio = 0.0
        elif op == OpType.READ:
            release_ratio = 0.0
        total = max(0.0, release_ratio) + max(0.0, acquire_ratio)
        pick = self.rng.random()
        if pick < release_ratio:
            return OrderType.RELEASE
        if pick < release_ratio + acquire_ratio:
            return OrderType.ACQUIRE
        return OrderType.RELAXED

    def _next_ord_epoch(self, domain: int) -> int:
        dom = min(max(int(domain), 0), 15)
        self._ord_epoch[dom] = (self._ord_epoch[dom] + 1) & 0xFF
        return self._ord_epoch[dom]
