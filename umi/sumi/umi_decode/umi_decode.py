from umi.sumi.common import Sumi

class Decode(Sumi):
    def __init__(self):
        name = 'umi_decode'
        sources = 'rtl/umi_decode.v'
        super().__init__(name, sources)

if __name__ == "__main__":
    d = Decode()
    d.write_fileset("umi_decode.f", fileset="rtl")
