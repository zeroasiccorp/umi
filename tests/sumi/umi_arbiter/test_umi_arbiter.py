import pytest
from typing import List

import cocotb

from cocotb.clock import Clock
from cocotb.triggers import ClockCycles
from cocotb.types import LogicArray

from cocotb_utils import drive_reset

from umi.sumi.umi_arbiter.umi_arbiter import Arbiter


def encode_req(req: List[bool]) -> int:
    return sum([(1 << i) for i, r in enumerate(req) if r])


def decode_grant(dut) -> List[bool]:
    return [bool(b) for b in list(dut.grants.value)[::-1]]


@cocotb.test()
async def test_umi_arbiter_round_robin(dut):
    """Test that UMI arbiter correctly performs round robin arbitration"""

    dut.mode.value = 0b01
    dut.mode.value = 0b10
    dut.requests.value = 0
    dut.mask.value = 0

    devices = int(dut.N.value)

    await drive_reset(reset=dut.nreset)
    Clock(dut.clk, 1, unit="ns").start()

    await ClockCycles(dut.clk, 10)

    # All devices make a req at the same time
    req = [True for _ in range(devices)]
    dut.requests.value = encode_req(req)

    await ClockCycles(dut.clk, 1)

    cur_device = 0
    while sum(decode_grant(dut)):
        while not decode_grant(dut)[cur_device]:
            print(f"cur_device = {cur_device}, grants = {[bool(b) for b in list(dut.grants.value)]}")
            await ClockCycles(dut.clk, 1)
        req[cur_device] = False
        dut.requests.value = encode_req(req)
        await ClockCycles(dut.clk, 1)
        print(f"cur_device = {cur_device}, requests = {req}")
        cur_device += 1

    await ClockCycles(dut.clk, 10)

    await ClockCycles(dut.clk, 1)
    dut.requests.value = encode_req([False, False, True, False])
    await ClockCycles(dut.clk, 1)
    await ClockCycles(dut.clk, 1)
    await ClockCycles(dut.clk, 1)
    dut.requests.value = encode_req([True, True, True, False])
    await ClockCycles(dut.clk, 1)
    for _ in range(10):
        dut.requests.value = encode_req([True, True, False, False])
        await ClockCycles(dut.clk, 1)
        #dut.requests.value = encode_req([False, True, False, False])
        await ClockCycles(dut.clk, 1)

    await ClockCycles(dut.clk, 100)


@pytest.mark.cocotb
@pytest.mark.parametrize("simulator", ["icarus", "verilator"])
def test_umi_arbiter(simulator):
    from run_cocotb_sim import load_cocotb_test
    load_cocotb_test(
        design=Arbiter(),
        topmodule="umi_arbiter",
        cocotb_files=__file__,
        simulator=simulator,
        trace=True,
        seed=None
    )
