from umi import sumi, lumi


__version__ = "0.1.2"


def setup(chip):
    return [
        sumi.setup(chip),
        lumi.setup(chip)
    ]
