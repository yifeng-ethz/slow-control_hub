from __future__ import annotations

from dataclasses import dataclass

from include.sc_hub_tlm_types import PayloadAllocation


@dataclass(slots=True)
class RamLine:
    data: int = 0
    next_ptr: int = -1
    is_last: bool = False
    is_free: bool = True


class ScHubMallocModel:
    def __init__(self, ram_depth: int, pool_name: str) -> None:
        self.ram_depth = ram_depth
        self.pool_name = pool_name
        self.ram = [RamLine() for _ in range(ram_depth)]
        self.total_allocs = 0
        self.total_frees = 0
        self.total_alloc_words = 0
        self.total_free_words = 0
        self.peak_used = 0
        self.alloc_failures = 0
        self.total_pointer_hops = 0
        self.total_words_accessed = 0
        self.free_count_trace: list[int] = []
        self._init_free_list()

    def _init_free_list(self) -> None:
        for idx, line in enumerate(self.ram):
            line.data = 0
            line.is_free = True
            line.next_ptr = idx + 1 if idx < self.ram_depth - 1 else -1
            line.is_last = idx == self.ram_depth - 1
        self.free_head = 0 if self.ram_depth else -1
        self.free_count = self.ram_depth

    def malloc(self, size: int) -> PayloadAllocation | None:
        if size <= 0:
            return PayloadAllocation(-1, 0, 0, 0.0, self.pool_name)
        if self.free_count < size:
            self.alloc_failures += 1
            return None

        collected: list[int] = []
        current = self.free_head
        for _ in range(size):
            if current < 0:
                self.alloc_failures += 1
                return None
            collected.append(current)
            current = self.ram[current].next_ptr

        self.free_head = current
        for idx, ptr in enumerate(collected):
            line = self.ram[ptr]
            line.is_free = False
            line.next_ptr = collected[idx + 1] if idx + 1 < size else -1
            line.is_last = idx == size - 1

        self.free_count -= size
        self.total_allocs += 1
        self.total_alloc_words += size
        self.peak_used = max(self.peak_used, self.ram_depth - self.free_count)
        self.free_count_trace.append(self.free_count)
        return PayloadAllocation(
            head_ptr=collected[0],
            words=size,
            pointer_hops=self._chain_pointer_hops(collected),
            alloc_latency_ns=float(size * 2),
            pool_name=self.pool_name,
        )

    def free(self, head_ptr: int) -> int:
        if head_ptr < 0 or head_ptr >= self.ram_depth:
            return 0
        chain = self._walk_allocated_chain(head_ptr)
        if not chain:
            return 0
        if any(self.ram[ptr].is_free for ptr in chain):
            return 0

        for ptr in chain:
            self.ram[ptr].is_free = True
        last_ptr = chain[-1]
        self.ram[last_ptr].next_ptr = self.free_head
        self.ram[last_ptr].is_last = self.free_head < 0
        self.free_head = head_ptr
        self.free_count += len(chain)
        self.total_frees += 1
        self.total_free_words += len(chain)
        self.free_count_trace.append(self.free_count)
        return len(chain)

    def walk_chain(self, head_ptr: int) -> list[int]:
        if head_ptr < 0:
            return []
        chain: list[int] = []
        current = head_ptr
        visited: set[int] = set()
        while current >= 0 and current not in visited and current < self.ram_depth:
            visited.add(current)
            chain.append(current)
            line = self.ram[current]
            if line.is_last:
                break
            current = line.next_ptr
        return chain

    def _walk_allocated_chain(self, head_ptr: int) -> list[int]:
        chain: list[int] = []
        current = head_ptr
        visited: set[int] = set()
        while current >= 0 and current < self.ram_depth:
            if current in visited:
                return []
            visited.add(current)
            line = self.ram[current]
            if line.is_free:
                return []
            chain.append(current)
            if line.is_last:
                break
            current = line.next_ptr
            if current < 0:
                return []
        return chain

    def get_free_count(self) -> int:
        return self.free_count

    def get_fragmentation_cost(self) -> float:
        if self.total_words_accessed == 0:
            return 0.0
        return self.total_pointer_hops / self.total_words_accessed

    def record_access(self, head_ptr: int) -> tuple[list[int], int, float]:
        chain = self.walk_chain(head_ptr)
        hops = self._chain_pointer_hops(chain)
        self.total_pointer_hops += hops
        self.total_words_accessed += len(chain)
        return chain, hops, float(len(chain) + hops)

    def current_used(self) -> int:
        return self.ram_depth - self.free_count

    def integrity_check(self) -> bool:
        free_seen: set[int] = set()
        current = self.free_head
        while current >= 0:
            if current in free_seen:
                return False
            free_seen.add(current)
            current = self.ram[current].next_ptr
        return len(free_seen) == self.free_count

    @staticmethod
    def _chain_pointer_hops(chain: list[int]) -> int:
        hops = 0
        for lhs, rhs in zip(chain, chain[1:]):
            if rhs != lhs + 1:
                hops += 1
        return hops
