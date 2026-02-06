import pytest
from siliconcompiler import Sim

from umi.adapters import UMI2APB
from cocotb_utils import run_cocotb


def run_umi2apb(simulator="verilator", waves=True, aw=64, dw=256):
    project = Sim(UMI2APB())
    project.add_fileset("rtl")

    tests_failed = run_cocotb(
        project=project,
        test_module_name="tests.adapters.umi2apb.test_basic_WR, "
        "tests.adapters.umi2apb.test_backpressure, "
        "tests.adapters.umi2apb.test_full_throughput, "
        "tests.adapters.umi2apb.test_posted_write, "
        "tests.adapters.umi2apb.test_random_stimulus",
        simulator_name=simulator,
        timescale=("1ns", "1ps"),
        build_args=["--report-unoptflat"] if simulator == "verilator" else [],
        output_dir_name=f"umi2apb_{simulator}_aw{aw}_dw{dw}",
        parameters={"AW": aw, "DW": dw},
        waves=waves,
    )
    assert tests_failed == 0


@pytest.mark.sim
@pytest.mark.parametrize("simulator", ["verilator"])
@pytest.mark.parametrize("aw", [32, 64])
@pytest.mark.parametrize("dw", [64, 128])
def test_umi2apb(simulator, aw, dw):
    run_umi2apb(simulator, aw=aw, dw=dw)
