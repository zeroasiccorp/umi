import pytest
import siliconcompiler as sc
from siliconcompiler.flows import lintflow
import umi


def lint(design):
    top = design.get_topmodule("rtl")
    if isinstance(top, str) and top:
        proj = sc.LintProject(design)
        proj.add_fileset("rtl")
        proj.set_flow(lintflow.LintFlow())
        return proj.run()
    else:
        return True


@pytest.mark.parametrize("name", umi.sumi.__all__)
def test_lint_sumi(name):
    assert lint(getattr(umi.sumi, name)())


@pytest.mark.parametrize("name", umi.adapters.__all__)
def test_lint_adapters(name):
    assert lint(getattr(umi.adapters, name)())
