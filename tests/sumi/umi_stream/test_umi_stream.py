import os
import math
import random
import copy

import pytest

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, Timer, Combine

from cocotb_bus.drivers import BitDriver
from cocotb_bus.scoreboard import Scoreboard

from cocotbext.umi.drivers.sumi_driver import SumiDriver
from cocotbext.umi.monitors.sumi_monitor import SumiMonitor
from cocotbext.umi.sumi import SumiCmd, SumiCmdType, SumiTransaction
from cocotbext.umi.tumi import TumiTransaction
from cocotbext.umi.utils import generators
from cocotbext.umi.utils.vrd_transaction import VRDTransaction

from siliconcompiler import Design

from umi.sumi.umi_stream.umi_stream import Stream

from valid_ready_driver import ValidReadyDriver
from valid_ready_monitor import ValidReadyMonitor
from run_cocotb_sim import load_cocotb_test


######################################################
# Test Environment
######################################################

class Env:
    """Reusable test environment for umi_stream tests."""

    def __init__(self, dut):
        self.dut = dut
        self.dw = int(dut.DW.value)
        self.aw = int(dut.AW.value)
        self.cw = int(dut.CW.value)
        self.data_bytes = self.dw // 8
        self.full_size = int(math.log2(self.data_bytes))

        self.umi_driver = None
        self.umi_monitor = None
        self.usi_source = None
        self.usi_monitor = None

        self.expected_usi_output = []
        self.expected_umi_output = []
        self.scoreboard = None

    async def assert_reset(self, nreset, period_ns=50):
        nreset.value = 1
        await Timer(1, unit="step")
        nreset.value = 0
        await Timer(period_ns, unit="ns")
        nreset.value = 1
        await Timer(period_ns, unit="ns")

    async def setup(
        self,
        umi_valid_gen,
        usi_valid_gen,
        umi_period_ns=10,
        usi_period_ns=12
    ):
        """Initialize signals, start clocks, apply reset, create drivers."""
        dut = self.dut

        # Initialize DUT inputs before drivers take over
        dut.devicemode.value = 1
        dut.s2mm_dstaddr.value = 0
        dut.s2mm_srcaddr.value = 0
        dut.s2mm_cmd.value = 0
        dut.umi_in_valid.value = 0
        dut.umi_in_cmd.value = 0
        dut.umi_in_dstaddr.value = 0
        dut.umi_in_srcaddr.value = 0
        dut.umi_in_data.value = 0
        dut.umi_out_ready.value = 0
        dut.usi_in_valid.value = 0
        dut.usi_in_last.value = 0
        dut.usi_in_data.value = 0
        dut.usi_out_ready.value = 0

        # Reset both clock domains
        umi_reset_task = cocotb.start_soon(self.assert_reset(dut.umi_nreset, umi_period_ns*5))
        usi_reset_task = cocotb.start_soon(self.assert_reset(dut.usi_nreset, usi_period_ns*5))
        await Combine(umi_reset_task, usi_reset_task)

        # Start independent clocks for UMI and USI domains
        Clock(dut.umi_clk, umi_period_ns, unit="ns").start()
        await Timer(umi_period_ns * random.random(), unit="ns", round_mode="round")
        Clock(dut.usi_clk, usi_period_ns, unit="ns").start()

        # Drivers
        self.umi_driver = SumiDriver(
            entity=dut,
            name="umi_in",
            clock=dut.umi_clk,
            valid_generator=umi_valid_gen
        )
        self.usi_source = ValidReadyDriver(
            entity=dut,
            name="usi_in",
            clock=dut.usi_clk,
            valid_generator=usi_valid_gen
        )

        # Monitors (passive -- do NOT drive ready signals)
        self.umi_monitor = SumiMonitor(entity=dut, name="umi_out", clock=dut.umi_clk)
        self.usi_monitor = ValidReadyMonitor(entity=dut, name="usi_out", clock=dut.usi_clk)

        # Scoreboard
        self.expected_usi_output = []
        self.expected_umi_output = []
        self.scoreboard = Scoreboard(dut, fail_immediately=True)
        self.scoreboard.add_interface(
            monitor=self.usi_monitor,
            expected_output=self.expected_usi_output
        )
        self.scoreboard.add_interface(
            monitor=self.umi_monitor,
            expected_output=self.expected_umi_output
        )

        await ClockCycles(dut.umi_clk, 5)


##################################################
# Test DUT in device mode
##################################################

@cocotb.test(timeout_time=100, timeout_unit="ms")
@cocotb.parametrize(
    umi_valid_gen=[None, generators.random_toggle_generator(), generators.wave_generator()],
    usi_valid_gen=[None, generators.random_toggle_generator(), generators.wave_generator()],
    umi_ready_gen=[None, generators.random_toggle_generator(), generators.wave_generator()],
    usi_ready_gen=[None, generators.random_toggle_generator(), generators.wave_generator()],
    n_ops=[int(20 * float(os.getenv("RAND_TEST_LEN_SCALER", default=1)))]
)
async def test_device_mode(
    dut,
    umi_valid_gen=None,
    usi_valid_gen=None,
    umi_ready_gen=None,
    usi_ready_gen=None,
    n_ops=20
):
    """Device mode: posted writes, writes with ack, and reads with data verification."""

    max_tumi_len = 500

    env = Env(dut)
    await env.setup(umi_valid_gen, usi_valid_gen)
    dut.devicemode.value = 1

    # Apply backpressure on UMI response consumer
    if umi_ready_gen is not None:
        BitDriver(signal=dut.umi_out_ready, clk=dut.umi_clk).start(generator=umi_ready_gen)
    else:
        dut.umi_out_ready.value = 1

    # Apply backpressure on USI stream consumer
    if usi_ready_gen is not None:
        BitDriver(signal=dut.usi_out_ready, clk=dut.usi_clk).start(generator=usi_ready_gen)
    else:
        dut.usi_out_ready.value = 1

    for _ in range(n_ops):

        ##############################################################
        # Generate random command type for UMI transaction
        ##############################################################
        cmd_type = random.choice([
            SumiCmdType.UMI_REQ_POSTED,
            SumiCmdType.UMI_REQ_WRITE,
            SumiCmdType.UMI_REQ_READ
        ])

        sumi_trans = None

        ##############################################################
        # Generate UMI transaction based on command type
        ##############################################################
        if cmd_type == SumiCmdType.UMI_REQ_READ:
            """
                TODO: RTL can only accept reads that can responded to with a single beat of data. 
                This should probably be fixed.
            """
            sumi_trans = [SumiTransaction(
                cmd=SumiCmd.from_fields(
                    cmd_type=cmd_type,
                    size=env.full_size,
                    len=0,
                    eom=1
                ),
                # TODO: DUT will accept any DST ADDR this seems like an issue 2 me
                da=random.randint(0, (1 << len(dut.umi_in_dstaddr)) - 1),
                sa=random.randint(0, (1 << len(dut.umi_in_srcaddr)) - 1),
                data=random.randbytes(env.data_bytes),
                addr_width=env.aw
            )]
        else:
            # Create random tumi transaction
            sumi_trans = TumiTransaction(
                cmd=SumiCmd.from_fields(cmd_type=cmd_type),
                da=random.randint(0, (1 << len(dut.umi_in_dstaddr)) - 1),
                sa=random.randint(0, (1 << len(dut.umi_in_srcaddr)) - 1),
                data=bytes(random.randbytes(
                    (random.randint(env.data_bytes, max_tumi_len) // env.data_bytes) * env.data_bytes
                )),
            ).to_sumi(
                data_bus_size=env.data_bytes,
                addr_width=env.aw
            )

        ##############################################################
        # Add expected values to scoreboard based on command type
        ##############################################################
        if cmd_type == SumiCmdType.UMI_REQ_POSTED:
            for t in sumi_trans:
                # Add sumi trans to expected output
                env.expected_usi_output.append(VRDTransaction(
                    data=t.data,
                    last=bool(int(t.cmd.eom))
                ))
        elif cmd_type == SumiCmdType.UMI_REQ_WRITE:
            for t in sumi_trans:
                # Add sumi trans to expected output
                env.expected_usi_output.append(VRDTransaction(
                    data=t.data,
                    last=bool(int(t.cmd.eom))
                ))
                # Add response to UMI expected output
                resp_cmd = copy.deepcopy(t.cmd)
                resp_cmd.cmd_type.from_int(SumiCmdType.UMI_RESP_WRITE)
                env.expected_umi_output.append(SumiTransaction(
                    cmd=resp_cmd,
                    da=int(t.sa),
                    # TODO: RTL hardcodes source address (This should be fixed and a expected value should be put here)
                    sa=0,
                    data=None,
                ))
        elif cmd_type == SumiCmdType.UMI_REQ_READ:
            for t in sumi_trans:
                data = random.randbytes(env.data_bytes)
                # Add response to UMI expected output
                resp_cmd = copy.deepcopy(t.cmd)
                resp_cmd.cmd_type.from_int(SumiCmdType.UMI_RESP_READ)
                env.expected_umi_output.append(SumiTransaction(
                    cmd=resp_cmd,
                    da=int(t.sa),
                    # TODO: RTL hardcodes source address (This should be fixed and a expected value should be put here)
                    sa=0,
                    data=data,
                ))
                env.usi_source.append(VRDTransaction(
                    data=data,
                    last=bool(int(t.cmd.eom))
                ))

        ##############################################################
        # Add randomly generated UMI transaction to UMI driver
        ##############################################################
        for t in sumi_trans:
            env.umi_driver.append(t)

    # Wait for all expected outputs to be consumed by scoreboards
    while (
        len(env.expected_usi_output) != 0
        or len(env.expected_umi_output) != 0
    ):
        await ClockCycles(dut.umi_clk, 1)

    # Check that scoreboard did not encounter any mismatches
    raise env.scoreboard.result


@cocotb.test(timeout_time=100, timeout_unit="ms")
@cocotb.parametrize(
    umi_valid_gen=[None, generators.random_toggle_generator(), generators.wave_generator()],
    usi_valid_gen=[None, generators.random_toggle_generator(), generators.wave_generator()],
    umi_ready_gen=[None, generators.random_toggle_generator(), generators.wave_generator()],
    usi_ready_gen=[None, generators.random_toggle_generator(), generators.wave_generator()],
    n_ops=[int(20 * float(os.getenv("RAND_TEST_LEN_SCALER", default=1)))]
)
async def test_non_device_mode(
    dut,
    umi_valid_gen=None,
    usi_valid_gen=None,
    umi_ready_gen=None,
    usi_ready_gen=None,
    n_ops=20
):
    """Non-device mode: full duplex with posted writes (MM2S) and stream-to-UMI (S2MM)."""

    max_tumi_len = 500

    env = Env(dut)
    await env.setup(umi_valid_gen, usi_valid_gen)
    dut.devicemode.value = 0

    # Apply backpressure on UMI output consumer
    if umi_ready_gen is not None:
        BitDriver(signal=dut.umi_out_ready, clk=dut.umi_clk).start(generator=umi_ready_gen)
    else:
        dut.umi_out_ready.value = 1

    # Apply backpressure on USI stream consumer
    if usi_ready_gen is not None:
        BitDriver(signal=dut.usi_out_ready, clk=dut.usi_clk).start(generator=usi_ready_gen)
    else:
        dut.usi_out_ready.value = 1

    async def mm2s_task():
        """MM2S: Posted writes from UMI input to USI output."""
        for _ in range(n_ops):

            ##############################################################
            # Generate random multi-beat posted write TUMI transaction
            ##############################################################
            sumi_trans = TumiTransaction(
                cmd=SumiCmd.from_fields(cmd_type=SumiCmdType.UMI_REQ_POSTED),
                da=random.randint(0, (1 << len(dut.umi_in_dstaddr)) - 1),
                sa=random.randint(0, (1 << len(dut.umi_in_srcaddr)) - 1),
                data=bytes(random.randbytes(
                    (random.randint(env.data_bytes, max_tumi_len) // env.data_bytes) * env.data_bytes
                )),
            ).to_sumi(
                data_bus_size=env.data_bytes,
                addr_width=env.aw
            )

            ##############################################################
            # Add expected USI output for each beat
            ##############################################################
            for t in sumi_trans:
                env.expected_usi_output.append(VRDTransaction(
                    data=t.data,
                    last=bool(int(t.cmd.eom))
                ))

            ##############################################################
            # Drive UMI posted writes
            ##############################################################
            for t in sumi_trans:
                env.umi_driver.append(t)

    async def s2mm_task():
        """S2MM: Stream data from USI input to UMI output with randomized s2mm fields."""
        for _ in range(n_ops):

            ##############################################################
            # Randomize external s2mm cmd/addr fields per transaction
            ##############################################################
            s2mm_cmd = SumiCmd.from_fields(
                cmd_type=SumiCmdType.UMI_REQ_POSTED,
                size=random.randint(0, env.full_size),
                len=random.randint(0, 255),
                eom=random.randint(0, 1)
            )
            s2mm_da = random.randint(0, (1 << env.aw) - 1)
            s2mm_sa = random.randint(0, (1 << env.aw) - 1)

            dut.s2mm_cmd.value = int(s2mm_cmd)
            dut.s2mm_dstaddr.value = s2mm_da
            dut.s2mm_srcaddr.value = s2mm_sa

            ##############################################################
            # Push one random USI beat into S2MM FIFO
            ##############################################################
            data = random.randbytes(env.data_bytes)
            last = random.choice([True, False])

            env.usi_source.append(VRDTransaction(data=data, last=last))

            ##############################################################
            # Add expected UMI output using current s2mm field values
            ##############################################################
            env.expected_umi_output.append(SumiTransaction(
                cmd=s2mm_cmd,
                da=s2mm_da,
                sa=s2mm_sa,
                data=data[:s2mm_cmd.total_bytes()],
            ))

            ##############################################################
            # Wait for this entry to drain before changing s2mm fields
            ##############################################################
            while len(env.expected_umi_output) > 0:
                await ClockCycles(dut.umi_clk, 1)

    mm2s = cocotb.start_soon(mm2s_task())
    s2mm = cocotb.start_soon(s2mm_task())
    await Combine(mm2s, s2mm)

    # Wait for all remaining expected outputs to be consumed by scoreboards
    while (
        len(env.expected_usi_output) != 0
        or len(env.expected_umi_output) != 0
    ):
        await ClockCycles(dut.umi_clk, 1)

    # Check that scoreboard did not encounter any mismatches
    raise env.scoreboard.result


class TbDesign(Design):

    def __init__(self):
        super().__init__()

        self.set_name("tb_umi_stream")

        self.set_dataroot("tb_umi_stream", __file__)

        with self.active_dataroot("tb_umi_stream"):
            with self.active_fileset("testbench.cocotb"):
                self.set_topmodule("umi_stream")
                self.add_file("test_umi_stream.py", filetype="python")
                self.add_depfileset(Stream(), "rtl")


@pytest.mark.cocotb
@pytest.mark.parametrize("simulator", ["icarus", "verilator"])
def test_umi_stream(simulator):
    load_cocotb_test(
        design=TbDesign(),
        simulator=simulator,
        trace=True,
        seed=None
    )
