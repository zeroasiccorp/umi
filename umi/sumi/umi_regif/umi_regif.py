from umi.sumi.common import Sumi


class Regif(Sumi):
    def __init__(self):
        name = 'umi_regif'
        sources = 'rtl/umi_regif.v'
        super().__init__(name, sources)


if __name__ == "__main__":
    d = Regif()
    d.write_fileset("umi_regif.f", fileset="rtl")
