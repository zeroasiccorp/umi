from typing import Any

from cocotb.types import LogicArray
from cocotb.triggers import RisingEdge
from cocotb.handle import SimHandleBase

from cocotb_bus.drivers import ValidatedBusDriver

from cocotbext.umi.utils.vrd_transaction import VRDTransaction


class ValidReadyDriver(ValidatedBusDriver):

    _signals = [
        "data",
        "valid",
        "ready"
    ]

    _optional_signals = ["strb", "len", "last"]

    def __init__(
        self,
        entity: SimHandleBase,
        name: str,
        clock: SimHandleBase,
        *,
        config={},
        **kwargs: Any
    ):
        ValidatedBusDriver.__init__(self, entity, name, clock, **kwargs)

        self.clock = clock
        self.bus.valid.value = 0

    async def _driver_send(self, transaction: VRDTransaction, sync: bool = True) -> None:
        """Implementation for BusDriver.
        Args:
            transaction: The transaction to send.
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

        while True:
            self.bus.valid.value = 1
            self.bus.data.value = LogicArray.from_bytes(transaction.data, byteorder="little")
            if hasattr(self.bus, "strb"):
                self.bus.strb.value = LogicArray(transaction.strb)
            if hasattr(self.bus, "len"):
                self.bus.len.value = transaction.len
            if hasattr(self.bus, "last"):
                self.bus.last.value = transaction.last
            await clk_re
            if ready():
                break

        self.bus.valid.value = 0
