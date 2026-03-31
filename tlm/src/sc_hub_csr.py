from __future__ import annotations

from include.sc_hub_tlm_types import ResponseCode


class ScHubCsrModel:
    HUB_ID = 0x53480000
    HUB_VERSION = 0x1A08031F
    # sc_hub_pkg.vhd defines live RTL offsets through 0x017, so 0x018 is the
    # first free CSR word in the 0xFE80..0xFE9F window for the TLM-only OoO control.
    OOO_CTRL_OFFSET = 0x18

    def __init__(self, *, ooo_ctrl_enable: bool = False) -> None:
        self.ctrl = 0x1
        self.scratch = 0
        self.err_flags = 0
        self.err_count = 0
        self.ooo_ctrl_enable = bool(ooo_ctrl_enable)

    def read(self, offset: int, length: int) -> tuple[ResponseCode, list[int]]:
        if offset < 0 or offset + length > 32:
            return ResponseCode.DECERR, [0xEEEEEEEE]

        words: list[int] = []
        for idx in range(length):
            addr = offset + idx
            if addr == 0x0:
                words.append(self.HUB_ID)
            elif addr == 0x1:
                words.append(self.HUB_VERSION)
            elif addr == 0x2:
                words.append(self.ctrl)
            elif addr == 0x4:
                words.append(self.err_flags)
            elif addr == 0x5:
                words.append(self.err_count)
            elif addr == 0x6:
                words.append(self.scratch)
            elif addr == self.OOO_CTRL_OFFSET:
                words.append(int(self.ooo_ctrl_enable))
            else:
                words.append((0xC0000000 | addr) & 0xFFFFFFFF)
        return ResponseCode.OK, words

    def write(self, offset: int, words: list[int]) -> ResponseCode:
        if offset < 0 or offset >= 32 or len(words) > 1:
            self.err_flags |= 0x4
            self.err_count = min(self.err_count + 1, 0xFFFFFFFF)
            return ResponseCode.DECERR
        value = words[0] & 0xFFFFFFFF if words else 0
        if offset == 0x2:
            self.ctrl = value
        elif offset == 0x4:
            self.err_flags &= ~value
        elif offset == 0x6:
            self.scratch = value
        elif offset == self.OOO_CTRL_OFFSET:
            self.ooo_ctrl_enable = bool(value & 0x1)
        return ResponseCode.OK
