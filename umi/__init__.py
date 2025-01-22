from umi import sumi, lumi


__version__ = "0.2.0"


def setup():
    return [
        sumi.setup(),
        lumi.setup()
    ]
