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

    return chip
