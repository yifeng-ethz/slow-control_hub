from __future__ import annotations


def apply_atomic_rmw(read_value: int, mask: int, modify: int) -> int:
    return ((read_value & (~mask & 0xFFFFFFFF)) | (modify & mask)) & 0xFFFFFFFF
