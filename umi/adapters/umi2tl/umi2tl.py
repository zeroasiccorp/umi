from umi.common import UMI
from umi.adapters.common import TileLink
from umi.sumi import FifoFlex
from umi.sumi import Unpack
from umi.sumi import Pack

class UMI2TL(UMI):
    def __init__(self):
        super().__init__('umi2tl',
                         files=['rtl/umi2tl.v'],
                         idirs=['rtl'],
                         deps=[TileLink(),
                               FifoFlex(),
                               Pack(),
                               Unpack()])


if __name__ == "__main__":
    d = UMI2TL()
    d.write_fileset(f"{d.name}.f", fileset="rtl")
