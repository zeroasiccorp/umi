from umi.sumi.common import Sumi


class FifoFlex(Sumi):
    def __init__(self):
        name = 'umi_fifoflex'
        sources = 'rtl/umi_fifoflex.v'
        super().__init__(name, sources)


if __name__ == "__main__":
    d = FifoFlex()
    d.write_fileset("umi_fifoflex.f", fileset="rtl")
