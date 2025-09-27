from umi.common import UMI
from umi.sumi.umi_mux.umi_mux import Mux


class Switch(UMI):
    def __init__(self):
        super().__init__('umi_switch',
                         files=['rtl/umi_switch.v'],
                         deps=[Mux()])


if __name__ == "__main__":
    d = Switch()
    d.write_fileset(f"{d.name}.f", fileset="rtl")
