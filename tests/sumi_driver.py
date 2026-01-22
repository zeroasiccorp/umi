from typing import Any

from cocotb.types import LogicArray
from cocotb.triggers import RisingEdge
from cocotb.handle import SimHandleBase

from cocotb_bus.drivers import ValidatedBusDriver

from sumi import SumiTransaction


class SumiDriver(ValidatedBusDriver):

    _signals = [
        "valid",
        "cmd",
        "dstaddr",
        "srcaddr",
        "data",
        "ready"
    ]

    _optional_signals = []

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

    async def _driver_send(self, transaction: SumiTransaction, sync: bool = True) -> None:
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

        bus_size = len(self.bus.data)//8

        while True:
            self.bus.valid.value = 1
            self.bus.cmd.value = int(transaction.cmd)
            self.bus.data.value = LogicArray.from_bytes(
                value=transaction.data + bytearray([0]*(bus_size - len(transaction.data))),
                range=len(self.bus.data),
                byteorder="little"
            )
            self.bus.dstaddr.value = int(transaction.da)
            self.bus.srcaddr.value = int(transaction.sa)
            await clk_re
            if ready():
                break

        self.bus.valid.value = 0