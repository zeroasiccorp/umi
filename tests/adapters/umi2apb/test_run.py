import pytest

from siliconcompiler import Design

from umi.adapters.umi2apb.umi2apb import UMI2APB


class TbDesign(Design):

    def __init__(self):
        super().__init__()

        self.set_name("tb_umi2apb")

        self.set_dataroot("tb_umi2apb", __file__)

        with self.active_dataroot("tb_umi2apb"):
            with self.active_fileset("testbench.cocotb"):
                self.set_topmodule("umi2apb")
                self.add_file("env.py", filetype="python")
                self.add_file("test_basic_WR.py", filetype="python")
                self.add_file("test_backpressure.py", filetype="python")
                self.add_file("test_full_throughput.py", filetype="python")
                self.add_file("test_posted_write.py", filetype="python")
                self.add_file("test_random_stimulus.py", filetype="python")
                self.add_depfileset(UMI2APB(), "rtl")


@pytest.mark.cocotb
@pytest.mark.parametrize("simulator", ["icarus", "verilator"])
def test_umi2apb(simulator, output_wave=False):
    from run_cocotb_sim import load_cocotb_test
    load_cocotb_test(
        design=TbDesign(),
        simulator=simulator,
        trace=output_wave,
        seed=None
    )
