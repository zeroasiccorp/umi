from umi.common import UMI


class Unpack(UMI):
    def __init__(self):
        super().__init__('umi_unpack',
                         files=['rtl/umi_unpack.v'],
                         deps=[])


if __name__ == "__main__":
    d = Unpack()
    d.write_fileset(f"{d.name}.f", fileset="rtl")
