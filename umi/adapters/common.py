import sys
from pathlib import Path
from typing import List, Tuple
from siliconcompiler import Design

##################################################
# Standard Definitions
##################################################
class TileLink(Design):
    def __init__(self):
        super().__init__("tilelink_standard")
        base_dir = Path(__file__).resolve().parent
        with self.active_fileset("rtl"):
            self.add_idir(base_dir / 'include')
