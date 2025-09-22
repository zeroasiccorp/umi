from lambdalib.ramlib import Asyncfifo
from umi.sumi.common import Sumi
from umi.sumi.umi_pack.umi_pack import Pack
from umi.sumi.umi_unpack.umi_unpack import Unpack


class Fifo(Sumi):
    def __init__(self):
        name = 'umi_fifo'
        sources = 'rtl/umi_fifo.v'
        super().__init__(name, sources)
        with self.active_fileset('rtl'):
            self.add_depfileset(Pack())
            self.add_depfileset(Unpack())
            self.add_depfileset(Asyncfifo())


if __name__ == "__main__":
    d = Fifo()
    d.write_fileset("umi_fifo.f", fileset="rtl")
