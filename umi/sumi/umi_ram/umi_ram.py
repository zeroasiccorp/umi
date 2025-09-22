from umi.sumi.common import Sumi
from umi.sumi.umi_mux.umi_mux import Mux
from umi.sumi.umi_memagent.umi_memagent import MemAgent


class RAM(Sumi):
    def __init__(self):
        name = 'umi_ram'
        sources = 'rtl/umi_ram.v'
        super().__init__(name, sources)
        with self.active_fileset('rtl'):
            self.add_depfileset(Mux())
            self.add_depfileset(MemAgent())


if __name__ == "__main__":
    d = RAM()
    d.write_fileset("umi_ram.f", fileset="rtl")
