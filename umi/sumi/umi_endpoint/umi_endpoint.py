from umi.sumi.common import Sumi
from umi.sumi.umi_decode.umi_decode import Decode
from umi.sumi.umi_pack.umi_pack import Pack
from umi.sumi.umi_unpack.umi_unpack import Unpack


class Endpoint(Sumi):
    def __init__(self):
        name = 'umi_endpoint'
        sources = 'rtl/umi_endpoint.v'
        super().__init__(name, sources)
        with self.active_fileset('rtl'):
            self.add_depfileset(Decode())
            self.add_depfileset(Pack())
            self.add_depfileset(Unpack())


if __name__ == "__main__":
    d = Endpoint()
    d.write_fileset("umi_endpoint.f", fileset="rtl")
