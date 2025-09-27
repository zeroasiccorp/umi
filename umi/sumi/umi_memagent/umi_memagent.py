from umi.common import UMI
from umi.sumi.umi_endpoint.umi_endpoint import Endpoint
from umi.sumi.umi_fifoflex.umi_fifoflex import FifoFlex
from lambdalib.ramlib import Spram

class MemAgent(UMI):
    def __init__(self):
        super().__init__('umi_memagent',
                         files=['rtl/umi_memagent.v'],
                         deps=[FifoFlex(),
                               Spram(),
                               Endpoint()])

if __name__ == "__main__":
    d = MemAgent()
    d.write_fileset(f"{d.name}.f", fileset="rtl")
