import pytest
from pathlib import Path
from siliconcompiler import Sim

from umi.common import UMI
from umi.adapters import TL2UMI
from umi.sumi import MemAgent
from cocotb_utils import run_cocotb


class TL2UMITestbench(UMI):
    """TL2UMI testbench with umi_memagent for cocotb testing"""

    def __init__(self):
        testbench_path = Path(__file__).parent / "testbench.v"
        super().__init__(
            'testbench',
            files=[str(testbench_path)],
            idirs=[],
            deps=[TL2UMI(), MemAgent()]
        )


def run_tl2umi(simulator="verilator", waves=True):
    # Create project with testbench
    project = Sim(TL2UMITestbench())
    project.add_fileset("rtl")

    tests_failed = run_cocotb(
        project=project,
        test_module_name="tests.adapters.tl2umi.test_basic, tests.adapters.tl2umi.test_advanced",
        simulator_name=simulator,
        timescale=("1ns", "1ps"),
        build_args=["--report-unoptflat"] if simulator == "verilator" else [],
        output_dir_name=f"tl2umi_{simulator}",
        waves=waves,
    )

    assert tests_failed == 0


@pytest.mark.sim
@pytest.mark.parametrize("simulator", ["verilator"])
def test_tl2umi(simulator):
    run_tl2umi(simulator)
