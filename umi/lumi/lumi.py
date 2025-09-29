from umi.common import UMI
from lambdalib.auxlib import Rsync
from lambdalib.auxlib import Dsync
from lambdalib.ramlib import Asyncfifo
from umi.sumi import FifoFlex
from umi.sumi import Crossbar
from umi.sumi import Regif
from umi.sumi import Mux


class LUMI(UMI):
    def __init__(self):
        super().__init__('lumi',
                         files=['rtl/lumi.v',
                                'rtl/lumi_crossbar.v',
                                'rtl/lumi_regs.v',
                                'rtl/lumi_tx.v',
                                'rtl/lumi_tx_ready.v',
                                'rtl/lumi_rx.v',
                                'rtl/lumi_rx_ready.v'],
                         idirs=['rtl'],
                         deps=[Mux(),
                               FifoFlex(),
                               Crossbar(),
                               Regif(),
                               Asyncfifo(),
                               Rsync(),
                               Dsync()])


if __name__ == "__main__":
    d = LUMI()
    d.write_fileset(f"{d.name}.f", fileset="rtl")
