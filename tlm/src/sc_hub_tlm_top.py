from __future__ import annotations

from include.sc_hub_tlm_config import HubConfig, LatencyModelConfig, WorkloadConfig

from .sc_hub_model import ScHubModel
from .sc_pkt_source import ScPktSource


class ScHubTlmTop:
    def __init__(self, hub_cfg: HubConfig, latency_cfg: LatencyModelConfig, workload_cfg: WorkloadConfig, seed: int) -> None:
        self.hub_cfg = hub_cfg
        self.latency_cfg = latency_cfg
        self.workload_cfg = workload_cfg
        self.seed = seed

    def run(self):
        source = ScPktSource(self.workload_cfg, self.seed)
        commands = source.generate()
        model = ScHubModel(self.hub_cfg, self.latency_cfg, self.seed)
        return model.run(commands)
