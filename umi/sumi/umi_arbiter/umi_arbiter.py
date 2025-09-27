from umi.common import UMI
from lambdalib.veclib import Vpriority

class Arbiter(UMI):
    def __init__(self):
        super().__init__('umi_arbiter',
                         files=['rtl/umi_arbiter.v'],
                         deps=[Vpriority()])


if __name__ == "__main__":
    d = Arbiter()
    d.write_fileset(f"{d.name}.f", fileset="rtl")
