import pytest
from switchboard import SbDut
from umi.lumi import LUMI
from umi.sumi import MemAgent
from siliconcompiler import Design
from switchboard.verilog.sim.switchboard_sim import SwitchboardSim


def pytest_collection_modifyitems(items):
    for item in items:
        if "lumi_dut" in getattr(item, "fixturenames", ()):
            item.add_marker("switchboard")
            pass


@pytest.fixture
def build_dir(pytestconfig):
    return pytestconfig.cache.mkdir('lumi_build')


@pytest.fixture
def lumi_dut(build_dir, request):

    class TB(Design):

        def __init__(self):
            top_module = "testbench"
            super().__init__("TB")
            self.set_dataroot('localroot', __file__)

            deps = [
                LUMI(),
                MemAgent()
            ]

            with self.active_fileset('rtl'):
                self.set_topmodule(top_module)
                self.add_file("../../umi/lumi/testbench/testbench_lumi.sv")
                for item in deps:
                    self.add_depfileset(item)

            with self.active_fileset('verilator'):
                self.set_topmodule(top_module)
                self.add_depfileset(self, "rtl")
                self.add_depfileset(SwitchboardSim())

            with self.active_fileset('icarus'):
                self.set_topmodule(top_module)
                self.add_depfileset(self, "rtl")
                self.add_depfileset(SwitchboardSim())

    import os
    print(f"CUR DIR {os.getcwd()}\n\n\n")

    dut = SbDut(
        design=TB(),
        fileset="verilator",
        tool="verilator",
        default_main=True,
        trace=False
    )

    # Build simulator
    dut.build()

    yield dut

    dut.terminate()


@pytest.fixture(params=("2d", "3d"))
def chip_topo(request):
    return request.param
