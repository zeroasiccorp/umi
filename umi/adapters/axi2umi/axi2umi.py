from umi.common import UMI
from umi.sumi import Pack, Mux, Demux


class AXI2UMI(UMI):
    def __init__(self):
        super().__init__(
            'axi2umi',
            files=[
                'rtl/axiwr2umi.v',
                'rtl/axird2umi.v',
                'rtl/axi2umi.v'
            ],
            idirs=['rtl'],
            deps=[
                Pack(),
                Mux(),
                Demux(),
            ]
        )


if __name__ == "__main__":
    d = AXI2UMI()
    d.write_fileset(f"{d.name}.f", fileset="rtl")
