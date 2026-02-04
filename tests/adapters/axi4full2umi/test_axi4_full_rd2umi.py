import os
import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles

from cocotb_bus.drivers import BitDriver

from cocotbext.axi import AxiReadBus, AxiMasterRead, AxiResp

from cocotbext.umi.drivers.sumi_driver import SumiDriver
from cocotbext.umi.monitors.sumi_monitor import SumiMonitor
from cocotbext.umi.models.umi_memory_device import UmiMemoryDevice
from cocotbext.umi.utils import generators

from siliconcompiler import Design, Sim
from siliconcompiler.flows.dvflow import DVFlow

from siliconcompiler.tools.icarus.compile import CompileTask as IcarusCompileTask
from siliconcompiler.tools.icarus.cocotb_exec import CocotbExecTask as IcarusCocotbExecTask

from umi.adapters.axi4full2umi.axi4full2umi import AXIF2UMI


class TestEnv:
    """Reusable test environment for AXI4 Full Read to UMI adapter tests."""

    def __init__(self, dut):
        self.dut = dut
        self.axi_master = None
        self.max_addr = (1 << int(self.dut.AW.value)) - 1
        self.alignment = int(self.dut.DW.value) // 8

    async def setup(self):
        """Initialize and reset the DUT, create AXI master."""
        dut = self.dut

        # Initialize AXI signals that cocotbext-axi may not drive
        dut.s_axi_arvalid.value = 0
        dut.s_axi_rready.value = 0

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

        # Create the AXI read master
        axi_read_bus = AxiReadBus.from_prefix(dut, "s_axi")
        self.axi_master = AxiMasterRead(
            axi_read_bus,
            dut.clk,
            dut.nreset,
            reset_active_level=False
        )

        await ClockCycles(dut.clk, 5)

    def random_read_params(self, max_read_size=None):
        """Generate random address and size for a read transaction."""
        if max_read_size is None:
            max_read_size = random.choices([4096, 256, 10], weights=[10, 40, 50])[0]
        test_addr = random.randint(0, (self.max_addr - max_read_size) // self.alignment) * self.alignment
        read_size = random.randint(1, max_read_size)
        return test_addr, read_size


@cocotb.test(timeout_time=10, timeout_unit="ms")
@cocotb.parametrize(
    resp_valid_gen=[None, generators.random_toggle_generator(), generators.wave_generator()],
    req_ready_gen=[None, generators.random_toggle_generator(), generators.wave_generator()],
    test_n_reads=[int(50 * float(os.getenv("RAND_TEST_LEN_SCALER", default=1)))]
)
async def basic_test(
    dut,
    test_n_reads=10,
    resp_valid_gen=None,
    req_ready_gen=None
):
    """Basic read transaction test - verify data read from memory matches expected."""

    ####################################
    # Setup test
    ####################################

    Clock(dut.clk, 1, unit="ns").start()

    env = TestEnv(dut)
    await env.setup()

    # Create SUMI monitor for UMI request channel
    sumi_req_monitor = SumiMonitor(entity=dut, name="uhost_req", clock=dut.clk)

    # Drive UMI request ready signal
    if req_ready_gen is None:
        dut.uhost_req_ready.value = 1
    else:
        BitDriver(signal=dut.uhost_req_ready, clk=dut.clk).start(generator=req_ready_gen)

    # Create SUMI driver for UMI response channel
    sumi_resp_driver = SumiDriver(
        entity=dut, name="uhost_resp", clock=dut.clk, valid_generator=resp_valid_gen
    )

    # Create UMI memory device with driver and monitor
    umi_memory = UmiMemoryDevice(
        monitor=sumi_req_monitor,
        driver=sumi_resp_driver,
        log=dut._log
    )

    ####################################
    # Run test
    ####################################

    for i in range(test_n_reads):
        test_addr, read_size = env.random_read_params()

        # Pre-populate memory with random data
        expected_data = random.randbytes(read_size)
        umi_memory.write(test_addr, expected_data)

        dut._log.info(f"Read {i+1}/{test_n_reads}: {read_size} bytes from 0x{test_addr:08x}")
        resp = await env.axi_master.read(test_addr, read_size)

        # Verify OKAY response
        assert resp.resp == AxiResp.OKAY, f"Read {i+1} expected OKAY, got {resp.resp}"

        # Verify data matches
        read_data = bytes(resp.data)
        assert read_data == expected_data, (
            f"Read {i+1} data mismatch at 0x{test_addr:08x}: "
            f"expected {expected_data.hex()}, got {read_data.hex()}"
        )

    dut._log.info(f"All {test_n_reads} reads completed and verified successfully")
    await ClockCycles(dut.clk, 10)


class TbDesign(Design):

    def __init__(self):
        super().__init__()

        # Set the design's name
        self.set_name("tb_axi4_full_rd2umi")

        # Establish the root directory for all design-related files
        self.set_dataroot("tb_axi4_full_rd2umi", __file__)

        # Configure filesets within the established data root
        with self.active_dataroot("tb_axi4_full_rd2umi"):
            with self.active_fileset("testbench.cocotb"):
                self.set_topmodule("axi4_full_rd2umi")
                self.add_file("test_axi4_full_rd2umi.py", filetype="python")
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
        filename="tb_axi4_full_rd2umi.vcd"
    )
    if vcd:
        print(f"Waveform file: {vcd}")


def test_axi4_full_rd2umi():
    load_cocotb_test()
