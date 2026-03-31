from __future__ import annotations

from include.sc_hub_tlm_config import HubConfig
from include.sc_hub_tlm_types import Route

from .sc_hub_hdr_fifo import ScHubHeaderFifo
from .sc_hub_pld_ram import ScHubPayloadRamModel


class ScHubBufferModel:
    def __init__(self, cfg: HubConfig) -> None:
        self.ext_down_hdr = ScHubHeaderFifo("ext_down_hdr", cfg.ext_hdr_depth)
        self.int_down_hdr = ScHubHeaderFifo("int_down_hdr", cfg.int_hdr_depth)
        self.ext_up_hdr = ScHubHeaderFifo("ext_up_hdr", cfg.ext_up_hdr_depth)
        self.int_up_hdr = ScHubHeaderFifo("int_up_hdr", cfg.int_up_hdr_depth)

        self.ext_down_pld = ScHubPayloadRamModel("ext_down_pld", cfg.ext_down_pld_depth)
        self.int_down_pld = ScHubPayloadRamModel("int_down_pld", cfg.int_down_pld_depth)
        self.ext_up_pld = ScHubPayloadRamModel("ext_up_pld", cfg.ext_up_pld_depth)
        self.int_up_pld = ScHubPayloadRamModel("int_up_pld", cfg.int_up_pld_depth)

    def down_hdr(self, route: Route) -> ScHubHeaderFifo:
        return self.ext_down_hdr if route == Route.EXT else self.int_down_hdr

    def up_hdr(self, route: Route) -> ScHubHeaderFifo:
        return self.ext_up_hdr if route == Route.EXT else self.int_up_hdr

    def down_pld(self, route: Route) -> ScHubPayloadRamModel:
        return self.ext_down_pld if route == Route.EXT else self.int_down_pld

    def up_pld(self, route: Route) -> ScHubPayloadRamModel:
        return self.ext_up_pld if route == Route.EXT else self.int_up_pld

    def aggregate_frag_cost(self) -> float:
        pools = (
            self.ext_down_pld,
            self.int_down_pld,
            self.ext_up_pld,
            self.int_up_pld,
        )
        non_zero = [pool.get_fragmentation_cost() for pool in pools if pool.depth > 0]
        if not non_zero:
            return 0.0
        return sum(non_zero) / len(non_zero)

    def aggregate_free_count(self) -> int:
        return sum(
            pool.get_free_count()
            for pool in (
                self.ext_down_pld,
                self.int_down_pld,
                self.ext_up_pld,
                self.int_up_pld,
            )
        )

    def aggregate_peak_used(self) -> int:
        return sum(
            pool.get_peak_used()
            for pool in (
                self.ext_down_pld,
                self.int_down_pld,
                self.ext_up_pld,
                self.int_up_pld,
            )
        )

    def upload_utilization(self) -> tuple[int, int]:
        used = self.ext_up_pld.get_used() + self.int_up_pld.get_used()
        total = self.ext_up_pld.depth + self.int_up_pld.depth
        return used, total

    def integrity_check(self) -> bool:
        return all(
            pool.integrity_check()
            for pool in (
                self.ext_down_pld,
                self.int_down_pld,
                self.ext_up_pld,
                self.int_up_pld,
            )
        )
