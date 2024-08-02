from umi import sumi, lumi


__version__ = "0.1.3"


def setup(chip):
    return [
        sumi.setup(chip),
        lumi.setup(chip)
    ]
