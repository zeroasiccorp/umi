from umi.sumi.common import Sumi

class Pipeline(Sumi):
    def __init__(self):
        name = 'umi_pipeline'
        sources = 'rtl/umi_pipeline.v'
        super().__init__(name, sources)

if __name__ == "__main__":
    d = Pipeline()
    d.write_fileset("umi_pipeline.f", fileset="rtl")
