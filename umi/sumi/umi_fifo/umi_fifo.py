from umi.sumi.common import Sumi

class Fifo(Sumi):
    def __init__(self):
        name = 'umi_fifo'
        sources = 'rtl/umi_fifo.v'
        super().__init__(name, sources)

if __name__ == "__main__":
    d = Fifo()
    d.write_fileset("umi_fifo.f", fileset="rtl")
