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
 * Intra-message framing checker for ONE UMI channel.
 *
 * umi_txn_checker judges the framing of RESPONSE messages, and says so
 * in its own header: request beats are observed to populate its
 * outstanding tracker, but their framing is not asserted, so a host
 * emitting broken multi-beat requests is not caught. This module is
 * that missing half. It watches a single channel and holds the beats of
 * one message to README 4.1.1, which makes it usable on a request
 * channel -- the case nothing covered before -- and equally on any
 * other channel whose framing is worth checking.
 *
 * It carries no outstanding tracker and pairs nothing with anything: it
 * is about the beats WITHIN one message, not about requests and
 * responses matching up. That keeps it small enough to bind to every
 * port of a fabric.
 *
 * THE RULES, with their README anchors. All of them are conditioned on
 * a CONTINUATION beat -- one accepted while a message is already open,
 * meaning an earlier beat of it went by with EOM low. A message carried
 * in a single beat has no intra-message framing and nothing here
 * constrains it.
 *
 *   FRAME_size_stable   SIZE is the same on every beat of a message.
 *                      README 4.1.1 rule 2: a split copies the fields.
 *   FRAME_opcode_stable the opcode likewise -- the beats of one message
 *                      are all the same message (README 4.1.1 rule 2).
 *   FRAME_fields_stable QOS, PROT and EOF likewise (README 3.3.4,
 *                      3.3.5, 3.3.7).
 *   FRAME_da_cont       a continuation beat's DA is the running address:
 *                      the previous DA advanced by the bytes the
 *                      previous beat carried. README 4.1.1 rule 4,
 *                      "only the destination address increments".
 *   FRAME_sa_cont       and its SA likewise, README 4.1.1 rule 5 -- the
 *                      rule umi_txn_checker records as
 *                      observed-but-not-asserted.
 *   FRAME_msgbytes      the bytes accumulated over a message never
 *                      exceed MAX_MSG_BYTES (README 2, 32768).
 *
 * Bytes come from the command word the way README 3.3.2 and 3.3.3
 * define them: (LEN+1) << SIZE.
 *
 * ADDRESS ARITHMETIC IS MODULAR. The running address is computed in AW
 * bits and wraps. The specification does not say what a split message
 * does at the top of the address space, so this module follows the
 * arithmetic rather than inventing a rule; a message that wraps is
 * checked against the wrapped address.
 *
 * ASSUME. As in the other checkers here: ASSUME=0 asserts the rules on
 * a channel being judged, ASSUME=1 assumes them on a channel being
 * driven, from one rule list so the two faces cannot drift apart.
 *
 * RULE_EN. One bit per rule, LSB first, so an adopter who reads one
 * rule differently can switch it off without losing the rest:
 *
 *    0  FRAME_size_stable     3  FRAME_da_cont
 *    1  FRAME_opcode_stable   4  FRAME_sa_cont
 *    2  FRAME_fields_stable   5  FRAME_msgbytes
 *
 * Outside this module: whether a message ever ends (no liveness
 * property here), whether the payload is right, and anything that needs
 * a second channel.
 *
 ******************************************************************************/

`default_nettype none

module umi_frame_checker #(
    parameter CW = 32,                       // command width
    parameter AW = 64,                       // address width
    parameter DW = 256,                      // data width
    parameter [31:0] MAX_MSG_BYTES = 32768,  // per-message byte ceiling
    parameter ASSUME = 0,                    // 0: assert the rules, 1: assume
    parameter [5:0] RULE_EN = 6'h3F          // per-rule enables
) (
    input wire          clk,
    input wire          nreset,
    input wire          valid,
    input wire          ready,
    input wire [CW-1:0] cmd,
    input wire [AW-1:0] dstaddr,
    input wire [AW-1:0] srcaddr,
    input wire [DW-1:0] data
);

`include "umi_messages.vh"

    // ----------------------------------------------------------------
    // this beat
    // ----------------------------------------------------------------
    wire        beat = valid & ready;
    wire        eom  = cmd[UMI_EOM_BIT];
    wire [2:0]  size = cmd[UMI_SIZE_MSB:UMI_SIZE_LSB];
    wire [7:0]  len  = cmd[UMI_LEN_MSB:UMI_LEN_LSB];

    // (LEN+1) << SIZE, README 3.3.2 and 3.3.3. Computed twice at two
    // widths on purpose: the byte ceiling is a 32-bit comparison, while
    // the running address must be added at AW, and slicing the 32-bit
    // form down to AW is out of range whenever AW is wider than 32.
    wire [31:0]   bytes    = ({24'd0, len} + 32'd1) << size;
    wire [AW-1:0] bytes_aw = ({{(AW-8){1'b0}}, len}
                              + {{(AW-1){1'b0}}, 1'b1}) << size;

    // ----------------------------------------------------------------
    // the message in progress
    // ----------------------------------------------------------------
    reg          open_msg;     // a message is open: an earlier beat had EOM low
    reg [CW-1:0] first_cmd;    // the fields every later beat must repeat
    reg [AW-1:0] next_da;      // where the next beat must be addressed
    reg [AW-1:0] next_sa;
    reg [31:0]   acc_bytes;    // bytes carried so far, this message

    wire [31:0] tot_bytes = acc_bytes + bytes;

    always @(posedge clk or negedge nreset)
        if (!nreset) begin
            open_msg  <= 1'b0;
            first_cmd <= {CW{1'b0}};
            next_da   <= {AW{1'b0}};
            next_sa   <= {AW{1'b0}};
            acc_bytes <= 32'd0;
        end else if (beat) begin
            open_msg  <= ~eom;
            if (!open_msg)
                first_cmd <= cmd;
            next_da   <= dstaddr + bytes_aw;
            next_sa   <= srcaddr + bytes_aw;
            acc_bytes <= eom ? 32'd0 : tot_bytes;
        end

    // a beat accepted while a message is already open
    wire cont = beat & open_msg;

    // ----------------------------------------------------------------
    // the rules, one list, two faces
    // ----------------------------------------------------------------
    wire fields_ok = (cmd[UMI_QOS_MSB:UMI_QOS_LSB]
                      == first_cmd[UMI_QOS_MSB:UMI_QOS_LSB])
                   & (cmd[UMI_PROT_MSB:UMI_PROT_LSB]
                      == first_cmd[UMI_PROT_MSB:UMI_PROT_LSB])
                   & (cmd[UMI_EOF_BIT] == first_cmd[UMI_EOF_BIT]);
    wire size_ok   = (size == first_cmd[UMI_SIZE_MSB:UMI_SIZE_LSB]);
    wire opcode_ok = (cmd[UMI_OPCODE_MSB:UMI_OPCODE_LSB]
                      == first_cmd[UMI_OPCODE_MSB:UMI_OPCODE_LSB]);
    wire da_ok     = (dstaddr == next_da);
    wire sa_ok     = (srcaddr == next_sa);
    wire bytes_ok  = (tot_bytes <= MAX_MSG_BYTES);

`ifdef FORMAL
    generate
        if (ASSUME == 0) begin : g_assert
            always @(posedge clk)
                if (nreset & cont) begin
                    if (RULE_EN[0])
                        FRAME_size_stable : assert (size_ok);
                    if (RULE_EN[1])
                        FRAME_opcode_stable : assert (opcode_ok);
                    if (RULE_EN[2])
                        FRAME_fields_stable : assert (fields_ok);
                    if (RULE_EN[3])
                        FRAME_da_cont : assert (da_ok);
                    if (RULE_EN[4])
                        FRAME_sa_cont : assert (sa_ok);
                    if (RULE_EN[5])
                        FRAME_msgbytes : assert (bytes_ok);
                end
        end else begin : g_assume
            always @(posedge clk)
                if (nreset & cont) begin
                    if (RULE_EN[0])
                        FRAME_size_stable : assume (size_ok);
                    if (RULE_EN[1])
                        FRAME_opcode_stable : assume (opcode_ok);
                    if (RULE_EN[2])
                        FRAME_fields_stable : assume (fields_ok);
                    if (RULE_EN[3])
                        FRAME_da_cont : assume (da_ok);
                    if (RULE_EN[4])
                        FRAME_sa_cont : assume (sa_ok);
                    if (RULE_EN[5])
                        FRAME_msgbytes : assume (bytes_ok);
                end
        end
    endgenerate

    // anti-vacuity: a multi-beat message really is exercised
    always @(posedge clk)
        if (nreset) begin
            FRAME_open  : cover (beat & ~eom);
            FRAME_cont  : cover (cont);
            FRAME_close : cover (cont & eom);
        end
`else
    // the same rules in a 4-state simulator
    always @(posedge clk)
        if (nreset & cont & (ASSUME == 0)) begin
            if (RULE_EN[0] && (size_ok !== 1'b1))
                $error("UMI-FRAME size %m: SIZE changed inside a message (README 4.1.1)");
            if (RULE_EN[1] && (opcode_ok !== 1'b1))
                $error("UMI-FRAME opcode %m: opcode changed inside a message (README 4.1.1)");
            if (RULE_EN[2] && (fields_ok !== 1'b1))
                $error("UMI-FRAME fields %m: QOS/PROT/EOF changed inside a message (README 4.1.1)");
            if (RULE_EN[3] && (da_ok !== 1'b1))
                $error("UMI-FRAME da %m: DA is not the running address (README 4.1.1 rule 4)");
            if (RULE_EN[4] && (sa_ok !== 1'b1))
                $error("UMI-FRAME sa %m: SA is not the running address (README 4.1.1 rule 5)");
            if (RULE_EN[5] && (bytes_ok !== 1'b1))
                $error("UMI-FRAME msgbytes %m: message exceeds MAX_MSG_BYTES (README 2)");
        end
`endif

    // data is not inspected: framing is a command-word property
    wire _unused_data = |{1'b0, data};

endmodule

`default_nettype wire
