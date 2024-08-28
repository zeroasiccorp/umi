from umi import sumi, lumi


__version__ = "0.1.3"


def setup():
    return [
        sumi.setup(),
        lumi.setup()
    ]
