from __future__ import annotations

import random

from include.sc_hub_tlm_config import LatencyModelConfig
from include.sc_hub_tlm_types import LatencyKind, ResponseCode

from .sc_hub_atomic import apply_atomic_rmw


class BusTargetModel:
    def __init__(self, cfg: LatencyModelConfig, seed: int) -> None:
        self.cfg = cfg
        self.rng = random.Random(seed)
        self.memory = [((idx * 0x9E3779B1) ^ 0x12345678) & 0xFFFFFFFF for idx in range(1 << 16)]

    def read(self, address: int, length: int) -> tuple[float, ResponseCode, list[int]]:
        latency, response = self._sample_latency(address, False)
        if response != ResponseCode.OK or not self._range_valid(address, length):
            return latency, response, [0xEEEEEEEE] * max(1, length)
        data = self.memory[address : address + length]
        return latency, ResponseCode.OK, data

    def write(self, address: int, words: list[int]) -> tuple[float, ResponseCode]:
        latency, response = self._sample_latency(address, True)
        if response != ResponseCode.OK or not self._range_valid(address, len(words)):
            return latency, response
        for idx, word in enumerate(words):
            self.memory[address + idx] = word & 0xFFFFFFFF
        return latency, ResponseCode.OK

    def atomic_rmw(
        self, address: int, mask: int, modify: int
    ) -> tuple[float, ResponseCode, int, int]:
        read_lat, response = self._sample_latency(address, False)
        if response != ResponseCode.OK or not self._range_valid(address, 1):
            return read_lat + self.cfg.atomic_overhead_ns, response, 0xEEEEEEEE, 0
        write_lat, write_response = self._sample_latency(address, True)
        if write_response != ResponseCode.OK:
            return read_lat + self.cfg.atomic_overhead_ns + write_lat, write_response, self.memory[address], 0
        old_value = self.memory[address]
        new_value = apply_atomic_rmw(old_value, mask, modify)
        self.memory[address] = new_value
        return read_lat + self.cfg.atomic_overhead_ns + write_lat, ResponseCode.OK, old_value, new_value

    def latency_stddev_hint(self) -> float:
        if self.cfg.kind == LatencyKind.FIXED:
            return 0.0
        if self.cfg.kind == LatencyKind.UNIFORM:
            span = self.cfg.uniform_read_max_ns - self.cfg.uniform_read_min_ns
            return span / (12.0 ** 0.5)
        if self.cfg.kind == LatencyKind.BIMODAL:
            fast = self.cfg.bimodal_fast_ns
            slow = self.cfg.bimodal_slow_ns
            prob = self.cfg.bimodal_fast_prob
            mean = prob * fast + (1.0 - prob) * slow
            variance = prob * (fast - mean) ** 2 + (1.0 - prob) * (slow - mean) ** 2
            return variance ** 0.5
        return 12.0

    def _range_valid(self, address: int, length: int) -> bool:
        return 0 <= address < len(self.memory) and address + max(length, 1) <= len(self.memory)

    def _sample_latency(self, address: int, is_write: bool) -> tuple[float, ResponseCode]:
        if self.cfg.error_rate > 0.0 and self.rng.random() < self.cfg.error_rate:
            latency = self.cfg.fixed_write_ns if is_write else self.cfg.fixed_read_ns
            return latency, ResponseCode.SLVERR

        if self.cfg.kind == LatencyKind.FIXED:
            return (self.cfg.fixed_write_ns if is_write else self.cfg.fixed_read_ns), ResponseCode.OK

        if self.cfg.kind == LatencyKind.UNIFORM:
            if is_write:
                return self.rng.uniform(self.cfg.uniform_write_min_ns, self.cfg.uniform_write_max_ns), ResponseCode.OK
            return self.rng.uniform(self.cfg.uniform_read_min_ns, self.cfg.uniform_read_max_ns), ResponseCode.OK

        if self.cfg.kind == LatencyKind.BIMODAL:
            choice = self.cfg.bimodal_fast_ns if self.rng.random() < self.cfg.bimodal_fast_prob else self.cfg.bimodal_slow_ns
            return choice, ResponseCode.OK

        return self._sample_address_latency(address)

    def _sample_address_latency(self, address: int) -> tuple[float, ResponseCode]:
        for region in self.cfg.address_regions:
            if region.start <= address <= region.end:
                latency = region.min_ns if region.kind == "fixed" else self.rng.uniform(region.min_ns, region.max_ns)
                if region.error:
                    return latency, ResponseCode.DECERR
                return latency, ResponseCode.OK
        return 50.0, ResponseCode.DECERR
