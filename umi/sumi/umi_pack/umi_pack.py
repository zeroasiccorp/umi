from umi.sumi.sumi import Sumi
from umi.sumi import Decode

class Pack(Sumi):
    def __init__(self):
        name = 'umi_pack'
        sources = 'rtl/umi_pack.v'
        super().__init__(name, sources)
        self.add_depfileset(Decode(), fileset='rtl')

if __name__ == "__main__":
    d = Pack()
    d.write_fileset("umi_pack.f", fileset="rtl")
