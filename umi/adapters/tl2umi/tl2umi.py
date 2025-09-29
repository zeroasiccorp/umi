from umi.common import UMI
from umi.adapters.common import TileLink
from umi.sumi import FifoFlex
from umi.sumi import Unpack
from umi.sumi import Pack


class TL2UMI(UMI):
    def __init__(self):
        super().__init__('tl2umi',
                         files=['rtl/tl2umi.v',
                                'rtl/umi_data_aggregator.v'],
                         idirs=['rtl'],
                         deps=[TileLink(),
                               FifoFlex(),
                               Unpack(),
                               Pack()])


if __name__ == "__main__":
    d = TL2UMI()
    d.write_fileset(f"{d.name}.f", fileset="rtl")
