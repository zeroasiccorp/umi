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
 * Fault tasks (see fv_umi_cmd.sby): each FV_FAULT_* define replaces
 * the beat chk_beat observes with a known-answer illegal beat while
 * env_legal still sees the clean channel. Every fault task must FAIL
 * with the intended assertion label -- the checker's own regression.
 * The known answers are constants (not free corruptions) so each one
 * trips exactly the rule under test; the two full-byte faults
 * necessarily also trip CMD1_opcode_legal, because any full-byte
 * aliasing error is also outside the legal opcode set (CMD-1 implies
 * CMD-10/CMD-12 over the whole language -- see the checker header).
 ******************************************************************************/

`default_nettype none

module fv_umi_cmd #(
    parameter CW = 32,
    parameter AW = 64,
    parameter DW = 256,
    parameter CHECK_SA_RESERVED = 0
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
    // .sby fault task; every constant is analyzed in the task table
    // of fv_umi_cmd.sby so it trips exactly the intended rule)
    // ----------------------------------------------------------------
`ifdef FV_FAULT_OPCODE
    // reserved opcode hole 0x19; SIZE=0 keeps every other rule content
    wire [CW-1:0] obs_cmd     = 32'h0000_0019;
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
    // .sby task turns the gate on with chparam CHECK_SA_RESERVED=1)
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
        .CHECK_SA_RESERVED (CHECK_SA_RESERVED)
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
        .CHECK_SA_RESERVED (CHECK_SA_RESERVED)
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
