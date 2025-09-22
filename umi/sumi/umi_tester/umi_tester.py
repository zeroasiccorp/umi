from lambdalib.ramlib import Spram
from umi.sumi.common import Sumi


class Tester(Sumi):
    def __init__(self):
        name = 'umi_tester'
        sources = 'rtl/umi_tester.v'
        super().__init__(name, sources)
        with self.active_fileset('rtl'):
            self.add_depfileset(Spram())


if __name__ == "__main__":
    d = Tester()
    d.write_fileset("umi_tester.f", fileset="rtl")
