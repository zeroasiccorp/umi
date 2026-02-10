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

from valid_ready_driver import ValidReadyDriver
from valid_ready_monitor import ValidReadyMonitor

from siliconcompiler import Design, Sim
from siliconcompiler.flows.dvflow import DVFlow

from siliconcompiler.tools.icarus.compile import CompileTask as IcarusCompileTask
from siliconcompiler.tools.icarus.cocotb_exec import CocotbExecTask as IcarusCocotbExecTask

from umi.sumi.umi_stream.umi_stream import Stream


######################################################
# UMI Response Compare
######################################################

def make_umi_compare(expected_output, scoreboard):
    """Create a monitor callback that compares UMI responses on critical fields.

    The Scoreboard registers this directly as the monitor callback when
    compare_fn is provided, so it must pop from expected_output itself.
    """
    def check(transaction):
        if not expected_output:
            scoreboard.errors += 1
            scoreboard.log.error("Received UMI response but wasn't expecting any")
            if scoreboard._imm:
                raise AssertionError("Received UMI response but wasn't expecting any")
            return

        exp = expected_output.pop(0)
        errors = []

        if int(transaction.cmd.cmd_type) != int(exp.cmd.cmd_type):
            errors.append(
                f"cmd_type: expected {exp.cmd.cmd_type}, got {transaction.cmd.cmd_type}"
            )

        if int(transaction.da) != int(exp.da):
            errors.append(
                f"da: expected 0x{int(exp.da):x}, got 0x{int(transaction.da):x}"
            )

        if exp.data is not None:
            got_data = int.from_bytes(transaction.data, 'little') if transaction.data else 0
            exp_data = int.from_bytes(exp.data, 'little')
            if got_data != exp_data:
                errors.append(
                    f"data: expected 0x{exp_data:x}, got 0x{got_data:x}"
                )

        if errors:
            scoreboard.errors += 1
            for e in errors:
                scoreboard.log.error(f"UMI response mismatch: {e}")
            if scoreboard._imm:
                raise AssertionError("UMI response mismatch:\n" + "\n".join(errors))

    return check


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

    async def setup(self, umi_valid_gen, umi_period_ns=10, usi_period_ns=12):
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
        self.usi_source = ValidReadyDriver(entity=dut, name="usi_in", clock=dut.usi_clk)

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


######################################################
# Cocotb Tests
######################################################

@cocotb.test(timeout_time=100, timeout_unit="ms")
@cocotb.parametrize(
    umi_valid_gen=[None, generators.random_toggle_generator(), generators.wave_generator()],
    umi_ready_gen=[None, generators.random_toggle_generator(), generators.wave_generator()],
    usi_ready_gen=[None, generators.random_toggle_generator(), generators.wave_generator()],
    n_ops=[int(20 * float(os.getenv("RAND_TEST_LEN_SCALER", default=1)))]
)
async def test_device_mode(
    dut,
    umi_valid_gen=None,
    umi_ready_gen=None,
    usi_ready_gen=None,
    n_ops=20
):
    """Device mode: posted writes, writes with ack, and reads with data verification."""

    env = Env(dut)
    await env.setup(umi_valid_gen)
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

    ####################################
    # Phase 1: Posted writes
    ####################################
    dut._log.info(f"Phase 1: {n_ops} posted writes")
    max_tumi_len = 500
    for _ in range(n_ops):

        cmd_type = random.choice([
            SumiCmdType.UMI_REQ_POSTED,
            SumiCmdType.UMI_REQ_WRITE,
            SumiCmdType.UMI_REQ_READ
        ])

        sumi_trans = None

        if cmd_type == SumiCmdType.UMI_REQ_READ:
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

        # Add sumi trans to UMI driver
        for t in sumi_trans:
            env.umi_driver.append(t)

    while (
        len(env.expected_usi_output) != 0
        or len(env.expected_umi_output) != 0
    ):
        await ClockCycles(dut.umi_clk, 1)

    raise env.scoreboard.result



    #####################################
    ## Phase 3: Reads from S2MM FIFO
    #####################################
    #dut._log.info(f"Phase 3: {n_ops} reads")
    #for i in range(n_ops):
    #    data = random.getrandbits(env.dw)
    #    srcaddr = random.getrandbits(env.aw)

    #    # Queue USI data into S2MM FIFO
    #    env.usi_source.append(VRDTransaction(
    #        data=data.to_bytes(env.data_bytes, 'little'),
    #        last=True
    #    ))
    #    # Queue UMI read request (DUT stalls until FIFO has data)
    #    cmd = SumiCmd.from_fields(
    #        cmd_type=SumiCmdType.UMI_REQ_READ,
    #        size=env.full_size,
    #        len=0,
    #        eom=1
    #    )
    #    env.umi_driver.append(SumiTransaction(
    #        cmd=cmd,
    #        da=random.getrandbits(env.aw),
    #        sa=srcaddr,
    #        data=bytes(env.data_bytes),
    #        addr_width=env.aw
    #    ))
    #    env.expected_umi_output.append(SumiTransaction(
    #        cmd=SumiCmd.from_fields(
    #            cmd_type=SumiCmdType.UMI_RESP_READ,
    #            size=env.full_size,
    #            len=0,
    #            eom=1
    #        ),
    #        da=srcaddr,
    #        sa=0,
    #        data=data.to_bytes(env.data_bytes, 'little'),
    #        addr_width=env.aw
    #    ))

    #while env.expected_umi_output:
    #    await ClockCycles(dut.umi_clk, 1)

    #await ClockCycles(dut.umi_clk, 20)
    #dut._log.info("Device mode test complete")


#@cocotb.test(timeout_time=100, timeout_unit="ms")
#@cocotb.parametrize(
#    umi_ready_gen=[None, generators.random_toggle_generator(), generators.wave_generator()],
#    usi_ready_gen=[None, generators.random_toggle_generator(), generators.wave_generator()],
#    n_ops=[int(20 * float(os.getenv("RAND_TEST_LEN_SCALER", default=1)))]
#)
async def test_nondevice_mode(
    dut,
    umi_ready_gen=None,
    usi_ready_gen=None,
    n_ops=20
):
    """Non-device (full duplex) mode: posted writes and stream-to-UMI passthrough."""

    env = Env(dut)
    await env.setup()
    dut.devicemode.value = 0
    await ClockCycles(dut.umi_clk, 5)

    if umi_ready_gen is not None:
        BitDriver(signal=dut.umi_out_ready, clk=dut.umi_clk).start(generator=umi_ready_gen)
    else:
        dut.umi_out_ready.value = 1

    if usi_ready_gen is not None:
        BitDriver(signal=dut.usi_out_ready, clk=dut.usi_clk).start(generator=usi_ready_gen)
    else:
        dut.usi_out_ready.value = 1

    ####################################
    # Phase 1: Posted writes to stream
    ####################################
    dut._log.info(f"Phase 1: {n_ops} posted writes (non-device)")
    for i in range(n_ops):
        data = random.getrandbits(env.dw)
        eom = random.choice([0, 1])
        cmd = SumiCmd.from_fields(
            cmd_type=SumiCmdType.UMI_REQ_POSTED,
            size=env.full_size,
            len=0,
            eom=eom
        )
        env.umi_driver.append(SumiTransaction(
            cmd=cmd,
            da=random.getrandbits(env.aw),
            sa=random.getrandbits(env.aw),
            data=data.to_bytes(env.data_bytes, 'little'),
            addr_width=env.aw
        ))
        env.expected_usi_output.append(VRDTransaction(
            data=data.to_bytes(env.data_bytes, 'little'),
            last=bool(eom)
        ))

    while env.expected_usi_output:
        await ClockCycles(dut.umi_clk, 1)

    dut._log.info("Phase 1 passed: non-device posted writes")

    ####################################
    # Phase 2: Stream to UMI passthrough
    ####################################
    dut._log.info(f"Phase 2: {n_ops} stream-to-UMI passthrough")

    # Configure S2MM control signals for passthrough
    s2mm_cmd = SumiCmd.from_fields(
        cmd_type=SumiCmdType.UMI_RESP_READ,
        size=env.full_size,
        len=0,
        eom=1
    )
    s2mm_dst = random.getrandbits(env.aw)
    s2mm_src = random.getrandbits(env.aw)
    dut.s2mm_cmd.value = int(s2mm_cmd)
    dut.s2mm_dstaddr.value = s2mm_dst
    dut.s2mm_srcaddr.value = s2mm_src

    for i in range(n_ops):
        data = random.getrandbits(env.dw)
        env.usi_source.append(VRDTransaction(
            data=data.to_bytes(env.data_bytes, 'little'),
            last=True
        ))
        env.expected_umi_output.append(SumiTransaction(
            cmd=s2mm_cmd,
            da=s2mm_dst,
            sa=0,
            data=data.to_bytes(env.data_bytes, 'little'),
            addr_width=env.aw
        ))

    while env.expected_umi_output:
        await ClockCycles(dut.umi_clk, 1)

    dut._log.info("Phase 2 passed: stream-to-UMI passthrough")
    await ClockCycles(dut.umi_clk, 20)
    raise env.scoreboard.result


#@cocotb.test(timeout_time=200, timeout_unit="ms")
async def test_fifo_stress(dut):
    """Stress test: rapid posted writes with slow stream consumption to exercise FIFO."""

    env = Env(dut)
    await env.setup()
    dut.devicemode.value = 1

    # Slow stream consumer to force FIFO fill-up
    BitDriver(signal=dut.usi_out_ready, clk=dut.usi_clk).start(
        generator=generators.wave_generator()
    )
    dut.umi_out_ready.value = 1

    n = int(100 * float(os.getenv("RAND_TEST_LEN_SCALER", default=1)))

    for i in range(n):
        data = random.getrandbits(env.dw)
        eom = 1 if (i % 8 == 7) else 0
        cmd = SumiCmd.from_fields(
            cmd_type=SumiCmdType.UMI_REQ_POSTED,
            size=env.full_size,
            len=0,
            eom=eom
        )
        env.umi_driver.append(SumiTransaction(
            cmd=cmd,
            da=0,
            sa=0,
            data=data.to_bytes(env.data_bytes, 'little'),
            addr_width=env.aw
        ))
        env.expected_usi_output.append(VRDTransaction(
            data=data.to_bytes(env.data_bytes, 'little'),
            last=bool(eom)
        ))

    while env.expected_usi_output:
        await ClockCycles(dut.umi_clk, 1)

    await ClockCycles(dut.umi_clk, 10)
    dut._log.info(f"FIFO stress test passed ({n} transactions)")
    raise env.scoreboard.result


#@cocotb.test(timeout_time=100, timeout_unit="ms")
async def test_mixed_operations(dut):
    """Interleaved device-mode operations: posted writes, ack writes, and reads."""

    env = Env(dut)
    await env.setup()
    dut.devicemode.value = 1

    # Moderate backpressure on both consumer sides
    BitDriver(signal=dut.umi_out_ready, clk=dut.umi_clk).start(
        generator=generators.random_toggle_generator()
    )
    BitDriver(signal=dut.usi_out_ready, clk=dut.usi_clk).start(
        generator=generators.random_toggle_generator()
    )

    n = int(30 * float(os.getenv("RAND_TEST_LEN_SCALER", default=1)))
    dut._log.info(f"Running {n} mixed operations")

    # Pre-generate operation sequence, compute expected outputs, and queue all
    for i in range(n):
        op = random.choice(['posted_write', 'write_ack', 'read'])
        data = random.getrandbits(env.dw)
        data_bytes = data.to_bytes(env.data_bytes, 'little')
        srcaddr = random.getrandbits(env.aw)
        dstaddr = random.getrandbits(env.aw)

        if op == 'posted_write':
            eom = random.choice([0, 1])
            cmd = SumiCmd.from_fields(
                cmd_type=SumiCmdType.UMI_REQ_POSTED,
                size=env.full_size,
                len=0,
                eom=eom
            )
            env.umi_driver.append(SumiTransaction(
                cmd=cmd,
                da=dstaddr,
                sa=srcaddr,
                data=data_bytes,
                addr_width=env.aw
            ))
            env.expected_usi_output.append(VRDTransaction(
                data=data_bytes,
                last=bool(eom)
            ))

        elif op == 'write_ack':
            cmd = SumiCmd.from_fields(
                cmd_type=SumiCmdType.UMI_REQ_WRITE,
                size=env.full_size,
                len=0,
                eom=1
            )
            env.umi_driver.append(SumiTransaction(
                cmd=cmd,
                da=dstaddr,
                sa=srcaddr,
                data=data_bytes,
                addr_width=env.aw
            ))
            env.expected_usi_output.append(VRDTransaction(
                data=data_bytes,
                last=True
            ))
            env.expected_umi_output.append(SumiTransaction(
                cmd=SumiCmd.from_fields(
                    cmd_type=SumiCmdType.UMI_RESP_WRITE,
                    size=env.full_size,
                    len=0,
                    eom=1
                ),
                da=srcaddr,
                sa=0,
                data=None,
                addr_width=env.aw
            ))

        elif op == 'read':
            # Queue USI data into S2MM FIFO
            env.usi_source.append(VRDTransaction(
                data=data_bytes,
                last=True
            ))
            cmd = SumiCmd.from_fields(
                cmd_type=SumiCmdType.UMI_REQ_READ,
                size=env.full_size,
                len=0,
                eom=1
            )
            env.umi_driver.append(SumiTransaction(
                cmd=cmd,
                da=dstaddr,
                sa=srcaddr,
                data=bytes(env.data_bytes),
                addr_width=env.aw
            ))
            env.expected_umi_output.append(SumiTransaction(
                cmd=SumiCmd.from_fields(
                    cmd_type=SumiCmdType.UMI_RESP_READ,
                    size=env.full_size,
                    len=0,
                    eom=1
                ),
                da=srcaddr,
                sa=0,
                data=data_bytes,
                addr_width=env.aw
            ))

    # Wait for all expected outputs to be consumed by scoreboards
    while env.expected_usi_output or env.expected_umi_output:
        await ClockCycles(dut.umi_clk, 1)

    dut._log.info(f"Mixed operations test passed ({n} ops)")
    await ClockCycles(dut.umi_clk, 20)
    raise env.scoreboard.result


######################################################
# SiliconCompiler Design & Pytest Integration
######################################################

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


def load_cocotb_test(trace=True, seed=None):
    project = Sim()
    project.set_design(TbDesign())
    project.add_fileset("testbench.cocotb")

    project.set_flow(DVFlow(tool="icarus-cocotb"))

    IcarusCompileTask.find_task(project).set_trace_enabled(trace)

    if seed is not None:
        IcarusCocotbExecTask.find_task(project).set_cocotb_randomseed(seed)

    project.run()
    project.summary()

    results = project.find_result(
        step='simulate',
        index='0',
        directory="outputs",
        filename="results.xml"
    )
    if results:
        print(f"\nCocotb results file: {results}")

    vcd = project.find_result(
        step='simulate',
        index='0',
        directory="reports",
        filename="tb_umi_stream.vcd"
    )
    if vcd:
        print(f"Waveform file: {vcd}")


@pytest.mark.cocotb
def test_umi_stream():
    load_cocotb_test()
