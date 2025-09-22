from umi.sumi.common import Sumi

class Mux2(Sumi):
    def __init__(self):
        name = 'umi_mux2'
        sources = 'rtl/umi_mux2.v'
        super().__init__(name, sources)

if __name__ == "__main__":
    d = Mux2()
    d.write_fileset("umi_mux2.f", fileset="rtl")
