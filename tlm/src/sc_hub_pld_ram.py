from __future__ import annotations

from include.sc_hub_tlm_types import PayloadAllocation

from .sc_hub_malloc import ScHubMallocModel


class ScHubPayloadRamModel:
    def __init__(self, name: str, depth: int) -> None:
        self.name = name
        self.depth = depth
        self.malloc = ScHubMallocModel(depth, name)
        self._alloc_words: dict[int, int] = {}

    def allocate(self, words: int) -> PayloadAllocation | None:
        alloc = self.malloc.malloc(words)
        if alloc is None:
            return None
        self._alloc_words[alloc.head_ptr] = alloc.words
        return alloc

    def write_chain(self, alloc: PayloadAllocation, data_words: list[int]) -> tuple[int, float]:
        chain = self.malloc.walk_chain(alloc.head_ptr)
        for ptr, data in zip(chain, data_words):
            self.malloc.ram[ptr].data = data & 0xFFFFFFFF
        _, hops, latency = self.malloc.record_access(alloc.head_ptr)
        return hops, latency

    def read_chain(self, alloc: PayloadAllocation) -> tuple[list[int], int, float]:
        chain, hops, latency = self.malloc.record_access(alloc.head_ptr)
        data_words = [self.malloc.ram[ptr].data for ptr in chain]
        return data_words, hops, latency

    def free(self, alloc: PayloadAllocation | None) -> int:
        if alloc is None or alloc.head_ptr < 0:
            return 0
        expected_words = self._alloc_words.get(alloc.head_ptr)
        if expected_words is None:
            return 0
        if expected_words != alloc.words:
            return 0
        freed = self.malloc.free(alloc.head_ptr)
        if freed == 0:
            return 0
        self._alloc_words.pop(alloc.head_ptr, None)
        return freed

    def get_free_count(self) -> int:
        return self.malloc.get_free_count()

    def get_used(self) -> int:
        return self.malloc.current_used()

    def get_peak_used(self) -> int:
        return self.malloc.peak_used

    def get_fragmentation_cost(self) -> float:
        return self.malloc.get_fragmentation_cost()

    def integrity_check(self) -> bool:
        return self.malloc.integrity_check()
