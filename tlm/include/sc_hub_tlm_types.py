from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum
from typing import Any


class Route(str, Enum):
    EXT = "ext"
    INT = "int"


class OpType(str, Enum):
    READ = "read"
    WRITE = "write"


class ResponseCode(str, Enum):
    OK = "OK"
    SLVERR = "SLVERR"
    DECERR = "DECERR"


class LatencyKind(str, Enum):
    FIXED = "fixed"
    UNIFORM = "uniform"
    BIMODAL = "bimodal"
    ADDRESS = "address"


@dataclass(slots=True)
class PayloadAllocation:
    head_ptr: int
    words: int
    pointer_hops: int
    alloc_latency_ns: float
    pool_name: str

class OrderType(str, Enum):
    RELAXED = "relaxed"
    RELEASE = "release"
    ACQUIRE = "acquire"
    RSVD = "reserved"


@dataclass(slots=True)
class SCCommand:
    seq: int
    arrival_ns: float
    route: Route
    op: OpType
    address: int
    length: int
    order: OrderType = OrderType.RELAXED
    ord_dom_id: int = 0
    ord_epoch: int = 0
    ord_scope: int = 0
    fpga_id: int = 0
    masks: int = 0
    atomic_flag: bool = False
    atomic_mask: int = 0xFFFFFFFF
    atomic_modify: int = 0
    payload_words: list[int] = field(default_factory=list)
    metadata: dict[str, Any] = field(default_factory=dict)

    @property
    def needs_payload(self) -> bool:
        return self.op == OpType.WRITE

    @property
    def is_reply_suppressed(self) -> bool:
        return self.masks != 0


@dataclass(slots=True)
class TxState:
    command: SCCommand
    packet_ready_ns: float
    release_drain_ns: float = 0.0
    acquire_hold_ns: float = 0.0
    admitted_ns: float | None = None
    dispatch_ns: float | None = None
    complete_ns: float | None = None
    reply_start_ns: float | None = None
    reply_done_ns: float | None = None
    response: ResponseCode = ResponseCode.OK
    bus_latency_ns: float = 0.0
    service_latency_ns: float = 0.0
    down_payload: PayloadAllocation | None = None
    up_payload: PayloadAllocation | None = None
    payload_access_hops: int = 0
    alloc_latency_ns_total: float = 0.0
    response_words: list[int] = field(default_factory=list)
    ready_for_reply: bool = False
    reply_scheduled: bool = False
    queue_wait_ns: float = 0.0
    dispatch_wait_ns: float = 0.0
    note: str = ""
