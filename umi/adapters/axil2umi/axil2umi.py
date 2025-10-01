from umi.common import UMI
from lambdalib.auxlib import Drsync
from umi.sumi import Unpack
from umi.sumi import Pack


class AXIL2UMI(UMI):
    def __init__(self):
        super().__init__('axil2umi',
                         files=['rtl/axil2umi.v'],
                         idirs=['rtl'],
                         deps=[Drsync(),
                               Pack(),
                               Unpack()])


if __name__ == "__main__":
    d = AXIL2UMI()
    d.write_fileset(f"{d.name}.f", fileset="rtl")
