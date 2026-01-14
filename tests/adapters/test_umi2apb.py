import pytest
import math
import cocotb

from random import randint, randbytes
from sumi_driver import SumiDriver
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles
from cocotb.handle import SimHandleBase
from cocotbext.apb import ApbBus, ApbSlave, MemoryRegion
from umi.adapters import UMI2APB
from cocotb_utils import (
    run_cocotb,
    do_reset as cocotb_common_do_reset
)

@cocotb.test(timeout_time=10, timeout_unit='ns')
async def test_umi_to_apb_adapter(dut: SimHandleBase, test_n_transactions = 512):
    """Test UMI to APB adapter"""

    ####################################
    # Constants and Parameters
    ####################################
    data_width = int(dut.RW.value)
    addr_width = int(dut.AW.value)

    data_size = data_width // 8

    clk_period_ns = 10

    ####################################
    # Instantiate Drivers
    ####################################

    # Create UMI Master BFM
    sumi_driver = SumiDriver(
        entity=dut,
        name="udev",
        clock=dut.clk,
        bus_separator="_"
    )

    # Create APB Slave BFM
    apb_bus = ApbBus.from_prefix(dut, "apb")
    apb_slave = ApbSlave(apb_bus, dut.apb_pclk, dut.apb_nreset)
    region = MemoryRegion(2**16)
    apb_slave.target = region

    ####################################
    # Reset DUT and start clock
    ####################################

    # Start clock
    cocotb.start_soon(Clock(dut.apb_pclk, clk_period_ns, units="ns").start())

    # Reset DUT  
    await cocotb_common_do_reset(dut.apb_nreset, clk_period_ns)

    # ADD TEST TRANSACTIONS HERE


def run_umi2apb(simulator="verilator", output_wave=True):
    from siliconcompiler import Sim

    test_inst_name = f"sim_{simulator}"
    project = Sim(UMI2APB())
    project.add_fileset("rtl")

    test_module_name = __name__
    test_name = f"{test_module_name}_{test_inst_name}"
    tests_failed = run_cocotb(
        project=project,
        test_module_name=test_module_name,
        simulator_name=simulator,
        timescale=("1ns", "1ps"),
        build_args=["--report-unoptflat"] if simulator == "verilator" else [],
        parameters=None,
        output_dir_name=test_name,
        waves=output_wave
    )
    assert (tests_failed == 0), f"Error test {test_name} failed!"

@pytest.mark.sim
@pytest.mark.parametrize("simulator", ["verilator"])
def test_umi2apb(simulator):
    run_umi2apb(simulator=simulator)