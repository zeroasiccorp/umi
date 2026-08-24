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
 * - Proves the single-cycle register stage umi_pipeline keeps the SUMI
 *   handshake (README.md section 4.2 rules 2 and 3) and delivers every
 *   beat it accepts -- once, in order, unchanged.
 *
 * READY IS EXTERNAL. umi_pipeline has no umi_in_ready port: the block
 * header states the ready must be broadcast externally. This harness
 * ties the upstream ready to umi_out_ready, and every law below is a
 * law of that usage. A fabric that broadcasts something else is
 * outside this proof.
 *
 * HANDSHAKE. umi_handshake_checker twice: ASSUME=1 upstream so the
 * driver is legal, ASSUME=0 downstream so the stage is judged. Both
 * output laws close unbounded. umi_out_valid changes only on a cycle
 * where umi_out_ready is high (umi_pipeline.v:53) and the payload
 * registers take the same enable (umi_pipeline.v:58), so an offer that
 * is not being accepted can neither withdraw nor move.
 *
 * PAYLOAD IDENTITY. The handshake rules say WHEN a beat moves, never
 * WHICH beat: a stage that swapped DSTADDR and SRCADDR obeys every one
 * of them. Two laws close that, both read off the ports:
 *
 *   a_pipe_occupancy  the beats accepted and not yet delivered are
 *                     exactly what the stage advertises -- one while
 *                     umi_out_valid is high, none while it is low.
 *                     Nothing dropped, duplicated or invented.
 *   a_pipe_beat       the beat now offered is the beat that entered
 *                     carrying that beat number, whole: CMD, DSTADDR,
 *                     SRCADDR and DATA compared as one vector. Order
 *                     rides along, because the number IS the accept
 *                     order -- a swapped pair delivers the wrong
 *                     payload against it.
 *
 * The tracked beat number is (* anyconst *), held for the whole trace:
 * the solver picks which beat is checked, so proving the tracked one
 * proves every one, and no shadow queue is needed. Numbers are three
 * bits and wrap, which is sound because the stage holds at most one
 * beat -- a_pipe_occupancy is that bound -- and so retires a number
 * long before it comes round again.
 *
 * ENGINE. Every register this stage owns is a port (umi_pipeline.v:41-45
 * are output reg), so k-induction closes both laws from the ports alone.
 * umi_buffer needs abc pdr for the same claim only because its skid
 * register is not observable; there is no hidden state here.
 *
 * The packet registers are deliberately unreset (block header), and
 * formal starts them free. umi_out_valid is reset low and every law
 * above is conditioned on it, so the stale payload is never offered.
 *
 * Outside these laws: progress (nothing here says an accepted beat is
 * ever delivered -- this file asserts no liveness property), and any
 * fabric that broadcasts a different upstream ready.
 *
 * ROWS (tests/sumi/test_formal_sc.py):
 *   pipeline:prove         the handshake at both faces, unbounded
 *   pipeline:cover         handshake witnesses: expect all reached
 *   pipeline:identity      a_pipe_occupancy + a_pipe_beat, unbounded
 *   pipeline:identity_cover  the tracked beat is really delivered and
 *                          an offer really stands unaccepted, so
 *                          neither law passes vacuously
 *   pipeline:prove_mask_off  RULE_EN=0 over a free output channel: with
 *                          the mask cleared no rule is reported. The
 *                          fault_mask_* rows are the other half
 *   pipeline:fault_valid   must FAIL, chk_out.RULE2_valid_hold
 *   pipeline:fault_data    must FAIL, chk_out.RULE3_data_stable
 *   pipeline:fault_swap    must FAIL, a_pipe_beat
 *   pipeline:fault_ghost   must FAIL, a_pipe_occupancy
 *   pipeline:fault_mask_r2 must FAIL, RULE2_valid_hold (mask bit 0 only)
 *   pipeline:fault_mask_r3data  must FAIL, RULE3_data_stable (bit 4)
 *
 ******************************************************************************/

`default_nettype none

module fv_umi_pipeline #(
    parameter CW = 32,
    parameter AW = 64,
    parameter DW = 64,
    parameter [5:0] RULE_EN = 6'h3F
) (
    input wire clk
);

    localparam PW = CW + AW + AW + DW;   // packed SUMI packet

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
    // free stimulus (constrained only by the rules, via env_in below)
    // ----------------------------------------------------------------
    (* anyseq *) wire          in_valid;
    (* anyseq *) wire [CW-1:0] in_cmd;
    (* anyseq *) wire [AW-1:0] in_dstaddr;
    (* anyseq *) wire [AW-1:0] in_srcaddr;
    (* anyseq *) wire [DW-1:0] in_data;
    (* anyseq *) wire          out_ready;

    wire            out_valid;
    wire [CW-1:0]   out_cmd;
    wire [AW-1:0]   out_dstaddr;
    wire [AW-1:0]   out_srcaddr;
    wire [DW-1:0]   out_data;

    // the block broadcasts one ready: see READY IS EXTERNAL above
    wire in_ready = out_ready;

    wire [PW-1:0] in_packet  = {in_cmd, in_dstaddr, in_srcaddr, in_data};

    umi_pipeline #(
        .CW (CW), .AW (AW), .DW (DW)
    ) dut (
        .clk             (clk),
        .nreset          (nreset),
        .umi_in_valid    (in_valid),
        .umi_in_cmd      (in_cmd),
        .umi_in_dstaddr  (in_dstaddr),
        .umi_in_srcaddr  (in_srcaddr),
        .umi_in_data     (in_data),
        .umi_out_valid   (out_valid),
        .umi_out_cmd     (out_cmd),
        .umi_out_dstaddr (out_dstaddr),
        .umi_out_srcaddr (out_srcaddr),
        .umi_out_data    (out_data),
        .umi_out_ready   (out_ready)
    );

    // ----------------------------------------------------------------
    // observed output channel: the faults corrupt what the checker and
    // the identity laws see, never the DUT. No RTL is copied or edited.
    // ----------------------------------------------------------------
    (* anyseq *) wire            f_glitch;
    (* anyseq *) wire            f_ghost;

`ifdef FV_FAULT_FREEOUT
    // the observed channel is entirely free: with the mask open every
    // handshake rule is breakable, so a single enabled bit names the
    // rule that gets reported
    (* anyseq *) wire            obs_valid;
    (* anyseq *) wire [CW-1:0]   obs_cmd;
    (* anyseq *) wire [AW-1:0]   obs_dstaddr;
    (* anyseq *) wire [AW-1:0]   obs_srcaddr;
    (* anyseq *) wire [DW-1:0]   obs_data;
`else
 `ifdef FV_FAULT_VALID
    // an offer withdrawn without being accepted: rule 2
    wire obs_valid = out_valid & ~f_glitch;
 `elsif FV_FAULT_GHOST
    // a beat the stage never accepted, offered anyway. The offer is
    // made a LEGAL one -- it rises out of reset and then changes only
    // on a cycle the receiver accepts, exactly as umi_pipeline drives
    // its own valid -- so every handshake rule still holds and the
    // accounting law is the only thing that can report it.
    reg ghost_q;
    always @(posedge clk or negedge nreset)
        if (!nreset)
            ghost_q <= 1'b0;
        else if (out_ready)
            ghost_q <= f_ghost;
    wire obs_valid = out_valid | ghost_q;
 `else
    wire obs_valid = out_valid;
 `endif

 `ifdef FV_FAULT_DATA
    // payload moving underneath a standing offer: rule 3
    wire [DW-1:0] obs_data = out_data ^ {DW{f_glitch}};
 `else
    wire [DW-1:0] obs_data = out_data;
 `endif

 `ifdef FV_FAULT_SWAP
    // the two addresses exchanged: every handshake rule still holds --
    // the swap is stable and the timing is untouched -- and only the
    // identity law can see it
    wire [AW-1:0] obs_dstaddr = out_srcaddr;
    wire [AW-1:0] obs_srcaddr = out_dstaddr;
 `else
    wire [AW-1:0] obs_dstaddr = out_dstaddr;
    wire [AW-1:0] obs_srcaddr = out_srcaddr;
 `endif

    wire [CW-1:0] obs_cmd = out_cmd;
`endif

    wire [PW-1:0] obs_packet = {obs_cmd, obs_dstaddr, obs_srcaddr, obs_data};

    // ----------------------------------------------------------------
    // the handshake, both faces of one rule list
    // ----------------------------------------------------------------
    umi_handshake_checker #(
        .CW (CW), .AW (AW), .DW (DW),
        .ASSUME (1),                      // environment: assume legal input
        .RULE_EN (RULE_EN)
    ) env_in (
        .clk     (clk),
        .nreset  (nreset),
        .valid   (in_valid),
        .ready   (in_ready),
        .cmd     (in_cmd),
        .dstaddr (in_dstaddr),
        .srcaddr (in_srcaddr),
        .data    (in_data)
    );

    umi_handshake_checker #(
        .CW (CW), .AW (AW), .DW (DW),
        .ASSUME (0),                      // requirement: assert legal output
        .RULE_EN (RULE_EN)
    ) chk_out (
        .clk     (clk),
        .nreset  (nreset),
        .valid   (obs_valid),
        .ready   (out_ready),
        .cmd     (obs_cmd),
        .dstaddr (obs_dstaddr),
        .srcaddr (obs_srcaddr),
        .data    (obs_data)
    );

    // ----------------------------------------------------------------
    // payload identity (FV_IDENTITY rows only)
    //
    // Kept off the handshake rows on purpose: the accounting law reads
    // the same obs_valid the handshake faults corrupt, and it breaks a
    // cycle earlier than the rule those rows are aimed at, so leaving
    // it live would let fault_valid convict a_pipe_occupancy and never
    // exercise rule 2 at all.
    // ----------------------------------------------------------------
`ifdef FV_IDENTITY
    wire insert = in_valid  & in_ready;    // accepted at the input
    wire remove = obs_valid & out_ready;   // delivered at the output

    localparam IW = 3;                     // beat numbers, modulo 8

    reg [IW-1:0] in_cnt;
    reg [IW-1:0] out_cnt;
    always @(posedge clk or negedge nreset)
        if (!nreset) begin
            in_cnt  <= {IW{1'b0}};
            out_cnt <= {IW{1'b0}};
        end else begin
            if (insert)
                in_cnt  <= in_cnt  + {{(IW-1){1'b0}}, 1'b1};
            if (remove)
                out_cnt <= out_cnt + {{(IW-1){1'b0}}, 1'b1};
        end

    // ONE arbitrary beat number, constant for the whole trace. The
    // solver picks it, so proving the tracked beat proves every beat.
    (* anyconst *) wire [IW-1:0] fv_beat;
    reg [PW-1:0] tracked;
    always @(posedge clk)
        if (insert && (in_cnt == fv_beat))
            tracked <= in_packet;

    // what the stage advertises it is holding: one beat while VALID is
    // high, none while it is low
    wire [IW-1:0] port_occ = {{(IW-1){1'b0}}, obs_valid};

    always @(posedge clk)
        if (f_past_exists & nreset & past_nreset) begin
            a_pipe_occupancy : assert ((in_cnt - out_cnt) == port_occ);
            if (obs_valid && (out_cnt == fv_beat))
                a_pipe_beat : assert (obs_packet == tracked);
        end

    // witnesses: neither identity law is passing on an idle link
    always @(posedge clk)
        if (f_past_exists & nreset & past_nreset) begin
            // the tracked beat really is delivered
            c_pipe_deliver : cover (remove && (out_cnt == fv_beat));
            // an offer really does stand unaccepted -- the case
            // a_pipe_beat covers that a delivery alone would not reach
            c_pipe_stall   : cover (obs_valid && !out_ready);
            // and the stage really does run full rate, accepting and
            // delivering on the same cycle
            c_pipe_fullrate : cover (insert && remove);
        end
`endif

    // ----------------------------------------------------------------
    // handshake witnesses: live on every row, so no handshake proof
    // passes over a link that never moves a beat or never stalls
    // ----------------------------------------------------------------
`ifdef FORMAL
    always @(posedge clk)
        if (f_past_exists & nreset & past_nreset) begin
            c_pipe_xfer  : cover (obs_valid & out_ready);
            c_pipe_wait  : cover (obs_valid & ~out_ready);
            c_pipe_empty : cover (~obs_valid);
        end
`endif

endmodule

`default_nettype wire
