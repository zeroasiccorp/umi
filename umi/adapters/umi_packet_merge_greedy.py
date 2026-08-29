from umi.common import UMI
from umi.sumi import Decode, Pack, Unpack


class PacketMergeGreedy(UMI):
    """Greedy packet merge, IDW in to ODW out.

    NOT re-exported from umi.adapters, so the parametrized lint in
    tests/test_lint.py does not reach it. The block does not elaborate
    under slang: umi_packet_merge_greedy.v:158 reads
    umi_in_mergeable_r and umi_in_bytes_r, which are declared at
    :240-241. Verilog tolerates that in some tools; slang, and so this
    repo's own lint gate, does not.

    Exporting it as-is would turn the lint suite red. Moving the two
    declarations above their first use is a behaviour-neutral fix and
    would let the export happen, but that is an RTL change and belongs
    with whoever owns the block.
    """
    def __init__(self):
        super().__init__('umi_packet_merge_greedy',
                         files=['rtl/umi_packet_merge_greedy.v'],
                         idirs=['rtl'],
                         deps=[Decode(),
                               Pack(),
                               Unpack()])


if __name__ == "__main__":
    d = PacketMergeGreedy()
    d.write_fileset(f"{d.name}.f", fileset="rtl")
