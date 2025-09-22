from umi.sumi.common import Sumi
from lambdalib.veclib import Vpriority


class Arbiter(Sumi):
    def __init__(self):
        name = 'umi_arbiter'
        sources = 'rtl/umi_arbiter.v'
        super().__init__(name, sources)
        self.add_depfileset(Vpriority(), fileset='rtl')


if __name__ == "__main__":
    d = Arbiter()
    d.write_fileset("umi_arbiter.f", fileset="rtl")
