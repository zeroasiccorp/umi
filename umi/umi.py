import siliconcompiler
import os

########################
# SiliconCompiler Setup
########################

def setup(target=None):
    '''UMI library setup'''

    # Create chip object
    chip = siliconcompiler.Chip('umi')

    # Project sources
    root = os.path.dirname(__file__)
    chip.add('option', 'ydir', f"{root}/rtl")
    chip.add('option', 'idir', f"{root}/rtl")
    chip.add('option', 'ydir', f"sumi/rtl")
    chip.add('option', 'idir', f"sumi/rtl")
    chip.add('option', 'ydir', f"umi/rtl")
    chip.add('option', 'idir', f"umi/rtl")

    return chip
