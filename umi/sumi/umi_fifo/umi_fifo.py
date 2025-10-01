from umi.common import UMI
from lambdalib.ramlib import Asyncfifo


class Fifo(UMI):
    def __init__(self):
        super().__init__('umi_fifo',
                         files=['rtl/umi_fifo.v'],
                         deps=[Asyncfifo()])


if __name__ == "__main__":
    d = Fifo()
    d.write_fileset(f"{d.name}.f", fileset="rtl")
