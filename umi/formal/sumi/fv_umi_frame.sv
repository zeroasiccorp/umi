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
 * - Qualifies umi_frame_checker the way fv_umi_cmd qualifies
 *   umi_cmd_checker: one face of the checker against the other. A free
 *   channel is driven through an ASSUME instance, so every beat that
 *   reaches the ASSERT instance is framed the way the rule list says a
 *   message is framed. If the two faces agree, prove closes; if a rule
 *   were written differently on one side, this harness reports it.
 *
 * WHY THIS MATTERS FOR A CHECKER RATHER THAN A BLOCK. There is no
 * design RTL under test here. What is under test is the module a
 * fabric would bind to its REQUEST ports -- the half umi_txn_checker's
 * header records as missing, since it asserts framing on responses only
 * and a host emitting broken multi-beat requests passes everything.
 * A checker nobody has qualified is not evidence, so it gets the same
 * treatment as the other two.
 *
 * THE FAULT ROWS ARE THE POINT. Six rules, and one row per rule that
 * breaks exactly that rule on the observed channel while the driving
 * channel stays legal. Each must FAIL on its own label, so no rule can
 * be quietly vacuous:
 *
 *   frame:fault_size    SIZE changed mid-message      FRAME_size_stable
 *   frame:fault_opcode  opcode changed mid-message    FRAME_opcode_stable
 *   frame:fault_fields  QOS moved mid-message         FRAME_fields_stable
 *   frame:fault_da      DA off the running address    FRAME_da_cont
 *   frame:fault_sa      SA off the running address    FRAME_sa_cont
 *   frame:fault_bytes   message over the ceiling      FRAME_msgbytes
 *
 * The corruptions are applied to the command and address words the
 * asserting instance sees, never to the assuming one, so the two faces
 * genuinely disagree rather than both being bent the same way.
 *
 * BOUNDED. FRAME_msgbytes accumulates bytes across a message, and a free
 * accumulator in the step case can start above the ceiling, so that one
 * rule does not close by induction. The other five are cycle-local
 * comparisons and would; the row is bounded because the weakest rule on
 * it is, and that is stated rather than split into two rows for a
 * better-looking label.
 *
 * ROWS (tests/sumi/test_formal_sc.py):
 *   frame:bmc            the two faces agree, bounded
 *   frame:cover          witnesses: expect all reached, including a
 *                        multi-beat message opening, continuing and
 *                        closing on both faces
 *   frame:bmc_mask_off   RULE_EN=0 over a fully free observed channel:
 *                        with the mask cleared nothing is reported. The
 *                        fault_mask_da row is the other half
 *   frame:fault_*        six rows, one per rule, listed above
 *   frame:fault_mask_da  RULE_EN with only bit 3 set, so FRAME_da_cont alone can
 *                        report -- the mask is falsifiable, not
 *                        decorative
 *
 ******************************************************************************/

`default_nettype none

module fv_umi_frame #(
    parameter CW = 32,
    parameter AW = 64,
    parameter DW = 64,
    parameter [31:0] MAX_MSG_BYTES = 32768,
    parameter [5:0] RULE_EN = 6'h3F
) (
    input wire clk
);

`include "umi_messages.vh"

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

    // ----------------------------------------------------------------
    // one free channel
    // ----------------------------------------------------------------
    (* anyseq *) wire          valid;
    (* anyseq *) wire          ready;
    (* anyseq *) wire [CW-1:0] cmd;
    (* anyseq *) wire [AW-1:0] dstaddr;
    (* anyseq *) wire [AW-1:0] srcaddr;
    (* anyseq *) wire [DW-1:0] data;

    // keep the beats inside a sane envelope: SIZE within the data word
    // and a byte count that fits, so the arithmetic under test is the
    // framing and not an out-of-range transfer
    wire [2:0] size = cmd[UMI_SIZE_MSB:UMI_SIZE_LSB];
    always @(*) begin
        m_frame_size : assume (size <= 3'd3);
        m_frame_len  : assume (cmd[UMI_LEN_MSB:UMI_LEN_LSB] <= 8'd3);
    end

    // ----------------------------------------------------------------
    // the driving face: every beat that gets past here is legally framed
    // ----------------------------------------------------------------
    umi_frame_checker #(
        .CW (CW), .AW (AW), .DW (DW),
        .MAX_MSG_BYTES (MAX_MSG_BYTES),
        .ASSUME (1),
        .RULE_EN (6'h3F)
    ) env_frm (
        .clk     (clk),
        .nreset  (nreset),
        .valid   (valid),
        .ready   (ready),
        .cmd     (cmd),
        .dstaddr (dstaddr),
        .srcaddr (srcaddr),
        .data    (data)
    );

    // ----------------------------------------------------------------
    // the observed channel: each fault bends exactly one rule, and only
    // on this side, so the two faces genuinely disagree
    // ----------------------------------------------------------------
    // A stability rule compares a continuation beat against the FIRST
    // beat of its message. Corrupting every beat the same way leaves
    // them agreeing -- the first beat carries the corruption into
    // first_cmd -- and the rule holds. That is how the first version of
    // these rows passed while proving nothing. The corruption is gated
    // on a continuation beat instead, tracked here from the port
    // signals rather than reached for inside the checker.
    reg h_open;
    always @(posedge clk or negedge nreset)
        if (!nreset)
            h_open <= 1'b0;
        else if (valid & ready)
            h_open <= ~cmd[UMI_EOM_BIT];

    wire bend = h_open;          // this beat continues an open message

`ifdef FV_FAULT_SIZE
    wire [CW-1:0] obs_cmd = cmd ^ (bend ? (32'd1 << UMI_SIZE_LSB) : 32'd0);
`elsif FV_FAULT_OPCODE
    wire [CW-1:0] obs_cmd = cmd ^ (bend ? (32'd1 << UMI_OPCODE_LSB) : 32'd0);
`elsif FV_FAULT_FIELDS
    wire [CW-1:0] obs_cmd = cmd ^ (bend ? (32'd1 << UMI_QOS_LSB) : 32'd0);
`else
    wire [CW-1:0] obs_cmd = cmd;
`endif

`ifdef FV_FAULT_DA
    wire [AW-1:0] obs_dstaddr = dstaddr ^ {{(AW-1){1'b0}}, 1'b1};
`else
    wire [AW-1:0] obs_dstaddr = dstaddr;
`endif

`ifdef FV_FAULT_SA
    wire [AW-1:0] obs_srcaddr = srcaddr ^ {{(AW-1){1'b0}}, 1'b1};
`else
    wire [AW-1:0] obs_srcaddr = srcaddr;
`endif

`ifdef FV_FAULT_FREEOUT
    // the observed channel entirely free: with the mask open every rule
    // is breakable, so a single enabled bit names the rule reported
    (* anyseq *) wire [CW-1:0] free_cmd;
    (* anyseq *) wire [AW-1:0] free_dstaddr;
    (* anyseq *) wire [AW-1:0] free_srcaddr;
    umi_frame_checker #(
        .CW (CW), .AW (AW), .DW (DW),
        .MAX_MSG_BYTES (MAX_MSG_BYTES),
        .ASSUME (0),
        .RULE_EN (RULE_EN)
    ) chk_frm (
        .clk     (clk),
        .nreset  (nreset),
        .valid   (valid),
        .ready   (ready),
        .cmd     (free_cmd),
        .dstaddr (free_dstaddr),
        .srcaddr (free_srcaddr),
        .data    (data)
    );
`else
    // The byte-ceiling row is a PARAMETER mismatch, not a corrupted
    // signal: the asserting face is given a lower ceiling than the
    // driving face, so a perfectly legal long message crosses it and
    // FRAME_msgbytes is the only rule that can report. Bending a signal to reach
    // the ceiling breaks the address laws a cycle sooner.
`ifdef FV_FAULT_BYTES
    localparam [31:0] CHK_MAX = 32'd64;
`else
    localparam [31:0] CHK_MAX = MAX_MSG_BYTES;
`endif

    umi_frame_checker #(
        .CW (CW), .AW (AW), .DW (DW),
        .MAX_MSG_BYTES (CHK_MAX),
        .ASSUME (0),
        .RULE_EN (RULE_EN)
    ) chk_frm (
        .clk     (clk),
        .nreset  (nreset),
        .valid   (valid),
        .ready   (ready),
        .cmd     (obs_cmd),
        .dstaddr (obs_dstaddr),
        .srcaddr (obs_srcaddr),
        .data    (data)
    );
`endif

    // ----------------------------------------------------------------
    // witnesses: a multi-beat message really is exercised, so the rules
    // are not passing on single-beat traffic that never opens a message
    // ----------------------------------------------------------------
`ifdef FORMAL
    wire beat = valid & ready;
    always @(posedge clk)
        if (f_past_exists & nreset) begin
            c_frame_single : cover (beat & cmd[UMI_EOM_BIT]);
            c_frame_open   : cover (beat & ~cmd[UMI_EOM_BIT]);
            c_frame_stall  : cover (valid & ~ready);
        end
`endif

endmodule

`default_nettype wire
