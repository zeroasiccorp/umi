from umi import umi, lumi


__version__ = "0.1.1"


def setup(chip):
    return [
        umi.setup(chip),
        lumi.setup(chip)
    ]
