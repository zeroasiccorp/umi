import os
import random
from typing import Any
import itertools

import pytest

from siliconcompiler import Design

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge, Timer
from cocotb.types import LogicArray
from cocotb.handle import SimHandleBase

from cocotb_bus.scoreboard import Scoreboard
from cocotb_bus.drivers import BitDriver, ValidatedBusDriver
from cocotb_bus.monitors import BusMonitor

from cocotbext.umi.utils.generators import (
    random_toggle_generator,
    wave_generator
)

from umi.sumi.umi_buffer.umi_buffer import Buffer


class ValidReadyDriver(ValidatedBusDriver):

    _signals = [
        "data",
        "valid",
        "ready"
    ]

    _optional_signals = []

    def __init__(
        self,
        entity: SimHandleBase,
        name: str,
        clock: SimHandleBase,
        *,
        config={},
        **kwargs: Any
    ):
        ValidatedBusDriver.__init__(self, entity, name, clock, **kwargs)

        self.clock = clock
        self.bus.valid.value = 0

    async def _driver_send(self, transaction: bytes, sync: bool = True) -> None:
        """Implementation for BusDriver.
        Args:
            transaction: The transaction to send.
            sync: Synchronize the transfer by waiting for a rising edge.
        """

        clk_re = RisingEdge(self.clock)

        if sync:
            await clk_re

        # Insert a gap where valid is low
        if not self.on:
            self.bus.valid.value = 0
            for _ in range(self.off):
                await clk_re

            # Grab the next set of on/off values
            self._next_valids()

        # Consume a valid cycle
        if self.on is not True and self.on:
            self.on -= 1

        def ready() -> bool:
            return bool(self.bus.ready.value)

        while True:
            self.bus.valid.value = 1
            self.bus.data.value = LogicArray.from_bytes(transaction, byteorder="little")
            await clk_re
            if ready():
                break

        self.bus.valid.value = 0


class ValidReadyMonitor(BusMonitor):

    _signals = [
        "data",
        "valid",
        "ready"
    ]

    _optional_signals = []

    def __init__(self, entity, name, clock, **kwargs):
        BusMonitor.__init__(self, entity, name, clock, **kwargs)

    async def _monitor_recv(self):
        clk_re = RisingEdge(self.clock)

        def valid_handshake():
            return bool(self.bus.valid.value) and bool(self.bus.ready.value)

        while True:
            await clk_re
            if valid_handshake():
                self._recv(self.bus.data.value.to_bytes(byteorder="little"))


async def drive_reset(reset, time_ns=50):
    reset.value = 1
    await Timer(1, unit="step")
    reset.value = 0
    await Timer(time_ns, unit="ns")
    reset.value = 1
    await Timer(1, unit="step")


@cocotb.test()
@cocotb.parametrize(
    input_valid_gen=[None, random_toggle_generator(), wave_generator()],
    output_ready_gen=[None, random_toggle_generator(), wave_generator()],
    test_n_transactions=[int(100 * float(os.getenv("RAND_TEST_LEN_SCALER", default=1)))]
)
async def umi_buffer_data_integrity_test(
    dut,
    test_n_transactions=100,
    input_valid_gen=None,
    output_ready_gen=None
):
    """Test data integrity through the buffer.

    Data should pass through unchanged regardless of MODE (bypass or skid buffer).
    """

    input_driver = ValidReadyDriver(
        entity=dut,
        name="in",
        clock=dut.clk,
        valid_generator=input_valid_gen,
        bus_separator="_"
    )

    output_monitor = ValidReadyMonitor(
        entity=dut,
        name="out",
        clock=dut.clk,
        bus_separator="_"
    )

    expected_output = []
    scoreboard = Scoreboard(dut, fail_immediately=True)
    scoreboard.add_interface(monitor=output_monitor, expected_output=expected_output)

    data_width = int(dut.DW.value)
    data_size = data_width // 8

    # Reset DUT and start clock
    await drive_reset(reset=dut.nreset)
    Clock(dut.clk, 10, unit="ns").start()

    await ClockCycles(dut.clk, 10)

    # Assign constant or bit driver to output ready signal
    if output_ready_gen is None:
        dut.out_ready.value = 1
    else:
        BitDriver(signal=dut.out_ready, clk=dut.clk).start(generator=output_ready_gen)

    # Generate random transactions
    data_to_driver = [
        random.randbytes(data_size)
        for _ in range(test_n_transactions)
    ]

    # Add generated data to expected output
    expected_output.extend(data_to_driver)

    # Drive test data into DUT
    for driver_input in data_to_driver:
        input_driver.append(driver_input)

    # Wait for scoreboard to consume all expected outputs
    while len(expected_output) != 0:
        await ClockCycles(dut.clk, 1)

    await ClockCycles(dut.clk, 10)

    # Verify scoreboard results
    raise scoreboard.result


@cocotb.test()
async def umi_buffer_backpressure_test(dut):
    """Test backpressure handling - data should not be lost when out_ready drops."""

    input_driver = ValidReadyDriver(
        entity=dut,
        name="in",
        clock=dut.clk,
        bus_separator="_"
    )

    output_monitor = ValidReadyMonitor(
        entity=dut,
        name="out",
        clock=dut.clk,
        bus_separator="_"
    )

    expected_output = []
    scoreboard = Scoreboard(dut, fail_immediately=True)
    scoreboard.add_interface(monitor=output_monitor, expected_output=expected_output)

    data_width = int(dut.DW.value)
    data_size = data_width // 8

    # Reset DUT and start clock
    await drive_reset(reset=dut.nreset)
    Clock(dut.clk, 10, unit="ns").start()

    await ClockCycles(dut.clk, 10)

    # Start with ready high
    dut.out_ready.value = 1

    # Generate test transactions
    test_n_transactions = 20
    data_to_driver = [
        random.randbytes(data_size)
        for _ in range(test_n_transactions)
    ]

    # Add generated data to expected output
    expected_output.extend(data_to_driver)

    # Drive test data into DUT
    for driver_input in data_to_driver:
        input_driver.append(driver_input)

    # Use aggressive backpressure toggling
    BitDriver(signal=dut.out_ready, clk=dut.clk).start(
        generator=random_toggle_generator(on_range=(1, 3), off_range=(1, 5))
    )

    # Wait for scoreboard to consume all expected outputs
    while len(expected_output) != 0:
        await ClockCycles(dut.clk, 1)

    await ClockCycles(dut.clk, 10)

    # Verify scoreboard results
    raise scoreboard.result


class TbDesign(Design):

    def __init__(self, mode: int):
        super().__init__()

        # Set the design's name
        self.set_name(f"tb_umi_buffer_mode_{mode}")

        # Establish the root directory for all design-related files
        self.set_dataroot("tb_umi_buffer", __file__)

        # Configure filesets within the established data root
        with self.active_dataroot("tb_umi_buffer"):
            with self.active_fileset("testbench.cocotb"):
                self.set_topmodule("umi_buffer")
                self.set_param("MODE", str(mode))
                self.add_file("test_umi_buffer.py", filetype="python")
                self.add_depfileset(Buffer(), "rtl")


@pytest.mark.cocotb
@pytest.mark.parametrize("simulator, mode", list(itertools.product(
    ["icarus", "verilator"],
    [0, 1]
)))
def test_umi_buffer(simulator, mode):
    from run_cocotb_sim import load_cocotb_test
    load_cocotb_test(
        design=TbDesign(mode),
        simulator=simulator,
        trace=False,
        seed=None
    )
