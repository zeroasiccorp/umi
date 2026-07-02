from cocotb.triggers import RisingEdge

from cocotb_bus.monitors import BusMonitor

from cocotbext.umi.utils.vrd_transaction import VRDTransaction


class ValidReadyMonitor(BusMonitor):

    _signals = [
        "data",
        "valid",
        "ready"
    ]
    _optional_signals = ["last"]

    def __init__(self, entity, name, clock, **kwargs):
        BusMonitor.__init__(self, entity, name, clock, **kwargs)

    async def _monitor_recv(self):
        clk_re = RisingEdge(self.clock)

        def valid_handshake():
            return bool(self.bus.valid.value) and bool(self.bus.ready.value)

        while True:
            await clk_re
            if valid_handshake():
                self._recv(VRDTransaction(
                    data=self.bus.data.value.to_bytes(byteorder="little"),
                    last=bool(self.bus.last.value) if hasattr(self.bus, "last") else None
                ))
