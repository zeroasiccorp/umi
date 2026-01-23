from dataclasses import dataclass
from enum import IntEnum
from typing import Any

from cocotb.triggers import RisingEdge
from cocotb.handle import SimHandleBase

from cocotb_bus.monitors import BusMonitor


class TLDOpcode(IntEnum):
    """TileLink D-channel opcodes"""
    AccessAck = 0
    AccessAckData = 1
    HintAck = 2


@dataclass
class TLDResponse:
    """TileLink D-channel response"""
    opcode: int
    param: int
    size: int
    source: int
    sink: int
    denied: bool
    data: int
    corrupt: bool

    def is_read_response(self) -> bool:
        return self.opcode == TLDOpcode.AccessAckData

    def is_write_response(self) -> bool:
        return self.opcode == TLDOpcode.AccessAck


class TLMonitor(BusMonitor):
    """TileLink D-channel monitor"""

    _signals = [
        "valid",
        "ready",
        "opcode",
        "param",
        "size",
        "source",
        "sink",
        "denied",
        "data",
        "corrupt",
    ]

    _optional_signals = []

    def __init__(
        self,
        entity: SimHandleBase,
        name: str,
        clock: SimHandleBase,
        ready_default: int = 1,
        **kwargs: Any,
    ):
        BusMonitor.__init__(self, entity, name, clock, **kwargs)
        self.clock = clock
        # Drive ready signal
        self.bus.ready.value = ready_default

    def set_ready(self, value: int) -> None:
        """Control backpressure by setting ready signal"""
        self.bus.ready.value = value

    async def _monitor_recv(self) -> None:
        """Monitor D-channel for responses"""
        clk_re = RisingEdge(self.clock)

        while True:
            await clk_re

            if self.in_reset:
                continue

            # Check for valid handshake
            if bool(self.bus.valid.value) and bool(self.bus.ready.value):
                response = TLDResponse(
                    opcode=int(self.bus.opcode.value),
                    param=int(self.bus.param.value),
                    size=int(self.bus.size.value),
                    source=int(self.bus.source.value),
                    sink=int(self.bus.sink.value),
                    denied=bool(self.bus.denied.value),
                    data=int(self.bus.data.value) if self.bus.data.value.is_resolvable else 0,
                    corrupt=bool(self.bus.corrupt.value),
                )
                self._recv(response)
