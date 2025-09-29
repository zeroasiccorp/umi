from umi.common import UMI
from umi.sumi import Unpack
from umi.sumi import Pack


class UMI2APB(UMI):
    def __init__(self):
        super().__init__('umi2apb',
                         files=['rtl/umi2apb.v'],
                         idirs=['rtl'],
                         deps=[Unpack(),
                               Pack()])


if __name__ == "__main__":
    d = UMI2APB()
    d.write_fileset(f"{d.name}.f", fileset="rtl")
