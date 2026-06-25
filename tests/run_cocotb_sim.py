import os
from pathlib import Path
from typing import List, Union
from siliconcompiler import Design, Sim
from lambdalib.reusable_tests.cocotb_common import use_cocotb
from sim_cmd_files.sim_cmd_files import IcarusCmdFile
from sim_cmd_files.sim_cmd_files import VerilatorCmdFile


def load_cocotb_test(
    design: Design,
    topmodule: str,
    cocotb_files: Union[str, List[str]],
    simulator="icarus",
    trace=True,
    seed=None,
    params=None,
):
    if isinstance(cocotb_files, str):
        cocotb_files = [cocotb_files]

    cocotb_files = [Path(f) for f in cocotb_files]

    ########################################################
    # Create test bench design object
    ########################################################
    tb_design = Design()
    tb_design.set_name(f"cocotb_test_{topmodule}")

    for cocotb_file in cocotb_files:
        print(f"data root name {cocotb_file.stem} path {cocotb_file.parent}")
        tb_design.set_dataroot(name=cocotb_file.stem, path=cocotb_file.parent)
        tb_design.add_file(
            filename=cocotb_file.name,
            fileset="testbench.cocotb",
            filetype="python",
            dataroot=cocotb_file.stem
        )

    tb_design.set_topmodule(topmodule, fileset="testbench.cocotb")

    # Add params
    for param_name, param_value in (params or {}).items():
        tb_design.set_param(param_name, str(param_value), fileset="testbench.cocotb")

    # Add user design as a dependency to the testbench.cocotb fileset
    tb_design.add_depfileset(dep=design, fileset="testbench.cocotb")

    # Add project specific icarus / verilator command files
    tb_design.add_depfileset(IcarusCmdFile(), fileset="icarus")
    tb_design.add_depfileset(VerilatorCmdFile(), fileset="verilator")

    ########################################################
    # Create project
    ########################################################
    project = Sim(tb_design)

    project.add_fileset("testbench.cocotb")
    use_cocotb(project=project, trace=trace, seed=seed)

    # Add simulator specific fileset
    project.add_fileset(simulator)

    # Set simulator specific flow
    project.set_flow(f"dvflow-{simulator}-cocotb")

    ########################################################
    # Run flow
    ########################################################
    # cocotb launches the simulation in a separate embedded interpreter whose
    # PYTHONPATH is seeded from os.environ. pytest puts the tests root on
    # sys.path via pyproject's pythonpath, but that does not reach the sim
    # subprocess. Add the tests root to python path env var here.

    tests_root = str(Path(__file__).parent.resolve())
    pythonpath = os.environ.get("PYTHONPATH", "")
    if tests_root not in pythonpath.split(os.pathsep):
        os.environ["PYTHONPATH"] = os.pathsep.join(
            p for p in [tests_root, pythonpath] if p
        )

    project.run()
    project.summary()
