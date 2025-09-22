from umi.sumi.common import Sumi
from umi.sumi import Arbiter
from lambdalib.veclib import Vmux2b


class Mux2(Sumi):
    def __init__(self):
        name = 'umi_mux2'
        sources = 'rtl/umi_mux2.v'
        super().__init__(name, sources)
        self.add_depfileset(Arbiter(), fileset='rtl')
        self.add_depfileset(Vmux2b(), fileset='rtl')


if __name__ == "__main__":
    d = Mux2()
    d.write_fileset("umi_mux2.f", fileset="rtl")
