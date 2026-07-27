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

Two pytest entry points, both under the `formal` marker:

    # the .sby lane: the full dual-solver matrix, every .sby task
    # (ordinary tasks must pass, fault_* tasks must fail)
    pytest -m formal tests/sumi/test_formal.py

    # the SiliconCompiler lane: the same proofs launched as
    # PropertyCheckFlow runs -- the sby jobs are GENERATED from the
    # repo's own Design filesets (harness on top, DUT and checker
    # blocks as depfilesets; include dirs, defines and params ride in
    # from the Design objects)
    pytest -m formal tests/sumi/test_formal_sc.py

    # one task by hand, from the proof's directory
    cd umi/formal/sumi && sby -f fv_umi_codec.sby prove

CI runs both entry points in the "Formal CI" job
(`.github/workflows/ci.yml`) inside SiliconCompiler's `sc_tools`
container (`ghcr.io/siliconcompiler/sc_tools:latest`, the same image the
Python CI lane uses). That image ships yosys, sby and boolector -- the
released SiliconCompiler 0.38.x engine -- and the job runs
`pytest -m "formal" --durations=0`. The formal lane runs the proofs
serially -- sby keeps a per-proof status database that is not safe to
share across the concurrent tasks of one proof, so this lane does not
add pytest-xdist (`-n`) here; the full set still finishes in a few
minutes. One solver is
all CI needs to gate the proofs; z3 and bitwuzla are the local dual-solver
evidence (see Engines), are absent from the container, and so their
rows skip cleanly there. Without the tools the formal tests skip, so no
other lane can be broken by this one.

Engines: CI and the SC lane run boolector, the engine siliconcompiler's
sby task offers in the released 0.38.x versions; bitwuzla engine support
is already merged in siliconcompiler main, so the SC lane gains a second
engine on the next release. z3 and bitwuzla are used only in the local
`.sby` lane as independent-solver evidence (z3 and bitwuzla
alongside boolector); where those solvers are absent -- notably the CI
container -- their rows skip cleanly and boolector alone gates the lane.

## Tools

`sby`, `yosys`, and `boolector` on PATH (add `z3` and `bitwuzla` for the
full local dual-solver matrix; their rows skip when absent). Easiest
source is the
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
* `prove` runs boolector and must pass; `prove_z3` runs the same proof
  under z3 where z3 is on PATH and skips otherwise (local evidence only).

## Adding a proof

1. Add `fv_<name>.sv` + `fv_<name>.sby` under the layer directory,
   with at least one `fault_*` task and covers for assumed corners.
2. Add its tasks to the lists in `tests/sumi/test_formal.py`.
3. Add a family entry (deps, depth, params) plus one green and one
   fault row in `tests/sumi/test_formal_sc.py` so the proof also rides
   the SiliconCompiler lane.

## Proofs

| proof | property module | claim | green tasks | fault tasks |
|---|---|---|---|---|
| `sumi/fv_umi_demux` | `umi_checker/rtl/umi_handshake_checker.sv` | routing and fork laws for the combinational demux, with EVERY output channel asserted legal SUMI by the handshake checker: an output is valid exactly when the input is valid and that output is selected, an unselected output is quiet, each output carries the input beat verbatim, and one accepted beat yields exactly one delivery (fork conservation). Rule 4.2.5 in two forms -- a stuck-low-READY cover and a self-composition miter proving `in_ready` is independent of `in_valid`. The `hazard` task drops the onehot-select assumption and witnesses the fork hazards (`select==0` accepts and drops; multi-hot duplicates) | prove, prove_z3, prove_m4, cover, rule5, hazard | fault_valid, fault_bcast, fault_drop, fault_dup, fault_r5, fault_rule5 |
| `sumi/fv_umi_codec` | (umi_pack / umi_unpack) | CMD codec round-trips over the 13 structured opcodes | prove, prove_z3, cover | fault_eom |
| `sumi/fv_umi_buffer` | `umi_checker/rtl/umi_handshake_checker.sv` | umi_buffer obeys the README 4.2 ready/valid handshake, including rule 5 (VALID must not wait for READY) | prove, prove_z3, bypass, cover, rule5 | fault_valid, fault_data, fault_rule5 |
| `sumi/fv_umi_cmd` | `umi_checker/rtl/umi_cmd_checker.sv` | CMD-word legality: the assume face (legal-traffic generator) and assert face of the checker agree, at DW=256 and DW=64, and every legal opcode plus a full-capacity beat is reachable | prove, prove_z3, prove_dw64, cover, cover_sa | fault_opcode, fault_atype, fault_align_da, fault_align_sa, fault_fullbyte, fault_ex, fault_errsize, fault_cap, fault_respdata, fault_sa_reserved |
| `sumi/fv_umi_txn` | `umi_checker/rtl/umi_txn_checker.sv` | response-side transaction / framing: against a perfect in-order responder every response beat pairs with its request (kind/field-copy), the split-response DA follows the continuation law, EOM lands exactly on the closing beat, an error reply is one length-echoing beat, and the FRM-4 per-message byte total and the outstanding-request tracker stay bounded | prove, prove_bw, prove_deep, prove_deep_bw, cover, cover_boundary | fault_wrongda, fault_size, fault_eom_early, fault_eom_missing, fault_msgbytes, fault_err_len, fault_orphan, fault_occ |

`fv_umi_buffer` additionally answers README section 4.2 rule 5
(README.md:462): *"The assertion of VALID must not depend on the
assertion of READY. In other words, it is not legal for the VALID
assertion to wait for the READY assertion."* This is a structural rule
a cycle-sampled bind-in monitor can not assert (the handshake checker's
header says so); the complete method is
harness-level, on the DUT being proven, in three parts. `rule5` (cover)
assumes out_ready stuck low for the entire trace (`FV_RULE5_READYLOW`),
keeps the upstream driver legal, and reaches a cover of out_valid
asserting -- and holding -- anyway: VALID rises with zero help from
READY, the literal negation of the illegal behavior. `a_rule5_state`
rides the prove/prove_z3/bypass tasks as the state-driven face
(a full, data-holding buffer always asserts VALID, read out at the
ports as `!in_ready |-> out_valid`; in bypass `in_valid |-> out_valid`).
`fault_rule5` is the teeth: `FV_FAULT_RULE5` models the illegal design
where VALID waits for READY (`out_valid & out_ready`), under which the
stuck-low cover can never be reached, so the task FAILs. The handshake
checker also carries a free per-bind `c_rule5` reachability witness
(VALID fires while READY is low). Both rule5 tasks add `-DFV_NO_WITNESS`
so the checker's own transaction covers -- unreachable under stuck-low
ready -- do not spuriously fail the cover task.

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
