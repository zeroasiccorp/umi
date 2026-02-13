from umi.common import UMI


class Buffer(UMI):
    def __init__(self):
        super().__init__('umi_buffer',
                         files=['rtl/umi_buffer.v'],
                         deps=[])


if __name__ == "__main__":
    d = Buffer()
    d.write_fileset(f"{d.name}.f", fileset="rtl")
