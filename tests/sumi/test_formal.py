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

# sby drives yosys; the green tasks run the boolector engine, which is
# always present in the sc_tools CI container. z3 and bitwuzla are extra
# solvers used only for the local dual-solver evidence and are skipped
# per-row (see below) when the solver is not on PATH.
_TOOLS = ("sby", "yosys", "boolector")
# the prove_z3 rows need z3 and the two fv_umi_txn *_bw rows need
# bitwuzla; skip just those rows when the solver is absent so the rest of
# the lane still runs on boolector alone
_HAVE_BITWUZLA = shutil.which("bitwuzla") is not None
_needs_bitwuzla = pytest.mark.skipif(not _HAVE_BITWUZLA,
                                     reason="bitwuzla not on PATH")
_HAVE_Z3 = shutil.which("z3") is not None
_needs_z3 = pytest.mark.skipif(not _HAVE_Z3,
                               reason="z3 not on PATH")

pytestmark = [
    pytest.mark.formal,
    pytest.mark.skipif(any(shutil.which(t) is None for t in _TOOLS),
                       reason="formal toolchain (sby/yosys/boolector) "
                              "not on PATH"),
]

GREEN_TASKS = [
    ("fv_umi_codec", "prove"),
    pytest.param("fv_umi_codec", "prove_z3", marks=_needs_z3),
    ("fv_umi_codec", "cover"),
    ("fv_umi_buffer", "prove"),
    pytest.param("fv_umi_buffer", "prove_z3", marks=_needs_z3),
    ("fv_umi_buffer", "bypass"),
    ("fv_umi_buffer", "cover"),
    ("fv_umi_buffer", "rule5"),
    ("fv_umi_buffer", "prove_mask_off"),
    ("fv_umi_cmd", "prove"),
    pytest.param("fv_umi_cmd", "prove_z3", marks=_needs_z3),
    ("fv_umi_cmd", "prove_dw64"),
    ("fv_umi_cmd", "cover"),
    ("fv_umi_cmd", "cover_sa"),
    ("fv_umi_cmd", "cover_invalid"),
    ("fv_umi_cmd", "prove_mask_off"),
    ("fv_umi_txn", "prove"),
    pytest.param("fv_umi_txn", "prove_bw", marks=_needs_bitwuzla),
    ("fv_umi_txn", "prove_deep"),
    pytest.param("fv_umi_txn", "prove_deep_bw", marks=_needs_bitwuzla),
    ("fv_umi_txn", "cover"),
    ("fv_umi_txn", "cover_boundary"),
    ("fv_umi_txn", "prove_mask_off"),
    ("fv_umi_demux", "prove"),
    pytest.param("fv_umi_demux", "prove_z3", marks=_needs_z3),
    ("fv_umi_demux", "prove_m4"),
    ("fv_umi_demux", "cover"),
    ("fv_umi_demux", "rule5"),
    ("fv_umi_demux", "hazard"),
    ("fv_umi_arbiter", "prove"),
    pytest.param("fv_umi_arbiter", "prove_z3", marks=_needs_z3),
    ("fv_umi_arbiter", "prove_n2"),
    ("fv_umi_arbiter", "prio"),
    ("fv_umi_arbiter", "cover"),
    ("fv_umi_arbiter", "rotate"),
]

FAULT_TASKS = [
    ("fv_umi_codec", "fault_eom"),
    ("fv_umi_buffer", "fault_valid"),
    ("fv_umi_buffer", "fault_data"),
    ("fv_umi_buffer", "fault_rule5"),
    ("fv_umi_cmd", "fault_opcode"),
    ("fv_umi_cmd", "fault_atype"),
    ("fv_umi_cmd", "fault_align_da"),
    ("fv_umi_cmd", "fault_align_sa"),
    ("fv_umi_cmd", "fault_fullbyte"),
    ("fv_umi_cmd", "fault_ex"),
    ("fv_umi_cmd", "fault_errsize"),
    ("fv_umi_cmd", "fault_cap"),
    ("fv_umi_cmd", "fault_respdata"),
    ("fv_umi_cmd", "fault_sa_reserved"),
    ("fv_umi_cmd", "fault_invalid"),
    ("fv_umi_txn", "fault_wrongda"),
    ("fv_umi_txn", "fault_size"),
    ("fv_umi_txn", "fault_eom_early"),
    ("fv_umi_txn", "fault_eom_missing"),
    ("fv_umi_txn", "fault_msgbytes"),
    ("fv_umi_txn", "fault_err_len"),
    ("fv_umi_txn", "fault_orphan"),
    ("fv_umi_txn", "fault_occ"),
    ("fv_umi_demux", "fault_valid"),
    ("fv_umi_demux", "fault_bcast"),
    ("fv_umi_demux", "fault_drop"),
    ("fv_umi_demux", "fault_dup"),
    ("fv_umi_demux", "fault_r5"),
    ("fv_umi_demux", "fault_rule5"),
    ("fv_umi_arbiter", "fault_onehot"),
    ("fv_umi_arbiter", "fault_subset"),
    ("fv_umi_arbiter", "fault_mask"),
]


def _sby(proof, task):
    # sby resolves [files] against its working directory, so run from
    # the proof's own directory (same as running it by hand)
    return subprocess.run(
        ["sby", "-f", f"{proof}.sby", task],
        cwd=FORMAL_SUMI, capture_output=True, text=True, timeout=600)


def _tid(entry):
    # entry is a (proof, task) tuple or a pytest.param wrapping the same
    # two values; render the shared "proof:task" id either way
    proof, task = getattr(entry, "values", entry)
    return f"{proof}:{task}"


@pytest.mark.parametrize("proof,task", GREEN_TASKS,
                         ids=[_tid(e) for e in GREEN_TASKS])
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
