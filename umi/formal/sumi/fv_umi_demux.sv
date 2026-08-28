/*******************************************************************************
 * Copyright 2026 Zero ASIC Corporation
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 * ----
 *
 * Documentation:
 *
 * Formal harness: umi_demux routing and fork laws, and every output
 * channel checked as legal SUMI by the shipped handshake checker.
 *
 * umi_demux is purely combinational -- no clk, no nreset port
 * (umi_demux.v:28-51). The harness supplies a clock only to host the
 * named immediate assertions. Its whole behaviour is three equations:
 *
 *     umi_out_valid = {M{umi_in_valid}} & select        (umi_demux.v:54)
 *     umi_in_ready  = &(~select | umi_out_ready)        (umi_demux.v:57)
 *     umi_out_<f>   = {M{umi_in_<f>}}                   (umi_demux.v:60-63)
 *
 * THREE FACES.
 *
 * 1. UNCONDITIONAL theorems -- no environment assumptions at all:
 *      a_dx_valid_eq    an output offers a beat exactly when the input
 *                       offers one AND that output is selected.
 *      a_dx_quiet       an unselected output never sees a beat.
 *      a_dx_bcast_*     every output carries the input beat verbatim in
 *                       all four SUMI fields -- cross-talk between output
 *                       ports is structurally impossible and stays so.
 *    These are written as whole-vector equalities against the M-fold
 *    replication (the form the RTL itself uses): a per-port assertion in
 *    a procedural loop emits M cells with one label, which yosys rejects.
 *
 * 2. CONTRACT under an audited environment. The input channel is
 *    constrained legal by umi_handshake_checker (ASSUME=1) and the fabric
 *    is assumed to drive exactly one destination per live beat
 *    (m_dx_sel_onehot) and to hold SELECT while the input is stalled
 *    (m_dx_sel_stable -- SELECT is part of the offer). Then EVERY output
 *    channel is asserted legal SUMI by an ASSUME=0 instance of the same
 *    checker, and the fork laws hold:
 *      a_dx_fork_xfer   one accepted input beat <=> one delivered beat.
 *      a_dx_fork_one    never two deliveries for one accept.
 *
 * 3. README 4.2 rule 5 (README.md:462) -- "the assertion of VALID must
 *    not depend on the assertion of READY" -- in two independent forms:
 *      c_rule5_valid_stuck_low / c_rule5_valid_held (`rule5` task):
 *        out_ready is pinned 0 for the whole trace and out_valid is
 *        covered asserting, and holding. Reaching them is the literal
 *        negation of "VALID waits for READY" (the fv_umi_buffer method).
 *      a_dx_r5_indep: the dual obligation on a combinational block is
 *        that in_ready must not depend on in_valid. Proven by SELF-
 *        COMPOSITION -- a twin instance sees identical select/out_ready
 *        but an INDEPENDENT input beat, and the two in_ready outputs must
 *        agree. Any path from in_valid to in_ready separates them.
 *        umi_demux passes both: a positive structural result.
 *
 * WHAT THE ENVIRONMENT IS BUYING. The onehot-select
 * assumption is not decoration -- it is the boundary of correct usage,
 * and the `hazard` task demonstrates exactly what lies outside it by
 * dropping the assumption and covering the two real behaviours:
 *   c_dx_drop   select==0 makes in_ready = &(~0 | out_ready) = 1, so an
 *               offered beat is ACCEPTED and goes nowhere. A demux with
 *               no output selected silently drops traffic; it does not
 *               stall and does not error.
 *   c_dx_dup    a multi-hot select with every selected output ready
 *               DELIVERS the beat to two or more outputs against the
 *               single accept the upstream sees -- the duplication. The
 *               cover says exactly that: in_xfer AND two or more
 *               out_xfer bits.
 *   c_dx_noaccept  the other half of a multi-hot select: only some of the
 *               selected outputs are ready, so a beat is DELIVERED while
 *               in_ready stays low. The upstream never sees an accept and
 *               offers the same beat again, which duplicates it in time
 *               rather than in space.
 * The fault_drop / fault_dup rows then WEAKEN the assumption and show
 * the fork laws convicting -- the assumption is auditable, not asserted.
 *
 * Fault rows corrupt only what the harness OBSERVES, never the DUT. A
 * checker that cannot fail a broken design proves nothing about a
 * working one.
 *
 * ROWS (tests/test_formal_sc.py):
 *   demux:prove       M=2, unbounded
 *   demux:prove_m4    M=4, unbounded
 *   demux:cover       witnesses: expect all reached
 *   demux:rule5       rule 4.2.5 witness (face 3 above)
 *   demux:hazard      the fork hazards, assumption dropped
 *   demux:fault_*     must FAIL, labels below
 *
 * Fault rows and the assertion label each is intended to trip. A fault
 * may falsify several related rules on the same cycle and which label
 * BMC reports can be solver-dependent; the INTENDED label is the one
 * guaranteed to appear in the log's failed-assertion list:
 *   fault_valid   a_dx_valid_eq    an observed output valid is dropped.
 *                                  Also trips the output handshake
 *                                  checker's RULE2_valid_hold when the
 *                                  counterexample drops a held VALID --
 *                                  legal here and NOT a regression.
 *   fault_bcast   a_dx_bcast_data  an output's data no longer equals the
 *                                  input's.
 *   fault_drop    a_dx_fork_xfer   env weakened to $onehot0: select==0 is
 *                                  now permitted, so an accepted beat is
 *                                  delivered nowhere (the silent drop).
 *   fault_dup     a_dx_fork_one    env weakened the other way: at least TWO
 *                                  destinations AND every output ready, so
 *                                  one accept is delivered to several outputs
 *                                  (the duplication). BOTH halves of that env
 *                                  are load-bearing -- multi-hot select alone
 *                                  still lets a partial ready deliver without
 *                                  an accept, which convicts a_dx_fork_xfer
 *                                  instead. Pinning ready high forces the
 *                                  accept so only the one-accept-one-delivery
 *                                  law can break. Removing the assumption
 *                                  entirely admits both hazards and lets the
 *                                  solver pick -- that unconstrained case is
 *                                  the `hazard` row, whose job is to cover
 *                                  both.
 *   fault_r5      a_dx_r5_indep    models the illegal design in which
 *                                  ready waits for valid; the self-
 *                                  composition miter separates.
 *   fault_rule5   (covers)         models the illegal design in which
 *                                  VALID waits for READY; under stuck-low
 *                                  ready c_rule5_valid_stuck_low and
 *                                  c_rule5_valid_held go UNREACHED.
 *
 * The rule5 / fault_rule5 rows carry FV_NO_WITNESS so the handshake
 * checkers' own transaction covers, unreachable under stuck-low ready,
 * do not spuriously fail the cover run.
 ******************************************************************************/

`default_nettype none

module fv_umi_demux #(
    parameter M  = 2,               // number of output ports
    parameter CW = 32,              // command width
    parameter AW = 16,              // address width
    parameter DW = 32               // data width (routing laws are DW-agnostic)
) (
    input wire clk
);

    // ----------------------------------------------------------------
    // reset: free, but asserted at time zero (grounds all history).
    // The DUT is combinational; nreset exists only for the checkers.
    // ----------------------------------------------------------------
    (* anyseq *) wire nreset;
    reg f_past_exists = 1'b0;
    always @(posedge clk)
        f_past_exists <= 1'b1;
    always @(*)
        if (!f_past_exists)
            assume (!nreset);

    // ----------------------------------------------------------------
    // free stimulus
    // ----------------------------------------------------------------
    (* anyseq *) wire [M-1:0]    select;
    (* anyseq *) wire            umi_in_valid;
    (* anyseq *) wire [CW-1:0]   umi_in_cmd;
    (* anyseq *) wire [AW-1:0]   umi_in_dstaddr;
    (* anyseq *) wire [AW-1:0]   umi_in_srcaddr;
    (* anyseq *) wire [DW-1:0]   umi_in_data;
    (* anyseq *) wire [M-1:0]    umi_out_ready_free;

`ifdef FV_RULE5_READYLOW
    // pin the downstream ready low for the entire trace
    wire [M-1:0] umi_out_ready = {M{1'b0}};
`else
    wire [M-1:0] umi_out_ready = umi_out_ready_free;
`endif

    wire            umi_in_ready;
    wire [M-1:0]    umi_out_valid;
    wire [M*CW-1:0] umi_out_cmd;
    wire [M*AW-1:0] umi_out_dstaddr;
    wire [M*AW-1:0] umi_out_srcaddr;
    wire [M*DW-1:0] umi_out_data;

    // ----------------------------------------------------------------
    // the design under test, exactly as shipped
    // ----------------------------------------------------------------
    umi_demux #(.M(M), .DW(DW), .CW(CW), .AW(AW)) dut (
        .select          (select),
        .umi_in_valid    (umi_in_valid),
        .umi_in_cmd      (umi_in_cmd),
        .umi_in_dstaddr  (umi_in_dstaddr),
        .umi_in_srcaddr  (umi_in_srcaddr),
        .umi_in_data     (umi_in_data),
        .umi_in_ready    (umi_in_ready),
        .umi_out_valid   (umi_out_valid),
        .umi_out_cmd     (umi_out_cmd),
        .umi_out_dstaddr (umi_out_dstaddr),
        .umi_out_srcaddr (umi_out_srcaddr),
        .umi_out_data    (umi_out_data),
        .umi_out_ready   (umi_out_ready));

    // ----------------------------------------------------------------
    // fault injection (formal known-answer tests -- one define per
    // fault row; the header tabulates the label each is intended to trip)
    // ----------------------------------------------------------------
`ifdef FV_FAULT_VALID
    // the solver may drop an observed output valid at any moment
    (* anyseq *) wire [M-1:0] fault;
    wire [M-1:0] obs_out_valid = umi_out_valid & ~fault;
`else
    wire [M-1:0] obs_out_valid = umi_out_valid;
`endif

`ifdef FV_FAULT_BCAST
    // the solver may flip an observed data lsb at any moment
    (* anyseq *) wire fault;
    wire [M*DW-1:0] obs_out_data = umi_out_data ^ {{(M*DW-1){1'b0}}, fault};
`else
    wire [M*DW-1:0] obs_out_data = umi_out_data;
`endif

    // ----------------------------------------------------------------
    // Face 1: unconditional theorems (no environment assumptions)
    // ----------------------------------------------------------------
    always @(posedge clk) begin
        a_dx_valid_eq : assert (obs_out_valid == ({M{umi_in_valid}} & select));
        a_dx_quiet : assert ((obs_out_valid & ~select) == {M{1'b0}});
        a_dx_bcast_cmd  : assert (umi_out_cmd     == {M{umi_in_cmd}});
        a_dx_bcast_dst  : assert (umi_out_dstaddr == {M{umi_in_dstaddr}});
        a_dx_bcast_src  : assert (umi_out_srcaddr == {M{umi_in_srcaddr}});
        a_dx_bcast_data : assert (obs_out_data    == {M{umi_in_data}});
    end

    // ----------------------------------------------------------------
    // Face 2: the audited environment
    // ----------------------------------------------------------------
    reg past_nreset   = 1'b0;
    reg prev_in_valid = 1'b0;
    reg prev_in_ready = 1'b0;
    reg [M-1:0] prev_select;
    always @(posedge clk) begin
        past_nreset   <= nreset;
        prev_in_valid <= nreset & umi_in_valid;
        prev_in_ready <= umi_in_ready;
        prev_select   <= select;
    end
    wire fv_active = f_past_exists & nreset & past_nreset;

    umi_handshake_checker #(
        .CW (CW), .AW (AW), .DW (DW),
        .ASSUME (1)                       // environment: assume legal input
    ) env_in (
        .clk     (clk),
        .nreset  (nreset),
        .valid   (umi_in_valid),
        .ready   (umi_in_ready),
        .cmd     (umi_in_cmd),
        .dstaddr (umi_in_dstaddr),
        .srcaddr (umi_in_srcaddr),
        .data    (umi_in_data));

`ifdef FORMAL
    always @(posedge clk) begin
        if (f_past_exists & nreset) begin
`ifdef FV_SEL_ALLOW_ZERO
            // weakened one way: at most one destination -- zero permitted.
            // Only the DROP hazard is reachable, so fault_drop convicts
            // a_dx_fork_xfer and nothing else.
            m_dx_sel_onehot0 : assume (!umi_in_valid || $onehot0(select));
`elsif FV_SEL_MULTIHOT
            // weakened the other way: at least TWO destinations, AND every
            // output ready. Both halves are needed to isolate a_dx_fork_one:
            // multi-hot select alone still lets a PARTIAL ready deliver to
            // one output while the input never accepts, which convicts
            // a_dx_fork_xfer instead (observed). Pinning ready high forces
            // the accept, so the only law that can break is "one accept,
            // one delivery".
            m_dx_sel_multi  : assume (!umi_in_valid || !$onehot0(select));
            m_dx_all_ready  : assume (umi_out_ready == {M{1'b1}});
`elsif FV_NO_SEL_ASSUME
            // no constraint at all -- the `hazard` task
`else
            // the fabric drives exactly one destination per live beat
            m_dx_sel_onehot : assume (!umi_in_valid || $onehot(select));
`endif
            // SELECT is part of the offer: it may not move under a stall
            if (prev_in_valid && !prev_in_ready)
                m_dx_sel_stable : assume (select == prev_select);
        end
    end
`endif

    // ----------------------------------------------------------------
    // Requirement: every output channel is legal SUMI. One checker
    // INSTANCE per port -- module instances carry their own scope, so
    // unlike assertion labels they may live in a generate loop.
    // ----------------------------------------------------------------
    wire         in_xfer  = umi_in_valid & umi_in_ready;
    wire [M-1:0] out_xfer = obs_out_valid & umi_out_ready;

    genvar i;
    generate
        for (i = 0; i < M; i = i + 1) begin : g_chk_out
            umi_handshake_checker #(
                .CW (CW), .AW (AW), .DW (DW),
                .ASSUME (0)               // requirement: assert legal output
            ) chk_out (
                .clk     (clk),
                .nreset  (nreset),
                .valid   (obs_out_valid[i]),
                .ready   (umi_out_ready[i]),
                .cmd     (umi_out_cmd[i*CW +: CW]),
                .dstaddr (umi_out_dstaddr[i*AW +: AW]),
                .srcaddr (umi_out_srcaddr[i*AW +: AW]),
                .data    (obs_out_data[i*DW +: DW]));
        end
    endgenerate

    // fork conservation: one accepted beat in, one delivered beat out
    always @(posedge clk)
        if (fv_active) begin
            a_dx_fork_xfer : assert (in_xfer == (out_xfer != {M{1'b0}}));
            a_dx_fork_one : assert ($onehot0(out_xfer));
        end

    // ----------------------------------------------------------------
    // Face 3b: rule 6, structural half. in_ready must not depend
    // combinationally on in_valid. Self-composition miter -- a twin instance driven with
    // the SAME select and out_ready but an INDEPENDENT input beat.
    // ----------------------------------------------------------------
    (* anyseq *) wire            in_valid_b;
    (* anyseq *) wire [CW-1:0]   in_cmd_b;
    (* anyseq *) wire [AW-1:0]   in_dstaddr_b;
    (* anyseq *) wire [AW-1:0]   in_srcaddr_b;
    (* anyseq *) wire [DW-1:0]   in_data_b;

    wire            in_ready_b;
    wire [M-1:0]    out_valid_b;
    wire [M*CW-1:0] out_cmd_b;
    wire [M*AW-1:0] out_dstaddr_b;
    wire [M*AW-1:0] out_srcaddr_b;
    wire [M*DW-1:0] out_data_b;

    umi_demux #(.M(M), .DW(DW), .CW(CW), .AW(AW)) dut_b (
        .select          (select),            // identical
        .umi_in_valid    (in_valid_b),        // independent
        .umi_in_cmd      (in_cmd_b),
        .umi_in_dstaddr  (in_dstaddr_b),
        .umi_in_srcaddr  (in_srcaddr_b),
        .umi_in_data     (in_data_b),
        .umi_in_ready    (in_ready_b),
        .umi_out_valid   (out_valid_b),
        .umi_out_cmd     (out_cmd_b),
        .umi_out_dstaddr (out_dstaddr_b),
        .umi_out_srcaddr (out_srcaddr_b),
        .umi_out_data    (out_data_b),
        .umi_out_ready   (umi_out_ready));    // identical

`ifdef FV_FAULT_R5
    // ILLEGAL design model: ready waits for valid. The miter's two
    // instances then disagree, so `fault_r5` must FAIL.
    wire r5_a = umi_in_ready & umi_in_valid;
`else
    wire r5_a = umi_in_ready;
`endif

    always @(posedge clk) begin
        a_dx_r5_indep : assert (r5_a == in_ready_b);
    end

    // ----------------------------------------------------------------
    // witnesses (formal-only)
    // ----------------------------------------------------------------
`ifdef FORMAL
`ifdef FV_RULE5_READYLOW
`ifdef FV_FAULT_RULE5
    // ILLEGAL design model: VALID gated by READY. Under stuck-low ready
    // this is 0 forever, so the covers go unreachable and the task FAILs.
    wire [M-1:0] rule5_valid = umi_out_valid & umi_out_ready;
`else
    wire [M-1:0] rule5_valid = umi_out_valid;
`endif
    reg [M-1:0] r5_past = {M{1'b0}};
    always @(posedge clk)
        r5_past <= rule5_valid;
    always @(posedge clk)
        if (f_past_exists & nreset) begin
            // VALID asserts even though READY has been low all along
            c_rule5_valid_stuck_low : cover (|rule5_valid);
            // and stays asserted with READY still low
            c_rule5_valid_held      : cover (|(rule5_valid & r5_past));
        end
`endif

    always @(posedge clk)
        if (fv_active) begin
`ifndef FV_RULE5_READYLOW
            // unreachable by construction when READY is pinned low
            c_dx_deliver : cover (in_xfer && out_xfer != {M{1'b0}});
`endif
            c_dx_stall   : cover (umi_in_valid && !umi_in_ready);
            c_dx_selmove : cover (select != prev_select && |select);
`ifdef FV_NO_SEL_ASSUME
            // demonstrated: what the onehot-select assumption is buying.
            // Three distinct hazards, one cover each -- the accept side
            // and the delivery side of a multi-hot select are separate
            // failures and neither implies the other.
            c_dx_drop : cover (in_xfer && select == {M{1'b0}});
            // DUPLICATION: one accepted input beat, delivered to two or
            // more outputs at once
            c_dx_dup  : cover (in_xfer && !$onehot0(out_xfer));
            // and the other half: a delivery the upstream never sees as
            // an accept, so the same beat is offered again afterwards
            c_dx_noaccept : cover (out_xfer != {M{1'b0}} && !in_xfer);
`endif
        end
`endif

endmodule

`default_nettype wire
