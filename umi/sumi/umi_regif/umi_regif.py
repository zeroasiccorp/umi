from umi.common import UMI


class Regif(UMI):
    def __init__(self):
        super().__init__(topmodule='umi_regif',
                         files=['rtl/umi_regif.v'],
                         deps=[])


if __name__ == "__main__":
    d = Regif()
    d.write_fileset(f"{d.name}.f", fileset="rtl")
