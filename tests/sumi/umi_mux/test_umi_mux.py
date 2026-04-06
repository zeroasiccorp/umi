import os
import random
from pathlib import Path
import pytest

from siliconcompiler import Design
from umi.sumi.umi_mux.umi_mux import Mux

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, Timer

from cocotb_bus.drivers import BitDriver
from cocotbext.umi.sumi import SumiCmd, SumiCmdType, SumiTransaction
from cocotbext.umi.drivers.sumi_driver import SumiDriver
from cocotbext.umi.monitors.sumi_monitor import SumiMonitor

from cocotbext.umi.utils.generators import (
    random_toggle_generator,
    wave_generator
)


@cocotb.test(timeout_time=20, timeout_unit="us")
@cocotb.parametrize(
    input_valid_gen=[None, random_toggle_generator(), wave_generator()],
    output_ready_gen=[None, random_toggle_generator(), wave_generator()],
    test_n_transactions=[int(100 * float(os.getenv("RAND_TEST_LEN_SCALER", default=1)))],
    arbmode=[0, 1]
)
async def mux_general_test(
    dut,
    arbmode=0,
    test_n_transactions=100,
    input_valid_gen=None,
    output_ready_gen=None
):

    umi_inputs = int(dut.umi_mux_i.N.value)
    data_size = int(dut.DW.value)//8
    aw = int(dut.AW.value)

    dut.clk.value = 0
    dut.nreset.value = 0

    dut.arbmode.value = arbmode
    dut.arbmask.value = 0

    ####################################
    # Create UMI Input Drivers
    ####################################
    umi_drivers = [
        SumiDriver(
            entity=dut,
            name=f"umi_in{i}",
            clock=dut.clk,
            valid_generator=input_valid_gen
        )
        for i in range(umi_inputs)
    ]

    ####################################
    # Create UMI mux output monitor
    ####################################
    umi_monitor = SumiMonitor(
        entity=dut,
        name="umi_out",
        clock=dut.clk
    )

    # Drive UMI out ready signal
    if output_ready_gen is None:
        dut.umi_out_ready.value = 1
    else:
        BitDriver(signal=dut.umi_out_ready, clk=dut.clk).start(generator=output_ready_gen)

    # Reset sequence (active-low reset)
    dut.nreset.value = 1
    await Timer(1, unit="step")
    dut.nreset.value = 0
    await Timer(10, unit="ns")
    dut.nreset.value = 1
    await Timer(10, unit="ns")

    # Start clock
    Clock(dut.clk, 1, unit="ns").start()

    expected_trans = []
    actual_trans = []

    # Monitor appends received transactions to actual_trans
    umi_monitor.add_callback(lambda trans: actual_trans.append(trans))

    # Callback so that transactions are added to expected_trans
    # in the order that they are sent
    def transaction_sent_callback(trans: SumiTransaction):
        expected_trans.append(trans)

    expected_trans_cnt = 0
    for umi_driver in umi_drivers:
        # Create random transactions
        transactions = [
            SumiTransaction(
                cmd=SumiCmd.from_fields(
                    cmd_type=int(SumiCmdType.UMI_REQ_WRITE),
                    size=1,
                    len=data_size
                ),
                addr_width=aw,
                da=random.randint(0, (1 << aw) - 1),
                sa=random.randint(0, (1 << aw) - 1),
                data=random.randbytes(data_size)
            )
            for _ in range(test_n_transactions + random.randint(0, 10))
        ]
        for t in transactions:
            umi_driver.append(t, callback=transaction_sent_callback)
        expected_trans_cnt += len(transactions)

    # Wait for all transactions to be received
    while len(actual_trans) != expected_trans_cnt:
        await ClockCycles(dut.clk, 10)

    # Verify expected output equals actual
    for expected, actual in zip(expected_trans, actual_trans):
        assert expected == actual


class TbDesign(Design):

    def __init__(self):
        super().__init__()

        self.set_name("tb_umi_mux")

        self.set_dataroot("tb_umi_mux", __file__)

        with self.active_dataroot("tb_umi_mux"):
            with self.active_fileset("testbench.cocotb"):
                self.set_topmodule("umi_mux_8_to_1")
                self.add_file("rtl/umi_mux_8_to_1.v")
                self.add_file(Path(__file__).name, filetype="python")
                self.add_depfileset(Mux(), "rtl")


@pytest.mark.cocotb
@pytest.mark.parametrize("simulator", ["icarus", "verilator"])
def test_umi_mux_cocotb(simulator):
    from run_cocotb_sim import load_cocotb_test
    load_cocotb_test(
        design=TbDesign(),
        simulator=simulator,
        trace=False,
        seed=None
    )
