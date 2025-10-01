from umi.common import UMI
from lambdalib.veclib import Vmux
from umi.sumi.umi_arbiter.umi_arbiter import Arbiter


class Crossbar(UMI):
    def __init__(self):
        super().__init__('umi_crossbar',
                         files=['rtl/umi_crossbar.v'],
                         deps=[Vmux(),
                               Arbiter()])


if __name__ == "__main__":
    d = Crossbar()
    d.write_fileset(f"{d.name}.f", fileset="rtl")
