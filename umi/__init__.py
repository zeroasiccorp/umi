from umi import sumi, lumi


__version__ = "0.1.4"


def setup():
    return [
        sumi.setup(),
        lumi.setup()
    ]
