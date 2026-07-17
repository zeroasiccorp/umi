from umi.common import UMI


class Checker(UMI):
    """The UMI verification IP: passive protocol checkers.

    One block, one fileset, growing by files -- never by folders:
      rtl/umi_handshake_checker.sv   README 4.2 ready/valid handshake
      (future: umi_cmd_checker.sv    CMD-field legality;
               umi_txn_checker.sv    request/response pairing)
    """
    def __init__(self):
        super().__init__('umi_checker',
                         files=['rtl/umi_handshake_checker.sv'],
                         deps=[])
        # the block name is the family home, not a module: point the
        # lint top at the (sole, for now) checker module
        with self.active_fileset('rtl'):
            self.set_topmodule('umi_handshake_checker')


if __name__ == "__main__":
    d = Checker()
    d.write_fileset(f"{d.name}.f", fileset="rtl")
