import pytest

from siliconcompiler import Sim
from siliconcompiler.targets.dvflow_cocotb import dvflow_cocotb

from umi.adapters.umi2apb.umi2apb import UMI2APB

from cocotb_utils import CocotbSimEnv


class TbDesign(CocotbSimEnv):

    def __init__(self, param=None):
        super().__init__(
            name="tb_umi2apb",
            topmodule="umi2apb",
            files=[
                "adapters/umi2apb/test_basic_WR.py",
                "adapters/umi2apb/test_backpressure.py",
                "adapters/umi2apb/test_full_throughput.py",
                "adapters/umi2apb/test_posted_write.py",
                "adapters/umi2apb/test_random_stimulus.py",
                "adapters/umi2apb/test_subword_err.py",
            ],
            dep=[UMI2APB()],
            param=param
        )


@pytest.mark.cocotb
@pytest.mark.parametrize("simulator", ["icarus", "verilator"])
@pytest.mark.parametrize("param", [
    pytest.param([], id="rw64"),
    pytest.param([("RW", "32"), ("RAW", "32"), ("GRPAW", "8")], id="rw32_grp")])
def test_umi2apb(simulator, param, output_wave=False):
    project = Sim(TbDesign(param))
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
