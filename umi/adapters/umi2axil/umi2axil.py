from umi.common import UMI
from lambdalib.auxlib import Drsync
from umi.sumi import FifoFlex
from umi.sumi import Unpack
from umi.sumi import Pack


class UMI2AXIL(UMI):
    def __init__(self):
        super().__init__('umi2axil',
                         files=['rtl/umi2axil.v'],
                         idirs=['rtl'],
                         deps=[Drsync(),
                               FifoFlex(),
                               Unpack(),
                               Pack()])


if __name__ == "__main__":
    d = UMI2AXIL()
    d.write_fileset(f"{d.name}.f", fileset="rtl")
