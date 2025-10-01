from umi.common import UMI
from umi.sumi.umi_pack.umi_pack import Pack
from umi.sumi.umi_unpack.umi_unpack import Unpack
from lambdalib.ramlib import Syncfifo


class FifoFlex(UMI):
    def __init__(self):
        super().__init__('umi_fifoflex',
                         files=['rtl/umi_fifoflex.v'],
                         deps=[Pack(),
                               Unpack(),
                               Syncfifo()])


if __name__ == "__main__":
    d = FifoFlex()
    d.write_fileset(f"{d.name}.f", fileset="rtl")
