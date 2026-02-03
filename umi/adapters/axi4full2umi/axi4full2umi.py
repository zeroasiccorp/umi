from umi.common import UMI
from umi.sumi import Pack


class AXIF2UMI(UMI):
    def __init__(self):
        super().__init__(
            'axi4_full_wr2umi',
            files=['rtl/axi4_full_wr2umi.v'],
            idirs=['rtl'],
            deps=[
                Pack(),
            ]
        )


if __name__ == "__main__":
    d = AXIF2UMI()
    d.write_fileset(f"{d.name}.f", fileset="rtl")
