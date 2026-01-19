import os
import math
import string
from typing import Optional, List, Tuple, Mapping, Union

import random
from pathlib import Path
from decimal import Decimal

from cocotb.triggers import Timer
from cocotb_tools.runner import get_runner, VerilatorControlFile
from cocotb_tools.check_results import get_results


from siliconcompiler import Sim


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

    if build_args is None:
        build_args = []

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
    sc_defines = []
    for lib, fileset in filesets:
        idirs.extend(lib.find_files("fileset", fileset, "idir"))
        sc_defines.extend(lib.get("fileset", fileset, "define"))

    defines = {}
    for define in sc_defines:
        parts = define.split("=", 1)
        if len(parts) == 2:
            defines[parts[0]] = parts[1]
        elif len(parts) == 1:
            defines[parts[0]] = "1"

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
        parameters=parameters,
        defines=defines
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


def random_decimal(max: int, min: int, decimal_places=2) -> Decimal:
    prefix = str(random.randint(min, max))
    suffix = ''.join(random.choice(string.digits) for _ in range(decimal_places))
    return Decimal(prefix + "." + suffix)


async def drive_reset(reset, reset_time_in_ns=100, active_level=False):
    """Perform a async reset"""
    reset.value = not active_level
    await Timer(1, unit="step")
    reset.value = active_level
    await Timer(reset_time_in_ns, "ns")
    reset.value = not active_level
    await Timer(1, unit="step")


def random_toggle_generator(on_range=(0, 15), off_range=(0, 15)):
    return bit_toggler_generator(
        gen_on=(random.randint(*on_range) for _ in iter(int, 1)),
        gen_off=(random.randint(*off_range) for _ in iter(int, 1))
    )


def sine_wave_generator(amplitude, w, offset=0):
    while True:
        for idx in (i / float(w) for i in range(int(w))):
            yield amplitude * math.sin(2 * math.pi * idx) + offset


def bit_toggler_generator(gen_on, gen_off):
    for n_on, n_off in zip(gen_on, gen_off):
        yield int(abs(n_on)), int(abs(n_off))


def wave_generator(on_ampl=30, on_freq=200, off_ampl=10, off_freq=100):
    return bit_toggler_generator(sine_wave_generator(on_ampl, on_freq),
                                 sine_wave_generator(off_ampl, off_freq))
