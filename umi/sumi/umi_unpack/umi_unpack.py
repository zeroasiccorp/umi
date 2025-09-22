from umi.sumi.sumi import Sumi

class Unpack(Sumi):
    def __init__(self):
        name = 'umi_unpack'
        sources = 'rtl/umi_unpack.v'
        super().__init__(name, sources)

if __name__ == "__main__":
    d = Unpack()
    d.write_fileset("umi_unpack.f", fileset="rtl")
