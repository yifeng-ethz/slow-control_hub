from __future__ import annotations

from include.sc_hub_tlm_config import HubConfig
from include.sc_hub_tlm_types import Route, TxState

from .sc_hub_buffer import ScHubBufferModel


class ScHubAdmitCtrlModel:
    def __init__(self, cfg: HubConfig) -> None:
        self.cfg = cfg

    def try_admit(
        self,
        tx: TxState,
        now_ns: float,
        buffers: ScHubBufferModel,
        ext_active: int,
        int_active: int,
        dispatch_order_used: int,
    ) -> tuple[bool, str | None]:
        cmd = tx.command
        total_active = ext_active + int_active
        if total_active >= self.cfg.outstanding_limit:
            return False, "outstanding_total"
        if cmd.route == Route.EXT and ext_active >= self.cfg.ext_outstanding_max:
            return False, "outstanding_ext"

        down_hdr = buffers.down_hdr(cmd.route)
        if not down_hdr.has_space():
            return False, f"{cmd.route.value}_down_hdr_full"

        if dispatch_order_used >= self.cfg.outstanding_limit:
            return False, "cmd_order_full"

        alloc = None
        alloc_latency_ns = 0.0
        if cmd.needs_payload:
            down_pld = buffers.down_pld(cmd.route)
            if down_pld.get_free_count() < cmd.length:
                return False, f"{cmd.route.value}_down_pld_empty"
            alloc = down_pld.allocate(cmd.length)
            if alloc is None:
                return False, f"{cmd.route.value}_down_pld_empty"
            alloc_latency_ns = alloc.alloc_latency_ns
            down_pld.write_chain(alloc, cmd.payload_words)

        if not down_hdr.push(cmd.seq):
            if alloc is not None:
                buffers.down_pld(cmd.route).free(alloc)
            return False, f"{cmd.route.value}_down_hdr_push_fail"

        tx.down_payload = alloc
        tx.alloc_latency_ns_total += alloc_latency_ns
        tx.admitted_ns = now_ns
        tx.queue_wait_ns = now_ns - tx.command.arrival_ns
        return True, None
