from umi.common import UMI
from umi.sumi.umi_decode.umi_decode import Decode
from umi.sumi.umi_pack.umi_pack import Pack
from umi.sumi.umi_unpack.umi_unpack import Unpack


class Endpoint(UMI):
    def __init__(self):
        super().__init__('umi_endpoint',
                         files=['rtl/umi_endpoint.v'],
                         deps=[Decode(),
                               Pack(),
                               Unpack()])


if __name__ == "__main__":
    d = Endpoint()
    d.write_fileset(f"{d.name}.f", fileset="rtl")
