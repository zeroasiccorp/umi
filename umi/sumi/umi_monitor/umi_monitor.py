from umi.common import UMI


class Monitor(UMI):
    def __init__(self):
        super().__init__('umi_monitor',
                         files=['rtl/umi_monitor.v'],
                         idirs=[])


if __name__ == "__main__":
    d = Monitor()
    d.write_fileset(f"{d.name}.f", fileset="rtl")
