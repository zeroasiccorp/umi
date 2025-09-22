from umi.sumi.common import Sumi

class Mux(Sumi):
    def __init__(self):
        name = 'umi_mux'
        sources = 'rtl/umi_mux.v'
        super().__init__(name, sources)

if __name__ == "__main__":
    d = Mux()
    d.write_fileset("umi_mux.f", fileset="rtl")
