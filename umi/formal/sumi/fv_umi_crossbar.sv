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
 * Formal harness: the umi_crossbar routing contract.
 *
 * umi_crossbar instantiates umi_arbiter and lambdalib's la_vmux
 * (umi_crossbar.v:76, 119-149), which resolves out of site-packages.
 * The lane (tests/test_formal_sc.py) assembles the sources from
 * the Crossbar block's own fileset graph, so that path is resolved at
 * run time rather than written down anywhere.
 *
 * INDEX CONVENTION. umi_in_request[k*N + j] is "input j requests output
 * k" (umi_crossbar.v:20-31). A ROW of the N*N vector is one output's
 * requesters, a COLUMN is one input's destinations, and mask, grants and
 * umi_out_sel all use the same layout.
 *
 * The block is N independent arbiters in front of N one-hot muxes:
 *
 *   grants row k     = umi_arbiter(requests = request row k,
 *                                  mask     = mask row k)         (:76)
 *   umi_out_valid[k] = |grants row k                              (:86)
 *   umi_out_sel      = grants & ~mask                             (:91)
 *   umi_in_ready[j]  = &_k ~(req[k][j] &
 *                            (~grants[k][j] | ~umi_out_ready[k])) (:102-109)
 *   umi_out_<f> k    = la_vmux(sel = umi_out_sel row k,
 *                              in  = umi_in_<f>)                  (:117-150)
 *
 * There is no umi_in_valid port. An input OFFERS a beat exactly when it
 * requests at least one output, so the harness derives
 *
 *     in_offer[j] = |{ request[k][j] : k }
 *
 * and drives that onto the .valid pin of input j's handshake checker.
 * The ready equation then reads: input j is accepted only if EVERY
 * output it requests both granted it and is ready in the same cycle.
 * The unit of transport is therefore a DELIVERY, one per matrix cell:
 *
 *     deliver[k][j] = in_offer[j] & umi_in_ready[j] & request[k][j]
 *
 * WHAT IS CHECKED. Everything below reads only ports, so no hierarchical
 * path into the DUT is needed and the claims survive any internal
 * refactor. grants and umi_out_sel are never referenced.
 *
 *   a_xb_dlv_onehot0  at most one input delivers to any one output.
 *   a_xb_dlv_acc      a delivery lands: its output is valid and ready in
 *                     the same cycle. Equivalently, an accepted input
 *                     was granted by, and is ready at, every output it
 *                     asked for -- no half-completed accept.
 *   a_xb_nomask       no delivery on a masked path.
 *   a_xb_valid_req    an output never offers a beat no input requested.
 *   a_xb_route_*      at a delivery, the output beat equals the
 *                     delivering input's beat in all four SUMI fields.
 *   a_xb_conserve     an output accept implies a delivery to that output
 *                     -- under one operating condition, below.
 *
 * The first five are UNCONDITIONAL: they hold for every request shape,
 * every mask, every arbiter mode and every backpressure pattern.
 * Multicast -- one input requesting several outputs at once -- needs no
 * exclusion, because at accept time the route is still exact.
 *
 * OPERATING CONDITION on a_xb_conserve: every input requests at most one
 * output in that cycle (in_unicast, the shape umi_switch's address
 * decode produces). It is an antecedent of the one assertion that needs
 * it, not a global assumption, so nothing else in this file is weakened
 * and the excluded traffic stays reachable for the covers.
 *
 * Why it is needed, and what lies outside it: an input requesting two
 * outputs can be granted by both and taken by only one, because
 * umi_in_ready[j] demands every requested output be ready at once. That
 * output's valid and ready are both high, so it accepts the beat, while
 * the input is still stalled and will offer the same beat again. One
 * output accept, no input accept, and a repeat delivery later.
 * c_xb_multicast witnesses exactly that trace. This is the crossbar's
 * behaviour, not a defect the harness hides -- but a consumer that
 * counts output accepts as beats delivered is only correct when the
 * request rows are unicast.
 *
 * QUIET INPUTS. umi_in_ready[j] is a conjunction over the outputs input
 * j requests, so an input requesting nothing reads ready = 1
 * (umi_crossbar.v:104-108, the seed value {N{1'b1}} survives). READY
 * alone is not an accept indicator on this block; it must be qualified
 * with the input's request column, which is what in_offer does above.
 * c_xb_quiet witnesses the raised ready with nothing asked for.
 *
 * ENVIRONMENT. Every input channel is constrained legal SUMI by an
 * ASSUME=1 umi_handshake_checker (valid = in_offer, ready =
 * umi_in_ready), and mask is anyconst.
 *
 * Unlike fv_umi_mux, neither constraint is load-bearing here: every law
 * above is a cycle-local statement about the current requests, mask,
 * ready lines and output beats, and the arbiter's thermometer can hold
 * any value without disturbing them. They are kept for two reasons. The
 * checkers make the witnesses legal-SUMI traces rather than arbitrary
 * waveforms, and they hold the door open for a future multi-cycle law,
 * which would otherwise rest silently on illegal stimulus. A constant
 * mask keeps a counterexample from being a mid-transfer reconfiguration
 * -- a mask bit set after the arbiter had already granted that path is a
 * change of routing table, not a router defect. The `cover` task reaches
 * every witness in this file AND all four vacuity covers inside each
 * checker instance, so neither is starving the proof.
 *
 * What the checkers do NOT constrain is which outputs a stalled input
 * requests: README 4.2 rule 3 (README.md:460) covers CMD, DSTADDR,
 * SRCADDR and DATA, and the request row is none of those. A stalled
 * input may therefore re-aim between cycles. No law here needs it to be
 * stable, because no law here spans a cycle boundary.
 *
 * UNBOUNDED. These run as `prove` -- k-induction, not a bounded search.
 * The step case starts from an arbitrary arbiter thermometer state,
 * which is sound precisely because the grant contract the laws rest on
 * (grants are a subset of the unmasked requests, at most one per row) is
 * independent of that state. Nothing below is specialised to a
 * particular port count: the lane runs the 2x2 face to keep CI quick,
 * and raising the harness N is the whole change needed to prove a wider
 * crossbar.
 *
 * SCOPE -- deliberately not claimed:
 *
 * 1. Output channel legality. No ASSUME=0 checker is bound to an output
 *    channel. umi_out_valid[k] follows |grants row k, which the arbiter
 *    re-evaluates every cycle from the live requests, so an output can
 *    drop VALID before its beat is taken -- the same limit fv_umi_mux
 *    records. Consumers must sample on accept, not on offer.
 * 2. Progress. Nothing here says a persistent requester is eventually
 *    granted. The umi_arbiter thermometer's fairness is out of scope at
 *    this level, and no liveness property is asserted.
 * 3. README 4.2 rule 6 (README.md:463), input-facing. Rule 6 permits
 *    READY to depend on VALID but "not combinational[ly]", and
 *    umi_in_ready is combinational in umi_in_request through the arbiter
 *    (umi_crossbar.v:76 -> :102-109). The request vector is this block's
 *    VALID, so that is a rule 6 dependency, not the rule 5 one: rule 5
 *    constrains VALID on READY, the opposite direction, and nothing here
 *    claims it either way. The dependency is read off the source above;
 *    c_xb_r6_path only shows the cycle is reachable.
 *
 * Fault tasks corrupt only OBSERVED signals, never the DUT, and each is
 * constrained so exactly one law can break:
 *
 *   FV_FAULT_DUP      a stalled input also reads as accepted, on
 *                     exactly the outputs that already take a delivery
 *                     and on unmasked paths only     -> a_xb_dlv_onehot0
 *   FV_FAULT_DROP     an output accept is observed as not having
 *                     happened                            -> a_xb_dlv_acc
 *   FV_FAULT_GHOST    an output offers a beat nobody requested, with
 *                     its ready low so no accept moves  -> a_xb_valid_req
 *   FV_FAULT_STARVE   an output accepts although no input delivers,
 *                     restricted to unicast cycles        -> a_xb_conserve
 *   FV_FAULT_BLEND    the observed output carries a foreign cmd
 *                                                       -> a_xb_route_cmd
 *
 * a_xb_nomask has no fault task, for the reason fv_umi_mux gives for its
 * own mask law: the teeth are in fv_umi_arbiter's `fault_mask`, and at
 * this level the claim is compositional -- that umi_crossbar does not
 * leak a grant the arbiter refused. Any corruption strong enough to
 * break it here also breaks a_xb_dlv_onehot0 or a_xb_route_*, so no
 * such task would pin the failure to one label.
 ******************************************************************************/

`default_nettype none

module fv_umi_crossbar #(
    parameter N  = 2,               // number of input and output ports
    parameter CW = 32,              // command width
    parameter AW = 16,              // address width
    parameter DW = 32               // data width (the laws are DW-agnostic)
) (
    input wire clk
);

    // ----------------------------------------------------------------
    // reset: free, but asserted at time zero, so the arbiter
    // thermometers start from their reset value
    // ----------------------------------------------------------------
    (* anyseq *) wire nreset;
    reg f_past_exists = 1'b0;
    always @(posedge clk)
        f_past_exists <= 1'b1;
    always @(*)
        if (!f_past_exists)
            assume (!nreset);

    // ----------------------------------------------------------------
    // free stimulus -- the routing contract holds for any traffic and
    // any arbiter configuration. mode is free per cycle; mask is
    // CONFIGURATION, held constant (see the header).
    // ----------------------------------------------------------------
    (* anyseq   *) wire [1:0]     mode;
    (* anyconst *) wire [N*N-1:0] mask;
    (* anyseq *) wire [N*N-1:0]   umi_in_request;
    (* anyseq *) wire [N*CW-1:0]  umi_in_cmd;
    (* anyseq *) wire [N*AW-1:0]  umi_in_dstaddr;
    (* anyseq *) wire [N*AW-1:0]  umi_in_srcaddr;
    (* anyseq *) wire [N*DW-1:0]  umi_in_data;
    (* anyseq *) wire [N-1:0]     umi_out_ready;

    wire [N-1:0]    umi_in_ready;
    wire [N-1:0]    umi_out_valid;
    wire [N*CW-1:0] umi_out_cmd;
    wire [N*AW-1:0] umi_out_dstaddr;
    wire [N*AW-1:0] umi_out_srcaddr;
    wire [N*DW-1:0] umi_out_data;

    // ----------------------------------------------------------------
    // the design under test, exactly as shipped
    // ----------------------------------------------------------------
    umi_crossbar #(.N(N), .DW(DW), .CW(CW), .AW(AW)) dut (
        .clk            (clk),
        .nreset         (nreset),
        .mode           (mode),
        .mask           (mask),
        .umi_in_request (umi_in_request),
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
    // matrix views of the request vector. req_t is the transpose, which
    // turns the per-INPUT questions (is it offering? does it ask for
    // more than one output? is any of its paths masked?) into plain
    // vector reductions over a contiguous slice.
    // ----------------------------------------------------------------
    wire [N*N-1:0] req_t;
    wire [N*N-1:0] mask_t;
    wire [N-1:0]   req_any;      // output i has at least one requester
    wire [N-1:0]   req_multi;    // output i has more than one requester
    wire [N-1:0]   in_offer;     // input i asks for at least one output
    wire [N-1:0]   in_unicast;   // input i asks for at most one output
    wire [N-1:0]   in_masked;    // input i asks on at least one masked path

    genvar gi, gt;
    generate
        for (gi = 0; gi < N; gi = gi + 1) begin : g_port
            for (gt = 0; gt < N; gt = gt + 1) begin : g_transpose
                assign req_t [gi*N + gt] = umi_in_request[gt*N + gi];
                assign mask_t[gi*N + gt] = mask          [gt*N + gi];
            end
            // gi read as an INPUT index: its column of destinations
            assign in_offer  [gi] = |req_t[gi*N +: N];
            assign in_unicast[gi] = $onehot0(req_t[gi*N +: N]);
            assign in_masked [gi] = |(req_t[gi*N +: N] & mask_t[gi*N +: N]);
            // gi read as an OUTPUT index: its row of requesters
            assign req_any   [gi] = |umi_in_request[gi*N +: N];
            assign req_multi [gi] = !$onehot0(umi_in_request[gi*N +: N]);
        end
    endgenerate

    // every input requests at most one output this cycle -- the
    // operating condition of a_xb_conserve
    wire unicast = &in_unicast;

    // ----------------------------------------------------------------
    // the audited environment: every input channel is legal SUMI. The
    // block has no umi_in_valid, so the checker's VALID is the input's
    // request column reduced -- an input offers a beat exactly when it
    // asks for somewhere to put it.
    // ----------------------------------------------------------------
    genvar gc;
    generate
        for (gc = 0; gc < N; gc = gc + 1) begin : g_env_in
            umi_handshake_checker #(
                .CW (CW), .AW (AW), .DW (DW),
                .ASSUME (1)               // environment: assume legal input
            ) env_in (
                .clk     (clk),
                .nreset  (nreset),
                .valid   (in_offer[gc]),
                .ready   (umi_in_ready[gc]),
                .cmd     (umi_in_cmd    [gc*CW +: CW]),
                .dstaddr (umi_in_dstaddr[gc*AW +: AW]),
                .srcaddr (umi_in_srcaddr[gc*AW +: AW]),
                .data    (umi_in_data   [gc*DW +: DW]));
        end
    endgenerate

    // ----------------------------------------------------------------
    // fault injection (formal known-answer tests -- see the SC lane).
    // One block per observed signal; a run defines at most one macro.
    // ----------------------------------------------------------------
`ifdef FV_FAULT_DUP
    // A SECOND input reads as accepted. The extra input is genuinely
    // offering and genuinely stalled, its destinations are exactly the
    // outputs that already take a delivery, and none of those paths is
    // masked for it. So every row it joins already holds one delivery:
    // a_xb_dlv_acc is untouched (those outputs accept), a_xb_nomask is
    // untouched (unmasked by assumption), a_xb_conserve is untouched
    // (no row gains its first delivery) and every route guard on a
    // joined row goes vacuous under a two-hot row. Only one-hotness can
    // break.
    wire [N-1:0]   acc_true = in_offer & umi_in_ready;
    wire [N*N-1:0] dlv_true = umi_in_request & {N{acc_true}};
    (* anyseq *) wire [N-1:0] fdup;
    wire [N-1:0] extra = fdup & in_offer & ~umi_in_ready;
    wire [N-1:0] dlv_true_any;
    wire [N-1:0] ex_req;
    wire [N-1:0] ex_mask;
    genvar gf;
    generate
        for (gf = 0; gf < N; gf = gf + 1) begin : g_fdup
            assign dlv_true_any[gf] = |dlv_true[gf*N +: N];
            assign ex_req      [gf] = |(umi_in_request[gf*N +: N] & extra);
            assign ex_mask     [gf] = |(mask          [gf*N +: N] & extra);
        end
    endgenerate
    always @(*) begin
        assume ($onehot0(extra));
        assume (!(|extra) || (ex_req == dlv_true_any));
        assume (!(|extra) || ((ex_mask & ex_req) == {N{1'b0}}));
    end
    wire [N-1:0] obs_in_ready = umi_in_ready | extra;
`else
    wire [N-1:0] obs_in_ready = umi_in_ready;
`endif

`ifdef FV_FAULT_GHOST
    // An output offers a beat no input requested, with that output's
    // ready low so no observed accept moves. Only the no-teleport law
    // reads umi_out_valid without qualifying it by ready, so only it
    // can break.
    (* anyseq *) wire [N-1:0] fghost;
    wire [N-1:0] obs_out_valid = umi_out_valid |
                                 (fghost & ~umi_out_valid & ~req_any &
                                  ~umi_out_ready);
`elsif FV_FAULT_STARVE
    // An output accepts although no input delivers to it, restricted to
    // outputs that DO have a requester (so a_xb_valid_req still holds)
    // and to cycles where every input asks for at most one output (so
    // the conservation law is in force). out_acc only grows, and no
    // other law is broken by a larger out_acc.
    (* anyseq *) wire [N-1:0] fstarve;
    wire [N-1:0] obs_out_valid = umi_out_valid |
                                 (fstarve & ~umi_out_valid & req_any &
                                  umi_out_ready & {N{unicast}});
`else
    wire [N-1:0] obs_out_valid = umi_out_valid;
`endif

`ifdef FV_FAULT_DROP
    // An output accept is observed as not having happened. The delivery
    // set is computed from umi_in_ready and is untouched, so the input
    // side of every law is unchanged; lowering an observed accept can
    // only make a_xb_conserve easier. Only "a delivery lands" can break.
    (* anyseq *) wire [N-1:0] fdrop;
    wire [N-1:0] obs_out_ready = umi_out_ready & ~fdrop;
`else
    wire [N-1:0] obs_out_ready = umi_out_ready;
`endif

`ifdef FV_FAULT_BLEND
    // The observed output command differs from what the block drove.
    // Nothing else reads cmd, so only the cmd route law can break.
    (* anyseq *) wire [N*CW-1:0] fcmd;
    always @(*)
        assume (fcmd != umi_out_cmd);
    wire [N*CW-1:0] obs_out_cmd = fcmd;
`else
    wire [N*CW-1:0] obs_out_cmd = umi_out_cmd;
`endif

    // ----------------------------------------------------------------
    // accept-time observables
    // ----------------------------------------------------------------
    wire [N-1:0]   in_acc  = in_offer & obs_in_ready;
    wire [N-1:0]   out_acc = obs_out_valid & obs_out_ready;
    // deliver[k*N + j]: input j hands a beat to output k this cycle.
    // {N{in_acc}} places in_acc[j] at every bit (k*N + j), which is the
    // request vector's own layout.
    wire [N*N-1:0] deliver = umi_in_request & {N{in_acc}};

    wire [N-1:0] dlv_any;   // output i takes at least one delivery
    wire [N-1:0] dlv_oh0;   // output i takes at most one
    wire [N-1:0] dlv_one;   // output i takes exactly one

    genvar gd;
    generate
        for (gd = 0; gd < N; gd = gd + 1) begin : g_dlv
            assign dlv_any[gd] = |deliver[gd*N +: N];
            assign dlv_oh0[gd] = $onehot0(deliver[gd*N +: N]);
            assign dlv_one[gd] = $onehot(deliver[gd*N +: N]);
        end
    endgenerate

    // ----------------------------------------------------------------
    // The beat each output owes: the delivering input's, selected by the
    // port-observable delivery matrix. A plain procedural loop, so it
    // holds for any N and emits no per-index assertion labels; the
    // verdict leaves as one bit per output and is asserted as a whole
    // vector. The route laws are guarded by dlv_one, not dlv_any: under
    // a_xb_dlv_onehot0 the two guards agree, but keeping them distinct
    // means a one-hotness fault fails one label instead of five.
    // ----------------------------------------------------------------
    integer i, k;
    reg [N*CW-1:0] exp_cmd;
    reg [N*AW-1:0] exp_dstaddr;
    reg [N*AW-1:0] exp_srcaddr;
    reg [N*DW-1:0] exp_data;
    reg [N-1:0]    bad_cmd;
    reg [N-1:0]    bad_dstaddr;
    reg [N-1:0]    bad_srcaddr;
    reg [N-1:0]    bad_data;

    always @(*) begin
        exp_cmd     = {(N*CW){1'b0}};
        exp_dstaddr = {(N*AW){1'b0}};
        exp_srcaddr = {(N*AW){1'b0}};
        exp_data    = {(N*DW){1'b0}};
        bad_cmd     = {N{1'b0}};
        bad_dstaddr = {N{1'b0}};
        bad_srcaddr = {N{1'b0}};
        bad_data    = {N{1'b0}};
        for (k = 0; k < N; k = k + 1) begin
            for (i = 0; i < N; i = i + 1)
                if (deliver[k*N + i]) begin
                    exp_cmd    [k*CW +: CW] = umi_in_cmd    [i*CW +: CW];
                    exp_dstaddr[k*AW +: AW] = umi_in_dstaddr[i*AW +: AW];
                    exp_srcaddr[k*AW +: AW] = umi_in_srcaddr[i*AW +: AW];
                    exp_data   [k*DW +: DW] = umi_in_data   [i*DW +: DW];
                end
            bad_cmd[k]     = dlv_one[k] &
                             (obs_out_cmd[k*CW +: CW] != exp_cmd[k*CW +: CW]);
            bad_dstaddr[k] = dlv_one[k] &
                             (umi_out_dstaddr[k*AW +: AW] != exp_dstaddr[k*AW +: AW]);
            bad_srcaddr[k] = dlv_one[k] &
                             (umi_out_srcaddr[k*AW +: AW] != exp_srcaddr[k*AW +: AW]);
            bad_data[k]    = dlv_one[k] &
                             (umi_out_data[k*DW +: DW] != exp_data[k*DW +: DW]);
        end
    end

    // ----------------------------------------------------------------
    // the routing contract
    // ----------------------------------------------------------------
    always @(posedge clk) begin

        a_xb_dlv_onehot0 : assert (dlv_oh0 == {N{1'b1}});

        a_xb_dlv_acc : assert ((dlv_any & ~out_acc) == {N{1'b0}});

        a_xb_nomask : assert ((deliver & mask) == {(N*N){1'b0}});

        a_xb_valid_req : assert ((obs_out_valid & ~req_any) == {N{1'b0}});

        // operating condition: every input asks for at most one output
        // this cycle -- see the header for what lies outside it
        a_xb_conserve : assert ((out_acc & ~dlv_any & {N{unicast}}) == {N{1'b0}});

        a_xb_route_cmd : assert (bad_cmd == {N{1'b0}});

        a_xb_route_dstaddr : assert (bad_dstaddr == {N{1'b0}});

        a_xb_route_srcaddr : assert (bad_srcaddr == {N{1'b0}});

        a_xb_route_data : assert (bad_data == {N{1'b0}});
    end

    // ----------------------------------------------------------------
    // witnesses (formal-only)
    // ----------------------------------------------------------------
`ifdef FORMAL
    always @(posedge clk)
        if (f_past_exists & nreset) begin
            // an ordinary routed transfer
            c_xb_xfer      : cover (|dlv_any);
            // a full permutation: every output takes a beat and every
            // input places one, in the same cycle
            c_xb_simul     : cover (dlv_any == {N{1'b1}}
                                    && in_acc == {N{1'b1}});
            // two inputs want the same output and exactly one gets it
            c_xb_contend   : cover (|(req_multi & dlv_any));
            // an output is offering a beat its sink is not taking
            c_xb_backpress : cover (|(umi_out_valid & ~umi_out_ready));
            // the mask holds a requester off while traffic flows
            c_xb_mask_hold : cover (|(in_masked & ~in_acc) && |in_acc);
            // the quiet/eager-accept hazard: an input that asks for
            // nothing is told it is ready
            c_xb_quiet     : cover (|(~in_offer & umi_in_ready));
            // outside the conservation law's operating condition: an
            // output accepts a beat while no input is accepted at all
            c_xb_multicast : cover (!unicast && |out_acc
                                    && in_acc == {N{1'b0}});
            // reachability only: a cycle in which some output is ready
            // and some input both offers and is ready. It does NOT
            // demonstrate the dependency -- a cover cannot. That needs a
            // self-composition miter, which this harness does not build.
            c_xb_r6_path   : cover (|umi_out_ready && |in_offer
                                    && umi_in_ready != {N{1'b0}});
        end
`endif

endmodule

`default_nettype wire
