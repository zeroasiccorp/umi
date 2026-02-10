import pytest

from siliconcompiler import Sim, Design
from siliconcompiler.flows.dvflow import DVFlow
from siliconcompiler.tools.verilator.cocotb_compile import CocotbCompileTask as VerilatorCompileTask
from siliconcompiler.tools.verilator.cocotb_exec import CocotbExecTask as VerilatorCocotbExecTask

from umi.adapters import TL2UMI
from umi.sumi import MemAgent


class TL2UMITestbench(Design):
    """TL2UMI testbench with umi_memagent for cocotb testing"""

    def __init__(self, aw=64, dw=64):
        super().__init__()

        self.set_name("testbench")
        self.set_dataroot("tl2umi", __file__)

        with self.active_dataroot("tl2umi"):
            with self.active_fileset("testbench.cocotb"):
                self.set_topmodule("testbench")
                # Add testbench Verilog
                self.add_file("testbench.v", filetype="verilog")
                # Add test files
                self.add_file("test_basic.py", filetype="python")
                self.add_file("test_advanced.py", filetype="python")
                # Add helper Python modules (populates PYTHONPATH via DVFlow)
                self.add_file("env.py", filetype="python")
                self.add_file("tl_driver.py", filetype="python")
                self.add_file("tl_monitor.py", filetype="python")
                # Add RTL dependencies
                self.add_depfileset(TL2UMI(), "rtl")
                self.add_depfileset(MemAgent(), "rtl")

        # Store parameters
        self.aw = aw
        self.dw = dw


def run_tl2umi(simulator="verilator", waves=True, aw=64, dw=64, seed=None):
    # Create project
    project = Sim()
    project.set_design(TL2UMITestbench(aw=aw, dw=dw))
    project.add_fileset("testbench.cocotb")

    # Set the cocotb design verification flow
    project.set_flow(DVFlow(tool=f"{simulator}-cocotb"))

    # Configure compilation
    compile_task = VerilatorCompileTask.find_task(project)
    compile_task.set_verilator_trace(waves)
    compile_task.add_parameter("AW", "int", "UMI address width", defvalue=aw)
    compile_task.add_parameter("DW", "int", "UMI data width", defvalue=dw)

    # Run the simulation
    project.run()
    project.summary()

    # Check for failures
    results = project.find_result(
        step='simulate',
        index='0',
        directory="outputs",
        filename="results.xml"
    )
    if results:
        print(f"\nCocotb results file: {results}")

    return project


@pytest.mark.sim
@pytest.mark.parametrize("simulator", ["verilator"])
@pytest.mark.parametrize("aw", [32, 64])
@pytest.mark.parametrize("dw", [64, 128])
def test_tl2umi(simulator, aw, dw):
    run_tl2umi(simulator, aw=aw, dw=dw)
