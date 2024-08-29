from siliconcompiler import Library
from lambdalib import auxlib, ramlib, vectorlib


def setup():
    lib = Library("sumi", package=("umi", "python://umi"), auto_enable=True)

    lib.add("option", "idir", "sumi/rtl")
    lib.add("option", "ydir", "sumi/rtl")

    lib.add("option", "idir", "utils/rtl")
    lib.add("option", "ydir", "utils/rtl")

    lib.use(auxlib)
    lib.use(ramlib)
    lib.use(vectorlib)

    return lib
