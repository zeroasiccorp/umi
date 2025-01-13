from siliconcompiler import Library
from lambdalib import auxlib, ramlib, vectorlib


def setup():
    lib = Library("sumi", package=("umi", "python://umi"), auto_enable=True)

    lib.add("option", "idir", "sumi/rtl")

    lib.input("sumi/rtl/umi_arbiter.v")
    lib.input("sumi/rtl/umi_crossbar.v")
    lib.input("sumi/rtl/umi_decode.v")
    lib.input("sumi/rtl/umi_demux.v")
    lib.input("sumi/rtl/umi_endpoint.v")
    lib.input("sumi/rtl/umi_fifo_flex.v")
    lib.input("sumi/rtl/umi_fifo.v")
    lib.input("sumi/rtl/umi_isolate.v")
    lib.input("sumi/rtl/umi_mem_agent.v")
    lib.input("sumi/rtl/umi_mux.v")
    lib.input("sumi/rtl/umi_pack.v")
    lib.input("sumi/rtl/umi_pipeline.v")
    lib.input("sumi/rtl/umi_priority.v")
    lib.input("sumi/rtl/umi_ram.v")
    lib.input("sumi/rtl/umi_regif.v")
    lib.input("sumi/rtl/umi_splitter.v")
    lib.input("sumi/rtl/umi_stimulus.v")
    lib.input("sumi/rtl/umi_switch.v")
    lib.input("sumi/rtl/umi_unpack.v")

    lib.add("option", "idir", "utils/rtl")

    lib.input("utils/rtl/axilite2umi.v")
    lib.input("utils/rtl/tl2umi_np.v")
    lib.input("utils/rtl/umi2apb.v")
    lib.input("utils/rtl/umi2axilite.v")
    lib.input("utils/rtl/umi2tl_np.v")
    lib.input("utils/rtl/umi_address_remap.v")
    lib.input("utils/rtl/umi_data_aggregator.v")
    lib.input("utils/rtl/umi_packet_merge_greedy.v")

    lib.use(auxlib)
    lib.use(ramlib)
    lib.use(vectorlib)

    return lib
