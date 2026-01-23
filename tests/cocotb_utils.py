import os
from pathlib import Path
from typing import List, Tuple, Optional, Mapping, Union

from siliconcompiler import Sim

from cocotb.triggers import Timer
from cocotb.handle import SimHandleBase

from cocotb_tools.runner import get_runner, VerilatorControlFile
from cocotb_tools.check_results import get_results


async def do_reset(
        reset: SimHandleBase,
        time_ns: int,
        active_level: bool = False):
    """Perform a async reset"""
    reset.value = not active_level
    await Timer(1, unit="step")
    reset.value = active_level
    await Timer(time_ns, "ns")
    reset.value = not active_level
    await Timer(1, unit="step")


def run_cocotb(
        project: Sim,
        test_module_name: str,
        output_dir_name: Optional[str] = None,
        simulator_name: str = "icarus",
        build_args: Optional[List] = None,
        timescale: Optional[Tuple[str, str]] = None,
        parameters: Optional[Mapping[str, object]] = None,
        seed: Optional[Union[str, int]] = None,
        waves: bool = True):
    """Launch cocotb given a SC Project"""

    if parameters is None:
        parameters = {}

    if output_dir_name is None:
        output_dir_name = test_module_name

    pytest_current_test = os.getenv("PYTEST_CURRENT_TEST", None)

    rootpath = Path(__file__).resolve().parent.parent
    top_level_dir = rootpath
    build_dir = rootpath / "build" / output_dir_name
    test_dir = None

    results_xml = None
    if not pytest_current_test:
        results_xml = build_dir / "results.xml"
        test_dir = top_level_dir

    # Get top level module name
    top_lvl_module_name = None
    main_filesets = project.get("option", "fileset")
    if main_filesets and len(main_filesets) != 0:
        main_fileset = main_filesets[0]
        top_lvl_module_name = project.design.get_topmodule(
            fileset=main_fileset
        )

    filesets = project.get_filesets()
    idirs = []
    defines = []
    for lib, fileset in filesets:
        idirs.extend(lib.find_files("fileset", fileset, "idir"))
        defines.extend(lib.get("fileset", fileset, "define"))

    sources = []
    for lib, fileset in filesets:
        for value in lib.get_file(fileset=fileset, filetype="systemverilog"):
            sources.append(value)
    for lib, fileset in filesets:
        for value in lib.get_file(fileset=fileset, filetype="verilog"):
            sources.append(value)

    vlt_files = []
    if simulator_name == "verilator":
        for lib, fileset in filesets:
            for value in lib.get_file(fileset=fileset, filetype="verilatorctrlfile"):
                vlt_files.append(VerilatorControlFile(value))

    # Build HDL in chosen simulator
    runner = get_runner(simulator_name)
    runner.build(
        sources=vlt_files + sources,
        includes=idirs,
        hdl_toplevel=top_lvl_module_name,
        build_args=build_args,
        waves=waves,
        timescale=timescale,
        build_dir=build_dir,
        parameters=parameters
    )

    # Run test
    _, tests_failed = get_results(runner.test(
        hdl_toplevel=top_lvl_module_name,
        test_module=test_module_name,
        test_dir=test_dir,
        test_args=build_args,
        results_xml=results_xml,
        build_dir=build_dir,
        seed=seed,
        waves=waves
    ))

    return tests_failed
