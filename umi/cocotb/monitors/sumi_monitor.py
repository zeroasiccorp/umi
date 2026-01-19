from cocotb.types import LogicArray
from cocotb.triggers import RisingEdge

from cocotb_bus.monitors import BusMonitor

from umi.cocotb.sumi import SumiCmd, SumiTransaction


class SumiMonitor(BusMonitor):

    _signals = [
        "valid",
        "cmd",
        "dstaddr",
        "srcaddr",
        "data",
        "ready"
    ]
    _optional_signals = []

    def __init__(self, entity, name, clock, **kwargs):
        BusMonitor.__init__(self, entity, name, clock, **kwargs)
        self.addr_width = len(self.bus.dstaddr)

    async def _monitor_recv(self):
        clk_re = RisingEdge(self.clock)

        def valid_handshake() -> bool:
            return bool(self.bus.valid.value) and bool(self.bus.ready.value)

        while True:
            await clk_re

            if self.in_reset:
                continue

            if valid_handshake():
                sumi_cmd: SumiCmd = SumiCmd.from_int(int(self.bus.cmd.value))
                data: LogicArray = self.bus.data.value
                data = data[(((int(sumi_cmd.len)+1) << (int(sumi_cmd.size)))*8)-1:0]
                self._recv(SumiTransaction(
                    cmd=sumi_cmd,
                    da=int(self.bus.dstaddr.value) if self.bus.dstaddr.value.is_resolvable
                    else None,
                    sa=int(self.bus.srcaddr.value) if self.bus.srcaddr.value.is_resolvable
                    else None,
                    data=data.to_bytes(byteorder="little") if data.is_resolvable else None,
                    addr_width=self.addr_width
                ))
