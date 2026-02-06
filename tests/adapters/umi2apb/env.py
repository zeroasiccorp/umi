# Owns the driver, monitor, and scoreboard for UMI to APB adapter tests,
# and provides common functionality for the tests.

import math

from cocotb.clock import Clock
from cocotb.triggers import ClockCycles

from cocotb_bus.scoreboard import Scoreboard
from cocotbext.apb import ApbBus, ApbSlave, MemoryRegion

from sumi_driver import SumiDriver
from sumi_monitor import SumiMonitor
from sumi import SumiTransaction, SumiCmdType, SumiCmd
from cocotb_utils import do_reset as cocotb_common_do_reset


# Creates the umi2apb test environment
class UMI2APBEnv:
    def __init__(self, dut, clk_period_ns=10, mem_size=2**16):
        self.dut = dut
        self.clk_period_ns = clk_period_ns
        self.mem_size = mem_size

        self.data_width = int(dut.RW.value)  # default of 64
        self.addr_width = int(dut.AW.value)  # default of 64
        self.data_size = self.data_width // 8
        self.umi_size = int(math.log2(self.data_size))

        self.expected_responses = []

        self.clk = dut.apb_pclk
        self.nreset = dut.apb_nreset

        self._build()

    def _build(self):
        dut = self.dut

        # Instantiates UMI driver
        self.sumi_driver = SumiDriver(
            entity=dut,
            name="udev_req",
            clock=self.clk,
            bus_separator="_"
        )

        # Instantiates APB slave and memory region
        apb_bus = ApbBus.from_prefix(dut, "apb")
        self.apb_slave = ApbSlave(apb_bus, self.clk, self.nreset)
        self.region = MemoryRegion(self.mem_size)
        self.apb_slave.target = self.region

        # Creates UMI monitor (for responses)
        self.sumi_monitor = SumiMonitor(
            entity=dut,
            name="udev_resp",
            clock=self.clk,
            bus_separator="_"
        )

        # Creates scoreboard
        self.scoreboard = Scoreboard(dut, fail_immediately=True)
        self.scoreboard.add_interface(monitor=self.sumi_monitor, expected_output=self.expected_responses)

    # Prerequisites for starting tests
    async def start(self):
        Clock(self.clk, self.clk_period_ns, unit="ns").start()
        await cocotb_common_do_reset(self.nreset, self.clk_period_ns)

    # Waits for umi responses
    async def wait_for_responses(self, max_cycles):
        cycles = 0
        while self.expected_responses:
            await ClockCycles(self.clk, 1)
            cycles += 1
            if cycles > max_cycles:
                raise TimeoutError(
                    f"Timeout waiting for responses "
                    f"({len(self.expected_responses)} remaining)"
                )


# Creates an ideal umi write response
def create_expected_write_response(write_txn, data_size, addr_width=64):
    req_da = int(write_txn.da.value) if hasattr(write_txn.da, "value") else int(write_txn.da)
    req_sa = int(write_txn.sa.value) if hasattr(write_txn.sa, "value") else int(write_txn.sa)

    req_size = int(write_txn.cmd.size)
    req_len = int(write_txn.cmd.len)

    return SumiTransaction(
        cmd=SumiCmd.from_fields(
            cmd_type=int(SumiCmdType.UMI_RESP_WRITE),
            size=req_size,
            len=req_len
        ),
        da=req_sa,
        sa=req_da,
        data=bytearray(data_size),  # Expect no data in write response
        addr_width=addr_width
    )
