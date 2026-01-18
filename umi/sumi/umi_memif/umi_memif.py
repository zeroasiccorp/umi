from umi.common import UMI


class Memif(UMI):
    def __init__(self):
        super().__init__('umi_memif',
                         files=['rtl/umi_memif.v'],
                         deps=[])


if __name__ == "__main__":
    d = Memif()
    d.write_fileset(f"{d.name}.f", fileset="rtl")
