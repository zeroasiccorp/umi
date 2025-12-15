from umi.common import UMI


class Demux(UMI):
    def __init__(self):
        super().__init__('umi_demux',
                         files=['rtl/umi_demux.v'])


if __name__ == "__main__":
    d = Demux()
    d.write_fileset(f"{d.name}.f", fileset="rtl")
