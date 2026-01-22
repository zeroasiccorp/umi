from dataclasses import dataclass
from enum import IntEnum
from typing import Any, Optional

from cocotb.triggers import RisingEdge
from cocotb.handle import SimHandleBase

from cocotb_bus.drivers import ValidatedBusDriver


class TLOpcode(IntEnum):
    """TileLink A-channel opcodes"""
    PutFullData = 0
    PutPartialData = 1
    ArithmeticData = 2
    LogicalData = 3
    Get = 4
    Intent = 5


class TLArithParam(IntEnum):
    """TileLink arithmetic operation parameters"""
    MIN = 0
    MAX = 1
    MINU = 2
    MAXU = 3
    ADD = 4


class TLLogicParam(IntEnum):
    """TileLink logical operation parameters"""
    XOR = 0
    OR = 1
    AND = 2
    SWAP = 3


@dataclass
class TLTransaction:
    """TileLink A-channel transaction"""
    opcode: int
    address: int
    size: int  # log2(bytes)
    mask: int = 0xFF
    data: int = 0
    source: int = 0
    param: int = 0

    @classmethod
    def get(cls, address: int, size: int, source: int = 0) -> "TLTransaction":
        """Create a Get (read) transaction"""
        mask = (1 << (1 << size)) - 1  # All bytes valid for size
        return cls(
            opcode=TLOpcode.Get,
            address=address,
            size=size,
            mask=mask,
            source=source,
        )

    @classmethod
    def put_full(cls, address: int, size: int, data: int, source: int = 0) -> "TLTransaction":
        """Create a PutFullData (write) transaction"""
        mask = (1 << (1 << size)) - 1
        return cls(
            opcode=TLOpcode.PutFullData,
            address=address,
            size=size,
            mask=mask,
            data=data,
            source=source,
        )

    @classmethod
    def put_partial(cls, address: int, size: int, data: int, mask: int, source: int = 0) -> "TLTransaction":
        """Create a PutPartialData (masked write) transaction"""
        return cls(
            opcode=TLOpcode.PutPartialData,
            address=address,
            size=size,
            mask=mask,
            data=data,
            source=source,
        )

    @classmethod
    def atomic_arith(cls, address: int, size: int, data: int, param: TLArithParam, source: int = 0) -> "TLTransaction":
        """Create an ArithmeticData atomic transaction"""
        mask = (1 << (1 << size)) - 1
        return cls(
            opcode=TLOpcode.ArithmeticData,
            address=address,
            size=size,
            mask=mask,
            data=data,
            param=int(param),
            source=source,
        )

    @classmethod
    def atomic_logic(cls, address: int, size: int, data: int, param: TLLogicParam, source: int = 0) -> "TLTransaction":
        """Create a LogicalData atomic transaction"""
        mask = (1 << (1 << size)) - 1
        return cls(
            opcode=TLOpcode.LogicalData,
            address=address,
            size=size,
            mask=mask,
            data=data,
            param=int(param),
            source=source,
        )


class TLDriver(ValidatedBusDriver):
    _signals = [
        "valid",
        "ready",
        "opcode",
        "param",
        "size",
        "source",
        "address",
        "mask",
        "data",
    ]

    def __init__(
        self,
        entity: SimHandleBase,
        name: str,
        clock: SimHandleBase,
        *,
        config: Optional[dict] = None,
        **kwargs: Any,
    ):
        ValidatedBusDriver.__init__(self, entity, name, clock, **kwargs)

        self.clock = clock
        self.bus.valid.value = 0

    async def _driver_send(self, transaction: TLTransaction, sync: bool = True) -> None:
        """Drive a TileLink A-channel transaction.

        Args:
            transaction: The TLTransaction to send.
            sync: Synchronize the transfer by waiting for a rising edge.
        """
        clk_re = RisingEdge(self.clock)

        if sync:
            await clk_re

        # Insert a gap where valid is low
        if not self.on:
            self.bus.valid.value = 0
            for _ in range(self.off):
                await clk_re

            # Grab the next set of on/off values
            self._next_valids()

        # Consume a valid cycle
        if self.on is not True and self.on:
            self.on -= 1

        def ready() -> bool:
            return bool(self.bus.ready.value)

        # Drive signals and wait for ready
        while True:
            self.bus.valid.value = 1
            self.bus.opcode.value = transaction.opcode
            self.bus.param.value = transaction.param
            self.bus.size.value = transaction.size
            self.bus.source.value = transaction.source
            self.bus.address.value = transaction.address
            self.bus.mask.value = transaction.mask
            self.bus.data.value = transaction.data

            await clk_re
            if ready():
                break

        self.bus.valid.value = 0
