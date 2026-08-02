"""Formal property proofs as SiliconCompiler flows (the SC lane).

The same proofs as tests/sumi/test_formal.py (the .sby task matrix),
launched here through siliconcompiler's PropertyCheckFlow.
Each proof family is a Design: the harness fv_<name>.sv on top, the
DUT and property blocks (Buffer, Checker, Pack, Unpack) pulled in as
depfilesets -- so the sby job is GENERATED from the same fileset graph
the rest of the repo builds from. Include dirs, defines and top-level
params ride in from the Design objects; sources are read in place.

Green rows must prove/cover clean: project.run() completes and the sby
errors metric is 0. fault_* rows inject a bug via a define and must
FAIL on a counterexample: run() raises naming the bmc node AND sby's
own verdict is FAIL (a tool/setup ERROR stays red here too).

Engine note: this lane runs boolector, the engine the sby task offers
in the siliconcompiler 0.38.x releases; bitwuzla support is already
merged in siliconcompiler main, so this lane gains a second engine on
the next release. Until then the .sby lane (test_formal.py) remains
the dual-solver evidence (z3 / bitwuzla alongside boolector).

Skips cleanly when sby/yosys/boolector or the SC formal flow are
missing, so other CI lanes are unaffected.
"""
import shutil
from pathlib import Path

import pytest

try:
    from siliconcompiler import Design, Project
    from siliconcompiler.flows.formalflow import PropertyCheckFlow, PropertyCheckMode
    from siliconcompiler.tools.sby import SBYTask
    _HAVE_SC_FORMAL = True
except ImportError:  # pragma: no cover -- pre-formal-flow siliconcompiler
    _HAVE_SC_FORMAL = False

from umi.sumi import Buffer, Checker, Mux, Pack, Unpack

REPO = Path(__file__).resolve().parents[2]
FORMAL_SUMI = REPO / "umi" / "formal" / "sumi"
SUMI_INCLUDE = REPO / "umi" / "sumi" / "include"

_TOOLS = ("sby", "yosys", "boolector")

pytestmark = [
    pytest.mark.formal,
    pytest.mark.skipif(any(shutil.which(t) is None for t in _TOOLS),
                       reason="formal toolchain (sby/yosys/boolector) "
                              "not on PATH"),
    pytest.mark.skipif(not _HAVE_SC_FORMAL,
                       reason="siliconcompiler PropertyCheckFlow/sby "
                              "not available"),
]

if _HAVE_SC_FORMAL:
    _MODES = {
        "prove": PropertyCheckMode.PROVE,
        "bmc": PropertyCheckMode.BMC,
        "cover": PropertyCheckMode.COVER,
    }

# One entry per proof family: the dependency blocks (DUT + property
# modules), top-level harness params, and the unrolling depth -- the
# same depths as the equivalent .sby tasks.
FAMILIES = {
    "fv_umi_codec": dict(deps=lambda: [Pack(), Unpack()],
                         depth=4, params=()),
    "fv_umi_buffer": dict(deps=lambda: [Buffer(), Checker()],
                          depth=12, params=()),
    # DW=64 (the hand lane's prove_dw64) keeps CI runtime down; the
    # DW=256 face and the per-rule fault matrix stay on the .sby lane
    "fv_umi_cmd": dict(deps=lambda: [Checker()],
                       depth=6, params=(("DW", "64"),)),
    # the fast MAXLEN=1 configuration (the hand lane's prove); the
    # MAXLEN=3 deep face stays on the .sby lane
    "fv_umi_txn": dict(deps=lambda: [Checker()],
                       depth=20, params=()),
    # umi_mux pulls in umi_arbiter and lambdalib's la_vmux, so it has no
    # checked-in .sby -- lambdalib resolves out of site-packages and a
    # job file cannot name that path portably. This lane assembles the
    # sources from Mux()'s own dependency graph instead.
    "fv_umi_mux": dict(deps=lambda: [Mux(), Checker()],
                       depth=12, params=()),
}

# (id, family, mode, defines) -- id names the equivalent .sby task
GREEN_RUNS = [
    ("codec:prove", "fv_umi_codec", "prove", ()),
    ("buffer:prove", "fv_umi_buffer", "prove", ()),
    # rule 4.2.5 witness (README.md section 4.2 rule 5): out_ready
    # ASSUMED stuck low, cover out_valid asserting-and-held anyway;
    # FV_NO_WITNESS drops the handshake checker's own transaction
    # covers, unreachable under stuck-low ready
    ("buffer:rule5", "fv_umi_buffer", "cover",
     ("FV_RULE5_READYLOW", "FV_NO_WITNESS")),
    ("cmd:prove_dw64", "fv_umi_cmd", "prove", ()),
    ("txn:prove", "fv_umi_txn", "prove", ()),
    # bounded, not prove: stalled_input is not port-observable while the
    # output is stalled, so the step case starts from states no trace
    # reaches. See the note in fv_umi_mux.sv.
    ("mux:bmc", "fv_umi_mux", "bmc", ()),
    ("mux:cover", "fv_umi_mux", "cover", ()),
]

# (id, family, defines) -- all run as bmc at the family depth
FAULT_RUNS = [
    ("codec:fault_eom", "fv_umi_codec", ("FV_FAULT_EOM",)),
    ("buffer:fault_valid", "fv_umi_buffer", ("FV_FAULT_VALID",)),
    # runs at the family's DW=64; the reserved-opcode fault (CMD1) is
    # width-independent
    ("cmd:fault_opcode", "fv_umi_cmd", ("FV_FAULT_OPCODE",)),
    ("txn:fault_orphan", "fv_umi_txn", ("FV_FAULT_ORPHAN",)),
    ("mux:fault_dup", "fv_umi_mux", ("FV_FAULT_DUP",)),
    ("mux:fault_teleport", "fv_umi_mux", ("FV_FAULT_TELEPORT",)),
    ("mux:fault_blend", "fv_umi_mux", ("FV_FAULT_BLEND",)),
]


def _harness(family, defines):
    """The proof-family Design: harness on top, repo blocks as deps."""
    spec = FAMILIES[family]
    design = Design(family)
    design.set_dataroot("umi_formal_sumi", str(FORMAL_SUMI))
    with design.active_fileset("rtl"):
        design.set_topmodule(family)
        design.add_file(f"{family}.sv")
        design.add_idir(str(SUMI_INCLUDE))
        for dep in spec["deps"]():
            design.add_depfileset(dep, "rtl")
        for define in defines:
            design.add_define(define)
        for name, value in spec["params"]:
            design.set_param(name, value)
    return design


def _project(design, mode, depth, builddir):
    proj = Project(design)
    proj.add_fileset("rtl")
    proj.set_flow(PropertyCheckFlow(f"formal_{mode}", modes=_MODES[mode]))
    proj.option.set_builddir(str(builddir))
    # gate on the proof, not the tool version string: OSS CAD Suite sby
    # builds answer --version with strings PEP-440 cannot parse (the
    # local build prints a bare "SBY")
    proj.option.set_novercheck(True)
    SBYTask.find_task(proj).set_sby_depth(depth)
    return proj


@pytest.mark.parametrize("tid,family,mode,defines", GREEN_RUNS,
                         ids=[r[0] for r in GREEN_RUNS])
def test_sc_proof(tid, family, mode, defines, tmp_path):
    proj = _project(_harness(family, defines), mode,
                    FAMILIES[family]["depth"], tmp_path)
    hist = proj.run()
    assert hist.get("metric", "errors", step=mode, index="0") == 0


@pytest.mark.parametrize("tid,family,defines", FAULT_RUNS,
                         ids=[r[0] for r in FAULT_RUNS])
def test_sc_fault_must_fail(tid, family, defines, tmp_path):
    """With the fault injected the bmc node must fail the run (the
    match pins the failure to the bmc node, not tool setup), and sby's
    own verdict must be FAIL -- a counterexample, not an ERROR."""
    proj = _project(_harness(family, defines), "bmc",
                    FAMILIES[family]["depth"], tmp_path)
    with pytest.raises(RuntimeError, match=r"bmc"):
        proj.run()
    status = (tmp_path / family / "job0" / "bmc" / "0" /
              "sby" / "status").read_text()
    assert status.startswith("FAIL"), status
