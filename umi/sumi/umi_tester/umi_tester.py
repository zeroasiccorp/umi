from umi.common import UMI
from lambdalib.ramlib import Spram


class Tester(UMI):
    def __init__(self):
        super().__init__('umi_tester',
                         files=['rtl/umi_tester.v'],
                         deps=[Spram()])


if __name__ == "__main__":
    d = Tester()
    d.write_fileset(f"{d.name}.f", fileset="rtl")
