# Copyright (C) 2026 Zero ASIC
# This code is licensed under Apache License 2.0 (see LICENSE for details)

import pytest

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, FallingEdge, RisingEdge, Timer

from siliconcompiler import Sim
from siliconcompiler.targets.dvflow_cocotb import dvflow_cocotb

from umi.sumi import Decode, FifoFlex
from cocotb_utils import CocotbSimEnv, drive_reset


@cocotb.test()
async def long_data_free_packets(dut):
    """Widening must preserve LEN even when a data-free packet exceeds the bus."""
    dut.umi_in_valid.value = 0
    dut.umi_in_cmd.value = 0
    dut.umi_in_dstaddr.value = 0
    dut.umi_in_srcaddr.value = 0
    dut.umi_in_data.value = 0
    dut.umi_out_ready.value = 1
    dut.bypass.value = 1
    dut.chaosmode.value = 0
    dut.vdd.value = 1
    dut.vss.value = 0

    await drive_reset(dut.umi_in_nreset)
    await drive_reset(dut.umi_out_nreset)
    Clock(dut.umi_in_clk, 10, unit="ns").start()
    Clock(dut.umi_out_clk, 10, unit="ns").start()
    await ClockCycles(dut.umi_in_clk, 5)

    # REQ_RD and RESP_WR carry no data. Include the old 512-byte wrap,
    # its neighbors, and the maximum LEN for every word size that fits.
    for opcode in (0x01, 0x04):
        for size in range((len(dut.umi_in_data) // 8).bit_length()):
            for words in (1, 63, 64, 65, 255, 256):
                for stalled in (False, True):
                    cmd = (1 << 22) | ((words - 1) << 8) | (size << 5) | opcode
                    await FallingEdge(dut.umi_in_clk)
                    dut.umi_out_ready.value = int(not stalled)
                    dut.umi_in_cmd.value = cmd
                    dut.umi_in_dstaddr.value = 0x1000
                    dut.umi_in_srcaddr.value = 0x4000
                    dut.umi_in_valid.value = 1
                    for _ in range(20):
                        await RisingEdge(dut.umi_in_clk)
                        if dut.umi_in_ready.value:
                            break
                    else:
                        assert False, "Input was not accepted"
                    await FallingEdge(dut.umi_in_clk)
                    dut.umi_in_valid.value = 0

                    for _ in range(20):
                        await Timer(1, unit="ns")
                        if dut.umi_out_valid.value:
                            break
                        await FallingEdge(dut.umi_in_clk)
                    else:
                        assert False, f"No output for opcode={opcode} size={size} words={words}"

                    for _ in range(4 if stalled else 1):
                        assert dut.umi_out_valid.value
                        assert int(dut.umi_out_cmd.value) == cmd
                        assert int(dut.umi_out_dstaddr.value) == 0x1000
                        assert int(dut.umi_out_srcaddr.value) == 0x4000
                        if stalled:
                            await FallingEdge(dut.umi_in_clk)
                            await Timer(1, unit="ns")
                    dut.umi_out_ready.value = 1
                    await RisingEdge(dut.umi_in_clk)
                    await FallingEdge(dut.umi_in_clk)
                    await Timer(1, unit="ns")
                    assert not dut.umi_out_valid.value, "Duplicate output"


class TbDesign(CocotbSimEnv):

    def __init__(self, idw):
        super().__init__(
            name=f"tb_umi_fifoflex_{idw}",
            topmodule="umi_fifoflex",
            files=[__file__],
            dep=[FifoFlex(), Decode()],
            param=[("IDW", str(idw)), ("ODW", str(2 * idw)), ("DEPTH", "0")]
        )


@pytest.mark.cocotb
@pytest.mark.parametrize("simulator", ["icarus", "verilator"])
@pytest.mark.parametrize("idw", [64, 1024])
def test_umi_fifoflex(simulator, idw):
    project = Sim(TbDesign(idw))
    project.add_fileset("testbench.cocotb")
    dvflow_cocotb(project=project, trace=False, timescale=("1ns", "1ps"), seed=0)
    project.set_flow(f"{simulator}cocotbdvflow")
    project.run()
    project.summary()
