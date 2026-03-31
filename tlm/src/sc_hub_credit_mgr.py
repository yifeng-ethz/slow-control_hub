from __future__ import annotations

from include.sc_hub_tlm_types import PayloadAllocation, Route

from .sc_hub_buffer import ScHubBufferModel


class ScHubCreditManagerModel:
    def has_reply_resources(self, buffers: ScHubBufferModel, route: Route, length: int) -> tuple[bool, str | None]:
        up_hdr = buffers.up_hdr(route)
        if not up_hdr.has_space():
            return False, f"{route.value}_up_hdr_full"
        if length > 0 and buffers.up_pld(route).get_free_count() < length:
            return False, f"{route.value}_up_credit_empty"
        return True, None

    def reserve_reply_resources(
        self, buffers: ScHubBufferModel, route: Route, length: int
    ) -> tuple[bool, PayloadAllocation | None, str | None]:
        ok, reason = self.has_reply_resources(buffers, route, length)
        if not ok:
            return False, None, reason

        if length <= 0:
            return True, None, None

        up_pld = buffers.up_pld(route)
        alloc = up_pld.allocate(length)
        if alloc is None:
            return False, None, f"{route.value}_up_credit_empty"
        return True, alloc, None
