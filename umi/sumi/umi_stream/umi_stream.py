from umi.common import UMI
from lambdalib.ramlib import Asyncfifo

class Stream(UMI):
    def __init__(self):
        super().__init__('umi_stream',
                         files=['rtl/umi_stream.v'],
                         deps=[Asyncfifo()])


if __name__ == "__main__":
    d = Stream()
    d.write_fileset(f"{d.name}.f", fileset="rtl")
