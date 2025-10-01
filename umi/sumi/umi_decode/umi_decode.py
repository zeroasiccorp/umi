from umi.common import UMI


class Decode(UMI):
    def __init__(self):
        super().__init__('umi_decode',
                         files=['rtl/umi_decode.v'],
                         deps=[])


if __name__ == "__main__":
    d = Decode()
    d.write_fileset(f"{d.name}.f", fileset="rtl")
