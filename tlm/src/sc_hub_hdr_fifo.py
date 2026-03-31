from __future__ import annotations

from collections import deque


class ScHubHeaderFifo:
    def __init__(self, name: str, depth: int) -> None:
        self.name = name
        self.depth = depth
        self._entries: deque[int] = deque()

    def __len__(self) -> int:
        return len(self._entries)

    def has_space(self) -> bool:
        return len(self._entries) < self.depth

    def push(self, seq: int) -> bool:
        if not self.has_space():
            return False
        self._entries.append(seq)
        return True

    def peek(self) -> int | None:
        if not self._entries:
            return None
        return self._entries[0]

    def pop(self) -> int | None:
        if not self._entries:
            return None
        return self._entries.popleft()

    def discard(self, seq: int) -> bool:
        try:
            self._entries.remove(seq)
            return True
        except ValueError:
            return False

    def used(self) -> int:
        return len(self._entries)
