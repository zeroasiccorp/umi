import os
import random

import pytest

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles

from cocotb_bus.drivers import BitDriver

from cocotbext.axi import AxiWriteBus, AxiMasterWrite

from cocotbext.umi.drivers.sumi_driver import SumiDriver
from cocotbext.umi.monitors.sumi_monitor import SumiMonitor
from cocotbext.umi.models.umi_memory_device import UmiMemoryDevice
from cocotbext.umi.utils import generators

from siliconcompiler import Design, Sim
from siliconcompiler.flows.dvflow import DVFlow

from siliconcompiler.tools.icarus.compile import CompileTask as IcarusCompileTask
from siliconcompiler.tools.icarus.cocotb_exec import CocotbExecTask as IcarusCocotbExecTask

from umi.adapters.axi4full2umi.axi4full2umi import AXIF2UMI


async def init_dut(dut):
    """Initialize DUT signals and perform reset."""
    # Initialize AXI signals that cocotbext-axi may not drive
    dut.s_axi_wid.value = 0  # AXI3 signal, tie off

    dut.s_axi_awvalid.value = 0
    dut.s_axi_wvalid.value = 0
    dut.s_axi_bready.value = 0

    # Initialize UMI request ready (will be driven by driver)
    dut.uhost_req_ready.value = 0

    # Initialize UMI response signals (will be driven by driver)
    dut.uhost_resp_valid.value = 0
    dut.uhost_resp_cmd.value = 0
    dut.uhost_resp_dstaddr.value = 0
    dut.uhost_resp_srcaddr.value = 0
    dut.uhost_resp_data.value = 0

    # Reset sequence (active-low reset)
    dut.nreset.value = 1
    await ClockCycles(dut.clk, 1)
    dut.nreset.value = 0
    await ClockCycles(dut.clk, 10)
    dut.nreset.value = 1
    await ClockCycles(dut.clk, 5)


@cocotb.test(timeout_time=10, timeout_unit="ms")
@cocotb.parametrize(
    resp_valid_gen=[None, generators.random_toggle_generator(), generators.wave_generator()],
    req_ready_gen=[None, generators.random_toggle_generator(), generators.wave_generator()],
    test_n_writes=[int(10 * float(os.getenv("RAND_TEST_LEN_SCALER", default=1)))]
)
async def basic_test(
    dut,
    test_n_writes=10,
    resp_valid_gen=None,
    req_ready_gen=None
):
    """Basic write transaction test."""
    clk_period_ns = 1
    Clock(dut.clk, clk_period_ns, unit="ns").start()

    await init_dut(dut)

    # Create SUMI monitor for UMI request channel (receives write requests)
    sumi_req_monitor = SumiMonitor(
        entity=dut,
        name="uhost_req",
        clock=dut.clk
    )
    if req_ready_gen is None:
        dut.uhost_req_ready.value = 1
    else:
        BitDriver(signal=dut.uhost_req_ready, clk=dut.clk).start(generator=req_ready_gen)

    # Create SUMI driver for UMI response channel (sends write responses)
    sumi_resp_driver = SumiDriver(
        entity=dut,
        name="uhost_resp",
        clock=dut.clk,
        valid_generator=resp_valid_gen
    )

    # Create the virtual memory device backed by the SUMI monitor/driver
    umi_memory = UmiMemoryDevice(
        monitor=sumi_req_monitor,
        driver=sumi_resp_driver,
        log=dut._log
    )

    # Create the AXI write bus and master
    axi_write_bus = AxiWriteBus.from_prefix(dut, "s_axi")
    axi_master = AxiMasterWrite(
        axi_write_bus,
        dut.clk,
        dut.nreset,
        reset_active_level=False
    )

    await ClockCycles(dut.clk, 5)

    # Generate and perform random write transactions
    max_addr = (1 << int(dut.AW.value)) - 1
    align = int(dut.DW.value) // 8

    for i in range(test_n_writes):
        max_write_size = random.choices([4096, 256, 10], weights=[10, 40, 50])[0]
        # Generate random address aligned to data bus width
        test_addr = random.randint(0, (max_addr - max_write_size) // align) * align
        write_size = random.randint(1, max_write_size)
        test_data = random.randbytes(write_size)

        dut._log.info(f"Write {i+1}/{test_n_writes}: {len(test_data)} bytes to address 0x{test_addr:08x}")
        await axi_master.write(test_addr, test_data)

        # Verify the data was written to virtual memory
        read_back = umi_memory.read(test_addr, len(test_data))
        assert read_back == test_data, (
            f"Write {i+1} data mismatch at 0x{test_addr:08x}: "
            f"expected {test_data.hex()}, got {read_back.hex()}"
        )

    dut._log.info(f"All {test_n_writes} writes completed and verified successfully")

    await ClockCycles(dut.clk, 10)


class TbDesign(Design):

    def __init__(self):
        super().__init__()

        # Set the design's name
        self.set_name("tb_axi4_full_wr2umi")

        # Establish the root directory for all design-related files
        self.set_dataroot("tb_axi4_full_wr2umi", __file__)

        # Configure filesets within the established data root
        with self.active_dataroot("tb_axi4_full_wr2umi"):
            with self.active_fileset("testbench.cocotb"):
                self.set_topmodule("axi4_full_wr2umi")
                self.add_file("test_axi4_full_wr2umi.py", filetype="python")
                self.add_depfileset(AXIF2UMI(), "rtl")


def load_cocotb_test(trace=True, seed=None):
    # Create project
    project = Sim()
    project.set_design(TbDesign())
    project.add_fileset("testbench.cocotb")

    # Set the cocotb design verification flow
    project.set_flow(DVFlow(tool="icarus-cocotb"))

    # Enable waveform tracing
    IcarusCompileTask.find_task(project).set_trace_enabled(trace)

    # Optionally set a random seed for reproducibility
    if seed is not None:
        IcarusCocotbExecTask.find_task(project).set_cocotb_randomseed(seed)

    # Run the simulation
    project.run()
    project.summary()

    # Find and display the results file
    results = project.find_result(
        step='simulate',
        index='0',
        directory="outputs",
        filename="results.xml"
    )
    if results:
        print(f"\nCocotb results file: {results}")

    # Find and display the waveform file
    vcd = project.find_result(
        step='simulate',
        index='0',
        directory="reports",
        filename="tb_axi4_full_wr2umi.vcd"
    )
    if vcd:
        print(f"Waveform file: {vcd}")


def test_axi4_full_wr2umi():
    load_cocotb_test()
