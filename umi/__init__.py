from siliconcompiler import Library
import lambdalib


__version__ = "0.1.1"


def _register_umi(lib):
    lib.register_source("umi", "python://umi")


def setup(chip):
    libs = []

    for name in ('umi', 'lumi'):
        lib = Library(chip, name, package="umi")
        _register_umi(lib)
        lib.use(lambdalib)

        lib.add("option", "idir", f"{name}/rtl")
        lib.add("option", "ydir", f"{name}/rtl")

        lib.add("option", "idir", "utils/rtl")
        lib.add("option", "ydir", "utils/rtl")

        libs.append(lib)

    return libs
