import pytest

from siliconcompiler import Sim
from siliconcompiler.targets.dvflow_cocotb import dvflow_cocotb

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles

from cocotb_bus.drivers import BitDriver
from cocotb_bus.scoreboard import Scoreboard

from cocotbext.umi.drivers.sumi_driver import SumiDriver
from cocotbext.umi.monitors.sumi_monitor import SumiMonitor
from cocotbext.umi.sumi import SumiTransaction, SumiCmdType, SumiCmd, SumiErrorCode
from cocotbext.umi.utils import generators

from umi.adapters.umi2tl.umi2tl import UMI2TL

from cocotb_utils import CocotbSimEnv, drive_reset


@cocotb.test(timeout_time=1, timeout_unit="ms")
@cocotb.parametrize(
    req_valid_gen=[None, generators.random_toggle_generator()],
    resp_ready_gen=[None, generators.random_toggle_generator()]
)
async def test_cas_deverr(dut, req_valid_gen=None, resp_ready_gen=None):
    """
    TileLink-UL has no compare and swap, so umi2tl answers a CAS itself:
      1. Send back to back CAS of each operand size (8, 16 and 32 bits)
      2. Verify each returns RESP_RD with ERR=DEVERR and no data
      3. Verify no request reached the TileLink A channel
    """

    ####################################
    # Setup test
    ####################################

    # Hold the TileLink bus inactive: no request is ever accepted or
    # answered, so any UMI response comes from umi2tl itself
    dut.tl_a_ready.value = 0
    dut.tl_d_valid.value = 0
    dut.tl_d_opcode.value = 0
    dut.tl_d_param.value = 0
    dut.tl_d_size.value = 0
    dut.tl_d_source.value = 0
    dut.tl_d_sink.value = 0
    dut.tl_d_denied.value = 0
    dut.tl_d_data.value = 0
    dut.tl_d_corrupt.value = 0

    await drive_reset(dut.nreset)
    Clock(dut.clk, 10, unit="ns").start()
    await ClockCycles(dut.clk, 10)

    addr_width = int(dut.AW.value)

    # Drive UMI response ready signal
    if resp_ready_gen is None:
        dut.udev_resp_ready.value = 1
    else:
        BitDriver(signal=dut.udev_resp_ready, clk=dut.clk).start(generator=resp_ready_gen)

    # Create SUMI driver for UMI request channel
    sumi_driver = SumiDriver(
        entity=dut, name="udev_req", clock=dut.clk, valid_generator=req_valid_gen
    )

    # Create SUMI monitor for UMI response channel
    sumi_monitor = SumiMonitor(entity=dut, name="udev_resp", clock=dut.clk)

    expected_responses = []
    scoreboard = Scoreboard(dut, fail_immediately=True)
    scoreboard.add_interface(monitor=sumi_monitor, expected_output=expected_responses)

    ####################################
    # Run test
    ####################################

    for i in range(16):
        size = 1 + i % 3
        operand_bytes = (1 << size) // 2
        new = i
        compare = 0x7F - i

        # New value in the low half of the data word, compare value in
        # the high half (README 3.4.6)
        cas_txn = SumiTransaction(
            cmd=SumiCmd.from_fields(
                cmd_type=int(SumiCmdType.UMI_REQ_ATOMIC),
                size=size,
                len=0x09  # ATYPE: CAS
            ),
            da=0x100 + 4*i,
            sa=0x200 + 4*i,
            data=(new.to_bytes(operand_bytes, byteorder="little")
                  + compare.to_bytes(operand_bytes, byteorder="little")),
            addr_width=addr_width
        )

        expected_responses.append(SumiTransaction(
            cmd=SumiCmd.from_fields(
                cmd_type=int(SumiCmdType.UMI_RESP_READ),
                size=size,
                len=0,
                u=int(SumiErrorCode.UMI_ERR_DEVERR)
            ),
            da=int(cas_txn.sa),
            sa=int(cas_txn.da),
            data=bytearray(1 << size),  # Expect no data in error response
            addr_width=addr_width
        ))

        sumi_driver.append(cas_txn)

    # Wait for scoreboard to consume all expected outputs
    while len(expected_responses) != 0:
        await ClockCycles(dut.clk, 1)

    await ClockCycles(dut.clk, 10)

    assert dut.tl_a_valid.value == 0, "CAS must not reach the TileLink A channel"

    # Check scoreboard results
    raise scoreboard.result


class TbDesign(CocotbSimEnv):

    def __init__(self):
        super().__init__(
            name="tb_umi2tl",
            topmodule="umi2tl",
            files=[__file__],
            dep=[UMI2TL()]
        )


@pytest.mark.cocotb
@pytest.mark.parametrize("simulator", ["icarus", "verilator"])
def test_umi2tl(simulator):
    project = Sim(TbDesign())
    project.add_fileset("testbench.cocotb")

    dvflow_cocotb(
        project=project,
        trace=False,
        timescale=("1ns", "1ps"),
        seed=None
    )

    project.set_flow(f"{simulator}cocotbdvflow")

    project.run()
    project.summary()
