import os
import pytest
from pathlib import Path

from siliconcompiler import Sim, Design
from siliconcompiler.flows.dvflow import DVFlow
from siliconcompiler.tools.verilator.cocotb_compile import CocotbCompileTask as VerilatorCompileTask
from siliconcompiler.tools.verilator.cocotb_exec import CocotbExecTask as VerilatorCocotbExecTask

from umi.adapters import UMI2APB


class UMI2APBTestbench(Design):
    """UMI2APB testbench for cocotb testing"""

    def __init__(self, aw=64, dw=256):
        super().__init__()

        self.set_name("tb_umi2apb")
        self.set_dataroot("umi2apb", __file__)

        with self.active_dataroot("umi2apb"):
            with self.active_fileset("testbench.cocotb"):
                self.set_topmodule("umi2apb")
                # Add test files
                self.add_file("test_basic_WR.py", filetype="python")
                self.add_file("test_backpressure.py", filetype="python")
                self.add_file("test_full_throughput.py", filetype="python")
                self.add_file("test_posted_write.py", filetype="python")
                self.add_file("test_random_stimulus.py", filetype="python")
                # Add RTL dependency
                self.add_depfileset(UMI2APB(), "rtl")

        # Store parameters
        self.aw = aw
        self.dw = dw


def run_umi2apb(simulator="verilator", waves=True, aw=64, dw=256, seed=None):
    # Create project
    project = Sim()
    project.set_design(UMI2APBTestbench(aw=aw, dw=dw))
    project.add_fileset("testbench.cocotb")

    # Set the cocotb design verification flow
    project.set_flow(DVFlow(tool=f"{simulator}-cocotb"))

    # Configure compilation
    compile_task = VerilatorCompileTask.find_task(project)
    compile_task.set_verilator_trace(waves)
    compile_task.add_parameter("AW", "int", "UMI address width", defvalue=aw)
    compile_task.add_parameter("DW", "int", "UMI data width", defvalue=dw)

    # Add tests directory to PYTHONPATH so cocotb test modules can find adapters.*
    tests_dir = str(Path(__file__).resolve().parent.parent.parent)
    os.environ["PYTHONPATH"] = tests_dir + os.pathsep + os.environ.get("PYTHONPATH", "")

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
def test_umi2apb(simulator, aw, dw):
    run_umi2apb(simulator, aw=aw, dw=dw)
