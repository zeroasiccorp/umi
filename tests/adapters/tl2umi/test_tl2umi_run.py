import itertools

import pytest

from siliconcompiler import Sim
from siliconcompiler.targets.dvflow_cocotb import dvflow_cocotb

from umi.adapters import TL2UMI

from cocotb_utils import CocotbSimEnv


class TL2UMITestbench(CocotbSimEnv):
    """TL2UMI testbench for cocotb testing (UMI memory agent in Python)"""

    def __init__(self, aw=64, dw=64):
        super().__init__(
            name=f"tb_tl2umi_aw{aw}_dw{dw}",
            topmodule="tl2umi",
            files=[
                "adapters/tl2umi/test_basic.py",
                "adapters/tl2umi/test_advanced.py",
            ],
            dep=[TL2UMI()],
            param=[("AW", str(aw)), ("DW", str(dw))]
        )


@pytest.mark.cocotb
@pytest.mark.parametrize("simulator, aw, dw", list(itertools.product(
    ["verilator"],
    [64],
    [64, 128]
)))
def test_tl2umi(simulator, aw, dw):
    project = Sim(TL2UMITestbench(aw=aw, dw=dw))
    project.add_fileset("testbench.cocotb")

    dvflow_cocotb(
        project=project,
        trace=False,
        timescale=("1ns", "1ps"),
        seed=None
    )

    project.set_flow(f"{simulator}cocotbdvflow")

    project.run()
    project.summary()
