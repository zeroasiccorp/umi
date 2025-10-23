from umi.common import UMI

class Arbiter(UMI):
    def __init__(self):
        super().__init__('umi_arbiter',
                         files=['rtl/umi_arbiter.v'],
                         deps=[])


if __name__ == "__main__":
    d = Arbiter()
    d.write_fileset(f"{d.name}.f", fileset="rtl")
