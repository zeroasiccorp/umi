import os
import random

import pytest

from siliconcompiler import Design

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles

from cocotb_bus.drivers import BitDriver

from cocotbext.axi import AxiBus, AxiMaster, AxiResp

from cocotbext.umi.drivers.sumi_driver import SumiDriver
from cocotbext.umi.monitors.sumi_monitor import SumiMonitor
from cocotbext.umi.models.umi_memory_device import UmiMemoryDevice
from cocotbext.umi.sumi import SumiCmd, SumiCmdType, SumiTransaction
from cocotbext.umi.utils import generators

from umi.adapters.axi2umi.axi2umi import AXI2UMI


class Env:
    """Reusable test environment for AXI4 Full to UMI adapter tests."""

    MAX_TRANSACTION_SIZE = 4096

    def __init__(self, dut):
        self.dut = dut
        self.axi_master = None
        self.max_addr = (1 << int(self.dut.AW.value)) - 1 - self.MAX_TRANSACTION_SIZE

    async def setup(self):
        """Initialize and reset the DUT, create AXI master."""
        dut = self.dut

        # Initialize AXI write signals
        dut.s_axi_wid.value = 0
        dut.s_axi_awvalid.value = 0
        dut.s_axi_wvalid.value = 0
        dut.s_axi_bready.value = 0

        # Initialize AXI read signals
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

        # Create the combined AXI master (read + write)
        axi_bus = AxiBus.from_prefix(dut, "s_axi")
        self.axi_master = AxiMaster(
            axi_bus,
            dut.clk,
            dut.nreset,
            reset_active_level=False
        )

        await ClockCycles(dut.clk, 5)

    def random_addr(self):
        """Generate random address for a transaction."""
        return random.randint(0, self.max_addr)


@cocotb.test(timeout_time=10, timeout_unit="ms")
@cocotb.parametrize(
    resp_valid_gen=[None, generators.random_toggle_generator(), generators.wave_generator()],
    req_ready_gen=[None, generators.random_toggle_generator(), generators.wave_generator()],
    test_n_transactions=[int(50 * float(os.getenv("RAND_TEST_LEN_SCALER", default=1)))]
)
async def basic_test(
    dut,
    test_n_transactions=10,
    resp_valid_gen=None,
    req_ready_gen=None
):
    """Basic read/write transaction test - verify data written can be read back."""

    ####################################
    # Setup test
    ####################################

    Clock(dut.clk, 1, unit="ns").start()

    env = Env(dut)
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
    UmiMemoryDevice(
        monitor=sumi_req_monitor,
        driver=sumi_resp_driver,
        log=dut._log
    )

    ####################################
    # Run test
    ####################################

    for i in range(test_n_transactions):
        # Random transaction size
        max_size = random.choices([4096, 256, 16], weights=[10, 40, 50])[0]
        size = random.randint(1, max_size)
        test_addr = env.random_addr()
        test_data = random.randbytes(size)

        # Write data
        dut._log.info(f"Transaction {i+1}/{test_n_transactions}: Write {size} bytes to 0x{test_addr:08x}")
        write_resp = await env.axi_master.write(test_addr, test_data)
        assert write_resp.resp == AxiResp.OKAY, f"Write {i+1} expected OKAY, got {write_resp.resp}"

        # Read data back
        dut._log.info(f"Transaction {i+1}/{test_n_transactions}: Read {size} bytes from 0x{test_addr:08x}")
        read_resp = await env.axi_master.read(test_addr, size)
        assert read_resp.resp == AxiResp.OKAY, f"Read {i+1} expected OKAY, got {read_resp.resp}"

        # Verify data matches
        read_data = bytes(read_resp.data)
        assert read_data == test_data, (
            f"Transaction {i+1} data mismatch at 0x{test_addr:08x}: "
            f"expected {test_data.hex()}, got {read_data.hex()}"
        )

    dut._log.info(f"All {test_n_transactions} read/write transactions verified successfully")
    await ClockCycles(dut.clk, 10)


@cocotb.test(timeout_time=10, timeout_unit="ms")
@cocotb.parametrize(
    resp_valid_gen=[None, generators.random_toggle_generator(), generators.wave_generator()],
    test_n_transactions=[int(50 * float(os.getenv("RAND_TEST_LEN_SCALER", default=1)))]
)
async def interleaved_test(
    dut,
    test_n_transactions=10,
    resp_valid_gen=None,
):
    """Test interleaved reads and writes to verify mux arbitration."""

    ####################################
    # Setup test
    ####################################

    Clock(dut.clk, 1, unit="ns").start()

    env = Env(dut)
    await env.setup()

    # Create SUMI monitor for UMI request channel
    sumi_req_monitor = SumiMonitor(entity=dut, name="uhost_req", clock=dut.clk)
    dut.uhost_req_ready.value = 1

    # Create SUMI driver for UMI response channel
    sumi_resp_driver = SumiDriver(entity=dut, name="uhost_resp", clock=dut.clk, valid_generator=resp_valid_gen)

    # Create UMI memory device
    umi_memory = UmiMemoryDevice(
        monitor=sumi_req_monitor,
        driver=sumi_resp_driver,
        log=dut._log
    )

    ####################################
    # Run test - pre-populate memory
    # then do random reads/writes
    ####################################

    # Pre-populate memory with known data
    mem_regions = {}  # addr -> (size, data) mapping
    for i in range(test_n_transactions):
        size = random.randint(1, 256)
        addr = env.random_addr()
        data = random.randbytes(size)
        umi_memory.write(addr, data)
        mem_regions[addr] = data

    # Randomly read or write
    for i in range(test_n_transactions):
        if random.random() < 0.5 and mem_regions:
            # Do a read from a known region
            addr = random.choice(list(mem_regions.keys()))
            expected_data = mem_regions[addr]
            size = len(expected_data)

            dut._log.info(f"Op {i+1}: Read {size} bytes from 0x{addr:08x}")
            read_resp = await env.axi_master.read(addr, size)
            assert read_resp.resp == AxiResp.OKAY
            assert bytes(read_resp.data) == expected_data
        else:
            # Do a write to a random location and track it
            size = random.randint(1, 256)
            addr = env.random_addr()
            data = random.randbytes(size)

            dut._log.info(f"Op {i+1}: Write {size} bytes to 0x{addr:08x}")
            write_resp = await env.axi_master.write(addr, data)
            assert write_resp.resp == AxiResp.OKAY

            # Verify write via memory model
            read_back = umi_memory.read(addr, size)
            assert read_back == data

            # Update tracking (overwrites any existing entry at this addr)
            mem_regions[addr] = data

    dut._log.info(f"All {test_n_transactions} interleaved operations completed successfully")
    await ClockCycles(dut.clk, 10)


async def inject_invalid_responses(driver, dut, n_invalid, min_gap=2, max_gap=15):
    """Inject n_invalid invalid UMI responses at random intervals.

    Each injected transaction carries an opcode that is neither UMI_RESP_WRITE
    nor UMI_RESP_READ, so the DUT's drop port should consume it immediately
    without disturbing in-flight AXI transactions.
    """
    aw = driver.get_addr_width()
    for i in range(n_invalid):
        await ClockCycles(dut.clk, random.randint(min_gap, max_gap))
        # Randomly pick an invalid resp opcode
        opcode = random.choice([
            SumiCmdType.UMI_INVALID,
            SumiCmdType.UMI_REQ_READ,
            SumiCmdType.UMI_REQ_WRITE,
            SumiCmdType.UMI_REQ_POSTED,
            SumiCmdType.UMI_RESP_USER0,
            SumiCmdType.UMI_RESP_USER1,
            SumiCmdType.UMI_RESP_FUTURE0,
            SumiCmdType.UMI_RESP_FUTURE1,
            SumiCmdType.UMI_RESP_LINK,
        ])
        cmd = SumiCmd()
        cmd.cmd_type.from_int(int(opcode))
        txn = SumiTransaction(
            cmd=cmd,
            da=random.randint(0, (1 << aw) - 1),
            sa=random.randint(0, (1 << aw) - 1),
            data=b'\x00',
            addr_width=aw,
        )
        dut._log.debug(f"Injecting invalid UMI response {i+1}/{n_invalid}: opcode=0x{int(opcode):02x}")
        driver.append(txn)


@cocotb.test(timeout_time=10, timeout_unit="ms")
@cocotb.parametrize(
    resp_valid_gen=[None, generators.random_toggle_generator(), generators.wave_generator()],
    test_n_transactions=[int(50 * float(os.getenv("RAND_TEST_LEN_SCALER", default=1)))]
)
async def drop_test(dut, test_n_transactions=10, resp_valid_gen=None):
    """Verify invalid UMI response opcodes are silently dropped.

    Injects ~2x as many invalid responses as there are AXI transactions,
    randomly interleaved with the normal traffic. All AXI reads and writes
    must still complete correctly, proving the drop path does not stall or
    corrupt in-flight transactions.
    """

    ####################################
    # Setup test
    ####################################

    Clock(dut.clk, 1, unit="ns").start()

    env = Env(dut)
    await env.setup()

    sumi_req_monitor = SumiMonitor(entity=dut, name="uhost_req", clock=dut.clk)
    dut.uhost_req_ready.value = 1

    sumi_resp_driver = SumiDriver(entity=dut, name="uhost_resp", clock=dut.clk, valid_generator=resp_valid_gen)

    UmiMemoryDevice(
        monitor=sumi_req_monitor,
        driver=sumi_resp_driver,
        log=dut._log
    )

    ####################################
    # Start invalid-response injector
    ####################################

    n_invalid = test_n_transactions * 2
    cocotb.start_soon(inject_invalid_responses(sumi_resp_driver, dut, n_invalid))

    ####################################
    # Run test
    ####################################

    for i in range(test_n_transactions):
        size = random.randint(1, 256)
        test_addr = env.random_addr()
        test_data = random.randbytes(size)

        dut._log.info(f"Transaction {i+1}/{test_n_transactions}: Write {size} bytes to 0x{test_addr:08x}")
        write_resp = await env.axi_master.write(test_addr, test_data)
        assert write_resp.resp == AxiResp.OKAY, f"Write {i+1} expected OKAY, got {write_resp.resp}"

        dut._log.info(f"Transaction {i+1}/{test_n_transactions}: Read {size} bytes from 0x{test_addr:08x}")
        read_resp = await env.axi_master.read(test_addr, size)
        assert read_resp.resp == AxiResp.OKAY, f"Read {i+1} expected OKAY, got {read_resp.resp}"

        assert bytes(read_resp.data) == test_data, (
            f"Transaction {i+1} data mismatch at 0x{test_addr:08x}: "
            f"expected {test_data.hex()}, got {bytes(read_resp.data).hex()}"
        )

    dut._log.info(
        f"All {test_n_transactions} transactions succeeded with "
        f"{n_invalid} invalid responses injected"
    )
    await ClockCycles(dut.clk, 10)


class TbDesign(Design):

    def __init__(self):
        super().__init__()

        # Set the design's name
        self.set_name("tb_axi2umi")

        # Establish the root directory for all design-related files
        self.set_dataroot("tb_axi2umi", __file__)

        # Configure filesets within the established data root
        with self.active_dataroot("tb_axi2umi"):
            with self.active_fileset("testbench.cocotb"):
                self.set_topmodule("axi2umi")
                self.add_file("test_axi2umi.py", filetype="python")
                self.add_depfileset(AXI2UMI(), "rtl")


@pytest.mark.cocotb
@pytest.mark.parametrize("simulator", ["icarus", "verilator"])
def test_axi2umi(simulator):
    from run_cocotb_sim import load_cocotb_test
    load_cocotb_test(
        design=TbDesign(),
        simulator=simulator,
        trace=False,
        seed=None
    )
