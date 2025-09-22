from pathlib import Path
from typing import Union, List
from siliconcompiler import Design

##################################################
# Helper Class (saves typing)
##################################################
class Sumi(Design):
    def __init__(self,
                 name: str,
                 sources: List[str] = None):
        base_dir = Path(__file__).resolve().parent
        super().__init__(name)
        with self.active_fileset("rtl"):
            # add messages/global definitions
            self.add_idir(base_dir / 'include')
            # adding top module
            self.set_topmodule(name)
            # setting abs paths to all sources
            if isinstance(sources, str):
                sources = [sources]
            for item in sources:
                self.add_file(base_dir / name / item)
