from umi import sumi, lumi


__version__ = "0.1.6"


def setup():
    return [
        sumi.setup(),
        lumi.setup()
    ]
