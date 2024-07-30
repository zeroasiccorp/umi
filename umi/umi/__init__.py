from siliconcompiler import Library
from lambdalib import auxlib, ramlib, vectorlib


def setup(chip):
    lib = Library(chip, "umi", package="umi", auto_enable=True)
    lib.register_source("umi", "python://umi")

    lib.add("option", "idir", "umi/rtl")
    lib.add("option", "ydir", "umi/rtl")

    lib.add("option", "idir", "utils/rtl")
    lib.add("option", "ydir", "utils/rtl")

    lib.use(auxlib)
    lib.use(ramlib)
    lib.use(vectorlib)

    return lib
