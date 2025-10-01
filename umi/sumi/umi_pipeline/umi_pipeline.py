from umi.common import UMI


class Pipeline(UMI):
    def __init__(self):
        super().__init__('umi_pipeline',
                         files=['rtl/umi_pipeline.v'],
                         deps=[])


if __name__ == "__main__":
    d = Pipeline()
    d.write_fileset(f"{d.name}.f", fileset="rtl")
