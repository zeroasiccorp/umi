import pytest
from siliconcompiler import Sim

from umi.adapters import UMI2APB
from cocotb_utils import run_cocotb


def run_umi2apb(simulator="verilator", waves=True):
    project = Sim(UMI2APB())
    project.add_fileset("rtl")

    tests_failed = run_cocotb(
        project=project,
        test_module_name="tests.adapters.umi2apb",
        simulator_name=simulator,
        timescale=("1ns", "1ps"),
        build_args=["--report-unoptflat"] if simulator == "verilator" else [],
        output_dir_name=f"umi2apb_{simulator}",
        waves=waves,
    )

    assert tests_failed == 0


@pytest.mark.sim
@pytest.mark.parametrize("simulator", ["verilator"])
def test_umi2apb(simulator):
    run_umi2apb(simulator)
