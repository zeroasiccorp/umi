from lambdalib.ramlib import Syncfifo
from umi.sumi.common import Sumi
from umi.sumi.umi_pack.umi_pack import Pack
from umi.sumi.umi_unpack.umi_unpack import Unpack


class FifoFlex(Sumi):
    def __init__(self):
        name = 'umi_fifoflex'
        sources = 'rtl/umi_fifoflex.v'
        super().__init__(name, sources)
        with self.active_fileset('rtl'):
            self.add_depfileset(Pack())
            self.add_depfileset(Unpack())
            self.add_depfileset(Syncfifo())


if __name__ == "__main__":
    d = FifoFlex()
    d.write_fileset("umi_fifoflex.f", fileset="rtl")
