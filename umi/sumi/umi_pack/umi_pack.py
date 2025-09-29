from umi.common import UMI
from umi.sumi.umi_decode.umi_decode import Decode


class Pack(UMI):
    def __init__(self):
        super().__init__('umi_pack',
                         files=['rtl/umi_pack.v'],
                         deps=[Decode()])


if __name__ == "__main__":
    d = Pack()
    d.write_fileset(f"{d.name}.f", fileset="rtl")
