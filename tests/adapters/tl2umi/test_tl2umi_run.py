import itertools

import pytest

from siliconcompiler import Design

from umi.adapters import TL2UMI


class TL2UMITestbench(Design):
    """TL2UMI testbench for cocotb testing (UMI memory agent in Python)"""

    def __init__(self, aw=64, dw=64):
        super().__init__()

        self.set_name(f"tb_tl2umi_aw{aw}_dw{dw}")
        self.set_dataroot("tl2umi", __file__)

        with self.active_dataroot("tl2umi"):
            with self.active_fileset("testbench.cocotb"):
                self.set_topmodule("tl2umi")
                self.set_param("AW", str(aw))
                self.set_param("DW", str(dw))
                # Add test files
                self.add_file("test_basic.py", filetype="python")
                self.add_file("test_advanced.py", filetype="python")
                # Add helper Python modules (populates PYTHONPATH via DVFlow)
                self.add_file("tl2umi_env.py", filetype="python")
                self.add_file("tl_driver.py", filetype="python")
                self.add_file("tl_monitor.py", filetype="python")
                # Add RTL dependency (no Verilog wrapper needed)
                self.add_depfileset(TL2UMI(), "rtl")


@pytest.mark.cocotb
@pytest.mark.parametrize("simulator, aw, dw", list(itertools.product(
    ["verilator"],
    [32, 64],
    [64, 128]
)))
def test_tl2umi(simulator, aw, dw):
    from run_cocotb_sim import load_cocotb_test
    load_cocotb_test(
        design=TL2UMITestbench(aw=aw, dw=dw),
        simulator=simulator,
        trace=False,
        seed=None
    )
