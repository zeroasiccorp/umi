from siliconcompiler import Library
from umi import sumi
from lambdalib import auxlib, ramlib


def setup(chip):
    lib = Library(chip, "lumi", package="umi", auto_enable=True)
    lib.register_source("umi", "python://umi")

    lib.add("option", "idir", "lumi/rtl")
    lib.add("option", "ydir", "lumi/rtl")

    lib.add("option", "idir", "utils/rtl")
    lib.add("option", "ydir", "utils/rtl")

    lib.use(sumi)

    lib.use(auxlib)
    lib.use(ramlib)

    return lib
