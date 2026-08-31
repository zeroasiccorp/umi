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
 * Formal harness: the umi_mux merge contract.
 *
 * umi_mux is the first block in this directory that instantiates other
 * blocks -- umi_arbiter and lambdalib's la_vmux (umi_mux.v:63, 105-140).
 * lambdalib resolves out of site-packages, a path that varies by
 * environment; the lane (tests/test_formal_sc.py) takes the
 * sources from the repo's own fileset graph, so that path is resolved
 * at run time rather than written down anywhere.
 *
 * The block is a select-and-merge around the arbiter:
 *
 *     grants        = umi_arbiter(requests = umi_in_valid)   (:63)
 *     sel_oh        = stalled ? stalled_input : grants       (:91)
 *     umi_out_valid = |sel_oh                                (:73)
 *     umi_in_ready  = sel_oh & {N{umi_out_ready}}            (:98)
 *     umi_out_<f>   = la_vmux(sel = sel_oh, in = umi_in_<f>) (:105-140)
 *
 * WHAT IS CHECKED -- the merge identity in ACCEPT-TIME form. Everything
 * below reads only ports, so no hierarchical path into the DUT is
 * needed and the claims survive any internal refactor:
 *
 *   a_mux_acc_onehot0  at most one input is accepted per cycle.
 *   a_mux_cnt_eq       an input accept happens exactly when an output
 *                      accept happens -- conservation (no beat is
 *                      swallowed) and no teleport (none is invented).
 *   a_mux_nomask       a masked input is never accepted.
 *   a_mux_route_*      at accept, the output beat equals the accepting
 *                      input's beat in all four SUMI fields.
 *
 * Order preservation is not a separate law here: the merge is
 * combinational, so a beat leaves in the cycle it is accepted and there
 * is no state in which to reorder one.
 *
 * BOUNDED, not unbounded: these run as BMC. stalled_input is read only
 * while the output is stalled and is not observable at the ports in that
 * window, so k-induction's step case starts from fabricated values no
 * trace can reach. The fix is an assume/guarantee composition replacing
 * umi_arbiter with a stub licensed by fv_umi_arbiter's grant contract;
 * it is not attempted here. A hierarchical invariant is not an
 * alternative: `stalled_input` does not resolve to one signal in the
 * elaborated netlist (a 2-bit register and a 1-bit artifact share the
 * name), so an assertion against it binds ambiguously.
 *
 * The route laws are guarded by $onehot(in_acc), not |in_acc. Under
 * a_mux_acc_onehot0 these are the same guard, but keeping them distinct
 * means a one-hotness fault convicts one label instead of four.
 *
 * ENVIRONMENT. Every input channel is constrained legal SUMI by an
 * ASSUME=1 umi_handshake_checker; arbmask is anyconst; arbmode is free.
 * Both constraints are load-bearing. Without the checkers an input may
 * drop VALID mid-stall while stalled_input still names it, and the
 * output fires a beat no input accepted -- conservation broken by an
 * illegal transmitter, not by the mux. Without a stable mask, an input
 * masked after its grant was captured breaks the mask law on a
 * reconfiguration rather than on anything the block did. The `cover`
 * task reaches every witness here AND all four vacuity covers inside
 * both checker instances, so neither constraint is silently starving the
 * proof.
 *
 * SCOPE -- two properties deliberately NOT asserted, both of which
 * fv_umi_demux does assert for its block. Silence would read as a claim
 * that they hold.
 *
 * 1. Output stability across a stall. The arbiter re-evaluates every
 *    cycle from the live umi_in_valid, and sel_oh falls back on the
 *    captured stalled_input only once `stalled` is set (umi_mux.v:83-91).
 *    No ASSUME=0 checker is bound to the output channel. Consumers must
 *    sample on accept, not on offer.
 *
 * 2. README 4.2 rule 6 (README.md:463), input-facing. Rule 6 allows
 *    READY to depend on VALID but not combinationally, and umi_in_ready
 *    is combinational in umi_in_valid through the arbiter (umi_mux.v:63
 *    -> :91 -> :98), so the argument fv_umi_buffer and fv_umi_demux make
 *    does not transfer here. Rule 5 is the opposite direction -- VALID
 *    on READY -- and is not claimed either way. The dependency is read
 *    off the source above; c_mux_r5_path only shows the cycle is
 *    reachable. No miter is built here to prove it.
 *
 * Fault tasks corrupt only OBSERVED signals, never the DUT, and each is
 * constrained so exactly one law can break:
 *
 *   FV_FAULT_DUP        a second input reads as accepted   -> a_mux_acc_onehot0
 *   FV_FAULT_TELEPORT   an output accept with no input     -> a_mux_cnt_eq
 *   FV_FAULT_BLEND      the output carries a foreign cmd   -> a_mux_route_cmd
 *
 * a_mux_nomask has no fault task here on purpose: the mask law is the
 * arbiter's, and its teeth are fv_umi_arbiter's `fault_mask`. At this
 * level it is a composition check -- that umi_mux does not leak a grant
 * the arbiter refused.
 ******************************************************************************/

`default_nettype none

module fv_umi_mux #(
    parameter N  = 2,               // number of inputs
    parameter CW = 32,              // command width
    parameter AW = 16,              // address width
    parameter DW = 32               // data width (the laws are DW-agnostic)
) (
    input wire clk
);

    // ----------------------------------------------------------------
    // reset: free, but asserted at time zero, so the arbiter thermometer
    // and stalled_input start from their reset values
    // ----------------------------------------------------------------
    (* anyseq *) wire nreset;
    reg f_past_exists = 1'b0;
    always @(posedge clk)
        f_past_exists <= 1'b1;
    always @(*)
        if (!f_past_exists)
            assume (!nreset);

    // ----------------------------------------------------------------
    // free stimulus -- the merge contract holds for any traffic and any
    // arbiter configuration
    // ----------------------------------------------------------------
    // arbmode is free per cycle: the merge laws hold for every
    // arbitration policy. arbmask is CONFIGURATION -- see the note on
    // the mask law below for why it is held constant.
    (* anyseq   *) wire [1:0]   arbmode;
    (* anyconst *) wire [N-1:0] arbmask;
    (* anyseq *) wire [N-1:0]   umi_in_valid;
    (* anyseq *) wire [N*CW-1:0] umi_in_cmd;
    (* anyseq *) wire [N*AW-1:0] umi_in_dstaddr;
    (* anyseq *) wire [N*AW-1:0] umi_in_srcaddr;
    (* anyseq *) wire [N*DW-1:0] umi_in_data;
    (* anyseq *) wire            umi_out_ready;

    wire [N-1:0]    umi_in_ready;
    wire            umi_out_valid;
    wire [CW-1:0]   umi_out_cmd;
    wire [AW-1:0]   umi_out_dstaddr;
    wire [AW-1:0]   umi_out_srcaddr;
    wire [DW-1:0]   umi_out_data;

    // ----------------------------------------------------------------
    // the design under test, exactly as shipped
    // ----------------------------------------------------------------
    umi_mux #(.N(N), .DW(DW), .CW(CW), .AW(AW)) dut (
        .clk            (clk),
        .nreset         (nreset),
        .arbmode        (arbmode),
        .arbmask        (arbmask),
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
    // the audited environment: every input channel is legal SUMI.
    //
    // This is load-bearing, not decoration. umi_mux latches the winning
    // grant into stalled_input and keeps selecting it until the output
    // fires (umi_mux.v:83-91). An input that drops VALID mid-stall --
    // a README 4.2 rule 2 violation -- leaves sel_oh pointing at a
    // channel that is no longer offering, and the output then fires a
    // beat no input accepted. That is a counterexample to conservation
    // produced by an illegal transmitter, not by the mux.
    // ----------------------------------------------------------------
    genvar gi;
    generate
        for (gi = 0; gi < N; gi = gi + 1) begin : g_env_in
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

    // ----------------------------------------------------------------
    // fault injection (formal known-answer tests -- see the SC lane)
    // ----------------------------------------------------------------
`ifdef FV_FAULT_DUP
    // A SECOND input reads as accepted alongside a real accept. The
    // extra bit is unmasked, so a_mux_nomask still holds; the output
    // accept is unchanged, so a_mux_cnt_eq still holds; and the route
    // guard goes vacuous under a multi-hot in_acc. Only one-hotness
    // can break.
    (* anyseq *) wire [N-1:0] fdup;
    wire [N-1:0] extra = fdup & umi_in_valid & ~umi_in_ready & ~arbmask;
    always @(*) begin
        assume ($onehot(extra));
        assume (|(umi_in_valid & umi_in_ready));
    end
    wire [N-1:0] obs_in_ready  = umi_in_ready | extra;
    wire         obs_out_valid = umi_out_valid;
    wire [CW-1:0] obs_out_cmd  = umi_out_cmd;

`elsif FV_FAULT_TELEPORT
    // An output accept in a cycle with no input accept. in_ready is
    // untouched, so one-hotness, the mask law and the route laws are
    // all unaffected. Only conservation can break.
    (* anyseq *) wire ftel;
    always @(*)
        assume (!ftel || (!umi_out_valid && umi_out_ready));
    wire [N-1:0] obs_in_ready  = umi_in_ready;
    wire         obs_out_valid = umi_out_valid | ftel;
    wire [CW-1:0] obs_out_cmd  = umi_out_cmd;

`elsif FV_FAULT_BLEND
    // The observed output command differs from the accepting input's.
    // Nothing else is disturbed, so only the cmd route law can break.
    (* anyseq *) wire [CW-1:0] fcmd;
    always @(*)
        assume (fcmd != umi_out_cmd);
    wire [N-1:0] obs_in_ready  = umi_in_ready;
    wire         obs_out_valid = umi_out_valid;
    wire [CW-1:0] obs_out_cmd  = fcmd;

`else
    wire [N-1:0] obs_in_ready  = umi_in_ready;
    wire         obs_out_valid = umi_out_valid;
    wire [CW-1:0] obs_out_cmd  = umi_out_cmd;
`endif

    // ----------------------------------------------------------------
    // accept-time observables
    // ----------------------------------------------------------------
    wire [N-1:0] in_acc  = umi_in_valid & obs_in_ready;
    wire         out_acc = obs_out_valid & umi_out_ready;
    // guard for the route laws -- see the note on $onehot vs |in_acc above
    wire         one_acc = $onehot(in_acc);

    // the accepting input's beat, selected by the port-observable
    // accept vector -- a plain loop, so it holds for any N and emits no
    // per-index assertion labels
    integer i;
    reg [CW-1:0] exp_cmd;
    reg [AW-1:0] exp_dstaddr;
    reg [AW-1:0] exp_srcaddr;
    reg [DW-1:0] exp_data;

    always @(*) begin
        exp_cmd     = {CW{1'b0}};
        exp_dstaddr = {AW{1'b0}};
        exp_srcaddr = {AW{1'b0}};
        exp_data    = {DW{1'b0}};
        for (i = 0; i < N; i = i + 1)
            if (in_acc[i]) begin
                exp_cmd     = umi_in_cmd    [i*CW +: CW];
                exp_dstaddr = umi_in_dstaddr[i*AW +: AW];
                exp_srcaddr = umi_in_srcaddr[i*AW +: AW];
                exp_data    = umi_in_data   [i*DW +: DW];
            end
    end

    // ----------------------------------------------------------------
    // the merge contract
    // ----------------------------------------------------------------
    always @(posedge clk) begin

        a_mux_acc_onehot0 : assert ($onehot0(in_acc));

        a_mux_cnt_eq : assert ((|in_acc) == out_acc);

        a_mux_nomask : assert ((in_acc & arbmask) == {N{1'b0}});

        a_mux_route_cmd : assert (!one_acc || obs_out_cmd == exp_cmd);

        a_mux_route_dstaddr : assert (!one_acc || umi_out_dstaddr == exp_dstaddr);

        a_mux_route_srcaddr : assert (!one_acc || umi_out_srcaddr == exp_srcaddr);

        a_mux_route_data : assert (!one_acc || umi_out_data == exp_data);
    end

    // ----------------------------------------------------------------
    // witnesses (formal-only)
    // ----------------------------------------------------------------
`ifdef FORMAL
    always @(posedge clk)
        if (f_past_exists & nreset) begin
            // an ordinary merged transfer
            c_mux_xfer     : cover (|in_acc);
            // two inputs offer at once and exactly one is accepted
            c_mux_contend  : cover ((umi_in_valid & ~arbmask) != {N{1'b0}}
                                    && !$onehot(umi_in_valid & ~arbmask)
                                    && |in_acc);
            // the output is offering a beat the sink is not taking
            c_mux_stall    : cover (umi_out_valid && !umi_out_ready
                                    && !$onehot0(umi_in_valid));
            // an input asks while masked and is held off
            c_mux_mask     : cover (|(umi_in_valid & arbmask)
                                    && (in_acc & arbmask) == {N{1'b0}});
            // reachability only: a cycle in which the output is ready
            // and some input is both offering and ready. It does NOT
            // demonstrate the dependency -- a cover cannot. Proving
            // in_ready independent of in_valid needs a self-composition
            // miter, as fv_umi_demux (a_dx_r5_indep) and fv_umi_mux2
            // (a_mux2_r6_nocross) do; neither is built for umi_mux.
            c_mux_r5_path  : cover (umi_out_ready && |umi_in_valid
                                    && (umi_in_ready != {N{1'b0}}));
        end
`endif

endmodule

`default_nettype wire
