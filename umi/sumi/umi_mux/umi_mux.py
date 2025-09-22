from umi.sumi.common import Sumi
from lambdalib.veclib import Vmux
from umi.sumi.umi_arbiter.umi_arbiter import Arbiter


class Mux(Sumi):
    def __init__(self):
        name = 'umi_mux'
        sources = 'rtl/umi_mux.v'
        super().__init__(name, sources)
        self.add_depfileset(Arbiter(), fileset='rtl')
        self.add_depfileset(Vmux(), fileset='rtl')


if __name__ == "__main__":
    d = Mux()
    d.write_fileset("umi_mux.f", fileset="rtl")
