from pathlib import Path
from typing import Union, List
from siliconcompiler import Design
from umi.sumi import Standard

class Sumi(Design):
    def __init__(self,
                 name: str,
                 sources: List[str] = None):
        base_dir = Path(__file__).resolve().parent
        path = base_dir / name
        super().__init__(name)
        self.set_dataroot(name, path)
        with self.active_fileset("rtl"):
            self.add_depfileset(Standard())
            self.set_topmodule(name)
            self.add_file(sources)
