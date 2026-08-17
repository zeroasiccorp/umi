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
 * Formal harness: umi_cmd_checker against itself, both directions.
 *
 *              assumed legal              asserted legal
 *   (free) --[ env_legal ASSUME=1 ]--+--[ chk_beat ASSUME=0 ]--
 *                                    |
 *                        (fault_* only: targeted corruption)
 *
 * One free SUMI channel feeds two instances of the SAME property
 * file: env_legal (ASSUME=1) generates the legal command language,
 * chk_beat (ASSUME=0) checks it. With no fault injected the prove
 * tasks show the assume and assert faces can never drift apart, and
 * the cover tasks show the assumed language is alive: all 13
 * structured opcodes and a full-capacity beat are reachable (a
 * language that can not express them would make every downstream
 * proof vacuous).
 *
 * Fault rows: each FV_FAULT_* define replaces the beat chk_beat
 * observes with a known-answer illegal beat while env_legal still sees
 * the clean channel. Every fault row must FAIL with the intended
 * assertion label -- the checker's own regression. The known answers
 * are constants (not free corruptions) so each one trips exactly the
 * rule under test; the two full-byte faults necessarily also trip
 * CMD1_opcode_legal, because any full-byte aliasing error is also
 * outside the legal opcode set (CMD-1 implies CMD-10/CMD-12 over the
 * whole language -- see the checker header).
 *
 * ROWS (tests/sumi/test_formal_sc.py):
 *   cmd:prove           DW=256, the shipped checker width, unbounded
 *   cmd:prove_dw64      the same proof at DW=64
 *   cmd:cover           witnesses: expect all reached
 *   cmd:cover_sa        CHECK_SA_RESERVED=1
 *   cmd:cover_invalid   ALLOW_INVALID=1
 *   cmd:prove_mask_off  RULE_EN=0, see below
 *   cmd:fault_<rule>    must FAIL, labels below
 *
 * Fault rows and the assertion label each must trip:
 *   fault_opcode       CMD1_opcode_legal      reserved opcode hole 0x19
 *   fault_atype        CMD2_atype_legal       REQ_ATOMIC ATYPE=0x09
 *   fault_align_da     CMD4_da_aligned        REQ_RD SIZE=1, odd DA
 *   fault_align_sa     CMD4_sa_aligned        REQ_RD SIZE=1, odd SA
 *   fault_fullbyte     CMD10_fullbyte_decode  opcode5 0x0E, CMD[7:5]=1
 *   fault_ex           CMD11_ex_zero          REQ_WRPOSTED with EX=1
 *   fault_errsize      CMD12_error_size       opcode5 0x0F, CMD[7:5]=2
 *   fault_cap          CMD15_beat_capacity    REQ_WR SIZE=7 (128B > DW/8)
 *   fault_respdata     CMD16_err_data_zero    NETERR RESP_RD, data lane 0 != 0
 *   fault_sa_reserved  CMD6_sa_reserved       SA[44]=1 (CHECK_SA_RESERVED=1)
 *   fault_invalid      CMD1_opcode_legal      CMD[7:0]=0x00 (ALLOW_INVALID=0)
 * fault_fullbyte and fault_errsize also trip CMD1_opcode_legal (and
 * fault_errsize CMD10): a full-byte aliasing error is by construction
 * outside the CMD-1 legal-opcode set. The intended label must appear
 * in the log's failed-assertion list.
 *
 * cover_invalid runs the ALLOW_INVALID profile: with the profile on, an
 * INVALID beat is part of the assumed language and SAW_invalid must be
 * reachable. fault_invalid is the same beat against the strict default,
 * where CMD1_opcode_legal must reject it -- the profile's two faces.
 *
 * WHAT THE PROVE ROWS DO NOT SHOW. With no fault injected chk_beat sees
 * exactly the channel env_legal constrains, and both instances carry the
 * same parameters, so every `assert (P)` in the asserting face is the
 * `assume (P)` the assuming face has already made about the same signals
 * from the same source line. The rows therefore hold for ANY P: they
 * test the rules' FORM -- that the file cannot say one thing as an
 * assumption and another as an assertion, in either profile or under any
 * RULE_EN -- and not their content. A checker whose rules were all
 * constant 1 would pass them.
 *
 * The content is carried entirely by the fault rows below: each is an
 * illegal beat that one named rule must reject, and a checker with the
 * rules hollowed out fails every one of them. Closing the gap in the
 * prove rows themselves wants a reference predicate written
 * independently of the checker to assert against -- a second
 * implementation of the CMD legality rules, not an added row.
 *
 * prove_mask_off is the soundness check for the per-rule mask itself.
 * RULE_EN=0 reaches BOTH checker instances, so env_legal constrains
 * nothing and the channel is entirely free -- every illegal beat the
 * fault rows above rely on is reachable here. chk_beat must still
 * assert nothing: a rule left outside its RULE_EN guard would be
 * falsified at once. It is the exact complement of the fault rows.
 ******************************************************************************/

`default_nettype none

module fv_umi_cmd #(
    parameter CW = 32,
    parameter AW = 64,
    parameter DW = 256,
    parameter CHECK_SA_RESERVED = 0,
    parameter ALLOW_INVALID = 0,
    parameter [9:0] RULE_EN = 10'h3FF
) (
    input wire clk
);

    // ----------------------------------------------------------------
    // reset: free, but asserted at time zero (grounds the first cycle)
    // ----------------------------------------------------------------
    (* anyseq *) wire nreset;
    reg f_past_exists = 1'b0;
    always @(posedge clk)
        f_past_exists <= 1'b1;
    always @(*)
        if (!f_past_exists)
            assume (!nreset);

    // ----------------------------------------------------------------
    // free stimulus (constrained only by the rules, via env_legal)
    // ----------------------------------------------------------------
    (* anyseq *) wire            valid;
    (* anyseq *) wire            ready;
    (* anyseq *) wire [CW-1:0]   in_cmd;
    (* anyseq *) wire [AW-1:0]   in_dstaddr;
    (* anyseq *) wire [AW-1:0]   in_srcaddr;
    (* anyseq *) wire [DW-1:0]   in_data;

    // ----------------------------------------------------------------
    // fault injection (formal known-answer tests -- one define per
    // fault row; every constant is analyzed in the fault table in
    // this file's header so it trips exactly the intended rule)
    // ----------------------------------------------------------------
`ifdef FV_FAULT_OPCODE
    // reserved opcode hole 0x19; SIZE=0 keeps every other rule content
    wire [CW-1:0] obs_cmd     = 32'h0000_0019;
    wire [AW-1:0] obs_dstaddr = {AW{1'b0}};
    wire [AW-1:0] obs_srcaddr = {AW{1'b0}};
    wire [DW-1:0] obs_data    = in_data;
`elsif FV_FAULT_INVALID
    // the in-band INVALID beat (CMD[7:0]==0x00): legal only under the
    // ALLOW_INVALID profile, and this task runs the strict default
    wire [CW-1:0] obs_cmd     = 32'h0000_0000;
    wire [AW-1:0] obs_dstaddr = {AW{1'b0}};
    wire [AW-1:0] obs_srcaddr = {AW{1'b0}};
    wire [DW-1:0] obs_data    = in_data;
`elsif FV_FAULT_ATYPE
    // REQ_ATOMIC with ATYPE=0x09 (one past ATOMICSWAP), SIZE=0
    wire [CW-1:0] obs_cmd     = 32'h0000_0909;
    wire [AW-1:0] obs_dstaddr = {AW{1'b0}};
    wire [AW-1:0] obs_srcaddr = {AW{1'b0}};
    wire [DW-1:0] obs_data    = in_data;
`elsif FV_FAULT_ALIGN_DA
    // REQ_RD SIZE=1 with an odd DA (SA kept aligned)
    wire [CW-1:0] obs_cmd     = 32'h0000_0021;
    wire [AW-1:0] obs_dstaddr = {{(AW-1){1'b0}}, 1'b1};
    wire [AW-1:0] obs_srcaddr = {AW{1'b0}};
    wire [DW-1:0] obs_data    = in_data;
`elsif FV_FAULT_ALIGN_SA
    // REQ_RD SIZE=1 with an odd SA (DA kept aligned)
    wire [CW-1:0] obs_cmd     = 32'h0000_0021;
    wire [AW-1:0] obs_dstaddr = {AW{1'b0}};
    wire [AW-1:0] obs_srcaddr = {{(AW-1){1'b0}}, 1'b1};
    wire [DW-1:0] obs_data    = in_data;
`elsif FV_FAULT_FULLBYTE
    // 5-bit opcode 0x0E extended with CMD[7:5]=1: not RESP_LINK,
    // not anything -- the 0x0E-family aliasing error
    wire [CW-1:0] obs_cmd     = 32'h0000_002E;
    wire [AW-1:0] obs_dstaddr = {AW{1'b0}};
    wire [AW-1:0] obs_srcaddr = {AW{1'b0}};
    wire [DW-1:0] obs_data    = in_data;
`elsif FV_FAULT_EX
    // REQ_WRPOSTED with EX=1 (bit 24), SIZE=LEN=0
    wire [CW-1:0] obs_cmd     = 32'h0100_0005;
    wire [AW-1:0] obs_dstaddr = {AW{1'b0}};
    wire [AW-1:0] obs_srcaddr = {AW{1'b0}};
    wire [DW-1:0] obs_data    = in_data;
`elsif FV_FAULT_ERRSIZE
    // 5-bit opcode 0x0F extended with CMD[7:5]=2: the REQ_ERROR
    // family carrying SIZE=2 instead of 0
    wire [CW-1:0] obs_cmd     = 32'h0000_004F;
    wire [AW-1:0] obs_dstaddr = {AW{1'b0}};
    wire [AW-1:0] obs_srcaddr = {AW{1'b0}};
    wire [DW-1:0] obs_data    = in_data;
`elsif FV_FAULT_CAP
    // REQ_WR SIZE=7 LEN=0: one beat claims 128 bytes, over any
    // DW <= 512 bus (the task runs the default DW=256 -> 32 bytes)
    wire [CW-1:0] obs_cmd     = 32'h0000_00E3;
    wire [AW-1:0] obs_dstaddr = {AW{1'b0}};
    wire [AW-1:0] obs_srcaddr = {AW{1'b0}};
    wire [DW-1:0] obs_data    = in_data;
`elsif FV_FAULT_RESPDATA
    // RESP_RD with ERR=NETERR (CMD[26:25]=3) and a nonzero byte in
    // the one relevant data lane (SIZE=LEN=0 -> lane 0)
    wire [CW-1:0] obs_cmd     = 32'h0600_0002;
    wire [AW-1:0] obs_dstaddr = {AW{1'b0}};
    wire [AW-1:0] obs_srcaddr = in_srcaddr;
    wire [DW-1:0] obs_data    = {{(DW-1){1'b0}}, 1'b1};
`elsif FV_FAULT_SA_RESERVED
    // REQ_RD with SA bit 44 set: reserved SA[63:40] nonzero (the
    // fault row turns the gate on with CHECK_SA_RESERVED=1)
    wire [CW-1:0] obs_cmd     = 32'h0000_0001;
    wire [AW-1:0] obs_dstaddr = {AW{1'b0}};
    wire [AW-1:0] obs_srcaddr = 64'h0000_1000_0000_0000;
    wire [DW-1:0] obs_data    = in_data;
`else
    wire [CW-1:0] obs_cmd     = in_cmd;
    wire [AW-1:0] obs_dstaddr = in_dstaddr;
    wire [AW-1:0] obs_srcaddr = in_srcaddr;
    wire [DW-1:0] obs_data    = in_data;
`endif

    // ----------------------------------------------------------------
    // the same file, both directions
    // ----------------------------------------------------------------
    umi_cmd_checker #(
        .CW (CW), .AW (AW), .DW (DW),
        .ASSUME (1),                      // environment: assume legal beats
        .CHECK_SA_RESERVED (CHECK_SA_RESERVED),
        .ALLOW_INVALID (ALLOW_INVALID),
        .RULE_EN (RULE_EN)
    ) env_legal (
        .clk     (clk),
        .nreset  (nreset),
        .valid   (valid),
        .ready   (ready),
        .cmd     (in_cmd),
        .dstaddr (in_dstaddr),
        .srcaddr (in_srcaddr),
        .data    (in_data)
    );

    umi_cmd_checker #(
        .CW (CW), .AW (AW), .DW (DW),
        .ASSUME (0),                      // requirement: assert legal beats
        .CHECK_SA_RESERVED (CHECK_SA_RESERVED),
        .ALLOW_INVALID (ALLOW_INVALID),
        .RULE_EN (RULE_EN)
    ) chk_beat (
        .clk     (clk),
        .nreset  (nreset),
        .valid   (valid),
        .ready   (ready),
        .cmd     (obs_cmd),
        .dstaddr (obs_dstaddr),
        .srcaddr (obs_srcaddr),
        .data    (obs_data)
    );

endmodule

`default_nettype wire
