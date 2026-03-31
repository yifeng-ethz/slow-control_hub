from __future__ import annotations

from include.sc_hub_tlm_config import HubConfig
from include.sc_hub_tlm_types import SCCommand


class ScHubPktRxModel:
    def __init__(self, cfg: HubConfig) -> None:
        self.cfg = cfg

    def packet_ready_ns(self, cmd: SCCommand) -> float:
        return cmd.arrival_ns + self.cfg.s_and_f_overhead_ns + float(cmd.length)
