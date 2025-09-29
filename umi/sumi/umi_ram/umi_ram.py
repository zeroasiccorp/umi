from umi.common import UMI
from umi.sumi.umi_mux.umi_mux import Mux
from umi.sumi.umi_memagent.umi_memagent import MemAgent


class RAM(UMI):
    def __init__(self):
        super().__init__('umi_ram',
                         files=['rtl/umi_ram.v'],
                         deps=[Mux(),
                               MemAgent()])


if __name__ == "__main__":
    d = RAM()
    d.write_fileset(f"{d.name}.f", fileset="rtl")
