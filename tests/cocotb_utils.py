from typing import List, Tuple
from siliconcompiler import Design
from cocotb.triggers import Timer


class CocotbSimEnv(Design):

    def __init__(
        self,
        name: str = None,
        topmodule: str = None,
        files: List[str] = None,
        dep: List[Design] = None,
        define: List[str] = None,
        undefine: List[str] = None,
        param: List[Tuple] = None
    ):

        if name:
            super().__init__(name)
        else:
            super().__init__(topmodule)

        self.set_dataroot("local", __file__)

        # Taking care of Nones
        if files is None:
            files = []
        if dep is None:
            dep = []
        if define is None:
            define = []
        if undefine is None:
            undefine = []
        if param is None:
            param = []

        with self.active_dataroot("local"):
            with self.active_fileset('testbench.cocotb'):
                if topmodule:
                    self.set_topmodule(topmodule)
                for item in files:
                    self.add_file(item)
                for item in dep:
                    self.add_depfileset(item)
                for item in define:
                    self.add_define(item)
                for item in undefine:
                    self.add_undefine(item)
                for item in param:
                    self.set_param(item[0], item[1])
                self.add_libdir(".")


async def drive_reset(reset, time_ns=50, active_level=False):
    """Drive an asynchronous reset pulse on *reset*.

    Holds *reset* asserted for *time_ns* nanoseconds. *active_level* selects
    the asserted logic level (False for active-low resets, the default).
    """
    reset.value = int(not active_level)
    await Timer(1, unit="step")
    reset.value = int(active_level)
    await Timer(time_ns, unit="ns")
    reset.value = int(not active_level)
    await Timer(1, unit="step")
