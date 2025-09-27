from umi.common import UMI
from lambdalib.veclib import Vmux
from umi.sumi.umi_arbiter.umi_arbiter import Arbiter

class Mux(UMI):
    def __init__(self):
        super().__init__('umi_mux',
                         files=['rtl/umi_mux.v'],
                         deps=[Arbiter(),
                               Vmux()])


if __name__ == "__main__":
    d = Mux()
    d.write_fileset(f"{d.name}.f", fileset="rtl")
