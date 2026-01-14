import os
import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles

from cocotb_bus.scoreboard import Scoreboard
from cocotb_bus.drivers import BitDriver

from clink.tests.drivers.sumi_driver import SumiDriver
from clink.tests.models.rx_proto_bfm import RxProtoBFM
from clink.tests.utils.common import (
    drive_reset,
    random_toggle_generator,
    run_cocotb,
    wave_generator
)

from clink.tests.utils.sumi import SumiCmd, SumiCmdType
from clink.tests.utils.tumi import TumiTransaction


@cocotb.test()
@cocotb.parametrize(
    input_valid_gen=[None, random_toggle_generator(), wave_generator()],
    output_ready_gen=[None, random_toggle_generator(), wave_generator()],
    test_n_transactions=[int(200 * float(os.getenv("RAND_TEST_LEN_SCALER", default=1)))]
)
async def clink_txproto(
    dut,
    test_n_transactions=200,
    input_valid_gen=None,
    output_ready_gen=None
):

    max_tumi_size = (len(dut.umi_in_data) // 8) * 4

    dut.lumi_txready.value = 0

    ####################################
    # Setup test infrastructure
    ####################################

    # Create driver for sumi interface
    sumi_driver = SumiDriver(
        entity=dut,
        name="umi_in",
        clock=dut.clk,
        valid_generator=input_valid_gen,
        bus_separator="_"
    )

    # Create monitor for lumi interface
    lumi_monitor = RxProtoBFM(
        entity=dut,
        name="lumi_tx",
        clock=dut.clk,
        cw=int(dut.CW.value),
        aw=int(dut.AW.value),
        dw=int(dut.DW.value),
        bus_separator="",
    )

    # Create scoreboard for test
    expected_output = []

    scoreboard = Scoreboard(dut, fail_immediately=True)
    scoreboard.add_interface(monitor=lumi_monitor, expected_output=expected_output)

    ####################################
    # Reset DUT and start clock
    ####################################
    await drive_reset(reset=dut.nreset)
    Clock(dut.clk, 10, unit="ns").start()

    await ClockCycles(dut.clk, 10)

    # Assign constant or bit driver to lumi ready signal
    if output_ready_gen is None:
        dut.lumi_txready.value = 1
    else:
        BitDriver(signal=dut.lumi_txready, clk=dut.clk).start(generator=output_ready_gen)

    for _ in range(test_n_transactions):
        tumi_len = random.choices(
            population=[
                random.randint(1, len(dut.umi_in_data) // 8),
                random.randint(1, max_tumi_size)
            ],
            weights=[80, 20]
        )[0]

        debug = False

        # Create random tumi transaction
        sumi_trans = TumiTransaction(
            cmd=SumiCmd.from_fields(
                cmd_type=int(random.choice([
                    SumiCmdType.UMI_REQ_WRITE,
                    SumiCmdType.UMI_REQ_POSTED,
                    SumiCmdType.UMI_RESP_READ,
                    SumiCmdType.UMI_REQ_READ,
                    SumiCmdType.UMI_RESP_WRITE
                ]))
            ),
            da=random.randint(0, (1 << len(dut.umi_in_dstaddr)) - 1),
            sa=random.randint(0, (1 << len(dut.umi_in_srcaddr)) - 1),
            data=bytes([i % 255 for i in range(tumi_len)]) if debug else random.randbytes(tumi_len)
        ).to_sumi(
            data_bus_size=len(dut.umi_in_data) // 8,
            addr_width=len(dut.umi_in_dstaddr)
        )

        expected_output.extend(sumi_trans)

        # Append sumi transactions to drivers queue
        for trans in sumi_trans:
            sumi_driver.append(trans)

    # Wait for scoreboard to consume all expected outputs
    while len(expected_output) != 0:
        await ClockCycles(dut.clk, 1)

    await ClockCycles(dut.clk, 10)

    # Verify scoreboard results
    raise scoreboard.result


def load_cocotb_test(
        lumi_data_width=32,
        sumi_addr_width=32,
        sumi_data_width=128,
        simulator="icarus",
        output_wave=True):

    from clink import CLINK
    from siliconcompiler import Sim

    test_inst_name = f"lw_{lumi_data_width}_aw_{sumi_addr_width}_dw_{sumi_data_width}_sim_{simulator}"

    project = Sim(CLINK("clink_txproto"))
    project.add_fileset("rtl")

    test_module_name = __name__
    test_name = f"{test_module_name}_{test_inst_name}"
    tests_failed = run_cocotb(
        project=project,
        test_module_name=test_module_name,
        simulator_name=simulator,
        timescale=("1ns", "1ps"),
        build_args=["--report-unoptflat"] if simulator == "verilator" else [],
        parameters={
            "LW": lumi_data_width,
            "CW": 32,
            "AW": sumi_addr_width,
            "DW": sumi_data_width
        },
        output_dir_name=test_name,
        waves=output_wave
    )
    assert (tests_failed == 0), f"Error test {test_name} failed!"