import inspect
from pathlib import Path
from typing import List, Tuple
from siliconcompiler import Design


class UMI(Design):
    def __init__(self,
                 name: str,
                 files: List[str] = None,
                 idirs: List[str] = None,
                 deps: List[Design] = None,
                 defines: List[str] = None,
                 undefines: List[str] = None,
                 params: List[Tuple] = None):

        super().__init__(name)

        # move this
        cls = self.__class__
        module = inspect.getmodule(cls)
        localpath = Path(inspect.getfile(module)).resolve().parent
        globalpath = Path(__file__).resolve().parent

        # Taking care of Nones
        if idirs is None:
            idirs = []
        if deps is None:
            deps = []
        if defines is None:
            defines = []
        if undefines is None:
            undefines = []
        if params is None:
            params = []

        # dataroot
        self.set_dataroot('localroot', localpath)

        # Setting RTL list, others outside
        with self.active_fileset('rtl'):
            self.set_topmodule(name)
            self.add_idir(globalpath / 'sumi' / 'include')
            for item in files:
                self.add_file(item)
            for item in idirs:
                self.add_idir(item)
            for item in deps:
                self.add_depfileset(item)
            for item in defines:
                self.add_define(item)
            for item in undefines:
                self.add_undefine(item)
            for item in params:
                self.add_param(item[0], item[1])


##################################################
# Standard Definition
##################################################
class Standard(Design):
    def __init__(self):
        super().__init__("umi_standard")
        base_dir = Path(__file__).resolve().parent
        with self.active_fileset("rtl"):
            self.add_idir(base_dir / 'sumi' / 'include')
