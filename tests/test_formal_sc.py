"""Formal property proofs, run as SiliconCompiler flows.

Each proof under umi/formal/ is one file, the harness fv_<name>.sv: it
instantiates the shipped RTL, constrains the inputs and states the
properties. The sby job is generated here from the repo's own Design
filesets -- the harness on top, the DUT and the property blocks pulled
in as depfilesets -- so a proof builds from the same fileset graph the
rest of the repo builds from. Include dirs, defines and top-level
params ride in from the Design objects; sources are read in place.

One row per question, named <family>:<task>. Green rows must prove or
cover clean: project.run() completes and the sby errors metric is 0.
fault_* rows inject a bug and must FAIL: run() raises naming the
mode's node, sby's own verdict is FAIL, so a tool or setup ERROR stays
red instead of counting as a catch, and the label sby blames is the
one the row named in expect, so a fault cannot convict the wrong rule
and still pass.

Engines: bitwuzla answers every row but the three buffer identity
rows. Those run abc pdr, and cannot run anything else -- the skid
register is not observable at any port, so k-induction starts its step
case from a buffer state no trace reaches and fails a_id_beat whichever
SMT solver sits behind it. sby's name for that engine is not in the sby
task's engine enum, so PdrProveTask rewrites the [engines] section of
the generated job file. One of the three is a fault row, so the pdr
engine is shown convicting a bug rather than only answering "proved".

Skips cleanly when the formal toolchain or the SC formal flow are
missing, so other CI lanes are unaffected.
"""
import re
import shutil
from pathlib import Path
from typing import Tuple

import pytest

try:
    from siliconcompiler import Design, Flowgraph, Project
    from siliconcompiler.flows.formalflow import PropertyCheckFlow, PropertyCheckMode
    from siliconcompiler.tools.sby import SBYTask
    from siliconcompiler.tools.sby.prove import ProveTask
    _HAVE_SC_FORMAL = True
except ImportError:  # pragma: no cover -- pre-formal-flow siliconcompiler
    _HAVE_SC_FORMAL = False

from umi.sumi import (Arbiter, Buffer, Checker, Crossbar, Decode, Demux,
                      Endpoint, Fifo, FifoFlex, Isolate, Memif, Monitor, Mux,
                      Mux2, Pack, Pipeline, RAM, Regif, Stream, Unpack)

# umi_switch is deliberately not re-exported from umi.sumi -- see
# "Disabling umi_switch in api for safety reasons". Reaching past the
# package API keeps that decision intact while still letting the block
# be judged; fv_umi_switch.sv states what the disabled path does.
from umi.sumi.umi_switch.umi_switch import Switch
from umi.adapters import (AddressRemap, AXI2UMI, AXIL2UMI, TL2UMI, UMI2APB,
                          UMI2AXIL, UMI2TL)

REPO = Path(__file__).resolve().parents[1]
FORMAL_SUMI = REPO / "umi" / "formal" / "sumi"
FORMAL_ADAPTERS = REPO / "umi" / "formal" / "adapters"
SUMI_INCLUDE = REPO / "umi" / "sumi" / "include"

# the lane pins its engine rather than inheriting the sby task's
# default, so a change of default upstream cannot silently move which
# solver the results are gated on. bitwuzla is boolector's maintained
# successor and is what the sc_tools image ships alongside it.
# Once it ships bitwuzla this becomes a one-line switch.
SMT_ENGINE = "smtbmc bitwuzla"
PDR_ENGINE = "abc pdr"

_TOOLS = ("sby", "yosys", "yosys-abc", "bitwuzla")

pytestmark = [
    pytest.mark.formal,
    pytest.mark.skipif(any(shutil.which(t) is None for t in _TOOLS),
                       reason="formal toolchain (sby/yosys/yosys-abc/bitwuzla) "
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

    class PdrProveTask(ProveTask):
        """prove driven by sby's property-driven reachability engine.

        The sby task's engine var is a closed enum of SMT engine lines,
        so abc pdr cannot be asked for through add_sby_engine. Rewrite
        the [engines] section of the job file the base class has just
        written instead, and add `aigsmt none` to [options] on the way
        past. abc reports a counterexample as an AIGER output index; sby
        turns that back into a named assertion by replaying the witness
        through a second SMT solver, a step that needs a solver beyond
        the four this lane requires and that is not reliable across
        yosys builds -- on the harnesses here it aborts with a witness
        signal mismatch and the run ends ERROR, hiding a genuine FAIL.
        With it off the engine's own verdict is what sby reports.
        """

        def pre_process(self):
            super().pre_process()
            job = Path(f"{self.design_topmodule}.sby")
            head, _, rest = job.read_text().partition("[engines]\n")
            _, _, script = rest.partition("\n\n")
            options = head.rstrip("\n")
            job.write_text(f"{options}\naigsmt none\n\n"
                           f"[engines]\n{PDR_ENGINE}\n\n{script}")

# One entry per proof family: the dependency blocks (DUT + property
# modules), the default unrolling depth, and the sby wall-clock ceiling.
# root is where the harness file lives, and defaults to umi/formal/sumi;
# the adapter harnesses sit beside their own layer instead. defines are
# applied to every row of the family, on top of the row's own.
FAMILIES = {
    "fv_umi_codec": dict(deps=lambda: [Pack(), Unpack()], depth=4, timeout=300),
    "fv_umi_buffer": dict(deps=lambda: [Buffer(), Checker()], depth=12, timeout=300),
    "fv_umi_demux": dict(deps=lambda: [Demux(), Checker()], depth=12, timeout=300),
    "fv_umi_arbiter": dict(deps=lambda: [Arbiter()], depth=12, timeout=300),
    "fv_umi_mux": dict(deps=lambda: [Mux(), Checker()], depth=12, timeout=300),
    "fv_umi_mux2": dict(deps=lambda: [Mux2(), Checker()], depth=12, timeout=300),
    "fv_umi_crossbar": dict(deps=lambda: [Crossbar(), Checker()], depth=12, timeout=300),
    "fv_umi_pipeline": dict(deps=lambda: [Pipeline(), Checker()], depth=12,
                            timeout=300),
    "fv_umi_decode": dict(deps=lambda: [Decode()], depth=4, timeout=300),
    "fv_umi_isolate": dict(deps=lambda: [Isolate()], depth=4, timeout=300),
    "fv_umi_monitor": dict(deps=lambda: [Monitor()], depth=12, timeout=300),
    "fv_umi_fifo": dict(deps=lambda: [Fifo(), Checker()], depth=16,
                        timeout=900),
    "fv_umi_stream": dict(deps=lambda: [Stream(), Checker()], depth=14,
                          timeout=900),
    "fv_umi_memif": dict(deps=lambda: [Memif()], depth=6, timeout=900),
    "fv_umi_regif": dict(deps=lambda: [Regif(), Checker()], depth=12,
                         timeout=900),
    "fv_umi_endpoint": dict(deps=lambda: [Endpoint(), Checker()], depth=12,
                            timeout=900),
    "fv_umi_ram": dict(deps=lambda: [RAM(), Checker()], depth=10,
                       timeout=1800),
    "fv_umi_fifoflex": dict(deps=lambda: [FifoFlex(), Checker()], depth=12,
                            timeout=1800),
    "fv_umi_switch": dict(deps=lambda: [Switch(), Checker()], depth=12,
                          timeout=1800),
    "fv_umi_frame": dict(deps=lambda: [Checker()], depth=10, timeout=900),
    "fv_umi_cmd": dict(deps=lambda: [Checker()], depth=6, timeout=300),
    "fv_umi_txn": dict(deps=lambda: [Checker()], depth=20, timeout=1200),
    "fv_umi2apb": dict(deps=lambda: [UMI2APB(), Checker()], depth=10,
                       timeout=1800, root=FORMAL_ADAPTERS),
    "fv_umi2axil": dict(deps=lambda: [UMI2AXIL(), Checker()], depth=12,
                        timeout=1800, root=FORMAL_ADAPTERS),
    "fv_axil2umi": dict(deps=lambda: [AXIL2UMI(), Checker()], depth=12,
                        timeout=1800, root=FORMAL_ADAPTERS),
    "fv_axi2umi": dict(deps=lambda: [AXI2UMI(), Checker()], depth=14,
                       timeout=1800, root=FORMAL_ADAPTERS),
    # tl2umi guards four $display calls with `ifndef SYNTHESIS. yosys
    # reads them as $check cells and async2sync rejects a $check with
    # more than one trigger, which is what an always block with an async
    # reset gives it. Defining SYNTHESIS takes the RTL's own escape and
    # removes simulation-only output, no logic.
    "fv_tl2umi": dict(deps=lambda: [TL2UMI(), Checker()], depth=12,
                      timeout=1800, root=FORMAL_ADAPTERS,
                      defines=("SYNTHESIS",)),
    "fv_umi2tl": dict(deps=lambda: [UMI2TL(), Checker()], depth=12,
                      timeout=1800, root=FORMAL_ADAPTERS,
                      defines=("SYNTHESIS",)),
    "fv_umi_address_remap": dict(deps=lambda: [AddressRemap(), Checker()],
                                 depth=4, timeout=900, root=FORMAL_ADAPTERS),
    # umi_data_aggregator ships inside the tl2umi fileset, so TL2UMI is
    # how the harness reaches it without a second Design for one file
    "fv_umi_data_aggregator": dict(deps=lambda: [TL2UMI(), Checker()],
                                   depth=12, timeout=1800,
                                   root=FORMAL_ADAPTERS,
                                   defines=("SYNTHESIS",)),
}


class Proof:
    """One sby job: which harness, which question, how to ask it.

    expect names the assertion (or cover) label a fault row must trip.
    Checking only that sby said FAIL would let a fault convict the
    wrong rule unnoticed, so every fault row pins its label. The one
    exception is a fault row on the abc pdr engine, which reports an
    AIGER output index rather than a label (see PdrProveTask): those
    rows leave expect None, pin the engine's verdict instead, and are
    paired with a bmc row that injects the same fault and does pin the
    label.
    """

    def __init__(self, tid: str, family: str, mode: str,
                 defines: Tuple[str, ...] = (),
                 params: Tuple[Tuple[str, str], ...] = (),
                 depth: int = 0, engine: str = SMT_ENGINE,
                 expect: str = None):
        self.tid = tid
        self.family = family
        self.mode = mode
        self.defines = defines
        self.params = params
        self.depth = depth or FAMILIES[family]["depth"]
        self.engine = engine
        self.expect = expect


# sby names the label that broke the run on one of two engine lines:
#   ##  0:00:00  Assert failed in <scope>: <label>
#   ##  0:00:00  Unreached cover statement at <scope>: <label>
# bmc/prove rows land on the first, cover rows on the second. A scope
# inside a generate loop is printed as a Verilog escaped identifier,
# which terminates with a SPACE -- "fv_umi_ram.\g_port[1].chk_resp :
# RULE3_dstaddr_stable" -- so the separator is not always a bare colon.
_FAIL_LABEL = re.compile(
    r"(?:Assert failed in|Unreached cover statement at) \S+\s*: (\w+)")


def _failed_labels(log: str):
    """Every label sby blamed for the FAIL, leaf name only."""
    return set(_FAIL_LABEL.findall(log))


GREEN = [
    # ---- fv_umi_codec -------------------------------------------------
    Proof("codec:prove", "fv_umi_codec", "prove"),
    Proof("codec:cover", "fv_umi_codec", "cover"),

    # ---- fv_umi_buffer ------------------------------------------------
    Proof("buffer:prove", "fv_umi_buffer", "prove"),
    Proof("buffer:bypass", "fv_umi_buffer", "prove", params=(("MODE", "0"),)),
    Proof("buffer:cover", "fv_umi_buffer", "cover"),
    # rule 4.2.5 witness (README.md section 4.2 rule 5): out_ready
    # ASSUMED stuck low, cover out_valid asserting anyway; FV_NO_WITNESS
    # drops the handshake checker's own transaction covers, unreachable
    # under stuck-low ready
    Proof("buffer:rule5", "fv_umi_buffer", "cover",
          defines=("FV_RULE5_READYLOW", "FV_NO_WITNESS")),
    # the per-rule enable mask is falsifiable, not decorative: with the
    # observed output channel entirely free EVERY handshake rule is
    # breakable, and with the mask cleared none of them is reported. The
    # buffer:fault_mask_* rows below are the other half -- one bit
    # enabled at a time, each convicting its own rule
    Proof("buffer:prove_mask_off", "fv_umi_buffer", "prove",
          defines=("FV_FAULT_FREEOUT",), params=(("RULE_EN", "0"),)),
    # payload identity: abc pdr, and a narrow face because pdr relates
    # the payload registers bit by bit (see the harness header)
    Proof("buffer:identity", "fv_umi_buffer", "prove",
          defines=("FV_IDENTITY",), params=(("AW", "16"), ("DW", "32")),
          engine=PDR_ENGINE),
    Proof("buffer:identity_bypass", "fv_umi_buffer", "prove",
          defines=("FV_IDENTITY",),
          params=(("MODE", "0"), ("AW", "16"), ("DW", "32")),
          engine=PDR_ENGINE),
    Proof("buffer:identity_cover", "fv_umi_buffer", "cover",
          defines=("FV_IDENTITY",), params=(("AW", "16"), ("DW", "32"))),
    # the MODE=0 arm states the same two laws over different logic, so it
    # needs its own witnesses: identity_bypass would pass on a link that
    # never moved a beat
    Proof("buffer:identity_cover_bypass", "fv_umi_buffer", "cover",
          defines=("FV_IDENTITY",),
          params=(("MODE", "0"), ("AW", "16"), ("DW", "32"))),

    # ---- fv_umi_pipeline ----------------------------------------------
    Proof("pipeline:prove", "fv_umi_pipeline", "prove"),
    Proof("pipeline:cover", "fv_umi_pipeline", "cover"),
    # identity rides its own rows: the accounting law reads the same
    # obs_valid the handshake faults corrupt and would convict a cycle
    # ahead of the rule those rows are aimed at
    Proof("pipeline:identity", "fv_umi_pipeline", "prove",
          defines=("FV_IDENTITY",)),
    Proof("pipeline:identity_cover", "fv_umi_pipeline", "cover",
          defines=("FV_IDENTITY",)),
    # as buffer:prove_mask_off -- a free output channel with the mask
    # cleared reports nothing; the fault_mask_* rows enable one bit each
    Proof("pipeline:prove_mask_off", "fv_umi_pipeline", "prove",
          defines=("FV_FAULT_FREEOUT",), params=(("RULE_EN", "0"),)),

    # ---- fv_umi_decode ------------------------------------------------
    Proof("decode:prove", "fv_umi_decode", "prove"),
    Proof("decode:cover", "fv_umi_decode", "cover"),
    # the legal-opcode assumption withdrawn: the structural laws still
    # hold and the covers pin what the four-bit compares admit
    Proof("decode:hazard", "fv_umi_decode", "cover",
          defines=("FV_DEC_ANYOPCODE",)),

    # ---- fv_umi_isolate -----------------------------------------------
    Proof("isolate:prove", "fv_umi_isolate", "prove"),
    # the arm with the cells compiled out: a different circuit behind
    # the same port list, so it gets judged rather than assumed
    Proof("isolate:prove_iso0", "fv_umi_isolate", "prove",
          params=(("ISO", "0"),)),
    Proof("isolate:cover", "fv_umi_isolate", "cover"),

    # ---- fv_umi_monitor -----------------------------------------------
    Proof("monitor:prove", "fv_umi_monitor", "prove"),
    Proof("monitor:cover", "fv_umi_monitor", "cover"),

    # ---- fv_umi_fifo --------------------------------------------------
    # bounded, not prove: the pointers reach la_drsync registers no port
    # shows, so induction starts from states no trace reaches. See the
    # note in fv_umi_fifo.sv
    Proof("fifo:bmc", "fv_umi_fifo", "bmc"),
    Proof("fifo:bmc_bypass", "fv_umi_fifo", "bmc", params=(("BYPASS", "1"),)),
    Proof("fifo:cover", "fv_umi_fifo", "cover"),
    Proof("fifo:identity", "fv_umi_fifo", "bmc", defines=("FV_IDENTITY",),
          params=(("DEPTH", "2"),)),
    Proof("fifo:identity_bypass", "fv_umi_fifo", "bmc",
          defines=("FV_IDENTITY",), params=(("BYPASS", "1"),)),
    Proof("fifo:identity_cover", "fv_umi_fifo", "cover",
          defines=("FV_IDENTITY",), params=(("DEPTH", "2"),)),
    # the bypass arm states the same three laws over different logic, so
    # it needs its own witnesses
    Proof("fifo:identity_cover_bypass", "fv_umi_fifo", "cover",
          defines=("FV_IDENTITY",), params=(("BYPASS", "1"),)),

    # ---- fv_umi_stream ------------------------------------------------
    # bounded for the reason fv_umi_fifo gives: the FIFO pointers cross
    # synchroniser registers no port shows
    Proof("stream:bmc", "fv_umi_stream", "bmc"),
    Proof("stream:cover", "fv_umi_stream", "cover"),

    # ---- fv_umi_demux -------------------------------------------------
    Proof("demux:prove", "fv_umi_demux", "prove"),
    Proof("demux:prove_m4", "fv_umi_demux", "prove", params=(("M", "4"),)),
    Proof("demux:cover", "fv_umi_demux", "cover"),
    Proof("demux:rule5", "fv_umi_demux", "cover",
          defines=("FV_RULE5_READYLOW", "FV_NO_WITNESS")),
    # the onehot-select assumption is the boundary of correct usage:
    # drop it and cover what the shipped RTL then does
    Proof("demux:hazard", "fv_umi_demux", "cover", defines=("FV_NO_SEL_ASSUME",)),

    # ---- fv_umi_arbiter -----------------------------------------------
    Proof("arbiter:prove", "fv_umi_arbiter", "prove"),
    Proof("arbiter:prove_n2", "fv_umi_arbiter", "prove", params=(("N", "2"),)),
    # bounded, not prove: the lowest-index law holds of traces from
    # reset, not of every thermometer state k-induction may start from
    Proof("arbiter:prio", "fv_umi_arbiter", "bmc", defines=("FV_MODE_PRIO",)),
    Proof("arbiter:cover", "fv_umi_arbiter", "cover"),
    Proof("arbiter:rotate", "fv_umi_arbiter", "cover", defines=("FV_MODE_RR",)),

    # ---- fv_umi_cmd ---------------------------------------------------
    Proof("cmd:prove", "fv_umi_cmd", "prove"),
    Proof("cmd:prove_dw64", "fv_umi_cmd", "prove", params=(("DW", "64"),)),
    Proof("cmd:cover", "fv_umi_cmd", "cover"),
    # the opt-in strict profile: request SA reserved bits zero
    Proof("cmd:cover_sa", "fv_umi_cmd", "cover",
          params=(("CHECK_SA_RESERVED", "1"),)),
    Proof("cmd:cover_invalid", "fv_umi_cmd", "cover",
          params=(("ALLOW_INVALID", "1"),)),
    Proof("cmd:prove_mask_off", "fv_umi_cmd", "prove", params=(("RULE_EN", "0"),)),

    # ---- fv_umi_frame -------------------------------------------------
    # the request-side half umi_txn_checker's header records as missing.
    # Checker against checker, so induction closes on the shadow state
    # bounded: FRAME_msgbytes accumulates over a message, and a free
    # accumulator in the step case can start above the ceiling, so the
    # rule does not close by induction. The other five are cycle-local
    Proof("frame:bmc", "fv_umi_frame", "bmc"),
    Proof("frame:cover", "fv_umi_frame", "cover"),
    # as buffer:prove_mask_off -- a free observed channel with the mask
    # cleared reports nothing; fault_mask_da enables one bit
    Proof("frame:bmc_mask_off", "fv_umi_frame", "bmc",
          defines=("FV_FAULT_FREEOUT",), params=(("RULE_EN", "0"),)),

    # ---- fv_umi_txn ---------------------------------------------------
    Proof("txn:prove", "fv_umi_txn", "prove"),
    # MAXLEN=3 raises the harness LEN ceiling to four beats
    Proof("txn:prove_deep", "fv_umi_txn", "prove", params=(("MAXLEN", "3"),)),
    Proof("txn:cover", "fv_umi_txn", "cover", depth=22),
    Proof("txn:cover_boundary", "fv_umi_txn", "cover", depth=24,
          defines=("FORMAL_MSGBYTES_BOUNDARY",),
          params=(("MAX_MSG_BYTES", "256"),)),
    Proof("txn:prove_mask_off", "fv_umi_txn", "prove",
          params=(("CAP", "1"), ("RULE_EN", "0"))),

    # ---- fv_umi_mux ---------------------------------------------------
    # bounded, not prove: stalled_input is not port-observable while the
    # output is stalled, so the step case starts from states no trace
    # reaches. See the note in fv_umi_mux.sv.
    Proof("mux:bmc", "fv_umi_mux", "bmc"),
    Proof("mux:cover", "fv_umi_mux", "cover"),

    # ---- fv_umi_mux2 --------------------------------------------------
    Proof("mux2:prove", "fv_umi_mux2", "prove"),
    Proof("mux2:cover", "fv_umi_mux2", "cover"),
    # the select-stability assumption is auditable, not decorative:
    # drop it and cover what the shipped RTL then does at the output
    Proof("mux2:hazard", "fv_umi_mux2", "cover", defines=("FV_NO_SEL_STABLE",)),

    # ---- fv_umi_crossbar ----------------------------------------------
    # unbounded: every crossbar law is cycle-local, so k-induction
    # closes over an arbitrary arbiter thermometer state
    Proof("crossbar:prove", "fv_umi_crossbar", "prove"),
    Proof("crossbar:cover", "fv_umi_crossbar", "cover"),

    # ---- fv_umi_memif -------------------------------------------------
    Proof("memif:prove", "fv_umi_memif", "prove"),
    Proof("memif:cover", "fv_umi_memif", "cover"),

    # ---- fv_umi_regif -------------------------------------------------
    Proof("regif:prove", "fv_umi_regif", "prove"),
    Proof("regif:cover", "fv_umi_regif", "cover"),
    # SAFE=1 breaks the resp_ready to req_ready path on purpose, so a
    # second request can land while the first answer still stands. The
    # response checker is lifted and the overwrite is witnessed
    Proof("regif:hazard", "fv_umi_regif", "cover",
          defines=("FV_REGIF_NOCHK", "FV_REGIF_HAZARD"),
          params=(("SAFE", "1"),)),

    # ---- fv_umi_endpoint ----------------------------------------------
    Proof("endpoint:prove", "fv_umi_endpoint", "prove"),
    # bounded, not prove: REG=1 holds a second answer in a pipeline
    # stage no port shows, so the exact count is not expressible and a
    # bare bound on wrapping counters does not close by induction
    Proof("endpoint:bmc_reg", "fv_umi_endpoint", "bmc",
          params=(("REG", "1"),)),
    Proof("endpoint:cover", "fv_umi_endpoint", "cover"),

    # ---- fv_umi_ram ---------------------------------------------------
    # bounded: the memory array and the arbiter thermometer are both
    # unobservable from these ports, so induction starts from states no
    # trace reaches
    # the response checker is lifted on the green rows: the block does
    # not keep rule 3 on its response ports, which ram:fault_stable
    # pins. a_ram_route is what this row proves
    Proof("ram:bmc", "fv_umi_ram", "bmc", defines=("FV_RAM_NOCHK",)),
    Proof("ram:cover", "fv_umi_ram", "cover", defines=("FV_RAM_NOCHK",)),
    # the routing convention dropped: the two failures it holds off are
    # behaviour of the shipped block, so they are witnessed not asserted
    Proof("ram:hazard", "fv_umi_ram", "cover",
          defines=("FV_RAM_NOCHK", "FV_RAM_ANYID")),

    # ---- fv_umi_fifoflex ----------------------------------------------
    # bounded: a conservation law over running counters is not
    # inductive, and the exact in-flight figure lives in latch_bytes,
    # which is not a port. See the harness header.
    Proof("fifoflex:bmc", "fv_umi_fifoflex", "bmc", params=(("SPLIT", "0"),)),
    # the merge arm is a separate circuit and keeps the law with the
    # splitter enabled
    Proof("fifoflex:bmc_merge", "fv_umi_fifoflex", "bmc",
          params=(("IDW", "64"), ("ODW", "128"))),
    Proof("fifoflex:cover", "fv_umi_fifoflex", "cover"),
    # alignment withdrawn: the split arm's length arithmetic underflows
    # on an unaligned address, which is behaviour of the shipped block
    Proof("fifoflex:hazard", "fv_umi_fifoflex", "cover",
          defines=("FV_FLEX_NOALIGN",), params=(("IDW", "128"), ("ODW", "64"))),

    # ---- fv_umi_switch ------------------------------------------------
    # bounded: the arbiter thermometer and the mux's captured
    # stalled_input are not observable from these ports, the same fence
    # fv_umi_mux documents
    Proof("switch:bmc", "fv_umi_switch", "bmc"),
    # M=2 turns the ready merge on: every output's per-input ready is
    # ANDed together, so acceptance depends on the stalled-grant history
    # of outputs an input is not even asking for. See the harness header
    Proof("switch:bmc_m2", "fv_umi_switch", "bmc", params=(("M", "2"),)),
    Proof("switch:cover_m2", "fv_umi_switch", "cover", params=(("M", "2"),)),
    Proof("switch:cover", "fv_umi_switch", "cover"),

    # ---- fv_umi2apb ---------------------------------------------------
    # the first adapter: one UMI face and one AMBA APB face, each held
    # to its own specification. Bounded -- the DUT carries request and
    # response registers no port shows, the same fence umi_buffer met
    Proof("apb:bmc", "fv_umi2apb", "bmc"),
    Proof("apb:cover", "fv_umi2apb", "cover"),
    # the block header says atomics and RDMA are dropped silently. This
    # row withdraws the opcode assumption and covers what they really do
    Proof("apb:hazard", "fv_umi2apb", "cover", defines=("FV_APB_ANYOP",)),

    # ---- fv_umi2axil --------------------------------------------------
    # AXI4-Lite manager: three channels the block owns, two it does not
    # RESP_RULE_EN 47 = 6'h2F masks RULE3_data_stable (bit 4): the
    # response data field is driven by RDATA even on a write response,
    # which axil:fault_data pins. The other five rules are still proven
    Proof("axil:bmc", "fv_umi2axil", "bmc",
          params=(("RESP_RULE_EN", "47"),)),
    Proof("axil:cover", "fv_umi2axil", "cover"),

    # ---- fv_axil2umi --------------------------------------------------
    # the same AXI4-Lite law set from the subordinate side: this block
    # owns B and R, so those are asserted and AW/W/AR assumed
    Proof("axil2:bmc", "fv_axil2umi", "bmc"),
    Proof("axil2:cover", "fv_axil2umi", "cover"),
    # AWVALID and ARVALID on one edge: both address channels report the
    # same ready, so both are accepted. Witnessed here, pinned below
    Proof("axil2:hazard", "fv_axil2umi", "cover",
          defines=("FV_AXIL2_CONCURRENT",)),

    # ---- fv_axi2umi ---------------------------------------------------
    # full AXI4 subordinate: the burst obligations are the part
    # AXI4-Lite does not have
    Proof("axi:bmc", "fv_axi2umi", "bmc"),
    Proof("axi:cover", "fv_axi2umi", "cover"),
    # the EOM integration condition withdrawn: what a device that
    # miscounts its beats does to the AXI face
    Proof("axi:hazard", "fv_axi2umi", "cover", defines=("FV_AXI_ANYEOM",)),
    # a second read burst accepted while the first is still returning
    Proof("axi:hazard_multi", "fv_axi2umi", "cover", defines=("FV_AXI_MULTI",)),

    # ---- fv_tl2umi ----------------------------------------------------
    # TileLink-UL subordinate: the D channel must carry the source and
    # size of the request it answers, and the opcode that request demands
    Proof("tl:bmc", "fv_tl2umi", "bmc"),
    Proof("tl:cover", "fv_tl2umi", "cover"),

    # ---- fv_umi2tl ----------------------------------------------------
    # the TileLink-UL manager side: the request-shape obligations
    Proof("tlm:bmc", "fv_umi2tl", "bmc"),
    Proof("tlm:cover", "fv_umi2tl", "cover"),

    # ---- fv_umi_address_remap -----------------------------------------
    # purely combinational, so prove closes and quantifies over every
    # input word
    Proof("remap:prove", "fv_umi_address_remap", "prove"),
    Proof("remap:cover", "fv_umi_address_remap", "cover"),
    Proof("remap:hazard", "fv_umi_address_remap", "cover",
          defines=("FV_REMAP_FREECFG",)),

    # ---- fv_umi_data_aggregator ---------------------------------------
    Proof("agg:bmc", "fv_umi_data_aggregator", "bmc"),
    Proof("agg:cover", "fv_umi_data_aggregator", "cover"),

    # ---- configuration matrix -----------------------------------------
    # The harnesses above run one face each, chosen for solve time, and
    # four of them (demux, mux, mux2, crossbar) run AW=16/DW=32 --
    # narrower than README 4.1 permits, which is fine for a routing law
    # but is not a configuration any UMI device ships. These rows
    # re-answer the same questions at widths the specification allows
    # and at the width nine blocks in this repo actually default to, so
    # a truncation that only appears in a wide counter cannot hide
    # behind a narrow proof.
    #
    # Every proof here is paired with a cover row at the SAME face. A
    # proof at a new width can pass for the wrong reason: if widening
    # made some assumption unsatisfiable, every assertion under it holds
    # vacuously and the row goes green while checking nothing. The
    # paired cover is what rules that out -- it must still reach every
    # witness, and the counts are in the folder README.
    Proof("buffer:prove_dw256", "fv_umi_buffer", "prove",
          params=(("DW", "256"),)),
    Proof("buffer:cover_dw256", "fv_umi_buffer", "cover",
          params=(("DW", "256"),)),
    Proof("buffer:prove_aw32", "fv_umi_buffer", "prove",
          params=(("AW", "32"),)),
    Proof("buffer:cover_aw32", "fv_umi_buffer", "cover",
          params=(("AW", "32"),)),
    Proof("demux:prove_legal", "fv_umi_demux", "prove",
          params=(("AW", "64"), ("DW", "64"))),
    Proof("demux:cover_legal", "fv_umi_demux", "cover",
          params=(("AW", "64"), ("DW", "64"))),
    Proof("mux2:prove_legal", "fv_umi_mux2", "prove",
          params=(("AW", "64"), ("DW", "64"))),
    Proof("crossbar:prove_legal", "fv_umi_crossbar", "prove",
          params=(("AW", "64"), ("DW", "64"))),
    # umi_mux runs the same narrow face as its three neighbours above
    # and was left out of the first widening. It answers bmc, not
    # prove, for the reason its harness header gives.
    Proof("mux:bmc_legal", "fv_umi_mux", "bmc",
          params=(("AW", "64"), ("DW", "64"))),
    Proof("mux:cover_legal", "fv_umi_mux", "cover",
          params=(("AW", "64"), ("DW", "64"))),
    Proof("pipeline:prove_dw256", "fv_umi_pipeline", "prove",
          params=(("DW", "256"),)),
    Proof("pipeline:cover_dw256", "fv_umi_pipeline", "cover",
          params=(("DW", "256"),)),
    # AW=32 is the other address width README 4.1 permits, and the one
    # nothing was elaborated at until the buffer rows above
    Proof("mux2:prove_aw32", "fv_umi_mux2", "prove",
          params=(("AW", "32"), ("DW", "64"))),
    Proof("mux2:cover_aw32", "fv_umi_mux2", "cover",
          params=(("AW", "32"), ("DW", "64"))),
    Proof("crossbar:prove_aw32", "fv_umi_crossbar", "prove",
          params=(("AW", "32"), ("DW", "64"))),
    Proof("crossbar:cover_aw32", "fv_umi_crossbar", "cover",
          params=(("AW", "32"), ("DW", "64"))),
    Proof("pipeline:prove_aw32", "fv_umi_pipeline", "prove",
          params=(("AW", "32"),)),
    Proof("pipeline:cover_aw32", "fv_umi_pipeline", "cover",
          params=(("AW", "32"),)),
    Proof("isolate:prove_dw256", "fv_umi_isolate", "prove",
          params=(("DW", "256"),)),
    Proof("isolate:cover_dw256", "fv_umi_isolate", "cover",
          params=(("DW", "256"),)),
    Proof("isolate:prove_aw32", "fv_umi_isolate", "prove",
          params=(("AW", "32"),)),
    Proof("isolate:cover_aw32", "fv_umi_isolate", "cover",
          params=(("AW", "32"),)),
    Proof("regif:prove_dw256", "fv_umi_regif", "prove",
          params=(("DW", "256"),)),
    Proof("regif:cover_dw256", "fv_umi_regif", "cover",
          params=(("DW", "256"),)),
    Proof("monitor:prove_dw256", "fv_umi_monitor", "prove",
          params=(("DW", "256"),)),
    Proof("monitor:cover_dw256", "fv_umi_monitor", "cover",
          params=(("DW", "256"),)),
    # the repo's own RAM testbench instantiates the arbiter at N=5; the
    # proofs above stop at 4, and the thermometer is N-asymmetric
    Proof("mux2:cover_legal", "fv_umi_mux2", "cover",
          params=(("AW", "64"), ("DW", "64"))),
    Proof("crossbar:cover_legal", "fv_umi_crossbar", "cover",
          params=(("AW", "64"), ("DW", "64"))),
    Proof("arbiter:prove_n5", "fv_umi_arbiter", "prove",
          params=(("N", "5"),)),
    Proof("arbiter:cover_n5", "fv_umi_arbiter", "cover",
          params=(("N", "5"),)),
]

FAULTS = [
    # Every expect= below is the label sby actually reported on a run of
    # that row, not a label read off the harness header. Where a fault
    # legitimately breaks several rules on the same beat the extra
    # labels are noted; the row pins the intended one and tolerates the
    # rest, since which extras a solver reports is not guaranteed.

    # ---- fv_umi_codec -------------------------------------------------
    Proof("codec:fault_eom", "fv_umi_codec", "bmc", defines=("FV_FAULT_EOM",),
          expect="FWD_eom"),

    # ---- fv_umi_buffer ------------------------------------------------
    Proof("buffer:fault_valid", "fv_umi_buffer", "bmc", defines=("FV_FAULT_VALID",),
          expect="RULE2_valid_hold"),
    Proof("buffer:fault_data", "fv_umi_buffer", "bmc", defines=("FV_FAULT_DATA",),
          expect="RULE3_data_stable"),
    # a cover that must go unreachable: VALID waiting on READY is
    # exactly the design buffer:rule5 rules out. Both rule5 covers go
    # unreached; the stuck-low one is the direct rule 4.2.5 witness,
    # c_rule5_valid_held is the rule 2 follow-on
    Proof("buffer:fault_rule5", "fv_umi_buffer", "cover",
          defines=("FV_RULE5_READYLOW", "FV_FAULT_RULE5", "FV_NO_WITNESS"),
          expect="c_rule5_valid_stuck_low"),
    Proof("buffer:fault_swap", "fv_umi_buffer", "bmc",
          defines=("FV_IDENTITY", "FV_FAULT_SWAP"),
          params=(("AW", "16"), ("DW", "32")),
          expect="a_id_beat"),
    # the same corruption on the engine the identity rows are proven
    # with: without this, abc pdr answering "proved" to everything would
    # look exactly like a passing lane. expect is None because abc names
    # an AIGER output rather than a label; the row above pins that the
    # corruption convicts a_id_beat and nothing else
    Proof("buffer:fault_swap_pdr", "fv_umi_buffer", "prove",
          defines=("FV_IDENTITY", "FV_FAULT_SWAP"),
          params=(("AW", "16"), ("DW", "32")),
          engine=PDR_ENGINE),
    # the per-rule mask, one bit at a time: the observed output channel is
    # free, so every rule is breakable, and the single enabled bit names
    # which one is reported. Every bit of RULE_EN is load-bearing or one
    # of these rows would pass. The complement is buffer:prove_mask_off,
    # the same free channel with the mask cleared
    Proof("buffer:fault_mask_r2", "fv_umi_buffer", "bmc",
          defines=("FV_FAULT_FREEOUT",), params=(("RULE_EN", "1"),),
          expect="RULE2_valid_hold"),
    Proof("buffer:fault_mask_r3cmd", "fv_umi_buffer", "bmc",
          defines=("FV_FAULT_FREEOUT",), params=(("RULE_EN", "2"),),
          expect="RULE3_cmd_stable"),
    Proof("buffer:fault_mask_r3dst", "fv_umi_buffer", "bmc",
          defines=("FV_FAULT_FREEOUT",), params=(("RULE_EN", "4"),),
          expect="RULE3_dstaddr_stable"),
    Proof("buffer:fault_mask_r3src", "fv_umi_buffer", "bmc",
          defines=("FV_FAULT_FREEOUT",), params=(("RULE_EN", "8"),),
          expect="RULE3_srcaddr_stable"),
    Proof("buffer:fault_mask_r3data", "fv_umi_buffer", "bmc",
          defines=("FV_FAULT_FREEOUT",), params=(("RULE_EN", "16"),),
          expect="RULE3_data_stable"),
    Proof("buffer:fault_mask_reset", "fv_umi_buffer", "bmc",
          defines=("FV_FAULT_FREEOUT",), params=(("RULE_EN", "32"),),
          expect="RESET_valid_low"),

    # ---- fv_umi_pipeline ----------------------------------------------
    Proof("pipeline:fault_valid", "fv_umi_pipeline", "bmc",
          defines=("FV_FAULT_VALID",), expect="RULE2_valid_hold"),
    Proof("pipeline:fault_data", "fv_umi_pipeline", "bmc",
          defines=("FV_FAULT_DATA",), expect="RULE3_data_stable"),
    # the two addresses exchanged: every handshake rule still holds, so
    # only the identity law can see it
    Proof("pipeline:fault_swap", "fv_umi_pipeline", "bmc",
          defines=("FV_IDENTITY", "FV_FAULT_SWAP"), expect="a_pipe_beat"),
    # a beat the stage never accepted: the accounting law catches it
    Proof("pipeline:fault_ghost", "fv_umi_pipeline", "bmc",
          defines=("FV_IDENTITY", "FV_FAULT_GHOST"),
          expect="a_pipe_occupancy"),
    Proof("pipeline:fault_mask_r2", "fv_umi_pipeline", "bmc",
          defines=("FV_FAULT_FREEOUT",), params=(("RULE_EN", "1"),),
          expect="RULE2_valid_hold"),
    Proof("pipeline:fault_mask_r3data", "fv_umi_pipeline", "bmc",
          defines=("FV_FAULT_FREEOUT",), params=(("RULE_EN", "16"),),
          expect="RULE3_data_stable"),

    # ---- fv_umi_decode ------------------------------------------------
    Proof("decode:fault_read", "fv_umi_decode", "bmc",
          defines=("FV_FAULT_READ",), expect="DEC_read"),
    Proof("decode:fault_onehot", "fv_umi_decode", "bmc",
          defines=("FV_FAULT_ONEHOT",), expect="DEC_class_onehot0"),
    Proof("decode:fault_req", "fv_umi_decode", "bmc",
          defines=("FV_FAULT_REQ",), expect="DEC_req_implies"),
    Proof("decode:fault_atomic", "fv_umi_decode", "bmc",
          defines=("FV_FAULT_ATOMIC",), expect="DEC_atomic_onehot0"),

    # ---- fv_umi_isolate -----------------------------------------------
    Proof("isolate:fault_pass", "fv_umi_isolate", "bmc",
          defines=("FV_FAULT_PASS",), expect="a_iso_pass"),
    Proof("isolate:fault_clamp", "fv_umi_isolate", "bmc",
          defines=("FV_FAULT_CLAMP",), expect="a_iso_clamp"),

    # ---- fv_umi_monitor -----------------------------------------------
    Proof("monitor:fault_or", "fv_umi_monitor", "bmc",
          defines=("FV_FAULT_OR",), expect="a_mon_beat"),

    # ---- fv_umi_fifo --------------------------------------------------
    Proof("fifo:fault_valid", "fv_umi_fifo", "bmc",
          defines=("FV_FAULT_VALID",), expect="RULE2_valid_hold"),
    Proof("fifo:fault_data", "fv_umi_fifo", "bmc",
          defines=("FV_FAULT_DATA",), expect="RULE3_data_stable"),
    Proof("fifo:fault_swap", "fv_umi_fifo", "bmc",
          defines=("FV_IDENTITY", "FV_FAULT_SWAP"), params=(("DEPTH", "2"),),
          expect="a_fifo_beat"),
    Proof("fifo:fault_ghost", "fv_umi_fifo", "bmc",
          defines=("FV_IDENTITY", "FV_FAULT_GHOST"), params=(("DEPTH", "2"),),
          expect="a_fifo_no_underflow"),

    # ---- fv_umi_stream ------------------------------------------------
    Proof("stream:fault_valid", "fv_umi_stream", "bmc",
          defines=("FV_FAULT_VALID",), expect="RULE2_valid_hold"),
    Proof("stream:fault_data", "fv_umi_stream", "bmc",
          defines=("FV_FAULT_DATA",), expect="RULE3_data_stable"),
    Proof("stream:fault_usi_hold", "fv_umi_stream", "bmc",
          defines=("FV_FAULT_USI_HOLD",), expect="a_usi_out_hold"),
    Proof("stream:fault_usi_stable", "fv_umi_stream", "bmc",
          defines=("FV_FAULT_USI_STABLE",), expect="a_usi_out_stable"),

    # ---- fv_umi_memif -------------------------------------------------
    # each fault is confined to one ATYPE so it can convict only its
    # own law
    Proof("memif:fault_add", "fv_umi_memif", "bmc",
          defines=("FV_FAULT_ADD",), expect="a_alu_add"),
    Proof("memif:fault_smax", "fv_umi_memif", "bmc",
          defines=("FV_FAULT_SMAX",), expect="a_alu_smax"),
    Proof("memif:fault_swap", "fv_umi_memif", "bmc",
          defines=("FV_FAULT_SWAP",), expect="a_alu_swap"),
    Proof("memif:fault_default", "fv_umi_memif", "bmc",
          defines=("FV_FAULT_DEFAULT",), expect="a_alu_default"),

    # ---- fv_umi_regif -------------------------------------------------
    Proof("regif:fault_valid", "fv_umi_regif", "bmc",
          defines=("FV_FAULT_VALID",), expect="RULE2_valid_hold"),
    # the xor swaps the two response opcodes, so either half of the
    # kind law can catch it; the solver reaches the write side first
    Proof("regif:fault_kind", "fv_umi_regif", "bmc",
          defines=("FV_FAULT_KIND",), expect="a_regif_kind_wr"),
    Proof("regif:fault_posted", "fv_umi_regif", "bmc",
          defines=("FV_FAULT_POSTED",), expect="a_regif_no_invent"),
    # nothing injected: SAFE=1 is the shipped default, and it breaks the
    # accounting law on its own. Pinned so the finding cannot regress
    # into silence
    Proof("regif:fault_safe", "fv_umi_regif", "bmc",
          defines=("FV_REGIF_NOCHK",), params=(("SAFE", "1"),),
          expect="a_regif_outstanding"),

    # ---- fv_umi_endpoint ----------------------------------------------
    Proof("endpoint:fault_valid", "fv_umi_endpoint", "bmc",
          defines=("FV_FAULT_VALID",), expect="RULE2_valid_hold"),
    Proof("endpoint:fault_kind", "fv_umi_endpoint", "bmc",
          defines=("FV_FAULT_KIND",), expect="a_ep_kind_wr"),
    Proof("endpoint:fault_da", "fv_umi_endpoint", "bmc",
          defines=("FV_FAULT_DA",), expect="a_ep_da"),
    Proof("endpoint:fault_posted", "fv_umi_endpoint", "bmc",
          defines=("FV_FAULT_POSTED",), expect="a_ep_outstanding"),
    # nothing injected: the REG=1 arm really can hold two answers, so
    # the REG=0 accounting law must fail there
    Proof("endpoint:fault_cap", "fv_umi_endpoint", "bmc",
          defines=("FV_EP_EXACT",), params=(("REG", "1"),),
          expect="a_ep_outstanding"),

    # ---- fv_umi_ram ---------------------------------------------------
    Proof("ram:fault_route", "fv_umi_ram", "bmc",
          defines=("FV_RAM_NOCHK", "FV_FAULT_ROUTE"), expect="a_ram_route"),
    # nothing injected: with the response checker in place the shipped
    # block moves its broadcast response address while an answer is
    # standing unaccepted. Pinned so the finding cannot regress
    Proof("ram:fault_stable", "fv_umi_ram", "bmc",
          expect="RULE3_dstaddr_stable"),

    # ---- fv_umi_fifoflex ----------------------------------------------
    Proof("fifoflex:fault_valid", "fv_umi_fifoflex", "bmc",
          defines=("FV_FAULT_VALID",), expect="RULE2_valid_hold"),
    Proof("fifoflex:fault_invent", "fv_umi_fifoflex", "bmc",
          defines=("FV_FAULT_INVENT",), expect="a_flex_conserve"),
    # nothing injected: with SPLIT=1 the block delivers bytes it was
    # never given. umi_memagent instantiates it exactly this way
    Proof("fifoflex:fault_split", "fv_umi_fifoflex", "bmc",
          params=(("SPLIT", "1"),), expect="a_flex_conserve"),

    # ---- fv_umi_switch ------------------------------------------------
    Proof("switch:fault_valid", "fv_umi_switch", "bmc",
          defines=("FV_FAULT_VALID",), expect="RULE2_valid_hold"),

    # ---- fv_umi_demux -------------------------------------------------
    Proof("demux:fault_valid", "fv_umi_demux", "bmc", defines=("FV_FAULT_VALID",),
          expect="a_dx_valid_eq"),
    Proof("demux:fault_bcast", "fv_umi_demux", "bmc", defines=("FV_FAULT_BCAST",),
          expect="a_dx_bcast_data"),
    # the two select assumptions weakened one direction each, so the
    # assumption is falsifiable rather than trusted
    Proof("demux:fault_drop", "fv_umi_demux", "bmc", defines=("FV_SEL_ALLOW_ZERO",),
          expect="a_dx_fork_xfer"),
    Proof("demux:fault_dup", "fv_umi_demux", "bmc", defines=("FV_SEL_MULTIHOT",),
          expect="a_dx_fork_one"),
    Proof("demux:fault_r5", "fv_umi_demux", "bmc", defines=("FV_FAULT_R5",),
          expect="a_dx_r5_indep"),
    # as buffer:fault_rule5: both rule5 covers go unreached here too
    Proof("demux:fault_rule5", "fv_umi_demux", "cover",
          defines=("FV_RULE5_READYLOW", "FV_FAULT_RULE5", "FV_NO_WITNESS"),
          expect="c_rule5_valid_stuck_low"),

    # ---- fv_umi_arbiter -----------------------------------------------
    Proof("arbiter:fault_onehot", "fv_umi_arbiter", "bmc", defines=("FV_FAULT_ONEHOT",),
          expect="a_arb_onehot0"),
    Proof("arbiter:fault_subset", "fv_umi_arbiter", "bmc", defines=("FV_FAULT_SUBSET",),
          expect="a_arb_subset"),
    Proof("arbiter:fault_mask", "fv_umi_arbiter", "bmc", defines=("FV_FAULT_MASK",),
          expect="a_arb_nomask"),
    # the rotation witness with the thermometer inert: c_arb_rotate holds
    # the request pattern still, so with priority pinned it cannot be
    # reached. Also reports c_arb_hold, unreachable for the same reason
    Proof("arbiter:fault_rotate", "fv_umi_arbiter", "cover",
          defines=("FV_MODE_RR", "FV_FAULT_ROTATE"),
          expect="c_arb_rotate"),

    # ---- fv_umi_cmd ---------------------------------------------------
    Proof("cmd:fault_opcode", "fv_umi_cmd", "bmc", defines=("FV_FAULT_OPCODE",),
          expect="CMD1_opcode_legal"),
    Proof("cmd:fault_atype", "fv_umi_cmd", "bmc", defines=("FV_FAULT_ATYPE",),
          expect="CMD2_atype_legal"),
    Proof("cmd:fault_align_da", "fv_umi_cmd", "bmc", defines=("FV_FAULT_ALIGN_DA",),
          expect="CMD4_da_aligned"),
    Proof("cmd:fault_align_sa", "fv_umi_cmd", "bmc", defines=("FV_FAULT_ALIGN_SA",),
          expect="CMD4_sa_aligned"),
    # also trips CMD1_opcode_legal: a full-byte aliasing error is by
    # construction outside the CMD-1 legal-opcode set
    Proof("cmd:fault_fullbyte", "fv_umi_cmd", "bmc", defines=("FV_FAULT_FULLBYTE",),
          expect="CMD10_fullbyte_decode"),
    Proof("cmd:fault_ex", "fv_umi_cmd", "bmc", defines=("FV_FAULT_EX",),
          expect="CMD11_ex_zero"),
    # also trips CMD10_fullbyte_decode and CMD1_opcode_legal
    Proof("cmd:fault_errsize", "fv_umi_cmd", "bmc", defines=("FV_FAULT_ERRSIZE",),
          expect="CMD12_error_size"),
    Proof("cmd:fault_cap", "fv_umi_cmd", "bmc", defines=("FV_FAULT_CAP",),
          expect="CMD15_beat_capacity"),
    Proof("cmd:fault_respdata", "fv_umi_cmd", "bmc", defines=("FV_FAULT_RESPDATA",),
          expect="CMD16_err_data_zero"),
    Proof("cmd:fault_sa_reserved", "fv_umi_cmd", "bmc",
          defines=("FV_FAULT_SA_RESERVED",), params=(("CHECK_SA_RESERVED", "1"),),
          expect="CMD6_sa_reserved"),
    Proof("cmd:fault_invalid", "fv_umi_cmd", "bmc", defines=("FV_FAULT_INVALID",),
          expect="CMD1_opcode_legal"),

    # ---- fv_umi_frame -------------------------------------------------
    # one row per rule, each bending exactly that rule on the observed
    # channel while the driving channel stays legal
    Proof("frame:fault_size", "fv_umi_frame", "bmc",
          defines=("FV_FAULT_SIZE",), expect="FRAME_size_stable"),
    Proof("frame:fault_opcode", "fv_umi_frame", "bmc",
          defines=("FV_FAULT_OPCODE",), expect="FRAME_opcode_stable"),
    Proof("frame:fault_fields", "fv_umi_frame", "bmc",
          defines=("FV_FAULT_FIELDS",), expect="FRAME_fields_stable"),
    Proof("frame:fault_da", "fv_umi_frame", "bmc",
          defines=("FV_FAULT_DA",), expect="FRAME_da_cont"),
    Proof("frame:fault_sa", "fv_umi_frame", "bmc",
          defines=("FV_FAULT_SA",), expect="FRAME_sa_cont"),
    # a message that never closes runs past the ceiling; lowered so the
    # boundary is reachable inside the bounded depth
    Proof("frame:fault_bytes", "fv_umi_frame", "bmc", depth=14,
          defines=("FV_FAULT_BYTES",), expect="FRAME_msgbytes"),
    # the mask is falsifiable: only bit 3 enabled, so FRAME_da_cont alone
    Proof("frame:fault_mask_da", "fv_umi_frame", "bmc",
          defines=("FV_FAULT_FREEOUT",), params=(("RULE_EN", "8"),),
          expect="FRAME_da_cont"),

    # ---- fv_umi_txn ---------------------------------------------------
    Proof("txn:fault_wrongda", "fv_umi_txn", "bmc", defines=("FV_FAULT_WRONGDA",),
          expect="TXN_da_first"),
    # one SIZE flip corrupts the byte-count arithmetic TXN_size and
    # TXN_eom_iff_closed share, so both fail together
    Proof("txn:fault_size", "fv_umi_txn", "bmc", defines=("FV_FAULT_SIZE",),
          expect="TXN_size"),
    Proof("txn:fault_eom_early", "fv_umi_txn", "bmc", defines=("FV_FAULT_EOM_EARLY",),
          expect="TXN_eom_iff_closed"),
    # the drop is restricted to non-error beats so the closing-beat law
    # is what convicts; dropping an error beat's EOM would convict the
    # error-single-beat law instead
    Proof("txn:fault_eom_missing", "fv_umi_txn", "bmc",
          defines=("FV_FAULT_EOM_MISSING",),
          expect="TXN_eom_iff_closed"),
    # a message longer than the harness ceiling the checker is told to
    # enforce
    Proof("txn:fault_msgbytes", "fv_umi_txn", "bmc", depth=24,
          defines=("FV_BIGMSG",), params=(("MAX_MSG_BYTES", "64"),),
          expect="TXN_msgbytes"),
    Proof("txn:fault_err_len", "fv_umi_txn", "bmc", defines=("FV_FAULT_ERR_LEN",),
          expect="TXN_err_len"),
    Proof("txn:fault_orphan", "fv_umi_txn", "bmc", defines=("FV_FAULT_ORPHAN",),
          expect="TXN_p5_outstanding"),
    # no define: the responder is simply allowed one more outstanding
    # request than the checker's capacity admits
    Proof("txn:fault_occ", "fv_umi_txn", "bmc", params=(("CAP", "1"),),
          expect="TXN_occ_bound"),

    # ---- fv_umi_mux ---------------------------------------------------
    Proof("mux:fault_dup", "fv_umi_mux", "bmc", defines=("FV_FAULT_DUP",),
          expect="a_mux_acc_onehot0"),
    Proof("mux:fault_teleport", "fv_umi_mux", "bmc", defines=("FV_FAULT_TELEPORT",),
          expect="a_mux_cnt_eq"),
    Proof("mux:fault_blend", "fv_umi_mux", "bmc", defines=("FV_FAULT_BLEND",),
          expect="a_mux_route_cmd"),

    # ---- fv_umi_mux2 --------------------------------------------------
    Proof("mux2:fault_route", "fv_umi_mux2", "bmc", defines=("FV_FAULT_ROUTE",),
          expect="a_mux2_route_cmd"),
    Proof("mux2:fault_teleport", "fv_umi_mux2", "bmc", defines=("FV_FAULT_TELEPORT",),
          expect="a_mux2_xfer_agg"),
    Proof("mux2:fault_spill", "fv_umi_mux2", "bmc", defines=("FV_FAULT_SPILL",),
          expect="a_mux2_unsel_quiet"),
    Proof("mux2:fault_stall", "fv_umi_mux2", "bmc", defines=("FV_FAULT_STALL",),
          expect="a_mux2_hold_valid"),
    Proof("mux2:fault_r5", "fv_umi_mux2", "bmc", defines=("FV_FAULT_R5",),
          expect="a_mux2_r5_valid_indep"),

    # ---- fv_umi_crossbar ----------------------------------------------
    Proof("crossbar:fault_dup", "fv_umi_crossbar", "bmc", defines=("FV_FAULT_DUP",),
          expect="a_xb_dlv_onehot0"),
    Proof("crossbar:fault_drop", "fv_umi_crossbar", "bmc", defines=("FV_FAULT_DROP",),
          expect="a_xb_dlv_acc"),
    Proof("crossbar:fault_ghost", "fv_umi_crossbar", "bmc", defines=("FV_FAULT_GHOST",),
          expect="a_xb_valid_req"),
    Proof("crossbar:fault_starve", "fv_umi_crossbar", "bmc",
          defines=("FV_FAULT_STARVE",),
          expect="a_xb_conserve"),
    Proof("crossbar:fault_blend", "fv_umi_crossbar", "bmc", defines=("FV_FAULT_BLEND",),
          expect="a_xb_route_cmd"),

    # ---- fv_umi2apb ---------------------------------------------------
    Proof("apb:fault_enable", "fv_umi2apb", "bmc", defines=("FV_FAULT_ENABLE",),
          expect="APB2_setup_to_access"),
    Proof("apb:fault_stable", "fv_umi2apb", "bmc", defines=("FV_FAULT_STABLE",),
          expect="APB4_payload_stable"),
    Proof("apb:fault_kind", "fv_umi2apb", "bmc", defines=("FV_FAULT_KIND",),
          expect="a_apb_kind"),
    Proof("apb:fault_posted", "fv_umi2apb", "bmc", defines=("FV_FAULT_POSTED",),
          expect="a_apb_posted_quiet"),
    # Nothing is injected here. The block header says atomics and RDMA
    # are dropped silently; they are not, and this row pins that
    Proof("apb:fault_drop", "fv_umi2apb", "bmc",
          defines=("FV_APB_ANYOP", "FV_APB_ASSERT_DROP"),
          expect="a_apb_unsupported_dropped"),

    # ---- fv_umi2axil --------------------------------------------------
    Proof("axil:fault_aw", "fv_umi2axil", "bmc", defines=("FV_FAULT_AW",),
          expect="AXIL_aw_hold"),
    Proof("axil:fault_w", "fv_umi2axil", "bmc", defines=("FV_FAULT_W",),
          expect="AXIL_w_stable"),
    Proof("axil:fault_ar", "fv_umi2axil", "bmc", defines=("FV_FAULT_AR",),
          expect="AXIL_ar_hold"),
    Proof("axil:fault_kind", "fv_umi2axil", "bmc", defines=("FV_FAULT_KIND",),
          expect="a_axil_kind"),
    # Nothing is injected here. The byte-lane shift amount is computed at
    # the width of a 3-bit signal and is therefore always zero
    Proof("axil:fault_lane", "fv_umi2axil", "bmc",
          defines=("FV_AXIL_ASSERT_LANE",), expect="a_axil_wdata_lane"),
    # Nothing injected: with the full rule set the response data field
    # moves under a standing offer on a write response
    Proof("axil:fault_data", "fv_umi2axil", "bmc",
          expect="RULE3_data_stable"),

    # ---- fv_axil2umi --------------------------------------------------
    Proof("axil2:fault_b", "fv_axil2umi", "bmc", defines=("FV_FAULT_B",),
          expect="AXIL_b_hold"),
    Proof("axil2:fault_r", "fv_axil2umi", "bmc", defines=("FV_FAULT_R",),
          expect="AXIL_r_stable"),
    Proof("axil2:fault_kind", "fv_axil2umi", "bmc", defines=("FV_FAULT_KIND",),
          expect="a_axil2_kind"),
    Proof("axil2:fault_inflight", "fv_axil2umi", "bmc",
          defines=("FV_FAULT_INFLIGHT",), expect="a_axil2_one_inflight"),
    # Nothing injected. With a concurrent read and write accepted, the
    # response steering drains the UMI answer on BREADY and RVALID falls
    # without RREADY
    Proof("axil2:fault_concurrent", "fv_axil2umi", "bmc",
          defines=("FV_AXIL2_CONCURRENT",), expect="AXIL_r_hold"),

    # ---- fv_axi2umi ---------------------------------------------------
    Proof("axi:fault_r", "fv_axi2umi", "bmc", defines=("FV_FAULT_R",),
          expect="AXI_r_data"),
    Proof("axi:fault_rid", "fv_axi2umi", "bmc", defines=("FV_FAULT_RID",),
          expect="AXI_rid_match"),
    Proof("axi:fault_b", "fv_axi2umi", "bmc", defines=("FV_FAULT_B",),
          expect="AXI_b_hold"),
    # Nothing injected. The block copies the device's EOM straight to
    # RLAST, so a device that miscounts breaks AXI at this output
    Proof("axi:fault_burst", "fv_axi2umi", "bmc", defines=("FV_AXI_ANYEOM",),
          expect="AXI_rlast_count"),
    # Nothing injected. One ar_id register, no gating on arready, so a
    # second burst overwrites RID while the first is still standing
    Proof("axi:fault_multi", "fv_axi2umi", "bmc", defines=("FV_AXI_MULTI",),
          expect="AXI_r_id"),

    # ---- fv_tl2umi ----------------------------------------------------
    Proof("tl:fault_d", "fv_tl2umi", "bmc", defines=("FV_FAULT_D",),
          expect="a_tl_d_stable"),
    Proof("tl:fault_hold", "fv_tl2umi", "bmc", defines=("FV_FAULT_HOLD",),
          expect="a_tl_d_hold"),
    Proof("tl:fault_opcode", "fv_tl2umi", "bmc", defines=("FV_FAULT_OPCODE",),
          expect="TL_d_opcode_legal"),

    # ---- fv_umi2tl ----------------------------------------------------
    Proof("tlm:fault_a", "fv_umi2tl", "bmc", defines=("FV_FAULT_A",),
          expect="a_tlm_a_hold"),
    Proof("tlm:fault_stable", "fv_umi2tl", "bmc", defines=("FV_FAULT_STABLE",),
          expect="a_tlm_a_stable"),
    # Nothing injected. A one-byte request becomes a TileLink request
    # with size 1 (two bytes) and a one-lane mask
    Proof("tlm:fault_mask", "fv_umi2tl", "bmc",
          defines=("FV_TLM_ASSERT_MASK",), expect="TL_a_mask_size"),

    # ---- fv_umi_address_remap -----------------------------------------
    Proof("remap:fault_local", "fv_umi_address_remap", "bmc",
          defines=("FV_FAULT_LOCAL",), expect="a_remap_local"),
    Proof("remap:fault_carry", "fv_umi_address_remap", "bmc",
          defines=("FV_FAULT_CARRY",), expect="a_remap_carry"),
    # Nothing injected: the configuration pins move, and DSTADDR is a
    # combinational function of them
    Proof("remap:fault_cfg", "fv_umi_address_remap", "bmc",
          defines=("FV_REMAP_FREECFG",), expect="RULE3_dstaddr_stable"),

    # ---- fv_umi_data_aggregator ---------------------------------------
    Proof("agg:fault_addr", "fv_umi_data_aggregator", "bmc",
          defines=("FV_FAULT_ADDR",), expect="a_agg_addr_first"),
    Proof("agg:fault_data", "fv_umi_data_aggregator", "bmc",
          defines=("FV_FAULT_DATA",), expect="RULE3_data_stable"),
]


def _harness(proof):
    """The proof's Design: harness on top, repo blocks as deps."""
    design = Design(proof.family)
    root = FAMILIES[proof.family].get("root", FORMAL_SUMI)
    design.set_dataroot(f"umi_formal_{root.name}", str(root))
    with design.active_fileset("rtl"):
        design.set_topmodule(proof.family)
        design.add_file(f"{proof.family}.sv")
        design.add_idir(str(SUMI_INCLUDE))
        for dep in FAMILIES[proof.family]["deps"]():
            design.add_depfileset(dep, "rtl")
        for define in (tuple(FAMILIES[proof.family].get("defines", ()))
                       + proof.defines):
            design.add_define(define)
        for name, value in proof.params:
            design.set_param(name, value)
    return design


def _project(proof, builddir):
    proj = Project(_harness(proof))
    proj.add_fileset("rtl")
    if proof.engine == PDR_ENGINE:
        # PropertyCheckFlow maps prove to the stock ProveTask, so the
        # pdr rows need their node built by hand
        flow = Flowgraph(f"formal_{proof.mode}_pdr")
        flow.node(proof.mode, PdrProveTask())
    else:
        flow = PropertyCheckFlow(f"formal_{proof.mode}", modes=_MODES[proof.mode])
    proj.set_flow(flow)
    proj.option.set_builddir(str(builddir))
    proj.option.set_timeout(FAMILIES[proof.family]["timeout"])
    # gate on the proof, not the tool version string: OSS CAD Suite sby
    # builds answer --version with git-describe strings PEP-440 cannot
    # parse, e.g. "SBY v0.67-4-gfea6e46"
    proj.option.set_novercheck(True)
    task = SBYTask.find_task(proj)
    task.set_sby_depth(proof.depth)
    if proof.engine != PDR_ENGINE:
        task.add_sby_engine(proof.engine, clobber=True)
    return proj


@pytest.mark.parametrize("proof", GREEN, ids=[p.tid for p in GREEN])
def test_sc_proof(proof, tmp_path):
    proj = _project(proof, tmp_path)
    hist = proj.run()
    assert hist.get("metric", "errors", step=proof.mode, index="0") == 0


@pytest.mark.parametrize("proof", FAULTS, ids=[p.tid for p in FAULTS])
def test_sc_fault_must_fail(proof, tmp_path):
    """With the fault injected the node must fail the run (the match
    pins the failure to the proof node, not tool setup), sby's own
    verdict must be FAIL -- a counterexample, not an ERROR -- and the
    label sby blames must be the one the fault was built to trip. FAIL
    alone would let a fault convict some unrelated rule and still be
    counted as a catch."""
    proj = _project(proof, tmp_path)
    with pytest.raises(RuntimeError, match=proof.mode):
        proj.run()
    node = tmp_path / proof.family / "job0" / proof.mode / "0" / "sby"
    status = (node / "status").read_text()
    assert status.startswith("FAIL"), status
    log = (node / "logfile.txt").read_text()
    if proof.expect is None:
        # the abc pdr rows: no label to check, so pin the verdict to the
        # engine itself -- a setup failure reports no engine verdict
        assert f"engine_0 ({proof.engine}) returned FAIL" in log, log[-2000:]
        return
    labels = _failed_labels(log)
    assert proof.expect in labels, (
        f"{proof.tid}: expected {proof.expect}, sby blamed {sorted(labels)}")
