from lambdalib.veclib import Vmux
from umi.sumi.common import Sumi
from umi.sumi.umi_arbiter.umi_arbiter import Arbiter


class Crossbar(Sumi):
    def __init__(self):
        name = 'umi_crossbar'
        sources = 'rtl/umi_crossbar.v'
        super().__init__(name, sources)
        with self.active_fileset('rtl'):
            self.add_depfileset(Arbiter())
            self.add_depfileset(Vmux())


if __name__ == "__main__":
    d = Crossbar()
    d.write_fileset("umi_crossbar.f", fileset="rtl")
