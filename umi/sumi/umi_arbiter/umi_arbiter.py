from umi.sumi.common import Sumi


class Arbiter(Sumi):
    def __init__(self):
        name = 'umi_arbiter'
        sources = 'rtl/umi_arbiter.v'
        super().__init__(name, sources)


if __name__ == "__main__":
    d = Arbiter()
    d.write_fileset("umi_arbiter.f", fileset="rtl")
