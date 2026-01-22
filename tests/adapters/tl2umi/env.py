# Owns the driver, monitor, and scoreboard for TL to UMI adapter tests,
# and provides common functionality for the tests.

from cocotb.clock import Clock
from cocotb.triggers import ClockCycles

from cocotb_bus.scoreboard import Scoreboard

from adapters.tl2umi.tl_driver import TLDriver, TLTransaction, TLOpcode
from adapters.tl2umi.tl_monitor import TLMonitor, TLDResponse, TLDOpcode
from cocotb_utils import do_reset as cocotb_common_do_reset


class TL2UMIEnv:
    """Test environment for tl2umi adapter with umi_memagent backend"""

    def __init__(self, dut, clk_period_ns=10):
        self.dut = dut
        self.clk_period_ns = clk_period_ns

        # Extract parameters from DUT
        self.cw = int(dut.CW.value)  # UMI command width (32)
        self.aw = int(dut.AW.value)  # Address width (64)
        self.dw = int(dut.DW.value)  # Data width (64)

        self.data_size = self.dw // 8  # 8 bytes

        self.expected_responses = []

        self.clk = dut.clk
        self.nreset = dut.nreset

        self._build()

    def _build(self):
        dut = self.dut

        # TileLink A-channel driver (sends requests)
        self.tl_driver = TLDriver(
            entity=dut,
            name="tl_a",
            clock=self.clk,
            bus_separator="_",
        )

        # TileLink D-channel monitor (receives responses)
        self.tl_monitor = TLMonitor(
            entity=dut,
            name="tl_d",
            clock=self.clk,
            bus_separator="_",
        )

        # Scoreboard for response checking
        self.scoreboard = Scoreboard(dut, fail_immediately=True)
        self.scoreboard.add_interface(
            monitor=self.tl_monitor,
            expected_output=self.expected_responses,
        )

    async def start(self):
        """Start clocks and perform reset"""
        Clock(self.clk, self.clk_period_ns, unit="ns").start()
        await cocotb_common_do_reset(self.nreset, self.clk_period_ns)

        # Initialize DUT configuration signals
        self.dut.globalid.value = 0xAE510000

    async def wait_for_responses(self, max_cycles=1000):
        """Wait for all expected responses to be received"""
        cycles = 0
        while self.expected_responses:
            await ClockCycles(self.clk, 1)
            cycles += 1
            if cycles > max_cycles:
                raise TimeoutError(
                    f"Timeout waiting for responses "
                    f"({len(self.expected_responses)} remaining)"
                )

def create_expected_read_response(address, size, data, source=0,):

    """Create expected TileLink D-channel read response"""
    return TLDResponse(
        opcode=TLDOpcode.AccessAckData,
        param=0,
        size=size,
        source=source,
        sink=0,
        denied=False,
        data=data,
        corrupt=False,
    )

def create_expected_write_response(size, source=0):
    """Create expected TileLink D-channel write response"""
    return TLDResponse(
        opcode=TLDOpcode.AccessAck,
        param=0,
        size=size,
        source=source,
        sink=0,
        denied=False,
        data=0,
        corrupt=False,
    )
