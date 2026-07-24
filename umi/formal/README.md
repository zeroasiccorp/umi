# Formal property proofs

Machine-checked proofs of UMI spec properties against the RTL in this
repo, run with [SymbiYosys](https://symbiyosys.readthedocs.io)
(yosys + SMT solvers).

Each proof is two files. No generators, no copied RTL:

    <layer>/fv_<name>.sv     harness: instantiates the shipped RTL,
                             constrains inputs, states the properties
    <layer>/fv_<name>.sby    the sby job, one task per question

`[files]` paths reference the RTL in place. Shared property modules
(the checkers themselves) are normal blocks under `umi/sumi/`, e.g.
`umi/sumi/umi_checker/`. The directories sby creates during a run
(`fv_*_<task>/`) are build products: gitignored, never committed.

## Run

    # the whole lane (ordinary tasks must pass, fault_* tasks must fail)
    pytest -m formal tests/sumi/test_formal.py

    # one task by hand, from the proof's directory
    cd umi/formal/sumi && sby -f fv_umi_codec.sby prove

SiliconCompiler's sby flow can generate these jobs from the filesets;
planned as the CI lane once its formal API stabilizes (currently
engine-locked to boolector).

## Tools

`sby`, `yosys`, `boolector`, and `z3` on PATH. Easiest source is the
[OSS CAD Suite](https://github.com/YosysHQ/oss-cad-suite-build/releases):

    source <extracted>/oss-cad-suite/environment

Plus the repo's python environment for the pytest lane; the test-tree
conftests import switchboard/cocotb, so collection fails without it:

    python3 -m venv .venv
    source .venv/bin/activate
    pip install -e .[test]

Without the tools on PATH the formal tests skip; they never break
other CI lanes.

## Conventions

* Tasks named `fault_*` inject a bug and must FAIL; all other tasks
  must PASS. The pytest lane enforces both directions (a fault task
  that passes is reported as the error it is).
* `prove` tasks are k-induction: a PASS is unbounded, not a bounded
  search. Every `cover` witness must be REACHED, or the environment
  is over-constrained.
* `prove` runs boolector, `prove_z3` runs z3; both must pass.

## Adding a proof

1. Add `fv_<name>.sv` + `fv_<name>.sby` under the layer directory,
   with at least one `fault_*` task and covers for assumed corners.
2. Add its tasks to the lists in `tests/sumi/test_formal.py`.

## Proofs

| proof | property module | claim | green tasks | fault tasks |
|---|---|---|---|---|
| `sumi/fv_umi_codec` | (umi_pack / umi_unpack) | CMD codec round-trips over the 13 structured opcodes | prove, prove_z3, cover | fault_eom |
| `sumi/fv_umi_buffer` | `umi_checker/rtl/umi_handshake_checker.sv` | umi_buffer obeys the README 4.2 ready/valid handshake | prove, prove_z3, bypass, cover | fault_valid, fault_data |
| `sumi/fv_umi_cmd` | `umi_checker/rtl/umi_cmd_checker.sv` | CMD-word legality: the assume face (legal-traffic generator) and assert face of the checker agree, at DW=256 and DW=64, and every legal opcode plus a full-capacity beat is reachable | prove, prove_z3, prove_dw64, cover, cover_sa | fault_opcode, fault_atype, fault_align_da, fault_align_sa, fault_fullbyte, fault_ex, fault_errsize, fault_cap, fault_respdata, fault_sa_reserved |
| `sumi/fv_umi_txn` | `umi_checker/rtl/umi_txn_checker.sv` | response-side transaction / framing: against a perfect in-order responder every response beat pairs with its request (kind/field-copy), the split-response DA follows the continuation law, EOM lands exactly on the closing beat, an error reply is one length-echoing beat, and the FRM-4 per-message byte total and the outstanding-request tracker stay bounded | prove, prove_bw, prove_deep, prove_deep_bw, cover, cover_boundary | fault_wrongda, fault_size, fault_eom_early, fault_eom_missing, fault_msgbytes, fault_err_len, fault_orphan, fault_occ |

`fv_umi_cmd` checks one rule per fault task (the label each must trip
is tabulated in `fv_umi_cmd.sby`); `cover_sa` and `fault_sa_reserved`
run with the opt-in strict profile `CHECK_SA_RESERVED=1` (request SA
reserved bits zero), which defaults off because the repo's own
reference traffic uses the high SA bytes as routing/control bits.

`fv_umi_txn` is a stateful, response-side (L2) proof and carries three
scope notes. **Framing depth.** The split-response framing rules are
proven by k-induction over messages of bounded length: `prove` /
`prove_bw` run the fast **MAXLEN=1** regression (short messages -- up
to two beats, one continuation), which already exercises the
continuation-address, mid-message ERR/EOF stability, and
EOM-exactly-on-close rules, and `prove_deep` / `prove_deep_bw` raise the
harness request-LEN ceiling to **MAXLEN=3**, extending the frame depth
to four beats. A PASS at each depth is unbounded (induction, not
bounded search); the harness glue lemmas
(`a_glue_*`, the checker tracker == responder queue equality) are
ASSERTED, not assumed. **No interleave.** The proof holds under the
single-link, un-interleaved operating condition documented in the
checker header: one point-to-point link, responses in request order, so
the checker's in-order shadow FIFO matches the responder queue
entry-for-entry. Bind the checker BEFORE any response mux; per-key
(HOSTID / bridge-specific) folding downstream of a merge is deferred.
**Harness width.** The harness runs at **DW=64** (the checker ships
DW=256) to keep the SMT problem tractable; DW is a data-path width the
framing rules are agnostic to. **Solver note.** `prove` / `prove_deep`
use **boolector** (the primary unbounded engine); `prove_bw` /
`prove_deep_bw` run the same proof under **bitwuzla**, which closes the
txn induction in seconds where z3 does not within a reasonable budget --
the same bitwuzla-alongside-boolector precedent used elsewhere in this
lane. A fault task may falsify several related rules on the same
beat and the reported label can be solver-dependent; the intended
label for each is tabulated in `fv_umi_txn.sby`. `cover_boundary` (chparam
`MAX_MSG_BYTES=256`) witnesses the FRM-4 byte accumulator reaching
exactly its ceiling.
