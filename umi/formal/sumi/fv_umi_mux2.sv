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
 * Formal harness: the umi_mux2 select-and-merge contract, including the
 * output-channel stability that umi_mux cannot offer.
 *
 * umi_mux2 is the 2:1 merge whose select is an EXTERNAL input port --
 * "arbiter is external" (umi_mux2.v:18). It is purely combinational: no
 * clk, no nreset (umi_mux2.v:27-43). The harness supplies a clock only
 * to host the named immediate assertions, the same way fv_umi_demux
 * does for the equally combinational umi_demux.
 *
 * It instantiates lambdalib's la_vmux2b (umi_mux2.v:52-79), which
 * resolves out of site-packages -- a path that varies by environment.
 * The lane (tests/test_formal_sc.py) takes the sources from the
 * repo's own fileset graph, so that path is resolved at run time
 * rather than written down anywhere.
 *
 * THE BLOCK IS FOUR EQUATIONS:
 *
 *     umi_out_valid   = ( sel & umi_in_valid[1])
 *                     | (~sel & umi_in_valid[0])                (:91-92)
 *     umi_in_ready[0] = ~umi_in_valid[0] | (~sel & umi_out_ready)  (:94)
 *     umi_in_ready[1] = ~umi_in_valid[1] | ( sel & umi_out_ready)  (:95)
 *     umi_out_<f>     = la_vmux2b(sel, in1 = <f>[1], in0 = <f>[0])
 *                                                               (:52-79)
 *
 * la_vmux2b is out = (~sel & in0) | (sel & in1), so the payload path is
 * an unconditional select: the output fields equal the selected input's
 * fields in every cycle, offered or not.
 *
 * Folding in_acc = umi_in_valid & umi_in_ready gives the accept sets,
 * and the `~umi_in_valid[i]` term cancels:
 *
 *     in_acc[0] = ~sel & umi_in_valid[0] & umi_out_ready
 *     in_acc[1] =  sel & umi_in_valid[1] & umi_out_ready
 *     out_acc   = umi_out_ready & (( sel & umi_in_valid[1])
 *                                | (~sel & umi_in_valid[0]))
 *
 * so the transfer set is unaffected by that term, while umi_in_ready
 * taken alone is not -- see FACE 3 and the scope note.
 *
 * ---------------------------------------------------------------------
 * FACE 1 -- UNCONDITIONAL theorems, no environment assumptions at all.
 * Everything reads ports only, so no hierarchical path into the DUT is
 * needed and the claims survive any internal refactor.
 *
 *   a_mux2_valid_eq      the output offers a beat exactly when the
 *                        SELECTED input offers one.
 *   a_mux2_route_*       the output carries the selected input's beat
 *                        verbatim in all four SUMI fields, for both
 *                        values of sel. Written as one equality against
 *                        the sel-selected expression, which covers both
 *                        polarities without a per-polarity label.
 *   a_mux2_unsel_quiet   the UNSELECTED input is never accepted.
 *   a_mux2_xfer_agg      the number of input accepts equals the number
 *                        of output accepts -- conservation (no beat is
 *                        swallowed) and no teleport (none is invented).
 *
 * fv_umi_mux states one-hotness of the accept vector as its own law.
 * Here it is not a separate law: at two inputs, "the unselected input
 * is never accepted" already implies "at most one input is accepted",
 * and a_mux2_xfer_agg is written in aggregation form (a two-bit sum, not
 * a reduction OR) so a double accept breaks it as well.
 *
 * ---------------------------------------------------------------------
 * FACE 2 -- OUTPUT STABILITY, under a stated environment. This is the
 * claim fv_umi_mux declines for umi_mux, and it is why this proof is
 * worth having alongside it.
 *
 *   a_mux2_hold_valid    a pending output offer is still offered.
 *   a_mux2_hold_*        and its payload has not moved.
 *   chk_out              the same obligation in the shipped checker's
 *                        vocabulary: an ASSUME=0 umi_handshake_checker
 *                        bound to the output channel, asserting README
 *                        4.2 rules 2 and 3 (README.md:459-460). The
 *                        named laws above are the port-observable form
 *                        this file's fault table targets; chk_out is
 *                        the repo's own statement of the same rules, and
 *                        it judges the DUT's outputs directly.
 *
 * umi_mux cannot make this claim because its internal umi_arbiter
 * re-evaluates every cycle. umi_mux2 has no arbiter: umi_out_valid and
 * the payload are combinational in `sel`, so output stability is exactly
 * as stable as `sel` and no more. The environment therefore has to say
 * so, and does:
 *
 *   m_mux2_sel_stable  while an output offer is pending (offered last
 *                      cycle, not accepted), `sel` may not move.
 *
 * That is an integration requirement, not a convenience. The merged
 * output is a SUMI channel, and README 4.2 rules 2 and 3 oblige its
 * transmitter to hold VALID and the payload until the beat is accepted.
 * Since both are combinational in `sel`, only whatever drives `sel` can
 * discharge that obligation -- the block itself has no state to do it
 * with. A `sel` driver that does not hold is not using umi_mux2 to build
 * a legal SUMI channel. The `hazard` task drops the assumption and
 * covers what happens then, on the shipped RTL:
 *   c_mux2_offer_lost  a pending beat is WITHDRAWN -- README 4.2 rule 2
 *                      broken at the output.
 *   c_mux2_beat_swap   the offer stays up but the payload is now the
 *                      other input's -- rule 3 broken at the output, and
 *                      a sink that samples on offer takes a beat that
 *                      was never sent.
 *
 * `sel` is free per cycle, not (* anyconst *). Holding it constant would
 * delete the only interesting behaviour the block has -- switching
 * sources -- and c_mux2_selflip would go unreachable. It is constrained
 * only inside the pending window, which is precisely where the SUMI
 * contract constrains it.
 *
 * The input channels are constrained legal SUMI by ASSUME=1
 * umi_handshake_checker instances. They are load-bearing for FACE 2 and
 * for nothing else: when umi_out_ready is low, umi_in_ready[i] reduces
 * to ~umi_in_valid[i], so an offering input is stalled, and it is the
 * checker's rule 2 / rule 3 assumptions that carry that input's beat
 * unchanged into the next cycle. Without them an input could withdraw
 * mid-stall and the output would lose a beat through no fault of the
 * mux. FACE 1 and FACE 3 hold with the checkers removed.
 *
 * chk_out runs CHECK_RESET=0. umi_mux2 has no reset port, so VALID-low-
 * during-reset is not an obligation it can discharge; it belongs to the
 * input transmitters, and the ASSUME=1 instances already carry it.
 *
 * ---------------------------------------------------------------------
 * FACE 3 -- the two structural handshake rules, by self-composition.
 * Twin instances see identical values on some ports and independent
 * values on others; comparing outputs separates dependence from
 * independence exactly, with no hierarchical peek.
 *
 *   a_mux2_r5_valid_indep  README 4.2 rule 5 (README.md:462), "the
 *       assertion of VALID must not depend on the assertion of READY".
 *       dut_c sees the same sel and the same input beats but an
 *       INDEPENDENT umi_out_ready; the two umi_out_valid outputs must
 *       agree. Any path from umi_out_ready to umi_out_valid separates
 *       them. umi_mux2 passes: a positive structural result, the same
 *       method fv_umi_demux uses for a_dx_r5_indep.
 *
 *   a_mux2_r6_nocross      dut_b sees the same sel, the same
 *       umi_out_ready and the same CHANNEL 0 beat, but an independent
 *       channel 1; umi_in_ready[0] must agree. So channel 0's READY does
 *       not depend on channel 1's traffic -- the two input ports are not
 *       combinationally cross-coupled.
 *
 *   c_mux2_r6_selfdep      the same twin, read the other way:
 *       umi_in_ready[1] DIFFERS between the instances although sel and
 *       umi_out_ready are identical. The only input that differs is
 *       channel 1's own VALID, so this is a constructive witness of a
 *       combinational path from umi_in_valid[1] to umi_in_ready[1]. See
 *       the scope note.
 *
 * ---------------------------------------------------------------------
 * SCOPE -- what is deliberately NOT asserted. Silence would read as a
 * claim that these hold.
 *
 * 1. README 4.2 rule 6 (README.md:463) -- "it is legal for the READY
 *    assertion to be dependent on the VALID assertion (as long as this
 *    dependence is not combinational)" -- is NOT met at the input ports.
 *    umi_in_ready[i] contains the literal term ~umi_in_valid[i]
 *    (umi_mux2.v:94-95), so an idle input reads READY=1 regardless of
 *    umi_out_ready. c_mux2_r6_selfdep witnesses the path rather than
 *    leaving it as a reading of the source, and no rule 6 assertion is
 *    made. Two consequences a reader must know:
 *      - the accept sets are unharmed. in_acc = VALID & READY cancels
 *        the term, which is why FACE 1 proves cleanly.
 *      - umi_in_ready alone is not a usable "the sink can take a beat"
 *        signal, and closing a combinational loop through it -- an
 *        upstream whose VALID is itself combinational in READY -- is
 *        not safe. a_mux2_r6_nocross bounds the exposure to the
 *        offering channel: it does not spread to the other input.
 *    fv_umi_mux reports the same shape for umi_mux, reached by a
 *    different mechanism (through the arbiter rather than a literal
 *    term).
 *
 * 2. No liveness, and in particular no starvation freedom. umi_mux2
 *    contains no arbiter; which input makes progress is entirely the
 *    `sel` driver's decision. A `sel` held at 1 forever starves input 0
 *    and violates nothing in this file. Fairness is a property of the
 *    external arbiter and has to be proven there.
 *
 * 3. Packet-level merging (README 4.1.2, README.md:431) is out of scope.
 *    umi_mux2 merges two CHANNELS beat by beat; it never combines two
 *    beats into one packet, so the CMD field rules for merging do not
 *    apply to it.
 *
 * ---------------------------------------------------------------------
 * Fault tasks corrupt only what the harness OBSERVES, never the DUT.
 * Each observed copy feeds exactly one law, so each fault breaks
 * exactly one label:
 *
 *   FV_FAULT_ROUTE     the output carries a foreign cmd
 *                                            -> a_mux2_route_cmd
 *   FV_FAULT_TELEPORT  an output accept with no input accept
 *                                            -> a_mux2_xfer_agg
 *   FV_FAULT_SPILL     the unselected input reads as accepted
 *                                            -> a_mux2_unsel_quiet
 *   FV_FAULT_STALL     a pending output offer is withdrawn
 *                                            -> a_mux2_hold_valid
 *   FV_FAULT_R5        models the illegal design in which VALID waits
 *                      for READY; the miter separates
 *                                            -> a_mux2_r5_valid_indep
 *
 * The remaining labels have no fault task of their own. Each is the
 * same equality as a fault-tested sibling over a different field or a
 * different port -- a_mux2_route_dstaddr / _srcaddr / _data alongside
 * a_mux2_route_cmd, a_mux2_hold_cmd / _dstaddr / _srcaddr / _data
 * alongside a_mux2_hold_valid -- and a fault per field would add rows
 * without adding evidence.
 *
 * Dropping m_mux2_sel_stable is a `cover` task and NOT a fault task.
 * It is a real counterexample -- run as bmc it breaks a_mux2_hold_*
 * and chk_out's RULE3_*_stable together -- but a fault whose blast
 * radius is a whole face proves less than one that isolates a single
 * label, and the two hazard covers say what actually goes wrong.
 ******************************************************************************/

`default_nettype none

module fv_umi_mux2 #(
    parameter CW = 32,              // command width
    parameter AW = 16,              // address width
    parameter DW = 32               // data width (the laws are DW-agnostic)
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
    // free stimulus. Input UMI order is {in1, in0} (umi_mux2.v:28).
    // ----------------------------------------------------------------
    (* anyseq *) wire            sel;
    (* anyseq *) wire [1:0]      umi_in_valid;
    (* anyseq *) wire [2*CW-1:0] umi_in_cmd;
    (* anyseq *) wire [2*AW-1:0] umi_in_dstaddr;
    (* anyseq *) wire [2*AW-1:0] umi_in_srcaddr;
    (* anyseq *) wire [2*DW-1:0] umi_in_data;
    (* anyseq *) wire            umi_out_ready;

    wire [1:0]     umi_in_ready;
    wire           umi_out_valid;
    wire [CW-1:0]  umi_out_cmd;
    wire [AW-1:0]  umi_out_dstaddr;
    wire [AW-1:0]  umi_out_srcaddr;
    wire [DW-1:0]  umi_out_data;

    // ----------------------------------------------------------------
    // the design under test, exactly as shipped
    // ----------------------------------------------------------------
    umi_mux2 #(.DW(DW), .CW(CW), .AW(AW)) dut (
        .sel            (sel),
        .umi_in_valid   (umi_in_valid),
        .umi_in_cmd     (umi_in_cmd),
        .umi_in_dstaddr (umi_in_dstaddr),
        .umi_in_srcaddr (umi_in_srcaddr),
        .umi_in_data    (umi_in_data),
        .umi_in_ready   (umi_in_ready),
        .umi_out_valid  (umi_out_valid),
        .umi_out_cmd    (umi_out_cmd),
        .umi_out_dstaddr(umi_out_dstaddr),
        .umi_out_srcaddr(umi_out_srcaddr),
        .umi_out_data   (umi_out_data),
        .umi_out_ready  (umi_out_ready));

    // ----------------------------------------------------------------
    // port-observable derived signals
    // ----------------------------------------------------------------
    // the beat on the selected input
    wire [CW-1:0] sel_cmd     = sel ? umi_in_cmd    [CW +: CW] : umi_in_cmd    [0 +: CW];
    wire [AW-1:0] sel_dstaddr = sel ? umi_in_dstaddr[AW +: AW] : umi_in_dstaddr[0 +: AW];
    wire [AW-1:0] sel_srcaddr = sel ? umi_in_srcaddr[AW +: AW] : umi_in_srcaddr[0 +: AW];
    wire [DW-1:0] sel_data    = sel ? umi_in_data   [DW +: DW] : umi_in_data   [0 +: DW];
    // 1 in the position of the input the select is NOT pointing at
    wire [1:0]    unsel       = sel ? 2'b01 : 2'b10;

    wire [1:0]    in_acc      = umi_in_valid & umi_in_ready;

    // ----------------------------------------------------------------
    // fault injection (formal known-answer tests -- see the SC lane).
    // Each observed copy is read by ONE law, so a fault cannot spill
    // into a neighbouring claim.
    // ----------------------------------------------------------------
`ifdef FV_FAULT_ROUTE
    // the observed output command differs from the selected input's
    (* anyseq *) wire [CW-1:0] froute;
    always @(*)
        assume (froute != umi_out_cmd);
    wire [CW-1:0] obs_route_cmd = froute;
`else
    wire [CW-1:0] obs_route_cmd = umi_out_cmd;
`endif

`ifdef FV_FAULT_TELEPORT
    // an output accept in a cycle with no input accept
    (* anyseq *) wire ftel;
    always @(*)
        assume (!ftel || (!umi_out_valid && umi_out_ready));
    wire obs_agg_valid = umi_out_valid | ftel;
`else
    wire obs_agg_valid = umi_out_valid;
`endif

`ifdef FV_FAULT_SPILL
    // the input the select is not pointing at reads as accepted
    (* anyseq *) wire fspill;
    always @(*)
        assume (!fspill || (umi_in_valid == 2'b11));
    wire [1:0] obs_unsel_ready = umi_in_ready | (fspill ? unsel : 2'b00);
`else
    wire [1:0] obs_unsel_ready = umi_in_ready;
`endif

`ifdef FV_FAULT_STALL
    // an offered beat may be withdrawn before it is accepted
    (* anyseq *) wire fstall;
    wire obs_hold_valid = umi_out_valid & ~fstall;
`else
    wire obs_hold_valid = umi_out_valid;
`endif

    wire       out_acc_agg  = obs_agg_valid & umi_out_ready;
    wire [1:0] in_acc_unsel = umi_in_valid & obs_unsel_ready;

    // ----------------------------------------------------------------
    // FACE 1: unconditional theorems (no environment assumptions)
    // ----------------------------------------------------------------
    always @(posedge clk) begin

        a_mux2_valid_eq : assert (umi_out_valid ==
                                  (sel ? umi_in_valid[1] : umi_in_valid[0]));

        a_mux2_route_cmd : assert (obs_route_cmd == sel_cmd);

        a_mux2_route_dstaddr : assert (umi_out_dstaddr == sel_dstaddr);

        a_mux2_route_srcaddr : assert (umi_out_srcaddr == sel_srcaddr);

        a_mux2_route_data : assert (umi_out_data == sel_data);

        a_mux2_unsel_quiet : assert ((in_acc_unsel & unsel) == 2'b00);

        // aggregation form: a two-bit sum, so a double accept breaks
        // this label as well as a swallowed or invented beat
        a_mux2_xfer_agg : assert (({1'b0, in_acc[0]} + {1'b0, in_acc[1]}) ==
                                  {1'b0, out_acc_agg});
    end

    // ----------------------------------------------------------------
    // FACE 2: the audited environment
    // ----------------------------------------------------------------
    reg          past_nreset      = 1'b0;
    reg          prev_out_valid   = 1'b0;
    reg          prev_out_ready   = 1'b0;
    reg          prev_sel         = 1'b0;
    reg [CW-1:0] prev_out_cmd;
    reg [AW-1:0] prev_out_dstaddr;
    reg [AW-1:0] prev_out_srcaddr;
    reg [DW-1:0] prev_out_data;

    always @(posedge clk) begin
        past_nreset      <= nreset;
        prev_out_valid   <= nreset & umi_out_valid;
        prev_out_ready   <= umi_out_ready;
        prev_sel         <= sel;
        prev_out_cmd     <= umi_out_cmd;
        prev_out_dstaddr <= umi_out_dstaddr;
        prev_out_srcaddr <= umi_out_srcaddr;
        prev_out_data    <= umi_out_data;
    end

    wire fv_active = f_past_exists & nreset & past_nreset;
    // last cycle the output offered a beat and the sink did not take it
    wire pending   = prev_out_valid & ~prev_out_ready;

    // both input channels are legal SUMI. One checker INSTANCE per
    // channel -- module instances carry their own scope, so unlike
    // assertion labels they may live in a generate loop.
    genvar gi;
    generate
        for (gi = 0; gi < 2; gi = gi + 1) begin : g_env_in
            umi_handshake_checker #(
                .CW (CW), .AW (AW), .DW (DW),
                .ASSUME (1)               // environment: assume legal input
            ) env_in (
                .clk     (clk),
                .nreset  (nreset),
                .valid   (umi_in_valid[gi]),
                .ready   (umi_in_ready[gi]),
                .cmd     (umi_in_cmd    [gi*CW +: CW]),
                .dstaddr (umi_in_dstaddr[gi*AW +: AW]),
                .srcaddr (umi_in_srcaddr[gi*AW +: AW]),
                .data    (umi_in_data   [gi*DW +: DW]));
        end
    endgenerate

`ifdef FORMAL
`ifndef FV_NO_SEL_STABLE
    // SELECT is part of the offer: the merged output's VALID and payload
    // are combinational in it, so it may not move under a stall
    always @(posedge clk)
        if (fv_active && pending)
            m_mux2_sel_stable : assume (sel == prev_sel);
`endif
`endif

    // Requirement: the merged output channel is legal SUMI. This is the
    // binding fv_umi_mux does not make for umi_mux.
    umi_handshake_checker #(
        .CW (CW), .AW (AW), .DW (DW),
        .ASSUME (0),                      // requirement: assert legal output
        .CHECK_RESET (0)                  // the DUT has no reset port
    ) chk_out (
        .clk     (clk),
        .nreset  (nreset),
        .valid   (umi_out_valid),
        .ready   (umi_out_ready),
        .cmd     (umi_out_cmd),
        .dstaddr (umi_out_dstaddr),
        .srcaddr (umi_out_srcaddr),
        .data    (umi_out_data));

    // the same obligation, port-observable and labelled in this file
    always @(posedge clk)
        if (fv_active && pending) begin

            a_mux2_hold_valid : assert (obs_hold_valid);

            a_mux2_hold_cmd : assert (umi_out_cmd == prev_out_cmd);

            a_mux2_hold_dstaddr : assert (umi_out_dstaddr == prev_out_dstaddr);

            a_mux2_hold_srcaddr : assert (umi_out_srcaddr == prev_out_srcaddr);

            a_mux2_hold_data : assert (umi_out_data == prev_out_data);
        end

    // ----------------------------------------------------------------
    // FACE 3a: README 4.2 rule 5 (README.md:462). VALID must not depend
    // on READY. Self-composition miter -- a twin driven with the SAME
    // select and the SAME input beats but an INDEPENDENT umi_out_ready.
    // ----------------------------------------------------------------
    (* anyseq *) wire out_ready_c;

    wire [1:0]     in_ready_c;
    wire           out_valid_c;
    wire [CW-1:0]  out_cmd_c;
    wire [AW-1:0]  out_dstaddr_c;
    wire [AW-1:0]  out_srcaddr_c;
    wire [DW-1:0]  out_data_c;

    umi_mux2 #(.DW(DW), .CW(CW), .AW(AW)) dut_c (
        .sel            (sel),               // identical
        .umi_in_valid   (umi_in_valid),      // identical
        .umi_in_cmd     (umi_in_cmd),
        .umi_in_dstaddr (umi_in_dstaddr),
        .umi_in_srcaddr (umi_in_srcaddr),
        .umi_in_data    (umi_in_data),
        .umi_in_ready   (in_ready_c),
        .umi_out_valid  (out_valid_c),
        .umi_out_cmd    (out_cmd_c),
        .umi_out_dstaddr(out_dstaddr_c),
        .umi_out_srcaddr(out_srcaddr_c),
        .umi_out_data   (out_data_c),
        .umi_out_ready  (out_ready_c));      // independent

`ifdef FV_FAULT_R5
    // ILLEGAL design model: VALID waits for READY. The miter's two
    // instances then disagree, so this task must FAIL.
    wire r5_valid_a = umi_out_valid & umi_out_ready;
`else
    wire r5_valid_a = umi_out_valid;
`endif

    // ----------------------------------------------------------------
    // FACE 3b: the ready side. A twin sees the same select, the same
    // umi_out_ready and the same CHANNEL 0 beat, but an independent
    // channel 1.
    // ----------------------------------------------------------------
    (* anyseq *) wire            in1_valid_b;
    (* anyseq *) wire [CW-1:0]   in1_cmd_b;
    (* anyseq *) wire [AW-1:0]   in1_dstaddr_b;
    (* anyseq *) wire [AW-1:0]   in1_srcaddr_b;
    (* anyseq *) wire [DW-1:0]   in1_data_b;

    wire [1:0]     in_ready_b;
    wire           out_valid_b;
    wire [CW-1:0]  out_cmd_b;
    wire [AW-1:0]  out_dstaddr_b;
    wire [AW-1:0]  out_srcaddr_b;
    wire [DW-1:0]  out_data_b;

    umi_mux2 #(.DW(DW), .CW(CW), .AW(AW)) dut_b (
        .sel            (sel),                                    // identical
        .umi_in_valid   ({in1_valid_b, umi_in_valid[0]}),         // ch0 identical
        .umi_in_cmd     ({in1_cmd_b, umi_in_cmd[0 +: CW]}),
        .umi_in_dstaddr ({in1_dstaddr_b, umi_in_dstaddr[0 +: AW]}),
        .umi_in_srcaddr ({in1_srcaddr_b, umi_in_srcaddr[0 +: AW]}),
        .umi_in_data    ({in1_data_b, umi_in_data[0 +: DW]}),
        .umi_in_ready   (in_ready_b),
        .umi_out_valid  (out_valid_b),
        .umi_out_cmd    (out_cmd_b),
        .umi_out_dstaddr(out_dstaddr_b),
        .umi_out_srcaddr(out_srcaddr_b),
        .umi_out_data   (out_data_b),
        .umi_out_ready  (umi_out_ready));                         // identical

    always @(posedge clk) begin

        a_mux2_r5_valid_indep : assert (r5_valid_a == out_valid_c);

        a_mux2_r6_nocross : assert (umi_in_ready[0] == in_ready_b[0]);
    end

    // ----------------------------------------------------------------
    // witnesses (formal-only)
    // ----------------------------------------------------------------
`ifdef FORMAL
    always @(posedge clk)
        if (fv_active) begin
            // a merged transfer from each input
            c_mux2_xfer0   : cover (in_acc[0]);
            c_mux2_xfer1   : cover (in_acc[1]);
            // the output is offering a beat the sink is not taking
            c_mux2_stall   : cover (umi_out_valid && !umi_out_ready);
            // the stability face is exercised, not vacuous: an offer
            // survives a stall and is then accepted
            c_mux2_hold    : cover (pending && umi_out_valid && umi_out_ready);
            // the select moves and the newly selected input transfers
            c_mux2_selflip : cover (sel != prev_sel && |in_acc);
            // scope note 1, witnessed constructively: sel and
            // umi_out_ready are identical across the twin, so the only
            // cause of the difference is channel 1's own VALID
            c_mux2_r6_selfdep : cover (umi_in_ready[1] != in_ready_b[1]);

`ifdef FV_NO_SEL_STABLE
            // what lies outside m_mux2_sel_stable, on the shipped RTL
            c_mux2_offer_lost : cover (pending && !umi_out_valid);
            c_mux2_beat_swap  : cover (pending && umi_out_valid
                                       && umi_out_cmd != prev_out_cmd);
`endif
        end
`endif

endmodule

`default_nettype wire
