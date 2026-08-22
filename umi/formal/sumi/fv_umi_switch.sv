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
 * - Proves the NxM switch keeps the SUMI handshake on each output, and
 *   pins down what its input-ready merge does once there is more than
 *   one output.
 *
 * THE READY MERGE, AND A CLAIM THE TOOL REFUTED. umi_switch builds one
 * umi_mux per output and ANDs every mux's per-input ready together
 * (umi_switch.v:121-127):
 *
 *     umi_in_ready[n] = 1;
 *     for each output m:  umi_in_ready[n] &= umi_ready[n + N*m];
 *
 * A mux raises ready only for the input it has selected (umi_mux.v:98,
 * umi_in_ready = sel_oh & {N{umi_out_ready}}), so reading the source
 * suggests an input asking for one output can never be accepted once
 * M > 1: some other mux has not selected it and contributes a zero.
 *
 * That is written here because it is wrong, and the harness is what
 * showed it. An assertion saying umi_in_ready stays zero under unicast
 * traffic FAILS in three cycles: a mux that stalled while granting an
 * input holds that selection in stalled_input (umi_mux.v:89-91), so its
 * ready can still be high for an input that is no longer asking it.
 * Acceptance therefore depends on the stalled-grant history of every
 * other output, which is not a property of the traffic at all.
 *
 * No law here claims the merge is right or wrong. What the rows do is
 * pin the handshake on both arms and witness that traffic moves, so a
 * change in that history-dependent behaviour shows up as a diff.
 *
 * WHAT IS PROVEN, both arms:
 *   RULE2_valid_hold / RULE3_*_stable   the handshake on every output
 *                     port, with each input's payload constrained
 *                     legal by the same checker in its ASSUME face
 *
 * BOUNDED. The arbiter thermometer inside each mux and the mux's
 * captured stalled_input are not observable from these ports -- the
 * fence fv_umi_mux already documents -- so induction starts from states
 * no trace reaches. These rows are bmc.
 *
 * Outside these laws: which input wins when several compete, fairness,
 * and progress. MASK is left at its default of zero, so no path is
 * statically disabled.
 *
 * ROWS (tests/sumi/test_formal_sc.py):
 *   switch:bmc            M=1, output handshake, bounded
 *   switch:bmc_m2         M=2, the same handshake with the ready merge
 *                         active across two outputs
 *   switch:cover          witnesses: expect all reached
 *   switch:fault_valid    must FAIL, chk_out.RULE2_valid_hold
 *
 ******************************************************************************/

`default_nettype none

module fv_umi_switch #(
    parameter N  = 2,
    parameter M  = 1,
    parameter CW = 32,
    parameter AW = 64,
    parameter DW = 64,
    parameter [5:0] RULE_EN = 6'h3F
) (
    input wire clk
);

    // ----------------------------------------------------------------
    // reset: free, but asserted at time zero (grounds all history)
    // ----------------------------------------------------------------
    (* anyseq *) wire nreset;
    reg f_past_exists = 1'b0;
    always @(posedge clk)
        f_past_exists <= 1'b1;
    always @(*)
        if (!f_past_exists)
            assume (!nreset);

    reg past_nreset = 1'b0;
    always @(posedge clk)
        past_nreset <= nreset;

    // ----------------------------------------------------------------
    // free stimulus
    // ----------------------------------------------------------------
    (* anyseq *) wire [N*M-1:0] in_valid;
    (* anyseq *) wire [N*CW-1:0] in_cmd;
    (* anyseq *) wire [N*AW-1:0] in_dstaddr;
    (* anyseq *) wire [N*AW-1:0] in_srcaddr;
    (* anyseq *) wire [N*DW-1:0] in_data;
    (* anyseq *) wire [M-1:0]   out_ready;

    wire [N-1:0]    in_ready;
    wire [M-1:0]    out_valid;
    wire [M*CW-1:0] out_cmd;
    wire [M*AW-1:0] out_dstaddr;
    wire [M*AW-1:0] out_srcaddr;
    wire [M*DW-1:0] out_data;

    umi_switch #(
        .N (N), .M (M), .MASK ({(M*N){1'b0}}),
        .DW (DW), .CW (CW), .AW (AW)
    ) dut (
        .clk             (clk),
        .nreset          (nreset),
        .arbmode         (2'b10),        // round robin, per umi_arbiter.v:63
        .arbmask         ({(N*M){1'b0}}),
        .umi_in_valid    (in_valid),
        .umi_in_cmd      (in_cmd),
        .umi_in_dstaddr  (in_dstaddr),
        .umi_in_srcaddr  (in_srcaddr),
        .umi_in_data     (in_data),
        .umi_in_ready    (in_ready),
        .umi_out_valid   (out_valid),
        .umi_out_cmd     (out_cmd),
        .umi_out_dstaddr (out_dstaddr),
        .umi_out_srcaddr (out_srcaddr),
        .umi_out_data    (out_data),
        .umi_out_ready   (out_ready)
    );

    // ----------------------------------------------------------------
    // unicast: each input asks for at most one output, which is how a
    // switch is ordinarily driven
    // ----------------------------------------------------------------
    wire [N-1:0] want;          // input n is asking for something
    wire [N-1:0] multi;         // input n is asking for more than one
    genvar gn, gm;
    generate
        for (gn = 0; gn < N; gn = gn + 1) begin : g_want
            wire [M-1:0] asks;
            for (gm = 0; gm < M; gm = gm + 1) begin : g_asks
                assign asks[gm] = in_valid[gm*N + gn];
            end
            assign want[gn]  = |asks;
            assign multi[gn] = |(asks & (asks - {{(M-1){1'b0}}, 1'b1}));
        end
    endgenerate

    always @(*)
        m_sw_unicast : assume (multi == {N{1'b0}});

    // ----------------------------------------------------------------
    // observed outputs: the fault corrupts what the checker sees, never
    // the DUT. No RTL is copied or edited.
    // ----------------------------------------------------------------
    (* anyseq *) wire f_glitch;

`ifdef FV_FAULT_VALID
    wire [M-1:0] obs_valid = out_valid & ~{M{f_glitch}};
`else
    wire [M-1:0] obs_valid = out_valid;
`endif

    // ----------------------------------------------------------------
    // the handshake on every output, and legality on every input
    // ----------------------------------------------------------------
    generate
        for (gn = 0; gn < N; gn = gn + 1) begin : g_env
            umi_handshake_checker #(
                .CW (CW), .AW (AW), .DW (DW),
                .ASSUME (1),              // environment: legal inputs
                .RULE_EN (RULE_EN)
            ) env_in (
                .clk     (clk),
                .nreset  (nreset),
                .valid   (want[gn]),
                .ready   (in_ready[gn]),
                .cmd     (in_cmd[gn*CW +: CW]),
                .dstaddr (in_dstaddr[gn*AW +: AW]),
                .srcaddr (in_srcaddr[gn*AW +: AW]),
                .data    (in_data[gn*DW +: DW])
            );
        end

        for (gm = 0; gm < M; gm = gm + 1) begin : g_chk
            umi_handshake_checker #(
                .CW (CW), .AW (AW), .DW (DW),
                .ASSUME (0),              // requirement: legal outputs
                .RULE_EN (RULE_EN)
            ) chk_out (
                .clk     (clk),
                .nreset  (nreset),
                .valid   (obs_valid[gm]),
                .ready   (out_ready[gm]),
                .cmd     (out_cmd[gm*CW +: CW]),
                .dstaddr (out_dstaddr[gm*AW +: AW]),
                .srcaddr (out_srcaddr[gm*AW +: AW]),
                .data    (out_data[gm*DW +: DW])
            );
        end
    endgenerate

    // ----------------------------------------------------------------
    // witnesses
    // ----------------------------------------------------------------
`ifdef FORMAL
    always @(posedge clk)
        if (f_past_exists & nreset & past_nreset) begin
            // an input asking with every output ready, and an input
            // actually accepted: together these say the merge does let
            // traffic through, which is what the refuted assertion got
            // wrong
            c_sw_want   : cover (|want & (&out_ready));
            c_sw_outxfer: cover (|(obs_valid & out_ready));
            c_sw_outwait: cover (|(obs_valid & ~out_ready));
            c_sw_accept : cover (|in_ready);
        end
`endif

endmodule

`default_nettype wire
