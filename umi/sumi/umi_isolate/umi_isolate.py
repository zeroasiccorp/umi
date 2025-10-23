from umi.common import UMI
import lambdalib as ll


class Isolate(UMI):
    def __init__(self):
        name = 'umi_isolate'
        super().__init__(name,
                         files=[f'rtl/{name}.v'],
                         deps=[ll.auxlib.Isolo()])


if __name__ == "__main__":
    d = Isolate()
    d.write_fileset(f"{d.name}.f", fileset="rtl")
