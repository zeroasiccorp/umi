from umi.sumi.common import Sumi

class RAM(Sumi):
    def __init__(self):
        name = 'umi_ram'
        sources = 'rtl/umi_ram.v'
        super().__init__(name, sources)

if __name__ == "__main__":
    d = RAM()
    d.write_fileset("umi_ram.f", fileset="rtl")
