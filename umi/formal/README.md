# Formal property proofs

Machine-checked proofs of UMI spec properties against the RTL in this repo,
run with [SymbiYosys](https://symbiyosys.readthedocs.io) (yosys + solvers)
through siliconcompiler's `PropertyCheckFlow`.

Each proof is one file -- no generators, no copied RTL, no job file:

    <layer>/fv_<name>.sv     harness: instantiates the shipped RTL,
                             constrains inputs, states the properties

The sby job is generated from the repo's own `Design` filesets: the harness on
top, the DUT and the shared property modules pulled in as depfilesets. Include
dirs, defines and top-level parameters ride in from those `Design` objects, and
the RTL is read in place. The checkers are normal blocks under `umi/sumi/`,
e.g. `umi/sumi/umi_checker/`. A block that instantiates lambdalib needs no
special handling: site-packages paths are resolved at run time rather than
written down anywhere.

One row per question, named `<family>:<task>` -- `codec:prove`,
`buffer:identity`, `txn:fault_orphan`. The rows are the matrix in
`tests/sumi/test_formal_sc.py`.

Each harness header documents its own properties, scope, rows and fault
table. This file is the index; the detail lives next to the code.

## Run

    pytest -m formal tests/sumi/test_formal_sc.py

    # one row
    pytest -m formal tests/sumi/test_formal_sc.py -k 'buffer:identity'

To debug a proof under sby or yosys directly, run its row once with a pinned
build directory and reuse the job file it generated:

    pytest -m formal tests/sumi/test_formal_sc.py -k 'buffer:identity' \
           --basetemp=/tmp/formal
    sby -f /tmp/formal/*/fv_umi_buffer/job0/prove/0/sby/fv_umi_buffer.sby

Without `--basetemp` the job goes to a pytest temporary directory. The file
names every source by absolute path and emits no `[files]` section, so it
reruns exactly what the lane ran, and its `[script]` block pasted into `yosys`
elaborates the same design.

CI runs the lane in the "Formal CI" job (`.github/workflows/ci.yml`) inside
`ghcr.io/siliconcompiler/sc_tools:latest`. The full set takes a couple of
minutes.

### Reading a counterexample

The step sby names is one clock edge ahead of the VCD row that carries the
violating values. A `bmc` run that prints

    Checking assertions in step 5..
    BMC failed!
    Assert failed in fv_umi_buffer.chk_out: RULE2_valid_hold

has its evidence at `smt_step` **4** of `engine_0/trace.vcd`: that is the row
where the rule's enable is high and its condition is false, and in that trace
step 5 does not violate the rule at all. Every assertion here is an immediate
assertion inside `always @(posedge clk)`, so it is judged on the values the
edge samples, and the trace numbers the state the edge produces. Open the row
before the one the log names, or the waveform will not show the bug.

## Tools

`sby`, `yosys`, `yosys-abc` and `bitwuzla` on PATH -- easiest via the
[OSS CAD Suite](https://github.com/YosysHQ/oss-cad-suite-build/releases):

    source <extracted>/oss-cad-suite/environment

Plus the repo's python env (the test-tree conftests import
switchboard/cocotb, so collection fails without it):

    python3 -m venv .venv && source .venv/bin/activate && pip install -e .[test]

You need **both**: the python env alone collects the tests but every one
of them skips. If the whole lane reports `skipped`, `sby` is not on PATH.

The lane generates sby jobs from the Design filesets; it does not bundle a
solver.

## Engines

One SMT engine, `bitwuzla`, answers every row but three. The lane pins it
explicitly rather than inheriting the sby task's default, so a change upstream
cannot quietly move which solver these results rest on. bitwuzla is
boolector's maintained successor; boolector remains in the tool image and
swapping back is a one-line change.

The three exceptions are `buffer:identity`, `buffer:identity_bypass` and
`buffer:fault_swap_pdr`, which run `abc pdr`. That is not a preference:
k-induction cannot close payload identity at all -- see the scope note below --
and no SMT engine changes that. sby's name for that engine is outside the sby
task's engine enum, so the lane subclasses the prove task and rewrites the
generated job file's `[engines]` section.

Those rows also run with `aigsmt none`. abc reports a counterexample as an
AIGER output index rather than a named assertion; sby can translate it back by
replaying the witness through a second SMT solver, but that step needs a solver
beyond the four above and aborts on these harnesses with a witness signal
mismatch, which turns a real FAIL into a tool ERROR. With it off the engine's
own verdict is what sby reports, which is why `buffer:fault_swap_pdr` pins a
verdict and not a label -- `buffer:fault_swap` injects the same corruption
under `bmc` and pins the label there.

There is no independent-solver corroboration here: every SMT result is gated on
bitwuzla alone. Standing in its place is the fault matrix -- 54 rows that each
inject a bug and must each still produce a counterexample, which a solver
quietly answering "proved" to everything would not deliver. To re-check one
result against another solver, run its row, edit the `[engines]` line of the
job file it generated, and rerun that file by hand.

## Conventions

* `fault_*` rows inject a bug and **must FAIL**; every other row must PASS.
  The lane enforces both directions -- a fault row that passes is reported as
  the error it is, and a fault row that ERRORs rather than producing a
  counterexample stays red too.
* `prove` rows are **unbounded**, not a bounded search. Nearly all close by
  k-induction; `fv_umi_buffer`'s `identity` pair runs `abc pdr`, which is
  equally unbounded but derives its own invariant instead of being handed one
  at the ports. `bmc` rows are bounded, and are used where a proof would
  otherwise rest on DUT-internal state; the harness header says why in each
  case.
* Every `cover` witness must be REACHED, or the environment is over-constrained.
* **A `cover` row says nothing about the assertions in the same harness.** sby's
  cover mode does not evaluate them, so a cover row passes in configurations
  where the harness's own rules are false. `demux:hazard` is one: it drops the
  onehot-select assumption to witness the fork hazards, and under that
  environment `a_dx_fork_one` is genuinely violated -- run the same
  configuration in `bmc` mode and it fails on that label. The row is still
  doing its job, but read it as "these behaviours are reachable", never as
  "this configuration is legal".
* A fault may falsify several related rules at once, and which label the solver
  reports can vary. Each harness header names the intended label per fault row.
* Rule identifiers are stable names, not a contiguous sequence. A gap in the
  numbering means a candidate rule was considered and not adopted; every
  identifier that appears is defined by the checker that implements it.

## Proofs

| proof | judges | claim | green | fault |
|---|---|---|---|---|
| `sumi/fv_umi_codec` | `umi_pack` / `umi_unpack` | CMD codec round-trips over the 13 structured opcodes, and each field sits at the bit position `umi_messages.vh` defines | 2 | 1 |
| `sumi/fv_umi_buffer` | `umi_buffer` | obeys the README 4.2 ready/valid handshake, including rule 5, and delivers every beat unchanged in all four SUMI fields and in accept order, with none dropped or invented | 11 | 11 |
| `sumi/fv_umi_demux` | `umi_demux` | routing, broadcast and fork conservation; every output channel legal SUMI; rule 5 clean | 7 | 6 |
| `sumi/fv_umi_arbiter` | `umi_arbiter` | grant contract: at most one grant, never to an idle or masked requester, and in priority mode the lowest unmasked requester wins | 6 | 4 |
| `sumi/fv_umi_mux` | `umi_mux` | merge identity at accept time: one accept in iff one accept out, and the output beat is the accepting input's (bounded) | 2 | 3 |
| `sumi/fv_umi_mux2` | `umi_mux2` | select-and-merge: the output is the selected input's beat, accepts are conserved, and the output channel is legal SUMI under a stable select | 4 | 5 |
| `sumi/fv_umi_crossbar` | `umi_crossbar` | NxN routing at accept time: one delivery per output, the delivered beat is the delivering input's, and no masked path delivers | 3 | 5 |
| `sumi/fv_umi_pipeline` | `umi_pipeline` | the single-cycle register stage keeps the handshake and delivers every beat it accepts, once, in order, unchanged (unbounded -- every register is a port) | 6 | 6 |
| `sumi/fv_umi_decode` | `umi_decode` | the class outputs are mutually exclusive and complete, and on the legal opcode set each matches the full five-bit encoding the four-bit compares stand in for | 3 | 4 |
| `sumi/fv_umi_isolate` | `umi_isolate` | isolate high clamps the whole channel to zero and isolate low passes it through, over both build-time arms | 3 | 2 |
| `sumi/fv_umi_monitor` | `umi_monitor` | the passive tap reports a transfer on exactly the cycles README 4.2 rule 1 defines one | 2 | 1 |
| `sumi/fv_umi_fifo` | `umi_fifo` | handshake and carriage over both the stored and bypass paths: nothing dropped, duplicated, invented or reordered (bounded, clocks tied) | 7 | 4 |
| `sumi/fv_umi_stream` | `umi_stream` | a legal handshake on all four faces at once, the two UMI and the two USI (bounded, clocks tied) | 2 | 4 |
| `sumi/fv_umi_memif` | `umi_memif` | the nine atomic operations against their arithmetic, and the arm that resolves an undefined ATYPE | 2 | 4 |
| `sumi/fv_umi_regif` | `umi_regif` | the register interface answers the right kind of request and keeps the response handshake at `SAFE=0`; `SAFE=1` loses answers and is pinned | 3 | 4 |
| `sumi/fv_umi_endpoint` | `umi_endpoint` | request to memory operation to response: one memory op per request, the right response kind, back to the requester, and the answers owed are accounted for | 3 | 5 |
| `sumi/fv_umi_ram` | `umi_ram` | an answer is only offered to a port whose id bit it carries; the response channel's rule 3 failure is pinned (bounded) | 3 | 2 |
| `sumi/fv_umi_fifoflex` | `umi_fifoflex` | bytes are conserved across a width change at `SPLIT=0` and on the merge arm; `SPLIT=1` is pinned as not conserving them (bounded) | 4 | 3 |
| `sumi/fv_umi_switch` | `umi_switch` | the output handshake on every port, with the ready merge active across one and two outputs (bounded) | 4 | 1 |
| `sumi/fv_umi_cmd` | `umi_cmd_checker` | CMD-word legality: the checker's assume face and assert face agree | 6 | 11 |
| `sumi/fv_umi_txn` | `umi_txn_checker` | response-side transaction / framing against a perfect in-order responder | 5 | 8 |

88 green rows and 94 fault rows, 182 in all, over 21 harnesses.

Nineteen of them judge **shipped design RTL**, covering every SUMI block
on a UMI path except `umi_memagent`, whose atomic unit is textually the
same as `umi_memif`'s but reaches no port without a memory round trip,
and `umi_tester`, which is test-bench infrastructure rather than a block
on a path. `fv_umi_cmd` and `fv_umi_txn` qualify
the **checkers themselves**. `fv_umi_cmd` does so one face against the other;
`fv_umi_txn` elaborates the asserting face alone, against a responder model, so
its ASSUME face is not covered (see the scope note below).

### Results that are pinned rather than proven

Four blocks do not satisfy a law a reader would expect, and each has a
row that REQUIRES the failure so it cannot regress into silence. Nothing
is injected on any of them -- the shipped configuration is the subject:

| row | what it requires to fail | why |
|---|---|---|
| `regif:fault_safe` | `a_regif_outstanding` | at `SAFE=1`, the default, a second request is accepted while the first answer still stands and the response is overwritten |
| `endpoint:fault_cap` | `a_ep_outstanding` | the `REG=1` arm holds two answers, not one, so the `REG=0` accounting law does not carry over |
| `ram:fault_stable` | `RULE3_dstaddr_stable` | the broadcast response address moves while an answer is standing unaccepted |
| `fifoflex:fault_split` | `a_flex_conserve` | at `SPLIT=1`, the arm `umi_memagent` instantiates, more bytes are delivered than were accepted |

If any of these ever goes green, the block changed and the lane says so.

### Scope notes

Only the caveats a reader must know before trusting a result; full rationale
is in each harness header.

**Clocks are tied** in `fv_umi_fifo`, `fv_umi_stream` and `fv_umi_fifoflex`.
Those blocks span two domains through `la_asyncfifo`; the harnesses drive both
from one clock. That covers everything independent of the clock ratio and says
nothing about true asynchrony, which needs a delay model on the synchroniser
outputs that this directory does not have yet.

**`umi_switch` is not re-exported** from `umi.sumi`, so the parametrized lint
does not reach it and `fv_umi_switch` imports it directly. That keeps the
existing decision to keep it out of the public API intact while still letting
the block be judged.

**README 4.2 rule 5** ("the assertion of VALID must not depend on the assertion
of READY") is structural -- a cycle-sampled bind-in monitor cannot assert it.
It is proven harness-side instead, on the DUT: a `rule5` cover pins READY low
for the whole trace and reaches VALID asserting anyway, and `fault_rule5`
models the illegal design where VALID waits for READY, under which that cover
becomes unreachable and the row fails. `fv_umi_demux` adds a second,
independent form for the neighbouring rule 6 (README.md:463, READY may depend
on VALID but not combinationally) -- a self-composition miter proving
`in_ready` does not depend on `in_valid`. That miter is `fv_umi_demux` only;
`fv_umi_buffer` carries no rule-6 property, so it is proven clean on rule 5
alone. `fv_umi_mux2` proves rule 5 by the same
miter method (`a_mux2_r5_valid_indep`) and uses it in the other direction to
witness the rule 6 dependence its input ports do have.

**`fv_umi_buffer`** -- payload identity (`a_id_occupancy`, `a_id_beat`) is
proven with **no environment assumption**: no bound on how long READY may stay
low, and no restriction on the traffic beyond the legal-SUMI stimulus the
handshake rows already use. Two things about it are worth knowing:

* **`abc pdr`, not k-induction.** The skid register is not observable at any
  port, so the step case starts from a full buffer whose skid slot holds a
  value no accepted beat put there and fails on `a_id_beat` -- the limit
  `fv_umi_mux` records for its own captured input. No assertion written over
  ports alone can exclude that start, and no choice of SMT solver helps: the
  step case is genuinely satisfiable. PDR derives its invariant over the
  design's registers and closes the same property unbounded.
* **A narrower face.** The identity rows run AW=16 / DW=32, because PDR
  relates the payload registers bit by bit; the law is width-agnostic and the
  harness defaults close too, about five times slower.
* **The pdr engine has its own known-answer row.** `fault_swap_pdr` runs the
  swap corruption on the engine the identity rows are proven with, so that
  engine is shown convicting a broken buffer rather than only answering
  "proved". It pins a verdict, not a label -- see the engines section.

The per-rule `RULE_EN` mask is checked over **every** bit, not only the one a
targeted fault reaches: `prove_mask_off` frees the whole observed output
channel, so every handshake rule is breakable at once, and clears the mask --
a rule left outside its guard fails there immediately. The six
`fault_mask_*` rows are the other half, one enabled bit each, and every one
must convict that bit's own rule.

**`fv_umi_demux`** -- the onehot-select assumption is the boundary of correct
usage. The `hazard` row drops it and witnesses all three real behaviours:
`select==0` **accepts and silently drops** a beat, a multi-hot select with its
outputs ready **duplicates** one across them, and a multi-hot select with only
some outputs ready **delivers without accepting**, so the upstream offers the
beat again. `fault_drop` / `fault_dup` weaken the assumption in each direction
so it is falsifiable rather than trusted. Read the row under the cover-mode
caveat above: those hazards are reachable, not legal.

**`fv_umi_mux`** -- three limits, all in the harness header:

* **Bounded, not unbounded.** The captured `stalled_input` is not observable at
  the ports while the output is stalled, so k-induction starts from states no
  trace reaches. Closing it wants an assume/guarantee stub licensed by
  `fv_umi_arbiter`'s grant contract, not a hierarchical peek.
* **Output stability across a stall is not claimed**, and no `ASSUME=0` checker
  is bound to the output channel. The arbiter re-evaluates every cycle, so
  consumers must sample on accept, not on offer.
* **Rule 6 is not met input-side.** `umi_in_ready` is combinational in
  `umi_in_valid` through the arbiter, so the argument `fv_umi_buffer` and
  `fv_umi_demux` make does not transfer here. Rule 5 governs the opposite
  direction and is not claimed either way. `c_mux_r5_path` witnesses the
  dependency instead of leaving it as a reading of the source.

**`fv_umi_mux2`** -- the same block family, the opposite result on stability,
because the select is a port rather than an internal arbiter:

* **Unbounded, not bounded.** `umi_mux2` is combinational and holds no state
  the ports cannot see, so the green row is `prove` (k-induction) rather than
  the `bmc` `fv_umi_mux` has to settle for.
* **Output stability IS claimed**, and an `ASSUME=0` handshake checker *is*
  bound to the output channel -- under one stated environment assumption,
  `m_mux2_sel_stable`: `sel` may not move while an output offer is pending.
  That is an integration requirement, not a convenience. Output VALID and
  payload are combinational in `sel`, so only the `sel` driver can discharge
  README 4.2 rules 2 and 3 at the merged output. The `hazard` row drops the
  assumption and covers what the shipped RTL then does: `c_mux2_offer_lost`
  (a pending beat is withdrawn) and `c_mux2_beat_swap` (the offer stands but
  the payload is now the other input's).
* **README 4.2 rule 6 is not met at the input ports.** `umi_in_ready[i]`
  contains the literal term `~umi_in_valid[i]`, so an idle input reads READY
  high regardless of `umi_out_ready`. The accept sets are unharmed -- `VALID & READY` cancels the term -- but `umi_in_ready` alone is not a usable
  "the sink can take a beat" signal. `c_mux2_r6_selfdep` witnesses the path
  constructively with a self-composition twin, and `a_mux2_r6_nocross` bounds
  the exposure by proving one input's READY does not depend on the other
  channel. Rule 5 itself is clean and proven: `a_mux2_r5_valid_indep`.
* **No liveness.** `umi_mux2` has no arbiter, so starvation freedom is a
  property of whatever drives `sel` and must be proven there.

**`fv_umi_crossbar`** -- unbounded (`prove` closes by k-induction), with three
limits, all in the harness header:

* **Conservation is conditional.** "An output accept means an input was
  accepted" is claimed only for cycles in which every input requests at most
  one output. That is an antecedent of `a_xb_conserve` alone -- the other five
  laws, including the whole route theorem, are unconditional and hold under
  multicast. Outside it, an input granted by two outputs but taken by only one
  leaves that output accepting a beat the still-stalled input will offer again;
  `c_xb_multicast` witnesses the trace.
* **READY alone is not an accept.** `umi_in_ready` is a conjunction over the
  outputs an input requests, so an input requesting nothing reads ready
  (`c_xb_quiet`). Every law here qualifies ready with the input's request
  column, and a consumer must do the same.
* **Output channels are not checked as SUMI, and rule 5 is not claimed
  input-side** -- the same two limits `fv_umi_mux` records, for the same
  reason: the arbiter re-evaluates every cycle, and `umi_in_ready` is
  combinational in `umi_in_request` through it. Rule 6 is the one that
  governs a READY-on-VALID path; rule 5 constrains the opposite direction and
  is not claimed here either way. `c_xb_r6_path` witnesses the dependency.

**`fv_umi_cmd`** -- `cover_sa` and `fault_sa_reserved` run the opt-in strict
profile `CHECK_SA_RESERVED=1` (request SA reserved bits zero). It defaults
**off**: the repo's own reference traffic uses the high SA bytes for routing.

* **The prove rows test the rules' form, not their content.** With no fault
  injected the asserting instance sees exactly the channel the assuming
  instance constrains, so each `assert (P)` is the `assume (P)` already made
  about the same signals from the same source line -- true for any `P`. What
  the rows establish is that the two faces cannot drift apart, in either
  profile and under any `RULE_EN`. The content is carried by the eleven fault
  rows, each an illegal beat one named rule must reject. Closing the gap in
  the prove rows wants a reference predicate written independently of the
  checker, which is a second implementation of the CMD rules rather than an
  added row.

**`fv_umi_txn`** -- five limits:

* **Framing depth.** `prove` runs MAXLEN=1 (up to two beats); `prove_deep`
  raises the harness LEN ceiling to MAXLEN=3 (four beats). Unbounded at each.
* **No interleave.** Holds for one point-to-point link with responses in
  request order. Bind the checker **before** any response mux; per-key
  (HOSTID) folding downstream of a merge is not covered.
* **Width.** The harness runs DW=64 (the checker ships DW=256) to keep the SMT
  problem tractable; the framing rules are DW-agnostic.
* **Obligation filtering is never exercised.** The checker enqueues a request
  only if it expects a response and closes its message; the requester model
  here emits single-beat READ/WRITE/ATOMIC requests with EOM set, so both
  terms are true on every request and neither is ever seen to reject one. A
  posted write and a multi-beat request would test them, and need a requester
  model that can emit both plus glue lemmas rewritten around them.
* **Only the asserting face is elaborated.** `umi_txn_checker` appears here as
  `ASSUME=0` alone. Nothing in this directory would notice if its `ASSUME=1`
  face drifted from it -- the property `fv_umi_cmd` establishes for the CMD
  checker has no counterpart for this one, and building it means a second
  harness rather than an added row.

### What the covers witness

Covers do two jobs here. Most are reachability witnesses: they show an
environment is not silently starving its proof, which is why the convention
above requires every one of them to be reached. The rest stand in for
behaviour that is real but cannot be asserted -- a hazard a block genuinely
has, or a structural property a cycle-sampled monitor cannot state.

| cover | witnesses |
|---|---|
| `c_dx_drop` | `umi_demux` accepting a beat at `select==0` and dropping it |
| `c_dx_dup` | one accepted input beat delivered to two or more outputs under a multi-hot select |
| `c_dx_noaccept` | a delivery with no accept, when only some selected outputs are ready -- the same beat is then offered again |
| `c_arb_rotate` | `umi_arbiter` moving the grant to another requester while the request and mask pattern is held still, which only the thermometer can do |
| `c_mux_r5_path` | the combinational valid-to-ready path in `umi_mux` |
| `c_xb_quiet` | `umi_crossbar` raising READY for an input that asked for nothing |
| `c_xb_multicast` | an output accept with no input accept, the traffic `a_xb_conserve` excludes |
| `c_xb_r6_path` | the combinational request-to-ready path in `umi_crossbar` |
| `c_mux2_offer_lost` / `c_mux2_beat_swap` | what `umi_mux2` does when `sel` moves under a pending offer |
| `c_mux2_r6_selfdep` | `umi_mux2`'s READY depending on its own channel's VALID |
| the `rule5` rows | VALID asserting while READY is held low for the whole trace |

Deliberately not covered anywhere: data widths above the per-harness value in
the table above, and any behaviour of the LUMI link layer, which has no proofs
in this directory.

## Binding a checker into a design

The checkers under `umi/sumi/umi_checker/` are ordinary modules with no
package or interface dependencies, so `bind` attaches one to a design without
editing that design. The worked example is two files in the checker block's
own testbench directory:

    umi/sumi/umi_checker/testbench/umi_buffer_checker_bind.sv
        the bind itself -- one umi_handshake_checker on each SUMI channel of
        umi_buffer, wired to that block's own clk, nreset and payload
    umi/sumi/umi_checker/testbench/tb_umi_buffer_bind.sv
        a testbench that drives the buffer through a stall and a drain, plus
        a +inject run that breaks README 4.2 rule 3 on purpose

Run it through pytest:

    pytest tests/sumi/test_checker_bind.py

or by hand, from the testbench directory:

    verilator --binary --assert --timing -o tb tb_umi_buffer_bind.sv \
              umi_buffer_checker_bind.sv ../rtl/umi_handshake_checker.sv \
              ../../umi_buffer/rtl/umi_buffer.v
    ./obj_dir/tb            # expect: EXAMPLE PASS
    ./obj_dir/tb +inject    # expect: RULE3_cmd_stable against u_umi_hs_in

The `+inject` run is the point of the example, not a footnote to it. A clean
run cannot distinguish a checker that is silent from one that is not there:
comment the two bind directives out and the injected violation goes
unreported, the example prints its pass line and exits zero. Keep a run that
must fail beside every run that must pass.

Icarus does not support `bind`. Use Verilator or a commercial simulator.

### Attaching one to your own block

Give the checker the channel's `valid` and `ready`, its four packet fields,
and the clock and reset. Every name in a bind port connection resolves in the
target block's scope, so a block whose ports are already `umi_*_cmd`,
`umi_*_dstaddr` and so on connects straight across; `umi_buffer` carries the
packet as one wide payload, so the example slices it back apart. Bind one
instance per channel: an instance on an input channel asserts against whoever
drives that channel, an instance on an output channel asserts against the
block itself.

| parameter | meaning |
|---|---|
| `CW` / `AW` / `DW` | command, address and data widths of the channel |
| `ASSUME` | 0 asserts the rules, 1 assumes them |
| `CHECK_RESET` | 1 also requires VALID low while `nreset` is asserted |

`ASSUME=0` is the only face that means anything in simulation: it reports a
rule break as a simulation error. `ASSUME=1` turns the same properties into
assumptions, which is useful only in a formal harness, where it constrains
free stimulus so the solver explores legal traffic. In simulation nothing is
free, and an assumption checks nothing. Set `CHECK_RESET=0` for a channel that
legitimately asserts VALID during reset; README 4.2 says nothing about reset,
and the default follows the convention every block in this repository keeps.

### Simulation only

This example is for simulation. yosys has dropped `bind` directives without
reporting it, so a property reached through a bind must never be the only
thing standing behind a formal claim. Every proof above instantiates its
checkers directly in the harness for that reason, and the formal counterpart
of this example is `sumi/fv_umi_buffer`.

## Adding a proof

1. Add `fv_<name>.sv` under the layer directory, with at least one `fault_*`
   define and covers for every assumed corner. Document its rows and its
   fault-to-label table in the harness header.
2. Add a family entry (deps, depth, timeout) to `FAMILIES` in
   `tests/sumi/test_formal_sc.py`, then one `Proof` row per question in
   `GREEN` and `FAULTS`.
3. Add a line to the table above.

Follow `fv_umi_mux` for a block that instantiates lambdalib, and
`fv_umi_buffer` for a property that needs `abc pdr`.
