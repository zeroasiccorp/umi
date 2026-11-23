from umi.common import UMI


class Exclusive(UMI):
    def __init__(self):
        super().__init__('umi_exclusive',
                         files=['rtl/umi_exclusive.v'],
                         deps=[])


if __name__ == "__main__":
    d = Exclusive()
    d.write_fileset(f"{d.name}.f", fileset="rtl")
