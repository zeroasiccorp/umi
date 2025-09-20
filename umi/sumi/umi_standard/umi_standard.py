from os.path import dirname, abspath
from siliconcompiler.design import Design

class Standard(Design):
    def __init__(self):

        name = 'standard'
        super().__init__(name)
        self.set_dataroot('root', dirname(abspath(__file__)))
        self.add_idir('include', fileset='rtl')

if __name__ == "__main__":
    d = Standard()
    d.write_fileset("standard.f", fileset="rtl")
