from siliconcompiler import Design, Sim
from siliconcompiler.flows.dvflow import DVFlow

from siliconcompiler.tools.icarus.compile import CompileTask as IcarusCompileTask
from siliconcompiler.tools.icarus.cocotb_exec import CocotbExecTask as IcarusCocotbExecTask

from siliconcompiler.tools.verilator.cocotb_compile import CocotbCompileTask as VerilatorCompileTask
from siliconcompiler.tools.verilator.cocotb_exec import CocotbExecTask as VerilatorCocotbExecTask


class IcarusDesign(Design):
    def __init__(self, design: Design):
        super().__init__()

        self.set_name(f"{design.name}_icarus_sim")

        self.set_dataroot("icarus_tb", __file__)

        with self.active_dataroot("icarus_tb"):
            with self.active_fileset("icarus_sim"):
                self.add_file("sim_cmd_files/icarus_cmd_file.f", filetype="commandfile")
                self.add_depfileset(design, "testbench.cocotb")
                self.set_topmodule(design.get_topmodule("testbench.cocotb"))


class VerilatorDesign(Design):
    def __init__(self, design: Design):
        super().__init__()

        self.set_name(f"{design.name}_verilator_sim")

        self.set_dataroot("verilator_tb", __file__)

        with self.active_dataroot("verilator_tb"):
            with self.active_fileset("verilator_sim"):
                self.add_file("sim_cmd_files/verilator_cmd_file.vc", filetype="commandfile")
                self.add_depfileset(design, "testbench.cocotb")
                self.set_topmodule(design.get_topmodule("testbench.cocotb"))


def load_cocotb_test(
    design: Design,
    simulator="icarus",
    trace=True,
    seed=None
):

    if simulator == "icarus":
        load_cocotb_icarus_sim(design, trace=trace, seed=seed)
    elif simulator == "verilator":
        load_cocotb_verilator_sim(design, trace=trace, seed=seed, trace_type="vcd")


def load_cocotb_icarus_sim(
    design: Design,
    trace=True,
    seed=None
):
    project = Sim()
    project.set_design(IcarusDesign(design))
    project.add_fileset("icarus_sim")
    project.set_flow(DVFlow(tool="icarus-cocotb"))

    IcarusCompileTask.find_task(project).set_trace_enabled(trace)

    if seed is not None:
        IcarusCocotbExecTask.find_task(project).set_cocotb_randomseed(seed)

    project.run()
    project.summary()

    results = project.find_result(
        step='simulate',
        index='0',
        directory="outputs",
        filename="results.xml"
    )
    if results:
        print(f"\nCocotb results file: {results}")

    vcd = project.find_result(
        step='simulate',
        index='0',
        directory="reports",
        filename="tb_umi_stream.vcd"
    )
    if vcd:
        print(f"Waveform file: {vcd}")


def load_cocotb_verilator_sim(
    design: Design,
    trace=True,
    seed=None,
    trace_type="vcd"
):
    project = Sim()
    project.set_design(VerilatorDesign(design))
    project.add_fileset("verilator_sim")
    project.set_flow(DVFlow(tool="verilator-cocotb"))

    # Enable waveform tracing (must be enabled on both compile and simulate tasks)
    compile_task = VerilatorCompileTask.find_task(project)
    compile_task.set_verilator_trace(trace)
    compile_task.set_verilator_tracetype(trace_type)

    cocotb_task = VerilatorCocotbExecTask.find_task(project)
    cocotb_task.set_cocotb_trace(
        enable=trace,
        trace_type=trace_type
    )

    # Optionally set a random seed for reproducibility
    if seed is not None:
        cocotb_task.set_cocotb_randomseed(seed)

    # Run the simulation
    project.run()
    project.summary()

    # Find and display the results file
    results = project.find_result(
        step='simulate',
        index='0',
        directory="outputs",
        filename="results.xml"
    )
    if results:
        print(f"\nCocotb results file: {results}")

    # Find and display the waveform file
    wave_ext = trace_type if trace_type in ("vcd", "fst") else "vcd"
    wave = project.find_result(
        step='simulate',
        index='0',
        directory="reports",
        filename=f"adder.{wave_ext}"
    )
    if wave:
        print(f"Waveform file: {wave}")
