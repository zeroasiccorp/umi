from umi.sumi.common import Sumi
from umi.sumi.umi_mux.umi_mux import Mux


class Switch(Sumi):
    def __init__(self):
        name = 'umi_switch'
        sources = 'rtl/umi_switch.v'
        super().__init__(name, sources)
        with self.active_fileset('rtl'):
            self.add_depfileset(Mux())


if __name__ == "__main__":
    d = Switch()
    d.write_fileset("umi_switch.f", fileset="rtl")
