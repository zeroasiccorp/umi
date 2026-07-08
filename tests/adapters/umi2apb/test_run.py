import pytest

from siliconcompiler import Sim
from siliconcompiler.targets.dvflow_cocotb import dvflow_cocotb

from umi.adapters.umi2apb.umi2apb import UMI2APB

from cocotb_utils import CocotbSimEnv


class TbDesign(CocotbSimEnv):

    def __init__(self):
        super().__init__(
            name="tb_umi2apb",
            topmodule="umi2apb",
            files=[
                "adapters/umi2apb/test_basic_WR.py",
                "adapters/umi2apb/test_backpressure.py",
                "adapters/umi2apb/test_full_throughput.py",
                "adapters/umi2apb/test_posted_write.py",
                "adapters/umi2apb/test_random_stimulus.py",
            ],
            dep=[UMI2APB()]
        )


@pytest.mark.cocotb
@pytest.mark.parametrize("simulator", ["icarus", "verilator"])
def test_umi2apb(simulator, output_wave=False):
    project = Sim(TbDesign())
    project.add_fileset("testbench.cocotb")

    dvflow_cocotb(
        project=project,
        trace=output_wave,
        timescale=("1ns", "1ps"),
        seed=None
    )

    project.set_flow(f"{simulator}cocotbdvflow")

    project.run()
    project.summary()
