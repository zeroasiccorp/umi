from umi.common import UMI


class Checker(UMI):
    """The UMI verification IP: passive protocol checkers.

    One block, one fileset, growing by files -- never by folders:
      rtl/umi_handshake_checker.sv   README 4.2 ready/valid handshake
      rtl/umi_cmd_checker.sv         CMD-word (command field) legality
      rtl/umi_txn_checker.sv         request/response pairing + framing
      rtl/umi_frame_checker.sv       intra-message framing, one channel
    """
    def __init__(self):
        super().__init__('umi_checker',
                         files=['rtl/umi_handshake_checker.sv',
                                'rtl/umi_cmd_checker.sv',
                                'rtl/umi_txn_checker.sv',
                                'rtl/umi_frame_checker.sv'],
                         deps=[])
        # the block name is the family home, not a module. test_lint
        # elaborates this fileset under a single top, so point it at the
        # handshake checker; umi_cmd_checker and umi_txn_checker ship in
        # the same fileset and are elaborated as tops by the formal lane.
        with self.active_fileset('rtl'):
            self.set_topmodule('umi_handshake_checker')


if __name__ == "__main__":
    d = Checker()
    d.write_fileset(f"{d.name}.f", fileset="rtl")
