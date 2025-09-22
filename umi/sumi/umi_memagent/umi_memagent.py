from lambdalib.ramlib import Spram
from umi.sumi.common import Sumi
from umi.sumi.umi_endpoint.umi_endpoint import Endpoint
from umi.sumi.umi_fifoflex.umi_fifoflex import FifoFlex


class MemAgent(Sumi):
    def __init__(self):
        name = 'umi_memagent'
        sources = 'rtl/umi_memagent.v'
        super().__init__(name, sources)
        with self.active_fileset('rtl'):
            self.add_depfileset(FifoFlex())
            self.add_depfileset(Spram())
            self.add_depfileset(Endpoint())


if __name__ == "__main__":
    d = MemAgent()
    d.write_fileset("umi_memagent.f", fileset="rtl")
