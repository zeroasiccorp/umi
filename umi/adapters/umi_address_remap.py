from umi.common import UMI


class AddressRemap(UMI):
    def __init__(self):
        super().__init__('umi_address_remap',
                         files=['rtl/umi_address_remap.v'],
                         idirs=['rtl'],
                         deps=[])


if __name__ == "__main__":
    d = AddressRemap()
    d.write_fileset(f"{d.name}.f", fileset="rtl")
