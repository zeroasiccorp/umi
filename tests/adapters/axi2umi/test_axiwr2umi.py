import os
import random

import pytest

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles

from cocotb_bus.drivers import BitDriver

from cocotbext.axi import AxiWriteBus, AxiMasterWrite, AxiResp, AxiBurstType

from cocotbext.umi.sumi import SumiCmd, SumiCmdType, SumiTransaction
from cocotbext.umi.drivers.sumi_driver import SumiDriver
from cocotbext.umi.monitors.sumi_monitor import SumiMonitor
from cocotbext.umi.models.umi_memory_device import UmiMemoryDevice
from cocotbext.umi.utils import generators

from siliconcompiler import Design, Sim
from siliconcompiler.flows.dvflow import DVFlow

from siliconcompiler.tools.icarus.compile import CompileTask as IcarusCompileTask
from siliconcompiler.tools.icarus.cocotb_exec import CocotbExecTask as IcarusCocotbExecTask

from umi.adapters.axi2umi.axi2umi import AXI2UMI


class ErrorInjectingUmiMemoryDevice(UmiMemoryDevice):
    """
    UmiMemoryDevice that can inject errors into write responses.

    Error injection is controlled by:
    - error_rate: Probability (0.0-1.0) of injecting an error on any response
    - error_addresses: Set of addresses that always trigger errors
    - error_code: The error code to inject (default SLVERR=2)
    """

    def __init__(
        self,
        monitor: SumiMonitor,
        driver: SumiDriver,
        log=None,
        error_rate: float = 0.0,
        error_addresses: set = None,
        error_code: int = 2  # SLVERR
    ):
        # Don't call super().__init__ yet - we need to set up error config first
        self.error_rate = error_rate
        self.error_addresses = error_addresses or set()
        self.error_code = error_code
        self.injected_errors = []  # Track which transactions got errors

        # Now call parent init (which sets up the callback)
        super().__init__(monitor, driver, log)

    def _should_inject_error(self, address: int) -> bool:
        """Determine if this transaction should have an error injected."""
        if address in self.error_addresses:
            return True
        if self.error_rate > 0 and random.random() < self.error_rate:
            return True
        return False

    def _handle_write(self, transaction: SumiTransaction, send_response: bool = True):
        """Handle a write request, optionally injecting errors into response."""
        dstaddr = int(transaction.da)
        data = transaction.data
        size = int(transaction.cmd.size)
        length = int(transaction.cmd.len)
        data_size = (length + 1) << size

        if self.log:
            self.log.info(
                f"MEM WRITE: addr=0x{dstaddr:08x} size={data_size} "
                f"data={data[:data_size].hex()}"
            )

        # Always write to memory (even if we'll return an error)
        for i in range(data_size):
            self.memory[dstaddr + i] = data[i]

        if send_response:
            inject_error = self._should_inject_error(dstaddr)

            resp_cmd = SumiCmd.from_fields(
                cmd_type=SumiCmdType.UMI_RESP_WRITE,
                size=0,
                len=0,
                eom=1,
                u=self.error_code if inject_error else 0
            )

            if inject_error:
                self.injected_errors.append((dstaddr, self.error_code))
                if self.log:
                    self.log.info(f"INJECTING ERROR: addr=0x{dstaddr:08x} err={self.error_code}")

            resp = SumiTransaction(
                cmd=resp_cmd,
                da=int(transaction.sa),
                sa=int(transaction.da),
                data=bytes([0]),
                addr_width=transaction._addr_width
            )
            self.driver.append(resp)


class TestEnv:
    """Reusable test environment for AXI4 Full to UMI adapter tests."""

    def __init__(self, dut):
        self.dut = dut
        self.axi_master = None
        self.max_addr = (1 << int(self.dut.AW.value)) - 1
        self.alignment = int(self.dut.DW.value) // 8

    async def setup(self):
        """Initialize and reset the DUT, create AXI master."""
        dut = self.dut

        # Initialize AXI signals that cocotbext-axi may not drive
        dut.s_axi_wid.value = 0
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

        # Create the AXI write master
        axi_write_bus = AxiWriteBus.from_prefix(dut, "s_axi")
        self.axi_master = AxiMasterWrite(
            axi_write_bus,
            dut.clk,
            dut.nreset,
            reset_active_level=False
        )

        await ClockCycles(dut.clk, 5)

    def random_write_params(self, max_write_size=None):
        """Generate random address and data for a write transaction."""
        if max_write_size is None:
            max_write_size = random.choices([4096, 256, 10], weights=[10, 40, 50])[0]
        test_addr = random.randint(0, (self.max_addr - max_write_size) // self.alignment) * self.alignment
        write_size = random.randint(1, max_write_size)
        test_data = random.randbytes(write_size)
        return test_addr, test_data


@cocotb.test(timeout_time=10, timeout_unit="ms")
@cocotb.parametrize(
    resp_valid_gen=[None, generators.random_toggle_generator(), generators.wave_generator()],
    req_ready_gen=[None, generators.random_toggle_generator(), generators.wave_generator()],
    test_n_writes=[int(50 * float(os.getenv("RAND_TEST_LEN_SCALER", default=1)))]
)
async def basic_test(
    dut,
    test_n_writes=10,
    resp_valid_gen=None,
    req_ready_gen=None
):
    """Basic write transaction test - verify data reaches memory."""

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

    for i in range(test_n_writes):
        test_addr, test_data = env.random_write_params()

        dut._log.info(f"Write {i+1}/{test_n_writes}: {len(test_data)} bytes to 0x{test_addr:08x}")
        resp = await env.axi_master.write(test_addr, test_data)

        # Verify OKAY response
        assert resp.resp == AxiResp.OKAY, f"Write {i+1} expected OKAY, got {resp.resp}"

        # Verify data in memory
        read_back = umi_memory.read(test_addr, len(test_data))
        assert read_back == test_data, (
            f"Write {i+1} data mismatch at 0x{test_addr:08x}: "
            f"expected {test_data.hex()}, got {read_back.hex()}"
        )

    dut._log.info(f"All {test_n_writes} writes completed and verified successfully")
    await ClockCycles(dut.clk, 10)


@cocotb.test(timeout_time=10, timeout_unit="ms")
@cocotb.parametrize(
    resp_valid_gen=[None, generators.random_toggle_generator()],
    test_n_writes=[int(50 * float(os.getenv("RAND_TEST_LEN_SCALER", default=1)))]
)
async def fixed_burst_test(
    dut,
    test_n_writes=10,
    resp_valid_gen=None
):
    """Test FIXED burst - all beats write to the same address."""

    ####################################
    # Setup test
    ####################################

    Clock(dut.clk, 1, unit="ns").start()

    env = TestEnv(dut)
    await env.setup()

    # Create SUMI monitor for UMI request channel
    sumi_req_monitor = SumiMonitor(entity=dut, name="uhost_req", clock=dut.clk)
    dut.uhost_req_ready.value = 1

    # Create SUMI driver for UMI response channel
    sumi_resp_driver = SumiDriver(
        entity=dut, name="uhost_resp", clock=dut.clk, valid_generator=resp_valid_gen
    )

    # Create UMI memory device
    umi_memory = UmiMemoryDevice(
        monitor=sumi_req_monitor, driver=sumi_resp_driver, log=dut._log
    )

    ####################################
    # Run test
    ####################################

    bus_width = env.alignment  # bytes per beat

    for i in range(test_n_writes):
        # Generate multi-beat write (2-4 beats) to test FIXED behavior
        num_beats = random.randint(2, 4)
        write_size = bus_width * num_beats
        test_addr = random.randint(0, (env.max_addr - bus_width) // env.alignment) * env.alignment
        test_data = random.randbytes(write_size)

        # Clear memory at test address before write
        umi_memory.write(test_addr, bytes(bus_width))

        dut._log.info(f"FIXED write {i+1}/{test_n_writes}: {num_beats} beats to 0x{test_addr:08x}")
        resp = await env.axi_master.write(test_addr, test_data, burst=AxiBurstType.FIXED)

        assert resp.resp == AxiResp.OKAY, f"Write {i+1} expected OKAY, got {resp.resp}"

        # With FIXED burst, all beats write to the same address
        # Only the last beat's data should remain in memory
        last_beat_data = test_data[-bus_width:]
        read_back = umi_memory.read(test_addr, bus_width)

        assert read_back == last_beat_data, (
            f"FIXED burst {i+1}: expected last beat data {last_beat_data.hex()}, "
            f"got {read_back.hex()}"
        )

    dut._log.info(f"All {test_n_writes} FIXED burst writes verified successfully")
    await ClockCycles(dut.clk, 10)


@cocotb.test(timeout_time=10, timeout_unit="ms")
@cocotb.parametrize(
    error_rate=[0.5, 1.0],
    error_code=[2, 3],
    resp_valid_gen=[None, generators.random_toggle_generator()],
    test_n_writes=[int(50 * float(os.getenv("RAND_TEST_LEN_SCALER", default=1)))]
)
async def error_injection_test(
    dut,
    error_rate=0.5,
    error_code=2,
    test_n_writes=10,
    resp_valid_gen=None
):
    """Test error injection - verify UMI errors propagate to AXI BRESP."""
    expected_resp = AxiResp(error_code)

    ####################################
    # Setup test
    ####################################

    Clock(dut.clk, 1, unit="ns").start()

    env = TestEnv(dut)
    await env.setup()

    # Create SUMI monitor for UMI request channel
    sumi_req_monitor = SumiMonitor(entity=dut, name="uhost_req", clock=dut.clk)
    dut.uhost_req_ready.value = 1

    # Create SUMI driver for UMI response channel
    sumi_resp_driver = SumiDriver(
        entity=dut, name="uhost_resp", clock=dut.clk, valid_generator=resp_valid_gen
    )

    # Create error-injecting memory device
    umi_memory = ErrorInjectingUmiMemoryDevice(
        monitor=sumi_req_monitor,
        driver=sumi_resp_driver,
        log=dut._log,
        error_rate=error_rate,
        error_code=error_code
    )

    ####################################
    # Run test
    ####################################

    ok_count = 0
    err_count = 0

    for i in range(test_n_writes):
        test_addr, test_data = env.random_write_params()

        errors_before = len(umi_memory.injected_errors)
        resp = await env.axi_master.write(test_addr, test_data)
        errors_after = len(umi_memory.injected_errors)

        error_injected = errors_after > errors_before

        if error_injected:
            assert resp.resp == expected_resp, (
                f"Write {i+1}: error injected but got {resp.resp.name}, expected {expected_resp.name}"
            )
            err_count += 1
        else:
            assert resp.resp == AxiResp.OKAY, (
                f"Write {i+1}: no error injected but got {resp.resp.name}, expected OKAY"
            )
            ok_count += 1

    dut._log.info(f"Completed {test_n_writes} writes: {ok_count} OKAY, {err_count} errors")
    await ClockCycles(dut.clk, 10)


class TbDesign(Design):

    def __init__(self):
        super().__init__()

        # Set the design's name
        self.set_name("tb_axiwr2umi")

        # Establish the root directory for all design-related files
        self.set_dataroot("tb_axiwr2umi", __file__)

        # Configure filesets within the established data root
        with self.active_dataroot("tb_axiwr2umi"):
            with self.active_fileset("testbench.cocotb"):
                self.set_topmodule("axiwr2umi")
                self.add_file("test_axiwr2umi.py", filetype="python")
                self.add_depfileset(AXI2UMI(), "rtl")


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
        filename="tb_axiwr2umi.vcd"
    )
    if vcd:
        print(f"Waveform file: {vcd}")


@pytest.mark.cocotb
def test_axiwr2umi():
    load_cocotb_test()
