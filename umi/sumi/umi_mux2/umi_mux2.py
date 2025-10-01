from umi.common import UMI
from umi.sumi import Arbiter
from lambdalib.veclib import Vmux2b


class Mux2(UMI):
    def __init__(self):
        super().__init__('umi_mux2',
                         files=['rtl/umi_mux2.v'],
                         deps=[Arbiter(),
                               Vmux2b()])


if __name__ == "__main__":
    d = Mux2()
    d.write_fileset(f"{d.name}.f", fileset="rtl")
