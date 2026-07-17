"""Formal property proofs (SymbiYosys) as a pytest lane.

Each proof under umi/formal/ is a harness (fv_<name>.sv) plus a job
file (fv_<name>.sby). This runner shells out to sby: ordinary tasks
must PASS, fault_* tasks inject a bug and must FAIL. Skips unless the
formal toolchain is on PATH, so other CI lanes are unaffected.
"""
import shutil
import subprocess
from pathlib import Path

import pytest

FORMAL_SUMI = Path(__file__).resolve().parents[2] / "umi" / "formal" / "sumi"

# sby drives yosys; the green tasks use the boolector and z3 engines
_TOOLS = ("sby", "yosys", "boolector", "z3")

pytestmark = [
    pytest.mark.formal,
    pytest.mark.skipif(any(shutil.which(t) is None for t in _TOOLS),
                       reason="formal toolchain (sby/yosys/boolector/z3) "
                              "not on PATH"),
]

GREEN_TASKS = [
    ("fv_umi_codec", "prove"),
    ("fv_umi_codec", "prove_z3"),
    ("fv_umi_codec", "cover"),
    ("fv_umi_buffer", "prove"),
    ("fv_umi_buffer", "prove_z3"),
    ("fv_umi_buffer", "bypass"),
    ("fv_umi_buffer", "cover"),
]

FAULT_TASKS = [
    ("fv_umi_codec", "fault_eom"),
    ("fv_umi_buffer", "fault_valid"),
    ("fv_umi_buffer", "fault_data"),
]


def _sby(proof, task):
    # sby resolves [files] against its working directory, so run from
    # the proof's own directory (same as running it by hand)
    return subprocess.run(
        ["sby", "-f", f"{proof}.sby", task],
        cwd=FORMAL_SUMI, capture_output=True, text=True, timeout=600)


@pytest.mark.parametrize("proof,task", GREEN_TASKS,
                         ids=[f"{p}:{t}" for p, t in GREEN_TASKS])
def test_proof(proof, task):
    r = _sby(proof, task)
    assert r.returncode == 0 and "DONE (PASS" in r.stdout, r.stdout[-800:]


@pytest.mark.parametrize("proof,task", FAULT_TASKS,
                         ids=[f"{p}:{t}" for p, t in FAULT_TASKS])
def test_fault_must_fail(proof, task):
    """Each proof's own regression: with the fault injected the proof
    must FAIL on an assertion. DONE (FAIL is a counterexample; anything
    else (ERROR, TIMEOUT) is a broken setup and stays red."""
    r = _sby(proof, task)
    assert r.returncode != 0 and "DONE (FAIL" in r.stdout, r.stdout[-800:]
