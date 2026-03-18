import pytest
import siliconcompiler as sc
from siliconcompiler.flows import lintflow
import umi


_all_modules = [
    (mod, n)
    for mod in (umi.sumi, umi.adapters)
    for n in mod.__all__
]


@pytest.mark.parametrize("mod,name", _all_modules)
def test_slang_lint(mod, name):
    design =getattr(mod,name)()
    top = design.get_topmodule("rtl")
    proj = sc.Lint(design)
    proj.add_fileset("rtl")
    proj.set_flow(lintflow.LintFlow())
    assert proj.run()


@pytest.mark.eda
@pytest.mark.parametrize("mod,name", _all_modules)
def test_verilator_lint(mod, name):
    design =getattr(mod,name)()
    top = design.get_topmodule("rtl")
    proj = sc.Lint(design)
    proj.add_fileset("rtl")
    proj.set_flow(lintflow.LintFlow(tool="verilator"))
    assert proj.run()
